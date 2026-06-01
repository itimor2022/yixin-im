package services

import (
	"bytes"
	"crypto/ecdsa"
	"crypto/rsa"
	"crypto/sha256"
	"crypto/tls"
	"crypto/x509"
	"encoding/hex"
	"encoding/json"
	"encoding/pem"
	"fmt"
	"io"
	"log"
	"net/http"
	"net/url"
	"strconv"
	"strings"
	"sync"
	"time"

	"gaoranim/internal/models"
	"gaoranim/internal/textutil"

	"github.com/golang-jwt/jwt/v5"
	"golang.org/x/net/http2"
	"gorm.io/gorm"
)

// APNsPayload is the APNs notification body.
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

// AndroidPushConfig stores multi-channel Android push settings.
type AndroidPushConfig struct {
	FCMEnabled            bool
	FCMProjectID          string
	FCMServiceAccountJSON string
	HMSEnabled            bool
	HMSAppID              string
	HMSAppSecret          string
	XiaomiEnabled         bool
	XiaomiPackageName     string
	XiaomiAppSecret       string
	OppoEnabled           bool
	OppoAppKey            string
	OppoAppSecret         string
}

type fcmServiceAccount struct {
	ProjectID   string `json:"project_id"`
	PrivateKey  string `json:"private_key"`
	ClientEmail string `json:"client_email"`
	TokenURI    string `json:"token_uri"`
}

// PushService sends APNs and Android vendor push notifications.
type PushService struct {
	db         *gorm.DB
	httpClient *http.Client
	apnsClient *http.Client

	config        *APNsConfig
	androidConfig AndroidPushConfig
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
			Timeout:   30 * time.Second,
		},
	}

	service.ReloadConfig()
	log.Printf("[Push] Push service initialized")
	return service
}

// ReloadConfig reloads APNs and Android push settings from DB.
func (s *PushService) ReloadConfig() {
	config := &APNsConfig{}
	androidConfig := AndroidPushConfig{}

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
		models.SettingXiaomiPushEnabled,
		models.SettingXiaomiPackageName,
		models.SettingXiaomiAppSecret,
		models.SettingOppoPushEnabled,
		models.SettingOppoAppKey,
		models.SettingOppoAppSecret,
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
		}
	}

	s.configMu.Lock()
	s.config = config
	s.androidConfig = androidConfig

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
		"[Push] Config reloaded: apns=%v, fcm=%v, hms=%v, xiaomi=%v, oppo=%v",
		config.Enabled,
		androidConfig.FCMEnabled,
		androidConfig.HMSEnabled,
		androidConfig.XiaomiEnabled,
		androidConfig.OppoEnabled,
	)
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
	s.configMu.RLock()
	config := s.config
	s.configMu.RUnlock()

	var devices []models.UserDevice
	s.db.Where("user_id = ? AND push_token != ''", userID).Find(&devices)
	if len(devices) == 0 {
		log.Printf("[Push] No push devices found for user %d", userID)
		return nil
	}

	seenTokens := make(map[string]struct{}, len(devices))
	uniqueDevices := make([]models.UserDevice, 0, len(devices))
	for _, device := range devices {
		token := strings.TrimSpace(device.PushToken)
		if token == "" {
			continue
		}
		channel := NormalizePushChannel(device.PushChannel, device.DeviceType)
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

	dataJSON, _ := json.Marshal(data)
	payload := APNsPayload{
		Aps: APNsAps{
			Alert: APNsAlert{
				Title: title,
				Body:  body,
			},
			Sound:          "default",
			MutableContent: 1,
		},
		Data: dataJSON,
	}

	for _, device := range uniqueDevices {
		go func(d models.UserDevice) {
			token := d.PushToken
			channel := NormalizePushChannel(d.PushChannel, d.DeviceType)

			var err error
			switch channel {
			case PushChannelAPNs:
				if config == nil || !config.Enabled {
					log.Printf("[Push] APNs disabled, skip iOS device: %s", d.DeviceID)
					s.recordPushDelivery(d, channel, title, body, fmt.Errorf("APNs 推送未启用"))
					return
				}
				err = s.sendAPNs(token, payload)
			case PushChannelFCM, PushChannelHMS, PushChannelXiaomi, PushChannelOppo:
				err = s.sendAndroidPush(channel, d, title, body, data)
			default:
				log.Printf("[Push] Unsupported channel for device %s: type=%s channel=%s", d.DeviceID, d.DeviceType, d.PushChannel)
				return
			}

			if err != nil {
				log.Printf("[Push] Failed to send %s push to device=%s token=%s: %v", channel, d.DeviceID, maskPushToken(token), err)
				s.recordPushDelivery(d, channel, title, body, err)
				if channel == PushChannelAPNs {
					if isInvalidPushTokenError(channel, err) {
						log.Printf("[Push] Removing invalid APNs token for device %s", d.DeviceID)
						s.db.Model(&models.UserDevice{}).Where("id = ?", d.ID).Update("push_token", "")
					}
				} else if isInvalidPushTokenError(channel, err) {
					log.Printf("[Push] Removing invalid Android token for device %s (channel=%s)", d.DeviceID, channel)
					s.db.Model(&models.UserDevice{}).Where("id = ?", d.ID).Update("push_token", "")
				} else {
					// Keep Android tokens on transient failures.
					log.Printf("[Push] Android push failed for device %s (channel=%s)", d.DeviceID, channel)
				}
			} else {
				s.recordPushDelivery(d, channel, title, body, nil)
			}
		}(device)
	}

	return nil
}

