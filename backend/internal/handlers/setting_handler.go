package handlers

import (
	"encoding/json"
	"fmt"
	"net/http"
	"net/url"
	"regexp"
	"strconv"
	"strings"
	"time"
	"unicode/utf8"

	"gaoranim/internal/cache"
	"gaoranim/internal/config"
	"gaoranim/internal/middleware"
	"gaoranim/internal/models"
	"gaoranim/internal/services"
	"gaoranim/pkg/response"

	"github.com/gin-gonic/gin"
	"gorm.io/gorm"
)

// sensitiveSettingKeys 敏感配置项，对 demo_admin 隐藏
var sensitiveSettingKeys = map[string]bool{
	models.SettingAgoraAppID:            true,
	models.SettingAgoraAppCertificate:   true,
	models.SettingAPNsKeyID:             true,
	models.SettingAPNsTeamID:            true,
	models.SettingAPNsAuthKey:           true,
	models.SettingAPNsBundleID:          true,
	models.SettingFCMProjectID:          true,
	models.SettingFCMServiceAccountJSON: true,
	models.SettingHMSAppID:              true,
	models.SettingHMSAppSecret:          true,
	models.SettingXiaomiPackageName:     true,
	models.SettingXiaomiAppSecret:       true,
	models.SettingOppoAppKey:            true,
	models.SettingOppoAppSecret:         true,
	models.SettingPaymentGateway:        true,
	models.SettingSmsGateway:            true,
}

// PushConfigReloader 推送配置重载接口
type PushConfigReloader interface {
	ReloadConfig()
}

