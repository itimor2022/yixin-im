package handlers

import (
	"context"
	"fmt"
	"log"
	"strconv"
	"strings"
	"time"

	"gaoranim/internal/cache"
	"gaoranim/internal/models"
	"gaoranim/internal/services"
	"gaoranim/internal/textutil"
	"gaoranim/internal/ws"
	"gaoranim/pkg/response"

	"github.com/gin-gonic/gin"
	"gorm.io/gorm"
	"gorm.io/gorm/clause"
)

// MessageHandler 消息处理器
type MessageHandler struct {
	db          *gorm.DB
	msgService  *services.MessageService
	pushService *services.PushService
	hub         *ws.Hub
	cache       *cache.Cache
	lastMsgCh   chan models.ChatLastMsg // 异步批量写channel
	pushSem     chan struct{}          // 推送并发限制信号量
}

// NewMessageHandler 创建消息处理器
func NewMessageHandler(db *gorm.DB, msgService *services.MessageService, pushService *services.PushService, hub *ws.Hub, c ...*cache.Cache) *MessageHandler {
	h := &MessageHandler{db: db, msgService: msgService, pushService: pushService, hub: hub}
	if len(c) > 0 && c[0] != nil {
		h.cache = c[0]
	}
	// 启动异步批量写 chat_last_msg 的 worker
	h.lastMsgCh = make(chan models.ChatLastMsg, 2000)
	h.pushSem = make(chan struct{}, 2000) // 最多2000个并发推送goroutine
	// [F-04B] MySQL写入已禁用，仅写Redis
	// go h.runLastMsgFlushWorker()
	return h
}

// runLastMsgFlushWorker 后台批量写 chat_last_msg 到 MySQL
// 每50ms或积累50条时触发一次批量 UPSERT，大幅减少 MySQL 写压力
func (h *MessageHandler) runLastMsgFlushWorker() {
	ticker := time.NewTicker(50 * time.Millisecond)
	defer ticker.Stop()
	buf := make(map[uint64]models.ChatLastMsg) // chatID → 最新一条
	flush := func() {
		if len(buf) == 0 {
			return
		}
		rows := make([]models.ChatLastMsg, 0, len(buf))
		for _, v := range buf {
			rows = append(rows, v)
		}
		buf = make(map[uint64]models.ChatLastMsg)
		// 批量 UPSERT：同一 chatID 只保留最新一条
		if err := h.db.Clauses(clause.OnConflict{
			Columns: []clause.Column{{Name: "chat_id"}},
			DoUpdates: clause.AssignmentColumns([]string{
				"last_seq", "last_msg_time", "last_msg_text",
				"last_msg_type", "last_msg_sender", "updated_at",
			}),
		}).Create(&rows).Error; err != nil {
			log.Printf("[LastMsgFlush] batch upsert error: %v", err)
		}
	}
	for {
		select {
		case msg, ok := <-h.lastMsgCh:
			if !ok {
				flush()
				return
			}
			// 同一 chatID 只保留最新（seq最大）的
			if existing, ok2 := buf[msg.ChatID]; !ok2 || msg.LastSeq > existing.LastSeq {
				buf[msg.ChatID] = msg
			}
			// 积累超过50条立即flush
			if len(buf) >= 50 {
				flush()
			}
		case <-ticker.C:
			flush()
		}
	}
}

// ★ --- 缓存辅助方法 ---

// getChatByUUID 获取群组信息，优先走缓存
func (h *MessageHandler) getChatByUUID(ctx context.Context, uuid string) (*models.Chat, error) {
	if h.cache != nil {
		var chat models.Chat
		if err := h.cache.GetChatInfo(ctx, uuid, &chat); err == nil {
			return &chat, nil
		}
	}
	var chat models.Chat
	if err := h.db.Where("uuid = ?", uuid).First(&chat).Error; err != nil {
		return nil, err
	}
	if h.cache != nil {
		_ = h.cache.SetChatInfo(ctx, uuid, &chat)
	}
	return &chat, nil
}

// getSenderByUUID 获取用户信息，优先走缓存
func (h *MessageHandler) getSenderByUUID(ctx context.Context, uuid string) (*models.User, error) {
	if h.cache != nil {
		var user models.User
		if err := h.cache.GetUserInfo(ctx, uuid, &user); err == nil {
			return &user, nil
		}
	}
	var user models.User
	if err := h.db.Where("uuid = ?", uuid).First(&user).Error; err != nil {
		return nil, err
	}
	if h.cache != nil {
		_ = h.cache.SetUserInfo(ctx, uuid, &user)
	}
	return &user, nil
}

// getChatMember 获取成员信息，优先走缓存
func (h *MessageHandler) getChatMember(ctx context.Context, chatID, userID uint64) (*models.ChatMember, error) {
	chatIDStr := strconv.FormatUint(chatID, 10)
	userIDStr := strconv.FormatUint(userID, 10)
	if h.cache != nil {
		var member models.ChatMember
		if err := h.cache.GetChatMemberInfo(ctx, chatIDStr, userIDStr, &member); err == nil {
			return &member, nil
		}
	}
	var member models.ChatMember
	if err := h.db.Where("chat_id = ? AND user_id = ?", chatID, userID).First(&member).Error; err != nil {
		return nil, err
	}
	if h.cache != nil {
		_ = h.cache.SetChatMemberInfo(ctx, chatIDStr, userIDStr, &member)
	}
	return &member, nil
}

// getChatTargetUUIDs 获取群内所有成员UUID（排除sender），优先走缓存
func (h *MessageHandler) getChatTargetUUIDs(ctx context.Context, chatID, senderUserID uint64) ([]uint64, []string) {
	chatIDStr := strconv.FormatUint(chatID, 10)

	if h.cache != nil {
		allIDStrs, err := h.cache.GetChatMemberAllIDs(ctx, chatIDStr)
		if err == nil && len(allIDStrs) > 0 {
			senderIDStr := strconv.FormatUint(senderUserID, 10)
			targetIDStrs := make([]string, 0, len(allIDStrs)-1)
			for _, id := range allIDStrs {
				if id != senderIDStr {
					targetIDStrs = append(targetIDStrs, id)
				}
			}
			uuids, err2 := h.cache.GetChatMemberUUIDs(ctx, chatIDStr, targetIDStrs)
			if err2 == nil {
				memberIDs := make([]uint64, 0, len(targetIDStrs))
				for _, idStr := range targetIDStrs {
					if id, err := strconv.ParseUint(idStr, 10, 64); err == nil {
						memberIDs = append(memberIDs, id)
					}
				}
				return memberIDs, uuids
			}
		}
	}

	// 缓存未命中：查 MySQL
	var memberUserIDs []uint64
	h.db.Model(&models.ChatMember{}).
		Where("chat_id = ? AND user_id != ?", chatID, senderUserID).
		Pluck("user_id", &memberUserIDs)

	var targetUserIDs []string
	if len(memberUserIDs) > 0 {
		h.db.Model(&models.User{}).Where("id IN ?", memberUserIDs).Pluck("uuid", &targetUserIDs)
	}

	// 异步回填缓存
	if h.cache != nil && len(memberUserIDs) > 0 {
		go func() {
			bgCtx := context.Background()
			type idUUID struct {
				ID   uint64
				UUID string
			}
			var allPairs []idUUID
			h.db.Model(&models.User{}).
				Select("id, uuid").
				Where("id IN (SELECT user_id FROM chat_members WHERE chat_id = ?)", chatID).
				Find(&allPairs)
			allIDStrs := make([]string, 0, len(allPairs))
			idToUUID := make(map[string]string, len(allPairs))
			for _, p := range allPairs {
				idStr := strconv.FormatUint(p.ID, 10)
				allIDStrs = append(allIDStrs, idStr)
				idToUUID[idStr] = p.UUID
			}
			_ = h.cache.SetChatMemberAllIDs(bgCtx, chatIDStr, allIDStrs)
			_ = h.cache.SetChatMemberIDMap(bgCtx, chatIDStr, idToUUID)
		}()
	}

	return memberUserIDs, targetUserIDs
}

