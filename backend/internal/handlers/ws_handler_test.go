// 文件用途：验证 ws_handler_test.go 对应模块的正常流程、异常处理和回归行为。
// 核心逻辑：覆盖输入校验、状态变化、错误返回、边界条件和并发幸命。

package handlers

import "testing"

func TestIsWebSocketOriginAllowed(t *testing.T) {
	tests := []struct {
		name    string
		origin  string
		allowed []string
		want    bool
	}{
		{
			name:    "empty origin is allowed for native clients",
			origin:  "",
			allowed: []string{"https://app.example.com"},
			want:    true,
		},
		{
			name:    "empty allow list keeps backward compatibility",
			origin:  "https://evil.example.com",
			allowed: nil,
			want:    true,
		},
		{
			name:    "matching origin is allowed",
			origin:  "https://app.example.com",
			allowed: []string{"https://app.example.com"},
			want:    true,
		},
		{
			name:    "matching origin ignores path in config",
			origin:  "https://app.example.com",
			allowed: []string{"https://app.example.com/app"},
			want:    true,
		},
		{
			name:    "different origin is rejected",
			origin:  "https://evil.example.com",
			allowed: []string{"https://app.example.com"},
			want:    false,
		},
		{
			name:    "invalid origin is rejected",
			origin:  "not a url",
			allowed: []string{"https://app.example.com"},
			want:    false,
		},
		{
			name:    "wildcard allows all",
			origin:  "https://evil.example.com",
			allowed: []string{"*"},
			want:    true,
		},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			if got := isWebSocketOriginAllowed(tt.origin, tt.allowed); got != tt.want {
				t.Fatalf("isWebSocketOriginAllowed() = %v, want %v", got, tt.want)
			}
		})
	}
}
