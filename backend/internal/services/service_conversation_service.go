// 文件用途：实现可复用的后端业务服务和领域逻辑。
// 核心逻辑：协调数据库、缓存、队列和外部服务，集中处理事务、幂等、重试和错误传播。

package services

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"github.com/google/uuid"
	"gorm.io/gorm"
	"gorm.io/gorm/clause"
	"strings"
	"time"
	"unicode/utf8"
	"genericim/internal/models"
)

var (
	ErrServiceAgentForbidden        = errors.New("service agent forbidden")
	ErrServiceConversationNotFound  = errors.New("service conversation not found")
	ErrServiceConversationConflict  = errors.New("service conversation state conflict")
	ErrServiceAgentAtCapacity       = errors.New("service agent at capacity")
	ErrServiceInvalidTransition     = errors.New("invalid service conversation transition")
	ErrServiceEncryptionUnsupported = errors.New("service workbench cannot send in strict encryption mode")
)

type ServiceEventHub interface {
	SendToUsers(userIDs []string, data interface{})
}

type ServiceConversationService struct {
	db         *gorm.DB
	msgService *MessageService
	hub        ServiceEventHub
}

func NewServiceConversationService(db *gorm.DB, msgService *MessageService, hub ServiceEventHub) *ServiceConversationService {
	return &ServiceConversationService{db: db, msgService: msgService, hub: hub}
}

type ServiceCustomerSummary struct {
	ID           uint64   `json:"id"`
	UUID         string   `json:"uuid"`
	Username     string   `json:"username"`
	Nickname     string   `json:"nickname"`
	Avatar       string   `json:"avatar"`
	Phone        string   `json:"phone"`
	RegisteredAt string   `json:"registered_at"`
	Tags         []string `json:"tags"`
	Note         string   `json:"note"`
	VipLevel     string   `json:"vip_level"`
	Balance      float64  `json:"balance"`
	OrderCount   int64    `json:"order_count"`
	TotalPaid    float64  `json:"total_paid"`
}

type ServiceAgentSummary struct {
	ID                uint64 `json:"id"`
	UserID            uint64 `json:"user_id"`
	UUID              string `json:"uuid"`
	Nickname          string `json:"nickname"`
	Avatar            string `json:"avatar"`
	Presence          string `json:"presence"`
	CurrentServing    int    `json:"current_serving"`
	MaxConcurrent     int    `json:"max_concurrent"`
	AutoAssignEnabled bool   `json:"auto_assign_enabled"`
}

type ServiceConversationItem struct {
	UUID            string                 `json:"uuid"`
	ChatUUID        string                 `json:"chat_uuid"`
	Status          string                 `json:"status"`
	Priority        int8                   `json:"priority"`
	Source          string                 `json:"source"`
	RoundNo         int                    `json:"round_no"`
	Customer        ServiceCustomerSummary `json:"customer"`
	AssignedAgent   *ServiceAgentSummary   `json:"assigned_agent,omitempty"`
	LastMessageID   string                 `json:"last_message_id"`
	LastMessageText string                 `json:"last_message_text"`
	LastMessageType int                    `json:"last_message_type"`
	LastMessageAt   *time.Time             `json:"last_message_at,omitempty"`
	UnreadCount     int                    `json:"unread_count"`
	WaitingSeconds  int64                  `json:"waiting_seconds"`
	AIStatus        string                 `json:"ai_status"`
	QueuedAt        time.Time              `json:"queued_at"`
	AssignedAt      *time.Time             `json:"assigned_at,omitempty"`
	AcceptedAt      *time.Time             `json:"accepted_at,omitempty"`
	FirstResponseAt *time.Time             `json:"first_response_at,omitempty"`
	ClosedAt        *time.Time             `json:"closed_at,omitempty"`
	CloseReason     string                 `json:"close_reason"`
	CreatedAt       time.Time              `json:"created_at"`
	UpdatedAt       time.Time              `json:"updated_at"`
}

type ServiceConversationListResult struct {
	List  []ServiceConversationItem `json:"list"`
	Total int64                     `json:"total"`
	Page  int                       `json:"page"`
	Limit int                       `json:"limit"`
}

type ServiceConversationListOptions struct {
	Queue    string
	Keyword  string
	Page     int
	PageSize int
}

func (s *ServiceConversationService) CurrentAgent(userUUID string) (*models.ServiceAgent, *models.User, error) {
	if s == nil || s.db == nil || strings.TrimSpace(userUUID) == "" {
		return nil, nil, ErrServiceAgentForbidden
	}

	var user models.User
	if err := s.db.Where("uuid = ?", strings.TrimSpace(userUUID)).First(&user).Error; err != nil {
		return nil, nil, ErrServiceAgentForbidden
	}

	var official models.OfficialUser
	if err := s.db.Where("user_id = ? AND is_service_enabled = ?", user.ID, true).First(&official).Error; err != nil {
		return nil, nil, ErrServiceAgentForbidden
	}
	agent := models.ServiceAgent{
		UserID:                       user.ID,
		DefaultServiceIdentityUserID: official.UserID,
		Role:                         models.ServiceAgentRoleAgent,
		Presence:                     models.ServicePresenceOffline,
		MaxConcurrent:                5,
		AutoAssignEnabled:            true,
	}
	if err := s.db.Where("user_id = ?", user.ID).FirstOrCreate(&agent).Error; err != nil {
		return nil, nil, err
	}
	if agent.DefaultServiceIdentityUserID == 0 {
		agent.DefaultServiceIdentityUserID = official.UserID
		if err := s.db.Model(&agent).Update("default_service_identity_user_id", official.UserID).Error; err != nil {
			return nil, nil, err
		}
	}
	if agent.Presence != models.ServicePresenceOffline && (agent.LastHeartbeatAt == nil || agent.LastHeartbeatAt.Before(time.Now().Add(-90*time.Second))) {
		agent.Presence = models.ServicePresenceOffline
		if err := s.db.Model(&agent).Update("presence", models.ServicePresenceOffline).Error; err != nil {
			return nil, nil, err
		}
	}
	return &agent, &user, nil
}

