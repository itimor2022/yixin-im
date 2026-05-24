package handlers

import (
	"context"
	"crypto/rand"
	"encoding/hex"
	"gaoranim/internal/models"
	"gaoranim/internal/services"
	"log"
	"strings"
	"time"

	"github.com/google/uuid"
	"gorm.io/gorm"
)

func generateCode() string {
	b := make([]byte, 4)
	rand.Read(b)
	return hex.EncodeToString(b)
}

// InviteCodeResult 邀请码处理结果
type InviteCodeResult struct {
	Valid         bool               `json:"valid"`
	Message       string             `json:"message,omitempty"`
	ServiceUserID uint64             `json:"service_user_id,omitempty"`
	WelcomeInfo   *InviteWelcomeInfo `json:"-"`
}

type InviteWelcomeInfo struct {
	ChatID        uint64
	ServiceUserID uint64
	NewUserID     uint64
	Welcome       string
}

// ValidateInviteCode 校验邀请码是否可用（注册前预校验）
func ValidateInviteCode(db *gorm.DB, inviteCode string) *InviteCodeResult {
	if inviteCode == "" {
		return nil
	}

	var code models.InviteCode
	if err := db.Where("code = ? AND status = 1", inviteCode).First(&code).Error; err != nil {
		return &InviteCodeResult{Valid: false, Message: "邀请码无效"}
	}

	if code.ExpiresAt != nil && code.ExpiresAt.Before(time.Now()) {
		return &InviteCodeResult{Valid: false, Message: "邀请码已过期"}
	}

	if code.MaxUses > 0 && code.UsedCount >= code.MaxUses {
		return &InviteCodeResult{Valid: false, Message: "邀请码已达使用上限"}
	}

	var official models.OfficialUser
	if err := db.Where("user_id = ? AND is_service_enabled = ?", code.ServiceUserID, true).First(&official).Error; err != nil {
		return &InviteCodeResult{Valid: false, Message: "邀请码对应官方客服未启用"}
	}

	return &InviteCodeResult{Valid: true, ServiceUserID: code.ServiceUserID}
}

// ProcessInviteCode 注册时处理邀请码（内部调用）
// 返回处理结果，invalid 不再静默失败
func ProcessInviteCode(db *gorm.DB, inviteCode string, newUserID uint64) *InviteCodeResult {
	if inviteCode == "" {
		return nil
	}

	var code models.InviteCode
	if err := db.Where("code = ? AND status = 1", inviteCode).First(&code).Error; err != nil {
		return &InviteCodeResult{Valid: false, Message: "邀请码无效"}
	}

	alreadyBound := false
	var existedUsage models.InviteCodeUsage
	if err := db.Where("user_id = ? AND invite_code_id = ?", newUserID, code.ID).
		Order("id DESC").
		First(&existedUsage).Error; err == nil {
		alreadyBound = true
	} else if err != gorm.ErrRecordNotFound {
		return &InviteCodeResult{Valid: false, Message: "邀请码处理失败"}
	}
	if !alreadyBound {
		validateResult := ValidateInviteCode(db, inviteCode)
		if validateResult != nil && !validateResult.Valid {
			return validateResult
		}
	}

	var newUser models.User
	if err := db.First(&newUser, newUserID).Error; err != nil {
		return &InviteCodeResult{Valid: false, Message: "用户不存在"}
	}

	var serviceUser models.User
	if err := db.First(&serviceUser, code.ServiceUserID).Error; err != nil {
		return &InviteCodeResult{Valid: false, Message: "官方客服不存在"}
	}

	var official models.OfficialUser
	if err := db.Where("user_id = ? AND is_service_enabled = ?", code.ServiceUserID, true).First(&official).Error; err != nil {
		return &InviteCodeResult{Valid: false, Message: "邀请码对应官方客服未启用"}
	}

	now := time.Now()
	if !alreadyBound {
		updateResult := db.Model(&models.InviteCode{}).
			Where("id = ? AND status = 1 AND (max_uses = 0 OR used_count < max_uses)", code.ID).
			Update("used_count", gorm.Expr("used_count + 1"))
		if updateResult.Error != nil {
			return &InviteCodeResult{Valid: false, Message: "邀请码处理失败"}
		}
		if updateResult.RowsAffected == 0 {
			return &InviteCodeResult{Valid: false, Message: "邀请码已达使用上限"}
		}

		if err := db.Create(&models.InviteCodeUsage{
			InviteCodeID: code.ID,
			UserID:       newUserID,
		}).Error; err != nil {
			return &InviteCodeResult{Valid: false, Message: "邀请码处理失败"}
		}
	}

	// 创建（或修复）双向联系人关系
	if _, err := ensureContactRelation(db, newUserID, code.ServiceUserID, now); err != nil {
		return &InviteCodeResult{Valid: false, Message: "邀请码处理失败"}
	}
	if _, err := ensureContactRelation(db, code.ServiceUserID, newUserID, now); err != nil {
		return &InviteCodeResult{Valid: false, Message: "邀请码处理失败"}
	}

	chat, err := getOrCreatePrivateChatForInvite(db, &newUser, &serviceUser, now)
	if err != nil {
		return &InviteCodeResult{Valid: false, Message: "创建会话失败"}
	}

	welcome := strings.TrimSpace(official.WelcomeMessage)
	if welcome == "" {
		welcome = "您好，我是您的官方客服。"
	}

	return &InviteCodeResult{
		Valid:         true,
		ServiceUserID: code.ServiceUserID,
		WelcomeInfo: &InviteWelcomeInfo{
			ChatID:        chat.ID,
			ServiceUserID: serviceUser.ID,
			NewUserID:     newUser.ID,
			Welcome:       welcome,
		},
	}
}

