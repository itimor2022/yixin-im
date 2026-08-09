// 文件用途：实现可复用的后端业务服务和领域逻辑。
// 核心逻辑：协调数据库、缓存、队列和外部服务，集中处理事务、幂等、重试和错误传播。

package services

import (
	"context"
	"errors"
	"gorm.io/gorm"
	"strconv"
	"genericim/internal/models"
)

var (
	ErrRelationshipCurrentUserNotFound = errors.New("current user not found")
	ErrRelationshipTargetUserNotFound  = errors.New("target user not found")
)

type CommonGroupInfo struct {
	ID          string
	Name        string
	Avatar      string
	Type        int8
	MemberCount int64
}

type CommonContactInfo struct {
	ID       string
	Username string
	Nickname string
	Avatar   string
}

type CommonRelationshipInfo struct {
	CommonGroupCount   int64
	CommonContactCount int64
	CommonContacts     []CommonContactInfo
}

type RelationshipService struct {
	db *gorm.DB
}

func NewRelationshipService(db *gorm.DB) *RelationshipService {
	return &RelationshipService{db: db}
}

func (s *RelationshipService) resolveUserByUUIDOrID(
	ctx context.Context,
	rawID string,
) (models.User, error) {
	var user models.User
	db := s.db.WithContext(ctx)
	if err := db.Where("uuid = ?", rawID).First(&user).Error; err != nil {
		numericID, parseErr := strconv.ParseUint(rawID, 10, 64)
		if parseErr != nil {
			return models.User{}, err
		}
		if err := db.First(&user, numericID).Error; err != nil {
			return models.User{}, err
		}
	}
	return user, nil
}

func (s *RelationshipService) resolvePair(
	ctx context.Context,
	currentUserUUID string,
	targetUserID string,
) (models.User, models.User, error) {
	var currentUser models.User
	db := s.db.WithContext(ctx)
	if err := db.Where("uuid = ?", currentUserUUID).First(&currentUser).Error; err != nil {
		return models.User{}, models.User{}, ErrRelationshipCurrentUserNotFound
	}

	targetUser, err := s.resolveUserByUUIDOrID(ctx, targetUserID)
	if err != nil {
		return models.User{}, models.User{}, ErrRelationshipTargetUserNotFound
	}
	return currentUser, targetUser, nil
}

func (s *RelationshipService) currentChatIDs(
	ctx context.Context,
	currentUserID uint64,
) ([]uint64, error) {
	var chatIDs []uint64
	err := s.db.WithContext(ctx).
		Model(&models.ChatMember{}).
		Where("user_id = ?", currentUserID).
		Pluck("chat_id", &chatIDs).Error
	return chatIDs, err
}

func activeCommonGroupsQuery(
	db *gorm.DB,
	targetUserID uint64,
	chatIDs []uint64,
) *gorm.DB {
	return db.
		Table("chats").
		Joins("INNER JOIN chat_members ON chats.id = chat_members.chat_id").
		Where(
			"chat_members.user_id = ? AND chats.id IN ? AND chats.type IN ?",
			targetUserID,
			chatIDs,
			[]int{2, 3},
		).
		Where("chats.status = ?", models.ChatStatusNormal)
}

func (s *RelationshipService) CommonGroups(
	ctx context.Context,
	currentUserUUID string,
	targetUserID string,
) ([]CommonGroupInfo, error) {
	currentUser, targetUser, err := s.resolvePair(ctx, currentUserUUID, targetUserID)
	if err != nil {
		return nil, err
	}

	chatIDs, err := s.currentChatIDs(ctx, currentUser.ID)
	if err != nil {
		return nil, err
	}
	if len(chatIDs) == 0 {
		return []CommonGroupInfo{}, nil
	}

	var commonGroups []models.Chat
	if err := activeCommonGroupsQuery(
		s.db.WithContext(ctx),
		targetUser.ID,
		chatIDs,
	).
		Find(&commonGroups).Error; err != nil {
		return nil, err
	}
	groups := make([]CommonGroupInfo, 0, len(commonGroups))
	for _, group := range commonGroups {
		var memberCount int64
		if err := s.db.WithContext(ctx).
			Model(&models.ChatMember{}).
			Where("chat_id = ?", group.ID).
			Count(&memberCount).Error; err != nil {
			return nil, err
		}

		groups = append(groups, CommonGroupInfo{
			ID:          group.UUID,
			Name:        group.Name,
			Avatar:      group.Avatar,
			Type:        group.Type,
			MemberCount: memberCount,
		})
	}
	return groups, nil
}

func (s *RelationshipService) CommonInfo(
	ctx context.Context,
	currentUserUUID string,
	targetUserID string,
	contactSampleLimit int,
) (CommonRelationshipInfo, error) {
	currentUser, targetUser, err := s.resolvePair(ctx, currentUserUUID, targetUserID)
	if err != nil {
		return CommonRelationshipInfo{}, err
	}

	chatIDs, err := s.currentChatIDs(ctx, currentUser.ID)
	if err != nil {
		return CommonRelationshipInfo{}, err
	}

	var commonGroupCount int64
	if len(chatIDs) > 0 {
		if err := activeCommonGroupsQuery(
			s.db.WithContext(ctx),
			targetUser.ID,
			chatIDs,
		).
			Count(&commonGroupCount).Error; err != nil {
			return CommonRelationshipInfo{}, err
		}
	}

	var commonContactCount int64

	commonContactsQuery := func() *gorm.DB {
		return s.db.WithContext(ctx).
			Table("contacts AS c1").
			Joins("INNER JOIN contacts AS c2 ON c1.contact_user_id = c2.contact_user_id").
			Where("c1.user_id = ? AND c2.user_id = ? AND c1.status = 1 AND c2.status = 1",
				currentUser.ID, targetUser.ID).
			Where("c1.contact_user_id NOT IN ?", []uint64{currentUser.ID, targetUser.ID})
	}
	if err := commonContactsQuery().Count(&commonContactCount).Error; err != nil {
		return CommonRelationshipInfo{}, err
	}

	var contacts []CommonContactInfo
	if contactSampleLimit > 0 {
		if err := commonContactsQuery().
			Select("users.uuid AS id, users.username, users.nickname, users.avatar").
			Joins("INNER JOIN users ON users.id = c1.contact_user_id").
			Order("c1.updated_at DESC").
			Limit(contactSampleLimit).
			Scan(&contacts).Error; err != nil {
			return CommonRelationshipInfo{}, err
		}
	}
	return CommonRelationshipInfo{
		CommonGroupCount:   commonGroupCount,
		CommonContactCount: commonContactCount,
		CommonContacts:     contacts,
	}, nil
}
