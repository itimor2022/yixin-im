package handlers

import (
	"fmt"
	"reflect"
	"strings"
	"testing"
	"time"
)

func TestSanitizeStringList_DedupeTrimClampAndLimit(t *testing.T) {
	input := []string{
		"  alpha  ",
		"beta",
		"alpha",
		"",
		"  ",
		"gamma",
		"delta",
	}

	out := sanitizeStringList(input, 3, 5, nil)
	if len(out) != 3 {
		t.Fatalf("expected 3 items, got %d (%v)", len(out), out)
	}

	want := []string{"alpha", "beta", "gamma"}
	for i := range want {
		if out[i] != want[i] {
			t.Fatalf("index %d expected %q got %q", i, want[i], out[i])
		}
	}
}

func TestSanitizeStringList_AllowFilter(t *testing.T) {
	input := []string{"emoji:😀", "custom:1", "invalid:abc", "emoji:😀"}
	out := sanitizeStringList(input, 10, 64, func(v string) bool {
		return strings.HasPrefix(v, "emoji:") || strings.HasPrefix(v, "custom:")
	})

	want := []string{"emoji:😀", "custom:1"}
	if len(out) != len(want) {
		t.Fatalf("expected %d items, got %d (%v)", len(want), len(out), out)
	}
	for i := range want {
		if out[i] != want[i] {
			t.Fatalf("index %d expected %q got %q", i, want[i], out[i])
		}
	}
}

func TestSanitizeCustomEmojiList_FiltersAndNormalizes(t *testing.T) {
	input := []map[string]interface{}{
		{
			"id":         "  one  ",
			"path":       " /uploads/images/a.png ",
			"created_at": "2026-04-21T10:30:00+08:00",
		},
		{
			"id":         "one",
			"path":       "/tmp/dup.png",
			"created_at": "2026-04-21T11:00:00+08:00",
		},
		{
			"id":         "two",
			"path":       "",
			"remote_url": "https://cdn.example.com/e2.png",
			"created_at": "invalid-time",
		},
		{
			"id":         "three",
			"path":       "",
			"remote_url": "ftp://bad.example.com/e3.png",
			"created_at": "2026-04-21T10:30:00Z",
		},
		{
			"id":   "",
			"path": "/tmp/empty-id.png",
		},
	}

	out := sanitizeCustomEmojiList(input)
	if len(out) != 2 {
		t.Fatalf("expected 2 items, got %d (%v)", len(out), out)
	}

	first := out[0]
	if first["id"] != "one" {
		t.Fatalf("first id expected one, got %v", first["id"])
	}
	if first["path"] != "/uploads/images/a.png" {
		t.Fatalf("first path expected /uploads/images/a.png, got %v", first["path"])
	}
	if _, ok := first["created_at"].(string); !ok {
		t.Fatalf("first created_at should be string, got %T", first["created_at"])
	}

	second := out[1]
	if second["id"] != "two" {
		t.Fatalf("second id expected two, got %v", second["id"])
	}
	if second["remote_url"] != "https://cdn.example.com/e2.png" {
		t.Fatalf("second remote_url mismatch, got %v", second["remote_url"])
	}
	if _, ok := second["created_at"].(string); !ok {
		t.Fatalf("second created_at should be string, got %T", second["created_at"])
	}
}

func TestSanitizeCustomEmojiList_HardLimit(t *testing.T) {
	input := make([]map[string]interface{}, 0, emojiStoreMaxCustomEmojis+50)
	for i := 0; i < emojiStoreMaxCustomEmojis+50; i++ {
		input = append(input, map[string]interface{}{
			"id":         fmt.Sprintf("emoji_%d", i),
			"path":       "/uploads/images/e.png",
			"created_at": "2026-04-21T10:30:00Z",
		})
	}

	out := sanitizeCustomEmojiList(input)
	if len(out) != emojiStoreMaxCustomEmojis {
		t.Fatalf("expected %d items, got %d", emojiStoreMaxCustomEmojis, len(out))
	}
}

func TestTrimAndClampRunes_UTF8(t *testing.T) {
	raw := "  你好世界abc  "
	out := trimAndClampRunes(raw, 4)
	if out != "你好世界" {
		t.Fatalf("expected %q, got %q", "你好世界", out)
	}
}

func TestNormalizeTimeString(t *testing.T) {
	valid := normalizeTimeString("2026-04-21T10:30:00+08:00")
	if valid != "2026-04-21T02:30:00Z" {
		t.Fatalf("unexpected normalized time: %s", valid)
	}

	invalid := normalizeTimeString("not-a-time")
	if invalid == "" {
		t.Fatalf("invalid time should fallback to current RFC3339 time")
	}
}

func TestInterfaceSliceConverters(t *testing.T) {
	mixed := []interface{}{
		"one",
		2,
		"two",
		map[string]interface{}{"id": "a"},
		map[string]interface{}{"id": "b"},
	}

	ss := interfaceSliceToStringSlice(mixed)
	if len(ss) != 2 || ss[0] != "one" || ss[1] != "two" {
		t.Fatalf("unexpected string conversion result: %v", ss)
	}

	ms := interfaceSliceToMapSlice(mixed)
	if len(ms) != 2 {
		t.Fatalf("unexpected map conversion length: %d", len(ms))
	}
	if ms[0]["id"] != "a" || ms[1]["id"] != "b" {
		t.Fatalf("unexpected map conversion result: %v", ms)
	}
}

func TestParseRFC3339Time(t *testing.T) {
	tm, ok := parseRFC3339Time("2026-04-21T10:30:00+08:00")
	if !ok {
		t.Fatalf("expected parse success")
	}
	if got := tm.Format(time.RFC3339); got != "2026-04-21T02:30:00Z" {
		t.Fatalf("unexpected normalized time: %s", got)
	}

	if _, ok := parseRFC3339Time("bad-time-value"); ok {
		t.Fatalf("expected parse failure for invalid value")
	}
}

func TestFilterInstalledPackIDsByActiveCatalog(t *testing.T) {
	installed := []string{"animated_faces", "unknown_pack", "animated_animals"}
	active := map[string]struct{}{
		"animated_faces":   {},
		"animated_animals": {},
	}
	got := filterInstalledPackIDsByActiveCatalog(installed, active)
	want := []string{"animated_faces", "animated_animals"}
	if !reflect.DeepEqual(got, want) {
		t.Fatalf("unexpected installed filter result: want=%v got=%v", want, got)
	}
}

func TestFilterFavoriteCodesWithCustomEmojis(t *testing.T) {
	favorites := []string{
		"emoji:😀",
		"custom:c1",
		"custom:missing",
		"bad:xx",
	}
	custom := []map[string]interface{}{
		{"id": "c1", "path": "/tmp/c1.png"},
		{"id": "c2", "path": "/tmp/c2.png"},
	}
	got := filterFavoriteCodesWithCustomEmojis(favorites, custom)
	want := []string{"emoji:😀", "custom:c1"}
	if !reflect.DeepEqual(got, want) {
		t.Fatalf("unexpected favorites filter result: want=%v got=%v", want, got)
	}
}

func TestIsUploadRelativePath(t *testing.T) {
	if !isUploadRelativePath("/uploads/images/a.png") {
		t.Fatalf("expected true for /uploads path")
	}
	if !isUploadRelativePath("uploads/images/a.png") {
		t.Fatalf("expected true for uploads path")
	}
	if isUploadRelativePath("/tmp/a.png") {
		t.Fatalf("expected false for local temp path")
	}
}
