// 文件用途：验证 message_revoke_state_test.go 对应模块的正常流程、异常处理和回归行为。
// 核心逻辑：覆盖输入校验、状态变化、错误返回、边界条件和并发幸命。

package services

import "testing"

func TestShouldDecrementUnreadAfterRevoke(t *testing.T) {
	tests := []struct {
		name      string
		sender    string
		candidate revokeUnreadCandidate
		seq       uint64
		want      bool
	}{
		{
			name:   "unread recipient",
			sender: "sender",
			candidate: revokeUnreadCandidate{
				UserID: 2, UserUUID: "recipient", LastReadSeq: 4, UnreadCount: 3,
			},
			seq:  5,
			want: true,
		},
		{
			name:   "sender was never incremented",
			sender: "sender",
			candidate: revokeUnreadCandidate{
				UserID: 1, UserUUID: "sender", LastReadSeq: 0, UnreadCount: 2,
			},
			seq: 5,
		},
		{
			name:   "recipient already read through message",
			sender: "sender",
			candidate: revokeUnreadCandidate{
				UserID: 2, UserUUID: "recipient", LastReadSeq: 5, UnreadCount: 1,
			},
			seq: 5,
		},
		{
			name:   "zero unread cannot go negative",
			sender: "sender",
			candidate: revokeUnreadCandidate{
				UserID: 2, UserUUID: "recipient", LastReadSeq: 0, UnreadCount: 0,
			},
			seq: 5,
		},
		{
			name:   "missing sequence is not reconciled",
			sender: "sender",
			candidate: revokeUnreadCandidate{
				UserID: 2, UserUUID: "recipient", LastReadSeq: 0, UnreadCount: 1,
			},
			seq: 0,
		},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			if got := shouldDecrementUnreadAfterRevoke(tt.sender, tt.candidate, tt.seq); got != tt.want {
				t.Fatalf("shouldDecrementUnreadAfterRevoke()=%v, want %v", got, tt.want)
			}
		})
	}
}
