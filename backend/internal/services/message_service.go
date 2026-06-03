package services

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"log"
	"regexp"
	"sort"
	"strconv"
	"strings"
	"time"

	"gaoranim/internal/cache"
	"gaoranim/internal/models"
	"gaoranim/internal/mq"
	"gaoranim/internal/ws"

	"github.com/google/uuid"
	"go.mongodb.org/mongo-driver/bson"
	"go.mongodb.org/mongo-driver/bson/primitive"
	"go.mongodb.org/mongo-driver/mongo"
	"go.mongodb.org/mongo-driver/mongo/options"
	"gorm.io/gorm"
)

// MessageService 消息服务
type MessageService struct {
	searchSvc *SearchService // ES搜索服务，nil时降级
	mongoDB *mongo.Database
	db      *gorm.DB
	cache   *cache.Cache
	mq      *mq.MessageQueue
	hub     *ws.Hub
	mongoCh chan mongoWriteTask // 异步批量写MongoDB channel
}

// NewMessageService 创建消息服务
func NewMessageService(
	mongoDB *mongo.Database,
	db *gorm.DB,
	cache *cache.Cache,
	mq *mq.MessageQueue,
	hub *ws.Hub,
) *MessageService {
	s := &MessageService{
		mongoDB: mongoDB,
		db:      db,
		cache:   cache,
		mq:      mq,
		hub:     hub,
	}
	s.mongoCh = make(chan mongoWriteTask, 5000)
	go s.runMongoFlushWorker()
	return s
}

// getChatMemberUUIDs 查询会话所有成员的 UUID（用于按用户推送，确保多设备都能收到）
func (s *MessageService) getChatMemberUUIDs(chatUUID string) []string {
	var chat models.Chat
	if err := s.db.Where("uuid = ?", chatUUID).First(&chat).Error; err != nil {
		return nil
	}
	var memberUserIDs []uint64
	s.db.Model(&models.ChatMember{}).Where("chat_id = ?", chat.ID).Pluck("user_id", &memberUserIDs)
	if len(memberUserIDs) == 0 {
		return nil
	}
	var uuids []string
	s.db.Model(&models.User{}).Where("id IN ?", memberUserIDs).Pluck("uuid", &uuids)
	return uuids
}

// SendMessageParams 发送消息参数
type SendMessageParams struct {
	ChatID           string                          `json:"chat_id"`
	SenderID         string                          `json:"sender_id"`
	SenderDeviceID   string                          `json:"sender_device_id,omitempty"`
	Type             int                             `json:"type"`
	Content          map[string]interface{}          `json:"content"`
	E2EE             *models.EncryptedMessagePayload `json:"e2ee,omitempty"`
	MsgID            string                          `json:"msg_id,omitempty"`
	ReplyTo          *ReplyInfo                      `json:"reply_to,omitempty"`
	Mentions         []string                        `json:"mentions,omitempty"`
	BurnAfterRead    bool                            `json:"burn_after_read,omitempty"`
	BurnAfterSeconds int                             `json:"burn_after_seconds,omitempty"`
	ChatType         int                             `json:"chat_type,omitempty"`
}

// ReplyInfo 回复信息
type ReplyInfo struct {
	MsgID      string `json:"msg_id"`
	SenderID   string `json:"sender_id"`
	SenderName string `json:"sender_name"`
	Content    string `json:"content"`
}

// GetMessagesParams 获取消息参数
type GetMessagesParams struct {
	ChatID    string `json:"chat_id"`
	UserID    string `json:"user_id"`
	BeforeSeq int    `json:"before_seq"`
	Limit     int    `json:"limit"`
}

type SendMessageResult struct {
	Message   *models.Message
	Duplicate bool
}

