package handlers

import (
	"encoding/json"
	"log"
	"strconv"
	"strings"
	"time"

	"gaoranim/internal/cache"
	"gaoranim/internal/models"
	"gaoranim/internal/privacy"
	"gaoranim/internal/services"
	"gaoranim/internal/ws"
	"gaoranim/pkg/response"

	"github.com/gin-gonic/gin"
	"github.com/google/uuid"
	"gorm.io/gorm"
	"gorm.io/gorm/clause"
)

// ContactHandler 鑱旂郴浜哄鐞嗗櫒
type ContactHandler struct {
	db         *gorm.DB
	cache      *cache.Cache
	hub        *ws.Hub
	msgService *services.MessageService
}

// NewContactHandler 鍒涘缓鑱旂郴浜哄鐞嗗櫒
func NewContactHandler(db *gorm.DB, cache *cache.Cache, hub *ws.Hub, msgService *services.MessageService) *ContactHandler {
	return &ContactHandler{db: db, cache: cache, hub: hub, msgService: msgService}
}

// GetContacts 鑾峰彇鑱旂郴浜哄垪琛?
func (h *ContactHandler) GetContacts(c *gin.Context) {
	userID := c.GetString("user_id")
	page, _ := strconv.Atoi(c.DefaultQuery("page", "1"))
	pageSize, _ := strconv.Atoi(c.DefaultQuery("page_size", "100"))
	keyword := strings.TrimSpace(c.Query("keyword"))

	if page < 1 {
		page = 1
	}
	if pageSize < 1 {
		pageSize = 100
	}
	if pageSize > 500 {
		pageSize = 500
	}
	offset := (page - 1) * pageSize

	var currentUser models.User
	if err := h.db.Where("uuid = ?", userID).First(&currentUser).Error; err != nil {
		response.NotFound(c, "用户不存在")
		return
	}

	type contactRow struct {
		ContactUserID uint64    `gorm:"column:contact_user_id"`
		Remark        string    `gorm:"column:remark"`
		UserID        uint64    `gorm:"column:user_id"`
		UUID          string    `gorm:"column:uuid"`
		Nickname      string    `gorm:"column:nickname"`
		Username      string    `gorm:"column:username"`
		Avatar        string    `gorm:"column:avatar"`
		Phone         *string   `gorm:"column:phone"`
		Bio           string    `gorm:"column:bio"`
		LastSeen      time.Time `gorm:"column:last_seen"`
		EmojiAvatar   string    `gorm:"column:emoji_avatar"`
		NicknameColor string    `gorm:"column:nickname_color"`
		PremiumType   string    `gorm:"column:premium_type"`
	}

	baseQuery := h.db.Table("contacts").
		Joins("JOIN users ON users.id = contacts.contact_user_id").
		Where("contacts.user_id = ? AND contacts.status = 1", currentUser.ID)

	if keyword != "" {
		like := "%" + keyword + "%"
		baseQuery = baseQuery.Where(
			h.db.Where("contacts.remark LIKE ?", like).
				Or("users.nickname LIKE ?", like).
				Or("users.username LIKE ?", like).
				Or("users.phone LIKE ?", like),
		)
	}

	var total int64
	if err := baseQuery.Count(&total).Error; err != nil {
		response.ServerError(c, "获取联系人失败")
		return
	}

	var rows []contactRow
	if total > 0 {
		if err := baseQuery.
			Select(`
				contacts.contact_user_id,
				contacts.remark,
				users.id AS user_id,
				users.uuid,
				users.nickname,
				users.username,
				users.avatar,
				users.phone,
				users.bio,
				users.last_seen,
				users.emoji_avatar,
				users.nickname_color,
				users.premium_type
			`).
			Order("CASE WHEN contacts.remark = '' OR contacts.remark IS NULL THEN 1 ELSE 0 END ASC").
			Order("contacts.remark ASC").
			Order("contacts.created_at DESC").
			Offset(offset).
			Limit(pageSize).
			Scan(&rows).Error; err != nil {
			response.ServerError(c, "获取联系人失败")
			return
		}
	}

	contactUserIDs := make([]uint64, 0, len(rows))
	for _, row := range rows {
		contactUserIDs = append(contactUserIDs, row.ContactUserID)
	}

	onlineVisibility := map[uint64]bool{}
	if len(contactUserIDs) > 0 {
		if visibility, err := privacy.BatchCanViewerSeeOnlineStatus(h.db, currentUser.ID, contactUserIDs); err == nil {
			onlineVisibility = visibility
		}
	}

	result := make([]gin.H, 0, len(rows))
	for _, row := range rows {
		name := row.Remark
		if name == "" {
			name = row.Nickname
		}

		isOnline := false
		var lastSeen interface{}
		if onlineVisibility[row.UserID] {
			lastSeen = row.LastSeen
			if h.hub != nil {
				isOnline = h.hub.IsUserOnline(row.UUID)
			} else {
				isOnline = isUserOnline(h.db, row.UserID)
			}
		}

		result = append(result, gin.H{
			"id":             row.UserID,
			"uuid":           row.UUID,
			"name":           name,
			"nickname":       row.Nickname,
			"username":       row.Username,
			"avatar":         row.Avatar,
			"phone":          row.Phone,
			"bio":            row.Bio,
			"remark":         row.Remark,
			"is_online":      isOnline,
			"last_seen":      lastSeen,
			"emoji_avatar":   row.EmojiAvatar,
			"nickname_color": row.NicknameColor,
			"premium_type":   row.PremiumType,
		})
	}

	response.Success(c, gin.H{
		"list":      result,
		"total":     total,
		"page":      page,
		"page_size": pageSize,
	})
}

