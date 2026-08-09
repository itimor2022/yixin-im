// 文件用途：实现可复用的后端业务服务和领域逻辑。
// 核心逻辑：协调数据库、缓存、队列和外部服务，集中处理事务、幂等、重试和错误传播。

package services

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"gorm.io/gorm"
	"strings"
	"genericim/internal/models"
	"genericim/internal/textutil"
)

func buildUserChatPreviewForViewer(msg *models.Message, viewerUserID string) string {
	if msg == nil {
		return ""
	}
	if msg.IsRevoked {
		if strings.TrimSpace(msg.RevokedBy) == strings.TrimSpace(viewerUserID) {
			return "你撤回了一条消息"
		}
		return "有人撤回了一条消息"
	}
	if msg.BurnAfterRead {
		return BurnAfterReadPreviewText()
	}
	if hasEncryptedPayload(msg.E2EE) {
		return EncryptedPreviewText(msg.Type)
	}

	switch msg.Type {
	case models.MsgTypeImage:
		return "[图片]"
	case models.MsgTypeVideo:
		return "[视频]"
	case models.MsgTypeVoice:
		return "[语音]"
	case models.MsgTypeFile:
		return "[文件]"
	case models.MsgTypeLocation:
		return "[位置]"
	case models.MsgTypeSticker:
		return "[表情]"
	case models.MsgTypeContact:
		return "[联系人名片]"
	case models.MsgTypeCall:
		if text := strings.TrimSpace(msg.Content.Text); text != "" {
			return textutil.TruncateRunes(textutil.RepairLegacyMojibakeText(text), 100)
		}
		return "[通话]"
	case models.MsgTypeRedPacket:
		return "[红包]"
	case models.MsgTypeTransfer:
		return "[转账]"
	case models.MsgTypeForwardBundle:
		return "[聊天记录]"
	case models.MsgTypeSystem:
		if text := strings.TrimSpace(msg.Content.Text); text != "" {
			return textutil.TruncateRunes(textutil.RepairLegacyMojibakeText(resolveSystemMessagePreviewText(text)), 100)
		}
		return "[系统消息]"
	default:
		if text := strings.TrimSpace(msg.Content.Text); text != "" {
			return textutil.TruncateRunes(textutil.RepairLegacyMojibakeText(text), 100)
		}
		return "[消息]"
	}
}

func buildUserChatPreviewSender(msg *models.Message) string {
	if msg == nil || msg.IsRevoked || msg.Type == models.MsgTypeSystem {
		return ""
	}
	return textutil.RepairLegacyMojibakeText(msg.SenderName)
}

func MessagePreviewMediaURL(msg *models.Message) string {
	if msg == nil || msg.IsRevoked || msg.BurnAfterRead || hasEncryptedPayload(msg.E2EE) {
		return ""
	}

	switch msg.Type {
	case models.MsgTypeImage, models.MsgTypeVideo:
		if msg.Content.Media == nil {
			return ""
		}
		if thumbnail := strings.TrimSpace(msg.Content.Media.Thumbnail); thumbnail != "" {
			return thumbnail
		}
		return strings.TrimSpace(msg.Content.Media.URL)
	case models.MsgTypeSticker:
		if msg.Content.Sticker == nil {
			return ""
		}
		return strings.TrimSpace(msg.Content.Sticker.URL)
	default:
		return ""
	}
}

func resolveSystemMessagePreviewText(rawText string) string {
	text := strings.TrimSpace(rawText)
	if text == "" {
		return "[系统消息]"
	}

	var data map[string]interface{}
	if err := json.Unmarshal([]byte(text), &data); err != nil {
		return text
	}
	msgType := strings.TrimSpace(stringValue(data["type"]))
	switch msgType {
	case "red_packet_claimed":
		claimerName := defaultString(stringValue(data["claimer_name"]), "对方")
		return fmt.Sprintf("%s 领取了红包", claimerName)
	case "transfer_accepted":
		receiverName := defaultString(stringValue(data["receiver_name"]), "对方")
		return fmt.Sprintf("%s 已收款", receiverName)
	case "contact_added_system_message":
		adderName := defaultString(stringValue(data["adder_name"]), "对方")
		targetName := defaultString(stringValue(data["target_name"]), "对方")
		return fmt.Sprintf("%s刚刚把%s添加到通讯录，现在可以开始聊天了", adderName, targetName)
	case "meeting_started":
		hostName := defaultString(stringValue(data["host_name"]), "对方")
		title := shortenMeetingTitlePreview(stringValue(data["title"]), 18)
		meetingType := "视频群会议"
		if strings.EqualFold(stringValue(data["meeting_type"]), "voice") {
			meetingType = "语音群会议"
		}
		if title != "" {
			return fmt.Sprintf("%s发起了%s：%s", hostName, meetingType, title)
		}
		return fmt.Sprintf("%s发起了%s", hostName, meetingType)
	case "meeting_invite":
		inviterName := defaultString(stringValue(data["inviter_name"]), "对方")
		title := shortenMeetingTitlePreview(stringValue(data["title"]), 18)
		meetingType := "视频群会议"
		if strings.EqualFold(stringValue(data["meeting_type"]), "voice") {
			meetingType = "语音群会议"
		}
		if title != "" {
			return fmt.Sprintf("%s 邀请您加入%s：%s", inviterName, meetingType, title)
		}
		return fmt.Sprintf("%s 邀请您加入%s", inviterName, meetingType)
	case "meeting_ended":
		title := shortenMeetingTitlePreview(stringValue(data["title"]), 18)
		meetingType := "视频群会议"
		if strings.EqualFold(stringValue(data["meeting_type"]), "voice") {
			meetingType = "语音群会议"
		}
		base := meetingType + "已结束"
		if title != "" {
			return base + "：" + title
		}
		reason := strings.TrimSpace(stringValue(data["end_reason"]))
		if reason != "" && reason != "host_end" {
			return fmt.Sprintf("%s：%s", base, reason)
		}
		return base
	case "meeting_title_updated":
		operatorName := defaultString(stringValue(data["operator_name"]), "对方")
		title := shortenMeetingTitlePreview(stringValue(data["title"]), 18)
		if title != "" {
			return fmt.Sprintf("%s 更新了群会议名称：%s", operatorName, title)
		}
		return fmt.Sprintf("%s 更新了群会议名称", operatorName)
	}
	if fallback := strings.TrimSpace(stringValue(data["text"])); fallback != "" {
		return textutil.RepairLegacyMojibakeText(fallback)
	}
	if fallback := strings.TrimSpace(stringValue(data["content"])); fallback != "" {
		return textutil.RepairLegacyMojibakeText(fallback)
	}
	return textutil.RepairLegacyMojibakeText(text)
}

