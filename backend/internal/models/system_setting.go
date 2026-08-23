// 文件用途：定义业务实体的 ORM 字段、关联关系和持久化约束。
// 核心逻辑：统一描述字段映射、状态值、索引和表名，作为各层共享数据契约。

package models

import (
	"gorm.io/gorm" // SystemSetting 系统设置表
	"time"
)

type SystemSetting struct {
	ID        uint64         `gorm:"primaryKey;autoIncrement" json:"id"`
	Key       string         `gorm:"type:varchar(100);uniqueIndex;not null" json:"key"`
	Value     string         `gorm:"type:text" json:"value"`
	Type      string         `gorm:"type:varchar(20);default:'string'" json:"type"` // string, int, bool, json
	Remark    string         `gorm:"type:varchar(500)" json:"remark"`
	CreatedAt time.Time      `gorm:"type:datetime;not null" json:"created_at"`
	UpdatedAt time.Time      `gorm:"type:datetime;not null" json:"updated_at"`
	DeletedAt gorm.DeletedAt `gorm:"index" json:"-"`
}

func (SystemSetting) TableName() string {
	return "system_settings"
}

// 系统设置键名常量
const (
	// App版本设置
	SettingAppVersionIOS              = "app_version_ios"               // iOS当前版本
	SettingAppVersionAndroid          = "app_version_android"           // Android当前版本
	SettingLatestVersionIOS           = "latest_version_ios"            // iOS最新版本（新字段）
	SettingLatestVersionAndroid       = "latest_version_android"        // Android最新版本（新字段）
	SettingAppForceUpdate             = "app_force_update"              // 是否强制更新
	SettingAppUpdateURL               = "app_update_url"                // 更新下载链接
	SettingAppUpdateMessage           = "app_update_message"            // 更新提示信息
	SettingAppUpdateURLIOS            = "app_update_url_ios"            // iOS App Store 更新链接
	SettingAppUpdateURLAndroid        = "app_update_url_android"        // Android 更新链接
	SettingMinSupportedVersionIOS     = "min_supported_version_ios"     // iOS 最低支持版本
	SettingMinSupportedVersionAndroid = "min_supported_version_android" // Android 最低支持版本
	SettingSplashEnabled              = "splash_enabled"                // 是否启用自定义启动页
	SettingSplashImageURL             = "splash_image_url"              // 自定义启动页图片
	SettingSplashDurationMs           = "splash_duration_ms"            // 启动页最短展示时长（毫秒）
	// 基本信息
	SettingSystemName       = "system_name"        // 系统名称
	SettingSystemVersion    = "system_version"     // 系统版本
	SettingRegisterBaseURL  = "register_base_url"  // 注册页/邀请链接外部访问域名
	SettingSupportOnlineURL = "support_online_url" // 在线客服链接
	SettingSupportQQ        = "support_qq"         // QQ 客服号
	// 用户设置
	SettingAllowRegister            = "allow_register"              // 是否允许注册
	SettingAllowQuickRegister       = "allow_quick_register"        // 是否允许一键注册并登录
	SettingQuickRegisterDeviceLimit = "quick_register_device_limit" // 单设备每日一键注册上限
	SettingQuickRegisterIPLimit     = "quick_register_ip_limit"     // 单IP每日一键注册上限
	SettingForceKeepAliveEnabled    = "force_keep_alive_enabled"    // 全局强制保活
	SettingRequireInviteCode        = "require_invite_code"         // 注册是否必须填写邀请码
	SettingRequireGenderOnRegister  = "require_gender_on_register"  // 注册是否必须选择性别
	SettingRequirePhoneBind         = "require_phone_bind"          // 是否强制绑定手机号
	SettingUserInviteCodeLength    = "user_invite_code_length"     // 新用户个人邀请码位数（4-12，默认 6）
	SettingEnableMomentPost         = "enable_moment_post"          // 是否允许发布动态（关闭后用户只能浏览）
	SettingMomentPostReviewEnabled  = "moment_post_review_enabled"  // 动态发布是否启用审核
	SettingCheckinEnabled           = "checkin_enabled"            // 签到功能开关
	SettingIOSCompliance            = "ios_compliance"              // iOS 合规模式及细分功能开关 JSON
	SettingNewUserFollowOfficial    = "new_user_follow_official"    // 新用户是否强制关注官方用户
	SettingInviteRegisterBindOnly   = "invite_register_bind_only"   // 邀请码注册用户只自动添加邀请码绑定客服
	SettingNewUserJoinGroup         = "new_user_join_group"         // 新用户是否强制加入官方群组
	SettingNewUserJoinChannel       = "new_user_join_channel"       // 新用户是否强制订阅官方频道
	SettingGroupInviteRequireFriend = "group_invite_require_friend" // 开启后只能邀请自己的联系人进群
	SettingFriendAddMode            = "friend_add_mode"             // 加好友方式：direct / approval / disabled
	SettingVipFreeEntitlements      = "vip_free_entitlements"       // 普通用户默认权益 JSON
	// 客户端自定义栏目
	SettingCustomPortalEnabled = "custom_portal_enabled"  // 是否启用联系人与发现之间的自定义栏目
	SettingCustomPortalTitle   = "custom_portal_title"    // 自定义栏目标题
	SettingCustomPortalURL     = "custom_portal_url"      // 自定义栏目访问网址
	SettingCustomPortalIconURL = "custom_portal_icon_url" // 自定义栏目图标
	// 官方用户/群组/频道
	SettingOfficialUsers    = "official_users"    // 官方用户列表 (JSON数组: ["uuid1", "uuid2"])
	SettingOfficialGroups   = "official_groups"   // 官方群组列表 (JSON数组: ["uuid1", "uuid2"])
	SettingOfficialChannels = "official_channels" // 官方频道列表 (JSON数组: ["uuid1", "uuid2"])
	// 群组/频道人数上限
	SettingGroupMaxMembers   = "group_max_members"   // 群组最大成员数（默认200000）
	SettingChannelMaxMembers = "channel_max_members" // 频道最大订阅者数（默认无限制，0表示无限制）
	// WebSocket 心跳
	SettingHeartbeatTimeout = "heartbeat_timeout" // 心跳超时（秒），超过此值未收到心跳视为离线（默认60）
	// 文件上传大小限制 (单位: MB)
	SettingMaxImageSize    = "max_image_size"   // 图片最大大小（默认10MB）
	SettingMaxVideoSize    = "max_video_size"   // 视频最大大小（默认100MB）
	SettingMaxFileSize     = "max_file_size"    // 文件最大大小（默认100MB）
	SettingMaxVoiceSize    = "max_voice_size"   // 语音最大大小（默认20MB）
	SettingCloudStorage    = "cloud_storage"    // 云存储配置（本地/阿里云OSS/七牛云/Amazon S3）
	SettingClientBootstrap = "client_bootstrap" // 客户端 API/WS/CDN 入口容灾配置
	// 聊天图片直传灰度配置（P0 基础能力，默认关闭）
	SettingChatImageDirectUploadEnabled        = "chat_image_direct_upload_enabled"
	SettingChatImageDirectUploadPlatforms      = "chat_image_direct_upload_platforms"
	SettingChatImageDirectUploadRolloutPercent = "chat_image_direct_upload_rollout_percent"
	SettingChatImageDirectUploadMaxConcurrency = "chat_image_direct_upload_max_concurrency"
	// 声网（Agora）音视频配置
	SettingAgoraEnabled        = "agora_enabled"         // 是否启用音视频通话
	SettingAgoraAppID          = "agora_app_id"          // 声网 App ID
	SettingAgoraAppCertificate = "agora_app_certificate" // 声网 App Certificate
	SettingAgoraTokenExpire    = "agora_token_expire"    // Token 过期时间（秒）
	// APNs 推送配置
	SettingAPNsEnabled     = "apns_enabled"     // 是否启用 APNs 推送
	SettingAPNsBundleID    = "apns_bundle_id"   // iOS Bundle ID
	SettingAPNsKeyID       = "apns_key_id"      // APNs Key ID（10位）
	SettingAPNsTeamID      = "apns_team_id"     // Apple Team ID（10位）
	SettingAPNsAuthKey     = "apns_auth_key"    // APNs Auth Key（.p8 文件内容）
	SettingAPNsEnvironment = "apns_environment" // development 或 production
	// Android 推送配置（多通道）
	SettingFCMEnabled              = "fcm_enabled"                // 是否启用 FCM 通道
	SettingFCMProjectID            = "fcm_project_id"             // Firebase Project ID
	SettingFCMServiceAccountJSON   = "fcm_service_account_json"   // Firebase service account JSON
	SettingHMSEnabled              = "hms_enabled"                // 是否启用 HMS 通道
	SettingHMSAppID                = "hms_app_id"                 // 华为 Push App ID
	SettingHMSAppSecret            = "hms_app_secret"             // 华为 Push App Secret
	SettingJPushEnabled            = "jpush_enabled"              // 是否启用极光推送统一通道
	SettingJPushAppKey             = "jpush_app_key"              // 极光 AppKey
	SettingJPushMasterSecret       = "jpush_master_secret"        // 极光 MasterSecret
	SettingPushDefaultTitle        = "push_default_title"         // 默认通知标题
	SettingPushChatEnabled         = "push_chat_enabled"          // 是否推送聊天消息
	SettingPushFriendEnabled       = "push_friend_enabled"        // 是否推送好友申请
	SettingPushSystemEnabled       = "push_system_enabled"        // 是否推送系统通知
	SettingPushCategoryChat        = "push_category_chat"         // 聊天消息分类
	SettingPushCategoryService     = "push_category_service"      // 服务通知分类
	SettingPushCategoryMarketing   = "push_category_marketing"    // 运营通知分类
	SettingPushPrimaryProvider     = "push_primary_provider"      // 主推送供应商
	SettingPushFallbackProvider    = "push_fallback_provider"     // 备用推送供应商
	SettingPushRateLimitPerMinute  = "push_rate_limit_per_min"    // 单用户每分钟推送上限，0 不限制
	SettingPushMarketingDailyLimit = "push_marketing_daily_limit" // 单用户每日运营推送上限，0 不限制
	SettingPushQuietHoursEnabled   = "push_quiet_hours_enabled"   // 是否启用运营推送夜间免打扰
	SettingPushQuietHoursStart     = "push_quiet_hours_start"     // 免打扰开始 HH:mm
	SettingPushQuietHoursEnd       = "push_quiet_hours_end"       // 免打扰结束 HH:mm
	SettingXiaomiPushEnabled       = "xiaomi_push_enabled"        // 是否启用小米推送通道
	SettingXiaomiPackageName       = "xiaomi_package_name"        // 小米推送包名
	SettingXiaomiAppSecret         = "xiaomi_app_secret"          // 小米推送 App Secret
	SettingOppoPushEnabled         = "oppo_push_enabled"          // 是否启用 OPPO 推送通道
	SettingOppoAppKey              = "oppo_app_key"               // OPPO 推送 App Key
	SettingOppoAppSecret           = "oppo_app_secret"            // OPPO 推送 App Secret
	SettingWebPushEnabled          = "webpush_enabled"            // 是否启用 H5 WebPush
	SettingWebPushVAPIDPublicKey   = "webpush_vapid_public"       // WebPush VAPID 公钥
	SettingWebPushVAPIDPrivateKey  = "webpush_vapid_private"      // WebPush VAPID 私钥
	SettingWebPushSubject          = "webpush_subject"            // WebPush VAPID subject
	SettingWebPushTTL              = "webpush_ttl"                // WebPush 消息 TTL（秒）
	// 协议文档
	SettingUserAgreement = "user_agreement" // 用户协议（HTML或Markdown）
	SettingPrivacyPolicy = "privacy_policy" // 隐私政策（HTML或Markdown）
	// 消息设置
	SettingRevokeMessageMinutes    = "revoke_message_minutes"  // 消息撤回时限（分钟），默认2分钟
	SettingBurnAfterReadEnabled    = "burn_after_read_enabled" // 是否启用阅后即焚，默认开启
	SettingChatAttachmentMenu      = "chat_attachment_menu"    // 聊天输入框扩展菜单 JSON，默认全部开启
	SettingMessageCryptoMode       = "message_crypto_mode"     // 消息加密模式：plain / compatible / strict
	SettingIPRateLimit             = "ip_rate_limit"           // IP发送消息频率限制（条/分钟，同一IP），0表示不限制，默认60
	SettingUserRateLimit           = "user_rate_limit"         // 用户发消息频率限制（条/分钟，单个用户），0表示不限制，默认30
	SettingVoiceTranscribeProvider = "voice_transcribe_provider"
	SettingVoiceTranscribeURL      = "voice_transcribe_url"
	SettingVoiceTranscribeToken    = "voice_transcribe_token"
	SettingVoiceTranscribeLanguage = "voice_transcribe_language"
	SettingOpenAIAPIKey            = "openai_api_key"
	SettingOpenAITranscribeModel   = "openai_transcribe_model"
	SettingOpenAITranscribeURL     = "openai_transcribe_url"
	SettingDeepSeekAPIKey          = "deepseek_api_key"
	SettingDeepSeekBaseURL         = "deepseek_base_url"
	SettingDeepSeekModel           = "deepseek_model"
	// 在线支付（微信/支付宝）完整 JSON 配置，管理后台维护；见 config.PaymentConfig 结构
	SettingPaymentGateway = "payment_gateway"
	// 短信网关 JSON（绑定手机号验证码），见 config.SMSConfig
	SettingSmsGateway = "sms_gateway"
	// 管理后台角色菜单权限 JSON
	SettingRolePermissions = "role_permissions"
)
const (
	FriendAddModeDirect   = "direct"
	FriendAddModeApproval = "approval"
	FriendAddModeDisabled = "disabled"
)
const (
	// UserInviteCodeMinLength 用户邀请码最小位数
	UserInviteCodeMinLength = 6
	// UserInviteCodeMaxLength 用户邀请码最大位数
	UserInviteCodeMaxLength = 10
	// UserInviteCodeDefaultLength 用户邀请码默认位数（与未配置时一致）
	UserInviteCodeDefaultLength = 6
	// UserInviteCodeLegacyLength 旧版固定邀请码长度，用于兼容已有用户
	UserInviteCodeLegacyLength = 10
)
const (
	SettingRTCProvider        = "rtc_provider"
	SettingLiveKitEnabled     = "livekit_enabled"
	SettingLiveKitServerURL   = "livekit_server_url"
	SettingLiveKitAPIKey      = "livekit_api_key"
	SettingLiveKitAPISecret   = "livekit_api_secret"
	SettingLiveKitTokenExpire = "livekit_token_expire"
)
const (
	MessageCryptoModePlain      = "plain"
	MessageCryptoModeCompatible = "compatible"
	MessageCryptoModeStrict     = "strict"
) // OfficialUser 官方用户信息
type OfficialUser struct {
	ID               uint64         `gorm:"primaryKey;autoIncrement" json:"id"`
	UserID           uint64         `gorm:"uniqueIndex;not null" json:"user_id"`
	UserUUID         string         `gorm:"type:char(36);uniqueIndex;not null" json:"user_uuid"`
	Remark           string         `gorm:"type:varchar(200)" json:"remark"`          // 备注说明
	WelcomeMessage   string         `gorm:"type:varchar(500)" json:"welcome_message"` // 注册欢迎语
	IsServiceEnabled bool           `gorm:"default:true" json:"is_service_enabled"`   // 官方客服状态
	SortOrder        int            `gorm:"default:0" json:"sort_order"`              // 排序
	CreatedAt        time.Time      `gorm:"type:datetime;not null" json:"created_at"`
	UpdatedAt        time.Time      `gorm:"type:datetime;not null" json:"updated_at"`
	DeletedAt        gorm.DeletedAt `gorm:"index" json:"-"`
}

