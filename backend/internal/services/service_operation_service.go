// 文件用途：实现可复用的后端业务服务和领域逻辑。
// 核心逻辑：协调数据库、缓存、队列和外部服务，集中处理事务、幂等、重试和错误传播。

package services

import (
	"context"
	"encoding/json"
	"errors"
	"github.com/google/uuid"
	"gorm.io/gorm"
	"strings"
	"time"
	"genericim/internal/models"
)

type ServiceOperationService struct {
	db *gorm.DB
}

func NewServiceOperationService(db *gorm.DB) *ServiceOperationService {
	return &ServiceOperationService{db: db}
}

type ServiceQuickReplyInput struct {
	Category  string `json:"category"`
	Title     string `json:"title"`
	Content   string `json:"content"`
	Shortcut  string `json:"shortcut"`
	Keywords  string `json:"keywords"`
	SortOrder int    `json:"sort_order"`
	Enabled   *bool  `json:"enabled"`
}

type ServiceFollowUpSummary struct {
	UUID      string     `json:"uuid"`
	Content   string     `json:"content"`
	DueAt     time.Time  `json:"due_at"`
	Status    string     `json:"status"`
	AgentID   uint64     `json:"agent_id"`
	AgentName string     `json:"agent_name"`
	Completed *time.Time `json:"completed_at,omitempty"`
	CreatedAt time.Time  `json:"created_at"`
}

type ServiceCustomerDirectoryItem struct {
	Customer             ServiceCustomerSummary  `json:"customer"`
	ConversationCount    int64                   `json:"conversation_count"`
	LastConversationUUID string                  `json:"last_conversation_uuid"`
	LastConversationAt   time.Time               `json:"last_conversation_at"`
	LastConversation     string                  `json:"last_conversation_status"`
	PendingFollowUp      *ServiceFollowUpSummary `json:"pending_follow_up,omitempty"`
}

type ServiceCustomerDirectoryResult struct {
	List  []ServiceCustomerDirectoryItem `json:"list"`
	Total int64                          `json:"total"`
	Page  int                            `json:"page"`
	Limit int                            `json:"limit"`
}

type ServiceCustomerProfileInput struct {
	Tags []string `json:"tags"`
	Note string   `json:"note"`
}

type ServiceFollowUpInput struct {
	ConversationUUID string    `json:"conversation_uuid"`
	Content          string    `json:"content"`
	DueAt            time.Time `json:"due_at"`
}

type ServiceFollowUpUpdateInput struct {
	Content string     `json:"content"`
	DueAt   *time.Time `json:"due_at"`
	Status  string     `json:"status"`
}

func (s *ServiceOperationService) ListQuickReplies(ctx context.Context, agent *models.ServiceAgent, keyword, category string, includeDisabled bool) ([]models.ServiceQuickReply, error) {
	if agent == nil {
		return nil, ErrServiceAgentForbidden
	}
	if err := s.seedQuickReplies(ctx, agent.ID); err != nil {
		return nil, err
	}
	query := s.db.WithContext(ctx).Model(&models.ServiceQuickReply{})
	if !includeDisabled {
		query = query.Where("enabled = ?", true)
	}
	if category = strings.TrimSpace(category); category != "" {
		query = query.Where("category = ?", category)
	}
	if keyword = strings.TrimSpace(keyword); keyword != "" {
		like := "%" + keyword + "%"
		query = query.Where("title LIKE ? OR content LIKE ? OR shortcut LIKE ? OR keywords LIKE ?", like, like, like, like)
	}
	var rows []models.ServiceQuickReply
	if err := query.Order("sort_order DESC, updated_at DESC").Find(&rows).Error; err != nil {
		return nil, err
	}
	return rows, nil
}

