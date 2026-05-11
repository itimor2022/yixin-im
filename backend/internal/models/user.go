package models

import (
	"strconv"
	"strings"
	"time"

	"golang.org/x/crypto/bcrypt"
	"gorm.io/gorm"
)

// User stores basic account information.
type User struct {
	ID            uint64         `gorm:"primaryKey;autoIncrement" json:"id"`
	UUID          string         `gorm:"type:char(36);uniqueIndex;not null" json:"uuid"`
	ShortID       *uint64        `gorm:"uniqueIndex" json:"short_id,omitempty"`
	Username      string         `gorm:"type:varchar(50);uniqueIndex;not null" json:"username"`
	Password      string         `gorm:"type:varchar(100);not null" json:"-"`
	Phone         *string        `gorm:"type:varchar(20);uniqueIndex" json:"phone"`
	Nickname      string         `gorm:"type:varchar(100);not null" json:"nickname"`
	Avatar        string         `gorm:"type:varchar(500)" json:"avatar"`
	Bio           string         `gorm:"type:varchar(500)" json:"bio"`
	EmojiAvatar   string         `gorm:"type:varchar(100)" json:"emoji_avatar"`
	NicknameColor string         `gorm:"type:varchar(20)" json:"nickname_color"`
	PremiumType   string         `gorm:"type:varchar(20)" json:"premium_type"`
	Status        int8           `gorm:"type:tinyint;default:1" json:"status"`
	BanReason     string         `gorm:"type:varchar(500)" json:"ban_reason"`
	BannedAt      *time.Time     `gorm:"type:datetime" json:"banned_at"`
	LastSeen      time.Time      `gorm:"type:datetime" json:"last_seen"`
	CreatedAt     time.Time      `gorm:"type:datetime;not null" json:"created_at"`
	UpdatedAt     time.Time      `gorm:"type:datetime;not null" json:"updated_at"`
	DeletedAt     gorm.DeletedAt `gorm:"index" json:"-"`
}

const (
	UserStatusDisabled = 0
	UserStatusNormal   = 1
	UserStatusPending  = 2
	UserStatusBanned   = 3
)

const UserShortIDBase uint64 = 100000000

func BuildUserShortID(userID uint64) uint64 {
	return UserShortIDBase + userID
}

func ParseUserShortIDKeyword(keyword string) (uint64, bool) {
	s := strings.TrimSpace(keyword)
	if s == "" {
		return 0, false
	}
	for _, ch := range s {
		if ch < '0' || ch > '9' {
			return 0, false
		}
	}
	v, err := strconv.ParseUint(s, 10, 64)
	if err != nil || v == 0 {
		return 0, false
	}
	return v, true
}

func (User) TableName() string {
	return "users"
}

func (u *User) SetPassword(password string) error {
	hashedPassword, err := bcrypt.GenerateFromPassword([]byte(password), bcrypt.DefaultCost)
	if err != nil {
		return err
	}
	u.Password = string(hashedPassword)
	return nil
}

func (u *User) CheckPassword(password string) bool {
	return bcrypt.CompareHashAndPassword([]byte(u.Password), []byte(password)) == nil
}

// UserDevice stores user login devices.
type UserDevice struct {
	ID                     uint64     `gorm:"primaryKey;autoIncrement" json:"id"`
	UserID                 uint64     `gorm:"index;not null" json:"user_id"`
	DeviceID               string     `gorm:"type:varchar(100);not null" json:"device_id"`
	DeviceType             string     `gorm:"type:varchar(20);not null" json:"device_type"`
	PushChannel            string     `gorm:"type:varchar(20);default:'';index" json:"push_channel"`
	DeviceName             string     `gorm:"type:varchar(100)" json:"device_name"`
	PushToken              string     `gorm:"type:varchar(2048)" json:"push_token"`
	E2EEPublicKey          string     `gorm:"column:e2ee_public_key;type:text" json:"e2ee_public_key"`
	E2EEPublicKeyAlgo      string     `gorm:"column:e2ee_public_key_algo;type:varchar(64)" json:"e2ee_public_key_algo"`
	E2EEPublicKeyUpdatedAt *time.Time `gorm:"column:e2ee_public_key_updated_at;type:datetime" json:"e2ee_public_key_updated_at"`
	IP                     string     `gorm:"type:varchar(50)" json:"ip"`
	Location               string     `gorm:"type:varchar(100)" json:"location"`
	LastActive             time.Time  `gorm:"type:datetime" json:"last_active"`
	CreatedAt              time.Time  `gorm:"type:datetime;not null" json:"created_at"`
}