func (OfficialUser) TableName() string {
	return "official_users"
}

// OfficialGroup 官方群组
type OfficialGroup struct {
	ID        uint64         `gorm:"primaryKey;autoIncrement" json:"id"`
	ChatID    uint64         `gorm:"uniqueIndex;not null" json:"chat_id"`
	ChatUUID  string         `gorm:"type:char(36);uniqueIndex;not null" json:"chat_uuid"`
	Remark    string         `gorm:"type:varchar(200)" json:"remark"`
	SortOrder int            `gorm:"default:0" json:"sort_order"`
	CreatedAt time.Time      `gorm:"type:datetime;not null" json:"created_at"`
	UpdatedAt time.Time      `gorm:"type:datetime;not null" json:"updated_at"`
	DeletedAt gorm.DeletedAt `gorm:"index" json:"-"`
}

func (OfficialGroup) TableName() string {
	return "official_groups"
}

// OfficialChannel 官方频道
type OfficialChannel struct {
	ID        uint64         `gorm:"primaryKey;autoIncrement" json:"id"`
	ChatID    uint64         `gorm:"uniqueIndex;not null" json:"chat_id"`
	ChatUUID  string         `gorm:"type:char(36);uniqueIndex;not null" json:"chat_uuid"`
	Remark    string         `gorm:"type:varchar(200)" json:"remark"`
	SortOrder int            `gorm:"default:0" json:"sort_order"`
	CreatedAt time.Time      `gorm:"type:datetime;not null" json:"created_at"`
	UpdatedAt time.Time      `gorm:"type:datetime;not null" json:"updated_at"`
	DeletedAt gorm.DeletedAt `gorm:"index" json:"-"`
}

func (OfficialChannel) TableName() string {
	return "official_channels"
}

// SystemBroadcast 全局公告记录
type SystemBroadcast struct {
	ID          uint64    `gorm:"primaryKey;autoIncrement" json:"id"`
	Title       string    `gorm:"type:varchar(200);not null" json:"title"`
	Content     string    `gorm:"type:text;not null" json:"content"`
	Type        string    `gorm:"type:varchar(50);default:'info'" json:"type"`
	OnlineCount int64     `json:"online_count"`
	AdminID     uint64    `json:"admin_id"`
	AdminName   string    `gorm:"type:varchar(100)" json:"admin_name"`
	CreatedAt   time.Time `gorm:"type:datetime;not null;index" json:"created_at"`
}

func (SystemBroadcast) TableName() string {
	return "system_broadcasts"
}
