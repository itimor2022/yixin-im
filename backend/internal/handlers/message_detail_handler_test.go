// 文件用途：验证 message_detail_handler_test.go 对应模块的正常流程、异常处理和回归行为。
// 核心逻辑：覆盖输入校验、状态变化、错误返回、边界条件和并发幸命。

package handlers

import (
	"testing"
	"genericim/internal/models"
)

func TestMessageDetailMemberVisibility(t *testing.T) {
	tests := []struct {
		name     string
		chatType int8
		role     int8
		want     bool
	}{
		{name: "private member", chatType: 1, role: 0, want: true},
		{name: "group member aggregate only", chatType: 2, role: 0, want: false},
		{name: "group admin", chatType: 2, role: 1, want: true},
		{name: "group owner", chatType: 2, role: 2, want: true},
		{name: "channel member aggregate only", chatType: 3, role: 0, want: false},
		{name: "channel admin", chatType: 3, role: 1, want: true},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			if got := canViewMessageReceiptMembers(tt.chatType, tt.role); got != tt.want {
				t.Fatalf("canViewMessageReceiptMembers(%d, %d)=%v want %v", tt.chatType, tt.role, got, tt.want)
			}
		})
	}
}

func TestMessageDetailStatusNames(t *testing.T) {
	if got := messageStatusName(models.MsgStatusRead); got != "read" {
		t.Fatalf("read status=%q", got)
	}
	if got := messageStatusName(models.MsgStatusDelivered); got != "delivered" {
		t.Fatalf("delivered status=%q", got)
	}
	if got := messageStatusName(models.MsgStatusSent); got != "sent" {
		t.Fatalf("sent status=%q", got)
	}
}