func getOrCreateServiceInviteCode(db *gorm.DB, serviceUser *models.User, remark string, customCode string) (models.InviteCode, error) {
	var existing models.InviteCode
	if err := db.Where("service_user_id = ?", serviceUser.ID).Order("id ASC").First(&existing).Error; err == nil {
		updates := map[string]interface{}{}
		if existing.Status != 1 {
			updates["status"] = 1
		}
		if customCode != "" && existing.Code != customCode {
			updates["code"] = customCode
		}
		if remark != "" && existing.Remark != remark {
			updates["remark"] = remark
		}
		if len(updates) > 0 {
			if err := db.Model(&existing).Updates(updates).Error; err != nil {
				return models.InviteCode{}, err
			}
			if code, ok := updates["code"].(string); ok {
				existing.Code = code
			}
			if status, ok := updates["status"].(int); ok {
				existing.Status = int8(status)
			}
			if remarkValue, ok := updates["remark"].(string); ok {
				existing.Remark = remarkValue
			}
		}
		return existing, nil
	}

	for i := 0; i < 10; i++ {
		code := customCode
		if code == "" {
			code = generateCode()
		}
		inviteCode := models.InviteCode{
			Code:            code,
			ServiceUserID:   serviceUser.ID,
			ServiceUserUUID: serviceUser.UUID,
			MaxUses:         0,
			Remark:          remark,
			Status:          1,
			ExpiresAt:       nil,
		}
		if err := db.Create(&inviteCode).Error; err == nil {
			return inviteCode, nil
		} else if customCode != "" {
			return models.InviteCode{}, err
		}
	}

	return models.InviteCode{}, gorm.ErrDuplicatedKey
}

func getOrCreatePrivateChatForInvite(db *gorm.DB, userA, userB *models.User, now time.Time) (*models.Chat, error) {
	var chat models.Chat
	err := db.Raw(`
		SELECT c.* FROM chats c
		JOIN chat_members cm1 ON c.id = cm1.chat_id AND cm1.user_id = ?
		JOIN chat_members cm2 ON c.id = cm2.chat_id AND cm2.user_id = ?
		WHERE c.type = 1
		LIMIT 1
	`, userA.ID, userB.ID).Scan(&chat).Error
	if err == nil && chat.ID > 0 {
		if err := ensureInviteUserChatRecord(db, chat.ID, userA.ID, userB.ID, now); err != nil {
			return nil, err
		}
		if err := ensureInviteUserChatRecord(db, chat.ID, userB.ID, userA.ID, now); err != nil {
			return nil, err
		}
		return &chat, nil
	}

	chat = models.Chat{
		UUID:        uuid.New().String(),
		Type:        1,
		MemberCount: 2,
		InviteLink:  uuid.NewString()[:8],
		CreatedAt:   now,
		UpdatedAt:   now,
	}
	if err := db.Create(&chat).Error; err != nil {
		return nil, err
	}

	if err := db.Create(&models.ChatMember{ChatID: chat.ID, UserID: userA.ID, Role: 0, JoinedAt: now, UpdatedAt: now}).Error; err != nil {
		return nil, err
	}
	if err := db.Create(&models.ChatMember{ChatID: chat.ID, UserID: userB.ID, Role: 0, JoinedAt: now, UpdatedAt: now}).Error; err != nil {
		return nil, err
	}

	if err := ensureInviteUserChatRecord(db, chat.ID, userA.ID, userB.ID, now); err != nil {
		return nil, err
	}
	if err := ensureInviteUserChatRecord(db, chat.ID, userB.ID, userA.ID, now); err != nil {
		return nil, err
	}

	return &chat, nil
}

