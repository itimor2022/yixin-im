// 文件用途：实现可复用的后端业务服务和领域逻辑。
// 核心逻辑：协调数据库、缓存、队列和外部服务，集中处理事务、幂等、重试和错误传播。

package services

import (
	"context"
	"crypto/hmac"
	"crypto/sha1"
	"crypto/sha256"
	"encoding/base64"
	"encoding/hex"
	"encoding/json"
	"fmt"
	"github.com/aws/aws-sdk-go-v2/aws"
	awsconfig "github.com/aws/aws-sdk-go-v2/config"
	"github.com/aws/aws-sdk-go-v2/credentials"
	"github.com/aws/aws-sdk-go-v2/service/s3"
	s3types "github.com/aws/aws-sdk-go-v2/service/s3/types"
	"gorm.io/gorm"
	"io"
	"mime/multipart"
	"net/http"
	"net/textproto"
	"net/url"
	"os"
	"path"
	"path/filepath"
	"strings"
	"sync"
	"time"
	"genericim/internal/config"
	"genericim/internal/models"
)

const (
	StorageProviderLocal       = "local"
	StorageProviderAliyun      = "aliyun"
	StorageProviderQiniu       = "qiniu"
	StorageProviderS3          = "s3"
	defaultQiniuUploadURL      = "https://upload.qiniup.com"
	defaultQiniuManagementHost = "rs.qiniuapi.com"
)
const immutableObjectCacheControl = "public, max-age=31536000, immutable"

var s3RuntimeClientCache struct {
	sync.Mutex
	fingerprint string
	client      *s3.Client
}

