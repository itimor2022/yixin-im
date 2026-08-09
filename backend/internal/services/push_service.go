// 文件用途：实现可复用的后端业务服务和领域逻辑。
// 核心逻辑：协调数据库、缓存、队列和外部服务，集中处理事务、幂等、重试和错误传播。

package services

import (
	"bytes"
	"context"
	"crypto/ecdsa"
	"crypto/rsa"
	"crypto/sha256"
	"crypto/tls"
	"crypto/x509"
	"encoding/hex"
	"encoding/json"
	"encoding/pem"
	"fmt"
	webpush "github.com/SherClockHolmes/webpush-go"
	"github.com/golang-jwt/jwt/v5"
	"golang.org/x/net/http2"
	"gorm.io/gorm" // APNsPayload is the APNs notification body.
	"io"
	"log"
	"net/http"
	"net/url"
	"sort"
	"strconv"
	"strings"
	"sync"
	"time"
	"genericim/internal/models"
	"genericim/internal/textutil"
)

type APNsPayload struct {
	Aps  APNsAps         `json:"aps"`
	Data json.RawMessage `json:"data,omitempty"`
}
type APNsAps struct {
	Alert            APNsAlert `json:"alert"`
	Sound            string    `json:"sound,omitempty"`
	Badge            *int      `json:"badge,omitempty"`
	MutableContent   int       `json:"mutable-content,omitempty"`
	ContentAvailable int       `json:"content-available,omitempty"`
}
type APNsAlert struct {
	Title    string `json:"title,omitempty"`
	Subtitle string `json:"subtitle,omitempty"`
	Body     string `json:"body,omitempty"`
}

// APNsConfig is loaded from system settings.
type APNsConfig struct {
	Enabled     bool
	BundleID    string
	KeyID       string
	TeamID      string
	AuthKey     *ecdsa.PrivateKey
	Environment string // development or production
}
type APNsSendOptions struct {
	PushType    string
	TopicSuffix string
}

// AndroidPushConfig stores multi-channel Android push settings.
type AndroidPushConfig struct {
	FCMEnabled            bool
	FCMProjectID          string
	FCMServiceAccountJSON string
	HMSEnabled            bool
	HMSAppID              string
	HMSAppSecret          string
	JPushEnabled          bool
	JPushAppKey           string
	JPushMasterSecret     string
	DefaultTitle          string
	ChatPushEnabled       bool
	FriendPushEnabled     bool
	SystemPushEnabled     bool
	ChatCategory          string
	ServiceCategory       string
	MarketingCategory     string
	PrimaryProvider       string
	FallbackProvider      string
	RateLimitPerMinute    int
	MarketingDailyLimit   int
	QuietHoursEnabled     bool
	QuietHoursStart       string
	QuietHoursEnd         string
	XiaomiEnabled         bool
	XiaomiPackageName     string
	XiaomiAppSecret       string
	OppoEnabled           bool
	OppoAppKey            string
	OppoAppSecret         string
}
type WebPushConfig struct {
	Enabled         bool
	VAPIDPublicKey  string
	VAPIDPrivateKey string
	Subject         string
	TTL             int
}
type fcmServiceAccount struct {
	ProjectID   string `json:"project_id"`
	PrivateKey  string `json:"private_key"`
	ClientEmail string `json:"client_email"`
	TokenURI    string `json:"token_uri"`
}

// PushService sends APNs and Android vendor push notifications.
type PushService struct {
	db            *gorm.DB
	httpClient    *http.Client
	apnsClient    *http.Client
	config        *APNsConfig
	androidConfig AndroidPushConfig
	webPushConfig WebPushConfig
	configMu      sync.RWMutex
	// APNs JWT cache
	jwtToken  string
	jwtExpiry time.Time
	// Android channel token caches
	fcmAccessToken  string
	fcmTokenExpiry  time.Time
	hmsAccessToken  string
	hmsTokenExpiry  time.Time
	oppoAuthToken   string
	oppoTokenExpiry time.Time
	oppoAPIHost     string
}

// NewPushService creates push service instance.
func NewPushService(db *gorm.DB) *PushService {
	apnsTransport := &http2.Transport{

		TLSClientConfig: &tls.Config{

			MinVersion: tls.VersionTLS12,
		},
	}
	service := &PushService{

		db: db,

		httpClient: &http.Client{

			Timeout: 30 * time.Second,
		},

		apnsClient: &http.Client{

			Transport: apnsTransport,

			Timeout: 30 * time.Second,
		},
	}
	service.ReloadConfig()
	log.Printf("[Push] Push service initialized")
	return service
}

// ReloadConfig reloads APNs and Android push settings from DB.
func (s *PushService) ReloadConfig() {
	config := &APNsConfig{}
	androidConfig := AndroidPushConfig{

		DefaultTitle: "通用IM",

		ChatPushEnabled: true,

		FriendPushEnabled: true,

		SystemPushEnabled: true,

		ChatCategory: "chat_message",

		ServiceCategory: "service_notice",

		MarketingCategory: "marketing",

		PrimaryProvider: PushChannelJPush,

		FallbackProvider: "none",

		QuietHoursStart: "22:00",

		QuietHoursEnd: "08:00",
	}
	webPushConfig := WebPushConfig{

		Enabled: true,

		Subject: "mailto:admin@example.com",

		TTL: 24 * 60 * 60,
	}
	var settings []models.SystemSetting
	s.db.Where("`key` IN ?", []string{

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
	}).Find(&settings)
	for _, setting := range settings {

		switch setting.Key {

		case models.SettingAPNsEnabled:

			config.Enabled = setting.Value == "true" || setting.Value == "1"

		case models.SettingAPNsBundleID:

			config.BundleID = setting.Value

		case models.SettingAPNsKeyID:

			config.KeyID = setting.Value

		case models.SettingAPNsTeamID:

			config.TeamID = setting.Value

		case models.SettingAPNsAuthKey:

			if setting.Value != "" {

				key, err := parseAuthKey([]byte(setting.Value))

				if err != nil {

					log.Printf("[Push] Failed to parse APNs auth key: %v", err)

				} else {

					config.AuthKey = key

				}

			}

		case models.SettingAPNsEnvironment:

			config.Environment = setting.Value

		case models.SettingFCMEnabled:

			androidConfig.FCMEnabled = setting.Value == "true" || setting.Value == "1"

		case models.SettingFCMProjectID:

			androidConfig.FCMProjectID = setting.Value

		case models.SettingFCMServiceAccountJSON:

			androidConfig.FCMServiceAccountJSON = setting.Value

		case models.SettingHMSEnabled:

			androidConfig.HMSEnabled = setting.Value == "true" || setting.Value == "1"

		case models.SettingHMSAppID:

			androidConfig.HMSAppID = setting.Value

		case models.SettingHMSAppSecret:

			androidConfig.HMSAppSecret = setting.Value

		case models.SettingJPushEnabled:

			androidConfig.JPushEnabled = setting.Value == "true" || setting.Value == "1"

		case models.SettingJPushAppKey:

			androidConfig.JPushAppKey = strings.TrimSpace(setting.Value)

		case models.SettingJPushMasterSecret:

			androidConfig.JPushMasterSecret = strings.TrimSpace(setting.Value)

		case models.SettingPushDefaultTitle:

			androidConfig.DefaultTitle = strings.TrimSpace(setting.Value)

		case models.SettingPushChatEnabled:

			androidConfig.ChatPushEnabled = setting.Value != "false" && setting.Value != "0"

		case models.SettingPushFriendEnabled:

			androidConfig.FriendPushEnabled = setting.Value != "false" && setting.Value != "0"

		case models.SettingPushSystemEnabled:

			androidConfig.SystemPushEnabled = setting.Value != "false" && setting.Value != "0"

		case models.SettingPushCategoryChat:

			if value := strings.TrimSpace(setting.Value); value != "" {

				androidConfig.ChatCategory = value

			}

		case models.SettingPushCategoryService:

			if value := strings.TrimSpace(setting.Value); value != "" {

				androidConfig.ServiceCategory = value

			}

		case models.SettingPushCategoryMarketing:

			if value := strings.TrimSpace(setting.Value); value != "" {

				androidConfig.MarketingCategory = value

			}

		case models.SettingPushPrimaryProvider:

			if value := normalizePushProviderSetting(setting.Value, PushChannelJPush); value != "" {

				androidConfig.PrimaryProvider = value

			}

		case models.SettingPushFallbackProvider:

			if value := normalizePushProviderSetting(setting.Value, "none"); value != "" {

				androidConfig.FallbackProvider = value

			}

		case models.SettingPushRateLimitPerMinute:

			androidConfig.RateLimitPerMinute = parseNonNegativeIntSetting(setting.Value)

		case models.SettingPushMarketingDailyLimit:

			androidConfig.MarketingDailyLimit = parseNonNegativeIntSetting(setting.Value)

		case models.SettingPushQuietHoursEnabled:

			androidConfig.QuietHoursEnabled = setting.Value == "true" || setting.Value == "1"

		case models.SettingPushQuietHoursStart:

			if value := normalizeQuietHour(setting.Value, ""); value != "" {

				androidConfig.QuietHoursStart = value

			}

		case models.SettingPushQuietHoursEnd:

			if value := normalizeQuietHour(setting.Value, ""); value != "" {

				androidConfig.QuietHoursEnd = value

			}

		case models.SettingXiaomiPushEnabled:

			androidConfig.XiaomiEnabled = setting.Value == "true" || setting.Value == "1"

		case models.SettingXiaomiPackageName:

			androidConfig.XiaomiPackageName = setting.Value

		case models.SettingXiaomiAppSecret:

			androidConfig.XiaomiAppSecret = setting.Value

		case models.SettingOppoPushEnabled:

			androidConfig.OppoEnabled = setting.Value == "true" || setting.Value == "1"

		case models.SettingOppoAppKey:

			androidConfig.OppoAppKey = setting.Value

		case models.SettingOppoAppSecret:

			androidConfig.OppoAppSecret = setting.Value

		case models.SettingWebPushEnabled:

			webPushConfig.Enabled = setting.Value != "false" && setting.Value != "0"

		case models.SettingWebPushVAPIDPublicKey:

			webPushConfig.VAPIDPublicKey = strings.TrimSpace(setting.Value)

		case models.SettingWebPushVAPIDPrivateKey:

			webPushConfig.VAPIDPrivateKey = strings.TrimSpace(setting.Value)

		case models.SettingWebPushSubject:

			if strings.TrimSpace(setting.Value) != "" {

				webPushConfig.Subject = strings.TrimSpace(setting.Value)

			}

		case models.SettingWebPushTTL:

			if ttl, err := strconv.Atoi(strings.TrimSpace(setting.Value)); err == nil && ttl > 0 {

				webPushConfig.TTL = ttl

			}

		}
	}
	s.ensureWebPushVAPIDKeys(&webPushConfig)
	// 配置和各厂商访问令牌受同一把锁保护；重载配置时清空令牌缓存，
	// 防止继续使用旧项目、旧密钥签发的凭据。
	s.configMu.Lock()
	s.config = config
	s.androidConfig = androidConfig
	s.webPushConfig = webPushConfig
	s.jwtToken = ""
	s.jwtExpiry = time.Time{}
	s.fcmAccessToken = ""
	s.fcmTokenExpiry = time.Time{}
	s.hmsAccessToken = ""
	s.hmsTokenExpiry = time.Time{}
	s.oppoAuthToken = ""
	s.oppoTokenExpiry = time.Time{}
	s.oppoAPIHost = ""
	s.configMu.Unlock()
	log.Printf(

		"[Push] Config reloaded: apns=%v, fcm=%v, hms=%v, jpush=%v, xiaomi=%v, oppo=%v, webpush=%v",

		config.Enabled,

		androidConfig.FCMEnabled,

		androidConfig.HMSEnabled,

		androidConfig.JPushEnabled,

		androidConfig.XiaomiEnabled,

		androidConfig.OppoEnabled,

		webPushConfig.Enabled && webPushConfig.VAPIDPublicKey != "" && webPushConfig.VAPIDPrivateKey != "",
	)
}
func (s *PushService) ensureWebPushVAPIDKeys(config *WebPushConfig) {
	if s == nil || s.db == nil || config == nil {

		return
	}
	if strings.TrimSpace(config.VAPIDPublicKey) != "" && strings.TrimSpace(config.VAPIDPrivateKey) != "" {

		return
	}
	privateKey, publicKey, err := webpush.GenerateVAPIDKeys()
	if err != nil {

		log.Printf("[Push][WebPush] Generate VAPID keys failed: %v", err)

		return
	}
	config.VAPIDPrivateKey = privateKey
	config.VAPIDPublicKey = publicKey
	s.upsertPushSystemSetting(models.SettingWebPushVAPIDPrivateKey, privateKey, "string", "WebPush VAPID private key")
	s.upsertPushSystemSetting(models.SettingWebPushVAPIDPublicKey, publicKey, "string", "WebPush VAPID public key")
	if strings.TrimSpace(config.Subject) == "" {

		config.Subject = "mailto:admin@example.com"
	}
	s.upsertPushSystemSetting(models.SettingWebPushSubject, config.Subject, "string", "WebPush VAPID subject")
	s.upsertPushSystemSetting(models.SettingWebPushTTL, strconv.Itoa(config.TTL), "int", "WebPush TTL seconds")
	log.Printf("[Push][WebPush] Generated VAPID keys")
}
func (s *PushService) upsertPushSystemSetting(key, value, valueType, remark string) {
	var setting models.SystemSetting
	if err := s.db.Where("`key` = ?", key).First(&setting).Error; err != nil {

		setting = models.SystemSetting{

			Key: key,

			Value: value,

			Type: valueType,

			Remark: remark,
		}

		if err := s.db.Create(&setting).Error; err != nil {

			log.Printf("[Push] create setting %s failed: %v", key, err)

		}

		return
	}
	updates := map[string]interface{}{

		"value": value,

		"type": valueType,

		"remark": remark,
	}
	if err := s.db.Model(&setting).Updates(updates).Error; err != nil {

		log.Printf("[Push] update setting %s failed: %v", key, err)
	}
}
func (s *PushService) WebPushPublicKey() (string, bool) {
	if s == nil {

		return "", false
	}
	s.configMu.RLock()
	cfg := s.webPushConfig
	s.configMu.RUnlock()
	publicKey := strings.TrimSpace(cfg.VAPIDPublicKey)
	privateKey := strings.TrimSpace(cfg.VAPIDPrivateKey)
	return publicKey, cfg.Enabled && publicKey != "" && privateKey != ""
}
func parseAuthKey(keyData []byte) (*ecdsa.PrivateKey, error) {
	block, _ := pem.Decode(keyData)
	if block == nil {

		return nil, fmt.Errorf("failed to decode PEM block")
	}
	key, err := x509.ParsePKCS8PrivateKey(block.Bytes)
	if err != nil {

		return nil, err
	}
	ecdsaKey, ok := key.(*ecdsa.PrivateKey)
	if !ok {

		return nil, fmt.Errorf("key is not ECDSA")
	}
	return ecdsaKey, nil
}
func parseRSAPrivateKey(keyData []byte) (*rsa.PrivateKey, error) {
	block, _ := pem.Decode(keyData)
	if block == nil {

		return nil, fmt.Errorf("failed to decode PEM block")
	}
	keyAny, err := x509.ParsePKCS8PrivateKey(block.Bytes)
	if err == nil {

		if key, ok := keyAny.(*rsa.PrivateKey); ok {

			return key, nil

		}

		return nil, fmt.Errorf("private key is not RSA")
	}
	if key, errPKCS1 := x509.ParsePKCS1PrivateKey(block.Bytes); errPKCS1 == nil {

		return key, nil
	}
	return nil, err
}

