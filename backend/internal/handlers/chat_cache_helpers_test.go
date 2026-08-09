package handlers

import (
	"strings"
	"testing"
)

func TestChatListHotCacheKeyIncludesVersion(t *testing.T) {
	oldKey := chatListHotCacheKey(42, 7, 1, 20)
	newKey := chatListHotCacheKey(42, 8, 1, 20)

	if oldKey == newKey {
		t.Fatalf("cache generation must change the key: %q", oldKey)
	}
	if !strings.Contains(newKey, "user:42:version:8") {
		t.Fatalf("unexpected versioned cache key: %q", newKey)
	}
}

func TestChatListHotCacheVersionKeyIsNotADataGlob(t *testing.T) {
	key := chatListHotCacheVersionKey(42)
	if strings.ContainsAny(key, "*?[") {
		t.Fatalf("version key must be an explicit Redis key: %q", key)
	}
}