type storageConfigFieldPresence struct {
	Aliyun struct {
		UseHTTPS *bool `json:"use_https"`
	} `json:"aliyun"`
	Qiniu struct {
		UseHTTPS *bool `json:"use_https"`
	} `json:"qiniu"`
	S3 struct {
		UsePathStyle *bool `json:"use_path_style"`
	} `json:"s3"`
} // LoadStorageForRuntime merges env, yaml and database cloud_storage JSON. // Database settings are the runtime source of truth; env only seeds/fills the // fallback config used when no database value exists. // 数据库配置是运行期权威值；环境变量和 YAML 只补齐数据库未提供的字段， // 避免管理后台更新后仍被进程启动参数意外覆盖。
func LoadStorageForRuntime(db *gorm.DB, yamlCfg config.StorageConfig) config.StorageConfig {
	fallbackCfg := applyStorageEnvOverrides(yamlCfg)
	if db == nil {

		return normalizeStorageConfig(fallbackCfg)
	}
	var row models.SystemSetting
	if err := db.Where("`key` = ?", models.SettingCloudStorage).First(&row).Error; err != nil {

		return normalizeStorageConfig(fallbackCfg)
	}
	if dbCfg, ok := storageConfigFromDatabaseValue(row.Value, fallbackCfg); ok {

		return normalizeStorageConfig(dbCfg)
	}
	return normalizeStorageConfig(fallbackCfg)
}
func storageConfigFromDatabaseValue(raw string, fallbackCfg config.StorageConfig) (config.StorageConfig, bool) {
	raw = strings.TrimSpace(raw)
	if raw == "" || raw == "{}" {

		return config.StorageConfig{}, false
	}
	var dbCfg config.StorageConfig
	if err := json.Unmarshal([]byte(raw), &dbCfg); err != nil {

		return config.StorageConfig{}, false
	}
	decrypted, err := DecryptStorageConfigSecrets(dbCfg)
	if err != nil {

		// Keep the database config authoritative. Empty credentials make the

		// runtime status invalid instead of silently falling back to another

		// credential source.

		dbCfg.S3.AccessKeyID = ""

		dbCfg.S3.SecretAccessKey = ""
	} else {

		dbCfg = decrypted
	}
	var presence storageConfigFieldPresence
	_ = json.Unmarshal([]byte(raw), &presence)
	return storageFillZeros(dbCfg, fallbackCfg, presence), true
}
func applyStorageEnvOverrides(cfg config.StorageConfig) config.StorageConfig {
	setStorageStringEnv("GENERIC_IM_STORAGE_PROVIDER", &cfg.Provider)
	setStorageStringEnv("GENERIC_IM_STORAGE_LOCAL_BASE_URL", &cfg.Local.BaseURL)
	setStorageStringEnv("GENERIC_IM_STORAGE_ALIYUN_ENDPOINT", &cfg.Aliyun.Endpoint)
	setStorageStringEnv("GENERIC_IM_STORAGE_ALIYUN_BUCKET", &cfg.Aliyun.Bucket)
	setStorageStringEnv("GENERIC_IM_STORAGE_ALIYUN_ACCESS_KEY_ID", &cfg.Aliyun.AccessKeyID)
	setStorageStringEnv("GENERIC_IM_STORAGE_ALIYUN_ACCESS_KEY_SECRET", &cfg.Aliyun.AccessKeySecret)
	setStorageStringEnv("GENERIC_IM_STORAGE_ALIYUN_PUBLIC_BASE_URL", &cfg.Aliyun.PublicBaseURL)
	setStorageBoolEnv("GENERIC_IM_STORAGE_ALIYUN_USE_HTTPS", &cfg.Aliyun.UseHTTPS)
	setStorageStringEnv("GENERIC_IM_STORAGE_QINIU_UPLOAD_URL", &cfg.Qiniu.UploadURL)
	setStorageStringEnv("GENERIC_IM_STORAGE_QINIU_BUCKET", &cfg.Qiniu.Bucket)
	setStorageStringEnv("GENERIC_IM_STORAGE_QINIU_ACCESS_KEY", &cfg.Qiniu.AccessKey)
	setStorageStringEnv("GENERIC_IM_STORAGE_QINIU_SECRET_KEY", &cfg.Qiniu.SecretKey)
	setStorageStringEnv("GENERIC_IM_STORAGE_QINIU_PUBLIC_BASE_URL", &cfg.Qiniu.PublicBaseURL)
	setStorageBoolEnv("GENERIC_IM_STORAGE_QINIU_USE_HTTPS", &cfg.Qiniu.UseHTTPS)
	setStorageStringEnv("GENERIC_IM_STORAGE_S3_REGION", &cfg.S3.Region)
	setStorageStringEnv("GENERIC_IM_STORAGE_S3_BUCKET", &cfg.S3.Bucket)
	setStorageStringEnv("GENERIC_IM_STORAGE_S3_ACCESS_KEY_ID", &cfg.S3.AccessKeyID)
	setStorageStringEnv("GENERIC_IM_STORAGE_S3_SECRET_ACCESS_KEY", &cfg.S3.SecretAccessKey)
	setStorageStringEnv("GENERIC_IM_STORAGE_S3_PUBLIC_BASE_URL", &cfg.S3.PublicBaseURL)
	setStorageStringEnv("GENERIC_IM_STORAGE_S3_ENDPOINT", &cfg.S3.Endpoint)
	setStorageBoolEnv("GENERIC_IM_STORAGE_S3_USE_PATH_STYLE", &cfg.S3.UsePathStyle)
	return cfg
}
func setStorageStringEnv(key string, target *string) {
	if value, ok := os.LookupEnv(key); ok {

		*target = strings.TrimSpace(value)
	}
}
func setStorageBoolEnv(key string, target *bool) {
	value, ok := os.LookupEnv(key)
	if !ok {

		return
	}
	switch strings.ToLower(strings.TrimSpace(value)) {
	case "1", "t", "true", "yes", "y", "on":

		*target = true
	case "0", "f", "false", "no", "n", "off":

		*target = false
	}
}
func storageFillZeros(db, yaml config.StorageConfig, presence storageConfigFieldPresence) config.StorageConfig {
	out := db
	if strings.TrimSpace(out.Provider) == "" {

		out.Provider = yaml.Provider
	}
	if out.Local.BaseURL == "" {

		out.Local.BaseURL = yaml.Local.BaseURL
	}
	al := out.Aliyun
	yal := yaml.Aliyun
	if al.Endpoint == "" {

		al.Endpoint = yal.Endpoint
	}
	if al.Bucket == "" {

		al.Bucket = yal.Bucket
	}
	if al.AccessKeyID == "" {

		al.AccessKeyID = yal.AccessKeyID
	}
	if al.AccessKeySecret == "" {

		al.AccessKeySecret = yal.AccessKeySecret
	}
	if al.PublicBaseURL == "" {

		al.PublicBaseURL = yal.PublicBaseURL
	}
	if presence.Aliyun.UseHTTPS == nil && !al.UseHTTPS {

		al.UseHTTPS = yal.UseHTTPS
	}
	out.Aliyun = al
	qn := out.Qiniu
	yqn := yaml.Qiniu
	if qn.UploadURL == "" {

		qn.UploadURL = yqn.UploadURL
	}
	if qn.Bucket == "" {

		qn.Bucket = yqn.Bucket
	}
	if qn.AccessKey == "" {

		qn.AccessKey = yqn.AccessKey
	}
	if qn.SecretKey == "" {

		qn.SecretKey = yqn.SecretKey
	}
	if qn.PublicBaseURL == "" {

		qn.PublicBaseURL = yqn.PublicBaseURL
	}
	if presence.Qiniu.UseHTTPS == nil && !qn.UseHTTPS {

		qn.UseHTTPS = yqn.UseHTTPS
	}
	out.Qiniu = qn
	s3Cfg := out.S3
	yamlS3 := yaml.S3
	if s3Cfg.Region == "" {

		s3Cfg.Region = yamlS3.Region
	}
	if s3Cfg.Bucket == "" {

		s3Cfg.Bucket = yamlS3.Bucket
	}
	if s3Cfg.AccessKeyID == "" {

		s3Cfg.AccessKeyID = yamlS3.AccessKeyID
	}
	if s3Cfg.SecretAccessKey == "" {

		s3Cfg.SecretAccessKey = yamlS3.SecretAccessKey
	}
	if s3Cfg.PublicBaseURL == "" {

		s3Cfg.PublicBaseURL = yamlS3.PublicBaseURL
	}
	if s3Cfg.Endpoint == "" {

		s3Cfg.Endpoint = yamlS3.Endpoint
	}
	if presence.S3.UsePathStyle == nil && !s3Cfg.UsePathStyle {

		s3Cfg.UsePathStyle = yamlS3.UsePathStyle
	}
	out.S3 = s3Cfg
	return out
}
func normalizeStorageConfig(cfg config.StorageConfig) config.StorageConfig {
	cfg.Provider = NormalizeStorageProvider(cfg.Provider)
	cfg.Local.BaseURL = strings.TrimRight(strings.TrimSpace(cfg.Local.BaseURL), "/")
	cfg.Aliyun.Endpoint = strings.TrimSpace(cfg.Aliyun.Endpoint)
	cfg.Aliyun.Bucket = strings.TrimSpace(cfg.Aliyun.Bucket)
	cfg.Aliyun.AccessKeyID = strings.TrimSpace(cfg.Aliyun.AccessKeyID)
	cfg.Aliyun.AccessKeySecret = strings.TrimSpace(cfg.Aliyun.AccessKeySecret)
	cfg.Aliyun.PublicBaseURL = strings.TrimRight(strings.TrimSpace(cfg.Aliyun.PublicBaseURL), "/")
	cfg.Qiniu.UploadURL = strings.TrimSpace(cfg.Qiniu.UploadURL)
	if cfg.Qiniu.UploadURL == "" {

		cfg.Qiniu.UploadURL = defaultQiniuUploadURL
	}
	cfg.Qiniu.Bucket = strings.TrimSpace(cfg.Qiniu.Bucket)
	cfg.Qiniu.AccessKey = strings.TrimSpace(cfg.Qiniu.AccessKey)
	cfg.Qiniu.SecretKey = strings.TrimSpace(cfg.Qiniu.SecretKey)
	cfg.Qiniu.PublicBaseURL = strings.TrimRight(strings.TrimSpace(cfg.Qiniu.PublicBaseURL), "/")
	cfg.S3.Region = strings.TrimSpace(cfg.S3.Region)
	cfg.S3.Bucket = strings.TrimSpace(cfg.S3.Bucket)
	cfg.S3.AccessKeyID = strings.TrimSpace(cfg.S3.AccessKeyID)
	cfg.S3.SecretAccessKey = strings.TrimSpace(cfg.S3.SecretAccessKey)
	cfg.S3.PublicBaseURL = strings.TrimRight(strings.TrimSpace(cfg.S3.PublicBaseURL), "/")
	cfg.S3.Endpoint = strings.TrimRight(strings.TrimSpace(cfg.S3.Endpoint), "/")
	return cfg
}
func NormalizeStorageProvider(provider string) string {
	switch strings.ToLower(strings.TrimSpace(provider)) {
	case "", StorageProviderLocal:

		return StorageProviderLocal
	case "aliyun", "aliyun_oss", "oss":

		return StorageProviderAliyun
	case "qiniu", "qiniu_kodo", "kodo":

		return StorageProviderQiniu
	case "s3", "aws_s3", "amazon_s3":

		return StorageProviderS3
	default:

		return strings.ToLower(strings.TrimSpace(provider))
	}
}
func ValidateStorageConfig(cfg config.StorageConfig) error {
	provider := NormalizeStorageProvider(cfg.Provider)
	switch provider {
	case StorageProviderLocal:

		if cfg.Local.BaseURL != "" {

			return validateStorageURL("本地访问域名", cfg.Local.BaseURL, true)

		}

		return nil
	case StorageProviderAliyun:

		a := cfg.Aliyun

		if strings.TrimSpace(a.Endpoint) == "" ||

			strings.TrimSpace(a.Bucket) == "" ||

			strings.TrimSpace(a.AccessKeyID) == "" ||

			strings.TrimSpace(a.AccessKeySecret) == "" {

			return fmt.Errorf("阿里云 OSS 的 Endpoint、Bucket、AccessKey ID、AccessKey Secret 不能为空")

		}

		if _, _, err := normalizeEndpoint(a.Endpoint, a.UseHTTPS); err != nil {

			return fmt.Errorf("阿里云 OSS Endpoint 格式错误")

		}

		if a.PublicBaseURL != "" {

			return validateStorageURL("阿里云访问域名", a.PublicBaseURL, true)

		}

		return nil
	case StorageProviderQiniu:

		q := cfg.Qiniu

		if strings.TrimSpace(q.Bucket) == "" ||

			strings.TrimSpace(q.AccessKey) == "" ||

			strings.TrimSpace(q.SecretKey) == "" ||

			strings.TrimSpace(q.PublicBaseURL) == "" {

			return fmt.Errorf("七牛云的 Bucket、AccessKey、SecretKey、访问域名不能为空")

		}

		if q.UploadURL != "" {

			if err := validateStorageURL("七牛上传接口地址", q.UploadURL, true); err != nil {

				return err

			}

		}

		return validateStorageURL("七牛访问域名", q.PublicBaseURL, true)
	case StorageProviderS3:

		s := cfg.S3

		if strings.TrimSpace(s.Region) == "" ||

			strings.TrimSpace(s.Bucket) == "" ||

			strings.TrimSpace(s.AccessKeyID) == "" ||

			strings.TrimSpace(s.SecretAccessKey) == "" ||

			strings.TrimSpace(s.PublicBaseURL) == "" {

			return fmt.Errorf("Amazon S3 的 Region、Bucket、Access Key ID、Secret Access Key、CloudFront/访问域名不能为空")

		}

		if strings.ContainsAny(s.Bucket, " \t\r\n/\\") {

			return fmt.Errorf("Amazon S3 Bucket 格式错误")

		}

		if err := validateStorageURL("Amazon S3 访问域名", s.PublicBaseURL, true); err != nil {

			return err

		}

		if s.Endpoint != "" {

			if err := validateStorageURL("Amazon S3 自定义 Endpoint", s.Endpoint, false); err != nil {

				return err

			}

		}

		return nil
	default:

		return fmt.Errorf("云存储类型仅支持 local、aliyun、qiniu、s3")
	}
}
func validateStorageURL(label, value string, allowHostOnly bool) error {
	value = strings.TrimSpace(value)
	if value == "" {

		return nil
	}
	if strings.ContainsAny(value, " \t\r\n") {

		return fmt.Errorf("%s不能包含空白字符", label)
	}
	parseValue := value
	if allowHostOnly && !strings.HasPrefix(parseValue, "http://") && !strings.HasPrefix(parseValue, "https://") {

		parseValue = "https://" + parseValue
	}
	parsed, err := url.Parse(parseValue)
	if err != nil || parsed.Host == "" {

		return fmt.Errorf("%s格式错误", label)
	}
	if parsed.Scheme != "http" && parsed.Scheme != "https" {

		return fmt.Errorf("%s仅支持 http 或 https", label)
	}
	return nil
}
func MaskStorageConfigForDemo(raw string) interface{} {
	var cfg config.StorageConfig
	if err := json.Unmarshal([]byte(strings.TrimSpace(raw)), &cfg); err != nil {

		return "******"
	}
	cfg.Aliyun.AccessKeyID = maskIfNotEmpty(cfg.Aliyun.AccessKeyID)
	cfg.Aliyun.AccessKeySecret = maskIfNotEmpty(cfg.Aliyun.AccessKeySecret)
	cfg.Qiniu.AccessKey = maskIfNotEmpty(cfg.Qiniu.AccessKey)
	cfg.Qiniu.SecretKey = maskIfNotEmpty(cfg.Qiniu.SecretKey)
	cfg.S3.AccessKeyID = maskIfNotEmpty(cfg.S3.AccessKeyID)
	cfg.S3.SecretAccessKey = maskIfNotEmpty(cfg.S3.SecretAccessKey)
	return normalizeStorageConfig(cfg)
} // MaskS3StorageCredentials prevents AWS credentials from being returned by // management APIs while still allowing the UI to show that values are set.
func MaskS3StorageCredentials(cfg config.StorageConfig) config.StorageConfig {
	cfg.S3.AccessKeyID = maskIfNotEmpty(cfg.S3.AccessKeyID)
	cfg.S3.SecretAccessKey = maskIfNotEmpty(cfg.S3.SecretAccessKey)
	return cfg
}
func IsMaskedStorageCredential(value string) bool {
	return strings.TrimSpace(value) == storageMaskedSecret
}
func maskIfNotEmpty(value string) string {
	if strings.TrimSpace(value) == "" {

		return ""
	}
	return "******"
}

