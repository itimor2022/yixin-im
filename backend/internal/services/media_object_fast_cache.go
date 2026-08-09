// 文件用途：缓存本进程刚完成上传的媒体规范元数据，减少图片消息 ACK 路径中的 MySQL 回读。
// 核心逻辑：上传完成时保存可信的服务端字段；发送时仍以条件 UPDATE 原子校验所有权、类型、状态和有效期，命中后直接规范化消息内容。

package services

import (
	"sync"
	"time"

	"genericim/internal/models"
)

const (
	messageMediaFastCacheTTL = 15 * time.Minute
	messageMediaFastCacheMax = 20000
)

type messageMediaFastCacheEntry struct {
	item      models.MediaObject
	expiresAt time.Time
}

var messageMediaFastCache = struct {
	sync.RWMutex
	items map[string]messageMediaFastCacheEntry
}{
	items: make(map[string]messageMediaFastCacheEntry),
}

// RememberUploadedMessageMedia records only server-produced metadata. The
// database conditional UPDATE remains the authority for whether the object may
// be bound, so a stale cache entry cannot bypass ownership or lifecycle rules.
func RememberUploadedMessageMedia(item *models.MediaObject, url, checksum string) {
	if item == nil || item.MediaID == "" || item.UserID == 0 {
		return
	}
	cached := *item
	cached.URL = url
	cached.ChecksumSHA256 = checksum
	cached.Status = models.MediaObjectStatusUploaded

	now := time.Now()
	messageMediaFastCache.Lock()
	if len(messageMediaFastCache.items) >= messageMediaFastCacheMax {
		for mediaID, entry := range messageMediaFastCache.items {
			if now.After(entry.expiresAt) {
				delete(messageMediaFastCache.items, mediaID)
			}
		}
	}
	if len(messageMediaFastCache.items) >= messageMediaFastCacheMax {
		for mediaID := range messageMediaFastCache.items {
			delete(messageMediaFastCache.items, mediaID)
			break
		}
	}
	messageMediaFastCache.items[cached.MediaID] = messageMediaFastCacheEntry{
		item:      cached,
		expiresAt: now.Add(messageMediaFastCacheTTL),
	}
	messageMediaFastCache.Unlock()
}

func uploadedMessageMediaFromFastCache(mediaID string) (models.MediaObject, bool) {
	now := time.Now()
	messageMediaFastCache.RLock()
	entry, ok := messageMediaFastCache.items[mediaID]
	messageMediaFastCache.RUnlock()
	if !ok {
		return models.MediaObject{}, false
	}
	if now.After(entry.expiresAt) {
		forgetUploadedMessageMedia(mediaID)
		return models.MediaObject{}, false
	}
	return entry.item, true
}

func forgetUploadedMessageMedia(mediaID string) {
	messageMediaFastCache.Lock()
	delete(messageMediaFastCache.items, mediaID)
	messageMediaFastCache.Unlock()
}
