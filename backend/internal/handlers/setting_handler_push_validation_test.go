// 文件用途：验证 setting_handler_push_validation_test.go 对应模块的正常流程、异常处理和回归行为。
// 核心逻辑：覆盖输入校验、状态变化、错误返回、边界条件和并发幸命。

package handlers

import (
	"encoding/json"
	"github.com/gin-gonic/gin"
	"strings"
	"testing"
	"genericim/internal/config"
	"genericim/internal/models"
)

func TestParseSettingBoolValue(t *testing.T) {
	t.Parallel()
	tests := []struct {
		name string

		input interface{}

		want bool

		wantError bool
	}{

		{name: "bool true", input: true, want: true},

		{name: "bool false", input: false, want: false},

		{name: "string true", input: "true", want: true},

		{name: "string on", input: "on", want: true},

		{name: "string one", input: "1", want: true},

		{name: "string false", input: "false", want: false},

		{name: "string empty", input: "", want: false},

		{name: "float one", input: float64(1), want: true},

		{name: "float zero", input: float64(0), want: false},

		{name: "string invalid", input: "abc", wantError: true},

		{name: "unsupported type", input: 1, wantError: true},
	}
	for _, tc := range tests {

		tc := tc

		t.Run(tc.name, func(t *testing.T) {

			t.Parallel()
			got, err := parseSettingBoolValue(tc.input)

			if tc.wantError {

				if err == nil {

					t.Fatalf("expected error, got nil")

				}

				return

			}

			if err != nil {

				t.Fatalf("unexpected error: %v", err)

			}

			if got != tc.want {

				t.Fatalf("parseSettingBoolValue(%v)=%v, want %v", tc.input, got, tc.want)

			}

		})
	}
}
func TestNormalizeSettingInputValue(t *testing.T) {
	t.Parallel()
	tests := []struct {
		name string

		input interface{}

		want string
	}{

		{name: "trim string", input: "  value  ", want: "value"},

		{name: "bool true", input: true, want: "true"},

		{name: "bool false", input: false, want: "false"},

		{name: "float to int", input: float64(12), want: "12"},
	}
	for _, tc := range tests {

		tc := tc

		t.Run(tc.name, func(t *testing.T) {

			t.Parallel()
			got := normalizeSettingInputValue(tc.input)

			if got != tc.want {

				t.Fatalf("normalizeSettingInputValue(%v)=%q, want %q", tc.input, got, tc.want)

			}

		})
	}
	t.Run("object marshal", func(t *testing.T) {

		t.Parallel()
		got := normalizeSettingInputValue(map[string]interface{}{"a": 1})

		if got == "" {

			t.Fatalf("expected marshaled json, got empty string")

		}
	})
}
func TestValidateSystemSettingsForUpdateRTCProvider(t *testing.T) {
	t.Parallel()
	handler := &SettingHandler{}
	tests := []struct {
		name string

		value interface{}

		wantError bool
	}{

		{name: "agora", value: "agora"},

		{name: "livekit", value: "livekit"},

		{name: "trim and case", value: " LiveKit "},

		{name: "empty defaults to agora", value: ""},

		{name: "invalid", value: "twilio", wantError: true},
	}
	for _, tc := range tests {

		tc := tc

		t.Run(tc.name, func(t *testing.T) {

			t.Parallel()
			err := handler.validateSystemSettingsForUpdate(map[string]interface{}{

				models.SettingRTCProvider: tc.value,
			})

			if tc.wantError && err == nil {

				t.Fatalf("expected error, got nil")

			}

			if !tc.wantError && err != nil {

				t.Fatalf("unexpected error: %v", err)

			}

		})
	}
}
func TestValidateSystemSettingsForUpdateLiveKitServerURL(t *testing.T) {
	t.Parallel()
	handler := &SettingHandler{}
	tests := []struct {
		name string

		value string

		wantError bool
	}{

		{name: "empty allowed", value: ""},

		{name: "wss url", value: "wss://livekit.example.com"},

		{name: "http localhost", value: "http://localhost:7880"},

		{name: "missing scheme", value: "livekit.example.com", wantError: true},

		{name: "unsupported scheme", value: "ftp://livekit.example.com", wantError: true},

		{name: "contains whitespace", value: "wss://live kit.example.com", wantError: true},
	}
	for _, tc := range tests {

		tc := tc

		t.Run(tc.name, func(t *testing.T) {

			t.Parallel()
			err := handler.validateSystemSettingsForUpdate(map[string]interface{}{

				models.SettingLiveKitServerURL: tc.value,
			})

			if tc.wantError && err == nil {

				t.Fatalf("expected error, got nil")

			}

			if !tc.wantError && err != nil {

				t.Fatalf("unexpected error: %v", err)

			}

		})
	}
}
func TestValidateFCMPushConfig(t *testing.T) {
	t.Parallel()
	const validJSON = `{ 

"type":"service_account", 

"project_id":"timi-9125c", 

"client_email":"firebase-adminsdk@test.iam.gserviceaccount.com", 

"private_key":"-----BEGIN PRIVATE KEY-----\nabc\n-----END PRIVATE KEY-----\n" 
}`
	tests := []struct {
		name string

		projectID string

		json string

		wantError bool
	}{

		{

			name: "valid",

			projectID: "timi-9125c",

			json: validJSON,

			wantError: false,
		},

		{

			name: "mobilesdk_app_id_should_fail",

			projectID: "1:462874705402:android:1ee89f88de6ab550afb843",

			json: validJSON,

			wantError: true,
		},

		{

			name: "missing_project_id_in_json",

			projectID: "timi-9125c",

			json: `{ 



"type":"service_account", 



"client_email":"firebase-adminsdk@test.iam.gserviceaccount.com", 



"private_key":"-----BEGIN PRIVATE KEY-----\nabc\n-----END PRIVATE KEY-----\n" 


}`,

			wantError: true,
		},

		{

			name: "project_id_mismatch",

			projectID: "another-project",

			json: validJSON,

			wantError: true,
		},
	}
	for _, tc := range tests {

		tc := tc

		t.Run(tc.name, func(t *testing.T) {

			t.Parallel()
			err := validateFCMPushConfig(tc.projectID, tc.json)

			if tc.wantError && err == nil {

				t.Fatalf("expected error, got nil")

			}

			if !tc.wantError && err != nil {

				t.Fatalf("unexpected error: %v", err)

			}

		})
	}
}
func TestCloudStorageSettingValueFallsBackToYAML(t *testing.T) {
	oldConfig := config.GlobalConfig
	t.Cleanup(func() {

		config.GlobalConfig = oldConfig
	})
	cfg := &config.Config{}
	cfg.Storage.Provider = "qiniu"
	cfg.Storage.Qiniu.UploadURL = "https://upload.qiniup.com"
	cfg.Storage.Qiniu.Bucket = "bucket-a"
	cfg.Storage.Qiniu.AccessKey = "ak"
	cfg.Storage.Qiniu.SecretKey = "sk"
	cfg.Storage.Qiniu.PublicBaseURL = "cdn.example.com"
	cfg.Storage.Qiniu.UseHTTPS = true
	config.GlobalConfig = cfg
	value, ok := cloudStorageSettingValue(nil, false).(config.StorageConfig)
	if !ok {

		t.Fatalf("expected StorageConfig value, got %T", value)
	}
	if value.Provider != "qiniu" {

		t.Fatalf("provider=%q, want qiniu", value.Provider)
	}
	if value.Qiniu.PublicBaseURL != "cdn.example.com" {

		t.Fatalf("public_base_url=%q, want cdn.example.com", value.Qiniu.PublicBaseURL)
	}
}
func TestCloudStorageSettingRecordUsesJSON(t *testing.T) {
	oldConfig := config.GlobalConfig
	t.Cleanup(func() {

		config.GlobalConfig = oldConfig
	})
	cfg := &config.Config{}
	cfg.Storage.Provider = "local"
	cfg.Storage.Local.BaseURL = "cdn.example.com"
	config.GlobalConfig = cfg
	record := cloudStorageSettingRecord(nil, false)
	if record.Key != models.SettingCloudStorage {

		t.Fatalf("key=%q, want %q", record.Key, models.SettingCloudStorage)
	}
	if record.Type != "json" {

		t.Fatalf("type=%q, want json", record.Type)
	}
	var parsed config.StorageConfig
	if err := json.Unmarshal([]byte(record.Value), &parsed); err != nil {

		t.Fatalf("record value should be json: %v", err)
	}
	if parsed.Provider != "local" {

		t.Fatalf("provider=%q, want local", parsed.Provider)
	}
}
func TestStorageStatusPayloadMasksSecrets(t *testing.T) {
	var cfg config.StorageConfig
	cfg.Provider = "aliyun"
	cfg.Aliyun.Endpoint = "oss-cn-hangzhou.aliyuncs.com"
	cfg.Aliyun.Bucket = "media-bucket"
	cfg.Aliyun.AccessKeyID = "raw-access-key-id"
	cfg.Aliyun.AccessKeySecret = "raw-access-key-secret"
	cfg.Aliyun.PublicBaseURL = "https://media.example.com"
	cfg.Aliyun.UseHTTPS = true
	payload := storageStatusPayload(cfg, "database", nil)
	raw, err := json.Marshal(payload)
	if err != nil {

		t.Fatalf("marshal payload: %v", err)
	}
	text := string(raw)
	if strings.Contains(text, "raw-access-key-id") || strings.Contains(text, "raw-access-key-secret") {

		t.Fatalf("payload leaked storage secret: %s", text)
	}
	aliyun, ok := payload["aliyun"].(gin.H)
	if !ok {

		t.Fatalf("aliyun payload type=%T", payload["aliyun"])
	}
	if aliyun["access_key_id_set"] != true || aliyun["access_key_secret_set"] != true {

		t.Fatalf("access key presence flags missing: %#v", aliyun)
	}
}
func TestPrepareCloudStorageSettingEncryptsS3Credentials(t *testing.T) {
	t.Setenv("GENERIC_IM_SETTINGS_ENCRYPTION_KEY", "handler-test-master-key")
	raw := map[string]interface{}{

		"provider": "s3",

		"s3": map[string]interface{}{

			"region": "ap-southeast-1",

			"bucket": "media-bucket",

			"access_key_id": "AKIA_HANDLER_TEST",

			"secret_access_key": "handler-secret-value",

			"public_base_url": "https://media.example.com",

			"endpoint": "",

			"use_path_style": false,
		},
	}
	prepared, err := prepareCloudStorageSettingForSave(nil, raw)
	if err != nil {

		t.Fatalf("prepareCloudStorageSettingForSave: %v", err)
	}
	encoded, err := json.Marshal(prepared)
	if err != nil {

		t.Fatalf("marshal prepared setting: %v", err)
	}
	text := string(encoded)
	if strings.Contains(text, "AKIA_HANDLER_TEST") || strings.Contains(text, "handler-secret-value") {

		t.Fatalf("prepared database value leaked plaintext AWS credentials: %s", text)
	}
	if !strings.Contains(text, "enc:v1:") {

		t.Fatalf("prepared database value is not encrypted: %s", text)
	}
}
func TestCloudStorageSettingValueMasksS3CredentialsForAdmin(t *testing.T) {
	oldConfig := config.GlobalConfig
	t.Cleanup(func() {

		config.GlobalConfig = oldConfig
	})
	cfg := &config.Config{}
	cfg.Storage.Provider = "s3"
	cfg.Storage.S3.Region = "ap-southeast-1"
	cfg.Storage.S3.Bucket = "media-bucket"
	cfg.Storage.S3.AccessKeyID = "AKIA_ADMIN_TEST"
	cfg.Storage.S3.SecretAccessKey = "admin-secret-value"
	cfg.Storage.S3.PublicBaseURL = "https://media.example.com"
	config.GlobalConfig = cfg
	value, ok := cloudStorageSettingValue(nil, false).(config.StorageConfig)
	if !ok {

		t.Fatalf("expected StorageConfig value, got %T", value)
	}
	if value.S3.AccessKeyID != "******" || value.S3.SecretAccessKey != "******" {

		t.Fatalf("admin response did not mask AWS credentials: %#v", value.S3)
	}
}