func (s *ServiceConversationService) List(ctx context.Context, agent *models.ServiceAgent, opts ServiceConversationListOptions) (*ServiceConversationListResult, error) {
	if agent == nil {
		return nil, ErrServiceAgentForbidden
	}
	if opts.Page <= 0 {
		opts.Page = 1
	}
	if opts.PageSize <= 0 || opts.PageSize > 100 {
		opts.PageSize = 50
	}
	query := s.db.WithContext(ctx).Model(&models.ServiceConversation{})
	switch strings.TrimSpace(opts.Queue) {
	case "waiting":
		query = query.Where("service_conversations.status = ?", models.ServiceConversationWaiting)
	case "pending", "follow_up":
		query = query.Where("service_conversations.status = ?", models.ServiceConversationPending)
		if agent.Role != models.ServiceAgentRoleSupervisor {
			query = query.Where("service_conversations.assigned_agent_id = ?", agent.ID)
		}
	case "closed":
		query = query.Where("service_conversations.status = ?", models.ServiceConversationClosed)
		if agent.Role != models.ServiceAgentRoleSupervisor {
			query = query.Where("service_conversations.assigned_agent_id = ?", agent.ID)
		}
	default:
		query = query.Where("service_conversations.status IN ?", []string{
			models.ServiceConversationAssigned,
			models.ServiceConversationServing,
		})
		if agent.Role != models.ServiceAgentRoleSupervisor {
			query = query.Where("service_conversations.assigned_agent_id = ?", agent.ID)
		}
	}
	if keyword := strings.TrimSpace(opts.Keyword); keyword != "" {
		like := "%" + keyword + "%"
		query = query.Joins("JOIN users service_customer ON service_customer.id = service_conversations.customer_user_id").
			Where("service_customer.nickname LIKE ? OR service_customer.username LIKE ? OR service_customer.uuid LIKE ? OR service_conversations.last_message_text LIKE ?", like, like, like, like)
	}

	var total int64
	if err := query.Count(&total).Error; err != nil {
		return nil, err
	}

	var rows []models.ServiceConversation
	if err := query.Order("service_conversations.priority DESC").
		Order("COALESCE(service_conversations.last_message_at, service_conversations.queued_at) DESC").
		Offset((opts.Page - 1) * opts.PageSize).
		Limit(opts.PageSize).
		Find(&rows).Error; err != nil {
		return nil, err
	}

	items, err := s.buildConversationItems(rows)
	if err != nil {
		return nil, err
	}
	return &ServiceConversationListResult{List: items, Total: total, Page: opts.Page, Limit: opts.PageSize}, nil
}

func (s *ServiceConversationService) Get(ctx context.Context, agent *models.ServiceAgent, conversationUUID string) (*ServiceConversationItem, error) {
	conversation, err := s.findAuthorizedConversation(ctx, agent, conversationUUID, true)
	if err != nil {
		return nil, err
	}
	items, err := s.buildConversationItems([]models.ServiceConversation{*conversation})
	if err != nil || len(items) == 0 {
		return nil, err
	}
	return &items[0], nil
}

func (s *ServiceConversationService) Presence(ctx context.Context, agent *models.ServiceAgent) (*ServiceAgentSummary, error) {
	if agent == nil {
		return nil, ErrServiceAgentForbidden
	}
	if err := s.reconcileAgentServing(ctx, agent.ID); err != nil {
		return nil, err
	}
	var refreshed models.ServiceAgent
	if err := s.db.WithContext(ctx).First(&refreshed, agent.ID).Error; err != nil {
		return nil, err
	}
	return s.agentSummary(&refreshed)
}

func (s *ServiceConversationService) UpdatePresence(ctx context.Context, agent *models.ServiceAgent, presence string) (*ServiceAgentSummary, error) {
	presence = strings.TrimSpace(presence)
	if presence != models.ServicePresenceOnline && presence != models.ServicePresenceBusy && presence != models.ServicePresenceOffline {
		return nil, ErrServiceInvalidTransition
	}
	now := time.Now()
	updates := map[string]interface{}{"presence": presence, "last_heartbeat_at": &now}
	if err := s.db.WithContext(ctx).Model(&models.ServiceAgent{}).Where("id = ?", agent.ID).Updates(updates).Error; err != nil {
		return nil, err
	}
	result, err := s.Presence(ctx, agent)
	if err == nil {
		s.notifyPresence(result)
	}
	return result, err
}

