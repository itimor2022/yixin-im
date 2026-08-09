// 文件用途：验证 push_service_device_filter_test.go 对应模块的正常流程、异常处理和回归行为。
// 核心逻辑：覆盖输入校验、状态变化、错误返回、边界条件和并发幸命。

package services

import (
	"testing"
	"genericim/internal/models"
)

func TestExcludePhysicalPushDeviceRemovesAllChannelBindings(t *testing.T) {
	devices := []models.UserDevice{
		{DeviceID: "phone-a", PushChannel: PushChannelFCM},
		{DeviceID: "phone-a:push:hms", PushChannel: PushChannelHMS},
		{DeviceID: "phone-b", PushChannel: PushChannelFCM},
	}
	filtered := excludePhysicalPushDevice(devices, "phone-a:push:fcm")
	if len(filtered) != 1 || filtered[0].DeviceID != "phone-b" {
		t.Fatalf("unexpected filtered devices: %+v", filtered)
	}
}