type SettingHandler struct {
	db          *gorm.DB
	pushService PushConfigReloader
	smsSvc      *services.SMSService
	cache       *cache.Cache // ★ 用于系统设置缓存失效
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

// SetCache 注入缓存实例，用于系统设置变更时主动失效缓存
func (h *SettingHandler) SetCache(c *cache.Cache) {
	h.cache = c
}

// ==================== 系统设置 ====================

// GetAllSettings 获取所有系统设置
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
	result := make(map[string]interface{})
	for _, s := range settings {
		// 演示管理员隐藏敏感配置
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
	if _, exists := result[models.SettingRegisterBaseURL]; !exists {
		result[models.SettingRegisterBaseURL] = resolveRegisterBaseURL(h.db)
	}
	if _, exists := result[models.SettingMessageCryptoMode]; !exists {
		result[models.SettingMessageCryptoMode] = models.MessageCryptoModePlain
	}
	if _, exists := result[models.SettingBurnAfterReadEnabled]; !exists {
		result[models.SettingBurnAfterReadEnabled] = true
	}

	response.Success(c, result)
}

// UpdateSettings 批量更新系统设置
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

		// 使用 Upsert（key是MySQL保留字，需要反引号）
		var setting models.SystemSetting
		result := h.db.Where("`key` = ?", key).First(&setting)
		if result.Error == gorm.ErrRecordNotFound {
			// 创建新设置
			setting = models.SystemSetting{
				Key:   key,
				Value: valueStr,
				Type:  valueType,
			}
			h.db.Create(&setting)
		} else {
			// 更新现有设置
			h.db.Model(&setting).Updates(map[string]interface{}{
				"value": valueStr,
				"type":  valueType,
			})
		}
	}

	// ★ 批量清除系统设置缓存，保证 RequirePhoneBind/getIntSetting/getStringSetting 读到最新值
	if h.cache != nil {
		ctx := c.Request.Context()
		for key := range req {
			_ = h.cache.DeleteSystemSetting(ctx, key)
		}
	}

	// 如果推送配置有变化，重新加载推送服务配置
	if hasPushConfigChange && h.pushService != nil {
		h.pushService.ReloadConfig()
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

func (h *SettingHandler) validateSystemSettingsForUpdate(req map[string]interface{}) error {
	for key := range req {
		if !isAllowedSystemSettingKey(key) {
			return fmt.Errorf("不支持的设置项：%s", key)
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

	if raw, exists := req[models.SettingRegisterBaseURL]; exists {
		if err := validateHTTPURLSetting("邀请注册链接域名", normalizeSettingInputValue(raw), true); err != nil {
			return err
		}
	}

	if raw, exists := req[models.SettingMessageCryptoMode]; exists {
		if !isValidMessageCryptoMode(normalizeSettingInputValue(raw)) {
			return fmt.Errorf("消息加密模式只能是 plain、compatible 或 strict")
		}
	}

	if hasCustomPortalSettingChange(req) {
		if err := h.validateCustomPortalSettingsForUpdate(req); err != nil {
			return err
		}
	}

	return nil
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
		models.SettingXiaomiPushEnabled,
		models.SettingXiaomiPackageName,
		models.SettingXiaomiAppSecret,
		models.SettingOppoPushEnabled,
		models.SettingOppoAppKey,
		models.SettingOppoAppSecret,
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

	return nil
}

func isAllowedSystemSettingKey(key string) bool {
	switch key {
	case models.SettingAppVersionIOS,
		models.SettingAppVersionAndroid,
		models.SettingAppForceUpdate,
		models.SettingAppUpdateURL,
		models.SettingAppUpdateMessage,
		models.SettingSystemName,
		models.SettingSystemVersion,
		models.SettingRegisterBaseURL,
		models.SettingAllowRegister,
		models.SettingRequireInviteCode,
		models.SettingRequirePhoneBind,
		models.SettingBurnAfterReadEnabled,
		models.SettingMessageCryptoMode,
		models.SettingEnableMomentPost,
		models.SettingMomentPostReviewEnabled,
		models.SettingNewUserFollowOfficial,
		models.SettingInviteRegisterBindOnly,
		models.SettingNewUserJoinGroup,
		models.SettingNewUserJoinChannel,
		models.SettingGroupInviteRequireFriend,
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
		models.SettingAgoraEnabled,
		models.SettingAgoraAppID,
		models.SettingAgoraAppCertificate,
		models.SettingAgoraTokenExpire,
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
		models.SettingUserAgreement,
		models.SettingPrivacyPolicy,
		models.SettingRevokeMessageMinutes,
		models.SettingIPRateLimit,
		models.SettingUserRateLimit,
		models.SettingPaymentGateway,
		models.SettingSmsGateway:
		return true
	default:
		return false
	}
}

// isPushSetting 检查是否是推送相关配置
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
		models.SettingXiaomiPushEnabled,
		models.SettingXiaomiPackageName,
		models.SettingXiaomiAppSecret,
		models.SettingOppoPushEnabled,
		models.SettingOppoAppKey,
		models.SettingOppoAppSecret:
		return true
	}
	return false
}

// GetSetting 获取单个设置
func (h *SettingHandler) GetSetting(c *gin.Context) {
	key := c.Param("key")

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
}

// ==================== 官方用户管理 ====================

// GetOfficialUsers 获取官方用户列表
func (h *SettingHandler) GetOfficialUsers(c *gin.Context) {
	var officials []models.OfficialUser
	h.db.Order("sort_order ASC, created_at ASC").Find(&officials)

	// 获取用户详细信息
	type OfficialUserDetail struct {
		models.OfficialUser
		Username   string `json:"username"`
		Nickname   string `json:"nickname"`
		Avatar     string `json:"avatar"`
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
				Username:     user.Username,
				Nickname:     user.Nickname,
				Avatar:       user.Avatar,
				InviteCode:   inviteCode,
			})
		}
	}

	response.Success(c, result)
}

