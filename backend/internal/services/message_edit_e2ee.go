// 文件用途：实现可复用的后端业务服务和领域逻辑。
// 核心逻辑：协调数据库、缓存、队列和外部服务，集中处理事务、幂等、重试和错误传播。

package services

import (
	"context"
	"errors"
	"go.mongodb.org/mongo-driver/bson"
	"go.mongodb.org/mongo-driver/mongo"
	"net/url"
	"path"
	"strings"
	"time"
	"genericim/internal/config"
	"genericim/internal/models"
	"genericim/internal/ws"
)

// EditMessageWithE2EE edits a text message and supports encrypted payload updates.
func (s *MessageService) EditMessageWithE2EE(
	ctx context.Context,
	chatID string,
	msgID string,
	userID string,
	newContent string,
	e2ee *models.EncryptedMessagePayload,
) error {
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
	if targetMsg.SenderID != userID {
		return errors.New("无权编辑他人消息")
	}
	if targetMsg.IsRevoked {
		return errors.New("消息已撤回，不能编辑")
	}
	if targetMsg.BurnAfterRead {
		return errors.New("无权编辑他人消息")
	}
	if targetMsg.Type != models.MsgTypeText {
		return errors.New("只能编辑文本消息")
	}
	editedAt := time.Now()
	updateSet := bson.M{
		"is_edited":  true,
		"edited_at":  editedAt,
		"updated_at": editedAt,
	}
	previewText := newContent

	if hasEncryptedPayload(e2ee) {
		updateSet["content"] = models.MessageContent{}
		updateSet["e2ee"] = e2ee
		updateSet["reply_to"] = nil
		updateSet["mentions"] = []string{}
		targetMsg.Content = models.MessageContent{}
		targetMsg.E2EE = e2ee
		targetMsg.ReplyTo = nil
		targetMsg.Mentions = nil
		previewText = EncryptedPreviewText(targetMsg.Type)
	} else {
		updateSet["content.text"] = newContent
		updateSet["e2ee"] = nil
		targetMsg.Content.Text = newContent
		targetMsg.E2EE = nil
	}
	if targetMsg.BurnAfterRead {
		previewText = BurnAfterReadPreviewText()
	}
	if _, err := targetCollection.UpdateOne(
		ctx,
		bson.M{"chat_id": chatID, "msg_id": msgID},
		bson.M{"$set": updateSet},
	); err != nil {
		return err
	}
	targetMsg.IsEdited = true
	targetMsg.EditedAt = &editedAt
	targetMsg.UpdatedAt = editedAt

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

	var dbChat struct {
		ID uint64
	}
	if err := s.db.Table("chats").
		Where("uuid = ?", chatID).
		Select("id").
		Scan(&dbChat).Error; err == nil && dbChat.ID > 0 {
		s.db.Table("user_chats").
			Where("chat_id = ? AND last_msg_type = 1 AND last_msg_seq = ?", dbChat.ID, targetMsg.Seq).
			Updates(map[string]interface{}{
				"last_msg_text":      previewText,
				"last_msg_sender":    targetMsg.SenderName,
				"last_msg_media_url": "",
			})
	}
	if memberUUIDs := s.getChatMemberUUIDs(chatID); len(memberUUIDs) > 0 {
		s.hub.Broadcast(&ws.BroadcastMessage{
			Type:    "message_edited",
			UserIDs: memberUUIDs,
			Data:    editPayload,
		})
	} else {
		s.hub.SendToChat(chatID, editPayload, "")
	}
	return nil
}

