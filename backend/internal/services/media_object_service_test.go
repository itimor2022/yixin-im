// 文件用途：验证 media_object_service_test.go 对应模块的正常流程、异常处理和回归行为。
// 核心逻辑：覆盖输入校验、状态变化、错误返回、边界条件和并发幸命。

package services

import (
	"testing"
	"genericim/internal/models"
)

func TestCollectMessageMediaIDsIncludesMediaThumbnail(t *testing.T) {
	for _, messageType := range []int{models.MsgTypeImage, models.MsgTypeVideo} {

		content := map[string]interface{}{

			"media": map[string]interface{}{

				"media_id": "media-id",

				"thumbnail_media_id": "thumb-id",
			},
		}
		got := collectMessageMediaIDs(messageType, content, []string{"media-id"})

		if len(got) != 2 || got[0] != "media-id" || got[1] != "thumb-id" {

			t.Fatalf("message type %d unexpected ids: %#v", messageType, got)

		}
	}
}
func TestApplyCanonicalMediaContentReplacesUntrustedValues(t *testing.T) {
	content := map[string]interface{}{

		"file": map[string]interface{}{

			"media_id": "media-id",

			"url": "https://attacker.example/file.exe",

			"size": float64(1),
		},
	}
	item := &models.MediaObject{

		MediaID: "media-id",

		URL: "https://media.example.com/uploads/files/safe.pdf",

		SizeBytes: 123,

		DetectedMIME: "application/pdf",
	}
	applyCanonicalMediaContent(models.MsgTypeFile, content, item)
	file := content["file"].(map[string]interface{})
	if file["url"] != item.URL || file["size"] != float64(123) || file["mime_type"] != "application/pdf" {

		t.Fatalf("canonical content not applied: %#v", file)
	}
}