// AddOfficialUser 添加官方用户
func (h *SettingHandler) AddOfficialUser(c *gin.Context) {
	var req struct {
		Username       string `json:"username"`  // 支持用户名搜索
		UserUUID       string `json:"user_uuid"` // 也支持直接用UUID
		Remark         string `json:"remark"`
		WelcomeMessage string `json:"welcome_message"` // 官方客服欢迎语
		InviteCode     string `json:"invite_code"`
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
			"user_uuid":          official.UserUUID,
			"remark":             official.Remark,
			"welcome_message":    official.WelcomeMessage,
			"is_service_enabled": true,
			"deleted_at":         nil,
		}).Error; err != nil {
			tx.Rollback()
			response.Error(c, http.StatusInternalServerError, "添加失败")
			return
		}
	} else {
		official = models.OfficialUser{
			UserID:           user.ID,
			UserUUID:         user.UUID,
			Remark:           req.Remark,
			WelcomeMessage:   req.WelcomeMessage,
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
		"id":          official.ID,
		"user_id":     user.ID,
		"uuid":        user.UUID,
		"username":    user.Username,
		"nickname":    user.Nickname,
		"invite_code": invite.Code,
	})
}

// UpdateOfficialUser 更新官方用户配置（欢迎语/状态/备注）
func (h *SettingHandler) UpdateOfficialUser(c *gin.Context) {
	id := c.Param("id")
	var official models.OfficialUser
	if err := h.db.Where("id = ?", id).First(&official).Error; err != nil {
		response.Error(c, http.StatusNotFound, "官方用户不存在")
		return
	}

	var req struct {
		Remark           *string `json:"remark"`
		WelcomeMessage   *string `json:"welcome_message"`
		IsServiceEnabled *bool   `json:"is_service_enabled"`
		InviteCode       *string `json:"invite_code"`
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
}

// RemoveOfficialUser 移除官方用户
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
}

// GetOfficialUserInvitees 获取某官方客服通过邀请码注册的用户列表
func (h *SettingHandler) GetOfficialUserInvitees(c *gin.Context) {
	id := c.Param("id")

	var official models.OfficialUser
	if err := h.db.Select("id", "user_id").Where("id = ?", id).First(&official).Error; err != nil {
		response.Error(c, http.StatusNotFound, "官方用户不存在")
		return
	}

	type InviteeItem struct {
		UsageID      uint64    `json:"usage_id"`
		UserID       uint64    `json:"user_id"`
		UserUUID     string    `json:"user_uuid"`
		Username     string    `json:"username"`
		Nickname     string    `json:"nickname"`
		Avatar       string    `json:"avatar"`
		InviteCode   string    `json:"invite_code"`
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
		"list":  list,
	})
}

// ==================== 官方群组管理 ====================

// GetOfficialGroups 获取官方群组列表
func (h *SettingHandler) GetOfficialGroups(c *gin.Context) {
	var officials []models.OfficialGroup
	h.db.Order("sort_order ASC, created_at ASC").Find(&officials)

	type OfficialGroupDetail struct {
		models.OfficialGroup
		Name        string `json:"name"`
		Username    string `json:"username"`
		Avatar      string `json:"avatar"`
		MemberCount int    `json:"member_count"`
	}

	var result []OfficialGroupDetail
	for _, o := range officials {
		var chat models.Chat
		if h.db.First(&chat, o.ChatID).Error == nil {
			result = append(result, OfficialGroupDetail{
				OfficialGroup: o,
				Name:          chat.Name,
				Username:      chat.Username,
				Avatar:        chat.Avatar,
				MemberCount:   chat.MemberCount,
			})
		}
	}

	response.Success(c, result)
}

// AddOfficialGroup 添加官方群组（支持 UUID 或用户名）
func (h *SettingHandler) AddOfficialGroup(c *gin.Context) {
	var req struct {
		ChatUUID string `json:"chat_uuid"` // UUID 或用户名
		Username string `json:"username"`  // 群组用户名
		Remark   string `json:"remark"`
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
		ChatID:   chat.ID,
		ChatUUID: chat.UUID,
		Remark:   req.Remark,
	}

	if err := h.db.Create(&official).Error; err != nil {
		response.Error(c, http.StatusInternalServerError, "添加失败")
		return
	}

	response.SuccessWithMessage(c, "已添加官方群组", gin.H{
		"id":      official.ID,
		"chat_id": chat.ID,
		"uuid":    chat.UUID,
		"name":    chat.Name,
	})
}