func ensureInviteUserChatRecord(db *gorm.DB, chatID, userID, targetID uint64, now time.Time) error {
	var userChat models.UserChat
	if err := db.Where("chat_id = ? AND user_id = ?", chatID, userID).First(&userChat).Error; err == nil {
		return nil
	}
	return db.Create(&models.UserChat{
		UserID:    userID,
		ChatID:    chatID,
		TargetID:  targetID,
		SortTime:  now,
		UpdatedAt: now,
	}).Error
}

func sendInviteWelcomeMessage(db *gorm.DB, msgService *services.MessageService, chat *models.Chat, serviceUser, newUser *models.User, welcome string) {
	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()
	msg, err := msgService.SendMessage(
		ctx,
		&services.SendMessageParams{
			ChatID:   chat.UUID,
			SenderID: serviceUser.UUID,
			Type:     models.MsgTypeText,
			Content: map[string]interface{}{
				"text": welcome,
			},
		},
		serviceUser.Nickname,
		serviceUser.Avatar,
		serviceUser.NicknameColor,
		serviceUser.PremiumType,
		serviceUser.EmojiAvatar,
		[]string{serviceUser.UUID, newUser.UUID},
	)
	if err != nil {
		log.Printf("[InviteCode] send welcome message failed: %v", err)
		return
	}

	db.Model(&models.UserChat{}).
		Where("chat_id = ? AND user_id = ?", chat.ID, serviceUser.ID).
		Updates(map[string]interface{}{
			"last_msg_text":   welcome,
			"last_msg_type":   models.MsgTypeText,
			"last_msg_time":   msg.CreatedAt,
			"last_msg_seq":    msg.Seq,
			"last_msg_sender": serviceUser.Nickname,
			"sort_time":       msg.CreatedAt,
			"is_archived":     false,
		})
	db.Model(&models.UserChat{}).
		Where("chat_id = ? AND user_id = ?", chat.ID, newUser.ID).
		Updates(map[string]interface{}{
			"last_msg_text":   welcome,
			"last_msg_type":   models.MsgTypeText,
			"last_msg_time":   msg.CreatedAt,
			"last_msg_seq":    msg.Seq,
			"last_msg_sender": serviceUser.Nickname,
			"sort_time":       msg.CreatedAt,
			"is_archived":     false,
		})
	db.Model(&models.UserChat{}).
		Where("chat_id = ? AND user_id = ?", chat.ID, newUser.ID).
		UpdateColumn("unread_count", gorm.Expr("unread_count + 1"))
}

func SendInviteWelcomeMessageByInfo(db *gorm.DB, msgService *services.MessageService, info *InviteWelcomeInfo) {
	if msgService == nil || info == nil {
		return
	}

	var chat models.Chat
	if err := db.First(&chat, info.ChatID).Error; err != nil {
		log.Printf("[InviteCode] load chat failed: %v", err)
		return
	}

	var serviceUser models.User
	if err := db.First(&serviceUser, info.ServiceUserID).Error; err != nil {
		log.Printf("[InviteCode] load service user failed: %v", err)
		return
	}

	var newUser models.User
	if err := db.First(&newUser, info.NewUserID).Error; err != nil {
		log.Printf("[InviteCode] load new user failed: %v", err)
		return
	}

	sendInviteWelcomeMessage(db, msgService, &chat, &serviceUser, &newUser, info.Welcome)
}
