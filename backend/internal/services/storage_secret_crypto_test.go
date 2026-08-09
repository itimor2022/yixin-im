// 文件用途：验证 storage_secret_crypto_test.go 对应模块的正常流程、异常处理和回归行为。
// 核心逻辑：覆盖输入校验、状态变化、错误返回、边界条件和并发幸命。

package services

import (
	"encoding/json"
	"strings"
	"testing"
	"genericim/internal/config"
)

func TestStorageS3CredentialsEncryptedForDatabaseAndDecryptedAtRuntime(t *testing.T) {
	t.Setenv(storageEncryptionKeyEnv, "unit-test-master-key")
	var cfg config.StorageConfig
	cfg.Provider = StorageProviderS3
	cfg.S3.Region = "ap-southeast-1"
	cfg.S3.Bucket = "media-bucket"
	cfg.S3.AccessKeyID = "AKIA_TEST_VALUE"
	cfg.S3.SecretAccessKey = "secret-test-value"
	cfg.S3.PublicBaseURL = "https://media.example.com"
	encrypted, err := EncryptStorageConfigSecrets(cfg)
	if err != nil {

		t.Fatalf("EncryptStorageConfigSecrets: %v", err)
	}
	if !strings.HasPrefix(encrypted.S3.AccessKeyID, storageSecretPrefix) ||

		!strings.HasPrefix(encrypted.S3.SecretAccessKey, storageSecretPrefix) {

		t.Fatalf("credentials were not encrypted: %#v", encrypted.S3)
	}
	raw, err := json.Marshal(encrypted)
	if err != nil {

		t.Fatalf("marshal encrypted config: %v", err)
	}
	if strings.Contains(string(raw), cfg.S3.AccessKeyID) ||

		strings.Contains(string(raw), cfg.S3.SecretAccessKey) {

		t.Fatalf("database JSON leaked plaintext AWS credentials: %s", raw)
	}
	runtimeCfg, ok := storageConfigFromDatabaseValue(string(raw), config.StorageConfig{})
	if !ok {

		t.Fatal("expected database config to load")
	}
	if runtimeCfg.S3.AccessKeyID != cfg.S3.AccessKeyID ||

		runtimeCfg.S3.SecretAccessKey != cfg.S3.SecretAccessKey {

		t.Fatalf("runtime credentials did not decrypt: %#v", runtimeCfg.S3)
	}
}
func TestStorageS3CredentialDecryptionRejectsWrongMasterKey(t *testing.T) {
	t.Setenv(storageEncryptionKeyEnv, "first-master-key")
	var cfg config.StorageConfig
	cfg.S3.AccessKeyID = "AKIA_TEST_VALUE"
	cfg.S3.SecretAccessKey = "secret-test-value"
	encrypted, err := EncryptStorageConfigSecrets(cfg)
	if err != nil {

		t.Fatalf("EncryptStorageConfigSecrets: %v", err)
	}
	t.Setenv(storageEncryptionKeyEnv, "different-master-key")
	if _, err := DecryptStorageConfigSecrets(encrypted); err == nil {

		t.Fatal("expected decrypting with a different master key to fail")
	}
}
func TestMaskS3StorageCredentialsDoesNotExposeValues(t *testing.T) {
	var cfg config.StorageConfig
	cfg.S3.AccessKeyID = "AKIA_TEST_VALUE"
	cfg.S3.SecretAccessKey = "secret-test-value"
	masked := MaskS3StorageCredentials(cfg)
	if masked.S3.AccessKeyID != storageMaskedSecret ||

		masked.S3.SecretAccessKey != storageMaskedSecret {

		t.Fatalf("AWS credentials were not masked: %#v", masked.S3)
	}
}