func (s *ServiceOperationService) CreateQuickReply(ctx context.Context, agent *models.ServiceAgent, input ServiceQuickReplyInput) (*models.ServiceQuickReply, error) {
	if agent == nil {
		return nil, ErrServiceAgentForbidden
	}
	category, title, content, shortcut, keywords, err := normalizeQuickReply(input)
	if err != nil {
		return nil, err
	}
	enabled := true
	if input.Enabled != nil {
		enabled = *input.Enabled
	}
	reply := models.ServiceQuickReply{
		UUID: uuid.NewString(), Category: category, Title: title, Content: content,
		Shortcut: shortcut, Keywords: keywords, SortOrder: input.SortOrder, Enabled: enabled,
		CreatedByAgentID: agent.ID, UpdatedByAgentID: agent.ID,
	}
	if err := s.db.WithContext(ctx).Create(&reply).Error; err != nil {
		return nil, err
	}
	return &reply, nil
}

func (s *ServiceOperationService) UpdateQuickReply(ctx context.Context, agent *models.ServiceAgent, replyUUID string, input ServiceQuickReplyInput) (*models.ServiceQuickReply, error) {
	if agent == nil {
		return nil, ErrServiceAgentForbidden
	}
	category, title, content, shortcut, keywords, err := normalizeQuickReply(input)
	if err != nil {
		return nil, err
	}
	var reply models.ServiceQuickReply
	if err := s.db.WithContext(ctx).Where("uuid = ?", strings.TrimSpace(replyUUID)).First(&reply).Error; err != nil {
		return nil, ErrServiceConversationNotFound
	}
	updates := map[string]interface{}{
		"category": category, "title": title, "content": content, "shortcut": shortcut,
		"keywords": keywords, "sort_order": input.SortOrder, "updated_by_agent_id": agent.ID,
	}
	if input.Enabled != nil {
		updates["enabled"] = *input.Enabled
	}
	if err := s.db.WithContext(ctx).Model(&reply).Updates(updates).Error; err != nil {
		return nil, err
	}
	if err := s.db.WithContext(ctx).Where("id = ?", reply.ID).First(&reply).Error; err != nil {
		return nil, err
	}
	return &reply, nil
}

func (s *ServiceOperationService) DeleteQuickReply(ctx context.Context, agent *models.ServiceAgent, replyUUID string) error {
	if agent == nil {
		return ErrServiceAgentForbidden
	}
	result := s.db.WithContext(ctx).Where("uuid = ?", strings.TrimSpace(replyUUID)).Delete(&models.ServiceQuickReply{})
	if result.Error != nil {
		return result.Error
	}
	if result.RowsAffected != 1 {
		return ErrServiceConversationNotFound
	}
	return nil
}

func (s *ServiceOperationService) ListCustomers(ctx context.Context, agent *models.ServiceAgent, keyword string, page, pageSize int) (*ServiceCustomerDirectoryResult, error) {
	if agent == nil {
		return nil, ErrServiceAgentForbidden
	}
	if page <= 0 {
		page = 1
	}
	if pageSize <= 0 || pageSize > 100 {
		pageSize = 30
	}
	base := s.db.WithContext(ctx).Table("service_conversations").
		Joins("JOIN users service_customer_directory ON service_customer_directory.id = service_conversations.customer_user_id")
	if keyword = strings.TrimSpace(keyword); keyword != "" {
		like := "%" + keyword + "%"
		base = base.Where("service_customer_directory.nickname LIKE ? OR service_customer_directory.username LIKE ? OR service_customer_directory.uuid LIKE ?", like, like, like)
	}
	var total int64
	if err := base.Distinct("service_conversations.customer_user_id").Count(&total).Error; err != nil {
		return nil, err
	}
	type directoryRow struct {
		CustomerUserID     uint64
		ConversationCount  int64
		LastConversationAt time.Time
	}
	var rows []directoryRow
	if err := base.Select("service_conversations.customer_user_id, COUNT(*) AS conversation_count, MAX(service_conversations.updated_at) AS last_conversation_at").
		Group("service_conversations.customer_user_id").Order("last_conversation_at DESC").
		Offset((page - 1) * pageSize).Limit(pageSize).Scan(&rows).Error; err != nil {
		return nil, err
	}
	items := make([]ServiceCustomerDirectoryItem, 0, len(rows))
	for _, row := range rows {
		var user models.User
		if err := s.db.WithContext(ctx).First(&user, row.CustomerUserID).Error; err != nil {
			return nil, err
		}
		customer, err := buildServiceCustomerSummary(s.db.WithContext(ctx), user)
		if err != nil {
			return nil, err
		}
		var last models.ServiceConversation
		if err := s.db.WithContext(ctx).Where("customer_user_id = ?", row.CustomerUserID).Order("updated_at DESC").First(&last).Error; err != nil {
			return nil, err
		}
		pending, err := s.latestPendingFollowUp(ctx, row.CustomerUserID)
		if err != nil {
			return nil, err
		}
		items = append(items, ServiceCustomerDirectoryItem{
			Customer: *customer, ConversationCount: row.ConversationCount,
			LastConversationUUID: last.UUID, LastConversationAt: row.LastConversationAt,
			LastConversation: last.Status, PendingFollowUp: pending,
		})
	}
	return &ServiceCustomerDirectoryResult{List: items, Total: total, Page: page, Limit: pageSize}, nil
}