func (s *ServiceConversationService) Heartbeat(ctx context.Context, agent *models.ServiceAgent) (*ServiceAgentSummary, error) {
	now := time.Now()
	if err := s.db.WithContext(ctx).Model(&models.ServiceAgent{}).Where("id = ?", agent.ID).Update("last_heartbeat_at", &now).Error; err != nil {
		return nil, err
	}
	return s.Presence(ctx, agent)
}

func (s *ServiceConversationService) AvailableAgents(ctx context.Context, current *models.ServiceAgent) ([]ServiceAgentSummary, error) {
	var agents []models.ServiceAgent
	if err := s.db.WithContext(ctx).
		Where("presence IN ? AND id <> ? AND last_heartbeat_at >= ?", []string{models.ServicePresenceOnline, models.ServicePresenceBusy}, current.ID, time.Now().Add(-90*time.Second)).
		Order("current_serving ASC, last_assigned_at ASC").Find(&agents).Error; err != nil {
		return nil, err
	}
	result := make([]ServiceAgentSummary, 0, len(agents))
	for i := range agents {
		if err := s.reconcileAgentServing(ctx, agents[i].ID); err != nil {
			return nil, err
		}
		if err := s.db.WithContext(ctx).First(&agents[i], agents[i].ID).Error; err != nil {
			return nil, err
		}
		summary, err := s.agentSummary(&agents[i])
		if err != nil {
			return nil, err
		}
		result = append(result, *summary)
	}
	return result, nil
}

func (s *ServiceConversationService) Claim(ctx context.Context, agent *models.ServiceAgent, conversationUUID string) (*ServiceConversationItem, error) {
	if err := s.ensureAgentCapacity(ctx, agent.ID); err != nil {
		return nil, err
	}
	now := time.Now()
	var conversation models.ServiceConversation
	err := s.db.WithContext(ctx).Transaction(func(tx *gorm.DB) error {
		result := tx.Model(&models.ServiceConversation{}).
			Where("uuid = ? AND status = ? AND assigned_agent_id IS NULL", conversationUUID, models.ServiceConversationWaiting).
			Updates(map[string]interface{}{
				"status":            models.ServiceConversationServing,
				"assigned_agent_id": agent.ID,
				"assigned_at":       &now,
				"accepted_at":       &now,
			})
		if result.Error != nil {
			return result.Error
		}
		if result.RowsAffected != 1 {
			return ErrServiceConversationConflict
		}
		if err := tx.Where("uuid = ?", conversationUUID).First(&conversation).Error; err != nil {
			return err
		}
		if err := createServiceEvent(tx, &conversation, "claimed", agentOperatorType(agent), agent.ID, models.ServiceConversationWaiting, models.ServiceConversationServing, nil); err != nil {
			return err
		}
		return tx.Model(&models.ServiceAgent{}).Where("id = ?", agent.ID).Updates(map[string]interface{}{
			"current_serving":  gorm.Expr("current_serving + 1"),
			"last_assigned_at": &now,
		}).Error
	})
	if err != nil {
		return nil, err
	}
	s.notifyConversation("service.conversation.claimed", &conversation)
	return s.Get(ctx, agent, conversationUUID)
}

func (s *ServiceConversationService) Accept(ctx context.Context, agent *models.ServiceAgent, conversationUUID string) (*ServiceConversationItem, error) {
	now := time.Now()
	result := s.db.WithContext(ctx).Model(&models.ServiceConversation{}).
		Where("uuid = ? AND status = ? AND assigned_agent_id = ?", conversationUUID, models.ServiceConversationAssigned, agent.ID).
		Updates(map[string]interface{}{"status": models.ServiceConversationServing, "accepted_at": &now})
	if result.Error != nil {
		return nil, result.Error
	}
	if result.RowsAffected != 1 {
		return nil, ErrServiceConversationConflict
	}
	var conversation models.ServiceConversation
	if err := s.db.WithContext(ctx).Where("uuid = ?", conversationUUID).First(&conversation).Error; err != nil {
		return nil, err
	}
	if err := createServiceEvent(s.db.WithContext(ctx), &conversation, "accepted", agentOperatorType(agent), agent.ID, models.ServiceConversationAssigned, models.ServiceConversationServing, nil); err != nil {
		return nil, err
	}
	s.notifyConversation("service.conversation.status_changed", &conversation)
	return s.Get(ctx, agent, conversationUUID)
}