// SendMessageWithResult sends a message and reports whether it was an idempotent duplicate.
func (s *MessageService) SendMessageWithResult(ctx context.Context, params *SendMessageParams, senderName, senderAvatar, senderNicknameColor, senderPremiumType, senderEmojiAvatar string, targetUserIDs []string) (*SendMessageResult, error) {
	clientMsgID := strings.TrimSpace(params.MsgID)
	if clientMsgID != "" {
		if existing, ok, err := s.FindMessageByClientID(ctx, params.ChatID, params.SenderID, clientMsgID); err != nil {
			return nil, err
		} else if ok {
			return &SendMessageResult{Message: existing, Duplicate: true}, nil
		}
	}

	// 1. 获取消息序号（Redis INCR 原子操作，无需额外锁）
	if clientMsgID != "" {
		if existing, ok, err := s.FindMessageByClientID(ctx, params.ChatID, params.SenderID, clientMsgID); err != nil {
			return nil, err
		} else if ok {
			return &SendMessageResult{Message: existing, Duplicate: true}, nil
		}
	}
	seq, err := s.cache.GetNextMsgSeq(ctx, params.ChatID)
	if err != nil {
		return nil, err
	}
	seq = s.repairNextMsgSeqIfNeeded(ctx, params.ChatID, seq)

	// 2. 构建消息内容
	hasE2EE := hasEncryptedPayload(params.E2EE)
	content := models.MessageContent{}
	if !hasE2EE {
		if text, ok := params.Content["text"].(string); ok {
			content.Text = text
		}

		// 处理媒体内容 (图片/视频)
		if media, ok := params.Content["media"].(map[string]interface{}); ok {
			content.Media = &models.MediaInfo{}
			if url, ok := media["url"].(string); ok {
				content.Media.URL = url
			}
			if thumbnail, ok := media["thumbnail"].(string); ok {
				content.Media.Thumbnail = thumbnail
			}
			if width, ok := media["width"].(float64); ok {
				content.Media.Width = int(width)
			}
			if height, ok := media["height"].(float64); ok {
				content.Media.Height = int(height)
			}
			if duration, ok := media["duration"].(float64); ok {
				content.Media.Duration = int(duration)
			}
			if size, ok := media["size"].(float64); ok {
				content.Media.Size = int64(size)
			}
			if mimeType, ok := media["mime_type"].(string); ok {
				content.Media.MimeType = mimeType
			}
		}

		// 处理语音内容
		if voice, ok := params.Content["voice"].(map[string]interface{}); ok {
			content.Voice = &models.VoiceInfo{}
			if url, ok := voice["url"].(string); ok {
				content.Voice.URL = url
			}
			if duration, ok := voice["duration"].(float64); ok {
				content.Voice.Duration = int(duration)
			}
			if size, ok := voice["size"].(float64); ok {
				content.Voice.Size = int64(size)
			}
			if transcript, ok := voice["transcript"].(string); ok {
				content.Voice.Transcript = transcript
			}
		}

		if location, ok := params.Content["location"].(map[string]interface{}); ok {
			content.Location = &models.LocationInfo{}
			if latitude, ok := location["latitude"].(float64); ok {
				content.Location.Latitude = latitude
			}
			if longitude, ok := location["longitude"].(float64); ok {
				content.Location.Longitude = longitude
			}
			if title, ok := location["title"].(string); ok {
				content.Location.Title = title
			}
			if address, ok := location["address"].(string); ok {
				content.Location.Address = address
			}
		}

		// 处理文件内容
		if file, ok := params.Content["file"].(map[string]interface{}); ok {
			content.File = &models.FileInfo{}
			if url, ok := file["url"].(string); ok {
				content.File.URL = url
			}
			if name, ok := file["name"].(string); ok {
				content.File.Name = name
			}
			if size, ok := file["size"].(float64); ok {
				content.File.Size = int64(size)
			}
			if mimeType, ok := file["mime_type"].(string); ok {
				content.File.MimeType = mimeType
			}
		}

		// 处理名片内容
		if contact, ok := params.Content["contact"].(map[string]interface{}); ok {
			content.Contact = &models.ContactInfo{}
			if userID, ok := contact["user_id"].(string); ok {
				content.Contact.UserID = userID
			}
			if nickname, ok := contact["nickname"].(string); ok {
				content.Contact.Nickname = nickname
			}
			if username, ok := contact["username"].(string); ok {
				content.Contact.Username = username
			}
			if avatar, ok := contact["avatar"].(string); ok {
				content.Contact.Avatar = avatar
			}
			if bio, ok := contact["bio"].(string); ok {
				content.Contact.Bio = bio
			}
			if nicknameColor, ok := contact["nickname_color"].(string); ok {
				content.Contact.NicknameColor = nicknameColor
			}
			if emojiAvatar, ok := contact["emoji_avatar"].(string); ok {
				content.Contact.EmojiAvatar = emojiAvatar
			}
			if premiumType, ok := contact["premium_type"].(string); ok {
				content.Contact.PremiumType = premiumType
			}
		}

		// 3. 构建回复信息
	}

	var replyTo *models.ReplyInfo
	if !hasE2EE && params.ReplyTo != nil {
		replyTo = &models.ReplyInfo{
			MsgID:      params.ReplyTo.MsgID,
			SenderID:   params.ReplyTo.SenderID,
			SenderName: params.ReplyTo.SenderName,
			Content:    params.ReplyTo.Content,
		}
	}
	var mentions []string
	if !hasE2EE && len(params.Mentions) > 0 {
		mentions = append([]string{}, params.Mentions...)
	}

	// 4. 构建消息对象
	now := time.Now()
	msgID := clientMsgID
	if msgID == "" {
		msgID = uuid.New().String()
	}
	msg := &models.Message{
		MsgID:               msgID,
		ChatID:              params.ChatID,
		Seq:                 seq,
		SenderID:            params.SenderID,
		SenderName:          senderName,
		SenderAvatar:        senderAvatar,
		SenderNicknameColor: senderNicknameColor,
		SenderPremiumType:   senderPremiumType,
		SenderEmojiAvatar:   senderEmojiAvatar,
		SenderDeviceID:      params.SenderDeviceID,
		Type:                params.Type,
		Content:             content,
		E2EE:                params.E2EE,
		ReplyTo:             replyTo,
		Mentions:            mentions,
		Status:              models.MsgStatusSent,
		BurnAfterRead:       params.BurnAfterRead,
		BurnAfterSeconds:    params.BurnAfterSeconds,
		CreatedAt:           now,
		UpdatedAt:           now,
	}


	// 5. ★ 异步写MongoDB（seq分配后立即释放锁，不再阻塞后续消息）

	// 异步持久化到MongoDB，失败时记录日志（消息已通过Redis/WS下发，不影响实时性）
	collectionName := models.GetMessageCollection(params.ChatID, now)
	// ★ 发送到批量写channel（worker每20ms批量InsertMany，消除高频单条写磁盘IO）
	select {
	case s.mongoCh <- mongoWriteTask{collName: collectionName, msg: msg}:
	default:
		// channel满时降级为单条异步写，防止消息丢失
		go func(cName string, m *models.Message) {
			coll := s.mongoDB.Collection(cName)
			if _, err := coll.InsertOne(context.Background(), m); err != nil {
				log.Printf("[MessageService] fallback insert failed coll=%s msgID=%s err=%v",
					cName, m.MsgID, err)
			}
	// 异步写入ES搜索索引（仅文字消息，ES未配置自动跳过）
	if msg.Type == models.MsgTypeText && s.searchSvc != nil {
		s.searchSvc.IndexMessage(ESMessageDoc{
			MsgID:      msg.MsgID,
			ChatID:     msg.ChatID,
			SenderID:   msg.SenderID,
			SenderName: msg.SenderName,
			Content:    msg.Content.Text,
			SentAt:     msg.CreatedAt,
		})
	}
		}(collectionName, msg)
	}


	// 6. 发布到消息队列（异步处理推送等）
	s.publishSyncMessage(msg)
	go s.publishUserChatSync(msg)

	// 7. ★ 集群改造：群聊走 BroadcastToGroupCluster（Redis Set 在线成员，避免传全量uid）
	// 私聊保持 SendToUsersCluster（成员少，直接推效率更高）
	wsPayload := map[string]interface{}{
		"type":    "new_message",
		"message": msg,
	}
	if params.ChatType == 2 {
		// 群聊：走 chatID 广播，只推在线成员，不需要传全量 uid 列表
		s.hub.BroadcastToGroupCluster(params.ChatID, wsPayload)
		// 发送者其他设备多设备同步
		s.hub.SendToUsersCluster([]string{params.SenderID}, wsPayload)
	} else {
		// 私聊：直接推双方
		wsPushIDs := append(append([]string{}, targetUserIDs...), params.SenderID)
		s.hub.SendToUsersCluster(wsPushIDs, wsPayload)
	}

	return &SendMessageResult{Message: msg}, nil
}

func (s *MessageService) publishSyncMessage(msg *models.Message) {
	if s == nil || s.mq == nil || msg == nil {
		return
	}

	payload, err := json.Marshal(msg)
	if err != nil {
		log.Printf("[MessageService] marshal sync_message failed: chatId=%s msgId=%s err=%v", msg.ChatID, msg.MsgID, err)
		return
	}

	publishCtx, cancel := context.WithTimeout(context.Background(), 3*time.Second)
	defer cancel()
	if err := s.mq.Publish(publishCtx, mq.QueueMessageSync, &mq.QueueMessage{
		Type:    "sync_message",
		Payload: payload,
	}); err != nil {
		log.Printf("[MessageService] publish sync_message failed: chatId=%s msgId=%s err=%v", msg.ChatID, msg.MsgID, err)
	}
}


// buildMsgPreviewText 根据消息类型生成会话列表预览文本
func buildMsgPreviewText(msg *models.Message) string {
	switch msg.Type {
	case 1:
		text := msg.Content.Text
		runes := []rune(text)
		if len(runes) > 50 {
			return string(runes[:50]) + "..."
		}
		return text
	case 2:
		if msg.Content.Media != nil {
			mime := msg.Content.Media.MimeType
			if strings.HasPrefix(mime, "video/") {
				return "[视频]"
			}
			if mime == "image/gif" {
				return "[动图]"
			}
		}
		return "[图片]"
	case 3:
		return "[语音]"
	case 4:
		if msg.Content.File != nil && msg.Content.File.Name != "" {
			return "[文件] " + msg.Content.File.Name
		}
		return "[文件]"
	case 5:
		if msg.Content.Location != nil && msg.Content.Location.Title != "" {
			return "[位置] " + msg.Content.Location.Title
		}
		return "[位置]"
	case 6:
		if msg.Content.Contact != nil && msg.Content.Contact.Nickname != "" {
			return "[名片] " + msg.Content.Contact.Nickname
		}
		return "[名片]"
	case 7:
		return "[贴纸]"
	case 10:
		return ""
	default:
		return "[消息]"
	}
}