type AddContactRequest struct {
	UserID string `json:"user_id" binding:"required"`
	Remark string `json:"remark"`
}

func (h *ContactHandler) AddContact(c *gin.Context) {
	userID := c.GetString("user_id")

	var req AddContactRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		response.BadRequest(c, "鍙傛暟閿欒")
		return
	}

	req.Remark = strings.TrimSpace(req.Remark)
	if !validateGeneralRemark(req.Remark, 100) {
		response.BadRequest(c, "remark too long")
		return
	}

	// 鑾峰彇褰撳墠鐢ㄦ埛
	var currentUser models.User
	if err := h.db.Where("uuid = ?", userID).First(&currentUser).Error; err != nil {
		response.NotFound(c, "user not found")
		return
	}

	var targetUser models.User
	if err := h.db.Where("uuid = ?", req.UserID).First(&targetUser).Error; err != nil {
		if _, parseErr := strconv.ParseUint(req.UserID, 10, 64); parseErr == nil {
			if err2 := h.db.Where("id = ?", req.UserID).First(&targetUser).Error; err2 != nil {
				response.NotFound(c, "user not found")
				return
			}
		} else {
			response.NotFound(c, "user not found")
			return
		}
	}

	// 涓嶈兘娣诲姞鑷繁
	if currentUser.ID == targetUser.ID {
		response.BadRequest(c, "涓嶈兘娣诲姞鑷繁涓鸿仈绯讳汉")
		return
	}

	var exists int64
	h.db.Model(&models.Contact{}).
		Where("user_id = ? AND contact_user_id = ? AND status = 1", currentUser.ID, targetUser.ID).
		Count(&exists)

	if exists > 0 {
		response.BadRequest(c, "宸茬粡鏄仈绯讳汉")
		return
	}

	now := time.Now()

	contact := models.Contact{
		UserID:        currentUser.ID,
		ContactUserID: targetUser.ID,
		Remark:        req.Remark,
		Status:        1,
		CreatedAt:     now,
		UpdatedAt:     now,
	}
	if err := h.db.Create(&contact).Error; err != nil {
		response.ServerError(c, "failed to add contact")
		return
	}

	if err := h.sendContactAddedSystemMessage(c, &currentUser, &targetUser); err != nil {
		// 鑱旂郴浜烘坊鍔犱互鎴愬姛涓轰富锛岀郴缁熸彁绀哄け璐ヤ粎璁板綍鏃ュ織锛岄伩鍏嶅奖鍝嶄富娴佺▼
		log.Printf("[Contact] sendContactAddedSystemMessage failed: %v", err)
	}

	response.Success(c, gin.H{
		"id":       targetUser.UUID,
		"name":     req.Remark,
		"nickname": targetUser.Nickname,
		"username": targetUser.Username,
		"avatar":   targetUser.Avatar,
	})
}