func (s *ServiceConversationService) Transfer(ctx context.Context, agent *models.ServiceAgent, conversationUUID string, targetAgentID uint64, reason string) (*ServiceConversationItem, error) {
	reason = strings.TrimSpace(reason)
	if reason == "" || targetAgentID == 0 || targetAgentID == agent.ID {
		return nil, ErrServiceInvalidTransition
	}
	var target models.ServiceAgent
	if err := s.db.WithContext(ctx).First(&target, targetAgentID).Error; err != nil {
		return nil, ErrServiceAgentForbidden
	}
	if target.Presence == models.ServicePresenceOffline {
		return nil, ErrServiceAgentForbidden
	}
	if err := s.ensureAgentCapacity(ctx, target.ID); err != nil {
		return nil, err
	}

	var conversation models.ServiceConversation
	now := time.Now()
	err := s.db.WithContext(ctx).Transaction(func(tx *gorm.DB) error {
		if err := tx.Clauses(clause.Locking{Strength: "UPDATE"}).Where("uuid = ?", conversationUUID).First(&conversation).Error; err != nil {
			return ErrServiceConversationNotFound
		}
		if conversation.Status == models.ServiceConversationClosed || conversation.AssignedAgentID == nil {
			return ErrServiceInvalidTransition
		}
		if agent.Role != models.ServiceAgentRoleSupervisor && *conversation.AssignedAgentID != agent.ID {
			return ErrServiceAgentForbidden
		}
		oldAgentID := *conversation.AssignedAgentID
		fromStatus := conversation.Status
		if err := tx.Model(&conversation).Updates(map[string]interface{}{
			"assigned_agent_id": target.ID,
			"status":            models.ServiceConversationAssigned,
			"assigned_at":       &now,
			"accepted_at":       nil,
		}).Error; err != nil {
			return err
		}
		conversation.AssignedAgentID = &target.ID
		conversation.Status = models.ServiceConversationAssigned
		conversation.AssignedAt = &now
		conversation.AcceptedAt = nil
		payload := map[string]interface{}{"reason": reason, "from_agent_id": oldAgentID, "to_agent_id": target.ID}
		if err := createServiceEvent(tx, &conversation, "transferred", agentOperatorType(agent), agent.ID, fromStatus, models.ServiceConversationAssigned, payload); err != nil {
			return err
		}
		if err := reconcileAgentServingTx(tx, oldAgentID); err != nil {
			return err
		}
		if err := reconcileAgentServingTx(tx, target.ID); err != nil {
			return err
		}
		return tx.Model(&models.ServiceAgent{}).Where("id = ?", target.ID).Update("last_assigned_at", &now).Error
	})
	if err != nil {
		return nil, err
	}
	s.notifyConversation("service.conversation.transferred", &conversation)
	items, buildErr := s.buildConversationItems([]models.ServiceConversation{conversation})
	if buildErr != nil {
		return nil, buildErr
	}
	return &items[0], nil
}

func (s *ServiceConversationService) ChangeStatus(ctx context.Context, agent *models.ServiceAgent, conversationUUID, nextStatus string) (*ServiceConversationItem, error) {
	if nextStatus != models.ServiceConversationServing && nextStatus != models.ServiceConversationPending {
		return nil, ErrServiceInvalidTransition
	}
	conversation, err := s.findAuthorizedConversation(ctx, agent, conversationUUID, false)
	if err != nil {
		return nil, err
	}
	if conversation.Status != models.ServiceConversationServing && conversation.Status != models.ServiceConversationPending {
		return nil, ErrServiceInvalidTransition
	}
	fromStatus := conversation.Status
	if err := s.db.WithContext(ctx).Model(conversation).Update("status", nextStatus).Error; err != nil {
		return nil, err
	}
	conversation.Status = nextStatus
	if err := createServiceEvent(s.db.WithContext(ctx), conversation, "status_changed", agentOperatorType(agent), agent.ID, fromStatus, nextStatus, nil); err != nil {
		return nil, err
	}
	s.notifyConversation("service.conversation.status_changed", conversation)
	return s.Get(ctx, agent, conversationUUID)
}

func (s *ServiceConversationService) Close(ctx context.Context, agent *models.ServiceAgent, conversationUUID, reason string) (*ServiceConversationItem, error) {
	reason = strings.TrimSpace(reason)
	if reason == "" {
		reason = "客服已解决"
	}
	conversation, err := s.findAuthorizedConversation(ctx, agent, conversationUUID, false)
	if err != nil {
		return nil, err
	}
	if conversation.Status == models.ServiceConversationClosed {
		return nil, ErrServiceConversationConflict
	}
	fromStatus := conversation.Status
	now := time.Now()
	if err := s.db.WithContext(ctx).Model(conversation).Updates(map[string]interface{}{
		"status":       models.ServiceConversationClosed,
		"closed_at":    &now,
		"close_reason": reason,
	}).Error; err != nil {
		return nil, err
	}
	conversation.Status = models.ServiceConversationClosed
	conversation.ClosedAt = &now
	conversation.CloseReason = reason
	if err := createServiceEvent(s.db.WithContext(ctx), conversation, "closed", agentOperatorType(agent), agent.ID, fromStatus, models.ServiceConversationClosed, map[string]interface{}{"reason": reason}); err != nil {
		return nil, err
	}
	if conversation.AssignedAgentID != nil {
		_ = s.reconcileAgentServing(ctx, *conversation.AssignedAgentID)
	}
	s.notifyConversation("service.conversation.status_changed", conversation)
	return s.Get(ctx, agent, conversationUUID)
}