func (s *ServiceOperationService) GetCustomer(ctx context.Context, agent *models.ServiceAgent, customerUUID string) (*ServiceCustomerSummary, error) {
	if agent == nil {
		return nil, ErrServiceAgentForbidden
	}
	user, err := s.findServiceCustomer(ctx, customerUUID)
	if err != nil {
		return nil, err
	}
	return buildServiceCustomerSummary(s.db.WithContext(ctx), *user)
}

func (s *ServiceOperationService) UpdateCustomerProfile(ctx context.Context, agent *models.ServiceAgent, customerUUID string, input ServiceCustomerProfileInput) (*ServiceCustomerSummary, error) {
	if agent == nil {
		return nil, ErrServiceAgentForbidden
	}
	user, err := s.findServiceCustomer(ctx, customerUUID)
	if err != nil {
		return nil, err
	}
	tags, err := normalizeServiceTags(input.Tags)
	if err != nil || len([]rune(strings.TrimSpace(input.Note))) > 2000 {
		return nil, ErrServiceInvalidTransition
	}
	encoded, _ := json.Marshal(tags)
	profile := models.ServiceCustomerProfile{CustomerUserID: user.ID}
	result := s.db.WithContext(ctx).Where("customer_user_id = ?", user.ID).First(&profile)
	if errors.Is(result.Error, gorm.ErrRecordNotFound) {
		profile.TagsJSON = string(encoded)
		profile.InternalNote = strings.TrimSpace(input.Note)
		profile.UpdatedByAgentID = agent.ID
		if err := s.db.WithContext(ctx).Create(&profile).Error; err != nil {
			return nil, err
		}
	} else if result.Error != nil {
		return nil, result.Error
	} else if err := s.db.WithContext(ctx).Model(&profile).Updates(map[string]interface{}{
		"tags_json": string(encoded), "internal_note": strings.TrimSpace(input.Note), "updated_by_agent_id": agent.ID,
	}).Error; err != nil {
		return nil, err
	}
	return buildServiceCustomerSummary(s.db.WithContext(ctx), *user)
}

func (s *ServiceOperationService) ListFollowUps(ctx context.Context, agent *models.ServiceAgent, customerUUID, status string) ([]ServiceFollowUpSummary, error) {
	if agent == nil {
		return nil, ErrServiceAgentForbidden
	}
	query := s.db.WithContext(ctx).Model(&models.ServiceFollowUp{})
	if strings.TrimSpace(customerUUID) != "" {
		user, err := s.findServiceCustomer(ctx, customerUUID)
		if err != nil {
			return nil, err
		}
		query = query.Where("customer_user_id = ?", user.ID)
	}
	if status = strings.TrimSpace(status); status != "" {
		query = query.Where("status = ?", status)
	}
	if agent.Role != models.ServiceAgentRoleSupervisor {
		query = query.Where("assigned_agent_id = ?", agent.ID)
	}
	var rows []models.ServiceFollowUp
	if err := query.Order("status = 'pending' DESC, due_at ASC").Limit(200).Find(&rows).Error; err != nil {
		return nil, err
	}
	return s.buildFollowUpSummaries(ctx, rows)
}

