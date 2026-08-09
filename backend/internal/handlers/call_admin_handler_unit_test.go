// 文件用途：验证 call_admin_handler_unit_test.go 对应模块的正常流程、异常处理和回归行为。
// 核心逻辑：覆盖输入校验、状态变化、错误返回、边界条件和并发幸命。

package handlers

import (
	"testing"
	"time"
	"genericim/internal/models"
)

func TestBuildCallAdminResponseIncludesRTCProviderAliases(t *testing.T) {
	t.Parallel()
	startedAt := time.Date(2026, 6, 8, 10, 30, 0, 0, time.UTC)
	endedAt := startedAt.Add(3 * time.Minute)
	createdAt := startedAt.Add(-time.Minute)
	call := models.Call{
		ChannelName: "call_livekit_room",
		RTCProvider: models.RTCProviderLiveKit,
		CallType:    "video",
		Status:      "ended",
		StartTime:   startedAt,
		EndTime:     &endedAt,
		Duration:    180,
		EndReason:   "admin_force_end",
	}
	call.ID = 42
	call.CreatedAt = createdAt

	caller := models.User{UUID: "caller-uuid", Nickname: "Caller", Avatar: "caller.png"}
	callee := models.User{UUID: "callee-uuid", Nickname: "Callee", Avatar: "callee.png"}
	got := buildCallAdminResponse(call, caller, callee)

	assertAdminCallValue(t, got, "id", uint(42))
	assertAdminCallValue(t, got, "channel_name", "call_livekit_room")
	assertAdminCallValue(t, got, "room_name", "call_livekit_room")
	assertAdminCallValue(t, got, "provider", models.RTCProviderLiveKit)
	assertAdminCallValue(t, got, "rtc_provider", models.RTCProviderLiveKit)
	assertAdminCallValue(t, got, "type", "video")
	assertAdminCallValue(t, got, "status", "ended")
	assertAdminCallValue(t, got, "caller_id", "caller-uuid")
	assertAdminCallValue(t, got, "caller_name", "Caller")
	assertAdminCallValue(t, got, "caller_avatar", "caller.png")
	assertAdminCallValue(t, got, "callee_id", "callee-uuid")
	assertAdminCallValue(t, got, "callee_name", "Callee")
	assertAdminCallValue(t, got, "callee_avatar", "callee.png")
	assertAdminCallValue(t, got, "duration", 180)
	assertAdminCallValue(t, got, "end_reason", "admin_force_end")
	assertAdminCallValue(t, got, "started_at", startedAt)
	assertAdminCallValue(t, got, "ended_at", &endedAt)
	assertAdminCallValue(t, got, "created_at", createdAt)
}

func TestBuildCallAdminResponseDefaultsRTCProvider(t *testing.T) {
	t.Parallel()
	got := buildCallAdminResponse(models.Call{}, models.User{}, models.User{})

	assertAdminCallValue(t, got, "provider", models.RTCProviderAgora)
	assertAdminCallValue(t, got, "rtc_provider", models.RTCProviderAgora)
}

func assertAdminCallValue(t *testing.T, values map[string]interface{}, key string, want interface{}) {
	t.Helper()
	if got := values[key]; got != want {
		t.Fatalf("%s=%v, want %v", key, got, want)
	}
}

func TestAdminForceEndStatusAndDuration(t *testing.T) {
	now := time.Date(2026, 6, 26, 13, 0, 0, 0, time.UTC)
	connectedAt := now.Add(-42 * time.Second)
	tests := []struct {
		name         string
		call         models.Call
		wantStatus   string
		wantDuration int
	}{
		{
			name: "calling call becomes cancelled",
			call: models.Call{
				Status:    "calling",
				StartTime: now.Add(-20 * time.Second),
			},
			wantStatus:   "cancelled",
			wantDuration: 0,
		},
		{
			name: "connected call becomes ended",
			call: models.Call{
				Status:      "connected",
				StartTime:   now.Add(-60 * time.Second),
				ConnectTime: &connectedAt,
			},
			wantStatus:   "ended",
			wantDuration: 42,
		},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			gotStatus, gotDuration := adminForceEndStatusAndDuration(tt.call, now)
			if gotStatus != tt.wantStatus {
				t.Fatalf("status=%q, want %q", gotStatus, tt.wantStatus)
			}
			if gotDuration != tt.wantDuration {
				t.Fatalf("duration=%d, want %d", gotDuration, tt.wantDuration)
			}
		})
	}
}
