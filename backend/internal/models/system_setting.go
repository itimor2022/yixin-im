package models

import (
	"time"

	"gorm.io/gorm"
)

// SystemSetting 系统设置表
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
	SettingAppVersionIOS     = "app_version_ios"     // iOS当前版本
	SettingAppVersionAndroid = "app_version_android" // Android当前版本
	SettingAppForceUpdate    = "app_force_update"    // 是否强制更新
	SettingAppUpdateURL      = "app_update_url"      // 更新下载链接
	SettingAppUpdateMessage  = "app_update_message"  // 更新提示信息

	// 基本信息
	SettingSystemName      = "system_name"       // 系统名称
	SettingSystemVersion   = "system_version"    // 系统版本
	SettingRegisterBaseURL = "register_base_url" // 注册页/邀请链接外部访问域名

	// 用户设置
	SettingAllowRegister            = "allow_register"              // 是否允许注册
	SettingRequireInviteCode        = "require_invite_code"         // 注册是否必须填写邀请码
	SettingRequirePhoneBind         = "require_phone_bind"          // 是否强制绑定手机号
	SettingMemberOnlyCreateGroup    = "member_only_create_group"     // 仅会员可建群
	SettingCheckinEnabled           = "checkin_enabled"             // 是否开启签到功能
	SettingEnableMomentPost         = "enable_moment_post"          // 是否允许发布动态（关闭后用户只能浏览）
	SettingMomentPostReviewEnabled  = "moment_post_review_enabled"  // 动态发布是否启用审核
	SettingNewUserFollowOfficial    = "new_user_follow_official"    // 新用户是否强制关注官方用户
	SettingInviteRegisterBindOnly   = "invite_register_bind_only"   // 邀请码注册用户只自动添加邀请码绑定客服
	SettingNewUserJoinGroup         = "new_user_join_group"         // 新用户是否强制加入官方群组
	SettingNewUserJoinChannel       = "new_user_join_channel"       // 新用户是否强制订阅官方频道
	SettingGroupInviteRequireFriend = "group_invite_require_friend" // 开启后只能邀请自己的联系人进群
	SettingAllowStrangerMessage     = "allow_stranger_message"      // 是否允许非好友直接发消息

	// 客户端自定义栏目
	SettingCustomPortalEnabled = "custom_portal_enabled"  // 是否启用联系人与发现之间的自定义栏目
	SettingCustomPortalTitle   = "custom_portal_title"    // 自定义栏目标题
	SettingCustomPortalURL     = "custom_portal_url"      // 自定义栏目访问网址
	SettingCustomPortalIconURL = "custom_portal_icon_url" // 自定义栏目图标

	// 在线客服
	SettingCustomerServiceURL = "customer_service_url" // 在线客服地址(App找回密码/FAQ跳转)

	SettingLogoImageUrl       = "logo_image_url"

	SettingDiscoverTopImageUrl = "discover_top_image_url"

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
	SettingMaxImageSize = "max_image_size" // 图片最大大小（默认10MB）
	SettingMaxVideoSize = "max_video_size" // 视频最大大小（默认100MB）
	SettingMaxFileSize  = "max_file_size"  // 文件最大大小（默认100MB）
	SettingMaxVoiceSize = "max_voice_size" // 语音最大大小（默认20MB）

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
	SettingFCMEnabled            = "fcm_enabled"              // 是否启用 FCM 通道
	SettingFCMProjectID          = "fcm_project_id"           // Firebase Project ID
	SettingFCMServiceAccountJSON = "fcm_service_account_json" // Firebase service account JSON
	SettingHMSEnabled            = "hms_enabled"              // 是否启用 HMS 通道
	SettingHMSAppID              = "hms_app_id"               // 华为 Push App ID
	SettingHMSAppSecret          = "hms_app_secret"           // 华为 Push App Secret
	SettingXiaomiPushEnabled     = "xiaomi_push_enabled"      // 是否启用小米推送通道
	SettingXiaomiPackageName     = "xiaomi_package_name"      // 小米推送包名
	SettingXiaomiAppSecret       = "xiaomi_app_secret"        // 小米推送 App Secret
	SettingOppoPushEnabled       = "oppo_push_enabled"        // 是否启用 OPPO 推送通道
	SettingOppoAppKey            = "oppo_app_key"             // OPPO 推送 App Key
	SettingOppoAppSecret         = "oppo_app_secret"          // OPPO 推送 App Secret

	// 协议文档
	SettingUserAgreement = "user_agreement" // 用户协议（HTML或Markdown）
	SettingPrivacyPolicy = "privacy_policy" // 隐私政策（HTML或Markdown）

	// 消息设置
	SettingRevokeMessageMinutes = "revoke_message_minutes" // 消息撤回时限（分钟），默认2分钟
	SettingBurnAfterReadEnabled = "burn_after_read_enabled" // 是否启用阅后即焚，默认开启
	SettingMessageCryptoMode    = "message_crypto_mode"    // 消息加密模式：plain / compatible / strict
	SettingIPRateLimit          = "ip_rate_limit"          // IP发送消息频率限制（条/分钟，同一IP），0表示不限制，默认60
	SettingUserRateLimit        = "user_rate_limit"        // 用户发消息频率限制（条/分钟，单个用户），0表示不限制，默认30

	// 在线支付（微信/支付宝）完整 JSON 配置，管理后台维护；见 config.PaymentConfig 结构
	SettingPaymentGateway = "payment_gateway"

	// 短信网关 JSON（绑定手机号验证码），见 config.SMSConfig
	SettingSmsGateway = "sms_gateway"
)

const (
	MessageCryptoModePlain      = "plain"
	MessageCryptoModeCompatible = "compatible"
	MessageCryptoModeStrict     = "strict"
)

// OfficialUser 官方用户信息
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