// RemoveOfficialGroup 移除官方群组
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
}

// ==================== 官方频道管理 ====================

// GetOfficialChannels 获取官方频道列表
func (h *SettingHandler) GetOfficialChannels(c *gin.Context) {
	var officials []models.OfficialChannel
	h.db.Order("sort_order ASC, created_at ASC").Find(&officials)

	type OfficialChannelDetail struct {
		models.OfficialChannel
		Name        string `json:"name"`
		Username    string `json:"username"`
		Avatar      string `json:"avatar"`
		MemberCount int    `json:"member_count"`
	}

	var result []OfficialChannelDetail
	for _, o := range officials {
		var chat models.Chat
		if h.db.First(&chat, o.ChatID).Error == nil {
			result = append(result, OfficialChannelDetail{
				OfficialChannel: o,
				Name:            chat.Name,
				Username:        chat.Username,
				Avatar:          chat.Avatar,
				MemberCount:     chat.MemberCount,
			})
		}
	}

	response.Success(c, result)
}

// AddOfficialChannel 添加官方频道（支持 UUID 或用户名）
func (h *SettingHandler) AddOfficialChannel(c *gin.Context) {
	var req struct {
		ChatUUID string `json:"chat_uuid"` // UUID 或用户名
		Username string `json:"username"`  // 频道用户名
		Remark   string `json:"remark"`
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
		ChatID:   chat.ID,
		ChatUUID: chat.UUID,
		Remark:   req.Remark,
	}

	if err := h.db.Create(&official).Error; err != nil {
		response.Error(c, http.StatusInternalServerError, "添加失败")
		return
	}

	response.SuccessWithMessage(c, "已添加官方频道", gin.H{
		"id":      official.ID,
		"chat_id": chat.ID,
		"uuid":    chat.UUID,
		"name":    chat.Name,
	})
}

// RemoveOfficialChannel 移除官方频道
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
}

// ==================== App端接口（无需管理员权限） ====================

// GetAppSettings 获取App端需要的系统设置（公开接口）
func (h *SettingHandler) GetAppSettings(c *gin.Context) {
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

	response.Success(c, gin.H{
		// App版本
		"app_version_ios":     settingMap[models.SettingAppVersionIOS],
		"app_version_android": settingMap[models.SettingAppVersionAndroid],
		"system_name":         settingMap[models.SettingSystemName],
		"system_version":      settingMap[models.SettingSystemVersion],
		"register_base_url":   resolveRegisterBaseURL(h.db),
		"app_force_update":    isSystemSettingTrue(settingMap[models.SettingAppForceUpdate]),
		"app_update_url":      settingMap[models.SettingAppUpdateURL],
		"app_update_message":  settingMap[models.SettingAppUpdateMessage],
		// 功能开关
		"allow_register":              !isSystemSettingFalse(settingMap[models.SettingAllowRegister]), // 默认允许
		"require_invite_code":         isSystemSettingTrue(settingMap[models.SettingRequireInviteCode]),
		"require_phone_bind":          isSystemSettingTrue(settingMap[models.SettingRequirePhoneBind]),
		"enable_moment_post":          !isSystemSettingFalse(settingMap[models.SettingEnableMomentPost]), // 默认允许发布
		"moment_post_review_enabled":  isSystemSettingTrue(settingMap[models.SettingMomentPostReviewEnabled]),
		"new_user_follow_official":    isSystemSettingTrue(settingMap[models.SettingNewUserFollowOfficial]),
		"invite_register_bind_only":   isSystemSettingTrue(settingMap[models.SettingInviteRegisterBindOnly]),
		"new_user_join_group":         isSystemSettingTrue(settingMap[models.SettingNewUserJoinGroup]),
		"new_user_join_channel":       isSystemSettingTrue(settingMap[models.SettingNewUserJoinChannel]),
		"group_invite_require_friend": isSystemSettingTrue(settingMap[models.SettingGroupInviteRequireFriend]),
		"custom_portal_enabled":       isSystemSettingTrue(settingMap[models.SettingCustomPortalEnabled]),
		"custom_portal_title":         settingMap[models.SettingCustomPortalTitle],
		"custom_portal_url":           settingMap[models.SettingCustomPortalURL],
		"custom_portal_icon_url":      settingMap[models.SettingCustomPortalIconURL],
		"burn_after_read_enabled":     !isSystemSettingFalse(settingMap[models.SettingBurnAfterReadEnabled]),
		"message_crypto_mode":         normalizeMessageCryptoMode(settingMap[models.SettingMessageCryptoMode]),
		// 官方用户/群组/频道
		"official_users":    officialUserUUIDs,
		"official_groups":   officialGroupUUIDs,
		"official_channels": officialChannelUUIDs,
		// 文件大小限制 (MB)
		"max_image_size": maxImageSize,
		"max_video_size": maxVideoSize,
		"max_file_size":  maxFileSize,
		"max_voice_size": maxVoiceSize,
		// 消息撤回时限（分钟）
		"revoke_message_minutes": revokeMessageMinutes,
		// 短信绑定：后台已配置且可发验证码时 App 可展示绑定入口
		"sms_bind_ready": config.GlobalConfig != nil && services.SMSSendReady(h.db, config.GlobalConfig.SMS),
	})
}