// PushToUser sends push notification to all devices of one user.
func (s *PushService) PushToUser(userID uint64, title, body string, data map[string]interface{}) error {
	return s.pushToUser(userID, "", title, body, data)
}

// PushToUserExceptDevice sends a user-level push while excluding one physical device.
func (s *PushService) PushToUserExceptDevice(userID uint64, excludedDeviceID, title, body string, data map[string]interface{}) error {
	return s.pushToUser(userID, LogicalPushDeviceID(excludedDeviceID), title, body, data)
}
func (s *PushService) pushToUser(userID uint64, excludedDeviceID, title, body string, data map[string]interface{}) error {
	title = normalizePushDisplayText(title)
	body = normalizePushDisplayText(body)
	data = s.withPushClassification(data)
	// Revocation is a privacy/control event, not a user-visible marketing or
	// chat alert. It must bypass quiet hours and preview preferences so an
	// already displayed message body can always be removed.
	if pushDataType(data) != "message_revoked" && !s.allowPushByPolicy(userID, data) {

		return nil
	}
	var devices []models.UserDevice
	// UserDevice 是推送绑定的权威来源。一次查询取回全部通道绑定，
	// 后续先按“物理设备 + 通道”去重，再为同一 Android 设备构造主备通道顺序。
	if err := s.db.Where("user_id = ? AND push_token != ''", userID).Find(&devices).Error; err != nil {
		return err
	}
	devices = excludePhysicalPushDevice(devices, excludedDeviceID)
	return s.pushToUserDevices(userID, devices, title, body, data)
}

func (s *PushService) pushToUserDevices(userID uint64, devices []models.UserDevice, title, body string, data map[string]interface{}) error {
	if len(devices) == 0 {

		log.Printf("[Push] No push devices found for user %d", userID)

		return nil
	}
	isIncomingCall := pushDataType(data) == "incoming_call"
	iosVoIPBaseDeviceIDs := map[string]struct{}{}
	for _, device := range devices {
		channel := NormalizePushChannel(device.PushChannel, device.DeviceType)

		if channel == PushChannelAPNsVoIP && strings.TrimSpace(device.PushToken) != "" {
			baseDeviceID := strings.TrimSuffix(strings.TrimSpace(device.DeviceID), ":voip")

			iosVoIPBaseDeviceIDs[baseDeviceID] = struct{}{}

		}
	}
	seenTokens := make(map[string]struct{}, len(devices))
	uniqueDevices := make([]models.UserDevice, 0, len(devices))
	for _, device := range devices {
		token := strings.TrimSpace(device.PushToken)

		if token == "" {

			continue

		}
		channel := NormalizePushChannel(device.PushChannel, device.DeviceType)

		if channel == PushChannelAPNsVoIP && !isIncomingCall {

			continue

		}

		if isIncomingCall && channel == PushChannelAPNs &&

			strings.EqualFold(strings.TrimSpace(device.DeviceType), "ios") {
			baseDeviceID := strings.TrimSpace(device.DeviceID)

			if _, ok := iosVoIPBaseDeviceIDs[baseDeviceID]; ok {

				continue

			}

		}
		key := channel + "\x00" + token

		if _, ok := seenTokens[key]; ok {

			log.Printf("[Push] Skip duplicate push token for user %d device=%s channel=%s", userID, device.DeviceID, channel)

			continue

		}

		seenTokens[key] = struct{}{}

		device.PushToken = token

		uniqueDevices = append(uniqueDevices, device)
	}
	if len(uniqueDevices) == 0 {

		log.Printf("[Push] No unique push devices found for user %d", userID)

		return nil
	}
	for _, plan := range buildPushDeliveryPlans(uniqueDevices, s.currentAndroidPushConfig()) {

		if len(plan.devices) == 0 {

			continue

		}

		if len(plan.devices) == 1 {

			_ = s.PushToDevice(plan.devices[0], title, body, data)

			continue

		}
		_ = s.pushToAndroidFallbackDevices(plan.devices, title, body, data)
	}
	return nil
}
func excludePhysicalPushDevice(devices []models.UserDevice, excludedDeviceID string) []models.UserDevice {
	excludedDeviceID = LogicalPushDeviceID(excludedDeviceID)
	if excludedDeviceID == "" || len(devices) == 0 {

		return devices
	}
	filtered := make([]models.UserDevice, 0, len(devices))
	for _, device := range devices {

		if LogicalPushDeviceID(device.DeviceID) == excludedDeviceID {

			continue

		}
		filtered = append(filtered, device)
	}
	return filtered
}

type pushDeliveryPlan struct {
	devices []models.UserDevice
}

func (s *PushService) currentAndroidPushConfig() AndroidPushConfig {
	if s == nil {

		return AndroidPushConfig{}
	}
	s.configMu.RLock()
	cfg := s.androidConfig
	s.configMu.RUnlock()
	return cfg
}
func buildPushDeliveryPlans(devices []models.UserDevice, cfg AndroidPushConfig) []pushDeliveryPlan {
	if len(devices) == 0 {

		return []pushDeliveryPlan{}
	}
	plans := make([]pushDeliveryPlan, 0, len(devices))
	androidGroups := make(map[string][]models.UserDevice)
	androidOrder := make([]string, 0, len(devices))
	seenAndroidGroup := map[string]struct{}{}
	for _, device := range devices {
		channel := NormalizePushChannel(device.PushChannel, device.DeviceType)

		if !IsAndroidPushChannel(channel) {

			plans = append(plans, pushDeliveryPlan{devices: []models.UserDevice{device}})

			continue

		}

		device.PushChannel = channel

		groupKey := LogicalPushDeviceID(device.DeviceID)

		if groupKey == "" {

			groupKey = strings.TrimSpace(device.DeviceID)

		}

		if groupKey == "" {

			groupKey = fmt.Sprintf("device-id-%d", device.ID)

		}

		if _, ok := seenAndroidGroup[groupKey]; !ok {

			seenAndroidGroup[groupKey] = struct{}{}
			androidOrder = append(androidOrder, groupKey)

		}

		androidGroups[groupKey] = append(androidGroups[groupKey], device)
	}
	for _, groupKey := range androidOrder {

		// 同一物理设备可能同时保留多个厂商 token：每个通道只取最近绑定，

		// 再按主通道、备用通道排序，成功一个即停止，避免同机重复弹窗。

		group := latestPushDevicePerChannel(androidGroups[groupKey])

		sortAndroidPushDevices(group, cfg)
		plans = append(plans, pushDeliveryPlan{devices: group})
	}
	return plans
}
func latestPushDevicePerChannel(devices []models.UserDevice) []models.UserDevice {
	if len(devices) <= 1 {

		return devices
	}
	latest := make(map[string]models.UserDevice, len(devices))
	order := make([]string, 0, len(devices))
	for _, device := range devices {
		channel := NormalizePushChannel(device.PushChannel, device.DeviceType)

		if channel == "" {

			channel = PushChannelUnknown

		}
		existing, ok := latest[channel]

		if !ok {

			order = append(order, channel)

			latest[channel] = device

			continue

		}

		if isNewerPushDevice(device, existing) {

			latest[channel] = device

		}
	}
	out := make([]models.UserDevice, 0, len(order))
	for _, channel := range order {

		out = append(out, latest[channel])
	}
	return out
}
func isNewerPushDevice(candidate, existing models.UserDevice) bool {
	if candidate.LastActive.After(existing.LastActive) {

		return true
	}
	if candidate.LastActive.Equal(existing.LastActive) && candidate.ID > existing.ID {

		return true
	}
	return false
}
func sortAndroidPushDevices(devices []models.UserDevice, cfg AndroidPushConfig) {
	if len(devices) <= 1 {

		return
	}
	sort.SliceStable(devices, func(i, j int) bool {
		leftRank := androidPushProviderRank(NormalizePushChannel(devices[i].PushChannel, devices[i].DeviceType), cfg)
		rightRank := androidPushProviderRank(NormalizePushChannel(devices[j].PushChannel, devices[j].DeviceType), cfg)

		if leftRank != rightRank {

			return leftRank < rightRank

		}

		if !devices[i].LastActive.Equal(devices[j].LastActive) {

			return devices[i].LastActive.After(devices[j].LastActive)

		}

		return devices[i].ID > devices[j].ID
	})
}
func androidPushProviderRank(channel string, cfg AndroidPushConfig) int {
	normalized := NormalizePushChannel(channel, "android")
	primary := NormalizePushChannel(cfg.PrimaryProvider, "")
	fallback := NormalizePushChannel(cfg.FallbackProvider, "")
	if normalized == primary && IsAndroidPushChannel(primary) {

		return 0
	}
	if normalized == fallback && IsAndroidPushChannel(fallback) {

		return 1
	}
	switch normalized {
	case PushChannelJPush:

		return 10
	case PushChannelFCM:

		return 11
	case PushChannelHMS:

		return 12
	case PushChannelXiaomi:

		return 13
	case PushChannelOppo:

		return 14
	default:

		return 100
	}
}