// getChatMutedMap 获取群内所有muted用户ID map，优先走缓存
func (h *MessageHandler) getChatMutedMap(ctx context.Context, chatID uint64) map[uint64]bool {
	chatIDStr := strconv.FormatUint(chatID, 10)
	if h.cache != nil {
		if mutedMap, loaded := h.cache.GetChatMutedIDs(ctx, chatIDStr); loaded {
			result := make(map[uint64]bool, len(mutedMap))
			for idStr := range mutedMap {
				if id, err := strconv.ParseUint(idStr, 10, 64); err == nil {
					result[id] = true
				}
			}
			return result
		}
	}
	var mutedUserIDs []uint64
	h.db.Model(&models.UserChat{}).
		Where("chat_id = ? AND is_muted = ?", chatID, true).
		Pluck("user_id", &mutedUserIDs)
	if h.cache != nil {
		mutedStrs := make([]string, len(mutedUserIDs))
		for i, id := range mutedUserIDs {
			mutedStrs[i] = strconv.FormatUint(id, 10)
		}
		_ = h.cache.SetChatMutedIDs(ctx, chatIDStr, mutedStrs)
	}
	result := make(map[uint64]bool, len(mutedUserIDs))
	for _, id := range mutedUserIDs {
		result[id] = true
	}
	return result
}


// getIntSetting 读取整型配置，优先从 Redis 缓存取，避免每次查 DB
// ★ 统一使用 cache.GetSystemSetting/SetSystemSetting，与 RequirePhoneBind 共享同一缓存命名空间
func (h *MessageHandler) getIntSetting(key string, defaultVal int) int {
	ctx := context.Background()

	// 1. 读缓存
	if h.cache != nil {
		if val, found := h.cache.GetSystemSetting(ctx, key); found && val != "" {
			if v, err := strconv.Atoi(val); err == nil {
				return v
			}
		}
	}

	// 2. 缓存未命中，查数据库
	var s models.SystemSetting
	if err := h.db.Where("`key` = ?", key).First(&s).Error; err != nil {
		return defaultVal
	}
	val := defaultVal
	if v, err := strconv.Atoi(s.Value); err == nil {
		val = v
	}

	// 3. 回写缓存
	if h.cache != nil {
		_ = h.cache.SetSystemSetting(ctx, key, strconv.Itoa(val))
	}

	return val
}

// getStringSetting 读取字符串配置，优先从 Redis 缓存取，避免每次查 DB
// ★ 统一使用 cache.GetSystemSetting/SetSystemSetting，与 RequirePhoneBind 共享同一缓存命名空间
func (h *MessageHandler) getStringSetting(key, defaultVal string) string {
	ctx := context.Background()

	// 1. 读缓存
	if h.cache != nil {
		if val, found := h.cache.GetSystemSetting(ctx, key); found {
			if strings.TrimSpace(val) != "" {
				return val
			}
			return defaultVal
		}
	}

	// 2. 缓存未命中，查数据库
	var s models.SystemSetting
	if err := h.db.Where("`key` = ?", key).First(&s).Error; err != nil {
		return defaultVal
	}
	val := strings.TrimSpace(s.Value)
	if val == "" {
		val = defaultVal
	}

	// 3. 回写缓存
	if h.cache != nil {
		_ = h.cache.SetSystemSetting(ctx, key, val)
	}

	return val
}

func uniqueUint64s(values []uint64) []uint64 {
	if len(values) == 0 {
		return nil
	}

	result := make([]uint64, 0, len(values))
	seen := make(map[uint64]struct{}, len(values))
	for _, value := range values {
		if value == 0 {
			continue
		}
		if _, ok := seen[value]; ok {
			continue
		}
		seen[value] = struct{}{}
		result = append(result, value)
	}
	return result
}

func (h *MessageHandler) ensureUserChatRecords(chat *models.Chat, memberIDs []uint64, sortTime time.Time) error {
	if h.db == nil || chat == nil || chat.ID == 0 {
		return nil
	}

	memberIDs = uniqueUint64s(memberIDs)
	if len(memberIDs) == 0 {
		return nil
	}

	effectiveTime := sortTime
	if effectiveTime.IsZero() {
		effectiveTime = time.Now()
	}

	rows := make([]map[string]interface{}, 0, len(memberIDs))
	for _, userID := range memberIDs {
		targetID := uint64(0)
		if chat.Type == 1 && len(memberIDs) == 2 {
			if memberIDs[0] == userID {
				targetID = memberIDs[1]
			} else {
				targetID = memberIDs[0]
			}
		}

		rows = append(rows, map[string]interface{}{
			"user_id":     userID,
			"chat_id":     chat.ID,
			"target_id":   targetID,
			"is_archived": false,
			"sort_time":   effectiveTime,
			"updated_at":  effectiveTime,
		})
	}

	return h.db.Table("user_chats").Clauses(clause.OnConflict{
		Columns: []clause.Column{
			{Name: "user_id"},
			{Name: "chat_id"},
		},
		DoUpdates: clause.AssignmentColumns([]string{
			"target_id",
			"updated_at",
			"sort_time",
			"is_archived",
		}),
	}).Create(rows).Error
}

// checkMessageRateLimit 检查消息发送频率限制，返回 false 表示超限
func (h *MessageHandler) checkMessageRateLimit(c *gin.Context, userID string) bool {
	if h.cache == nil {
		return true
	}
	ctx := c.Request.Context()

	// IP 频率限制（条/分钟）
	ipLimit := h.getIntSetting(models.SettingIPRateLimit, 60)
	if ipLimit > 0 {
		ipKey := "msg_ip:" + c.ClientIP()
		allowed, err := h.cache.RateLimit(ctx, ipKey, ipLimit, time.Minute)
		if err != nil {
			log.Printf("IP rate limit error: %v", err)
		} else if !allowed {
			response.TooManyRequests(c, "发送消息过于频繁，请稍后再试")
			return false
		}
	}

	// 用户频率限制（条/分钟）
	userLimit := h.getIntSetting(models.SettingUserRateLimit, 30)
	if userLimit > 0 {
		userKey := "msg_user:" + userID
		allowed, err := h.cache.RateLimit(ctx, userKey, userLimit, time.Minute)
		if err != nil {
			log.Printf("User rate limit error: %v", err)
		} else if !allowed {
			response.TooManyRequests(c, "发送消息过于频繁，请稍后再试")
			return false
		}
	}

	return true
}

