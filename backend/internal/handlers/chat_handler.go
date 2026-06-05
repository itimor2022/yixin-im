package handlers

import (
	"encoding/json"
	"context"
	"fmt"
	"log"
	"net/http"
	"strconv"
	"strings"
	"time"

	"gaoranim/internal/cache"
	"gaoranim/internal/models"
	"gaoranim/internal/privacy"
	"gaoranim/internal/services"
	"gaoranim/internal/textutil"
	"gaoranim/internal/ws"
	"gaoranim/pkg/response"

	"github.com/gin-gonic/gin"
	"github.com/google/uuid"
	"gorm.io/gorm"
	"gorm.io/gorm/clause"
)

// ChatHandler 聊天处理器
type ChatHandler struct {
	db         *gorm.DB
	cache      *cache.Cache
	hub        *ws.Hub
	msgService *services.MessageService
	searchSvc  *services.SearchService
}

// NewChatHandler 创建聊天处理器
func NewChatHandler(db *gorm.DB, cache *cache.Cache, hub *ws.Hub, msgService *services.MessageService, searchSvc *services.SearchService) *ChatHandler {
	return &ChatHandler{db: db, cache: cache, hub: hub, msgService: msgService, searchSvc: searchSvc}
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

// getMaxMembers 获取群组/频道的全局成员上限
// chatType: 2=群组, 3=频道
// 返回0表示无限制
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

// getEffectiveMaxMembers 获取单个群组/频道的有效成员上限
// 优先使用群自身的 MaxMembers，为 0 时 fallback 到全局设置
func (h *ChatHandler) getEffectiveMaxMembers(chat *models.Chat) int {
	if chat.MaxMembers > 0 {
		return chat.MaxMembers
	}
	return h.getMaxMembers(chat.Type)
}

func (h *ChatHandler) ensureUserChatRecord(tx *gorm.DB, userID uint64, chatID uint64, sortTime time.Time) error {
	effectiveTime := nowOr(sortTime)

	return tx.Table("user_chats").Clauses(clause.OnConflict{
		Columns: []clause.Column{
			{Name: "user_id"},
			{Name: "chat_id"},
		},
		DoUpdates: clause.Assignments(map[string]interface{}{
			"updated_at":  effectiveTime,
			"sort_time":   effectiveTime,
			"is_archived": false,
		}),
	}).Create(map[string]interface{}{
		"user_id":     userID,
		"chat_id":     chatID,
		"target_id":   0,
		"is_archived": false,
		"sort_time":   effectiveTime,
		"updated_at":  effectiveTime,
	}).Error
}

func nowOr(t time.Time) time.Time {
	if t.IsZero() {
		return time.Now()
	}
	return t
}

func optionalTimeValue(t time.Time) interface{} {
	if t.IsZero() {
		return nil
	}
	return t
}

// GetChatList 获取会话列表
func (h *ChatHandler) GetChatList(c *gin.Context) {
	userID := c.GetString("user_id")
	page, _ := strconv.Atoi(c.DefaultQuery("page", "1"))
	pageSize, _ := strconv.Atoi(c.DefaultQuery("page_size", "20"))
	offset := (page - 1) * pageSize

	// 获取当前用户
	var currentUser models.User
	if err := h.db.Where("uuid = ?", userID).First(&currentUser).Error; err != nil {
		response.NotFound(c, "用户不存在")
		return
	}

	// 获取用户的会话列表（使用 UserChat 表）
	var userChats []models.UserChat
	h.db.Where("user_id = ?", currentUser.ID).
		Order("is_pinned DESC, sort_time DESC").
		Offset(offset).
		Limit(pageSize).
		Find(&userChats)

	// 获取会话详情
	chatIDs := make([]uint64, 0, len(userChats))
	for _, uc := range userChats {
		chatIDs = append(chatIDs, uc.ChatID)
	}

	var chats []models.Chat
	if len(chatIDs) > 0 {
		h.db.Where("id IN ?", chatIDs).Find(&chats)
	}

	// ★ F-04B 时间线模型 v2：Pipeline 批量读 Redis(chat:lastmsg + chat:last_seq)
	// miss 再从 chat_last_msg 兜底，异步回填 Redis，O(1) 次网络往返
	type lastMsgRow struct {
		ChatID        uint64
		LastSeq       uint64
		LastMsgTime   time.Time
		LastMsgText   string
		LastMsgType   int
		LastMsgSender string
	}
	chatLastMsgMap := make(map[uint64]lastMsgRow)
	chatLastSeqMap := make(map[uint64]uint64) // 用于 unread_count 计算，比 lastmsg 里的 seq 更实时

	if len(chatIDs) > 0 {
		// chatID(数字) -> UUID 映射
		chatIDToUUID := make(map[uint64]string, len(chats))
		uuids := make([]string, 0, len(chats))
		for _, ch := range chats {
			chatIDToUUID[ch.ID] = ch.UUID
			uuids = append(uuids, ch.UUID)
		}

		missChatIDs := make([]uint64, 0)
		if h.cache != nil {
			// Pipeline 批量读 last_seq（O(1) 次网络往返）
			seqMap, _ := h.cache.BatchGetChatLastSeq(c.Request.Context(), uuids)
			for _, ch := range chats {
				if seq, ok := seqMap[ch.UUID]; ok {
					chatLastSeqMap[ch.ID] = seq
				}
			}

			// Pipeline 批量读 last_msg（O(1) 次网络往返）
			rawMsgMap, _ := h.cache.BatchGetChatLastMsg(c.Request.Context(), uuids)
			for _, ch := range chats {
				raw, ok := rawMsgMap[ch.UUID]
				if !ok {
					missChatIDs = append(missChatIDs, ch.ID)
					continue
				}
				var cached map[string]interface{}
				if err := json.Unmarshal(raw, &cached); err != nil {
					missChatIDs = append(missChatIDs, ch.ID)
					continue
				}
				row := lastMsgRow{ChatID: ch.ID}
				if v, ok := cached["seq"]; ok {
					switch n := v.(type) {
					case float64:
						row.LastSeq = uint64(n)
					case json.Number:
						if i, e := n.Int64(); e == nil { row.LastSeq = uint64(i) }
					}
				}
				if v, ok := cached["text"]; ok { row.LastMsgText, _ = v.(string) }
				if v, ok := cached["type"]; ok {
					if n, ok2 := v.(float64); ok2 { row.LastMsgType = int(n) }
				}
				if v, ok := cached["sender_name"]; ok { row.LastMsgSender, _ = v.(string) }
				if v, ok := cached["time"]; ok {
					switch t := v.(type) {
					case string:
						if pt, e := time.Parse(time.RFC3339Nano, t); e == nil { row.LastMsgTime = pt }
					case float64:
						row.LastMsgTime = time.UnixMilli(int64(t))
					}
				}
				chatLastMsgMap[ch.ID] = row
			}
		} else {
			missChatIDs = chatIDs
		}

		// miss 从 chat_last_msg 兜底，异步回填 Redis
		if len(missChatIDs) > 0 {
			type dbLastMsg struct {
				ChatID        uint64    `gorm:"column:chat_id"`
				LastSeq       uint64    `gorm:"column:last_seq"`
				LastMsgTime   time.Time `gorm:"column:last_msg_time"`
				LastMsgText   string    `gorm:"column:last_msg_text"`
				LastMsgType   int       `gorm:"column:last_msg_type"`
				LastMsgSender string    `gorm:"column:last_msg_sender"`
			}
			var dbMsgs []dbLastMsg
			h.db.Table("chat_last_msg").Where("chat_id IN ?", missChatIDs).Find(&dbMsgs)
			for _, lm := range dbMsgs {
				chatLastMsgMap[lm.ChatID] = lastMsgRow{
					ChatID:        lm.ChatID,
					LastSeq:       lm.LastSeq,
					LastMsgTime:   lm.LastMsgTime,
					LastMsgText:   lm.LastMsgText,
					LastMsgType:   lm.LastMsgType,
					LastMsgSender: lm.LastMsgSender,
				}
				if chatLastSeqMap[lm.ChatID] == 0 {
					chatLastSeqMap[lm.ChatID] = lm.LastSeq
				}
				// 异步回填 Redis，不阻塞响应
				if h.cache != nil {
					if uuid, ok := chatIDToUUID[lm.ChatID]; ok {
						lmCopy := lm
						uuidCopy := uuid
						go func() {
							ctx := context.Background()
							_ = h.cache.SetChatLastSeq(ctx, uuidCopy, lmCopy.LastSeq)
							_ = h.cache.SetChatLastMsg(ctx, uuidCopy, map[string]interface{}{
								"seq":         lmCopy.LastSeq,
								"time":        lmCopy.LastMsgTime.UnixMilli(),
								"text":        lmCopy.LastMsgText,
								"type":        lmCopy.LastMsgType,
								"sender_name": lmCopy.LastMsgSender,
							})
						}()
					}
				}
			}
		}
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

	// Step 4：统一组装响应
	result := make([]gin.H, 0, len(userChats))
	for _, userChat := range userChats {
		chat, ok := chatMap[userChat.ChatID]
		if !ok {
			continue
		}

		item := gin.H{
			"id":                    userChat.ID,
			"chat_id":               chat.UUID,
			"type":                  chat.Type,
			"name":                  chat.Name,
			"avatar":                chat.Avatar,
			"description":           chat.Description,
			"member_count":          chat.MemberCount,
			"pending_request":       false,
			"pending_request_count": 0,
			"last_msg_text":         func() string { if lm, ok := chatLastMsgMap[userChat.ChatID]; ok { return lm.LastMsgText }; return userChat.LastMsgText }(),
			"last_msg_type":         func() int { if lm, ok := chatLastMsgMap[userChat.ChatID]; ok { return lm.LastMsgType }; return userChat.LastMsgType }(),
			"last_msg_time":         func() interface{} { if lm, ok := chatLastMsgMap[userChat.ChatID]; ok && !lm.LastMsgTime.IsZero() { return lm.LastMsgTime }; return optionalTimeValue(userChat.LastMsgTime) }(),
			"last_msg_seq":          func() uint64 { if lm, ok := chatLastMsgMap[userChat.ChatID]; ok { return lm.LastSeq }; return userChat.LastMsgSeq }(),
			"last_msg_sender":       func() string { if lm, ok := chatLastMsgMap[userChat.ChatID]; ok { return lm.LastMsgSender }; return userChat.LastMsgSender }(),
			"unread_count":          func() int { if seq, ok := chatLastSeqMap[userChat.ChatID]; ok { if seq <= userChat.LastReadSeq { return 0 }; return int(seq - userChat.LastReadSeq) }; if lm, ok := chatLastMsgMap[userChat.ChatID]; ok { if lm.LastSeq <= userChat.LastReadSeq { return 0 }; return int(lm.LastSeq - userChat.LastReadSeq) }; return userChat.UnreadCount }(),
			"is_pinned":             userChat.IsPinned,
			"is_muted":              userChat.IsMuted,
			"is_archived":           userChat.IsArchived,
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
				item["premium_type"] = tu.PremiumType
				item["is_member"] = tu.IsMember
				item["badge_text"] = tu.BadgeText
				item["badge_color"] = tu.BadgeColor
			}
		} else if chat.JoinApproval {
			var membership models.ChatMember
			if err := h.db.Where("chat_id = ? AND user_id = ?", chat.ID, currentUser.ID).First(&membership).Error; err == nil {
				if canReviewJoinRequests(chat.Type, membership.Role) {
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

	response.Success(c, gin.H{
		"list":      result,
		"page":      page,
		"page_size": pageSize,
	})
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

// CreateChat 创建会话
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
				_ = h.ensureUserChatRecord(h.db, currentUser.ID, existingChat.ID, now)
				h.db.Model(&models.UserChat{}).Where("chat_id = ? AND user_id = ?", existingChat.ID, currentUser.ID).Update("target_id", targetUser.ID)
			} else if userChat1.TargetID == 0 {
				// 更新 TargetID
				h.db.Model(&userChat1).Update("target_id", targetUser.ID)
			}

			var userChat2 models.UserChat
			if err := h.db.Where("chat_id = ? AND user_id = ?", existingChat.ID, targetUser.ID).First(&userChat2).Error; err != nil {
				_ = h.ensureUserChatRecord(h.db, targetUser.ID, existingChat.ID, now)
				h.db.Model(&models.UserChat{}).Where("chat_id = ? AND user_id = ?", existingChat.ID, targetUser.ID).Update("target_id", currentUser.ID)
			} else if userChat2.TargetID == 0 {
				// 更新 TargetID
				h.db.Model(&userChat2).Update("target_id", currentUser.ID)
			}

			response.Success(c, existingChat)
			return
		}

		// 创建私聊
		chat := models.Chat{
			UUID:        uuid.New().String(),
			Type:        1,
			MemberCount: 2,
			InviteLink:  uuid.New().String()[:8], // 私聊也需要唯一的 invite_link 避免索引冲突
			CreatedAt:   now,
			UpdatedAt:   now,
		}
		if err := h.db.Create(&chat).Error; err != nil {
			response.ServerError(c, "创建失败")
			return
		}

		// 添加成员（私聊双方都是普通成员）
		members := []models.ChatMember{
			{ChatID: chat.ID, UserID: currentUser.ID, Role: 0, JoinedAt: now, UpdatedAt: now},
			{ChatID: chat.ID, UserID: targetUser.ID, Role: 0, JoinedAt: now, UpdatedAt: now},
		}
		h.db.Create(&members)

		// 为双方创建 UserChat 记录
		userChats := []models.UserChat{
			{
				UserID:   currentUser.ID,
				ChatID:   chat.ID,
				TargetID: targetUser.ID,
				SortTime: now,
			},
			{
				UserID:   targetUser.ID,
				ChatID:   chat.ID,
				TargetID: currentUser.ID,
				SortTime: now,
			},
		}
		// 逐条 upsert 防止唯一索引冲突
		for _, uc := range userChats {
			_ = h.ensureUserChatRecord(h.db, uc.UserID, uc.ChatID, uc.SortTime)
			if uc.TargetID > 0 {
				h.db.Model(&models.UserChat{}).Where("chat_id = ? AND user_id = ?", uc.ChatID, uc.UserID).Update("target_id", uc.TargetID)
			}
		}

		// 通过 WebSocket 通知对方有新会话
		h.hub.SendToUsersCluster([]string{targetUser.UUID}, map[string]interface{}{
			"type":      "new_chat",
			"chat_id":   chat.UUID,
			"chat_type": 1,
			"target_id": currentUser.ID, // 使用数字ID保持头像颜色一致
			"name":      currentUser.Nickname,
			"avatar":    currentUser.Avatar,
		})

		response.Success(c, chat)
		return
	}

	// 仅会员可建群（读系统设置开关）
	if req.Type == 2 || req.Type == 3 {
		var memberOnlySetting models.SystemSetting
		if err := h.db.Where("`key` = ?", models.SettingMemberOnlyCreateGroup).First(&memberOnlySetting).Error; err == nil {
			if isSystemSettingTrue(memberOnlySetting.Value) && !currentUser.IsMember {
				response.Error(c, http.StatusForbidden, "仅会员可创建群组，请联系管理员开通会员")
				return
			}
		}
	}

	// 群聊/频道创建数量限制
	if req.Type == 2 || req.Type == 3 {
		var ownedCount int64
		h.db.Model(&models.Chat{}).Where("owner_id = ? AND type = ?", currentUser.ID, req.Type).Count(&ownedCount)
		limit := getOwnedChatCreationLimit(h.db, currentUser.ID, req.Type)
		if limit > 0 && int(ownedCount) >= limit {
			if req.Type == 2 {
				response.Error(c, http.StatusBadRequest, "创建群组数量已达上限，开通会员可提升额度")
			} else {
				response.Error(c, http.StatusBadRequest, "创建频道数量已达上限，开通会员可提升额度")
			}
			return
		}
	}

	// 群聊/频道
	if req.Name == "" {
		response.BadRequest(c, "群组名称不能为空")
		return
	}

	maxMembers := req.MaxMembers
	if maxMembers <= 0 {
		maxMembers = h.getMaxMembers(req.Type)
	}

	chat := models.Chat{
		UUID:        uuid.New().String(),
		Type:        req.Type,
		Name:        req.Name,
		Description: req.Description,
		Avatar:      req.Avatar,
		OwnerID:     currentUser.ID,
		IsPublic:    req.IsPublic,
		MemberCount: 1,
		MaxMembers:  maxMembers,
		InviteLink:  uuid.New().String()[:8],
		CreatedAt:   now,
		UpdatedAt:   now,
	}

	// 频道模式: 默认只有管理员可发言（类似 Telegram）
	if req.Type == 3 {
		chat.CanSendMessage = false
	}

	if err := h.db.Create(&chat).Error; err != nil {
		response.ServerError(c, "创建失败")
		return
	}

	// 添加创建者为群主
	ownerMember := models.ChatMember{
		ChatID:    chat.ID,
		UserID:    currentUser.ID,
		Role:      2, // 群主 (数据库: 0=成员, 1=管理员, 2=创建者)
		JoinedAt:  now,
		UpdatedAt: now,
	}
	h.db.Create(&ownerMember)

	// 为创建者创建 user_chats 记录（使用 ensureUserChatRecord 防止唯一索引冲突）
	if err := h.ensureUserChatRecord(h.db, currentUser.ID, chat.ID, now); err != nil {
		response.ServerError(c, "创建会话记录失败")
		return
	}

	// 收集所有需要通知的成员ID
	var notifyUserIDs []string

	// 添加其他成员
	if len(req.MemberIDs) > 0 {
		memberUsers, err := h.resolveUsersByIdentifiers(req.MemberIDs)
		if err != nil {
			response.ServerError(c, "获取群成员失败")
			return
		}

		if req.Type == 2 && h.isGroupInviteRequireFriendEnabled() {
			candidateIDs := make([]uint64, 0, len(memberUsers))
			for _, u := range memberUsers {
				if u.ID != currentUser.ID {
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
				for _, u := range memberUsers {
					if u.ID == currentUser.ID {
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

		// 检查成员上限（创建者已占1个位置）
		effectiveMax := h.getEffectiveMaxMembers(&chat)
		if effectiveMax > 0 && len(memberUsers)+1 > effectiveMax {
			memberUsers = memberUsers[:effectiveMax-1]
		}

		for _, u := range memberUsers {
			if u.ID == currentUser.ID {
				continue
			}
			// 创建 chat_member 记录
			member := models.ChatMember{
				ChatID:    chat.ID,
				UserID:    u.ID,
				Role:      0, // 普通成员 (数据库: 0=成员, 1=管理员, 2=创建者)
				JoinedAt:  now,
				UpdatedAt: now,
			}
			h.db.Create(&member)

			// 创建 user_chats 记录（使用 ensureUserChatRecord 防止唯一索引冲突）
			_ = h.ensureUserChatRecord(h.db, u.ID, chat.ID, now)

			notifyUserIDs = append(notifyUserIDs, u.UUID)
		}

		// 更新成员数
		chat.MemberCount = len(memberUsers) + 1
		h.db.Save(&chat)
	}

	// 通过 WebSocket 通知被邀请的成员以及创建者的其他设备
	if h.hub != nil {
		// 构造新群聊通知（包含创建者自己，用于多设备同步）
		allNotifyIDs := append(notifyUserIDs, currentUser.UUID)
		newChatNotification := map[string]interface{}{
			"type": "new_chat",
			"message": map[string]interface{}{
				"id":           chat.UUID,
				"type":         chat.Type,
				"name":         chat.Name,
				"avatar":       chat.Avatar,
				"owner_id":     currentUser.UUID,
				"member_count": chat.MemberCount,
				"created_at":   chat.CreatedAt,
			},
		}
		h.hub.SendToUsersCluster(allNotifyIDs, newChatNotification)
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

// GetChat 获取会话详情
func (h *ChatHandler) GetChat(c *gin.Context) {
	chatID := c.Param("id")
	userID := c.GetString("user_id")

	var chat models.Chat
	if err := h.db.Where("uuid = ?", chatID).First(&chat).Error; err != nil {
		response.NotFound(c, "会话不存在")
		return
	}

	// 获取当前用户
	// ★ 获取当前用户（加错误检查）
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

	// ★ 私聊：一次性查出所有成员 + 对方用户信息，合并原来两段重复逻辑
	var targetUserID string
	var targetUserName string
	var targetUserAvatar string
	var targetEmojiAvatar string
	var targetNicknameColor string
	onlineCount := 0
	if chat.Type == 1 {
		var members []models.ChatMember
		h.db.Where("chat_id = ?", chat.ID).Find(&members)
		for _, m := range members {
			if m.UserID != currentUser.ID {
				var targetUser models.User
				if err := h.db.First(&targetUser, m.UserID).Error; err != nil {
					log.Printf("[ChatHandler] GetChat: target user not found memberUserID=%d err=%v", m.UserID, err)
					break
				}
				// 填充对方用户信息
				targetUserID = targetUser.UUID
				targetUserName = targetUser.Nickname
				if targetUserName == "" {
					targetUserName = targetUser.Username
				}
				targetUserAvatar = targetUser.Avatar
				targetEmojiAvatar = targetUser.EmojiAvatar
				targetNicknameColor = targetUser.NicknameColor
				// 同时检查在线状态
				canSeeOnline, err := privacy.CanViewerSeeOnlineStatus(h.db, currentUser.ID, targetUser.ID)
				if err == nil && canSeeOnline && h.hub != nil && h.hub.IsUserOnlineCluster(targetUser.UUID) {
					onlineCount = 1
				}
				break
			}
		}
	} else if chat.Type == 2 || chat.Type == 3 {
		if h.hub != nil {
			onlineCount = h.hub.GetChatOnlineCount(chat.UUID)
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
		"id":                chat.ID,
		"uuid":              chat.UUID,
		"type":              chat.Type,
		"name":              respName,
		"avatar":            respAvatar,
		"description":       chat.Description,
		"owner_id":          chat.OwnerID,
		"member_count":      chat.MemberCount,
		"online_count":      onlineCount,
		"my_role":           myRole,
		"pending_request":   hasPendingRequest,
		"is_public":         chat.IsPublic,
		"join_approval":     chat.JoinApproval,
		"invite_link":       chat.InviteLink,
		"username":          chat.Username,
		"can_send_message":  chat.CanSendMessage,
		"can_send_media":    chat.CanSendMedia,
		"can_send_links":    chat.CanSendLinks,
		"can_add_members":   chat.CanAddMembers,
		"can_pin_messages":  chat.CanPinMessages,
		"member_protection": chat.MemberProtection,
		"created_at":        chat.CreatedAt,
	}

	// 私聊添加对方用户信息
	if chat.Type == 1 && targetUserID != "" {
		resp["target_user_id"] = targetUserID
		resp["emoji_avatar"] = targetEmojiAvatar
		resp["nickname_color"] = targetNicknameColor
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

	if member.Role < 1 { // 需要管理员或群主权限 (0:成员 1:管理员 2:群主)
		response.Forbidden(c, "无权限，需要管理员或群主身份")
		return
	}

	// 更新
	updates := map[string]interface{}{
		"updated_at": time.Now(),
	}
	if req.Name != nil && *req.Name != "" {
		updates["name"] = *req.Name
	}
	if req.Description != nil {
		updates["description"] = *req.Description
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
	if req.MemberProtection != nil {
		updates["member_protection"] = *req.MemberProtection
	}

	h.db.Model(&chat).Updates(updates)

	// 重新获取更新后的数据
	h.db.Where("uuid = ?", chatID).First(&chat)

	// 如果权限相关字段或加入审批设置被更新，广播给所有成员
	if req.CanSendMessage != nil || req.CanSendMedia != nil || req.CanSendLinks != nil || req.CanAddMembers != nil || req.CanPinMessages != nil || req.MemberProtection != nil || req.JoinApproval != nil {
		h.broadcastChatPermissionsUpdated(&chat)
	}

	// 使相关缓存失效
	if h.cache != nil {
		_ = h.cache.DeleteChatInfo(c.Request.Context(), chat.UUID)
	}

	response.Success(c, chat)
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

	// 删除前先收集所有成员UUID，用于广播通知
	var memberUserIDs []uint64
	h.db.Model(&models.ChatMember{}).Where("chat_id = ?", chat.ID).Pluck("user_id", &memberUserIDs)
	var memberUUIDs []string
	if len(memberUserIDs) > 0 {
		h.db.Model(&models.User{}).Where("id IN ?", memberUserIDs).Pluck("uuid", &memberUUIDs)
	}

	// 删除会话成员
	h.db.Where("chat_id = ?", chat.ID).Delete(&models.ChatMember{})

	// 删除所有成员的 user_chats 记录
	h.db.Where("chat_id = ?", chat.ID).Delete(&models.UserChat{})

	// 删除会话
	h.db.Delete(&chat)

	// 广播群解散事件给所有成员（含多设备同步）
	if h.hub != nil && len(memberUUIDs) > 0 {
		deletedPayload := map[string]interface{}{
			"type":    "chat_deleted",
			"chat_id": chatID,
		}
		h.hub.SendToUsersCluster(memberUUIDs, deletedPayload)
	}

	response.Success(c, nil)
}

// ChatMemberItem 成员信息
type ChatMemberItem struct {
	UserID        string     `json:"user_id"`
	Username      string     `json:"username"`
	Nickname      string     `json:"nickname"`
	Avatar        string     `json:"avatar"`
	Role          int8       `json:"role"` // 1:成员 2:管理员 3:群主
	IsOnline      bool       `json:"is_online"`
	IsMuted       bool       `json:"is_muted"`
	MuteEndTime   *time.Time `json:"mute_end_time,omitempty"`
	NicknameColor string     `json:"nickname_color,omitempty"` // 昵称颜色
	EmojiAvatar   string     `json:"emoji_avatar,omitempty"`   // 动态表情
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
		response.NotFound(c, "用户不存在")
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

	var result []ChatMemberItem
	for _, m := range members {
		user := userMap[m.UserID]

		isOnline := false
		if onlineVisibility[user.ID] && h.hub != nil {
			isOnline = h.hub.IsUserOnlineCluster(user.UUID)
		}

		result = append(result, ChatMemberItem{
			UserID:        user.UUID,
			Username:      user.Username,
			Nickname:      user.Nickname,
			Avatar:        user.Avatar,
			Role:          m.Role + 1,
			IsOnline:      isOnline,
			IsMuted:       m.IsMuted,
			MuteEndTime:   m.MuteEndTime,
			NicknameColor: user.NicknameColor,
			EmojiAvatar:   user.EmojiAvatar,
		})
	}

	response.Success(c, result)
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

	result := make([]ChatMemberItem, 0, len(rows))
	for _, row := range rows {
		isOnline := false
		if searchVisibility[row.UserID] && h.hub != nil {
			isOnline = h.hub.IsUserOnlineCluster(row.UserUUID)
		}

		result = append(result, ChatMemberItem{
			UserID:        row.UserUUID,
			Username:      row.Username,
			Nickname:      row.Nickname,
			Avatar:        row.Avatar,
			Role:          row.Role + 1,
			IsOnline:      isOnline,
			IsMuted:       row.IsMuted,
			MuteEndTime:   row.MuteEndTime,
			NicknameColor: row.NicknameColor,
			EmojiAvatar:   row.EmojiAvatar,
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

	// 若群设置为「仅管理员可邀请」，则普通成员无法邀请（Role: 0=成员 1=管理员 2=群主）
	if !chat.CanAddMembers && member.Role < 1 {
		response.Forbidden(c, "仅管理员可邀请新成员")
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
			ChatID:    chat.ID,
			UserID:    u.ID,
			Role:      0,
			JoinedAt:  now,
			UpdatedAt: now,
		})
		newUserChats = append(newUserChats, models.UserChat{
			UserID:    u.ID,
			ChatID:    chat.ID,
			SortTime:  now,
			UpdatedAt: now,
		})

		addedCount++
		addedUsers = append(addedUsers, u)
		addedUserUUIDs = append(addedUserUUIDs, u.UUID)
	}

	// 批量插入（2 条 SQL 替代 2N 条）
	if len(newMembers) > 0 {
		h.db.Create(&newMembers)
		// 逐条 upsert 防止唯一索引冲突
		for _, uc := range newUserChats {
			_ = h.ensureUserChatRecord(h.db, uc.UserID, uc.ChatID, uc.SortTime)
		}
	}

	// 更新成员数
	h.db.Model(&chat).Update("member_count", gorm.Expr("member_count + ?", addedCount))

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
			ChatID:   chat.UUID,
			SenderID: "system",
			Type:     models.MsgTypeSystem,
			Content: map[string]interface{}{
				"text": systemText,
			},
		}

		// 获取所有群成员的 UUID 用于广播
		var allMemberIDs []uint64
		h.db.Model(&models.ChatMember{}).Where("chat_id = ?", chat.ID).Pluck("user_id", &allMemberIDs)
		var allMemberUUIDs []string
		h.db.Model(&models.User{}).Where("id IN ?", allMemberIDs).Pluck("uuid", &allMemberUUIDs)

		sendCtx, sendCancel := context.WithTimeout(context.Background(), 10*time.Second)
		defer sendCancel()
		sysMsg, err := h.msgService.SendMessage(sendCtx, systemParams, "系统消息", "", "", "", "", allMemberUUIDs)
		if err != nil {
			log.Printf("Failed to send system message: %v", err)
		} else {
			// 更新 UserChat 系统消息预览
			truncatedText := textutil.TruncateRunes(systemText, 100)
			h.db.Model(&models.UserChat{}).
				Where("chat_id = ?", chat.ID).
				Updates(map[string]interface{}{
					"last_msg_text":   truncatedText,
					"last_msg_type":   models.MsgTypeSystem,
					"last_msg_time":   sysMsg.CreatedAt,
					"last_msg_seq":    sysMsg.Seq,
					"last_msg_sender": "",
					"sort_time":       sysMsg.CreatedAt,
				})
		}

		// WebSocket 通知新成员有新群组
		if h.hub != nil {
			newChatNotification := map[string]interface{}{
				"type": "new_chat",
				"message": map[string]interface{}{
					"id":           chat.UUID,
					"type":         chat.Type,
					"name":         chat.Name,
					"avatar":       chat.Avatar,
					"member_count": chat.MemberCount + addedCount,
				},
			}
			h.hub.SendToUsersCluster(addedUserUUIDs, newChatNotification)
		}
	}

	// 使相关缓存失效
	if h.cache != nil {
		chatIDStr := strconv.FormatUint(chat.ID, 10)
		_ = h.cache.InvalidateChatMembers(c.Request.Context(), chatIDStr)
		_ = h.cache.DeleteChatInfo(c.Request.Context(), chat.UUID)
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

	// 需要管理员或创建者权限 (role >= 1)
	if currentMember.Role < 1 {
		response.Forbidden(c, "无权限")
		return
	}

	// 获取要移除的用户
	var targetUser models.User
	if err := h.db.Where("uuid = ?", targetUserID).First(&targetUser).Error; err != nil {
		response.NotFound(c, "用户不存在")
		return
	}

	// 获取目标成员信息
	var targetMember models.ChatMember
	if err := h.db.Where("chat_id = ? AND user_id = ?", chat.ID, targetUser.ID).First(&targetMember).Error; err != nil {
		response.NotFound(c, "该用户不是群成员")
		return
	}

	// 不能移除群主
	if chat.OwnerID == targetUser.ID {
		response.BadRequest(c, "不能移除群主")
		return
	}

	// 管理员不能移除其他管理员，只有群主可以
	if currentMember.Role == 1 && targetMember.Role >= 1 {
		response.Forbidden(c, "管理员不能移除其他管理员")
		return
	}

	// 移除成员
	result := h.db.Where("chat_id = ? AND user_id = ?", chat.ID, targetUser.ID).Delete(&models.ChatMember{})
	if result.RowsAffected > 0 {
		h.db.Model(&chat).Update("member_count", gorm.Expr("member_count - 1"))
	}

	// 删除用户的 UserChat 记录
	h.db.Where("user_id = ? AND chat_id = ?", targetUser.ID, chat.ID).Delete(&models.UserChat{})

	// 通知被移除用户的所有设备
	if h.hub != nil {
		h.hub.SendToUserCluster(targetUser.UUID, map[string]interface{}{
			"type":    "chat_left",
			"chat_id": chat.UUID,
		})
	}

	// 广播成员数更新给剩余成员
	h.broadcastChatUpdate(&chat)

	// 使相关缓存失效
	if h.cache != nil {
		chatIDStr := strconv.FormatUint(chat.ID, 10)
		_ = h.cache.InvalidateChatMembers(c.Request.Context(), chatIDStr)
		_ = h.cache.DeleteChatInfo(c.Request.Context(), chat.UUID)
	}

	response.Success(c, nil)
}

// SetMemberRole 设置成员角色（管理员）
func (h *ChatHandler) SetMemberRole(c *gin.Context) {
	userID := c.GetString("user_id")
	chatID := c.Param("id")
	targetUserID := c.Param("user_id")

	var req struct {
		Role int8 `json:"role"` // 0: 普通成员, 1: 管理员
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

	if currentMember.Role != 2 { // 只有群主（创建者）可以设置管理员
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

	// 更新角色
	if err := h.db.Model(&targetMember).Update("role", req.Role).Error; err != nil {
		response.ServerError(c, "设置失败")
		return
	}

	roleText := "普通成员"
	if req.Role == 1 {
		roleText = "管理员"
	}

	response.Success(c, gin.H{
		"message": "已将该用户设为" + roleText,
		"role":    req.Role,
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

	// 删除成员记录
	if err := h.db.Where("chat_id = ? AND user_id = ?", chat.ID, currentUser.ID).Delete(&models.ChatMember{}).Error; err != nil {
		response.ServerError(c, "退出失败")
		return
	}

	// 减少成员数
	h.db.Model(&chat).Update("member_count", gorm.Expr("member_count - 1"))

	// 删除用户的 UserChat 记录
	h.db.Where("user_id = ? AND chat_id = ?", currentUser.ID, chat.ID).Delete(&models.UserChat{})

	// 用户主动退出不发送系统消息
	// 只有被管理员移除时才发送系统消息

	// 通知当前用户的其他设备同步退出事件
	if h.hub != nil {
		h.hub.SendToUserCluster(userID, map[string]interface{}{
			"type":    "chat_left",
			"chat_id": chat.UUID,
		})
	}

	// 通知群组/频道成员，成员数已更新
	h.broadcastChatUpdate(&chat)

	// 使相关缓存失效
	if h.cache != nil {
		chatIDStr := strconv.FormatUint(chat.ID, 10)
		_ = h.cache.InvalidateChatMembers(c.Request.Context(), chatIDStr)
		_ = h.cache.DeleteChatInfo(c.Request.Context(), chat.UUID)
	}

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
	result := h.db.Where("user_id = ? AND chat_id = ?", currentUser.ID, chat.ID).Delete(&models.UserChat{})

	if result.RowsAffected == 0 {
		response.NotFound(c, "聊天不在列表中")
		return
	}

	// 广播隐藏事件到当前用户的其他设备（多端同步）
	if h.hub != nil {
		h.hub.SendToUserCluster(userID, map[string]interface{}{
			"type":    "chat_hidden",
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
			ChatID:    chat.ID,
			UserID:    currentUser.ID,
			Status:    models.JoinRequestPending,
			CreatedAt: now,
			UpdatedAt: now,
		}
		if err := h.db.Create(&joinRequest).Error; err != nil {
			response.ServerError(c, "提交申请失败")
			return
		}

		message := buildJoinApprovalMessage(chat.Type)
		response.SuccessWithMessage(c, message, gin.H{
			"message":           message,
			"requires_approval": true,
		})
		return
	}

	// 直接加入成员（使用事务+条件更新防止并发超卖）
	now := time.Now()
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
		ChatID:    chat.ID,
		UserID:    currentUser.ID,
		Role:      0,
		JoinedAt:  now,
		UpdatedAt: now,
	}
	if err := joinTx.Create(&member).Error; err != nil {
		joinTx.Rollback()
		response.ServerError(c, "加入失败")
		return
	}
	joinTx.Commit()

	// 创建 UserChat 记录
	userChat := models.UserChat{
		UserID:    currentUser.ID,
		ChatID:    chat.ID,
		TargetID:  0,
		UpdatedAt: now,
	}
	_ = h.ensureUserChatRecord(h.db, userChat.UserID, userChat.ChatID, userChat.SortTime)

	// 用户主动加入不发送系统消息
	// 只有被邀请加入时才发送系统消息

	// 通知群组/频道成员，成员数已更新
	h.broadcastChatUpdate(&chat)

	response.Success(c, gin.H{
		"message":           "加入成功",
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
				ChatID:    chat.ID,
				UserID:    currentUser.ID,
				Status:    models.JoinRequestPending,
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
			ChatID:    chat.ID,
			UserID:    currentUser.ID,
			Role:      0,
			JoinedAt:  now,
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
			"message":           approvalMessage,
			"requires_approval": true,
			"chat_id":           chat.UUID,
			"chat_name":         chat.Name,
			"chat_avatar":       chat.Avatar,
			"chat_type":         chat.Type,
			"already_joined":    false,
		})
		return
	}

	if !alreadyJoined {
		h.broadcastChatUpdate(&chat)
	}

	response.Success(c, gin.H{
		"message":           map[bool]string{true: "already in group", false: "joined successfully"}[alreadyJoined],
		"requires_approval": false,
		"chat_id":           chat.UUID,
		"chat_name":         chat.Name,
		"chat_avatar":       chat.Avatar,
		"chat_type":         chat.Type,
		"already_joined":    alreadyJoined,
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
	if !canReviewJoinRequests(chat.Type, member.Role) {
		response.Forbidden(c, "没有权限查看加入请求")
		return
	}

	// 获取待审批请求
	var requests []models.JoinRequest
	h.db.Where("chat_id = ? AND status = ?", chat.ID, models.JoinRequestPending).
		Order("created_at DESC").
		Find(&requests)

	// 获取用户信息
	result := make([]gin.H, 0, len(requests))
	for _, req := range requests {
		var user models.User
		h.db.First(&user, req.UserID)
		result = append(result, gin.H{
			"id":         req.ID,
			"user_id":    user.UUID,
			"nickname":   user.Nickname,
			"username":   user.Username,
			"avatar":     user.Avatar,
			"message":    req.Message,
			"created_at": req.CreatedAt,
		})
	}

	response.Success(c, gin.H{
		"list":  result,
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
	if !canReviewJoinRequests(chat.Type, member.Role) {
		response.Forbidden(c, "没有权限审批加入请求")
		return
	}

	// 获取加入请求
	var joinRequest models.JoinRequest
	if err := h.db.First(&joinRequest, requestID).Error; err != nil {
		response.NotFound(c, "请求不存在")
		return
	}
	if joinRequest.ChatID != chat.ID {
		response.BadRequest(c, "请求不属于该群组")
		return
	}
	if joinRequest.Status != models.JoinRequestPending {
		response.BadRequest(c, "该请求已处理")
		return
	}

	now := time.Now()
	if req.Approve {
		approveTx := h.db.Begin()
		if approveTx.Error != nil {
			response.ServerError(c, "审批失败")
			return
		}

		// 重新检查是否已是成员
		var existingMemberCount int64
		if err := approveTx.Model(&models.ChatMember{}).
			Where("chat_id = ? AND user_id = ?", chat.ID, joinRequest.UserID).
			Count(&existingMemberCount).Error; err != nil {
			approveTx.Rollback()
			response.ServerError(c, "审批失败")
			return
		}
		if existingMemberCount > 0 {
			joinRequest.Status = models.JoinRequestApproved
			joinRequest.ReviewerID = currentUser.ID
			joinRequest.ReviewedAt = &now
			if err := approveTx.Save(&joinRequest).Error; err != nil {
				approveTx.Rollback()
				response.ServerError(c, "审批失败")
				return
			}
			if err := approveTx.Commit().Error; err != nil {
				approveTx.Rollback()
				response.ServerError(c, "审批失败")
				return
			}
			response.Success(c, gin.H{"message": "该用户已在群内"})
			return
		}

		// 审批通过前重新检查成员上限，避免超卖
		approveMaxMembers := h.getEffectiveMaxMembers(&chat)
		updateResult := approveTx.Model(&models.Chat{}).
			Where("id = ? AND (? = 0 OR member_count < ?)", chat.ID, approveMaxMembers, approveMaxMembers).
			Update("member_count", gorm.Expr("member_count + 1"))
		if updateResult.Error != nil {
			approveTx.Rollback()
			response.ServerError(c, "审批失败")
			return
		}
		if updateResult.RowsAffected == 0 {
			approveTx.Rollback()
			if chat.Type == 3 {
				response.BadRequest(c, "该频道订阅者已达上限")
			} else {
				response.BadRequest(c, "该群组成员已达上限")
			}
			return
		}

		// 通过申请
		joinRequest.Status = models.JoinRequestApproved
		joinRequest.ReviewerID = currentUser.ID
		joinRequest.ReviewedAt = &now
		if err := approveTx.Save(&joinRequest).Error; err != nil {
			approveTx.Rollback()
			response.ServerError(c, "审批失败")
			return
		}

		// 添加成员
		var requestUser models.User
		if err := approveTx.First(&requestUser, joinRequest.UserID).Error; err != nil {
			approveTx.Rollback()
			response.ServerError(c, "审批失败")
			return
		}

		newMember := models.ChatMember{
			ChatID:    chat.ID,
			UserID:    joinRequest.UserID,
			Role:      0, // 普通成员
			JoinedAt:  now,
			UpdatedAt: now,
		}
		if err := approveTx.Create(&newMember).Error; err != nil {
			approveTx.Rollback()
			response.ServerError(c, "审批失败")
			return
		}

		// 创建 UserChat 记录
		userChat := models.UserChat{
			UserID:    joinRequest.UserID,
			ChatID:    chat.ID,
			TargetID:  0,
			UpdatedAt: now,
		}
		if err := h.ensureUserChatRecord(approveTx, userChat.UserID, userChat.ChatID, userChat.SortTime); err != nil {
			approveTx.Rollback()
			response.ServerError(c, "审批失败")
			return
		}

		if err := approveTx.Commit().Error; err != nil {
			approveTx.Rollback()
			response.ServerError(c, "审批失败")
			return
		}

		chat.MemberCount++

		// 用户自己申请加入不发送系统消息，只有被邀请时才发送

		// 通知申请人
		h.hub.SendToUsersCluster([]string{requestUser.UUID}, map[string]interface{}{
			"type":    "join_approved",
			"chat_id": chat.UUID,
			"name":    chat.Name,
		})

		// 通知群组/频道成员，成员数已更新
		h.broadcastChatUpdate(&chat)

		response.Success(c, gin.H{"message": "已通过申请"})
	} else {
		// 拒绝申请
		joinRequest.Status = models.JoinRequestRejected
		joinRequest.ReviewerID = currentUser.ID
		joinRequest.ReviewedAt = &now
		h.db.Save(&joinRequest)

		// 通知申请人
		var requestUser models.User
		h.db.First(&requestUser, joinRequest.UserID)
		h.hub.SendToUsersCluster([]string{requestUser.UUID}, map[string]interface{}{
			"type":    "join_rejected",
			"chat_id": chat.UUID,
			"name":    chat.Name,
		})

		response.Success(c, gin.H{"message": "已拒绝申请"})
	}
}

// MuteMember 禁言成员
func (h *ChatHandler) MuteMember(c *gin.Context) {
	chatID := c.Param("id")
	userUUID := c.GetString("user_id")

	var req struct {
		UserID   string `json:"user_id" binding:"required"`  // 被禁言用户UUID
		Duration *int   `json:"duration" binding:"required"` // 禁言时长（分钟），0表示永久
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

	// 检查权限：只有群主和管理员可以禁言
	if operatorMember.Role < 1 {
		response.Forbidden(c, "没有权限执行此操作")
		return
	}

	// 获取被禁言用户
	var targetUser models.User
	if err := h.db.Where("uuid = ?", req.UserID).First(&targetUser).Error; err != nil {
		response.NotFound(c, "目标用户不存在")
		return
	}

	// 获取被禁言用户的成员信息
	var targetMember models.ChatMember
	if err := h.db.Where("chat_id = ? AND user_id = ?", chat.ID, targetUser.ID).First(&targetMember).Error; err != nil {
		response.NotFound(c, "目标用户不是群成员")
		return
	}

	// 不能禁言群主
	if targetMember.Role >= 2 {
		response.Forbidden(c, "不能禁言群主")
		return
	}

	// 管理员不能禁言管理员
	if operatorMember.Role == 1 && targetMember.Role >= 1 {
		response.Forbidden(c, "管理员不能禁言其他管理员")
		return
	}

	// 设置禁言
	updates := map[string]interface{}{
		"is_muted":   true,
		"updated_at": time.Now(),
	}

	if duration > 0 {
		muteEndTime := time.Now().Add(time.Duration(duration) * time.Minute)
		updates["mute_end_time"] = muteEndTime
	} else {
		updates["mute_end_time"] = nil // 永久禁言
	}

	h.db.Model(&targetMember).Updates(updates)

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
	h.broadcastMuteStatusChanged(&chat, targetUser.UUID, true, updates["mute_end_time"])

	// 使muted缓存失效
	if h.cache != nil {
		chatIDStr := strconv.FormatUint(chat.ID, 10)
		_ = h.cache.InvalidateChatMutedIDs(c.Request.Context(), chatIDStr)
		// 同时失效成员缓存（禁言状态存在ChatMember中）
		userIDStr := strconv.FormatUint(targetUser.ID, 10)
		_ = h.cache.DeleteChatMemberInfo(c.Request.Context(), chatIDStr, userIDStr)
	}

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

	// 检查权限
	if operatorMember.Role < 1 {
		response.Forbidden(c, "没有权限执行此操作")
		return
	}

	// 获取被解禁用户
	var targetUser models.User
	if err := h.db.Where("uuid = ?", req.UserID).First(&targetUser).Error; err != nil {
		response.NotFound(c, "目标用户不存在")
		return
	}

	// 解除禁言
	h.db.Model(&models.ChatMember{}).
		Where("chat_id = ? AND user_id = ?", chat.ID, targetUser.ID).
		Updates(map[string]interface{}{
			"is_muted":      false,
			"mute_end_time": nil,
			"updated_at":    time.Now(),
		})

	// 发送系统消息
	systemMsg := fmt.Sprintf("%s 已被 %s 解除禁言", targetUser.Nickname, operator.Nickname)
	h.sendSystemMessage(c.Request.Context(), &chat, systemMsg)

	// 广播解禁状态变更
	h.broadcastMuteStatusChanged(&chat, targetUser.UUID, false, nil)

	// 使muted缓存失效
	if h.cache != nil {
		chatIDStr := strconv.FormatUint(chat.ID, 10)
		_ = h.cache.InvalidateChatMutedIDs(c.Request.Context(), chatIDStr)
		// 同时失效成员缓存（禁言状态存在ChatMember中）
		userIDStr := strconv.FormatUint(targetUser.ID, 10)
		_ = h.cache.DeleteChatMemberInfo(c.Request.Context(), chatIDStr, userIDStr)
	}

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
		ChatID:  chat.UUID,
		Type:    models.MsgTypeSystem,
		Content: map[string]interface{}{"text": content},
	}

	msg, err := h.msgService.SendMessage(ctx, params, "系统", "", "", "", "", targetUserIDs)
	if err != nil {
		return
	}

	// 更新 UserChat 系统消息预览
	truncated := textutil.TruncateRunes(content, 100)
	h.db.Model(&models.UserChat{}).
		Where("chat_id = ?", chat.ID).
		Updates(map[string]interface{}{
			"last_msg_text":   truncated,
			"last_msg_type":   models.MsgTypeSystem,
			"last_msg_time":   msg.CreatedAt,
			"last_msg_seq":    msg.Seq,
			"last_msg_sender": "",
			"sort_time":       msg.CreatedAt,
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
	h.hub.SendToUsersCluster(memberUUIDs, map[string]interface{}{
		"type": "member_mute_status_changed",
		"message": map[string]interface{}{
			"chat_id":       chat.UUID,
			"user_id":       targetUserUUID,
			"is_muted":      isMuted,
			"mute_end_time": muteEndTime,
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
	h.hub.SendToUsersCluster(memberUUIDs, map[string]interface{}{
		"type": "chat_permissions_updated",
		"message": map[string]interface{}{
			"chat_id":           chat.UUID,
			"can_send_message":  chat.CanSendMessage,
			"can_send_media":    chat.CanSendMedia,
			"can_send_links":    chat.CanSendLinks,
			"can_add_members":   chat.CanAddMembers,
			"can_pin_messages":  chat.CanPinMessages,
			"member_protection": chat.MemberProtection,
			"join_approval":     chat.JoinApproval,
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
		h.db.Model(&member).Updates(map[string]interface{}{
			"is_muted":      false,
			"mute_end_time": nil,
		})
		isMuted = false
	}

	response.Success(c, gin.H{
		"is_muted":      isMuted,
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
	h.hub.SendToUsersCluster(memberUUIDs, map[string]interface{}{
		"type":         "chat_update",
		"chat_id":      chat.UUID,
		"member_count": chat.MemberCount,
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
			response.Error(c, http.StatusBadRequest, "置顶数量已达上限，开通会员可提升至10个")
			return
		}
	}

	// 切换置顶状态
	if err := h.db.Model(&userChat).Update("is_pinned", newPinned).Error; err != nil {
		response.Error(c, http.StatusInternalServerError, "操作失败")
		return
	}

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
	if err := h.db.Model(&userChat).Update("is_muted", newMuted).Error; err != nil {
		response.Error(c, http.StatusInternalServerError, "操作失败")
		return
	}

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

	if err := h.db.Model(&userChat).Update("unread_count", newUnreadCount).Error; err != nil {
		response.Error(c, http.StatusInternalServerError, "操作失败")
		return
	}

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
	if err := h.db.Model(&userChat).Updates(map[string]interface{}{
		"cleared_at":    now,
		"last_msg_text": "",
		"last_msg_time": now,
		"unread_count":  0,
	}).Error; err != nil {
		response.Error(c, http.StatusInternalServerError, "清空失败")
		return
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
		UserID   uint64 `gorm:"column:user_id"`
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
			Updates(map[string]interface{}{
				"cleared_at":    now,
				"last_msg_text": "",
				"last_msg_time": now,
				"unread_count":  0,
			}).Error
	}); err != nil {
		response.ServerError(c, "双向删除失败")
		return
	}

	h.broadcastChatHistoryCleared(chat.UUID, memberUUIDs, user.UUID, now, true)

	response.Success(c, gin.H{
		"message": "已为双方清空聊天记录",
	})
}

func (h *ChatHandler) broadcastChatHistoryCleared(
	chatUUID string,
	targetUserUUIDs []string,
	operatorUUID string,
	clearedAt time.Time,
	forBoth bool,
) {
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

	h.hub.SendToUsersCluster(userUUIDs, map[string]interface{}{
		"type":        "chat_history_cleared",
		"chat_id":     chatUUID,
		"for_both":    forBoth,
		"operator_id": operatorUUID,
		"cleared_at":  clearedAt.UTC().Format(time.RFC3339),
	})
}

// SearchMessages 搜索消息
func (h *ChatHandler) SearchMessages(c *gin.Context) {
	userID := c.GetString("user_id")
	chatUUID := c.Param("id")
	keyword := c.Query("keyword")

	if keyword == "" {
		response.BadRequest(c, "请输入搜索关键词")
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

	// 校验当前用户是否为该会话成员（群/频道需在成员表中存在）
	if chat.Type == 2 || chat.Type == 3 {
		var memberCount int64
		h.db.Model(&models.ChatMember{}).Where("chat_id = ? AND user_id = ?", chat.ID, user.ID).Count(&memberCount)
		if memberCount == 0 {
			response.Forbidden(c, "无权搜索该会话消息")
			return
		}
	} else if chat.Type == 1 {
		var memberCount int64
		h.db.Model(&models.ChatMember{}).Where("chat_id = ? AND user_id = ?", chat.ID, user.ID).Count(&memberCount)
		if memberCount == 0 {
			response.Forbidden(c, "无权搜索该会话消息")
			return
		}
	}

	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()

	// 优先走 ES 搜索，降级到 MongoDB 正则搜索
	if h.searchSvc != nil && h.searchSvc.IsEnabled() {
		results, total, err := h.searchSvc.Search(ctx, keyword, chat.UUID, 1, 50)
		if err == nil {
			response.Success(c, gin.H{
				"list":   results,
				"total":  total,
				"engine": "elasticsearch",
			})
			return
		}
		log.Printf("[Search] ES搜索失败，降级MongoDB: %v", err)
	}

	// 降级：MongoDB 正则搜索
	messages, err := h.msgService.SearchMessages(ctx, chat.UUID, keyword, 50)
	if err != nil {
		response.Error(c, http.StatusInternalServerError, "搜索失败")
		return
	}
	response.Success(c, gin.H{
		"list":   messages,
		"total":  len(messages),
		"engine": "mongodb",
	})
}