// PushToDevice 异步提交单设备推送；返回 nil 仅表示任务已进入后台发送， // 厂商最终结果由 push_delivery_logs 和日志记录，不应作为业务事务提交依据。
func (s *PushService) PushToDevice(device models.UserDevice, title, body string, data map[string]interface{}) error {
	title = normalizePushDisplayText(title)
	body = normalizePushDisplayText(body)
	token := strings.TrimSpace(device.PushToken)
	if token == "" {

		return fmt.Errorf("设备未绑定推送 token")
	}
	device.PushToken = token
	data = s.withPushClassification(data)
	s.configMu.RLock()
	config := s.config
	webPushConfig := s.webPushConfig
	s.configMu.RUnlock()
	dataJSON, _ := json.Marshal(data)
	payload := APNsPayload{

		Aps: APNsAps{

			Alert: APNsAlert{

				Title: title,

				Body: body,
			},

			Sound: "default",

			MutableContent: 1,
		},

		Data: dataJSON,
	}
	if strings.TrimSpace(fmt.Sprint(data["type"])) == "incoming_call" {

		payload.Aps.ContentAvailable = 1
	}
	scene := strings.TrimSpace(fmt.Sprint(data["scene"]))
	if scene == "" || scene == "<nil>" {

		scene = pushDataType(data)
	}
	go func(d models.UserDevice) {

		_ = s.pushToDeviceSync(d, title, body, data, config, webPushConfig, payload, scene)
	}(device)
	return nil
}
func (s *PushService) pushToAndroidFallbackDevices(devices []models.UserDevice, title, body string, data map[string]interface{}) error {
	title = normalizePushDisplayText(title)
	body = normalizePushDisplayText(body)
	data = s.withPushClassification(data)
	candidates := make([]models.UserDevice, 0, len(devices))
	for _, device := range devices {
		token := strings.TrimSpace(device.PushToken)

		if token == "" {

			continue

		}
		channel := NormalizePushChannel(device.PushChannel, device.DeviceType)

		if !IsAndroidPushChannel(channel) {

			continue

		}

		device.PushToken = token

		candidates = append(candidates, device)
	}
	if len(candidates) == 0 {

		return fmt.Errorf("设备未绑定推送 token")
	}
	go func(list []models.UserDevice) {

		// 降级通道严格串行：只有当前厂商明确失败才尝试下一个，

		// 从而在提高到达率的同时尽量避免多个厂商同时送达。
		var lastErr error

		for index, device := range list {
			channel := NormalizePushChannel(device.PushChannel, device.DeviceType)

			if index > 0 {

				log.Printf("[Push] Trying fallback channel=%s for device=%s", channel, device.DeviceID)

			}

			if err := s.pushToDevicePrepared(device, title, body, data); err != nil {

				lastErr = err

				continue

			}

			if index > 0 {

				log.Printf("[Push] Fallback channel=%s succeeded for device=%s", channel, device.DeviceID)

			}

			return

		}

		if lastErr != nil {

			log.Printf("[Push] All fallback channels failed for logical device=%s: %v", LogicalPushDeviceID(list[0].DeviceID), lastErr)

		}
	}(candidates)
	return nil
}
func (s *PushService) pushToDevicePrepared(device models.UserDevice, title, body string, data map[string]interface{}) error {
	s.configMu.RLock()
	config := s.config
	webPushConfig := s.webPushConfig
	s.configMu.RUnlock()
	dataJSON, _ := json.Marshal(data)
	payload := APNsPayload{

		Aps: APNsAps{

			Alert: APNsAlert{

				Title: title,

				Body: body,
			},

			Sound: "default",

			MutableContent: 1,
		},

		Data: dataJSON,
	}
	if strings.TrimSpace(fmt.Sprint(data["type"])) == "incoming_call" {

		payload.Aps.ContentAvailable = 1
	}
	scene := strings.TrimSpace(fmt.Sprint(data["scene"]))
	if scene == "" || scene == "<nil>" {

		scene = pushDataType(data)
	}
	return s.pushToDeviceSync(device, title, body, data, config, webPushConfig, payload, scene)
}
func (s *PushService) pushToDeviceSync(
	d models.UserDevice,
	title string,
	body string,
	data map[string]interface{},
	config *APNsConfig,
	webPushConfig WebPushConfig,
	payload APNsPayload,
	scene string) error {
	token := strings.TrimSpace(d.PushToken)
	if token == "" {

		return fmt.Errorf("设备未绑定推送 token")
	}
	d.PushToken = token
	channel := NormalizePushChannel(d.PushChannel, d.DeviceType)
	var err error
	switch channel {
	case PushChannelJPush:

		err = s.sendJPush(d, title, body, data)
	case PushChannelAPNs:

		if config == nil || !config.Enabled {

			err = fmt.Errorf("APNs 推送未启用")

			log.Printf("[Push] APNs disabled, skip iOS device: %s", d.DeviceID)

		} else {

			err = s.sendAPNs(d.PushToken, payload)

		}
	case PushChannelAPNsVoIP:

		if config == nil || !config.Enabled {

			err = fmt.Errorf("APNs 推送未启用")

			log.Printf("[Push] APNs VoIP disabled, skip iOS device: %s", d.DeviceID)

		} else if validationErr := validateIncomingCallVoIPPayload(data, time.Now()); validationErr != nil {

			err = validationErr

			log.Printf(

				"[Push][APNsVoIP] Reject invalid incoming-call payload call_id=%s device=%s: %v",

				pushStringValue(data["call_id"]),

				LogicalPushDeviceID(d.DeviceID),

				validationErr,
			)

		} else {
			voipPayload := payload

			voipPayload.Aps.Alert = APNsAlert{}

			voipPayload.Aps.Sound = ""

			voipPayload.Aps.MutableContent = 0

			voipPayload.Aps.ContentAvailable = 1

			err = s.sendAPNs(d.PushToken, voipPayload, APNsSendOptions{

				PushType: "voip",

				TopicSuffix: ".voip",
			})

		}
	case PushChannelFCM, PushChannelHMS, PushChannelXiaomi, PushChannelOppo:

		err = s.sendAndroidPush(channel, d, title, body, data)
	case PushChannelWebPush:

		if !webPushConfig.Enabled ||

			strings.TrimSpace(webPushConfig.VAPIDPublicKey) == "" ||

			strings.TrimSpace(webPushConfig.VAPIDPrivateKey) == "" {

			log.Printf("[Push][WebPush] disabled, skip device: %s", d.DeviceID)
			err = fmt.Errorf("WebPush 推送未启用")

		} else {

			err = s.sendWebPush(d, title, body, data)

		}
	default:

		err = fmt.Errorf("unsupported push channel: type=%s channel=%s", d.DeviceType, d.PushChannel)

		log.Printf("[Push] Unsupported channel for device %s: %v", d.DeviceID, err)
	}
	if err != nil {

		log.Printf("[Push] Failed to send %s push to device=%s token=%s: %v", channel, d.DeviceID, maskPushToken(d.PushToken), err)

		s.recordPushDelivery(d, channel, title, body, err, scene)

		if isInvalidPushTokenError(channel, err) {

			// 仅厂商明确判定 token 永久失效时清理绑定；超时、限流等临时错误保留 token 供后续重试。

			log.Printf("[Push] Removing invalid push token for device %s (channel=%s)", d.DeviceID, channel)

			if clearErr := ClearInvalidPushToken(s.db, d); clearErr != nil {

				log.Printf("[Push] Failed to clear invalid token snapshot for device %s: %v", d.DeviceID, clearErr)

			}

		} else {

			log.Printf("[Push] Push failed for device %s (channel=%s)", d.DeviceID, channel)

		}

		return err
	}
	s.recordPushDelivery(d, channel, title, body, nil, scene)
	return nil
}
func (s *PushService) withPushClassification(data map[string]interface{}) map[string]interface{} {
	if data == nil {

		data = map[string]interface{}{}
	}
	enriched := make(map[string]interface{}, len(data)+2)
	for key, value := range data {

		enriched[key] = value
	}
	ensureStablePushNotificationIdentity(enriched)
	explicitCategory := strings.TrimSpace(fmt.Sprint(enriched["push_category"]))
	if explicitCategory != "" && explicitCategory != "<nil>" {

		if messageCategory := strings.TrimSpace(fmt.Sprint(enriched["message_category"])); messageCategory == "" || messageCategory == "<nil>" {

			enriched["message_category"] = explicitCategory

		}

		return enriched
	}
	category := s.pushCategoryForData(enriched)
	if category == "" {

		return enriched
	}
	enriched["push_category"] = category
	enriched["message_category"] = category
	return enriched
}
func ensureStablePushNotificationIdentity(data map[string]interface{}) {
	if data == nil {

		return
	}
	if value := strings.TrimSpace(fmt.Sprint(data["notification_id"])); value != "" && value != "<nil>" {

		return
	}
	dataType := pushDataType(data)
	switch dataType {
	case "meeting_invite", "meeting_join_request", "meeting_join_request_reviewed", "meeting_status":

		meetingID := strings.TrimSpace(fmt.Sprint(data["meeting_id"]))

		if meetingID != "" && meetingID != "<nil>" {

			data["notification_id"] = meetingNotificationID(dataType, meetingID)

		}
	case "system_announcement":

		broadcastID := strings.TrimSpace(fmt.Sprint(data["broadcast_id"]))

		if broadcastID != "" && broadcastID != "<nil>" {

			data["notification_id"] = systemAnnouncementNotificationID(broadcastID)

		}
	}
}
func (s *PushService) allowPushByPolicy(userID uint64, data map[string]interface{}) bool {
	if s == nil || s.db == nil || userID == 0 {

		return true
	}
	var userSetting models.UserPushSetting
	if err := s.db.Where("user_id = ?", userID).First(&userSetting).Error; err == nil && !userSetting.Enabled {

		log.Printf("[Push][Policy] Skip push because notifications are disabled user=%d", userID)

		return false
	}
	category := strings.TrimSpace(fmt.Sprint(data["push_category"]))
	scene := strings.TrimSpace(fmt.Sprint(data["scene"]))
	if scene == "" || scene == "<nil>" {

		scene = strings.TrimSpace(fmt.Sprint(data["type"]))
	}
	s.configMu.RLock()
	cfg := s.androidConfig
	s.configMu.RUnlock()
	if isMarketingPushCategory(category) && cfg.QuietHoursEnabled &&

		isNowInQuietHours(time.Now(), cfg.QuietHoursStart, cfg.QuietHoursEnd) {

		log.Printf("[Push][Policy] Skip marketing push during quiet hours user=%d scene=%s", userID, scene)

		return false
	}
	if cfg.RateLimitPerMinute > 0 {
		var recentCount int64
		if err := s.db.Model(&models.PushDeliveryLog{}).
			Where("user_id = ? AND occurred_at >= ?", userID, time.Now().Add(-time.Minute)).
			Count(&recentCount).Error; err == nil && recentCount >= int64(cfg.RateLimitPerMinute) {

			log.Printf("[Push][Policy] Skip push by minute rate limit user=%d limit=%d recent=%d", userID, cfg.RateLimitPerMinute, recentCount)

			return false

		}
	}
	if isMarketingPushCategory(category) && cfg.MarketingDailyLimit > 0 {
		now := time.Now()
		year, month, day := now.Date()
		startOfDay := time.Date(year, month, day, 0, 0, 0, 0, now.Location())
		var dailyCount int64
		if err := s.db.Model(&models.PushDeliveryLog{}).
			Where("user_id = ? AND occurred_at >= ? AND scene IN ?", userID, startOfDay, []string{"marketing", "marketing_notice", "operation_notice"}).
			Count(&dailyCount).Error; err == nil && dailyCount >= int64(cfg.MarketingDailyLimit) {

			log.Printf("[Push][Policy] Skip marketing push by daily limit user=%d limit=%d count=%d", userID, cfg.MarketingDailyLimit, dailyCount)

			return false

		}
	}
	return true
}
func isMarketingPushCategory(category string) bool {
	switch strings.ToLower(strings.TrimSpace(category)) {
	case "marketing", "marketing_notice", "operation_notice":

		return true
	default:

		return false
	}
}
func isNowInQuietHours(now time.Time, start, end string) bool {
	startMinute, okStart := parseHHMMToMinute(start)
	endMinute, okEnd := parseHHMMToMinute(end)
	if !okStart || !okEnd || startMinute == endMinute {

		return false
	}
	currentMinute := now.Hour()*60 + now.Minute()
	if startMinute < endMinute {

		return currentMinute >= startMinute && currentMinute < endMinute
	}
	return currentMinute >= startMinute || currentMinute < endMinute
}
func parseHHMMToMinute(value string) (int, bool) {
	parts := strings.Split(strings.TrimSpace(value), ":")
	if len(parts) != 2 {

		return 0, false
	}
	hour, errHour := strconv.Atoi(parts[0])
	minute, errMinute := strconv.Atoi(parts[1])
	if errHour != nil || errMinute != nil || hour < 0 || hour > 23 || minute < 0 || minute > 59 {

		return 0, false
	}
	return hour*60 + minute, true
}
func (s *PushService) pushCategoryForData(data map[string]interface{}) string {
	scene := strings.TrimSpace(fmt.Sprint(data["scene"]))
	if scene == "" || scene == "<nil>" {

		scene = strings.TrimSpace(fmt.Sprint(data["type"]))
	}
	s.configMu.RLock()
	cfg := s.androidConfig
	s.configMu.RUnlock()
	switch scene {
	case "new_message", "chat_message":

		return firstNonEmpty(cfg.ChatCategory, "chat_message")
	case "marketing", "marketing_notice", "operation_notice":

		return firstNonEmpty(cfg.MarketingCategory, "marketing")
	case "friend_request", "group_notice", "system_notice", "incoming_call":

		return firstNonEmpty(cfg.ServiceCategory, "service_notice")
	default:

		return firstNonEmpty(cfg.ServiceCategory, "service_notice")
	}
}
func (s *PushService) recordPushDelivery(device models.UserDevice, channel, title, body string, sendErr error, scenes ...string) {
	if s == nil || s.db == nil {

		return
	}
	errText := ""
	if sendErr != nil {

		errText = truncatePushLogText(sendErr.Error(), 512)
	}
	now := time.Now()
	scene := ""
	if len(scenes) > 0 {

		scene = strings.TrimSpace(scenes[0])
	}
	logItem := models.PushDeliveryLog{

		UserID: device.UserID,

		DeviceID: device.ID,

		DeviceKey: truncatePushLogText(device.DeviceID, 100),

		Channel: truncatePushLogText(channel, 20),

		Provider: truncatePushLogText(channel, 20),

		Scene: truncatePushLogText(scene, 50),

		Success: sendErr == nil,

		Error: errText,

		Title: truncatePushLogText(title, 120),

		Body: truncatePushLogText(body, 255),

		OccurredAt: now,

		CreatedAt: now,
	}
	if err := s.db.Create(&logItem).Error; err != nil {

		log.Printf("[Push] record delivery log failed: user=%d device=%s channel=%s err=%v", device.UserID, device.DeviceID, channel, err)

		return
	}
	if logItem.ID > 0 && logItem.ID%100 == 0 {
		cutoff := now.Add(-14 * 24 * time.Hour)
		_ = s.db.Where("occurred_at < ?", cutoff).Delete(&models.PushDeliveryLog{}).Error
	}
}
func truncatePushLogText(v string, max int) string {
	v = strings.TrimSpace(v)
	if max <= 0 || len(v) <= max {

		return v
	}
	runes := []rune(v)
	if len(runes) <= max {

		return v
	}
	return string(runes[:max])
}
func normalizePushProviderSetting(value, fallback string) string {
	normalized := strings.ToLower(strings.TrimSpace(value))
	switch normalized {
	case "none", "":

		if fallback == "" {

			return "none"

		}

		return fallback
	case PushChannelJPush, PushChannelFCM, PushChannelHMS, PushChannelXiaomi, PushChannelOppo, PushChannelAPNs, PushChannelAPNsVoIP, "native", "getui":

		return normalized
	default:

		if fallback == "" {

			return "none"

		}

		return fallback
	}
}
func parseNonNegativeIntSetting(value string) int {
	n, err := strconv.Atoi(strings.TrimSpace(value))
	if err != nil || n < 0 {

		return 0
	}
	return n
}
func normalizeQuietHour(value, fallback string) string {
	value = strings.TrimSpace(value)
	if _, ok := parseHHMMToMinute(value); ok {

		return value
	}
	return fallback
}
func isInvalidPushTokenError(channel string, err error) bool {
	if err == nil {

		return false
	}
	errText := strings.ToLower(err.Error())
	switch channel {
	case PushChannelAPNs, PushChannelAPNsVoIP:

		return strings.Contains(errText, "baddevicetoken") ||

			strings.Contains(errText, "unregistered") ||

			strings.Contains(errText, "devicetokennotfortopic")
	case PushChannelFCM:

		return strings.Contains(errText, "unregistered") ||

			strings.Contains(errText, "registration-token-not-registered") ||

			strings.Contains(errText, "invalid registration token") ||

			strings.Contains(errText, "not a valid fcm registration token") ||

			strings.Contains(errText, "sender_id_mismatch") ||

			strings.Contains(errText, "senderid mismatch") ||

			strings.Contains(errText, "sender id mismatch")
	case PushChannelHMS:

		return strings.Contains(errText, "invalid token") ||

			strings.Contains(errText, "token invalid") ||

			strings.Contains(errText, "token does not exist")
	case PushChannelJPush:

		return strings.Contains(errText, "invalid registration_id") ||

			strings.Contains(errText, "registration_id is invalid") ||

			strings.Contains(errText, "cannot find user by this audience") ||

			strings.Contains(errText, "invalid audience")
	case PushChannelXiaomi:

		return strings.Contains(errText, "invalid registration") ||

			strings.Contains(errText, "invalid regid") ||

			strings.Contains(errText, "invalid registration_id") ||

			strings.Contains(errText, "registration_id invalid")
	case PushChannelOppo:

		return strings.Contains(errText, "invalid registration") ||

			strings.Contains(errText, "invalid registration_id") ||

			strings.Contains(errText, "registration_id invalid") ||

			strings.Contains(errText, "target_value invalid")
	case PushChannelWebPush:

		return strings.Contains(errText, "status=404") ||

			strings.Contains(errText, "status=410") ||

			strings.Contains(errText, "gone") ||

			strings.Contains(errText, "not found") ||

			strings.Contains(errText, "invalid subscription")
	default:

		return false
	}
}

