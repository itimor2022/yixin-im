// 文件用途：验证 stats_handler_test.go 对应模块的正常流程、异常处理和回归行为。
// 核心逻辑：覆盖输入校验、状态变化、错误返回、边界条件和并发幸命。

package handlers

import (
	"testing"
	"time"
)

func TestMessageStatsTypeName(t *testing.T) {
	cases := []struct {
		name string
		raw  interface{}
		want string
	}{
		{name: "text int", raw: 1, want: "text"},
		{name: "image int32", raw: int32(2), want: "image"},
		{name: "video int64", raw: int64(3), want: "video"},
		{name: "voice float64", raw: float64(4), want: "voice"},
		{name: "file string", raw: "5", want: "file"},
		{name: "voice alias", raw: "audio", want: "voice"},
		{name: "unknown int", raw: 99, want: "other"},
		{name: "unknown string", raw: "sticker", want: "other"},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			if got := messageStatsTypeName(tc.raw); got != tc.want {
				t.Fatalf("messageStatsTypeName(%v)=%q want %q", tc.raw, got, tc.want)
			}
		})
	}
}

func TestMapKeysSorted(t *testing.T) {
	got := mapKeys(map[string]struct{}{
		"messages_202606": {},
		"messages":        {},
		"messages_202605": {},
	})
	want := []string{"messages", "messages_202605", "messages_202606"}
	if len(got) != len(want) {
		t.Fatalf("len=%d want=%d", len(got), len(want))
	}
	for i := range want {
		if got[i] != want[i] {
			t.Fatalf("got[%d]=%q want %q", i, got[i], want[i])
		}
	}
}

func TestStartOfLocalDay(t *testing.T) {
	loc := time.FixedZone("UTC+8", 8*60*60)
	got := startOfLocalDay(time.Date(2026, 6, 27, 17, 25, 0, 0, loc))
	want := time.Date(2026, 6, 27, 0, 0, 0, 0, loc)
	if !got.Equal(want) {
		t.Fatalf("startOfLocalDay=%s want %s", got, want)
	}
	if got.Location() != loc {
		t.Fatalf("location=%v want %v", got.Location(), loc)
	}
}
