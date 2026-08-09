// 文件用途：实现可复用的后端业务服务和领域逻辑。
// 核心逻辑：协调数据库、缓存、队列和外部服务，集中处理事务、幂等、重试和错误传播。

package services

import "genericim/internal/models"

func hasEncryptedPayload(payload *models.EncryptedMessagePayload) bool {
	return payload != nil && payload.Ciphertext != "" && len(payload.Envelopes) > 0
}

func EncryptedPreviewText(msgType int) string {
	switch msgType {
	case models.MsgTypeImage:
		return "[加密图片]"
	case models.MsgTypeVideo:
		return "[加密视频]"
	case models.MsgTypeVoice:
		return "[加密语音]"
	case models.MsgTypeFile:
		return "[加密文件]"
	case models.MsgTypeLocation:
		return "[加密位置]"
	case models.MsgTypeContact:
		return "[加密名片]"
	default:
		return "[加密消息]"
	}
}

func EncryptedPushPreviewText() string {
	return "您收到一条加密消息"
}

func BurnAfterReadPreviewText() string {
	return "[阅后即焚消息]"
}
