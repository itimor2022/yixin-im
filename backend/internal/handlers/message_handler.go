// 文件用途：实现后端 HTTP 接口的请求处理和统一响应。
// 核心逻辑：绑定参数，校验身份与权限，调用业务服务并持久化关键状态。

package handlers

import (
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"github.com/gin-gonic/gin"
	"github.com/google/uuid"
	"gorm.io/gorm"
	"gorm.io/gorm/clause" // MessageHandler 消息处理器
	"io"
	"log"
	"mime/multipart"
	"net/http"
	"net/url"
	"os"
	"path/filepath"
	"strconv"
	"strings"
	"sync"
	"time"
	"genericim/internal/cache"
	"genericim/internal/config"
	"genericim/internal/models"
	"genericim/internal/privacy"
	"genericim/internal/services"
	"genericim/internal/ws"
	"genericim/pkg/response"
)

type MessageHandler struct {
	db                         *gorm.DB
	msgService                 *services.MessageService
	pushService                *services.PushService
	hub                        *ws.Hub
	cache                      *cache.Cache
	serviceConversationService *services.ServiceConversationService
	messageProjectionQueue     chan messageProjectionBatch
	messageProjectionBatcher   *messageProjectionBatcher
	messageProjectionLocks     [64]sync.Mutex
	messageNotificationQueue   chan func()
	messagePushBatcher         *messagePushBatcher
	chatListCacheBatcher       *chatListCacheInvalidationBatcher
	messageMediaCommitBatcher  *messageMediaCommitBatcher
	messageOutboxWake          chan struct{}
}

type messageProjectionTask struct {
	chat            models.Chat
	message         models.Message
	sender          models.User
	senderName      string
	memberUserIDs   []uint64
	lastMsgText     string
	lastMsgMediaURL string
	mentionAll      bool
	mentionUUIDs    []string
}

const (
	messageProjectionQueueSize = 8192
	messageProjectionWorkers   = 4
	messageNotificationWorkers = 4
)

var (
	errChatWriteBanned    = errors.New("chat write banned")
	errChatWriteDissolved = errors.New("chat write dissolved")
) // withChatWriteLock serializes message mutations with chat dissolution. The // dissolve path locks the same SQL row, so a write is either committed before // dissolution or rejected after it; it cannot slip through a stale status // check while the terminal transition is in progress.
func (h *MessageHandler) withChatWriteLock(
	ctx context.Context,
	chatID uint64,
	operation func() error) error {
	return h.db.WithContext(ctx).Transaction(func(tx *gorm.DB) error {
		var lockedChat models.Chat
		if err := tx.Clauses(clause.Locking{Strength: "UPDATE"}).
			Select("id", "status").
			Where("id = ?", chatID).
			First(&lockedChat).Error; err != nil {

			return err

		}

		switch lockedChat.Status {

		case models.ChatStatusBanned:

			return errChatWriteBanned

		case models.ChatStatusDissolved:

			return errChatWriteDissolved

		default:

			return operation()

		}
	})
}
func respondChatWriteError(c *gin.Context, err error, fallback string) bool {
	switch {
	case errors.Is(err, errChatWriteBanned):

		response.Forbidden(c, "该群组已被管理员封禁，无法操作")

		return true
	case errors.Is(err, errChatWriteDissolved):

		response.Forbidden(c, "该群组已被解散，仅可查看历史消息")

		return true
	case err != nil:

		response.ServerError(c, sanitizeMessageServiceError(err, fallback))

		return true
	default:

		return false
	}
}
func (h *MessageHandler) SetServiceConversationService(service *services.ServiceConversationService) {
	h.serviceConversationService = service
	h.signalMessageOutbox()
}

// NewMessageHandler 创建消息处理器
func NewMessageHandler(db *gorm.DB, msgService *services.MessageService, pushService *services.PushService, hub *ws.Hub, c ...*cache.Cache) *MessageHandler {
	h := &MessageHandler{
		db:                       db,
		msgService:               msgService,
		pushService:              pushService,
		hub:                      hub,
		messageProjectionQueue:   make(chan messageProjectionBatch, messageProjectionQueueSize),
		messageNotificationQueue: make(chan func(), messageProjectionQueueSize),
	}
	if len(c) > 0 && c[0] != nil {

		h.cache = c[0]
	}
	h.messageProjectionBatcher = newMessageProjectionBatcher(
		250*time.Millisecond,
		func(batch messageProjectionBatch) {
			h.messageProjectionQueue <- batch
		},
	)
	for i := 0; i < messageProjectionWorkers; i++ {
		go h.runMessageProjectionWorker()
	}
	for i := 0; i < messageNotificationWorkers; i++ {
		go h.runMessageNotificationWorker()
	}
	h.messagePushBatcher = newMessagePushBatcher(
		500*time.Millisecond,
		func(task messagePushTask) {
			h.enqueueMessageNotification(func() {
				h.sendBatchedMessagePush(task)
			})
		},
	)
	h.chatListCacheBatcher = newChatListCacheInvalidationBatcher(
		500*time.Millisecond,
		func(chatID uint64) {
			h.enqueueMessageNotification(func() {
				h.invalidateChatListCacheForMembers(chatID)
			})
		},
	)
	h.messageMediaCommitBatcher = newMessageMediaCommitBatcher(
		500*time.Millisecond,
		func(mediaIDs []string) {
			h.enqueueMessageNotification(func() {
				if err := services.CommitMessageMediaBatch(h.db, mediaIDs); err != nil {
					log.Printf("[MessageMediaCommitBatch] commit failed media_count=%d err=%v", len(mediaIDs), err)
				}
			})
		},
	)
	h.startMessageOutboxWorkers()
	return h
}

// getIntSetting 读取整型配置，优先从 Redis 缓存取（TTL 60s），避免每次查 DB
func (h *MessageHandler) runMessageProjectionWorker() {
	for batch := range h.messageProjectionQueue {
		func() {
			defer func() {
				if recovered := recover(); recovered != nil {
					log.Printf("[MessageProjection] panic chatID=%s msgID=%s recovered=%v", batch.chat.UUID, batch.latestMessage.MsgID, recovered)
				}
			}()
			lock := &h.messageProjectionLocks[batch.chat.ID%uint64(len(h.messageProjectionLocks))]
			lock.Lock()
			defer lock.Unlock()
			h.applyMessageProjection(batch)
		}()
	}
}

func (h *MessageHandler) enqueueMessageProjection(task messageProjectionTask) {
	if h == nil || h.messageProjectionBatcher == nil {
		return
	}
	h.messageProjectionBatcher.enqueue(task)
}

func (h *MessageHandler) runMessageNotificationWorker() {
	for task := range h.messageNotificationQueue {
		func() {
			defer func() {
				if recovered := recover(); recovered != nil {
					log.Printf("[MessageNotification] panic recovered=%v", recovered)
				}
			}()
			task()
		}()
	}
}

func (h *MessageHandler) enqueueMessageNotification(task func()) {
	if h == nil || h.messageNotificationQueue == nil || task == nil {
		return
	}
	h.messageNotificationQueue <- task
}

func (h *MessageHandler) applyMessageProjection(batch messageProjectionBatch) {
	if err := h.applyMessageProjectionDB(h.db, batch); err != nil {
		log.Printf("[MessageProjection] apply database projection failed chatID=%s msgID=%s err=%v", batch.chat.UUID, batch.latestMessage.MsgID, err)
		return
	}
	if err := h.applyMessageProjectionPost(context.Background(), batch); err != nil {
		log.Printf("[MessageProjection] apply post projection failed chatID=%s msgID=%s err=%v", batch.chat.UUID, batch.latestMessage.MsgID, err)
	}
}

func (h *MessageHandler) applyMessageProjectionDB(db *gorm.DB, batch messageProjectionBatch) error {
	if h == nil || db == nil || batch.chat.ID == 0 || batch.latestMessage.MsgID == "" || batch.messageCount <= 0 {
		return nil
	}
	msg := &batch.latestMessage

	// Workers may finish out of order. Only a newer sequence can replace the
	// conversation preview, while every committed message increments unread.
	if err := db.Model(&models.UserChat{}).
		Where("chat_id = ? AND last_msg_seq < ?", batch.chat.ID, msg.Seq).
		Updates(map[string]interface{}{
			"last_msg_text":      batch.lastMsgText,
			"last_msg_type":      msg.Type,
			"last_msg_time":      msg.CreatedAt,
			"last_msg_seq":       msg.Seq,
			"last_msg_sender":    batch.senderName,
			"last_msg_media_url": batch.lastMsgMediaURL,
			"sort_time":          msg.CreatedAt,
		}).Error; err != nil {
		return err
	}
	unreadExpr := "unread_count + ?"
	unreadArgs := make([]interface{}, 0, 1+len(batch.senderCounts)*2)
	unreadArgs = append(unreadArgs, batch.messageCount)
	if len(batch.senderCounts) > 0 {
		unreadExpr += " - CASE user_id"
		for senderID, count := range batch.senderCounts {
			unreadExpr += " WHEN ? THEN ?"
			unreadArgs = append(unreadArgs, senderID, count)
		}
		unreadExpr += " ELSE 0 END"
	}
	if err := db.Model(&models.UserChat{}).
		Where("chat_id = ?", batch.chat.ID).
		UpdateColumn("unread_count", gorm.Expr(unreadExpr, unreadArgs...)).Error; err != nil {
		return err
	}

	if len(batch.mentionAllSenderIDs) > 0 {
		query := db.Model(&models.UserChat{}).Where("chat_id = ?", batch.chat.ID)
		if len(batch.mentionAllSenderIDs) == 1 {
			for senderID := range batch.mentionAllSenderIDs {
				query = query.Where("user_id != ?", senderID)
			}
		}
		if err := query.Update("has_mention", true).Error; err != nil {
			return err
		}
	}
	if len(batch.mentionUUIDs) > 0 {
		mentionUUIDs := make([]string, 0, len(batch.mentionUUIDs))
		for userUUID := range batch.mentionUUIDs {
			mentionUUIDs = append(mentionUUIDs, userUUID)
		}
		var mentionedUserIDs []uint64
		if err := db.Model(&models.User{}).
			Where("uuid IN ?", mentionUUIDs).
			Pluck("id", &mentionedUserIDs).Error; err != nil {
			return err
		}
		if len(mentionedUserIDs) > 0 {
			if err := db.Model(&models.UserChat{}).
				Where("chat_id = ? AND user_id IN ?", batch.chat.ID, mentionedUserIDs).
				Update("has_mention", true).Error; err != nil {
				return err
			}
		}
	}
	return nil
}

