// 文件用途：验证 push_service_error_test.go 对应模块的正常流程、异常处理和回归行为。
// 核心逻辑：覆盖输入校验、状态变化、错误返回、边界条件和并发幸命。

package services

import (
	"errors"
	"strings"
	"testing"
)

func TestIsInvalidPushTokenError(t *testing.T) {
	tests := []struct {
		name    string
		channel string
		err     error
		want    bool
	}{
		{
			name:    "apns bad token",
			channel: PushChannelAPNs,
			err:     errors.New("APNs error: 400 - BadDeviceToken"),
			want:    true,
		},
		{
			name:    "fcm unregistered",
			channel: PushChannelFCM,
			err:     errors.New(`fcm send failed: status=404 body={"error":{"status":"NOT_FOUND","details":[{"errorCode":"UNREGISTERED"}]}}`),
			want:    true,
		},
		{
			name:    "fcm sender mismatch",
			channel: PushChannelFCM,
			err:     errors.New(`fcm send failed: status=403 body={"error":{"code":403,"message":"SenderId mismatch","status":"PERMISSION_DENIED","details":[{"@type":"type.googleapis.com/google.firebase.fcm.v1.FcmError","errorCode":"SENDER_ID_MISMATCH"}]}}`),
			want:    true,
		},
		{
			name:    "hms invalid token",
			channel: PushChannelHMS,
			err:     errors.New("hms send failed: code=80300007 msg=invalid token"),
			want:    true,
		},
		{
			name:    "xiaomi invalid registration",
			channel: PushChannelXiaomi,
			err:     errors.New("xiaomi send failed: reason=invalid registration_id"),
			want:    true,
		},
		{
			name:    "oppo invalid registration",
			channel: PushChannelOppo,
			err:     errors.New("oppo send failed: msg=target_value invalid"),
			want:    true,
		},
		{
			name:    "android auth failure is retained",
			channel: PushChannelFCM,
			err:     errors.New("fcm auth failed: invalid service account"),
			want:    false,
		},
		{
			name:    "network failure is retained",
			channel: PushChannelXiaomi,
			err:     errors.New("send xiaomi request failed: timeout"),
			want:    false,
		},
	}
	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			got := isInvalidPushTokenError(tc.channel, tc.err)
			if got != tc.want {
				t.Fatalf("isInvalidPushTokenError(%q, %v)=%v, want %v", tc.channel, tc.err, got, tc.want)
			}
		})
	}
}

func TestSanitizePushErrorBody(t *testing.T) {
	raw := []byte(`{"access_token":"secret-token","data":{"auth_token":"oppo-token","registration_id":"push-token","message":"bad token"}}`)
	got := sanitizePushErrorBody(raw)
	for _, leaked := range []string{"secret-token", "oppo-token", "push-token"} {
		if strings.Contains(got, leaked) {
			t.Fatalf("sanitizePushErrorBody leaked %q in %s", leaked, got)
		}
	}
	if !strings.Contains(got, `"access_token":"***"`) ||
		!strings.Contains(got, `"auth_token":"***"`) ||
		!strings.Contains(got, `"registration_id":"***"`) {
		t.Fatalf("sanitizePushErrorBody did not redact sensitive fields: %s", got)
	}
}

func TestMaskPushToken(t *testing.T) {
	if got := maskPushToken("abcdef123456"); got != "abcd...3456" {
		t.Fatalf("maskPushToken()=%q", got)
	}
	if got := maskPushToken("short"); got != "***" {
		t.Fatalf("maskPushToken(short)=%q", got)
	}
}
