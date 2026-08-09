// 文件用途：验证 call_handler_unit_test.go 对应模块的正常流程、异常处理和回归行为。
// 核心逻辑：覆盖输入校验、状态变化、错误返回、边界条件和并发幸命。

package handlers

import (
	"github.com/gin-gonic/gin"
	"strings"
	"testing"
	"time"
	"genericim/internal/models"
)

func TestIsStaleCallingCall(t *testing.T) {
	now := time.Date(2026, 6, 14, 12, 0, 0, 0, time.UTC)
	tests := []struct {
		name  string
		call  models.Call
		stale bool
	}{
		{
			name: "calling newer than timeout remains active",
			call: models.Call{
				Status:    "calling",
				StartTime: now.Add(-callRingingTimeout + time.Second),
			},
			stale: false,
		},
		{
			name: "calling at timeout is stale",
			call: models.Call{
				Status:    "calling",
				StartTime: now.Add(-callRingingTimeout),
			},
			stale: true,
		},
		{
			name: "connected call is not treated as stale ringing",
			call: models.Call{
				Status:    "connected",
				StartTime: now.Add(-time.Hour),
			},
			stale: false,
		},
		{
			name: "zero start time is ignored",
			call: models.Call{
				Status: "calling",
			},
			stale: false,
		},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			if got := isStaleCallingCall(tt.call, now); got != tt.stale {
				t.Fatalf("stale=%v, want %v", got, tt.stale)
			}
		})
	}
}

func TestReverseSimultaneousCallReusesOnlyTheLiveOppositeDirection(t *testing.T) {
	now := time.Date(2026, 7, 16, 12, 0, 0, 0, time.UTC)
	live := models.Call{
		CallerID:  20,
		CalleeID:  10,
		Status:    "calling",
		StartTime: now.Add(-time.Second),
	}
	if !isReverseSimultaneousCall(live, 10, 20, now) {
		t.Fatal("expected reverse live call to be arbitrated onto call_id=77")
	}
	if isReverseSimultaneousCall(live, 20, 10, now) {
		t.Fatal("same-direction duplicate must not be treated as reverse arbitration")
	}
	stale := live
	stale.StartTime = now.Add(-callRingingTimeout)
	if isReverseSimultaneousCall(stale, 10, 20, now) {
		t.Fatal("stale reverse call must not be reused")
	}
	connected := live
	connected.Status = "connected"
	if isReverseSimultaneousCall(connected, 10, 20, now) {
		t.Fatal("connected call must be handled as busy, not simultaneous ringing")
	}
}

func TestGenerateChannelNameIsUniqueAcrossRapidCalls(t *testing.T) {
	t.Parallel()

	const total = 500
	names := make(map[string]struct{}, total)
	for i := 0; i < total; i++ {
		name := generateChannelName(
			"366cd03b-0000-0000-0000-000000000001",
			"57dcc4ce-0000-0000-0000-000000000002",
		)
		if _, exists := names[name]; exists {
			t.Fatalf("duplicate channel generated at iteration %d: %s", i, name)
		}
		names[name] = struct{}{}
	}
}

func TestGenerateChannelNameHandlesShortParticipantIDs(t *testing.T) {
	t.Parallel()
	name := generateChannelName("a", "short-id")
	if !strings.HasPrefix(name, "call_a_short-id_") {
		t.Fatalf("short-id channel=%q", name)
	}
}

func TestTerminalCallStatusIncludesFailed(t *testing.T) {
	for _, status := range []string{"ended", "rejected", "cancelled", "missed", "failed"} {
		t.Run(status, func(t *testing.T) {
			if !isTerminalCallStatus(status) {
				t.Fatalf("%q should be terminal", status)
			}
		})
	}
	if isTerminalCallStatus("calling") {
		t.Fatal("calling should not be terminal")
	}
	if isTerminalCallStatus("connected") {
		t.Fatal("connected should not be terminal")
	}
}

func TestCallCleanupIntervalIsFastEnoughForP0Release(t *testing.T) {
	if callCleanupInterval > time.Second {
		t.Fatalf("callCleanupInterval=%s, want <=1s", callCleanupInterval)
	}
}

func TestCallRingingTimeoutMatchesClientReliabilityWindow(t *testing.T) {
	if callRingingTimeout != 30*time.Second {
		t.Fatalf("callRingingTimeout=%s, want 30s", callRingingTimeout)
	}
}