// publishUserChatSync F-04B 时间线模型：只写 Redis，不查 MySQL
// 去掉两次 DB 查询（chat uuid→id, sender uuid→id），发消息延迟大幅降低
func (s *MessageService) publishUserChatSync(msg *models.Message) {
	if s == nil || s.mq == nil || msg == nil {
		return
	}
	if msg.Type == 10 {
		return
	}
	previewText := buildMsgPreviewText(msg)

	type syncPayload struct {
		ChatUUID      string `json:"chat_uuid"`
		LastMsgID     string `json:"last_msg_id"`
		LastMsgSeq    uint64 `json:"last_msg_seq"`
		LastMsgTime   int64  `json:"last_msg_time"`
		LastMsgText   string `json:"last_msg_text"`
		LastMsgType   int    `json:"last_msg_type"`
		LastMsgSender string `json:"last_msg_sender"`
	}

	payload, err := json.Marshal(&syncPayload{
		ChatUUID:      msg.ChatID,
		LastMsgID:     msg.MsgID,
		LastMsgSeq:    msg.Seq,
		LastMsgTime:   msg.CreatedAt.UnixMilli(),
		LastMsgText:   previewText,
		LastMsgType:   msg.Type,
		LastMsgSender: msg.SenderName,
	})
	if err != nil {
		log.Printf("[MessageService] publishUserChatSync marshal failed: %v", err)
		return
	}

	publishCtx, cancel := context.WithTimeout(context.Background(), 3*time.Second)
	defer cancel()
	if err := s.mq.Publish(publishCtx, mq.QueueUserChatSync, &mq.QueueMessage{
		Type:    "user_chat_sync",
		Payload: payload,
	}); err != nil {
		log.Printf("[MessageService] publishUserChatSync failed: chatUUID=%s err=%v", msg.ChatID, err)
	}

	// ★ 双保险：MQ 异步之外，同步直写 Redis，防止 MQ 延迟/失败导致缓存落后
	if s.cache != nil {
		cacheCtx, cacheCancel := context.WithTimeout(context.Background(), 2*time.Second)
		defer cacheCancel()
		lastMsg := map[string]interface{}{
			"msg_id":      msg.MsgID,
			"seq":         msg.Seq,
			"time":        msg.CreatedAt.UnixMilli(),
			"text":        previewText,
			"type":        msg.Type,
			"sender_name": msg.SenderName,
		}
		_ = s.cache.SetChatLastSeq(cacheCtx, msg.ChatID, msg.Seq)
		_ = s.cache.SetChatLastMsg(cacheCtx, msg.ChatID, lastMsg)
	}
}
// SendMessage 发送消息
func (s *MessageService) SendMessage(ctx context.Context, params *SendMessageParams, senderName, senderAvatar, senderNicknameColor, senderPremiumType, senderEmojiAvatar string, targetUserIDs []string) (*models.Message, error) {
	result, err := s.SendMessageWithResult(ctx, params, senderName, senderAvatar, senderNicknameColor, senderPremiumType, senderEmojiAvatar, targetUserIDs)
	if err != nil || result == nil {
		return nil, err
	}
	return result.Message, nil
}

func (s *MessageService) FindMessageByClientID(ctx context.Context, chatID, senderID, msgID string) (*models.Message, bool, error) {
	msgID = strings.TrimSpace(msgID)
	if msgID == "" {
		return nil, false, nil
	}

	filter := bson.M{
		"chat_id":   chatID,
		"sender_id": senderID,
		"msg_id":    msgID,
	}
	now := time.Now()
	for i := 0; i < 12; i++ {
		t := now.AddDate(0, -i, 0)
		col := s.mongoDB.Collection(models.GetMessageCollection(chatID, t))
		var msg models.Message
		err := col.FindOne(ctx, filter).Decode(&msg)
		if err == nil {
			return &msg, true, nil
		}
		if err != mongo.ErrNoDocuments {
			return nil, false, err
		}
	}

	return nil, false, nil
}

// GetMessages 获取消息列表（Handler调用版本）
func (s *MessageService) GetMessages(ctx context.Context, params *GetMessagesParams) ([]*models.Message, error) {
	clearedAt, err := s.getUserChatClearedAt(params.ChatID, params.UserID)
	if err != nil {
		return nil, err
	}
	return s.getMessagesBySeq(ctx, params.ChatID, params.UserID, uint64(params.BeforeSeq), params.Limit, clearedAt)
}

// GetMessagesBySeq 按序号获取消息列表
// 支持跨月查询，确保历史消息不会丢失
func (s *MessageService) GetMessagesBySeq(ctx context.Context, chatID string, beforeSeq uint64, limit int) ([]*models.Message, error) {
	return s.getMessagesBySeq(ctx, chatID, "", beforeSeq, limit, nil)
}

func (s *MessageService) getMessagesBySeq(
	ctx context.Context,
	chatID string,
	userID string,
	beforeSeq uint64,
	limit int,
	clearedAt *time.Time,
) ([]*models.Message, error) {
	if limit <= 0 || limit > 100 {
		limit = 50
	}

	// 构建查询条件
	filter := bson.M{"chat_id": chatID}
	if userID != "" {
		filter["deleted_for"] = bson.M{"$ne": userID}
	}
	if beforeSeq > 0 {
		filter["seq"] = bson.M{"$lt": beforeSeq}
	}
	if clearedAt != nil {
		filter["created_at"] = bson.M{"$gt": *clearedAt}
	}

	var allMessages []*models.Message
	now := time.Now()

	// 查询最近12个月的集合，直到获取足够的消息
	// 每次查询动态调整 limit，只取还缺少的数量，避免过度读取
	for i := 0; i < 12 && len(allMessages) < limit; i++ {
		remaining := int64(limit - len(allMessages))
		opts := options.Find().
			SetSort(bson.D{{Key: "seq", Value: -1}}).
			SetLimit(remaining)

		t := now.AddDate(0, -i, 0)
		collectionName := models.GetMessageCollection(chatID, t)
		collection := s.mongoDB.Collection(collectionName)

		cursor, err := collection.Find(ctx, filter, opts)
		if err != nil {
			log.Printf("[Message] Query collection %s error: %v", collectionName, err)
			continue
		}

		var messages []*models.Message
		if err := cursor.All(ctx, &messages); err != nil {
			cursor.Close(ctx)
			log.Printf("[Message] Decode messages from %s error: %v", collectionName, err)
			continue
		}
		cursor.Close(ctx)

		if len(messages) > 0 {
			log.Printf("[Message] Found %d messages in collection %s", len(messages), collectionName)
			allMessages = append(allMessages, messages...)
		}
	}

	// 按序号倒序排序（因为可能来自多个集合）
	sort.Slice(allMessages, func(i, j int) bool {
		return allMessages[i].Seq > allMessages[j].Seq
	})

	// 限制返回数量
	if len(allMessages) > limit {
		allMessages = allMessages[:limit]
	}

	log.Printf("[Message] GetMessagesBySeq chatId=%s, beforeSeq=%d, limit=%d, total=%d",
		chatID, beforeSeq, limit, len(allMessages))

	return allMessages, nil
}

