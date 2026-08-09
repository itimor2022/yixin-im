// 文件用途：实现后端 HTTP 接口的请求处理和统一响应。
// 核心逻辑：绑定参数，校验身份与权限，调用业务服务并持久化关键状态。

package handlers

import (
	"encoding/json"
	"github.com/gin-gonic/gin"
	"github.com/google/uuid"
	"gorm.io/gorm"
	"gorm.io/gorm/clause" // ContactHandler 联系人处理器
	"log"
	"strconv"
	"strings"
	"time"
	"genericim/internal/cache"
	"genericim/internal/models"
	"genericim/internal/privacy"
	"genericim/internal/services"
	"genericim/internal/ws"
	"genericim/pkg/response"
)

type ContactHandler struct {
	db         *gorm.DB
	cache      *cache.Cache
	hub        *ws.Hub
	msgService *services.MessageService
} // NewContactHandler 创建联系人处理器
func NewContactHandler(db *gorm.DB, cache *cache.Cache, hub *ws.Hub, msgService *services.MessageService) *ContactHandler {
	return &ContactHandler{db: db, cache: cache, hub: hub, msgService: msgService}
} // GetContacts 获取联系人列表
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
		ContactUserID uint64 `gorm:"column:contact_user_id"`

		Remark string `gorm:"column:remark"`

		UserID uint64 `gorm:"column:user_id"`

		UUID string `gorm:"column:uuid"`

		Nickname string `gorm:"column:nickname"`

		Username string `gorm:"column:username"`

		Avatar string `gorm:"column:avatar"`

		Phone *string `gorm:"column:phone"`

		Bio string `gorm:"column:bio"`

		LastSeen time.Time `gorm:"column:last_seen"`

		EmojiAvatar string `gorm:"column:emoji_avatar"`

		NicknameColor string `gorm:"column:nickname_color"`
	}
	// Contact 是“当前用户 -> 联系人”的单向关系；列表查询必须固定以 currentUser.ID 为关系起点。
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



