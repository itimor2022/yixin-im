// 文件用途：实现可复用的后端业务服务和领域逻辑。
// 核心逻辑：协调数据库、缓存、队列和外部服务，集中处理事务、幂等、重试和错误传播。

package services

import (
	"crypto/aes"
	"crypto/cipher"
	"crypto/rand"
	"crypto/sha256"
	"encoding/base64"
	"fmt"
	"io"
	"os"
	"strings"
	"genericim/internal/config"
)

const (
	storageSecretPrefix       = "enc:v1:"
	storageMaskedSecret       = "******"
	storageEncryptionKeyEnv   = "GENERIC_IM_SETTINGS_ENCRYPTION_KEY"
	storageEncryptionKeyScope = "genericim-storage-settings-v1:"
) // EncryptStorageConfigSecrets encrypts AWS credentials before cloud_storage // is serialized into system_settings. The encryption master key remains on the // server and is never stored in the database.
func EncryptStorageConfigSecrets(cfg config.StorageConfig) (config.StorageConfig, error) {
	var err error
	cfg.S3.AccessKeyID, err = encryptStorageSecret(cfg.S3.AccessKeyID)
	if err != nil {

		return config.StorageConfig{}, err
	}
	cfg.S3.SecretAccessKey, err = encryptStorageSecret(cfg.S3.SecretAccessKey)
	if err != nil {

		return config.StorageConfig{}, err
	}
	return cfg, nil
} // DecryptStorageConfigSecrets is used only in backend runtime code before // constructing the AWS SDK client.
func DecryptStorageConfigSecrets(cfg config.StorageConfig) (config.StorageConfig, error) {
	var err error
	cfg.S3.AccessKeyID, err = decryptStorageSecret(cfg.S3.AccessKeyID)
	if err != nil {

		return config.StorageConfig{}, err
	}
	cfg.S3.SecretAccessKey, err = decryptStorageSecret(cfg.S3.SecretAccessKey)
	if err != nil {

		return config.StorageConfig{}, err
	}
	return cfg, nil
}
func encryptStorageSecret(value string) (string, error) {
	value = strings.TrimSpace(value)
	if value == "" || value == storageMaskedSecret || strings.HasPrefix(value, storageSecretPrefix) {

		return value, nil
	}
	block, err := storageSecretCipher()
	if err != nil {

		return "", err
	}
	gcm, err := cipher.NewGCM(block)
	if err != nil {

		return "", fmt.Errorf("初始化云存储密钥加密失败: %w", err)
	}
	nonce := make([]byte, gcm.NonceSize())
	if _, err := io.ReadFull(rand.Reader, nonce); err != nil {

		return "", fmt.Errorf("生成云存储密钥随机数失败: %w", err)
	}
	ciphertext := gcm.Seal(nil, nonce, []byte(value), nil)
	payload := append(nonce, ciphertext...)
	return storageSecretPrefix + base64.RawStdEncoding.EncodeToString(payload), nil
}
func decryptStorageSecret(value string) (string, error) {
	value = strings.TrimSpace(value)
	if value == "" || value == storageMaskedSecret || !strings.HasPrefix(value, storageSecretPrefix) {

		return value, nil
	}
	payload, err := base64.RawStdEncoding.DecodeString(strings.TrimPrefix(value, storageSecretPrefix))
	if err != nil {

		return "", fmt.Errorf("云存储密钥密文格式错误")
	}
	block, err := storageSecretCipher()
	if err != nil {

		return "", err
	}
	gcm, err := cipher.NewGCM(block)
	if err != nil {

		return "", fmt.Errorf("初始化云存储密钥解密失败: %w", err)
	}
	if len(payload) <= gcm.NonceSize() {

		return "", fmt.Errorf("云存储密钥密文长度错误")
	}
	plaintext, err := gcm.Open(nil, payload[:gcm.NonceSize()], payload[gcm.NonceSize():], nil)
	if err != nil {

		return "", fmt.Errorf("云存储密钥解密失败，请检查服务端加密主密钥")
	}
	return string(plaintext), nil
}
func storageSecretCipher() (cipher.Block, error) {
	material := strings.TrimSpace(os.Getenv(storageEncryptionKeyEnv))
	if material == "" && config.GlobalConfig != nil {

		material = strings.TrimSpace(config.GlobalConfig.JWT.Secret)
	}
	if material == "" {

		return nil, fmt.Errorf("未配置 %s，无法加密保存 AWS 密钥", storageEncryptionKeyEnv)
	}
	key := sha256.Sum256([]byte(storageEncryptionKeyScope + material))
	block, err := aes.NewCipher(key[:])
	if err != nil {

		return nil, fmt.Errorf("初始化云存储密钥加密失败: %w", err)
	}
	return block, nil
}