func (h *ContactHandler) sendContactAddedSystemMessage(c *gin.Context, adder, targetUser *models.User) error {
	if h.msgService == nil {
		return nil
	}

	now := time.Now()
	chat, err := h.getOrCreatePrivateChat(adder, targetUser, now)
	if err != nil {
		return err
	}

	systemPayload := map[string]interface{}{
		"type":        "contact_added_system_message",
		"adder_id":    adder.UUID,
		"adder_name":  displayUserName(adder),
		"target_id":   targetUser.UUID,
		"target_name": displayUserName(targetUser),
	}

	payloadText, err := json.Marshal(systemPayload)
	if err != nil {
		return err
	}

	msg, err := h.msgService.SendMessage(
		c.Request.Context(),
		&services.SendMessageParams{
			ChatID:   chat.UUID,
			SenderID: "system",
			Type:     models.MsgTypeSystem,
			Content: map[string]interface{}{
				"text": string(payloadText),
			},
		},
		"绯荤粺娑堟伅",
		"",
		"",
		"",
		"",
		[]string{adder.UUID, targetUser.UUID},
	)
	if err != nil {
		return err
	}

	h.db.Model(&models.UserChat{}).
		Where("chat_id = ? AND user_id = ?", chat.ID, adder.ID).
		Updates(map[string]interface{}{
			"last_msg_text":   string(payloadText),
			"last_msg_type":   models.MsgTypeSystem,
			"last_msg_time":   msg.CreatedAt,
			"last_msg_seq":    msg.Seq,
			"last_msg_sender": "",
			"sort_time":       msg.CreatedAt,
			"is_archived":     false,
		})

	h.db.Model(&models.UserChat{}).
		Where("chat_id = ? AND user_id = ?", chat.ID, targetUser.ID).
		Updates(map[string]interface{}{
			"last_msg_text":   string(payloadText),
			"last_msg_type":   models.MsgTypeSystem,
			"last_msg_time":   msg.CreatedAt,
			"last_msg_seq":    msg.Seq,
			"last_msg_sender": "",
			"sort_time":       msg.CreatedAt,
			"is_archived":     false,
		})
	h.db.Model(&models.UserChat{}).
		Where("chat_id = ? AND user_id = ?", chat.ID, targetUser.ID).
		UpdateColumn("unread_count", gorm.Expr("unread_count + 1"))

	return nil
}

func (h *ContactHandler) getOrCreatePrivateChat(currentUser, targetUser *models.User, now time.Time) (*models.Chat, error) {
	var existingChat models.Chat
	err := h.db.Raw(`
		SELECT c.* FROM chats c
		JOIN chat_members cm1 ON c.id = cm1.chat_id AND cm1.user_id = ?
		JOIN chat_members cm2 ON c.id = cm2.chat_id AND cm2.user_id = ?
		WHERE c.type = 1
		LIMIT 1
	`, currentUser.ID, targetUser.ID).Scan(&existingChat).Error
	if err == nil && existingChat.ID > 0 {
		if err := h.ensurePrivateUserChatRecord(existingChat.ID, currentUser.ID, targetUser.ID, now); err != nil {
			return nil, err
		}
		if err := h.ensurePrivateUserChatRecord(existingChat.ID, targetUser.ID, currentUser.ID, now); err != nil {
			return nil, err
		}
		return &existingChat, nil
	}

	chat := models.Chat{
		UUID:        uuid.New().String(),
		Type:        1,
		MemberCount: 2,
		InviteLink:  uuid.New().String()[:8],
		CreatedAt:   now,
		UpdatedAt:   now,
	}

	tx := h.db.Begin()
	if tx.Error != nil {
		return nil, tx.Error
	}
	defer func() {
		if r := recover(); r != nil {
			tx.Rollback()
			panic(r)
		}
	}()

	if err := tx.Create(&chat).Error; err != nil {
		tx.Rollback()
		return nil, err
	}

	members := []models.ChatMember{
		{ChatID: chat.ID, UserID: currentUser.ID, Role: 0, JoinedAt: now, UpdatedAt: now},
		{ChatID: chat.ID, UserID: targetUser.ID, Role: 0, JoinedAt: now, UpdatedAt: now},
	}
	if err := tx.Create(&members).Error; err != nil {
		tx.Rollback()
		return nil, err
	}

	userChats := []models.UserChat{
		{
			UserID:    currentUser.ID,
			ChatID:    chat.ID,
			TargetID:  targetUser.ID,
			SortTime:  now,
			UpdatedAt: now,
		},
		{
			UserID:    targetUser.ID,
			ChatID:    chat.ID,
			TargetID:  currentUser.ID,
			SortTime:  now,
			UpdatedAt: now,
		},
	}
	if err := tx.Create(&userChats).Error; err != nil {
		tx.Rollback()
		return nil, err
	}

	if err := tx.Commit().Error; err != nil {
		return nil, err
	}

	return &chat, nil
}