func (s *PushService) recordPushDelivery(device models.UserDevice, channel, title, body string, sendErr error) {
	if s == nil || s.db == nil {
		return
	}

	errText := ""
	if sendErr != nil {
		errText = truncatePushLogText(sendErr.Error(), 512)
	}
	now := time.Now()
	logItem := models.PushDeliveryLog{
		UserID:     device.UserID,
		DeviceID:   device.ID,
		DeviceKey:  truncatePushLogText(device.DeviceID, 100),
		Channel:    truncatePushLogText(channel, 20),
		Success:    sendErr == nil,
		Error:      errText,
		Title:      truncatePushLogText(title, 120),
		Body:       truncatePushLogText(body, 255),
		OccurredAt: now,
		CreatedAt:  now,
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

func isInvalidPushTokenError(channel string, err error) bool {
	if err == nil {
		return false
	}
	errText := strings.ToLower(err.Error())

	switch channel {
	case PushChannelAPNs:
		return strings.Contains(errText, "baddevicetoken") ||
			strings.Contains(errText, "unregistered") ||
			strings.Contains(errText, "devicetokennotfortopic")
	case PushChannelFCM:
		return strings.Contains(errText, "unregistered") ||
			strings.Contains(errText, "registration-token-not-registered") ||
			strings.Contains(errText, "invalid registration token") ||
			strings.Contains(errText, "not a valid fcm registration token")
	case PushChannelHMS:
		return strings.Contains(errText, "invalid token") ||
			strings.Contains(errText, "token invalid") ||
			strings.Contains(errText, "token does not exist")
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
	default:
		return false
	}
}

// PushNewMessage sends new-message push.
func (s *PushService) PushNewMessage(userID uint64, senderName, content, chatID, chatType string) error {
	title := senderName

	showPreview := true
	var setting models.UserPushSetting
	if err := s.db.Where("user_id = ?", userID).First(&setting).Error; err == nil {
		showPreview = setting.ShowPreview
	}

	var body string
	if showPreview {
		body = textutil.TruncateRunesWithSuffix(content, 100, "...")
	} else {
		body = "您收到一条新消息"
	}

	data := map[string]interface{}{
		"type":      "new_message",
		"chat_id":   chatID,
		"chat_type": chatType,
	}

	return s.PushToUser(userID, title, body, data)
}

// PushNewMessageWithBody 发送新消息推送（body 已由调用方计算好，跳过单行查询）
func (s *PushService) PushNewMessageWithBody(userID uint64, senderName, body, chatID, chatType string) error {
	data := map[string]interface{}{
		"type":      "new_message",
		"chat_id":   chatID,
		"chat_type": chatType,
	}
	return s.PushToUser(userID, senderName, body, data)
}

// PushCall sends incoming call push.
// PushNewMessageBatch 批量推送新消息通知（大群优化：一次查所有用户设备，避免 N 次单行查询）
// users: []struct{ID uint64, body string, senderName string}
type BatchPushUser struct {
	UserID     uint64
	SenderName string
	Body       string
}

// PushNewMessageBatch 批量推送新消息（大群优化：一次查所有用户设备，避免N次单行查询）
func (s *PushService) PushNewMessageBatch(users []BatchPushUser, chatID, chatType string) {
	if len(users) == 0 {
		return
	}

	// 一次查所有用户的设备
	userIDs := make([]uint64, 0, len(users))
	for _, u := range users {
		userIDs = append(userIDs, u.UserID)
	}

	var allDevices []models.UserDevice
	s.db.Where("user_id IN ? AND push_token != ''", userIDs).Find(&allDevices)
	if len(allDevices) == 0 {
		return
	}

	// 按 userID 分组设备
	deviceMap := make(map[uint64][]models.UserDevice, len(users))
	for _, d := range allDevices {
		deviceMap[d.UserID] = append(deviceMap[d.UserID], d)
	}

	data := map[string]interface{}{
		"type":      "new_message",
		"chat_id":   chatID,
		"chat_type": chatType,
	}

	// 并发推送，每个用户复用 PushToUser 逻辑，限制并发20
	sem := make(chan struct{}, 20)
	var wg sync.WaitGroup
	for _, u := range users {
		if _, hasDevice := deviceMap[u.UserID]; !hasDevice {
			continue
		}
		sem <- struct{}{}
		wg.Add(1)
		go func(pu BatchPushUser) {
			defer wg.Done()
			defer func() { <-sem }()
			_ = s.PushToUser(pu.UserID, pu.SenderName, pu.Body, data)
		}(u)
	}
	wg.Wait()
}

func (s *PushService) PushCall(userID uint64, callerName string, callID string, isVideo bool, extras ...map[string]interface{}) error {
	callType := "语音"
	if isVideo {
		callType = "视频"
	}

	title := callerName
	body := fmt.Sprintf("来电：%s通话", callType)

	data := map[string]interface{}{
		"type":     "incoming_call",
		"call_id":  callID,
		"is_video": isVideo,
	}
	for _, extra := range extras {
		for k, v := range extra {
			data[k] = v
		}
	}

	return s.PushToUser(userID, title, body, data)
}

// PushIncomingCall sends a call push with the fields required by mobile clients
// to render an incoming-call screen when the websocket is unavailable.
func (s *PushService) PushIncomingCall(userID uint64, callerName string, callID string, isVideo bool, data map[string]interface{}) error {
	callType := "voice"
	callTypeText := "\u8bed\u97f3"
	if isVideo {
		callType = "video"
		callTypeText = "\u89c6\u9891"
	}

	payload := map[string]interface{}{
		"type":        "incoming_call",
		"call_id":     callID,
		"caller_name": callerName,
		"call_type":   callType,
		"is_video":    isVideo,
	}
	for k, v := range data {
		payload[k] = v
	}

	return s.PushToUser(
		userID,
		callerName,
		fmt.Sprintf("\u6765\u7535: %s\u901a\u8bdd", callTypeText),
		payload,
	)
}

func (s *PushService) sendAndroidPush(
	channel string,
	device models.UserDevice,
	title string,
	body string,
	data map[string]interface{},
) error {
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

func (s *PushService) sendFCMPush(device models.UserDevice, title, body string, data map[string]interface{}) error {
	s.configMu.RLock()
	cfg := s.androidConfig
	s.configMu.RUnlock()
	if strings.TrimSpace(cfg.FCMServiceAccountJSON) == "" {
		log.Printf("[Push][FCM] Config incomplete, skip device=%s", device.DeviceID)
		return nil
	}

	dataMap := stringifyPushData(data)
	requestBody := map[string]interface{}{
		"message": map[string]interface{}{
			"token": device.PushToken,
			"notification": map[string]string{
				"title": title,
				"body":  body,
			},
			"android": map[string]interface{}{
				"priority": "high",
				"notification": map[string]string{
					"sound":      "default",
					"channel_id": "gaoranim_messages",
				},
			},
		},
	}
	if len(dataMap) > 0 {
		requestBody["message"].(map[string]interface{})["data"] = dataMap
	}
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
		return nil
	}

	dataString := marshalPushData(data)
	requestBody := map[string]interface{}{
		"validate_only": false,
		"message": map[string]interface{}{
			"token": []string{device.PushToken},
			"android": map[string]interface{}{
				"notification": map[string]string{
					"title": title,
					"body":  body,
				},
			},
		},
	}
	if dataString != "" {
		requestBody["message"].(map[string]interface{})["android"].(map[string]interface{})["data"] = dataString
	}
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
			Code    string `json:"code"`
			Msg     string `json:"msg"`
			Message string `json:"message"`
		}
		if err := json.Unmarshal(respBody, &hmsResp); err == nil {
			if hmsResp.Code != "" && hmsResp.Code != "80000000" {
				return fmt.Errorf("hms send failed: code=%s msg=%s body=%s",
					hmsResp.Code, firstNonEmpty(hmsResp.Msg, hmsResp.Message), sanitizePushErrorBody(respBody))
			}
		}

		log.Printf("[Push][HMS] Sent push to device=%s", device.DeviceID)
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
		return nil
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
		Result      string `json:"result"`
		Code        int    `json:"code"`
		Description string `json:"description"`
		Reason      string `json:"reason"`
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
		return nil
	}

	messagePayload := map[string]interface{}{
		"target_type":            2,
		"target_value":           strings.TrimSpace(device.PushToken),
		"verify_registration_id": true,
		"notification": map[string]interface{}{
			"app_message_id":    fmt.Sprintf("oppo-%d", time.Now().UnixNano()),
			"title":             title,
			"content":           body,
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
			Code    int                    `json:"code"`
			Message string                 `json:"message"`
			Data    map[string]interface{} `json:"data"`
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
		"iss":   account.ClientEmail,
		"sub":   account.ClientEmail,
		"aud":   tokenURI,
		"scope": "https://www.googleapis.com/auth/firebase.messaging",
		"iat":   now.Unix(),
		"exp":   now.Add(55 * time.Minute).Unix(),
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
		ExpiresIn   int64  `json:"expires_in"`
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
		ExpiresIn   int64  `json:"expires_in"`
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
			Code    int    `json:"code"`
			Message string `json:"message"`
			Data    struct {
				AuthToken  string `json:"auth_token"`
				CreateTime int64  `json:"create_time"`
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

func (s *PushService) sendAPNs(deviceToken string, payload APNsPayload) error {
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

	req.Header.Set("Content-Type", "application/json")
	req.Header.Set("apns-topic", config.BundleID)
	req.Header.Set("apns-push-type", "alert")
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

	if resp.StatusCode != http.StatusOK {
		body, _ := io.ReadAll(resp.Body)
		return fmt.Errorf("APNs error: %d - %s", resp.StatusCode, sanitizePushErrorBody(body))
	}

	log.Printf("[Push] Sent to token=%s successfully", maskPushToken(deviceToken))
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
