// 文件用途：验证 push_binding_test.go 对应模块的正常流程、异常处理和回归行为。
// 核心逻辑：覆盖输入校验、状态变化、错误返回、边界条件和并发幸命。

package services

import (
	"errors"
	"gorm.io/gorm"
	"testing"
)

func TestNormalizePushTokenAPNs(t *testing.T) {
	token, hash, err := NormalizePushToken(PushChannelAPNs, " <AA bb\nCCdd> ")
	if err != nil {
		t.Fatalf("NormalizePushToken returned error: %v", err)
	}
	if token != "aabbccdd" {
		t.Fatalf("unexpected normalized token: %q", token)
	}
	if len(hash) != 64 {
		t.Fatalf("unexpected hash length: %d", len(hash))
	}
}

func TestNormalizePushTokenDoesNotFoldAndroidCase(t *testing.T) {
	token, _, err := NormalizePushToken(PushChannelFCM, " AbC-Token ")
	if err != nil {
		t.Fatalf("NormalizePushToken returned error: %v", err)
	}
	if token != "AbC-Token" {
		t.Fatalf("Android token case changed: %q", token)
	}
}

func TestNormalizePushTokenCanonicalizesWebPush(t *testing.T) {
	first := `{"keys":{"p256dh":"p","auth":"a"},"endpoint":"https://push.example.test/x"}`
	second := `{"endpoint":"https://push.example.test/x","keys":{"auth":"a","p256dh":"p"}}`
	tokenA, hashA, err := NormalizePushToken(PushChannelWebPush, first)
	if err != nil {
		t.Fatalf("first NormalizePushToken returned error: %v", err)
	}
	tokenB, hashB, err := NormalizePushToken(PushChannelWebPush, second)
	if err != nil {
		t.Fatalf("second NormalizePushToken returned error: %v", err)
	}
	if tokenA != tokenB || hashA != hashB {
		t.Fatalf("equivalent WebPush subscriptions did not canonicalize equally")
	}
}

func TestNormalizePushTokenRejectsInvalidAPNs(t *testing.T) {
	if _, _, err := NormalizePushToken(PushChannelAPNs, "not-hex"); err == nil {
		t.Fatal("expected invalid APNs token error")
	}
}

func TestNormalizeExplicitPushChannelRejectsUnknownValue(t *testing.T) {
	if got := NormalizeExplicitPushChannel("unexpected", "ios"); got != PushChannelUnknown {
		t.Fatalf("expected unknown explicit channel, got %q", got)
	}
	if got := NormalizeExplicitPushChannel("", "android"); got != PushChannelFCM {
		t.Fatalf("expected Android default FCM channel, got %q", got)
	}
}

func TestClearPushBindingsForDeviceRejectsInvalidScope(t *testing.T) {
	if _, err := ClearPushBindingsForDevice(nil, 1, "device-1"); err == nil {
		t.Fatal("expected nil database to be rejected")
	}
	if _, err := ClearPushBindingsForDevice(&gorm.DB{}, 0, "device-1"); err == nil {
		t.Fatal("expected empty user scope to be rejected")
	}
	if _, err := ClearPushBindingsForDevice(&gorm.DB{}, 1, ""); !errors.Is(err, ErrPushDeviceMismatch) {
		t.Fatalf("expected device mismatch, got %v", err)
	}
}