users.nickname_color 


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
	// 在线状态先经过隐私规则授权；即使 Hub 知道用户在线，也不能绕过该结果直接下发。
	onlineVisibility := map[uint64]bool{}
	if len(contactUserIDs) > 0 {

		if visibility, err := privacy.BatchCanViewerSeeOnlineStatus(h.db, currentUser.ID, contactUserIDs); err == nil {

			onlineVisibility = visibility

		}
	}
	vipSummaries := buildUserVipSummaries(h.db, contactUserIDs)
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

			"id": row.UserID,

			"uuid": row.UUID,

			"name": name,

			"nickname": row.Nickname,

			"username": row.Username,

			"avatar": row.Avatar,

			"phone": row.Phone,

			"bio": row.Bio,

			"remark": row.Remark,

			"is_online": isOnline,

			"last_seen": lastSeen,

			"emoji_avatar": row.EmojiAvatar,

			"nickname_color": row.NicknameColor,

			"vip": vipSummaries[row.UserID],
		})
	}
	response.Success(c, gin.H{

		"list": result,

		"total": total,

		"page": page,

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

		response.BadRequest(c, "参数错误")

		return
	}
	req.Remark = strings.TrimSpace(req.Remark)
	if !validateGeneralRemark(req.Remark, 100) {

		response.BadRequest(c, "备注长度不能超过 100 个字符")

		return
	}
	// 获取当前用户
	var currentUser models.User
	if err := h.db.Where("uuid = ?", userID).First(&currentUser).Error; err != nil {

		response.NotFound(c, "用户不存在")

		return
	}
	var targetUser models.User
	if err := h.db.Where("uuid = ?", req.UserID).First(&targetUser).Error; err != nil {

		if _, parseErr := strconv.ParseUint(req.UserID, 10, 64); parseErr == nil {

			if err2 := h.db.Where("id = ?", req.UserID).First(&targetUser).Error; err2 != nil {

				response.NotFound(c, "用户不存在")

				return

			}

		} else {

			response.NotFound(c, "用户不存在")

			return

		}
	}
	// 不能添加自己
	if currentUser.ID == targetUser.ID {

		response.BadRequest(c, "不能将自己添加为联系人")

		return
	}
	switch loadFriendAddMode(h.db) {
	case models.FriendAddModeDisabled:

		response.Forbidden(c, "管理员已关闭添加好友功能")

		return
	case models.FriendAddModeApproval:

		response.BadRequest(c, "当前需要好友验证，请发送好友申请")

		return
	}
	var exists int64
	h.db.Model(&models.Contact{}).
		Where("user_id = ? AND contact_user_id = ? AND status = 1", currentUser.ID, targetUser.ID).
		Count(&exists)
	if exists > 0 {

		response.BadRequest(c, "已经是联系人")

		return
	}
	now := time.Now()
	if err := h.db.Transaction(func(tx *gorm.DB) error {

		// 添加好友要原子创建两条单向 Contact；备注只属于发起方自己的那一条记录。

		if err := lockFriendRequestUsers(tx, currentUser.ID, targetUser.ID); err != nil {

			return err

		}

		if err := ensureMutualContacts(tx, currentUser.ID, targetUser.ID, now); err != nil {

			return err

		}

		if req.Remark != "" {

			return tx.Model(&models.Contact{}).
				Where("user_id = ? AND contact_user_id = ?", currentUser.ID, targetUser.ID).
				Updates(map[string]interface{}{

					"remark": req.Remark,

					"status": 1,

					"updated_at": now,
				}).Error

		}

		return nil
	}); err != nil {

		response.ServerError(c, "添加联系人失败")

		return
	}
	if err := h.sendContactAddedSystemMessage(c, &currentUser, &targetUser); err != nil {

		// 联系人添加以主流程成功为准，系统消息发送失败仅记录日志，避免影响主流程

		log.Printf("[Contact] sendContactAddedSystemMessage failed: %v", err)
	}
	response.Success(c, gin.H{

		"id": targetUser.UUID,

		"name": req.Remark,

		"nickname": targetUser.Nickname,

		"username": targetUser.Username,

		"avatar": targetUser.Avatar,
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

		"type": "contact_added_system_message",

		"adder_id": adder.UUID,

		"adder_name": displayUserName(adder),

		"target_id": targetUser.UUID,

		"target_name": displayUserName(targetUser),
	}
	payloadText, err := json.Marshal(systemPayload)
	if err != nil {

		return err
	}
	msg, err := h.msgService.SendMessage(

		c.Request.Context(),

		&services.SendMessageParams{

			ChatID: chat.UUID,

			SenderID: "system",

			Type: models.MsgTypeSystem,

			Content: map[string]interface{}{

				"text": string(payloadText),
			},
		},

		"系统消息",

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

			"last_msg_text": string(payloadText),

			"last_msg_type": models.MsgTypeSystem,

			"last_msg_time": msg.CreatedAt,

			"last_msg_seq": msg.Seq,

			"last_msg_sender": "",

			"last_msg_media_url": "",

			"sort_time": msg.CreatedAt,

			"is_archived": false,
		})
	h.db.Model(&models.UserChat{}).
		Where("chat_id = ? AND user_id = ?", chat.ID, targetUser.ID).
		Updates(map[string]interface{}{

			"last_msg_text": string(payloadText),

			"last_msg_type": models.MsgTypeSystem,

			"last_msg_time": msg.CreatedAt,

			"last_msg_seq": msg.Seq,

			"last_msg_sender": "",

			"last_msg_media_url": "",

			"sort_time": msg.CreatedAt,

			"is_archived": false,
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

		UUID: uuid.New().String(),

		Type: 1,

		MemberCount: 2,

		InviteLink: uuid.New().String()[:8],

		CreatedAt: now,

		UpdatedAt: now,
	}
	// 新私聊的会话、双方成员和双方 UserChat 投影必须一起落库，避免出现能收消息却看不到会话的半成品状态。
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

			UserID: currentUser.ID,

			ChatID: chat.ID,

			TargetID: targetUser.ID,

			SortTime: now,

			UpdatedAt: now,
		},

		{

			UserID: targetUser.ID,

			ChatID: chat.ID,

			TargetID: currentUser.ID,

			SortTime: now,

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

			"target_id": targetID,

			"updated_at": effectiveTime,

			"sort_time": effectiveTime,

			"is_archived": false,
		}),
	}).Create(map[string]interface{}{

		"user_id": userID,

		"chat_id": chatID,

		"target_id": targetID,

		"is_archived": false,

		"sort_time": effectiveTime,

		"updated_at": effectiveTime,
	}).Error
}
func displayUserName(user *models.User) string {
	if user == nil {

		return "用户"
	}
	if user.Nickname != "" {

		return user.Nickname
	}
	if user.Username != "" {

		return user.Username
	}
	return "用户"
}
func (h *ContactHandler) DeleteContact(c *gin.Context) {
	userID := c.GetString("user_id")
	contactID := c.Param("id")
	// 获取当前用户
	var currentUser models.User
	if err := h.db.Where("uuid = ?", userID).First(&currentUser).Error; err != nil {

		response.NotFound(c, "用户不存在")

		return
	}
	var targetUser models.User
	if err := h.db.Where("uuid = ?", contactID).First(&targetUser).Error; err != nil {

		response.NotFound(c, "联系人不存在")

		return
	}
	// 删除只影响当前用户这一侧；对方的反向联系人记录和历史私聊都继续保留。
	h.db.Where("user_id = ? AND contact_user_id = ?", currentUser.ID, targetUser.ID).
		Delete(&models.Contact{})
	response.Success(c, nil)
} // UpdateRemarkRequest 更新备注请求
type UpdateRemarkRequest struct {
	Remark string `json:"remark"`
}

func (h *ContactHandler) UpdateRemark(c *gin.Context) {
	userID := c.GetString("user_id")
	contactID := c.Param("id")
	var req UpdateRemarkRequest
	if err := c.ShouldBindJSON(&req); err != nil {

		response.BadRequest(c, "参数错误")

		return
	}
	req.Remark = strings.TrimSpace(req.Remark)
	if !validateGeneralRemark(req.Remark, 100) {

		response.BadRequest(c, "备注长度不能超过 100 个字符")

		return
	}
	// 获取当前用户
	var currentUser models.User
	if err := h.db.Where("uuid = ?", userID).First(&currentUser).Error; err != nil {

		response.NotFound(c, "用户不存在")

		return
	}
	var targetUser models.User
	if err := h.db.Where("uuid = ?", contactID).First(&targetUser).Error; err != nil {

		response.NotFound(c, "联系人不存在")

		return
	}
	var contact models.Contact
	if err := h.db.Where("user_id = ? AND contact_user_id = ? AND status = 1", currentUser.ID, targetUser.ID).
		First(&contact).Error; err != nil {

		response.NotFound(c, "联系人不存在")

		return
	}
	// 更新备注
	if err := h.db.Model(&contact).
		Updates(map[string]interface{}{

			"remark": req.Remark,

			"updated_at": time.Now(),
		}).Error; err != nil {

		response.ServerError(c, "更新备注失败")

		return
	}
	response.Success(c, nil)
}
func isUserOnline(db *gorm.DB, userID uint64) bool {
	var device models.UserDevice
	// 5分钟内有活动视为在线
	err := db.Where("user_id = ? AND last_active > ?", userID, time.Now().Add(-5*time.Minute)).
		First(&device).Error
	return err == nil
}