func (s *ServiceOperationService) CreateFollowUp(ctx context.Context, agent *models.ServiceAgent, customerUUID string, input ServiceFollowUpInput) (*ServiceFollowUpSummary, error) {
	if agent == nil {
		return nil, ErrServiceAgentForbidden
	}
	user, err := s.findServiceCustomer(ctx, customerUUID)
	if err != nil {
		return nil, err
	}
	content := strings.TrimSpace(input.Content)
	if content == "" || len([]rune(content)) > 500 || input.DueAt.IsZero() {
		return nil, ErrServiceInvalidTransition
	}
	var conversationID *uint64
	if strings.TrimSpace(input.ConversationUUID) != "" {
		var conversation models.ServiceConversation
		if err := s.db.WithContext(ctx).Where("uuid = ? AND customer_user_id = ?", strings.TrimSpace(input.ConversationUUID), user.ID).First(&conversation).Error; err != nil {
			return nil, ErrServiceConversationNotFound
		}
		conversationID = &conversation.ID
	}
	followUp := models.ServiceFollowUp{
		UUID: uuid.NewString(), CustomerUserID: user.ID, ConversationID: conversationID,
		AssignedAgentID: agent.ID, Content: content, DueAt: input.DueAt,
		Status: models.ServiceFollowUpPending, CreatedByAgentID: agent.ID,
	}
	if err := s.db.WithContext(ctx).Create(&followUp).Error; err != nil {
		return nil, err
	}
	summaries, err := s.buildFollowUpSummaries(ctx, []models.ServiceFollowUp{followUp})
	if err != nil || len(summaries) == 0 {
		return nil, err
	}
	return &summaries[0], nil
}

func (s *ServiceOperationService) UpdateFollowUp(ctx context.Context, agent *models.ServiceAgent, followUpUUID string, input ServiceFollowUpUpdateInput) (*ServiceFollowUpSummary, error) {
	if agent == nil {
		return nil, ErrServiceAgentForbidden
	}
	var followUp models.ServiceFollowUp
	if err := s.db.WithContext(ctx).Where("uuid = ?", strings.TrimSpace(followUpUUID)).First(&followUp).Error; err != nil {
		return nil, ErrServiceConversationNotFound
	}
	if agent.Role != models.ServiceAgentRoleSupervisor && followUp.AssignedAgentID != agent.ID {
		return nil, ErrServiceAgentForbidden
	}
	updates := map[string]interface{}{}
	if content := strings.TrimSpace(input.Content); content != "" {
		if len([]rune(content)) > 500 {
			return nil, ErrServiceInvalidTransition
		}
		updates["content"] = content
	}
	if input.DueAt != nil && !input.DueAt.IsZero() {
		updates["due_at"] = *input.DueAt
	}
	if status := strings.TrimSpace(input.Status); status != "" {
		if status != models.ServiceFollowUpPending && status != models.ServiceFollowUpDone && status != models.ServiceFollowUpCanceled {
			return nil, ErrServiceInvalidTransition
		}

		updates["status"] = status
		if status == models.ServiceFollowUpDone {
			now := time.Now()
			updates["completed_at"] = &now
		} else {
			updates["completed_at"] = nil
		}
	}
	if len(updates) == 0 {
		return nil, ErrServiceInvalidTransition
	}
	if err := s.db.WithContext(ctx).Model(&followUp).Updates(updates).Error; err != nil {
		return nil, err
	}
	if err := s.db.WithContext(ctx).Where("id = ?", followUp.ID).First(&followUp).Error; err != nil {
		return nil, err
	}
	summaries, err := s.buildFollowUpSummaries(ctx, []models.ServiceFollowUp{followUp})
	if err != nil || len(summaries) == 0 {
		return nil, err
	}
	return &summaries[0], nil
}

