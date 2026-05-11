package services

import (
	"context"
	"errors"
	"time"

	"gaoranim/internal/models"
	"gaoranim/internal/ws"

	"go.mongodb.org/mongo-driver/bson"
	"go.mongodb.org/mongo-driver/mongo"
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
				"last_msg_text":   previewText,
				"last_msg_sender": targetMsg.SenderName,
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