func (s *ServiceConversationService) Reopen(ctx context.Context, agent *models.ServiceAgent, conversationUUID string) (*ServiceConversationItem, error) {
	if _, err := s.findAuthorizedConversation(ctx, agent, conversationUUID, false); err != nil {
		return nil, err
	}
	if err := s.ensureAgentCapacity(ctx, agent.ID); err != nil {
		return nil, err
	}
	var conversation models.ServiceConversation
	now := time.Now()
	result := s.db.WithContext(ctx).Model(&models.ServiceConversation{}).
		Where("uuid = ? AND status = ?", conversationUUID, models.ServiceConversationClosed).
		Updates(map[string]interface{}{
			"status":            models.ServiceConversationServing,
			"assigned_agent_id": agent.ID,
			"assigned_at":       &now,
			"accepted_at":       &now,
			"closed_at":         nil,
			"close_reason":      "",
		})
	if result.Error != nil {
		return nil, result.Error
	}
	if result.RowsAffected != 1 {
		return nil, ErrServiceConversationConflict
	}
	if err := s.db.WithContext(ctx).Where("uuid = ?", conversationUUID).First(&conversation).Error; err != nil {
		return nil, err
	}
	if err := createServiceEvent(s.db.WithContext(ctx), &conversation, "reopened", agentOperatorType(agent), agent.ID, models.ServiceConversationClosed, models.ServiceConversationServing, nil); err != nil {
		return nil, err
	}
	_ = s.reconcileAgentServing(ctx, agent.ID)
	s.notifyConversation("service.conversation.status_changed", &conversation)
	return s.Get(ctx, agent, conversationUUID)
}

func (s *ServiceConversationService) MarkRead(ctx context.Context, agent *models.ServiceAgent, conversationUUID string) error {
	conversation, err := s.findAuthorizedConversation(ctx, agent, conversationUUID, false)
	if err != nil {
		return err
	}
	return s.db.WithContext(ctx).Model(conversation).Update("customer_unread_count", 0).Error
}

func (s *ServiceConversationService) Messages(ctx context.Context, agent *models.ServiceAgent, conversationUUID string, beforeSeq, limit int) ([]*models.Message, error) {
	conversation, err := s.findAuthorizedConversation(ctx, agent, conversationUUID, true)
	if err != nil {
		return nil, err
	}
	var identity models.User
	if err := s.db.WithContext(ctx).Select("uuid").First(&identity, conversation.ServiceIdentityUserID).Error; err != nil {
		return nil, err
	}
	if limit <= 0 || limit > 100 {
		limit = 50
	}
	return s.msgService.GetMessages(ctx, &GetMessagesParams{
		ChatID: conversation.ChatUUID, UserID: identity.UUID, BeforeSeq: beforeSeq, Limit: limit,
	})
}

func (s *ServiceConversationService) SendText(ctx context.Context, agent *models.ServiceAgent, agentUser *models.User, conversationUUID, text, clientMsgID string) (*models.Message, error) {
	text = strings.TrimSpace(text)
	if text == "" || utf8.RuneCountInString(text) > 2000 {
		return nil, ErrServiceInvalidTransition
	}
	var cryptoSetting models.SystemSetting
	if err := s.db.WithContext(ctx).Where("`key` = ?", models.SettingMessageCryptoMode).First(&cryptoSetting).Error; err == nil && strings.EqualFold(strings.TrimSpace(cryptoSetting.Value), models.MessageCryptoModeStrict) {
		return nil, ErrServiceEncryptionUnsupported
	}
	conversation, err := s.findAuthorizedConversation(ctx, agent, conversationUUID, false)
	if err != nil {
		return nil, err
	}
	if conversation.Status != models.ServiceConversationServing && conversation.Status != models.ServiceConversationPending {
		return nil, ErrServiceInvalidTransition
	}
	var identity, customer models.User
	if err := s.db.WithContext(ctx).First(&identity, conversation.ServiceIdentityUserID).Error; err != nil {
		return nil, err
	}
	if err := s.db.WithContext(ctx).First(&customer, conversation.CustomerUserID).Error; err != nil {
		return nil, err
	}

	result, err := s.msgService.SendMessageWithResult(ctx, &SendMessageParams{
		ChatID:         conversation.ChatUUID,
		SenderID:       identity.UUID,
		SenderDeviceID: "service-admin-web",
		Type:           models.MsgTypeText,
		Content:        map[string]interface{}{"text": text},
		MsgID:          strings.TrimSpace(clientMsgID),
		OperatorType:   "human",
		OperatorID:     agentUser.UUID,
	}, identity.Nickname, identity.Avatar, identity.NicknameColor, identity.EmojiAvatar, []string{customer.UUID})
	if err != nil {
		return nil, err
	}
	if result == nil || result.Message == nil {
		return nil, errors.New("message service returned empty message")
	}
	if result.Duplicate {
		return result.Message, nil
	}
	msg := result.Message
	now := msg.CreatedAt
	updates := map[string]interface{}{
		"last_message_id":       msg.MsgID,
		"last_message_text":     text,
		"last_message_type":     msg.Type,
		"last_message_at":       &now,
		"customer_unread_count": 0,
		"status":                models.ServiceConversationServing,
	}
	if conversation.FirstResponseAt == nil {
		updates["first_response_at"] = &now
	}
	if err := s.db.WithContext(ctx).Model(conversation).Updates(updates).Error; err != nil {
		return nil, err
	}
	s.db.WithContext(ctx).Model(&models.UserChat{}).Where("chat_id = ?", conversation.ChatID).Updates(map[string]interface{}{
		"last_msg_text": text, "last_msg_type": msg.Type, "last_msg_time": now,
		"last_msg_seq": msg.Seq, "last_msg_sender": identity.Nickname, "sort_time": now,
	})
	s.db.WithContext(ctx).Model(&models.UserChat{}).
		Where("chat_id = ? AND user_id = ?", conversation.ChatID, customer.ID).
		UpdateColumn("unread_count", gorm.Expr("unread_count + 1"))

	_ = createServiceEvent(s.db.WithContext(ctx), conversation, "message_sent", agentOperatorType(agent), agent.ID, conversation.Status, models.ServiceConversationServing, map[string]interface{}{"message_id": msg.MsgID})
	return msg, nil
}