func (s *ServiceOperationService) seedQuickReplies(ctx context.Context, agentID uint64) error {

	var count int64
	if err := s.db.WithContext(ctx).Model(&models.ServiceQuickReply{}).Count(&count).Error; err != nil || count > 0 {
		return err
	}
	defaults := []models.ServiceQuickReply{
		{UUID: uuid.NewString(), Category: "通用", Title: "欢迎咨询", Content: "您好，我是本次为您服务的客服，请问有什么可以帮您？", Shortcut: "/hello", Keywords: "欢迎,您好", SortOrder: 100, Enabled: true},
		{UUID: uuid.NewString(), Category: "排查", Title: "收集问题信息", Content: "为了更快定位问题，请您提供设备型号、客户端版本和问题发生时间。", Shortcut: "/info", Keywords: "版本,设备,排查", SortOrder: 90, Enabled: true},
		{UUID: uuid.NewString(), Category: "进度", Title: "处理中", Content: "问题已经记录，我正在为您核查，请稍等片刻。", Shortcut: "/checking", Keywords: "等待,核查,处理中", SortOrder: 80, Enabled: true},
		{UUID: uuid.NewString(), Category: "结束", Title: "确认解决", Content: "请问刚才的问题是否已经解决？如果还有其他问题，我可以继续协助您。", Shortcut: "/solved", Keywords: "解决,确认", SortOrder: 70, Enabled: true},
		{UUID: uuid.NewString(), Category: "结束", Title: "结束致谢", Content: "感谢您的反馈，祝您使用愉快。如有其他问题，欢迎随时联系我们。", Shortcut: "/thanks", Keywords: "感谢,结束", SortOrder: 60, Enabled: true},
	}
	for i := range defaults {
		defaults[i].CreatedByAgentID = agentID
		defaults[i].UpdatedByAgentID = agentID
	}
	return s.db.WithContext(ctx).Create(&defaults).Error
}

func (s *ServiceOperationService) findServiceCustomer(ctx context.Context, customerUUID string) (*models.User, error) {
	var user models.User
	if err := s.db.WithContext(ctx).Where("uuid = ?", strings.TrimSpace(customerUUID)).First(&user).Error; err != nil {
		return nil, ErrServiceConversationNotFound
	}
	var count int64
	if err := s.db.WithContext(ctx).Model(&models.ServiceConversation{}).Where("customer_user_id = ?", user.ID).Count(&count).Error; err != nil {
		return nil, err
	}
	if count == 0 {
		return nil, ErrServiceConversationNotFound
	}
	return &user, nil
}

func (s *ServiceOperationService) latestPendingFollowUp(ctx context.Context, customerUserID uint64) (*ServiceFollowUpSummary, error) {
	var row models.ServiceFollowUp
	err := s.db.WithContext(ctx).Where("customer_user_id = ? AND status = ?", customerUserID, models.ServiceFollowUpPending).Order("due_at ASC").First(&row).Error
	if errors.Is(err, gorm.ErrRecordNotFound) {
		return nil, nil
	}
	if err != nil {
		return nil, err
	}
	items, err := s.buildFollowUpSummaries(ctx, []models.ServiceFollowUp{row})
	if err != nil || len(items) == 0 {
		return nil, err
	}
	return &items[0], nil
}

func (s *ServiceOperationService) buildFollowUpSummaries(ctx context.Context, rows []models.ServiceFollowUp) ([]ServiceFollowUpSummary, error) {
	items := make([]ServiceFollowUpSummary, 0, len(rows))
	for _, row := range rows {
		var agent models.ServiceAgent
		var user models.User
		if err := s.db.WithContext(ctx).First(&agent, row.AssignedAgentID).Error; err != nil {
			return nil, err
		}
		if err := s.db.WithContext(ctx).First(&user, agent.UserID).Error; err != nil {
			return nil, err
		}
		items = append(items, ServiceFollowUpSummary{
			UUID: row.UUID, Content: row.Content, DueAt: row.DueAt, Status: row.Status,
			AgentID: row.AssignedAgentID, AgentName: user.Nickname, Completed: row.CompletedAt, CreatedAt: row.CreatedAt,
		})
	}
	return items, nil
}

