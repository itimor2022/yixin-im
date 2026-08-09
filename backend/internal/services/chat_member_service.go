// 文件用途：实现可复用的后端业务服务和领域逻辑。
// 核心逻辑：协调数据库、缓存、队列和外部服务，集中处理事务、幂等、重试和错误传播。

package services

import (
	"context"
	"errors"
	"gorm.io/gorm"
	"time"
	"genericim/internal/models"
)

var (
	ErrChatMemberTargetUserNotFound = errors.New("chat member target user not found")
	ErrChatMemberTargetNotFound     = errors.New("chat member target not found")
)

type ChatMemberService struct {
	db      *gorm.DB
	permSvc *ChatPermissionService
}

type RemoveMemberResult struct {
	TargetUser models.User
}

type MuteMemberResult struct {
	TargetUser  models.User
	MuteEndTime *time.Time
}

type UnmuteMemberResult struct {
	TargetUser models.User
}

func NewChatMemberService(db *gorm.DB) *ChatMemberService {
	return &ChatMemberService{
		db:      db,
		permSvc: NewChatPermissionService(db),
	}
}

func (s *ChatMemberService) RemoveMember(
	ctx context.Context,
	chat models.Chat,
	operatorMember models.ChatMember,
	targetUserUUID string,
) (RemoveMemberResult, error) {
	targetUser, err := s.findUserByUUID(ctx, targetUserUUID)
	if err != nil {
		return RemoveMemberResult{}, err
	}

	targetMember, err := s.findMember(ctx, chat.ID, targetUser.ID)
	if err != nil {
		return RemoveMemberResult{}, err
	}
	if err := s.permSvc.CanRemoveMember(ctx, chat, operatorMember, targetMember); err != nil {
		return RemoveMemberResult{}, err
	}

	err = s.db.WithContext(ctx).Transaction(func(tx *gorm.DB) error {
		result := tx.Where("chat_id = ? AND user_id = ?", chat.ID, targetUser.ID).
			Delete(&models.ChatMember{})
		if result.Error != nil {
			return result.Error
		}
		if result.RowsAffected > 0 {
			if err := tx.Model(&models.Chat{}).
				Where("id = ?", chat.ID).
				Update("member_count", gorm.Expr("member_count - 1")).Error; err != nil {
				return err
			}
		}
		if err := tx.Where("user_id = ? AND chat_id = ?", targetUser.ID, chat.ID).
			Delete(&models.UserChat{}).Error; err != nil {
			return err
		}
		return tx.Where("chat_id = ? AND user_id = ?", chat.ID, targetUser.ID).
			Delete(&models.ChatAdminPermission{}).Error
	})
	if err != nil {
		return RemoveMemberResult{}, err
	}
	return RemoveMemberResult{TargetUser: targetUser}, nil
}

func (s *ChatMemberService) MuteMember(
	ctx context.Context,
	chat models.Chat,
	operatorMember models.ChatMember,
	targetUserUUID string,
	durationMinutes int,
) (MuteMemberResult, error) {
	targetUser, err := s.findUserByUUID(ctx, targetUserUUID)
	if err != nil {
		return MuteMemberResult{}, err
	}

	targetMember, err := s.findMember(ctx, chat.ID, targetUser.ID)
	if err != nil {
		return MuteMemberResult{}, err
	}
	if err := s.permSvc.CanMuteMember(ctx, chat, operatorMember, targetMember); err != nil {
		return MuteMemberResult{}, err
	}
	updates := map[string]interface{}{
		"is_muted":   true,
		"updated_at": time.Now(),
	}

	var muteEndTime *time.Time
	if durationMinutes > 0 {
		end := time.Now().Add(time.Duration(durationMinutes) * time.Minute)
		muteEndTime = &end
		updates["mute_end_time"] = end
	} else {
		updates["mute_end_time"] = nil
	}
	if err := s.db.WithContext(ctx).Model(&targetMember).Updates(updates).Error; err != nil {
		return MuteMemberResult{}, err
	}
	return MuteMemberResult{
		TargetUser:  targetUser,
		MuteEndTime: muteEndTime,
	}, nil
}

func (s *ChatMemberService) UnmuteMember(
	ctx context.Context,
	chat models.Chat,
	operatorMember models.ChatMember,
	targetUserUUID string,
) (UnmuteMemberResult, error) {
	if !s.permSvc.HasAdminPermission(ctx, chat, operatorMember, ChatPermissionMuteUsers) {
		return UnmuteMemberResult{}, ErrChatPermissionDenied
	}

	targetUser, err := s.findUserByUUID(ctx, targetUserUUID)
	if err != nil {
		return UnmuteMemberResult{}, err
	}
	if err := s.db.WithContext(ctx).Model(&models.ChatMember{}).
		Where("chat_id = ? AND user_id = ?", chat.ID, targetUser.ID).
		Updates(map[string]interface{}{
			"is_muted":      false,
			"mute_end_time": nil,
			"updated_at":    time.Now(),
		}).Error; err != nil {
		return UnmuteMemberResult{}, err
	}
	return UnmuteMemberResult{TargetUser: targetUser}, nil
}

func (s *ChatMemberService) findUserByUUID(ctx context.Context, userUUID string) (models.User, error) {
	var user models.User
	if err := s.db.WithContext(ctx).Where("uuid = ?", userUUID).First(&user).Error; err != nil {
		return models.User{}, ErrChatMemberTargetUserNotFound
	}
	return user, nil
}

func (s *ChatMemberService) findMember(ctx context.Context, chatID uint64, userID uint64) (models.ChatMember, error) {
	var member models.ChatMember
	if err := s.db.WithContext(ctx).
		Where("chat_id = ? AND user_id = ?", chatID, userID).
		First(&member).Error; err != nil {
		return models.ChatMember{}, ErrChatMemberTargetNotFound
	}
	return member, nil
}