func (UserDevice) TableName() string {
	return "user_devices"
}

// PushDeliveryLog records push outcomes for admin diagnostics.
type PushDeliveryLog struct {
	ID         uint64    `gorm:"primaryKey;autoIncrement" json:"id"`
	UserID     uint64    `gorm:"index;not null" json:"user_id"`
	DeviceID   uint64    `gorm:"index;not null" json:"device_id"`
	DeviceKey  string    `gorm:"type:varchar(100);index" json:"device_key"`
	Channel    string    `gorm:"type:varchar(20);index" json:"channel"`
	Success    bool      `gorm:"type:tinyint(1);not null;default:0;index" json:"success"`
	Error      string    `gorm:"type:varchar(512)" json:"error"`
	Title      string    `gorm:"type:varchar(120)" json:"title"`
	Body       string    `gorm:"type:varchar(255)" json:"body"`
	OccurredAt time.Time `gorm:"type:datetime;not null;index" json:"occurred_at"`
	CreatedAt  time.Time `gorm:"type:datetime;not null" json:"created_at"`
}

func (PushDeliveryLog) TableName() string {
	return "push_delivery_logs"
}

// UserPushSetting stores push-notification preferences.
type UserPushSetting struct {
	ID          uint64    `gorm:"primaryKey;autoIncrement" json:"id"`
	UserID      uint64    `gorm:"uniqueIndex;not null" json:"user_id"`
	ShowPreview bool      `gorm:"type:tinyint(1);default:1" json:"show_preview"`
	CreatedAt   time.Time `gorm:"type:datetime;not null" json:"created_at"`
	UpdatedAt   time.Time `gorm:"type:datetime;not null" json:"updated_at"`
}

func (UserPushSetting) TableName() string {
	return "user_push_settings"
}

// UserRelation stores friend relationships.
type UserRelation struct {
	ID        uint64    `gorm:"primaryKey;autoIncrement" json:"id"`
	UserID    uint64    `gorm:"index:idx_user_friend;not null" json:"user_id"`
	FriendID  uint64    `gorm:"index:idx_user_friend;not null" json:"friend_id"`
	Status    int8      `gorm:"type:tinyint;default:0" json:"status"`
	Remark    string    `gorm:"type:varchar(100)" json:"remark"`
	CreatedAt time.Time `gorm:"type:datetime;not null" json:"created_at"`
	UpdatedAt time.Time `gorm:"type:datetime;not null" json:"updated_at"`
}

func (UserRelation) TableName() string {
	return "user_relations"
}

// Contact stores contact relationship rows.
type Contact struct {
	ID            uint64    `gorm:"primaryKey;autoIncrement" json:"id"`
	UserID        uint64    `gorm:"index:idx_contact;not null" json:"user_id"`
	ContactUserID uint64    `gorm:"index:idx_contact;not null" json:"contact_user_id"`
	Remark        string    `gorm:"type:varchar(100)" json:"remark"`
	Status        int8      `gorm:"type:tinyint;default:1" json:"status"`
	CreatedAt     time.Time `gorm:"type:datetime;not null" json:"created_at"`
	UpdatedAt     time.Time `gorm:"type:datetime;not null" json:"updated_at"`
}

func (Contact) TableName() string {
	return "contacts"
}

// UserPrivacySetting stores privacy and security options.
type UserPrivacySetting struct {
	ID                    uint64    `gorm:"primaryKey;autoIncrement" json:"id"`
	UserID                uint64    `gorm:"uniqueIndex;not null" json:"user_id"`
	LastSeenVisibility    string    `gorm:"type:varchar(20);default:'所有人'" json:"last_seen_visibility"`
	PhoneVisibility       string    `gorm:"type:varchar(20);default:'联系人'" json:"phone_visibility"`
	GroupInvitePermission string    `gorm:"type:varchar(20);default:'所有人'" json:"group_invite_permission"`
	AllowPhoneSearch      bool      `gorm:"type:tinyint(1);default:1" json:"allow_phone_search"`
	AllowShortIDSearch    bool      `gorm:"type:tinyint(1);default:1" json:"allow_short_id_search"`
	DeviceLockEnabled     bool      `gorm:"type:tinyint(1);default:0" json:"device_lock_enabled"`
	TwoStepEnabled        bool      `gorm:"type:tinyint(1);default:0" json:"two_step_enabled"`
	TwoStepPasswordHash   string    `gorm:"type:varchar(255)" json:"-"`
	TwoStepPasswordHint   string    `gorm:"type:varchar(100)" json:"two_step_password_hint"`
	AutoDeleteAccount     string    `gorm:"type:varchar(20);default:'6 个月'" json:"auto_delete_account"`
	CreatedAt             time.Time `gorm:"type:datetime;not null" json:"created_at"`
	UpdatedAt             time.Time `gorm:"type:datetime;not null" json:"updated_at"`
}