func TestResolveCallMediaState(t *testing.T) {
	videoOff := false
	nextType, videoEnabled, err := resolveCallMediaState("video", "", &videoOff)
	if err != nil || nextType != "video" || videoEnabled {
		t.Fatalf("camera toggle result=(%q,%v,%v)", nextType, videoEnabled, err)
	}

	nextType, videoEnabled, err = resolveCallMediaState("video", "voice", nil)
	if err != nil || nextType != "voice" || videoEnabled {
		t.Fatalf("downgrade result=(%q,%v,%v)", nextType, videoEnabled, err)
	}
	if _, _, err = resolveCallMediaState("voice", "video", nil); err == nil {
		t.Fatal("voice-to-video upgrade must be rejected")
	}
}

func TestBuildCallMessageTextUsesReadableChineseLabels(t *testing.T) {
	tests := []struct {
		name string
		call *models.Call
		want string
	}{
		{
			name: "voice cancelled",
			call: &models.Call{CallType: "voice", EndReason: "cancelled"},
			want: "语音通话 已取消",
		},
		{
			name: "video missed",
			call: &models.Call{CallType: "video", EndReason: "timeout"},
			want: "视频通话 未接",
		},
		{
			name: "voice duration",
			call: &models.Call{CallType: "voice", EndReason: "hangup", Duration: 125},
			want: "语音通话 02:05",
		},
		{
			name: "nil call fallback",
			call: nil,
			want: "语音通话 未接",
		},
		{
			name: "admin force ended without duration",
			call: &models.Call{CallType: "voice", EndReason: "admin_force_end"},
			want: "语音通话 已结束",
		},
		{
			name: "heartbeat timeout with duration",
			call: &models.Call{CallType: "video", EndReason: "heartbeat_timeout", Duration: 95},
			want: "视频通话 01:35",
		},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			if got := buildCallMessageText(tt.call); got != tt.want {
				t.Fatalf("buildCallMessageText()=%q, want %q", got, tt.want)
			}
		})
	}
}

func TestFinishActiveCallForRelease(t *testing.T) {
	now := time.Date(2026, 6, 26, 15, 0, 0, 0, time.UTC)
	connectedAt := now.Add(-42 * time.Second)
	tests := []struct {
		name           string
		call           models.Call
		reason         string
		wantStatus     string
		wantReason     string
		wantDuration   int
		wantEndTimeSet bool
	}{
		{
			name: "ringing call is cancelled immediately",
			call: models.Call{
				Status:    "calling",
				StartTime: now.Add(-time.Second),
			},
			reason:         "hangup",
			wantStatus:     "cancelled",
			wantReason:     "cancelled",
			wantDuration:   0,
			wantEndTimeSet: true,
		},
		{
			name: "connected call is ended with duration",
			call: models.Call{
				Status:      "connected",
				StartTime:   now.Add(-time.Minute),
				ConnectTime: &connectedAt,
			},
			reason:         "hangup",
			wantStatus:     "ended",
			wantReason:     "hangup",
			wantDuration:   42,
			wantEndTimeSet: true,
		},
		{
			name: "empty reason defaults to hangup",
			call: models.Call{
				Status:      "connected",
				StartTime:   now.Add(-time.Minute),
				ConnectTime: &connectedAt,
			},
			wantStatus:     "ended",
			wantReason:     "hangup",
			wantDuration:   42,
			wantEndTimeSet: true,
		},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			call := tt.call
			finishActiveCallForRelease(&call, tt.reason, now)
			if call.Status != tt.wantStatus {
				t.Fatalf("status=%q, want %q", call.Status, tt.wantStatus)
			}
			if call.EndReason != tt.wantReason {
				t.Fatalf("reason=%q, want %q", call.EndReason, tt.wantReason)
			}
			if call.Duration != tt.wantDuration {
				t.Fatalf("duration=%d, want %d", call.Duration, tt.wantDuration)
			}
			if (call.EndTime != nil) != tt.wantEndTimeSet {
				t.Fatalf("endTime set=%v, want %v", call.EndTime != nil, tt.wantEndTimeSet)
			}
		})
	}
}