func (s *MessageService) getUserChatClearedAt(chatID, userID string) (*time.Time, error) {
	if chatID == "" || userID == "" {
		return nil, nil
	}

	type row struct {
		ClearedAt *time.Time `gorm:"column:cleared_at"`
	}
	var r row
	if err := s.db.Table("user_chats uc").
		Select("uc.cleared_at").
		Joins("JOIN users u ON u.id = uc.user_id").
		Joins("JOIN chats c ON c.id = uc.chat_id").
		Where("u.uuid = ? AND c.uuid = ?", userID, chatID).
		Take(&r).Error; err != nil {
		if errors.Is(err, gorm.ErrRecordNotFound) {
			return nil, nil
		}
		return nil, err
	}

	if r.ClearedAt == nil || r.ClearedAt.IsZero() {
		return nil, nil
	}
	t := r.ClearedAt.UTC()
	return &t, nil
}

// GetMessagesBySeqRange 按序号范围获取消息（支持跨月查询）
func (s *MessageService) GetMessagesBySeqRange(ctx context.Context, chatID, userID string, startSeq, endSeq uint64) ([]*models.Message, error) {
	filter := bson.M{
		"chat_id": chatID,
		"seq": bson.M{
			"$gte": startSeq,
			"$lte": endSeq,
		},
	}
	if userID != "" {
		filter["deleted_for"] = bson.M{"$ne": userID}
	}

	opts := options.Find().SetSort(bson.D{{Key: "seq", Value: 1}})

	var allMessages []*models.Message
	now := time.Now()

	// 查询最近12个月的集合
	for i := 0; i < 12; i++ {
		t := now.AddDate(0, -i, 0)
		collection := s.mongoDB.Collection(models.GetMessageCollection(chatID, t))
		cursor, err := collection.Find(ctx, filter, opts)
		if err != nil {
			continue
		}

		var messages []*models.Message
		if err := cursor.All(ctx, &messages); err != nil {
			cursor.Close(ctx)
			continue
		}
		cursor.Close(ctx)

		allMessages = append(allMessages, messages...)
	}

	// 按序号正序排序
	sort.Slice(allMessages, func(i, j int) bool {
		return allMessages[i].Seq < allMessages[j].Seq
	})

	return allMessages, nil
}

func (s *MessageService) getLatestMessageSeqFromMongo(ctx context.Context, chatID string) (uint64, error) {
	var latest uint64
	now := time.Now()

	for i := 0; i < 12; i++ {
		t := now.AddDate(0, -i, 0)
		collection := s.mongoDB.Collection(models.GetMessageCollection(chatID, t))
		opts := options.FindOne().SetSort(bson.D{{Key: "seq", Value: -1}})

		var msg models.Message
		err := collection.FindOne(ctx, bson.M{"chat_id": chatID}, opts).Decode(&msg)
		if err != nil {
			if err == mongo.ErrNoDocuments {
				continue
			}
			return 0, err
		}
		if msg.Seq > latest {
			latest = msg.Seq
		}
	}

	return latest, nil
}

func (s *MessageService) repairNextMsgSeqIfNeeded(ctx context.Context, chatID string, seq uint64) uint64 {
	latestSeq, latestErr := s.getLatestMessageSeqFromMongo(ctx, chatID)
	if latestErr != nil {
		log.Printf("[Message] Check latest msg seq failed chatId=%s err=%v", chatID, latestErr)
		return seq
	}
	if seq > latestSeq {
		return seq
	}

	repairedSeq := latestSeq + 1
	if setErr := s.cache.SetCurrentMsgSeq(ctx, chatID, repairedSeq); setErr != nil {
		log.Printf("[Message] Failed to repair msg seq cache chatId=%s seq=%d err=%v", chatID, repairedSeq, setErr)
	}
	return repairedSeq
}

// RevokeMessage 撤回消息（支持跨月查询；管理员撤回群消息时不要求必须是发送者）
func (s *MessageService) RevokeMessage(ctx context.Context, chatID, msgID, userID string, isAdminRevoke bool) error {
	now := time.Now()

	// 先查找消息，验证时间限制
	findFilter := bson.M{
		"msg_id": msgID,
	}
	if !isAdminRevoke {
		findFilter["sender_id"] = userID
	}
	var foundMsg bson.M
	var foundCollection *mongo.Collection
	for i := 0; i < 12; i++ {
		t := now.AddDate(0, -i, 0)
		col := s.mongoDB.Collection(models.GetMessageCollection(chatID, t))
		err := col.FindOne(ctx, findFilter).Decode(&foundMsg)
		if err == nil {
			foundCollection = col
			break
		}
	}
	if foundCollection == nil {
		return ErrMessageNotFound
	}

	// 普通用户撤回受时间限制；管理员撤回群成员消息时不限制时间。
	if !isAdminRevoke {
		revokeMinutes := 2
		var setting models.SystemSetting
		if err := s.db.Where("`key` = ?", models.SettingRevokeMessageMinutes).First(&setting).Error; err == nil {
			if v, e := strconv.Atoi(setting.Value); e == nil && v > 0 {
				revokeMinutes = v
			}
		}
		if createdAt, ok := foundMsg["created_at"].(primitive.DateTime); ok {
			msgTime := createdAt.Time()
			if now.Sub(msgTime) > time.Duration(revokeMinutes)*time.Minute {
				return fmt.Errorf("超过%d分钟，无法撤回", revokeMinutes)
			}
		}
	}

	// 更新消息状态（存储撤回者 ID，用于前端显示正确的撤回提示）
	update := bson.M{
		"$set": bson.M{
			"is_revoked": true,
			"revoked_by": userID,
			"updated_at": now,
		},
	}
	result, err := foundCollection.UpdateOne(ctx, findFilter, update)
	if err != nil || result.MatchedCount == 0 {
		return ErrMessageNotFound
	}

	// 提取被撤回消息的 seq（用于判断是否为最后一条消息）
	var revokedSeq int64
	if seq, ok := foundMsg["seq"]; ok {
		switch v := seq.(type) {
		case int64:
			revokedSeq = v
		case int32:
			revokedSeq = int64(v)
		case float64:
			revokedSeq = int64(v)
		}
	}

	// ★ 集群改造：广播撤回通知给所有成员的所有设备（跨节点多端同步）
	revokePayload := map[string]interface{}{
		"type":       "message_revoked",
		"chat_id":    chatID,
		"msg_id":     msgID,
		"revoker_id": userID,
		"msg_seq":    revokedSeq,
	}
	if memberUUIDs := s.getChatMemberUUIDs(chatID); len(memberUUIDs) > 0 {
		s.hub.SendToUsersCluster(memberUUIDs, revokePayload)
	} else {
		s.hub.BroadcastToGroupCluster(chatID, revokePayload)
	}

	// 更新聊天列表预览为撤回提示（仅当被撤回消息是最后一条消息时才更新，区分撤回者本人和其他成员）
	var chat models.Chat
	if err := s.db.Where("uuid = ?", chatID).First(&chat).Error; err == nil {
		// 找到撤回者的内部用户 ID
		var revokerUser models.User
		if err := s.db.Where("uuid = ?", userID).Select("id").First(&revokerUser).Error; err == nil {
			// 撤回者自己看到"你撤回了一条消息"
			revokerWhere := "chat_id = ? AND user_id = ?"
			othersWhere := "chat_id = ? AND user_id != ?"
			// 仅在被撤回消息是最后一条时更新预览
			if revokedSeq > 0 {
				revokerWhere += " AND last_msg_seq = ?"
				othersWhere += " AND last_msg_seq = ?"
				s.db.Model(&models.UserChat{}).
					Where(revokerWhere, chat.ID, revokerUser.ID, revokedSeq).
					Updates(map[string]interface{}{"last_msg_text": "你撤回了一条消息", "last_msg_sender": ""})
				s.db.Model(&models.UserChat{}).
					Where(othersWhere, chat.ID, revokerUser.ID, revokedSeq).
					Updates(map[string]interface{}{"last_msg_text": "有人撤回了一条消息", "last_msg_sender": ""})
			} else {
				s.db.Model(&models.UserChat{}).
					Where("chat_id = ? AND user_id = ?", chat.ID, revokerUser.ID).
					Updates(map[string]interface{}{"last_msg_text": "你撤回了一条消息", "last_msg_sender": ""})
				s.db.Model(&models.UserChat{}).
					Where("chat_id = ? AND user_id != ?", chat.ID, revokerUser.ID).
					Updates(map[string]interface{}{"last_msg_text": "有人撤回了一条消息", "last_msg_sender": ""})
			}
		} else {
			// 若找不到用户，fallback 为统一文本
			if revokedSeq > 0 {
				s.db.Model(&models.UserChat{}).
					Where("chat_id = ? AND last_msg_seq = ?", chat.ID, revokedSeq).
					Updates(map[string]interface{}{"last_msg_text": "有人撤回了一条消息", "last_msg_sender": ""})
			} else {
				s.db.Model(&models.UserChat{}).Where("chat_id = ?", chat.ID).
					Updates(map[string]interface{}{"last_msg_text": "有人撤回了一条消息", "last_msg_sender": ""})
			}
		}
	}

	return nil
}