// SendMessageRequest 发送消息请求
type SendMessageRequest struct {
	ChatID           string                          `json:"chat_id" binding:"required"`
	Type             int                             `json:"type" binding:"required"` // 1:文本 2:图片 3:视频 4:语音 5:文件
	Content          map[string]interface{}          `json:"content"`
	E2EE             *models.EncryptedMessagePayload `json:"e2ee"`
	MsgID            string                          `json:"msg_id"`
	ReplyTo          *ReplyToRequest                 `json:"reply_to"`
	Mentions         []string                        `json:"mentions"`
	BurnAfterRead    bool                            `json:"burn_after_read"`
	BurnAfterSeconds int                             `json:"burn_after_seconds"`
}

// ReplyToRequest 回复消息
type ReplyToRequest struct {
	MsgID      string `json:"msg_id"`
	SenderID   string `json:"sender_id"`
	SenderName string `json:"sender_name"`
	Content    string `json:"content"`
}

func hasValidEncryptedPayload(payload *models.EncryptedMessagePayload) bool {
	return payload != nil &&
		payload.Ciphertext != "" &&
		payload.IV != "" &&
		payload.Mac != "" &&
		len(payload.Envelopes) > 0
}

func supportsE2EEMessageType(msgType int) bool {
	switch msgType {
	case 1, 2, 3, 4, 5, 6, 10:
		return true
	default:
		return false
	}
}

func (h *MessageHandler) getMessageCryptoMode() string {
	if h == nil || h.db == nil {
		return models.MessageCryptoModePlain
	}

	var setting models.SystemSetting
	if err := h.db.
		Where("`key` = ?", models.SettingMessageCryptoMode).
		Select("value").
		First(&setting).Error; err != nil {
		return models.MessageCryptoModePlain
	}

	return normalizeMessageCryptoMode(setting.Value)
}

func sanitizeMessageServiceError(err error, fallback string) string {
	if err == nil {
		return fallback
	}

	if svcErr, ok := err.(*services.ServiceError); ok {
		message := strings.TrimSpace(svcErr.Message)
		if message != "" {
			return message
		}
	}

	message := strings.TrimSpace(err.Error())
	if message == "" {
		return fallback
	}

	lower := strings.ToLower(message)
	technicalMarkers := []string{
		"not authorized on",
		"command {",
		"$db:",
		"tbimimqq_messages",
		"messages_",
		"mongo",
		"server selection timeout",
		"connection refused",
		"context deadline exceeded",
		"broken pipe",
		"topology",
	}
	for _, marker := range technicalMarkers {
		if strings.Contains(lower, marker) {
			return fallback
		}
	}

	return message
}

func hasPlainMessageContent(content map[string]interface{}) bool {
	if len(content) == 0 {
		return false
	}
	if text, ok := content["text"].(string); ok && text != "" {
		return true
	}
	for _, key := range []string{"media", "voice", "file", "location", "contact"} {
		if value, ok := content[key].(map[string]interface{}); ok && len(value) > 0 {
			return true
		}
	}
	return false
}

func chatPushType(chatType int8) string {
	switch chatType {
	case 1:
		return "private"
	case 2:
		return "group"
	case 3:
		return "channel"
	default:
		return "unknown"
	}
}

