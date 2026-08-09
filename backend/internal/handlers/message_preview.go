// 文件用途：实现后端 HTTP 接口的请求处理和统一响应。
// 核心逻辑：绑定参数，校验身份与权限，调用业务服务并持久化关键状态。

package handlers

import (
	"encoding/json"
	"fmt"
	"strings"
	"genericim/internal/models"
	"genericim/internal/services"
	"genericim/internal/textutil"
)

func buildUserChatMessagePreview(msg *models.Message, encrypted bool) string {
	if msg == nil {
		return ""
	}
	if msg.BurnAfterRead {
		return services.BurnAfterReadPreviewText()
	}
	if encrypted {
		return services.EncryptedPreviewText(msg.Type)
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

func normalizeStoredChatPreviewText(text string, msgType int) string {
	trimmed := textutil.RepairLegacyMojibakeText(text)

	switch msgType {
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
		if trimmed != "" && !looksLikeStructuredPayload(trimmed) {
			return textutil.TruncateRunes(trimmed, 100)
		}
		return "[表情]"
	case models.MsgTypeContact:
		return "[联系人名片]"
	case models.MsgTypeCall:
		if trimmed != "" && !looksLikeStructuredPayload(trimmed) {
			return textutil.TruncateRunes(trimmed, 100)
		}
		return "[通话]"
	case models.MsgTypeRedPacket:
		return "[红包]"
	case models.MsgTypeTransfer:
		return "[转账]"
	case models.MsgTypeForwardBundle:
		return "[聊天记录]"
	case models.MsgTypeSystem:
		if trimmed == "" {
			return "[系统消息]"
		}
		return textutil.TruncateRunes(textutil.RepairLegacyMojibakeText(resolveSystemMessagePreviewText(trimmed)), 100)
	default:
		if trimmed == "" {
			return ""
		}
		return textutil.TruncateRunes(trimmed, 100)
	}
}

func buildPinnedMessagePreview(msg *models.Message) string {
	if msg == nil {
		return ""
	}
	if msg.IsRevoked {
		return "消息已撤回"
	}
	if msg.BurnAfterRead {
		return services.BurnAfterReadPreviewText()
	}

	switch msg.Type {
	case models.MsgTypeImage:
		return "[图片]"
	case models.MsgTypeVideo:
		return "[视频]"
	case models.MsgTypeVoice:
		return "[语音]"
	case models.MsgTypeFile:
		if msg.Content.File != nil && strings.TrimSpace(msg.Content.File.Name) != "" {
			return truncatePinnedMessagePreview("[文件] " + strings.TrimSpace(msg.Content.File.Name))
		}
		return "[文件]"
	case models.MsgTypeLocation:
		if msg.Content.Location != nil {
			if title := strings.TrimSpace(msg.Content.Location.Title); title != "" {
				return truncatePinnedMessagePreview("[位置] " + title)
			}
			if address := strings.TrimSpace(msg.Content.Location.Address); address != "" {
				return truncatePinnedMessagePreview("[位置] " + address)
			}
		}
		return "[位置]"
	case models.MsgTypeSticker:
		return "[表情]"
	case models.MsgTypeContact:
		if msg.Content.Contact != nil {
			name := strings.TrimSpace(msg.Content.Contact.Nickname)
			if name == "" {
				name = strings.TrimSpace(msg.Content.Contact.Username)
			}
			if name != "" {
				return truncatePinnedMessagePreview("[名片] " + name)
			}
		}
		return "[名片]"
	case models.MsgTypeCall:
		if text := strings.TrimSpace(msg.Content.Text); text != "" {
			return truncatePinnedMessagePreview(textutil.RepairLegacyMojibakeText(text))
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
			return truncatePinnedMessagePreview(textutil.RepairLegacyMojibakeText(resolveSystemMessagePreviewText(text)))
		}
		return "[系统消息]"
	default:
		if text := strings.TrimSpace(msg.Content.Text); text != "" {
			return truncatePinnedMessagePreview(textutil.RepairLegacyMojibakeText(text))
		}
		return "[消息]"
	}
}

func shouldRefreshPinnedMessagePreview(text string) bool {
	trimmed := strings.TrimSpace(text)
	if trimmed == "" {
		return true
	}
	if looksLikeStructuredPayload(trimmed) {
		return true
	}
	switch trimmed {
	case "[系统消息]", "[消息]":
		return true
	default:
		return false
	}
}

func truncatePinnedMessagePreview(text string) string {
	text = strings.TrimSpace(text)
	runes := []rune(text)
	if len(runes) <= 100 {
		return text
	}
	return string(runes[:100]) + "..."
}

func looksLikeStructuredPayload(text string) bool {
	trimmed := strings.TrimSpace(text)
	if trimmed == "" {
		return false
	}
	if strings.HasPrefix(trimmed, "{") && strings.HasSuffix(trimmed, "}") {
		return true
	}
	return strings.Contains(trimmed, `"type"`) || strings.Contains(trimmed, "red_packet_claimed") || strings.Contains(trimmed, "transfer_accepted")
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
			return fmt.Sprintf("%s（%s）", base, reason)
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