// DeleteMessageForUser 删除消息（仅对当前用户不可见）
func (s *MessageService) DeleteMessageForUser(ctx context.Context, chatID, msgID, userID string) error {
	// 搜索所有月份的集合找到消息
	now := time.Now()

	for i := 0; i < 12; i++ {
		t := now.AddDate(0, -i, 0)
		collection := s.mongoDB.Collection(models.GetMessageCollection(chatID, t))

		// 将用户 ID 添加到 deleted_for 数组
		result, err := collection.UpdateOne(ctx,
			bson.M{"chat_id": chatID, "msg_id": msgID},
			bson.M{
				"$addToSet": bson.M{"deleted_for": userID},
				"$set":      bson.M{"updated_at": time.Now()},
			},
		)

		if err == nil && result.MatchedCount > 0 {
			return nil
		}
	}

	return ErrMessageNotFound
}

// MarkAsRead 标记已读（广播给聊天订阅者）
func (s *MessageService) MarkAsRead(ctx context.Context, chatID, userID string, msgSeq uint64) error {
	// ★ 集群改造：使用集群版群组广播，确保跨节点推送
	s.hub.BroadcastToGroupCluster(chatID, map[string]interface{}{
		"type":    "read_receipt",
		"chat_id": chatID,
		"user_id": userID,
		"msg_seq": msgSeq,
	})

	return nil
}

// BroadcastReadReceipt 广播已读回执给指定用户
func (s *MessageService) BroadcastReadReceipt(chatID, userID string, msgSeq int, targetUserIDs []string) {
	payload := map[string]interface{}{
		"type":    "read",
		"chat_id": chatID,
		"user_id": userID,
		"msg_seq": msgSeq,
	}

	// ★ 集群改造：使用集群版多用户推送，确保跨节点投递
	s.hub.SendToUsersCluster(targetUserIDs, payload)
}

// MarkMessagesAsRead 将对方发送的消息标记为已读（持久化到 MongoDB）
// 只标记发送者不是当前用户且 seq <= msgSeq 的消息（支持跨月查询）
func (s *MessageService) MarkMessagesAsRead(ctx context.Context, chatID, readerID string, msgSeq int, senderIDs []string) error {
	if len(senderIDs) == 0 || msgSeq <= 0 {
		return nil
	}

	// 更新所有对方发送的、seq <= msgSeq 的消息为已读状态
	filter := bson.M{
		"chat_id":   chatID,
		"sender_id": bson.M{"$in": senderIDs}, // 只更新对方发送的消息
		"seq":       bson.M{"$lte": msgSeq},
		"status":    bson.M{"$lt": models.MsgStatusRead}, // 只更新未读的消息
	}

	update := bson.M{
		"$set": bson.M{
			"status": models.MsgStatusRead,
		},
	}

	now := time.Now()
	// 在最近12个月的集合中更新
	for i := 0; i < 12; i++ {
		t := now.AddDate(0, -i, 0)
		collection := s.mongoDB.Collection(models.GetMessageCollection(chatID, t))
		if _, err := collection.UpdateMany(ctx, filter, update); err != nil {
			return err
		}
	}

	burnFilter := bson.M{
		"chat_id":         chatID,
		"sender_id":       bson.M{"$in": senderIDs},
		"seq":             bson.M{"$lte": msgSeq},
		"burn_after_read": true,
		"burned_for":      bson.M{"$ne": readerID},
	}
	burnUpdate := bson.M{"$addToSet": bson.M{"burned_for": readerID}}
	burnApplied := false
	for i := 0; i < 12; i++ {
		t := now.AddDate(0, -i, 0)
		collection := s.mongoDB.Collection(models.GetMessageCollection(chatID, t))
		result, err := collection.UpdateMany(ctx, burnFilter, burnUpdate)
		if err != nil {
			return err
		}
		if result.ModifiedCount > 0 {
			burnApplied = true
		}
	}

	// ★ 集群改造：阅后即焚通知使用集群版单用户推送（跨节点投递到 readerID 所在节点）
	if burnApplied && s.hub != nil {
		s.hub.SendToUserCluster(readerID, map[string]interface{}{
			"type":    "message_burned",
			"chat_id": chatID,
			"user_id": readerID,
			"msg_seq": msgSeq,
		})
	}

	return nil
}