// UploadObject uploads one object to the selected cloud provider and returns a public URL.
func UploadObject(ctx context.Context, cfg config.StorageConfig, objectKey string, r io.Reader, size int64, contentType string) (string, error) {
	cfg = normalizeStorageConfig(cfg)
	objectKey = strings.TrimLeft(path.Clean(strings.ReplaceAll(objectKey, "\\", "/")), "/")
	if objectKey == "." || objectKey == "" {

		return "", fmt.Errorf("对象路径不能为空")
	}
	if contentType == "" {

		contentType = "application/octet-stream"
	}
	switch cfg.Provider {
	case StorageProviderLocal:

		return uploadLocalObject(cfg, objectKey, r, size)
	case StorageProviderAliyun:

		return uploadAliyunObject(ctx, cfg, objectKey, r, size, contentType)
	case StorageProviderQiniu:

		return uploadQiniuObject(ctx, cfg, objectKey, r, contentType)
	case StorageProviderS3:

		return uploadS3Object(ctx, cfg, objectKey, r, size, contentType)
	default:

		return "", fmt.Errorf("当前存储类型不支持云端上传")
	}
} // DeleteObject deletes one object from the selected cloud provider.

func uploadLocalObject(
	cfg config.StorageConfig,
	objectKey string,
	r io.Reader,
	expectedSize int64) (string, error) {
	baseURL := cfg.Local.BaseURL
	if config.GlobalConfig != nil {

		if strings.TrimSpace(baseURL) == "" {

			baseURL = config.GlobalConfig.Server.BaseURL
		}
	}
	target, err := localObjectFilePath(objectKey)
	if err != nil {

		return "", err
	}
	if err := os.MkdirAll(filepath.Dir(target), 0755); err != nil {

		return "", err
	}
	temp, err := os.CreateTemp(filepath.Dir(target), ".processed-*")
	if err != nil {

		return "", err
	}
	tempPath := temp.Name()
	defer os.Remove(tempPath)
	written, copyErr := io.Copy(temp, r)
	closeErr := temp.Close()
	if copyErr != nil {

		return "", copyErr
	}
	if closeErr != nil {

		return "", closeErr
	}
	if expectedSize >= 0 && written != expectedSize {

		return "", fmt.Errorf("local object size mismatch: expected %d got %d", expectedSize, written)
	}
	if err := os.Chmod(tempPath, 0644); err != nil {

		return "", err
	}
	if err := os.Rename(tempPath, target); err != nil {

		return "", err
	}
	return PublicObjectURL(baseURL, objectKey, true), nil
}

func localObjectFilePath(objectKey string) (string, error) {
	uploadDir := "./uploads"
	if config.GlobalConfig != nil {

		if value := strings.TrimSpace(config.GlobalConfig.Server.UploadDir); value != "" {

			uploadDir = value
		}
	}
	relativePath := strings.TrimPrefix(objectKey, "uploads/")
	root, err := filepath.Abs(uploadDir)
	if err != nil {

		return "", err
	}
	target, err := filepath.Abs(filepath.Join(root, filepath.FromSlash(relativePath)))
	if err != nil {

		return "", err
	}
	rel, err := filepath.Rel(root, target)
	if err != nil || rel == ".." || strings.HasPrefix(rel, ".."+string(filepath.Separator)) {

		return "", fmt.Errorf("local object path escapes upload directory")
	}
	return target, nil
}

