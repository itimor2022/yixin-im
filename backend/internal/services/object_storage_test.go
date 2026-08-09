// 文件用途：验证 object_storage_test.go 对应模块的正常流程、异常处理和回归行为。
// 核心逻辑：覆盖输入校验、状态变化、错误返回、边界条件和并发幸命。

package services

import (
	"bytes"
	"context"
	"encoding/json"
	"io"
	"net/http"
	"net/http/httptest"
	"strconv"
	"strings"
	"testing"
	"time"
	"genericim/internal/config"
)

func TestApplyImmutableObjectCacheHeader(t *testing.T) {
	header := make(http.Header)
	applyImmutableObjectCacheHeader(header)
	if got := header.Get("Cache-Control"); got != immutableObjectCacheControl {

		t.Fatalf("Cache-Control=%q, want %q", got, immutableObjectCacheControl)
	}
}
func TestPublicObjectURLAddsSchemeForHostOnlyBaseURL(t *testing.T) {
	got := PublicObjectURL("cdn.example.com", "uploads/images/a.png", true)
	want := "https://cdn.example.com/uploads/images/a.png"
	if got != want {

		t.Fatalf("PublicObjectURL() = %q, want %q", got, want)
	}
}
func TestObjectKeyFromPublicURLQiniuHostOnlyBaseURL(t *testing.T) {
	var cfg config.StorageConfig
	cfg.Provider = StorageProviderQiniu
	cfg.Qiniu.PublicBaseURL = "cdn.example.com"
	cfg.Qiniu.UseHTTPS = true
	got, ok := ObjectKeyFromPublicURL(cfg, "https://cdn.example.com/uploads/images/a.png?token=1")
	if !ok {

		t.Fatal("expected qiniu public URL to match")
	}
	if got != "uploads/images/a.png" {

		t.Fatalf("object key = %q, want %q", got, "uploads/images/a.png")
	}
}
func TestObjectKeyFromPublicURLAliyunDefaultBucketEndpoint(t *testing.T) {
	var cfg config.StorageConfig
	cfg.Provider = StorageProviderAliyun
	cfg.Aliyun.Endpoint = "oss-cn-hangzhou.aliyuncs.com"
	cfg.Aliyun.Bucket = "bucket-a"
	cfg.Aliyun.UseHTTPS = true
	got, ok := ObjectKeyFromPublicURL(cfg, "https://bucket-a.oss-cn-hangzhou.aliyuncs.com/uploads/images/a.png")
	if !ok {

		t.Fatal("expected aliyun bucket endpoint URL to match")
	}
	if got != "uploads/images/a.png" {

		t.Fatalf("object key = %q, want %q", got, "uploads/images/a.png")
	}
}
func TestS3ConfigAndPublicURLRoundTrip(t *testing.T) {
	var cfg config.StorageConfig
	cfg.Provider = "amazon_s3"
	cfg.S3.Region = "ap-southeast-1"
	cfg.S3.Bucket = "genericim-media-prod"
	cfg.S3.AccessKeyID = "test-access-key"
	cfg.S3.SecretAccessKey = "test-secret-key"
	cfg.S3.PublicBaseURL = "https://media.example.com"
	if got := NormalizeStorageProvider(cfg.Provider); got != StorageProviderS3 {

		t.Fatalf("provider=%q, want s3", got)
	}
	if err := ValidateStorageConfig(cfg); err != nil {

		t.Fatalf("unexpected validation error: %v", err)
	}
	key, ok := ObjectKeyFromPublicURL(cfg, "https://media.example.com/uploads/videos/a.mp4?x=1")
	if !ok || key != "uploads/videos/a.mp4" {

		t.Fatalf("key=%q ok=%v", key, ok)
	}
}
func TestS3ConfigRequiresPublicBaseURL(t *testing.T) {
	var cfg config.StorageConfig
	cfg.Provider = StorageProviderS3
	cfg.S3.Region = "ap-southeast-1"
	cfg.S3.Bucket = "genericim-media-prod"
	if err := ValidateStorageConfig(cfg); err == nil {

		t.Fatal("expected missing public base URL to fail")
	}
}
func TestS3UploadHeadAndDeleteAgainstCompatibleEndpoint(t *testing.T) {
	t.Setenv("AWS_ACCESS_KEY_ID", "test-access-key")
	t.Setenv("AWS_SECRET_ACCESS_KEY", "test-secret-key")
	t.Setenv("AWS_EC2_METADATA_DISABLED", "true")
	var uploaded []byte
	var deleteCalled bool
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {

		if r.URL.Path != "/media-bucket/uploads/images/a.txt" {

			http.Error(w, "unexpected path", http.StatusNotFound)

			return

		}

		switch r.Method {

		case http.MethodPut:

			uploaded, _ = io.ReadAll(r.Body)

			w.WriteHeader(http.StatusOK)

		case http.MethodHead:

			w.Header().Set("Content-Length", strconv.Itoa(len(uploaded)))

			w.WriteHeader(http.StatusOK)

		case http.MethodGet:

			w.Header().Set("Content-Length", strconv.Itoa(len(uploaded)))

			_, _ = w.Write(uploaded)

		case http.MethodDelete:

			deleteCalled = true

			w.WriteHeader(http.StatusNoContent)

		default:

			http.Error(w, "unexpected method", http.StatusMethodNotAllowed)

		}
	}))
	defer server.Close()
	var cfg config.StorageConfig
	cfg.Provider = StorageProviderS3
	cfg.S3.Region = "ap-southeast-1"
	cfg.S3.Bucket = "media-bucket"
	cfg.S3.AccessKeyID = "test-access-key"
	cfg.S3.SecretAccessKey = "test-secret-key"
	cfg.S3.PublicBaseURL = "https://media.example.com"
	cfg.S3.Endpoint = server.URL
	cfg.S3.UsePathStyle = true
	body := []byte("hello s3")
	got, err := UploadObject(context.Background(), cfg, "uploads/images/a.txt", bytes.NewReader(body), int64(len(body)), "text/plain")
	if err != nil {

		t.Fatalf("upload: %v", err)
	}
	if got != "https://media.example.com/uploads/images/a.txt" || !bytes.Equal(uploaded, body) {

		t.Fatalf("unexpected result url=%q body=%q", got, string(uploaded))
	}
	checksum, err := ComputeS3ObjectSHA256(

		context.Background(),

		cfg,

		"uploads/images/a.txt",

		int64(len(body)),
	)
	if err != nil {

		t.Fatalf("checksum: %v", err)
	}
	if checksum != "f2ff189a4ef686231302becc266e6c8d5eee814b868d11631f7660073fc9b613" {

		t.Fatalf("unexpected checksum: %s", checksum)
	}
	if err := DeleteObject(context.Background(), cfg, "uploads/images/a.txt"); err != nil {

		t.Fatalf("delete: %v", err)
	}
	if !deleteCalled {

		t.Fatal("delete endpoint was not called")
	}
}
func TestS3PresignedPutAndPartURLs(t *testing.T) {
	t.Setenv("AWS_ACCESS_KEY_ID", "test-access-key")
	t.Setenv("AWS_SECRET_ACCESS_KEY", "test-secret-key")
	t.Setenv("AWS_EC2_METADATA_DISABLED", "true")
	var cfg config.StorageConfig
	cfg.Provider = StorageProviderS3
	cfg.S3.Region = "ap-southeast-1"
	cfg.S3.Bucket = "media-bucket"
	cfg.S3.AccessKeyID = "test-access-key"
	cfg.S3.SecretAccessKey = "test-secret-key"
	cfg.S3.PublicBaseURL = "https://media.example.com"
	cfg.S3.Endpoint = "https://s3.example.com"
	cfg.S3.UsePathStyle = true
	put, err := PresignS3PutObject(

		context.Background(),

		cfg,

		"uploads/videos/a.mp4",

		123,

		"video/mp4",

		strings.Repeat("01", 32),

		time.Minute,
	)
	if err != nil {

		t.Fatalf("presign put: %v", err)
	}
	if !strings.Contains(put.URL, "X-Amz-Signature=") ||

		put.Headers["Content-Type"] != "video/mp4" {

		t.Fatalf("unexpected presigned PUT: %#v", put)
	}
	if !strings.Contains(put.URL, "X-Amz-Checksum-Sha256=") {

		t.Fatalf("checksum was not signed into the presigned URL: %s", put.URL)
	}
	if _, ok := put.Headers["x-amz-checksum-sha256"]; ok {

		t.Fatalf("query-signed checksum must not be repeated as an unsigned header: %#v", put.Headers)
	}
	part, err := PresignS3UploadPart(

		context.Background(), cfg, "uploads/videos/a.mp4", "upload-123", 2, time.Minute,
	)
	if err != nil {

		t.Fatalf("presign part: %v", err)
	}
	if !strings.Contains(part.URL, "partNumber=2") ||

		!strings.Contains(part.URL, "uploadId=upload-123") {

		t.Fatalf("unexpected presigned part URL: %s", part.URL)
	}
}
func TestObjectKeyFromPublicURLRejectsDifferentHost(t *testing.T) {
	var cfg config.StorageConfig
	cfg.Provider = StorageProviderQiniu
	cfg.Qiniu.PublicBaseURL = "cdn.example.com"
	cfg.Qiniu.UseHTTPS = true
	if got, ok := ObjectKeyFromPublicURL(cfg, "https://other.example.com/uploads/images/a.png"); ok {

		t.Fatalf("unexpected match with key %q", got)
	}
}
func TestObjectKeyFromPublicURLRejectsUnexpectedPort(t *testing.T) {
	var cfg config.StorageConfig
	cfg.Provider = StorageProviderQiniu
	cfg.Qiniu.PublicBaseURL = "cdn.example.com"
	cfg.Qiniu.UseHTTPS = true
	if got, ok := ObjectKeyFromPublicURL(cfg, "https://cdn.example.com:9443/uploads/images/a.png"); ok {

		t.Fatalf("unexpected port match with key %q", got)
	}
}
func TestObjectKeyFromPublicURLRejectsTraversal(t *testing.T) {
	var cfg config.StorageConfig
	cfg.Provider = StorageProviderQiniu
	cfg.Qiniu.PublicBaseURL = "cdn.example.com"
	cfg.Qiniu.UseHTTPS = true
	if got, ok := ObjectKeyFromPublicURL(cfg, "https://cdn.example.com/uploads/images/../secret.txt"); ok {

		t.Fatalf("unexpected traversal match with key %q", got)
	}
}
func TestStorageFillZerosPreservesExplicitHTTPSFalse(t *testing.T) {
	var yamlCfg config.StorageConfig
	yamlCfg.Aliyun.UseHTTPS = true
	yamlCfg.Qiniu.UseHTTPS = true
	var dbCfg config.StorageConfig
	var presence storageConfigFieldPresence
	aliyunHTTPS := false
	qiniuHTTPS := false
	presence.Aliyun.UseHTTPS = &aliyunHTTPS
	presence.Qiniu.UseHTTPS = &qiniuHTTPS
	got := storageFillZeros(dbCfg, yamlCfg, presence)
	if got.Aliyun.UseHTTPS {

		t.Fatal("Aliyun UseHTTPS should preserve explicit false")
	}
	if got.Qiniu.UseHTTPS {

		t.Fatal("Qiniu UseHTTPS should preserve explicit false")
	}
}
func TestStorageFillZerosBackfillsMissingHTTPS(t *testing.T) {
	var yamlCfg config.StorageConfig
	yamlCfg.Aliyun.UseHTTPS = true
	yamlCfg.Qiniu.UseHTTPS = true
	got := storageFillZeros(config.StorageConfig{}, yamlCfg, storageConfigFieldPresence{})
	if !got.Aliyun.UseHTTPS {

		t.Fatal("Aliyun UseHTTPS should backfill from yaml when missing")
	}
	if !got.Qiniu.UseHTTPS {

		t.Fatal("Qiniu UseHTTPS should backfill from yaml when missing")
	}
}
func TestLoadStorageForRuntimeEnvOverridesYAML(t *testing.T) {
	t.Setenv("GENERIC_IM_STORAGE_PROVIDER", "oss")
	t.Setenv("GENERIC_IM_STORAGE_ALIYUN_ENDPOINT", "oss-cn-shanghai.aliyuncs.com")
	t.Setenv("GENERIC_IM_STORAGE_ALIYUN_BUCKET", "media-bucket")
	t.Setenv("GENERIC_IM_STORAGE_ALIYUN_ACCESS_KEY_ID", "env-ak")
	t.Setenv("GENERIC_IM_STORAGE_ALIYUN_ACCESS_KEY_SECRET", "env-sk")
	t.Setenv("GENERIC_IM_STORAGE_ALIYUN_PUBLIC_BASE_URL", "https://media.example.com")
	t.Setenv("GENERIC_IM_STORAGE_ALIYUN_USE_HTTPS", "true")
	var yamlCfg config.StorageConfig
	yamlCfg.Provider = StorageProviderLocal
	got := LoadStorageForRuntime(nil, yamlCfg)
	if got.Provider != StorageProviderAliyun {

		t.Fatalf("provider=%q, want %q", got.Provider, StorageProviderAliyun)
	}
	if got.Aliyun.Endpoint != "oss-cn-shanghai.aliyuncs.com" {

		t.Fatalf("endpoint=%q", got.Aliyun.Endpoint)
	}
	if got.Aliyun.Bucket != "media-bucket" {

		t.Fatalf("bucket=%q", got.Aliyun.Bucket)
	}
	if got.Aliyun.AccessKeyID != "env-ak" || got.Aliyun.AccessKeySecret != "env-sk" {

		t.Fatalf("access keys not loaded from env")
	}
	if got.Aliyun.PublicBaseURL != "https://media.example.com" {

		t.Fatalf("public_base_url=%q", got.Aliyun.PublicBaseURL)
	}
	if !got.Aliyun.UseHTTPS {

		t.Fatal("use_https=false, want true")
	}
}
func TestLoadStorageForRuntimeS3EnvOverrides(t *testing.T) {
	t.Setenv("GENERIC_IM_STORAGE_PROVIDER", "s3")
	t.Setenv("GENERIC_IM_STORAGE_S3_REGION", "ap-southeast-1")
	t.Setenv("GENERIC_IM_STORAGE_S3_BUCKET", "media-bucket")
	t.Setenv("GENERIC_IM_STORAGE_S3_PUBLIC_BASE_URL", "https://media.example.com")
	t.Setenv("GENERIC_IM_STORAGE_S3_ENDPOINT", "https://s3.example.com")
	t.Setenv("GENERIC_IM_STORAGE_S3_USE_PATH_STYLE", "true")
	got := LoadStorageForRuntime(nil, config.StorageConfig{})
	if got.Provider != StorageProviderS3 ||

		got.S3.Region != "ap-southeast-1" ||

		got.S3.Bucket != "media-bucket" ||

		!got.S3.UsePathStyle {

		t.Fatalf("unexpected s3 config: %+v", got.S3)
	}
}
func TestStorageConfigFromDatabaseValueOverridesEnvFallback(t *testing.T) {
	var fallback config.StorageConfig
	fallback.Provider = StorageProviderLocal
	fallback.Local.BaseURL = "https://api.example.com"
	fallback.Aliyun.Endpoint = "oss-cn-env.aliyuncs.com"
	fallback.Aliyun.Bucket = "env-bucket"
	fallback.Aliyun.AccessKeyID = "env-ak"
	fallback.Aliyun.AccessKeySecret = "env-sk"
	fallback.Aliyun.PublicBaseURL = "https://env-media.example.com"
	fallback.Aliyun.UseHTTPS = true
	var dbCfg config.StorageConfig
	dbCfg.Provider = StorageProviderAliyun
	dbCfg.Aliyun.Endpoint = "oss-cn-db.aliyuncs.com"
	dbCfg.Aliyun.Bucket = "db-bucket"
	dbCfg.Aliyun.AccessKeyID = "db-ak"
	dbCfg.Aliyun.AccessKeySecret = "db-sk"
	dbCfg.Aliyun.PublicBaseURL = "https://db-media.example.com"
	dbCfg.Aliyun.UseHTTPS = true
	raw, err := json.Marshal(dbCfg)
	if err != nil {

		t.Fatalf("marshal db cfg: %v", err)
	}
	got, ok := storageConfigFromDatabaseValue(string(raw), fallback)
	if !ok {

		t.Fatal("database storage config should be parsed")
	}
	got = normalizeStorageConfig(got)
	if got.Provider != StorageProviderAliyun {

		t.Fatalf("provider=%q, want %q", got.Provider, StorageProviderAliyun)
	}
	if got.Aliyun.Endpoint != "oss-cn-db.aliyuncs.com" {

		t.Fatalf("endpoint=%q", got.Aliyun.Endpoint)
	}
	if got.Aliyun.Bucket != "db-bucket" {

		t.Fatalf("bucket=%q", got.Aliyun.Bucket)
	}
	if got.Aliyun.AccessKeyID != "db-ak" || got.Aliyun.AccessKeySecret != "db-sk" {

		t.Fatalf("database access keys were not preferred")
	}
	if got.Aliyun.PublicBaseURL != "https://db-media.example.com" {

		t.Fatalf("public_base_url=%q", got.Aliyun.PublicBaseURL)
	}
}
func TestStorageConfigFromDatabaseValueFillsMissingFieldsFromFallback(t *testing.T) {
	var fallback config.StorageConfig
	fallback.Provider = StorageProviderAliyun
	fallback.Aliyun.Endpoint = "oss-cn-env.aliyuncs.com"
	fallback.Aliyun.Bucket = "env-bucket"
	fallback.Aliyun.AccessKeyID = "env-ak"
	fallback.Aliyun.AccessKeySecret = "env-sk"
	fallback.Aliyun.PublicBaseURL = "https://env-media.example.com"
	fallback.Aliyun.UseHTTPS = true
	var dbCfg config.StorageConfig
	dbCfg.Provider = StorageProviderAliyun
	dbCfg.Aliyun.Bucket = "db-bucket"
	raw, err := json.Marshal(dbCfg)
	if err != nil {

		t.Fatalf("marshal db cfg: %v", err)
	}
	got, ok := storageConfigFromDatabaseValue(string(raw), fallback)
	if !ok {

		t.Fatal("database storage config should be parsed")
	}
	if got.Aliyun.Bucket != "db-bucket" {

		t.Fatalf("bucket=%q, want db-bucket", got.Aliyun.Bucket)
	}
	if got.Aliyun.Endpoint != "oss-cn-env.aliyuncs.com" {

		t.Fatalf("endpoint=%q, want fallback endpoint", got.Aliyun.Endpoint)
	}
	if got.Aliyun.AccessKeyID != "env-ak" || got.Aliyun.AccessKeySecret != "env-sk" {

		t.Fatalf("missing database access keys should be filled from fallback")
	}
}