type NewMessagePushRecipient struct {
	UserID    uint64
	Mentioned bool
}

type NewMessagePushBatchResult struct {
	CandidateUsers   int
	DeviceUsers      int
	ScheduledDevices int
	DisabledUsers    int
	RateLimitedUsers int
}

type newMessagePushPolicy struct {
	enabled     bool
	showPreview bool
}

// PushNewMessageBatch loads devices, user preferences and rate-limit counts in
// set-based queries. Callers should already remove online and muted users.
func (s *PushService) PushNewMessageBatch(
	recipients []NewMessagePushRecipient,
	senderName, content, chatID, chatType, msgID string,
	imageURLs ...string,
) (NewMessagePushBatchResult, error) {
	result := NewMessagePushBatchResult{}
	if s == nil || s.db == nil || len(recipients) == 0 {
		return result, nil
	}

	s.configMu.RLock()
	cfg := s.androidConfig
	s.configMu.RUnlock()
	if !cfg.ChatPushEnabled {
		return result, nil
	}

	recipientByUserID := make(map[uint64]NewMessagePushRecipient, len(recipients))
	for _, recipient := range recipients {
		if recipient.UserID == 0 {
			continue
		}
		existing := recipientByUserID[recipient.UserID]
		existing.UserID = recipient.UserID
		existing.Mentioned = existing.Mentioned || recipient.Mentioned
		recipientByUserID[recipient.UserID] = existing
	}
	result.CandidateUsers = len(recipientByUserID)
	if len(recipientByUserID) == 0 {
		return result, nil
	}

	userIDs := make([]uint64, 0, len(recipientByUserID))
	for userID := range recipientByUserID {
		userIDs = append(userIDs, userID)
	}
	var devices []models.UserDevice
	if err := s.db.
		Where("user_id IN ? AND push_token != ''", userIDs).
		Find(&devices).Error; err != nil {
		return result, err
	}
	devicesByUserID := make(map[uint64][]models.UserDevice)
	for _, device := range devices {
		if strings.TrimSpace(device.PushToken) == "" {
			continue
		}
		devicesByUserID[device.UserID] = append(devicesByUserID[device.UserID], device)
	}
	result.DeviceUsers = len(devicesByUserID)
	if len(devicesByUserID) == 0 {
		return result, nil
	}

	deviceUserIDs := make([]uint64, 0, len(devicesByUserID))
	for userID := range devicesByUserID {
		deviceUserIDs = append(deviceUserIDs, userID)
	}
	var settings []models.UserPushSetting
	if err := s.db.Where("user_id IN ?", deviceUserIDs).Find(&settings).Error; err != nil {
		return result, err
	}
	policies := make(map[uint64]newMessagePushPolicy, len(deviceUserIDs))
	for _, userID := range deviceUserIDs {
		policies[userID] = newMessagePushPolicy{enabled: true, showPreview: true}
	}
	for _, setting := range settings {
		policies[setting.UserID] = newMessagePushPolicy{
			enabled:     setting.Enabled,
			showPreview: setting.ShowPreview,
		}
	}

	recentPushCounts := make(map[uint64]int64)
	if cfg.RateLimitPerMinute > 0 {
		type recentPushCountRow struct {
			UserID uint64 `gorm:"column:user_id"`
			Count  int64  `gorm:"column:push_count"`
		}
		var rows []recentPushCountRow
		if err := s.db.Model(&models.PushDeliveryLog{}).
			Select("user_id, COUNT(*) AS push_count").
			Where("user_id IN ? AND occurred_at >= ?", deviceUserIDs, time.Now().Add(-time.Minute)).
			Group("user_id").
			Scan(&rows).Error; err != nil {
			return result, err
		}
		for _, row := range rows {
			recentPushCounts[row.UserID] = row.Count
		}
	}

	title := normalizePushDisplayText(senderName)
	content = normalizePushDisplayText(content)
	var firstErr error
	for userID, userDevices := range devicesByUserID {
		policy := policies[userID]
		if !policy.enabled {
			result.DisabledUsers++
			continue
		}
		if cfg.RateLimitPerMinute > 0 &&
			recentPushCounts[userID] >= int64(cfg.RateLimitPerMinute) {
			result.RateLimitedUsers++
			continue
		}

		userContent := content
		if recipientByUserID[userID].Mentioned && userContent != "" {
			userContent = "[有人@你] " + userContent
		}
		titleText, body := pushNotificationPrivacyText(policy.showPreview, title, userContent)
		data := s.withPushClassification(
			newMessagePushData(policy.showPreview, chatID, chatType, msgID, imageURLs...),
		)
		if err := s.pushToUserDevices(userID, userDevices, titleText, body, data); err != nil {
			if firstErr == nil {
				firstErr = err
			}
			continue
		}
		result.ScheduledDevices += len(
			buildPushDeliveryPlans(userDevices, s.currentAndroidPushConfig()),
		)
	}
	return result, firstErr
}

// PushNewMessage sends new-message push.
func (s *PushService) PushNewMessage(userID uint64, senderName, content, chatID, chatType, msgID string, imageURLs ...string) error {
	s.configMu.RLock()
	chatPushEnabled := s.androidConfig.ChatPushEnabled
	s.configMu.RUnlock()
	if !chatPushEnabled {

		log.Printf("[Push] Chat push disabled, skip user=%d chat=%s", userID, chatID)

		return nil
	}
	title := normalizePushDisplayText(senderName)
	content = normalizePushDisplayText(content)
	showPreview := true
	var setting models.UserPushSetting
	if err := s.db.Where("user_id = ?", userID).First(&setting).Error; err == nil {

		showPreview = setting.ShowPreview
	}
	titleText, body := pushNotificationPrivacyText(showPreview, title, content)
	data := newMessagePushData(showPreview, chatID, chatType, msgID, imageURLs...)
	return s.PushToUser(userID, titleText, body, data)
}
func newMessagePushData(showPreview bool, chatID, chatType, msgID string, imageURLs ...string) map[string]interface{} {
	normalizedChatID := strings.TrimSpace(chatID)
	normalizedMessageID := strings.TrimSpace(msgID)
	data := map[string]interface{}{

		"type": "new_message",

		"scene": "new_message",

		"chat_id": normalizedChatID,

		"chat_type": strings.TrimSpace(chatType),

		"msg_id": normalizedMessageID,

		"message_id": normalizedMessageID,

		"notification_id": chatNotificationID(normalizedChatID),
	}
	if showPreview && len(imageURLs) > 0 {

		if imageURL := normalizePushImageURL(imageURLs[0]); imageURL != "" {

			attachPushImageAliases(data, imageURL)

		}
	}
	return data
}
func pushNotificationPrivacyText(showPreview bool, title, content string) (string, string) {
	if !showPreview {

		return "新消息", "您收到一条新消息"
	}
	return title, textutil.TruncateRunesWithSuffix(content, 100, "...")
}

// PushMessageRevoked delivers a data event that vendor clients use to cancel // an already displayed unread-message notification. Native clients must not // render this payload as a second notification.
func (s *PushService) PushMessageRevoked(userID uint64, chatID, msgID string) error {
	return s.PushToUser(

		userID,

		"消息已撤回",

		"一条未读消息已被撤回",

		messageRevokedPushData(chatID, msgID),
	)
}
func messageRevokedPushData(chatID, msgID string) map[string]interface{} {
	normalizedChatID := strings.TrimSpace(chatID)
	normalizedMessageID := strings.TrimSpace(msgID)
	return map[string]interface{}{

		"type": "message_revoked",

		"scene": "message_revoked",

		"chat_id": normalizedChatID,

		"msg_id": normalizedMessageID,

		"message_id": normalizedMessageID,

		"notification_id": chatNotificationID(normalizedChatID),

		"push_category": "service_notice",

		"message_category": "service_notice",
	}
}

// PushChatAnnouncement routes group announcements through the same policy, // delivery log, vendor fallback and deep-link contract as other pushes.
func (s *PushService) PushChatAnnouncement(userID uint64, chatID string, announcementID uint64) error {
	return s.PushToUser(

		userID,

		"群公告",

		"群内发布了新公告",

		chatAnnouncementPushData(chatID, announcementID),
	)
}

