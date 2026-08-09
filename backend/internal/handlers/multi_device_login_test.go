// 文件用途：验证 multi_device_login_test.go 对应模块的正常流程、异常处理和回归行为。
// 核心逻辑：覆盖输入校验、状态变化、错误返回、边界条件和并发幸命。

package handlers

import (
	"testing"
	"time"
	"genericim/internal/models"
)

func TestMultiDeviceLoginContextCountsDistinctOtherDevices(t *testing.T) {
	sessions := []models.UserSession{
		{UserID: 7, Token: "a1", DeviceID: "phone-a"},
		{UserID: 7, Token: "a2", DeviceID: "phone-a"},
		{UserID: 7, Token: "b1", DeviceID: "phone-b"},
		{UserID: 7, Token: "w1", DeviceID: "web-c"},
	}
	context := multiDeviceLoginContextFromSessions(sessions, "phone-a")
	if context.Policy != multiDeviceLoginPolicy || context.OtherActiveDeviceCount != 2 {
		t.Fatalf("unexpected context: %+v", context)
	}
}

func TestBuildForceLogoutEventIncludesAuditContext(t *testing.T) {
	occurredAt := time.Date(2026, 7, 18, 3, 4, 5, 0, time.FixedZone("CST", 8*60*60))
	event := buildForceLogoutEvent(
		[]string{"phone-a"},
		"device_terminated",
		"phone-b:push:hms",
		"Huawei B",
		"android",
		occurredAt,
	)
	if event["actor_device_id"] != "phone-b" || event["actor_device_name"] != "Huawei B" {
		t.Fatalf("actor context missing: %+v", event)
	}
	if event["occurred_at"] != "2026-07-17T19:04:05Z" {
		t.Fatalf("unexpected occurred_at: %+v", event)
	}
}

func TestLoginDeviceSecurityContextDetectsOnlyNewPhysicalDevices(t *testing.T) {
	devices := []models.UserDevice{
		{UserID: 7, DeviceID: "phone-a"},
		{UserID: 7, DeviceID: "phone-a:push:hms"},
		{UserID: 7, DeviceID: "web-b"},
	}
	known := loginDeviceSecurityContextFromDevices(devices, "phone-a")
	if known.IsNewDevice || known.OtherKnownDeviceCount != 1 {
		t.Fatalf("known device context mismatch: %+v", known)
	}
	newDevice := loginDeviceSecurityContextFromDevices(devices, "phone-c")
	if !newDevice.IsNewDevice || newDevice.OtherKnownDeviceCount != 2 {
		t.Fatalf("new device context mismatch: %+v", newDevice)
	}
}

func TestBuildNewDeviceLoginEventIncludesSecurityContext(t *testing.T) {
	occurredAt := time.Date(2026, 7, 18, 3, 4, 5, 0, time.FixedZone("CST", 8*60*60))
	event := buildNewDeviceLoginEvent(
		"phone-b:push:hms",
		"android",
		"Huawei B",
		"192.0.2.9",
		occurredAt,
	)
	if event["type"] != "new_device_login" || event["device_id"] != "phone-b" {
		t.Fatalf("device login event mismatch: %+v", event)
	}
	if event["device_name"] != "Huawei B" || event["ip"] != "192.0.2.9" {
		t.Fatalf("security context missing: %+v", event)
	}
	if event["occurred_at"] != "2026-07-17T19:04:05Z" || event["event_id"] == "" {
		t.Fatalf("event audit fields missing: %+v", event)
	}
}
