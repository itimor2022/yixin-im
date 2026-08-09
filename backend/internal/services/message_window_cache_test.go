package services

import (
	"strings"
	"testing"
)

func TestMessageWindowCacheKeyIncludesVersion(t *testing.T) {
	oldKey := messageWindowCacheKey("chat-1", "user-1", 10, 100, 50)
	newKey := messageWindowCacheKey("chat-1", "user-1", 11, 100, 50)

	if oldKey == newKey {
		t.Fatalf("cache generation must change the key: %q", oldKey)
	}
	if !strings.Contains(newKey, "chat-1:version:11") {
		t.Fatalf("unexpected versioned cache key: %q", newKey)
	}
}

func TestMessageWindowCacheVersionKeyIsNotADataGlob(t *testing.T) {
	key := messageWindowCacheVersionKey("chat-1")
	if strings.ContainsAny(key, "*?[") {
		t.Fatalf("version key must be an explicit Redis key: %q", key)
	}
}
