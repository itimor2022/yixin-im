// 文件用途：验证 push_channel_test.go 对应模块的正常流程、异常处理和回归行为。
// 核心逻辑：覆盖输入校验、状态变化、错误返回、边界条件和并发幸命。

package services

import "testing"

func TestNormalizePushChannelExplicit(t *testing.T) {
	t.Parallel()
	tests := []struct {
		name       string
		channel    string
		deviceType string
		want       string
	}{
		{name: "apns", channel: "apns", deviceType: "ios", want: PushChannelAPNs},
		{name: "apns voip", channel: "apns_voip", deviceType: "ios", want: PushChannelAPNsVoIP},
		{name: "apns voip dash alias", channel: "apns-voip", deviceType: "ios", want: PushChannelAPNsVoIP},
		{name: "voip alias", channel: "voip", deviceType: "ios", want: PushChannelAPNsVoIP},
		{name: "fcm", channel: "fcm", deviceType: "android", want: PushChannelFCM},
		{name: "hms", channel: "hms", deviceType: "android", want: PushChannelHMS},
		{name: "huawei alias", channel: "huawei", deviceType: "android", want: PushChannelHMS},
		{name: "jpush", channel: "jpush", deviceType: "android", want: PushChannelJPush},
		{name: "jiguang alias", channel: "jiguang", deviceType: "android", want: PushChannelJPush},
		{name: "xiaomi", channel: "xiaomi", deviceType: "android", want: PushChannelXiaomi},
		{name: "mi alias", channel: "mi", deviceType: "android", want: PushChannelXiaomi},
		{name: "mipush alias", channel: "mipush", deviceType: "android", want: PushChannelXiaomi},
		{name: "oppo", channel: "oppo", deviceType: "android", want: PushChannelOppo},
		{name: "opush alias", channel: "opush", deviceType: "android", want: PushChannelOppo},
		{name: "heytap alias", channel: "heytap", deviceType: "android", want: PushChannelOppo},
		{name: "webpush", channel: "webpush", deviceType: "web", want: PushChannelWebPush},
		{name: "web alias", channel: "web", deviceType: "web", want: PushChannelWebPush},
		{name: "h5 alias", channel: "h5", deviceType: "web", want: PushChannelWebPush},
		{name: "trim and lower", channel: "  HMS  ", deviceType: "android", want: PushChannelHMS},
	}
	for _, tc := range tests {
		tc := tc
		t.Run(tc.name, func(t *testing.T) {
			t.Parallel()
			got := NormalizePushChannel(tc.channel, tc.deviceType)
			if got != tc.want {
				t.Fatalf("NormalizePushChannel(%q,%q)=%q, want %q", tc.channel, tc.deviceType, got, tc.want)
			}
		})
	}
}

func TestNormalizePushChannelDefaultByDeviceType(t *testing.T) {
	t.Parallel()
	tests := []struct {
		name       string
		channel    string
		deviceType string
		want       string
	}{
		{name: "ios default apns", channel: "", deviceType: "ios", want: PushChannelAPNs},
		{name: "android default fcm", channel: "", deviceType: "android", want: PushChannelFCM},
		{name: "unknown device default unknown", channel: "", deviceType: "web", want: PushChannelUnknown},
		{name: "device trim lower", channel: "  ", deviceType: "  iOS ", want: PushChannelAPNs},
	}
	for _, tc := range tests {
		tc := tc
		t.Run(tc.name, func(t *testing.T) {
			t.Parallel()
			got := NormalizePushChannel(tc.channel, tc.deviceType)
			if got != tc.want {
				t.Fatalf("NormalizePushChannel(%q,%q)=%q, want %q", tc.channel, tc.deviceType, got, tc.want)
			}
		})
	}
}

func TestPushStorageDeviceIDKeepsAndroidChannelsSeparate(t *testing.T) {
	t.Parallel()
	if got := PushStorageDeviceID("device-1", PushChannelHMS); got != "device-1:push:hms" {
		t.Fatalf("hms storage id=%q", got)
	}
	if got := PushStorageDeviceID("device-1:push:fcm", PushChannelHMS); got != "device-1:push:hms" {
		t.Fatalf("normalized storage id=%q", got)
	}
	if got := PushStorageDeviceID("device-1", PushChannelAPNsVoIP); got != "device-1:voip" {
		t.Fatalf("voip storage id=%q", got)
	}
	if got := PushStorageDeviceID("device-1", PushChannelWebPush); got != "device-1" {
		t.Fatalf("webpush storage id=%q", got)
	}
}

func TestLogicalPushDeviceIDStripsPushSuffixes(t *testing.T) {
	t.Parallel()
	tests := map[string]string{
		"device-1:push:jpush":  "device-1",
		"device-1:push:fcm":    "device-1",
		"device-1:push:hms":    "device-1",
		"device-1:push:xiaomi": "device-1",
		"device-1:push:oppo":   "device-1",
		"device-1:voip":        "device-1",
		"device-1":             "device-1",
	}
	for input, want := range tests {
		input, want := input, want
		t.Run(input, func(t *testing.T) {
			t.Parallel()
			if got := LogicalPushDeviceID(input); got != want {
				t.Fatalf("LogicalPushDeviceID(%q)=%q, want %q", input, got, want)
			}
		})
	}
}

func TestPushStorageDeviceIDsIncludesAllChannelRows(t *testing.T) {
	t.Parallel()
	got := PushStorageDeviceIDs("device-1:push:hms")
	want := []string{
		"device-1",
		"device-1:voip",
		"device-1:push:jpush",
		"device-1:push:fcm",
		"device-1:push:hms",
		"device-1:push:xiaomi",
		"device-1:push:oppo",
	}
	if len(got) != len(want) {
		t.Fatalf("len=%d, want %d: %v", len(got), len(want), got)
	}
	for i := range want {
		if got[i] != want[i] {
			t.Fatalf("ids[%d]=%q, want %q; all=%v", i, got[i], want[i], got)
		}
	}
}
