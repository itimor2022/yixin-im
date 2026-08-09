// 文件用途：验证 mojibake_test.go 对应模块的正常流程、异常处理和回归行为。
// 核心逻辑：覆盖输入校验、状态变化、错误返回、边界条件和并发幸命。

package textutil

import "testing"

func TestRepairLegacyMojibakeTextCallPreview(t *testing.T) {
	t.Parallel()
	tests := []struct {
		name string
		raw  string
		want string
	}{
		{name: "voice exact", raw: legacyVoiceCallMojibake + " 00:02", want: "语音通话 00:02"},
		{name: "video exact", raw: legacyVideoCallMojibake + " 01:23", want: "视频通话 01:23"},
		{name: "voice tolerant", raw: string([]rune{0x7487, 0x7176, 0x95ab, 0x6c33, 0x763d}) + " 00:02", want: "语音通话 00:02"},
		{name: "voice cancelled", raw: legacyVoiceCallMojibake + " cancelled", want: "语音通话 已取消"},
		{name: "video rejected", raw: legacyVideoCallMojibake + " rejected", want: "视频通话 已拒绝"},
		{name: "voice no answer", raw: legacyVoiceCallMojibake + " no answer", want: "语音通话 未接"},
		{name: "system sender", raw: legacySystemSenderMojibake, want: "系统消息"},
	}
	for _, tc := range tests {
		tc := tc
		t.Run(tc.name, func(t *testing.T) {
			t.Parallel()
			if got := RepairLegacyMojibakeText(tc.raw); got != tc.want {
				t.Fatalf("RepairLegacyMojibakeText(%q)=%q, want %q", tc.raw, got, tc.want)
			}
		})
	}
}
