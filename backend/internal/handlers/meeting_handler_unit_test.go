// 文件用途：验证 meeting_handler_unit_test.go 对应模块的正常流程、异常处理和回归行为。
// 核心逻辑：覆盖输入校验、状态变化、错误返回、边界条件和并发幸命。

package handlers

import (
	"strings"
	"testing"
)

func TestNormalizeMeetingType(t *testing.T) {
	tests := []struct {
		name        string
		meetingType string
		callType    string
		wantType    string
		wantOK      bool
	}{
		{name: "meeting type voice", meetingType: "voice", callType: "", wantType: "voice", wantOK: true},
		{name: "meeting type video", meetingType: "video", callType: "", wantType: "video", wantOK: true},
		{name: "fallback from call type", meetingType: "", callType: "voice", wantType: "voice", wantOK: true},
		{name: "invalid type", meetingType: "audio", callType: "", wantType: "", wantOK: false},
		{name: "both invalid", meetingType: "", callType: "screen", wantType: "", wantOK: false},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			got, ok := normalizeMeetingType(tt.meetingType, tt.callType)
			if ok != tt.wantOK {
				t.Fatalf("ok mismatch: want=%v got=%v", tt.wantOK, ok)
			}
			if got != tt.wantType {
				t.Fatalf("type mismatch: want=%s got=%s", tt.wantType, got)
			}
		})
	}
}

func TestGenerateMeetingChannelName(t *testing.T) {
	meetingUUID := "12345678-90ab-cdef-1234-567890abcdef"
	channel := generateMeetingChannelName(meetingUUID)
	if !strings.HasPrefix(channel, "meeting_12345678_") {
		t.Fatalf("channel should use uuid prefix: got=%s", channel)
	}
	if len(channel) <= len("meeting_12345678_") {
		t.Fatalf("channel should include unix timestamp suffix: got=%s", channel)
	}
}

func TestToAgoraUID(t *testing.T) {
	if got := toAgoraUID(0); got != 0 {
		t.Fatalf("zero user id should map to zero, got=%d", got)
	}
	if got := toAgoraUID(42); got != 42 {
		t.Fatalf("small user id should map directly, got=%d", got)
	}

	const maxUint32 = ^uint32(0)
	if got := toAgoraUID(uint64(maxUint32) + 1); got != 0 {
		t.Fatalf("overflow wrap mismatch, want=0 got=%d", got)
	}
}

func TestIsMeetingCapacityReached(t *testing.T) {
	tests := []struct {
		name            string
		maxParticipants int
		joinedCount     int64
		want            bool
	}{
		{name: "limit disabled", maxParticipants: 0, joinedCount: 999, want: false},
		{name: "below limit", maxParticipants: 10, joinedCount: 9, want: false},
		{name: "at limit", maxParticipants: 10, joinedCount: 10, want: true},
		{name: "over limit", maxParticipants: 10, joinedCount: 11, want: true},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			got := isMeetingCapacityReached(tt.maxParticipants, tt.joinedCount)
			if got != tt.want {
				t.Fatalf("result mismatch: want=%v got=%v", tt.want, got)
			}
		})
	}
}
