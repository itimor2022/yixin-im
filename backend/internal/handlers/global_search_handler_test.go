// 文件用途：验证 global_search_handler_test.go 对应模块的正常流程、异常处理和回归行为。
// 核心逻辑：覆盖输入校验、状态变化、错误返回、边界条件和并发幸命。

package handlers

import (
	"github.com/gin-gonic/gin"
	"testing"
)

func TestParseSearchLimit(t *testing.T) {
	if got := parseSearchLimit("0", 1, 20, 8); got != 1 {
		t.Fatalf("min clamp=%d", got)
	}
	if got := parseSearchLimit("50", 1, 20, 8); got != 20 {
		t.Fatalf("max clamp=%d", got)
	}
	if got := parseSearchLimit("bad", 1, 20, 8); got != 8 {
		t.Fatalf("fallback=%d", got)
	}
}

func TestParseSearchPage(t *testing.T) {
	if got := parseSearchPage("0"); got != 1 {
		t.Fatalf("min page=%d", got)
	}
	if got := parseSearchPage("bad"); got != 1 {
		t.Fatalf("fallback page=%d", got)
	}
	if got := parseSearchPage("99"); got != 50 {
		t.Fatalf("max page=%d", got)
	}
}

func TestSliceSearchItems(t *testing.T) {
	items := []gin.H{{"id": "1"}, {"id": "2"}, {"id": "3"}}
	got, hasMore := sliceSearchItems(items, 0, 2)
	if len(got) != 2 || !hasMore {
		t.Fatalf("page1 len=%d hasMore=%v", len(got), hasMore)
	}
	got, hasMore = sliceSearchItems(items, 2, 2)
	if len(got) != 1 || hasMore {
		t.Fatalf("page2 len=%d hasMore=%v", len(got), hasMore)
	}
}

func TestHighlightSnippet(t *testing.T) {
	got := highlightSnippet("hello product search world", "product")
	if got["text"] != "hello product search world" {
		t.Fatalf("text=%v", got["text"])
	}
	if got["start"] != 6 || got["end"] != 13 {
		t.Fatalf("range=%v-%v", got["start"], got["end"])
	}
}

func TestHighlightBestSnippet(t *testing.T) {
	got := highlightBestSnippet("needle", "", "first value", "second needle value")
	if got["text"] != "second needle value" {
		t.Fatalf("text=%v", got["text"])
	}
	if got["start"] != 7 || got["end"] != 13 {
		t.Fatalf("range=%v-%v", got["start"], got["end"])
	}
	fallback := highlightBestSnippet("missing", "", "first value")
	if fallback["text"] != "first value" || fallback["start"] != -1 {
		t.Fatalf("fallback=%v", fallback)
	}
}

func TestChatTypeName(t *testing.T) {
	cases := map[int8]string{
		1: "private",
		2: "group",
		3: "channel",
		9: "chat",
	}
	for input, want := range cases {
		if got := chatTypeName(input); got != want {
			t.Fatalf("chatTypeName(%d)=%q want %q", input, got, want)
		}
	}
}

func TestFilterGlobalSearchChats(t *testing.T) {
	rows := []globalSearchChatRow{
		{ChatUUID: "chat-1", Type: 2, Name: "产品群", Username: "product", MemberCount: 8},
		{ChatUUID: "chat-2", Type: 1, TargetName: "张三", TargetUsername: "zhangsan", Remark: "设计师"},
	}
	got := filterGlobalSearchChats(rows, "设计", 10)
	if len(got) != 1 {
		t.Fatalf("len=%d", len(got))
	}
	if got[0]["id"] != "chat-2" {
		t.Fatalf("id=%v", got[0]["id"])
	}
	if got[0]["title"] != "设计师" {
		t.Fatalf("title=%v", got[0]["title"])
	}
}
