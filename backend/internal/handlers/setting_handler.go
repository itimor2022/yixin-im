// 文件用途：实现后端 HTTP 接口的请求处理和统一响应。
// 核心逻辑：绑定参数，校验身份与权限，调用业务服务并持久化关键状态。

package handlers

import (
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"github.com/gin-gonic/gin"
	"gorm.io/gorm" // sensitiveSettingKeys 敏感配置项，对 demo_admin 隐藏
	"io"
	"log"
	"net/http"
	"net/url"
	"os"
	"path/filepath"
	"regexp"
	"strconv"
	"strings"
	"time"
	"unicode/utf8"
	"genericim/internal/config"
	"genericim/internal/middleware"
	"genericim/internal/models"
	"genericim/internal/services"
	"genericim/pkg/response"
)

var sensitiveSettingKeys = map[string]bool{
	models.SettingAgoraAppID:             true,
	models.SettingAgoraAppCertificate:    true,
	models.SettingLiveKitAPIKey:          true,
	models.SettingLiveKitAPISecret:       true,
	models.SettingAPNsKeyID:              true,
	models.SettingAPNsTeamID:             true,
	models.SettingAPNsAuthKey:            true,
	models.SettingAPNsBundleID:           true,
	models.SettingFCMProjectID:           true,
	models.SettingFCMServiceAccountJSON:  true,
	models.SettingHMSAppID:               true,
	models.SettingHMSAppSecret:           true,
	models.SettingJPushAppKey:            true,
	models.SettingJPushMasterSecret:      true,
	models.SettingXiaomiPackageName:      true,
	models.SettingXiaomiAppSecret:        true,
	models.SettingOppoAppKey:             true,
	models.SettingOppoAppSecret:          true,
	models.SettingWebPushVAPIDPrivateKey: true,
	models.SettingPaymentGateway:         true,
	models.SettingSmsGateway:             true,
	models.SettingVoiceTranscribeToken:   true,
	models.SettingOpenAIAPIKey:           true,
	models.SettingDeepSeekAPIKey:         true} // PushConfigReloader 推送配置重载接口
type PushConfigReloader interface {
	ReloadConfig()
}
type SettingsWebSocketHub interface {
	SendToAll(data interface{})
}
type SettingHandler struct {
	db          *gorm.DB
	pushService PushConfigReloader
	hub         SettingsWebSocketHub
	smsSvc      *services.SMSService
	uploadDir   string
	baseURL     string
}

func defaultServiceWelcomeMessage() string {
	return "您好，我是您的官方客服。"
}
func isSystemSettingTrue(v string) bool {
	s := strings.ToLower(strings.TrimSpace(v))
	return s == "true" || s == "1"
}
func isSystemSettingFalse(v string) bool {
	s := strings.ToLower(strings.TrimSpace(v))
	return s == "false" || s == "0"
}
func normalizeMessageCryptoMode(v string) string {
	switch strings.ToLower(strings.TrimSpace(v)) {
	case models.MessageCryptoModeCompatible:

		return models.MessageCryptoModeCompatible
	case models.MessageCryptoModeStrict:

		return models.MessageCryptoModeStrict
	default:

		return models.MessageCryptoModePlain
	}
}
func voiceTranscriptionConfigured(settingMap map[string]string) bool {
	provider := strings.ToLower(strings.TrimSpace(settingMap[models.SettingVoiceTranscribeProvider]))
	if provider == "openai" {

		return strings.TrimSpace(settingMap[models.SettingOpenAIAPIKey]) != "" ||

			strings.TrimSpace(os.Getenv("OPENAI_API_KEY")) != ""
	}
	if strings.TrimSpace(settingMap[models.SettingVoiceTranscribeURL]) != "" ||

		strings.TrimSpace(os.Getenv("VOICE_TRANSCRIBE_URL")) != "" {

		return true
	}
	return provider == "" && (strings.TrimSpace(settingMap[models.SettingOpenAIAPIKey]) != "" ||

		strings.TrimSpace(os.Getenv("OPENAI_API_KEY")) != "")
}
func isValidMessageCryptoMode(v string) bool {
	switch strings.ToLower(strings.TrimSpace(v)) {
	case models.MessageCryptoModePlain, models.MessageCryptoModeCompatible, models.MessageCryptoModeStrict:

		return true
	default:

		return false
	}
}
func validateOfficialWelcomeMessage(msg string) bool {
	return utf8.RuneCountInString(msg) <= 500
}
func validateOfficialRemark(remark string) bool {
	return utf8.RuneCountInString(remark) <= 200
}

var officialInviteCodePattern = regexp.MustCompile(`^[A-Za-z0-9]{6,12}$`)
var pushCategoryPattern = regexp.MustCompile(`^[A-Za-z0-9_:-]{1,64}$`)
var pushQuietHourPattern = regexp.MustCompile(`^([01]\d|2[0-3]):[0-5]\d$`)

func validateOfficialInviteCode(code string) bool {
	return officialInviteCodePattern.MatchString(code)
}

type fcmServiceAccountPayload struct {
	Type        string `json:"type"`
	ProjectID   string `json:"project_id"`
	ClientEmail string `json:"client_email"`
	PrivateKey  string `json:"private_key"`
}

func validateFCMPushConfig(projectID, serviceJSON string) error {
	projectID = strings.TrimSpace(projectID)
	serviceJSON = strings.TrimSpace(serviceJSON)
	if projectID == "" || serviceJSON == "" {

		return fmt.Errorf("启用 FCM 推送时，Project ID 与 Service Account JSON 不能为空")
	}
	// 常见误填：把 mobilesdk_app_id（形如 1:123456:android:xxxx）填到 Project ID。
	lowerProjectID := strings.ToLower(projectID)
	if strings.HasPrefix(projectID, "1:") || strings.Contains(lowerProjectID, ":android:") || strings.Contains(lowerProjectID, ":ios:") {

		return fmt.Errorf("FCM Project ID 填写错误，请填写 Firebase Project ID（示例：my-project-id），不要填写 mobilesdk_app_id")
	}
	var parsed fcmServiceAccountPayload
	if err := json.Unmarshal([]byte(serviceJSON), &parsed); err != nil {

		return fmt.Errorf("FCM Service Account JSON 格式错误")
	}
	serviceProjectID := strings.TrimSpace(parsed.ProjectID)
	if serviceProjectID == "" {

		return fmt.Errorf("FCM Service Account JSON 缺少 project_id")
	}
	if strings.TrimSpace(parsed.ClientEmail) == "" || strings.TrimSpace(parsed.PrivateKey) == "" {

		return fmt.Errorf("FCM Service Account JSON 缺少 client_email 或 private_key")
	}
	if projectID != serviceProjectID {

		return fmt.Errorf("FCM Project ID 与 Service Account JSON 的 project_id 不一致")
	}
	return nil
}
func validateGeneralRemark(remark string, maxLen int) bool {
	return utf8.RuneCountInString(remark) <= maxLen
}
func NewSettingHandler(db *gorm.DB, pushService ...*services.PushService) *SettingHandler {
	h := &SettingHandler{db: db}
	if len(pushService) > 0 && pushService[0] != nil {

		h.pushService = pushService[0]
	}
	return h
}
func (h *SettingHandler) SetSMSService(smsSvc *services.SMSService) {
	h.smsSvc = smsSvc
}
func (h *SettingHandler) SetWebSocketHub(hub SettingsWebSocketHub) {
	h.hub = hub
}
func (h *SettingHandler) SetUploadRuntime(uploadDir, baseURL string) {
	h.uploadDir = uploadDir
	h.baseURL = strings.TrimRight(strings.TrimSpace(baseURL), "/")
}

type chatAttachmentMenuSetting struct {
	Enabled   bool `json:"enabled"`
	Album     bool `json:"album"`
	Camera    bool `json:"camera"`
	Call      bool `json:"call"`
	Location  bool `json:"location"`
	RedPacket bool `json:"red_packet"`
	Transfer  bool `json:"transfer"`
	Favorite  bool `json:"favorite"`
	File      bool `json:"file"`
}

func defaultChatAttachmentMenuSetting() chatAttachmentMenuSetting {
	return chatAttachmentMenuSetting{

		Enabled: true,

		Album: true,

		Camera: true,

		Call: true,

		Location: true,

		RedPacket: true,

		Transfer: true,

		Favorite: true,

		File: true,
	}
}
func chatAttachmentMenuSettingValue(raw interface{}) chatAttachmentMenuSetting {
	result := defaultChatAttachmentMenuSetting()
	if raw == nil {

		return result
	}
	var data []byte
	switch value := raw.(type) {
	case string:

		data = []byte(strings.TrimSpace(value))
	default:

		encoded, err := json.Marshal(value)

		if err != nil {

			return result

		}
		data = encoded
	}
	if len(data) == 0 {

		return result
	}
	var values map[string]interface{}
	if err := json.Unmarshal(data, &values); err != nil {

		return result
	}
	apply := func(key string, target *bool) {

		if value, exists := values[key]; exists {

			if enabled, ok := value.(bool); ok {

				*target = enabled

			}

		}
	}
	apply("enabled", &result.Enabled)
	apply("album", &result.Album)
	apply("camera", &result.Camera)
	apply("call", &result.Call)
	apply("location", &result.Location)
	apply("red_packet", &result.RedPacket)
	apply("transfer", &result.Transfer)
	apply("favorite", &result.Favorite)
	apply("file", &result.File)
	return result
}
func validateChatAttachmentMenuSetting(raw interface{}) error {
	values, ok := raw.(map[string]interface{})
	if !ok {

		return fmt.Errorf("聊天扩展菜单配置必须是对象")
	}
	allowed := map[string]struct{}{

		"enabled": {}, "album": {}, "camera": {}, "call": {},

		"location": {}, "red_packet": {}, "transfer": {},

		"favorite": {}, "file": {},
	}
	for key, value := range values {

		if _, exists := allowed[key]; !exists {

			return fmt.Errorf("聊天扩展菜单包含不支持的字段：%s", key)

		}

		if _, ok := value.(bool); !ok {

			return fmt.Errorf("聊天扩展菜单字段 %s 必须是布尔值", key)

		}
	}
	return nil
}

type storageTestUploadResult struct {
	OK         bool   `json:"ok"`
	Provider   string `json:"provider"`
	Source     string `json:"source"`
	ObjectKey  string `json:"object_key"`
	URL        string `json:"url"`
	HTTPStatus int    `json:"http_status"`
	DurationMS int64  `json:"duration_ms"`
	Cleaned    bool   `json:"cleaned"`
	Error      string `json:"error,omitempty"`
}

