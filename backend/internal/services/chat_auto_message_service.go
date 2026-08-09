// 文件用途：实现可复用的后端业务服务和领域逻辑。
// 核心逻辑：协调数据库、缓存、队列和外部服务，集中处理事务、幂等、重试和错误传播。

package services

import (
	"context"
	"encoding/json"
	"fmt"
	"gorm.io/gorm"
	"log"
	"strings"
	"time"
	"genericim/internal/cache"
	"genericim/internal/models"
	"genericim/internal/ws"
)

type ChatAutoMessageService struct {
	db          *gorm.DB
	msgService  *MessageService
	cache       *cache.Cache
	hub         *ws.Hub
	pushService *PushService
	stopCh      chan struct{}
}

func NewChatAutoMessageService(db *gorm.DB, msgService *MessageService, cache *cache.Cache, hub *ws.Hub, pushService *PushService) *ChatAutoMessageService {
	return &ChatAutoMessageService{
		db:          db,
		msgService:  msgService,
		cache:       cache,
		hub:         hub,
		pushService: pushService,
		stopCh:      make(chan struct{}),
	}
}

func (s *ChatAutoMessageService) Start() {
	if s == nil || s.db == nil || s.msgService == nil {
		return
	}
	go s.loop()
}

func (s *ChatAutoMessageService) Stop() {
	if s == nil || s.stopCh == nil {
		return
	}
	close(s.stopCh)
}

func (s *ChatAutoMessageService) loop() {
	ticker := time.NewTicker(30 * time.Second)
	defer ticker.Stop()
	s.runDue(context.Background())
	for {
		select {
		case <-ticker.C:
			s.runDue(context.Background())
		case <-s.stopCh:
			return
		}
	}
}

func (s *ChatAutoMessageService) runDue(ctx context.Context) {
	now := time.Now()
	var items []models.ChatAutoMessage
	if err := s.db.
		Where("enabled = ? AND next_run_at IS NOT NULL AND next_run_at <= ?", true, now).
		Order("next_run_at ASC, id ASC").
		Limit(20).
		Find(&items).Error; err != nil {
		log.Printf("[AutoMessage] query due messages failed: %v", err)
		return
	}
	for _, item := range items {
		scheduledRunAt := item.NextRunAt
		if item.LockedRunAt != nil && !item.LockedRunAt.IsZero() {
			scheduledRunAt = item.LockedRunAt
		}
		claimed, ok := s.claimDue(ctx, item.ID, now, scheduledRunAt)
		if !ok {
			continue
		}
		if err := s.sendOne(ctx, claimed, now, scheduledRunAt); err != nil {
			log.Printf("[AutoMessage] send failed id=%d chat_id=%d err=%v", item.ID, item.ChatID, err)
		}
	}
}

func (s *ChatAutoMessageService) claimDue(ctx context.Context, id uint64, now time.Time, scheduledRunAt *time.Time) (models.ChatAutoMessage, bool) {
	claimUntil := now.Add(2 * time.Minute)
	result := s.db.WithContext(ctx).
		Model(&models.ChatAutoMessage{}).
		Where("id = ? AND enabled = ? AND next_run_at IS NOT NULL AND next_run_at <= ?", id, true, now).
		Updates(map[string]interface{}{
			"next_run_at":   claimUntil,
			"locked_run_at": scheduledRunAt,
			"updated_at":    now,
		})
	if result.Error != nil {
		log.Printf("[AutoMessage] claim failed id=%d err=%v", id, result.Error)
		return models.ChatAutoMessage{}, false
	}
	if result.RowsAffected != 1 {
		return models.ChatAutoMessage{}, false
	}
	var item models.ChatAutoMessage
	if err := s.db.WithContext(ctx).Where("id = ?", id).First(&item).Error; err != nil {
		log.Printf("[AutoMessage] load claimed message failed id=%d err=%v", id, err)
		return models.ChatAutoMessage{}, false
	}
	return item, true
}