// PushSystemAnnouncement delivers a persisted admin broadcast to devices that // were offline or backgrounded when the websocket event was emitted.
func (s *PushService) PushSystemAnnouncement(
	userID uint64,
	title, content string,
	broadcastID uint64,
	subtype string) error {
	return s.PushToUser(

		userID,

		normalizePushDisplayText(title),

		normalizePushDisplayText(content),

		systemAnnouncementPushData(broadcastID, subtype),
	)
}
func chatAnnouncementPushData(chatID string, announcementID uint64) map[string]interface{} {
	normalizedChatID := strings.TrimSpace(chatID)
	return map[string]interface{}{

		"type": "chat_announcement",

		"scene": "group_notice",

		"chat_id": normalizedChatID,

		"chat_type": "group",

		"announcement_id": announcementID,

		"push_category": "group_notice",

		"message_category": "group_notice",

		"notification_id": announcementNotificationID(normalizedChatID, announcementID),
	}
}
func announcementNotificationID(chatID string, announcementID uint64) int {
	hash := 0
	key := fmt.Sprintf("%s#%d", strings.TrimSpace(chatID), announcementID)
	for _, unit := range []byte(key) {

		hash = (hash*31 + int(unit)) & 0x3fffffff
	}
	// Keep announcements outside the 10,000-89,999 per-chat message range.
	return 100000 + hash%800000
}
func systemAnnouncementPushData(broadcastID uint64, subtype string) map[string]interface{} {
	id := strconv.FormatUint(broadcastID, 10)
	return map[string]interface{}{

		"type": "system_announcement",

		"scene": "system_notice",

		"broadcast_id": broadcastID,

		"subtype": strings.TrimSpace(subtype),

		"push_category": "service_notice",

		"message_category": "service_notice",

		"notification_id": systemAnnouncementNotificationID(id),
	}
}
func systemAnnouncementNotificationID(broadcastID string) int {
	hash := 0
	for _, unit := range []byte(strings.TrimSpace(broadcastID)) {

		hash = (hash*31 + int(unit)) & 0x3fffffff
	}
	// Keep system broadcasts outside message, group announcement and meeting ranges.
	return 2000000 + hash%900000
}
func meetingNotificationID(dataType, meetingID string) int {
	hash := 0
	key := strings.TrimSpace(dataType) + "#" + strings.TrimSpace(meetingID)
	for _, unit := range []byte(key) {

		hash = (hash*31 + int(unit)) & 0x3fffffff
	}
	// Keep meetings outside the message and announcement notification ranges.
	return 1000000 + hash%900000
}

// chatNotificationID mirrors Android's 31-based String hash contract for the // UUID chat IDs used by this service.
func chatNotificationID(chatID string) int {
	hash := 0
	for _, unit := range []byte(strings.TrimSpace(chatID)) {

		hash = (hash*31 + int(unit)) & 0x3fffffff
	}
	return 10000 + hash%80000
}
func normalizePushDisplayText(text string) string {
	return textutil.RepairLegacyMojibakeText(text)
}
func normalizePushImageURL(value interface{}) string {
	imageURL := strings.TrimSpace(fmt.Sprint(value))
	if imageURL == "" || imageURL == "<nil>" {

		return ""
	}
	return imageURL
}
func attachPushImageAliases(data map[string]interface{}, imageURL string) {
	imageURL = normalizePushImageURL(imageURL)
	if imageURL == "" {

		return
	}
	data["image_url"] = imageURL
	data["thumbnail"] = imageURL
	data["media_url"] = imageURL
	data["image"] = imageURL
}

// PushCall sends incoming call push.
func (s *PushService) PushCall(userID uint64, callerName string, callID string, isVideo bool, extras ...map[string]interface{}) error {
	callType := "语音"
	if isVideo {

		callType = "视频"
	}
	title := callerName
	body := fmt.Sprintf("来电：%s通话", callType)
	data := map[string]interface{}{

		"type": "incoming_call",

		"call_id": callID,

		"is_video": isVideo,
	}
	for _, extra := range extras {

		for k, v := range extra {

			data[k] = v

		}
	}
	return s.PushToUser(userID, title, body, data)
}

// PushIncomingCall sends a call push with the fields required by mobile clients // to render an incoming-call screen when the websocket is unavailable.
func (s *PushService) PushIncomingCall(userID uint64, callerName string, callID string, isVideo bool, data map[string]interface{}) error {
	payload, err := buildIncomingCallPushPayload(callerName, callID, isVideo, data, time.Now())
	if err != nil {

		log.Printf("[Push][IncomingCall] Reject invalid payload call_id=%s user=%d: %v", strings.TrimSpace(callID), userID, err)

		return err
	}
	callTypeText := "\u8bed\u97f3"
	if isVideo {

		callTypeText = "\u89c6\u9891"
	}
	return s.PushToUser(

		userID,

		pushStringValue(payload["caller_name"]),

		fmt.Sprintf("\u6765\u7535: %s\u901a\u8bdd", callTypeText),

		payload,
	)
}
func buildIncomingCallPushPayload(
	callerName string,
	callID string,
	isVideo bool,
	data map[string]interface{},
	now time.Time) (map[string]interface{}, error) {
	payload := make(map[string]interface{}, len(data)+8)
	for key, value := range data {

		payload[key] = value
	}
	callerName = strings.TrimSpace(callerName)
	if callerName == "" {

		callerName = "未知来电"
	}
	callType := "voice"
	if isVideo {

		callType = "video"
	}
	payload["type"] = "incoming_call"
	payload["call_id"] = strings.TrimSpace(callID)
	payload["caller_name"] = callerName
	payload["call_type"] = callType
	payload["is_video"] = isVideo
	channelName := firstNonEmpty(

		pushStringValue(payload["channel_name"]),

		pushStringValue(payload["room_name"]),
	)
	if channelName != "" {

		payload["channel_name"] = channelName

		payload["room_name"] = firstNonEmpty(pushStringValue(payload["room_name"]), channelName)
	}
	if err := validateIncomingCallVoIPPayload(payload, now); err != nil {

		return nil, err
	}
	return payload, nil
}
func validateIncomingCallVoIPPayload(data map[string]interface{}, now time.Time) error {
	missing := make([]string, 0, 6)
	if pushDataType(data) != "incoming_call" {

		missing = append(missing, "type")
	}
	if pushStringValue(data["call_id"]) == "" {

		missing = append(missing, "call_id")
	}
	if pushStringValue(data["caller_id"]) == "" {

		missing = append(missing, "caller_id")
	}
	if pushStringValue(data["caller_name"]) == "" {

		missing = append(missing, "caller_name")
	}
	if firstNonEmpty(

		pushStringValue(data["channel_name"]),

		pushStringValue(data["room_name"]),
	) == "" {

		missing = append(missing, "channel_name")
	}
	switch pushStringValue(data["call_type"]) {
	case "voice", "video":
	default:

		missing = append(missing, "call_type")
	}
	expiresAt, hasExpiry := parsePushExpiryTime(data["expires_at"])
	if !hasExpiry {

		missing = append(missing, "expires_at")
	}
	if len(missing) > 0 {

		sort.Strings(missing)

		return fmt.Errorf("invalid APNs VoIP payload fields: %s", strings.Join(missing, ","))
	}
	if !expiresAt.After(now) {

		return fmt.Errorf("invalid APNs VoIP payload: expires_at is not in the future")
	}
	return nil
}
func pushStringValue(value interface{}) string {
	text := strings.TrimSpace(fmt.Sprint(value))
	if text == "<nil>" {

		return ""
	}
	return text
}
func (s *PushService) sendAndroidPush(
	channel string,
	device models.UserDevice,
	title string,
	body string,
	data map[string]interface{}) error {
	if !s.isAndroidChannelEnabled(channel) {

		log.Printf("[Push] Android channel disabled, skip device=%s channel=%s", device.DeviceID, channel)

		return fmt.Errorf("Android 推送通道未启用: %s", channel)
	}
	switch channel {
	case PushChannelFCM:

		return s.sendFCMPush(device, title, body, data)
	case PushChannelHMS:

		return s.sendHMSPush(device, title, body, data)
	case PushChannelXiaomi:

		return s.sendXiaomiPush(device, title, body, data)
	case PushChannelOppo:

		return s.sendOppoPush(device, title, body, data)
	default:

		return fmt.Errorf("unsupported android push channel: %s", channel)
	}
}
func (s *PushService) isAndroidChannelEnabled(channel string) bool {
	s.configMu.RLock()
	cfg := s.androidConfig
	s.configMu.RUnlock()
	switch channel {
	case PushChannelFCM:

		return cfg.FCMEnabled
	case PushChannelHMS:

		return cfg.HMSEnabled
	case PushChannelXiaomi:

		return cfg.XiaomiEnabled
	case PushChannelOppo:

		return cfg.OppoEnabled
	default:

		return false
	}
}
func (s *PushService) sendWebPush(device models.UserDevice, title, body string, data map[string]interface{}) error {
	s.configMu.RLock()
	cfg := s.webPushConfig
	s.configMu.RUnlock()
	var subscription webpush.Subscription
	if err := json.Unmarshal([]byte(device.PushToken), &subscription); err != nil {

		return fmt.Errorf("invalid subscription json: %w", err)
	}
	if strings.TrimSpace(subscription.Endpoint) == "" ||

		strings.TrimSpace(subscription.Keys.Auth) == "" ||

		strings.TrimSpace(subscription.Keys.P256dh) == "" {

		return fmt.Errorf("invalid subscription")
	}
	payload := map[string]interface{}{

		"title": title,

		"body": body,

		"url": webPushNotificationURL(data),

		"tag": webPushNotificationTag(data),

		"data": data,
	}
	if imageURL := pushImageURLFromData(data); imageURL != "" {

		payload["image"] = imageURL
	}
	payloadBytes, err := json.Marshal(payload)
	if err != nil {

		return fmt.Errorf("marshal webpush payload failed: %w", err)
	}
	ctx, cancel := context.WithTimeout(context.Background(), 20*time.Second)
	defer cancel()
	resp, err := webpush.SendNotificationWithContext(ctx, payloadBytes, &subscription, &webpush.Options{

		HTTPClient: s.httpClient,

		Subscriber: cfg.Subject,

		VAPIDPublicKey: cfg.VAPIDPublicKey,

		VAPIDPrivateKey: cfg.VAPIDPrivateKey,

		TTL: cfg.TTL,

		Urgency: webpush.UrgencyHigh,
	})
	if resp != nil {

		defer resp.Body.Close()
		respBody, _ := io.ReadAll(resp.Body)

		if resp.StatusCode < 200 || resp.StatusCode >= 300 {

			return fmt.Errorf("webpush send failed: status=%d body=%s", resp.StatusCode, sanitizePushErrorBody(respBody))

		}
	}
	if err != nil {

		return fmt.Errorf("webpush send failed: %w", err)
	}
	log.Printf("[Push][WebPush] Sent push to device=%s", device.DeviceID)
	return nil
}
func webPushNotificationURL(data map[string]interface{}) string {
	if len(data) == 0 {

		return "/chats"
	}
	switch strings.TrimSpace(fmt.Sprint(data["type"])) {
	case "new_message":

		chatID := strings.TrimSpace(fmt.Sprint(data["chat_id"]))

		if chatID != "" {

			return "/chat/" + url.PathEscape(chatID)

		}
	case "incoming_call":

		values := url.Values{}

		values.Set("mode", "incoming")

		for _, key := range []string{

			"call_id",

			"channel_name",

			"room_name",

			"provider",

			"rtc_provider",

			"caller_id",

			"caller_name",

			"caller_avatar",

			"call_type",

			"chat_id",
		} {
			value := strings.TrimSpace(fmt.Sprint(data[key]))

			if value != "" && value != "<nil>" {

				values.Set(key, value)

			}

		}

		if values.Get("call_id") != "" {

			return "/call?" + values.Encode()

		}
	case "meeting_invite":

		meetingID := strings.TrimSpace(fmt.Sprint(data["meeting_id"]))

		if meetingID != "" {
			values := url.Values{}

			if chatID := strings.TrimSpace(fmt.Sprint(data["chat_id"])); chatID != "" && chatID != "<nil>" {

				values.Set("chat_id", chatID)

			}

			if meetingType := strings.TrimSpace(fmt.Sprint(data["meeting_type"])); meetingType != "" && meetingType != "<nil>" {

				values.Set("meeting_type", meetingType)

			}
			query := values.Encode()

			if query != "" {

				return "/meeting/" + url.PathEscape(meetingID) + "?" + query

			}

			return "/meeting/" + url.PathEscape(meetingID)

		}
	}
	return "/chats"
}
func webPushNotificationTag(data map[string]interface{}) string {
	if len(data) == 0 {

		return "genericim-h5"
	}
	for _, key := range []string{"chat_id", "call_id", "meeting_id"} {
		value := strings.TrimSpace(fmt.Sprint(data[key]))

		if value != "" && value != "<nil>" {

			return strings.TrimSpace(fmt.Sprint(data["type"])) + "-" + value

		}
	}
	return strings.TrimSpace(fmt.Sprint(data["type"]))
}
func pushDataType(data map[string]interface{}) string {
	if len(data) == 0 {

		return ""
	}
	return strings.TrimSpace(fmt.Sprint(data["type"]))
}
func pushImageURLFromData(data map[string]interface{}) string {
	for _, key := range []string{"image_url", "thumbnail", "media_url", "image"} {

		if imageURL := normalizePushImageURL(data[key]); imageURL != "" {

			return imageURL

		}
	}
	return ""
}
func pushImageURLFromStringData(data map[string]string) string {
	for _, key := range []string{"image_url", "thumbnail", "media_url", "image"} {

		if imageURL := normalizePushImageURL(data[key]); imageURL != "" {

			return imageURL

		}
	}
	return ""
}
func buildFCMRequestBody(deviceToken, title, body string, data map[string]interface{}) map[string]interface{} {
	return buildFCMRequestBodyForClient(deviceToken, title, body, data, false)
}
func buildFCMRequestBodyForClient(
	deviceToken, title, body string,
	data map[string]interface{},
	clientGatedNotifications bool) map[string]interface{} {
	dataMap := stringifyPushData(data)
	dataType := pushDataType(data)
	// Visible messages, announcements and meetings stay data-only for capable
	// Android clients so the device-local master switch runs before display. FCM
	// notification payloads are rendered by Google Play services while the app
	// is stopped and would bypass that final privacy gate.
	isClientGatedVisible := dataType == "new_message" || dataType == "chat_announcement" ||

		dataType == "system_announcement" ||

		dataType == "meeting_invite" || dataType == "meeting_join_request" ||

		dataType == "meeting_join_request_reviewed" || dataType == "meeting_status"
	isDataOnly := dataType == "incoming_call" || dataType == "message_revoked" ||

		(isClientGatedVisible && clientGatedNotifications)
	if isDataOnly {

		if dataMap == nil {

			dataMap = make(map[string]string)

		}

		if strings.TrimSpace(title) != "" {

			dataMap["title"] = title

		}

		if strings.TrimSpace(body) != "" {

			dataMap["body"] = body

		}
	}
	android := map[string]interface{}{

		"priority": "high",
	}
	if ttlSeconds, ok := incomingCallPushTTLSeconds(data, time.Now()); ok {

		android["ttl"] = fmt.Sprintf("%ds", ttlSeconds)
	}
	message := map[string]interface{}{

		"token": deviceToken,

		"android": android,
	}
	if !isDataOnly {
		notification := map[string]string{

			"title": title,

			"body": body,
		}

		if imageURL := pushImageURLFromStringData(dataMap); imageURL != "" {

			notification["image"] = imageURL

		}

		message["notification"] = notification

		androidNotification := map[string]string{

			"sound": "default",

			"channel_id": pushNotificationChannelID(dataType),
		}

		if tag := pushNotificationTag(dataType, dataMap); tag != "" {

			androidNotification["tag"] = tag

		}

		if imageURL := pushImageURLFromStringData(dataMap); imageURL != "" {

			androidNotification["image"] = imageURL

		}

		message["android"].(map[string]interface{})["notification"] = androidNotification
	}
	if len(dataMap) > 0 {

		message["data"] = dataMap
	}
	return map[string]interface{}{

		"message": message,
	}
}
func supportsClientGatedFCMNotifications(appVersion string) bool {
	return supportsMinimumClientBuild(appVersion, 26)
}
func supportsClientGatedFCMServiceNotifications(appVersion string) bool {
	return supportsMinimumClientBuild(appVersion, 27)
}
func supportsClientGatedFCMSystemNotifications(appVersion string) bool {
	return supportsMinimumClientBuild(appVersion, 28)
}
func supportsClientGatedFCMNotificationsForType(appVersion, dataType string) bool {
	switch strings.TrimSpace(dataType) {
	case "new_message", "chat_announcement":

		return supportsClientGatedFCMNotifications(appVersion)
	case "meeting_invite", "meeting_join_request", "meeting_join_request_reviewed", "meeting_status":

		return supportsClientGatedFCMServiceNotifications(appVersion)
	case "system_announcement":

		return supportsClientGatedFCMSystemNotifications(appVersion)
	default:

		return false
	}
}
func supportsMinimumClientBuild(appVersion string, minimumBuild int) bool {
	const minimumMajor = 5
	const minimumMinor = 0
	const minimumPatch = 0
	raw := strings.TrimSpace(appVersion)
	base, buildRaw, hasBuild := strings.Cut(raw, "+")
	parts := strings.Split(base, ".")
	if len(parts) < 3 {

		return false
	}
	major, majorErr := strconv.Atoi(parts[0])
	minor, minorErr := strconv.Atoi(parts[1])
	patch, patchErr := strconv.Atoi(parts[2])
	if majorErr != nil || minorErr != nil || patchErr != nil {

		return false
	}
	if major != minimumMajor {

		return major > minimumMajor
	}
	if minor != minimumMinor {

		return minor > minimumMinor
	}
	if patch != minimumPatch {

		return patch > minimumPatch
	}
	if !hasBuild {

		return false
	}
	build, err := strconv.Atoi(strings.TrimSpace(buildRaw))
	return err == nil && build >= minimumBuild
}
func pushNotificationTag(dataType string, data map[string]string) string {
	notificationID := strings.TrimSpace(data["notification_id"])
	if notificationID == "" {

		return ""
	}
	switch strings.TrimSpace(dataType) {
	case "new_message":

		return "genericim-message-" + notificationID
	case "chat_announcement":

		return "genericim-announcement-" + notificationID
	case "system_announcement":

		return "genericim-system-announcement-" + notificationID
	case "meeting_invite", "meeting_join_request", "meeting_join_request_reviewed", "meeting_status":

		return "genericim-meeting-" + notificationID
	default:

		return ""
	}
}
func pushNotificationChannelID(dataType string) string {
	switch strings.TrimSpace(dataType) {
	case "chat_announcement", "system_announcement", "group_notice":

		return "genericim_announcements_v1"
	case "incoming_call", "call_missed", "missed_call":

		return "genericim_calls_v1"
	case "meeting_invite", "meeting_join_request", "meeting_join_request_reviewed", "meeting_status":

		return "genericim_meetings_v1"
	default:

		return "genericim_messages"
	}
}
func buildHMSRequestBody(deviceToken, title, body string, data map[string]interface{}) map[string]interface{} {
	dataMap := make(map[string]interface{}, len(data)+2)
	for key, value := range data {

		dataMap[key] = value
	}
	if strings.TrimSpace(title) != "" {

		dataMap["title"] = title
	}
	if strings.TrimSpace(body) != "" {

		dataMap["body"] = body
	}
	android := map[string]interface{}{

		"urgency": "HIGH",

		"ttl": "86400s",
	}
	if ttlSeconds, ok := incomingCallPushTTLSeconds(data, time.Now()); ok {

		android["ttl"] = fmt.Sprintf("%ds", ttlSeconds)
	}
	message := map[string]interface{}{

		"token": []string{deviceToken},

		"android": android,
	}
	if dataString := marshalPushData(dataMap); dataString != "" {

		message["data"] = dataString
	}
	return map[string]interface{}{

		"validate_only": false,

		"message": message,
	}
}