func normalizeQuickReply(input ServiceQuickReplyInput) (string, string, string, string, string, error) {
	category := strings.TrimSpace(input.Category)
	if category == "" {
		category = "通用"
	}
	title := strings.TrimSpace(input.Title)
	content := strings.TrimSpace(input.Content)
	shortcut := strings.TrimSpace(input.Shortcut)
	keywords := strings.TrimSpace(input.Keywords)
	if title == "" || content == "" || len([]rune(category)) > 50 || len([]rune(title)) > 100 || len([]rune(content)) > 2000 || len([]rune(shortcut)) > 30 || len([]rune(keywords)) > 255 {
		return "", "", "", "", "", ErrServiceInvalidTransition
	}
	return category, title, content, shortcut, keywords, nil
}

func normalizeServiceTags(tags []string) ([]string, error) {
	result := make([]string, 0, len(tags))
	seen := map[string]struct{}{}
	for _, raw := range tags {
		tag := strings.TrimSpace(raw)
		if tag == "" {
			continue
		}
		if len([]rune(tag)) > 20 {
			return nil, ErrServiceInvalidTransition
		}
		if _, ok := seen[tag]; ok {
			continue
		}
		seen[tag] = struct{}{}
		result = append(result, tag)
		if len(result) > 10 {
			return nil, ErrServiceInvalidTransition
		}
	}
	return result, nil
}

func buildServiceCustomerSummary(db *gorm.DB, customer models.User) (*ServiceCustomerSummary, error) {
	phone := ""
	if customer.Phone != nil {
		phone = maskServicePhone(*customer.Phone)
	}
	summary := &ServiceCustomerSummary{
		ID: customer.ID, UUID: customer.UUID, Username: customer.Username, Nickname: customer.Nickname,
		Avatar: customer.Avatar, Phone: phone, RegisteredAt: customer.CreatedAt.Format("2006-01-02 15:04"),
		VipLevel: "普通用户", Tags: []string{},
	}
	var profile models.ServiceCustomerProfile
	if err := db.Where("customer_user_id = ?", customer.ID).First(&profile).Error; err == nil {
		_ = json.Unmarshal([]byte(profile.TagsJSON), &summary.Tags)
		if summary.Tags == nil {
			summary.Tags = []string{}
		}
		summary.Note = profile.InternalNote
	} else if !errors.Is(err, gorm.ErrRecordNotFound) {
		return nil, err
	}
	var wallet models.Wallet
	if err := db.Where("user_id = ?", customer.ID).First(&wallet).Error; err == nil {
		summary.Balance = wallet.Balance
	} else if !errors.Is(err, gorm.ErrRecordNotFound) {
		return nil, err
	}
	var membership models.UserVipMembership
	if err := db.Where("user_id = ? AND status = ? AND expired_at > ?", customer.ID, models.VipMembershipStatusActive, time.Now()).First(&membership).Error; err == nil {
		switch membership.Level {
		case models.VipLevelSVIP:
			summary.VipLevel = "SVIP"
		case models.VipLevelVIP:
			summary.VipLevel = "VIP"
		}
	} else if !errors.Is(err, gorm.ErrRecordNotFound) {
		return nil, err
	}
	type orderAggregate struct {
		Count int64
		Total float64
	}
	var aggregate orderAggregate
	if err := db.Model(&models.VipOrder{}).Select("COUNT(*) AS count, COALESCE(SUM(amount), 0) AS total").
		Where("user_id = ? AND status = ?", customer.ID, models.VipOrderStatusPaid).Scan(&aggregate).Error; err != nil {
		return nil, err
	}
	summary.OrderCount = aggregate.Count
	summary.TotalPaid = aggregate.Total
	return summary, nil
}
