// 文件用途：实现可复用的后端业务服务和领域逻辑。
// 核心逻辑：协调数据库、缓存、队列和外部服务，集中处理事务、幂等、重试和错误传播。

package services

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"github.com/google/uuid"
	"go.mongodb.org/mongo-driver/bson"
	"go.mongodb.org/mongo-driver/bson/primitive"
	"go.mongodb.org/mongo-driver/mongo"
	"go.mongodb.org/mongo-driver/mongo/options"
	"gorm.io/gorm" // MessageService 消息服务
	"log"
	"regexp"
	"sort"
	"strconv"
	"strings"
	"sync"
	"time"
	"genericim/internal/cache"
	"genericim/internal/models"
	"genericim/internal/mq"
	"genericim/internal/shard"
	"genericim/internal/ws"
)

type MessageService struct {
	mongoDB           *mongo.Database
	db                *gorm.DB
	cache             *cache.Cache
	mq                *mq.MessageQueue
	hub               *ws.Hub
	seqLock           *shard.ShardedLock // 消息序号分片锁
	indexes           sync.Map
	retentionMonths   int
	idempotencyMonths int
}

// NewMessageService 创建消息服务
func NewMessageService(
	mongoDB *mongo.Database,
	db *gorm.DB,
	cache *cache.Cache,
	mq *mq.MessageQueue,
	hub *ws.Hub,
	retentionMonths int,
	idempotencyMonths int) *MessageService {
	retentionMonths = normalizeMessageRetentionMonths(retentionMonths)
	if idempotencyMonths < retentionMonths {

		idempotencyMonths = retentionMonths
	}
	return &MessageService{

		mongoDB: mongoDB,

		db: db,

		cache: cache,

		mq: mq,

		hub: hub,

		seqLock: shard.NewShardedLock(64),

		retentionMonths: retentionMonths,

		idempotencyMonths: idempotencyMonths,
	}
}
func (s *MessageService) retainedMessageCollections(chatID string, now time.Time) []string {
	months := defaultMessageRetentionMonths
	if s != nil {

		months = s.retentionMonths
	}
	return messageCollectionNames(chatID, now, months)
}
func (s *MessageService) recentMessageCollections(chatID string, now time.Time, months int) []string {
	if months <= 0 {

		months = 1
	}
	if s != nil && s.retentionMonths > 0 && months > s.retentionMonths {

		months = s.retentionMonths
	}
	return messageCollectionNames(chatID, now, months)
}

const (
	messageUniqueMsgIDIndexName = "uniq_chat_msg_id"
	messageUniqueSeqIndexName   = "uniq_chat_seq"
	messageWindowCacheTTL       = 20 * time.Second
)

func messageWindowCacheVersionKey(chatID string) string {
	return fmt.Sprintf("message:window:%s:version", chatID)
}

func messageWindowCacheKey(chatID, userID string, version, beforeSeq uint64, limit int) string {
	if userID == "" {

		userID = "anonymous"
	}
	return fmt.Sprintf("message:window:%s:version:%d:user:%s:before:%d:limit:%d", chatID, version, userID, beforeSeq, limit)
}

// InvalidateMessageWindowCache clears hot message windows for one chat.
func (s *MessageService) InvalidateMessageWindowCache(ctx context.Context, chatID string) {
	if s == nil || s.cache == nil || chatID == "" {

		return
	}
	if _, err := s.cache.Increment(ctx, messageWindowCacheVersionKey(chatID)); err != nil {

		log.Printf("[MessageCache] invalidate message window failed chatId=%s err=%v", chatID, err)
	}
}

