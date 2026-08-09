// 文件用途：实现可复用的后端业务服务和领域逻辑。
// 核心逻辑：协调数据库、缓存、队列和外部服务，集中处理事务、幂等、重试和错误传播。

package services

import (
	"context"
	"errors"
	"gorm.io/gorm"
	"strconv"
	"time"
	"genericim/internal/models"
)

var (
	ErrJoinRequestNotFound    = errors.New("join request not found")
	ErrJoinRequestWrongChat   = errors.New("join request wrong chat")
	ErrJoinRequestReviewed    = errors.New("join request reviewed")
	ErrJoinRequestMemberLimit = errors.New("join request member limit")
)

type JoinRequestService struct {
	db      *gorm.DB
	permSvc *ChatPermissionService
}

type JoinRequestItem struct {
	Request models.JoinRequest
	User    models.User
}

type ReviewJoinRequestResult struct {
	RequestUser   models.User
	AlreadyMember bool
	MemberAdded   bool
	Approved      bool
}

func NewJoinRequestService(db *gorm.DB) *JoinRequestService {
	return &JoinRequestService{
		db:      db,
		permSvc: NewChatPermissionService(db),
	}
}

func (s *JoinRequestService) ListPending(
	ctx context.Context,
	chat models.Chat,
	reviewerMember models.ChatMember,
) ([]JoinRequestItem, error) {
	if !s.permSvc.HasAdminPermission(ctx, chat, reviewerMember, ChatPermissionManageJoinRequests) {
		return nil, ErrChatPermissionDenied
	}

	var requests []models.JoinRequest
	if err := s.db.WithContext(ctx).
		Where("chat_id = ? AND status = ?", chat.ID, models.JoinRequestPending).
		Order("created_at DESC").
		Find(&requests).Error; err != nil {
		return nil, err
	}
	if len(requests) == 0 {
		return []JoinRequestItem{}, nil
	}
	userIDs := make([]uint64, 0, len(requests))
	for _, req := range requests {
		userIDs = append(userIDs, req.UserID)
	}

	var users []models.User
	if err := s.db.WithContext(ctx).Where("id IN ?", userIDs).Find(&users).Error; err != nil {
		return nil, err
	}
	userByID := make(map[uint64]models.User, len(users))
	for _, user := range users {
		userByID[user.ID] = user
	}
	items := make([]JoinRequestItem, 0, len(requests))
	for _, req := range requests {
		user, ok := userByID[req.UserID]
		if !ok {
			continue
		}
		items = append(items, JoinRequestItem{Request: req, User: user})
	}
	return items, nil
}

func (s *JoinRequestService) Review(
	ctx context.Context,
	chat models.Chat,
	reviewer models.User,
	reviewerMember models.ChatMember,
	requestID string,
	approve bool,
	maxMembers int,
) (ReviewJoinRequestResult, error) {
	if !s.permSvc.HasAdminPermission(ctx, chat, reviewerMember, ChatPermissionManageJoinRequests) {
		return ReviewJoinRequestResult{}, ErrChatPermissionDenied
	}

	joinRequestID, err := strconv.ParseUint(requestID, 10, 64)
	if err != nil || joinRequestID == 0 {
		return ReviewJoinRequestResult{}, ErrJoinRequestNotFound
	}

	var joinRequest models.JoinRequest
	if err := s.db.WithContext(ctx).First(&joinRequest, joinRequestID).Error; err != nil {
		return ReviewJoinRequestResult{}, ErrJoinRequestNotFound
	}
	if joinRequest.ChatID != chat.ID {
		return ReviewJoinRequestResult{}, ErrJoinRequestWrongChat
	}
	if joinRequest.Status != models.JoinRequestPending {
		return ReviewJoinRequestResult{}, ErrJoinRequestReviewed
	}
	if approve {
		return s.approve(ctx, chat, reviewer, joinRequest, maxMembers)
	}
	return s.reject(ctx, reviewer, joinRequest)
}

func (s *JoinRequestService) approve(
	ctx context.Context,
	chat models.Chat,
	reviewer models.User,
	joinRequest models.JoinRequest,
	maxMembers int,
) (ReviewJoinRequestResult, error) {
	now := time.Now()
	result := ReviewJoinRequestResult{Approved: true}
	err := s.db.WithContext(ctx).Transaction(func(tx *gorm.DB) error {
		var existingMemberCount int64
		if err := tx.Model(&models.ChatMember{}).
			Where("chat_id = ? AND user_id = ?", chat.ID, joinRequest.UserID).
			Count(&existingMemberCount).Error; err != nil {
			return err
		}
		if existingMemberCount > 0 {

			joinRequest.Status = models.JoinRequestApproved
			joinRequest.ReviewerID = reviewer.ID
			joinRequest.ReviewedAt = &now
			result.AlreadyMember = true
			return tx.Save(&joinRequest).Error
		}
		updateResult := tx.Model(&models.Chat{}).
			Where("id = ? AND(? = 0 OR member_count < ?)", chat.ID, maxMembers, maxMembers).
			Update("member_count", gorm.Expr("member_count + 1"))
		if updateResult.Error != nil {
			return updateResult.Error
		}
		if updateResult.RowsAffected == 0 {
			return ErrJoinRequestMemberLimit
		}
		joinRequest.Status = models.JoinRequestApproved
		joinRequest.ReviewerID = reviewer.ID
		joinRequest.ReviewedAt = &now
		if err := tx.Save(&joinRequest).Error; err != nil {
			return err
		}

		var requestUser models.User
		if err := tx.First(&requestUser, joinRequest.UserID).Error; err != nil {
			return err
		}
		result.RequestUser = requestUser

		if err := tx.Create(&models.ChatMember{
			ChatID:    chat.ID,
			UserID:    joinRequest.UserID,
			Role:      0,
			JoinedAt:  now,
			UpdatedAt: now,
		}).Error; err != nil {
			return err
		}
		if err := tx.Create(&models.UserChat{
			UserID:    joinRequest.UserID,
			ChatID:    chat.ID,
			TargetID:  0,
			SortTime:  now,
			UpdatedAt: now,
		}).Error; err != nil {
			return err
		}
		result.MemberAdded = true
		return nil
	})
	if err != nil {
		return ReviewJoinRequestResult{}, err
	}
	return result, nil
}

func (s *JoinRequestService) reject(
	ctx context.Context,
	reviewer models.User,
	joinRequest models.JoinRequest,
) (ReviewJoinRequestResult, error) {
	now := time.Now()
	joinRequest.Status = models.JoinRequestRejected
	joinRequest.ReviewerID = reviewer.ID
	joinRequest.ReviewedAt = &now

	if err := s.db.WithContext(ctx).Save(&joinRequest).Error; err != nil {
		return ReviewJoinRequestResult{}, err
	}

	var requestUser models.User
	_ = s.db.WithContext(ctx).First(&requestUser, joinRequest.UserID).Error

	return ReviewJoinRequestResult{
		RequestUser: requestUser,
		Approved:    false,
	}, nil
}
