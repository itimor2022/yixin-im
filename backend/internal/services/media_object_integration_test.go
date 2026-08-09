// 文件用途：验证 media_object_integration_test.go 对应模块的正常流程、异常处理和回归行为。
// 核心逻辑：覆盖输入校验、状态变化、错误返回、边界条件和并发幸命。

package services

import (
	"github.com/google/uuid"
	"gorm.io/driver/mysql"
	"gorm.io/gorm"
	"os"
	"testing"
	"time"
	"genericim/internal/models"
)

func openMediaLifecycleIntegrationDB(t *testing.T) *gorm.DB {
	t.Helper()
	dsn := os.Getenv("GENERIC_IM_TEST_MYSQL_DSN")
	if dsn == "" {

		t.Skip("set GENERIC_IM_TEST_MYSQL_DSN to run media lifecycle integration tests")
	}
	db, err := gorm.Open(mysql.Open(dsn), &gorm.Config{})
	if err != nil {

		t.Fatalf("open integration database: %v", err)
	}
	return db
}
func createLifecycleTestMedia(
	t *testing.T,
	db *gorm.DB,
	messageID string,
	referenceCount int,
	boundAt time.Time) *models.MediaObject {
	t.Helper()
	token := uuid.NewString()
	item := &models.MediaObject{

		MediaID: token,

		UserID: 1,

		ClientRequestID: "p0-test-" + token,

		Category: "image",

		Provider: StorageProviderS3,

		Bucket: "p0-test",

		ObjectKey: "p0-test/" + token + ".png",

		Status: models.MediaObjectStatusBound,

		BusinessType: "message",

		BusinessID: messageID,

		BusinessScopeID: "p0-chat-" + token,

		ReferenceCount: referenceCount,

		BoundAt: &boundAt,
	}
	if err := db.Create(item).Error; err != nil {

		t.Fatalf("create lifecycle media: %v", err)
	}
	t.Cleanup(func() {

		_ = db.Unscoped().Delete(&models.MediaObject{}, item.ID).Error
	})
	return item
}
func reloadLifecycleMedia(t *testing.T, db *gorm.DB, id uint64) models.MediaObject {
	t.Helper()
	var item models.MediaObject
	if err := db.First(&item, id).Error; err != nil {

		t.Fatalf("reload lifecycle media: %v", err)
	}
	return item
}
func TestMarkMessageMediaForDeletionIntegration(t *testing.T) {
	db := openMediaLifecycleIntegrationDB(t)
	messageID := "p0-message-" + uuid.NewString()
	item := createLifecycleTestMedia(t, db, messageID, 1, time.Now())
	if err := MarkMessageMediaForDeletion(db, messageID); err != nil {

		t.Fatalf("first release: %v", err)
	}
	got := reloadLifecycleMedia(t, db, item.ID)
	if got.Status != models.MediaObjectStatusDeleting ||

		got.ReferenceCount != 0 ||

		got.NextRetryAt == nil {

		t.Fatalf("unexpected released media: %#v", got)
	}
	if err := MarkMessageMediaForDeletion(db, messageID); err != nil {

		t.Fatalf("idempotent release: %v", err)
	}
	got = reloadLifecycleMedia(t, db, item.ID)
	if got.Status != models.MediaObjectStatusDeleting || got.ReferenceCount != 0 {

		t.Fatalf("idempotent release changed terminal state: %#v", got)
	}
}
func TestMarkMessageMediaForDeletionPreservesSharedObjectIntegration(t *testing.T) {
	db := openMediaLifecycleIntegrationDB(t)
	messageID := "p0-shared-message-" + uuid.NewString()
	item := createLifecycleTestMedia(t, db, messageID, 2, time.Now())
	for attempt := 0; attempt < 2; attempt++ {

		if err := MarkMessageMediaForDeletion(db, messageID); err != nil {

			t.Fatalf("release attempt %d: %v", attempt+1, err)

		}
	}
	got := reloadLifecycleMedia(t, db, item.ID)
	if got.Status != models.MediaObjectStatusBound || got.ReferenceCount != 2 {

		t.Fatalf("shared media was released prematurely: %#v", got)
	}
}
