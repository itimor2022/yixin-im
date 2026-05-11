package models

import "time"

const (
	MeetingTypeVoice = "voice"
	MeetingTypeVideo = "video"
)

const (
	MeetingStatusActive = "active"
	MeetingStatusEnded  = "ended"
)

const (
	MeetingParticipantRoleHost   = "host"
	MeetingParticipantRoleMember = "member"
)

const (
	MeetingParticipantStatusInvited = "invited"
	MeetingParticipantStatusJoined  = "joined"
	MeetingParticipantStatusLeft    = "left"
	MeetingParticipantStatusKicked  = "kicked"
)

const (
	MeetingInviteStatusPending  = "pending"
	MeetingInviteStatusAccepted = "accepted"
	MeetingInviteStatusRejected = "rejected"
	MeetingInviteStatusCanceled = "canceled"
)

const (
	MeetingInviteTypeInvite      = "invite"
	MeetingInviteTypeJoinRequest = "join_request"
)

// Meeting stores a group meeting room.
type Meeting struct {
	ID              uint64     `gorm:"primaryKey;autoIncrement" json:"id"`
	UUID            string     `gorm:"type:char(36);uniqueIndex;not null" json:"uuid"`
	ChannelName     string     `gorm:"type:varchar(100);uniqueIndex;not null" json:"channel_name"`
	ChatID          uint64     `gorm:"index;default:0" json:"chat_id"`
	CreatorID       uint64     `gorm:"index;not null" json:"creator_id"`
	Title           string     `gorm:"type:varchar(100)" json:"title"`
	MeetingType     string     `gorm:"type:varchar(20);not null" json:"meeting_type"`
	Status          string     `gorm:"type:varchar(20);index;not null;default:'active'" json:"status"`
	MaxParticipants int        `gorm:"type:int;not null;default:16" json:"max_participants"`
	StartTime       time.Time  `gorm:"type:datetime;not null" json:"start_time"`
	EndTime         *time.Time `gorm:"type:datetime" json:"end_time"`
	Duration        int        `gorm:"type:int;not null;default:0" json:"duration"`
	EndReason       string     `gorm:"type:varchar(50)" json:"end_reason"`
	CreatedAt       time.Time  `gorm:"type:datetime;not null" json:"created_at"`
	UpdatedAt       time.Time  `gorm:"type:datetime;not null" json:"updated_at"`
}

func (Meeting) TableName() string {
	return "meetings"
}

// MeetingParticipant stores user state inside a meeting.
type MeetingParticipant struct {
	ID         uint64     `gorm:"primaryKey;autoIncrement" json:"id"`
	MeetingID  uint64     `gorm:"uniqueIndex:idx_meeting_user;index;not null" json:"meeting_id"`
	UserID     uint64     `gorm:"uniqueIndex:idx_meeting_user;index;not null" json:"user_id"`
	Role       string     `gorm:"type:varchar(20);not null;default:'member'" json:"role"`
	Status     string     `gorm:"type:varchar(20);index;not null;default:'invited'" json:"status"`
	InviterID  uint64     `gorm:"index;default:0" json:"inviter_id"`
	JoinedAt   *time.Time `gorm:"type:datetime" json:"joined_at"`
	LeftAt     *time.Time `gorm:"type:datetime" json:"left_at"`
	MutedAudio bool       `gorm:"type:tinyint(1);not null;default:0" json:"muted_audio"`
	MutedVideo bool       `gorm:"type:tinyint(1);not null;default:0" json:"muted_video"`
	CreatedAt  time.Time  `gorm:"type:datetime;not null" json:"created_at"`
	UpdatedAt  time.Time  `gorm:"type:datetime;not null" json:"updated_at"`
}

func (MeetingParticipant) TableName() string {
	return "meeting_participants"
}

// MeetingInvite stores invitation lifecycle.
type MeetingInvite struct {
	ID          uint64     `gorm:"primaryKey;autoIncrement" json:"id"`
	MeetingID   uint64     `gorm:"index:idx_meeting_invitee;not null" json:"meeting_id"`
	InviterID   uint64     `gorm:"index;not null" json:"inviter_id"`
	InviteeID   uint64     `gorm:"index:idx_meeting_invitee;not null" json:"invitee_id"`
	InviteType  string     `gorm:"type:varchar(20);index;not null;default:'invite'" json:"invite_type"`
	Status      string     `gorm:"type:varchar(20);index;not null;default:'pending'" json:"status"`
	RespondedAt *time.Time `gorm:"type:datetime" json:"responded_at"`
	CreatedAt   time.Time  `gorm:"type:datetime;not null" json:"created_at"`
	UpdatedAt   time.Time  `gorm:"type:datetime;not null" json:"updated_at"`
}

func (MeetingInvite) TableName() string {
	return "meeting_invites"
}