func (h *ContactHandler) ensurePrivateUserChatRecord(chatID, userID, targetID uint64, sortTime time.Time) error {
	effectiveTime := sortTime
	if effectiveTime.IsZero() {
		effectiveTime = time.Now()
	}

	return h.db.Table("user_chats").Clauses(clause.OnConflict{
		Columns: []clause.Column{
			{Name: "user_id"},
			{Name: "chat_id"},
		},
		DoUpdates: clause.Assignments(map[string]interface{}{
			"target_id":   targetID,
			"updated_at":  effectiveTime,
			"sort_time":   effectiveTime,
			"is_archived": false,
		}),
	}).Create(map[string]interface{}{
		"user_id":     userID,
		"chat_id":     chatID,
		"target_id":   targetID,
		"is_archived": false,
		"sort_time":   effectiveTime,
		"updated_at":  effectiveTime,
	}).Error
}

func displayUserName(user *models.User) string {
	if user == nil {
		return "鐢ㄦ埛"
	}
	if user.Nickname != "" {
		return user.Nickname
	}
	if user.Username != "" {
		return user.Username
	}
	return "鐢ㄦ埛"
}

func (h *ContactHandler) DeleteContact(c *gin.Context) {
	userID := c.GetString("user_id")
	contactID := c.Param("id")

	// 鑾峰彇褰撳墠鐢ㄦ埛
	var currentUser models.User
	if err := h.db.Where("uuid = ?", userID).First(&currentUser).Error; err != nil {
		response.NotFound(c, "user not found")
		return
	}

	var targetUser models.User
	if err := h.db.Where("uuid = ?", contactID).First(&targetUser).Error; err != nil {
		response.NotFound(c, "鑱旂郴浜轰笉瀛樺湪")
		return
	}

	// 鍒犻櫎鑱旂郴浜猴紙浠呭垹闄ゅ綋鍓嶇敤鎴疯嚜宸辩殑鑱旂郴浜鸿褰曪級
	h.db.Where("user_id = ? AND contact_user_id = ?", currentUser.ID, targetUser.ID).
		Delete(&models.Contact{})

	response.Success(c, nil)
}

// UpdateRemarkRequest 鏇存柊澶囨敞璇锋眰
type UpdateRemarkRequest struct {
	Remark string `json:"remark"`
}

func (h *ContactHandler) UpdateRemark(c *gin.Context) {
	userID := c.GetString("user_id")
	contactID := c.Param("id")

	var req UpdateRemarkRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		response.BadRequest(c, "鍙傛暟閿欒")
		return
	}
	req.Remark = strings.TrimSpace(req.Remark)
	if !validateGeneralRemark(req.Remark, 100) {
		response.BadRequest(c, "remark too long")
		return
	}

	// 鑾峰彇褰撳墠鐢ㄦ埛
	var currentUser models.User
	if err := h.db.Where("uuid = ?", userID).First(&currentUser).Error; err != nil {
		response.NotFound(c, "user not found")
		return
	}

	var targetUser models.User
	if err := h.db.Where("uuid = ?", contactID).First(&targetUser).Error; err != nil {
		response.NotFound(c, "鑱旂郴浜轰笉瀛樺湪")
		return
	}

	var contact models.Contact
	if err := h.db.Where("user_id = ? AND contact_user_id = ? AND status = 1", currentUser.ID, targetUser.ID).
		First(&contact).Error; err != nil {
		response.NotFound(c, "鑱旂郴浜轰笉瀛樺湪")
		return
	}

	// 鏇存柊澶囨敞
	if err := h.db.Model(&contact).
		Updates(map[string]interface{}{
			"remark":     req.Remark,
			"updated_at": time.Now(),
		}).Error; err != nil {
		response.ServerError(c, "鏇存柊澶囨敞澶辫触")
		return
	}

	response.Success(c, nil)
}

func isUserOnline(db *gorm.DB, userID uint64) bool {
	var device models.UserDevice
	// 5鍒嗛挓鍐呮湁娲诲姩瑙嗕负鍦ㄧ嚎
	err := db.Where("user_id = ? AND last_active > ?", userID, time.Now().Add(-5*time.Minute)).
		First(&device).Error
	return err == nil
}