func (s *ChatAutoMessageService) sendOne(ctx context.Context, item models.ChatAutoMessage, now time.Time, scheduledRunAt *time.Time) error {
	var chat models.Chat
	if err := s.db.Where("id = ? AND status = ?", item.ChatID, models.ChatStatusNormal).First(&chat).Error; err != nil {
		return err
	}

	var sender models.User
	if item.CreatedBy == 0 {
		s.disableAutoMessage(ctx, item, now, "missing creator")
		return nil
	}
	if err := s.db.Where("id = ? AND status = ?", item.CreatedBy, models.UserStatusNormal).First(&sender).Error; err != nil || sender.UUID == "" {
		s.disableAutoMessage(ctx, item, now, "creator missing or not normal")
		return nil
	}
	var creatorMember models.ChatMember
	if err := s.db.Where("chat_id = ? AND user_id = ? AND role >= ?", chat.ID, sender.ID, int8(2)).First(&creatorMember).Error; err != nil {
		s.disableAutoMessage(ctx, item, now, "creator is no longer owner")
		return nil
	}
	senderID := sender.UUID
	senderName := sender.Nickname
	if strings.TrimSpace(senderName) == "" {
		senderName = sender.Username
	}
	if strings.TrimSpace(senderName) == "" {
		senderName = "定时消息"
	}
	senderAvatar := sender.Avatar
	senderNicknameColor := sender.NicknameColor
	senderEmojiAvatar := sender.EmojiAvatar

	var memberIDs []uint64
	if err := s.db.Model(&models.ChatMember{}).Where("chat_id = ?", chat.ID).Pluck("user_id", &memberIDs).Error; err != nil {
		return err
	}
	var targetUserIDs []string
	if len(memberIDs) > 0 {
		query := s.db.Model(&models.User{}).Where("id IN ?", memberIDs)
		if sender.ID > 0 {
			query = query.Where("id != ?", sender.ID)
		}
		if err := query.Pluck("uuid", &targetUserIDs).Error; err != nil {
			return err
		}
	}

	msgType, msgContent := autoMessageSendContent(item)
	msgID := autoMessageRunMsgID(item.ID, scheduledRunAt, now)
	sendResult, err := s.msgService.SendMessageWithResult(ctx, &SendMessageParams{
		ChatID:   chat.UUID,
		SenderID: senderID,
		Type:     msgType,
		Content:  msgContent,
		MsgID:    msgID,
	}, senderName, senderAvatar, senderNicknameColor, senderEmojiAvatar, targetUserIDs)
	if err != nil {
		return err
	}
	if sendResult == nil || sendResult.Message == nil {
		return fmt.Errorf("auto message send returned empty result")
	}
	msg := sendResult.Message

	previewText := autoMessagePreviewText(item)
	if len([]rune(previewText)) > 200 {
		previewText = string([]rune(previewText)[:200])
	}
	if err := s.db.Model(&models.UserChat{}).
		Where("chat_id = ?", chat.ID).
		Updates(map[string]interface{}{
			"last_msg_text":      previewText,
			"last_msg_type":      msg.Type,
			"last_msg_time":      msg.CreatedAt,
			"last_msg_seq":       msg.Seq,
			"last_msg_sender":    senderName,
			"last_msg_media_url": MessagePreviewMediaURL(msg),
			"sort_time":          msg.CreatedAt,
		}).Error; err != nil {
		return err
	}
	if !sendResult.Duplicate {
		query := s.db.Model(&models.UserChat{}).Where("chat_id = ?", chat.ID)
		if sender.ID > 0 {
			query = query.Where("user_id != ?", sender.ID)
		}
		if err := query.UpdateColumn("unread_count", gorm.Expr("unread_count + 1")).Error; err != nil {
			return err
		}
	}
	s.syncChatStateAfterMessage(ctx, chat, msg, sender, memberIDs, targetUserIDs, previewText, MessagePreviewMediaURL(msg), sendResult.Duplicate)
	updates := map[string]interface{}{
		"last_run_at":   now,
		"locked_run_at": nil,
		"updated_at":    now,
	}
	next := NextChatAutoMessageRun(item, now)
	if next == nil {
		updates["enabled"] = false
		updates["next_run_at"] = nil
	} else {
		updates["next_run_at"] = *next
	}
	result := s.db.Model(&models.ChatAutoMessage{}).
		Where("id = ? AND enabled = ? AND next_run_at = ?", item.ID, true, item.NextRunAt).
		Updates(updates)
	if result.Error != nil {
		return result.Error
	}
	if result.RowsAffected == 0 {
		log.Printf("[AutoMessage] skip final update because rule changed id=%d chat_id=%d", item.ID, item.ChatID)
	}
	return nil
}

func (s *ChatAutoMessageService) disableAutoMessage(ctx context.Context, item models.ChatAutoMessage, now time.Time, reason string) {
	if s == nil || s.db == nil {
		return
	}
	if err := s.db.WithContext(ctx).Model(&models.ChatAutoMessage{}).
		Where("id = ?", item.ID).
		Updates(map[string]interface{}{
			"enabled":       false,
			"next_run_at":   nil,
			"locked_run_at": nil,
			"updated_at":    now,
		}).Error; err != nil {
		log.Printf("[AutoMessage] disable failed id=%d chat_id=%d reason=%s err=%v", item.ID, item.ChatID, reason, err)
		return
	}
	log.Printf("[AutoMessage] disabled id=%d chat_id=%d reason=%s", item.ID, item.ChatID, reason)
}

