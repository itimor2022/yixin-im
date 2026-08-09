// 文件用途：定义业务实体的 ORM 字段、关联关系和持久化约束。
// 核心逻辑：统一描述字段映射、状态值、索引和表名，作为各层共享数据契约。

package models

import (
	"encoding/json"
	"gorm.io/gorm"
	"time"
)

// Chat 会话表 - MySQL

type Chat struct {
	ID          uint64     `gorm:"primaryKey;autoIncrement" json:"id"`
	UUID        string     `gorm:"type:char(36);uniqueIndex;not null" json:"uuid"`
	Type        int8       `gorm:"type:tinyint;not null" json:"type"` // 1:私聊 2:群聊 3:频道
	Name        string     `gorm:"type:varchar(100)" json:"name"`
	Avatar      string     `gorm:"type:varchar(500)" json:"avatar"`
	Description string     `gorm:"type:varchar(1000)" json:"description"`
	OwnerID     uint64     `gorm:"index" json:"owner_id"`
	MemberCount int        `gorm:"default:0" json:"member_count"`
	MaxMembers  int        `gorm:"default:200" json:"max_members"`
	IsPublic    bool       `gorm:"default:false" json:"is_public"`
	InviteLink  string     `gorm:"type:varchar(100);uniqueIndex" json:"invite_link"`
	Username    string     `gorm:"type:varchar(32);index" json:"username"` // 群组用户名 (公开链接)
	Status      int8       `gorm:"type:tinyint;default:0" json:"status"`   // 0:正常 1:封禁 2:解散
	BanReason   string     `gorm:"type:varchar(500)" json:"ban_reason"`    // 封禁原因
	BannedAt    *time.Time `gorm:"type:datetime" json:"banned_at"`         // 封禁时间
	// 权限设置
	CanSendMessage    bool       `gorm:"default:true" json:"can_send_message"`                 // 成员可发送消息
	CanSendMedia      bool       `gorm:"default:true" json:"can_send_media"`                   // 成员可发送媒体
	CanSendLinks      bool       `gorm:"default:true" json:"can_send_links"`                   // 成员可发送链接
	CanAddMembers     bool       `gorm:"default:false" json:"can_add_members"`                 // 成员可添加成员
	CanPinMessages    bool       `gorm:"default:false" json:"can_pin_messages"`                // 成员可置顶消息
	AllowAnonymous    bool       `gorm:"default:false" json:"allow_anonymous"`                 // 是否允许成员匿名发言
	AllowForward      bool       `gorm:"default:true" json:"allow_forward"`                    // 是否允许成员转发本群消息
	AllowViewHistory  bool       `gorm:"default:true" json:"allow_view_history"`               // 新成员进群后是否可查看历史消息
	MemberProtection  bool       `gorm:"default:false" json:"member_protection"`               // 开启后普通成员仅可见管理员/群主，且不可打开成员资料
	PinnedMessageID   string     `gorm:"type:varchar(36);default:''" json:"pinned_message_id"` // 置顶消息ID(msg_id UUID)
	PinnedMessageText string     `gorm:"type:varchar(500)" json:"pinned_message_text"`         // 置顶消息预览文本
	PinnedMessageBy   uint64     `gorm:"default:0" json:"pinned_message_by"`                   // 置顶操作者ID
	PinnedMessageAt   *time.Time `gorm:"type:datetime" json:"pinned_message_at"`               // 置顶时间
	// 加入审批设置
	JoinApproval bool           `gorm:"default:false" json:"join_approval"` // 是否需要审批加入
	CreatedAt    time.Time      `gorm:"type:datetime;not null" json:"created_at"`
	UpdatedAt    time.Time      `gorm:"type:datetime;not null" json:"updated_at"`
	DeletedAt    gorm.DeletedAt `gorm:"index" json:"-"`
}

// Chat 状态常量
const (
	ChatStatusNormal    = 0 // 正常
	ChatStatusBanned    = 1 // 封禁
	ChatStatusDissolved = 2 // 解散
)

func (Chat) TableName() string {
	return "chats"
}

// ChatMember 会话成员表

