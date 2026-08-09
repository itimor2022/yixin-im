// 文件用途：验证 user_profile_validation_test.go 对应模块的正常流程、异常处理和回归行为。
// 核心逻辑：覆盖输入校验、状态变化、错误返回、边界条件和并发幸命。

package handlers

import (
	"strings"
	"testing"
)

func TestNormalizeProfileNickname(t *testing.T) {
	tests := []struct {
		name  string
		value string
		want  string
		ok    bool
	}{
		{name: "trim", value: "  测试用户  ", want: "测试用户", ok: true},
		{name: "emoji", value: "用户😀", want: "用户😀", ok: true},
		{name: "empty", value: "   ", ok: false},
		{name: "newline", value: "第一行\n第二行", ok: false},
		{name: "too long", value: strings.Repeat("名", 51), ok: false},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			got, ok := normalizeProfileNickname(tt.value)
			if ok != tt.ok || got != tt.want {
				t.Fatalf("normalizeProfileNickname(%q) = %q, %v; want %q, %v", tt.value, got, ok, tt.want, tt.ok)
			}
		})
	}
}

func TestNormalizeProfileUsername(t *testing.T) {
	tests := []struct {
		value string
		want  string
		ok    bool
	}{
		{value: "  User_123  ", want: "User_123", ok: true},
		{value: "ab", ok: false},
		{value: strings.Repeat("a", 21), ok: false},
		{value: "中文用户", ok: false},
		{value: "bad-name", ok: false},
	}
	for _, tt := range tests {
		got, ok := normalizeProfileUsername(tt.value)
		if ok != tt.ok || got != tt.want {
			t.Fatalf("normalizeProfileUsername(%q) = %q, %v; want %q, %v", tt.value, got, ok, tt.want, tt.ok)
		}
	}
}

func TestValidateProfileBio(t *testing.T) {
	if !validateProfileBio(strings.Repeat("签", 500)) {
		t.Fatal("500-character bio should be accepted")
	}
	if validateProfileBio(strings.Repeat("签", 501)) {
		t.Fatal("501-character bio should be rejected")
	}
}
