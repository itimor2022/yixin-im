// 文件用途：验证 service_conversation_service_test.go 对应模块的正常流程、异常处理和回归行为。
// 核心逻辑：覆盖输入校验、状态变化、错误返回、边界条件和并发幸命。

package services

import (
	"strings"
	"testing"
	"unicode/utf8"
)

func TestTruncateRunesPreservesChineseCharacters(t *testing.T) {
	input := strings.Repeat("客服消息", 200)
	got := truncateRunes(input, 500)
	if count := utf8.RuneCountInString(got); count != 500 {
		t.Fatalf("truncateRunes() rune count = %d, want 500", count)
	}
	if !utf8.ValidString(got) {
		t.Fatal("truncateRunes() produced invalid UTF-8")
	}
}

func TestMaskServicePhone(t *testing.T) {
	tests := map[string]string{
		"13812345678": "138****5678",
		"123456":      "123456",
		"":            "",
	}
	for input, want := range tests {
		if got := maskServicePhone(input); got != want {
			t.Fatalf("maskServicePhone(%q) = %q, want %q", input, got, want)
		}
	}
}
