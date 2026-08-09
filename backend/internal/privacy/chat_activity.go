// 文件用途：根据用户隐私设置计算在线和活跃状态的可见性。
// 核心逻辑：将单用户或批量查询结果转换为对外可见状态。

package privacy

import (
	"errors"
	"gorm.io/gorm"
	"strings"
	"genericim/internal/models"
)

type chatActivityKind uint8

const (
	chatActivityReadReceipt chatActivityKind = iota
	chatActivityTyping
)

func CanUserBroadcastReadReceipt(db *gorm.DB, userUUID, chatUUID string) (bool, error) {
	return canUserBroadcastChatActivity(db, userUUID, chatUUID, chatActivityReadReceipt)
}

func CanUserBroadcastTyping(db *gorm.DB, userUUID, chatUUID string) (bool, error) {
	return canUserBroadcastChatActivity(db, userUUID, chatUUID, chatActivityTyping)
}

func canBroadcastChatActivityForType(kind chatActivityKind, chatType int8) bool {
	// Group/channel read state is derived from chat_members.last_read_seq.
	// Broadcasting every reader to every online member creates O(N²) traffic.
	// Typing remains a transient group activity and is intentionally unchanged.
	return kind != chatActivityReadReceipt || chatType == 1
}

func canUserBroadcastChatActivity(db *gorm.DB, userUUID, chatUUID string, kind chatActivityKind) (bool, error) {
	userUUID = strings.TrimSpace(userUUID)
	chatUUID = strings.TrimSpace(chatUUID)
	if db == nil || userUUID == "" || chatUUID == "" {
		return false, nil
	}

	var user models.User
	if err := db.Select("id").Where("uuid = ?", userUUID).Take(&user).Error; err != nil {
		return false, err
	}
	enabled := true
	var setting models.UserPrivacySetting

	err := db.Select("send_read_receipts", "show_typing_status").
		Where("user_id = ?", user.ID).
		Take(&setting).Error
	if err == nil {
		switch kind {
		case chatActivityTyping:
			enabled = setting.ShowTypingStatus
		default:
			enabled = setting.SendReadReceipts
		}
	} else if !errors.Is(err, gorm.ErrRecordNotFound) {
		return false, err
	}
	if !enabled {
		return false, nil
	}

	var chat models.Chat
	if err := db.Select("id", "type").Where("uuid = ?", chatUUID).Take(&chat).Error; err != nil {
		return false, err
	}
	if !canBroadcastChatActivityForType(kind, chat.Type) {
		return false, nil
	}
	if chat.Type != 1 {

		return true, nil
	}

	var peerIDs []uint64
	if err := db.Model(&models.ChatMember{}).
		Where("chat_id = ? AND user_id != ?", chat.ID, user.ID).
		Pluck("user_id", &peerIDs).Error; err != nil {
		return false, err
	}
	if len(peerIDs) == 0 {
		return false, nil
	}

	var blockCount int64

	if err := db.Model(&models.UserBlock{}).
		Where(
			"(user_id = ? AND blocked_user_id IN ?) OR(blocked_user_id = ? AND user_id IN ?)",
			user.ID,
			peerIDs,
			user.ID,
			peerIDs,
		).
		Count(&blockCount).Error; err != nil {
		return false, err
	}
	return blockCount == 0, nil
}