type ChatMember struct {
	ID          uint64     `gorm:"primaryKey;autoIncrement" json:"id"`
	ChatID      uint64     `gorm:"uniqueIndex:idx_chat_user;index:idx_chat_members_user_chat,priority:2;index:idx_chat_members_chat_role_joined,priority:1;not null" json:"chat_id"`
	UserID      uint64     `gorm:"uniqueIndex:idx_chat_user;index:idx_chat_members_user_chat,priority:1;index:idx_chat_members_chat_role_joined,priority:4;not null" json:"user_id"`
	Role        int8       `gorm:"type:tinyint;default:0;index:idx_chat_members_chat_role_joined,priority:2,sort:desc" json:"role"` // 0:成员 1:管理员 2:创建者
	Nickname    string     `gorm:"type:varchar(100)" json:"nickname"`                                                               // 群昵称
	IsMuted     bool       `gorm:"default:false" json:"is_muted"`
	IsPinned    bool       `gorm:"default:false" json:"is_pinned"`
	MuteEndTime *time.Time `gorm:"type:datetime" json:"mute_end_time"`
	LastReadSeq uint64     `gorm:"default:0" json:"last_read_seq"` // 最后已读消息序号
	JoinedAt    time.Time  `gorm:"type:datetime;not null;index:idx_chat_members_chat_role_joined,priority:3" json:"joined_at"`
	UpdatedAt   time.Time  `gorm:"type:datetime;not null" json:"updated_at"`
}

func (ChatMember) TableName() string {
	return "chat_members"
}

// ChatAdminPermission 群/频道管理员细分权限

type ChatAdminPermission struct {
	ID                    uint64    `gorm:"primaryKey;autoIncrement" json:"id"`
	ChatID                uint64    `gorm:"uniqueIndex:idx_chat_admin_perm;not null" json:"chat_id"`
	UserID                uint64    `gorm:"uniqueIndex:idx_chat_admin_perm;not null" json:"user_id"`
	CanChangeInfo         bool      `gorm:"default:false" json:"can_change_info"`
	CanDeleteMessages     bool      `gorm:"default:false" json:"can_delete_messages"`
	CanBanUsers           bool      `gorm:"default:false" json:"can_ban_users"`
	CanMuteUsers          bool      `gorm:"default:false" json:"can_mute_users"`
	CanInviteUsers        bool      `gorm:"default:false" json:"can_invite_users"`
	CanManageJoinRequests bool      `gorm:"default:false" json:"can_manage_join_requests"`
	CanPinMessages        bool      `gorm:"default:false" json:"can_pin_messages"`
	CanPostMessages       bool      `gorm:"default:false" json:"can_post_messages"`
	CanEditMessages       bool      `gorm:"default:false" json:"can_edit_messages"`
	CanManageAdmins       bool      `gorm:"default:false" json:"can_manage_admins"`
	CanManageInviteLinks  bool      `gorm:"default:false" json:"can_manage_invite_links"`
	CanViewStats          bool      `gorm:"default:false" json:"can_view_stats"`
	CreatedAt             time.Time `gorm:"type:datetime;not null" json:"created_at"`
	UpdatedAt             time.Time `gorm:"type:datetime;not null" json:"updated_at"`
}

func (ChatAdminPermission) TableName() string {
	return "chat_admin_permissions"
}

// UserChat

type UserChat struct {
	ID              uint64     `gorm:"primaryKey;autoIncrement;index:idx_user_chats_user_pin_sort,priority:4,sort:desc;index:idx_user_chats_user_updated,priority:3,sort:desc" json:"id"`
	UserID          uint64     `gorm:"uniqueIndex:idx_user_chat;index:idx_user_chats_user_pin_sort,priority:1;index:idx_user_chats_user_updated,priority:1;not null" json:"user_id"`
	ChatID          uint64     `gorm:"uniqueIndex:idx_user_chat;not null" json:"chat_id"`
	TargetID        uint64     `gorm:"index" json:"target_id"` // 私聊对方ID
	LastMsgID       uint64     `gorm:"default:0" json:"last_msg_id"`
	LastMsgSeq      uint64     `gorm:"default:0" json:"last_msg_seq"`
	LastMsgTime     *time.Time `gorm:"type:datetime" json:"last_msg_time"`
	LastMsgText     string     `gorm:"type:varchar(200)" json:"last_msg_text"`
	LastMsgType     int        `gorm:"default:1" json:"last_msg_type"`           // 最后消息类型
	LastMsgSender   string     `gorm:"type:varchar(100)" json:"last_msg_sender"` // 最后消息发送者名称（群聊预览用）
	LastMsgMediaURL string     `gorm:"column:last_msg_media_url;type:varchar(500)" json:"last_msg_media_url"`
	UnreadCount     int        `gorm:"default:0" json:"unread_count"`
	HasMention      bool       `gorm:"default:false" json:"has_mention"`
	IsPinned        bool       `gorm:"default:false;index:idx_user_chats_user_pin_sort,priority:2,sort:desc" json:"is_pinned"`
	IsMuted         bool       `gorm:"default:false" json:"is_muted"`
	IsArchived      bool       `gorm:"default:false" json:"is_archived"`
	ClearedAt       *time.Time `gorm:"type:datetime" json:"cleared_at"` // 清空聊天记录时间点
	SortTime        time.Time  `gorm:"type:datetime;index;index:idx_user_chats_user_pin_sort,priority:3,sort:desc" json:"sort_time"`
	UpdatedAt       time.Time  `gorm:"type:datetime;not null;index:idx_user_chats_user_updated,priority:2,sort:desc" json:"updated_at"`
}