// DeleteAllMessagesForChat removes stored messages for a chat up to cutoff // across all message collections.
func (s *MessageService) DeleteAllMessagesForChat(ctx context.Context, chatID string, cutoff time.Time) (int64, error) {
	if s == nil || s.mongoDB == nil || chatID == "" {

		return 0, nil
	}
	defer s.InvalidateMessageWindowCache(ctx, chatID)
	names, err := s.mongoDB.ListCollectionNames(ctx, bson.M{

		"name": bson.M{"$regex": "^messages(_[0-9]{6})?$"},
	})
	if err != nil {

		return 0, err
	}
	if len(names) == 0 {

		names = []string{"messages"}
	}
	var deleted int64
	filter := bson.M{"chat_id": chatID}
	if !cutoff.IsZero() {

		filter["created_at"] = bson.M{"$lte": cutoff}
	}
	for _, name := range names {

		result, err := s.mongoDB.Collection(name).DeleteMany(ctx, filter)

		if err != nil {

			return deleted, err

		}

		deleted += result.DeletedCount
	}
	idempotencyFilter := bson.M{"chat_id": chatID}
	if !cutoff.IsZero() {

		idempotencyFilter["created_at"] = bson.M{"$lte": cutoff}
	}
	if _, err := s.mongoDB.Collection(messageIdempotencyCollectionName).DeleteMany(ctx, idempotencyFilter); err != nil {

		return deleted, err
	}
	if err := MarkChatMediaForDeletion(s.db, chatID, cutoff); err != nil {

		return deleted, fmt.Errorf("release deleted chat media: %w", err)
	}
	return deleted, nil
}
func (s *MessageService) ensureMessageCollectionIndexes(ctx context.Context, collectionName string, collection *mongo.Collection) {
	if s == nil || collection == nil || collectionName == "" {

		return
	}
	if _, loaded := s.indexes.LoadOrStore(collectionName, struct{}{}); loaded {

		return
	}
	indexCtx, cancel := context.WithTimeout(ctx, 3*time.Second)
	defer cancel()
	_, err := collection.Indexes().CreateMany(indexCtx, []mongo.IndexModel{

		{

			Keys: bson.D{{Key: "chat_id", Value: 1}, {Key: "msg_id", Value: 1}},

			Options: options.Index().
				SetName(messageUniqueMsgIDIndexName).
				SetUnique(true),
		},

		{

			Keys: bson.D{{Key: "chat_id", Value: 1}, {Key: "seq", Value: 1}},

			Options: options.Index().
				SetName(messageUniqueSeqIndexName).
				SetUnique(true),
		},

		{

			Keys: bson.D{{Key: "chat_id", Value: 1}, {Key: "created_at", Value: -1}, {Key: "msg_id", Value: 1}},

			Options: options.Index().
				SetName("idx_chat_created_msg"),
		},

		{

			Keys: bson.D{{Key: "chat_id", Value: 1}, {Key: "sender_id", Value: 1}, {Key: "seq", Value: 1}, {Key: "status", Value: 1}},

			Options: options.Index().
				SetName("idx_chat_sender_seq_status"),
		},

		{

			Keys: bson.D{{Key: "created_at", Value: -1}, {Key: "type", Value: 1}},

			Options: options.Index().
				SetName("idx_created_type"),
		},

		{

			Keys: bson.D{{Key: "chat_id", Value: 1}, {Key: "type", Value: 1}, {Key: "content.file.name", Value: 1}, {Key: "created_at", Value: -1}},

			Options: options.Index().
				SetName("idx_chat_file_name_created"),
		},
	})
	if err != nil {

		log.Printf("[MessageService] ensure message indexes failed collection=%s err=%v", collectionName, err)
	}
}
func isMongoDuplicateKeyError(err error) bool {
	if err == nil {

		return false
	}
	var writeErr mongo.WriteException
	if errors.As(err, &writeErr) {

		for _, item := range writeErr.WriteErrors {

			if item.Code == 11000 || item.Code == 11001 || item.Code == 12582 {

				return true

			}

		}
	}
	var bulkWriteErr mongo.BulkWriteException
	if errors.As(err, &bulkWriteErr) {

		for _, item := range bulkWriteErr.WriteErrors {

			if item.Code == 11000 || item.Code == 11001 || item.Code == 12582 {

				return true

			}

		}
	}
	var commandErr mongo.CommandError
	if errors.As(err, &commandErr) {

		return commandErr.Code == 11000 || commandErr.Code == 11001 || commandErr.Code == 12582
	}
	return strings.Contains(err.Error(), "E11000 duplicate key")
}
func isLikelyMessageSeqDuplicate(err error) bool {
	if err == nil {

		return false
	}
	text := err.Error()
	return strings.Contains(text, messageUniqueSeqIndexName) ||

		strings.Contains(text, "seq")
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
	OperatorType     string                          `json:"operator_type,omitempty"`
	OperatorID       string                          `json:"operator_id,omitempty"`
	Type             int                             `json:"type"`
	Content          map[string]interface{}          `json:"content"`
	E2EE             *models.EncryptedMessagePayload `json:"e2ee,omitempty"`
	MsgID            string                          `json:"msg_id,omitempty"`
	ReplyTo          *ReplyInfo                      `json:"reply_to,omitempty"`
	Mentions         []string                        `json:"mentions,omitempty"`
	BurnAfterRead    bool                            `json:"burn_after_read,omitempty"`
	BurnAfterSeconds int                             `json:"burn_after_seconds,omitempty"`
	Anonymous        bool                            `json:"anonymous,omitempty"`
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

// SendMessageResult 同时返回最终持久化消息和幂等命中状态，供 Handler 区分首次发送与重试确认。
type SendMessageResult struct {
	Message   *models.Message
	Duplicate bool
}

// SendMessageWithResult 完成消息幂等占位、序号分配、MongoDB 持久化和实时投递。 // MongoDB 写入成功是“消息已发送”的提交点；后续 MQ/WS 均为可补偿的分发路径。
func (s *MessageService) SendMessageWithResult(ctx context.Context, params *SendMessageParams, senderName, senderAvatar, senderNicknameColor, senderEmojiAvatar string, targetUserIDs []string) (*SendMessageResult, error) {
	clientMsgID := strings.TrimSpace(params.MsgID)
	var idempotencyReservation *messageIdempotencyReservation
	messageStored := false
	if clientMsgID != "" {

		// 先兼容查询历史上未写幂等账本的消息，再通过账本占位串行化同一客户端消息 ID 的并发重试。

		reservation, existing, err := s.reserveMessageIdempotency(ctx, params.ChatID, params.SenderID, clientMsgID)

		if err != nil {

			return nil, err

		}

		if existing != nil {

			return &SendMessageResult{Message: existing, Duplicate: true}, nil

		}
		idempotencyReservation = reservation

		defer func() {

			if !messageStored {

				s.releaseMessageIdempotency(ctx, idempotencyReservation)

			}

		}()
	}
	// 同一会话内必须在“取序号 -> 持久化”全过程持锁；仅原子递增 Redis
	// 不能阻止缓存回退或修复场景下两个写入者使用同一序号。
	// 1. 获取消息序号（使用分片锁保证原子性）
	seq, err := s.nextMessageSeq(ctx, params.ChatID)
	if err != nil {

		return nil, err
	}
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

			if mediaID, ok := media["media_id"].(string); ok {

				content.Media.MediaID = strings.TrimSpace(mediaID)

			}

			if thumbnailMediaID, ok := media["thumbnail_media_id"].(string); ok {

				content.Media.ThumbnailMediaID = strings.TrimSpace(thumbnailMediaID)

			}

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

			if mediaGroupID, ok := media["media_group_id"].(string); ok {

				content.Media.MediaGroupID = strings.TrimSpace(mediaGroupID)

			}

		}

		// 处理语音内容

		if voice, ok := params.Content["voice"].(map[string]interface{}); ok {

			content.Voice = &models.VoiceInfo{}

			if mediaID, ok := voice["media_id"].(string); ok {

				content.Voice.MediaID = strings.TrimSpace(mediaID)

			}

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

		if sticker, ok := params.Content["sticker"].(map[string]interface{}); ok {

			content.Sticker = &models.StickerInfo{}

			if packID, ok := sticker["pack_id"].(string); ok {

				content.Sticker.PackID = packID

			}

			if stickerID, ok := sticker["sticker_id"].(string); ok {

				content.Sticker.StickerID = stickerID

			}

			if url, ok := sticker["url"].(string); ok {

				content.Sticker.URL = url

			}

			if emoji, ok := sticker["emoji"].(string); ok {

				content.Sticker.Emoji = emoji

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

			if mediaID, ok := file["media_id"].(string); ok {

				content.File.MediaID = strings.TrimSpace(mediaID)

			}

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

		}

		if bundle, ok := params.Content["forward_bundle"].(map[string]interface{}); ok {

			raw, err := json.Marshal(bundle)

			if err != nil {

				return nil, err

			}

			content.ForwardBundle = &models.ForwardBundleInfo{}

			if err := json.Unmarshal(raw, content.ForwardBundle); err != nil {

				return nil, err

			}

		}

		// 3. 构建回复信息
	}
	var replyTo *models.ReplyInfo
	if !hasE2EE && params.ReplyTo != nil {

		replyTo = &models.ReplyInfo{

			MsgID: params.ReplyTo.MsgID,

			SenderID: params.ReplyTo.SenderID,

			SenderName: params.ReplyTo.SenderName,

			Content: params.ReplyTo.Content,
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

		MsgID: msgID,

		ChatID: params.ChatID,

		Seq: seq,

		SenderID: params.SenderID,

		SenderName: senderName,

		SenderAvatar: senderAvatar,

		SenderNicknameColor: senderNicknameColor,

		SenderEmojiAvatar: senderEmojiAvatar,

		SenderDeviceID: params.SenderDeviceID,

		OperatorType: params.OperatorType,

		OperatorID: params.OperatorID,

		IsAnonymous: params.Anonymous,

		Type: params.Type,

		Content: content,

		E2EE: params.E2EE,

		ReplyTo: replyTo,

		Mentions: mentions,

		Status: models.MsgStatusSent,

		BurnAfterRead: params.BurnAfterRead,

		BurnAfterSeconds: params.BurnAfterSeconds,

		CreatedAt: now,

		UpdatedAt: now,
	}
	// MongoDB 是消息正文、状态和顺序的权威存储；按月集合只改变物理位置，
	// chat_id + seq/client msg_id 的唯一约束仍负责兜底并发冲突。
	// 5. 存储到MongoDB（按月分表）
	collectionName := models.GetMessageCollection(params.ChatID, now)
	collection := s.mongoDB.Collection(collectionName)
	s.ensureMessageCollectionIndexes(ctx, collectionName, collection)
	for attempt := 0; attempt < 2; attempt++ {

		if _, err := collection.InsertOne(ctx, msg); err != nil {

			if isMongoDuplicateKeyError(err) {

				if clientMsgID != "" {

					if existing, ok, findErr := s.FindMessageByClientID(ctx, params.ChatID, params.SenderID, clientMsgID); findErr != nil {

						log.Printf("[MessageService] duplicate insert fallback lookup failed collection=%s chatID=%s msgID=%s err=%v",

							collectionName, params.ChatID, clientMsgID, findErr)

					} else if ok {

						return &SendMessageResult{Message: existing, Duplicate: true}, nil

					}

				}

				if attempt == 0 && isLikelyMessageSeqDuplicate(err) {

					if latestSeq, latestErr := s.getLatestMessageSeqFromMongo(ctx, params.ChatID); latestErr == nil && latestSeq >= msg.Seq {

						if setErr := s.cache.SetCurrentMsgSeq(ctx, params.ChatID, latestSeq); setErr != nil {

							log.Printf("[MessageService] repair msg seq cache after duplicate failed chatId=%s seq=%d err=%v",

								params.ChatID, latestSeq, setErr)

						}
						nextSeq, nextErr := s.cache.GetNextMsgSeq(ctx, params.ChatID)

						if nextErr == nil {

							msg.Seq = nextSeq

							continue

						}

						log.Printf("[MessageService] get next seq after duplicate failed chatId=%s err=%v", params.ChatID, nextErr)

					}

				}

			}

			log.Printf("[MessageService] insert message failed collection=%s chatID=%s msgID=%s senderID=%s type=%d err=%v",

				collectionName, params.ChatID, msg.MsgID, params.SenderID, params.Type, err)

			return nil, err

		}

		break
	}
	messageStored = true
	if idempotencyReservation != nil {

		if err := s.completeMessageIdempotency(ctx, idempotencyReservation, msg, collectionName); err != nil {

			log.Printf("[MessageIdempotency] completion failed chatId=%s msgId=%s err=%v", params.ChatID, msg.MsgID, err)

		}
	}
	// 热窗口可能含有旧的最后一页，必须在对外分发前失效，确保客户端回源能看到刚提交的消息。
	s.InvalidateMessageWindowCache(ctx, params.ChatID)
	// 顺序刻意固定为：持久化 -> 清缓存 -> MQ -> WebSocket。
	// MQ/WS 失败不会回滚已提交消息；客户端依靠 seq 断点同步补齐实时链路的丢失。
	// 6. 发布到消息队列（异步处理推送等）
	s.publishSyncMessage(msg)
	// 7. 通过 WebSocket 按会话订阅推送。客户端在加载会话列表后会订阅全部会话，
	// 因此发送 ACK 不需要先读取并展开全群 UUID；订阅接口本身会校验成员资格。
	wsPayload := map[string]interface{}{

		"type": "new_message",

		"message": publicMessageForDelivery(msg),
	}
	s.hub.SendToChat(params.ChatID, wsPayload, "")
	return &SendMessageResult{Message: msg}, nil
}
func publicMessageForDelivery(msg *models.Message) *models.Message {
	if msg == nil || !msg.IsAnonymous {

		return msg
	}
	copyMsg := *msg
	copyMsg.SenderID = "anonymous"
	copyMsg.SenderAvatar = ""
	copyMsg.SenderNicknameColor = ""
	copyMsg.SenderEmojiAvatar = ""
	copyMsg.SenderDeviceID = ""
	return &copyMsg
}
func (s *MessageService) publishSyncMessage(msg *models.Message) {
	if s == nil || s.mq == nil || msg == nil {

		return
	}
	payload, err := json.Marshal(publicMessageForDelivery(msg))
	if err != nil {

		log.Printf("[MessageService] marshal sync_message failed: chatId=%s msgId=%s err=%v", msg.ChatID, msg.MsgID, err)

		return
	}
	publishCtx, cancel := context.WithTimeout(context.Background(), 3*time.Second)
	defer cancel()
	if err := s.mq.Publish(publishCtx, mq.QueueMessageSync, &mq.QueueMessage{

		Type: "sync_message",

		Payload: payload,
	}); err != nil {

		log.Printf("[MessageService] publish sync_message failed: chatId=%s msgId=%s err=%v", msg.ChatID, msg.MsgID, err)
	}
}

// SendMessage 发送消息
func (s *MessageService) SendMessage(ctx context.Context, params *SendMessageParams, senderName, senderAvatar, senderNicknameColor, senderEmojiAvatar string, targetUserIDs []string) (*models.Message, error) {
	result, err := s.SendMessageWithResult(ctx, params, senderName, senderAvatar, senderNicknameColor, senderEmojiAvatar, targetUserIDs)
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
	return s.findMessageByClientIDInCollections(

		ctx,

		chatID,

		senderID,

		msgID,

		s.retainedMessageCollections(chatID, time.Now()),
	)
}
func (s *MessageService) findMessageByClientIDInCollections(
	ctx context.Context,
	chatID string,
	senderID string,
	msgID string,
	collectionNames []string) (*models.Message, bool, error) {
	filter := bson.M{

		"chat_id": chatID,

		"sender_id": senderID,

		"msg_id": msgID,
	}
	for _, collectionName := range collectionNames {
		col := s.mongoDB.Collection(collectionName)
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
func (s *MessageService) UpdateVoiceTranscript(ctx context.Context, chatID, msgID, transcript string) error {
	msgID = strings.TrimSpace(msgID)
	transcript = strings.TrimSpace(transcript)
	if msgID == "" || transcript == "" {

		return nil
	}
	filter := bson.M{

		"chat_id": chatID,

		"msg_id": msgID,

		"type": models.MsgTypeVoice,
	}
	update := bson.M{

		"$set": bson.M{

			"content.voice.transcript": transcript,

			"updated_at": time.Now(),
		},
	}
	for _, collectionName := range s.retainedMessageCollections(chatID, time.Now()) {
		col := s.mongoDB.Collection(collectionName)
		result, err := col.UpdateOne(ctx, filter, update)

		if err != nil {

			return err

		}

		if result.MatchedCount > 0 {

			return nil

		}
	}
	return nil
}
func (s *MessageService) FindMessageByMsgID(ctx context.Context, chatID, msgID string) (*models.Message, bool, error) {
	msgID = strings.TrimSpace(msgID)
	if msgID == "" {

		return nil, false, nil
	}
	filter := bson.M{

		"chat_id": chatID,

		"msg_id": msgID,
	}
	for _, collectionName := range s.retainedMessageCollections(chatID, time.Now()) {
		col := s.mongoDB.Collection(collectionName)
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

// GetMessagesBySeq 按序号获取消息列表 // 支持跨月查询，确保历史消息不会丢失
func (s *MessageService) GetMessagesBySeq(ctx context.Context, chatID string, beforeSeq uint64, limit int) ([]*models.Message, error) {
	return s.getMessagesBySeq(ctx, chatID, "", beforeSeq, limit, nil)
}
func (s *MessageService) getMessagesBySeq(
	ctx context.Context,
	chatID string,
	userID string,
	beforeSeq uint64,
	limit int,
	clearedAt *time.Time) ([]*models.Message, error) {
	if limit <= 0 || limit > 100 {

		limit = 50
	}
	// 构建查询条件
	cacheKey := ""
	if s.cache != nil {

		// 用户维度和 clearedAt 均进入缓存键，防止清空记录或入群历史权限不同的用户共享消息窗口。

		version, _ := s.cache.GetUint64(ctx, messageWindowCacheVersionKey(chatID))
		cacheKey = messageWindowCacheKey(chatID, userID, version, beforeSeq, limit)

		if clearedAt != nil {

			cacheKey = fmt.Sprintf("%s:after:%d", cacheKey, clearedAt.UnixNano())

		}
		var cached []*models.Message

		if err := s.cache.Get(ctx, cacheKey, &cached); err == nil {

			return cached, nil

		}
	}
	filter := bson.M{"chat_id": chatID}
	if userID != "" {

		filter["deleted_for"] = bson.M{"$ne": userID}

		filter["burned_for"] = bson.M{"$ne": userID}
	}
	if beforeSeq > 0 {

		filter["seq"] = bson.M{"$lt": beforeSeq}
	}
	if clearedAt != nil {

		filter["created_at"] = bson.M{"$gt": *clearedAt}
	}
	var allMessages []*models.Message
	// 查询完整承诺保留期内的集合，直到获取足够的消息。
	// 每次查询动态调整 limit，只取还缺少的数量，避免过度读取
	for _, collectionName := range s.retainedMessageCollections(chatID, time.Now()) {

		if len(allMessages) >= limit {

			break

		}
		remaining := int64(limit - len(allMessages))
		opts := options.Find().
			SetSort(bson.D{{Key: "seq", Value: -1}}).
			SetLimit(remaining)
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
	if cacheKey != "" {

		_ = s.cache.Set(ctx, cacheKey, allMessages, messageWindowCacheTTL)
	}
	return allMessages, nil
}
func (s *MessageService) getUserChatClearedAt(chatID, userID string) (*time.Time, error) {
	if chatID == "" || userID == "" {

		return nil, nil
	}
	type row struct {
		ClearedAt *time.Time `gorm:"column:cleared_at"`

		JoinedAt time.Time `gorm:"column:joined_at"`

		ChatType int8 `gorm:"column:chat_type"`

		MemberRole int8 `gorm:"column:member_role"`

		AllowViewHistory bool `gorm:"column:allow_view_history"`
	}
	var r row
	// 可见边界由 MySQL 中的成员关系、入群时间和用户清空时间共同决定；
	// 不能仅依赖客户端传入游标，否则可能越权读取入群前或已清空的消息。
	if err := s.db.Table("user_chats uc").
		Select("uc.cleared_at, cm.joined_at, c.type AS chat_type, cm.role AS member_role, c.allow_view_history").
		Joins("JOIN users u ON u.id = uc.user_id").
		Joins("JOIN chats c ON c.id = uc.chat_id").
		Joins("JOIN chat_members cm ON cm.chat_id = c.id AND cm.user_id = u.id").
		Where("u.uuid = ? AND c.uuid = ?", userID, chatID).
		Take(&r).Error; err != nil {

		if errors.Is(err, gorm.ErrRecordNotFound) {

			return nil, nil

		}

		return nil, err
	}
	var visibleAfter *time.Time
	if r.ClearedAt != nil && !r.ClearedAt.IsZero() {
		t := r.ClearedAt.UTC()
		visibleAfter = &t
	}
	if r.ChatType == 2 && !r.AllowViewHistory && r.MemberRole < 1 && !r.JoinedAt.IsZero() {
		joinedAt := r.JoinedAt.UTC()

		if visibleAfter == nil || joinedAt.After(*visibleAfter) {

			visibleAfter = &joinedAt

		}
	}
	if visibleAfter == nil {

		return nil, nil
	}
	return visibleAfter, nil
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

		filter["burned_for"] = bson.M{"$ne": userID}
	}
	opts := options.Find().SetSort(bson.D{{Key: "seq", Value: 1}})
	var allMessages []*models.Message
	for _, collectionName := range s.retainedMessageCollections(chatID, time.Now()) {
		collection := s.mongoDB.Collection(collectionName)
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
	for _, collectionName := range s.retainedMessageCollections(chatID, time.Now()) {
		collection := s.mongoDB.Collection(collectionName)
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
func (s *MessageService) nextMessageSeq(ctx context.Context, chatID string) (uint64, error) {
	current, err := s.cache.GetCurrentMsgSeq(ctx, chatID)
	if err != nil {
		return 0, err
	}
	if current > 0 {
		return s.cache.GetNextMsgSeq(ctx, chatID)
	}

	// The sharded lock is needed only while rebuilding a missing Redis
	// sequence. Steady-state sends use Redis INCR concurrently.
	s.seqLock.Lock(chatID)
	defer s.seqLock.Unlock(chatID)

	current, err = s.cache.GetCurrentMsgSeq(ctx, chatID)
	if err != nil {
		return 0, err
	}
	if current == 0 {
		latest, latestErr := s.getLatestMessageSeqFromMongo(ctx, chatID)
		if latestErr != nil {
			return 0, latestErr
		}
		if err := s.cache.SetCurrentMsgSeq(ctx, chatID, latest); err != nil {
			return 0, err
		}
	}
	return s.cache.GetNextMsgSeq(ctx, chatID)
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

type revokeUnreadCandidate struct {
	UserID      uint64 `gorm:"column:user_id"`
	UserUUID    string `gorm:"column:user_uuid"`
	LastReadSeq uint64 `gorm:"column:last_read_seq"`
	UnreadCount int    `gorm:"column:unread_count"`
}

func shouldDecrementUnreadAfterRevoke(
	messageSenderUUID string,
	candidate revokeUnreadCandidate,
	revokedSeq uint64) bool {
	return revokedSeq > 0 &&

		candidate.UserUUID != "" &&

		candidate.UserUUID != messageSenderUUID &&

		candidate.LastReadSeq < revokedSeq &&

		candidate.UnreadCount > 0
}

// reconcileUnreadAfterRevoke removes exactly the revoked message from each // recipient's authoritative unread count. The sender was never incremented, // and a member whose read cursor already passed the message must not be // decremented again. It also invalidates every member's chat-list cache because // the last-message preview may have changed even when unread did not.
func (s *MessageService) reconcileUnreadAfterRevoke(
	ctx context.Context,
	chat models.Chat,
	messageSenderUUID string,
	revokedSeq uint64) {
	if s == nil || s.db == nil || chat.ID == 0 || revokedSeq == 0 {

		return
	}
	var candidates []revokeUnreadCandidate
	if err := s.db.Table("user_chats AS uc").
		Select("uc.user_id, users.uuid AS user_uuid, cm.last_read_seq, uc.unread_count").
		Joins("JOIN users ON users.id = uc.user_id AND users.deleted_at IS NULL").
		Joins("JOIN chat_members AS cm ON cm.chat_id = uc.chat_id AND cm.user_id = uc.user_id").
		Where("uc.chat_id = ?", chat.ID).
		Scan(&candidates).Error; err != nil {

		log.Printf("[Message] Load revoke unread candidates failed chatId=%s seq=%d err=%v", chat.UUID, revokedSeq, err)

		return
	}
	affectedIDs := make([]uint64, 0, len(candidates))
	for _, candidate := range candidates {

		if shouldDecrementUnreadAfterRevoke(messageSenderUUID, candidate, revokedSeq) {

			affectedIDs = append(affectedIDs, candidate.UserID)

		}
	}
	if len(affectedIDs) > 0 {
		now := time.Now()

		if err := s.db.Model(&models.UserChat{}).
			Where("chat_id = ? AND user_id IN ? AND unread_count > 0", chat.ID, affectedIDs).
			Updates(map[string]interface{}{

				"unread_count": gorm.Expr("CASE WHEN unread_count > 0 THEN unread_count - 1 ELSE 0 END"),

				"updated_at": now,
			}).Error; err != nil {

			log.Printf("[Message] Reconcile revoke unread failed chatId=%s seq=%d err=%v", chat.UUID, revokedSeq, err)

		}
	}
	for _, candidate := range candidates {

		if s.cache != nil {

			if err := s.cache.DeleteByPattern(ctx, fmt.Sprintf("chat:list:user:%d:*", candidate.UserID)); err != nil {

				log.Printf("[MessageCache] invalidate chat list after revoke failed user=%d err=%v", candidate.UserID, err)

			}

		}

		if s.hub == nil || candidate.UserUUID == "" {

			continue

		}
		var userChat models.UserChat
		if err := s.db.Where("chat_id = ? AND user_id = ?", chat.ID, candidate.UserID).First(&userChat).Error; err != nil {

			continue

		}
		lastReadSeq := candidate.LastReadSeq

		s.hub.SendToUser(candidate.UserUUID, map[string]interface{}{

			"type": "chat_state_changed",

			"chat_id": chat.UUID,

			"user_id": candidate.UserUUID,

			"last_read_seq": lastReadSeq,

			"unread_count": userChat.UnreadCount,

			"is_pinned": userChat.IsPinned,

			"is_muted": userChat.IsMuted,

			"last_msg_seq": userChat.LastMsgSeq,

			"changed": []string{"unread_count", "last_msg_text"},

			"updated_at": time.Now().UTC().Format(time.RFC3339Nano),
		})
	}
}

// RevokeMessage 撤回消息（支持跨月查询；管理员撤回群消息时不要求必须是发送者）
func (s *MessageService) RevokeMessage(ctx context.Context, chatID, msgID, userID string, isAdminRevoke bool) error {
	now := time.Now()
	// 先查找消息，验证时间限制
	findFilter := bson.M{

		"chat_id": chatID,

		"msg_id": msgID,
	}
	if !isAdminRevoke {

		findFilter["sender_id"] = userID
	}
	var foundMsg bson.M
	var foundCollection *mongo.Collection
	for _, collectionName := range s.retainedMessageCollections(chatID, now) {
		col := s.mongoDB.Collection(collectionName)
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
	revokeTransitionFilter := bson.M{}
	for key, value := range findFilter {

		revokeTransitionFilter[key] = value
	}
	revokeTransitionFilter["is_revoked"] = bson.M{"$ne": true}
	result, err := foundCollection.UpdateOne(ctx, revokeTransitionFilter, update)
	if err != nil {

		return ErrMessageNotFound
	}
	if result.MatchedCount == 0 {

		// A retry that observes the already-revoked terminal state is a

		// successful no-op. This prevents a concurrent/retried request from

		// decrementing unread counts or broadcasting the transition twice.
		var current bson.M
		if err := foundCollection.FindOne(ctx, findFilter).Decode(&current); err == nil {

			if revoked, ok := current["is_revoked"].(bool); ok && revoked {

				if releaseErr := MarkMessageMediaForDeletion(s.db, msgID); releaseErr != nil {

					return fmt.Errorf("release revoked message media: %w", releaseErr)

				}

				return nil

			}

		}

		return ErrMessageNotFound
	}
	if releaseErr := MarkMessageMediaForDeletion(s.db, msgID); releaseErr != nil {

		// The message transition is already durable in MongoDB. Continue the

		// user-visible revoke flow and let an idempotent retry repair the media

		// lifecycle instead of leaving clients with inconsistent revoke state.

		log.Printf("[Message] release revoked media failed chatId=%s msgId=%s err=%v", chatID, msgID, releaseErr)
	}
	s.InvalidateMessageWindowCache(ctx, chatID)
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
	// 广播撤回通知给所有成员的所有设备（多端同步）
	revokePayload := map[string]interface{}{

		"type": "message_revoked",

		"chat_id": chatID,

		"msg_id": msgID,

		"revoker_id": userID,

		"msg_seq": revokedSeq,
	}
	if memberUUIDs := s.getChatMemberUUIDs(chatID); len(memberUUIDs) > 0 {

		s.hub.Broadcast(&ws.BroadcastMessage{

			Type: "message_revoked",

			UserIDs: memberUUIDs,

			Data: revokePayload,
		})
	} else {

		s.hub.SendToChat(chatID, revokePayload, "")
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
					Updates(map[string]interface{}{"last_msg_text": "你撤回了一条消息", "last_msg_sender": "", "last_msg_media_url": ""})

				s.db.Model(&models.UserChat{}).
					Where(othersWhere, chat.ID, revokerUser.ID, revokedSeq).
					Updates(map[string]interface{}{"last_msg_text": "有人撤回了一条消息", "last_msg_sender": "", "last_msg_media_url": ""})

			} else {

				s.db.Model(&models.UserChat{}).
					Where("chat_id = ? AND user_id = ?", chat.ID, revokerUser.ID).
					Updates(map[string]interface{}{"last_msg_text": "你撤回了一条消息", "last_msg_sender": "", "last_msg_media_url": ""})

				s.db.Model(&models.UserChat{}).
					Where("chat_id = ? AND user_id != ?", chat.ID, revokerUser.ID).
					Updates(map[string]interface{}{"last_msg_text": "有人撤回了一条消息", "last_msg_sender": "", "last_msg_media_url": ""})

			}

		} else {

			// 若找不到用户，fallback 为统一文本

			if revokedSeq > 0 {

				s.db.Model(&models.UserChat{}).
					Where("chat_id = ? AND last_msg_seq = ?", chat.ID, revokedSeq).
					Updates(map[string]interface{}{"last_msg_text": "有人撤回了一条消息", "last_msg_sender": "", "last_msg_media_url": ""})

			} else {

				s.db.Model(&models.UserChat{}).Where("chat_id = ?", chat.ID).
					Updates(map[string]interface{}{"last_msg_text": "有人撤回了一条消息", "last_msg_sender": "", "last_msg_media_url": ""})

			}

		}
		messageSenderUUID, _ := foundMsg["sender_id"].(string)

		s.reconcileUnreadAfterRevoke(ctx, chat, messageSenderUUID, uint64(revokedSeq))
	}
	return nil
}

// DeleteMessageForUser 删除消息（仅对当前用户不可见）
func (s *MessageService) DeleteMessageForUser(ctx context.Context, chatID, msgID, userID string) error {
	// 搜索完整保留期内的集合找到消息。
	for _, collectionName := range s.retainedMessageCollections(chatID, time.Now()) {
		collection := s.mongoDB.Collection(collectionName)

		// 将用户 ID 添加到 deleted_for 数组

		result, err := collection.UpdateOne(ctx,

			bson.M{"chat_id": chatID, "msg_id": msgID},

			bson.M{

				"$addToSet": bson.M{"deleted_for": userID},

				"$set": bson.M{"updated_at": time.Now()},
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
	// 广播已读状态
	s.hub.SendToChat(chatID, map[string]interface{}{

		"type": "read_receipt",

		"chat_id": chatID,

		"user_id": userID,

		"msg_seq": msgSeq,
	}, "")
	return nil
}

// BroadcastReadReceipt 广播已读回执给指定用户
func (s *MessageService) BroadcastReadReceipt(chatID, userID string, msgSeq int, targetUserIDs []string) {
	payload := map[string]interface{}{

		"type": "read",

		"chat_id": chatID,

		"user_id": userID,

		"msg_seq": msgSeq,
	}
	s.hub.Broadcast(&ws.BroadcastMessage{

		Type: "read",

		UserIDs: targetUserIDs,

		Data: payload,
	})
}

// BroadcastDeliveryReceipt broadcasts a delivered receipt to message senders.
func (s *MessageService) BroadcastDeliveryReceipt(chatID, userID string, msgSeq int, targetUserIDs []string) {
	if s == nil || s.hub == nil || len(targetUserIDs) == 0 || msgSeq <= 0 {

		return
	}
	payload := map[string]interface{}{

		"type": "delivered",

		"chat_id": chatID,

		"user_id": userID,

		"msg_seq": msgSeq,
	}
	s.hub.Broadcast(&ws.BroadcastMessage{

		Type: "delivered",

		UserIDs: targetUserIDs,

		Data: payload,
	})
}

// MarkMessagesAsDelivered persists delivered state for messages fetched by the recipient. // It never downgrades read messages because only status values below delivered are updated. // MongoDB 中的状态是送达回执权威值；WebSocket 回执仅用于通知发送方刷新界面。
func (s *MessageService) MarkMessagesAsDelivered(ctx context.Context, chatID, receiverID string, msgSeq int, senderIDs []string) error {
	if len(senderIDs) == 0 || msgSeq <= 0 {

		return nil
	}
	filter := bson.M{

		"chat_id": chatID,

		"sender_id": bson.M{"$in": senderIDs},

		"seq": bson.M{"$lte": msgSeq},

		"status": bson.M{"$lt": models.MsgStatusDelivered},
	}
	update := bson.M{

		"$set": bson.M{

			"status": models.MsgStatusDelivered,

			"updated_at": time.Now(),
		},
	}
	modified := false
	for _, collectionName := range s.retainedMessageCollections(chatID, time.Now()) {
		collection := s.mongoDB.Collection(collectionName)
		result, err := collection.UpdateMany(ctx, filter, update)

		if err != nil {

			return err

		}

		if result.ModifiedCount > 0 {

			modified = true

		}
	}
	if modified {

		s.InvalidateMessageWindowCache(ctx, chatID)

		log.Printf("[Message] Delivered status persisted chatId=%s receiverId=%s seq=%d senders=%d",

			chatID, receiverID, msgSeq, len(senderIDs))
	}
	return nil
}

// MarkMessagesAsRead 将对方发送的消息标记为已读（持久化到 MongoDB） // 只标记发送者不是当前用户且 seq <= msgSeq 的消息（支持跨月查询） // 状态更新使用单调条件，重复回执天然幂等，也不会把已读状态降级为已送达。
func (s *MessageService) MarkMessagesAsRead(ctx context.Context, chatID, readerID string, msgSeq int, senderIDs []string) error {
	if len(senderIDs) == 0 || msgSeq <= 0 {

		return nil
	}
	// 更新所有对方发送的、seq <= msgSeq 的消息为已读状态
	filter := bson.M{

		"chat_id": chatID,

		"sender_id": bson.M{"$in": senderIDs}, // 只更新对方发送的消息

		"seq": bson.M{"$lte": msgSeq},

		"status": bson.M{"$lt": models.MsgStatusRead}, // 只更新未读的消息
	}
	update := bson.M{

		"$set": bson.M{

			"status": models.MsgStatusRead,
		},
	}
	for _, collectionName := range s.retainedMessageCollections(chatID, time.Now()) {
		collection := s.mongoDB.Collection(collectionName)

		if _, err := collection.UpdateMany(ctx, filter, update); err != nil {

			return err

		}
	}
	s.InvalidateMessageWindowCache(ctx, chatID)
	burnFilter := bson.M{

		"chat_id": chatID,

		"sender_id": bson.M{"$in": senderIDs},

		"seq": bson.M{"$lte": msgSeq},

		"burn_after_read": true,

		"burned_for": bson.M{"$ne": readerID},
	}
	burnUpdate := bson.M{"$addToSet": bson.M{"burned_for": readerID}}
	burnApplied := false
	for _, collectionName := range s.retainedMessageCollections(chatID, time.Now()) {
		collection := s.mongoDB.Collection(collectionName)
		result, err := collection.UpdateMany(ctx, burnFilter, burnUpdate)

		if err != nil {

			return err

		}

		if result.ModifiedCount > 0 {

			burnApplied = true

		}
	}
	if burnApplied {

		if err := s.refreshUserChatPreviewAfterBurn(ctx, chatID, readerID, uint64(msgSeq)); err != nil {

			log.Printf("[Message] Refresh user chat preview after burn failed chatId=%s userId=%s seq=%d err=%v", chatID, readerID, msgSeq, err)

		}
	}
	if burnApplied && s.hub != nil {

		s.hub.SendToUser(readerID, map[string]interface{}{

			"type": "message_burned",

			"chat_id": chatID,

			"user_id": readerID,

			"msg_seq": msgSeq,
		})
	}
	return nil
}

// SyncMessages 同步消息（客户端断线重连后同步）
func (s *MessageService) SyncMessages(ctx context.Context, chatID, userID string, lastSeq int, limit int) ([]*models.Message, error) {
	if limit <= 0 {

		limit = 100
	}
	if limit > 200 {

		limit = 200
	}
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
	endSeq := currentSeq
	if uint64(lastSeq+limit) < endSeq {

		endSeq = uint64(lastSeq + limit)
	}
	// 获取增量消息
	messages, err := s.GetMessagesBySeqRange(ctx, chatID, userID, uint64(lastSeq)+1, endSeq)
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
func filterMessagesAfter(messages []*models.Message, after *time.Time) []*models.Message {
	if after == nil {

		return messages
	}
	filtered := make([]*models.Message, 0, len(messages))
	for _, msg := range messages {

		if msg == nil {

			continue

		}

		if msg.CreatedAt.After(*after) {

			filtered = append(filtered, msg)

		}
	}
	return filtered
}

// MessageSearchOptions contains optional filters for user-facing message search.
type MessageSearchOptions struct {
	Keyword     string
	SenderID    string
	MessageType *int
	StartAt     *time.Time
	EndAt       *time.Time
}

func buildMessageSearchFilter(chatID, userID string, search MessageSearchOptions) bson.M {
	filter := bson.M{

		"chat_id": chatID,

		"is_revoked": false,
	}
	if userID != "" {

		filter["deleted_for"] = bson.M{"$ne": userID}

		filter["burned_for"] = bson.M{"$ne": userID}
	}
	if keyword := strings.TrimSpace(search.Keyword); keyword != "" {
		escapedKeyword := regexp.QuoteMeta(keyword)
		pattern := bson.M{"$regex": escapedKeyword, "$options": "i"}

		filter["$or"] = []bson.M{

			{"content.text": pattern},

			{"content.file.name": pattern},

			{"content.voice.transcript": pattern},

			{"content.location.title": pattern},

			{"content.location.address": pattern},

			{"content.contact.nickname": pattern},

			{"content.contact.username": pattern},
		}
	}
	if senderID := strings.TrimSpace(search.SenderID); senderID != "" {

		filter["sender_id"] = senderID
	}
	if search.MessageType != nil {

		filter["type"] = *search.MessageType
	}
	createdAt := bson.M{}
	if search.StartAt != nil {

		createdAt["$gte"] = search.StartAt.UTC()
	}
	if search.EndAt != nil {

		createdAt["$lt"] = search.EndAt.UTC()
	}
	if len(createdAt) > 0 {

		filter["created_at"] = createdAt
	}
	return filter
}

// SearchMessagesWithOptions searches all retained message collections and // applies user-specific visibility constraints when userID is provided.
func (s *MessageService) SearchMessagesWithOptions(
	ctx context.Context,
	chatID string,
	userID string,
	search MessageSearchOptions,
	limit int) ([]*models.Message, error) {
	if limit <= 0 {

		limit = 50
	}
	collections := s.retainedMessageCollections(chatID, time.Now())
	filter := buildMessageSearchFilter(chatID, userID, search)
	findOptions := options.Find().
		SetSort(bson.D{{Key: "created_at", Value: -1}}).
		SetLimit(int64(limit))
	var allMessages []*models.Message
	for _, name := range collections {

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

// SearchMessages searches messages by keyword without a user visibility scope.
func (s *MessageService) SearchMessages(ctx context.Context, chatID, keyword string, limit int) ([]*models.Message, error) {
	return s.SearchMessagesWithOptions(ctx, chatID, "", MessageSearchOptions{Keyword: keyword}, limit)
}
func (s *MessageService) SearchMessagesForUser(ctx context.Context, chatID, userID, keyword string, limit int) ([]*models.Message, error) {
	return s.SearchMessagesForUserWithOptions(ctx, chatID, userID, MessageSearchOptions{Keyword: keyword}, limit)
}
func (s *MessageService) SearchMessagesForUserWithOptions(
	ctx context.Context,
	chatID string,
	userID string,
	search MessageSearchOptions,
	limit int) ([]*models.Message, error) {
	messages, err := s.SearchMessagesWithOptions(ctx, chatID, userID, search, limit)
	if err != nil {

		return nil, err
	}
	visibleAfter, err := s.getUserChatClearedAt(chatID, userID)
	if err != nil {

		return nil, err
	}
	return filterMessagesAfter(messages, visibleAfter), nil
}
func (s *MessageService) SearchFiles(ctx context.Context, chatID, userID, keyword string, limit int) ([]*models.Message, error) {
	if limit <= 0 {

		limit = 20
	}
	visibleAfter, err := s.getUserChatClearedAt(chatID, userID)
	if err != nil {

		return nil, err
	}
	escapedKeyword := regexp.QuoteMeta(keyword)
	filter := bson.M{

		"chat_id": chatID,

		"type": models.MsgTypeFile,

		"is_revoked": false,

		"deleted_for": bson.M{"$ne": userID},

		"$or": []bson.M{

			{"content.file.name": bson.M{"$regex": escapedKeyword, "$options": "i"}},

			{"content.file.mime_type": bson.M{"$regex": escapedKeyword, "$options": "i"}},
		},
	}
	opts := options.Find().
		SetSort(bson.D{{Key: "created_at", Value: -1}}).
		SetLimit(int64(limit))
	var allMessages []*models.Message
	for _, collectionName := range s.retainedMessageCollections(chatID, time.Now()) {

		if len(allMessages) >= limit {

			break

		}
		collection := s.mongoDB.Collection(collectionName)
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
	sort.Slice(allMessages, func(i, j int) bool {

		return allMessages[i].CreatedAt.After(allMessages[j].CreatedAt)
	})
	allMessages = filterMessagesAfter(allMessages, visibleAfter)
	if len(allMessages) > limit {

		allMessages = allMessages[:limit]
	}
	return allMessages, nil
}

// AddReaction 添加表情回复
func (s *MessageService) AddReaction(ctx context.Context, chatID, msgID, userID, userName, emoji string) error {
	// 获取消息所在的集合（覆盖完整保留期）。
	var targetCollection *mongo.Collection
	var targetMsg *models.Message
	for _, collectionName := range s.retainedMessageCollections(chatID, time.Now()) {
		collection := s.mongoDB.Collection(collectionName)
		var msg models.Message

		err := collection.FindOne(ctx, bson.M{

			"chat_id": chatID,

			"msg_id": msgID,
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

		Emoji: emoji,

		UserID: userID,

		UserName: userName,

		CreatedAt: time.Now(),
	}
	_, err := targetCollection.UpdateOne(ctx,

		bson.M{"chat_id": chatID, "msg_id": msgID},

		bson.M{

			"$push": bson.M{"reactions": reaction},

			"$set": bson.M{"updated_at": time.Now()},
		},
	)
	if err != nil {

		return err
	}
	s.InvalidateMessageWindowCache(ctx, chatID)
	// 通过 WebSocket 广播表情回复
	s.broadcastReaction(chatID, msgID, userID, userName, emoji, "add")
	return nil
}

// RemoveReaction 移除表情回复
func (s *MessageService) RemoveReaction(ctx context.Context, chatID, msgID, userID, emoji string) error {
	// 获取消息所在的集合。
	var targetCollection *mongo.Collection
	for _, collectionName := range s.retainedMessageCollections(chatID, time.Now()) {
		collection := s.mongoDB.Collection(collectionName)
		count, err := collection.CountDocuments(ctx, bson.M{

			"chat_id": chatID,

			"msg_id": msgID,
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

					"emoji": emoji,
				},
			},

			"$set": bson.M{"updated_at": time.Now()},
		},
	)
	if err != nil {

		return err
	}
	s.InvalidateMessageWindowCache(ctx, chatID)
	// 通过 WebSocket 广播移除表情
	s.broadcastReaction(chatID, msgID, userID, "", emoji, "remove")
	return nil
}

// broadcastReaction 广播表情回复事件给所有成员的所有设备（多端同步）
func (s *MessageService) broadcastReaction(chatID, msgID, userID, userName, emoji, action string) {
	reactionPayload := map[string]interface{}{

		"type": "reaction",

		"chat_id": chatID,

		"msg_id": msgID,

		"user_id": userID,

		"user_name": userName,

		"emoji": emoji,

		"action": action,
	}
	if memberUUIDs := s.getChatMemberUUIDs(chatID); len(memberUUIDs) > 0 {

		s.hub.Broadcast(&ws.BroadcastMessage{

			Type: "reaction",

			UserIDs: memberUUIDs,

			Data: reactionPayload,
		})
	} else {

		s.hub.SendToChat(chatID, reactionPayload, "")
	}
}

// ForwardMessage 转发消息。clientMsgID 用于保证网络层重试时只生成一条目标消息。
func (s *MessageService) ForwardMessage(ctx context.Context, sourceChatID, sourceMsgID, targetChatID, senderID, senderName, senderAvatar, senderNicknameColor, senderEmojiAvatar, clientMsgID string, targetUserIDs []string) (*SendMessageResult, error) {
	// 获取源消息。
	var sourceMsg *models.Message
	for _, collectionName := range s.retainedMessageCollections(sourceChatID, time.Now()) {
		collection := s.mongoDB.Collection(collectionName)
		var msg models.Message

		err := collection.FindOne(ctx, bson.M{

			"chat_id": sourceChatID,

			"msg_id": sourceMsgID,
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
	clientMsgID = strings.TrimSpace(clientMsgID)
	if clientMsgID != "" {

		if existing, ok, err := s.FindMessageByClientID(ctx, targetChatID, senderID, clientMsgID); err != nil {

			return nil, err

		} else if ok {

			return &SendMessageResult{Message: existing, Duplicate: true}, nil

		}
	}
	// 获取新序号
	s.seqLock.Lock(targetChatID)
	seq, err := s.cache.GetNextMsgSeq(ctx, targetChatID)
	if err == nil {

		seq = s.repairNextMsgSeqIfNeeded(ctx, targetChatID, seq)
	}
	s.seqLock.Unlock(targetChatID)
	if err != nil {

		return nil, err
	}
	// 创建新消息（复制内容）
	msgID := clientMsgID
	if msgID == "" {

		msgID = uuid.New().String()
	}
	newMsg := &models.Message{

		MsgID: msgID,

		ChatID: targetChatID,

		Seq: seq,

		SenderID: senderID,

		SenderName: senderName,

		SenderAvatar: senderAvatar,

		SenderNicknameColor: senderNicknameColor,

		SenderEmojiAvatar: senderEmojiAvatar,

		Type: sourceMsg.Type,

		Content: sourceMsg.Content,

		Status: models.MsgStatusSent,

		CreatedAt: time.Now(),

		UpdatedAt: time.Now(),
	}
	// 保存到目标会话的集合
	targetCollectionName := models.GetMessageCollection(targetChatID, time.Now())
	targetCollection := s.mongoDB.Collection(targetCollectionName)
	s.ensureMessageCollectionIndexes(ctx, targetCollectionName, targetCollection)
	_, err = targetCollection.InsertOne(ctx, newMsg)
	if err != nil {

		if clientMsgID != "" && isMongoDuplicateKeyError(err) {

			if existing, ok, findErr := s.FindMessageByClientID(ctx, targetChatID, senderID, clientMsgID); findErr != nil {

				return nil, findErr

			} else if ok {

				return &SendMessageResult{Message: existing, Duplicate: true}, nil

			}

		}

		return nil, err
	}
	s.InvalidateMessageWindowCache(ctx, targetChatID)
	// 转发消息同样按已鉴权的会话订阅投递，避免在提交链路展开全群 UUID。
	s.hub.SendToChat(targetChatID, map[string]interface{}{

		"type": "new_message",

		"message": newMsg,
	}, "")
	return &SendMessageResult{Message: newMsg}, nil
}

// EditMessage 编辑消息
func (s *MessageService) EditMessage(ctx context.Context, chatID, msgID, userID, newContent string) error {
	// 查找消息。
	var targetCollection *mongo.Collection
	var targetMsg *models.Message
	for _, collectionName := range s.retainedMessageCollections(chatID, time.Now()) {
		collection := s.mongoDB.Collection(collectionName)
		var msg models.Message

		err := collection.FindOne(ctx, bson.M{

			"chat_id": chatID,

			"msg_id": msgID,
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

				"is_edited": true,

				"edited_at": editedAt,

				"updated_at": editedAt,
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

		"type": "message_edited",

		"chat_id": chatID,

		"msg_id": msgID,

		"new_content": previewText,

		"is_edited": true,

		"edited_at": editedAt,

		"seq": targetMsg.Seq,

		"message": targetMsg,
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

				"last_msg_text": previewText,

				"last_msg_sender": targetMsg.SenderName,

				"last_msg_media_url": "",
			})
	}
	if memberUUIDs := s.getChatMemberUUIDs(chatID); len(memberUUIDs) > 0 {

		s.hub.Broadcast(&ws.BroadcastMessage{

			Type: "message_edited",

			UserIDs: memberUUIDs,

			Data: editPayload,
		})
	} else {

		s.hub.SendToChat(chatID, editPayload, "")
	}
	return nil
}

// GetChatMediaMessages 获取聊天媒体消息
func (s *MessageService) GetChatMediaMessages(ctx context.Context, chatID, userID string, msgTypes []int, filterType string, page, limit int) ([]map[string]interface{}, int64, error) {
	// 构建查询条件
	filter := bson.M{

		"chat_id": chatID,

		"type": bson.M{"$in": msgTypes},

		"is_revoked": bson.M{"$ne": true},

		"deleted_for": bson.M{"$ne": userID}, // 排除用户已删除的消息
	}
	// 如果是链接类型，需要检查内容中是否包含链接
	if filterType == "link" {

		filter["content.text"] = bson.M{"$regex": `https?://`, "$options": "i"}
	}
	var rawMsgs []bson.M
	var total int64
	for _, collectionName := range s.retainedMessageCollections(chatID, time.Now()) {
		collection := s.mongoDB.Collection(collectionName)

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

			"id": msg["_id"],

			"msg_id": msg["msg_id"],

			"chat_id": msg["chat_id"],

			"seq": msg["seq"],

			"sender_id": msg["sender_id"],

			"type": msg["type"],

			"content": msg["content"],

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

		"file": 0,

		"link": 0,

		"voice": 0,
	}
	for _, collectionName := range s.retainedMessageCollections(chatID, time.Now()) {
		collection := s.mongoDB.Collection(collectionName)

		// 媒体（图片+视频）

		mediaFilter := bson.M{

			"chat_id": chatID,

			"type": bson.M{"$in": []int{2, 3}},

			"is_revoked": bson.M{"$ne": true},

			"deleted_for": bson.M{"$ne": userID},
		}
		mediaCount, _ := collection.CountDocuments(ctx, mediaFilter)

		counts["media"] += mediaCount

		// 文件

		fileFilter := bson.M{

			"chat_id": chatID,

			"type": 5,

			"is_revoked": bson.M{"$ne": true},

			"deleted_for": bson.M{"$ne": userID},
		}
		fileCount, _ := collection.CountDocuments(ctx, fileFilter)

		counts["file"] += fileCount

		// 链接（文本消息中包含URL）

		linkFilter := bson.M{

			"chat_id": chatID,

			"type": 1,

			"is_revoked": bson.M{"$ne": true},

			"deleted_for": bson.M{"$ne": userID},

			"content.text": bson.M{"$regex": `https?://`, "$options": "i"},
		}
		linkCount, _ := collection.CountDocuments(ctx, linkFilter)

		counts["link"] += linkCount

		// 语音

		voiceFilter := bson.M{

			"chat_id": chatID,

			"type": 4,

			"is_revoked": bson.M{"$ne": true},

			"deleted_for": bson.M{"$ne": userID},
		}
		voiceCount, _ := collection.CountDocuments(ctx, voiceFilter)

		counts["voice"] += voiceCount
	}
	return counts, nil
}