// OnCustomerMessage

func (s *ServiceConversationService) OnCustomerMessage(ctx context.Context, sender *models.User, chat *models.Chat, otherMemberIDs []uint64, msg *models.Message, preview string) error {
	if s == nil || s.db == nil || sender == nil || chat == nil || msg == nil || chat.Type != 1 || len(otherMemberIDs) == 0 {
		return nil
	}
	var senderOfficialCount int64
	if err := s.db.WithContext(ctx).Model(&models.OfficialUser{}).
		Where("user_id = ? AND is_service_enabled = ?", sender.ID, true).Count(&senderOfficialCount).Error; err != nil {
		return err
	}
	if senderOfficialCount > 0 {
		return nil
	}
	var official models.OfficialUser
	if err := s.db.WithContext(ctx).Where("user_id IN ? AND is_service_enabled = ?", otherMemberIDs, true).
		Order("sort_order ASC, id ASC").First(&official).Error; err != nil {
		if errors.Is(err, gorm.ErrRecordNotFound) {
			return nil
		}
		return err
	}
	if official.UserID == sender.ID {
		return nil
	}

	preview = truncateRunes(strings.TrimSpace(preview), 500)
	now := msg.CreatedAt
	if now.IsZero() {
		now = time.Now()
	}
	var conversation models.ServiceConversation
	created := false
	applied := false
	fromStatus := ""
	err := s.db.WithContext(ctx).Transaction(func(tx *gorm.DB) error {
		err := tx.Clauses(clause.Locking{Strength: "UPDATE"}).
			Where("chat_id = ? AND customer_user_id = ? AND service_identity_user_id = ? AND status <> ?", chat.ID, sender.ID, official.UserID, models.ServiceConversationClosed).
			Order("id DESC").First(&conversation).Error
		if err != nil && !errors.Is(err, gorm.ErrRecordNotFound) {
			return err
		}
		if errors.Is(err, gorm.ErrRecordNotFound) {
			var maxRound int
			tx.Model(&models.ServiceConversation{}).Where("chat_id = ?", chat.ID).Select("COALESCE(MAX(round_no), 0)").Scan(&maxRound)
			conversation = models.ServiceConversation{
				UUID:                  uuid.NewString(),
				ChatID:                chat.ID,
				ChatUUID:              chat.UUID,
				CustomerUserID:        sender.ID,
				ServiceIdentityUserID: official.UserID,
				Status:                models.ServiceConversationWaiting,
				Source:                "direct",
				RoundNo:               maxRound + 1,
				QueuedAt:              now,
				AIStatus:              "disabled",
			}
			created = true
		} else {
			fromStatus = conversation.Status
			// Outbox may retry after a process crash or deliver an older event
			// after a newer one. The chat sequence is the durable idempotency
			// cursor: never increment unread or roll the preview backwards.
			if msg.Seq > 0 && msg.Seq <= conversation.LastCustomerMessageSeq {
				return nil
			}
			if conversation.Status == models.ServiceConversationPending {
				conversation.Status = models.ServiceConversationServing
			}
		}
		conversation.LastMessageID = msg.MsgID
		conversation.LastCustomerMessageSeq = msg.Seq
		conversation.LastMessageText = preview
		conversation.LastMessageType = msg.Type
		conversation.LastMessageAt = &now
		conversation.CustomerUnreadCount++
		applied = true
		if created {
			if err := tx.Create(&conversation).Error; err != nil {
				return err
			}
			return createServiceEvent(tx, &conversation, "created", models.ServiceOperatorCustomer, sender.ID, "", models.ServiceConversationWaiting, map[string]interface{}{"message_id": msg.MsgID})
		}
		if err := tx.Save(&conversation).Error; err != nil {
			return err
		}
		if fromStatus == models.ServiceConversationPending {
			return createServiceEvent(tx, &conversation, "status_changed", models.ServiceOperatorCustomer, sender.ID, fromStatus, models.ServiceConversationServing, map[string]interface{}{"message_id": msg.MsgID})
		}
		return nil
	})
	if err != nil {
		return err
	}
	if !applied {
		return nil
	}
	if created {
		_ = s.autoAssign(ctx, &conversation)
	}
	s.notifyConversation("service.message.new", &conversation)
	return nil
}