func (UserChat) TableName() string {
	return "user_chats"
}

// JoinRequest 加入群组请求

type JoinRequest struct {
	ID         uint64         `gorm:"primaryKey;autoIncrement" json:"id"`
	ChatID     uint64         `gorm:"index;not null" json:"chat_id"`
	UserID     uint64         `gorm:"index;not null" json:"user_id"`
	Message    string         `gorm:"type:varchar(500)" json:"message"`     // 申请留言
	Status     int8           `gorm:"type:tinyint;default:0" json:"status"` // 0:待审批 1:已通过 2:已拒绝
	ReviewerID uint64         `gorm:"default:0" json:"reviewer_id"`         // 审批人ID
	ReviewedAt *time.Time     `gorm:"type:datetime" json:"reviewed_at"`     // 审批时间
	CreatedAt  time.Time      `gorm:"type:datetime;not null" json:"created_at"`
	UpdatedAt  time.Time      `gorm:"type:datetime;not null" json:"updated_at"`
	DeletedAt  gorm.DeletedAt `gorm:"index" json:"-"`
}

// JoinRequest 状态常量
const (
	JoinRequestPending  = 0 // 待审批
	JoinRequestApproved = 1 // 已通过
	JoinRequestRejected = 2 // 已拒绝
)

func (JoinRequest) TableName() string {
	return "join_requests"
}

const (
	ChatAutoMessageScheduleOnce     = "once"
	ChatAutoMessageScheduleDaily    = "daily"
	ChatAutoMessageScheduleInterval = "interval"
)

type ChatAutoMessage struct {
	ID              uint64          `gorm:"primaryKey;autoIncrement" json:"id"`
	ChatID          uint64          `gorm:"index;not null" json:"chat_id"`
	Title           string          `gorm:"type:varchar(100)" json:"title"`
	Content         string          `gorm:"type:text;not null" json:"content"`
	MessageType     int             `gorm:"not null;default:1" json:"message_type"`
	Media           json.RawMessage `gorm:"type:json" json:"media,omitempty"`
	ScheduleType    string          `gorm:"type:varchar(20);not null;default:'once'" json:"schedule_type"`
	IntervalSeconds int             `gorm:"default:0" json:"interval_seconds"`
	SendAt          *time.Time      `gorm:"type:datetime" json:"send_at"`
	DailyTime       string          `gorm:"type:varchar(5)" json:"daily_time"`
	NextRunAt       *time.Time      `gorm:"type:datetime;index" json:"next_run_at"`
	LockedRunAt     *time.Time      `gorm:"type:datetime" json:"locked_run_at,omitempty"`
	LastRunAt       *time.Time      `gorm:"type:datetime" json:"last_run_at"`
	Enabled         bool            `gorm:"default:true;index" json:"enabled"`
	CreatedBy       uint64          `gorm:"index;not null" json:"created_by"`
	CreatedAt       time.Time       `gorm:"type:datetime;not null" json:"created_at"`
	UpdatedAt       time.Time       `gorm:"type:datetime;not null" json:"updated_at"`
	DeletedAt       gorm.DeletedAt  `gorm:"index" json:"-"`
}

func (ChatAutoMessage) TableName() string {
	return "chat_auto_messages"
}