// SendMessage 发送消息
func (h *MessageHandler) SendMessage(c *gin.Context) {
	userID := c.GetString("user_id")

	var req SendMessageRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		response.BadRequest(c, "参数错误")
		return
	}
	hasEncryptedPayload := hasValidEncryptedPayload(req.E2EE)
	if req.E2EE != nil && !hasEncryptedPayload {
		response.BadRequest(c, "加密消息载荷无效")
		return
	}
	cryptoMode := h.getMessageCryptoMode()
	if hasEncryptedPayload && !supportsE2EEMessageType(req.Type) {
		response.BadRequest(c, "当前消息类型暂不支持端到端加密")
		return
	}
	switch cryptoMode {
	case models.MessageCryptoModePlain:
		if hasEncryptedPayload {
			response.BadRequest(c, "当前系统已关闭消息加密，请使用明文模式发送")
			return
		}
	case models.MessageCryptoModeStrict:
		if !supportsE2EEMessageType(req.Type) {
			response.BadRequest(c, "严格加密模式下，当前消息类型暂不支持发送")
			return
		}
		if !hasEncryptedPayload {
			response.BadRequest(c, "严格加密模式下，消息必须使用端到端加密发送")
			return
		}
	}
	if !hasEncryptedPayload && !hasPlainMessageContent(req.Content) {
		response.BadRequest(c, "消息内容不能为空")
		return
	}

	if req.MsgID != "" {
		existing, ok, err := h.msgService.FindMessageByClientID(c.Request.Context(), req.ChatID, userID, req.MsgID)
		if err != nil {
			log.Printf("[Message] FindMessageByClientID error chatID=%s userID=%s msgID=%s err=%v", req.ChatID, userID, req.MsgID, err)
			response.ServerError(c, sanitizeMessageServiceError(err, "消息发送失败，请稍后重试"))
			return
		}
		if ok {
			response.Success(c, existing)
			return
		}
	}

	// 频率限制检查
	if !h.checkMessageRateLimit(c, userID) {
		return
	}

	// 获取发送者信息（优先走缓存）
	ctx := c.Request.Context()
	senderPtr, err := h.getSenderByUUID(ctx, userID)
	if err != nil {
		response.NotFound(c, "用户不存在")
		return
	}
	sender := *senderPtr

	// 检查用户是否被封禁（封禁状态可以登录但不能发消息）
	if sender.Status == models.UserStatusBanned {
		banMsg := "您的账号已被封禁，无法发送消息"
		if sender.BanReason != "" {
			banMsg = fmt.Sprintf("您的账号已被封禁（%s），无法发送消息", sender.BanReason)
		}
		response.Forbidden(c, banMsg)
		return
	}

	// 检查用户是否被禁用
	if sender.Status == models.UserStatusDisabled {
		response.Forbidden(c, "您的账号已被禁用")
		return
	}

	// 获取会话信息（优先走缓存）
	chatPtr, err := h.getChatByUUID(ctx, req.ChatID)
	if err != nil {
		response.NotFound(c, "会话不存在")
		return
	}
	chat := *chatPtr

	// 检查会话是否被封禁或解散
	if chat.Status == models.ChatStatusBanned {
		response.Forbidden(c, "该群组已被管理员封禁，无法发送消息")
		return
	}
	if chat.Status == models.ChatStatusDissolved {
		response.Forbidden(c, "该群组已被解散")
		return
	}

	// 获取发送者成员信息（优先走缓存）
	var senderMember models.ChatMember
	senderMemberPtr, err := h.getChatMember(ctx, chat.ID, sender.ID)
	if err != nil {
		response.Forbidden(c, "您不是该会话成员")
		return
	}
	senderMember = *senderMemberPtr

	if chat.Type != 1 { // 非私聊
		// 频道模式: 仅管理员和创建者可发言（类似 Telegram）
		// 数据库 role: 0=普通成员, 1=管理员, 2=群主
		if chat.Type == 3 && senderMember.Role < 1 {
			response.Forbidden(c, "频道仅允许管理员发布内容")
			return
		}

		// 检查全员禁言（管理员和群主不受限制）- 仅对群组生效
		if chat.Type == 2 && !chat.CanSendMessage && senderMember.Role < 1 {
			response.Forbidden(c, "群组已开启全员禁言，仅管理员可发言")
			return
		}

		// 检查发送媒体权限（图片、视频、文件）
		if !chat.CanSendMedia && senderMember.Role < 1 && (req.Type == 2 || req.Type == 3 || req.Type == 5) {
			response.Forbidden(c, "群组已禁止发送媒体内容")
			return
		}

		// 检查是否被禁言（个人禁言）
		if senderMember.IsMuted {
			// 检查禁言是否过期
			if senderMember.MuteEndTime != nil && time.Now().After(*senderMember.MuteEndTime) {
				// 禁言已过期，自动解除
				h.db.Model(&senderMember).Updates(map[string]interface{}{
					"is_muted":      false,
					"mute_end_time": nil,
				})
			} else {
				// 仍在禁言期
				muteMsg := "您已被禁言"
				if senderMember.MuteEndTime != nil {
					muteMsg = fmt.Sprintf("您已被禁言至 %s", senderMember.MuteEndTime.Format("2006-01-02 15:04"))
				}
				response.Forbidden(c, muteMsg)
				return
			}
		}
	}

	// 获取目标用户 UUID 列表（优先走缓存，排除发送者）
	// 群聊跳过全量成员查询，BroadcastToGroupCluster 走 Redis 在线集合，无需全量 UUID
	var memberUserIDs []uint64
	var targetUserIDs []string
	if chat.Type == 1 {
		// 私聊：需要 targetUserIDs 做屏蔽检查和 WS 推送
		memberUserIDs, targetUserIDs = h.getChatTargetUUIDs(ctx, chat.ID, sender.ID)
	}


	// 私聊：检查对方是否已将发送者加入屏蔽列表
	if chat.Type == 1 && len(memberUserIDs) > 0 {
		var blockCount int64
		h.db.Model(&models.UserBlock{}).
			Where("user_id IN ? AND blocked_user_id = ?", memberUserIDs, sender.ID).
			Count(&blockCount)
		if blockCount > 0 {
			response.Forbidden(c, "对方已将您屏蔽，无法发送消息")
			return
		}
	}

	// 违禁词过滤（仅对文本消息检测 text 字段）
	if req.Type == 1 && !hasEncryptedPayload {
		if text, ok := req.Content["text"].(string); ok && text != "" {
			filtered, blocked := filterContentWithDB(h.db, text)
			if blocked {
				response.Forbidden(c, "消息包含违禁词，无法发送")
				return
			}
			req.Content["text"] = filtered
		}
	}

	burnAfterReadEnabled := !isSystemSettingFalse(
		h.getStringSetting(models.SettingBurnAfterReadEnabled, "true"),
	)
	if !burnAfterReadEnabled {
		req.BurnAfterRead = false
		req.BurnAfterSeconds = 0
	}

	// 转换回复信息
	var replyTo *services.ReplyInfo
	if req.ReplyTo != nil {
		replyTo = &services.ReplyInfo{
			MsgID:      req.ReplyTo.MsgID,
			SenderID:   req.ReplyTo.SenderID,
			SenderName: req.ReplyTo.SenderName,
			Content:    req.ReplyTo.Content,
		}
	}

	// 发送消息
	sendResult, err := h.msgService.SendMessageWithResult(c.Request.Context(), &services.SendMessageParams{
		ChatID:           req.ChatID,
		SenderID:         userID,
		SenderDeviceID:   c.GetString("device_id"),
		Type:             req.Type,
		Content:          req.Content,
		E2EE:             req.E2EE,
		MsgID:            req.MsgID,
		ReplyTo:          replyTo,
		Mentions:         req.Mentions,
		BurnAfterRead:    req.BurnAfterRead,
		BurnAfterSeconds: req.BurnAfterSeconds,
		ChatType:         int(chat.Type),
	}, sender.Nickname, sender.Avatar, sender.NicknameColor, sender.PremiumType, sender.EmojiAvatar, targetUserIDs)

	if err != nil {
		log.Printf("[Message] SendMessageWithResult error chatID=%s userID=%s msgID=%s type=%d err=%v", req.ChatID, userID, req.MsgID, req.Type, err)
		response.ServerError(c, sanitizeMessageServiceError(err, "消息发送失败，请稍后重试"))
		return
	}
	if sendResult == nil || sendResult.Message == nil {
		response.ServerError(c, "消息发送失败")
		return
	}
	msg := sendResult.Message
	if sendResult.Duplicate {
		response.Success(c, msg)
		return
	}

	// 更新 UserChat 的最后消息
	lastMsgText := ""
	if req.BurnAfterRead {
		lastMsgText = services.BurnAfterReadPreviewText()
	} else if hasEncryptedPayload {
		lastMsgText = services.EncryptedPreviewText(req.Type)
	} else if text, ok := req.Content["text"].(string); ok {
		lastMsgText = textutil.TruncateRunes(text, 100)
	} else {
		switch req.Type {
		case 2:
			lastMsgText = "[图片]"
		case 3:
			lastMsgText = "[视频]"
		case 4:
			lastMsgText = "[语音]"
		case 5:
			lastMsgText = "[文件]"
		case 6:
			lastMsgText = "[位置]"
		case 10:
			lastMsgText = "[联系人名片]"
		}
	}


	// ★ 阶段二：chat_last_msg 先写Redis（<1ms），异步刷MySQL（不阻塞响应）
	chatIDStr := strconv.FormatUint(chat.ID, 10)
	chatLastMsgData := map[string]interface{}{
		"chat_id":        chat.ID,
		"last_seq":       msg.Seq,
		"last_msg_time":  msg.CreatedAt,
		"last_msg_text":  lastMsgText,
		"last_msg_type":  msg.Type,
		"last_msg_sender": sender.Nickname,
		"updated_at":     msg.CreatedAt,
	}
	// 1. 同步写 Redis（会话列表实时更新）
	if h.cache != nil {
		_ = h.cache.SetChatLastMsg(ctx, chatIDStr, chatLastMsgData)
	}
	// [F-04B] 以下MySQL异步写入已禁用
	// // 2. 发送到批量写channel（worker每50ms批量UPSERT，消除高频单行写压力）
	// if h.lastMsgCh != nil {
	// select {
	// case h.lastMsgCh <- models.ChatLastMsg{
	// ChatID:        chat.ID,
	// LastSeq:       msg.Seq,
	// LastMsgTime:   msg.CreatedAt,
	// LastMsgText:   lastMsgText,
	// LastMsgType:   msg.Type,
	// LastMsgSender: sender.Nickname,
	// UpdatedAt:     msg.CreatedAt,
	// }:
	// default:
	// // channel满时降级为单条异步写，防止数据丢失
	// go func() {
	// h.db.Save(&models.ChatLastMsg{
	// ChatID:        chat.ID,
	// LastSeq:       msg.Seq,
	// LastMsgTime:   msg.CreatedAt,
	// LastMsgText:   lastMsgText,
	// LastMsgType:   msg.Type,
	// LastMsgSender: sender.Nickname,
	// UpdatedAt:     msg.CreatedAt,
	// })
	// }()
	// }
	// }


	// 3. 更新 user_chats（按群规模分策略，memberCount 直接用缓存字段，无需 COUNT 查询）
	memberCount := int64(chat.MemberCount)

	if memberCount <= 50 {
		// 小群/私聊（≤50人）：同步更新，兼容旧客户端
		h.db.Model(&models.UserChat{}).
			Where("chat_id = ?", chat.ID).
			Updates(map[string]interface{}{
				"last_msg_text":   lastMsgText,
				"last_msg_type":   msg.Type,
				"last_msg_time":   msg.CreatedAt,
				"last_msg_seq":    msg.Seq,
				"last_msg_sender": sender.Nickname,
				"sort_time":       msg.CreatedAt,
			})
		h.db.Model(&models.UserChat{}).
			Where("chat_id = ? AND user_id != ?", chat.ID, sender.ID).
			UpdateColumn("unread_count", gorm.Expr("unread_count + 1"))
	} else {
		// 大群（>50人）：完全跳过 user_chats 批量更新，零写入
		// sort_time/last_msg_* 从 Redis chat:lastmsg 实时读取
		// unread_count 用 chat_last_msg.last_seq - user_chats.last_read_seq 差值计算
	}

	pushPreviewText := lastMsgText
	if req.BurnAfterRead {
		pushPreviewText = services.BurnAfterReadPreviewText()
	} else if hasEncryptedPayload {
		pushPreviewText = services.EncryptedPushPreviewText()
	}

	// 向离线用户发送推送通知（批量查询，避免 N+1）
	if h.pushService != nil {
		go func() {
			// 非阻塞获取推送信号量，满了直接跳过（推送非核心路径）
			select {
			case h.pushSem <- struct{}{}:
				defer func() { <-h.pushSem }()
			default:
				log.Printf("[Push] pushSem full, skip push for chat=%s", req.ChatID)
				return
			}
			log.Printf("[Push] Checking push for %d targets", len(targetUserIDs))
			if len(targetUserIDs) == 0 {
				return
			}
			// 批量获取用户 ID，只推送离线用户
			// ★ 直接用已缓存的 memberUserIDs/targetUserIDs，避免再查一次5000行
			type userIDPair struct {
				ID   uint64
				UUID string
			}
			pairs := make([]userIDPair, 0, len(memberUserIDs))
			for idx, uid := range memberUserIDs {
				if idx < len(targetUserIDs) {
					pairs = append(pairs, userIDPair{ID: uid, UUID: targetUserIDs[idx]})
				}
			}

				// 获取muted用户（优先走缓存）
				mutedUsers64 := h.getChatMutedMap(context.Background(), chat.ID)
				mutedUsers := make(map[uint64]bool, len(mutedUsers64))
				for id := range mutedUsers64 {
					mutedUsers[id] = true
				}

			// 批量查询推送设置，避免 N 次单行查询打爆数据库
			pushChatType := chatPushType(chat.Type)
				// ★ 先用Redis过滤有效推送用户，避免对无设备用户做无效查询
				pushUIDs := make([]uint64, 0, len(pairs))
				for _, p := range pairs {
					if !mutedUsers[p.ID] {
						pushUIDs = append(pushUIDs, p.ID)
					}
				}
				// Redis过滤：只保留有有效push_token的用户
				if h.cache != nil && h.cache.IsPushableUsersLoaded(context.Background()) {
					filtered, _ := h.cache.FilterPushableUsers(context.Background(), pushUIDs)
					pushUIDs = filtered
				}
				if len(pushUIDs) > 0 {
					// 批量查推送设置（优先Redis缓存）
					showPreviewMap := make(map[uint64]bool)
					missUIDs := make([]uint64, 0)
					if h.cache != nil {
						for _, uid := range pushUIDs {
							uidStr := strconv.FormatUint(uid, 10)
							if sp, found := h.cache.GetUserPushSetting(context.Background(), uidStr); found {
								showPreviewMap[uid] = sp
							} else {
								missUIDs = append(missUIDs, uid)
							}
						}
					} else {
						missUIDs = pushUIDs
					}
					// miss的从MySQL补查并回填缓存
					if len(missUIDs) > 0 {
						var pushSettings []models.UserPushSetting
						h.db.Where("user_id IN ?", missUIDs).Find(&pushSettings)
						for _, ps := range pushSettings {
							showPreviewMap[ps.UserID] = ps.ShowPreview
							if h.cache != nil {
								_ = h.cache.SetUserPushSetting(context.Background(),
									strconv.FormatUint(ps.UserID, 10), ps.ShowPreview)
							}
						}
					}
					// 构建批量推送列表
					batchUsers := make([]services.BatchPushUser, 0, len(pushUIDs))
					for _, p := range pairs {
						if mutedUsers[p.ID] {
							continue
						}
						showPreview := true
						if sp, ok := showPreviewMap[p.ID]; ok {
							showPreview = sp
						}
						body := pushPreviewText
						if !showPreview {
							body = "您收到一条新消息"
						}
						batchUsers = append(batchUsers, services.BatchPushUser{
							UserID:     p.ID,
							SenderName: sender.Nickname,
							Body:       body,
						})
					}
					h.pushService.PushNewMessageBatch(batchUsers, req.ChatID, pushChatType)
				}
	}()
	}

	log.Printf("[Message] Sent message: chatId=%s, msgId=%s, seq=%d, type=%d",
		msg.ChatID, msg.MsgID, msg.Seq, msg.Type)

	response.Success(c, msg)
}

