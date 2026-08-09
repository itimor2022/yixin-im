// 文件用途：验证上传媒体快速缓存的命中、消费和容量边界行为。
// 核心逻辑：缓存只保存服务端规范字段，消费后删除，避免被第二条消息复用。

package services

import (
	"fmt"
	"testing"

	"genericim/internal/models"
)

func TestUploadedMessageMediaFastCacheStoresCanonicalMetadata(t *testing.T) {
	item := &models.MediaObject{
		MediaID:   "fast-cache-test",
		UserID:    42,
		Category:  "image",
		ObjectKey: "uploads/images/fast-cache-test.png",
	}
	t.Cleanup(func() { forgetUploadedMessageMedia(item.MediaID) })

	RememberUploadedMessageMedia(item, "https://cdn.example/fast-cache-test.png", "checksum")
	got, ok := uploadedMessageMediaFromFastCache(item.MediaID)
	if !ok {
		t.Fatal("expected uploaded media cache hit")
	}
	if got.UserID != item.UserID || got.URL != "https://cdn.example/fast-cache-test.png" ||
		got.ChecksumSHA256 != "checksum" || got.Status != models.MediaObjectStatusUploaded {
		t.Fatalf("unexpected cached media: %#v", got)
	}

	forgetUploadedMessageMedia(item.MediaID)
	if _, ok := uploadedMessageMediaFromFastCache(item.MediaID); ok {
		t.Fatal("consumed uploaded media remained in cache")
	}
}

func TestUploadedMessageMediaFastCacheRemainsBounded(t *testing.T) {
	messageMediaFastCache.Lock()
	original := messageMediaFastCache.items
	messageMediaFastCache.items = make(map[string]messageMediaFastCacheEntry)
	messageMediaFastCache.Unlock()
	t.Cleanup(func() {
		messageMediaFastCache.Lock()
		messageMediaFastCache.items = original
		messageMediaFastCache.Unlock()
	})

	for i := 0; i < messageMediaFastCacheMax+25; i++ {
		RememberUploadedMessageMedia(&models.MediaObject{
			MediaID:  fmt.Sprintf("bounded-%d", i),
			UserID:   1,
			Category: "image",
		}, "https://cdn.example/image.png", "")
	}
	messageMediaFastCache.RLock()
	got := len(messageMediaFastCache.items)
	messageMediaFastCache.RUnlock()
	if got > messageMediaFastCacheMax {
		t.Fatalf("cache size = %d, want <= %d", got, messageMediaFastCacheMax)
	}
}