func autoMessageRunMsgID(ruleID uint64, scheduledRunAt *time.Time, fallback time.Time) string {
	runAt := fallback
	if scheduledRunAt != nil && !scheduledRunAt.IsZero() {
		runAt = *scheduledRunAt
	}
	return fmt.Sprintf("auto-%d-%d", ruleID, runAt.UnixNano())
}

func autoMessageSendContent(item models.ChatAutoMessage) (int, map[string]interface{}) {
	if item.MessageType == models.MsgTypeImage {
		return models.MsgTypeImage, map[string]interface{}{
			"media": autoMessageMediaMap(item.Media),
			"text":  strings.TrimSpace(item.Content),
		}
	}
	return models.MsgTypeText, map[string]interface{}{"text": strings.TrimSpace(item.Content)}
}

func autoMessagePreviewText(item models.ChatAutoMessage) string {
	if item.MessageType == models.MsgTypeImage {
		text := strings.TrimSpace(item.Content)
		if text != "" {
			return text
		}
		return "[图片]"
	}
	return strings.TrimSpace(item.Content)
}

func (s *ChatAutoMessageService) syncChatStateAfterMessage(
	ctx context.Context,
	chat models.Chat,
	msg *models.Message,
	sender models.User,
	memberIDs []uint64,
	targetUserUUIDs []string,
	previewText string,
	mediaURL string,
	duplicate bool,
) {
	if msg == nil {
		return
	}
	s.deleteChatMembersChatListHotCache(ctx, memberIDs...)
	s.broadcastChatState(ctx, chat, memberIDs)
	if duplicate {
		s.broadcastDuplicateMessage(msg, targetUserUUIDs)
		return
	}
	s.pushAutoMessageNotifications(chat, sender, targetUserUUIDs, previewText, msg.MsgID, mediaURL)
}

func (s *ChatAutoMessageService) deleteChatMembersChatListHotCache(ctx context.Context, userIDs ...uint64) {
	if s == nil || s.cache == nil {
		return
	}
	for _, userID := range userIDs {
		if userID == 0 {
			continue
		}
		if err := s.cache.DeleteByPattern(ctx, fmt.Sprintf("chat:list:user:%d:*", userID)); err != nil {
			log.Printf("[AutoMessage] delete chat list cache failed user_id=%d err=%v", userID, err)
		}
	}
}

func (s *ChatAutoMessageService) broadcastChatState(ctx context.Context, chat models.Chat, userIDs []uint64) {
	if s == nil || s.hub == nil || s.db == nil || len(userIDs) == 0 {
		return
	}
	uniqueIDs := uniqueUint64s(userIDs)
	var userChats []models.UserChat
	if err := s.db.WithContext(ctx).
		Where("chat_id = ? AND user_id IN ?", chat.ID, uniqueIDs).
		Find(&userChats).Error; err != nil {
		log.Printf("[AutoMessage] query user chats for state sync failed chat_id=%d err=%v", chat.ID, err)
		return
	}
	uuidByID := s.userUUIDMap(ctx, uniqueIDs)
	for i := range userChats {
		uc := &userChats[i]
		userUUID := uuidByID[uc.UserID]
		if userUUID == "" {
			continue
		}
		s.hub.SendToUser(userUUID, map[string]interface{}{
			"type":          "chat_state_changed",
			"chat_id":       chat.UUID,
			"user_id":       userUUID,
			"last_read_seq": s.currentLastReadSeq(ctx, chat.ID, uc.UserID),
			"changed":       []string{"last_msg_seq", "unread_count"},
			"updated_at":    time.Now().UTC().Format(time.RFC3339Nano),
			"unread_count":  uc.UnreadCount,
			"is_pinned":     uc.IsPinned,
			"is_muted":      uc.IsMuted,
			"last_msg_seq":  uc.LastMsgSeq,
		})
	}
}

func (s *ChatAutoMessageService) broadcastDuplicateMessage(msg *models.Message, targetUserUUIDs []string) {
	if s == nil || s.hub == nil || msg == nil {
		return
	}
	wsPushIDs := append(append([]string{}, targetUserUUIDs...), msg.SenderID)
	s.hub.Broadcast(&ws.BroadcastMessage{
		Type:    "new_message",
		UserIDs: wsPushIDs,
		Data: map[string]interface{}{
			"type":    "new_message",
			"message": msg,
		},
	})
}