// SyncMessages 同步消息（客户端断线重连后同步）
func (s *MessageService) SyncMessages(ctx context.Context, chatID, userID string, lastSeq int) ([]*models.Message, error) {
	// 获取当前最新序号
	currentSeq, err := s.cache.GetCurrentMsgSeq(ctx, chatID)
	if err != nil {
		return nil, err
	}
	if latestSeq, latestErr := s.getLatestMessageSeqFromMongo(ctx, chatID); latestErr == nil && latestSeq > currentSeq {
		currentSeq = latestSeq
		if setErr := s.cache.SetCurrentMsgSeq(ctx, chatID, currentSeq); setErr != nil {
			log.Printf("[Message] Failed to repair msg seq cache during sync chatId=%s seq=%d err=%v", chatID, currentSeq, setErr)
		}
	} else if latestErr != nil {
		log.Printf("[Message] Sync latest msg seq fallback failed chatId=%s err=%v", chatID, latestErr)
	}

	if uint64(lastSeq) >= currentSeq {
		return []*models.Message{}, nil
	}

	// 获取增量消息
	messages, err := s.GetMessagesBySeqRange(ctx, chatID, userID, uint64(lastSeq)+1, currentSeq)
	if err != nil {
		return nil, err
	}

	clearedAt, err := s.getUserChatClearedAt(chatID, userID)
	if err != nil {
		return nil, err
	}
	if clearedAt != nil {
		filtered := make([]*models.Message, 0, len(messages))
		for _, msg := range messages {
			if msg == nil {
				continue
			}
			if msg.CreatedAt.After(*clearedAt) {
				filtered = append(filtered, msg)
			}
		}
		messages = filtered
	}

	return messages, nil
}

// 错误定义
var (
	ErrMessageNotFound = &ServiceError{Code: "MESSAGE_NOT_FOUND", Message: "消息不存在"}
)

type ServiceError struct {
	Code    string
	Message string
}

func (e *ServiceError) Error() string {
	return e.Message
}

// SearchMessages 搜索消息（搜索所有分片集合，按时间倒序返回）
func (s *MessageService) SearchMessages(ctx context.Context, chatID, keyword string, limit int) ([]*models.Message, error) {
	if limit <= 0 {
		limit = 50
	}

	escapedKeyword := regexp.QuoteMeta(keyword)

	collections, err := s.mongoDB.ListCollectionNames(ctx, bson.M{
		"name": bson.M{"$regex": "^messages"},
	})
	if err != nil || len(collections) == 0 {
		collections = []string{"messages"}
	}
	sort.Sort(sort.Reverse(sort.StringSlice(collections)))

	filter := bson.M{
		"chat_id":    chatID,
		"is_revoked": false,
		"content.text": bson.M{
			"$regex":   escapedKeyword,
			"$options": "i",
		},
	}

	findOptions := options.Find().
		SetSort(bson.D{{Key: "created_at", Value: -1}}).
		SetLimit(int64(limit))

	var allMessages []*models.Message
	seen := make(map[string]struct{})

	for _, name := range collections {
		if _, ok := seen[name]; ok {
			continue
		}
		seen[name] = struct{}{}

		cursor, err := s.mongoDB.Collection(name).Find(ctx, filter, findOptions)
		if err != nil {
			continue
		}

		var messages []*models.Message
		if err := cursor.All(ctx, &messages); err != nil {
			cursor.Close(ctx)
			continue
		}
		cursor.Close(ctx)

		allMessages = append(allMessages, messages...)

		if len(allMessages) >= limit {
			break
		}
	}

	if len(allMessages) > limit {
		allMessages = allMessages[:limit]
	}

	return allMessages, nil
}

// AddReaction 添加表情回复
func (s *MessageService) AddReaction(ctx context.Context, chatID, msgID, userID, userName, emoji string) error {
	// 获取消息所在的集合（搜索最近几个月）
	now := time.Now()
	var targetCollection *mongo.Collection
	var targetMsg *models.Message

	for i := 0; i < 6; i++ {
		t := now.AddDate(0, -i, 0)
		collection := s.mongoDB.Collection(models.GetMessageCollection(chatID, t))

		var msg models.Message
		err := collection.FindOne(ctx, bson.M{
			"chat_id": chatID,
			"msg_id":  msgID,
		}).Decode(&msg)

		if err == nil {
			targetCollection = collection
			targetMsg = &msg
			break
		}
	}

	if targetCollection == nil || targetMsg == nil {
		return nil // 消息不存在，静默返回
	}

	// 检查用户是否已经对该消息使用了这个表情
	for _, r := range targetMsg.Reactions {
		if r.UserID == userID && r.Emoji == emoji {
			return nil // 已经回复过了
		}
	}

	// 添加表情回复
	reaction := models.MessageReaction{
		Emoji:     emoji,
		UserID:    userID,
		UserName:  userName,
		CreatedAt: time.Now(),
	}

	_, err := targetCollection.UpdateOne(ctx,
		bson.M{"chat_id": chatID, "msg_id": msgID},
		bson.M{
			"$push": bson.M{"reactions": reaction},
			"$set":  bson.M{"updated_at": time.Now()},
		},
	)

	if err != nil {
		return err
	}

	// 通过 WebSocket 广播表情回复
	s.broadcastReaction(chatID, msgID, userID, userName, emoji, "add")

	return nil
}

// RemoveReaction 移除表情回复
func (s *MessageService) RemoveReaction(ctx context.Context, chatID, msgID, userID, emoji string) error {
	// 获取消息所在的集合
	now := time.Now()
	var targetCollection *mongo.Collection

	for i := 0; i < 6; i++ {
		t := now.AddDate(0, -i, 0)
		collection := s.mongoDB.Collection(models.GetMessageCollection(chatID, t))

		count, err := collection.CountDocuments(ctx, bson.M{
			"chat_id": chatID,
			"msg_id":  msgID,
		})

		if err == nil && count > 0 {
			targetCollection = collection
			break
		}
	}

	if targetCollection == nil {
		return nil // 消息不存在
	}

	// 移除表情回复
	_, err := targetCollection.UpdateOne(ctx,
		bson.M{"chat_id": chatID, "msg_id": msgID},
		bson.M{
			"$pull": bson.M{
				"reactions": bson.M{
					"user_id": userID,
					"emoji":   emoji,
				},
			},
			"$set": bson.M{"updated_at": time.Now()},
		},
	)

	if err != nil {
		return err
	}

	// 通过 WebSocket 广播移除表情
	s.broadcastReaction(chatID, msgID, userID, "", emoji, "remove")

	return nil
}

// broadcastReaction 广播表情回复事件给所有成员的所有设备（跨节点多端同步）
func (s *MessageService) broadcastReaction(chatID, msgID, userID, userName, emoji, action string) {
	reactionPayload := map[string]interface{}{
		"type":      "reaction",
		"chat_id":   chatID,
		"msg_id":    msgID,
		"user_id":   userID,
		"user_name": userName,
		"emoji":     emoji,
		"action":    action,
	}
	// ★ 集群改造：优先按成员 UUID 列表精确推送，回退时使用群组广播
	if memberUUIDs := s.getChatMemberUUIDs(chatID); len(memberUUIDs) > 0 {
		s.hub.SendToUsersCluster(memberUUIDs, reactionPayload)
	} else {
		s.hub.BroadcastToGroupCluster(chatID, reactionPayload)
	}
}