func shortenMeetingTitlePreview(text string, maxLen int) string {
	value := strings.TrimSpace(text)
	runes := []rune(value)
	if value == "" || len(runes) <= maxLen {
		return value
	}
	return string(runes[:maxLen]) + "..."
}

func stringValue(value interface{}) string {
	switch v := value.(type) {
	case string:
		return v
	case fmt.Stringer:
		return v.String()
	default:
		return fmt.Sprintf("%v", value)
	}
}

func defaultString(value string, fallback string) string {
	if strings.TrimSpace(value) == "" || value == "<nil>" {
		return fallback
	}
	return value
}

func (s *MessageService) refreshUserChatPreviewAfterBurn(ctx context.Context, chatUUID, userUUID string, maxBurnSeq uint64) error {
	if strings.TrimSpace(chatUUID) == "" || strings.TrimSpace(userUUID) == "" || maxBurnSeq == 0 {
		return nil
	}

	var chat struct {
		ID uint64
	}
	if err := s.db.Table("chats").Where("uuid = ?", chatUUID).Select("id").Take(&chat).Error; err != nil {
		if errors.Is(err, gorm.ErrRecordNotFound) {
			return nil
		}
		return err
	}

	var user struct {
		ID uint64
	}
	if err := s.db.Table("users").Where("uuid = ?", userUUID).Select("id").Take(&user).Error; err != nil {
		if errors.Is(err, gorm.ErrRecordNotFound) {
			return nil
		}
		return err
	}

	var userChat models.UserChat
	if err := s.db.Where("chat_id = ? AND user_id = ?", chat.ID, user.ID).Take(&userChat).Error; err != nil {
		if errors.Is(err, gorm.ErrRecordNotFound) {
			return nil
		}
		return err
	}
	if userChat.LastMsgSeq == 0 || userChat.LastMsgSeq > maxBurnSeq {
		return nil
	}

	messages, err := s.getMessagesBySeq(ctx, chatUUID, userUUID, userChat.LastMsgSeq+1, 1, nil)
	if err != nil {
		return err
	}
	updates := map[string]interface{}{}
	if len(messages) == 0 || messages[0] == nil {
		if userChat.LastMsgSeq == 0 &&
			userChat.LastMsgType == 0 &&
			strings.TrimSpace(userChat.LastMsgText) == "" &&
			strings.TrimSpace(userChat.LastMsgSender) == "" {
			return nil
		}

		updates["last_msg_text"] = ""
		updates["last_msg_type"] = 0
		updates["last_msg_seq"] = 0
		updates["last_msg_sender"] = ""
		updates["last_msg_media_url"] = ""
	} else {
		latest := messages[0]
		previewText := buildUserChatPreviewForViewer(latest, userUUID)
		previewSender := buildUserChatPreviewSender(latest)
		previewMediaURL := MessagePreviewMediaURL(latest)
		if latest.Seq == userChat.LastMsgSeq &&
			latest.Type == userChat.LastMsgType &&
			previewText == userChat.LastMsgText &&
			previewSender == userChat.LastMsgSender &&
			previewMediaURL == userChat.LastMsgMediaURL {
			return nil
		}

		updates["last_msg_text"] = previewText
		updates["last_msg_type"] = latest.Type
		updates["last_msg_seq"] = latest.Seq
		updates["last_msg_sender"] = previewSender
		updates["last_msg_media_url"] = previewMediaURL
	}
	return s.db.Model(&models.UserChat{}).
		Where("chat_id = ? AND user_id = ? AND last_msg_seq <= ?", chat.ID, user.ID, maxBurnSeq).
		Updates(updates).Error
}