// GetMessagesRequest 获取消息请求
type GetMessagesRequest struct {
	ChatID    string `form:"chat_id" binding:"required"`
	BeforeSeq int    `form:"before_seq"`
	Limit     int    `form:"limit"`
}

// GetMessages 获取消息列表
func (h *MessageHandler) GetMessages(c *gin.Context) {
	userID := c.GetString("user_id")

	var req GetMessagesRequest
	if err := c.ShouldBindQuery(&req); err != nil {
		response.BadRequest(c, "参数错误")
		return
	}

	// 校验当前用户是否为该会话成员
	var sender models.User
	if err := h.db.Where("uuid = ?", userID).First(&sender).Error; err != nil {
		response.Unauthorized(c, "请先登录")
		return
	}
	var chat models.Chat
	if err := h.db.Where("uuid = ?", req.ChatID).First(&chat).Error; err != nil {
		response.NotFound(c, "会话不存在")
		return
	}
	var memberCount int64
	h.db.Model(&models.ChatMember{}).Where("chat_id = ? AND user_id = ?", chat.ID, sender.ID).Count(&memberCount)
	if memberCount == 0 {
		response.Forbidden(c, "无权访问该会话消息")
		return
	}

	if req.Limit <= 0 || req.Limit > 100 {
		req.Limit = 50
	}

	messages, err := h.msgService.GetMessages(c.Request.Context(), &services.GetMessagesParams{
		ChatID:    req.ChatID,
		UserID:    userID,
		BeforeSeq: req.BeforeSeq,
		Limit:     req.Limit,
	})

	if err != nil {
		log.Printf("[Message] GetMessages error: %v", err)
		response.ServerError(c, sanitizeMessageServiceError(err, "消息加载失败，请稍后重试"))
		return
	}

	log.Printf("[Message] GetMessages chatId=%s, beforeSeq=%d, limit=%d, returned=%d messages",
		req.ChatID, req.BeforeSeq, req.Limit, len(messages))

	response.Success(c, messages)
}