// ForwardMessage 转发消息
func (s *MessageService) ForwardMessage(ctx context.Context, sourceChatID, sourceMsgID, targetChatID, senderID, senderName, senderAvatar, senderNicknameColor, senderPremiumType, senderEmojiAvatar string, targetUserIDs []string) (*models.Message, error) {
	// 获取源消息
	now := time.Now()
	var sourceMsg *models.Message

	for i := 0; i < 6; i++ {
		t := now.AddDate(0, -i, 0)
		collection := s.mongoDB.Collection(models.GetMessageCollection(sourceChatID, t))

		var msg models.Message
		err := collection.FindOne(ctx, bson.M{
			"chat_id": sourceChatID,
			"msg_id":  sourceMsgID,
		}).Decode(&msg)

		if err == nil {
			sourceMsg = &msg
			break
		}
	}

	if sourceMsg == nil {
		return nil, errors.New("源消息不存在")
	}
	if sourceMsg.BurnAfterRead {
		return nil, errors.New("阅后即焚消息不支持转发")
	}
	if hasEncryptedPayload(sourceMsg.E2EE) {
		return nil, errors.New("端到端加密消息需由客户端重新发送后再转发")
	}

	// 获取新序号
	seq, err := s.cache.GetNextMsgSeq(ctx, targetChatID)
	if err == nil {
		seq = s.repairNextMsgSeqIfNeeded(ctx, targetChatID, seq)
	}
	if err != nil {
		return nil, err
	}

	// 创建新消息（复制内容）
	newMsg := &models.Message{
		MsgID:               uuid.New().String(),
		ChatID:              targetChatID,
		Seq:                 seq,
		SenderID:            senderID,
		SenderName:          senderName,
		SenderAvatar:        senderAvatar,
		SenderNicknameColor: senderNicknameColor,
		SenderPremiumType:   senderPremiumType,
		SenderEmojiAvatar:   senderEmojiAvatar,
		Type:                sourceMsg.Type,
		Content:             sourceMsg.Content,
		Status:              models.MsgStatusSent,
		CreatedAt:           time.Now(),
		UpdatedAt:           time.Now(),
	}

	// 保存到目标会话的集合
	targetCollection := s.mongoDB.Collection(models.GetMessageCollection(targetChatID, time.Now()))
	_, err = targetCollection.InsertOne(ctx, newMsg)
	if err != nil {
		return nil, err
	}

	// ★ 集群改造：通过集群版多用户推送（含发送者自己，用于多设备同步）
	fwdPushIDs := append(append([]string{}, targetUserIDs...), senderID)
	s.hub.SendToUsersCluster(fwdPushIDs, map[string]interface{}{
		"type":    "new_message",
		"message": newMsg,
	})

	return newMsg, nil
}

// EditMessage 编辑消息
func (s *MessageService) EditMessage(ctx context.Context, chatID, msgID, userID, newContent string) error {
	// 查找消息
	now := time.Now()
	var targetCollection *mongo.Collection
	var targetMsg *models.Message

	for i := 0; i < 6; i++ {
		t := now.AddDate(0, -i, 0)
		collection := s.mongoDB.Collection(models.GetMessageCollection(chatID, t))

		var msg models.Message
		err := collection.FindOne(ctx, bson.M{
			"chat_id": chatID,
			"msg_id":  msgID,
		}).Decode(&msg)

		if err == nil {
			targetCollection = collection
			targetMsg = &msg
			break
		}
	}

	if targetCollection == nil || targetMsg == nil {
		return errors.New("消息不存在")
	}

	// 检查是否是消息发送者
	if targetMsg.SenderID != userID {
		return errors.New("无权编辑他人消息")
	}

	// 只能编辑文本消息
	if targetMsg.Type != models.MsgTypeText {
		return errors.New("只能编辑文本消息")
	}

	// 更新消息内容
	editedAt := time.Now()
	_, err := targetCollection.UpdateOne(ctx,
		bson.M{"chat_id": chatID, "msg_id": msgID},
		bson.M{
			"$set": bson.M{
				"content.text": newContent,
				"is_edited":    true,
				"edited_at":    editedAt,
				"updated_at":   editedAt,
			},
		},
	)

	if err != nil {
		return err
	}

	targetMsg.Content.Text = newContent
	targetMsg.IsEdited = true
	targetMsg.EditedAt = &editedAt
	targetMsg.UpdatedAt = editedAt

	previewText := newContent
	if targetMsg.BurnAfterRead {
		previewText = BurnAfterReadPreviewText()
	}

	// 广播编辑事件给所有成员的所有设备（多端同步）
	editPayload := map[string]interface{}{
		"type":        "message_edited",
		"chat_id":     chatID,
		"msg_id":      msgID,
		"new_content": previewText,
		"is_edited":   true,
		"edited_at":   editedAt,
		"seq":         targetMsg.Seq,
		"message":     targetMsg,
	}

	// 更新 user_chats 的最新消息预览
	// 仅当 last_msg_seq 与被编辑消息的 seq 相同时才更新，确保只更新最后一条消息
	var dbChat struct {
		ID uint64
	}
	if err2 := s.db.Table("chats").Where("uuid = ?", chatID).Select("id").Scan(&dbChat).Error; err2 == nil && dbChat.ID > 0 {
		s.db.Table("user_chats").
			Where("chat_id = ? AND last_msg_type = 1 AND last_msg_seq = ?", dbChat.ID, targetMsg.Seq).
			Updates(map[string]interface{}{
				"last_msg_text":   previewText,
				"last_msg_sender": targetMsg.SenderName,
			})
	}

	// ★ 集群改造：优先按成员 UUID 列表精确推送，回退时使用群组广播
	if memberUUIDs := s.getChatMemberUUIDs(chatID); len(memberUUIDs) > 0 {
		s.hub.SendToUsersCluster(memberUUIDs, editPayload)
	} else {
		s.hub.BroadcastToGroupCluster(chatID, editPayload)
	}

	return nil
}

