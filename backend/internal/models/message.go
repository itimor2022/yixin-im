// 文件用途：定义业务实体的 ORM 字段、关联关系和持久化约束。
// 核心逻辑：统一描述字段映射、状态值、索引和表名，作为各层共享数据契约。

package models

import (
	"go.mongodb.org/mongo-driver/bson/primitive"
	"time"
)

// Message is the MongoDB message document.
type Message struct {
	ID                  primitive.ObjectID       `bson:"_id,omitempty" json:"id"`
	MsgID               string                   `bson:"msg_id" json:"msg_id"`
	ChatID              string                   `bson:"chat_id" json:"chat_id"`
	Seq                 uint64                   `bson:"seq" json:"seq"`
	SenderID            string                   `bson:"sender_id" json:"sender_id"`
	SenderName          string                   `bson:"sender_name" json:"sender_name"`
	SenderAvatar        string                   `bson:"sender_avatar" json:"sender_avatar"`
	SenderNicknameColor string                   `bson:"sender_nickname_color,omitempty" json:"sender_nickname_color,omitempty"`
	SenderEmojiAvatar   string                   `bson:"sender_emoji_avatar,omitempty" json:"sender_emoji_avatar,omitempty"`
	SenderDeviceID      string                   `bson:"sender_device_id,omitempty" json:"sender_device_id,omitempty"`
	OperatorType        string                   `bson:"operator_type,omitempty" json:"operator_type,omitempty"`
	OperatorID          string                   `bson:"operator_id,omitempty" json:"operator_id,omitempty"`
	IsAnonymous         bool                     `bson:"is_anonymous,omitempty" json:"is_anonymous,omitempty"`
	Type                int                      `bson:"type" json:"type"`
	Content             MessageContent           `bson:"content" json:"content"`
	E2EE                *EncryptedMessagePayload `bson:"e2ee,omitempty" json:"e2ee,omitempty"`
	ReplyTo             *ReplyInfo               `bson:"reply_to,omitempty" json:"reply_to,omitempty"`
	Mentions            []string                 `bson:"mentions,omitempty" json:"mentions,omitempty"`
	Reactions           []MessageReaction        `bson:"reactions,omitempty" json:"reactions,omitempty"`
	Status              int                      `bson:"status" json:"status"`
	IsRevoked           bool                     `bson:"is_revoked" json:"is_revoked"`
	RevokedBy           string                   `bson:"revoked_by,omitempty" json:"revoked_by,omitempty"`
	IsEdited            bool                     `bson:"is_edited" json:"is_edited"`
	DeletedFor          []string                 `bson:"deleted_for,omitempty" json:"deleted_for,omitempty"`
	BurnAfterRead       bool                     `bson:"burn_after_read,omitempty" json:"burn_after_read,omitempty"`
	BurnAfterSeconds    int                      `bson:"burn_after_seconds,omitempty" json:"burn_after_seconds,omitempty"`
	BurnedFor           []string                 `bson:"burned_for,omitempty" json:"burned_for,omitempty"`
	CreatedAt           time.Time                `bson:"created_at" json:"created_at"`
	UpdatedAt           time.Time                `bson:"updated_at" json:"updated_at"`
	EditedAt            *time.Time               `bson:"edited_at,omitempty" json:"edited_at,omitempty"`
}

// MessageReaction stores one emoji reaction on a message.
type MessageReaction struct {
	Emoji     string    `bson:"emoji" json:"emoji"`
	UserID    string    `bson:"user_id" json:"user_id"`
	UserName  string    `bson:"user_name" json:"user_name"`
	CreatedAt time.Time `bson:"created_at" json:"created_at"`
}

// MessageContent stores the logical message body.
type MessageContent struct {
	Text          string             `bson:"text,omitempty" json:"text,omitempty"`
	Media         *MediaInfo         `bson:"media,omitempty" json:"media,omitempty"`
	Location      *LocationInfo      `bson:"location,omitempty" json:"location,omitempty"`
	Contact       *ContactInfo       `bson:"contact,omitempty" json:"contact,omitempty"`
	Sticker       *StickerInfo       `bson:"sticker,omitempty" json:"sticker,omitempty"`
	Voice         *VoiceInfo         `bson:"voice,omitempty" json:"voice,omitempty"`
	File          *FileInfo          `bson:"file,omitempty" json:"file,omitempty"`
	System        *SystemInfo        `bson:"system,omitempty" json:"system,omitempty"`
	ForwardBundle *ForwardBundleInfo `bson:"forward_bundle,omitempty" json:"forward_bundle,omitempty"`
}

// ForwardBundleInfo is a server-authored immutable snapshot. Forwarded
// records never resolve their display fields from mutable source messages.
type ForwardBundleInfo struct {
	Title string              `bson:"title" json:"title"`
	Items []ForwardBundleItem `bson:"items" json:"items"`
}