// CheckUserOfficial 检查用户是否是官方用户
func (h *SettingHandler) CheckUserOfficial(c *gin.Context) {
	userUUID := c.Param("uuid")

	var count int64
	h.db.Model(&models.OfficialUser{}).
		Where("user_uuid = ? AND is_service_enabled = ?", userUUID, true).
		Count(&count)

	response.Success(c, gin.H{
		"is_official": count > 0,
	})
}

// CheckChatOfficial 检查群组/频道是否是官方
func (h *SettingHandler) CheckChatOfficial(c *gin.Context) {
	chatUUID := c.Param("uuid")

	var groupCount, channelCount int64
	h.db.Model(&models.OfficialGroup{}).Where("chat_uuid = ?", chatUUID).Count(&groupCount)
	h.db.Model(&models.OfficialChannel{}).Where("chat_uuid = ?", chatUUID).Count(&channelCount)

	response.Success(c, gin.H{
		"is_official": groupCount > 0 || channelCount > 0,
	})
}

// SyncOfficialContacts 同步官方用户到联系人（用户调用）
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
			"added":   0,
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
			"added":   0,
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
		"added":   addedCount,
		"message": fmt.Sprintf("已添加 %d 个官方用户为好友", addedCount),
	})
}

// GetMyOfficialServiceProfile 获取当前登录用户的官方客服配置
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
		"is_official":        true,
		"official_user_id":   official.ID,
		"welcome_message":    welcome,
		"is_service_enabled": official.IsServiceEnabled,
	})
}

// UpdateMyOfficialServiceProfile 更新当前登录用户的官方客服欢迎语
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
}

// ==================== 公开协议 API（无需登录） ====================

// GetUserAgreement 获取用户协议
func (h *SettingHandler) GetUserAgreement(c *gin.Context) {
	var setting models.SystemSetting
	if err := h.db.Where("`key` = ?", models.SettingUserAgreement).First(&setting).Error; err != nil {
		// 返回默认协议内容
		response.Success(c, gin.H{
			"title":      "用户协议",
			"content":    getDefaultUserAgreement(),
			"updated_at": nil,
		})
		return
	}

	response.Success(c, gin.H{
		"title":      "用户协议",
		"content":    setting.Value,
		"updated_at": setting.UpdatedAt,
	})
}