func storageConfigHasDatabaseValue(db *gorm.DB) bool {
	if db == nil {

		return false
	}
	var row models.SystemSetting
	if err := db.Where("`key` = ?", models.SettingCloudStorage).First(&row).Error; err != nil {

		return false
	}
	raw := strings.TrimSpace(row.Value)
	if raw == "" || raw == "{}" {

		return false
	}
	var cfg config.StorageConfig
	return json.Unmarshal([]byte(raw), &cfg) == nil
}
func storageHasEnvOverride() bool {
	for _, key := range []string{

		"GENERIC_IM_STORAGE_PROVIDER",

		"GENERIC_IM_STORAGE_LOCAL_BASE_URL",

		"GENERIC_IM_STORAGE_ALIYUN_ENDPOINT",

		"GENERIC_IM_STORAGE_ALIYUN_BUCKET",

		"GENERIC_IM_STORAGE_ALIYUN_ACCESS_KEY_ID",

		"GENERIC_IM_STORAGE_ALIYUN_ACCESS_KEY_SECRET",

		"GENERIC_IM_STORAGE_ALIYUN_PUBLIC_BASE_URL",

		"GENERIC_IM_STORAGE_ALIYUN_USE_HTTPS",

		"GENERIC_IM_STORAGE_QINIU_UPLOAD_URL",

		"GENERIC_IM_STORAGE_QINIU_BUCKET",

		"GENERIC_IM_STORAGE_QINIU_ACCESS_KEY",

		"GENERIC_IM_STORAGE_QINIU_SECRET_KEY",

		"GENERIC_IM_STORAGE_QINIU_PUBLIC_BASE_URL",

		"GENERIC_IM_STORAGE_QINIU_USE_HTTPS",

		"GENERIC_IM_STORAGE_S3_REGION",

		"GENERIC_IM_STORAGE_S3_BUCKET",

		"GENERIC_IM_STORAGE_S3_ACCESS_KEY_ID",

		"GENERIC_IM_STORAGE_S3_SECRET_ACCESS_KEY",

		"GENERIC_IM_STORAGE_S3_PUBLIC_BASE_URL",

		"GENERIC_IM_STORAGE_S3_ENDPOINT",

		"GENERIC_IM_STORAGE_S3_USE_PATH_STYLE",
	} {

		if _, ok := os.LookupEnv(key); ok {

			return true

		}
	}
	return false
}
func storageConfigHasYAMLValue(cfg config.StorageConfig) bool {
	return strings.TrimSpace(cfg.Provider) != "" ||

		strings.TrimSpace(cfg.Local.BaseURL) != "" ||

		strings.TrimSpace(cfg.Aliyun.Endpoint) != "" ||

		strings.TrimSpace(cfg.Aliyun.Bucket) != "" ||

		strings.TrimSpace(cfg.Aliyun.AccessKeyID) != "" ||

		strings.TrimSpace(cfg.Aliyun.AccessKeySecret) != "" ||

		strings.TrimSpace(cfg.Aliyun.PublicBaseURL) != "" ||

		strings.TrimSpace(cfg.Qiniu.UploadURL) != "" ||

		strings.TrimSpace(cfg.Qiniu.Bucket) != "" ||

		strings.TrimSpace(cfg.Qiniu.AccessKey) != "" ||

		strings.TrimSpace(cfg.Qiniu.SecretKey) != "" ||

		strings.TrimSpace(cfg.Qiniu.PublicBaseURL) != "" ||

		strings.TrimSpace(cfg.S3.Region) != "" ||

		strings.TrimSpace(cfg.S3.Bucket) != "" ||

		strings.TrimSpace(cfg.S3.AccessKeyID) != "" ||

		strings.TrimSpace(cfg.S3.SecretAccessKey) != "" ||

		strings.TrimSpace(cfg.S3.PublicBaseURL) != "" ||

		strings.TrimSpace(cfg.S3.Endpoint) != ""
}
func detectStorageConfigSource(db *gorm.DB) string {
	if storageConfigHasDatabaseValue(db) {

		return "database"
	}
	if storageHasEnvOverride() {

		return "env"
	}
	if config.GlobalConfig != nil && storageConfigHasYAMLValue(config.GlobalConfig.Storage) {

		return "yaml"
	}
	return "default"
}
func storagePublicBaseURL(cfg config.StorageConfig) string {
	switch services.NormalizeStorageProvider(cfg.Provider) {
	case services.StorageProviderAliyun:

		return strings.TrimRight(strings.TrimSpace(cfg.Aliyun.PublicBaseURL), "/")
	case services.StorageProviderQiniu:

		return strings.TrimRight(strings.TrimSpace(cfg.Qiniu.PublicBaseURL), "/")
	case services.StorageProviderS3:

		return strings.TrimRight(strings.TrimSpace(cfg.S3.PublicBaseURL), "/")
	default:

		return strings.TrimRight(strings.TrimSpace(cfg.Local.BaseURL), "/")
	}
}
func storageStatusPayload(cfg config.StorageConfig, source string, validationErr error) gin.H {
	provider := services.NormalizeStorageProvider(cfg.Provider)
	payload := gin.H{

		"provider": provider,

		"source": source,

		"valid": validationErr == nil,

		"masked": true,

		"public_base_url": storagePublicBaseURL(cfg),

		"local_base_url": strings.TrimRight(strings.TrimSpace(cfg.Local.BaseURL), "/"),

		"upload_stages": services.GetUploadStageMetrics(),

		"aliyun": gin.H{

			"endpoint": strings.TrimSpace(cfg.Aliyun.Endpoint),

			"bucket": strings.TrimSpace(cfg.Aliyun.Bucket),

			"public_base_url": strings.TrimRight(strings.TrimSpace(cfg.Aliyun.PublicBaseURL), "/"),

			"use_https": cfg.Aliyun.UseHTTPS,

			"access_key_id_set": strings.TrimSpace(cfg.Aliyun.AccessKeyID) != "",

			"access_key_secret_set": strings.TrimSpace(cfg.Aliyun.AccessKeySecret) != "",
		},

		"qiniu": gin.H{

			"upload_url": strings.TrimRight(strings.TrimSpace(cfg.Qiniu.UploadURL), "/"),

			"bucket": strings.TrimSpace(cfg.Qiniu.Bucket),

			"public_base_url": strings.TrimRight(strings.TrimSpace(cfg.Qiniu.PublicBaseURL), "/"),

			"use_https": cfg.Qiniu.UseHTTPS,

			"access_key_set": strings.TrimSpace(cfg.Qiniu.AccessKey) != "",

			"secret_key_set": strings.TrimSpace(cfg.Qiniu.SecretKey) != "",
		},

		"s3": gin.H{

			"region": strings.TrimSpace(cfg.S3.Region),

			"bucket": strings.TrimSpace(cfg.S3.Bucket),

			"public_base_url": strings.TrimRight(strings.TrimSpace(cfg.S3.PublicBaseURL), "/"),

			"endpoint": strings.TrimRight(strings.TrimSpace(cfg.S3.Endpoint), "/"),

			"use_path_style": cfg.S3.UsePathStyle,

			"access_key_id_set": strings.TrimSpace(cfg.S3.AccessKeyID) != "",

			"secret_access_key_set": strings.TrimSpace(cfg.S3.SecretAccessKey) != "",

			"credentials_source": storageS3CredentialsSource(cfg, source),
		},
	}
	switch provider {
	case services.StorageProviderAliyun:

		payload["endpoint"] = strings.TrimSpace(cfg.Aliyun.Endpoint)

		payload["bucket"] = strings.TrimSpace(cfg.Aliyun.Bucket)
	case services.StorageProviderQiniu:

		payload["endpoint"] = strings.TrimRight(strings.TrimSpace(cfg.Qiniu.UploadURL), "/")

		payload["bucket"] = strings.TrimSpace(cfg.Qiniu.Bucket)
	case services.StorageProviderS3:

		payload["endpoint"] = strings.TrimRight(strings.TrimSpace(cfg.S3.Endpoint), "/")

		payload["bucket"] = strings.TrimSpace(cfg.S3.Bucket)
	default:

		payload["endpoint"] = ""

		payload["bucket"] = ""
	}
	if validationErr != nil {

		payload["error"] = validationErr.Error()
	}
	return payload
}
func storageS3CredentialsSource(cfg config.StorageConfig, source string) string {
	if strings.TrimSpace(cfg.S3.AccessKeyID) == "" || strings.TrimSpace(cfg.S3.SecretAccessKey) == "" {

		return "not_configured"
	}
	if source == "database" {

		return "database_encrypted"
	}
	return "server_fallback"
}
func (h *SettingHandler) uploadStorageHealthObject(
	ctx context.Context,
	cfg config.StorageConfig,
	objectKey string,
	payload []byte,
	contentType string) (string, error) {
	provider := services.NormalizeStorageProvider(cfg.Provider)
	if provider != services.StorageProviderLocal {

		return services.UploadObject(ctx, cfg, objectKey, bytes.NewReader(payload), int64(len(payload)), contentType)
	}
	uploadDir := strings.TrimSpace(h.uploadDir)
	if uploadDir == "" {

		uploadDir = "./uploads"
	}
	relativePath := strings.TrimPrefix(objectKey, "uploads/")
	savePath, err := safeLocalUploadPath(uploadDir, relativePath)
	if err != nil {

		return "", err
	}
	if err := os.MkdirAll(filepath.Dir(savePath), 0755); err != nil {

		return "", err
	}
	if err := os.Chmod(filepath.Dir(savePath), 0755); err != nil {

		return "", err
	}
	if err := os.WriteFile(savePath, payload, 0644); err != nil {

		return "", err
	}
	baseURL := strings.TrimRight(strings.TrimSpace(cfg.Local.BaseURL), "/")
	if baseURL == "" {

		baseURL = h.baseURL
	}
	return services.PublicObjectURL(baseURL, objectKey, true), nil
}
func (h *SettingHandler) deleteStorageHealthObject(ctx context.Context, cfg config.StorageConfig, objectKey string) error {
	provider := services.NormalizeStorageProvider(cfg.Provider)
	if provider != services.StorageProviderLocal {

		return services.DeleteObject(ctx, cfg, objectKey)
	}
	uploadDir := strings.TrimSpace(h.uploadDir)
	if uploadDir == "" {

		uploadDir = "./uploads"
	}
	relativePath := strings.TrimPrefix(objectKey, "uploads/")
	savePath, err := safeLocalUploadPath(uploadDir, relativePath)
	if err != nil {

		return err
	}
	if err := os.Remove(savePath); err != nil && !errors.Is(err, os.ErrNotExist) {

		return err
	}
	return nil
}
func verifyStoragePublicURL(ctx context.Context, rawURL string) (int, error) {
	parsed, err := url.Parse(strings.TrimSpace(rawURL))
	if err != nil || parsed == nil || parsed.Host == "" || (parsed.Scheme != "http" && parsed.Scheme != "https") {

		return 0, fmt.Errorf("测试 URL 不是完整的 http/https 地址")
	}
	client := &http.Client{Timeout: 8 * time.Second}
	methods := []string{http.MethodHead, http.MethodGet}
	var lastStatus int
	var lastErr error
	for _, method := range methods {

		req, err := http.NewRequestWithContext(ctx, method, rawURL, nil)

		if err != nil {

			return 0, err

		}
		resp, err := client.Do(req)

		if err != nil {

			lastErr = err

			continue

		}
		lastStatus = resp.StatusCode

		_, _ = io.Copy(io.Discard, io.LimitReader(resp.Body, 4096))
		_ = resp.Body.Close()

		if resp.StatusCode >= 200 && resp.StatusCode < 300 {

			return resp.StatusCode, nil

		}
		lastErr = fmt.Errorf("公开 URL 返回状态码 %d", resp.StatusCode)

		if method == http.MethodHead {

			continue

		}
	}
	if lastErr != nil {

		return lastStatus, lastErr
	}
	return lastStatus, fmt.Errorf("公开 URL 验证失败")
}
func storageURLForVerification(c *gin.Context, rawURL string) string {
	rawURL = strings.TrimSpace(rawURL)
	if !strings.HasPrefix(rawURL, "/") || c == nil || c.Request == nil {

		return rawURL
	}
	scheme := strings.TrimSpace(c.GetHeader("X-Forwarded-Proto"))
	if scheme == "" {

		if c.Request.TLS != nil {

			scheme = "https"

		} else {

			scheme = "http"

		}
	}
	host := strings.TrimSpace(c.GetHeader("X-Forwarded-Host"))
	if host == "" {

		host = c.Request.Host
	}
	if host == "" {

		return rawURL
	}
	return scheme + "://" + host + rawURL
} // ==================== 系统设置 ====================  // GetStorageStatus returns the effective runtime storage config without secrets.
func (h *SettingHandler) GetStorageStatus(c *gin.Context) {
	cfg := runtimeCloudStorageConfig(h.db)
	source := detectStorageConfigSource(h.db)
	validationErr := services.ValidateStorageConfig(cfg)
	response.Success(c, storageStatusPayload(cfg, source, validationErr))
} // TestStorageUpload writes a small object through the current storage backend and verifies the public URL.
func (h *SettingHandler) TestStorageUpload(c *gin.Context) {
	startedAt := time.Now()
	cfg := runtimeCloudStorageConfig(h.db)
	source := detectStorageConfigSource(h.db)
	provider := services.NormalizeStorageProvider(cfg.Provider)
	result := storageTestUploadResult{

		Provider: provider,

		Source: source,
	}
	var payloadSize int64
	defer func() {

		result.DurationMS = time.Since(startedAt).Milliseconds()
		var eventErr error

		if result.Error != "" {

			eventErr = fmt.Errorf("%s", result.Error)

		}
		if eventErr != nil {

			log.Printf(
				"[StorageHealth] test failed provider=%s source=%s objectKey=%s httpStatus=%d durationMs=%d err=%v",
				provider,
				source,
				result.ObjectKey,
				result.HTTPStatus,
				result.DurationMS,
				eventErr,
			)

		} else {

			log.Printf(
				"[StorageHealth] test passed provider=%s source=%s objectKey=%s httpStatus=%d durationMs=%d cleaned=%t",
				provider,
				source,
				result.ObjectKey,
				result.HTTPStatus,
				result.DurationMS,
				result.Cleaned,
			)

		}

		recordUploadOutcome(h.db, c, uploadLogParams{

			MediaType: "storage_health",

			Provider: provider,

			ObjectKey: result.ObjectKey,

			URL: result.URL,

			ContentType: "text/plain; charset=utf-8",

			Size: payloadSize,

			Success: result.OK,

			Err: eventErr,

			StartedAt: startedAt,
		})

		recordAdminSecurityEvent(c, h.db, adminSecurityEventInput{

			EventType: "storage",

			Action: "test_upload",

			Target: provider,

			Success: result.OK,

			Err: eventErr,

			Metadata: map[string]interface{}{

				"source": source,

				"provider": provider,

				"object_key": result.ObjectKey,

				"http_status": result.HTTPStatus,

				"duration_ms": result.DurationMS,

				"public_url_ok": result.OK,
			},
		})

		response.Success(c, result)
	}()
	if err := services.ValidateStorageConfig(cfg); err != nil {

		result.Error = err.Error()

		return
	}
	now := time.Now()
	objectKey := buildUploadObjectKey(

		"health",

		now.Format("2006/01/02"),

		fmt.Sprintf("storage_health_%d.txt", now.UnixMilli()),
	)
	result.ObjectKey = objectKey
	payload := []byte(fmt.Sprintf("genericim storage health check\nprovider=%s\nsource=%s\ntime=%s\n",

		provider,

		source,

		now.UTC().Format(time.RFC3339),
	))
	payloadSize = int64(len(payload))
	url, err := h.uploadStorageHealthObject(

		c.Request.Context(),

		cfg,

		objectKey,

		payload,

		"text/plain; charset=utf-8",
	)
	if err != nil {

		result.Error = err.Error()

		return
	}
	cleanupNeeded := true
	defer func() {

		if !cleanupNeeded {

			return

		}
		cleanupCtx, cancel := context.WithTimeout(context.Background(), 15*time.Second)

		defer cancel()

		if cleanupErr := h.deleteStorageHealthObject(cleanupCtx, cfg, objectKey); cleanupErr != nil {

			log.Printf("[StorageHealth] cleanup failed provider=%s objectKey=%s err=%v", provider, objectKey, cleanupErr)

		}
	}()
	result.URL = storageURLForVerification(c, url)
	status, err := verifyStoragePublicURL(c.Request.Context(), result.URL)
	result.HTTPStatus = status
	if err != nil {

		result.Error = err.Error()

		return
	}
	cleanupCtx, cancel := context.WithTimeout(c.Request.Context(), 15*time.Second)
	defer cancel()
	if err := h.deleteStorageHealthObject(cleanupCtx, cfg, objectKey); err != nil {

		result.Error = fmt.Sprintf("测试对象删除失败: %v", err)

		return
	}
	cleanupNeeded = false
	result.Cleaned = true
	result.OK = true
} // GetAllSettings 获取所有系统设置
func (h *SettingHandler) GetAllSettings(c *gin.Context) {
	var settings []models.SystemSetting
	if err := h.db.Find(&settings).Error; err != nil {

		response.Error(c, http.StatusInternalServerError, "获取设置失败")

		return
	}
	// 检查是否是演示管理员
	adminRole := middleware.GetAdminRole(c)
	isDemoAdmin := adminRole == "demo_admin"
	// 转换为map格式
	// 数据库保存字符串值和类型标签，管理端响应在这里恢复为 bool/int/json 等可编辑类型。
	result := make(map[string]interface{})
	for _, s := range settings {

		// 演示管理员隐藏敏感配置

		if isDemoAdmin && s.Key == models.SettingCloudStorage {

			result[s.Key] = services.MaskStorageConfigForDemo(s.Value)

			continue

		}

		if isDemoAdmin && sensitiveSettingKeys[s.Key] {

			// 返回占位符，让演示管理员知道有这个配置但看不到值

			result[s.Key] = "******"

			continue

		}

		switch s.Type {

		case "bool":

			result[s.Key] = s.Value == "true" || s.Value == "1"

		case "int":

			if v, err := strconv.Atoi(s.Value); err == nil {

				result[s.Key] = v

			} else {

				result[s.Key] = 0

			}

		case "json":
			var jsonVal interface{}

			if err := json.Unmarshal([]byte(s.Value), &jsonVal); err == nil {

				result[s.Key] = jsonVal

			} else {

				result[s.Key] = s.Value

			}

		default:

			result[s.Key] = s.Value

		}
	}
	// 添加角色信息，前端可以根据这个判断是否显示编辑按钮
	result["_admin_role"] = adminRole
	result[models.SettingCloudStorage] = cloudStorageSettingValue(h.db, isDemoAdmin)
	if _, exists := result[models.SettingClientBootstrap]; !exists {

		result[models.SettingClientBootstrap] = clientBootstrapSettingValue()
	}
	directUploadConfig := services.LoadChatImageDirectUploadConfig(h.db)
	if _, exists := result[models.SettingChatImageDirectUploadEnabled]; !exists {

		result[models.SettingChatImageDirectUploadEnabled] = directUploadConfig.Enabled
	}
	if _, exists := result[models.SettingChatImageDirectUploadPlatforms]; !exists {

		result[models.SettingChatImageDirectUploadPlatforms] = directUploadConfig.Platforms
	}
	if _, exists := result[models.SettingChatImageDirectUploadRolloutPercent]; !exists {

		result[models.SettingChatImageDirectUploadRolloutPercent] = directUploadConfig.RolloutPercent
	}
	if _, exists := result[models.SettingChatImageDirectUploadMaxConcurrency]; !exists {

		result[models.SettingChatImageDirectUploadMaxConcurrency] = directUploadConfig.MaxConcurrency
	}
	if _, exists := result[models.SettingRegisterBaseURL]; !exists {

		result[models.SettingRegisterBaseURL] = resolveRegisterBaseURL(h.db)
	}
	if _, exists := result[models.SettingMessageCryptoMode]; !exists {

		result[models.SettingMessageCryptoMode] = models.MessageCryptoModePlain
	}
	if _, exists := result[models.SettingBurnAfterReadEnabled]; !exists {

		result[models.SettingBurnAfterReadEnabled] = true
	}
	if raw, exists := result[models.SettingChatAttachmentMenu]; exists {

		result[models.SettingChatAttachmentMenu] = chatAttachmentMenuSettingValue(raw)
	} else {

		result[models.SettingChatAttachmentMenu] = defaultChatAttachmentMenuSetting()
	}
	if _, exists := result[models.SettingForceKeepAliveEnabled]; !exists {

		result[models.SettingForceKeepAliveEnabled] = false
	}
	if raw, exists := result[models.SettingFriendAddMode]; exists {

		result[models.SettingFriendAddMode] = normalizeFriendAddMode(normalizeSettingInputValue(raw))
	} else {

		result[models.SettingFriendAddMode] = models.FriendAddModeApproval
	}
	if _, exists := result[models.SettingAllowQuickRegister]; !exists {

		result[models.SettingAllowQuickRegister] = false
	}
	if raw, exists := result[models.SettingIOSCompliance]; exists {

		result[models.SettingIOSCompliance] = normalizeIOSComplianceConfig(raw)
	} else {

		result[models.SettingIOSCompliance] = defaultIOSComplianceConfig()
	}
	if _, exists := result[models.SettingQuickRegisterDeviceLimit]; !exists {

		result[models.SettingQuickRegisterDeviceLimit] = 1
	}
	if _, exists := result[models.SettingQuickRegisterIPLimit]; !exists {

		result[models.SettingQuickRegisterIPLimit] = 5
	}
	if _, exists := result[models.SettingRTCProvider]; !exists {

		result[models.SettingRTCProvider] = models.RTCProviderAgora
	}
	if _, exists := result[models.SettingLiveKitEnabled]; !exists {

		result[models.SettingLiveKitEnabled] = false
	}
	if _, exists := result[models.SettingLiveKitTokenExpire]; !exists {

		result[models.SettingLiveKitTokenExpire] = 3600
	}
	if _, exists := result[models.SettingDeepSeekBaseURL]; !exists {

		result[models.SettingDeepSeekBaseURL] = "https://api.deepseek.com"
	}
	if _, exists := result[models.SettingDeepSeekModel]; !exists {

		result[models.SettingDeepSeekModel] = "deepseek-v4-flash"
	}
	if _, exists := result[models.SettingDeepSeekAPIKey]; !exists {

		result[models.SettingDeepSeekAPIKey] = ""
	}
	if _, exists := result[models.SettingJPushEnabled]; !exists {

		result[models.SettingJPushEnabled] = false
	}
	if _, exists := result[models.SettingJPushAppKey]; !exists {

		result[models.SettingJPushAppKey] = ""
	}
	if _, exists := result[models.SettingJPushMasterSecret]; !exists {

		result[models.SettingJPushMasterSecret] = ""
	}
	if _, exists := result[models.SettingPushDefaultTitle]; !exists {

		result[models.SettingPushDefaultTitle] = "通用IM"
	}
	if _, exists := result[models.SettingPushChatEnabled]; !exists {

		result[models.SettingPushChatEnabled] = true
	}
	if _, exists := result[models.SettingPushFriendEnabled]; !exists {

		result[models.SettingPushFriendEnabled] = true
	}
	if _, exists := result[models.SettingPushSystemEnabled]; !exists {

		result[models.SettingPushSystemEnabled] = true
	}
	if _, exists := result[models.SettingPushCategoryChat]; !exists {

		result[models.SettingPushCategoryChat] = "chat_message"
	}
	if _, exists := result[models.SettingPushCategoryService]; !exists {

		result[models.SettingPushCategoryService] = "service_notice"
	}
	if _, exists := result[models.SettingPushCategoryMarketing]; !exists {

		result[models.SettingPushCategoryMarketing] = "marketing"
	}
	if _, exists := result[models.SettingPushPrimaryProvider]; !exists {

		result[models.SettingPushPrimaryProvider] = "jpush"
	}
	if _, exists := result[models.SettingPushFallbackProvider]; !exists {

		result[models.SettingPushFallbackProvider] = "none"
	}
	if _, exists := result[models.SettingPushRateLimitPerMinute]; !exists {

		result[models.SettingPushRateLimitPerMinute] = 0
	}
	if _, exists := result[models.SettingPushMarketingDailyLimit]; !exists {

		result[models.SettingPushMarketingDailyLimit] = 0
	}
	if _, exists := result[models.SettingPushQuietHoursEnabled]; !exists {

		result[models.SettingPushQuietHoursEnabled] = false
	}
	if _, exists := result[models.SettingPushQuietHoursStart]; !exists {

		result[models.SettingPushQuietHoursStart] = "22:00"
	}
	if _, exists := result[models.SettingPushQuietHoursEnd]; !exists {

		result[models.SettingPushQuietHoursEnd] = "08:00"
	}
	response.Success(c, result)
} // UpdateSettings 批量更新系统设置
func (h *SettingHandler) UpdateSettings(c *gin.Context) {
	// 检查是否是演示管理员 - 禁止编辑
	adminRole := middleware.GetAdminRole(c)
	if adminRole == "demo_admin" {

		response.Forbidden(c, "演示账号无法修改设置")

		return
	}
	var req map[string]interface{}
	if err := c.ShouldBindJSON(&req); err != nil {

		response.Error(c, http.StatusBadRequest, "参数错误")

		return
	}
	if raw, exists := req[models.SettingCloudStorage]; exists {

		prepared, err := prepareCloudStorageSettingForSave(h.db, raw)

		if err != nil {

			response.Error(c, http.StatusBadRequest, err.Error())

			return

		}

		req[models.SettingCloudStorage] = prepared
	}
	// 持久化前先校验完整批次，避免处理到中途才发现某个键或组合配置非法。
	if err := h.validateSystemSettingsForUpdate(req); err != nil {

		response.Error(c, http.StatusBadRequest, err.Error())

		return
	}
	hasPushConfigChange := false
	for key := range req {

		if isPushSetting(key) {

			hasPushConfigChange = true

			break

		}
	}
	if hasPushConfigChange {

		if err := h.validatePushSettingsForUpdate(req); err != nil {

			response.Error(c, http.StatusBadRequest, err.Error())

			return

		}
	}
	for key, value := range req {

		valueStr := ""

		valueType := "string"

		switch v := value.(type) {

		case bool:

			valueType = "bool"

			if v {

				valueStr = "true"

			} else {

				valueStr = "false"

			}

		case float64:

			valueType = "int"

			valueStr = strconv.Itoa(int(v))

		case string:

			valueStr = v

		default:

			// JSON类型

			valueType = "json"

			if jsonBytes, err := json.Marshal(v); err == nil {

				valueStr = string(jsonBytes)

			}

		}

		if key == models.SettingMessageCryptoMode {

			valueType = "string"

			valueStr = normalizeMessageCryptoMode(valueStr)

		}

		if key == models.SettingRTCProvider {

			valueType = "string"

			valueStr = normalizeRTCProvider(valueStr)

		}

		// 使用 Upsert（key是MySQL保留字，需要反引号）
		var setting models.SystemSetting

		result := h.db.Where("`key` = ?", key).First(&setting)

		if result.Error == gorm.ErrRecordNotFound {

			// 创建新设置

			setting = models.SystemSetting{

				Key: key,

				Value: valueStr,

				Type: valueType,
			}

			h.db.Create(&setting)

		} else {

			// 更新现有设置

			h.db.Model(&setting).Updates(map[string]interface{}{

				"value": valueStr,

				"type": valueType,
			})

		}
	}
	// 数据库 SystemSetting 是运行时权威来源；写入阶段结束后才让常驻服务重新读取配置。
	if hasPushConfigChange && h.pushService != nil {

		h.pushService.ReloadConfig()
	}
	changedKeys := make([]string, 0, len(req))
	for key := range req {

		changedKeys = append(changedKeys, key)
	}
	recordAdminSecurityEvent(c, h.db, adminSecurityEventInput{

		EventType: "settings",

		Action: "update",

		Target: "system_settings",

		Success: true,

		Metadata: map[string]interface{}{

			"changed_keys": changedKeys,

			"changed_count": len(changedKeys),

			"push_reloaded": hasPushConfigChange && h.pushService != nil,
		},
	})
	if h.hub != nil {

		h.hub.SendToAll(map[string]interface{}{

			"type": "system_settings_updated",
		})
	}
	response.SuccessWithMessage(c, "设置已保存", nil)
}
func normalizeSettingInputValue(value interface{}) string {
	switch v := value.(type) {
	case string:

		return strings.TrimSpace(v)
	case bool:

		if v {

			return "true"

		}

		return "false"
	case float64:

		return strconv.Itoa(int(v))
	default:

		if jsonBytes, err := json.Marshal(v); err == nil {

			return string(jsonBytes)

		}

		return ""
	}
}
func parseSettingBoolValue(value interface{}) (bool, error) {
	switch v := value.(type) {
	case bool:

		return v, nil
	case string:

		s := strings.ToLower(strings.TrimSpace(v))

		switch s {

		case "true", "1", "yes", "on":

			return true, nil

		case "false", "0", "no", "off", "":

			return false, nil

		default:

			return false, fmt.Errorf("invalid bool value: %s", v)

		}
	case float64:

		return int(v) != 0, nil
	default:

		return false, fmt.Errorf("invalid bool type")
	}
}
func runtimeCloudStorageConfig(db *gorm.DB) config.StorageConfig {
	var yamlCfg config.StorageConfig
	if config.GlobalConfig != nil {

		yamlCfg = config.GlobalConfig.Storage
	}
	return services.LoadStorageForRuntime(db, yamlCfg)
}
func prepareCloudStorageSettingForSave(db *gorm.DB, raw interface{}) (config.StorageConfig, error) {
	var incoming config.StorageConfig
	b, err := json.Marshal(raw)
	if err != nil || json.Unmarshal(b, &incoming) != nil {

		return config.StorageConfig{}, fmt.Errorf("云存储配置格式错误")
	}
	current := runtimeCloudStorageConfig(db)
	if services.IsMaskedStorageCredential(incoming.S3.AccessKeyID) {

		incoming.S3.AccessKeyID = current.S3.AccessKeyID
	}
	if services.IsMaskedStorageCredential(incoming.S3.SecretAccessKey) {

		incoming.S3.SecretAccessKey = current.S3.SecretAccessKey
	}
	if err := services.ValidateStorageConfig(incoming); err != nil {

		return config.StorageConfig{}, err
	}
	encrypted, err := services.EncryptStorageConfigSecrets(incoming)
	if err != nil {

		return config.StorageConfig{}, err
	}
	return encrypted, nil
}
func cloudStorageSettingValue(db *gorm.DB, isDemoAdmin bool) interface{} {
	cfg := runtimeCloudStorageConfig(db)
	if !isDemoAdmin {

		return services.MaskS3StorageCredentials(cfg)
	}
	b, err := json.Marshal(cfg)
	if err != nil {

		return "******"
	}
	return services.MaskStorageConfigForDemo(string(b))
}
func cloudStorageSettingRecord(db *gorm.DB, isDemoAdmin bool) models.SystemSetting {
	value := cloudStorageSettingValue(db, isDemoAdmin)
	b, err := json.Marshal(value)
	if err != nil {

		b = []byte(`"******"`)
	}
	return models.SystemSetting{

		Key: models.SettingCloudStorage,

		Value: string(b),

		Type: "json",
	}
}
func clientBootstrapSettingValue() config.ClientBootstrapConfig {
	if config.GlobalConfig == nil {

		return config.ClientBootstrapConfig{

			Enabled: true,

			Version: 1,

			TTLSeconds: 300,

			Strategy: config.ClientBootstrapStrategyConfig{

				ConnectTimeoutMS: 5000,

				HealthTimeoutMS: 3000,

				FailThreshold: 1,

				CooldownSeconds: 60,

				PreferLastSuccess: true,
			},
		}
	}
	return config.GlobalConfig.ClientBootstrap
}
func (h *SettingHandler) validateSystemSettingsForUpdate(req map[string]interface{}) error {
	// 先做顶层键白名单，再做各配置域的组合校验，禁止任意键借批量接口写入 system_settings。
	for key := range req {

		if !isAllowedSystemSettingKey(key) {

			return fmt.Errorf("不支持的设置项：%s", key)

		}
	}
	if raw, exists := req[models.SettingChatAttachmentMenu]; exists {

		if err := validateChatAttachmentMenuSetting(raw); err != nil {

			return err

		}
	}
	if raw, exists := req[models.SettingChatImageDirectUploadPlatforms]; exists {
		var platforms []string

		payload, err := json.Marshal(raw)

		if err != nil || json.Unmarshal(payload, &platforms) != nil {

			return fmt.Errorf("图片直传平台必须为数组")

		}
		normalized := services.NormalizeDirectUploadPlatforms(platforms)

		if len(normalized) == 0 || len(normalized) != len(platforms) {

			return fmt.Errorf("图片直传平台仅支持 android、ios、windows、macos、linux、web，且不能重复")

		}

		req[models.SettingChatImageDirectUploadPlatforms] = normalized
	}
	for key, bounds := range map[string][2]int{

		models.SettingChatImageDirectUploadRolloutPercent: {0, 100},

		models.SettingChatImageDirectUploadMaxConcurrency: {1, 3},
	} {

		if raw, exists := req[key]; exists {

			value, err := strconv.Atoi(normalizeSettingInputValue(raw))

			if err != nil || value < bounds[0] || value > bounds[1] {

				return fmt.Errorf("%s 需为 %d-%d 的整数", key, bounds[0], bounds[1])

			}

		}
	}
	if raw, exists := req[models.SettingChatImageDirectUploadEnabled]; exists {

		enabled, err := parseSettingBoolValue(raw)

		if err != nil {

			return fmt.Errorf("图片直传启用状态格式错误")

		}

		if enabled {

			provider := services.NormalizeStorageProvider(runtimeCloudStorageConfig(h.db).Provider)

			if storageRaw, exists := req[models.SettingCloudStorage]; exists {

				payload, _ := json.Marshal(storageRaw)
				var requested config.StorageConfig

				if json.Unmarshal(payload, &requested) == nil {

					provider = services.NormalizeStorageProvider(requested.Provider)

				}

			}

			if provider != services.StorageProviderS3 {

				return fmt.Errorf("开启聊天图片直传前，云存储必须选择 Amazon S3")

			}

		}
	}
	if raw, exists := req[models.SettingRequirePhoneBind]; exists {

		enabled, err := parseSettingBoolValue(raw)

		if err != nil {

			return fmt.Errorf("强制绑定手机号状态格式错误")

		}

		if enabled && (h.smsSvc == nil || !h.smsSvc.CanSend()) {

			return fmt.Errorf("开启强制绑定手机号前，请先配置并启用短信服务")

		}
	}
	for key, maximum := range map[string]int{

		models.SettingQuickRegisterDeviceLimit: 20,

		models.SettingQuickRegisterIPLimit: 1000,
	} {

		if raw, exists := req[key]; exists {

			value, err := strconv.Atoi(normalizeSettingInputValue(raw))

			if err != nil || value < 1 || value > maximum {

				return fmt.Errorf("%s 需为 1-%d 的整数", key, maximum)

			}

		}
	}
	if raw, exists := req[models.SettingRegisterBaseURL]; exists {

		if err := validatePublicH5URLSetting(normalizeSettingInputValue(raw)); err != nil {

			return err

		}
	}
	if raw, exists := req[models.SettingSupportOnlineURL]; exists {

		if err := validateHTTPURLSetting("在线客服链接", normalizeSettingInputValue(raw), true); err != nil {

			return err

		}
	}
	if raw, exists := req[models.SettingSupportQQ]; exists {

		if err := validateSupportQQSetting(normalizeSettingInputValue(raw)); err != nil {

			return err

		}
	}
	for _, key := range []string{

		models.SettingAppUpdateURL,

		models.SettingAppUpdateURLAndroid,
	} {

		if raw, exists := req[key]; exists {

			if err := validateHTTPURLSetting("应用更新链接", normalizeSettingInputValue(raw), true); err != nil {

				return err

			}

		}
	}
	if raw, exists := req[models.SettingAppUpdateURLIOS]; exists {

		if err := validateAppStoreURLSetting(normalizeSettingInputValue(raw)); err != nil {

			return err

		}
	}
	if raw, exists := req[models.SettingMessageCryptoMode]; exists {

		if !isValidMessageCryptoMode(normalizeSettingInputValue(raw)) {

			return fmt.Errorf("消息加密模式只能是 plain、compatible 或 strict")

		}
	}
	if raw, exists := req[models.SettingFriendAddMode]; exists {

		mode := strings.ToLower(strings.TrimSpace(normalizeSettingInputValue(raw)))

		if mode != models.FriendAddModeDirect &&

			mode != models.FriendAddModeApproval &&

			mode != models.FriendAddModeDisabled {

			return fmt.Errorf("加好友方式只能是 direct、approval 或 disabled")

		}
	}
	if raw, exists := req[models.SettingRTCProvider]; exists {

		if normalizeRTCProvider(normalizeSettingInputValue(raw)) == "" {

			return fmt.Errorf("rtc_provider must be agora or livekit")

		}
	}
	if raw, exists := req[models.SettingLiveKitServerURL]; exists {

		if err := validateRTCURLSetting("LiveKit Server URL", normalizeSettingInputValue(raw), true); err != nil {

			return err

		}
	}
	if hasRTCSettingChange(req) {

		if err := h.validateRTCSettingsForUpdate(req); err != nil {

			return err

		}
	}
	if raw, exists := req[models.SettingCloudStorage]; exists {

		if err := validateCloudStorageSetting(raw); err != nil {

			return err

		}
	}
	if raw, exists := req[models.SettingClientBootstrap]; exists {

		if err := validateClientBootstrapSetting(raw); err != nil {

			return err

		}
	}
	if hasCustomPortalSettingChange(req) {

		if err := h.validateCustomPortalSettingsForUpdate(req); err != nil {

			return err

		}
	}
	return nil
}
func hasRTCSettingChange(req map[string]interface{}) bool {
	for _, key := range []string{

		models.SettingRTCProvider,

		models.SettingAgoraEnabled,

		models.SettingAgoraAppID,

		models.SettingAgoraAppCertificate,

		models.SettingAgoraTokenExpire,

		models.SettingLiveKitEnabled,

		models.SettingLiveKitServerURL,

		models.SettingLiveKitAPIKey,

		models.SettingLiveKitAPISecret,

		models.SettingLiveKitTokenExpire,
	} {

		if _, exists := req[key]; exists {

			return true

		}
	}
	return false
}
func (h *SettingHandler) validateRTCSettingsForUpdate(req map[string]interface{}) error {
	if h == nil || h.db == nil {

		return nil
	}
	keys := []string{

		models.SettingRTCProvider,

		models.SettingAgoraEnabled,

		models.SettingAgoraAppID,

		models.SettingAgoraAppCertificate,

		models.SettingAgoraTokenExpire,

		models.SettingLiveKitEnabled,

		models.SettingLiveKitServerURL,

		models.SettingLiveKitAPIKey,

		models.SettingLiveKitAPISecret,

		models.SettingLiveKitTokenExpire,
	}
	var settings []models.SystemSetting
	_ = h.db.Where("`key` IN ?", keys).Find(&settings).Error
	current := make(map[string]string, len(settings))
	for _, setting := range settings {

		current[setting.Key] = strings.TrimSpace(setting.Value)
	}
	getString := func(key string) string {

		if raw, exists := req[key]; exists {

			return normalizeSettingInputValue(raw)

		}

		return strings.TrimSpace(current[key])
	}
	getBool := func(key string) (bool, error) {

		if raw, exists := req[key]; exists {

			return parseSettingBoolValue(raw)

		}

		return parseSettingBoolValue(current[key])
	}
	getInt := func(key string, fallback int) (int, error) {

		raw := getString(key)

		if raw == "" {

			return fallback, nil

		}
		value, err := strconv.Atoi(raw)

		if err != nil {

			return 0, fmt.Errorf("%s must be a positive integer", key)

		}

		if value <= 0 {

			return 0, fmt.Errorf("%s must be greater than 0", key)

		}

		return value, nil
	}
	provider := normalizeRTCProvider(getString(models.SettingRTCProvider))
	if provider == "" {

		provider = models.RTCProviderAgora
	}
	agoraEnabled, err := getBool(models.SettingAgoraEnabled)
	if err != nil {

		return fmt.Errorf("agora_enabled format is invalid")
	}
	liveKitEnabled, err := getBool(models.SettingLiveKitEnabled)
	if err != nil {

		return fmt.Errorf("livekit_enabled format is invalid")
	}
	if _, err := getInt(models.SettingAgoraTokenExpire, 3600); err != nil {

		return err
	}
	if _, err := getInt(models.SettingLiveKitTokenExpire, 3600); err != nil {

		return err
	}
	agoraAppID := getString(models.SettingAgoraAppID)
	agoraCertificate := getString(models.SettingAgoraAppCertificate)
	if agoraEnabled && (agoraAppID == "" || agoraCertificate == "") {

		return fmt.Errorf("Agora App ID and App Certificate are required when Agora is enabled")
	}
	liveKitServerURL := getString(models.SettingLiveKitServerURL)
	liveKitAPIKey := getString(models.SettingLiveKitAPIKey)
	liveKitAPISecret := getString(models.SettingLiveKitAPISecret)
	if liveKitEnabled {

		if liveKitServerURL == "" || liveKitAPIKey == "" || liveKitAPISecret == "" {

			return fmt.Errorf("LiveKit Server URL, API Key and API Secret are required when LiveKit is enabled")

		}

		if err := validateRTCURLSetting("LiveKit Server URL", liveKitServerURL, false); err != nil {

			return err

		}
	}
	switch provider {
	case models.RTCProviderLiveKit:

		if !liveKitEnabled {

			return fmt.Errorf("LiveKit must be enabled before selecting it as rtc_provider")

		}
	case models.RTCProviderAgora:

		if !agoraEnabled {

			return fmt.Errorf("Agora must be enabled before selecting it as rtc_provider")

		}
	default:

		return fmt.Errorf("rtc_provider must be agora or livekit")
	}
	return nil
}
func validateCloudStorageSetting(raw interface{}) error {
	var cfg config.StorageConfig
	b, err := json.Marshal(raw)
	if err != nil {

		return fmt.Errorf("云存储配置格式错误")
	}
	if err := json.Unmarshal(b, &cfg); err != nil {

		return fmt.Errorf("云存储配置格式错误")
	}
	return services.ValidateStorageConfig(cfg)
}
func validateClientBootstrapSetting(raw interface{}) error {
	var cfg config.ClientBootstrapConfig
	b, err := json.Marshal(raw)
	if err != nil {

		return fmt.Errorf("客户端入口容灾配置格式错误")
	}
	if err := json.Unmarshal(b, &cfg); err != nil {

		return fmt.Errorf("客户端入口容灾配置格式错误")
	}
	if cfg.TTLSeconds < 30 {

		return fmt.Errorf("客户端入口配置缓存时间不能小于 30 秒")
	}
	if cfg.Strategy.FailThreshold < 1 {

		return fmt.Errorf("失败切换阈值不能小于 1")
	}
	if cfg.Strategy.CooldownSeconds < 10 {

		return fmt.Errorf("入口冷却时间不能小于 10 秒")
	}
	if len(cfg.APIEndpoints) == 0 {

		return fmt.Errorf("至少需要配置一个 API 入口")
	}
	if len(cfg.WSEndpoints) == 0 {

		return fmt.Errorf("至少需要配置一个 WebSocket 入口")
	}
	if len(normalizeClientEndpoints(cfg.APIEndpoints, "", "/api/v1/ping", runtimeServerMode())) == 0 {

		return fmt.Errorf("API 入口地址格式错误")
	}
	if len(normalizeClientEndpoints(cfg.WSEndpoints, "", "", runtimeServerMode())) == 0 {

		return fmt.Errorf("WebSocket 入口地址格式错误")
	}
	for _, mediaURL := range cfg.MediaBaseURLs {

		if strings.TrimSpace(mediaURL) == "" {

			continue

		}

		if !isAllowedHTTPClientURL(strings.TrimSpace(mediaURL), runtimeServerMode()) {

			return fmt.Errorf("资源入口地址格式错误")

		}
	}
	return nil
}
func runtimeServerMode() string {
	if config.GlobalConfig == nil {

		return ""
	}
	return config.GlobalConfig.Server.Mode
}
func hasCustomPortalSettingChange(req map[string]interface{}) bool {
	for _, key := range []string{

		models.SettingCustomPortalEnabled,

		models.SettingCustomPortalTitle,

		models.SettingCustomPortalURL,

		models.SettingCustomPortalIconURL,
	} {

		if _, exists := req[key]; exists {

			return true

		}
	}
	return false
}
func (h *SettingHandler) validateCustomPortalSettingsForUpdate(req map[string]interface{}) error {
	keys := []string{

		models.SettingCustomPortalEnabled,

		models.SettingCustomPortalTitle,

		models.SettingCustomPortalURL,

		models.SettingCustomPortalIconURL,
	}
	var settings []models.SystemSetting
	_ = h.db.Where("`key` IN ?", keys).Find(&settings).Error
	current := make(map[string]string, len(settings))
	for _, setting := range settings {

		current[setting.Key] = strings.TrimSpace(setting.Value)
	}
	getString := func(key string) string {

		if raw, exists := req[key]; exists {

			return normalizeSettingInputValue(raw)

		}

		return current[key]
	}
	getBool := func(key string) (bool, error) {

		if raw, exists := req[key]; exists {

			return parseSettingBoolValue(raw)

		}

		return isSystemSettingTrue(current[key]), nil
	}
	enabled, err := getBool(models.SettingCustomPortalEnabled)
	if err != nil {

		return fmt.Errorf("自定义栏目启用状态格式错误")
	}
	title := getString(models.SettingCustomPortalTitle)
	if utf8.RuneCountInString(title) > 20 {

		return fmt.Errorf("自定义栏目名称不能超过20个字符")
	}
	portalURL := getString(models.SettingCustomPortalURL)
	if enabled {

		if strings.TrimSpace(portalURL) == "" {

			return fmt.Errorf("启用自定义栏目时，打开网址不能为空")

		}

		if err := validateHTTPURLSetting("自定义栏目打开网址", portalURL, false); err != nil {

			return err

		}
	} else if strings.TrimSpace(portalURL) != "" {

		if err := validateHTTPURLSetting("自定义栏目打开网址", portalURL, true); err != nil {

			return err

		}
	}
	iconURL := getString(models.SettingCustomPortalIconURL)
	if strings.TrimSpace(iconURL) != "" {

		if err := validateImageURLSetting("自定义栏目图标", iconURL); err != nil {

			return err

		}
	}
	return nil
}
func validateHTTPURLSetting(label, value string, allowEmpty bool) error {
	value = strings.TrimSpace(value)
	if value == "" {

		if allowEmpty {

			return nil

		}

		return fmt.Errorf("%s不能为空", label)
	}
	if strings.ContainsAny(value, " \t\r\n") {

		return fmt.Errorf("%s不能包含空白字符", label)
	}
	parseValue := value
	if !strings.HasPrefix(parseValue, "http://") && !strings.HasPrefix(parseValue, "https://") {

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
func validateAppStoreURLSetting(value string) error {
	value = strings.TrimSpace(value)
	if value == "" {

		return nil
	}
	parsed, err := url.Parse(value)
	if err != nil || parsed.Scheme != "https" || parsed.Host == "" {

		return fmt.Errorf("iOS 更新链接必须是 Apple 官方 HTTPS 地址")
	}
	host := strings.ToLower(parsed.Hostname())
	if host != "apps.apple.com" && host != "itunes.apple.com" && host != "appstore.com" {

		return fmt.Errorf("iOS 更新链接必须使用 apps.apple.com 或 itunes.apple.com")
	}
	return nil
}
func firstNonEmptySetting(primary, fallback string) string {
	if strings.TrimSpace(primary) != "" {

		return primary
	}
	return fallback
}
func validatePublicH5URLSetting(value string) error {
	value = strings.TrimSpace(value)
	if err := validateHTTPURLSetting("H5分享地址", value, true); err != nil || value == "" {

		return err
	}
	parsed, err := url.Parse(value)
	if err != nil {

		return fmt.Errorf("H5分享地址格式错误")
	}
	hostParts := strings.Split(strings.ToLower(parsed.Hostname()), ".")
	firstLabel := ""
	if len(hostParts) > 0 {

		firstLabel = hostParts[0]
	}
	path := strings.ToLower(parsed.Path)
	if firstLabel == "api" || firstLabel == "imapi" || strings.HasSuffix(firstLabel, "-api") || path == "/api" || strings.HasPrefix(path, "/api/") {

		return fmt.Errorf("H5分享地址必须填写H5页面域名，不能填写API接口域名")
	}
	return nil
}
func validateSupportQQSetting(value string) error {
	value = strings.TrimSpace(value)
	if value == "" {

		return nil
	}
	if utf8.RuneCountInString(value) > 50 {

		return fmt.Errorf("QQ 客服号不能超过50个字符")
	}
	if strings.ContainsAny(value, "\r\n") {

		return fmt.Errorf("QQ 客服号不能包含换行")
	}
	return nil
}
func validateRTCURLSetting(label, value string, allowEmpty bool) error {
	value = strings.TrimSpace(value)
	if value == "" {

		if allowEmpty {

			return nil

		}

		return fmt.Errorf("%s cannot be empty", label)
	}
	if strings.ContainsAny(value, " \t\r\n") {

		return fmt.Errorf("%s cannot contain whitespace", label)
	}
	parsed, err := url.Parse(value)
	if err != nil || parsed.Host == "" {

		return fmt.Errorf("%s format is invalid", label)
	}
	switch parsed.Scheme {
	case "ws", "wss", "http", "https":

		return nil
	default:

		return fmt.Errorf("%s must start with ws://, wss://, http:// or https://", label)
	}
}
func validateImageURLSetting(label, value string) error {
	value = strings.TrimSpace(value)
	if value == "" {

		return nil
	}
	if strings.ContainsAny(value, " \t\r\n") {

		return fmt.Errorf("%s不能包含空白字符", label)
	}
	if strings.HasPrefix(value, "/") || strings.HasPrefix(value, "uploads/") {

		return nil
	}
	return validateHTTPURLSetting(label, value, false)
}
func isValidPushProviderSetting(value string, allowNone bool) bool {
	switch strings.ToLower(strings.TrimSpace(value)) {
	case "jpush", "getui", "native", "fcm", "hms", "xiaomi", "oppo", "apns":

		return true
	case "none", "":

		return allowNone
	default:

		return false
	}
}
func resolveRegisterBaseURL(db *gorm.DB) string {
	if db != nil {
		var setting models.SystemSetting

		if err := db.Where("`key` = ?", models.SettingRegisterBaseURL).First(&setting).Error; err == nil {

			if value := strings.TrimSpace(setting.Value); value != "" {

				return strings.TrimRight(value, "/")

			}

		}
	}
	if config.GlobalConfig != nil {

		if value := strings.TrimSpace(config.GlobalConfig.Server.RegisterBaseURL); value != "" {

			return strings.TrimRight(value, "/")

		}

		if value := strings.TrimSpace(config.GlobalConfig.Server.BaseURL); value != "" {

			return strings.TrimRight(value, "/")

		}
	}
	return ""
}
func (h *SettingHandler) validatePushSettingsForUpdate(req map[string]interface{}) error {
	keys := []string{

		models.SettingAPNsEnabled,

		models.SettingAPNsBundleID,

		models.SettingAPNsKeyID,

		models.SettingAPNsTeamID,

		models.SettingAPNsAuthKey,

		models.SettingAPNsEnvironment,

		models.SettingFCMEnabled,

		models.SettingFCMProjectID,

		models.SettingFCMServiceAccountJSON,

		models.SettingHMSEnabled,

		models.SettingHMSAppID,

		models.SettingHMSAppSecret,

		models.SettingJPushEnabled,

		models.SettingJPushAppKey,

		models.SettingJPushMasterSecret,

		models.SettingPushDefaultTitle,

		models.SettingPushChatEnabled,

		models.SettingPushFriendEnabled,

		models.SettingPushSystemEnabled,

		models.SettingPushCategoryChat,

		models.SettingPushCategoryService,

		models.SettingPushCategoryMarketing,

		models.SettingPushPrimaryProvider,

		models.SettingPushFallbackProvider,

		models.SettingPushRateLimitPerMinute,

		models.SettingPushMarketingDailyLimit,

		models.SettingPushQuietHoursEnabled,

		models.SettingPushQuietHoursStart,

		models.SettingPushQuietHoursEnd,

		models.SettingXiaomiPushEnabled,

		models.SettingXiaomiPackageName,

		models.SettingXiaomiAppSecret,

		models.SettingOppoPushEnabled,

		models.SettingOppoAppKey,

		models.SettingOppoAppSecret,

		models.SettingWebPushEnabled,

		models.SettingWebPushVAPIDPublicKey,

		models.SettingWebPushVAPIDPrivateKey,

		models.SettingWebPushSubject,

		models.SettingWebPushTTL,
	}
	var settings []models.SystemSetting
	_ = h.db.Where("`key` IN ?", keys).Find(&settings).Error
	current := make(map[string]string, len(settings))
	for _, s := range settings {

		current[s.Key] = strings.TrimSpace(s.Value)
	}
	getString := func(key string) string {

		if raw, exists := req[key]; exists {

			return normalizeSettingInputValue(raw)

		}

		return strings.TrimSpace(current[key])
	}
	getBool := func(key string) (bool, error) {

		if raw, exists := req[key]; exists {

			return parseSettingBoolValue(raw)

		}

		return isSystemSettingTrue(current[key]), nil
	}
	getInt := func(key string) (int, error) {

		if raw, exists := req[key]; exists {

			switch value := raw.(type) {

			case float64:

				return int(value), nil

			case int:

				return value, nil

			case int64:

				return int(value), nil

			case string:

				return strconv.Atoi(strings.TrimSpace(value))

			default:

				return strconv.Atoi(normalizeSettingInputValue(raw))

			}

		}

		if strings.TrimSpace(current[key]) == "" {

			return 0, nil

		}

		return strconv.Atoi(strings.TrimSpace(current[key]))
	}
	apnsEnabled, err := getBool(models.SettingAPNsEnabled)
	if err != nil {

		return fmt.Errorf("APNs 启用状态格式错误")
	}
	if apnsEnabled {

		if getString(models.SettingAPNsBundleID) == "" ||

			getString(models.SettingAPNsKeyID) == "" ||

			getString(models.SettingAPNsTeamID) == "" ||

			getString(models.SettingAPNsAuthKey) == "" {

			return fmt.Errorf("启用 APNs 推送时，Bundle ID/Key ID/Team ID/Auth Key 不能为空")

		}
		env := strings.ToLower(getString(models.SettingAPNsEnvironment))

		if env == "" {

			env = "development"

		}

		if env != "development" && env != "production" {

			return fmt.Errorf("APNs 环境仅支持 development 或 production")

		}
	}
	fcmEnabled, err := getBool(models.SettingFCMEnabled)
	if err != nil {

		return fmt.Errorf("FCM 启用状态格式错误")
	}
	if fcmEnabled {

		projectID := getString(models.SettingFCMProjectID)
		serviceJSON := getString(models.SettingFCMServiceAccountJSON)

		if err := validateFCMPushConfig(projectID, serviceJSON); err != nil {

			return err

		}
	}
	hmsEnabled, err := getBool(models.SettingHMSEnabled)
	if err != nil {

		return fmt.Errorf("HMS 启用状态格式错误")
	}
	if hmsEnabled {

		if getString(models.SettingHMSAppID) == "" || getString(models.SettingHMSAppSecret) == "" {

			return fmt.Errorf("启用 HMS 推送时，App ID 与 App Secret 不能为空")

		}
	}
	jpushEnabled, err := getBool(models.SettingJPushEnabled)
	if err != nil {

		return fmt.Errorf("极光推送启用状态格式错误")
	}
	if jpushEnabled {

		if getString(models.SettingJPushAppKey) == "" || getString(models.SettingJPushMasterSecret) == "" {

			return fmt.Errorf("启用极光推送时，AppKey 与 MasterSecret 不能为空")

		}
	}
	for key, label := range map[string]string{

		models.SettingPushCategoryChat: "聊天消息分类",

		models.SettingPushCategoryService: "服务通知分类",

		models.SettingPushCategoryMarketing: "运营通知分类",
	} {

		value := getString(key)

		if value == "" {

			return fmt.Errorf("%s不能为空", label)

		}

		if !pushCategoryPattern.MatchString(value) {

			return fmt.Errorf("%s仅支持 1-64 位字母、数字、下划线、横线、冒号", label)

		}
	}
	if !isValidPushProviderSetting(getString(models.SettingPushPrimaryProvider), false) {

		return fmt.Errorf("主推送供应商仅支持 jpush/getui/native/fcm/hms/xiaomi/oppo/apns")
	}
	if !isValidPushProviderSetting(getString(models.SettingPushFallbackProvider), true) {

		return fmt.Errorf("备用推送供应商仅支持 none/getui/native/fcm/hms/xiaomi/oppo/apns")
	}
	for key, label := range map[string]string{

		models.SettingPushRateLimitPerMinute: "单用户每分钟上限",

		models.SettingPushMarketingDailyLimit: "单用户每日运营上限",
	} {

		value, err := getInt(key)

		if err != nil || value < 0 {

			return fmt.Errorf("%s必须是非负整数", label)

		}
	}
	for key, label := range map[string]string{

		models.SettingPushQuietHoursStart: "免打扰开始时间",

		models.SettingPushQuietHoursEnd: "免打扰结束时间",
	} {

		value := getString(key)

		if value != "" && !pushQuietHourPattern.MatchString(value) {

			return fmt.Errorf("%s格式必须是 HH:mm", label)

		}
	}
	xiaomiEnabled, err := getBool(models.SettingXiaomiPushEnabled)
	if err != nil {

		return fmt.Errorf("小米推送启用状态格式错误")
	}
	if xiaomiEnabled {

		if getString(models.SettingXiaomiPackageName) == "" || getString(models.SettingXiaomiAppSecret) == "" {

			return fmt.Errorf("启用小米推送时，包名与 App Secret 不能为空")

		}
	}
	oppoEnabled, err := getBool(models.SettingOppoPushEnabled)
	if err != nil {

		return fmt.Errorf("OPPO 推送启用状态格式错误")
	}
	if oppoEnabled {

		if getString(models.SettingOppoAppKey) == "" || getString(models.SettingOppoAppSecret) == "" {

			return fmt.Errorf("启用 OPPO 推送时，App Key 与 App Secret 不能为空")

		}
	}
	webPushEnabled, err := getBool(models.SettingWebPushEnabled)
	if err != nil {

		return fmt.Errorf("WebPush 启用状态格式错误")
	}
	if webPushEnabled {

		if getString(models.SettingWebPushVAPIDPublicKey) == "" ||

			getString(models.SettingWebPushVAPIDPrivateKey) == "" {

			return fmt.Errorf("启用 WebPush 时，VAPID 公钥与私钥不能为空")

		}
	}
	if ttlText := getString(models.SettingWebPushTTL); ttlText != "" {

		ttl, err := strconv.Atoi(ttlText)

		if err != nil || ttl <= 0 || ttl > 2419200 {

			return fmt.Errorf("WebPush TTL 需为 1-2419200 秒")

		}
	}
	return nil
}
func isAllowedSystemSettingKey(key string) bool {
	// 此白名单定义管理端可写范围；新增设置只有明确加入后才能通过批量更新接口生效。
	switch key {
	case models.SettingAppVersionIOS,

		models.SettingAppVersionAndroid,

		models.SettingLatestVersionIOS,

		models.SettingLatestVersionAndroid,

		models.SettingAppForceUpdate,

		models.SettingAppUpdateURL,

		models.SettingAppUpdateURLIOS,

		models.SettingAppUpdateURLAndroid,

		models.SettingMinSupportedVersionIOS,

		models.SettingMinSupportedVersionAndroid,

		models.SettingAppUpdateMessage,

		models.SettingSplashEnabled,

		models.SettingSplashImageURL,

		models.SettingSplashDurationMs,

		models.SettingSystemName,

		models.SettingSystemVersion,

		models.SettingRegisterBaseURL,

		models.SettingSupportOnlineURL,

		models.SettingSupportQQ,

		models.SettingAllowRegister,

		models.SettingAllowQuickRegister,

		models.SettingQuickRegisterDeviceLimit,

		models.SettingQuickRegisterIPLimit,

		models.SettingForceKeepAliveEnabled,

		models.SettingRequireInviteCode,

		models.SettingRequireGenderOnRegister,

		models.SettingRequirePhoneBind,

		models.SettingBurnAfterReadEnabled,

		models.SettingChatAttachmentMenu,

		models.SettingMessageCryptoMode,

		models.SettingEnableMomentPost,

		models.SettingMomentPostReviewEnabled,

		models.SettingIOSCompliance,

		models.SettingNewUserFollowOfficial,

		models.SettingInviteRegisterBindOnly,

		models.SettingNewUserJoinGroup,

		models.SettingNewUserJoinChannel,

		models.SettingGroupInviteRequireFriend,

		models.SettingFriendAddMode,

		models.SettingVipFreeEntitlements,

		models.SettingCustomPortalEnabled,

		models.SettingCustomPortalTitle,

		models.SettingCustomPortalURL,

		models.SettingCustomPortalIconURL,

		models.SettingOfficialUsers,

		models.SettingOfficialGroups,

		models.SettingOfficialChannels,

		models.SettingGroupMaxMembers,

		models.SettingChannelMaxMembers,

		models.SettingHeartbeatTimeout,

		models.SettingMaxImageSize,

		models.SettingMaxVideoSize,

		models.SettingMaxFileSize,

		models.SettingMaxVoiceSize,

		models.SettingCloudStorage,

		models.SettingClientBootstrap,

		models.SettingChatImageDirectUploadEnabled,

		models.SettingChatImageDirectUploadPlatforms,

		models.SettingChatImageDirectUploadRolloutPercent,

		models.SettingChatImageDirectUploadMaxConcurrency,

		models.SettingRTCProvider,

		models.SettingAgoraEnabled,

		models.SettingAgoraAppID,

		models.SettingAgoraAppCertificate,

		models.SettingAgoraTokenExpire,

		models.SettingLiveKitEnabled,

		models.SettingLiveKitServerURL,

		models.SettingLiveKitAPIKey,

		models.SettingLiveKitAPISecret,

		models.SettingLiveKitTokenExpire,

		models.SettingAPNsEnabled,

		models.SettingAPNsBundleID,

		models.SettingAPNsKeyID,

		models.SettingAPNsTeamID,

		models.SettingAPNsAuthKey,

		models.SettingAPNsEnvironment,

		models.SettingFCMEnabled,

		models.SettingFCMProjectID,

		models.SettingFCMServiceAccountJSON,

		models.SettingHMSEnabled,

		models.SettingHMSAppID,

		models.SettingHMSAppSecret,

		models.SettingJPushEnabled,

		models.SettingJPushAppKey,

		models.SettingJPushMasterSecret,

		models.SettingPushDefaultTitle,

		models.SettingPushChatEnabled,

		models.SettingPushFriendEnabled,

		models.SettingPushSystemEnabled,

		models.SettingPushCategoryChat,

		models.SettingPushCategoryService,

		models.SettingPushCategoryMarketing,

		models.SettingPushPrimaryProvider,

		models.SettingPushFallbackProvider,

		models.SettingPushRateLimitPerMinute,

		models.SettingPushMarketingDailyLimit,

		models.SettingPushQuietHoursEnabled,

		models.SettingPushQuietHoursStart,

		models.SettingPushQuietHoursEnd,

		models.SettingXiaomiPushEnabled,

		models.SettingXiaomiPackageName,

		models.SettingXiaomiAppSecret,

		models.SettingOppoPushEnabled,

		models.SettingOppoAppKey,

		models.SettingOppoAppSecret,

		models.SettingWebPushEnabled,

		models.SettingWebPushVAPIDPublicKey,

		models.SettingWebPushVAPIDPrivateKey,

		models.SettingWebPushSubject,

		models.SettingWebPushTTL,

		models.SettingUserAgreement,

		models.SettingPrivacyPolicy,

		models.SettingRevokeMessageMinutes,

		models.SettingIPRateLimit,

		models.SettingUserRateLimit,

		models.SettingVoiceTranscribeProvider,

		models.SettingVoiceTranscribeURL,

		models.SettingVoiceTranscribeToken,

		models.SettingVoiceTranscribeLanguage,

		models.SettingOpenAIAPIKey,

		models.SettingOpenAITranscribeModel,

		models.SettingOpenAITranscribeURL,

		models.SettingDeepSeekAPIKey,

		models.SettingDeepSeekBaseURL,

		models.SettingDeepSeekModel,

		models.SettingPaymentGateway,

		models.SettingSmsGateway,

		models.SettingRolePermissions:

		return true
	default:

		return false
	}
} // isPushSetting 检查是否是推送相关配置
func isPushSetting(key string) bool {
	switch key {
	case models.SettingAPNsEnabled,

		models.SettingAPNsBundleID,

		models.SettingAPNsKeyID,

		models.SettingAPNsTeamID,

		models.SettingAPNsAuthKey,

		models.SettingAPNsEnvironment,

		models.SettingFCMEnabled,

		models.SettingFCMProjectID,

		models.SettingFCMServiceAccountJSON,

		models.SettingHMSEnabled,

		models.SettingHMSAppID,

		models.SettingHMSAppSecret,

		models.SettingJPushEnabled,

		models.SettingJPushAppKey,

		models.SettingJPushMasterSecret,

		models.SettingPushDefaultTitle,

		models.SettingPushChatEnabled,

		models.SettingPushFriendEnabled,

		models.SettingPushSystemEnabled,

		models.SettingPushCategoryChat,

		models.SettingPushCategoryService,

		models.SettingPushCategoryMarketing,

		models.SettingPushPrimaryProvider,

		models.SettingPushFallbackProvider,

		models.SettingPushRateLimitPerMinute,

		models.SettingPushMarketingDailyLimit,

		models.SettingPushQuietHoursEnabled,

		models.SettingPushQuietHoursStart,

		models.SettingPushQuietHoursEnd,

		models.SettingXiaomiPushEnabled,

		models.SettingXiaomiPackageName,

		models.SettingXiaomiAppSecret,

		models.SettingOppoPushEnabled,

		models.SettingOppoAppKey,

		models.SettingOppoAppSecret,

		models.SettingWebPushEnabled,

		models.SettingWebPushVAPIDPublicKey,

		models.SettingWebPushVAPIDPrivateKey,

		models.SettingWebPushSubject,

		models.SettingWebPushTTL:

		return true
	}
	return false
} // GetSetting 获取单个设置
func (h *SettingHandler) GetSetting(c *gin.Context) {
	key := c.Param("key")
	if key == models.SettingCloudStorage {

		response.Success(c, cloudStorageSettingRecord(h.db, middleware.GetAdminRole(c) == "demo_admin"))

		return
	}
	var setting models.SystemSetting
	if err := h.db.Where("`key` = ?", key).First(&setting).Error; err != nil {

		response.Error(c, http.StatusNotFound, "设置不存在")

		return
	}
	if middleware.GetAdminRole(c) == "demo_admin" && sensitiveSettingKeys[key] {

		masked := setting

		switch key {

		case models.SettingSmsGateway, models.SettingPaymentGateway:

			masked.Value = "******"

			masked.Type = "string"

		default:

			masked.Value = "******"

		}

		response.Success(c, masked)

		return
	}
	response.Success(c, setting)
} // ==================== 官方用户管理 ====================  // GetOfficialUsers 获取官方用户列表
func (h *SettingHandler) GetOfficialUsers(c *gin.Context) {
	var officials []models.OfficialUser
	h.db.Order("sort_order ASC, created_at ASC").Find(&officials)
	// 获取用户详细信息
	type OfficialUserDetail struct {
		models.OfficialUser

		Username string `json:"username"`

		Nickname string `json:"nickname"`

		Avatar string `json:"avatar"`

		InviteCode string `json:"invite_code"`
	}
	var result []OfficialUserDetail
	for _, o := range officials {
		var user models.User

		if h.db.First(&user, o.UserID).Error == nil {
			var invite models.InviteCode

			inviteCode := ""

			// 只读查询，不在列表接口做任何写操作，避免误改邀请码状态

			if err := h.db.Where("service_user_id = ?", o.UserID).Order("id ASC").First(&invite).Error; err == nil {

				inviteCode = invite.Code

			}
			result = append(result, OfficialUserDetail{

				OfficialUser: o,

				Username: user.Username,

				Nickname: user.Nickname,

				Avatar: user.Avatar,

				InviteCode: inviteCode,
			})

		}
	}
	response.Success(c, result)
} // AddOfficialUser 添加官方用户
func (h *SettingHandler) AddOfficialUser(c *gin.Context) {
	var req struct {
		Username string `json:"username"` // 支持用户名搜索

		UserUUID string `json:"user_uuid"` // 也支持直接用UUID

		Remark string `json:"remark"`

		WelcomeMessage string `json:"welcome_message"` // 官方客服欢迎语

		InviteCode string `json:"invite_code"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {

		response.Error(c, http.StatusBadRequest, "参数错误")

		return
	}
	req.Username = strings.TrimSpace(req.Username)
	req.UserUUID = strings.TrimSpace(req.UserUUID)
	req.Remark = strings.TrimSpace(req.Remark)
	req.WelcomeMessage = strings.TrimSpace(req.WelcomeMessage)
	req.InviteCode = strings.TrimSpace(req.InviteCode)
	if req.Username == "" && req.UserUUID == "" {

		response.Error(c, http.StatusBadRequest, "请输入用户名或UUID")

		return
	}
	if !validateOfficialRemark(req.Remark) {

		response.Error(c, http.StatusBadRequest, "备注不能超过200个字符")

		return
	}
	if req.WelcomeMessage != "" && !validateOfficialWelcomeMessage(req.WelcomeMessage) {

		response.Error(c, http.StatusBadRequest, "欢迎语不能超过500个字符")

		return
	}
	if req.InviteCode != "" && !validateOfficialInviteCode(req.InviteCode) {

		response.Error(c, http.StatusBadRequest, "自定义邀请码需为6-12位字母或数字")

		return
	}
	// 查找用户（优先用户名，其次UUID）
	var user models.User
	if req.Username != "" {

		if err := h.db.Where("username = ?", req.Username).First(&user).Error; err != nil {

			response.Error(c, http.StatusNotFound, "用户不存在")

			return

		}
	} else {

		if err := h.db.Where("uuid = ?", req.UserUUID).First(&user).Error; err != nil {

			response.Error(c, http.StatusNotFound, "用户不存在")

			return

		}
	}
	// 检查是否已存在（包含已软删除记录）
	var existingOfficial models.OfficialUser
	hasExistingOfficial := false
	if err := h.db.Unscoped().Where("user_id = ?", user.ID).First(&existingOfficial).Error; err == nil {

		hasExistingOfficial = true

		if existingOfficial.DeletedAt.Valid == false {

			response.Error(c, http.StatusBadRequest, "该用户已是官方用户")

			return

		}
	}
	if req.InviteCode != "" {
		var inviteCount int64

		h.db.Model(&models.InviteCode{}).Where("code = ?", req.InviteCode).Count(&inviteCount)

		if inviteCount > 0 {

			response.Error(c, http.StatusBadRequest, "自定义邀请码已存在")

			return

		}
	}
	tx := h.db.Begin()
	if tx.Error != nil {

		response.Error(c, http.StatusInternalServerError, "添加失败")

		return
	}
	var official models.OfficialUser
	if hasExistingOfficial {

		official = existingOfficial

		official.UserUUID = user.UUID

		official.Remark = req.Remark

		official.WelcomeMessage = req.WelcomeMessage

		official.IsServiceEnabled = true

		official.DeletedAt = gorm.DeletedAt{}

		if official.WelcomeMessage == "" {

			official.WelcomeMessage = defaultServiceWelcomeMessage()

		}

		if err := tx.Unscoped().Model(&models.OfficialUser{}).Where("id = ?", existingOfficial.ID).Updates(map[string]interface{}{

			"user_uuid": official.UserUUID,

			"remark": official.Remark,

			"welcome_message": official.WelcomeMessage,

			"is_service_enabled": true,

			"deleted_at": nil,
		}).Error; err != nil {

			tx.Rollback()

			response.Error(c, http.StatusInternalServerError, "添加失败")

			return

		}
	} else {

		official = models.OfficialUser{

			UserID: user.ID,

			UserUUID: user.UUID,

			Remark: req.Remark,

			WelcomeMessage: req.WelcomeMessage,

			IsServiceEnabled: true,
		}

		if official.WelcomeMessage == "" {

			official.WelcomeMessage = defaultServiceWelcomeMessage()

		}

		if err := tx.Create(&official).Error; err != nil {

			tx.Rollback()

			response.Error(c, http.StatusInternalServerError, "添加失败")

			return

		}
	}
	invite, err := getOrCreateServiceInviteCode(tx, &user, "官方客服专属邀请码", req.InviteCode)
	if err != nil {

		tx.Rollback()

		response.Error(c, http.StatusInternalServerError, "官方客服添加失败：邀请码生成失败")

		return
	}
	if err := tx.Commit().Error; err != nil {

		tx.Rollback()

		response.Error(c, http.StatusInternalServerError, "保存失败")

		return
	}
	response.SuccessWithMessage(c, "已添加官方用户", gin.H{

		"id": official.ID,

		"user_id": user.ID,

		"uuid": user.UUID,

		"username": user.Username,

		"nickname": user.Nickname,

		"invite_code": invite.Code,
	})
} // UpdateOfficialUser 更新官方用户配置（欢迎语/状态/备注）
func (h *SettingHandler) UpdateOfficialUser(c *gin.Context) {
	id := c.Param("id")
	var official models.OfficialUser
	if err := h.db.Where("id = ?", id).First(&official).Error; err != nil {

		response.Error(c, http.StatusNotFound, "官方用户不存在")

		return
	}
	var req struct {
		Remark *string `json:"remark"`

		WelcomeMessage *string `json:"welcome_message"`

		IsServiceEnabled *bool `json:"is_service_enabled"`

		InviteCode *string `json:"invite_code"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {

		response.Error(c, http.StatusBadRequest, "参数错误")

		return
	}
	updates := map[string]interface{}{}
	inviteCodeToUpdate := ""
	if req.Remark != nil {

		remark := strings.TrimSpace(*req.Remark)

		if !validateOfficialRemark(remark) {

			response.Error(c, http.StatusBadRequest, "备注不能超过200个字符")

			return

		}

		updates["remark"] = remark
	}
	if req.WelcomeMessage != nil {

		msg := strings.TrimSpace(*req.WelcomeMessage)

		if msg != "" && !validateOfficialWelcomeMessage(msg) {

			response.Error(c, http.StatusBadRequest, "欢迎语不能超过500个字符")

			return

		}

		if msg == "" {

			msg = defaultServiceWelcomeMessage()

		}

		updates["welcome_message"] = msg
	}
	if req.IsServiceEnabled != nil {

		updates["is_service_enabled"] = *req.IsServiceEnabled
	}
	if req.InviteCode != nil {

		inviteCode := strings.TrimSpace(*req.InviteCode)

		if !validateOfficialInviteCode(inviteCode) {

			response.Error(c, http.StatusBadRequest, "自定义邀请码需为6-12位字母或数字")

			return

		}
		var inviteCount int64

		query := h.db.Model(&models.InviteCode{}).Where("code = ?", inviteCode)

		if official.UserID != 0 {

			query = query.Where("service_user_id <> ?", official.UserID)

		}

		query.Count(&inviteCount)

		if inviteCount > 0 {

			response.Error(c, http.StatusBadRequest, "自定义邀请码已存在")

			return

		}
		inviteCodeToUpdate = inviteCode
	}
	if len(updates) == 0 && inviteCodeToUpdate == "" {

		response.BadRequest(c, "没有可更新字段")

		return
	}
	tx := h.db.Begin()
	if tx.Error != nil {

		response.Error(c, http.StatusInternalServerError, "更新失败")

		return
	}
	if err := tx.Model(&official).Updates(updates).Error; err != nil {

		tx.Rollback()

		response.Error(c, http.StatusInternalServerError, "更新失败")

		return
	}
	if inviteCodeToUpdate != "" {
		var serviceUser models.User

		if err := tx.Select("id", "uuid").First(&serviceUser, official.UserID).Error; err != nil {

			tx.Rollback()

			response.Error(c, http.StatusInternalServerError, "更新失败")

			return

		}

		if _, err := getOrCreateServiceInviteCode(tx, &serviceUser, "官方客服专属邀请码", inviteCodeToUpdate); err != nil {

			tx.Rollback()

			response.Error(c, http.StatusInternalServerError, "更新失败")

			return

		}
	}
	if enabled, ok := updates["is_service_enabled"]; ok {

		if enabled.(bool) {
			var serviceUser models.User

			if err := tx.Select("id", "uuid").First(&serviceUser, official.UserID).Error; err != nil {

				tx.Rollback()

				response.Error(c, http.StatusInternalServerError, "更新失败")

				return

			}

			if _, err := getOrCreateServiceInviteCode(tx, &serviceUser, "官方客服专属邀请码", ""); err != nil {

				tx.Rollback()

				response.Error(c, http.StatusInternalServerError, "更新失败")

				return

			}

		} else {

			if err := tx.Model(&models.InviteCode{}).Where("service_user_id = ?", official.UserID).Update("status", 0).Error; err != nil {

				tx.Rollback()

				response.Error(c, http.StatusInternalServerError, "更新失败")

				return

			}

		}
	}
	if err := tx.Commit().Error; err != nil {

		tx.Rollback()

		response.Error(c, http.StatusInternalServerError, "更新失败")

		return
	}
	response.SuccessWithMessage(c, "更新成功", nil)
} // RemoveOfficialUser 移除官方用户
func (h *SettingHandler) RemoveOfficialUser(c *gin.Context) {
	id := c.Param("id")
	var official models.OfficialUser
	if err := h.db.Where("id = ?", id).First(&official).Error; err != nil {

		response.Error(c, http.StatusNotFound, "官方用户不存在")

		return
	}
	tx := h.db.Begin()
	if tx.Error != nil {

		response.Error(c, http.StatusInternalServerError, "删除失败")

		return
	}
	// 移除官方用户后，停用其专属邀请码，避免继续注册绑定
	if err := tx.Model(&models.InviteCode{}).Where("service_user_id = ?", official.UserID).Update("status", 0).Error; err != nil {

		tx.Rollback()

		response.Error(c, http.StatusInternalServerError, "删除失败")

		return
	}
	result := tx.Delete(&models.OfficialUser{}, id)
	if result.Error != nil {

		tx.Rollback()

		response.Error(c, http.StatusInternalServerError, "删除失败")

		return
	}
	if result.RowsAffected == 0 {

		tx.Rollback()

		response.Error(c, http.StatusNotFound, "官方用户不存在")

		return
	}
	if err := tx.Commit().Error; err != nil {

		tx.Rollback()

		response.Error(c, http.StatusInternalServerError, "删除失败")

		return
	}
	response.SuccessWithMessage(c, "已移除", nil)
} // GetOfficialUserInvitees 获取某官方客服通过邀请码注册的用户列表
func (h *SettingHandler) GetOfficialUserInvitees(c *gin.Context) {
	id := c.Param("id")
	var official models.OfficialUser
	if err := h.db.Select("id", "user_id").Where("id = ?", id).First(&official).Error; err != nil {

		response.Error(c, http.StatusNotFound, "官方用户不存在")

		return
	}
	type InviteeItem struct {
		UsageID uint64 `json:"usage_id"`

		UserID uint64 `json:"user_id"`

		UserUUID string `json:"user_uuid"`

		Username string `json:"username"`

		Nickname string `json:"nickname"`

		Avatar string `json:"avatar"`

		InviteCode string `json:"invite_code"`

		RegisteredAt time.Time `json:"registered_at"`
	}
	latestUsageSubQuery := h.db.Table("invite_code_usages").
		Select("MAX(id)").
		Group("user_id")
	var list []InviteeItem
	if err := h.db.Table("invite_code_usages AS icu").
		Select(` 


icu.id AS usage_id, 


icu.user_id AS user_id, 


u.uuid AS user_uuid, 


u.username AS username, 


u.nickname AS nickname, 


u.avatar AS avatar, 


ic.code AS invite_code, 


icu.created_at AS registered_at 

`).
		Joins("JOIN invite_codes ic ON ic.id = icu.invite_code_id").
		Joins("JOIN users u ON u.id = icu.user_id AND u.deleted_at IS NULL").
		Where("icu.id IN (?)", latestUsageSubQuery).
		Where("ic.service_user_id = ?", official.UserID).
		Order("icu.created_at DESC").
		Scan(&list).Error; err != nil {

		response.Error(c, http.StatusInternalServerError, "获取失败")

		return
	}
	response.Success(c, gin.H{

		"total": len(list),

		"list": list,
	})
} // ==================== 官方群组管理 ====================  // GetOfficialGroups 获取官方群组列表
func (h *SettingHandler) GetOfficialGroups(c *gin.Context) {
	var officials []models.OfficialGroup
	h.db.Order("sort_order ASC, created_at ASC").Find(&officials)
	type OfficialGroupDetail struct {
		models.OfficialGroup

		Name string `json:"name"`

		Username string `json:"username"`

		Avatar string `json:"avatar"`

		MemberCount int `json:"member_count"`
	}
	var result []OfficialGroupDetail
	for _, o := range officials {
		var chat models.Chat

		if h.db.First(&chat, o.ChatID).Error == nil {

			result = append(result, OfficialGroupDetail{

				OfficialGroup: o,

				Name: chat.Name,

				Username: chat.Username,

				Avatar: chat.Avatar,

				MemberCount: chat.MemberCount,
			})

		}
	}
	response.Success(c, result)
} // AddOfficialGroup 添加官方群组（支持 UUID 或用户名）
func (h *SettingHandler) AddOfficialGroup(c *gin.Context) {
	var req struct {
		ChatUUID string `json:"chat_uuid"` // UUID 或用户名

		Username string `json:"username"` // 群组用户名

		Remark string `json:"remark"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {

		response.Error(c, http.StatusBadRequest, "参数错误")

		return
	}
	req.ChatUUID = strings.TrimSpace(req.ChatUUID)
	req.Username = strings.TrimSpace(req.Username)
	req.Remark = strings.TrimSpace(req.Remark)
	if !validateGeneralRemark(req.Remark, 200) {

		response.Error(c, http.StatusBadRequest, "备注不能超过200个字符")

		return
	}
	// 优先使用 username，其次使用 chat_uuid
	identifier := req.Username
	if identifier == "" {

		identifier = req.ChatUUID
	}
	if identifier == "" {

		response.Error(c, http.StatusBadRequest, "请提供群组用户名或UUID")

		return
	}
	var chat models.Chat
	// 先尝试用 UUID 查询，再尝试用 username 查询
	if err := h.db.Where("uuid = ? AND type = 2", identifier).First(&chat).Error; err != nil {

		// UUID 查询失败，尝试用 username 查询

		if err := h.db.Where("username = ? AND type = 2", identifier).First(&chat).Error; err != nil {

			response.Error(c, http.StatusNotFound, "群组不存在")

			return

		}
	}
	var count int64
	h.db.Model(&models.OfficialGroup{}).Where("chat_id = ?", chat.ID).Count(&count)
	if count > 0 {

		response.Error(c, http.StatusBadRequest, "该群组已是官方群组")

		return
	}
	official := models.OfficialGroup{

		ChatID: chat.ID,

		ChatUUID: chat.UUID,

		Remark: req.Remark,
	}
	if err := h.db.Create(&official).Error; err != nil {

		response.Error(c, http.StatusInternalServerError, "添加失败")

		return
	}
	response.SuccessWithMessage(c, "已添加官方群组", gin.H{

		"id": official.ID,

		"chat_id": chat.ID,

		"uuid": chat.UUID,

		"name": chat.Name,
	})
} // RemoveOfficialGroup 移除官方群组
func (h *SettingHandler) RemoveOfficialGroup(c *gin.Context) {
	id := c.Param("id")
	result := h.db.Delete(&models.OfficialGroup{}, id)
	if result.Error != nil {

		response.Error(c, http.StatusInternalServerError, "删除失败")

		return
	}
	if result.RowsAffected == 0 {

		response.Error(c, http.StatusNotFound, "官方群组不存在")

		return
	}
	response.SuccessWithMessage(c, "已移除", nil)
} // ==================== 官方频道管理 ====================  // GetOfficialChannels 获取官方频道列表
func (h *SettingHandler) GetOfficialChannels(c *gin.Context) {
	var officials []models.OfficialChannel
	h.db.Order("sort_order ASC, created_at ASC").Find(&officials)
	type OfficialChannelDetail struct {
		models.OfficialChannel

		Name string `json:"name"`

		Username string `json:"username"`

		Avatar string `json:"avatar"`

		MemberCount int `json:"member_count"`
	}
	var result []OfficialChannelDetail
	for _, o := range officials {
		var chat models.Chat

		if h.db.First(&chat, o.ChatID).Error == nil {

			result = append(result, OfficialChannelDetail{

				OfficialChannel: o,

				Name: chat.Name,

				Username: chat.Username,

				Avatar: chat.Avatar,

				MemberCount: chat.MemberCount,
			})

		}
	}
	response.Success(c, result)
} // AddOfficialChannel 添加官方频道（支持 UUID 或用户名）
func (h *SettingHandler) AddOfficialChannel(c *gin.Context) {
	var req struct {
		ChatUUID string `json:"chat_uuid"` // UUID 或用户名

		Username string `json:"username"` // 频道用户名

		Remark string `json:"remark"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {

		response.Error(c, http.StatusBadRequest, "参数错误")

		return
	}
	req.ChatUUID = strings.TrimSpace(req.ChatUUID)
	req.Username = strings.TrimSpace(req.Username)
	req.Remark = strings.TrimSpace(req.Remark)
	if !validateGeneralRemark(req.Remark, 200) {

		response.Error(c, http.StatusBadRequest, "备注不能超过200个字符")

		return
	}
	// 优先使用 username，其次使用 chat_uuid
	identifier := req.Username
	if identifier == "" {

		identifier = req.ChatUUID
	}
	if identifier == "" {

		response.Error(c, http.StatusBadRequest, "请提供频道用户名或UUID")

		return
	}
	var chat models.Chat
	// 先尝试用 UUID 查询，再尝试用 username 查询
	if err := h.db.Where("uuid = ? AND type = 3", identifier).First(&chat).Error; err != nil {

		// UUID 查询失败，尝试用 username 查询

		if err := h.db.Where("username = ? AND type = 3", identifier).First(&chat).Error; err != nil {

			response.Error(c, http.StatusNotFound, "频道不存在")

			return

		}
	}
	var count int64
	h.db.Model(&models.OfficialChannel{}).Where("chat_id = ?", chat.ID).Count(&count)
	if count > 0 {

		response.Error(c, http.StatusBadRequest, "该频道已是官方频道")

		return
	}
	official := models.OfficialChannel{

		ChatID: chat.ID,

		ChatUUID: chat.UUID,

		Remark: req.Remark,
	}
	if err := h.db.Create(&official).Error; err != nil {

		response.Error(c, http.StatusInternalServerError, "添加失败")

		return
	}
	response.SuccessWithMessage(c, "已添加官方频道", gin.H{

		"id": official.ID,

		"chat_id": chat.ID,

		"uuid": chat.UUID,

		"name": chat.Name,
	})
} // RemoveOfficialChannel 移除官方频道
func (h *SettingHandler) RemoveOfficialChannel(c *gin.Context) {
	id := c.Param("id")
	result := h.db.Delete(&models.OfficialChannel{}, id)
	if result.Error != nil {

		response.Error(c, http.StatusInternalServerError, "删除失败")

		return
	}
	if result.RowsAffected == 0 {

		response.Error(c, http.StatusNotFound, "官方频道不存在")

		return
	}
	response.SuccessWithMessage(c, "已移除", nil)
} // ==================== App端接口（无需管理员权限） ====================  // GetAppSettings 获取App端需要的系统设置（公开接口）
func (h *SettingHandler) GetAppSettings(c *gin.Context) {
	// 公开接口必须由下方响应字段显式放行，不能把 settingMap 整体返回，以免泄露密钥类设置。
	var settings []models.SystemSetting
	h.db.Find(&settings)
	settingMap := make(map[string]string)
	for _, s := range settings {

		settingMap[s.Key] = s.Value
	}
	// 获取启用中的官方用户UUID列表
	var officialUsers []models.OfficialUser
	h.db.Where("is_service_enabled = ?", true).Find(&officialUsers)
	officialUserUUIDs := make([]string, 0, len(officialUsers))
	for _, u := range officialUsers {

		officialUserUUIDs = append(officialUserUUIDs, u.UserUUID)
	}
	// 获取官方群组UUID列表
	var officialGroups []models.OfficialGroup
	h.db.Find(&officialGroups)
	officialGroupUUIDs := make([]string, 0, len(officialGroups))
	for _, g := range officialGroups {

		officialGroupUUIDs = append(officialGroupUUIDs, g.ChatUUID)
	}
	// 获取官方频道UUID列表
	var officialChannels []models.OfficialChannel
	h.db.Find(&officialChannels)
	officialChannelUUIDs := make([]string, 0, len(officialChannels))
	for _, c := range officialChannels {

		officialChannelUUIDs = append(officialChannelUUIDs, c.ChatUUID)
	}
	// 解析文件大小限制（默认值）
	maxImageSize := 10
	maxVideoSize := 100
	maxFileSize := 100
	maxVoiceSize := 20
	if v, err := strconv.Atoi(settingMap[models.SettingMaxImageSize]); err == nil && v > 0 {

		maxImageSize = v
	}
	if v, err := strconv.Atoi(settingMap[models.SettingMaxVideoSize]); err == nil && v > 0 {

		maxVideoSize = v
	}
	if v, err := strconv.Atoi(settingMap[models.SettingMaxFileSize]); err == nil && v > 0 {

		maxFileSize = v
	}
	if v, err := strconv.Atoi(settingMap[models.SettingMaxVoiceSize]); err == nil && v > 0 {

		maxVoiceSize = v
	}
	// 消息撤回时限（分钟，默认2）
	revokeMessageMinutes := 2
	if v, err := strconv.Atoi(settingMap[models.SettingRevokeMessageMinutes]); err == nil && v > 0 {

		revokeMessageMinutes = v
	}
	directUploadConfig := services.LoadChatImageDirectUploadConfig(h.db)
	response.Success(c, gin.H{

		// App版本

		"app_version_ios": settingMap[models.SettingAppVersionIOS],

		"app_version_android": settingMap[models.SettingAppVersionAndroid],

		"latest_version_ios": firstNonEmptySetting(settingMap[models.SettingLatestVersionIOS], settingMap[models.SettingAppVersionIOS]),

		"latest_version_android": firstNonEmptySetting(settingMap[models.SettingLatestVersionAndroid], settingMap[models.SettingAppVersionAndroid]),

		"system_name": settingMap[models.SettingSystemName],

		"system_version": settingMap[models.SettingSystemVersion],

		"support_online_url": settingMap[models.SettingSupportOnlineURL],

		"support_qq": settingMap[models.SettingSupportQQ],

		"splash_enabled": isSystemSettingTrue(settingMap[models.SettingSplashEnabled]),

		"splash_image_url": settingMap[models.SettingSplashImageURL],

		"splash_duration_ms": func() int {

			if v, err := strconv.Atoi(settingMap[models.SettingSplashDurationMs]); err == nil && v > 0 {

				if v < 800 {

					return 800

				}

				if v > 8000 {

					return 8000

				}

				return v

			}

			return 3000

		}(),

		"register_base_url": resolveRegisterBaseURL(h.db),

		"app_force_update": isSystemSettingTrue(settingMap[models.SettingAppForceUpdate]),

		"app_update_url": settingMap[models.SettingAppUpdateURL],

		"app_update_url_ios": firstNonEmptySetting(settingMap[models.SettingAppUpdateURLIOS], settingMap[models.SettingAppUpdateURL]),

		"app_update_url_android": firstNonEmptySetting(settingMap[models.SettingAppUpdateURLAndroid], settingMap[models.SettingAppUpdateURL]),

		"min_supported_version_ios": settingMap[models.SettingMinSupportedVersionIOS],

		"min_supported_version_android": settingMap[models.SettingMinSupportedVersionAndroid],

		"app_update_message": settingMap[models.SettingAppUpdateMessage],

		// 功能开关

		"allow_register": !isSystemSettingFalse(settingMap[models.SettingAllowRegister]), // 默认允许

		"allow_quick_register": !isSystemSettingFalse(settingMap[models.SettingAllowRegister]) &&

			!isSystemSettingTrue(settingMap[models.SettingRequireInviteCode]) &&

			isSystemSettingTrue(settingMap[models.SettingAllowQuickRegister]),

		"force_keep_alive_enabled": isSystemSettingTrue(settingMap[models.SettingForceKeepAliveEnabled]),

		"require_invite_code": isSystemSettingTrue(settingMap[models.SettingRequireInviteCode]),

		"require_gender_on_register": !isSystemSettingFalse(settingMap[models.SettingRequireGenderOnRegister]), // 默认必选

		"require_phone_bind": isSystemSettingTrue(settingMap[models.SettingRequirePhoneBind]),

		"enable_moment_post": !isSystemSettingFalse(settingMap[models.SettingEnableMomentPost]), // 默认允许发布

		"moment_post_review_enabled": isSystemSettingTrue(settingMap[models.SettingMomentPostReviewEnabled]),

		"ios_compliance": normalizeIOSComplianceConfig(settingMap[models.SettingIOSCompliance]),

		"new_user_follow_official": isSystemSettingTrue(settingMap[models.SettingNewUserFollowOfficial]),

		"invite_register_bind_only": isSystemSettingTrue(settingMap[models.SettingInviteRegisterBindOnly]),

		"new_user_join_group": isSystemSettingTrue(settingMap[models.SettingNewUserJoinGroup]),

		"new_user_join_channel": isSystemSettingTrue(settingMap[models.SettingNewUserJoinChannel]),

		"group_invite_require_friend": isSystemSettingTrue(settingMap[models.SettingGroupInviteRequireFriend]),

		"friend_add_mode": normalizeFriendAddMode(settingMap[models.SettingFriendAddMode]),

		"custom_portal_enabled": isSystemSettingTrue(settingMap[models.SettingCustomPortalEnabled]),

		"custom_portal_title": settingMap[models.SettingCustomPortalTitle],

		"custom_portal_url": settingMap[models.SettingCustomPortalURL],

		"custom_portal_icon_url": settingMap[models.SettingCustomPortalIconURL],

		"burn_after_read_enabled": !isSystemSettingFalse(settingMap[models.SettingBurnAfterReadEnabled]),

		"chat_attachment_menu": chatAttachmentMenuSettingValue(settingMap[models.SettingChatAttachmentMenu]),

		"message_crypto_mode": normalizeMessageCryptoMode(settingMap[models.SettingMessageCryptoMode]),

		"voice_transcription_enabled": voiceTranscriptionConfigured(settingMap),

		"chat_image_direct_upload": directUploadConfig,

		// 官方用户/群组/频道

		"official_users": officialUserUUIDs,

		"official_groups": officialGroupUUIDs,

		"official_channels": officialChannelUUIDs,

		// 文件大小限制 (MB)

		"max_image_size": maxImageSize,

		"max_video_size": maxVideoSize,

		"max_file_size": maxFileSize,

		"max_voice_size": maxVoiceSize,

		// 消息撤回时限（分钟）

		"revoke_message_minutes": revokeMessageMinutes,

		// 短信绑定：后台已配置且可发验证码时 App 可展示绑定入口

		"sms_bind_ready": config.GlobalConfig != nil && services.SMSSendReady(h.db, config.GlobalConfig.SMS, config.GlobalConfig.Server.Mode),

		"email_registration_ready": config.GlobalConfig != nil && services.EmailSendReady(config.GlobalConfig.Email, config.GlobalConfig.Server.Mode),
	})
} // CheckUserOfficial 检查用户是否是官方用户
func (h *SettingHandler) CheckUserOfficial(c *gin.Context) {
	userUUID := c.Param("uuid")
	var count int64
	h.db.Model(&models.OfficialUser{}).
		Where("user_uuid = ? AND is_service_enabled = ?", userUUID, true).
		Count(&count)
	response.Success(c, gin.H{

		"is_official": count > 0,
	})
} // CheckChatOfficial 检查群组/频道是否是官方
func (h *SettingHandler) CheckChatOfficial(c *gin.Context) {
	chatUUID := c.Param("uuid")
	var groupCount, channelCount int64
	h.db.Model(&models.OfficialGroup{}).Where("chat_uuid = ?", chatUUID).Count(&groupCount)
	h.db.Model(&models.OfficialChannel{}).Where("chat_uuid = ?", chatUUID).Count(&channelCount)
	response.Success(c, gin.H{

		"is_official": groupCount > 0 || channelCount > 0,
	})
} // SyncOfficialContacts 同步官方用户到联系人（用户调用）
func (h *SettingHandler) SyncOfficialContacts(c *gin.Context) {
	userUUID := strings.TrimSpace(c.GetString("user_id"))
	if userUUID == "" {

		response.Unauthorized(c, "未登录")

		return
	}
	// 查找当前用户
	var user models.User
	if err := h.db.Where("uuid = ?", userUUID).First(&user).Error; err != nil {

		response.Error(c, http.StatusUnauthorized, "用户不存在")

		return
	}
	var followOfficialSetting models.SystemSetting
	if err := h.db.Where("`key` = ?", models.SettingNewUserFollowOfficial).First(&followOfficialSetting).Error; err != nil ||

		!isSystemSettingTrue(followOfficialSetting.Value) {

		response.Success(c, gin.H{

			"added": 0,

			"message": "未开启新用户强制关注官方用户",
		})

		return
	}
	// 获取启用中的官方用户
	var officialUsers []models.OfficialUser
	officialQuery := h.db.Where("is_service_enabled = ?", true)
	var bindOnlySetting models.SystemSetting
	if err := h.db.Where("`key` = ?", models.SettingInviteRegisterBindOnly).First(&bindOnlySetting).Error; err == nil &&

		isSystemSettingTrue(bindOnlySetting.Value) {
		var serviceUserIDs []uint64

		_ = h.db.Table("invite_code_usages AS icu").
			Joins("JOIN invite_codes ic ON ic.id = icu.invite_code_id").
			Where("icu.user_id = ?", user.ID).
			Distinct().
			Pluck("ic.service_user_id", &serviceUserIDs).Error

		if len(serviceUserIDs) > 0 {

			officialQuery = officialQuery.Where("user_id IN ?", serviceUserIDs)

		}
	}
	officialQuery.Find(&officialUsers)
	if len(officialUsers) == 0 {

		response.Success(c, gin.H{

			"added": 0,

			"message": "暂无官方用户",
		})

		return
	}
	tx := h.db.Begin()
	if tx.Error != nil {

		response.Error(c, http.StatusInternalServerError, "同步联系人失败")

		return
	}
	addedCount := 0
	now := time.Now()
	for _, official := range officialUsers {

		// 跳过自己

		if official.UserID == user.ID {

			continue

		}
		pairAdded := false

		changed1, err := ensureContactRelation(tx, user.ID, official.UserID, now)

		if err != nil {

			tx.Rollback()

			response.Error(c, http.StatusInternalServerError, "同步联系人失败")

			return

		}

		if changed1 {

			pairAdded = true

		}
		changed2, err := ensureContactRelation(tx, official.UserID, user.ID, now)

		if err != nil {

			tx.Rollback()

			response.Error(c, http.StatusInternalServerError, "同步联系人失败")

			return

		}

		if changed2 {

			pairAdded = true

		}

		if pairAdded {

			addedCount++

		}
	}
	if err := tx.Commit().Error; err != nil {

		tx.Rollback()

		response.Error(c, http.StatusInternalServerError, "同步联系人失败")

		return
	}
	response.Success(c, gin.H{

		"added": addedCount,

		"message": fmt.Sprintf("已添加 %d 个官方用户为好友", addedCount),
	})
} // GetMyOfficialServiceProfile 获取当前登录用户的官方客服配置
func (h *SettingHandler) GetMyOfficialServiceProfile(c *gin.Context) {
	userUUID := strings.TrimSpace(c.GetString("user_id"))
	if userUUID == "" {

		response.Unauthorized(c, "未登录")

		return
	}
	var official models.OfficialUser
	if err := h.db.Where("user_uuid = ?", userUUID).First(&official).Error; err != nil {

		if err == gorm.ErrRecordNotFound {

			response.Success(c, gin.H{"is_official": false})

			return

		}

		response.Error(c, http.StatusInternalServerError, "获取失败")

		return
	}
	welcome := strings.TrimSpace(official.WelcomeMessage)
	if welcome == "" {

		welcome = defaultServiceWelcomeMessage()
	}
	response.Success(c, gin.H{

		"is_official": true,

		"official_user_id": official.ID,

		"welcome_message": welcome,

		"is_service_enabled": official.IsServiceEnabled,
	})
} // UpdateMyOfficialServiceProfile 更新当前登录用户的官方客服欢迎语
func (h *SettingHandler) UpdateMyOfficialServiceProfile(c *gin.Context) {
	userUUID := strings.TrimSpace(c.GetString("user_id"))
	if userUUID == "" {

		response.Unauthorized(c, "未登录")

		return
	}
	var req struct {
		WelcomeMessage string `json:"welcome_message"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {

		response.BadRequest(c, "参数错误")

		return
	}
	var official models.OfficialUser
	if err := h.db.Where("user_uuid = ?", userUUID).First(&official).Error; err != nil {

		if err == gorm.ErrRecordNotFound {

			response.Forbidden(c, "仅官方客服可操作")

			return

		}

		response.Error(c, http.StatusInternalServerError, "更新失败")

		return
	}
	msg := strings.TrimSpace(req.WelcomeMessage)
	if msg != "" && !validateOfficialWelcomeMessage(msg) {

		response.Error(c, http.StatusBadRequest, "欢迎语不能超过500个字符")

		return
	}
	if msg == "" {

		msg = defaultServiceWelcomeMessage()
	}
	if err := h.db.Model(&official).Update("welcome_message", msg).Error; err != nil {

		response.Error(c, http.StatusInternalServerError, "更新失败")

		return
	}
	response.SuccessWithMessage(c, "欢迎语已更新", gin.H{

		"welcome_message": msg,
	})
} // ==================== 公开协议 API（无需登录） ====================  // GetUserAgreement 获取用户协议
func (h *SettingHandler) GetUserAgreement(c *gin.Context) {
	var setting models.SystemSetting
	if err := h.db.Where("`key` = ?", models.SettingUserAgreement).First(&setting).Error; err != nil {

		// 返回默认协议内容

		response.Success(c, gin.H{

			"title": "用户协议",

			"content": getDefaultUserAgreement(),

			"updated_at": nil,
		})

		return
	}
	response.Success(c, gin.H{

		"title": "用户协议",

		"content": setting.Value,

		"updated_at": setting.UpdatedAt,
	})
} // GetPrivacyPolicy 获取隐私政策
func (h *SettingHandler) GetPrivacyPolicy(c *gin.Context) {
	var setting models.SystemSetting
	if err := h.db.Where("`key` = ?", models.SettingPrivacyPolicy).First(&setting).Error; err != nil {

		// 返回默认隐私政策内容

		response.Success(c, gin.H{

			"title": "隐私政策",

			"content": getDefaultPrivacyPolicy(),

			"updated_at": nil,
		})

		return
	}
	response.Success(c, gin.H{

		"title": "隐私政策",

		"content": setting.Value,

		"updated_at": setting.UpdatedAt,
	})
} // 默认用户协议
func getDefaultUserAgreement() string {
	return `# 用户协议  欢迎使用通用IM！  ## 一、服务条款的接受  在使用本应用前，请您仔细阅读本协议的全部内容。如果您不同意本协议的任何条款，请不要使用本应用。使用本应用即表示您同意接受本协议的所有条款。  ## 二、用户账号  1. 您需要注册账号才能使用本应用的全部功能 2. 您应当妥善保管账号信息，对账号下的所有行为负责 3. 禁止将账号转让、出借给他人使用  ## 三、用户行为规范  在使用本应用时，您承诺： 1. 不发布违法、有害、威胁、辱骂、骚扰、诽谤、侵权内容 2. 不发布垃圾信息或广告 3. 不进行任何可能损害本应用正常运营的行为 4. 遵守中华人民共和国相关法律法规  ## 四、知识产权  本应用的所有内容，包括但不限于文字、图片、软件、音频、视频等，均受著作权法保护。未经许可，不得复制、修改、传播。  ## 五、免责声明  1. 本应用按"现状"提供服务，不提供任何明示或暗示的担保 2. 对于用户发布的内容，本应用不承担任何责任 3. 因不可抗力导致的服务中断，本应用不承担责任  ## 六、协议修改  我们保留随时修改本协议的权利。修改后的协议一经发布即生效。  ## 七、联系我们  如有任何问题，请通过应用内的反馈功能联系我们。  --- 最后更新日期：2024年1月`
} // 默认隐私政策
func getDefaultPrivacyPolicy() string {
	return `# 隐私政策  本隐私政策说明我们如何收集、使用和保护您的个人信息。  ## 一、信息收集  我们可能收集以下类型的信息：  ### 1. 账号信息 - 用户名、昵称 - 头像 - 个人简介  ### 2. 设备信息 - 设备型号 - 操作系统版本 - 设备标识符  ### 3. 使用信息 - 登录时间 - 功能使用情况  ### 4. 通讯内容 - 您发送的消息（端对端加密传输） - 分享的媒体文件  ## 二、信息使用  我们使用收集的信息用于： 1. 提供、维护和改进服务 2. 发送通知和更新 3. 保障账号安全 4. 遵守法律法规要求  ## 三、信息保护  我们采取以下措施保护您的信息： 1. 使用加密技术保护数据传输 2. 限制员工访问用户数据的权限 3. 定期审查安全措施  ## 四、信息共享  除以下情况外，我们不会与第三方共享您的个人信息： 1. 经您明确同意 2. 法律法规要求 3. 保护我们或他人的权益  ## 五、您的权利  您有权： 1. 访问您的个人信息 2. 更正不准确的信息 3. 删除您的账号和数据 4. 撤回同意  ## 六、Cookie 和类似技术  我们可能使用 Cookie 来改善用户体验和分析使用情况。  ## 七、未成年人保护  本应用不面向未满 14 周岁的儿童。如果您是未成年人，请在监护人指导下使用本应用。  ## 八、隐私政策更新  我们可能不时更新本隐私政策。重大变更时，我们会通过应用内通知您。  ## 九、联系我们  如对本隐私政策有任何疑问，请通过应用内的反馈功能联系我们。  --- 最后更新日期：2024年1月`
}
