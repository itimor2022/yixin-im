// 文件用途：实现后端 HTTP 接口的请求处理和统一响应。
// 核心逻辑：绑定参数，校验身份与权限，调用业务服务并持久化关键状态。

package handlers

import (
	"context"
	"encoding/base64"
	"encoding/json"
	"errors"
	"fmt"
	"github.com/gin-gonic/gin"
	"github.com/google/uuid"
	"gorm.io/gorm"
	"gorm.io/gorm/clause" // ChatHandler 聊天处理器
	"log"
	"net/http"
	"net/url"
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

type ChatHandler struct {
	db         *gorm.DB
	cache      *cache.Cache
	hub        *ws.Hub
	msgService *services.MessageService
	permSvc    *services.ChatPermissionService
	memberSvc  *services.ChatMemberService
	joinSvc    *services.JoinRequestService
	vipSvc     *services.VipService
}

// NewChatHandler 创建聊天处理器
func NewChatHandler(db *gorm.DB, cache *cache.Cache, hub *ws.Hub, msgService *services.MessageService) *ChatHandler {
	return &ChatHandler{

		db: db,

		cache: cache,

		hub: hub,

		msgService: msgService,

		permSvc: services.NewChatPermissionService(db),

		memberSvc: services.NewChatMemberService(db),

		joinSvc: services.NewJoinRequestService(db),

		vipSvc: services.NewVipService(db),
	}
}

type chatAdminPermissionPayload struct {
	CanChangeInfo         *bool `json:"can_change_info"`
	CanDeleteMessages     *bool `json:"can_delete_messages"`
	CanBanUsers           *bool `json:"can_ban_users"`
	CanMuteUsers          *bool `json:"can_mute_users"`
	CanInviteUsers        *bool `json:"can_invite_users"`
	CanManageJoinRequests *bool `json:"can_manage_join_requests"`
	CanPinMessages        *bool `json:"can_pin_messages"`
	CanPostMessages       *bool `json:"can_post_messages"`
	CanEditMessages       *bool `json:"can_edit_messages"`
	CanManageAdmins       *bool `json:"can_manage_admins"`
	CanManageInviteLinks  *bool `json:"can_manage_invite_links"`
	CanViewStats          *bool `json:"can_view_stats"`
}

func defaultAdminPermissions(chatType int8) models.ChatAdminPermission {
	return services.DefaultChatAdminPermissions(chatType)
}
func ownerAdminPermissions() models.ChatAdminPermission {
	return services.OwnerChatAdminPermissions()
}
func applyAdminPermissionPayload(base models.ChatAdminPermission, payload *chatAdminPermissionPayload) models.ChatAdminPermission {
	if payload == nil {

		return base
	}
	if payload.CanChangeInfo != nil {

		base.CanChangeInfo = *payload.CanChangeInfo
	}
	if payload.CanDeleteMessages != nil {

		base.CanDeleteMessages = *payload.CanDeleteMessages
	}
	if payload.CanBanUsers != nil {

		base.CanBanUsers = *payload.CanBanUsers
	}
	if payload.CanMuteUsers != nil {

		base.CanMuteUsers = *payload.CanMuteUsers
	}
	if payload.CanInviteUsers != nil {

		base.CanInviteUsers = *payload.CanInviteUsers
	}
	if payload.CanManageJoinRequests != nil {

		base.CanManageJoinRequests = *payload.CanManageJoinRequests
	}
	if payload.CanPinMessages != nil {

		base.CanPinMessages = *payload.CanPinMessages
	}
	if payload.CanPostMessages != nil {

		base.CanPostMessages = *payload.CanPostMessages
	}
	if payload.CanEditMessages != nil {

		base.CanEditMessages = *payload.CanEditMessages
	}
	if payload.CanManageAdmins != nil {

		base.CanManageAdmins = *payload.CanManageAdmins
	}
	if payload.CanManageInviteLinks != nil {

		base.CanManageInviteLinks = *payload.CanManageInviteLinks
	}
	if payload.CanViewStats != nil {

		base.CanViewStats = *payload.CanViewStats
	}
	return base
}
func adminPermissionMap(perm models.ChatAdminPermission) gin.H {
	return gin.H{

		"can_change_info": perm.CanChangeInfo,

		"can_delete_messages": perm.CanDeleteMessages,

		"can_ban_users": perm.CanBanUsers,

		"can_mute_users": perm.CanMuteUsers,

		"can_invite_users": perm.CanInviteUsers,

		"can_manage_join_requests": perm.CanManageJoinRequests,

		"can_pin_messages": perm.CanPinMessages,

		"can_post_messages": perm.CanPostMessages,

		"can_edit_messages": perm.CanEditMessages,

		"can_manage_admins": perm.CanManageAdmins,

		"can_manage_invite_links": perm.CanManageInviteLinks,

		"can_view_stats": perm.CanViewStats,
	}
}
func (h *ChatHandler) getEffectiveAdminPermissions(chat models.Chat, member models.ChatMember) models.ChatAdminPermission {
	perm, err := h.chatPermissionService().EffectiveAdminPermissions(context.Background(), chat, member)
	if err != nil {

		return models.ChatAdminPermission{}
	}
	return perm
}
func (h *ChatHandler) ensureAdminPermissions(tx *gorm.DB, chat models.Chat, userID uint64, payload *chatAdminPermissionPayload) error {
	now := time.Now()
	base := defaultAdminPermissions(chat.Type)
	var existing models.ChatAdminPermission
	err := tx.Where("chat_id = ? AND user_id = ?", chat.ID, userID).First(&existing).Error
	if err == nil {
		updates := applyAdminPermissionPayload(existing, payload)

		return tx.Model(&existing).Updates(map[string]interface{}{

			"can_change_info": updates.CanChangeInfo,

			"can_delete_messages": updates.CanDeleteMessages,

			"can_ban_users": updates.CanBanUsers,

			"can_mute_users": updates.CanMuteUsers,

			"can_invite_users": updates.CanInviteUsers,

			"can_manage_join_requests": updates.CanManageJoinRequests,

			"can_pin_messages": updates.CanPinMessages,

			"can_post_messages": updates.CanPostMessages,

			"can_edit_messages": updates.CanEditMessages,

			"can_manage_admins": updates.CanManageAdmins,

			"can_manage_invite_links": updates.CanManageInviteLinks,

			"can_view_stats": updates.CanViewStats,

			"updated_at": now,
		}).Error
	}
	if err != nil && err != gorm.ErrRecordNotFound {

		return err
	}
	created := applyAdminPermissionPayload(base, payload)
	created.ChatID = chat.ID
	created.UserID = userID
	created.CreatedAt = now
	created.UpdatedAt = now
	return tx.Create(&created).Error
}
func (h *ChatHandler) hasAdminPermission(chat models.Chat, member models.ChatMember, permission string) bool {
	return h.chatPermissionService().HasAdminPermission(context.Background(), chat, member, permission)
}
func (h *ChatHandler) chatPermissionService() *services.ChatPermissionService {
	if h.permSvc != nil {

		return h.permSvc
	}
	return services.NewChatPermissionService(h.db)
}
func (h *ChatHandler) chatMemberService() *services.ChatMemberService {
	if h.memberSvc != nil {

		return h.memberSvc
	}
	return services.NewChatMemberService(h.db)
}
func (h *ChatHandler) joinRequestService() *services.JoinRequestService {
	if h.joinSvc != nil {

		return h.joinSvc
	}
	return services.NewJoinRequestService(h.db)
}
func (h *ChatHandler) vipService() *services.VipService {
	if h.vipSvc != nil {

		return h.vipSvc
	}
	return services.NewVipService(h.db)
}
func (h *ChatHandler) validateVipChatSettings(userID uint64, chat models.Chat, req UpdateChatRequest) (string, error) {
	needsPublicAbility := false
	if req.IsPublic != nil && *req.IsPublic && !chat.IsPublic {

		needsPublicAbility = true
	}
	if req.Username != nil {
		nextUsername := strings.TrimSpace(*req.Username)

		if nextUsername != "" && nextUsername != strings.TrimSpace(chat.Username) {

			needsPublicAbility = true

		}
	}
	needsMemberProtection := req.MemberProtection != nil && *req.MemberProtection && !chat.MemberProtection
	if !needsPublicAbility && !needsMemberProtection {

		return "", nil
	}
	status, err := h.vipService().GetStatus(userID)
	if err != nil {

		return "", err
	}
	entitlements := status.Entitlements
	if needsPublicAbility && !entitlements.CanSetPublicUsername {

		return "开通 SVIP 后可设置公开群号和公开频道", nil
	}
	if needsMemberProtection && !entitlements.CanEnableMemberProtect {

		return "开通 SVIP 后可开启群成员保护", nil
	}
	return "", nil
}
func (h *ChatHandler) isGroupInviteRequireFriendEnabled() bool {
	var setting models.SystemSetting
	if err := h.db.Where("`key` = ?", models.SettingGroupInviteRequireFriend).First(&setting).Error; err != nil {

		return false
	}
	return isSystemSettingTrue(setting.Value)
}
func (h *ChatHandler) resolveUsersByIdentifiers(identifiers []string) ([]models.User, error) {
	uuidInputs := make([]string, 0, len(identifiers))
	numericIDs := make([]uint64, 0, len(identifiers))
	for _, raw := range identifiers {
		value := strings.TrimSpace(raw)

		if value == "" {

			continue

		}

		if numericID, err := strconv.ParseUint(value, 10, 64); err == nil && numericID > 0 {

			numericIDs = append(numericIDs, numericID)

			continue

		}
		uuidInputs = append(uuidInputs, value)
	}
	if len(uuidInputs) == 0 && len(numericIDs) == 0 {

		return []models.User{}, nil
	}
	query := h.db.Model(&models.User{})
	if len(uuidInputs) > 0 {

		query = query.Where("uuid IN ?", uuidInputs)
	}
	if len(numericIDs) > 0 {

		if len(uuidInputs) > 0 {

			query = query.Or("id IN ?", numericIDs)

		} else {

			query = query.Where("id IN ?", numericIDs)

		}
	}
	var users []models.User
	if err := query.Find(&users).Error; err != nil {

		return nil, err
	}
	return users, nil
}

// getMaxMembers 获取群组/频道的全局成员上限 // chatType: 2=群组, 3=频道 // 返回0表示无限制
func (h *ChatHandler) getMaxMembers(chatType int8) int {
	var settingKey string
	var defaultValue int
	if chatType == 2 {

		settingKey = models.SettingGroupMaxMembers

		defaultValue = 200000
	} else if chatType == 3 {

		settingKey = models.SettingChannelMaxMembers

		defaultValue = 0
	} else {

		return 0
	}
	var setting models.SystemSetting
	if err := h.db.Where("`key` = ?", settingKey).First(&setting).Error; err != nil {

		return defaultValue
	}
	maxMembers, err := strconv.Atoi(setting.Value)
	if err != nil {

		return defaultValue
	}
	return maxMembers
}

// getEffectiveMaxMembers 获取单个群组/频道的有效成员上限 // 优先使用群自身的 MaxMembers，为 0 时 fallback 到全局设置
func (h *ChatHandler) getEffectiveMaxMembers(chat *models.Chat) int {
	if chat.MaxMembers > 0 {

		return chat.MaxMembers
	}
	return h.getMaxMembers(chat.Type)
}
func (h *ChatHandler) resolveCreateMaxMembers(req CreateChatRequest, entitlementMax int) int {
	maxMembers := req.MaxMembers
	if maxMembers <= 0 {

		maxMembers = h.getMaxMembers(req.Type)
	}
	if entitlementMax > 0 && (maxMembers <= 0 || maxMembers > entitlementMax) {

		maxMembers = entitlementMax
	}
	return maxMembers
}
func (h *ChatHandler) ensureUserChatRecord(tx *gorm.DB, userID uint64, chatID uint64, sortTime time.Time) error {
	// UserChat 是每个用户自己的会话列表投影；成员身份与角色仍以 ChatMember 为准。
	effectiveTime := nowOr(sortTime)
	return tx.Table("user_chats").Clauses(clause.OnConflict{

		Columns: []clause.Column{

			{Name: "user_id"},

			{Name: "chat_id"},
		},

		DoUpdates: clause.Assignments(map[string]interface{}{

			"updated_at": effectiveTime,

			"sort_time": effectiveTime,

			"is_archived": false,
		}),
	}).Create(map[string]interface{}{

		"user_id": userID,

		"chat_id": chatID,

		"target_id": 0,

		"is_archived": false,

		"sort_time": effectiveTime,

		"updated_at": effectiveTime,
	}).Error
}
func nowOr(t time.Time) time.Time {
	if t.IsZero() {

		return time.Now()
	}
	return t
}
func optionalTimeValue(t *time.Time) interface{} {
	if t == nil || t.IsZero() {

		return nil
	}
	return *t
}

type chatListCursor struct {
	// 游标必须携带完整排序元组；只记录时间会在置顶状态或同一时间戳下漏项、重项。
	Pinned   bool   `json:"p"`
	SortTime string `json:"t"`
	ID       uint64 `json:"i"`
}

func encodeChatListCursor(userChat models.UserChat) string {
	sortTime := ""
	if !userChat.SortTime.IsZero() {

		sortTime = userChat.SortTime.UTC().Format(time.RFC3339Nano)
	}
	data, err := json.Marshal(chatListCursor{

		Pinned: userChat.IsPinned,

		SortTime: sortTime,

		ID: userChat.ID,
	})
	if err != nil {

		return ""
	}
	return base64.RawURLEncoding.EncodeToString(data)
}
func decodeChatListCursor(raw string) (chatListCursor, time.Time, error) {
	var cursor chatListCursor
	data, err := base64.RawURLEncoding.DecodeString(strings.TrimSpace(raw))
	if err != nil {

		return cursor, time.Time{}, err
	}
	if err := json.Unmarshal(data, &cursor); err != nil {

		return cursor, time.Time{}, err
	}
	var sortTime time.Time
	if cursor.SortTime != "" {

		sortTime, err = time.Parse(time.RFC3339Nano, cursor.SortTime)

		if err != nil {

			return cursor, time.Time{}, err

		}
	}
	return cursor, sortTime, nil
}

// GetChatList 获取会话列表
func (h *ChatHandler) GetChatList(c *gin.Context) {
	userID := c.GetString("user_id")
	page, _ := strconv.Atoi(c.DefaultQuery("page", "1"))
	pageSize, _ := strconv.Atoi(c.DefaultQuery("page_size", "20"))
	cursorToken := strings.TrimSpace(c.Query("cursor"))
	if page < 1 {

		page = 1
	}
	if pageSize <= 0 {

		pageSize = 20
	}
	if pageSize > 100 {

		pageSize = 100
	}
	offset := 0
	if cursorToken == "" {

		offset = (page - 1) * pageSize
	}
	var decodedCursor chatListCursor
	var cursorSortTime time.Time
	if cursorToken != "" {
		var err error

		decodedCursor, cursorSortTime, err = decodeChatListCursor(cursorToken)

		if err != nil || decodedCursor.ID == 0 {

			response.BadRequest(c, "无效游标")

			return

		}
	}
	// 获取当前用户
	var currentUser models.User
	if err := h.db.Where("uuid = ?", userID).First(&currentUser).Error; err != nil {

		response.NotFound(c, "用户不存在")

		return
	}
	// 获取用户的会话列表（使用 UserChat 表）
	// 热缓存只服务传统页码请求；游标请求依赖上一页边界，不能复用按 page 生成的缓存结果。
	useHotCache := cursorToken == ""
	cacheVersion := chatListHotCacheVersion(c.Request.Context(), h.cache, currentUser.ID)
	cacheKey := chatListHotCacheKey(currentUser.ID, cacheVersion, page, pageSize)
	if useHotCache && h.cache != nil {
		var cached map[string]interface{}

		if err := h.cache.Get(c.Request.Context(), cacheKey, &cached); err == nil && cached != nil {

			response.Success(c, cached)

			return

		}
	}
	var userChats []models.UserChat
	query := h.db.Where("user_id = ?", currentUser.ID)
	if cursorToken != "" {

		// 过滤条件与下方的三段降序排序严格对应：置顶、排序时间、记录 ID。

		pinnedValue := 0

		if decodedCursor.Pinned {

			pinnedValue = 1

		}
		query = query.Where(

			"(is_pinned < ?) OR (is_pinned = ? AND sort_time < ?) OR (is_pinned = ? AND sort_time = ? AND id < ?)",

			pinnedValue,

			pinnedValue,

			cursorSortTime,

			pinnedValue,

			cursorSortTime,

			decodedCursor.ID,
		)
	} else if offset > 0 {

		query = query.Offset(offset)
	}
	query.
		Order("is_pinned DESC, sort_time DESC, id DESC").
		Limit(pageSize + 1).
		Find(&userChats)
	hasMore := len(userChats) > pageSize
	if hasMore {

		userChats = userChats[:pageSize]
	}
	nextCursor := ""
	if hasMore && len(userChats) > 0 {

		nextCursor = encodeChatListCursor(userChats[len(userChats)-1])
	}
	// 获取会话详情
	chatIDs := make([]uint64, 0, len(userChats))
	for _, uc := range userChats {

		chatIDs = append(chatIDs, uc.ChatID)
	}
	var chats []models.Chat
	if len(chatIDs) > 0 {

		h.db.Where("id IN ?", chatIDs).Find(&chats)
	}
	// 构建聊天 ID 到聊天的映射
	chatMap := make(map[uint64]models.Chat)
	for _, chat := range chats {

		chatMap[chat.ID] = chat
	}
	// 批量预加载私聊对方用户信息，避免 N+1 查询
	// Step 1：收集已知 TargetID 和需要通过 ChatMember 补全的私聊
	knownTargetIDs := make([]uint64, 0)
	missingChatIDs := make([]uint64, 0)
	for _, uc := range userChats {

		if chat, ok := chatMap[uc.ChatID]; ok && chat.Type == 1 {

			if uc.TargetID > 0 {

				knownTargetIDs = append(knownTargetIDs, uc.TargetID)

			} else {

				missingChatIDs = append(missingChatIDs, uc.ChatID)

			}

		}
	}
	// Step 2：批量查询已知 TargetID 对应的用户
	targetUserMap := make(map[uint64]models.User) // userID -> User
	if len(knownTargetIDs) > 0 {
		var targetUsers []models.User

		h.db.Where("id IN ?", knownTargetIDs).Find(&targetUsers)

		for _, u := range targetUsers {

			targetUserMap[u.ID] = u

		}
	}
	// Step 3：对 TargetID=0 的私聊，批量查 ChatMember 再批量查用户
	chatIDToTargetUserID := make(map[uint64]uint64) // chatID -> targetUserID（用于 TargetID=0 的情况）
	if len(missingChatIDs) > 0 {
		var otherMembers []models.ChatMember

		h.db.Where("chat_id IN ? AND user_id != ?", missingChatIDs, currentUser.ID).Find(&otherMembers)
		missingUserIDs := make([]uint64, 0, len(otherMembers))

		for _, m := range otherMembers {

			chatIDToTargetUserID[m.ChatID] = m.UserID

			missingUserIDs = append(missingUserIDs, m.UserID)

		}

		if len(missingUserIDs) > 0 {
			var missingUsers []models.User

			h.db.Where("id IN ?", missingUserIDs).Find(&missingUsers)

			for _, u := range missingUsers {

				targetUserMap[u.ID] = u

			}

		}

		// 异步补填 TargetID，不阻塞响应

		for _, uc := range userChats {

			if uc.TargetID == 0 {

				if tid, ok := chatIDToTargetUserID[uc.ChatID]; ok {

					ucID, memberID := uc.ID, tid

					go h.db.Model(&models.UserChat{}).Where("id = ?", ucID).Update("target_id", memberID)

				}

			}

		}
	}
	// Step 3.5：批量查询当前用户对私聊对象设置的联系人备注
	contactRemarkMap := make(map[uint64]string) // targetUserID -> remark
	remarkTargetIDs := make([]uint64, 0, len(targetUserMap))
	for userID := range targetUserMap {

		remarkTargetIDs = append(remarkTargetIDs, userID)
	}
	if len(remarkTargetIDs) > 0 {
		var contacts []models.Contact

		h.db.Where(

			"user_id = ? AND contact_user_id IN ? AND status = 1",

			currentUser.ID,

			remarkTargetIDs,
		).Find(&contacts)

		for _, contact := range contacts {

			if contact.Remark != "" {

				contactRemarkMap[contact.ContactUserID] = contact.Remark

			}

		}
	}
	vipSummaries := buildUserVipSummaries(h.db, remarkTargetIDs)
	// Step 4：统一组装响应
	result := make([]gin.H, 0, len(userChats))
	for _, userChat := range userChats {

		chat, ok := chatMap[userChat.ChatID]

		if !ok {

			continue

		}
		item := gin.H{

			"id": userChat.ID,

			"chat_id": chat.UUID,

			"type": chat.Type,

			"name": chat.Name,

			"avatar": chat.Avatar,

			"description": chat.Description,

			"member_count": chat.MemberCount,

			"status": chat.Status,

			"pending_request": false,

			"pending_request_count": 0,

			"last_msg_text": normalizeStoredChatPreviewText(userChat.LastMsgText, userChat.LastMsgType),

			"last_msg_type": userChat.LastMsgType,

			"last_msg_time": optionalTimeValue(userChat.LastMsgTime),

			"last_msg_seq": userChat.LastMsgSeq,

			"last_msg_sender": userChat.LastMsgSender,

			"last_msg_media_url": userChat.LastMsgMediaURL,

			"unread_count": userChat.UnreadCount,

			"has_mention": userChat.HasMention,

			"is_pinned": userChat.IsPinned,

			"is_muted": userChat.IsMuted,

			"is_archived": userChat.IsArchived,
		}

		if chat.Type == 1 {
			targetID := userChat.TargetID

			if targetID == 0 {

				targetID = chatIDToTargetUserID[userChat.ChatID]

			}

			if tu, ok := targetUserMap[targetID]; ok {
				displayName := tu.Nickname

				if remark, ok := contactRemarkMap[targetID]; ok && strings.TrimSpace(remark) != "" {

					displayName = remark

				} else if displayName == "" {

					displayName = tu.Username

				}

				item["target_id"] = tu.ID

				item["target_uuid"] = tu.UUID

				item["name"] = displayName

				item["remark"] = contactRemarkMap[targetID]

				item["avatar"] = tu.Avatar

				item["emoji_avatar"] = tu.EmojiAvatar

				item["nickname_color"] = tu.NicknameColor

				item["vip"] = vipSummaries[targetID]

			}

		} else if chat.JoinApproval {
			var member models.ChatMember
			if err := h.db.Where("chat_id = ? AND user_id = ?", chat.ID, currentUser.ID).First(&member).Error; err == nil {

				if canReviewJoinRequests(chat.Type, member.Role) {
					var pendingCount int64

					h.db.Model(&models.JoinRequest{}).
						Where("chat_id = ? AND status = ?", chat.ID, models.JoinRequestPending).
						Count(&pendingCount)

					item["pending_request"] = pendingCount > 0

					item["pending_request_count"] = pendingCount

				}

			}

		}
		result = append(result, item)
	}
	payload := gin.H{

		"list": result,

		"page": page,

		"page_size": pageSize,

		"has_more": hasMore,

		"next_cursor": nextCursor,
	}
	if useHotCache && h.cache != nil {

		_ = h.cache.Set(c.Request.Context(), cacheKey, payload, chatListHotCacheTTL)
	}
	response.Success(c, payload)
}

// CreateChatRequest 创建会话请求
type CreateChatRequest struct {
	Type        int8     `json:"type" binding:"required,oneof=1 2 3"` // 1:私聊 2:群聊 3:频道
	Name        string   `json:"name"`
	Description string   `json:"description"`
	MemberIDs   []string `json:"member_ids"` // 成员UUID列表
	IsPublic    bool     `json:"is_public"`
	Avatar      string   `json:"avatar"`
	MaxMembers  int      `json:"max_members"` // 自定义群人数上限，0使用系统默认
}

func (h *ChatHandler) CreateChat(c *gin.Context) {
	userID := c.GetString("user_id")
	var req CreateChatRequest
	if err := c.ShouldBindJSON(&req); err != nil {

		response.BadRequest(c, "参数错误")

		return
	}
	// 获取当前用户
	var currentUser models.User
	if err := h.db.Where("uuid = ?", userID).First(&currentUser).Error; err != nil {

		response.NotFound(c, "用户不存在")

		return
	}
	now := time.Now()
	// 私聊检查
	if req.Type == 1 {

		if len(req.MemberIDs) != 1 {

			response.BadRequest(c, "私聊只能有一个对方")

			return

		}
		// 获取对方用户（支持数字ID和UUID）
		var targetUser models.User
		if err := h.db.Where("uuid = ?", req.MemberIDs[0]).First(&targetUser).Error; err != nil {

			// UUID 查询失败，尝试用数字 ID 查询

			if err := h.db.First(&targetUser, req.MemberIDs[0]).Error; err != nil {

				response.NotFound(c, "用户不存在")

				return

			}

		}
		// 检查是否已存在私聊
		var existingChat models.Chat

		err := h.db.Raw(` 


SELECT c.* FROM chats c 


JOIN chat_members cm1 ON c.id = cm1.chat_id AND cm1.user_id = ? 


JOIN chat_members cm2 ON c.id = cm2.chat_id AND cm2.user_id = ? 


WHERE c.type = 1 


LIMIT 1 

`, currentUser.ID, targetUser.ID).Scan(&existingChat).Error

		if err == nil && existingChat.ID > 0 {

			// 确保双方都有 UserChat 记录，并更新 TargetID
			var userChat1 models.UserChat
			if err := h.db.Where("chat_id = ? AND user_id = ?", existingChat.ID, currentUser.ID).First(&userChat1).Error; err != nil {

				if err := h.db.Create(&models.UserChat{

					UserID: currentUser.ID,

					ChatID: existingChat.ID,

					TargetID: targetUser.ID,

					SortTime: now,
				}).Error; err != nil {

					response.ServerError(c, "恢复会话失败")

					return

				}

			} else if userChat1.TargetID == 0 {

				// 更新 TargetID

				if err := h.db.Model(&userChat1).Update("target_id", targetUser.ID).Error; err != nil {

					response.ServerError(c, "恢复会话失败")

					return

				}

			}
			var userChat2 models.UserChat
			if err := h.db.Where("chat_id = ? AND user_id = ?", existingChat.ID, targetUser.ID).First(&userChat2).Error; err != nil {

				if err := h.db.Create(&models.UserChat{

					UserID: targetUser.ID,

					ChatID: existingChat.ID,

					TargetID: currentUser.ID,

					SortTime: now,
				}).Error; err != nil {

					response.ServerError(c, "恢复会话失败")

					return

				}

			} else if userChat2.TargetID == 0 {

				// 更新 TargetID

				if err := h.db.Model(&userChat2).Update("target_id", currentUser.ID).Error; err != nil {

					response.ServerError(c, "恢复会话失败")

					return

				}

			}

			response.Success(c, existingChat)

			return

		}

		// 创建私聊

		chat := models.Chat{

			UUID: uuid.New().String(),

			Type: 1,

			MemberCount: 2,

			InviteLink: uuid.New().String()[:8], // 私聊也需要唯一的 invite_link 避免索引冲突

			CreatedAt: now,

			UpdatedAt: now,
		}
		tx := h.db.Begin()

		if tx.Error != nil {

			response.ServerError(c, "创建失败")

			return

		}

		defer func() {

			if r := recover(); r != nil {

				tx.Rollback()

				panic(r)

			}

		}()

		if err := tx.Create(&chat).Error; err != nil {

			tx.Rollback()

			response.ServerError(c, "创建失败")

			return

		}

		// 添加成员（私聊双方都是普通成员）

		members := []models.ChatMember{

			{ChatID: chat.ID, UserID: currentUser.ID, Role: 0, JoinedAt: now, UpdatedAt: now},

			{ChatID: chat.ID, UserID: targetUser.ID, Role: 0, JoinedAt: now, UpdatedAt: now},
		}

		if err := tx.Create(&members).Error; err != nil {

			tx.Rollback()

			response.ServerError(c, "创建失败")

			return

		}

		// 为双方创建 UserChat 记录

		userChats := []models.UserChat{

			{

				UserID: currentUser.ID,

				ChatID: chat.ID,

				TargetID: targetUser.ID,

				SortTime: now,
			},

			{

				UserID: targetUser.ID,

				ChatID: chat.ID,

				TargetID: currentUser.ID,

				SortTime: now,
			},
		}

		if err := tx.Create(&userChats).Error; err != nil {

			tx.Rollback()

			response.ServerError(c, "创建失败")

			return

		}

		if err := tx.Commit().Error; err != nil {

			response.ServerError(c, "创建失败")

			return

		}

		// 通过 WebSocket 通知对方有新会话

		if h.hub != nil {

			h.hub.Broadcast(&ws.BroadcastMessage{

				Type: "new_chat",

				UserIDs: []string{targetUser.UUID},

				Data: map[string]interface{}{

					"chat_id": chat.UUID,

					"chat_type": 1,

					"target_id": currentUser.ID, // 使用数字ID保持头像颜色一致

					"name": currentUser.Nickname,

					"avatar": currentUser.Avatar,
				},
			})

		}

		response.Success(c, chat)

		return
	}
	var vipCreationCheck services.ChatCreationCheck
	if req.Type == 2 || req.Type == 3 {

		check, err := h.vipService().CanCreateChat(currentUser.ID, req.Type)

		if err != nil {

			response.ServerError(c, "校验会员权限失败")

			return

		}

		if !check.Allowed {
			message := check.Message

			if message == "" {

				message = "当前会员权限不足"

			}

			response.Forbidden(c, message)

			return

		}
		vipCreationCheck = check

		if req.IsPublic && !check.Entitlements.CanSetPublicUsername {

			response.Forbidden(c, "开通 SVIP 后可设置公开群号和公开频道")

			return

		}
	}
	// 群聊/频道
	if req.Name == "" {

		response.BadRequest(c, "群组名称不能为空")

		return
	}
	maxMembers := h.resolveCreateMaxMembers(req, vipCreationCheck.MaxMembers)
	memberUsers := make([]models.User, 0)
	if len(req.MemberIDs) > 0 {

		resolvedUsers, err := h.resolveUsersByIdentifiers(req.MemberIDs)

		if err != nil {

			response.ServerError(c, "获取群成员失败")

			return

		}
		seenMemberIDs := make(map[uint64]struct{}, len(resolvedUsers))

		for _, u := range resolvedUsers {

			if u.ID == currentUser.ID {

				continue

			}

			if _, ok := seenMemberIDs[u.ID]; ok {

				continue

			}

			seenMemberIDs[u.ID] = struct{}{}
			memberUsers = append(memberUsers, u)

		}

		if req.Type == 2 && h.isGroupInviteRequireFriendEnabled() && len(memberUsers) > 0 {
			candidateIDs := make([]uint64, 0, len(memberUsers))

			for _, u := range memberUsers {

				candidateIDs = append(candidateIDs, u.ID)

			}
			var friendIDs []uint64

			if err := h.db.Model(&models.Contact{}).
				Where("user_id = ? AND contact_user_id IN ? AND status = 1", currentUser.ID, candidateIDs).
				Pluck("contact_user_id", &friendIDs).Error; err != nil {

				response.ServerError(c, "校验联系人关系失败")

				return

			}
			friendSet := make(map[uint64]bool, len(friendIDs))

			for _, id := range friendIDs {

				friendSet[id] = true

			}

			for _, u := range memberUsers {

				if !friendSet[u.ID] {
					name := u.Nickname

					if name == "" {

						name = u.Username

					}

					if name == "" {

						name = u.UUID

					}

					response.Forbidden(c, "非好友不可拉进群聊："+name)

					return

				}

			}

		}

		// 检查成员上限（创建者已占1个位置）

		if maxMembers > 0 && len(memberUsers)+1 > maxMembers {

			memberUsers = memberUsers[:maxMembers-1]

		}
	}
	chat := models.Chat{

		UUID: uuid.New().String(),

		Type: req.Type,

		Name: req.Name,

		Description: req.Description,

		Avatar: req.Avatar,

		OwnerID: currentUser.ID,

		IsPublic: req.IsPublic,

		MemberCount: len(memberUsers) + 1,

		MaxMembers: maxMembers,

		InviteLink: uuid.New().String()[:8],

		CreatedAt: now,

		UpdatedAt: now,
	}
	// 频道模式: 默认只有管理员可发言（类似 Telegram）
	if req.Type == 3 {

		chat.CanSendMessage = false
	}
	// 群/频道、创建者成员记录、管理员权限及各成员 UserChat 投影属于同一个创建事务。
	tx := h.db.Begin()
	if tx.Error != nil {

		response.ServerError(c, "创建失败")

		return
	}
	defer func() {

		if r := recover(); r != nil {

			tx.Rollback()

			panic(r)

		}
	}()
	if err := tx.Create(&chat).Error; err != nil {

		tx.Rollback()

		response.ServerError(c, "创建失败")

		return
	}
	// 添加创建者为群主
	ownerMember := models.ChatMember{

		ChatID: chat.ID,

		UserID: currentUser.ID,

		Role: 2, // 群主 (数据库: 0=成员, 1=管理员, 2=创建者)

		JoinedAt: now,

		UpdatedAt: now,
	}
	if err := tx.Create(&ownerMember).Error; err != nil {

		tx.Rollback()

		response.ServerError(c, "创建失败")

		return
	}
	// 为创建者创建 user_chats 记录
	ownerUserChat := models.UserChat{

		UserID: currentUser.ID,

		ChatID: chat.ID,

		IsPinned: false,

		IsMuted: false,

		SortTime: now,

		UpdatedAt: now,
	}
	if err := tx.Create(&ownerUserChat).Error; err != nil {

		tx.Rollback()

		response.ServerError(c, "创建失败")

		return
	}
	// 收集所有需要通知的成员ID
	var notifyUserIDs []string
	// 添加其他成员
	if len(memberUsers) > 0 {
		members := make([]models.ChatMember, 0, len(memberUsers))
		userChats := make([]models.UserChat, 0, len(memberUsers))

		for _, u := range memberUsers {

			members = append(members, models.ChatMember{

				ChatID: chat.ID,

				UserID: u.ID,

				Role: 0, // 普通成员 (数据库: 0=成员, 1=管理员, 2=创建者)

				JoinedAt: now,

				UpdatedAt: now,
			})
			userChats = append(userChats, models.UserChat{

				UserID: u.ID,

				ChatID: chat.ID,

				IsPinned: false,

				IsMuted: false,

				SortTime: now,

				UpdatedAt: now,
			})
			notifyUserIDs = append(notifyUserIDs, u.UUID)

		}

		if err := tx.Create(&members).Error; err != nil {

			tx.Rollback()

			response.ServerError(c, "添加群成员失败")

			return

		}

		if err := tx.Create(&userChats).Error; err != nil {

			tx.Rollback()

			response.ServerError(c, "添加群成员失败")

			return

		}
	}
	if err := tx.Commit().Error; err != nil {

		response.ServerError(c, "创建失败")

		return
	}
	// 通过 WebSocket 通知被邀请的成员以及创建者的其他设备
	if h.hub != nil {

		// 构造新群聊通知（包含创建者自己，用于多设备同步）

		allNotifyIDs := append(notifyUserIDs, currentUser.UUID)
		newChatNotification := map[string]interface{}{

			"type": "new_chat",

			"message": map[string]interface{}{

				"id": chat.UUID,

				"type": chat.Type,

				"name": chat.Name,

				"avatar": chat.Avatar,

				"owner_id": currentUser.UUID,

				"member_count": chat.MemberCount,

				"created_at": chat.CreatedAt,
			},
		}

		h.hub.Broadcast(&ws.BroadcastMessage{

			Data: newChatNotification,

			UserIDs: allNotifyIDs,
		})
	}
	// 发送"xxx 创建了群聊/频道"系统消息，让会话排到列表顶部
	if h.msgService != nil {
		chatTypeName := "群聊"

		if chat.Type == 3 {

			chatTypeName = "频道"

		}
		creatorName := currentUser.Nickname

		if creatorName == "" {

			creatorName = currentUser.Username

		}

		h.sendSystemMessage(c.Request.Context(), &chat, creatorName+" 创建了"+chatTypeName)
	}
	response.Success(c, chat)
}

// ChatDetailResponse 聊天详情响应
type ChatDetailResponse struct {
	models.Chat
	OnlineCount int  `json:"online_count"`
	MyRole      int8 `json:"my_role"` // 当前用户在此群的角色: 0=非成员, 1=普通成员, 2=管理员, 3=群主
}

func (h *ChatHandler) GetChat(c *gin.Context) {
	chatID := c.Param("id")
	userID := c.GetString("user_id")
	var chat models.Chat
	if err := h.db.Where("uuid = ?", chatID).First(&chat).Error; err != nil {

		response.NotFound(c, "会话不存在")

		return
	}
	// 获取当前用户
	var currentUser models.User
	if err := h.db.Where("uuid = ?", userID).First(&currentUser).Error; err != nil {

		response.NotFound(c, "用户不存在")

		return
	}
	// 获取当前用户在此群的角色
	// 返回值: 0=非成员, 1=普通成员, 2=管理员, 3=群主
	var myRole int8 = 0
	var hasPendingRequest bool = false
	if chat.Type == 2 || chat.Type == 3 { // 群聊或频道
		var member models.ChatMember
		if err := h.db.Where("chat_id = ? AND user_id = ?", chat.ID, currentUser.ID).First(&member).Error; err == nil {

			// 数据库存储: 0=成员, 1=管理员, 2=创建者

			// 转换为: 1=普通成员, 2=管理员, 3=群主

			myRole = member.Role + 1

		} else {

			// 检查是否有待审批的加入请求
			var count int64

			h.db.Model(&models.JoinRequest{}).Where("chat_id = ? AND user_id = ? AND status = ?",

				chat.ID, currentUser.ID, models.JoinRequestPending).Count(&count)
			hasPendingRequest = count > 0

		}
	} else if chat.Type == 1 { // 私聊

		myRole = 1 // 私聊中双方都是普通成员
	}
	// 私聊：必须是成员；群/频道：非成员仅允许访问（可查看基本信息用于加入），敏感字段已在后续屏蔽
	if chat.Type == 1 && myRole == 0 {

		response.Forbidden(c, "无权访问该会话")

		return
	}
	// 在线人数必须以当前成员表为边界。仅统计 WebSocket 订阅会把刚退群但
	// 尚未重连的客户端算进去，造成 member_count=1、online_count=2。
	onlineCount := 0
	if chat.Type == 2 || chat.Type == 3 {

		if h.hub != nil {
			var memberUUIDs []string

			h.db.Table("chat_members AS cm").
				Select("u.uuid").
				Joins("JOIN users AS u ON u.id = cm.user_id AND u.deleted_at IS NULL").
				Where("cm.chat_id = ?", chat.ID).
				Pluck("u.uuid", &memberUUIDs)

			for _, memberUUID := range memberUUIDs {

				if h.hub.IsUserOnline(memberUUID) {

					onlineCount++

				}

			}

		}
	} else if chat.Type == 1 {
		var members []models.ChatMember

		h.db.Where("chat_id = ?", chat.ID).Find(&members)

		for _, m := range members {

			if m.UserID != currentUser.ID {
				var targetUser models.User

				h.db.First(&targetUser, m.UserID)
				canSeeOnline, err := privacy.CanViewerSeeOnlineStatus(h.db, currentUser.ID, targetUser.ID)

				if err == nil && canSeeOnline && h.hub != nil && h.hub.IsUserOnline(targetUser.UUID) {

					onlineCount = 1

				}

			}

		}
	}
	// 对于私聊，获取对方用户信息（包括名字、头像、数字ID、表情状态、昵称颜色）
	var targetUserID string
	var targetUserName string
	var targetUserAvatar string
	var targetEmojiAvatar string
	var targetNicknameColor string
	var targetVip gin.H
	if chat.Type == 1 {
		var members []models.ChatMember

		h.db.Where("chat_id = ?", chat.ID).Find(&members)

		for _, m := range members {

			if m.UserID != currentUser.ID {
				var targetUser models.User

				h.db.First(&targetUser, m.UserID)
				targetUserID = targetUser.UUID // 使用 UUID

				// 获取对方用户的名字、头像、表情状态、昵称颜色

				targetUserName = targetUser.Nickname

				if targetUserName == "" {

					targetUserName = targetUser.Username

				}
				targetUserAvatar = targetUser.Avatar

				targetEmojiAvatar = targetUser.EmojiAvatar

				targetNicknameColor = targetUser.NicknameColor

				targetVip = buildUserVipSummary(h.db, targetUser.ID)

				break

			}

		}
	}
	// 确定返回的名字和头像（私聊用对方用户的信息）
	respName := chat.Name
	respAvatar := chat.Avatar
	if chat.Type == 1 && targetUserName != "" {

		respName = targetUserName

		respAvatar = targetUserAvatar
	}
	resp := gin.H{

		"id": chat.ID,

		"uuid": chat.UUID,

		"type": chat.Type,

		"name": respName,

		"avatar": respAvatar,

		"description": chat.Description,

		"owner_id": chat.OwnerID,

		"member_count": chat.MemberCount,

		"status": chat.Status,

		"online_count": onlineCount,

		"my_role": myRole,

		"pending_request": hasPendingRequest,

		"is_public": chat.IsPublic,

		"join_approval": chat.JoinApproval,

		"invite_link": chat.InviteLink,

		"username": chat.Username,

		"can_send_message": chat.CanSendMessage,

		"can_send_media": chat.CanSendMedia,

		"can_send_links": chat.CanSendLinks,

		"can_add_members": chat.CanAddMembers,

		"can_pin_messages": chat.CanPinMessages,

		"allow_anonymous": chat.AllowAnonymous,

		"allow_forward": chat.AllowForward,

		"allow_view_history": chat.AllowViewHistory,

		"member_protection": chat.MemberProtection,

		"created_at": chat.CreatedAt,
	}
	// 私聊添加对方用户信息
	if chat.Type == 1 && targetUserID != "" {

		resp["target_user_id"] = targetUserID

		resp["emoji_avatar"] = targetEmojiAvatar

		resp["nickname_color"] = targetNicknameColor

		resp["vip"] = targetVip
	}
	response.Success(c, resp)
}

// UpdateChatRequest 更新会话请求
type UpdateChatRequest struct {
	Name             *string `json:"name"`
	Description      *string `json:"description"`
	Avatar           *string `json:"avatar"`
	Username         *string `json:"username"`
	IsPublic         *bool   `json:"is_public"`
	JoinApproval     *bool   `json:"join_approval"`
	CanSendMessage   *bool   `json:"can_send_message"`
	CanSendMedia     *bool   `json:"can_send_media"`
	CanSendLinks     *bool   `json:"can_send_links"`
	CanAddMembers    *bool   `json:"can_add_members"`
	CanPinMessages   *bool   `json:"can_pin_messages"`
	AllowAnonymous   *bool   `json:"allow_anonymous"`
	AllowForward     *bool   `json:"allow_forward"`
	AllowViewHistory *bool   `json:"allow_view_history"`
	MemberProtection *bool   `json:"member_protection"`
}

// UpdateChat 更新会话
func (h *ChatHandler) UpdateChat(c *gin.Context) {
	userID := c.GetString("user_id")
	chatID := c.Param("id")
	var req UpdateChatRequest
	if err := c.ShouldBindJSON(&req); err != nil {

		response.BadRequest(c, "参数错误")

		return
	}
	var chat models.Chat
	if err := h.db.Where("uuid = ?", chatID).First(&chat).Error; err != nil {

		response.NotFound(c, "会话不存在")

		return
	}
	// 检查权限
	var currentUser models.User
	if err := h.db.Where("uuid = ?", userID).First(&currentUser).Error; err != nil {

		response.NotFound(c, "用户不存在")

		return
	}
	var member models.ChatMember
	if err := h.db.Where("chat_id = ? AND user_id = ?", chat.ID, currentUser.ID).First(&member).Error; err != nil {

		response.Forbidden(c, "无权限")

		return
	}
	if !h.hasAdminPermission(chat, member, "change_info") {

		response.Forbidden(c, "无权限，需要管理员或群主身份")

		return
	}
	if chat.Type == 2 && (req.AllowAnonymous != nil || req.AllowForward != nil || req.AllowViewHistory != nil) && member.Role < 2 {

		response.Forbidden(c, "无权限，需要管理员或群主身份")

		return
	}
	if message, err := h.validateVipChatSettings(currentUser.ID, chat, req); err != nil {

		response.ServerError(c, "校验会员权益失败")

		return
	} else if message != "" {

		response.Forbidden(c, message)

		return
	}
	// 群资料统一做去空格、长度和敏感词校验，避免不同客户端绕过限制。
	var normalizedName *string
	if req.Name != nil {
		name := strings.TrimSpace(*req.Name)

		if name == "" {

			response.BadRequest(c, "群名称不能为空")

			return

		}

		if len([]rune(name)) > 32 {

			response.BadRequest(c, "群名称不能超过32个字符")

			return

		}
		filtered, blocked := filterContentWithDB(h.db, name)

		if blocked {

			response.BadRequest(c, "群名称包含不允许的内容")

			return

		}
		normalizedName = &filtered
	}
	var normalizedDescription *string
	if req.Description != nil {
		raw := *req.Description

		description := strings.TrimSpace(raw)

		if raw != "" && description == "" {

			response.BadRequest(c, "群描述不能只包含空格")

			return

		}

		if len([]rune(description)) > 1000 {

			response.BadRequest(c, "群描述不能超过1000个字符")

			return

		}
		filtered, blocked := filterContentWithDB(h.db, description)

		if blocked {

			response.BadRequest(c, "群描述包含不允许的内容")

			return

		}
		normalizedDescription = &filtered
	}
	oldName := chat.Name
	oldCanSendMessage := chat.CanSendMessage
	// 更新
	updates := map[string]interface{}{

		"updated_at": time.Now(),
	}
	if normalizedName != nil {

		updates["name"] = *normalizedName
	}
	if normalizedDescription != nil {

		updates["description"] = *normalizedDescription
	}
	if req.Avatar != nil {

		updates["avatar"] = *req.Avatar
	}
	if req.Username != nil {

		updates["username"] = *req.Username
	}
	if req.IsPublic != nil {

		updates["is_public"] = *req.IsPublic
	}
	if req.JoinApproval != nil {

		updates["join_approval"] = *req.JoinApproval
	}
	// 权限设置
	if req.CanSendMessage != nil {

		updates["can_send_message"] = *req.CanSendMessage
	}
	if req.CanSendMedia != nil {

		updates["can_send_media"] = *req.CanSendMedia
	}
	if req.CanSendLinks != nil {

		updates["can_send_links"] = *req.CanSendLinks
	}
	if req.CanAddMembers != nil {

		updates["can_add_members"] = *req.CanAddMembers
	}
	if req.CanPinMessages != nil {

		updates["can_pin_messages"] = *req.CanPinMessages
	}
	if req.AllowAnonymous != nil {

		updates["allow_anonymous"] = *req.AllowAnonymous
	}
	if req.AllowForward != nil {

		updates["allow_forward"] = *req.AllowForward
	}
	if req.AllowViewHistory != nil {

		updates["allow_view_history"] = *req.AllowViewHistory
	}
	if req.MemberProtection != nil {

		updates["member_protection"] = *req.MemberProtection
	}
	if err := h.db.Model(&chat).Updates(updates).Error; err != nil {

		response.ServerError(c, "更新失败")

		return
	}
	// 重新获取更新后的数据
	if err := h.db.Where("uuid = ?", chatID).First(&chat).Error; err != nil {

		response.ServerError(c, "更新失败")

		return
	}
	// 如果权限相关字段或加入审批设置被更新，广播给所有成员
	if req.CanSendMessage != nil || req.CanSendMedia != nil || req.CanSendLinks != nil || req.CanAddMembers != nil || req.CanPinMessages != nil || req.AllowAnonymous != nil || req.AllowForward != nil || req.AllowViewHistory != nil || req.MemberProtection != nil || req.JoinApproval != nil {

		h.broadcastChatPermissionsUpdated(&chat)
	}
	if normalizedName != nil || normalizedDescription != nil || req.Avatar != nil {

		h.broadcastChatUpdate(&chat)
	}
	operatorName := strings.TrimSpace(currentUser.Nickname)
	if operatorName == "" {

		operatorName = currentUser.Username
	}
	if normalizedName != nil && chat.Name != oldName {

		h.sendSystemMessage(c.Request.Context(), &chat, fmt.Sprintf("%s 将群名称修改为 %s", operatorName, chat.Name))
	}
	if req.CanSendMessage != nil && chat.CanSendMessage != oldCanSendMessage {

		if chat.CanSendMessage {

			h.sendSystemMessage(c.Request.Context(), &chat, fmt.Sprintf("%s 已解除全员禁言", operatorName))

		} else {

			h.sendSystemMessage(c.Request.Context(), &chat, fmt.Sprintf("%s 已开启全员禁言", operatorName))

		}
	}
	response.Success(c, chat)
}

// GetMyPermissions 获取当前用户在群/频道内的细分权限
func (h *ChatHandler) GetMyPermissions(c *gin.Context) {
	userID := c.GetString("user_id")
	chatID := c.Param("id")
	var chat models.Chat
	if err := h.db.Where("uuid = ?", chatID).First(&chat).Error; err != nil {

		response.NotFound(c, "会话不存在")

		return
	}
	if chat.Type == 1 {

		response.BadRequest(c, "私聊没有群权限")

		return
	}
	var currentUser models.User
	if err := h.db.Where("uuid = ?", userID).First(&currentUser).Error; err != nil {

		response.NotFound(c, "用户不存在")

		return
	}
	var member models.ChatMember
	if err := h.db.Where("chat_id = ? AND user_id = ?", chat.ID, currentUser.ID).First(&member).Error; err != nil {

		response.Forbidden(c, "您不是该群成员")

		return
	}
	perm := h.getEffectiveAdminPermissions(chat, member)
	response.Success(c, gin.H{

		"role": member.Role + 1,

		"is_owner": member.Role >= 2,

		"is_admin": member.Role >= 1,

		"permissions": adminPermissionMap(perm),
	})
}

// TransferChatOwner 用户侧转让群主/频道主
func (h *ChatHandler) TransferChatOwner(c *gin.Context) {
	userID := c.GetString("user_id")
	chatID := c.Param("id")
	var req struct {
		UserID string `json:"user_id" binding:"required"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {

		response.BadRequest(c, "请选择新群主")

		return
	}
	var currentUser models.User
	if err := h.db.Where("uuid = ?", userID).First(&currentUser).Error; err != nil {

		response.NotFound(c, "用户不存在")

		return
	}
	var targetUser models.User
	if err := h.db.Where("uuid = ?", req.UserID).First(&targetUser).Error; err != nil {

		response.NotFound(c, "目标用户不存在")

		return
	}
	var chat models.Chat
	if err := h.db.Where("uuid = ?", chatID).First(&chat).Error; err != nil {

		response.NotFound(c, "会话不存在")

		return
	}
	if chat.Type == 1 {

		response.BadRequest(c, "私聊不能转让")

		return
	}
	if chat.Status == models.ChatStatusBanned {

		response.Forbidden(c, "已封禁的群不能转让群主")

		return
	}
	if chat.Status == models.ChatStatusDissolved {

		response.Forbidden(c, "已解散的群不能转让群主")

		return
	}
	if chat.OwnerID != currentUser.ID {

		response.Forbidden(c, "只有群主可以转让")

		return
	}
	if currentUser.ID == targetUser.ID {

		response.BadRequest(c, "不能转让给自己")

		return
	}
	now := time.Now()
	if err := h.db.Transaction(func(tx *gorm.DB) error {

		if err := tx.Clauses(clause.Locking{Strength: "UPDATE"}).Where("id = ?", chat.ID).First(&chat).Error; err != nil {

			return err

		}

		if chat.OwnerID != currentUser.ID {

			return fmt.Errorf("owner_changed")

		}
		var targetMember models.ChatMember
		if err := tx.Clauses(clause.Locking{Strength: "UPDATE"}).
			Where("chat_id = ? AND user_id = ?", chat.ID, targetUser.ID).
			First(&targetMember).Error; err != nil {

			return err

		}

		if err := tx.Model(&models.ChatMember{}).
			Where("chat_id = ? AND user_id = ?", chat.ID, currentUser.ID).
			Updates(map[string]interface{}{"role": 1, "updated_at": now}).Error; err != nil {

			return err

		}

		if err := tx.Model(&targetMember).
			Updates(map[string]interface{}{"role": 2, "updated_at": now}).Error; err != nil {

			return err

		}

		if err := tx.Model(&chat).
			Updates(map[string]interface{}{"owner_id": targetUser.ID, "updated_at": now}).Error; err != nil {

			return err

		}

		if err := h.ensureAdminPermissions(tx, chat, currentUser.ID, nil); err != nil {

			return err

		}

		return tx.Where("chat_id = ? AND user_id = ?", chat.ID, targetUser.ID).
			Delete(&models.ChatAdminPermission{}).Error
	}); err != nil {

		if err == gorm.ErrRecordNotFound {

			response.NotFound(c, "目标用户不是群成员")

			return

		}

		if err.Error() == "owner_changed" {

			response.Forbidden(c, "群主已变更，请刷新后重试")

			return

		}

		response.ServerError(c, "转让失败")

		return
	}
	if h.hub != nil {

		h.broadcastChatUpdate(&chat)

		h.hub.Broadcast(&ws.BroadcastMessage{

			UserIDs: []string{currentUser.UUID, targetUser.UUID},

			Data: map[string]interface{}{

				"type": "chat_owner_transferred",

				"message": map[string]interface{}{

					"chat_id": chat.UUID,

					"old_owner_id": currentUser.UUID,

					"new_owner_id": targetUser.UUID,
				},
			},
		})
	}
	oldOwnerName := strings.TrimSpace(currentUser.Nickname)
	if oldOwnerName == "" {

		oldOwnerName = currentUser.Username
	}
	newOwnerName := strings.TrimSpace(targetUser.Nickname)
	if newOwnerName == "" {

		newOwnerName = targetUser.Username
	}
	h.sendSystemMessage(c.Request.Context(), &chat, fmt.Sprintf("%s 将群主转让给 %s", oldOwnerName, newOwnerName))
	response.Success(c, gin.H{

		"message": "群主已转让",

		"owner_id": targetUser.UUID,
	})
}

// DeleteChat 删除会话
func (h *ChatHandler) DeleteChat(c *gin.Context) {
	userID := c.GetString("user_id")
	chatID := c.Param("id")
	var chat models.Chat
	if err := h.db.Where("uuid = ?", chatID).First(&chat).Error; err != nil {

		response.NotFound(c, "会话不存在")

		return
	}
	// 检查权限
	var currentUser models.User
	if err := h.db.Where("uuid = ?", userID).First(&currentUser).Error; err != nil {

		response.NotFound(c, "用户不存在")

		return
	}
	if chat.OwnerID != currentUser.ID {

		response.Forbidden(c, "只有群主可以解散群组")

		return
	}
	if chat.Type == 1 {

		response.BadRequest(c, "私聊不能解散")

		return
	}
	// 删除前先收集所有成员UUID，用于广播通知
	var memberUserIDs []uint64
	h.db.Model(&models.ChatMember{}).Where("chat_id = ?", chat.ID).Pluck("user_id", &memberUserIDs)
	var memberUUIDs []string
	if len(memberUserIDs) > 0 {

		h.db.Model(&models.User{}).Where("id IN ?", memberUserIDs).Pluck("uuid", &memberUUIDs)
	}
	if err := h.db.Transaction(func(tx *gorm.DB) error {

		if err := tx.Clauses(clause.Locking{Strength: "UPDATE"}).
			Where("id = ?", chat.ID).First(&chat).Error; err != nil {

			return err

		}

		if chat.Status == models.ChatStatusDissolved {

			return nil

		}
		now := time.Now()

		if err := tx.Model(&chat).Updates(map[string]interface{}{

			"status": models.ChatStatusDissolved,

			"updated_at": now,
		}).Error; err != nil {

			return err

		}

		// 保留成员和会话列表投影，供离线设备拉取“已解散”终态，并继续只读历史消息。

		return tx.Model(&models.UserChat{}).Where("chat_id = ?", chat.ID).
			Updates(map[string]interface{}{"updated_at": now}).Error
	}); err != nil {

		response.ServerError(c, "解散群组失败")

		return
	}
	// 先提交不可逆的解散终态，再失效缓存并广播，避免客户端收到事件后仍读到可写状态。
	deleteUserChatListHotCache(c.Request.Context(), h.cache, memberUserIDs...)
	if h.msgService != nil {

		h.msgService.InvalidateMessageWindowCache(c.Request.Context(), chat.UUID)
	}
	if h.hub != nil && len(memberUUIDs) > 0 {
		dissolvedPayload := map[string]interface{}{

			"type": "chat_dissolved",

			"chat_id": chatID,

			"status": models.ChatStatusDissolved,

			"read_only": true,
		}

		h.hub.Broadcast(&ws.BroadcastMessage{

			Data: dissolvedPayload,

			UserIDs: memberUUIDs,
		})
	}
	response.Success(c, nil)
}

// ChatMemberItem 成员信息
type ChatMemberItem struct {
	UserID         string     `json:"user_id"`
	Username       string     `json:"username"`
	Nickname       string     `json:"nickname"`
	GlobalNickname string     `json:"global_nickname,omitempty"`
	NicknameInChat string     `json:"nickname_in_chat,omitempty"`
	Avatar         string     `json:"avatar"`
	Role           int8       `json:"role"` // 1:成员 2:管理员 3:群主
	IsOnline       bool       `json:"is_online"`
	IsMuted        bool       `json:"is_muted"`
	MuteEndTime    *time.Time `json:"mute_end_time,omitempty"`
	NicknameColor  string     `json:"nickname_color,omitempty"` // 昵称颜色
	EmojiAvatar    string     `json:"emoji_avatar,omitempty"`   // 动态表情
	Vip            gin.H      `json:"vip"`
}

// GetMembers 获取群成员列表
func (h *ChatHandler) GetMembers(c *gin.Context) {
	userID := c.GetString("user_id")
	chatID := c.Param("id")
	var chat models.Chat
	if err := h.db.Where("uuid = ?", chatID).First(&chat).Error; err != nil {

		response.NotFound(c, "会话不存在")

		return
	}
	// 检查当前用户是否是成员
	var currentUser models.User
	if err := h.db.Where("uuid = ?", userID).First(&currentUser).Error; err != nil {

		response.NotFound(c, "not found")

		return
	}
	var myMember models.ChatMember
	if err := h.db.Where("chat_id = ? AND user_id = ?", chat.ID, currentUser.ID).First(&myMember).Error; err != nil {

		response.Forbidden(c, "你不是该群成员")

		return
	}
	// 获取成员列表（支持分页，避免万人群一次加载全部）
	page, _ := strconv.Atoi(c.DefaultQuery("page", "1"))
	pageSize, _ := strconv.Atoi(c.DefaultQuery("page_size", "200"))
	if pageSize > 500 {

		pageSize = 500
	}
	offset := (page - 1) * pageSize
	var members []models.ChatMember
	query := h.db.Where("chat_id = ?", chat.ID)
	if chat.Type == 2 && chat.MemberProtection && myMember.Role < 1 {

		query = h.db.Where("chat_id = ? AND role >= 1", chat.ID)
	} else if chat.Type == 3 && myMember.Role < 1 {

		query = h.db.Where("chat_id = ? AND role >= 1", chat.ID)
	}
	query.Order("role DESC, joined_at ASC").Offset(offset).Limit(pageSize).Find(&members)
	// 批量获取成员详情（一条 SQL 替代 N 条）
	userIDs := make([]uint64, len(members))
	for i, m := range members {

		userIDs[i] = m.UserID
	}
	var users []models.User
	if len(userIDs) > 0 {

		h.db.Where("id IN ?", userIDs).Find(&users)
	}
	onlineVisibility, err := privacy.BatchCanViewerSeeOnlineStatus(h.db, currentUser.ID, userIDs)
	if err != nil {

		onlineVisibility = map[uint64]bool{}
	}
	userMap := make(map[uint64]models.User)
	for _, u := range users {

		userMap[u.ID] = u
	}
	vipSummaries := buildUserVipSummaries(h.db, userIDs)
	var result []ChatMemberItem
	for _, m := range members {
		user := userMap[m.UserID]

		isOnline := false

		if onlineVisibility[user.ID] && h.hub != nil {

			isOnline = h.hub.IsUserOnline(user.UUID)

		}
		effectiveNickname := strings.TrimSpace(m.Nickname)

		if effectiveNickname == "" {

			effectiveNickname = user.Nickname

		}
		result = append(result, ChatMemberItem{

			UserID: user.UUID,

			Username: user.Username,

			Nickname: effectiveNickname,

			GlobalNickname: user.Nickname,

			NicknameInChat: m.Nickname,

			Avatar: user.Avatar,

			Role: m.Role + 1,

			IsOnline: isOnline,

			IsMuted: m.IsMuted,

			MuteEndTime: m.MuteEndTime,

			NicknameColor: user.NicknameColor,

			EmojiAvatar: user.EmojiAvatar,

			Vip: vipSummaries[m.UserID],
		})
	}
	response.Success(c, result)
}

// UpdateMemberNickname 修改本人或被授权成员的群昵称。
func (h *ChatHandler) UpdateMemberNickname(c *gin.Context) {
	chatUUID := c.Param("id")
	targetUUID := c.Param("user_id")
	operatorUUID := c.GetString("user_id")
	var req struct {
		Nickname string `json:"nickname"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {

		response.BadRequest(c, "参数错误")

		return
	}
	nickname := strings.TrimSpace(req.Nickname)
	if len([]rune(nickname)) > 32 {

		response.BadRequest(c, "群昵称不能超过32个字符")

		return
	}
	filtered, blocked := filterContentWithDB(h.db, nickname)
	if blocked {

		response.BadRequest(c, "群昵称包含不允许的内容")

		return
	}
	nickname = filtered
	var chat models.Chat
	if err := h.db.Where("uuid = ?", chatUUID).First(&chat).Error; err != nil {

		response.NotFound(c, "会话不存在")

		return
	}
	if chat.Type == 1 {

		response.BadRequest(c, "私聊不支持群昵称")

		return
	}
	var operator, target models.User
	if err := h.db.Where("uuid = ?", operatorUUID).First(&operator).Error; err != nil {

		response.Unauthorized(c, "用户不存在")

		return
	}
	if err := h.db.Where("uuid = ?", targetUUID).First(&target).Error; err != nil {

		response.NotFound(c, "目标用户不存在")

		return
	}
	var operatorMember, targetMember models.ChatMember
	if err := h.db.Where("chat_id = ? AND user_id = ?", chat.ID, operator.ID).First(&operatorMember).Error; err != nil {

		response.Forbidden(c, "您不是该群成员")

		return
	}
	if err := h.db.Where("chat_id = ? AND user_id = ?", chat.ID, target.ID).First(&targetMember).Error; err != nil {

		response.NotFound(c, "目标用户不是群成员")

		return
	}
	if operator.ID != target.ID {

		if operatorMember.Role < 1 {

			response.Forbidden(c, "没有权限修改其他成员的群昵称")

			return

		}

		if targetMember.Role >= 2 || (operatorMember.Role == 1 && targetMember.Role >= 1) {

			response.Forbidden(c, "不能修改群主或同级管理员的群昵称")

			return

		}
	}
	if err := h.db.Model(&targetMember).Updates(map[string]interface{}{

		"nickname": nickname,

		"updated_at": time.Now(),
	}).Error; err != nil {

		response.ServerError(c, "群昵称修改失败")

		return
	}
	operatorName := strings.TrimSpace(operator.Nickname)
	if operatorName == "" {

		operatorName = operator.Username
	}
	targetName := strings.TrimSpace(target.Nickname)
	if targetName == "" {

		targetName = target.Username
	}
	if operator.ID == target.ID {

		if nickname == "" {

			h.sendSystemMessage(c.Request.Context(), &chat, fmt.Sprintf("%s 清除了群昵称", targetName))

		} else {

			h.sendSystemMessage(c.Request.Context(), &chat, fmt.Sprintf("%s 将群昵称修改为 %s", targetName, nickname))

		}
	} else if nickname == "" {

		h.sendSystemMessage(c.Request.Context(), &chat, fmt.Sprintf("%s 清除了 %s 的群昵称", operatorName, targetName))
	} else {

		h.sendSystemMessage(c.Request.Context(), &chat, fmt.Sprintf("%s 将 %s 的群昵称修改为 %s", operatorName, targetName, nickname))
	}
	h.broadcastMemberNicknameChanged(c.Request.Context(), &chat, target.UUID, nickname)
	response.Success(c, gin.H{"nickname": nickname})
}

// AddMembersRequest 添加成员请求
type chatMemberSearchRow struct {
	UserID        uint64     `gorm:"column:user_id"`
	Role          int8       `gorm:"column:role"`
	IsMuted       bool       `gorm:"column:is_muted"`
	MuteEndTime   *time.Time `gorm:"column:mute_end_time"`
	UserUUID      string     `gorm:"column:user_uuid"`
	Username      string     `gorm:"column:username"`
	Nickname      string     `gorm:"column:nickname"`
	Avatar        string     `gorm:"column:avatar"`
	NicknameColor string     `gorm:"column:nickname_color"`
	EmojiAvatar   string     `gorm:"column:emoji_avatar"`
}

// SearchMembers 搜索群成员
func (h *ChatHandler) SearchMembers(c *gin.Context) {
	userID := c.GetString("user_id")
	chatID := c.Param("id")
	keyword := strings.TrimSpace(c.Query("keyword"))
	if keyword == "" {

		response.Success(c, []ChatMemberItem{})

		return
	}
	var chat models.Chat
	if err := h.db.Where("uuid = ?", chatID).First(&chat).Error; err != nil {

		response.NotFound(c, "not found")

		return
	}
	var currentUser models.User
	if err := h.db.Where("uuid = ?", userID).First(&currentUser).Error; err != nil {

		response.NotFound(c, "用户不存在")

		return
	}
	var myMember models.ChatMember
	if err := h.db.Where("chat_id = ? AND user_id = ?", chat.ID, currentUser.ID).First(&myMember).Error; err != nil {

		response.Forbidden(c, "forbidden")

		return
	}
	page, _ := strconv.Atoi(c.DefaultQuery("page", "1"))
	pageSize, _ := strconv.Atoi(c.DefaultQuery("page_size", "200"))
	if page < 1 {

		page = 1
	}
	if pageSize <= 0 {

		pageSize = 200
	}
	if pageSize > 500 {

		pageSize = 500
	}
	offset := (page - 1) * pageSize
	likeKeyword := "%" + keyword + "%"
	query := h.db.Table("chat_members AS cm").
		Select("cm.user_id, cm.role, cm.is_muted, cm.mute_end_time, u.uuid AS user_uuid, u.username, u.nickname, u.avatar, u.nickname_color, u.emoji_avatar").
		Joins("JOIN users AS u ON u.id = cm.user_id AND u.deleted_at IS NULL").
		Where("cm.chat_id = ?", chat.ID).
		Where("(u.nickname LIKE ? OR u.username LIKE ?)", likeKeyword, likeKeyword)
	if chat.Type == 2 && chat.MemberProtection && myMember.Role < 1 {

		query = query.Where("cm.role >= 1")
	}
	var rows []chatMemberSearchRow
	if err := query.Order("cm.role DESC, cm.joined_at ASC").Offset(offset).Limit(pageSize).Scan(&rows).Error; err != nil {

		response.Error(c, http.StatusInternalServerError, "search members failed")

		return
	}
	searchUserIDs := make([]uint64, 0, len(rows))
	for _, row := range rows {

		searchUserIDs = append(searchUserIDs, row.UserID)
	}
	searchVisibility, err := privacy.BatchCanViewerSeeOnlineStatus(h.db, currentUser.ID, searchUserIDs)
	if err != nil {

		searchVisibility = map[uint64]bool{}
	}
	vipSummaries := buildUserVipSummaries(h.db, searchUserIDs)
	result := make([]ChatMemberItem, 0, len(rows))
	for _, row := range rows {
		isOnline := false

		if searchVisibility[row.UserID] && h.hub != nil {

			isOnline = h.hub.IsUserOnline(row.UserUUID)

		}
		result = append(result, ChatMemberItem{

			UserID: row.UserUUID,

			Username: row.Username,

			Nickname: row.Nickname,

			Avatar: row.Avatar,

			Role: row.Role + 1,

			IsOnline: isOnline,

			IsMuted: row.IsMuted,

			MuteEndTime: row.MuteEndTime,

			NicknameColor: row.NicknameColor,

			EmojiAvatar: row.EmojiAvatar,

			Vip: vipSummaries[row.UserID],
		})
	}
	response.Success(c, result)
}

type AddMembersRequest struct {
	UserIDs []string `json:"user_ids" binding:"required"`
}

// AddMembers 添加成员
func (h *ChatHandler) AddMembers(c *gin.Context) {
	userID := c.GetString("user_id")
	chatID := c.Param("id")
	var req AddMembersRequest
	if err := c.ShouldBindJSON(&req); err != nil {

		response.BadRequest(c, "参数错误")

		return
	}
	var chat models.Chat
	if err := h.db.Where("uuid = ?", chatID).First(&chat).Error; err != nil {

		response.NotFound(c, "会话不存在")

		return
	}
	if chat.Status == models.ChatStatusBanned {

		response.Forbidden(c, "该群组已被管理员封禁，无法添加成员")

		return
	}
	if chat.Status == models.ChatStatusDissolved {

		response.Forbidden(c, "该群组已被解散")

		return
	}
	// 检查权限
	var currentUser models.User
	if err := h.db.Where("uuid = ?", userID).First(&currentUser).Error; err != nil {

		response.NotFound(c, "用户不存在")

		return
	}
	var member models.ChatMember
	if err := h.db.Where("chat_id = ? AND user_id = ?", chat.ID, currentUser.ID).First(&member).Error; err != nil {

		response.Forbidden(c, "无权限")

		return
	}
	if member.Role < 1 && !chat.CanAddMembers {

		response.Forbidden(c, "仅管理员可邀请新成员")

		return
	}
	if member.Role >= 1 && !h.hasAdminPermission(chat, member, "invite_users") {

		response.Forbidden(c, "没有邀请成员权限")

		return
	}
	// 检查成员上限
	maxMembers := h.getEffectiveMaxMembers(&chat)
	if maxMembers > 0 {
		remainingSlots := maxMembers - chat.MemberCount

		if remainingSlots <= 0 {

			if chat.Type == 3 {

				response.BadRequest(c, "该频道订阅者已达上限")

			} else {

				response.BadRequest(c, "该群组成员已达上限")

			}

			return

		}
	}
	// 添加成员
	users, err := h.resolveUsersByIdentifiers(req.UserIDs)
	if err != nil {

		response.ServerError(c, "获取群成员失败")

		return
	}
	now := time.Now()
	addedCount := 0
	var addedUsers []models.User
	var addedUserUUIDs []string
	// 批量检查已存在的成员（1 条 SQL 替代 N 条）
	allUserIDs := make([]uint64, len(users))
	for i, u := range users {

		allUserIDs[i] = u.ID
	}
	var existingUserIDs []uint64
	if len(allUserIDs) > 0 {

		h.db.Model(&models.ChatMember{}).Where("chat_id = ? AND user_id IN ?", chat.ID, allUserIDs).Pluck("user_id", &existingUserIDs)
	}
	existingSet := make(map[uint64]bool)
	for _, id := range existingUserIDs {

		existingSet[id] = true
	}
	if chat.Type == 2 && h.isGroupInviteRequireFriendEnabled() {
		candidateIDs := make([]uint64, 0, len(users))

		for _, u := range users {

			if !existingSet[u.ID] && u.ID != currentUser.ID {

				candidateIDs = append(candidateIDs, u.ID)

			}

		}

		if len(candidateIDs) > 0 {
			var friendIDs []uint64

			if err := h.db.Model(&models.Contact{}).
				Where("user_id = ? AND contact_user_id IN ? AND status = 1", currentUser.ID, candidateIDs).
				Pluck("contact_user_id", &friendIDs).Error; err != nil {

				response.ServerError(c, "校验联系人关系失败")

				return

			}
			friendSet := make(map[uint64]bool, len(friendIDs))

			for _, id := range friendIDs {

				friendSet[id] = true

			}

			for _, u := range users {

				if existingSet[u.ID] || u.ID == currentUser.ID {

					continue

				}

				if !friendSet[u.ID] {
					name := u.Nickname

					if name == "" {

						name = u.Username

					}

					if name == "" {

						name = u.UUID

					}

					response.Forbidden(c, "非好友不可拉进群聊："+name)

					return

				}

			}

		}
	}
	// 构建批量插入数据
	var newMembers []models.ChatMember
	var newUserChats []models.UserChat
	for _, u := range users {

		if maxMembers > 0 && chat.MemberCount+addedCount >= maxMembers {

			break

		}

		if existingSet[u.ID] {

			continue

		}
		newMembers = append(newMembers, models.ChatMember{

			ChatID: chat.ID,

			UserID: u.ID,

			Role: 0,

			JoinedAt: now,

			UpdatedAt: now,
		})
		newUserChats = append(newUserChats, models.UserChat{

			UserID: u.ID,

			ChatID: chat.ID,

			SortTime: now,

			UpdatedAt: now,
		})

		addedCount++

		addedUsers = append(addedUsers, u)
		addedUserUUIDs = append(addedUserUUIDs, u.UUID)
	}
	// 批量插入（2 条 SQL 替代 2N 条）
	if len(newMembers) > 0 {
		tx := h.db.Begin()

		if tx.Error != nil {

			response.ServerError(c, "添加成员失败")

			return

		}

		defer func() {

			if r := recover(); r != nil {

				tx.Rollback()

				panic(r)

			}

		}()

		if err := tx.Create(&newMembers).Error; err != nil {

			tx.Rollback()

			response.ServerError(c, "添加成员失败")

			return

		}

		if err := tx.Create(&newUserChats).Error; err != nil {

			tx.Rollback()

			response.ServerError(c, "添加成员失败")

			return

		}

		if err := tx.Model(&chat).Update("member_count", gorm.Expr("member_count + ?", addedCount)).Error; err != nil {

			tx.Rollback()

			response.ServerError(c, "添加成员失败")

			return

		}

		if err := tx.Commit().Error; err != nil {

			response.ServerError(c, "添加成员失败")

			return

		}
	}
	// 发送系统消息通知群里所有人
	if addedCount > 0 && h.msgService != nil {

		// 构造被添加成员的名字列表
		var addedNames []string

		for _, u := range addedUsers {
			name := u.Nickname

			if name == "" {

				name = u.Username

			}
			addedNames = append(addedNames, name)

		}
		inviterName := currentUser.Nickname

		if inviterName == "" {

			inviterName = currentUser.Username

		}
		// 系统消息内容
		var systemText string
		if len(addedNames) == 1 {

			systemText = inviterName + " 邀请 " + addedNames[0] + " 加入了群组"

		} else {

			systemText = inviterName + " 邀请 " + strconv.Itoa(len(addedNames)) + " 位成员加入了群组"

		}

		// 发送系统消息

		systemParams := &services.SendMessageParams{

			ChatID: chat.UUID,

			SenderID: "system",

			Type: models.MsgTypeSystem,

			Content: map[string]interface{}{

				"text": systemText,
			},
		}
		// 获取所有群成员的 UUID 用于广播
		var allMemberIDs []uint64

		h.db.Model(&models.ChatMember{}).Where("chat_id = ?", chat.ID).Pluck("user_id", &allMemberIDs)
		var allMemberUUIDs []string

		h.db.Model(&models.User{}).Where("id IN ?", allMemberIDs).Pluck("uuid", &allMemberUUIDs)
		sysMsg, err := h.msgService.SendMessage(context.Background(), systemParams, "系统消息", "", "", "", allMemberUUIDs)

		if err != nil {

			log.Printf("Failed to send system message: %v", err)

		} else {

			// 更新 UserChat 系统消息预览

			previewText := normalizeStoredChatPreviewText(systemText, models.MsgTypeSystem)

			h.db.Model(&models.UserChat{}).
				Where("chat_id = ?", chat.ID).
				Updates(map[string]interface{}{

					"last_msg_text": previewText,

					"last_msg_type": models.MsgTypeSystem,

					"last_msg_time": sysMsg.CreatedAt,

					"last_msg_seq": sysMsg.Seq,

					"last_msg_sender": "",

					"last_msg_media_url": "",

					"sort_time": sysMsg.CreatedAt,
				})

		}

		// WebSocket 通知新成员有新群组

		if h.hub != nil {
			newChatNotification := map[string]interface{}{

				"type": "new_chat",

				"message": map[string]interface{}{

					"id": chat.UUID,

					"type": chat.Type,

					"name": chat.Name,

					"avatar": chat.Avatar,

					"member_count": chat.MemberCount + addedCount,
				},
			}

			h.hub.Broadcast(&ws.BroadcastMessage{

				Data: newChatNotification,

				UserIDs: addedUserUUIDs,
			})

		}
	}
	response.Success(c, gin.H{"added": addedCount})
}

// RemoveMember 移除成员
func (h *ChatHandler) RemoveMember(c *gin.Context) {
	userID := c.GetString("user_id")
	chatID := c.Param("id")
	targetUserID := c.Param("user_id")
	var chat models.Chat
	if err := h.db.Where("uuid = ?", chatID).First(&chat).Error; err != nil {

		response.NotFound(c, "会话不存在")

		return
	}
	// 获取当前用户
	var currentUser models.User
	if err := h.db.Where("uuid = ?", userID).First(&currentUser).Error; err != nil {

		response.NotFound(c, "用户不存在")

		return
	}
	// 检查权限
	var currentMember models.ChatMember
	if err := h.db.Where("chat_id = ? AND user_id = ?", chat.ID, currentUser.ID).First(&currentMember).Error; err != nil {

		response.Forbidden(c, "无权限")

		return
	}
	removeResult, err := h.chatMemberService().RemoveMember(c.Request.Context(), chat, currentMember, targetUserID)
	if err != nil {

		switch {

		case errors.Is(err, services.ErrChatMemberTargetUserNotFound):

			response.NotFound(c, "用户不存在")

		case errors.Is(err, services.ErrChatMemberTargetNotFound):

			response.NotFound(c, "该用户不是群成员")

		case errors.Is(err, services.ErrChatPermissionDenied):

			response.Forbidden(c, "无权限")

		case errors.Is(err, services.ErrChatPermissionTargetOwner):

			response.BadRequest(c, "不能移除群主")

		case errors.Is(err, services.ErrChatPermissionAdminPeer):

			response.Forbidden(c, "管理员不能移除其他管理员")

		default:

			response.ServerError(c, "移除失败")

		}

		return
	}
	targetUser := removeResult.TargetUser
	// 通知被移除用户的所有设备
	if h.hub != nil {

		h.hub.SendToUser(targetUser.UUID, map[string]interface{}{

			"type": "chat_left",

			"chat_id": chat.UUID,
		})
	}
	// 广播成员数更新给剩余成员
	h.broadcastChatUpdate(&chat)
	response.Success(c, nil)
}

// SetMemberRole 设置成员角色（管理员）
func (h *ChatHandler) SetMemberRole(c *gin.Context) {
	userID := c.GetString("user_id")
	chatID := c.Param("id")
	targetUserID := c.Param("user_id")
	var req struct {
		Role int8 `json:"role"` // 0: 普通成员, 1: 管理员

		Permissions *chatAdminPermissionPayload `json:"permissions"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {

		response.BadRequest(c, "参数错误")

		return
	}
	// 只允许设置为普通成员或管理员
	if req.Role < 0 || req.Role > 1 {

		response.BadRequest(c, "无效的角色")

		return
	}
	var chat models.Chat
	if err := h.db.Where("uuid = ?", chatID).First(&chat).Error; err != nil {

		response.NotFound(c, "会话不存在")

		return
	}
	if chat.Status == models.ChatStatusDissolved {

		response.Forbidden(c, "已解散的群不能设置管理员")

		return
	}
	// 获取当前用户
	var currentUser models.User
	if err := h.db.Where("uuid = ?", userID).First(&currentUser).Error; err != nil {

		response.NotFound(c, "用户不存在")

		return
	}
	// 检查权限 - 只有群主可以设置管理员
	var currentMember models.ChatMember
	if err := h.db.Where("chat_id = ? AND user_id = ?", chat.ID, currentUser.ID).First(&currentMember).Error; err != nil {

		response.Forbidden(c, "无权限")

		return
	}
	if !h.hasAdminPermission(chat, currentMember, "manage_admins") {

		response.Forbidden(c, "只有群主可以设置管理员")

		return
	}
	// 获取要设置的用户
	var targetUser models.User
	if err := h.db.Where("uuid = ?", targetUserID).First(&targetUser).Error; err != nil {

		response.NotFound(c, "用户不存在")

		return
	}
	// 不能修改群主角色
	if chat.OwnerID == targetUser.ID {

		response.BadRequest(c, "不能修改群主角色")

		return
	}
	// 检查目标用户是否为群成员
	var targetMember models.ChatMember
	if err := h.db.Where("chat_id = ? AND user_id = ?", chat.ID, targetUser.ID).First(&targetMember).Error; err != nil {

		response.NotFound(c, "该用户不是群成员")

		return
	}
	previousRole := targetMember.Role
	err := h.db.Transaction(func(tx *gorm.DB) error {

		if err := tx.Clauses(clause.Locking{Strength: "UPDATE"}).
			Where("id = ?", chat.ID).First(&chat).Error; err != nil {

			return err

		}

		if chat.Status == models.ChatStatusDissolved {

			return fmt.Errorf("chat_dissolved")

		}

		if err := tx.Clauses(clause.Locking{Strength: "UPDATE"}).
			Where("id = ?", targetMember.ID).First(&targetMember).Error; err != nil {

			return err

		}

		if err := tx.Model(&targetMember).Updates(map[string]interface{}{

			"role": req.Role,

			"updated_at": time.Now(),
		}).Error; err != nil {

			return err

		}

		if req.Role == 1 {

			return h.ensureAdminPermissions(tx, chat, targetUser.ID, req.Permissions)

		}

		return tx.Where("chat_id = ? AND user_id = ?", chat.ID, targetUser.ID).
			Delete(&models.ChatAdminPermission{}).Error
	})
	if err != nil {

		if err.Error() == "chat_dissolved" {

			response.Forbidden(c, "已解散的群不能设置管理员")

			return

		}

		response.ServerError(c, "设置失败")

		return
	}
	roleText := "普通成员"
	if req.Role == 1 {

		roleText = "管理员"
	}
	h.broadcastMemberRoleChanged(c.Request.Context(), &chat, targetUser.UUID, req.Role+1)
	if previousRole != req.Role {
		operatorName := strings.TrimSpace(currentUser.Nickname)

		if operatorName == "" {

			operatorName = currentUser.Username

		}
		targetName := strings.TrimSpace(targetUser.Nickname)

		if targetName == "" {

			targetName = targetUser.Username

		}

		if req.Role == 1 {

			h.sendSystemMessage(c.Request.Context(), &chat, fmt.Sprintf("%s 将 %s 设为管理员", operatorName, targetName))

		} else {

			h.sendSystemMessage(c.Request.Context(), &chat, fmt.Sprintf("%s 取消了 %s 的管理员身份", operatorName, targetName))

		}
	}
	response.Success(c, gin.H{

		"message": "已将该用户设为" + roleText,

		"role": req.Role,

		"permissions": adminPermissionMap(h.getEffectiveAdminPermissions(chat, models.ChatMember{ChatID: chat.ID, UserID: targetUser.ID, Role: req.Role})),
	})
}
func (h *ChatHandler) broadcastMemberRoleChanged(
	ctx context.Context,
	chat *models.Chat,
	targetUserUUID string,
	clientRole int8) {
	if h == nil || chat == nil {

		return
	}
	var memberUserIDs []uint64
	h.db.Model(&models.ChatMember{}).Where("chat_id = ?", chat.ID).Pluck("user_id", &memberUserIDs)
	deleteUserChatListHotCache(ctx, h.cache, memberUserIDs...)
	if h.hub == nil || len(memberUserIDs) == 0 {

		return
	}
	var memberUUIDs []string
	h.db.Model(&models.User{}).Where("id IN ?", memberUserIDs).Pluck("uuid", &memberUUIDs)
	if len(memberUUIDs) == 0 {

		return
	}
	h.hub.Broadcast(&ws.BroadcastMessage{

		UserIDs: memberUUIDs,

		Data: map[string]interface{}{

			"type": "member_role_changed",

			"chat_id": chat.UUID,

			"user_id": targetUserUUID,

			"role": clientRole,
		},
	})
}

// GetMemberPermissions 获取指定管理员的细分权限
func (h *ChatHandler) GetMemberPermissions(c *gin.Context) {
	userID := c.GetString("user_id")
	chatID := c.Param("id")
	targetUserID := c.Param("user_id")
	var chat models.Chat
	if err := h.db.Where("uuid = ?", chatID).First(&chat).Error; err != nil {

		response.NotFound(c, "会话不存在")

		return
	}
	if chat.Type == 1 {

		response.BadRequest(c, "私聊没有管理员权限")

		return
	}
	var currentUser models.User
	if err := h.db.Where("uuid = ?", userID).First(&currentUser).Error; err != nil {

		response.NotFound(c, "用户不存在")

		return
	}
	var currentMember models.ChatMember
	if err := h.db.Where("chat_id = ? AND user_id = ?", chat.ID, currentUser.ID).First(&currentMember).Error; err != nil {

		response.Forbidden(c, "无权限")

		return
	}
	if !h.hasAdminPermission(chat, currentMember, "manage_admins") && currentUser.UUID != targetUserID {

		response.Forbidden(c, "没有权限查看管理员权限")

		return
	}
	var targetUser models.User
	if err := h.db.Where("uuid = ?", targetUserID).First(&targetUser).Error; err != nil {

		response.NotFound(c, "目标用户不存在")

		return
	}
	var targetMember models.ChatMember
	if err := h.db.Where("chat_id = ? AND user_id = ?", chat.ID, targetUser.ID).First(&targetMember).Error; err != nil {

		response.NotFound(c, "该用户不是群成员")

		return
	}
	perm := h.getEffectiveAdminPermissions(chat, targetMember)
	response.Success(c, gin.H{

		"role": targetMember.Role + 1,

		"is_owner": targetMember.Role >= 2,

		"is_admin": targetMember.Role >= 1,

		"permissions": adminPermissionMap(perm),
	})
}

// UpdateMemberPermissions 调整管理员细分权限
func (h *ChatHandler) UpdateMemberPermissions(c *gin.Context) {
	userID := c.GetString("user_id")
	chatID := c.Param("id")
	targetUserID := c.Param("user_id")
	var req chatAdminPermissionPayload
	if err := c.ShouldBindJSON(&req); err != nil {

		response.BadRequest(c, "参数错误")

		return
	}
	var chat models.Chat
	if err := h.db.Where("uuid = ?", chatID).First(&chat).Error; err != nil {

		response.NotFound(c, "会话不存在")

		return
	}
	if chat.Type == 1 {

		response.BadRequest(c, "私聊没有管理员权限")

		return
	}
	var currentUser models.User
	if err := h.db.Where("uuid = ?", userID).First(&currentUser).Error; err != nil {

		response.NotFound(c, "用户不存在")

		return
	}
	var currentMember models.ChatMember
	if err := h.db.Where("chat_id = ? AND user_id = ?", chat.ID, currentUser.ID).First(&currentMember).Error; err != nil {

		response.Forbidden(c, "无权限")

		return
	}
	if !h.hasAdminPermission(chat, currentMember, "manage_admins") {

		response.Forbidden(c, "没有权限调整管理员权限")

		return
	}
	var targetUser models.User
	if err := h.db.Where("uuid = ?", targetUserID).First(&targetUser).Error; err != nil {

		response.NotFound(c, "目标用户不存在")

		return
	}
	var targetMember models.ChatMember
	if err := h.db.Where("chat_id = ? AND user_id = ?", chat.ID, targetUser.ID).First(&targetMember).Error; err != nil {

		response.NotFound(c, "该用户不是群成员")

		return
	}
	if targetMember.Role >= 2 {

		response.BadRequest(c, "群主拥有全部权限，无需调整")

		return
	}
	if targetMember.Role < 1 {

		response.BadRequest(c, "请先将成员设为管理员")

		return
	}
	if err := h.ensureAdminPermissions(h.db, chat, targetUser.ID, &req); err != nil {

		response.ServerError(c, "保存权限失败")

		return
	}
	var perm models.ChatAdminPermission
	h.db.Where("chat_id = ? AND user_id = ?", chat.ID, targetUser.ID).First(&perm)
	response.Success(c, gin.H{

		"message": "管理员权限已更新",

		"permissions": adminPermissionMap(perm),
	})
}

// LeaveChat 用户主动退出群组/频道
func (h *ChatHandler) LeaveChat(c *gin.Context) {
	userID := c.GetString("user_id")
	chatID := c.Param("id")
	var chat models.Chat
	if err := h.db.Where("uuid = ?", chatID).First(&chat).Error; err != nil {

		response.NotFound(c, "会话不存在")

		return
	}
	// 私聊不能退出
	if chat.Type == 1 {

		response.BadRequest(c, "私聊不能退出")

		return
	}
	// 获取当前用户
	var currentUser models.User
	if err := h.db.Where("uuid = ?", userID).First(&currentUser).Error; err != nil {

		response.NotFound(c, "用户不存在")

		return
	}
	// 检查是否是成员
	var member models.ChatMember
	if err := h.db.Where("chat_id = ? AND user_id = ?", chat.ID, currentUser.ID).First(&member).Error; err != nil {

		response.BadRequest(c, "您不是该群成员")

		return
	}
	// 群主不能直接退出，需要先转让或解散
	if chat.OwnerID == currentUser.ID {

		response.BadRequest(c, "群主不能直接退出，请先转让群主或解散群组")

		return
	}
	defer deleteUserChatListHotCache(c.Request.Context(), h.cache, currentUser.ID)
	leaveTx := h.db.Begin()
	if leaveTx.Error != nil {

		response.ServerError(c, "退出失败")

		return
	}
	leaveResult := leaveTx.Where("chat_id = ? AND user_id = ?", chat.ID, currentUser.ID).Delete(&models.ChatMember{})
	if leaveResult.Error != nil {

		leaveTx.Rollback()

		response.ServerError(c, "退出失败")

		return
	}
	if leaveResult.RowsAffected == 0 {

		leaveTx.Rollback()

		response.BadRequest(c, "您不是该群成员")

		return
	}
	if err := leaveTx.Model(&chat).Update("member_count", gorm.Expr("member_count - 1")).Error; err != nil {

		leaveTx.Rollback()

		response.ServerError(c, "退出失败")

		return
	}
	if err := leaveTx.Where("user_id = ? AND chat_id = ?", currentUser.ID, chat.ID).Delete(&models.UserChat{}).Error; err != nil {

		leaveTx.Rollback()

		response.ServerError(c, "退出失败")

		return
	}
	if err := leaveTx.Commit().Error; err != nil {

		response.ServerError(c, "退出失败")

		return
	}
	// 退出也是群管理审计事件；此时成员关系已删除，消息只发送给剩余成员。
	leaverName := strings.TrimSpace(currentUser.Nickname)
	if leaverName == "" {

		leaverName = currentUser.Username
	}
	h.sendSystemMessage(c.Request.Context(), &chat, fmt.Sprintf("%s 退出了群组", leaverName))
	// 通知当前用户的其他设备同步退出事件
	if h.hub != nil {

		h.hub.SendToUser(userID, map[string]interface{}{

			"type": "chat_left",

			"chat_id": chat.UUID,
		})
	}
	// 通知群组/频道成员，成员数已更新
	h.broadcastChatUpdate(&chat)
	response.Success(c, nil)
}

// HideChat 隐藏/归档聊天（从列表中移除，不删除消息）
func (h *ChatHandler) HideChat(c *gin.Context) {
	userID := c.GetString("user_id")
	chatID := c.Param("id")
	// 获取当前用户
	var currentUser models.User
	if err := h.db.Where("uuid = ?", userID).First(&currentUser).Error; err != nil {

		response.NotFound(c, "用户不存在")

		return
	}
	// 获取会话
	var chat models.Chat
	if err := h.db.Where("uuid = ?", chatID).First(&chat).Error; err != nil {

		response.NotFound(c, "会话不存在")

		return
	}
	// 删除用户的 UserChat 记录（这会让聊天从列表中消失）
	// 但不删除消息，下次有新消息时会重新创建 UserChat
	defer deleteUserChatListHotCache(c.Request.Context(), h.cache, currentUser.ID)
	result := h.db.Where("user_id = ? AND chat_id = ?", currentUser.ID, chat.ID).Delete(&models.UserChat{})
	if result.RowsAffected == 0 {

		response.NotFound(c, "聊天不在列表中")

		return
	}
	// 广播隐藏事件到当前用户的其他设备（多端同步）
	if h.hub != nil {

		h.hub.SendToUser(userID, map[string]interface{}{

			"type": "chat_hidden",

			"chat_id": chatID,
		})
	}
	response.Success(c, nil)
}

// JoinChat 用户主动加入/订阅群组或频道
func (h *ChatHandler) JoinChat(c *gin.Context) {
	userID := c.GetString("user_id")
	chatID := c.Param("id")
	var chat models.Chat
	if err := h.db.Where("uuid = ?", chatID).First(&chat).Error; err != nil {

		response.NotFound(c, "会话不存在")

		return
	}
	// 只能加入群组或频道
	if chat.Type == 1 {

		response.BadRequest(c, "私聊不支持此操作")

		return
	}
	// 检查是否是公开群组/频道，或者有邀请链接
	if !chat.IsPublic {

		response.Forbidden(c, "该群组/频道不允许直接加入")

		return
	}
	// 获取当前用户
	var currentUser models.User
	if err := h.db.Where("uuid = ?", userID).First(&currentUser).Error; err != nil {

		response.NotFound(c, "用户不存在")

		return
	}
	// 检查是否已是成员
	var exists int64
	h.db.Model(&models.ChatMember{}).Where("chat_id = ? AND user_id = ?", chat.ID, currentUser.ID).Count(&exists)
	if exists > 0 {

		response.BadRequest(c, "您已是成员")

		return
	}
	// 检查成员上限
	joinMaxMembers := h.getEffectiveMaxMembers(&chat)
	if joinMaxMembers > 0 && chat.MemberCount >= joinMaxMembers {

		if chat.Type == 3 {

			response.BadRequest(c, "该频道订阅者已达上限")

		} else {

			response.BadRequest(c, "该群组成员已达上限")

		}

		return
	}
	// 检查是否有待审批的请求
	var pendingRequest models.JoinRequest
	h.db.Where("chat_id = ? AND user_id = ? AND status = ?", chat.ID, currentUser.ID, models.JoinRequestPending).First(&pendingRequest)
	if pendingRequest.ID > 0 {

		response.BadRequest(c, "您已提交加入申请，请等待审批")

		return
	}
	// 如果需要审批，创建加入请求（群组和频道都支持）
	if chat.JoinApproval {
		now := time.Now()
		joinRequest := models.JoinRequest{

			ChatID: chat.ID,

			UserID: currentUser.ID,

			Status: models.JoinRequestPending,

			CreatedAt: now,

			UpdatedAt: now,
		}

		if err := h.db.Create(&joinRequest).Error; err != nil {

			response.ServerError(c, "提交申请失败")

			return

		}
		message := buildJoinApprovalMessage(chat.Type)

		response.SuccessWithMessage(c, message, gin.H{

			"message": message,

			"requires_approval": true,
		})

		return
	}
	// 直接加入成员（使用事务+条件更新防止并发超卖）
	now := time.Now()
	defer deleteUserChatListHotCache(c.Request.Context(), h.cache, currentUser.ID)
	joinTx := h.db.Begin()
	if joinTx.Error != nil {

		response.ServerError(c, "加入失败")

		return
	}
	joinMaxCheck := h.getEffectiveMaxMembers(&chat)
	updateResult := joinTx.Model(&models.Chat{}).
		Where("id = ? AND (? = 0 OR member_count < ?)", chat.ID, joinMaxCheck, joinMaxCheck).
		Update("member_count", gorm.Expr("member_count + 1"))
	if updateResult.Error != nil || updateResult.RowsAffected == 0 {

		joinTx.Rollback()

		if chat.Type == 3 {

			response.BadRequest(c, "该频道订阅者已达上限")

		} else {

			response.BadRequest(c, "该群组成员已达上限")

		}

		return
	}
	member := models.ChatMember{

		ChatID: chat.ID,

		UserID: currentUser.ID,

		Role: 0,

		JoinedAt: now,

		UpdatedAt: now,
	}
	if err := joinTx.Create(&member).Error; err != nil {

		joinTx.Rollback()

		response.ServerError(c, "加入失败")

		return
	}
	// 创建 UserChat 记录
	userChat := models.UserChat{

		UserID: currentUser.ID,

		ChatID: chat.ID,

		TargetID: 0,

		SortTime: now,

		UpdatedAt: now,
	}
	if err := joinTx.Create(&userChat).Error; err != nil {

		joinTx.Rollback()

		response.ServerError(c, "加入失败")

		return
	}
	if err := joinTx.Commit().Error; err != nil {

		response.ServerError(c, "加入失败")

		return
	}
	// 用户主动加入不发送系统消息
	// 只有被邀请加入时才发送系统消息
	// 通知群组/频道成员，成员数已更新
	h.broadcastChatUpdate(&chat)
	response.Success(c, gin.H{

		"message": "加入成功",

		"requires_approval": false,
	})
}
func buildJoinApprovalMessage(chatType int8) string {
	if chatType == 3 {

		return "已提交订阅申请，请等待管理员审批"
	}
	return "已提交加入申请，请等待管理员审批"
}
func canReviewJoinRequests(chatType, memberRole int8) bool {
	if chatType == 2 {

		return memberRole >= 1
	}
	return memberRole >= 2
}

// JoinChatByInviteLink 通过邀请链接加入群组（扫码场景）
func (h *ChatHandler) JoinChatByInviteLink(c *gin.Context) {
	inviteLink := strings.TrimSpace(c.Param("invite_link"))
	userID := c.GetString("user_id")
	if inviteLink == "" {

		response.BadRequest(c, "bad request")

		return
	}
	var chat models.Chat
	if err := h.db.Where("invite_link = ?", inviteLink).First(&chat).Error; err != nil {

		response.NotFound(c, "not found")

		return
	}
	if chat.Type != 2 {

		response.BadRequest(c, "bad request")

		return
	}
	if chat.Status == models.ChatStatusBanned {

		response.Forbidden(c, "forbidden")

		return
	}
	if chat.Status == models.ChatStatusDissolved {

		response.BadRequest(c, "group dissolved")

		return
	}
	var currentUser models.User
	if err := h.db.Where("uuid = ?", userID).First(&currentUser).Error; err != nil {

		response.NotFound(c, "not found")

		return
	}
	now := time.Now()
	alreadyJoined := false
	requiresApproval := false
	approvalMessage := ""
	errGroupFull := fmt.Errorf("group_full")
	errPendingRequest := fmt.Errorf("join_request_pending")
	if err := h.db.Transaction(func(tx *gorm.DB) error {
		var exists int64
		if err := tx.Model(&models.ChatMember{}).
			Where("chat_id = ? AND user_id = ?", chat.ID, currentUser.ID).
			Count(&exists).Error; err != nil {

			return err

		}

		if exists > 0 {

			alreadyJoined = true

			return h.ensureUserChatRecord(tx, currentUser.ID, chat.ID, now)

		}
		inviteMaxMembers := h.getEffectiveMaxMembers(&chat)

		if chat.JoinApproval {
			var pendingCount int64
			if err := tx.Model(&models.JoinRequest{}).
				Where("chat_id = ? AND user_id = ? AND status = ?", chat.ID, currentUser.ID, models.JoinRequestPending).
				Count(&pendingCount).Error; err != nil {

				return err

			}

			if pendingCount > 0 {

				return errPendingRequest

			}
			joinRequest := models.JoinRequest{

				ChatID: chat.ID,

				UserID: currentUser.ID,

				Status: models.JoinRequestPending,

				CreatedAt: now,

				UpdatedAt: now,
			}

			if err := tx.Create(&joinRequest).Error; err != nil {

				return err

			}
			requiresApproval = true

			approvalMessage = buildJoinApprovalMessage(chat.Type)

			return nil

		}

		if err := tx.Where(

			"chat_id = ? AND user_id = ? AND status = ?",

			chat.ID,

			currentUser.ID,

			models.JoinRequestPending,
		).Delete(&models.JoinRequest{}).Error; err != nil {

			return err

		}
		member := models.ChatMember{

			ChatID: chat.ID,

			UserID: currentUser.ID,

			Role: 0,

			JoinedAt: now,

			UpdatedAt: now,
		}

		if err := tx.Create(&member).Error; err != nil {

			return err

		}

		// 条件更新：只有未超上限时才更新成员数，防止并发超卖

		inviteUpdateResult := tx.Model(&models.Chat{}).
			Where("id = ? AND (? = 0 OR member_count < ?)", chat.ID, inviteMaxMembers, inviteMaxMembers).
			Update("member_count", gorm.Expr("member_count + 1"))

		if inviteUpdateResult.Error != nil {

			return inviteUpdateResult.Error

		}

		if inviteUpdateResult.RowsAffected == 0 {

			return errGroupFull

		}

		chat.MemberCount++

		return h.ensureUserChatRecord(tx, currentUser.ID, chat.ID, now)
	}); err != nil {

		log.Printf("JoinChatByInviteLink failed: invite_link=%s user_uuid=%s chat_id=%d err=%v", inviteLink, userID, chat.ID, err)

		if err == errGroupFull {

			response.BadRequest(c, "bad request")

			return

		}

		if err == errPendingRequest {

			response.BadRequest(c, "您已提交加入申请，请等待审批")

			return

		}

		response.ServerError(c, "join group failed")

		return
	}
	if requiresApproval {

		response.SuccessWithMessage(c, approvalMessage, gin.H{

			"message": approvalMessage,

			"requires_approval": true,

			"chat_id": chat.UUID,

			"chat_name": chat.Name,

			"chat_avatar": chat.Avatar,

			"chat_type": chat.Type,

			"already_joined": false,
		})

		return
	}
	if !alreadyJoined {

		h.broadcastChatUpdate(&chat)
	}
	response.Success(c, gin.H{

		"message": map[bool]string{true: "already in group", false: "joined successfully"}[alreadyJoined],

		"requires_approval": false,

		"chat_id": chat.UUID,

		"chat_name": chat.Name,

		"chat_avatar": chat.Avatar,

		"chat_type": chat.Type,

		"already_joined": alreadyJoined,
	})
}
func (h *ChatHandler) GetJoinRequests(c *gin.Context) {
	chatID := c.Param("id")
	userID := c.GetString("user_id")
	var chat models.Chat
	if err := h.db.Where("uuid = ?", chatID).First(&chat).Error; err != nil {

		response.NotFound(c, "群组不存在")

		return
	}
	// 获取当前用户
	var currentUser models.User
	if err := h.db.Where("uuid = ?", userID).First(&currentUser).Error; err != nil {

		response.NotFound(c, "用户不存在")

		return
	}
	// 检查权限（只有管理员和群主可以查看）
	var member models.ChatMember
	if err := h.db.Where("chat_id = ? AND user_id = ?", chat.ID, currentUser.ID).First(&member).Error; err != nil {

		response.Forbidden(c, "您不是该群成员")

		return
	}
	items, err := h.joinRequestService().ListPending(c.Request.Context(), chat, member)
	if err != nil {

		if errors.Is(err, services.ErrChatPermissionDenied) {

			response.Forbidden(c, "没有权限查看加入请求")

		} else {

			response.ServerError(c, "获取加入请求失败")

		}

		return
	}
	result := make([]gin.H, 0, len(items))
	for _, item := range items {

		result = append(result, gin.H{

			"id": item.Request.ID,

			"user_id": item.User.UUID,

			"nickname": item.User.Nickname,

			"username": item.User.Username,

			"avatar": item.User.Avatar,

			"message": item.Request.Message,

			"created_at": item.Request.CreatedAt,
		})
	}
	response.Success(c, gin.H{

		"list": result,

		"total": len(result),
	})
}

// ReviewJoinRequest 审批加入请求
func (h *ChatHandler) ReviewJoinRequest(c *gin.Context) {
	chatID := c.Param("id")
	requestID := c.Param("request_id")
	userID := c.GetString("user_id")
	var req struct {
		Approve bool `json:"approve"` // true: 通过, false: 拒绝
	}
	if err := c.ShouldBindJSON(&req); err != nil {

		response.BadRequest(c, "参数错误")

		return
	}
	var chat models.Chat
	if err := h.db.Where("uuid = ?", chatID).First(&chat).Error; err != nil {

		response.NotFound(c, "群组不存在")

		return
	}
	// 获取当前用户
	var currentUser models.User
	if err := h.db.Where("uuid = ?", userID).First(&currentUser).Error; err != nil {

		response.NotFound(c, "用户不存在")

		return
	}
	// 检查权限
	var member models.ChatMember
	if err := h.db.Where("chat_id = ? AND user_id = ?", chat.ID, currentUser.ID).First(&member).Error; err != nil {

		response.Forbidden(c, "您不是该群成员")

		return
	}
	maxMembers := 0
	if req.Approve {

		maxMembers = h.getEffectiveMaxMembers(&chat)
	}
	reviewResult, err := h.joinRequestService().Review(

		c.Request.Context(),

		chat,

		currentUser,

		member,

		requestID,

		req.Approve,

		maxMembers,
	)
	if err != nil {

		switch {

		case errors.Is(err, services.ErrChatPermissionDenied):

			response.Forbidden(c, "没有权限审批加入请求")

		case errors.Is(err, services.ErrJoinRequestNotFound):

			response.NotFound(c, "请求不存在")

		case errors.Is(err, services.ErrJoinRequestWrongChat):

			response.BadRequest(c, "请求不属于该群组")

		case errors.Is(err, services.ErrJoinRequestReviewed):

			response.BadRequest(c, "该请求已处理")

		case errors.Is(err, services.ErrJoinRequestMemberLimit):

			if chat.Type == 3 {

				response.BadRequest(c, "该频道订阅者已达上限")

			} else {

				response.BadRequest(c, "该群组成员已达上限")

			}

		default:

			response.ServerError(c, "审批失败")

		}

		return
	}
	if req.Approve {

		if reviewResult.AlreadyMember {

			response.Success(c, gin.H{"message": "该用户已在群内"})

			return

		}
		requestUser := reviewResult.RequestUser

		chat.MemberCount++

		// 用户自己申请加入不发送系统消息，只有被邀请时才发送

		// 通知申请人

		if h.hub != nil {

			h.hub.Broadcast(&ws.BroadcastMessage{

				UserIDs: []string{requestUser.UUID},

				Data: map[string]interface{}{

					"type": "join_approved",

					"chat_id": chat.UUID,

					"name": chat.Name,
				},
			})

		}

		// 通知群组/频道成员，成员数已更新

		h.broadcastChatUpdate(&chat)

		response.Success(c, gin.H{"message": "已通过申请"})
	} else {

		// 通知申请人

		requestUser := reviewResult.RequestUser

		if requestUser.UUID != "" && h.hub != nil {

			h.hub.Broadcast(&ws.BroadcastMessage{

				UserIDs: []string{requestUser.UUID},

				Data: map[string]interface{}{

					"type": "join_rejected",

					"chat_id": chat.UUID,

					"name": chat.Name,
				},
			})

		}

		response.Success(c, gin.H{"message": "已拒绝申请"})
	}
}

// MuteMember 禁言成员
func (h *ChatHandler) MuteMember(c *gin.Context) {
	chatID := c.Param("id")
	userUUID := c.GetString("user_id")
	var req struct {
		UserID string `json:"user_id" binding:"required"` // 被禁言用户UUID

		Duration *int `json:"duration" binding:"required"` // 禁言时长（分钟），0表示永久
	}
	if err := c.ShouldBindJSON(&req); err != nil {

		response.BadRequest(c, "参数错误")

		return
	}
	duration := *req.Duration
	if duration < 0 {

		response.BadRequest(c, "禁言时长不能小于0")

		return
	}
	// 获取聊天
	var chat models.Chat
	if err := h.db.Where("uuid = ?", chatID).First(&chat).Error; err != nil {

		response.NotFound(c, "会话不存在")

		return
	}
	// 只有群组和频道可以禁言
	if chat.Type == 1 {

		response.BadRequest(c, "私聊不支持禁言")

		return
	}
	// 获取操作者
	var operator models.User
	if err := h.db.Where("uuid = ?", userUUID).First(&operator).Error; err != nil {

		response.Unauthorized(c, "用户不存在")

		return
	}
	// 获取操作者的成员信息
	var operatorMember models.ChatMember
	if err := h.db.Where("chat_id = ? AND user_id = ?", chat.ID, operator.ID).First(&operatorMember).Error; err != nil {

		response.Forbidden(c, "您不是该群成员")

		return
	}
	muteResult, err := h.chatMemberService().MuteMember(c.Request.Context(), chat, operatorMember, req.UserID, duration)
	if err != nil {

		switch {

		case errors.Is(err, services.ErrChatMemberTargetUserNotFound):

			response.NotFound(c, "目标用户不存在")

		case errors.Is(err, services.ErrChatMemberTargetNotFound):

			response.NotFound(c, "目标用户不是群成员")

		case errors.Is(err, services.ErrChatPermissionDenied):

			response.Forbidden(c, "没有权限执行此操作")

		case errors.Is(err, services.ErrChatPermissionTargetOwner):

			response.Forbidden(c, "不能禁言群主")

		case errors.Is(err, services.ErrChatPermissionAdminPeer):

			response.Forbidden(c, "管理员不能禁言其他管理员")

		default:

			response.ServerError(c, "禁言失败")

		}

		return
	}
	targetUser := muteResult.TargetUser
	// 发送系统消息
	durationText := "永久"
	if duration > 0 {

		if duration >= 1440 {

			durationText = fmt.Sprintf("%d 天", duration/1440)

		} else if duration >= 60 {

			durationText = fmt.Sprintf("%d 小时", duration/60)

		} else {

			durationText = fmt.Sprintf("%d 分钟", duration)

		}
	}
	systemMsg := fmt.Sprintf("%s 已被 %s 禁言 %s", targetUser.Nickname, operator.Nickname, durationText)
	h.sendSystemMessage(c.Request.Context(), &chat, systemMsg)
	// 广播禁言状态变更
	h.broadcastMuteStatusChanged(&chat, targetUser.UUID, true, muteResult.MuteEndTime)
	response.Success(c, gin.H{

		"message": "禁言成功",
	})
}

// UnmuteMember 解除禁言
func (h *ChatHandler) UnmuteMember(c *gin.Context) {
	chatID := c.Param("id")
	userUUID := c.GetString("user_id")
	var req struct {
		UserID string `json:"user_id" binding:"required"` // 被解禁用户UUID
	}
	if err := c.ShouldBindJSON(&req); err != nil {

		response.BadRequest(c, "参数错误")

		return
	}
	// 获取聊天
	var chat models.Chat
	if err := h.db.Where("uuid = ?", chatID).First(&chat).Error; err != nil {

		response.NotFound(c, "会话不存在")

		return
	}
	// 获取操作者
	var operator models.User
	if err := h.db.Where("uuid = ?", userUUID).First(&operator).Error; err != nil {

		response.Unauthorized(c, "用户不存在")

		return
	}
	// 获取操作者的成员信息
	var operatorMember models.ChatMember
	if err := h.db.Where("chat_id = ? AND user_id = ?", chat.ID, operator.ID).First(&operatorMember).Error; err != nil {

		response.Forbidden(c, "您不是该群成员")

		return
	}
	unmuteResult, err := h.chatMemberService().UnmuteMember(c.Request.Context(), chat, operatorMember, req.UserID)
	if err != nil {

		switch {

		case errors.Is(err, services.ErrChatPermissionDenied):

			response.Forbidden(c, "没有权限执行此操作")

		case errors.Is(err, services.ErrChatMemberTargetUserNotFound):

			response.NotFound(c, "目标用户不存在")

		default:

			response.ServerError(c, "解除禁言失败")

		}

		return
	}
	targetUser := unmuteResult.TargetUser
	// 发送系统消息
	systemMsg := fmt.Sprintf("%s 已被 %s 解除禁言", targetUser.Nickname, operator.Nickname)
	h.sendSystemMessage(c.Request.Context(), &chat, systemMsg)
	// 广播解禁状态变更
	h.broadcastMuteStatusChanged(&chat, targetUser.UUID, false, nil)
	response.Success(c, gin.H{

		"message": "解除禁言成功",
	})
}

// sendSystemMessage 发送系统消息的辅助方法
func (h *ChatHandler) sendSystemMessage(ctx context.Context, chat *models.Chat, content string) {
	if h.msgService == nil {

		return
	}
	// 批量获取所有成员 UUID（2 条 SQL 替代 N+1）
	var sysUserIDs []uint64
	h.db.Model(&models.ChatMember{}).Where("chat_id = ?", chat.ID).Pluck("user_id", &sysUserIDs)
	var targetUserIDs []string
	if len(sysUserIDs) > 0 {

		h.db.Model(&models.User{}).Where("id IN ?", sysUserIDs).Pluck("uuid", &targetUserIDs)
	}
	params := &services.SendMessageParams{

		ChatID: chat.UUID,

		Type: models.MsgTypeSystem,

		Content: map[string]interface{}{"text": content},
	}
	msg, err := h.msgService.SendMessage(ctx, params, "系统", "", "", "", targetUserIDs)
	if err != nil {

		return
	}
	// 更新 UserChat 系统消息预览
	previewText := normalizeStoredChatPreviewText(content, models.MsgTypeSystem)
	h.db.Model(&models.UserChat{}).
		Where("chat_id = ?", chat.ID).
		Updates(map[string]interface{}{

			"last_msg_text": previewText,

			"last_msg_type": models.MsgTypeSystem,

			"last_msg_time": msg.CreatedAt,

			"last_msg_seq": msg.Seq,

			"last_msg_sender": "",

			"last_msg_media_url": "",

			"sort_time": msg.CreatedAt,
		})
}

// broadcastMuteStatusChanged 广播禁言状态变更
func (h *ChatHandler) broadcastMuteStatusChanged(chat *models.Chat, targetUserUUID string, isMuted bool, muteEndTime interface{}) {
	if h.hub == nil {

		return
	}
	// 获取所有成员的 UUID
	var memberUserIDs []uint64
	h.db.Model(&models.ChatMember{}).Where("chat_id = ?", chat.ID).Pluck("user_id", &memberUserIDs)
	if len(memberUserIDs) == 0 {

		return
	}
	var memberUUIDs []string
	h.db.Model(&models.User{}).Where("id IN ?", memberUserIDs).Pluck("uuid", &memberUUIDs)
	if len(memberUUIDs) == 0 {

		return
	}
	// 广播给所有成员
	h.hub.Broadcast(&ws.BroadcastMessage{

		UserIDs: memberUUIDs,

		Data: map[string]interface{}{

			"type": "member_mute_status_changed",

			"message": map[string]interface{}{

				"chat_id": chat.UUID,

				"user_id": targetUserUUID,

				"is_muted": isMuted,

				"mute_end_time": muteEndTime,
			},
		},
	})
}

// broadcastChatPermissionsUpdated 广播聊天权限更新
func (h *ChatHandler) broadcastChatPermissionsUpdated(chat *models.Chat) {
	if h.hub == nil {

		return
	}
	// 获取所有成员的 UUID
	var memberUserIDs []uint64
	h.db.Model(&models.ChatMember{}).Where("chat_id = ?", chat.ID).Pluck("user_id", &memberUserIDs)
	if len(memberUserIDs) == 0 {

		return
	}
	var memberUUIDs []string
	h.db.Model(&models.User{}).Where("id IN ?", memberUserIDs).Pluck("uuid", &memberUUIDs)
	if len(memberUUIDs) == 0 {

		return
	}
	// 广播给所有成员
	h.hub.Broadcast(&ws.BroadcastMessage{

		UserIDs: memberUUIDs,

		Data: map[string]interface{}{

			"type": "chat_permissions_updated",

			"message": map[string]interface{}{

				"chat_id": chat.UUID,

				"can_send_message": chat.CanSendMessage,

				"can_send_media": chat.CanSendMedia,

				"can_send_links": chat.CanSendLinks,

				"can_add_members": chat.CanAddMembers,

				"can_pin_messages": chat.CanPinMessages,

				"allow_anonymous": chat.AllowAnonymous,

				"allow_forward": chat.AllowForward,

				"allow_view_history": chat.AllowViewHistory,

				"member_protection": chat.MemberProtection,

				"join_approval": chat.JoinApproval,
			},
		},
	})
}

// GetMemberMuteStatus 获取成员禁言状态
func (h *ChatHandler) GetMemberMuteStatus(c *gin.Context) {
	chatID := c.Param("id")
	userID := c.Query("user_id")
	var chat models.Chat
	if err := h.db.Where("uuid = ?", chatID).First(&chat).Error; err != nil {

		response.NotFound(c, "会话不存在")

		return
	}
	var targetUser models.User
	if err := h.db.Where("uuid = ?", userID).First(&targetUser).Error; err != nil {

		response.NotFound(c, "用户不存在")

		return
	}
	var member models.ChatMember
	if err := h.db.Where("chat_id = ? AND user_id = ?", chat.ID, targetUser.ID).First(&member).Error; err != nil {

		response.NotFound(c, "用户不是群成员")

		return
	}
	// 检查禁言是否过期
	isMuted := member.IsMuted
	if isMuted && member.MuteEndTime != nil && time.Now().After(*member.MuteEndTime) {

		// 禁言已过期，自动解除

		if err := h.db.Model(&member).Updates(map[string]interface{}{

			"is_muted": false,

			"mute_end_time": nil,
		}).Error; err != nil {

			response.ServerError(c, "更新禁言状态失败")

			return

		}
		isMuted = false
	}
	response.Success(c, gin.H{

		"is_muted": isMuted,

		"mute_end_time": member.MuteEndTime,
	})
}

// broadcastChatUpdate 广播群组/频道更新（成员数变化等）
func (h *ChatHandler) broadcastChatUpdate(chat *models.Chat) {
	if h.hub == nil {

		return
	}
	// 获取所有成员的 UUID
	var memberUserIDs []uint64
	h.db.Model(&models.ChatMember{}).Where("chat_id = ?", chat.ID).Pluck("user_id", &memberUserIDs)
	if len(memberUserIDs) == 0 {

		return
	}
	var memberUUIDs []string
	h.db.Model(&models.User{}).Where("id IN ?", memberUserIDs).Pluck("uuid", &memberUUIDs)
	if len(memberUUIDs) == 0 {

		return
	}
	// 重新加载最新的群组信息
	h.db.First(chat, chat.ID)
	// 广播给所有成员
	h.hub.Broadcast(&ws.BroadcastMessage{

		UserIDs: memberUUIDs,

		Data: map[string]interface{}{

			"type": "chat_update",

			"chat_id": chat.UUID,

			"member_count": chat.MemberCount,

			"name": chat.Name,

			"description": chat.Description,

			"avatar": chat.Avatar,

			"owner_id": chat.OwnerID,

			"updated_at": chat.UpdatedAt,
		},
	})
}
func (h *ChatHandler) broadcastMemberNicknameChanged(
	ctx context.Context,
	chat *models.Chat,
	targetUserUUID string,
	nickname string) {
	if h == nil || chat == nil {

		return
	}
	var memberUserIDs []uint64
	h.db.Model(&models.ChatMember{}).Where("chat_id = ?", chat.ID).Pluck("user_id", &memberUserIDs)
	deleteUserChatListHotCache(ctx, h.cache, memberUserIDs...)
	if h.hub == nil || len(memberUserIDs) == 0 {

		return
	}
	var memberUUIDs []string
	h.db.Model(&models.User{}).Where("id IN ?", memberUserIDs).Pluck("uuid", &memberUUIDs)
	h.hub.Broadcast(&ws.BroadcastMessage{

		UserIDs: memberUUIDs,

		Data: map[string]interface{}{

			"type": "member_nickname_changed",

			"chat_id": chat.UUID,

			"user_id": targetUserUUID,

			"nickname": nickname,
		},
	})
}

// TogglePin 置顶/取消置顶聊天
func (h *ChatHandler) TogglePin(c *gin.Context) {
	userID := c.GetString("user_id")
	chatUUID := c.Param("id")
	var user models.User
	if err := h.db.Where("uuid = ?", userID).First(&user).Error; err != nil {

		response.Error(c, http.StatusUnauthorized, "请先登录")

		return
	}
	var chat models.Chat
	if err := h.db.Where("uuid = ?", chatUUID).First(&chat).Error; err != nil {

		response.Error(c, http.StatusNotFound, "会话不存在")

		return
	}
	// 查找用户的会话记录
	var userChat models.UserChat
	if err := h.db.Where("user_id = ? AND chat_id = ?", user.ID, chat.ID).First(&userChat).Error; err != nil {

		response.Error(c, http.StatusNotFound, "会话不存在")

		return
	}
	// 置顶数量限制
	newPinned := !userChat.IsPinned
	if newPinned {
		var pinnedCount int64

		h.db.Model(&models.UserChat{}).Where("user_id = ? AND is_pinned = ?", user.ID, true).Count(&pinnedCount)

		if int(pinnedCount) >= getPinnedChatLimit(h.db, user.ID) {

			response.Error(c, http.StatusBadRequest, "置顶数量已达上限")

			return

		}
	}
	// 切换置顶状态
	now := time.Now()
	if err := h.db.Model(&userChat).Updates(map[string]interface{}{

		"is_pinned": newPinned,

		"updated_at": now,
	}).Error; err != nil {

		response.Error(c, http.StatusInternalServerError, "操作失败")

		return
	}
	userChat.IsPinned = newPinned
	userChat.UpdatedAt = now
	deleteUserChatListHotCache(c.Request.Context(), h.cache, user.ID)
	sendUserChatStateChanged(

		h.hub,

		user.UUID,

		chat.UUID,

		&userChat,

		currentLastReadSeq(h.db, chat.ID, user.ID),

		"is_pinned",
	)
	response.Success(c, gin.H{

		"is_pinned": newPinned,
	})
}

// ToggleMuteChat 静音/取消静音聊天
func (h *ChatHandler) ToggleMuteChat(c *gin.Context) {
	userID := c.GetString("user_id")
	chatUUID := c.Param("id")
	var user models.User
	if err := h.db.Where("uuid = ?", userID).First(&user).Error; err != nil {

		response.Error(c, http.StatusUnauthorized, "请先登录")

		return
	}
	var chat models.Chat
	if err := h.db.Where("uuid = ?", chatUUID).First(&chat).Error; err != nil {

		response.Error(c, http.StatusNotFound, "会话不存在")

		return
	}
	// 查找用户的会话记录
	var userChat models.UserChat
	if err := h.db.Where("user_id = ? AND chat_id = ?", user.ID, chat.ID).First(&userChat).Error; err != nil {

		response.Error(c, http.StatusNotFound, "会话不存在")

		return
	}
	// 切换静音状态
	newMuted := !userChat.IsMuted
	now := time.Now()
	if err := h.db.Model(&userChat).Updates(map[string]interface{}{

		"is_muted": newMuted,

		"updated_at": now,
	}).Error; err != nil {

		response.Error(c, http.StatusInternalServerError, "操作失败")

		return
	}
	userChat.IsMuted = newMuted
	userChat.UpdatedAt = now
	deleteUserChatListHotCache(c.Request.Context(), h.cache, user.ID)
	sendUserChatStateChanged(

		h.hub,

		user.UUID,

		chat.UUID,

		&userChat,

		currentLastReadSeq(h.db, chat.ID, user.ID),

		"is_muted",
	)
	response.Success(c, gin.H{

		"is_muted": newMuted,
	})
}

// ToggleUnread 标记已读/未读
func (h *ChatHandler) ToggleUnread(c *gin.Context) {
	userID := c.GetString("user_id")
	chatUUID := c.Param("id")
	var user models.User
	if err := h.db.Where("uuid = ?", userID).First(&user).Error; err != nil {

		response.Error(c, http.StatusUnauthorized, "请先登录")

		return
	}
	var chat models.Chat
	if err := h.db.Where("uuid = ?", chatUUID).First(&chat).Error; err != nil {

		response.Error(c, http.StatusNotFound, "会话不存在")

		return
	}
	// 查找用户的会话记录
	var userChat models.UserChat
	if err := h.db.Where("user_id = ? AND chat_id = ?", user.ID, chat.ID).First(&userChat).Error; err != nil {

		response.Error(c, http.StatusNotFound, "会话不存在")

		return
	}
	// 切换未读状态：如果当前已读(unread=0)则标记为未读(unread=1)，否则标记为已读(unread=0)
	var newUnreadCount int
	if userChat.UnreadCount == 0 {

		newUnreadCount = 1 // 标记为未读
	} else {

		newUnreadCount = 0 // 标记为已读
	}
	now := time.Now()
	if err := h.db.Model(&userChat).Updates(map[string]interface{}{

		"unread_count": newUnreadCount,

		"has_mention": false,

		"updated_at": now,
	}).Error; err != nil {

		response.Error(c, http.StatusInternalServerError, "操作失败")

		return
	}
	userChat.UnreadCount = newUnreadCount
	userChat.HasMention = false
	userChat.UpdatedAt = now
	deleteUserChatListHotCache(c.Request.Context(), h.cache, user.ID)
	sendUserChatStateChanged(

		h.hub,

		user.UUID,

		chat.UUID,

		&userChat,

		currentLastReadSeq(h.db, chat.ID, user.ID),

		"unread_count",

		"has_mention",
	)
	response.Success(c, gin.H{

		"unread_count": newUnreadCount,
	})
}

// ClearChatHistory 清空聊天记录（仅对当前用户可见）
func (h *ChatHandler) ClearChatHistory(c *gin.Context) {
	userID := c.GetString("user_id")
	chatUUID := c.Param("id")
	var user models.User
	if err := h.db.Where("uuid = ?", userID).First(&user).Error; err != nil {

		response.Error(c, http.StatusUnauthorized, "请先登录")

		return
	}
	var chat models.Chat
	if err := h.db.Where("uuid = ?", chatUUID).First(&chat).Error; err != nil {

		response.Error(c, http.StatusNotFound, "会话不存在")

		return
	}
	// 查找用户的会话记录
	var userChat models.UserChat
	if err := h.db.Where("user_id = ? AND chat_id = ?", user.ID, chat.ID).First(&userChat).Error; err != nil {

		response.Error(c, http.StatusNotFound, "会话不存在")

		return
	}
	// 删除 MongoDB 中该聊天的消息（仅属于当前用户可见的）
	// 实际上 TG 风格是清空本地显示，不删除对方的消息
	// 这里我们通过更新 UserChat 的 cleared_at 时间戳来实现
	// 前端加载消息时只显示 cleared_at 之后的消息
	now := time.Now()
	if err := h.db.Model(&userChat).Updates(chatHistoryClearUpdates(now)).Error; err != nil {

		response.Error(c, http.StatusInternalServerError, "清空失败")

		return
	}
	deleteUserChatListHotCache(c.Request.Context(), h.cache, user.ID)
	if h.msgService != nil {

		h.msgService.InvalidateMessageWindowCache(c.Request.Context(), chat.UUID)
	}
	h.broadcastChatHistoryCleared(chat.UUID, []string{userID}, user.UUID, now, false)
	response.Success(c, gin.H{

		"message": "聊天记录已清空",
	})
}

// ClearChatHistoryForBoth 双向清空聊天记录（TG 模式，仅私聊）
func (h *ChatHandler) ClearChatHistoryForBoth(c *gin.Context) {
	userID := c.GetString("user_id")
	chatUUID := c.Param("id")
	var user models.User
	if err := h.db.Where("uuid = ?", userID).First(&user).Error; err != nil {

		response.Error(c, http.StatusUnauthorized, "请先登录")

		return
	}
	var chat models.Chat
	if err := h.db.Where("uuid = ?", chatUUID).First(&chat).Error; err != nil {

		response.Error(c, http.StatusNotFound, "会话不存在")

		return
	}
	if chat.Type != 1 {

		response.BadRequest(c, "仅个人会话支持双向删除")

		return
	}
	type memberRow struct {
		UserID uint64 `gorm:"column:user_id"`

		UserUUID string `gorm:"column:user_uuid"`
	}
	var members []memberRow
	if err := h.db.Table("chat_members cm").
		Select("cm.user_id, u.uuid AS user_uuid").
		Joins("JOIN users u ON u.id = cm.user_id").
		Where("cm.chat_id = ?", chat.ID).
		Find(&members).Error; err != nil {

		response.ServerError(c, "读取会话成员失败")

		return
	}
	if len(members) == 0 {

		response.Forbidden(c, "无权操作该会话")

		return
	}
	memberIDs := make([]uint64, 0, len(members))
	memberUUIDs := make([]string, 0, len(members))
	isMember := false
	for _, m := range members {

		memberIDs = append(memberIDs, m.UserID)

		if m.UserUUID != "" {

			memberUUIDs = append(memberUUIDs, m.UserUUID)

		}

		if m.UserID == user.ID {

			isMember = true

		}
	}
	if !isMember {

		response.Forbidden(c, "无权操作该会话")

		return
	}
	now := time.Now()
	if err := h.db.Transaction(func(tx *gorm.DB) error {

		return tx.Model(&models.UserChat{}).
			Where("chat_id = ? AND user_id IN ?", chat.ID, memberIDs).
			Updates(chatHistoryClearUpdates(now)).Error
	}); err != nil {

		response.ServerError(c, "双向删除失败")

		return
	}
	deleteUserChatListHotCache(c.Request.Context(), h.cache, memberIDs...)
	if h.msgService != nil {

		h.msgService.InvalidateMessageWindowCache(c.Request.Context(), chat.UUID)
	}
	h.broadcastChatHistoryCleared(chat.UUID, memberUUIDs, user.UUID, now, true)
	response.Success(c, gin.H{

		"message": "已为双方清空聊天记录",
	})
}
func chatHistoryClearUpdates(clearedAt time.Time) map[string]interface{} {
	return map[string]interface{}{

		"cleared_at": clearedAt,

		"last_msg_id": uint64(0),

		"last_msg_seq": uint64(0),

		"last_msg_time": nil,

		"last_msg_text": "",

		"last_msg_type": 0,

		"last_msg_sender": "",

		"last_msg_media_url": "",

		"unread_count": 0,

		"has_mention": false,
	}
}
func (h *ChatHandler) broadcastChatHistoryCleared(
	chatUUID string,
	targetUserUUIDs []string,
	operatorUUID string,
	clearedAt time.Time,
	forBoth bool) {
	if h.hub == nil || len(targetUserUUIDs) == 0 {

		return
	}
	seen := make(map[string]struct{}, len(targetUserUUIDs))
	userUUIDs := make([]string, 0, len(targetUserUUIDs))
	for _, uid := range targetUserUUIDs {

		if uid == "" {

			continue

		}

		if _, ok := seen[uid]; ok {

			continue

		}

		seen[uid] = struct{}{}
		userUUIDs = append(userUUIDs, uid)
	}
	if len(userUUIDs) == 0 {

		return
	}
	h.hub.SendToUsers(userUUIDs, map[string]interface{}{

		"type": "chat_history_cleared",

		"chat_id": chatUUID,

		"for_both": forBoth,

		"operator_id": operatorUUID,

		"cleared_at": clearedAt.UTC().Format(time.RFC3339),
	})
}

// SearchMessages 搜索消息
type chatAutoMessagePayload struct {
	Title           *string                 `json:"title"`
	Content         *string                 `json:"content"`
	MessageType     *int                    `json:"message_type"`
	Media           *map[string]interface{} `json:"media"`
	ScheduleType    *string                 `json:"schedule_type"`
	IntervalSeconds *int                    `json:"interval_seconds"`
	IntervalMinutes *int                    `json:"interval_minutes"`
	SendAt          *string                 `json:"send_at"`
	DailyTime       *string                 `json:"daily_time"`
	Enabled         *bool                   `json:"enabled"`
}

func (h *ChatHandler) ListAutoMessages(c *gin.Context) {
	chat, _, ok := h.requireChatOwner(c)
	if !ok {

		return
	}
	var items []models.ChatAutoMessage
	if err := h.db.Where("chat_id = ?", chat.ID).Order("id DESC").Find(&items).Error; err != nil {

		response.ServerError(c, "获取定时群消息失败")

		return
	}
	response.Success(c, items)
}

// ClearGroupMessages clears all messages in a group or channel for every member.
func (h *ChatHandler) ClearGroupMessages(c *gin.Context) {
	chat, user, ok := h.requireChatOwnerWithMessage(c, "只有群主或频道主可以清空消息")
	if !ok {

		return
	}
	type memberRow struct {
		UserID uint64 `gorm:"column:user_id"`

		UserUUID string `gorm:"column:user_uuid"`
	}
	var members []memberRow
	if err := h.db.Table("chat_members cm").
		Select("cm.user_id, u.uuid AS user_uuid").
		Joins("JOIN users u ON u.id = cm.user_id").
		Where("cm.chat_id = ?", chat.ID).
		Find(&members).Error; err != nil {

		response.ServerError(c, "读取群成员失败")

		return
	}
	memberIDs := make([]uint64, 0, len(members))
	memberUUIDs := make([]string, 0, len(members))
	for _, member := range members {

		memberIDs = append(memberIDs, member.UserID)

		if member.UserUUID != "" {

			memberUUIDs = append(memberUUIDs, member.UserUUID)

		}
	}
	cutoff := time.Now()
	hadPinnedMessage := chat.PinnedMessageID != ""
	if err := h.db.Transaction(func(tx *gorm.DB) error {

		if len(memberIDs) > 0 {

			if err := tx.Model(&models.UserChat{}).
				Where("chat_id = ? AND user_id IN ?", chat.ID, memberIDs).
				Updates(map[string]interface{}{

					"cleared_at": cutoff,

					"last_msg_text": "",

					"last_msg_sender": "",

					"last_msg_media_url": "",

					"last_msg_seq": 0,

					"last_msg_time": cutoff,

					"unread_count": 0,

					"has_mention": false,
				}).Error; err != nil {

				return err

			}

		}

		return tx.Model(&models.Chat{}).
			Where("id = ?", chat.ID).
			Updates(map[string]interface{}{

				"pinned_message_id": "",

				"pinned_message_text": "",

				"pinned_message_by": 0,

				"pinned_message_at": nil,

				"updated_at": cutoff,
			}).Error
	}); err != nil {

		response.ServerError(c, "更新群会话失败")

		return
	}
	if len(memberIDs) > 0 {

		deleteUserChatListHotCache(c.Request.Context(), h.cache, memberIDs...)
	}
	deletedCount := int64(0)
	cleanupStatus := "ok"
	if h.msgService != nil {
		var err error

		deletedCount, err = h.msgService.DeleteAllMessagesForChat(c.Request.Context(), chat.UUID, cutoff)

		if err != nil {

			log.Printf("[Chat] clear group messages mongo delete failed chat=%s cutoff=%s err=%v", chat.UUID, cutoff.Format(time.RFC3339Nano), err)
			cleanupStatus = "failed"

		}
	}
	if hadPinnedMessage && h.hub != nil {

		h.hub.SendToChat(chat.UUID, map[string]interface{}{

			"type": "message_unpinned",

			"chat_id": chat.UUID,

			"unpinned_by": user.UUID,
		}, "")
	}
	h.broadcastChatHistoryCleared(chat.UUID, memberUUIDs, user.UUID, cutoff, true)
	response.Success(c, gin.H{

		"deleted_count": deletedCount,

		"cleared_at": cutoff.UTC().Format(time.RFC3339),

		"cleanup_status": cleanupStatus,
	})
}
func (h *ChatHandler) CreateAutoMessage(c *gin.Context) {
	chat, currentUser, ok := h.requireChatOwner(c)
	if !ok {

		return
	}
	var req chatAutoMessagePayload
	if err := c.ShouldBindJSON(&req); err != nil {

		response.BadRequest(c, "参数错误")

		return
	}
	item, err := h.buildAutoMessageFromPayload(req, nil)
	if err != nil {

		response.BadRequest(c, err.Error())

		return
	}
	now := time.Now()
	item.ChatID = chat.ID
	item.CreatedBy = currentUser.ID
	item.CreatedAt = now
	item.UpdatedAt = now
	if err := h.db.Create(&item).Error; err != nil {

		response.ServerError(c, "创建定时群消息失败")

		return
	}
	response.Success(c, item)
}
func (h *ChatHandler) UpdateAutoMessage(c *gin.Context) {
	chat, _, ok := h.requireChatOwner(c)
	if !ok {

		return
	}
	id, err := strconv.ParseUint(c.Param("auto_message_id"), 10, 64)
	if err != nil || id == 0 {

		response.BadRequest(c, "参数错误")

		return
	}
	var existing models.ChatAutoMessage
	if err := h.db.Where("id = ? AND chat_id = ?", id, chat.ID).First(&existing).Error; err != nil {

		response.NotFound(c, "定时群消息不存在")

		return
	}
	var req chatAutoMessagePayload
	if err := c.ShouldBindJSON(&req); err != nil {

		response.BadRequest(c, "参数错误")

		return
	}
	item, err := h.buildAutoMessageFromPayload(req, &existing)
	if err != nil {

		response.BadRequest(c, err.Error())

		return
	}
	item.UpdatedAt = time.Now()
	if err := h.db.Model(&existing).Updates(map[string]interface{}{

		"title": item.Title,

		"content": item.Content,

		"message_type": item.MessageType,

		"media": item.Media,

		"schedule_type": item.ScheduleType,

		"interval_seconds": item.IntervalSeconds,

		"send_at": item.SendAt,

		"daily_time": item.DailyTime,

		"next_run_at": item.NextRunAt,

		"locked_run_at": nil,

		"enabled": item.Enabled,

		"updated_at": item.UpdatedAt,
	}).Error; err != nil {

		response.ServerError(c, "更新定时群消息失败")

		return
	}
	if err := h.db.Where("id = ?", existing.ID).First(&existing).Error; err != nil {

		response.ServerError(c, "更新定时群消息失败")

		return
	}
	response.Success(c, existing)
}
func (h *ChatHandler) DeleteAutoMessage(c *gin.Context) {
	chat, _, ok := h.requireChatOwner(c)
	if !ok {

		return
	}
	id, err := strconv.ParseUint(c.Param("auto_message_id"), 10, 64)
	if err != nil || id == 0 {

		response.BadRequest(c, "参数错误")

		return
	}
	if err := h.db.Where("id = ? AND chat_id = ?", id, chat.ID).Delete(&models.ChatAutoMessage{}).Error; err != nil {

		response.ServerError(c, "删除定时群消息失败")

		return
	}
	response.Success(c, gin.H{"deleted": true})
}
func (h *ChatHandler) requireChatOwner(c *gin.Context) (models.Chat, models.User, bool) {
	return h.requireChatOwnerWithMessage(c, "只有群主或频道主可以设置定时消息")
}
func (h *ChatHandler) requireChatOwnerWithMessage(c *gin.Context, forbiddenMessage string) (models.Chat, models.User, bool) {
	chatID := c.Param("id")
	userID := c.GetString("user_id")
	var chat models.Chat
	if err := h.db.Where("uuid = ?", chatID).First(&chat).Error; err != nil {

		response.NotFound(c, "群组不存在")

		return models.Chat{}, models.User{}, false
	}
	if chat.Type != 2 && chat.Type != 3 {

		response.BadRequest(c, "仅群组和频道支持该功能")

		return models.Chat{}, models.User{}, false
	}
	var user models.User
	if err := h.db.Where("uuid = ?", userID).First(&user).Error; err != nil {

		response.NotFound(c, "用户不存在")

		return models.Chat{}, models.User{}, false
	}
	var member models.ChatMember
	if err := h.db.Where("chat_id = ? AND user_id = ?", chat.ID, user.ID).First(&member).Error; err != nil {

		response.Forbidden(c, "您不是该会话成员")

		return models.Chat{}, models.User{}, false
	}
	if member.Role < 2 {

		if forbiddenMessage == "" {

			forbiddenMessage = "只有群主或频道主可以操作"

		}

		response.Forbidden(c, forbiddenMessage)

		return models.Chat{}, models.User{}, false
	}
	return chat, user, true
}
func (h *ChatHandler) buildAutoMessageFromPayload(req chatAutoMessagePayload, existing *models.ChatAutoMessage) (models.ChatAutoMessage, error) {
	item := models.ChatAutoMessage{

		ScheduleType: models.ChatAutoMessageScheduleOnce,

		Enabled: true,
	}
	if existing != nil {

		item = *existing
	}
	if req.Title != nil {

		item.Title = strings.TrimSpace(*req.Title)
	}
	if req.Content != nil {

		item.Content = strings.TrimSpace(*req.Content)
	}
	if item.Content != "" {

		filtered, blocked := filterContentWithDB(h.db, item.Content)

		if blocked {

			return item, fmt.Errorf("定时消息包含违禁词，无法保存")

		}

		item.Content = filtered
	}
	if req.MessageType != nil {

		item.MessageType = *req.MessageType
	}
	if item.MessageType == 0 {

		item.MessageType = models.MsgTypeText
	}
	if req.Media != nil {

		mediaBytes, err := json.Marshal(*req.Media)

		if err != nil {

			return item, fmt.Errorf("media 格式错误")

		}

		item.Media = mediaBytes
	}
	if item.MessageType != models.MsgTypeText && item.MessageType != models.MsgTypeImage {

		return item, fmt.Errorf("message_type 仅支持文字和图片")
	}
	if item.MessageType == models.MsgTypeText && item.Content == "" {

		return item, fmt.Errorf("定时消息内容不能为空")
	}
	if item.MessageType == models.MsgTypeText {

		item.Media = nil
	}
	if item.MessageType == models.MsgTypeImage {
		media := autoMessageMediaMap(item.Media)
		mediaURL := strings.TrimSpace(fmt.Sprint(media["url"]))
		normalizedURL, ok := normalizeAutoMessageImageURL(mediaURL)

		if mediaURL == "" {

			return item, fmt.Errorf("图片定时消息需要图片")

		}

		if !ok {

			return item, fmt.Errorf("图片地址无效")

		}

		media["url"] = normalizedURL

		mediaBytes, err := json.Marshal(media)

		if err != nil {

			return item, fmt.Errorf("media format error")

		}

		item.Media = mediaBytes
	}
	if req.ScheduleType != nil {

		item.ScheduleType = strings.ToLower(strings.TrimSpace(*req.ScheduleType))
	}
	switch item.ScheduleType {
	case models.ChatAutoMessageScheduleOnce, models.ChatAutoMessageScheduleDaily, models.ChatAutoMessageScheduleInterval:
	default:

		return item, fmt.Errorf("schedule_type 仅支持 once、daily、interval")
	}
	if req.IntervalSeconds != nil {

		item.IntervalSeconds = *req.IntervalSeconds
	}
	if req.IntervalMinutes != nil && *req.IntervalMinutes > 0 {

		item.IntervalSeconds = *req.IntervalMinutes * 60
	}
	if req.DailyTime != nil {

		item.DailyTime = strings.TrimSpace(*req.DailyTime)
	}
	if req.SendAt != nil {

		parsed, err := time.Parse(time.RFC3339, strings.TrimSpace(*req.SendAt))

		if err != nil {

			return item, fmt.Errorf("send_at 必须是 RFC3339 时间")

		}

		item.SendAt = &parsed
	}
	if req.Enabled != nil {

		item.Enabled = *req.Enabled
	}
	normalizeAutoMessageScheduleFields(&item)
	now := time.Now()
	next, err := nextAutoMessageRunForSave(item, now)
	if err != nil {

		return item, err
	}
	item.NextRunAt = next
	item.LockedRunAt = nil
	return item, nil
}
func normalizeAutoMessageScheduleFields(item *models.ChatAutoMessage) {
	if item == nil {

		return
	}
	switch item.ScheduleType {
	case models.ChatAutoMessageScheduleOnce:

		item.IntervalSeconds = 0

		item.DailyTime = ""
	case models.ChatAutoMessageScheduleDaily:

		item.IntervalSeconds = 0

		item.SendAt = nil
	case models.ChatAutoMessageScheduleInterval:

		item.SendAt = nil

		item.DailyTime = ""
	}
}
func autoMessageMediaMap(raw []byte) map[string]interface{} {
	if len(raw) == 0 {

		return map[string]interface{}{}
	}
	var media map[string]interface{}
	if err := json.Unmarshal(raw, &media); err != nil || media == nil {

		return map[string]interface{}{}
	}
	return media
}
func normalizeAutoMessageImageURL(raw string) (string, bool) {
	value := strings.TrimSpace(raw)
	if value == "" {

		return "", false
	}
	parsed, err := url.Parse(value)
	if err != nil {

		return "", false
	}
	if parsed.Scheme != "" || parsed.Host != "" {

		return "", false
	}
	pathValue := parsed.Path
	if pathValue == "" && parsed.Scheme == "" && parsed.Host == "" {

		pathValue = value
	}
	unescaped, err := url.PathUnescape(pathValue)
	if err != nil {

		return "", false
	}
	normalized := strings.TrimSpace(unescaped)
	if strings.HasPrefix(normalized, "uploads/") {

		normalized = "/" + normalized
	}
	if strings.Contains(normalized, "..") {

		return "", false
	}
	if !strings.HasPrefix(normalized, "/uploads/images/") {

		return "", false
	}
	return normalized, true
}
func nextAutoMessageRunForSave(item models.ChatAutoMessage, now time.Time) (*time.Time, error) {
	if !item.Enabled {

		return nil, nil
	}
	switch item.ScheduleType {
	case models.ChatAutoMessageScheduleOnce:

		if item.SendAt != nil && item.SendAt.After(now) {
			next := *item.SendAt

			return &next, nil

		}
		next := now

		return &next, nil
	case models.ChatAutoMessageScheduleInterval:

		if item.IntervalSeconds < 60 {

			return nil, fmt.Errorf("interval 间隔不能小于 60 秒")

		}
		next := now.Add(time.Duration(item.IntervalSeconds) * time.Second)

		return &next, nil
	case models.ChatAutoMessageScheduleDaily:

		if strings.TrimSpace(item.DailyTime) == "" {

			return nil, fmt.Errorf("daily 需要 daily_time，例如 09:30")

		}
		next := services.NextChatAutoMessageRun(item, now)

		if next == nil {

			return nil, fmt.Errorf("daily_time 格式错误，应为 HH:mm")

		}

		return next, nil
	default:

		return nil, fmt.Errorf("schedule_type 仅支持 once、daily、interval")
	}
}
func supportedSearchMessageType(messageType int) bool {
	switch messageType {
	case models.MsgTypeText,

		models.MsgTypeImage,

		models.MsgTypeVideo,

		models.MsgTypeVoice,

		models.MsgTypeFile,

		models.MsgTypeLocation,

		models.MsgTypeSticker,

		models.MsgTypeContact,

		models.MsgTypeCall,

		models.MsgTypeRedPacket,

		models.MsgTypeTransfer,

		models.MsgTypeForwardBundle,

		models.MsgTypeSystem:

		return true
	default:

		return false
	}
}
func parseMessageSearchTime(raw string) (*time.Time, error) {
	raw = strings.TrimSpace(raw)
	if raw == "" {

		return nil, nil
	}
	parsed, err := time.Parse(time.RFC3339, raw)
	if err != nil {

		return nil, err
	}
	parsed = parsed.UTC()
	return &parsed, nil
}
func (h *ChatHandler) SearchMessages(c *gin.Context) {
	userID := c.GetString("user_id")
	chatUUID := c.Param("id")
	keyword := strings.TrimSpace(c.Query("keyword"))
	senderID := strings.TrimSpace(c.Query("sender_id"))
	messageTypeRaw := strings.TrimSpace(c.Query("message_type"))
	startAt, startErr := parseMessageSearchTime(c.Query("start_at"))
	endAt, endErr := parseMessageSearchTime(c.Query("end_at"))
	if startErr != nil || endErr != nil {

		response.BadRequest(c, "日期筛选格式错误")

		return
	}
	if startAt != nil && endAt != nil && !endAt.After(*startAt) {

		response.BadRequest(c, "结束日期必须晚于开始日期")

		return
	}
	var messageType *int
	if messageTypeRaw != "" {

		value, err := strconv.Atoi(messageTypeRaw)

		if err != nil || !supportedSearchMessageType(value) {

			response.BadRequest(c, "不支持的消息类型")

			return

		}
		messageType = &value
	}
	if keyword == "" && senderID == "" && messageType == nil && startAt == nil && endAt == nil {

		response.BadRequest(c, "请输入关键词或选择筛选条件")

		return
	}
	var user models.User
	if err := h.db.Where("uuid = ?", userID).First(&user).Error; err != nil {

		response.Error(c, http.StatusUnauthorized, "请先登录")

		return
	}
	var chat models.Chat
	if err := h.db.Where("uuid = ?", chatUUID).First(&chat).Error; err != nil {

		response.Error(c, http.StatusNotFound, "会话不存在")

		return
	}
	var memberCount int64
	h.db.Model(&models.ChatMember{}).Where("chat_id = ? AND user_id = ?", chat.ID, user.ID).Count(&memberCount)
	if memberCount == 0 {

		response.Forbidden(c, "无权搜索该会话消息")

		return
	}
	if senderID != "" {
		var senderCount int64

		h.db.Table("chat_members cm").
			Joins("JOIN users u ON u.id = cm.user_id").
			Where("cm.chat_id = ? AND u.uuid = ?", chat.ID, senderID).
			Count(&senderCount)

		if senderCount == 0 {

			response.BadRequest(c, "筛选联系人不属于该会话")

			return

		}
	}
	// 从 MongoDB 搜索消息
	messages, err := h.msgService.SearchMessagesForUserWithOptions(

		c.Request.Context(),

		chat.UUID,

		user.UUID,

		services.MessageSearchOptions{

			Keyword: keyword,

			SenderID: senderID,

			MessageType: messageType,

			StartAt: startAt,

			EndAt: endAt,
		},

		50,
	)
	if err != nil {

		response.Error(c, http.StatusInternalServerError, "搜索失败")

		return
	}
	response.Success(c, gin.H{

		"list": messages,

		"total": len(messages),
	})
}
