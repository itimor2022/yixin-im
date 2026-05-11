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
		{name: "fcm", channel: "fcm", deviceType: "android", want: PushChannelFCM},
		{name: "hms", channel: "hms", deviceType: "android", want: PushChannelHMS},
		{name: "huawei alias", channel: "huawei", deviceType: "android", want: PushChannelHMS},
		{name: "xiaomi", channel: "xiaomi", deviceType: "android", want: PushChannelXiaomi},
		{name: "mi alias", channel: "mi", deviceType: "android", want: PushChannelXiaomi},
		{name: "mipush alias", channel: "mipush", deviceType: "android", want: PushChannelXiaomi},
		{name: "oppo", channel: "oppo", deviceType: "android", want: PushChannelOppo},
		{name: "opush alias", channel: "opush", deviceType: "android", want: PushChannelOppo},
		{name: "heytap alias", channel: "heytap", deviceType: "android", want: PushChannelOppo},
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