// GetChatMediaRequest 获取聊天媒体请求
type GetChatMediaRequest struct {
	ChatID string `form:"chat_id" binding:"required"`
	Type   string `form:"type" binding:"required"` // media(图片视频), file, link, voice
	Page   int    `form:"page"`
	Limit  int    `form:"limit"`
}

// GetChatMedia 获取聊天媒体/文件/链接
func (h *MessageHandler) GetChatMedia(c *gin.Context) {
	userID := c.GetString("user_id")

	var req GetChatMediaRequest
	if err := c.ShouldBindQuery(&req); err != nil {
		response.BadRequest(c, "参数错误")
		return
	}

	if req.Page <= 0 {
		req.Page = 1
	}
	if req.Limit <= 0 || req.Limit > 50 {
		req.Limit = 20
	}

	// 获取用户
	var user models.User
	if err := h.db.Where("uuid = ?", userID).First(&user).Error; err != nil {
		response.NotFound(c, "用户不存在")
		return
	}

	// 获取会话
	var chat models.Chat
	if err := h.db.Where("uuid = ?", req.ChatID).First(&chat).Error; err != nil {
		response.NotFound(c, "会话不存在")
		return
	}

	// 检查是否是会话成员
	var member models.ChatMember
	if err := h.db.Where("chat_id = ? AND user_id = ?", chat.ID, user.ID).First(&member).Error; err != nil {
		response.Forbidden(c, "无权限访问")
		return
	}

	// 根据类型筛选消息类型
	var msgTypes []int
	switch req.Type {
	case "media":
		msgTypes = []int{2, 3} // 图片、视频
	case "file":
		msgTypes = []int{5} // 文件
	case "link":
		msgTypes = []int{1} // 文本消息（需要在内容中检测链接）
	case "voice":
		msgTypes = []int{4} // 语音
	default:
		response.BadRequest(c, "无效的类型")
		return
	}

	// 从 MongoDB 获取消息（传入用户ID过滤已删除的消息）
	messages, total, err := h.msgService.GetChatMediaMessages(c.Request.Context(), req.ChatID, user.UUID, msgTypes, req.Type, req.Page, req.Limit)
	if err != nil {
		response.ServerError(c, sanitizeMessageServiceError(err, "聊天资料暂时无法加载，请稍后重试"))
		return
	}

	response.Success(c, gin.H{
		"list":  messages,
		"total": total,
		"page":  req.Page,
		"limit": req.Limit,
	})
}

// GetChatMediaCount 获取聊天媒体数量统计
func (h *MessageHandler) GetChatMediaCount(c *gin.Context) {
	userID := c.GetString("user_id")
	chatID := c.Query("chat_id")

	if chatID == "" {
		response.BadRequest(c, "参数错误")
		return
	}

	// 获取用户
	var user models.User
	if err := h.db.Where("uuid = ?", userID).First(&user).Error; err != nil {
		response.NotFound(c, "用户不存在")
		return
	}

	// 获取会话
	var chat models.Chat
	if err := h.db.Where("uuid = ?", chatID).First(&chat).Error; err != nil {
		response.NotFound(c, "会话不存在")
		return
	}

	// 检查是否是会话成员
	var member models.ChatMember
	if err := h.db.Where("chat_id = ? AND user_id = ?", chat.ID, user.ID).First(&member).Error; err != nil {
		response.Forbidden(c, "无权限访问")
		return
	}

	// 获取各类型消息数量（传入用户ID过滤已删除的消息）
	counts, err := h.msgService.GetChatMediaCounts(c.Request.Context(), chatID, userID)
	if err != nil {
		response.ServerError(c, sanitizeMessageServiceError(err, "聊天资料统计失败，请稍后重试"))
		return
	}

	response.Success(c, counts)
}

// RevokeMessageRequest 撤回消息请求
type RevokeMessageRequest struct {
	ChatID string `json:"chat_id" binding:"required"`
	MsgID  string `json:"msg_id" binding:"required"`
}

// RevokeMessage 撤回消息
func (h *MessageHandler) RevokeMessage(c *gin.Context) {
	userID := c.GetString("user_id")

	var req RevokeMessageRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		response.BadRequest(c, "参数错误")
		return
	}

	isAdminRevoke := false

	var chat models.Chat
	if err := h.db.Where("uuid = ?", req.ChatID).First(&chat).Error; err == nil && chat.Type == 2 {
		var currentUser models.User
		if err := h.db.Where("uuid = ?", userID).First(&currentUser).Error; err == nil {
			var member models.ChatMember
			if err := h.db.Where("chat_id = ? AND user_id = ?", chat.ID, currentUser.ID).First(&member).Error; err == nil && member.Role >= 1 {
				isAdminRevoke = true
			}
		}
	}

	err := h.msgService.RevokeMessage(c.Request.Context(), req.ChatID, req.MsgID, userID, isAdminRevoke)
	if err != nil {
		response.Error(c, 400, sanitizeMessageServiceError(err, "撤回消息失败，请稍后重试"))
		return
	}

	response.Success(c, nil)
}

// DeleteMessageRequest 删除消息请求
type DeleteMessageRequest struct {
	ChatID string `json:"chat_id" binding:"required"`
	MsgID  string `json:"msg_id" binding:"required"`
}

// DeleteMessage 删除消息（仅对当前用户不可见）
func (h *MessageHandler) DeleteMessage(c *gin.Context) {
	userID := c.GetString("user_id")

	var req DeleteMessageRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		response.BadRequest(c, "参数错误")
		return
	}

	err := h.msgService.DeleteMessageForUser(c.Request.Context(), req.ChatID, req.MsgID, userID)
	if err != nil {
		response.Error(c, 400, sanitizeMessageServiceError(err, "删除消息失败，请稍后重试"))
		return
	}

	response.Success(c, nil)
}

// SyncMessagesRequest 同步消息请求
type SyncMessagesRequest struct {
	ChatID  string `json:"chat_id" binding:"required"`
	LastSeq int    `json:"last_seq"`
}