// GetChatMediaMessages 获取聊天媒体消息
func (s *MessageService) GetChatMediaMessages(ctx context.Context, chatID, userID string, msgTypes []int, filterType string, page, limit int) ([]map[string]interface{}, int64, error) {
	// 构建查询条件
	filter := bson.M{
		"chat_id":     chatID,
		"type":        bson.M{"$in": msgTypes},
		"is_revoked":  bson.M{"$ne": true},
		"deleted_for": bson.M{"$ne": userID}, // 排除用户已删除的消息
	}

	// 如果是链接类型，需要检查内容中是否包含链接
	if filterType == "link" {
		filter["content.text"] = bson.M{"$regex": `https?://`, "$options": "i"}
	}

	// 搜索最近 12 个月的集合
	now := time.Now()
	var rawMsgs []bson.M
	var total int64

	for i := 0; i < 12; i++ {
		t := now.AddDate(0, -i, 0)
		collection := s.mongoDB.Collection(models.GetMessageCollection(chatID, t))

		// 统计总数
		count, _ := collection.CountDocuments(ctx, filter)
		total += count

		// 获取该月份的消息
		opts := options.Find().SetSort(bson.D{{Key: "created_at", Value: -1}})
		cursor, err := collection.Find(ctx, filter, opts)
		if err != nil {
			continue
		}

		var monthMsgs []bson.M
		if err := cursor.All(ctx, &monthMsgs); err != nil {
			cursor.Close(ctx)
			continue
		}
		cursor.Close(ctx)
		rawMsgs = append(rawMsgs, monthMsgs...)
	}

	// 批量查询所有发送者信息，避免 N+1 查询
	senderIDSet := make(map[string]struct{})
	for _, msg := range rawMsgs {
		if sid, ok := msg["sender_id"].(string); ok {
			senderIDSet[sid] = struct{}{}
		}
	}
	senderUUIDs := make([]string, 0, len(senderIDSet))
	for sid := range senderIDSet {
		senderUUIDs = append(senderUUIDs, sid)
	}
	senderMap := make(map[string]models.User)
	if len(senderUUIDs) > 0 {
		var users []models.User
		s.db.Where("uuid IN ?", senderUUIDs).Find(&users)
		for _, u := range users {
			senderMap[u.UUID] = u
		}
	}

	// 组装最终结果
	allResults := make([]map[string]interface{}, 0, len(rawMsgs))
	for _, msg := range rawMsgs {
		result := map[string]interface{}{
			"id":         msg["_id"],
			"chat_id":    msg["chat_id"],
			"sender_id":  msg["sender_id"],
			"type":       msg["type"],
			"content":    msg["content"],
			"created_at": msg["created_at"],
		}
		if sid, ok := msg["sender_id"].(string); ok {
			if u, exists := senderMap[sid]; exists {
				result["sender_name"] = u.Nickname
				result["sender_avatar"] = u.Avatar
			}
		}
		allResults = append(allResults, result)
	}

	// 按时间排序（最新的在前）
	sort.Slice(allResults, func(i, j int) bool {
		ti, _ := allResults[i]["created_at"].(time.Time)
		tj, _ := allResults[j]["created_at"].(time.Time)
		return ti.After(tj)
	})

	// 分页
	skip := (page - 1) * limit
	end := skip + limit
	if skip >= len(allResults) {
		return []map[string]interface{}{}, total, nil
	}
	if end > len(allResults) {
		end = len(allResults)
	}

	return allResults[skip:end], total, nil
}

// GetChatMediaCounts 获取聊天媒体数量统计
func (s *MessageService) GetChatMediaCounts(ctx context.Context, chatID, userID string) (map[string]int64, error) {
	counts := map[string]int64{
		"media": 0,
		"file":  0,
		"link":  0,
		"voice": 0,
	}

	// 搜索最近 12 个月的集合
	now := time.Now()
	for i := 0; i < 12; i++ {
		t := now.AddDate(0, -i, 0)
		collection := s.mongoDB.Collection(models.GetMessageCollection(chatID, t))

		// 媒体（图片+视频）
		mediaFilter := bson.M{
			"chat_id":     chatID,
			"type":        bson.M{"$in": []int{2, 3}},
			"is_revoked":  bson.M{"$ne": true},
			"deleted_for": bson.M{"$ne": userID},
		}
		mediaCount, _ := collection.CountDocuments(ctx, mediaFilter)
		counts["media"] += mediaCount

		// 文件
		fileFilter := bson.M{
			"chat_id":     chatID,
			"type":        5,
			"is_revoked":  bson.M{"$ne": true},
			"deleted_for": bson.M{"$ne": userID},
		}
		fileCount, _ := collection.CountDocuments(ctx, fileFilter)
		counts["file"] += fileCount

		// 链接（文本消息中包含URL）
		linkFilter := bson.M{
			"chat_id":      chatID,
			"type":         1,
			"is_revoked":   bson.M{"$ne": true},
			"deleted_for":  bson.M{"$ne": userID},
			"content.text": bson.M{"$regex": `https?://`, "$options": "i"},
		}
		linkCount, _ := collection.CountDocuments(ctx, linkFilter)
		counts["link"] += linkCount

		// 语音
		voiceFilter := bson.M{
			"chat_id":     chatID,
			"type":        4,
			"is_revoked":  bson.M{"$ne": true},
			"deleted_for": bson.M{"$ne": userID},
		}
		voiceCount, _ := collection.CountDocuments(ctx, voiceFilter)
		counts["voice"] += voiceCount
	}

	return counts, nil
}

// mongoWriteTask 单条消息写入任务
type mongoWriteTask struct {
	collName string
	msg      *models.Message
}

// runMongoFlushWorker 后台批量写MongoDB
// 每20ms或积累50条时触发一次InsertMany，大幅减少磁盘IO次数
func (s *MessageService) runMongoFlushWorker() {
	ticker := time.NewTicker(20 * time.Millisecond)
	defer ticker.Stop()

	// 按collection分组缓冲
	type collBuf struct {
		msgs []interface{}
	}
	buf := make(map[string]*collBuf)

	flush := func() {
		if len(buf) == 0 {
			return
		}
		for collName, cb := range buf {
			if len(cb.msgs) == 0 {
				continue
			}
			coll := s.mongoDB.Collection(collName)
			if _, err := coll.InsertMany(context.Background(), cb.msgs); err != nil {
				log.Printf("[MongoFlush] InsertMany error coll=%s count=%d err=%v",
					collName, len(cb.msgs), err)
			}
		}
		buf = make(map[string]*collBuf)
	}

	totalBuf := 0
	for {
		select {
		case task, ok := <-s.mongoCh:
			if !ok {
				flush()
				return
			}
			if buf[task.collName] == nil {
				buf[task.collName] = &collBuf{}
			}
			buf[task.collName].msgs = append(buf[task.collName].msgs, task.msg)
			totalBuf++
			if totalBuf >= 50 {
				flush()
				totalBuf = 0
			}
		case <-ticker.C:
			flush()
			totalBuf = 0
		}
	}
}

// SearchMessagesGlobal 全局搜索文字消息（ES降级方案，MongoDB正则）
func (s *MessageService) SearchMessagesGlobal(ctx context.Context, keyword string, limit int) ([]*models.Message, error) {
	if limit <= 0 {
		limit = 20
	}
	escapedKeyword := regexp.QuoteMeta(keyword)
	collections, err := s.mongoDB.ListCollectionNames(ctx, bson.M{
		"name": bson.M{"$regex": "^messages_"},
	})
	if err != nil || len(collections) == 0 {
		collections = []string{"messages"}
	}
	sort.Sort(sort.Reverse(sort.StringSlice(collections)))

	filter := bson.M{
		"type":       models.MsgTypeText,
		"is_revoked": false,
		"content.text": bson.M{
			"$regex":   escapedKeyword,
			"$options": "i",
		},
	}
	findOptions := options.Find().
		SetSort(bson.D{{Key: "created_at", Value: -1}}).
		SetLimit(int64(limit))

	var allMessages []*models.Message
	seen := make(map[string]struct{})
	for _, name := range collections {
		if _, ok := seen[name]; ok {
			continue
		}
		seen[name] = struct{}{}
		cursor, err := s.mongoDB.Collection(name).Find(ctx, filter, findOptions)
		if err != nil {
			continue
		}
		var msgs []*models.Message
		if err := cursor.All(ctx, &msgs); err != nil {
			cursor.Close(ctx)
			continue
		}
		cursor.Close(ctx)
		allMessages = append(allMessages, msgs...)
		if len(allMessages) >= limit {
			break
		}
	}
	if len(allMessages) > limit {
		allMessages = allMessages[:limit]
	}
	return allMessages, nil
}