// DeleteObject deletes one object from the selected cloud provider.
func DeleteObject(ctx context.Context, cfg config.StorageConfig, objectKey string) error {
	cfg = normalizeStorageConfig(cfg)
	cleanKey, ok := cleanObjectKey(objectKey)
	if !ok {

		return fmt.Errorf("object key cannot be empty")
	}
	switch cfg.Provider {
	case StorageProviderAliyun:

		return deleteAliyunObject(ctx, cfg, cleanKey)
	case StorageProviderQiniu:

		return deleteQiniuObject(ctx, cfg, cleanKey)
	case StorageProviderS3:

		return deleteS3Object(ctx, cfg, cleanKey)
	default:

		return fmt.Errorf("current storage provider does not support cloud delete")
	}
} // ObjectKeyFromPublicURL maps a public cloud URL back to the object key for the current provider.
func ObjectKeyFromPublicURL(cfg config.StorageConfig, rawURL string) (string, bool) {
	cfg = normalizeStorageConfig(cfg)
	switch cfg.Provider {
	case StorageProviderAliyun:

		if key, ok := objectKeyFromPublicBaseURL(cfg.Aliyun.PublicBaseURL, rawURL, cfg.Aliyun.UseHTTPS); ok {

			return key, true

		}
		scheme, endpointHost, err := normalizeEndpoint(cfg.Aliyun.Endpoint, cfg.Aliyun.UseHTTPS)

		if err != nil || strings.TrimSpace(cfg.Aliyun.Bucket) == "" {

			return "", false

		}

		return objectKeyFromPublicBaseURL(scheme+"://"+cfg.Aliyun.Bucket+"."+endpointHost, rawURL, cfg.Aliyun.UseHTTPS)
	case StorageProviderQiniu:

		return objectKeyFromPublicBaseURL(cfg.Qiniu.PublicBaseURL, rawURL, cfg.Qiniu.UseHTTPS)
	case StorageProviderS3:

		return objectKeyFromPublicBaseURL(cfg.S3.PublicBaseURL, rawURL, true)
	default:

		return "", false
	}
}
func newS3Client(ctx context.Context, cfg config.StorageConfig) (*s3.Client, error) {
	s := cfg.S3
	// 指纹包含连接端点和凭据但只保存 SHA-256，不把明文密钥作为缓存键暴露；
	// 配置变化会构造新客户端，同配置则复用连接池。
	fingerprintSource := strings.Join([]string{

		s.Region,

		s.Bucket,

		s.AccessKeyID,

		s.SecretAccessKey,

		s.Endpoint,

		fmt.Sprintf("%t", s.UsePathStyle),
	}, "\x00")
	fingerprintBytes := sha256.Sum256([]byte(fingerprintSource))
	fingerprint := hex.EncodeToString(fingerprintBytes[:])
	s3RuntimeClientCache.Lock()
	defer s3RuntimeClientCache.Unlock()
	if s3RuntimeClientCache.client != nil && s3RuntimeClientCache.fingerprint == fingerprint {

		return s3RuntimeClientCache.client, nil
	}
	clientBuildStartedAt := time.Now()
	loadOptions := []func(*awsconfig.LoadOptions) error{

		awsconfig.WithRegion(s.Region),
	}
	if strings.TrimSpace(s.AccessKeyID) != "" && strings.TrimSpace(s.SecretAccessKey) != "" {

		loadOptions = append(loadOptions, awsconfig.WithCredentialsProvider(

			credentials.NewStaticCredentialsProvider(s.AccessKeyID, s.SecretAccessKey, ""),
		))
	}
	awsCfg, err := awsconfig.LoadDefaultConfig(ctx, loadOptions...)
	if err != nil {

		RecordUploadStage("s3_client_build", clientBuildStartedAt, err)

		return nil, fmt.Errorf("加载 Amazon S3 凭证失败: %w", err)
	}
	client := s3.NewFromConfig(awsCfg, func(options *s3.Options) {

		options.UsePathStyle = s.UsePathStyle

		if s.Endpoint != "" {

			options.BaseEndpoint = aws.String(s.Endpoint)

		}
	})
	s3RuntimeClientCache.fingerprint = fingerprint
	s3RuntimeClientCache.client = client
	RecordUploadStage("s3_client_build", clientBuildStartedAt, nil)
	return client, nil
} // S3PresignedRequest 返回短期 URL、必须随请求发送的签名头和明确过期时间。
type S3PresignedRequest struct {
	URL       string
	Headers   map[string]string
	ExpiresAt time.Time
} // S3UploadedPart 是服务端从 S3 读取并用于最终合并的分片快照。
type S3UploadedPart struct {
	PartNumber int32  `json:"part_number"`
	ETag       string `json:"etag"`
	Size       int64  `json:"size"`
} // S3ObjectInfo 是完成直传时用于核对实际对象属性的服务端视图。
type S3ObjectInfo struct {
	Size           int64
	ContentType    string
	ETag           string
	ChecksumSHA256 string
}