func (h *MessageHandler) applyMessageProjectionPost(ctx context.Context, batch messageProjectionBatch) error {
	if h == nil || h.db == nil || batch.chat.ID == 0 || batch.latestMessage.MsgID == "" || batch.messageCount <= 0 {
		return nil
	}
	msg := &batch.latestMessage

	userIDs := append([]uint64{batch.sender.ID}, batch.memberUserIDs...)
	if batch.chat.Type == 1 {
		if err := bumpUserChatListHotCacheVersions(ctx, h.cache, userIDs...); err != nil {
			return err
		}
	} else {
		if err := h.db.Model(&models.UserChat{}).
			Where("chat_id = ?", batch.chat.ID).
			Pluck("user_id", &userIDs).Error; err != nil {
			return err
		}
		if err := bumpUserChatListHotCacheVersions(ctx, h.cache, userIDs...); err != nil {
			return err
		}
	}
	return h.broadcastChatStateAfterMessageWithError(&batch.chat, msg, userIDs)
}

func (h *MessageHandler) getIntSetting(key string, defaultVal int) int {
	cacheKey := "setting:" + key
	// 尝试从缓存读取
	if h.cache != nil {
		var cached int
		if err := h.cache.Get(context.Background(), cacheKey, &cached); err == nil {

			return cached

		}
	}
	// 缓存未命中，查数据库
	var s models.SystemSetting
	if err := h.db.Where("`key` = ?", key).First(&s).Error; err != nil {

		return defaultVal
	}
	val := defaultVal
	if v, err := strconv.Atoi(s.Value); err == nil {

		val = v
	}
	// 写入缓存，60 秒过期
	if h.cache != nil {

		_ = h.cache.Set(context.Background(), cacheKey, val, 60*time.Second)
	}
	return val
}
func (h *MessageHandler) getStringSetting(key, defaultVal string) string {
	cacheKey := "setting:" + key
	if h.cache != nil {
		var cached string
		if err := h.cache.Get(context.Background(), cacheKey, &cached); err == nil {

			if strings.TrimSpace(cached) != "" {

				return cached

			}

			return defaultVal

		}
	}
	var s models.SystemSetting
	if err := h.db.Where("`key` = ?", key).First(&s).Error; err != nil {

		return defaultVal
	}
	val := strings.TrimSpace(s.Value)
	if val == "" {

		val = defaultVal
	}
	if h.cache != nil {

		_ = h.cache.Set(context.Background(), cacheKey, val, 60*time.Second)
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

			"user_id": userID,

			"chat_id": chat.ID,

			"target_id": targetID,

			"is_archived": false,

			"sort_time": effectiveTime,

			"updated_at": effectiveTime,
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
	MentionAll       bool                            `json:"mention_all"`
	BurnAfterRead    bool                            `json:"burn_after_read"`
	BurnAfterSeconds int                             `json:"burn_after_seconds"`
	Anonymous        bool                            `json:"anonymous"`
	SourceChatID     string                          `json:"source_chat_id"`
	SourceMsgIDs     []string                        `json:"source_msg_ids"`
	MediaIDs         []string                        `json:"media_ids"`
}

// ReplyToRequest 回复消息
type ReplyToRequest struct {
	MsgID      string `json:"msg_id"`
	SenderID   string `json:"sender_id"`
	SenderName string `json:"sender_name"`
	Content    string `json:"content"`
}

func messageAckPayload(msg *models.Message, duplicate bool, clientMsgID string) gin.H {
	if msg == nil {

		return gin.H{}
	}
	payload := publicMessagePayload(msg)
	if len(payload) == 0 {

		payload["msg_id"] = msg.MsgID

		payload["chat_id"] = msg.ChatID

		payload["seq"] = msg.Seq

		payload["status"] = msg.Status
	}
	clientMsgID = strings.TrimSpace(clientMsgID)
	if clientMsgID == "" {

		clientMsgID = msg.MsgID
	}
	payload["client_msg_id"] = clientMsgID
	payload["server_msg_id"] = msg.MsgID
	payload["server_seq"] = msg.Seq
	payload["duplicate"] = duplicate
	if duplicate {

		payload["ack_status"] = "duplicate"
	} else {

		payload["ack_status"] = "sent"
	}
	return payload
}
func publicMessagePayload(msg *models.Message) gin.H {
	payload := gin.H{}
	if msg == nil {

		return payload
	}
	raw, err := json.Marshal(msg)
	if err == nil {

		_ = json.Unmarshal(raw, &payload)
	}
	if msg.IsAnonymous {

		payload["sender_id"] = "anonymous"

		payload["sender_name"] = msg.SenderName

		payload["sender_avatar"] = ""

		payload["sender_nickname_color"] = ""

		payload["sender_emoji_avatar"] = ""

		payload["sender_device_id"] = ""

		payload["is_anonymous"] = true
	}
	return payload
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
	for _, key := range []string{"media", "voice", "file", "location", "contact", "sticker"} {

		if value, ok := content[key].(map[string]interface{}); ok && len(value) > 0 {

			return true

		}
	}
	return false
}
func messageRequestHasMediaID(req *SendMessageRequest) bool {
	if req == nil {

		return false
	}
	for _, value := range req.MediaIDs {

		if strings.TrimSpace(value) != "" {

			return true

		}
	}
	for _, key := range []string{"media", "voice", "file"} {

		nested, ok := req.Content[key].(map[string]interface{})

		if !ok {

			continue

		}

		if value, ok := nested["media_id"].(string); ok && strings.TrimSpace(value) != "" {

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
func sanitizeMessageMentions(raw []string, allowedUUIDs ...string) []string {
	if len(raw) == 0 {

		return nil
	}
	allowed := make(map[string]struct{}, len(allowedUUIDs))
	for _, uuid := range allowedUUIDs {

		uuid = strings.TrimSpace(uuid)

		if uuid == "" {

			continue

		}

		allowed[uuid] = struct{}{}
	}
	if len(allowed) == 0 {

		return nil
	}
	seen := make(map[string]struct{}, len(raw))
	mentions := make([]string, 0, len(raw))
	for _, uuid := range raw {

		uuid = strings.TrimSpace(uuid)

		if uuid == "" {

			continue

		}

		if _, ok := allowed[uuid]; !ok {

			continue

		}

		if _, ok := seen[uuid]; ok {

			continue

		}

		seen[uuid] = struct{}{}
		mentions = append(mentions, uuid)

		if len(mentions) >= 50 {

			break

		}
	}
	return mentions
}

const mentionAllSentinel = "__all__"
const maxTextMessageRunes = 5000

func validateTextMessageLength(messageType int, content map[string]interface{}) bool {
	if messageType != models.MsgTypeText {

		return true
	}
	text, ok := content["text"].(string)
	return !ok || len([]rune(text)) <= maxTextMessageRunes
}
func validateMessageMentions(raw []string, maxMentions int, allowedUUIDs ...string) ([]string, bool) {
	if len(raw) == 0 {

		return nil, true
	}
	if maxMentions <= 0 {

		return nil, false
	}
	allowed := make(map[string]struct{}, len(allowedUUIDs))
	for _, id := range allowedUUIDs {

		if id = strings.TrimSpace(id); id != "" {

			allowed[id] = struct{}{}

		}
	}
	seen := make(map[string]struct{}, len(raw))
	mentions := make([]string, 0, len(raw))
	for _, rawID := range raw {
		id := strings.TrimSpace(rawID)

		if id == "" || id == mentionAllSentinel {

			return nil, false

		}

		if _, ok := allowed[id]; !ok {

			return nil, false

		}

		if _, duplicate := seen[id]; duplicate {

			continue

		}

		seen[id] = struct{}{}
		mentions = append(mentions, id)

		if len(mentions) > maxMentions {

			return nil, false

		}
	}
	return mentions, true
}
func canUseMentionAll(chatType int8, storedRole int8) bool {
	return chatType != 1 && storedRole >= 1
}

func (h *MessageHandler) SendMessage(c *gin.Context) {
	userID := c.GetString("user_id")
	var req SendMessageRequest
	if err := c.ShouldBindJSON(&req); err != nil {

		response.BadRequest(c, "参数错误")

		return
	}
	if messageRequestHasMediaID(&req) && strings.TrimSpace(req.MsgID) == "" {

		req.MsgID = uuid.NewString()
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
	isForwardBundleRequest := req.Type == models.MsgTypeForwardBundle &&

		strings.TrimSpace(req.SourceChatID) != "" && len(req.SourceMsgIDs) >= 2
	if !hasEncryptedPayload && !isForwardBundleRequest && !hasPlainMessageContent(req.Content) {

		response.BadRequest(c, "消息内容不能为空")

		return
	}
	if !hasEncryptedPayload && !validateTextMessageLength(req.Type, req.Content) {

		response.BadRequest(c, "消息内容不能超过5000个字符")

		return
	}
	// 频率限制检查
	if !h.checkMessageRateLimit(c, userID) {

		return
	}
	// 获取发送者信息
	var sender models.User
	if err := h.db.Where("uuid = ?", userID).First(&sender).Error; err != nil {

		response.NotFound(c, "用户不存在")

		return
	}
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
	// 获取会话信息和成员列表
	var chat models.Chat
	if err := h.db.Where("uuid = ?", req.ChatID).First(&chat).Error; err != nil {

		response.NotFound(c, "会话不存在")

		return
	}
	// 检查会话是否被封禁或解散
	if chat.Status == models.ChatStatusBanned {

		response.Forbidden(c, "该群组已被管理员封禁，无法发送消息")

		return
	}
	if chat.Status == models.ChatStatusDissolved {

		response.Forbidden(c, "该群组已被解散")

		return
	}
	// 群组和频道检查禁言状态和权限
	var senderMember models.ChatMember
	if err := h.db.Where("chat_id = ? AND user_id = ?", chat.ID, sender.ID).First(&senderMember).Error; err != nil {

		response.Forbidden(c, "您不是该会话成员")

		return
	}
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

		if !chat.CanSendMedia && senderMember.Role < 1 && (req.Type == 2 || req.Type == 3 || req.Type == 4 || req.Type == 5) {

			response.Forbidden(c, "群组已禁止发送媒体内容")

			return

		}

		// 检查是否被禁言（个人禁言）

		if senderMember.IsMuted {

			// 检查禁言是否过期

			if senderMember.MuteEndTime != nil && time.Now().After(*senderMember.MuteEndTime) {

				// 禁言已过期，自动解除

				h.db.Model(&senderMember).Updates(map[string]interface{}{

					"is_muted": false,

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
	// 群聊普通发送不再在 ACK 链路读取全体成员。所有客户端会订阅自己的会话，
	// WebSocket 可直接按 chatID 广播；投影缓存和离线推送在短窗口后台批量取成员。
	// 私聊仍同步取得另一方；群聊只有实际携带 @ 时才校验最多 50 个指定成员。
	var memberUserIDs []uint64
	var memberTargets []messagePushTarget
	var targetUserIDs []string
	if chat.Type == 1 {
		if err := h.db.Table("chat_members AS cm").
			Select("cm.user_id AS user_id, u.uuid AS uuid").
			Joins("JOIN users AS u ON u.id = cm.user_id").
			Where("cm.chat_id = ? AND cm.user_id != ?", chat.ID, sender.ID).
			Scan(&memberTargets).Error; err != nil {
			response.ServerError(c, "读取会话成员失败")
			return
		}
		memberUserIDs = make([]uint64, 0, len(memberTargets))
		targetUserIDs = make([]string, 0, len(memberTargets))
		for _, target := range memberTargets {
			memberUserIDs = append(memberUserIDs, target.UserID)
			targetUserIDs = append(targetUserIDs, target.UUID)
		}
	} else if len(req.Mentions) > 0 {
		requestedMentions := make([]string, 0, len(req.Mentions))
		for _, mention := range req.Mentions {
			if mention = strings.TrimSpace(mention); mention != "" {
				requestedMentions = append(requestedMentions, mention)
			}
		}
		if len(requestedMentions) > 0 {
			if err := h.db.Table("chat_members AS cm").
				Select("u.uuid").
				Joins("JOIN users AS u ON u.id = cm.user_id").
				Where("cm.chat_id = ? AND cm.user_id != ? AND u.uuid IN ?", chat.ID, sender.ID, requestedMentions).
				Pluck("u.uuid", &targetUserIDs).Error; err != nil {
				response.ServerError(c, "校验提及成员失败")
				return
			}
		}
	}
	mentionLimit := 10
	if senderMember.Role >= 1 {

		mentionLimit = 50
	}
	validatedMentions, validMentions := validateMessageMentions(

		req.Mentions,

		mentionLimit,

		targetUserIDs...,
	)
	if !validMentions {

		response.Forbidden(c, "提及成员无效或超过数量限制")

		return
	}
	if req.MentionAll {

		if !canUseMentionAll(chat.Type, senderMember.Role) {

			response.Forbidden(c, "只有群管理员可以使用全员提及")

			return

		}

		if h.cache != nil {

			allowed, err := h.cache.RateLimit(

				c.Request.Context(),

				"mention_all:"+chat.UUID+":"+userID,

				1,

				time.Minute,
			)

			if err != nil || !allowed {

				response.TooManyRequests(c, "全员提及过于频繁，请稍后再试")

				return

			}

		}
		validatedMentions = append(validatedMentions, mentionAllSentinel)
	}
	req.Mentions = validatedMentions
	// Group/channel membership flows create UserChat rows. Re-upserting every
	// member on every message causes all concurrent sends to lock the same rows.
	// Keep the defensive repair only for the two-row private-chat path.
	if chat.Type == 1 {
		if err := h.ensureUserChatRecords(&chat, append([]uint64{sender.ID}, memberUserIDs...), time.Now()); err != nil {
			log.Printf("[Message] ensure private user_chats before send failed chatID=%d err=%v", chat.ID, err)
		}
	}
	// 私聊：任一方向存在屏蔽关系时都不允许继续发送。
	if chat.Type == 1 && len(memberUserIDs) > 0 {
		var blockCount int64
		if err := h.db.Model(&models.UserBlock{}).
			Where(

				"(user_id IN ? AND blocked_user_id = ?) OR (user_id = ? AND blocked_user_id IN ?)",

				memberUserIDs,

				sender.ID,

				sender.ID,

				memberUserIDs,
			).
			Count(&blockCount).Error; err != nil {

			response.ServerError(c, "检查屏蔽关系失败")

			return

		}

		if blockCount > 0 {

			response.Forbidden(c, "存在屏蔽关系，无法发送消息")

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
	if req.Anonymous && chat.Type != 2 {

		response.BadRequest(c, "匿名发言仅支持群组")

		return
	}
	if req.Anonymous && !chat.AllowAnonymous {

		response.Forbidden(c, "群主未开启匿名发言")

		return
	}
	if req.Type == models.MsgTypeForwardBundle {

		bundle, ok := h.prepareForwardBundle(c, &sender, &req)

		if !ok {

			return

		}
		raw, err := json.Marshal(bundle)

		if err != nil {

			response.ServerError(c, "failed to create forwarded record")

			return

		}
		var bundleMap map[string]interface{}

		if err := json.Unmarshal(raw, &bundleMap); err != nil {

			response.ServerError(c, "failed to create forwarded record")

			return

		}

		req.Content = map[string]interface{}{"forward_bundle": bundleMap}
	}
	senderName := sender.Nickname
	senderAvatar := sender.Avatar
	senderNicknameColor := sender.NicknameColor
	senderEmojiAvatar := sender.EmojiAvatar
	if req.Anonymous {

		senderName = "匿名成员"

		senderAvatar = ""

		senderNicknameColor = ""

		senderEmojiAvatar = ""
	}
	burnAfterReadEnabled := !isSystemSettingFalse(

		h.getStringSetting(models.SettingBurnAfterReadEnabled, "true"),
	)
	if !burnAfterReadEnabled {

		req.BurnAfterRead = false

		req.BurnAfterSeconds = 0
	}
	// 转换回复信息
	if req.ReplyTo != nil {

		replyTarget, found, err := h.msgService.FindMessageByMsgID(

			c.Request.Context(),

			req.ChatID,

			req.ReplyTo.MsgID,
		)

		if err != nil {

			response.ServerError(c, "引用消息校验失败")

			return

		}

		if found && replyTarget.BurnAfterRead {

			response.Forbidden(c, "阅后即焚消息不支持引用")

			return

		}
	}
	var replyTo *services.ReplyInfo
	if req.ReplyTo != nil {

		replyTo = &services.ReplyInfo{

			MsgID: req.ReplyTo.MsgID,

			SenderID: req.ReplyTo.SenderID,

			SenderName: req.ReplyTo.SenderName,

			Content: req.ReplyTo.Content,
		}
	}
	var reservedMediaIDs []string
	var err error
	reservedMediaIDs, err = services.ReserveMessageMedia(

		h.db,

		sender.ID,

		req.MsgID,

		req.ChatID,

		req.Type,

		req.Content,

		req.MediaIDs,
	)
	if err != nil {

		if services.IsMessageMediaError(err) {

			response.BadRequest(c, err.Error())

			return

		}

		log.Printf("[Message] reserve media failed userID=%d msgID=%s err=%v", sender.ID, req.MsgID, err)

		response.ServerError(c, "校验上传文件失败，请稍后重试")

		return
	}
	// 媒体先进入“预留”态，只有消息持久化成功后才绑定；发送失败则释放，
	// 避免孤立上传对象被误认为已被消息引用。
	// 最终写入在会话行锁内执行，与解散事务形成严格先后关系。
	var sendResult *services.SendMessageResult
	var sendErr error

	sendResult, sendErr = h.msgService.SendMessageWithResult(c.Request.Context(), &services.SendMessageParams{

		ChatID: req.ChatID,

		SenderID: userID,

		SenderDeviceID: c.GetString("device_id"),

		Type: req.Type,

		Content: req.Content,

		E2EE: req.E2EE,

		MsgID: req.MsgID,

		ReplyTo: replyTo,

		Mentions: req.Mentions,

		BurnAfterRead: req.BurnAfterRead,

		BurnAfterSeconds: req.BurnAfterSeconds,

		Anonymous: req.Anonymous,
	}, senderName, senderAvatar, senderNicknameColor, senderEmojiAvatar, targetUserIDs)
	err = sendErr
	if err != nil {

		services.ReleaseMessageMedia(h.db, reservedMediaIDs, req.MsgID)

		log.Printf("[Message] SendMessageWithResult error chatID=%s userID=%s msgID=%s type=%d err=%v", req.ChatID, userID, req.MsgID, req.Type, err)

		respondChatWriteError(c, err, "消息发送失败，请稍后重试")

		return
	}
	if sendResult == nil || sendResult.Message == nil {

		services.ReleaseMessageMedia(h.db, reservedMediaIDs, req.MsgID)

		response.ServerError(c, "消息发送失败")

		return
	}
	msg := sendResult.Message
	// MongoDB 消息已经提交；UserChat 是用于会话列表、未读数和排序的 MySQL 派生投影。
	// 派生工作先写入 MySQL Outbox，再由可恢复 worker 批量处理。若此处失败，
	// 客户端使用同一个 msg_id 重试即可补写唯一事件，不会重复插入 Mongo 消息。
	lastMsgText := buildUserChatMessagePreview(msg, hasEncryptedPayload)
	lastMsgMediaURL := services.MessagePreviewMediaURL(msg)
	mentionAll := false
	mentionUUIDs := make([]string, 0, len(req.Mentions))
	for _, mention := range req.Mentions {

		if mention == mentionAllSentinel {

			mentionAll = true

			continue

		}
		mentionUUIDs = append(mentionUUIDs, mention)
	}
	pushPreviewText := lastMsgText
	if req.BurnAfterRead {

		pushPreviewText = services.BurnAfterReadPreviewText()
	} else if hasEncryptedPayload {

		pushPreviewText = services.EncryptedPushPreviewText()
	}
	payloadMemberIDs := []uint64(nil)
	if chat.Type == 1 {
		payloadMemberIDs = append(payloadMemberIDs, memberUserIDs...)
	}
	outboxPayload := messageOutboxPayload{
		ChatID:           chat.ID,
		ChatUUID:         chat.UUID,
		ChatType:         chat.Type,
		MessageID:        msg.MsgID,
		MessageSeq:       msg.Seq,
		MessageType:      msg.Type,
		MessageCreatedAt: msg.CreatedAt,
		SenderUserID:     sender.ID,
		SenderUUID:       sender.UUID,
		SenderName:       senderName,
		MemberUserIDs:    payloadMemberIDs,
		LastMsgText:      lastMsgText,
		LastMsgMediaURL:  lastMsgMediaURL,
		MentionAll:       mentionAll,
		MentionUUIDs:     append([]string(nil), mentionUUIDs...),
		PushPreviewText:  pushPreviewText,
		PushChatType:     chatPushType(chat.Type),
		ReservedMediaIDs: append([]string(nil), reservedMediaIDs...),
	}
	eventTypes := []string{models.MessageOutboxTypeProjection}
	if len(reservedMediaIDs) > 0 {
		eventTypes = append(eventTypes, models.MessageOutboxTypeMediaCommit)
	}
	if h.pushService != nil {
		eventTypes = append(eventTypes, models.MessageOutboxTypePush)
	}
	if h.serviceConversationService != nil && chat.Type == 1 {
		eventTypes = append(eventTypes, models.MessageOutboxTypeServiceConversation)
	}
	if err := h.ensureMessageOutboxEvents(c.Request.Context(), outboxPayload, eventTypes...); err != nil {
		log.Printf("[MessageOutbox] persist failed chatID=%s msgID=%s err=%v", chat.UUID, msg.MsgID, err)
		response.ServerError(c, "消息已保存，派生状态同步失败，请使用相同消息ID重试")
		return
	}
	if sendResult.Duplicate {
		response.Success(c, messageAckPayload(msg, true, req.MsgID))
		return
	}
	log.Printf("[Message] Sent message: chatId=%s, msgId=%s, seq=%d, type=%d",

		msg.ChatID, msg.MsgID, msg.Seq, msg.Type)
	response.Success(c, messageAckPayload(msg, false, req.MsgID))
}
func (h *MessageHandler) broadcastChatStateAfterMessage(chat *models.Chat, msg *models.Message, userIDs []uint64) {
	if err := h.broadcastChatStateAfterMessageWithError(chat, msg, userIDs); err != nil {
		log.Printf("[ChatState] broadcast after message failed chatID=%s msgID=%s err=%v", chat.UUID, msg.MsgID, err)
	}
}

func (h *MessageHandler) broadcastChatStateAfterMessageWithError(chat *models.Chat, msg *models.Message, userIDs []uint64) error {
	if h == nil || h.hub == nil || h.db == nil || chat == nil || msg == nil || len(userIDs) == 0 {

		return nil
	}
	// Group recipients already receive the authoritative new_message event.
	// Only the sender needs a personalized multi-device chat-state sync.
	if chat.Type != 1 && len(userIDs) > 1 {
		userIDs = userIDs[:1]
	}
	seen := make(map[uint64]struct{}, len(userIDs))
	uniqueIDs := make([]uint64, 0, len(userIDs))
	for _, id := range userIDs {

		if id == 0 {

			continue

		}

		if _, ok := seen[id]; ok {

			continue

		}

		seen[id] = struct{}{}
		uniqueIDs = append(uniqueIDs, id)
	}
	if len(uniqueIDs) == 0 {

		return nil
	}
	var userChats []models.UserChat
	if err := h.db.
		Where("chat_id = ? AND user_id IN ?", chat.ID, uniqueIDs).
		Find(&userChats).Error; err != nil {

		return err
	}
	type userUUIDRow struct {
		ID uint64 `gorm:"column:id"`

		UUID string `gorm:"column:uuid"`
	}
	var users []userUUIDRow
	if err := h.db.Model(&models.User{}).
		Where("id IN ?", uniqueIDs).
		Select("id, uuid").
		Find(&users).Error; err != nil {

		return err
	}
	uuidByID := make(map[uint64]string, len(users))
	for _, user := range users {

		uuidByID[user.ID] = user.UUID
	}
	var memberCursors []models.ChatMember
	if err := h.db.
		Where("chat_id = ? AND user_id IN ?", chat.ID, uniqueIDs).
		Select("user_id", "last_read_seq").
		Find(&memberCursors).Error; err != nil {
		return err
	}
	lastReadSeqByID := make(map[uint64]uint64, len(memberCursors))
	for _, member := range memberCursors {
		lastReadSeqByID[member.UserID] = member.LastReadSeq
	}
	for i := range userChats {
		uc := &userChats[i]

		userUUID := uuidByID[uc.UserID]

		if userUUID == "" {

			continue

		}

		sendUserChatStateChanged(

			h.hub,

			userUUID,

			chat.UUID,

			uc,

			lastReadSeqByID[uc.UserID],

			"last_msg_seq",

			"unread_count",

			"has_mention",
		)
	}
	return nil
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

		ChatID: req.ChatID,

		UserID: userID,

		BeforeSeq: req.BeforeSeq,

		Limit: req.Limit,
	})
	if err != nil {

		log.Printf("[Message] GetMessages error: %v", err)

		response.ServerError(c, sanitizeMessageServiceError(err, "消息加载失败，请稍后重试"))

		return
	}
	log.Printf("[Message] GetMessages chatId=%s, beforeSeq=%d, limit=%d, returned=%d messages",

		req.ChatID, req.BeforeSeq, req.Limit, len(messages))
	h.markPrivateMessagesDelivered(&chat, userID, messages)
	response.Success(c, h.messagesWithSenderVip(messages))
}
func (h *MessageHandler) markPrivateMessagesDelivered(chat *models.Chat, receiverUUID string, messages []*models.Message) {
	if h == nil || h.msgService == nil || chat == nil || chat.Type != 1 || receiverUUID == "" || len(messages) == 0 {

		return
	}
	senderSet := make(map[string]struct{})
	maxSeq := uint64(0)
	for _, msg := range messages {

		if msg == nil || msg.SenderID == "" || msg.SenderID == receiverUUID || msg.Seq == 0 {

			continue

		}

		senderSet[msg.SenderID] = struct{}{}

		if msg.Seq > maxSeq {

			maxSeq = msg.Seq

		}
	}
	if maxSeq == 0 || len(senderSet) == 0 {

		return
	}
	senderIDs := make([]string, 0, len(senderSet))
	for senderID := range senderSet {

		senderIDs = append(senderIDs, senderID)
	}
	chatUUID := chat.UUID
	msgSeq := int(maxSeq)
	go func() {

		deliverCtx, cancel := context.WithTimeout(context.Background(), 3*time.Second)

		defer cancel()

		if err := h.msgService.MarkMessagesAsDelivered(deliverCtx, chatUUID, receiverUUID, msgSeq, senderIDs); err != nil {

			log.Printf("[Message] Persist delivered status failed chatId=%s receiver=%s seq=%d err=%v",

				chatUUID, receiverUUID, msgSeq, err)

			return

		}

		h.msgService.BroadcastDeliveryReceipt(chatUUID, receiverUUID, msgSeq, senderIDs)
	}()
}
func (h *MessageHandler) messagesWithSenderVip(messages []*models.Message) []gin.H {
	result := make([]gin.H, 0, len(messages))
	if len(messages) == 0 {

		return result
	}
	senderUUIDs := make([]string, 0, len(messages))
	seenUUIDs := make(map[string]struct{}, len(messages))
	for _, msg := range messages {

		if msg == nil || msg.SenderID == "" || msg.IsAnonymous {

			continue

		}

		if _, ok := seenUUIDs[msg.SenderID]; ok {

			continue

		}

		seenUUIDs[msg.SenderID] = struct{}{}
		senderUUIDs = append(senderUUIDs, msg.SenderID)
	}
	userIDByUUID := make(map[string]uint64, len(senderUUIDs))
	userByUUID := make(map[string]models.User, len(senderUUIDs))
	userIDs := make([]uint64, 0, len(senderUUIDs))
	if len(senderUUIDs) > 0 {
		var users []models.User

		h.db.Where("uuid IN ?", senderUUIDs).Find(&users)

		for _, user := range users {

			userIDByUUID[user.UUID] = user.ID

			userByUUID[user.UUID] = user

			userIDs = append(userIDs, user.ID)

		}
	}
	vipSummaries := buildUserVipSummaries(h.db, userIDs)
	for _, msg := range messages {

		if msg == nil {

			continue

		}
		currentUser, hasCurrentUser := userByUUID[msg.SenderID]

		sender := currentMessageSenderDisplay(msg, currentUser, hasCurrentUser)
		item := gin.H{

			"id": msg.ID,

			"msg_id": msg.MsgID,

			"chat_id": msg.ChatID,

			"seq": msg.Seq,

			"sender_id": sender.id,

			"sender_name": sender.name,

			"sender_avatar": sender.avatar,

			"sender_nickname_color": sender.nicknameColor,

			"sender_emoji_avatar": sender.emojiAvatar,

			"sender_device_id": sender.deviceID,

			"type": msg.Type,

			"content": msg.Content,

			"e2ee": msg.E2EE,

			"reply_to": msg.ReplyTo,

			"mentions": msg.Mentions,

			"reactions": msg.Reactions,

			"status": msg.Status,

			"is_anonymous": msg.IsAnonymous,

			"is_revoked": msg.IsRevoked,

			"revoked_by": msg.RevokedBy,

			"is_edited": msg.IsEdited,

			"deleted_for": msg.DeletedFor,

			"burn_after_read": msg.BurnAfterRead,

			"burn_after_seconds": msg.BurnAfterSeconds,

			"burned_for": msg.BurnedFor,

			"created_at": msg.CreatedAt,

			"updated_at": msg.UpdatedAt,

			"edited_at": msg.EditedAt,
		}

		if userID, ok := userIDByUUID[msg.SenderID]; ok {

			item["sender_vip"] = vipSummaries[userID]

		}
		result = append(result, item)
	}
	return result
}

type messageSenderDisplay struct {
	id            string
	name          string
	avatar        string
	nicknameColor string
	emojiAvatar   string
	deviceID      string
}

func currentMessageSenderDisplay(msg *models.Message, currentUser models.User, hasCurrentUser bool) messageSenderDisplay {
	display := messageSenderDisplay{

		id: msg.SenderID,

		name: msg.SenderName,

		avatar: msg.SenderAvatar,

		nicknameColor: msg.SenderNicknameColor,

		emojiAvatar: msg.SenderEmojiAvatar,

		deviceID: msg.SenderDeviceID,
	}
	if msg.IsAnonymous {

		display.id = "anonymous"

		display.avatar = ""

		display.nicknameColor = ""

		display.emojiAvatar = ""

		display.deviceID = ""

		return display
	}
	if !hasCurrentUser {

		return display
	}
	if strings.TrimSpace(currentUser.Nickname) != "" {

		display.name = currentUser.Nickname
	} else if strings.TrimSpace(currentUser.Username) != "" {

		display.name = currentUser.Username
	}
	display.avatar = currentUser.Avatar
	display.nicknameColor = currentUser.NicknameColor
	display.emojiAvatar = currentUser.EmojiAvatar
	return display
}

type TranscribeVoiceRequest struct {
	ChatID string `json:"chat_id" binding:"required"`
	MsgID  string `json:"msg_id" binding:"required"`
}
type TranslateMessageRequest struct {
	ChatID     string `json:"chat_id" binding:"required"`
	MsgID      string `json:"msg_id"`
	Text       string `json:"text"`
	TargetLang string `json:"target_lang"`
	SourceLang string `json:"source_lang"`
}
type deepSeekChatMessage struct {
	Role    string `json:"role"`
	Content string `json:"content"`
}
type deepSeekChatRequest struct {
	Model       string                `json:"model"`
	Messages    []deepSeekChatMessage `json:"messages"`
	Temperature float64               `json:"temperature"`
	MaxTokens   int                   `json:"max_tokens,omitempty"`
}
type deepSeekChatResponse struct {
	Choices []struct {
		Message deepSeekChatMessage `json:"message"`
	} `json:"choices"`
	Error *struct {
		Message string `json:"message"`

		Type string `json:"type"`

		Code string `json:"code"`
	} `json:"error,omitempty"`
}

func (h *MessageHandler) TranscribeVoiceMessage(c *gin.Context) {
	userID := c.GetString("user_id")
	var req TranscribeVoiceRequest
	if err := c.ShouldBindJSON(&req); err != nil {

		response.BadRequest(c, "参数错误")

		return
	}
	var user models.User
	if err := h.db.Where("uuid = ?", userID).First(&user).Error; err != nil {

		response.NotFound(c, "用户不存在")

		return
	}
	var chat models.Chat
	if err := h.db.Where("uuid = ?", req.ChatID).First(&chat).Error; err != nil {

		response.NotFound(c, "会话不存在")

		return
	}
	var memberCount int64
	h.db.Model(&models.ChatMember{}).Where("chat_id = ? AND user_id = ?", chat.ID, user.ID).Count(&memberCount)
	if memberCount == 0 {

		response.Forbidden(c, "无权访问该语音消息")

		return
	}
	msg, found, err := h.msgService.FindMessageByMsgID(c.Request.Context(), req.ChatID, req.MsgID)
	if err != nil {

		log.Printf("[Message] Find voice message failed chatID=%s msgID=%s err=%v", req.ChatID, req.MsgID, err)

		response.ServerError(c, "语音消息查询失败")

		return
	}
	if !found || msg == nil || msg.Type != models.MsgTypeVoice || msg.Content.Voice == nil {

		response.NotFound(c, "语音消息不存在")

		return
	}
	if text := strings.TrimSpace(msg.Content.Voice.Transcript); text != "" {

		response.Success(c, gin.H{"transcript": text, "cached": true})

		return
	}
	transcript, err := h.transcribeVoiceByExternalService(c.Request.Context(), msg.Content.Voice.URL)
	if err != nil {

		response.Error(c, http.StatusServiceUnavailable, err.Error())

		return
	}
	if transcript == "" {

		response.Error(c, http.StatusServiceUnavailable, "未识别到文字")

		return
	}
	if err := h.msgService.UpdateVoiceTranscript(c.Request.Context(), req.ChatID, req.MsgID, transcript); err != nil {

		log.Printf("[Message] Update voice transcript failed chatID=%s msgID=%s err=%v", req.ChatID, req.MsgID, err)

		response.ServerError(c, "语音文字保存失败")

		return
	}
	response.Success(c, gin.H{"transcript": transcript, "cached": false})
}
func (h *MessageHandler) TranslateMessage(c *gin.Context) {
	userID := c.GetString("user_id")
	var req TranslateMessageRequest
	if err := c.ShouldBindJSON(&req); err != nil {

		response.BadRequest(c, "参数错误")

		return
	}
	var user models.User
	if err := h.db.Where("uuid = ?", userID).First(&user).Error; err != nil {

		response.NotFound(c, "用户不存在")

		return
	}
	var chat models.Chat
	if err := h.db.Where("uuid = ?", req.ChatID).First(&chat).Error; err != nil {

		response.NotFound(c, "会话不存在")

		return
	}
	var memberCount int64
	h.db.Model(&models.ChatMember{}).Where("chat_id = ? AND user_id = ?", chat.ID, user.ID).Count(&memberCount)
	if memberCount == 0 {

		response.Forbidden(c, "无权访问该消息")

		return
	}
	sourceText := strings.TrimSpace(req.Text)
	if sourceText == "" && strings.TrimSpace(req.MsgID) != "" {

		msg, found, err := h.msgService.FindMessageByMsgID(c.Request.Context(), req.ChatID, req.MsgID)

		if err != nil {

			log.Printf("[Message] Find message for translation failed chatID=%s msgID=%s err=%v", req.ChatID, req.MsgID, err)

			response.ServerError(c, "消息查询失败")

			return

		}

		if !found || msg == nil || msg.IsRevoked {

			response.NotFound(c, "消息不存在")

			return

		}
		sourceText = translatableMessageText(msg)
	}
	if sourceText == "" {

		response.BadRequest(c, "没有可翻译的文字")

		return
	}
	if len([]rune(sourceText)) > 5000 {

		response.BadRequest(c, "文字过长，暂不支持翻译")

		return
	}
	targetLang := normalizeTranslateLanguage(req.TargetLang)
	if targetLang == "" {

		targetLang = "中文"
	}
	translated, model, err := h.translateTextByDeepSeek(c.Request.Context(), sourceText, targetLang, req.SourceLang)
	if err != nil {

		response.Error(c, http.StatusServiceUnavailable, err.Error())

		return
	}
	if translated == "" {

		response.Error(c, http.StatusServiceUnavailable, "翻译失败，请稍后重试")

		return
	}
	response.Success(c, gin.H{

		"text": sourceText,

		"translation": translated,

		"target_lang": targetLang,

		"model": model,
	})
}
func (h *MessageHandler) transcribeVoiceByExternalService(ctx context.Context, voiceURL string) (string, error) {
	provider := strings.ToLower(h.voiceTranscribeSetting(models.SettingVoiceTranscribeProvider, "VOICE_TRANSCRIBE_PROVIDER"))
	openAIKey := h.voiceTranscribeSetting(models.SettingOpenAIAPIKey, "OPENAI_API_KEY")
	if provider == "openai" || (provider == "" && openAIKey != "") {

		return h.transcribeVoiceByOpenAI(ctx, voiceURL)
	}
	endpoint := h.voiceTranscribeSetting(models.SettingVoiceTranscribeURL, "VOICE_TRANSCRIBE_URL")
	if endpoint == "" {

		return "", fmt.Errorf("语音转文字服务未配置")
	}
	body, _ := json.Marshal(map[string]string{"url": strings.TrimSpace(voiceURL)})
	req, err := http.NewRequestWithContext(ctx, http.MethodPost, endpoint, bytes.NewReader(body))
	if err != nil {

		return "", err
	}
	req.Header.Set("Content-Type", "application/json")
	if token := h.voiceTranscribeSetting(models.SettingVoiceTranscribeToken, "VOICE_TRANSCRIBE_TOKEN"); token != "" {

		req.Header.Set("Authorization", "Bearer "+token)
	}
	resp, err := (&http.Client{Timeout: 60 * time.Second}).Do(req)
	if err != nil {

		return "", fmt.Errorf("语音识别请求失败")
	}
	defer resp.Body.Close()
	raw, err := io.ReadAll(io.LimitReader(resp.Body, 2<<20))
	if err != nil {

		return "", fmt.Errorf("语音识别响应读取失败")
	}
	if resp.StatusCode < 200 || resp.StatusCode >= 300 {

		return "", fmt.Errorf("语音识别服务返回失败")
	}
	var result map[string]interface{}
	if err := json.Unmarshal(raw, &result); err != nil {

		return strings.TrimSpace(string(raw)), nil
	}
	return extractTranscriptText(result), nil
}
func (h *MessageHandler) transcribeVoiceByOpenAI(ctx context.Context, voiceURL string) (string, error) {
	apiKey := h.voiceTranscribeSetting(models.SettingOpenAIAPIKey, "OPENAI_API_KEY")
	if apiKey == "" {

		return "", fmt.Errorf("OpenAI 语音转文字服务未配置")
	}
	audio, filename, err := downloadVoiceForTranscription(ctx, voiceURL)
	if err != nil {

		return "", err
	}
	var body bytes.Buffer
	writer := multipart.NewWriter(&body)
	model := h.voiceTranscribeSetting(models.SettingOpenAITranscribeModel, "OPENAI_TRANSCRIBE_MODEL")
	if model == "" {

		model = "gpt-4o-mini-transcribe"
	}
	_ = writer.WriteField("model", model)
	_ = writer.WriteField("response_format", "json")
	if language := h.voiceTranscribeSetting(models.SettingVoiceTranscribeLanguage, "VOICE_TRANSCRIBE_LANGUAGE"); language != "" {

		_ = writer.WriteField("language", language)
	}
	part, err := writer.CreateFormFile("file", filename)
	if err != nil {

		return "", err
	}
	if _, err := part.Write(audio); err != nil {

		return "", err
	}
	if err := writer.Close(); err != nil {

		return "", err
	}
	endpoint := h.voiceTranscribeSetting(models.SettingOpenAITranscribeURL, "OPENAI_TRANSCRIBE_URL")
	if endpoint == "" {

		endpoint = "https://api.openai.com/v1/audio/transcriptions"
	}
	req, err := http.NewRequestWithContext(ctx, http.MethodPost, endpoint, &body)
	if err != nil {

		return "", err
	}
	req.Header.Set("Authorization", "Bearer "+apiKey)
	req.Header.Set("Content-Type", writer.FormDataContentType())
	resp, err := (&http.Client{Timeout: 90 * time.Second}).Do(req)
	if err != nil {

		return "", fmt.Errorf("OpenAI 语音识别请求失败")
	}
	defer resp.Body.Close()
	raw, err := io.ReadAll(io.LimitReader(resp.Body, 4<<20))
	if err != nil {

		return "", fmt.Errorf("OpenAI 语音识别响应读取失败")
	}
	if resp.StatusCode < 200 || resp.StatusCode >= 300 {

		return "", fmt.Errorf("OpenAI 语音识别失败：%s", compactHTTPError(raw))
	}
	var result map[string]interface{}
	if err := json.Unmarshal(raw, &result); err != nil {

		return strings.TrimSpace(string(raw)), nil
	}
	return extractTranscriptText(result), nil
}
func (h *MessageHandler) translateTextByDeepSeek(ctx context.Context, text, targetLang, sourceLang string) (string, string, error) {
	apiKey := h.aiSetting(models.SettingDeepSeekAPIKey, "DEEPSEEK_API_KEY")
	if apiKey == "" {

		return "", "", fmt.Errorf("DeepSeek 接口未配置")
	}
	model := h.aiSetting(models.SettingDeepSeekModel, "DEEPSEEK_MODEL")
	if model == "" {

		model = "deepseek-v4-flash"
	}
	baseURL := h.aiSetting(models.SettingDeepSeekBaseURL, "DEEPSEEK_BASE_URL")
	if baseURL == "" {

		baseURL = "https://api.deepseek.com"
	}
	endpoint := strings.TrimRight(baseURL, "/") + "/chat/completions"
	sourceLang = strings.TrimSpace(sourceLang)
	if sourceLang == "" {

		sourceLang = "自动检测"
	}
	systemPrompt := "你是专业即时通讯翻译助手。只输出译文，不要解释，不要添加引号；保留原文中的链接、数字、表情、换行和专有名词。"
	userPrompt := fmt.Sprintf("请将以下%s内容翻译成%s：\n\n%s", sourceLang, targetLang, text)
	payload := deepSeekChatRequest{

		Model: model,

		Messages: []deepSeekChatMessage{

			{Role: "system", Content: systemPrompt},

			{Role: "user", Content: userPrompt},
		},

		Temperature: 0.2,

		MaxTokens: 2048,
	}
	body, err := json.Marshal(payload)
	if err != nil {

		return "", model, err
	}
	req, err := http.NewRequestWithContext(ctx, http.MethodPost, endpoint, bytes.NewReader(body))
	if err != nil {

		return "", model, err
	}
	req.Header.Set("Authorization", "Bearer "+apiKey)
	req.Header.Set("Content-Type", "application/json")
	resp, err := (&http.Client{Timeout: 60 * time.Second}).Do(req)
	if err != nil {

		return "", model, fmt.Errorf("DeepSeek 翻译请求失败")
	}
	defer resp.Body.Close()
	raw, err := io.ReadAll(io.LimitReader(resp.Body, 4<<20))
	if err != nil {

		return "", model, fmt.Errorf("DeepSeek 翻译响应读取失败")
	}
	if resp.StatusCode < 200 || resp.StatusCode >= 300 {

		return "", model, fmt.Errorf("DeepSeek 翻译失败：%s", compactHTTPError(raw))
	}
	var result deepSeekChatResponse
	if err := json.Unmarshal(raw, &result); err != nil {

		return "", model, fmt.Errorf("DeepSeek 翻译响应解析失败")
	}
	if result.Error != nil && strings.TrimSpace(result.Error.Message) != "" {

		return "", model, fmt.Errorf("DeepSeek 翻译失败：%s", strings.TrimSpace(result.Error.Message))
	}
	if len(result.Choices) == 0 {

		return "", model, fmt.Errorf("DeepSeek 翻译未返回结果")
	}
	return strings.TrimSpace(result.Choices[0].Message.Content), model, nil
}
func (h *MessageHandler) voiceTranscribeSetting(settingKey, envKey string) string {
	return h.aiSetting(settingKey, envKey)
}
func (h *MessageHandler) aiSetting(settingKey, envKey string) string {
	if h != nil && h.db != nil && settingKey != "" {
		var setting models.SystemSetting
		if err := h.db.Where("`key` = ?", settingKey).First(&setting).Error; err == nil {

			if value := strings.TrimSpace(setting.Value); value != "" && value != "******" {

				return value

			}

		}
	}
	if envKey == "" {

		return ""
	}
	return strings.TrimSpace(os.Getenv(envKey))
}
func normalizeTranslateLanguage(lang string) string {
	lang = strings.TrimSpace(lang)
	switch strings.ToLower(lang) {
	case "", "auto":

		return ""
	case "zh", "zh-cn", "zh_cn", "chinese", "simplified chinese", "中文", "简体中文":

		return "简体中文"
	case "zh-tw", "zh_tw", "traditional chinese", "繁體中文", "繁体中文":

		return "繁体中文"
	case "en", "english", "英文":

		return "英文"
	case "ja", "jp", "japanese", "日文", "日语":

		return "日文"
	case "ko", "kr", "korean", "韩文", "韩语":

		return "韩文"
	case "fr", "french", "法文", "法语":

		return "法文"
	case "de", "german", "德文", "德语":

		return "德文"
	case "es", "spanish", "西班牙文", "西班牙语":

		return "西班牙文"
	case "ru", "russian", "俄文", "俄语":

		return "俄文"
	default:

		return lang
	}
}
func translatableMessageText(msg *models.Message) string {
	if msg == nil {

		return ""
	}
	switch msg.Type {
	case models.MsgTypeText:

		return strings.TrimSpace(msg.Content.Text)
	case models.MsgTypeVoice:

		if msg.Content.Voice != nil {

			return strings.TrimSpace(msg.Content.Voice.Transcript)

		}
	case models.MsgTypeCall, models.MsgTypeSystem:

		return strings.TrimSpace(msg.Content.Text)
	}
	return ""
}
func downloadVoiceForTranscription(ctx context.Context, rawURL string) ([]byte, string, error) {
	resolvedURL, err := resolveVoiceTranscribeURL(rawURL)
	if err != nil {

		return nil, "", err
	}
	if resolvedURL == "" {

		return nil, "", fmt.Errorf("语音文件地址为空")
	}
	parsedURL, err := normalizeLinkPreviewURL(resolvedURL)
	if err != nil {

		if errors.Is(err, errUnsafeLinkPreviewURL) {

			return nil, "", fmt.Errorf("语音文件地址不安全")

		}

		return nil, "", fmt.Errorf("语音文件地址格式错误")
	}
	req, err := http.NewRequestWithContext(ctx, http.MethodGet, parsedURL.String(), nil)
	if err != nil {

		return nil, "", err
	}
	resp, err := newSafeOutboundHTTPClient(60 * time.Second).Do(req)
	if err != nil {

		if errors.Is(err, errUnsafeLinkPreviewURL) {

			return nil, "", fmt.Errorf("语音文件地址不安全")

		}

		return nil, "", fmt.Errorf("语音文件下载失败")
	}
	defer resp.Body.Close()
	if resp.StatusCode < 200 || resp.StatusCode >= 300 {

		return nil, "", fmt.Errorf("语音文件下载失败")
	}
	data, err := io.ReadAll(io.LimitReader(resp.Body, 26<<20))
	if err != nil {

		return nil, "", fmt.Errorf("语音文件读取失败")
	}
	if len(data) == 0 {

		return nil, "", fmt.Errorf("语音文件为空")
	}
	filename := "voice.m4a"
	if u, err := url.Parse(parsedURL.String()); err == nil {

		if base := filepath.Base(u.Path); base != "." && base != "/" && base != "" {

			filename = base

		}
	}
	return data, filename, nil
}
func resolveVoiceTranscribeURL(rawURL string) (string, error) {
	value := strings.TrimSpace(rawURL)
	if value == "" {

		return "", nil
	}
	if strings.HasPrefix(value, "http://") || strings.HasPrefix(value, "https://") {

		return value, nil
	}
	baseURL := ""
	if config.GlobalConfig != nil {

		baseURL = strings.TrimSpace(config.GlobalConfig.Server.BaseURL)
	}
	if baseURL == "" {

		return "", fmt.Errorf("语音文件地址不是完整URL")
	}
	return strings.TrimRight(baseURL, "/") + "/" + strings.TrimLeft(value, "/"), nil
}
func compactHTTPError(raw []byte) string {
	text := strings.TrimSpace(string(raw))
	if text == "" {

		return "无响应内容"
	}
	if len(text) > 300 {

		return text[:300]
	}
	return text
}
func extractTranscriptText(result map[string]interface{}) string {
	for _, key := range []string{"transcript", "text", "result"} {

		if value, ok := result[key].(string); ok && strings.TrimSpace(value) != "" {

			return strings.TrimSpace(value)

		}
	}
	if data, ok := result["data"].(map[string]interface{}); ok {

		return extractTranscriptText(data)
	}
	return ""
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

		"list": messages,

		"total": total,

		"page": req.Page,

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
	if err := h.db.Where("uuid = ?", req.ChatID).First(&chat).Error; err != nil {

		response.NotFound(c, "会话不存在")

		return
	}
	if chat.Type == 2 {
		var currentUser models.User
		if err := h.db.Where("uuid = ?", userID).First(&currentUser).Error; err == nil {
			var member models.ChatMember
			if err := h.db.Where("chat_id = ? AND user_id = ?", chat.ID, currentUser.ID).First(&member).Error; err == nil && member.Role >= 1 {

				isAdminRevoke = true

			}

		}
	}
	err := h.withChatWriteLock(c.Request.Context(), chat.ID, func() error {

		return h.msgService.RevokeMessage(c.Request.Context(), req.ChatID, req.MsgID, userID, isAdminRevoke)
	})
	if err != nil {

		if errors.Is(err, errChatWriteBanned) || errors.Is(err, errChatWriteDissolved) {

			respondChatWriteError(c, err, "撤回消息失败，请稍后重试")

			return

		}

		response.Error(c, 400, sanitizeMessageServiceError(err, "撤回消息失败，请稍后重试"))

		return
	}
	// WebSocket is not sufficient while the app is backgrounded or killed.
	// Send a vendor data event so HMS/FCM clients can cancel the exact unread
	// notification using the same stable ID as the original new-message push.
	if h.pushService != nil && chat.ID != 0 {
		var revoker models.User
		if err := h.db.Where("uuid = ?", userID).Select("id").First(&revoker).Error; err == nil {
			var targetIDs []uint64

			if err := h.db.Model(&models.ChatMember{}).
				Where("chat_id = ? AND user_id != ?", chat.ID, revoker.ID).
				Pluck("user_id", &targetIDs).Error; err == nil && len(targetIDs) > 0 {
				chatID := req.ChatID

				msgID := req.MsgID

				go func(ids []uint64) {

					for _, targetID := range ids {

						if err := h.pushService.PushMessageRevoked(targetID, chatID, msgID); err != nil {

							log.Printf("[Push] revoked-message cancel failed user=%d chat=%s err=%v", targetID, chatID, err)

						}

					}

				}(append([]uint64(nil), targetIDs...))

			}

		}
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
	var user models.User
	if err := h.db.Where("uuid = ?", userID).Select("id").First(&user).Error; err != nil {

		response.Unauthorized(c, "请先登录")

		return
	}
	var chat models.Chat
	if err := h.db.Where("uuid = ?", req.ChatID).Select("id").First(&chat).Error; err != nil {

		response.NotFound(c, "会话不存在")

		return
	}
	var memberCount int64
	if err := h.db.Model(&models.ChatMember{}).
		Where("chat_id = ? AND user_id = ?", chat.ID, user.ID).
		Count(&memberCount).Error; err != nil {

		response.ServerError(c, "删除消息失败，请稍后重试")

		return
	}
	if memberCount == 0 {

		response.Forbidden(c, "无权删除该会话消息")

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
	Limit   int    `json:"limit"`
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
	limit := req.Limit
	if limit <= 0 {

		limit = 100
	}
	if limit > 200 {

		limit = 200
	}
	messages, err := h.msgService.SyncMessages(c.Request.Context(), req.ChatID, userID, req.LastSeq, limit)
	if err != nil {

		response.ServerError(c, sanitizeMessageServiceError(err, "消息同步失败，请稍后重试"))

		return
	}
	h.markPrivateMessagesDelivered(&syncChat, userID, messages)
	response.Success(c, gin.H{

		"messages": h.messagesWithSenderVip(messages),

		"has_more": len(messages) >= limit,
	})
}

// MarkAsReadRequest 标记已读请求
type MarkAsReadRequest struct {
	ChatID string `json:"chat_id" binding:"required"`
	MsgSeq int    `json:"msg_seq"` // 已读到的消息序号
}

// shouldFanOutRealtimeReceipts keeps group/channel receipts cursor-only.
// Broadcasting every member's receipt to every peer turns one group message
// into O(N²) WebSocket work; only a two-party private chat needs live fan-out.
func shouldFanOutRealtimeReceipts(chatType int8) bool {
	return chatType == 1
}

func (h *MessageHandler) MarkAsDelivered(c *gin.Context) {
	userID := c.GetString("user_id")
	var req MarkAsReadRequest
	if err := c.ShouldBindJSON(&req); err != nil || req.MsgSeq <= 0 {

		response.BadRequest(c, "参数错误")

		return
	}
	var user models.User
	if err := h.db.Where("uuid = ?", userID).First(&user).Error; err != nil {

		response.NotFound(c, "用户不存在")

		return
	}
	var chat models.Chat
	if err := h.db.Where("uuid = ?", req.ChatID).First(&chat).Error; err != nil {

		response.NotFound(c, "会话不存在")

		return
	}
	if !shouldFanOutRealtimeReceipts(chat.Type) {

		response.Success(c, gin.H{"delivered": false})

		return
	}
	var membershipCount int64
	if err := h.db.Model(&models.ChatMember{}).
		Where("chat_id = ? AND user_id = ?", chat.ID, user.ID).
		Count(&membershipCount).Error; err != nil || membershipCount == 0 {

		response.Error(c, http.StatusForbidden, "无权访问此会话")

		return
	}
	var senderIDs []string
	if err := h.db.Model(&models.User{}).
		Joins("JOIN chat_members ON chat_members.user_id = users.id").
		Where("chat_members.chat_id = ? AND users.id != ?", chat.ID, user.ID).
		Pluck("users.uuid", &senderIDs).Error; err != nil {

		response.ServerError(c, "更新送达状态失败")

		return
	}
	ctx, cancel := context.WithTimeout(c.Request.Context(), 5*time.Second)
	defer cancel()
	if err := h.msgService.MarkMessagesAsDelivered(ctx, req.ChatID, userID, req.MsgSeq, senderIDs); err != nil {

		response.ServerError(c, "更新送达状态失败")

		return
	}
	h.msgService.BroadcastDeliveryReceipt(req.ChatID, userID, req.MsgSeq, senderIDs)
	response.Success(c, gin.H{"delivered": true, "msg_seq": req.MsgSeq})
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
	var userChat models.UserChat
	if err := h.db.Where("chat_id = ? AND user_id = ?", chat.ID, user.ID).First(&userChat).Error; err != nil {

		response.NotFound(c, "会话不存在")

		return
	}
	effectiveSeq := req.MsgSeq
	if effectiveSeq <= 0 && userChat.LastMsgSeq > 0 {

		effectiveSeq = int(userChat.LastMsgSeq)
	}
	// 清除未读计数
	now := time.Now()
	result := h.db.Model(&userChat).Updates(map[string]interface{}{

		"unread_count": 0,

		"has_mention": false,

		"updated_at": now,
	})
	if result.Error != nil {

		response.ServerError(c, "更新失败")

		return
	}
	userChat.UnreadCount = 0
	userChat.HasMention = false
	userChat.UpdatedAt = now
	deleteUserChatListHotCache(c.Request.Context(), h.cache, user.ID)
	lastReadSeq := uint64(0)
	if effectiveSeq > 0 {

		lastReadSeq = uint64(effectiveSeq)

		if err := h.db.Model(&models.ChatMember{}).
			Where("chat_id = ? AND user_id = ? AND last_read_seq < ?", chat.ID, user.ID, lastReadSeq).
			Updates(map[string]interface{}{

				"last_read_seq": lastReadSeq,

				"updated_at": now,
			}).Error; err != nil {

			response.ServerError(c, "更新已读游标失败")

			return

		}
	} else {
		var member models.ChatMember
		if err := h.db.Where("chat_id = ? AND user_id = ?", chat.ID, user.ID).First(&member).Error; err == nil {

			lastReadSeq = member.LastReadSeq

		}
	}
	// 获取聊天对方的用户 UUID 列表（批量查询，避免 N+1）
	var memberUserIDs2 []uint64
	if shouldFanOutRealtimeReceipts(chat.Type) {
		h.db.Model(&models.ChatMember{}).
			Where("chat_id = ? AND user_id != ?", chat.ID, user.ID).
			Pluck("user_id", &memberUserIDs2)
	}
	var targetUserIDs []string
	if len(memberUserIDs2) > 0 {

		h.db.Model(&models.User{}).Where("id IN ?", memberUserIDs2).Pluck("uuid", &targetUserIDs)
	}
	canShareReadState := false
	if len(targetUserIDs) > 0 && effectiveSeq > 0 {

		allowed, privacyErr := privacy.CanUserBroadcastReadReceipt(h.db, userID, req.ChatID)

		if privacyErr != nil {

			log.Printf("[MarkAsRead] privacy check failed user=%s chat=%s err=%v", userID, req.ChatID, privacyErr)

		} else {

			canShareReadState = allowed

		}
	}
	// Only persist shared read state when the user allows receipts.
	if canShareReadState {

		ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)

		defer cancel()

		if err := h.msgService.MarkMessagesAsRead(ctx, req.ChatID, userID, effectiveSeq, targetUserIDs); err != nil {

			// 记录错误但不影响响应

			println("[MarkAsRead] Failed to persist read status:", err.Error())

		}
	}
	// 通过 WebSocket 广播已读状态给对方用户
	if canShareReadState {

		h.msgService.BroadcastReadReceipt(req.ChatID, userID, effectiveSeq, targetUserIDs)
	}
	// 同步已读状态到当前用户的其他设备
	if h.hub != nil {
		selfSyncPayload := map[string]interface{}{

			"type": "read_sync",

			"chat_id": req.ChatID,

			"user_id": userID,

			"msg_seq": effectiveSeq,

			"last_read_seq": lastReadSeq,

			"unread_count": 0,

			"has_mention": false,
		}

		h.hub.SendToUser(userID, selfSyncPayload)

		sendUserChatStateChanged(

			h.hub,

			userID,

			req.ChatID,

			&userChat,

			lastReadSeq,

			"unread_count",

			"has_mention",

			"last_read_seq",
		)
	}
	response.Success(c, gin.H{

		"cleared": result.RowsAffected > 0,

		"unread_count": 0,

		"last_read_seq": lastReadSeq,
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
	var chat models.Chat
	if err := h.db.Where("uuid = ?", req.ChatID).First(&chat).Error; err != nil {

		response.NotFound(c, "会话不存在")

		return
	}
	// 添加表情回复
	err := h.withChatWriteLock(c.Request.Context(), chat.ID, func() error {

		return h.msgService.AddReaction(c.Request.Context(), req.ChatID, req.MsgID, userID, user.Nickname, req.Emoji)
	})
	if err != nil {

		if errors.Is(err, errChatWriteBanned) || errors.Is(err, errChatWriteDissolved) {

			respondChatWriteError(c, err, "添加表情失败，请稍后重试")

			return

		}

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
	var chat models.Chat
	if err := h.db.Where("uuid = ?", req.ChatID).First(&chat).Error; err != nil {

		response.NotFound(c, "会话不存在")

		return
	}
	// 移除表情回复
	err := h.withChatWriteLock(c.Request.Context(), chat.ID, func() error {

		return h.msgService.RemoveReaction(c.Request.Context(), req.ChatID, req.MsgID, userID, req.Emoji)
	})
	if err != nil {

		if errors.Is(err, errChatWriteBanned) || errors.Is(err, errChatWriteDissolved) {

			respondChatWriteError(c, err, "移除表情失败，请稍后重试")

			return

		}

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
	ClientMsgID  string `json:"client_msg_id"`
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
	var sourceMember models.ChatMember
	if err := h.db.Where("chat_id = ? AND user_id = ?", sourceChat.ID, sender.ID).First(&sourceMember).Error; err != nil {

		response.Forbidden(c, "无权转发该会话消息")

		return
	}
	if sourceChat.Type == 2 && !sourceChat.AllowForward && sourceMember.Role < 1 {

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

				"is_muted": false,

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

		peerQuery := h.db.Model(&models.ChatMember{}).
			Select("user_id").
			Where("chat_id = ? AND user_id != ?", targetChat.ID, sender.ID)

		if err := h.db.Model(&models.UserBlock{}).
			Where(

				"(user_id IN (?) AND blocked_user_id = ?) OR (user_id = ? AND blocked_user_id IN (?))",

				peerQuery,

				sender.ID,

				sender.ID,

				peerQuery,
			).
			Count(&blockCount).Error; err != nil {

			response.ServerError(c, "检查屏蔽关系失败")

			return

		}

		if blockCount > 0 {

			response.Forbidden(c, "存在屏蔽关系，无法转发消息")

			return

		}
	}
	// 获取目标用户 UUID 列表（批量查询，避免 N+1）
	var fwdMemberIDs []uint64
	h.db.Model(&models.ChatMember{}).Where("chat_id = ? AND user_id != ?", targetChat.ID, sender.ID).Pluck("user_id", &fwdMemberIDs)
	fwdTargets := make([]messagePushTarget, 0, len(fwdMemberIDs))
	var targetUserIDs []string
	if len(fwdMemberIDs) > 0 {
		h.db.Model(&models.User{}).
			Where("id IN ?", fwdMemberIDs).
			Select("id AS user_id, uuid").
			Scan(&fwdTargets)
		targetUserIDs = make([]string, 0, len(fwdTargets))
		for _, target := range fwdTargets {
			targetUserIDs = append(targetUserIDs, target.UUID)
		}
	}
	if err := h.ensureUserChatRecords(&targetChat, append([]uint64{sender.ID}, fwdMemberIDs...), time.Now()); err != nil {

		log.Printf("[Message] ensure user_chats before forward failed chatID=%d err=%v", targetChat.ID, err)
	}
	// 转发写入同样与目标会话解散事务串行化。
	var forwardResult *services.SendMessageResult
	err := h.withChatWriteLock(c.Request.Context(), targetChat.ID, func() error {
		var forwardErr error

		forwardResult, forwardErr = h.msgService.ForwardMessage(c.Request.Context(), req.SourceChatID, req.SourceMsgID, req.TargetChatID, userID, sender.Nickname, sender.Avatar, sender.NicknameColor, sender.EmojiAvatar, req.ClientMsgID, targetUserIDs)

		return forwardErr
	})
	if err != nil {

		if errors.Is(err, errChatWriteBanned) || errors.Is(err, errChatWriteDissolved) {

			respondChatWriteError(c, err, "转发消息失败，请稍后重试")

			return

		}

		if strings.Contains(err.Error(), "阅后即焚消息不支持转发") {

			response.Forbidden(c, "阅后即焚消息不支持转发")

			return

		}

		response.ServerError(c, sanitizeMessageServiceError(err, "转发消息失败，请稍后重试"))

		return
	}
	msg := forwardResult.Message
	if forwardResult.Duplicate {

		response.Success(c, msg)

		return
	}
	// 更新 UserChat 的最后消息
	lastMsgText := "[转发消息]"
	lastMsgMediaURL := services.MessagePreviewMediaURL(msg)
	h.db.Model(&models.UserChat{}).
		Where("chat_id = ?", targetChat.ID).
		Updates(map[string]interface{}{

			"last_msg_text": lastMsgText,

			"last_msg_type": msg.Type,

			"last_msg_time": msg.CreatedAt,

			"last_msg_seq": msg.Seq,

			"last_msg_sender": sender.Nickname,

			"last_msg_media_url": lastMsgMediaURL,

			"sort_time": msg.CreatedAt,
		})
	// 更新对方的未读数
	h.db.Model(&models.UserChat{}).
		Where("chat_id = ? AND user_id != ?", targetChat.ID, sender.ID).
		UpdateColumn("unread_count", gorm.Expr("unread_count + 1"))
	deleteChatMembersChatListHotCache(context.Background(), h.cache, h.db, targetChat.ID)
	// Forwarded messages must refresh the same per-user chat snapshot as a
	// normal send. Without this event an online client can receive/store the
	// message while its chat list and incremental history remain on the stale
	// last_msg_seq, and an offline client can reopen the old cached window.
	h.broadcastChatStateAfterMessage(

		&targetChat,

		msg,

		append([]uint64{sender.ID}, fwdMemberIDs...),
	)
	if h.pushService != nil {
		h.enqueueMessagePush(messagePushTask{
			chatID:       targetChat.ID,
			chatUUID:     req.TargetChatID,
			chatType:     chatPushType(targetChat.Type),
			messageID:    msg.MsgID,
			messageSeq:   msg.Seq,
			senderUserID: sender.ID,
			senderName:   sender.Nickname,
			content:      lastMsgText,
			mediaURL:     lastMsgMediaURL,
			targets:      fwdTargets,
		})
	}
	response.Success(c, msg)
}

// EditMessageRequest 编辑消息请求
type EditMessageRequest struct {
	ChatID  string                          `json:"chat_id" binding:"required"`
	MsgID   string                          `json:"msg_id" binding:"required"`
	Content string                          `json:"content"`
	Media   *models.MediaInfo               `json:"media"`
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
	if req.Media != nil {

		if hasEncryptedPayload {

			response.BadRequest(c, "替换图片消息暂不支持端到端加密载荷")

			return

		}

		if cryptoMode == models.MessageCryptoModeStrict {

			response.BadRequest(c, "严格加密模式下暂不支持替换图片消息")

			return

		}
	} else {

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
	}
	// 编辑消息
	if req.Content == "" && req.Media == nil && !hasEncryptedPayload {

		response.BadRequest(c, "消息内容不能为空")

		return
	}
	if !hasEncryptedPayload && req.Media == nil && len([]rune(req.Content)) > maxTextMessageRunes {

		response.BadRequest(c, "消息内容不能超过5000个字符")

		return
	}
	var chat models.Chat
	if err := h.db.Where("uuid = ?", req.ChatID).First(&chat).Error; err != nil {

		response.NotFound(c, "会话不存在")

		return
	}
	var reservedMediaIDs []string
	var mediaOwnerID uint64
	var err error
	oldMediaID := ""
	if req.Media != nil && strings.TrimSpace(req.Media.MediaID) != "" {
		var mediaOwner models.User
		if err := h.db.Where("uuid = ?", userID).Select("id").First(&mediaOwner).Error; err != nil {

			response.NotFound(c, "用户不存在")

			return

		}
		mediaOwnerID = mediaOwner.ID

		mediaPayload := map[string]interface{}{}
		rawMedia, _ := json.Marshal(req.Media)
		_ = json.Unmarshal(rawMedia, &mediaPayload)

		reservedMediaIDs, err = services.ReserveMessageMedia(

			h.db,

			mediaOwner.ID,

			req.MsgID,

			req.ChatID,

			models.MsgTypeImage,

			map[string]interface{}{"media": mediaPayload},

			nil,
		)

		if err != nil {

			if services.IsMessageMediaError(err) {

				response.BadRequest(c, err.Error())

				return

			}

			response.ServerError(c, "校验上传图片失败，请稍后重试")

			return

		}

		req.Media.URL, _ = mediaPayload["url"].(string)

		if value, ok := mediaPayload["size"].(float64); ok {

			req.Media.Size = int64(value)

		}

		req.Media.MimeType, _ = mediaPayload["mime_type"].(string)

		if existing, found, findErr := h.msgService.FindMessageByMsgID(

			c.Request.Context(),

			req.ChatID,

			req.MsgID,
		); findErr == nil && found && existing.Content.Media != nil {

			oldMediaID = existing.Content.Media.MediaID

		}
	}
	err = h.withChatWriteLock(c.Request.Context(), chat.ID, func() error {

		if req.Media != nil {

			return h.msgService.EditImageMessageMedia(c.Request.Context(), req.ChatID, req.MsgID, userID, req.Media)

		}

		return h.msgService.EditMessageWithE2EE(c.Request.Context(), req.ChatID, req.MsgID, userID, req.Content, req.E2EE)
	})
	if err != nil {

		services.ReleaseMessageMedia(h.db, reservedMediaIDs, req.MsgID)

		if errors.Is(err, errChatWriteBanned) || errors.Is(err, errChatWriteDissolved) {

			respondChatWriteError(c, err, "编辑消息失败，请稍后重试")

			return

		}

		response.Error(c, 400, sanitizeMessageServiceError(err, "编辑消息失败，请稍后重试"))

		return
	}
	if err := services.CommitMessageMedia(h.db, reservedMediaIDs, req.MsgID); err != nil {

		log.Printf("[Message] commit edited media binding failed msgID=%s err=%v", req.MsgID, err)
	}
	if oldMediaID != "" && oldMediaID != req.Media.MediaID {

		services.MarkMediaForDeletion(h.db, mediaOwnerID, oldMediaID)
	}
	response.Success(c, gin.H{"message": "消息已编辑"})
}