func (s *ServiceConversationService) autoAssign(ctx context.Context, conversation *models.ServiceConversation) error {
	if conversation == nil || conversation.Status != models.ServiceConversationWaiting {
		return nil
	}
	now := time.Now()
	return s.db.WithContext(ctx).Transaction(func(tx *gorm.DB) error {
		var candidate models.ServiceAgent
		if err := tx.Clauses(clause.Locking{Strength: "UPDATE"}).
			Where("presence = ? AND auto_assign_enabled = ? AND current_serving < max_concurrent AND last_heartbeat_at >= ?", models.ServicePresenceOnline, true, now.Add(-90*time.Second)).
			Order("current_serving ASC").Order("last_assigned_at IS NOT NULL ASC").Order("last_assigned_at ASC").
			First(&candidate).Error; err != nil {
			if errors.Is(err, gorm.ErrRecordNotFound) {
				return nil
			}
			return err
		}
		result := tx.Model(&models.ServiceConversation{}).
			Where("id = ? AND status = ? AND assigned_agent_id IS NULL", conversation.ID, models.ServiceConversationWaiting).
			Updates(map[string]interface{}{"status": models.ServiceConversationAssigned, "assigned_agent_id": candidate.ID, "assigned_at": &now})
		if result.Error != nil || result.RowsAffected != 1 {
			return result.Error
		}
		conversation.Status = models.ServiceConversationAssigned
		conversation.AssignedAgentID = &candidate.ID
		conversation.AssignedAt = &now
		if err := tx.Model(&models.ServiceAgent{}).Where("id = ?", candidate.ID).Updates(map[string]interface{}{
			"current_serving": gorm.Expr("current_serving + 1"), "last_assigned_at": &now,
		}).Error; err != nil {
			return err
		}
		return createServiceEvent(tx, conversation, "assigned", models.ServiceOperatorSystem, 0, models.ServiceConversationWaiting, models.ServiceConversationAssigned, map[string]interface{}{"agent_id": candidate.ID})
	})
}

func (s *ServiceConversationService) findAuthorizedConversation(ctx context.Context, agent *models.ServiceAgent, conversationUUID string, allowWaiting bool) (*models.ServiceConversation, error) {
	if agent == nil {
		return nil, ErrServiceAgentForbidden
	}
	var conversation models.ServiceConversation
	if err := s.db.WithContext(ctx).Where("uuid = ?", strings.TrimSpace(conversationUUID)).First(&conversation).Error; err != nil {
		return nil, ErrServiceConversationNotFound
	}
	if agent.Role == models.ServiceAgentRoleSupervisor {
		return &conversation, nil
	}
	if allowWaiting && conversation.Status == models.ServiceConversationWaiting {
		return &conversation, nil
	}
	if conversation.AssignedAgentID == nil || *conversation.AssignedAgentID != agent.ID {
		return nil, ErrServiceAgentForbidden
	}
	return &conversation, nil
}

func (s *ServiceConversationService) buildConversationItems(rows []models.ServiceConversation) ([]ServiceConversationItem, error) {
	items := make([]ServiceConversationItem, 0, len(rows))
	for i := range rows {
		row := rows[i]
		var customer models.User
		if err := s.db.First(&customer, row.CustomerUserID).Error; err != nil {
			return nil, err
		}
		customerSummary, err := buildServiceCustomerSummary(s.db, customer)
		if err != nil {
			return nil, err
		}
		item := ServiceConversationItem{
			UUID: row.UUID, ChatUUID: row.ChatUUID, Status: row.Status, Priority: row.Priority,
			Source: row.Source, RoundNo: row.RoundNo, LastMessageID: row.LastMessageID,
			LastMessageText: row.LastMessageText, LastMessageType: row.LastMessageType,
			LastMessageAt: row.LastMessageAt, UnreadCount: row.CustomerUnreadCount,
			AIStatus: row.AIStatus, QueuedAt: row.QueuedAt, AssignedAt: row.AssignedAt,
			AcceptedAt: row.AcceptedAt, FirstResponseAt: row.FirstResponseAt,
			ClosedAt: row.ClosedAt, CloseReason: row.CloseReason, CreatedAt: row.CreatedAt, UpdatedAt: row.UpdatedAt,
			Customer: *customerSummary,
		}
		if row.Status == models.ServiceConversationWaiting {
			item.WaitingSeconds = int64(time.Since(row.QueuedAt).Seconds())
			if item.WaitingSeconds < 0 {
				item.WaitingSeconds = 0
			}
		}
		if row.AssignedAgentID != nil {
			var assigned models.ServiceAgent
			if err := s.db.First(&assigned, *row.AssignedAgentID).Error; err == nil {
				summary, summaryErr := s.agentSummary(&assigned)
				if summaryErr != nil {
					return nil, summaryErr
				}
				item.AssignedAgent = summary
			}
		}
		items = append(items, item)
	}
	return items, nil
}

func (s *ServiceConversationService) agentSummary(agent *models.ServiceAgent) (*ServiceAgentSummary, error) {
	var user models.User
	if err := s.db.Select("id", "uuid", "nickname", "avatar").First(&user, agent.UserID).Error; err != nil {
		return nil, err
	}
	return &ServiceAgentSummary{
		ID: agent.ID, UserID: agent.UserID, UUID: user.UUID, Nickname: user.Nickname,
		Avatar: user.Avatar, Presence: agent.Presence, CurrentServing: agent.CurrentServing,
		MaxConcurrent: agent.MaxConcurrent, AutoAssignEnabled: agent.AutoAssignEnabled,
	}, nil
}

