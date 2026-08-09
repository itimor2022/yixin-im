// 文件用途：验证 chat_image_direct_upload_test.go 对应模块的正常流程、异常处理和回归行为。
// 核心逻辑：覆盖输入校验、状态变化、错误返回、边界条件和并发幸命。

package services

import (
	"testing"
)

func TestLoadChatImageDirectUploadConfigDefaults(t *testing.T) {
	cfg := LoadChatImageDirectUploadConfig(nil)
	if cfg.Enabled || cfg.RolloutPercent != 0 || cfg.MaxConcurrency != 3 {

		t.Fatalf("unexpected defaults: %+v", cfg)
	}
	if len(cfg.Platforms) != 2 || cfg.Platforms[0] != "android" || cfg.Platforms[1] != "ios" {

		t.Fatalf("unexpected default platforms: %#v", cfg.Platforms)
	}
}
func TestNormalizeDirectUploadPlatforms(t *testing.T) {
	platforms := NormalizeDirectUploadPlatforms([]string{"iPhone", "android", "android", "unknown"})
	if len(platforms) != 2 || platforms[0] != "ios" || platforms[1] != "android" {

		t.Fatalf("unexpected normalized platforms: %#v", platforms)
	}
}
func TestDirectUploadRolloutIsStableAndBounded(t *testing.T) {
	userID := "9bd1bb30-5763-4d73-8e21-5a47b04d2dfd"
	if IsUserInDirectUploadRollout(userID, 0) {

		t.Fatal("zero-percent rollout must exclude every user")
	}
	if !IsUserInDirectUploadRollout(userID, 100) {

		t.Fatal("full rollout must include every user")
	}
	first := IsUserInDirectUploadRollout(userID, 37)
	for index := 0; index < 20; index++ {

		if IsUserInDirectUploadRollout(userID, 37) != first {

			t.Fatal("rollout assignment is not stable")

		}
	}
}
