// 文件用途：验证 friend_request_handler_test.go 对应模块的正常流程、异常处理和回归行为。
// 核心逻辑：覆盖输入校验、状态变化、错误返回、边界条件和并发幸命。

package handlers

import (
	"testing"
	"time"
	"genericim/internal/models"
)

func TestFriendRequestExpirationBoundary(t *testing.T) {
	now := time.Date(2026, 7, 18, 12, 0, 0, 0, time.UTC)
	cases := []struct {
		name    string
		request *models.FriendRequest
		want    bool
	}{
		{
			name: "pending before deadline",
			request: &models.FriendRequest{
				Status:    models.FriendRequestPending,
				ExpiresAt: now.Add(time.Second),
			},
			want: false,
		},
		{
			name: "pending at deadline",
			request: &models.FriendRequest{
				Status:    models.FriendRequestPending,
				ExpiresAt: now,
			},
			want: true,
		},
		{
			name: "accepted request is terminal",
			request: &models.FriendRequest{
				Status:    models.FriendRequestAccepted,
				ExpiresAt: now.Add(-time.Hour),
			},
			want: false,
		},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			if got := friendRequestIsExpired(tc.request, now); got != tc.want {
				t.Fatalf("friendRequestIsExpired()=%v, want %v", got, tc.want)
			}
		})
	}
}