// EditImageMessageMedia replaces the media payload of an image message.
func (s *MessageService) EditImageMessageMedia(
	ctx context.Context,
	chatID string,
	msgID string,
	userID string,
	media *models.MediaInfo,
) error {
	if err := s.validateEditableImageMedia(media); err != nil {
		return err
	}
	if media == nil || media.URL == "" {
		return errors.New("图片地址不能为空")
	}
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
	if targetMsg.SenderID != userID {
		return errors.New("无权编辑他人消息")
	}
	if targetMsg.IsRevoked {
		return errors.New("消息已撤回，不能编辑")
	}
	if targetMsg.BurnAfterRead {
		return errors.New("阅后即焚消息不能编辑")
	}
	if targetMsg.Type != models.MsgTypeImage {
		return errors.New("只能替换图片消息")
	}
	editedAt := time.Now()
	updateSet := bson.M{
		"content.media": media,
		"content.text":  "",
		"is_edited":     true,
		"edited_at":     editedAt,
		"updated_at":    editedAt,
	}
	if _, err := targetCollection.UpdateOne(
		ctx,
		bson.M{"chat_id": chatID, "msg_id": msgID},
		bson.M{"$set": updateSet},
	); err != nil {
		return err
	}
	targetMsg.Content.Media = media
	targetMsg.Content.Text = ""
	targetMsg.IsEdited = true
	targetMsg.EditedAt = &editedAt
	targetMsg.UpdatedAt = editedAt

	previewText := "[图片]"
	if targetMsg.BurnAfterRead {
		previewText = BurnAfterReadPreviewText()
	}
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

	var dbChat struct {
		ID uint64
	}
	if err := s.db.Table("chats").
		Where("uuid = ?", chatID).
		Select("id").
		Scan(&dbChat).Error; err == nil && dbChat.ID > 0 {
		s.db.Table("user_chats").
			Where("chat_id = ? AND last_msg_type = 2 AND last_msg_seq = ?", dbChat.ID, targetMsg.Seq).
			Updates(map[string]interface{}{
				"last_msg_text":      previewText,
				"last_msg_sender":    targetMsg.SenderName,
				"last_msg_media_url": media.URL,
			})
	}
	if memberUUIDs := s.getChatMemberUUIDs(chatID); len(memberUUIDs) > 0 {
		s.hub.Broadcast(&ws.BroadcastMessage{
			Type:    "message_edited",
			UserIDs: memberUUIDs,
			Data:    editPayload,
		})
	} else {
		s.hub.SendToChat(chatID, editPayload, "")
	}
	return nil
}

func (s *MessageService) validateEditableImageMedia(media *models.MediaInfo) error {
	if media == nil {
		return errors.New("图片地址不能为空")
	}
	rawURL := strings.TrimSpace(media.URL)
	if rawURL == "" {
		return errors.New("图片地址不能为空")
	}
	mimeType := strings.ToLower(strings.TrimSpace(media.MimeType))
	if mimeType != "" && !strings.HasPrefix(mimeType, "image/") {
		return errors.New("只能使用图片媒体")
	}
	if u, err := url.Parse(rawURL); err == nil && u.IsAbs() {
		storageCfg := LoadStorageForRuntime(s.db, config.GlobalConfig.Storage)
		if key, ok := ObjectKeyFromPublicURL(storageCfg, rawURL); ok {
			if cleanUploadedImagePath(key) {
				return nil
			}
			return errors.New("图片地址必须来自图片上传目录")
		}
		if !editableMediaURLHostAllowed(u, storageCfg) {
			return errors.New("图片地址必须来自站内上传")
		}
		if cleanUploadedImagePath(u.Path) {
			return nil
		}
		return errors.New("图片地址必须来自图片上传目录")
	}
	if cleanUploadedImagePath(rawURL) {
		return nil
	}
	return errors.New("图片地址必须来自站内上传")
}

func cleanUploadedImagePath(rawPath string) bool {
	value := strings.TrimSpace(strings.ReplaceAll(rawPath, "\\", "/"))
	if value == "" {
		return false
	}
	value = strings.TrimPrefix(value, "/")
	if strings.HasPrefix(value, "uploads/") {
		value = strings.TrimPrefix(value, "uploads/")
	}
	cleaned := path.Clean(value)
	return cleaned != "." &&
		cleaned == value &&
		strings.HasPrefix(cleaned, "images/") &&
		!strings.Contains(cleaned, "../")
}

func editableMediaURLHostAllowed(u *url.URL, storageCfg config.StorageConfig) bool {
	host := strings.ToLower(strings.TrimSpace(u.Host))
	if host == "" {
		return false
	}
	for _, base := range []string{
		config.GlobalConfig.Server.BaseURL,
		storageCfg.Local.BaseURL,
		storageCfg.Aliyun.PublicBaseURL,
		storageCfg.Qiniu.PublicBaseURL,
	} {
		if editableMediaBaseHost(base, storageCfg) == host {
			return true
		}
	}
	return false
}

func editableMediaBaseHost(base string, storageCfg config.StorageConfig) string {
	base = strings.TrimSpace(base)
	if base == "" {
		return ""
	}
	if !strings.HasPrefix(base, "http://") && !strings.HasPrefix(base, "https://") {
		if storageCfg.Aliyun.UseHTTPS || storageCfg.Qiniu.UseHTTPS {
			base = "https://" + base
		} else {
			base = "http://" + base
		}
	}
	u, err := url.Parse(base)
	if err != nil {
		return ""
	}
	return strings.ToLower(strings.TrimSpace(u.Host))
}