type ForwardBundleItem struct {
	SourceMessageID string         `bson:"source_message_id" json:"source_message_id"`
	Type            int            `bson:"type" json:"type"`
	SenderName      string         `bson:"sender_name" json:"sender_name"`
	SenderAvatar    string         `bson:"sender_avatar,omitempty" json:"sender_avatar,omitempty"`
	Content         MessageContent `bson:"content" json:"content"`
	CreatedAt       time.Time      `bson:"created_at" json:"created_at"`
}

type MediaInfo struct {
	MediaID          string `bson:"media_id, omitempty" json:"media_id, omitempty"`
	URL              string `bson:"url" json:"url"`
	ThumbnailMediaID string `bson:"thumbnail_media_id, omitempty" json:"thumbnail_media_id, omitempty"`
	Thumbnail        string `bson:"thumbnail,omitempty" json:"thumbnail,omitempty"`
	Width            int    `bson:"width,omitempty" json:"width,omitempty"`
	Height           int    `bson:"height,omitempty" json:"height,omitempty"`
	Duration         int    `bson:"duration,omitempty" json:"duration,omitempty"`
	Size             int64  `bson:"size" json:"size"`
	MimeType         string `bson:"mime_type" json:"mime_type"`
	MediaGroupID     string `bson:"media_group_id,omitempty" json:"media_group_id,omitempty"`
}

type LocationInfo struct {
	Latitude  float64 `bson:"latitude" json:"latitude"`
	Longitude float64 `bson:"longitude" json:"longitude"`
	Title     string  `bson:"title,omitempty" json:"title,omitempty"`
	Address   string  `bson:"address,omitempty" json:"address,omitempty"`
}

type ContactInfo struct {
	UserID        string `bson:"user_id" json:"user_id"`
	Nickname      string `bson:"nickname" json:"nickname"`
	Username      string `bson:"username,omitempty" json:"username,omitempty"`
	Avatar        string `bson:"avatar,omitempty" json:"avatar,omitempty"`
	Bio           string `bson:"bio,omitempty" json:"bio,omitempty"`
	NicknameColor string `bson:"nickname_color,omitempty" json:"nickname_color,omitempty"`
	EmojiAvatar   string `bson:"emoji_avatar,omitempty" json:"emoji_avatar,omitempty"`
}

type StickerInfo struct {
	PackID    string `bson:"pack_id" json:"pack_id"`
	StickerID string `bson:"sticker_id" json:"sticker_id"`
	URL       string `bson:"url" json:"url"`
	Emoji     string `bson:"emoji,omitempty" json:"emoji,omitempty"`
}

type VoiceInfo struct {
	MediaID    string `bson:"media_id, omitempty" json:"media_id, omitempty"`
	URL        string `bson:"url" json:"url"`
	Duration   int    `bson:"duration" json:"duration"`
	Size       int64  `bson:"size" json:"size"`
	Waveform   []int  `bson:"waveform,omitempty" json:"waveform,omitempty"`
	Transcript string `bson:"transcript,omitempty" json:"transcript,omitempty"`
}

type FileInfo struct {
	MediaID  string `bson:"media_id, omitempty" json:"media_id, omitempty"`
	URL      string `bson:"url" json:"url"`
	Name     string `bson:"name" json:"name"`
	Size     int64  `bson:"size" json:"size"`
	MimeType string `bson:"mime_type" json:"mime_type"`
}

type SystemInfo struct {
	Action     string            `bson:"action" json:"action"`
	OperatorID string            `bson:"operator_id,omitempty" json:"operator_id,omitempty"`
	TargetIDs  []string          `bson:"target_ids,omitempty" json:"target_ids,omitempty"`
	Extra      map[string]string `bson:"extra,omitempty" json:"extra,omitempty"`
}

type ReplyInfo struct {
	MsgID      string `bson:"msg_id" json:"msg_id"`
	SenderID   string `bson:"sender_id" json:"sender_id"`
	SenderName string `bson:"sender_name" json:"sender_name"`
	Content    string `bson:"content" json:"content"`
}

const (
	MsgTypeText          = 1
	MsgTypeImage         = 2
	MsgTypeVideo         = 3
	MsgTypeVoice         = 4
	MsgTypeFile          = 5
	MsgTypeLocation      = 6
	MsgTypeSticker       = 8
	MsgTypeContact       = 10
	MsgTypeCall          = 11
	MsgTypeRedPacket     = 12
	MsgTypeTransfer      = 13
	MsgTypeForwardBundle = 14
	MsgTypeSystem        = 99
)

const (
	MsgStatusSending   = 0
	MsgStatusSent      = 1
	MsgStatusDelivered = 2
	MsgStatusRead      = 3
)

func GetMessageCollection(chatID string, t time.Time) string {
	return "messages_" + t.Format("200601")
}