// SyncMessages 同步消息
func (h *MessageHandler) SyncMessages(c *gin.Context) {
	userID := c.GetString("user_id")

	var req SyncMessagesRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		response.BadRequest(c, "参数错误")
		return
	}

	// 校验当前用户是否为该会话成员
	var syncUser models.User
	if err := h.db.Where("uuid = ?", userID).First(&syncUser).Error; err != nil {
		response.Unauthorized(c, "请先登录")
		return
	}
	var syncChat models.Chat
	if err := h.db.Where("uuid = ?", req.ChatID).First(&syncChat).Error; err != nil {
		response.NotFound(c, "会话不存在")
		return
	}
	var syncMemberCount int64
	h.db.Model(&models.ChatMember{}).Where("chat_id = ? AND user_id = ?", syncChat.ID, syncUser.ID).Count(&syncMemberCount)
	if syncMemberCount == 0 {
		response.Forbidden(c, "无权同步该会话消息")
		return
	}

	messages, err := h.msgService.SyncMessages(c.Request.Context(), req.ChatID, userID, req.LastSeq)
	if err != nil {
		response.ServerError(c, sanitizeMessageServiceError(err, "消息同步失败，请稍后重试"))
		return
	}

	response.Success(c, gin.H{
		"messages": messages,
		"has_more": len(messages) >= 100,
	})
}

// MarkAsReadRequest 标记已读请求
type MarkAsReadRequest struct {
	ChatID string `json:"chat_id" binding:"required"`
	MsgSeq int    `json:"msg_seq"` // 已读到的消息序号
}

// MarkAsRead 标记消息已读
func (h *MessageHandler) MarkAsRead(c *gin.Context) {
	userID := c.GetString("user_id")

	var req MarkAsReadRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		response.BadRequest(c, "参数错误")
		return
	}

	// 获取用户信息
	var user models.User
	if err := h.db.Where("uuid = ?", userID).First(&user).Error; err != nil {
		response.NotFound(c, "用户不存在")
		return
	}

	// 获取会话信息
	var chat models.Chat
	if err := h.db.Where("uuid = ?", req.ChatID).First(&chat).Error; err != nil {
		response.NotFound(c, "会话不存在")
		return
	}

	// 清除未读计数，同步更新 last_read_seq
	updateFields := map[string]interface{}{"unread_count": 0}
	if req.MsgSeq > 0 {
		updateFields["last_read_seq"] = req.MsgSeq
	}
	result := h.db.Model(&models.UserChat{}).
		Where("chat_id = ? AND user_id = ?", chat.ID, user.ID).
		Updates(updateFields)

	if result.Error != nil {
		response.ServerError(c, "更新失败")
		return
	}

	// 获取聊天对方的用户 UUID 列表（批量查询，避免 N+1）
	var memberUserIDs2 []uint64
	h.db.Model(&models.ChatMember{}).Where("chat_id = ? AND user_id != ?", chat.ID, user.ID).Pluck("user_id", &memberUserIDs2)

	var targetUserIDs []string
	if len(memberUserIDs2) > 0 {
		h.db.Model(&models.User{}).Where("id IN ?", memberUserIDs2).Pluck("uuid", &targetUserIDs)
	}

	// 持久化：将对方发送的消息标记为已读（存储到 MongoDB）
	if len(targetUserIDs) > 0 && req.MsgSeq > 0 {
		ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
		defer cancel()
		if err := h.msgService.MarkMessagesAsRead(ctx, req.ChatID, userID, req.MsgSeq, targetUserIDs); err != nil {
			// 记录错误但不影响响应
			println("[MarkAsRead] Failed to persist read status:", err.Error())
		}
	}

	// 通过 WebSocket 广播已读状态给对方用户
	if len(targetUserIDs) > 0 {
		h.msgService.BroadcastReadReceipt(req.ChatID, userID, req.MsgSeq, targetUserIDs)
	}

	// ★ 集群改造：同步已读状态到当前用户的其他设备（使用集群版，跨节点投递）
	if h.hub != nil {
		selfSyncPayload := map[string]interface{}{
			"type":         "read_sync",
			"chat_id":      req.ChatID,
			"user_id":      userID,
			"msg_seq":      req.MsgSeq,
			"unread_count": 0,
		}
		h.hub.SendToUserCluster(userID, selfSyncPayload)
	}

	response.Success(c, gin.H{
		"cleared": result.RowsAffected > 0,
	})
}

// AddReactionRequest 添加表情回复请求
type AddReactionRequest struct {
	ChatID string `json:"chat_id" binding:"required"`
	MsgID  string `json:"msg_id" binding:"required"`
	Emoji  string `json:"emoji" binding:"required"`
}

// AddReaction 添加表情回复
func (h *MessageHandler) AddReaction(c *gin.Context) {
	userID := c.GetString("user_id")

	var req AddReactionRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		response.BadRequest(c, "参数错误")
		return
	}

	// 获取用户信息
	var user models.User
	if err := h.db.Where("uuid = ?", userID).First(&user).Error; err != nil {
		response.NotFound(c, "用户不存在")
		return
	}

	// 添加表情回复
	err := h.msgService.AddReaction(c.Request.Context(), req.ChatID, req.MsgID, userID, user.Nickname, req.Emoji)
	if err != nil {
		response.Error(c, 400, sanitizeMessageServiceError(err, "添加表情失败，请稍后重试"))
		return
	}

	response.Success(c, gin.H{"message": "已添加表情回复"})
}

// RemoveReactionRequest 移除表情回复请求
type RemoveReactionRequest struct {
	ChatID string `json:"chat_id" binding:"required"`
	MsgID  string `json:"msg_id" binding:"required"`
	Emoji  string `json:"emoji" binding:"required"`
}

// RemoveReaction 移除表情回复
func (h *MessageHandler) RemoveReaction(c *gin.Context) {
	userID := c.GetString("user_id")

	var req RemoveReactionRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		response.BadRequest(c, "参数错误")
		return
	}

	// 移除表情回复
	err := h.msgService.RemoveReaction(c.Request.Context(), req.ChatID, req.MsgID, userID, req.Emoji)
	if err != nil {
		response.Error(c, 400, sanitizeMessageServiceError(err, "移除表情失败，请稍后重试"))
		return
	}

	response.Success(c, gin.H{"message": "已移除表情回复"})
}

// ForwardMessageRequest 转发消息请求
type ForwardMessageRequest struct {
	SourceChatID string `json:"source_chat_id" binding:"required"`
	SourceMsgID  string `json:"source_msg_id" binding:"required"`
	TargetChatID string `json:"target_chat_id" binding:"required"`
}