// GetPrivacyPolicy 获取隐私政策
func (h *SettingHandler) GetPrivacyPolicy(c *gin.Context) {
	var setting models.SystemSetting
	if err := h.db.Where("`key` = ?", models.SettingPrivacyPolicy).First(&setting).Error; err != nil {
		// 返回默认隐私政策内容
		response.Success(c, gin.H{
			"title":      "隐私政策",
			"content":    getDefaultPrivacyPolicy(),
			"updated_at": nil,
		})
		return
	}

	response.Success(c, gin.H{
		"title":      "隐私政策",
		"content":    setting.Value,
		"updated_at": setting.UpdatedAt,
	})
}

// 默认用户协议
func getDefaultUserAgreement() string {
	return `# 用户协议

欢迎使用壹信IM！

## 一、服务条款的接受

在使用本应用前，请您仔细阅读本协议的全部内容。如果您不同意本协议的任何条款，请不要使用本应用。使用本应用即表示您同意接受本协议的所有条款。

## 二、用户账号

1. 您需要注册账号才能使用本应用的全部功能
2. 您应当妥善保管账号信息，对账号下的所有行为负责
3. 禁止将账号转让、出借给他人使用

## 三、用户行为规范

在使用本应用时，您承诺：
1. 不发布违法、有害、威胁、辱骂、骚扰、诽谤、侵权内容
2. 不发布垃圾信息或广告
3. 不进行任何可能损害本应用正常运营的行为
4. 遵守中华人民共和国相关法律法规

## 四、知识产权

本应用的所有内容，包括但不限于文字、图片、软件、音频、视频等，均受著作权法保护。未经许可，不得复制、修改、传播。

## 五、免责声明

1. 本应用按"现状"提供服务，不提供任何明示或暗示的担保
2. 对于用户发布的内容，本应用不承担任何责任
3. 因不可抗力导致的服务中断，本应用不承担责任

## 六、协议修改

我们保留随时修改本协议的权利。修改后的协议一经发布即生效。

## 七、联系我们

如有任何问题，请通过应用内的反馈功能联系我们。

---
最后更新日期：2024年1月`
}

// 默认隐私政策
func getDefaultPrivacyPolicy() string {
	return `# 隐私政策

本隐私政策说明我们如何收集、使用和保护您的个人信息。

## 一、信息收集

我们可能收集以下类型的信息：

### 1. 账号信息
- 用户名、昵称
- 头像
- 个人简介

### 2. 设备信息
- 设备型号
- 操作系统版本
- 设备标识符

### 3. 使用信息
- 登录时间
- 功能使用情况

### 4. 通讯内容
- 您发送的消息（端对端加密传输）
- 分享的媒体文件

## 二、信息使用

我们使用收集的信息用于：
1. 提供、维护和改进服务
2. 发送通知和更新
3. 保障账号安全
4. 遵守法律法规要求

## 三、信息保护

我们采取以下措施保护您的信息：
1. 使用加密技术保护数据传输
2. 限制员工访问用户数据的权限
3. 定期审查安全措施

## 四、信息共享

除以下情况外，我们不会与第三方共享您的个人信息：
1. 经您明确同意
2. 法律法规要求
3. 保护我们或他人的权益

## 五、您的权利

您有权：
1. 访问您的个人信息
2. 更正不准确的信息
3. 删除您的账号和数据
4. 撤回同意

## 六、Cookie 和类似技术

我们可能使用 Cookie 来改善用户体验和分析使用情况。

## 七、未成年人保护

本应用不面向未满 14 周岁的儿童。如果您是未成年人，请在监护人指导下使用本应用。

## 八、隐私政策更新

我们可能不时更新本隐私政策。重大变更时，我们会通过应用内通知您。

## 九、联系我们

如对本隐私政策有任何疑问，请通过应用内的反馈功能联系我们。

---
最后更新日期：2024年1月`
}