func (UserPrivacySetting) TableName() string {
	return "user_privacy_settings"
}

// UserEmojiStoreSetting stores cloud-synced emoji-store preferences.
type UserEmojiStoreSetting struct {
	ID               uint64    `gorm:"primaryKey;autoIncrement" json:"id"`
	UserID           uint64    `gorm:"uniqueIndex;not null" json:"user_id"`
	InstalledPackIDs string    `gorm:"type:longtext" json:"installed_pack_ids"` // JSON array
	FavoriteCodes    string    `gorm:"type:longtext" json:"favorite_codes"`     // JSON array
	CustomEmojis     string    `gorm:"type:longtext" json:"custom_emojis"`      // JSON array
	CreatedAt        time.Time `gorm:"type:datetime;not null" json:"created_at"`
	UpdatedAt        time.Time `gorm:"type:datetime;not null" json:"updated_at"`
}

func (UserEmojiStoreSetting) TableName() string {
	return "user_emoji_store_settings"
}

// EmojiStorePackCatalog stores configurable sticker-pack catalog entries.
type EmojiStorePackCatalog struct {
	ID           uint64    `gorm:"primaryKey;autoIncrement" json:"id"`
	PackID       string    `gorm:"type:varchar(64);uniqueIndex;not null" json:"pack_id"`
	Name         string    `gorm:"type:varchar(100);not null" json:"name"`
	Description  string    `gorm:"type:varchar(255)" json:"description"`
	PreviewEmoji string    `gorm:"type:varchar(16)" json:"preview_emoji"`
	PreviewFile  string    `gorm:"type:varchar(100);not null" json:"preview_file"`
	StickerFiles string    `gorm:"type:longtext;not null" json:"sticker_files"` // JSON array
	SortOrder    int       `gorm:"type:int;default:0;index" json:"sort_order"`
	IsBuiltIn    bool      `gorm:"type:tinyint(1);default:1" json:"is_built_in"`
	IsActive     bool      `gorm:"type:tinyint(1);default:1;index" json:"is_active"`
	CreatedAt    time.Time `gorm:"type:datetime;not null" json:"created_at"`
	UpdatedAt    time.Time `gorm:"type:datetime;not null" json:"updated_at"`
}

func (EmojiStorePackCatalog) TableName() string {
	return "emoji_store_pack_catalogs"
}

// UserBlock stores block relationships.
type UserBlock struct {
	ID            uint64    `gorm:"primaryKey;autoIncrement" json:"id"`
	UserID        uint64    `gorm:"index:idx_user_block;not null" json:"user_id"`
	BlockedUserID uint64    `gorm:"index:idx_user_block;not null" json:"blocked_user_id"`
	CreatedAt     time.Time `gorm:"type:datetime;not null" json:"created_at"`
}

func (UserBlock) TableName() string {
	return "user_blocks"
}

// UserSession stores active user sessions.
type UserSession struct {
	ID         uint64    `gorm:"primaryKey;autoIncrement" json:"id"`
	UserID     uint64    `gorm:"index;not null" json:"user_id"`
	Token      string    `gorm:"type:varchar(500);uniqueIndex;not null" json:"-"`
	DeviceID   string    `gorm:"type:varchar(100)" json:"device_id"`
	DeviceType string    `gorm:"type:varchar(20)" json:"device_type"`
	DeviceName string    `gorm:"type:varchar(100)" json:"device_name"`
	IP         string    `gorm:"type:varchar(50)" json:"ip"`
	Location   string    `gorm:"type:varchar(100)" json:"location"`
	IsCurrent  bool      `gorm:"-" json:"is_current"`
	LastActive time.Time `gorm:"type:datetime" json:"last_active"`
	CreatedAt  time.Time `gorm:"type:datetime;not null" json:"created_at"`
}

func (UserSession) TableName() string {
	return "user_sessions"
}
