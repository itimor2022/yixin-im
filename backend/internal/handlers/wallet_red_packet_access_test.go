// 文件用途：验证 wallet_red_packet_access_test.go 对应模块的正常流程、异常处理和回归行为。
// 核心逻辑：覆盖输入校验、状态变化、错误返回、边界条件和并发幸命。

package handlers

import (
	"net/http"
	"testing"
	"genericim/internal/models"
)

func TestNextRedPacketClaimProgress(t *testing.T) {
	t.Parallel()
	packet := models.RedPacket{
		RemainingAmount: 10,
		RemainingCount:  2,
		Status:          models.RedPacketStatusActive,
	}
	amount, count, status := nextRedPacketClaimProgress(packet, 2.79)
	if amount != 7.21 || count != 1 || status != models.RedPacketStatusActive {
		t.Fatalf("first claim progress = (%.2f, %d, %s), want(7.21, 1, active)", amount, count, status)
	}
	packet.RemainingAmount = amount
	packet.RemainingCount = count
	packet.Status = status
	amount, count, status = nextRedPacketClaimProgress(packet, 7.21)
	if amount != 0 || count != 0 || status != models.RedPacketStatusFinished {
		t.Fatalf("final claim progress = (%.2f, %d, %s), want(0.00, 0, finished)", amount, count, status)
	}
}

func TestDecideRedPacketAccess(t *testing.T) {
	t.Parallel()
	tests := []struct {
		name      string
		chat      models.Chat
		isSender  bool
		isMember  bool
		operation redPacketAccessOperation
		allowed   bool
		status    int
	}{
		{
			name:     "sender can view after leaving",
			chat:     models.Chat{Type: 2, Status: models.ChatStatusNormal},
			isSender: true, operation: redPacketAccessView,
			allowed: true, status: http.StatusNotFound,
		},
		{
			name:     "current member can view",
			chat:     models.Chat{Type: 2, Status: models.ChatStatusNormal},
			isMember: true, operation: redPacketAccessView,
			allowed: true, status: http.StatusNotFound,
		},
		{
			name:      "outsider cannot discover packet",
			chat:      models.Chat{Type: 2, Status: models.ChatStatusNormal},
			operation: redPacketAccessView,
			allowed:   false, status: http.StatusNotFound,
		},
		{
			name:     "group member can claim",
			chat:     models.Chat{Type: 2, Status: models.ChatStatusNormal},
			isMember: true, operation: redPacketAccessClaim,
			allowed: true, status: http.StatusNotFound,
		},
		{
			name:     "group sender can claim while still member",
			chat:     models.Chat{Type: 2, Status: models.ChatStatusNormal},
			isSender: true, isMember: true, operation: redPacketAccessClaim,
			allowed: true, status: http.StatusNotFound,
		},
		{
			name:     "private sender cannot claim own packet",
			chat:     models.Chat{Type: 1, Status: models.ChatStatusNormal},
			isSender: true, isMember: true, operation: redPacketAccessClaim,
			allowed: false, status: http.StatusForbidden,
		},
		{
			name:     "sender cannot claim after leaving",
			chat:     models.Chat{Type: 2, Status: models.ChatStatusNormal},
			isSender: true, operation: redPacketAccessClaim,
			allowed: false, status: http.StatusForbidden,
		},
		{
			name:      "outsider cannot claim or discover packet",
			chat:      models.Chat{Type: 2, Status: models.ChatStatusNormal},
			operation: redPacketAccessClaim,
			allowed:   false, status: http.StatusNotFound,
		},
		{
			name:     "banned group cannot claim",
			chat:     models.Chat{Type: 2, Status: models.ChatStatusBanned},
			isMember: true, operation: redPacketAccessClaim,
			allowed: false, status: http.StatusForbidden,
		},
		{
			name:     "dissolved group cannot claim",
			chat:     models.Chat{Type: 2, Status: models.ChatStatusDissolved},
			isMember: true, operation: redPacketAccessClaim,
			allowed: false, status: http.StatusForbidden,
		},
		{
			name:     "channel packet cannot claim",
			chat:     models.Chat{Type: 3, Status: models.ChatStatusNormal},
			isMember: true, operation: redPacketAccessClaim,
			allowed: false, status: http.StatusForbidden,
		},
	}
	for _, tt := range tests {
		tt := tt
		t.Run(tt.name, func(t *testing.T) {
			t.Parallel()
			got := decideRedPacketAccess(tt.chat, tt.isSender, tt.isMember, tt.operation)
			if got.Allowed != tt.allowed {
				t.Fatalf("Allowed = %v, want %v", got.Allowed, tt.allowed)
			}
			if got.Status != tt.status {
				t.Fatalf("Status = %d, want %d", got.Status, tt.status)
			}
			if !got.Allowed && got.Message == "" {
				t.Fatal("denied access must include a user-facing message")
			}
		})
	}
}