func (s *ChatAutoMessageService) pushAutoMessageNotifications(chat models.Chat, sender models.User, targetUserUUIDs []string, previewText string, msgID string, mediaURL string) {
	if s == nil || s.pushService == nil || s.db == nil || len(targetUserUUIDs) == 0 {
		return
	}
	type userIDPair struct {
		ID   uint64
		UUID string
	}
	var pairs []userIDPair
	if err := s.db.Model(&models.User{}).
		Where("uuid IN ?", targetUserUUIDs).
		Select("id, uuid").
		Find(&pairs).Error; err != nil {
		log.Printf("[AutoMessage] query push targets failed chat_id=%d err=%v", chat.ID, err)
		return
	}
	userIDs := make([]uint64, 0, len(pairs))
	for _, p := range pairs {
		userIDs = append(userIDs, p.ID)
	}
	mutedUsers := map[uint64]bool{}
	if len(userIDs) > 0 {
		var mutedUserIDs []uint64
		_ = s.db.Model(&models.UserChat{}).
			Where("chat_id = ? AND user_id IN ? AND is_muted = ?", chat.ID, userIDs, true).
			Pluck("user_id", &mutedUserIDs).Error
		for _, id := range mutedUserIDs {
			mutedUsers[id] = true
		}
	}
	senderName := strings.TrimSpace(sender.Nickname)
	if senderName == "" {
		senderName = strings.TrimSpace(sender.Username)
	}
	if senderName == "" {
		senderName = "定时消息"
	}
	recipients := make([]NewMessagePushRecipient, 0, len(pairs))
	for _, p := range pairs {
		if mutedUsers[p.ID] {
			continue
		}
		if s.hub != nil && s.hub.IsUserOnline(p.UUID) {
			continue
		}
		recipients = append(recipients, NewMessagePushRecipient{UserID: p.ID})
	}
	if len(recipients) > 0 {
		if _, err := s.pushService.PushNewMessageBatch(
			recipients,
			senderName,
			previewText,
			chat.UUID,
			autoMessageChatPushType(chat.Type),
			msgID,
			mediaURL,
		); err != nil {
			log.Printf("[AutoMessage] batch push failed chat_id=%d err=%v", chat.ID, err)
		}
	}
}

func (s *ChatAutoMessageService) currentLastReadSeq(ctx context.Context, chatID uint64, userID uint64) uint64 {
	if s == nil || s.db == nil || chatID == 0 || userID == 0 {
		return 0
	}
	var member models.ChatMember
	if err := s.db.WithContext(ctx).
		Where("chat_id = ? AND user_id = ?", chatID, userID).
		Select("last_read_seq").
		First(&member).Error; err != nil {
		return 0
	}
	return member.LastReadSeq
}

func (s *ChatAutoMessageService) userUUIDMap(ctx context.Context, userIDs []uint64) map[uint64]string {
	result := map[uint64]string{}
	if s == nil || s.db == nil || len(userIDs) == 0 {
		return result
	}
	type row struct {
		ID   uint64
		UUID string
	}
	var rows []row
	if err := s.db.WithContext(ctx).
		Model(&models.User{}).
		Where("id IN ?", userIDs).
		Select("id, uuid").
		Find(&rows).Error; err != nil {
		log.Printf("[AutoMessage] query user uuid map failed err=%v", err)
		return result
	}
	for _, row := range rows {
		result[row.ID] = row.UUID
	}
	return result
}

func uniqueUint64s(values []uint64) []uint64 {
	seen := map[uint64]struct{}{}
	result := make([]uint64, 0, len(values))
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

func autoMessageChatPushType(chatType int8) string {
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

func NextChatAutoMessageRun(item models.ChatAutoMessage, from time.Time) *time.Time {
	switch strings.ToLower(strings.TrimSpace(item.ScheduleType)) {
	case models.ChatAutoMessageScheduleInterval:
		if item.IntervalSeconds <= 0 {
			return nil
		}
		next := from.Add(time.Duration(item.IntervalSeconds) * time.Second)
		return &next
	case models.ChatAutoMessageScheduleDaily:
		hour, minute, ok := parseDailyHHMM(item.DailyTime)
		if !ok {
			return nil
		}
		next := time.Date(from.Year(), from.Month(), from.Day(), hour, minute, 0, 0, from.Location())
		if !next.After(from) {
			next = next.AddDate(0, 0, 1)
		}
		return &next
	default:
		return nil
	}
}

func parseDailyHHMM(value string) (int, int, bool) {
	parts := strings.Split(strings.TrimSpace(value), ":")
	if len(parts) != 2 {
		return 0, 0, false
	}
	hour, okHour := parseSmallInt(parts[0], 0, 23)
	minute, okMinute := parseSmallInt(parts[1], 0, 59)
	return hour, minute, okHour && okMinute
}

func parseSmallInt(value string, min int, max int) (int, bool) {
	n := 0
	if value == "" {
		return 0, false
	}
	for _, ch := range value {
		if ch < '0' || ch > '9' {
			return 0, false
		}
		n = n*10 + int(ch-'0')
	}
	if n < min || n > max {
		return 0, false
	}
	return n, true
}