// ForwardMessage 转发消息
func (h *MessageHandler) ForwardMessage(c *gin.Context) {
	userID := c.GetString("user_id")

	var req ForwardMessageRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		response.BadRequest(c, "参数错误")
		return
	}

	// 获取发送者信息
	var sender models.User
	if err := h.db.Where("uuid = ?", userID).First(&sender).Error; err != nil {
		response.NotFound(c, "用户不存在")
		return
	}

	// 检查用户是否被封禁
	if sender.Status == models.UserStatusBanned {
		response.Forbidden(c, "您的账号已被封禁，无法转发消息")
		return
	}
	if sender.Status == models.UserStatusDisabled {
		response.Forbidden(c, "您的账号已被禁用")
		return
	}

	var sourceChat models.Chat
	if err := h.db.Where("uuid = ?", req.SourceChatID).First(&sourceChat).Error; err != nil {
		response.NotFound(c, "源会话不存在")
		return
	}
	var sourceMemberCount int64
	h.db.Model(&models.ChatMember{}).
		Where("chat_id = ? AND user_id = ?", sourceChat.ID, sender.ID).
		Count(&sourceMemberCount)
	if sourceMemberCount == 0 {
		response.Forbidden(c, "无权转发该会话消息")
		return
	}

	// 获取目标会话信息
	var targetChat models.Chat
	if err := h.db.Where("uuid = ?", req.TargetChatID).First(&targetChat).Error; err != nil {
		response.NotFound(c, "目标会话不存在")
		return
	}
	if targetChat.Status == models.ChatStatusBanned {
		response.Forbidden(c, "目标群组已被封禁，无法转发消息")
		return
	}
	if targetChat.Status == models.ChatStatusDissolved {
		response.Forbidden(c, "目标群组已被解散")
		return
	}

	var targetMember models.ChatMember
	if err := h.db.Where("chat_id = ? AND user_id = ?", targetChat.ID, sender.ID).First(&targetMember).Error; err != nil {
		response.Forbidden(c, "您不是目标会话成员")
		return
	}
	if targetChat.Type == 3 && targetMember.Role < 1 {
		response.Forbidden(c, "频道仅允许管理员发布内容")
		return
	}
	if targetChat.Type == 2 && !targetChat.CanSendMessage && targetMember.Role < 1 {
		response.Forbidden(c, "群组已开启全员禁言，仅管理员可发言")
		return
	}
	if targetMember.IsMuted {
		if targetMember.MuteEndTime != nil && time.Now().After(*targetMember.MuteEndTime) {
			h.db.Model(&targetMember).Updates(map[string]interface{}{
				"is_muted":      false,
				"mute_end_time": nil,
			})
		} else {
			muteMsg := "您已被禁言"
			if targetMember.MuteEndTime != nil {
				muteMsg = fmt.Sprintf("您已被禁言至 %s", targetMember.MuteEndTime.Format("2006-01-02 15:04"))
			}
			response.Forbidden(c, muteMsg)
			return
		}
	}
	if targetChat.Type == 1 {
		var blockCount int64
		h.db.Model(&models.UserBlock{}).
			Where("user_id IN (SELECT user_id FROM chat_members WHERE chat_id = ? AND user_id != ?) AND blocked_user_id = ?", targetChat.ID, sender.ID, sender.ID).
			Count(&blockCount)
		if blockCount > 0 {
			response.Forbidden(c, "对方已将您屏蔽，无法转发消息")
			return
		}
	}

	// 获取目标用户 UUID 列表（批量查询，避免 N+1）
	var fwdMemberIDs []uint64
	h.db.Model(&models.ChatMember{}).Where("chat_id = ? AND user_id != ?", targetChat.ID, sender.ID).Pluck("user_id", &fwdMemberIDs)

	var targetUserIDs []string
	if len(fwdMemberIDs) > 0 {
		h.db.Model(&models.User{}).Where("id IN ?", fwdMemberIDs).Pluck("uuid", &targetUserIDs)
	}

	// 转发消息
	msg, err := h.msgService.ForwardMessage(c.Request.Context(), req.SourceChatID, req.SourceMsgID, req.TargetChatID, userID, sender.Nickname, sender.Avatar, sender.NicknameColor, sender.PremiumType, sender.EmojiAvatar, targetUserIDs)
	if err != nil {
		if strings.Contains(err.Error(), "阅后即焚消息不支持转发") {
			response.Forbidden(c, "阅后即焚消息不支持转发")
			return
		}
		response.ServerError(c, sanitizeMessageServiceError(err, "转发消息失败，请稍后重试"))
		return
	}

	// 更新 UserChat 的最后消息
	lastMsgText := "[转发消息]"
	h.db.Model(&models.UserChat{}).
		Where("chat_id = ?", targetChat.ID).
		Updates(map[string]interface{}{
			"last_msg_text":   lastMsgText,
			"last_msg_type":   msg.Type,
			"last_msg_time":   msg.CreatedAt,
			"last_msg_seq":    msg.Seq,
			"last_msg_sender": sender.Nickname,
			"sort_time":       msg.CreatedAt,
		})

	// 更新对方的未读数
	h.db.Model(&models.UserChat{}).
		Where("chat_id = ? AND user_id != ?", targetChat.ID, sender.ID).
		UpdateColumn("unread_count", gorm.Expr("unread_count + 1"))

	if h.pushService != nil {
		go func() {
			if len(targetUserIDs) == 0 {
				return
			}
			type userIDPair struct {
				ID   uint64
				UUID string
			}
			var pairs []userIDPair
			h.db.Model(&models.User{}).Where("uuid IN ?", targetUserIDs).Select("id, uuid").Find(&pairs)

			userIDs := make([]uint64, 0, len(pairs))
			for _, p := range pairs {
				userIDs = append(userIDs, p.ID)
			}
				// 获取muted用户（优先走缓存）
				mutedUsers64 := h.getChatMutedMap(context.Background(), targetChat.ID)
				mutedUsers := make(map[uint64]bool, len(mutedUsers64))
				for id := range mutedUsers64 {
					mutedUsers[id] = true
				}

			pushChatType := chatPushType(targetChat.Type)
			for _, p := range pairs {
				if mutedUsers[p.ID] {
					continue
				}
				h.pushService.PushNewMessage(p.ID, sender.Nickname, lastMsgText, req.TargetChatID, pushChatType)
			}
		}()
	}

	response.Success(c, msg)
}

// EditMessageRequest 编辑消息请求
type EditMessageRequest struct {
	ChatID  string                          `json:"chat_id" binding:"required"`
	MsgID   string                          `json:"msg_id" binding:"required"`
	Content string                          `json:"content"`
	E2EE    *models.EncryptedMessagePayload `json:"e2ee"`
}

// EditMessage 编辑消息
func (h *MessageHandler) EditMessage(c *gin.Context) {
	userID := c.GetString("user_id")

	var req EditMessageRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		response.BadRequest(c, "参数错误")
		return
	}
	hasEncryptedPayload := hasValidEncryptedPayload(req.E2EE)
	if req.E2EE != nil && !hasEncryptedPayload {
		response.BadRequest(c, "加密消息载荷无效")
		return
	}
	cryptoMode := h.getMessageCryptoMode()
	switch cryptoMode {
	case models.MessageCryptoModePlain:
		if hasEncryptedPayload {
			response.BadRequest(c, "当前系统已关闭消息加密，请使用明文模式编辑")
			return
		}
	case models.MessageCryptoModeStrict:
		if !hasEncryptedPayload {
			response.BadRequest(c, "严格加密模式下，编辑消息必须使用端到端加密")
			return
		}
	}

	// 编辑消息
	if req.Content == "" && !hasEncryptedPayload {
		response.BadRequest(c, "消息内容不能为空")
		return
	}

	err := h.msgService.EditMessageWithE2EE(c.Request.Context(), req.ChatID, req.MsgID, userID, req.Content, req.E2EE)
	if err != nil {
		response.Error(c, 400, sanitizeMessageServiceError(err, "编辑消息失败，请稍后重试"))
		return
	}

	response.Success(c, gin.H{"message": "消息已编辑"})
}