func TestStaleCallCleanupDecision(t *testing.T) {
	now := time.Date(2026, 6, 26, 14, 0, 0, 0, time.UTC)
	connectedAt := now.Add(-2 * time.Minute)
	tests := []struct {
		name         string
		call         models.Call
		wantStatus   string
		wantReason   string
		wantDuration int
		wantOK       bool
	}{
		{
			name: "stale ringing call becomes missed",
			call: models.Call{
				Status:    "calling",
				StartTime: now.Add(-callRingingTimeout - time.Second),
			},
			wantStatus:   "missed",
			wantReason:   "timeout",
			wantDuration: 0,
			wantOK:       true,
		},
		{
			name: "stale connected call ends by heartbeat timeout",
			call: models.Call{
				Status:          "connected",
				StartTime:       now.Add(-3 * time.Minute),
				ConnectTime:     &connectedAt,
				LastHeartbeatAt: callTimePtr(now.Add(-callHeartbeatStale - time.Second)),
			},
			wantStatus:   "ended",
			wantReason:   "heartbeat_timeout",
			wantDuration: 120,
			wantOK:       true,
		},
		{
			name: "fresh connected call is ignored",
			call: models.Call{
				Status:          "connected",
				StartTime:       now.Add(-time.Minute),
				ConnectTime:     callTimePtr(now.Add(-time.Minute)),
				LastHeartbeatAt: callTimePtr(now.Add(-5 * time.Second)),
			},
			wantOK: false,
		},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			gotStatus, gotReason, gotDuration, gotOK := staleCallCleanupDecision(tt.call, now)
			if gotOK != tt.wantOK {
				t.Fatalf("ok=%v, want %v", gotOK, tt.wantOK)
			}
			if !tt.wantOK {
				return
			}
			if gotStatus != tt.wantStatus {
				t.Fatalf("status=%q, want %q", gotStatus, tt.wantStatus)
			}
			if gotReason != tt.wantReason {
				t.Fatalf("reason=%q, want %q", gotReason, tt.wantReason)
			}
			if gotDuration != tt.wantDuration {
				t.Fatalf("duration=%d, want %d", gotDuration, tt.wantDuration)
			}
		})
	}
}

func TestReplacementCallStatusAndDuration(t *testing.T) {
	now := time.Date(2026, 6, 26, 12, 0, 0, 0, time.UTC)
	connectedAt := now.Add(-75 * time.Second)
	tests := []struct {
		name         string
		call         models.Call
		wantStatus   string
		wantDuration int
	}{
		{
			name: "ringing call is cancelled without duration",
			call: models.Call{
				Status:    "calling",
				StartTime: now.Add(-10 * time.Second),
			},
			wantStatus:   "cancelled",
			wantDuration: 0,
		},
		{
			name: "connected call is ended with connected duration",
			call: models.Call{
				Status:      "connected",
				StartTime:   now.Add(-90 * time.Second),
				ConnectTime: &connectedAt,
			},
			wantStatus:   "ended",
			wantDuration: 75,
		},
		{
			name: "connected call without connect time has no duration",
			call: models.Call{
				Status:    "connected",
				StartTime: now.Add(-90 * time.Second),
			},
			wantStatus:   "ended",
			wantDuration: 0,
		},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			gotStatus, gotDuration := replacementCallStatusAndDuration(tt.call, now)
			if gotStatus != tt.wantStatus {
				t.Fatalf("status=%q, want %q", gotStatus, tt.wantStatus)
			}
			if gotDuration != tt.wantDuration {
				t.Fatalf("duration=%d, want %d", gotDuration, tt.wantDuration)
			}
		})
	}
}

func TestCallReleaseEventTypeFromReason(t *testing.T) {
	tests := []struct {
		reason string
		want   string
	}{
		{reason: "heartbeat_timeout", want: "heartbeat_timeout"},
		{reason: "timeout", want: "ringing_timeout"},
		{reason: "client_replaced", want: "client_replaced"},
		{reason: "admin_force_end", want: "admin_force_end"},
		{reason: "hangup", want: "end"},
	}
	for _, tt := range tests {
		t.Run(tt.reason, func(t *testing.T) {
			if got := callReleaseEventTypeFromReason(tt.reason); got != tt.want {
				t.Fatalf("eventType=%q, want %q", got, tt.want)
			}
		})
	}
}

func TestCallMetricsSnapshotLatencyPercentiles(t *testing.T) {
	metrics := newCallMetricsCollector()
	metrics.Inc(callMetricCreateTotal)
	metrics.Inc(callMetricEndTotal)
	for _, latency := range []int64{10, 20, 30, 40, 50} {
		metrics.ObserveReleaseLatency(latency)
	}
	snapshot := metrics.Snapshot()
	counters := snapshot["counters"].(map[string]int64)
	if got := counters[callMetricCreateTotal]; got != 1 {
		t.Fatalf("create_total=%d, want 1", got)
	}
	if got := counters[callMetricEndTotal]; got != 1 {
		t.Fatalf("end_total=%d, want 1", got)
	}
	latency := snapshot["release_latency_ms"].(gin.H)
	if got := latency["avg"]; got != int64(30) {
		t.Fatalf("avg=%v, want 30", got)
	}
	if got := latency["p95"]; got != int64(50) {
		t.Fatalf("p95=%v, want 50", got)
	}
	if got := latency["p99"]; got != int64(50) {
		t.Fatalf("p99=%v, want 50", got)
	}
}