const incomingCallMaxPushTTLSeconds int64 = 30 // incomingCallPushTTLSeconds keeps vendor queues inside the authoritative // ringing window. The mobile client still validates expires_at because a // provider can deliver a message that was already in flight when it expired.
func incomingCallPushTTLSeconds(data map[string]interface{}, now time.Time) (int64, bool) {
	if pushDataType(data) != "incoming_call" {

		return 0, false
	}
	expiresAt, ok := parsePushExpiryTime(data["expires_at"])
	if !ok {

		return incomingCallMaxPushTTLSeconds, true
	}
	remaining := expiresAt.Sub(now)
	if remaining <= 0 {

		// HMS expects a positive duration. One second is the shortest safe

		// cross-provider fallback; the native client will still suppress it.

		return 1, true
	}
	seconds := int64((remaining + time.Second - 1) / time.Second)
	if seconds > incomingCallMaxPushTTLSeconds {

		seconds = incomingCallMaxPushTTLSeconds
	}
	return seconds, true
}
func parsePushExpiryTime(value interface{}) (time.Time, bool) {
	switch typed := value.(type) {
	case time.Time:

		return typed, !typed.IsZero()
	case *time.Time:

		if typed == nil || typed.IsZero() {

			return time.Time{}, false

		}

		return *typed, true
	case string:

		raw := strings.TrimSpace(typed)

		if raw == "" {

			return time.Time{}, false

		}

		if parsed, err := time.Parse(time.RFC3339Nano, raw); err == nil {

			return parsed, true

		}

		if numeric, err := strconv.ParseInt(raw, 10, 64); err == nil {

			return pushUnixExpiryTime(numeric), true

		}
	case json.Number:

		if numeric, err := typed.Int64(); err == nil {

			return pushUnixExpiryTime(numeric), true

		}
	case int64:

		return pushUnixExpiryTime(typed), true
	case int:

		return pushUnixExpiryTime(int64(typed)), true
	case float64:

		return pushUnixExpiryTime(int64(typed)), true
	}
	return time.Time{}, false
}
func pushUnixExpiryTime(value int64) time.Time {
	if value >= 10_000_000_000 {

		return time.UnixMilli(value)
	}
	return time.Unix(value, 0)
}
func (s *PushService) sendFCMPush(device models.UserDevice, title, body string, data map[string]interface{}) error {
	s.configMu.RLock()
	cfg := s.androidConfig
	s.configMu.RUnlock()
	if strings.TrimSpace(cfg.FCMServiceAccountJSON) == "" {

		log.Printf("[Push][FCM] Config incomplete, skip device=%s", device.DeviceID)

		return fmt.Errorf("FCM 推送配置不完整")
	}
	requestBody := buildFCMRequestBodyForClient(

		device.PushToken,

		title,

		body,

		data,

		supportsClientGatedFCMNotificationsForType(device.AppVersion, pushDataType(data)),
	)
	bodyBytes, err := json.Marshal(requestBody)
	if err != nil {

		return fmt.Errorf("marshal fcm body failed: %w", err)
	}
	var lastErr error
	for attempt := 0; attempt < 2; attempt++ {

		accessToken, projectID, err := s.getFCMAccessToken()

		if err != nil {

			return err

		}
		endpoint := fmt.Sprintf("https://fcm.googleapis.com/v1/projects/%s/messages:send", projectID)
		req, err := http.NewRequest(http.MethodPost, endpoint, bytes.NewReader(bodyBytes))

		if err != nil {

			return fmt.Errorf("create fcm request failed: %w", err)

		}

		req.Header.Set("Content-Type", "application/json")

		req.Header.Set("Authorization", "Bearer "+accessToken)
		resp, err := s.httpClient.Do(req)

		if err != nil {

			return fmt.Errorf("send fcm request failed: %w", err)

		}
		respBody, _ := io.ReadAll(resp.Body)

		resp.Body.Close()

		if resp.StatusCode >= 200 && resp.StatusCode < 300 {

			log.Printf("[Push][FCM] Sent push to device=%s", device.DeviceID)

			return nil

		}

		if (resp.StatusCode == http.StatusUnauthorized || resp.StatusCode == http.StatusForbidden) && attempt == 0 {

			s.invalidateFCMToken()
			lastErr = fmt.Errorf("fcm auth failed: %s", sanitizePushErrorBody(respBody))

			continue

		}

		return fmt.Errorf("fcm send failed: status=%d body=%s", resp.StatusCode, sanitizePushErrorBody(respBody))
	}
	if lastErr != nil {

		return lastErr
	}
	return fmt.Errorf("fcm send failed")
}
func (s *PushService) sendHMSPush(device models.UserDevice, title, body string, data map[string]interface{}) error {
	s.configMu.RLock()
	cfg := s.androidConfig
	s.configMu.RUnlock()
	if strings.TrimSpace(cfg.HMSAppID) == "" || strings.TrimSpace(cfg.HMSAppSecret) == "" {

		log.Printf("[Push][HMS] Config incomplete, skip device=%s", device.DeviceID)

		return fmt.Errorf("HMS 推送配置不完整")
	}
	requestBody := buildHMSRequestBody(device.PushToken, title, body, data)
	bodyBytes, err := json.Marshal(requestBody)
	if err != nil {

		return fmt.Errorf("marshal hms body failed: %w", err)
	}
	endpoint := fmt.Sprintf("https://push-api.cloud.huawei.com/v1/%s/messages:send", strings.TrimSpace(cfg.HMSAppID))
	var lastErr error
	for attempt := 0; attempt < 2; attempt++ {

		token, err := s.getHMSAccessToken()

		if err != nil {

			return err

		}
		req, err := http.NewRequest(http.MethodPost, endpoint, bytes.NewReader(bodyBytes))

		if err != nil {

			return fmt.Errorf("create hms request failed: %w", err)

		}

		req.Header.Set("Content-Type", "application/json; charset=UTF-8")

		req.Header.Set("Authorization", "Bearer "+token)
		resp, err := s.httpClient.Do(req)

		if err != nil {

			return fmt.Errorf("send hms request failed: %w", err)

		}
		respBody, _ := io.ReadAll(resp.Body)

		resp.Body.Close()

		if resp.StatusCode < 200 || resp.StatusCode >= 300 {

			if (resp.StatusCode == http.StatusUnauthorized || resp.StatusCode == http.StatusForbidden) && attempt == 0 {

				s.invalidateHMSToken()
				lastErr = fmt.Errorf("hms auth failed: %s", sanitizePushErrorBody(respBody))

				continue

			}

			return fmt.Errorf("hms send failed: status=%d body=%s", resp.StatusCode, sanitizePushErrorBody(respBody))

		}
		var hmsResp struct {
			Code string `json:"code"`

			Msg string `json:"msg"`

			Message string `json:"message"`

			RequestID string `json:"requestId"`
		}
		requestID := ""

		if err := json.Unmarshal(respBody, &hmsResp); err == nil {

			requestID = hmsResp.RequestID

			if hmsResp.Code != "" && hmsResp.Code != "80000000" {

				return fmt.Errorf("hms send failed: code=%s msg=%s body=%s",

					hmsResp.Code, firstNonEmpty(hmsResp.Msg, hmsResp.Message), sanitizePushErrorBody(respBody))

			}

		}

		if requestID != "" {

			log.Printf("[Push][HMS] Sent push to device=%s request_id=%s", device.DeviceID, requestID)

		} else {

			log.Printf("[Push][HMS] Sent push to device=%s", device.DeviceID)

		}

		return nil
	}
	if lastErr != nil {

		return lastErr
	}
	return fmt.Errorf("hms send failed")
}
func (s *PushService) sendXiaomiPush(device models.UserDevice, title, body string, data map[string]interface{}) error {
	s.configMu.RLock()
	cfg := s.androidConfig
	s.configMu.RUnlock()
	if strings.TrimSpace(cfg.XiaomiPackageName) == "" || strings.TrimSpace(cfg.XiaomiAppSecret) == "" {

		log.Printf("[Push][Xiaomi] Config incomplete, skip device=%s", device.DeviceID)

		return fmt.Errorf("小米推送配置不完整")
	}
	form := url.Values{}
	form.Set("registration_id", strings.TrimSpace(device.PushToken))
	form.Set("title", title)
	form.Set("description", body)
	form.Set("payload", marshalPushData(data))
	form.Set("pass_through", "0")
	form.Set("notify_type", "1")
	form.Set("restricted_package_name", strings.TrimSpace(cfg.XiaomiPackageName))
	form.Set("extra.notify_foreground", "1")
	req, err := http.NewRequest(http.MethodPost, "https://api.xmpush.xiaomi.com/v3/message/regid", strings.NewReader(form.Encode()))
	if err != nil {

		return fmt.Errorf("create xiaomi request failed: %w", err)
	}
	req.Header.Set("Content-Type", "application/x-www-form-urlencoded")
	req.Header.Set("Authorization", "key="+strings.TrimSpace(cfg.XiaomiAppSecret))
	resp, err := s.httpClient.Do(req)
	if err != nil {

		return fmt.Errorf("send xiaomi request failed: %w", err)
	}
	respBody, _ := io.ReadAll(resp.Body)
	resp.Body.Close()
	if resp.StatusCode < 200 || resp.StatusCode >= 300 {

		return fmt.Errorf("xiaomi send failed: status=%d body=%s", resp.StatusCode, sanitizePushErrorBody(respBody))
	}
	var miResp struct {
		Result string `json:"result"`

		Code int `json:"code"`

		Description string `json:"description"`

		Reason string `json:"reason"`
	}
	if err := json.Unmarshal(respBody, &miResp); err == nil {
		successByResult := strings.EqualFold(strings.TrimSpace(miResp.Result), "ok")
		successByCode := miResp.Code == 0

		if !successByResult && !successByCode {

			return fmt.Errorf("xiaomi send failed: code=%d result=%s reason=%s body=%s",

				miResp.Code, miResp.Result, firstNonEmpty(miResp.Reason, miResp.Description), sanitizePushErrorBody(respBody))

		}
	}
	log.Printf("[Push][Xiaomi] Sent push to device=%s", device.DeviceID)
	return nil
}
func (s *PushService) sendOppoPush(device models.UserDevice, title, body string, data map[string]interface{}) error {
	s.configMu.RLock()
	cfg := s.androidConfig
	s.configMu.RUnlock()
	if strings.TrimSpace(cfg.OppoAppKey) == "" || strings.TrimSpace(cfg.OppoAppSecret) == "" {

		log.Printf("[Push][OPPO] Config incomplete, skip device=%s", device.DeviceID)

		return fmt.Errorf("OPPO 推送配置不完整")
	}
	messagePayload := map[string]interface{}{

		"target_type": 2,

		"target_value": strings.TrimSpace(device.PushToken),

		"verify_registration_id": true,

		"notification": map[string]interface{}{

			"app_message_id": fmt.Sprintf("oppo-%d", time.Now().UnixNano()),

			"title": title,

			"content": body,

			"click_action_type": 0,
		},
	}
	if channelID, ok := data["channel_id"]; ok {
		channelIDStr := strings.TrimSpace(fmt.Sprint(channelID))

		if channelIDStr != "" {

			messagePayload["notification"].(map[string]interface{})["channel_id"] = channelIDStr

		}
	}
	if category, ok := data["category"]; ok {
		categoryStr := strings.TrimSpace(fmt.Sprint(category))

		if categoryStr != "" {

			messagePayload["notification"].(map[string]interface{})["category"] = categoryStr

			// If category is set but notify_level is not provided, use default 16.

			if _, exists := data["notify_level"]; !exists {

				messagePayload["notification"].(map[string]interface{})["notify_level"] = 16

			}

		}
	}
	if notifyLevel, ok := data["notify_level"]; ok {
		levelStr := strings.TrimSpace(fmt.Sprint(notifyLevel))

		if levelInt, err := strconv.Atoi(levelStr); err == nil && levelInt > 0 {

			messagePayload["notification"].(map[string]interface{})["notify_level"] = levelInt

		}
	}
	messageJSON, err := json.Marshal(messagePayload)
	if err != nil {

		return fmt.Errorf("marshal oppo message failed: %w", err)
	}
	var lastErr error
	for attempt := 0; attempt < 2; attempt++ {

		authToken, host, err := s.getOppoAuthToken()

		if err != nil {

			return err

		}
		form := url.Values{}

		form.Set("auth_token", authToken)

		form.Set("message", string(messageJSON))
		endpoint := strings.TrimRight(host, "/") + "/server/v1/message/notification/unicast"

		req, err := http.NewRequest(http.MethodPost, endpoint, strings.NewReader(form.Encode()))

		if err != nil {

			return fmt.Errorf("create oppo request failed: %w", err)

		}

		req.Header.Set("Content-Type", "application/x-www-form-urlencoded")
		resp, err := s.httpClient.Do(req)

		if err != nil {

			return fmt.Errorf("send oppo request failed: %w", err)

		}
		respBody, _ := io.ReadAll(resp.Body)

		resp.Body.Close()

		if resp.StatusCode < 200 || resp.StatusCode >= 300 {

			if (resp.StatusCode == http.StatusUnauthorized || resp.StatusCode == http.StatusForbidden) && attempt == 0 {

				s.invalidateOppoAuthToken()
				lastErr = fmt.Errorf("oppo auth http failed: %d %s", resp.StatusCode, sanitizePushErrorBody(respBody))

				continue

			}

			return fmt.Errorf("oppo send failed: status=%d body=%s", resp.StatusCode, sanitizePushErrorBody(respBody))

		}
		var oppoResp struct {
			Code int `json:"code"`

			Message string `json:"message"`

			Data map[string]interface{} `json:"data"`
		}

		if err := json.Unmarshal(respBody, &oppoResp); err != nil {

			return fmt.Errorf("parse oppo send response failed: %w body=%s", err, sanitizePushErrorBody(respBody))

		}

		if oppoResp.Code != 0 {

			// code 29 is documented as "Missing Auth Token"; refresh and retry once.

			if oppoResp.Code == 29 && attempt == 0 {

				s.invalidateOppoAuthToken()
				lastErr = fmt.Errorf("oppo auth token invalid: code=%d msg=%s", oppoResp.Code, oppoResp.Message)

				continue

			}

			return fmt.Errorf("oppo send failed: code=%d msg=%s body=%s",

				oppoResp.Code, oppoResp.Message, sanitizePushErrorBody(respBody))

		}

		log.Printf("[Push][OPPO] Sent push to device=%s", device.DeviceID)

		return nil
	}
	if lastErr != nil {

		return lastErr
	}
	return fmt.Errorf("oppo send failed")
}
func (s *PushService) getFCMAccessToken() (string, string, error) {
	s.configMu.RLock()
	cfg := s.androidConfig
	if s.fcmAccessToken != "" && time.Now().Before(s.fcmTokenExpiry) {
		token := s.fcmAccessToken

		projectID := strings.TrimSpace(cfg.FCMProjectID)

		s.configMu.RUnlock()

		if projectID == "" {

			projectID = extractProjectIDFromServiceAccount(strings.TrimSpace(cfg.FCMServiceAccountJSON))

		}

		if projectID == "" {

			return "", "", fmt.Errorf("fcm project id is empty")

		}

		return token, projectID, nil
	}
	s.configMu.RUnlock()
	accountJSON := strings.TrimSpace(cfg.FCMServiceAccountJSON)
	if accountJSON == "" {

		return "", "", fmt.Errorf("fcm service account json is empty")
	}
	var account fcmServiceAccount
	if err := json.Unmarshal([]byte(accountJSON), &account); err != nil {

		return "", "", fmt.Errorf("parse fcm service account failed: %w", err)
	}
	projectID := strings.TrimSpace(cfg.FCMProjectID)
	if projectID == "" {

		projectID = strings.TrimSpace(account.ProjectID)
	}
	if projectID == "" {

		return "", "", fmt.Errorf("fcm project id is empty")
	}
	if strings.TrimSpace(account.ClientEmail) == "" || strings.TrimSpace(account.PrivateKey) == "" {

		return "", "", fmt.Errorf("fcm service account missing client_email/private_key")
	}
	tokenURI := strings.TrimSpace(account.TokenURI)
	if tokenURI == "" {

		tokenURI = "https://oauth2.googleapis.com/token"
	}
	privateKey, err := parseRSAPrivateKey([]byte(account.PrivateKey))
	if err != nil {

		return "", "", fmt.Errorf("parse fcm private key failed: %w", err)
	}
	now := time.Now()
	claims := jwt.MapClaims{

		"iss": account.ClientEmail,

		"sub": account.ClientEmail,

		"aud": tokenURI,

		"scope": "https://www.googleapis.com/auth/firebase.messaging",

		"iat": now.Unix(),

		"exp": now.Add(55 * time.Minute).Unix(),
	}
	jwtToken := jwt.NewWithClaims(jwt.SigningMethodRS256, claims)
	assertion, err := jwtToken.SignedString(privateKey)
	if err != nil {

		return "", "", fmt.Errorf("sign fcm jwt failed: %w", err)
	}
	form := url.Values{}
	form.Set("grant_type", "urn:ietf:params:oauth:grant-type:jwt-bearer")
	form.Set("assertion", assertion)
	req, err := http.NewRequest(http.MethodPost, tokenURI, strings.NewReader(form.Encode()))
	if err != nil {

		return "", "", fmt.Errorf("create fcm token request failed: %w", err)
	}
	req.Header.Set("Content-Type", "application/x-www-form-urlencoded")
	resp, err := s.httpClient.Do(req)
	if err != nil {

		return "", "", fmt.Errorf("request fcm token failed: %w", err)
	}
	respBody, _ := io.ReadAll(resp.Body)
	resp.Body.Close()
	if resp.StatusCode < 200 || resp.StatusCode >= 300 {

		return "", "", fmt.Errorf("request fcm token failed: status=%d body=%s",

			resp.StatusCode, sanitizePushErrorBody(respBody))
	}
	var tokenResp struct {
		AccessToken string `json:"access_token"`

		ExpiresIn int64 `json:"expires_in"`
	}
	if err := json.Unmarshal(respBody, &tokenResp); err != nil {

		return "", "", fmt.Errorf("parse fcm token response failed: %w", err)
	}
	if strings.TrimSpace(tokenResp.AccessToken) == "" {

		return "", "", fmt.Errorf("fcm token response missing access_token: %s", sanitizePushErrorBody(respBody))
	}
	expireAfter := time.Duration(tokenResp.ExpiresIn) * time.Second
	if expireAfter <= 0 {

		expireAfter = 55 * time.Minute
	}
	expireAt := now.Add(expireAfter - 60*time.Second)
	if expireAt.Before(now.Add(5 * time.Minute)) {

		expireAt = now.Add(5 * time.Minute)
	}
	s.configMu.Lock()
	s.fcmAccessToken = tokenResp.AccessToken
	s.fcmTokenExpiry = expireAt
	s.configMu.Unlock()
	return tokenResp.AccessToken, projectID, nil
}
func (s *PushService) invalidateFCMToken() {
	s.configMu.Lock()
	s.fcmAccessToken = ""
	s.fcmTokenExpiry = time.Time{}
	s.configMu.Unlock()
}
func (s *PushService) getHMSAccessToken() (string, error) {
	s.configMu.RLock()
	if s.hmsAccessToken != "" && time.Now().Before(s.hmsTokenExpiry) {
		token := s.hmsAccessToken

		s.configMu.RUnlock()

		return token, nil
	}
	cfg := s.androidConfig
	s.configMu.RUnlock()
	appID := strings.TrimSpace(cfg.HMSAppID)
	appSecret := strings.TrimSpace(cfg.HMSAppSecret)
	if appID == "" || appSecret == "" {

		return "", fmt.Errorf("hms app id/app secret is empty")
	}
	form := url.Values{}
	form.Set("grant_type", "client_credentials")
	form.Set("client_id", appID)
	form.Set("client_secret", appSecret)
	req, err := http.NewRequest(http.MethodPost, "https://oauth-login.cloud.huawei.com/oauth2/v3/token", strings.NewReader(form.Encode()))
	if err != nil {

		return "", fmt.Errorf("create hms token request failed: %w", err)
	}
	req.Header.Set("Content-Type", "application/x-www-form-urlencoded")
	resp, err := s.httpClient.Do(req)
	if err != nil {

		return "", fmt.Errorf("request hms token failed: %w", err)
	}
	respBody, _ := io.ReadAll(resp.Body)
	resp.Body.Close()
	if resp.StatusCode < 200 || resp.StatusCode >= 300 {

		return "", fmt.Errorf("request hms token failed: status=%d body=%s",

			resp.StatusCode, sanitizePushErrorBody(respBody))
	}
	var tokenResp struct {
		AccessToken string `json:"access_token"`

		ExpiresIn int64 `json:"expires_in"`
	}
	if err := json.Unmarshal(respBody, &tokenResp); err != nil {

		return "", fmt.Errorf("parse hms token response failed: %w", err)
	}
	if strings.TrimSpace(tokenResp.AccessToken) == "" {

		return "", fmt.Errorf("hms token response missing access_token: %s", sanitizePushErrorBody(respBody))
	}
	now := time.Now()
	expireAfter := time.Duration(tokenResp.ExpiresIn) * time.Second
	if expireAfter <= 0 {

		expireAfter = 30 * time.Minute
	}
	expireAt := now.Add(expireAfter - 60*time.Second)
	if expireAt.Before(now.Add(2 * time.Minute)) {

		expireAt = now.Add(2 * time.Minute)
	}
	s.configMu.Lock()
	s.hmsAccessToken = tokenResp.AccessToken
	s.hmsTokenExpiry = expireAt
	s.configMu.Unlock()
	return tokenResp.AccessToken, nil
}
func (s *PushService) invalidateHMSToken() {
	s.configMu.Lock()
	s.hmsAccessToken = ""
	s.hmsTokenExpiry = time.Time{}
	s.configMu.Unlock()
}
func (s *PushService) getOppoAuthToken() (string, string, error) {
	s.configMu.RLock()
	cfg := s.androidConfig
	if s.oppoAuthToken != "" && time.Now().Before(s.oppoTokenExpiry) && strings.TrimSpace(s.oppoAPIHost) != "" {
		token := s.oppoAuthToken

		host := s.oppoAPIHost

		s.configMu.RUnlock()

		return token, host, nil
	}
	s.configMu.RUnlock()
	appKey := strings.TrimSpace(cfg.OppoAppKey)
	appSecret := strings.TrimSpace(cfg.OppoAppSecret)
	if appKey == "" || appSecret == "" {

		return "", "", fmt.Errorf("oppo app key/app secret is empty")
	}
	timestamp := strconv.FormatInt(time.Now().UnixMilli(), 10)
	signBytes := sha256.Sum256([]byte(appKey + timestamp + appSecret))
	sign := hex.EncodeToString(signBytes[:])
	authRequest := url.Values{}
	authRequest.Set("app_key", appKey)
	authRequest.Set("timestamp", timestamp)
	authRequest.Set("sign", sign)
	hosts := []string{

		"https://api.push.oppomobile.com",

		"https://api-intl.push.oppomobile.com",
	}
	var lastErr error
	for _, host := range hosts {
		endpoint := strings.TrimRight(host, "/") + "/server/v1/auth"

		req, err := http.NewRequest(http.MethodPost, endpoint, strings.NewReader(authRequest.Encode()))

		if err != nil {

			lastErr = fmt.Errorf("create oppo auth request failed: %w", err)

			continue

		}

		req.Header.Set("Content-Type", "application/x-www-form-urlencoded")
		resp, err := s.httpClient.Do(req)

		if err != nil {

			lastErr = fmt.Errorf("request oppo auth token failed: %w", err)

			continue

		}
		respBody, _ := io.ReadAll(resp.Body)

		resp.Body.Close()

		if resp.StatusCode < 200 || resp.StatusCode >= 300 {

			lastErr = fmt.Errorf("request oppo auth token failed: status=%d body=%s",

				resp.StatusCode, sanitizePushErrorBody(respBody))

			continue

		}
		var authResp struct {
			Code int `json:"code"`

			Message string `json:"message"`

			Data struct {
				AuthToken string `json:"auth_token"`

				CreateTime int64 `json:"create_time"`
			} `json:"data"`
		}

		if err := json.Unmarshal(respBody, &authResp); err != nil {

			lastErr = fmt.Errorf("parse oppo auth response failed: %w body=%s", err, sanitizePushErrorBody(respBody))

			continue

		}

		if authResp.Code != 0 || strings.TrimSpace(authResp.Data.AuthToken) == "" {

			lastErr = fmt.Errorf("request oppo auth token failed: code=%d msg=%s body=%s",

				authResp.Code, authResp.Message, sanitizePushErrorBody(respBody))

			continue

		}
		now := time.Now()

		// Docs mention token valid up to 24h; refresh conservatively every ~1h.

		expireAt := now.Add(55 * time.Minute)

		s.configMu.Lock()

		s.oppoAuthToken = authResp.Data.AuthToken

		s.oppoTokenExpiry = expireAt

		s.oppoAPIHost = host

		s.configMu.Unlock()

		return authResp.Data.AuthToken, host, nil
	}
	if lastErr == nil {

		lastErr = fmt.Errorf("request oppo auth token failed")
	}
	return "", "", lastErr
}
func (s *PushService) invalidateOppoAuthToken() {
	s.configMu.Lock()
	s.oppoAuthToken = ""
	s.oppoTokenExpiry = time.Time{}
	s.oppoAPIHost = ""
	s.configMu.Unlock()
}
func extractProjectIDFromServiceAccount(rawJSON string) string {
	rawJSON = strings.TrimSpace(rawJSON)
	if rawJSON == "" {

		return ""
	}
	var account fcmServiceAccount
	if err := json.Unmarshal([]byte(rawJSON), &account); err != nil {

		return ""
	}
	return strings.TrimSpace(account.ProjectID)
}
func stringifyPushData(data map[string]interface{}) map[string]string {
	if len(data) == 0 {

		return nil
	}
	out := make(map[string]string, len(data))
	for key, value := range data {

		switch v := value.(type) {

		case string:

			out[key] = v

		default:

			encoded, err := json.Marshal(v)

			if err != nil {

				out[key] = fmt.Sprint(v)

			} else {

				out[key] = string(encoded)

			}

		}
	}
	return out
}
func marshalPushData(data map[string]interface{}) string {
	if len(data) == 0 {

		return "{}"
	}
	encoded, err := json.Marshal(data)
	if err != nil {

		return "{}"
	}
	return string(encoded)
}
func maskPushToken(token string) string {
	token = strings.TrimSpace(token)
	if token == "" {

		return "<empty>"
	}
	if len(token) <= 8 {

		return "***"
	}
	return token[:4] + "..." + token[len(token)-4:]
}
func sanitizePushErrorBody(body []byte) string {
	return sanitizePushErrorText(string(body))
}
func sanitizePushErrorText(text string) string {
	text = strings.TrimSpace(text)
	if text == "" {

		return ""
	}
	var decoded interface{}
	if err := json.Unmarshal([]byte(text), &decoded); err == nil {
		sanitized := sanitizePushValue(decoded)

		if encoded, err := json.Marshal(sanitized); err == nil {

			return truncatePushErrorText(string(encoded))

		}
	}
	return truncatePushErrorText(text)
}
func sanitizePushValue(value interface{}) interface{} {
	switch typed := value.(type) {
	case map[string]interface{}:

		out := make(map[string]interface{}, len(typed))

		for key, item := range typed {

			if isSensitivePushKey(key) {

				out[key] = "***"

				continue

			}

			out[key] = sanitizePushValue(item)

		}

		return out
	case []interface{}:

		out := make([]interface{}, len(typed))

		for i, item := range typed {

			out[i] = sanitizePushValue(item)

		}

		return out
	default:

		return value
	}
}
func isSensitivePushKey(key string) bool {
	key = strings.ToLower(strings.TrimSpace(key))
	switch key {
	case "token", "access_token", "auth_token", "registration_id", "target_value", "client_secret", "private_key", "authorization", "assertion", "sign":

		return true
	default:

		return strings.Contains(key, "token") || strings.Contains(key, "secret") || strings.Contains(key, "password")
	}
}
func truncatePushErrorText(text string) string {
	const maxLen = 800
	text = strings.TrimSpace(text)
	if len(text) <= maxLen {

		return text
	}
	return text[:maxLen] + "...(truncated)"
}
func firstNonEmpty(values ...string) string {
	for _, v := range values {

		if strings.TrimSpace(v) != "" {

			return strings.TrimSpace(v)

		}
	}
	return ""
}
func (s *PushService) sendAPNs(deviceToken string, payload APNsPayload, options ...APNsSendOptions) error {
	s.configMu.RLock()
	config := s.config
	s.configMu.RUnlock()
	if config == nil || config.BundleID == "" {

		return fmt.Errorf("APNs not configured")
	}
	host := "api.push.apple.com"
	if config.Environment == "development" {

		host = "api.sandbox.push.apple.com"
	}
	endpoint := fmt.Sprintf("https://%s/3/device/%s", host, deviceToken)
	payloadBytes, err := json.Marshal(payload)
	if err != nil {

		return err
	}
	req, err := http.NewRequest(http.MethodPost, endpoint, bytes.NewReader(payloadBytes))
	if err != nil {

		return err
	}
	pushType := "alert"
	topic := config.BundleID
	if len(options) > 0 {

		if value := strings.TrimSpace(options[0].PushType); value != "" {

			pushType = value

		}

		if suffix := strings.TrimSpace(options[0].TopicSuffix); suffix != "" {

			topic += suffix

		}
	}
	req.Header.Set("Content-Type", "application/json")
	req.Header.Set("apns-topic", topic)
	req.Header.Set("apns-push-type", pushType)
	req.Header.Set("apns-priority", "10")
	req.Header.Set("apns-expiration", "0")
	token, err := s.getJWT()
	if err != nil {

		return fmt.Errorf("failed to generate JWT: %v", err)
	}
	req.Header.Set("authorization", "bearer "+token)
	resp, err := s.apnsClient.Do(req)
	if err != nil {

		return err
	}
	defer resp.Body.Close()
	apnsID := strings.TrimSpace(resp.Header.Get("apns-id"))
	if resp.StatusCode != http.StatusOK {

		body, _ := io.ReadAll(resp.Body)

		return fmt.Errorf(

			"APNs error: status=%d apns_id=%s body=%s",

			resp.StatusCode,

			apnsID,

			sanitizePushErrorBody(body),
		)
	}
	log.Printf("[Push] Sent to token=%s successfully apns_id=%s", maskPushToken(deviceToken), apnsID)
	return nil
}
func (s *PushService) getJWT() (string, error) {
	s.configMu.RLock()
	if s.jwtToken != "" && time.Now().Before(s.jwtExpiry) {
		token := s.jwtToken

		s.configMu.RUnlock()

		return token, nil
	}
	config := s.config
	s.configMu.RUnlock()
	if config == nil || config.AuthKey == nil {

		return "", fmt.Errorf("auth key not configured")
	}
	now := time.Now()
	claims := jwt.MapClaims{

		"iss": config.TeamID,

		"iat": now.Unix(),
	}
	token := jwt.NewWithClaims(jwt.SigningMethodES256, claims)
	token.Header["kid"] = config.KeyID
	signedToken, err := token.SignedString(config.AuthKey)
	if err != nil {

		return "", err
	}
	s.configMu.Lock()
	s.jwtToken = signedToken
	s.jwtExpiry = now.Add(50 * time.Minute)
	s.configMu.Unlock()
	return signedToken, nil
}
func min(a, b int) int {
	if a < b {

		return a
	}
	return b
}