func validateS3DirectConfig(cfg config.StorageConfig) (config.StorageConfig, error) {
	cfg = normalizeStorageConfig(cfg)
	if cfg.Provider != StorageProviderS3 {

		return cfg, fmt.Errorf("direct upload is available only when Amazon S3 is enabled")
	}
	if err := ValidateStorageConfig(cfg); err != nil {

		return cfg, err
	}
	return cfg, nil
}
func PresignS3PutObject(
	ctx context.Context,
	cfg config.StorageConfig,
	objectKey string,
	size int64,
	contentType string,
	checksumSHA256 string,
	ttl time.Duration) (S3PresignedRequest, error) {
	cfg, err := validateS3DirectConfig(cfg)
	if err != nil {

		return S3PresignedRequest{}, err
	}
	client, err := newS3Client(ctx, cfg)
	if err != nil {

		return S3PresignedRequest{}, err
	}
	if ttl <= 0 {

		ttl = 15 * time.Minute
	}
	input := &s3.PutObjectInput{

		Bucket: aws.String(cfg.S3.Bucket),

		Key: aws.String(objectKey),

		ContentType: aws.String(contentType),

		CacheControl: aws.String(immutableObjectCacheControl),
	}
	checksumSHA256 = strings.ToLower(strings.TrimSpace(checksumSHA256))
	checksumBase64 := ""
	if checksumSHA256 != "" {

		rawChecksum, decodeErr := hex.DecodeString(checksumSHA256)

		if decodeErr != nil || len(rawChecksum) != 32 {

			return S3PresignedRequest{}, fmt.Errorf("invalid SHA-256 checksum")

		}
		checksumBase64 = base64.StdEncoding.EncodeToString(rawChecksum)

		input.ChecksumSHA256 = aws.String(checksumBase64)
	}
	// Do not sign Content-Length: browsers control that header and cannot set it
	// explicitly. The completion endpoint verifies the exact object size.
	// 浏览器无法稳定显式设置 Content-Length，因此不将其纳入签名；
	// 对象大小必须在 Complete 阶段通过 HeadObject 再校验。
	_ = size
	presignStartedAt := time.Now()
	result, err := s3.NewPresignClient(client).PresignPutObject(ctx, input, func(options *s3.PresignOptions) {

		options.Expires = ttl
	})
	RecordUploadStage("s3_presign_put", presignStartedAt, err)
	if err != nil {

		return S3PresignedRequest{}, fmt.Errorf("presign Amazon S3 upload failed: %w", err)
	}
	headers := map[string]string{

		"Content-Type": contentType,

		"Cache-Control": immutableObjectCacheControl,
	}
	return S3PresignedRequest{URL: result.URL, Headers: headers, ExpiresAt: time.Now().Add(ttl)}, nil
}
func CreateS3MultipartUpload(
	ctx context.Context,
	cfg config.StorageConfig,
	objectKey, contentType string) (string, error) {
	cfg, err := validateS3DirectConfig(cfg)
	if err != nil {

		return "", err
	}
	client, err := newS3Client(ctx, cfg)
	if err != nil {

		return "", err
	}
	result, err := client.CreateMultipartUpload(ctx, &s3.CreateMultipartUploadInput{

		Bucket: aws.String(cfg.S3.Bucket),

		Key: aws.String(objectKey),

		ContentType: aws.String(contentType),

		CacheControl: aws.String(immutableObjectCacheControl),
	})
	if err != nil {

		return "", fmt.Errorf("create Amazon S3 multipart upload failed: %w", err)
	}
	if result.UploadId == nil || strings.TrimSpace(*result.UploadId) == "" {

		return "", fmt.Errorf("Amazon S3 did not return a multipart upload ID")
	}
	return *result.UploadId, nil
}
func PresignS3UploadPart(
	ctx context.Context,
	cfg config.StorageConfig,
	objectKey, uploadID string,
	partNumber int32,
	ttl time.Duration) (S3PresignedRequest, error) {
	cfg, err := validateS3DirectConfig(cfg)
	if err != nil {

		return S3PresignedRequest{}, err
	}
	if partNumber < 1 || partNumber > 10000 {

		return S3PresignedRequest{}, fmt.Errorf("invalid multipart part number")
	}
	client, err := newS3Client(ctx, cfg)
	if err != nil {

		return S3PresignedRequest{}, err
	}
	if ttl <= 0 {

		ttl = 15 * time.Minute
	}
	result, err := s3.NewPresignClient(client).PresignUploadPart(ctx, &s3.UploadPartInput{

		Bucket: aws.String(cfg.S3.Bucket),

		Key: aws.String(objectKey),

		UploadId: aws.String(uploadID),

		PartNumber: aws.Int32(partNumber),
	}, func(options *s3.PresignOptions) {

		options.Expires = ttl
	})
	if err != nil {

		return S3PresignedRequest{}, fmt.Errorf("presign Amazon S3 part failed: %w", err)
	}
	return S3PresignedRequest{

		URL: result.URL,

		Headers: map[string]string{},

		ExpiresAt: time.Now().Add(ttl),
	}, nil
}
func ListS3MultipartParts(
	ctx context.Context,
	cfg config.StorageConfig,
	objectKey, uploadID string) ([]S3UploadedPart, error) {
	cfg, err := validateS3DirectConfig(cfg)
	if err != nil {

		return nil, err
	}
	client, err := newS3Client(ctx, cfg)
	if err != nil {

		return nil, err
	}
	paginator := s3.NewListPartsPaginator(client, &s3.ListPartsInput{

		Bucket: aws.String(cfg.S3.Bucket),

		Key: aws.String(objectKey),

		UploadId: aws.String(uploadID),
	})
	parts := make([]S3UploadedPart, 0)
	for paginator.HasMorePages() {

		page, pageErr := paginator.NextPage(ctx)

		if pageErr != nil {

			return nil, fmt.Errorf("list Amazon S3 multipart parts failed: %w", pageErr)

		}

		for _, part := range page.Parts {

			parts = append(parts, S3UploadedPart{

				PartNumber: aws.ToInt32(part.PartNumber),

				ETag: aws.ToString(part.ETag),

				Size: aws.ToInt64(part.Size),
			})

		}
	}
	return parts, nil
}
func CompleteS3MultipartUpload(
	ctx context.Context,
	cfg config.StorageConfig,
	objectKey, uploadID string,
	parts []S3UploadedPart) error {
	cfg, err := validateS3DirectConfig(cfg)
	if err != nil {

		return err
	}
	client, err := newS3Client(ctx, cfg)
	if err != nil {

		return err
	}
	completed := make([]s3types.CompletedPart, 0, len(parts))
	// parts 必须来自 ListParts 后的服务端校验结果，不能直接信任客户端提交的 ETag/顺序。
	for _, part := range parts {

		completed = append(completed, s3types.CompletedPart{

			PartNumber: aws.Int32(part.PartNumber),

			ETag: aws.String(part.ETag),
		})
	}
	if _, err := client.CompleteMultipartUpload(ctx, &s3.CompleteMultipartUploadInput{

		Bucket: aws.String(cfg.S3.Bucket),

		Key: aws.String(objectKey),

		UploadId: aws.String(uploadID),

		MultipartUpload: &s3types.CompletedMultipartUpload{

			Parts: completed,
		},
	}); err != nil {

		return fmt.Errorf("complete Amazon S3 multipart upload failed: %w", err)
	}
	return nil
}
func AbortS3MultipartUpload(
	ctx context.Context,
	cfg config.StorageConfig,
	objectKey, uploadID string) error {
	cfg, err := validateS3DirectConfig(cfg)
	if err != nil {

		return err
	}
	client, err := newS3Client(ctx, cfg)
	if err != nil {

		return err
	}
	_, err = client.AbortMultipartUpload(ctx, &s3.AbortMultipartUploadInput{

		Bucket: aws.String(cfg.S3.Bucket),

		Key: aws.String(objectKey),

		UploadId: aws.String(uploadID),
	})
	if err != nil {

		return fmt.Errorf("abort Amazon S3 multipart upload failed: %w", err)
	}
	return nil
}
func HeadS3Object(ctx context.Context, cfg config.StorageConfig, objectKey string) (S3ObjectInfo, error) {
	cfg, err := validateS3DirectConfig(cfg)
	if err != nil {

		return S3ObjectInfo{}, err
	}
	client, err := newS3Client(ctx, cfg)
	if err != nil {

		return S3ObjectInfo{}, err
	}
	headStartedAt := time.Now()
	result, err := client.HeadObject(ctx, &s3.HeadObjectInput{

		Bucket: aws.String(cfg.S3.Bucket),

		Key: aws.String(objectKey),

		ChecksumMode: s3types.ChecksumModeEnabled,
	})
	RecordUploadStage("s3_head_object", headStartedAt, err)
	if err != nil {

		return S3ObjectInfo{}, fmt.Errorf("head Amazon S3 object failed: %w", err)
	}
	return S3ObjectInfo{

		Size: aws.ToInt64(result.ContentLength),

		ContentType: aws.ToString(result.ContentType),

		ETag: aws.ToString(result.ETag),

		ChecksumSHA256: aws.ToString(result.ChecksumSHA256),
	}, nil
}
func ReadS3ObjectPrefix(
	ctx context.Context,
	cfg config.StorageConfig,
	objectKey string,
	limit int64) ([]byte, error) {
	cfg, err := validateS3DirectConfig(cfg)
	if err != nil {

		return nil, err
	}
	if limit <= 0 || limit > 64*1024 {

		limit = 4096
	}
	client, err := newS3Client(ctx, cfg)
	if err != nil {

		return nil, err
	}
	rangeStartedAt := time.Now()
	result, err := client.GetObject(ctx, &s3.GetObjectInput{

		Bucket: aws.String(cfg.S3.Bucket),

		Key: aws.String(objectKey),

		Range: aws.String(fmt.Sprintf("bytes=0-%d", limit-1)),
	})
	RecordUploadStage("s3_range_get", rangeStartedAt, err)
	if err != nil {

		return nil, fmt.Errorf("read Amazon S3 object prefix failed: %w", err)
	}
	defer result.Body.Close()
	data, err := io.ReadAll(io.LimitReader(result.Body, limit))
	if err != nil {

		return nil, fmt.Errorf("read Amazon S3 object prefix failed: %w", err)
	}
	return data, nil
}
func ReadS3ObjectLimited(
	ctx context.Context,
	cfg config.StorageConfig,
	objectKey string,
	maxBytes int64) ([]byte, error) {
	cfg, err := validateS3DirectConfig(cfg)
	if err != nil {

		return nil, err
	}
	if maxBytes <= 0 || maxBytes > 32*1024*1024 {

		return nil, fmt.Errorf("invalid Amazon S3 read limit")
	}
	client, err := newS3Client(ctx, cfg)
	if err != nil {

		return nil, err
	}
	fullReadStartedAt := time.Now()
	result, err := client.GetObject(ctx, &s3.GetObjectInput{

		Bucket: aws.String(cfg.S3.Bucket),

		Key: aws.String(objectKey),
	})
	RecordUploadStage("s3_full_get", fullReadStartedAt, err)
	if err != nil {

		return nil, fmt.Errorf("read Amazon S3 object failed: %w", err)
	}
	defer result.Body.Close()
	// 多读 1 字节用于区分“恰好达到上限”和“实际超限”，避免完整载入未知大小对象。
	data, err := io.ReadAll(io.LimitReader(result.Body, maxBytes+1))
	if err != nil {

		return nil, fmt.Errorf("read Amazon S3 object failed: %w", err)
	}
	if int64(len(data)) > maxBytes {

		return nil, fmt.Errorf("Amazon S3 object exceeds validation limit")
	}
	return data, nil
}
func ComputeS3ObjectSHA256(
	ctx context.Context,
	cfg config.StorageConfig,
	objectKey string,
	maxBytes int64) (string, error) {
	cfg, err := validateS3DirectConfig(cfg)
	if err != nil {

		return "", err
	}
	if maxBytes <= 0 || maxBytes > 100*1024*1024 {

		return "", fmt.Errorf("invalid Amazon S3 checksum limit")
	}
	client, err := newS3Client(ctx, cfg)
	if err != nil {

		return "", err
	}
	checksumStartedAt := time.Now()
	result, err := client.GetObject(ctx, &s3.GetObjectInput{

		Bucket: aws.String(cfg.S3.Bucket),

		Key: aws.String(objectKey),
	})
	RecordUploadStage("s3_checksum_get", checksumStartedAt, err)
	if err != nil {

		return "", fmt.Errorf("read Amazon S3 object for checksum failed: %w", err)
	}
	defer result.Body.Close()
	digest := sha256.New()
	written, err := io.Copy(digest, io.LimitReader(result.Body, maxBytes+1))
	if err != nil {

		return "", fmt.Errorf("calculate Amazon S3 checksum failed: %w", err)
	}
	if written > maxBytes {

		return "", fmt.Errorf("Amazon S3 object exceeds checksum limit")
	}
	return hex.EncodeToString(digest.Sum(nil)), nil
}
func PresignS3GetObject(
	ctx context.Context,
	cfg config.StorageConfig,
	objectKey, downloadName string,
	ttl time.Duration) (S3PresignedRequest, error) {
	cfg, err := validateS3DirectConfig(cfg)
	if err != nil {

		return S3PresignedRequest{}, err
	}
	client, err := newS3Client(ctx, cfg)
	if err != nil {

		return S3PresignedRequest{}, err
	}
	if ttl <= 0 {

		ttl = 10 * time.Minute
	}
	input := &s3.GetObjectInput{

		Bucket: aws.String(cfg.S3.Bucket),

		Key: aws.String(objectKey),
	}
	if strings.TrimSpace(downloadName) != "" {

		input.ResponseContentDisposition = aws.String(fmt.Sprintf("inline; filename*=UTF-8''%s", url.PathEscape(downloadName)))
	}
	result, err := s3.NewPresignClient(client).PresignGetObject(ctx, input, func(options *s3.PresignOptions) {

		options.Expires = ttl
	})
	if err != nil {

		return S3PresignedRequest{}, fmt.Errorf("presign Amazon S3 access URL failed: %w", err)
	}
	return S3PresignedRequest{URL: result.URL, Headers: map[string]string{}, ExpiresAt: time.Now().Add(ttl)}, nil
}
func StorageObjectPublicURL(cfg config.StorageConfig, objectKey string) string {
	cfg = normalizeStorageConfig(cfg)
	switch cfg.Provider {
	case StorageProviderS3:

		return joinPublicURL(cfg.S3.PublicBaseURL, objectKey, true)
	case StorageProviderAliyun:

		return joinPublicURL(cfg.Aliyun.PublicBaseURL, objectKey, cfg.Aliyun.UseHTTPS)
	case StorageProviderQiniu:

		return joinPublicURL(cfg.Qiniu.PublicBaseURL, objectKey, cfg.Qiniu.UseHTTPS)
	default:

		return ""
	}
}
func uploadS3Object(ctx context.Context, cfg config.StorageConfig, objectKey string, r io.Reader, size int64, contentType string) (string, error) {
	client, err := newS3Client(ctx, cfg)
	if err != nil {

		return "", err
	}
	body, cleanup, err := prepareRetryableS3UploadBody(r, size)
	if err != nil {
		return "", err
	}
	defer cleanup()
	input := &s3.PutObjectInput{

		Bucket: aws.String(cfg.S3.Bucket),

		Key: aws.String(objectKey),

		Body: body,

		ContentType: aws.String(contentType),

		CacheControl: aws.String(immutableObjectCacheControl),
	}
	if size >= 0 {

		input.ContentLength = aws.Int64(size)
	}
	putStartedAt := time.Now()
	if _, err := client.PutObject(ctx, input); err != nil {

		RecordUploadStage("s3_put_object", putStartedAt, err)

		return "", fmt.Errorf("Amazon S3 上传失败: %w", err)
	}
	RecordUploadStage("s3_put_object", putStartedAt, nil)
	headStartedAt := time.Now()
	head, err := client.HeadObject(ctx, &s3.HeadObjectInput{

		Bucket: aws.String(cfg.S3.Bucket),

		Key: aws.String(objectKey),
	})
	RecordUploadStage("s3_head_object", headStartedAt, err)
	if err != nil {

		_ = deleteS3Object(context.Background(), cfg, objectKey)

		return "", fmt.Errorf("Amazon S3 上传后校验失败: %w", err)
	}
	if size >= 0 && head.ContentLength != nil && *head.ContentLength != size {

		_ = deleteS3Object(context.Background(), cfg, objectKey)

		return "", fmt.Errorf("Amazon S3 对象大小校验失败: got=%d want=%d", *head.ContentLength, size)
	}
	return joinPublicURL(cfg.S3.PublicBaseURL, objectKey, true), nil
}