func (s *ServiceConversationService) ensureAgentCapacity(ctx context.Context, agentID uint64) error {
	var agent models.ServiceAgent
	if err := s.db.WithContext(ctx).First(&agent, agentID).Error; err != nil {
		return ErrServiceAgentForbidden
	}
	var count int64
	if err := s.db.WithContext(ctx).Model(&models.ServiceConversation{}).
		Where("assigned_agent_id = ? AND status IN ?", agentID, []string{models.ServiceConversationAssigned, models.ServiceConversationServing}).Count(&count).Error; err != nil {
		return err
	}
	if int(count) >= agent.MaxConcurrent {
		return ErrServiceAgentAtCapacity
	}
	return nil
}

func (s *ServiceConversationService) reconcileAgentServing(ctx context.Context, agentID uint64) error {
	return reconcileAgentServingTx(s.db.WithContext(ctx), agentID)
}

func reconcileAgentServingTx(tx *gorm.DB, agentID uint64) error {
	if agentID == 0 {
		return nil
	}
	var count int64
	if err := tx.Model(&models.ServiceConversation{}).
		Where("assigned_agent_id = ? AND status IN ?", agentID, []string{models.ServiceConversationAssigned, models.ServiceConversationServing}).Count(&count).Error; err != nil {
		return err
	}
	return tx.Model(&models.ServiceAgent{}).Where("id = ?", agentID).Update("current_serving", count).Error
}

func createServiceEvent(tx *gorm.DB, conversation *models.ServiceConversation, eventType, operatorType string, operatorID uint64, fromStatus, toStatus string, payload interface{}) error {
	payloadJSON := ""
	if payload != nil {
		if encoded, err := json.Marshal(payload); err == nil {
			payloadJSON = string(encoded)
		}
	}
	return tx.Create(&models.ServiceConversationEvent{
		ConversationID: conversation.ID, EventType: eventType, OperatorType: operatorType,
		OperatorID: operatorID, FromStatus: fromStatus, ToStatus: toStatus,
		PayloadJSON: payloadJSON, CreatedAt: time.Now(),
	}).Error
}

func agentOperatorType(agent *models.ServiceAgent) string {
	if agent != nil && agent.Role == models.ServiceAgentRoleSupervisor {
		return models.ServiceOperatorSupervisor
	}
	return models.ServiceOperatorAgent
}

func (s *ServiceConversationService) notifyConversation(eventType string, conversation *models.ServiceConversation) {
	if s == nil || s.hub == nil || conversation == nil {
		return
	}
	query := s.db.Model(&models.ServiceAgent{}).Select("users.uuid").Joins("JOIN users ON users.id = service_agents.user_id").
		Where("service_agents.presence IN ? AND service_agents.last_heartbeat_at >= ?", []string{models.ServicePresenceOnline, models.ServicePresenceBusy}, time.Now().Add(-90*time.Second))
	var userUUIDs []string
	if err := query.Pluck("users.uuid", &userUUIDs).Error; err != nil {
		return
	}
	if conversation.AssignedAgentID != nil {
		var assignedUUID string
		s.db.Model(&models.ServiceAgent{}).Select("users.uuid").Joins("JOIN users ON users.id = service_agents.user_id").
			Where("service_agents.id = ?", *conversation.AssignedAgentID).Scan(&assignedUUID)
		if assignedUUID != "" {
			userUUIDs = append(userUUIDs, assignedUUID)
		}
	}
	if len(userUUIDs) == 0 {
		return
	}
	s.hub.SendToUsers(userUUIDs, map[string]interface{}{
		"type":              eventType,
		"event_id":          uuid.NewString(),
		"conversation_uuid": conversation.UUID,
		"status":            conversation.Status,
		"updated_at":        time.Now(),
	})
}

func (s *ServiceConversationService) notifyPresence(summary *ServiceAgentSummary) {
	if s == nil || s.hub == nil || summary == nil {
		return
	}
	var userUUIDs []string
	if err := s.db.Model(&models.ServiceAgent{}).Select("users.uuid").Joins("JOIN users ON users.id = service_agents.user_id").
		Pluck("users.uuid", &userUUIDs).Error; err != nil || len(userUUIDs) == 0 {
		return
	}
	s.hub.SendToUsers(userUUIDs, map[string]interface{}{
		"type":       "service.agent.presence_changed",
		"event_id":   uuid.NewString(),
		"agent":      summary,
		"updated_at": time.Now(),
	})
}

func truncateRunes(value string, max int) string {
	if max <= 0 || utf8.RuneCountInString(value) <= max {
		return value
	}
	runes := []rune(value)
	return string(runes[:max])
}

func maskServicePhone(phone string) string {
	phone = strings.TrimSpace(phone)
	if len(phone) < 7 {
		return phone
	}
	return fmt.Sprintf("%s****%s", phone[:3], phone[len(phone)-4:])
}
