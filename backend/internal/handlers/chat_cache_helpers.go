// 文件用途：实现后端 HTTP 接口的请求处理和统一响应。
// 核心逻辑：绑定参数，校验身份与权限，调用业务服务并持久化关键状态。

package handlers

import (
	"context"
	"fmt"
	"gorm.io/gorm"
	"log"
	"time"
	"genericim/internal/cache"
	"genericim/internal/models"
)

const chatListHotCacheTTL = 8 * time.Second

func chatListHotCacheVersionKey(userID uint64) string {
	return fmt.Sprintf("chat:list:user:%d:version", userID)
}

func chatListHotCacheVersion(ctx context.Context, c *cache.Cache, userID uint64) uint64 {
	if c == nil || userID == 0 {
		return 0
	}
	version, err := c.GetUint64(ctx, chatListHotCacheVersionKey(userID))
	if err != nil {
		return 0
	}
	return version
}

func chatListHotCacheKey(userID uint64, version uint64, page, pageSize int) string {
	return fmt.Sprintf("chat:list:user:%d:version:%d:page:%d:size:%d", userID, version, page, pageSize)
}

func deleteUserChatListHotCache(ctx context.Context, c *cache.Cache, userIDs ...uint64) {
	if err := bumpUserChatListHotCacheVersions(ctx, c, userIDs...); err != nil {
		log.Printf("[ChatCache] bump user chat-list versions failed users=%d err=%v", len(userIDs), err)
	}
}

func bumpUserChatListHotCacheVersions(ctx context.Context, c *cache.Cache, userIDs ...uint64) error {
	if c == nil {
		return nil
	}
	seen := make(map[uint64]struct{}, len(userIDs))
	versionKeys := make([]string, 0, len(userIDs))
	for _, userID := range userIDs {
		if userID == 0 {
			continue
		}
		if _, ok := seen[userID]; ok {
			continue
		}
		seen[userID] = struct{}{}
		versionKeys = append(versionKeys, chatListHotCacheVersionKey(userID))
	}
	if len(versionKeys) == 0 {
		return nil
	}
	return c.IncrementMany(ctx, versionKeys...)
}

func deleteChatMembersChatListHotCache(ctx context.Context, c *cache.Cache, db *gorm.DB, chatID uint64) {
	if c == nil || db == nil || chatID == 0 {
		return
	}
	var userIDs []uint64
	if err := db.Model(&models.ChatMember{}).
		Where("chat_id = ?", chatID).
		Pluck("user_id", &userIDs).Error; err != nil {
		log.Printf("[ChatCache] query chat member ids failed chatID=%d err=%v", chatID, err)
		return
	}
	deleteUserChatListHotCache(ctx, c, userIDs...)
}