// prepareRetryableS3UploadBody ensures the AWS SDK can rewind a request body
// after a transient transport failure. HTTP multipart streams and TeeReader do
// not implement io.Seeker, so they are spooled to a temporary file instead of
// being buffered completely in memory.
func prepareRetryableS3UploadBody(r io.Reader, expectedSize int64) (io.ReadSeeker, func(), error) {
	if r == nil {
		return nil, func() {}, fmt.Errorf("Amazon S3 upload body is nil")
	}
	if seeker, ok := r.(io.ReadSeeker); ok {
		if _, err := seeker.Seek(0, io.SeekStart); err != nil {
			return nil, func() {}, fmt.Errorf("rewind Amazon S3 upload body: %w", err)
		}
		return seeker, func() {}, nil
	}

	temp, err := os.CreateTemp("", ".genericim-s3-upload-*")
	if err != nil {
		return nil, func() {}, fmt.Errorf("create Amazon S3 upload spool: %w", err)
	}
	tempPath := temp.Name()
	cleanup := func() {
		_ = temp.Close()
		_ = os.Remove(tempPath)
	}
	written, copyErr := io.Copy(temp, r)
	if copyErr != nil {
		cleanup()
		return nil, func() {}, fmt.Errorf("spool Amazon S3 upload body: %w", copyErr)
	}
	if expectedSize >= 0 && written != expectedSize {
		cleanup()
		return nil, func() {}, fmt.Errorf(
			"Amazon S3 upload spool size mismatch: got=%d want=%d",
			written,
			expectedSize,
		)
	}
	if _, err := temp.Seek(0, io.SeekStart); err != nil {
		cleanup()
		return nil, func() {}, fmt.Errorf("rewind Amazon S3 upload spool: %w", err)
	}
	return temp, cleanup, nil
}

