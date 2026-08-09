// 文件用途：实现可复用的后端业务服务和领域逻辑。
// 核心逻辑：协调数据库、缓存、队列和外部服务，集中处理事务、幂等、重试和错误传播。

package services

import (
	"context"
	"errors"
	"gorm.io/gorm"
	"genericim/internal/models"
)

const (
	ChatPermissionChangeInfo         = "change_info"
	ChatPermissionDeleteMessages     = "delete_messages"
	ChatPermissionBanUsers           = "ban_users"
	ChatPermissionMuteUsers          = "mute_users"
	ChatPermissionInviteUsers        = "invite_users"
	ChatPermissionManageJoinRequests = "manage_join_requests"
	ChatPermissionPinMessages        = "pin_messages"
	ChatPermissionPostMessages       = "post_messages"
	ChatPermissionEditMessages       = "edit_messages"
	ChatPermissionManageAdmins       = "manage_admins"
	ChatPermissionManageInviteLinks  = "manage_invite_links"
	ChatPermissionViewStats          = "view_stats"
)

var (
	ErrChatPermissionDenied      = errors.New("chat permission denied")
	ErrChatPermissionTargetOwner = errors.New("chat permission target is owner")
	ErrChatPermissionAdminPeer   = errors.New("chat permission admin peer")
)

type ChatPermissionService struct {
	db *gorm.DB
}

func NewChatPermissionService(db *gorm.DB) *ChatPermissionService {
	return &ChatPermissionService{db: db}
}

func DefaultChatAdminPermissions(chatType int8) models.ChatAdminPermission {
	perm := models.ChatAdminPermission{
		CanChangeInfo:         true,
		CanDeleteMessages:     true,
		CanBanUsers:           true,
		CanMuteUsers:          true,
		CanInviteUsers:        true,
		CanManageJoinRequests: true,
		CanPinMessages:        true,
		CanManageInviteLinks:  true,
		CanViewStats:          true,
	}
	if chatType == 3 {
		perm.CanPostMessages = true
		perm.CanEditMessages = true
	}
	return perm
}

func OwnerChatAdminPermissions() models.ChatAdminPermission {
	perm := DefaultChatAdminPermissions(3)
	perm.CanManageAdmins = true
	return perm
}

func (s *ChatPermissionService) EffectiveAdminPermissions(
	ctx context.Context,
	chat models.Chat,
	member models.ChatMember,
) (models.ChatAdminPermission, error) {

	if member.Role >= 2 {
		return OwnerChatAdminPermissions(), nil
	}
	if member.Role < 1 {
		return models.ChatAdminPermission{}, nil
	}

	var perm models.ChatAdminPermission
	err := s.db.WithContext(ctx).
		Where("chat_id = ? AND user_id = ?", chat.ID, member.UserID).
		First(&perm).Error
	if err == nil {
		return perm, nil
	}
	if errors.Is(err, gorm.ErrRecordNotFound) {

		return DefaultChatAdminPermissions(chat.Type), nil
	}
	return models.ChatAdminPermission{}, err
}

func (s *ChatPermissionService) HasAdminPermission(
	ctx context.Context,
	chat models.Chat,
	member models.ChatMember,
	permission string,
) bool {
	if member.Role >= 2 {
		return true
	}
	if member.Role < 1 {
		return false
	}

	perm, err := s.EffectiveAdminPermissions(ctx, chat, member)
	if err != nil {
		return false
	}

	switch permission {
	case ChatPermissionChangeInfo:
		return perm.CanChangeInfo
	case ChatPermissionDeleteMessages:
		return perm.CanDeleteMessages
	case ChatPermissionBanUsers:
		return perm.CanBanUsers
	case ChatPermissionMuteUsers:
		return perm.CanMuteUsers
	case ChatPermissionInviteUsers:
		return perm.CanInviteUsers
	case ChatPermissionManageJoinRequests:
		return perm.CanManageJoinRequests
	case ChatPermissionPinMessages:
		return perm.CanPinMessages
	case ChatPermissionPostMessages:
		return perm.CanPostMessages
	case ChatPermissionEditMessages:
		return perm.CanEditMessages
	case ChatPermissionManageAdmins:
		return perm.CanManageAdmins
	case ChatPermissionManageInviteLinks:
		return perm.CanManageInviteLinks
	case ChatPermissionViewStats:
		return perm.CanViewStats
	default:
		return false
	}
}

func (s *ChatPermissionService) CanRemoveMember(
	ctx context.Context,
	chat models.Chat,
	operatorMember models.ChatMember,
	targetMember models.ChatMember,
) error {
	if !s.HasAdminPermission(ctx, chat, operatorMember, ChatPermissionBanUsers) {
		return ErrChatPermissionDenied
	}
	return validateAdminTarget(chat, operatorMember, targetMember)
}

func (s *ChatPermissionService) CanMuteMember(
	ctx context.Context,
	chat models.Chat,
	operatorMember models.ChatMember,
	targetMember models.ChatMember,
) error {
	if !s.HasAdminPermission(ctx, chat, operatorMember, ChatPermissionMuteUsers) {
		return ErrChatPermissionDenied
	}
	return validateAdminTarget(chat, operatorMember, targetMember)
}

func validateAdminTarget(
	chat models.Chat,
	operatorMember models.ChatMember,
	targetMember models.ChatMember,
) error {

	if targetMember.Role >= 2 || chat.OwnerID == targetMember.UserID {
		return ErrChatPermissionTargetOwner
	}
	if operatorMember.Role == 1 && targetMember.Role >= 1 {
		return ErrChatPermissionAdminPeer
	}
	return nil
}