func deleteS3Object(ctx context.Context, cfg config.StorageConfig, objectKey string) error {
	client, err := newS3Client(ctx, cfg)
	if err != nil {

		return err
	}
	if _, err := client.DeleteObject(ctx, &s3.DeleteObjectInput{

		Bucket: aws.String(cfg.S3.Bucket),

		Key: aws.String(objectKey),
	}); err != nil {

		return fmt.Errorf("Amazon S3 删除失败: %w", err)
	}
	return nil
}
func uploadAliyunObject(ctx context.Context, cfg config.StorageConfig, objectKey string, r io.Reader, size int64, contentType string) (string, error) {
	a := cfg.Aliyun
	scheme, endpointHost, err := normalizeEndpoint(a.Endpoint, a.UseHTTPS)
	if err != nil {

		return "", err
	}
	bucketHost := a.Bucket + "." + endpointHost
	putURL := (&url.URL{

		Scheme: scheme,

		Host: bucketHost,

		Path: "/" + objectKey,
	}).String()
	req, err := http.NewRequestWithContext(ctx, http.MethodPut, putURL, r)
	if err != nil {

		return "", err
	}
	date := time.Now().UTC().Format(http.TimeFormat)
	stringToSign := strings.Join([]string{

		http.MethodPut,

		"",

		contentType,

		date,

		"/" + a.Bucket + "/" + objectKey,
	}, "\n")
	req.Header.Set("Date", date)
	req.Header.Set("Content-Type", contentType)
	applyImmutableObjectCacheHeader(req.Header)
	req.Header.Set("Authorization", "OSS "+a.AccessKeyID+":"+signHMACSHA1Base64(a.AccessKeySecret, stringToSign))
	if size >= 0 {

		req.ContentLength = size
	}
	resp, err := http.DefaultClient.Do(req)
	if err != nil {

		return "", err
	}
	defer resp.Body.Close()
	if resp.StatusCode < 200 || resp.StatusCode >= 300 {

		body, _ := io.ReadAll(io.LimitReader(resp.Body, 4096))

		return "", fmt.Errorf("阿里云 OSS 上传失败：%s %s", resp.Status, strings.TrimSpace(string(body)))
	}
	publicBaseURL := a.PublicBaseURL
	if strings.TrimSpace(publicBaseURL) == "" {

		publicBaseURL = scheme + "://" + bucketHost
	}
	return joinPublicURL(publicBaseURL, objectKey, a.UseHTTPS), nil
}
func applyImmutableObjectCacheHeader(header http.Header) {
	header.Set("Cache-Control", immutableObjectCacheControl)
}
func uploadQiniuObject(ctx context.Context, cfg config.StorageConfig, objectKey string, r io.Reader, fileContentType string) (string, error) {
	q := cfg.Qiniu
	uploadURL := strings.TrimSpace(q.UploadURL)
	if uploadURL == "" {

		uploadURL = defaultQiniuUploadURL
	}
	if !strings.HasPrefix(uploadURL, "http://") && !strings.HasPrefix(uploadURL, "https://") {

		uploadURL = "https://" + uploadURL
	}
	pr, pw := io.Pipe()
	writer := multipart.NewWriter(pw)
	requestContentType := writer.FormDataContentType()
	go func() {

		err := func() error {

			if err := writer.WriteField("token", qiniuUploadToken(q.AccessKey, q.SecretKey, q.Bucket, objectKey)); err != nil {

				return err

			}

			if err := writer.WriteField("key", objectKey); err != nil {

				return err

			}
			part, err := createMultipartFilePart(writer, "file", path.Base(objectKey), fileContentType)

			if err != nil {

				return err

			}

			if _, err := io.Copy(part, r); err != nil {

				return err

			}

			return writer.Close()

		}()

		if err != nil {

			_ = pw.CloseWithError(err)

			return

		}
		_ = pw.Close()
	}()
	req, err := http.NewRequestWithContext(ctx, http.MethodPost, uploadURL, pr)
	if err != nil {

		return "", err
	}
	req.Header.Set("Content-Type", requestContentType)
	resp, err := http.DefaultClient.Do(req)
	if err != nil {

		return "", err
	}
	defer resp.Body.Close()
	if resp.StatusCode < 200 || resp.StatusCode >= 300 {

		body, _ := io.ReadAll(io.LimitReader(resp.Body, 4096))

		return "", fmt.Errorf("七牛云上传失败：%s %s", resp.Status, strings.TrimSpace(string(body)))
	}
	return joinPublicURL(q.PublicBaseURL, objectKey, q.UseHTTPS), nil
}
func deleteAliyunObject(ctx context.Context, cfg config.StorageConfig, objectKey string) error {
	a := cfg.Aliyun
	if strings.TrimSpace(a.Bucket) == "" || strings.TrimSpace(a.AccessKeyID) == "" || strings.TrimSpace(a.AccessKeySecret) == "" {

		return fmt.Errorf("aliyun oss delete config incomplete")
	}
	scheme, endpointHost, err := normalizeEndpoint(a.Endpoint, a.UseHTTPS)
	if err != nil {

		return err
	}
	deleteURL := (&url.URL{

		Scheme: scheme,

		Host: a.Bucket + "." + endpointHost,

		Path: "/" + objectKey,
	}).String()
	req, err := http.NewRequestWithContext(ctx, http.MethodDelete, deleteURL, nil)
	if err != nil {

		return err
	}
	date := time.Now().UTC().Format(http.TimeFormat)
	stringToSign := strings.Join([]string{

		http.MethodDelete,

		"",

		"",

		date,

		"/" + a.Bucket + "/" + objectKey,
	}, "\n")
	req.Header.Set("Date", date)
	req.Header.Set("Authorization", "OSS "+a.AccessKeyID+":"+signHMACSHA1Base64(a.AccessKeySecret, stringToSign))
	resp, err := http.DefaultClient.Do(req)
	if err != nil {

		return err
	}
	defer resp.Body.Close()
	_, _ = io.Copy(io.Discard, resp.Body)
	if (resp.StatusCode >= 200 && resp.StatusCode < 300) || resp.StatusCode == http.StatusNotFound {

		return nil
	}
	return fmt.Errorf("aliyun oss delete failed: status=%d", resp.StatusCode)
}
func deleteQiniuObject(ctx context.Context, cfg config.StorageConfig, objectKey string) error {
	q := cfg.Qiniu
	if strings.TrimSpace(q.Bucket) == "" || strings.TrimSpace(q.AccessKey) == "" || strings.TrimSpace(q.SecretKey) == "" {

		return fmt.Errorf("qiniu delete config incomplete")
	}
	encodedEntryURI := qiniuURLSafeBase64([]byte(q.Bucket + ":" + objectKey))
	requestPath := "/delete/" + encodedEntryURI
	deleteURL := (&url.URL{

		Scheme: "https",

		Host: defaultQiniuManagementHost,

		Path: requestPath,
	}).String()
	contentType := "application/x-www-form-urlencoded"
	qiniuDate := time.Now().UTC().Format("20060102T150405Z")
	signingStr := strings.Join([]string{

		http.MethodPost + " " + requestPath,

		"Host: " + defaultQiniuManagementHost,

		"Content-Type: " + contentType,

		"X-Qiniu-Date: " + qiniuDate,

		"",

		"",
	}, "\n")
	req, err := http.NewRequestWithContext(ctx, http.MethodPost, deleteURL, nil)
	if err != nil {

		return err
	}
	req.Header.Set("Content-Type", contentType)
	req.Header.Set("X-Qiniu-Date", qiniuDate)
	req.Header.Set("Authorization", "Qiniu "+q.AccessKey+":"+qiniuSign(q.SecretKey, signingStr))
	resp, err := http.DefaultClient.Do(req)
	if err != nil {

		return err
	}
	defer resp.Body.Close()
	_, _ = io.Copy(io.Discard, resp.Body)
	if (resp.StatusCode >= 200 && resp.StatusCode < 300) || resp.StatusCode == 612 {

		return nil
	}
	return fmt.Errorf("qiniu delete failed: status=%d", resp.StatusCode)
}
func createMultipartFilePart(writer *multipart.Writer, fieldName, filename, contentType string) (io.Writer, error) {
	if contentType == "" {

		contentType = "application/octet-stream"
	}
	header := make(textproto.MIMEHeader)
	header.Set("Content-Disposition", fmt.Sprintf(`form-data; name="%s"; filename="%s"`, escapeMultipartParam(fieldName), escapeMultipartParam(filename)))
	header.Set("Content-Type", contentType)
	return writer.CreatePart(header)
}
func escapeMultipartParam(value string) string {
	return strings.NewReplacer(`\`, `\\`, `"`, `\"`).Replace(value)
}
func cleanObjectKey(value string) (string, bool) {
	value = strings.TrimSpace(strings.ReplaceAll(value, "\\", "/"))
	value = strings.TrimLeft(value, "/")
	if value == "" {

		return "", false
	}
	parts := strings.Split(value, "/")
	cleaned := make([]string, 0, len(parts))
	for _, part := range parts {

		part = strings.TrimSpace(part)

		if part == "" || part == "." {

			continue

		}

		if part == ".." {

			// 对象键会参与删除和 URL 反解，任何上级目录片段都直接拒绝。

			return "", false

		}
		cleaned = append(cleaned, part)
	}
	if len(cleaned) == 0 {

		return "", false
	}
	return strings.Join(cleaned, "/"), true
}
func objectKeyFromPublicBaseURL(baseURL, rawURL string, useHTTPS bool) (string, bool) {
	baseURL = publicBaseURLWithScheme(baseURL, useHTTPS)
	if baseURL == "" {

		return "", false
	}
	base, err := url.Parse(baseURL)
	if err != nil || base == nil || base.Hostname() == "" {

		return "", false
	}
	parsed, err := url.Parse(strings.TrimSpace(rawURL))
	if err != nil || parsed == nil || parsed.Hostname() == "" {

		return "", false
	}
	if parsed.Scheme != "http" && parsed.Scheme != "https" {

		return "", false
	}
	// 只有当前配置的主机、端口和基础路径都匹配时才反解对象键，
	// 防止把任意外部 URL 转换成删除操作的目标。
	if !publicURLHostMatches(base, parsed) {

		return "", false
	}
	value := parsed.Path
	basePath := strings.TrimRight(base.Path, "/")
	if basePath != "" {

		if value == basePath {

			return "", false

		}

		if !strings.HasPrefix(value, basePath+"/") {

			return "", false

		}
		value = strings.TrimPrefix(value, basePath)
	}
	return cleanObjectKey(value)
}
func publicBaseURLWithScheme(baseURL string, useHTTPS bool) string {
	baseURL = strings.TrimRight(strings.TrimSpace(baseURL), "/")
	if baseURL == "" {

		return ""
	}
	if strings.HasPrefix(baseURL, "http://") || strings.HasPrefix(baseURL, "https://") {

		return baseURL
	}
	scheme := "http"
	if useHTTPS {

		scheme = "https"
	}
	return scheme + "://" + baseURL
}
func publicURLHostMatches(base, actual *url.URL) bool {
	if !strings.EqualFold(base.Hostname(), actual.Hostname()) {

		return false
	}
	basePort := base.Port()
	actualPort := actual.Port()
	if basePort == "" {

		return actualPort == "" || actualPort == defaultURLPort(actual.Scheme)
	}
	return basePort == actualPort
}
func defaultURLPort(scheme string) string {
	switch scheme {
	case "http":

		return "80"
	case "https":

		return "443"
	default:

		return ""
	}
}
func normalizeEndpoint(endpoint string, useHTTPS bool) (string, string, error) {
	endpoint = strings.TrimRight(strings.TrimSpace(endpoint), "/")
	if endpoint == "" {

		return "", "", fmt.Errorf("endpoint 不能为空")
	}
	if !strings.HasPrefix(endpoint, "http://") && !strings.HasPrefix(endpoint, "https://") {

		scheme := "http"

		if useHTTPS {

			scheme = "https"

		}
		endpoint = scheme + "://" + endpoint
	}
	parsed, err := url.Parse(endpoint)
	if err != nil || parsed.Host == "" {

		return "", "", fmt.Errorf("endpoint 格式错误")
	}
	if parsed.Scheme != "http" && parsed.Scheme != "https" {

		return "", "", fmt.Errorf("endpoint 仅支持 http 或 https")
	}
	return parsed.Scheme, parsed.Host, nil
}
func signHMACSHA1Base64(secret, data string) string {
	mac := hmac.New(sha1.New, []byte(secret))
	_, _ = mac.Write([]byte(data))
	return base64.StdEncoding.EncodeToString(mac.Sum(nil))
}
func qiniuUploadToken(accessKey, secretKey, bucket, objectKey string) string {
	putPolicy := map[string]interface{}{

		"scope": bucket + ":" + objectKey,

		"deadline": time.Now().Add(time.Hour).Unix(),
	}
	policyBytes, _ := json.Marshal(putPolicy)
	encodedPolicy := base64.RawURLEncoding.EncodeToString(policyBytes)
	mac := hmac.New(sha1.New, []byte(secretKey))
	_, _ = mac.Write([]byte(encodedPolicy))
	encodedSign := base64.RawURLEncoding.EncodeToString(mac.Sum(nil))
	return accessKey + ":" + encodedSign + ":" + encodedPolicy
}
func qiniuSign(secret, data string) string {
	mac := hmac.New(sha1.New, []byte(secret))
	_, _ = mac.Write([]byte(data))
	return qiniuURLSafeBase64(mac.Sum(nil))
}
func qiniuURLSafeBase64(data []byte) string {
	return base64.URLEncoding.EncodeToString(data)
}
func joinPublicURL(baseURL, objectKey string, useHTTPS bool) string {
	return PublicObjectURL(baseURL, objectKey, useHTTPS)
} // PublicObjectURL joins a public base URL and object key, adding a scheme for host-only domains.
func PublicObjectURL(baseURL, objectKey string, useHTTPS bool) string {
	baseURL = strings.TrimRight(strings.TrimSpace(baseURL), "/")
	if baseURL == "" {

		return "/" + strings.TrimLeft(objectKey, "/")
	}
	if !strings.HasPrefix(baseURL, "http://") && !strings.HasPrefix(baseURL, "https://") {

		scheme := "http"

		if useHTTPS {

			scheme = "https"

		}
		baseURL = scheme + "://" + baseURL
	}
	return baseURL + "/" + strings.TrimLeft(objectKey, "/")
}
