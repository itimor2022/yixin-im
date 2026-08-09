// 文件用途：实现可复用的后端业务服务和领域逻辑。
// 核心逻辑：协调数据库、缓存、队列和外部服务，集中处理事务、幂等、重试和错误传播。

package services

import (
	"context"
	"errors"
	"fmt"
	"github.com/google/uuid"
	"gorm.io/gorm"
	"gorm.io/gorm/clause"
	"log"
	"os"
	"path/filepath"
	"strings"
	"sync"
	"time"
	"genericim/internal/config"
	"genericim/internal/models"
)

const (
	defaultUnboundMediaTTL = 24 * time.Hour
	staleUploadingTTL      = time.Hour
) // BeginMediaUploadParams 描述上传对象的不可变身份和客户端幂等键。
type BeginMediaUploadParams struct {
	UserID          uint64
	AdminID         uint64
	ClientRequestID string
	Category        string
	Provider        string
	Bucket          string
	ObjectKey       string
	OriginalName    string
	NormalizedExt   string
	DeclaredMIME    string
	DetectedMIME    string
	SizeBytes       int64
	ExpectedSHA256  string
	UploadMode      string
	RemoteUploadID  string
	PartSizeBytes   int64
} // BeginMediaUpload 创建或恢复上传任务，同一用户的 client_request_id 只对应一份文件。
func BeginMediaUpload(db *gorm.DB, params BeginMediaUploadParams) (*models.MediaObject, error) {
	if db == nil {

		return nil, fmt.Errorf("媒体数据库不可用")
	}
	now := time.Now()
	requestID := strings.TrimSpace(params.ClientRequestID)
	if requestID == "" {

		requestID = uuid.NewString()
	} else {
		var existing models.MediaObject

		err := db.Where("user_id = ? AND client_request_id = ?", params.UserID, requestID).First(&existing).Error

		if err == nil {

			if existing.Category != strings.TrimSpace(params.Category) || existing.SizeBytes != params.SizeBytes {

				return nil, fmt.Errorf("上传请求 ID 已被其他文件使用")

			}

			if existing.Status == models.MediaObjectStatusDeleting &&

				existing.BusinessID == "" &&

				existing.ReferenceCount == 0 &&

				existing.RetryCount == 0 {

				expiresAt := now.Add(defaultUnboundMediaTTL)

				if err := db.Model(&models.MediaObject{}).Where("id = ? AND status = ?", existing.ID, models.MediaObjectStatusDeleting).
					Updates(map[string]interface{}{

						"status": models.MediaObjectStatusUploading,

						"last_error": "",

						"next_retry_at": nil,

						"expires_at": expiresAt,

						"updated_at": now,
					}).Error; err != nil {

					return nil, err

				}

				existing.Status = models.MediaObjectStatusUploading

				existing.LastError = ""

				existing.NextRetryAt = nil

				existing.ExpiresAt = &expiresAt

			}

			return &existing, nil

		}

		if !errors.Is(err, gorm.ErrRecordNotFound) {

			return nil, err

		}
	}
	item := &models.MediaObject{

		MediaID: uuid.NewString(),

		UserID: params.UserID,

		AdminID: params.AdminID,

		ClientRequestID: truncateMediaValue(requestID, 64),

		Category: truncateMediaValue(params.Category, 30),

		Provider: truncateMediaValue(params.Provider, 20),

		Bucket: truncateMediaValue(params.Bucket, 255),

		ObjectKey: truncateMediaValue(params.ObjectKey, 500),

		OriginalName: truncateMediaValue(params.OriginalName, 255),

		NormalizedExt: truncateMediaValue(params.NormalizedExt, 20),

		DeclaredMIME: truncateMediaValue(params.DeclaredMIME, 120),

		DetectedMIME: truncateMediaValue(params.DetectedMIME, 120),

		SizeBytes: params.SizeBytes,

		ExpectedSHA256: truncateMediaValue(params.ExpectedSHA256, 64),

		UploadMode: truncateMediaValue(params.UploadMode, 20),

		RemoteUploadID: truncateMediaValue(params.RemoteUploadID, 512),

		PartSizeBytes: params.PartSizeBytes,

		Status: models.MediaObjectStatusUploading,

		ExpiresAt: timePointer(now.Add(defaultUnboundMediaTTL)),

		CreatedAt: now,

		UpdatedAt: now,
	}
	if err := db.Create(item).Error; err != nil {

		return nil, err
	}
	return item, nil
} // CompleteMediaUpload 将 uploading 原子推进到 uploaded；旧接口可选择直接进入 bound。 // 条件更新阻止迟到的完成请求复活已进入删除流程的对象。
func CompleteMediaUpload(db *gorm.DB, id uint64, url, checksum string, legacyAutoBind bool) error {
	if db == nil || id == 0 {

		return fmt.Errorf("媒体上传记录无效")
	}
	updates := map[string]interface{}{

		"url": truncateMediaValue(url, 800),

		"checksum_sha256": truncateMediaValue(checksum, 64),

		"status": models.MediaObjectStatusUploaded,

		"remote_upload_id": "",

		"last_error": "",

		"updated_at": time.Now(),
	}
	if legacyAutoBind {

		now := time.Now()

		updates["status"] = models.MediaObjectStatusBound

		updates["business_type"] = "legacy_upload"

		updates["reference_count"] = 1

		updates["expires_at"] = nil

		updates["bound_at"] = now
	}
	return db.Model(&models.MediaObject{}).
		Where("id = ? AND status = ?", id, models.MediaObjectStatusUploading).
		Updates(updates).Error
} // FailMediaUpload 不直接物理删除对象，而是转入 deleting 并交给清理任务重试。
func FailMediaUpload(db *gorm.DB, id uint64, err error) {
	if db == nil || id == 0 {

		return
	}
	message := "upload_failed"
	if err != nil {

		message = err.Error()
	}
	now := time.Now()
	_ = db.Model(&models.MediaObject{}).Where("id = ?", id).Updates(map[string]interface{}{

		"status": models.MediaObjectStatusDeleting,

		"last_error": truncateMediaValue(message, 512),

		"next_retry_at": now,

		"updated_at": now,
	}).Error
} // MessageMediaError 表示可以安全返回给客户端的媒体绑定校验错误。
type MessageMediaError struct {
	Message string
}

func (e *MessageMediaError) Error() string {
	return e.Message
} // IsMessageMediaError 判断错误是否属于客户端可修正的媒体绑定问题。
func IsMessageMediaError(err error) bool {
	var target *MessageMediaError
	return errors.As(err, &target)
} // ReserveMessageMedia 校验所有权、类型、有效期和单消息占用关系，并将对象锁定为 binding。 // 行锁保证同一媒体不能被两个并发消息同时绑定；业务消息持久化后必须调用 Commit， // 失败路径必须调用 Release，形成两阶段生命周期。
func ReserveMessageMedia(
	db *gorm.DB,
	userID uint64,
	messageID string,
	businessScopeID string,
	messageType int,
	content map[string]interface{},
	explicitMediaIDs []string) ([]string, error) {
	mediaIDs := collectMessageMediaIDs(messageType, content, explicitMediaIDs)
	if len(mediaIDs) == 0 {

		return nil, nil
	}
	expectedCategory := expectedMediaCategory(messageType)
	if expectedCategory == "" {

		return nil, &MessageMediaError{Message: "当前消息类型不能绑定上传文件"}
	}
	messageID = strings.TrimSpace(messageID)
	if messageID == "" {

		return nil, &MessageMediaError{Message: "媒体消息缺少消息幂等 ID"}
	}
	// 图片消息通常只有一个 media_id。使用带所有权、类型、状态和有效期条件的
	// 原子 UPDATE 取得业务所有权，可省去 BEGIN / SELECT FOR UPDATE / COMMIT
	// 三次额外往返；多媒体消息仍保留下面的事务路径以保证整组原子性。
	if len(mediaIDs) == 1 {
		if err := reserveSingleMessageMedia(
			db,
			userID,
			messageID,
			businessScopeID,
			messageType,
			expectedCategory,
			content,
			mediaIDs[0],
		); err != nil {
			return nil, err
		}
		return mediaIDs, nil
	}
	err := db.Transaction(func(tx *gorm.DB) error {

		for _, mediaID := range mediaIDs {
			var item models.MediaObject

			// 锁住对象后再检查状态与 business_id，避免“先检查后占用”的并发窗口。

			if err := tx.Clauses(clause.Locking{Strength: "UPDATE"}).
				Where("media_id = ?", mediaID).
				First(&item).Error; err != nil {

				if errors.Is(err, gorm.ErrRecordNotFound) {

					return &MessageMediaError{Message: "上传文件不存在或已过期"}

				}

				return err

			}

			if item.UserID == 0 || item.UserID != userID {

				return &MessageMediaError{Message: "不能发送其他用户上传的文件"}

			}
			isMediaThumbnail := (messageType == models.MsgTypeImage ||

				messageType == models.MsgTypeVideo) &&

				item.Category == "image" &&

				messageThumbnailMediaID(content) == item.MediaID

			if item.Category != expectedCategory && !isMediaThumbnail {

				return &MessageMediaError{Message: "上传文件类型与消息类型不匹配"}

			}

			if item.ExpiresAt != nil && time.Now().After(*item.ExpiresAt) &&

				item.Status != models.MediaObjectStatusBound {

				return &MessageMediaError{Message: "上传文件已过期，请重新上传"}

			}

			switch item.Status {

			case models.MediaObjectStatusUploaded:

			case models.MediaObjectStatusBinding, models.MediaObjectStatusBound:

				if item.BusinessType != "message" || item.BusinessID != messageID {

					return &MessageMediaError{Message: "上传文件已经被其他消息使用"}

				}

			default:

				return &MessageMediaError{Message: "上传文件当前不可发送"}

			}

			if isMediaThumbnail {

				applyCanonicalMediaThumbnail(content, &item)

			} else {

				applyCanonicalMediaContent(messageType, content, &item)

			}

			if item.Status == models.MediaObjectStatusUploaded {

				if err := tx.Model(&models.MediaObject{}).Where("id = ?", item.ID).Updates(map[string]interface{}{

					"status": models.MediaObjectStatusBinding,

					"business_type": "message",

					"business_id": messageID,

					"business_scope_id": truncateMediaValue(businessScopeID, 64),

					"reference_count": 1,

					"expires_at": nil,

					"updated_at": time.Now(),
				}).Error; err != nil {

					return err

				}

			}

		}

		return nil
	})
	if err != nil {

		return nil, err
	}
	return mediaIDs, nil
}

func reserveSingleMessageMedia(
	db *gorm.DB,
	userID uint64,
	messageID string,
	businessScopeID string,
	messageType int,
	expectedCategory string,
	content map[string]interface{},
	mediaID string,
) error {
	now := time.Now()
	isMediaThumbnail := (messageType == models.MsgTypeImage || messageType == models.MsgTypeVideo) &&
		messageThumbnailMediaID(content) == mediaID
	cachedItem, cacheHit := uploadedMessageMediaFromFastCache(mediaID)

	query := db.Model(&models.MediaObject{}).
		Where("media_id = ? AND user_id = ? AND status = ?", mediaID, userID, models.MediaObjectStatusUploaded).
		Where("(expires_at IS NULL OR expires_at > ?)", now)
	if isMediaThumbnail {
		query = query.Where("category IN ?", []string{expectedCategory, "image"})
	} else {
		query = query.Where("category = ?", expectedCategory)
	}
	result := query.Updates(map[string]interface{}{
		"status":            models.MediaObjectStatusBinding,
		"business_type":     "message",
		"business_id":       messageID,
		"business_scope_id": truncateMediaValue(businessScopeID, 64),
		"reference_count":   1,
		"expires_at":        nil,
		"updated_at":        now,
	})
	if result.Error != nil {
		return result.Error
	}
	if result.RowsAffected == 1 && cacheHit {
		// The UPDATE above remains the security and lifecycle gate. The cache
		// only avoids the second MySQL round-trip needed to recover canonical
		// URL/object metadata for an upload completed by this API instance.
		cachedItem.Status = models.MediaObjectStatusBinding
		cachedItem.BusinessType = "message"
		cachedItem.BusinessID = messageID
		cachedItem.BusinessScopeID = truncateMediaValue(businessScopeID, 64)
		cachedItem.ReferenceCount = 1
		cachedItem.ExpiresAt = nil
		if isMediaThumbnail {
			applyCanonicalMediaThumbnail(content, &cachedItem)
		} else {
			applyCanonicalMediaContent(messageType, content, &cachedItem)
		}
		forgetUploadedMessageMedia(mediaID)
		return nil
	}

	var item models.MediaObject
	if err := db.Where("media_id = ?", mediaID).First(&item).Error; err != nil {
		if errors.Is(err, gorm.ErrRecordNotFound) {
			return &MessageMediaError{Message: "上传文件不存在或已过期"}
		}
		return err
	}
	if cacheHit {
		forgetUploadedMessageMedia(mediaID)
	}
	if item.UserID == 0 || item.UserID != userID {
		return &MessageMediaError{Message: "不能发送其他用户上传的文件"}
	}
	if item.Category != expectedCategory && !(isMediaThumbnail && item.Category == "image") {
		return &MessageMediaError{Message: "上传文件类型与消息类型不匹配"}
	}
	if item.ExpiresAt != nil && now.After(*item.ExpiresAt) &&
		item.Status != models.MediaObjectStatusBound {
		return &MessageMediaError{Message: "上传文件已过期，请重新上传"}
	}
	switch item.Status {
	case models.MediaObjectStatusBinding, models.MediaObjectStatusBound:
		if item.BusinessType != "message" || item.BusinessID != messageID {
			return &MessageMediaError{Message: "上传文件已经被其他消息使用"}
		}
	case models.MediaObjectStatusUploaded:
		// 条件 UPDATE 没有取得对象，通常是有效期或并发状态刚发生变化。
		return &MessageMediaError{Message: "上传文件当前不可发送"}
	default:
		return &MessageMediaError{Message: "上传文件当前不可发送"}
	}

	if isMediaThumbnail {
		applyCanonicalMediaThumbnail(content, &item)
	} else {
		applyCanonicalMediaContent(messageType, content, &item)
	}
	return nil
}

// CommitMessageMedia 在消息已持久化后将预留对象推进为长期 bound 状态。
func CommitMessageMedia(db *gorm.DB, mediaIDs []string, messageID string) error {
	if db == nil || len(mediaIDs) == 0 {

		return nil
	}
	now := time.Now()
	return db.Model(&models.MediaObject{}).
		Where("media_id IN ? AND business_type = ? AND business_id = ? AND status IN ?",

			mediaIDs, "message", messageID, []string{models.MediaObjectStatusBinding, models.MediaObjectStatusBound}).
		Updates(map[string]interface{}{

			"status": models.MediaObjectStatusBound,

			"bound_at": now,

			"updated_at": now,
		}).Error
}

// CommitMessageMediaBatch 将已经成功持久化消息对应的媒体对象一次推进为 bound。
// 调用方必须只传入 ReserveMessageMedia 成功且业务消息已经提交的 media_id。
func CommitMessageMediaBatch(db *gorm.DB, mediaIDs []string) error {
	if db == nil || len(mediaIDs) == 0 {
		return nil
	}
	uniqueIDs := make([]string, 0, len(mediaIDs))
	seen := make(map[string]struct{}, len(mediaIDs))
	for _, mediaID := range mediaIDs {
		mediaID = strings.TrimSpace(mediaID)
		if mediaID == "" {
			continue
		}
		if _, exists := seen[mediaID]; exists {
			continue
		}
		seen[mediaID] = struct{}{}
		uniqueIDs = append(uniqueIDs, mediaID)
	}
	if len(uniqueIDs) == 0 {
		return nil
	}
	now := time.Now()
	return db.Model(&models.MediaObject{}).
		Where("media_id IN ? AND status = ?", uniqueIDs, models.MediaObjectStatusBinding).
		Updates(map[string]interface{}{
			"status":     models.MediaObjectStatusBound,
			"bound_at":   now,
			"updated_at": now,
		}).Error
}

// ReleaseMessageMedia 回滚尚未提交的 binding，并恢复未绑定对象 TTL 供后台回收。
func ReleaseMessageMedia(db *gorm.DB, mediaIDs []string, messageID string) {
	if db == nil || len(mediaIDs) == 0 {

		return
	}
	now := time.Now()
	expiresAt := now.Add(defaultUnboundMediaTTL)
	_ = db.Model(&models.MediaObject{}).
		Where("media_id IN ? AND business_type = ? AND business_id = ? AND status = ?",

			mediaIDs, "message", messageID, models.MediaObjectStatusBinding).
		Updates(map[string]interface{}{

			"status": models.MediaObjectStatusUploaded,

			"business_type": "",

			"business_id": "",

			"business_scope_id": "",

			"reference_count": 0,

			"expires_at": expiresAt,

			"updated_at": now,
		}).Error
} // MarkMessageMediaForDeletion releases every durable media object owned by a // globally removed message. The business ID is stable across retries, so the // operation is idempotent even when MongoDB already contains the terminal // revoked state.
func MarkMessageMediaForDeletion(db *gorm.DB, messageID string) error {
	if db == nil || strings.TrimSpace(messageID) == "" {

		return nil
	}
	return markBoundMessageMediaForDeletion(

		db,

		"business_type = ? AND business_id = ?",

		"message",

		strings.TrimSpace(messageID),
	)
} // MarkChatMediaForDeletion releases media after messages are physically // removed for every participant. A per-user "delete for me" must not call this // function because the message remains visible to other participants.
func MarkChatMediaForDeletion(db *gorm.DB, chatID string, cutoff time.Time) error {
	if db == nil || strings.TrimSpace(chatID) == "" {

		return nil
	}
	query := "business_type = ? AND business_scope_id = ?"
	args := []interface{}{"message", strings.TrimSpace(chatID)}
	if !cutoff.IsZero() {

		query += " AND bound_at IS NOT NULL AND bound_at <= ?"

		args = append(args, cutoff)
	}
	return markBoundMessageMediaForDeletion(db, query, args...)
}
func markBoundMessageMediaForDeletion(db *gorm.DB, scopeQuery string, scopeArgs ...interface{}) error {
	now := time.Now()
	return db.Transaction(func(tx *gorm.DB) error {
		var rows []models.MediaObject

		query := tx.Clauses(clause.Locking{Strength: "UPDATE"}).
			Where(scopeQuery, scopeArgs...).
			Where("status IN ?", []string{

				models.MediaObjectStatusBinding,

				models.MediaObjectStatusBound,
			})

		if err := query.Find(&rows).Error; err != nil {

			return err

		}

		for i := range rows {

			item := &rows[i]

			// The current schema stores one business binding per object. Until

			// shared-reference rows are normalized into a separate binding

			// table, never guess which reference should be decremented: keeping

			// a shared object is safer than deleting media still in use.

			if item.ReferenceCount > 1 {

				continue

			}

			if err := tx.Model(&models.MediaObject{}).
				Where("id = ? AND status IN ?", item.ID, []string{

					models.MediaObjectStatusBinding,

					models.MediaObjectStatusBound,
				}).
				Updates(map[string]interface{}{

					"status": models.MediaObjectStatusDeleting,

					"reference_count": 0,

					"expires_at": nil,

					"next_retry_at": now,

					"last_error": "",

					"updated_at": now,
				}).Error; err != nil {

				return err

			}

		}

		return nil
	})
}
func MarkUserMediaForDeletion(db *gorm.DB, userID uint64) {
	if db == nil || userID == 0 {

		return
	}
	now := time.Now()
	_ = db.Model(&models.MediaObject{}).
		Where("user_id = ? AND status NOT IN ?", userID, []string{

			models.MediaObjectStatusDeleted,

			models.MediaObjectStatusDeleting,
		}).
		Updates(map[string]interface{}{

			"status": models.MediaObjectStatusDeleting,

			"next_retry_at": now,

			"updated_at": now,
		}).Error
}
func MarkMediaForDeletion(db *gorm.DB, userID uint64, mediaID string) {
	if db == nil || userID == 0 || strings.TrimSpace(mediaID) == "" {

		return
	}
	now := time.Now()
	_ = db.Model(&models.MediaObject{}).
		Where("user_id = ? AND media_id = ? AND status = ?", userID, mediaID, models.MediaObjectStatusBound).
		Updates(map[string]interface{}{

			"status": models.MediaObjectStatusDeleting,

			"next_retry_at": now,

			"updated_at": now,
		}).Error
}
func collectMessageMediaIDs(messageType int, content map[string]interface{}, explicit []string) []string {
	seen := map[string]struct{}{}
	out := make([]string, 0, len(explicit)+1)
	add := func(value string) {

		value = strings.TrimSpace(value)

		if value == "" {

			return

		}

		if _, ok := seen[value]; ok {

			return

		}

		seen[value] = struct{}{}
		out = append(out, value)
	}
	for _, value := range explicit {

		add(value)
	}
	var key string
	switch messageType {
	case models.MsgTypeImage, models.MsgTypeVideo:

		key = "media"
	case models.MsgTypeVoice:

		key = "voice"
	case models.MsgTypeFile:

		key = "file"
	}
	if nested, ok := content[key].(map[string]interface{}); ok {

		if value, ok := nested["media_id"].(string); ok {

			add(value)

		}

		if messageType == models.MsgTypeImage || messageType == models.MsgTypeVideo {

			if value, ok := nested["thumbnail_media_id"].(string); ok {

				add(value)

			}

		}
	}
	return out
}
func messageThumbnailMediaID(content map[string]interface{}) string {
	nested, ok := content["media"].(map[string]interface{})
	if !ok {

		return ""
	}
	value, _ := nested["thumbnail_media_id"].(string)
	return strings.TrimSpace(value)
}
func applyCanonicalMediaThumbnail(content map[string]interface{}, item *models.MediaObject) {
	nested, ok := content["media"].(map[string]interface{})
	if !ok {

		nested = map[string]interface{}{}

		content["media"] = nested
	}
	nested["thumbnail_media_id"] = item.MediaID
	nested["thumbnail"] = item.URL
}
func expectedMediaCategory(messageType int) string {
	switch messageType {
	case models.MsgTypeImage:

		return "image"
	case models.MsgTypeVideo:

		return "video"
	case models.MsgTypeVoice:

		return "voice"
	case models.MsgTypeFile:

		return "file"
	default:

		return ""
	}
}
func applyCanonicalMediaContent(messageType int, content map[string]interface{}, item *models.MediaObject) {
	if content == nil || item == nil {

		return
	}
	var key string
	switch messageType {
	case models.MsgTypeImage, models.MsgTypeVideo:

		key = "media"
	case models.MsgTypeVoice:

		key = "voice"
	case models.MsgTypeFile:

		key = "file"
	default:

		return
	}
	nested, ok := content[key].(map[string]interface{})
	if !ok {

		nested = map[string]interface{}{}

		content[key] = nested
	}
	nested["media_id"] = item.MediaID
	nested["url"] = item.URL
	nested["size"] = float64(item.SizeBytes)
	if key != "voice" {

		nested["mime_type"] = item.DetectedMIME
	}
}
func truncateMediaValue(value string, limit int) string {
	value = strings.TrimSpace(value)
	if limit <= 0 || len(value) <= limit {

		return value
	}
	return value[:limit]
}
func timePointer(value time.Time) *time.Time {
	return &value
} // MediaObjectCleanupService 异步回收过期、上传失败或业务解绑后的底层对象。
type MediaObjectCleanupService struct {
	db        *gorm.DB
	uploadDir string
	ticker    *time.Ticker
	stopCh    chan struct{}
	stopOnce  sync.Once
} // NewMediaObjectCleanupService 创建媒体对象清理服务。
func NewMediaObjectCleanupService(db *gorm.DB, uploadDir string) *MediaObjectCleanupService {
	return &MediaObjectCleanupService{

		db: db,

		uploadDir: strings.TrimSpace(uploadDir),

		stopCh: make(chan struct{}),
	}
}
func (s *MediaObjectCleanupService) Start() {
	if s == nil || s.db == nil || s.ticker != nil {

		return
	}
	s.ticker = time.NewTicker(10 * time.Minute)
	go func() {

		timer := time.NewTimer(time.Minute)

		defer timer.Stop()

		select {

		case <-timer.C:

			s.runOnce()

		case <-s.stopCh:

			return

		}

		for {

			select {

			case <-s.ticker.C:

				s.runOnce()

			case <-s.stopCh:

				return

			}

		}
	}()
}
func (s *MediaObjectCleanupService) Stop() {
	if s == nil {

		return
	}
	s.stopOnce.Do(func() {

		if s.ticker != nil {

			s.ticker.Stop()

		}

		close(s.stopCh)
	})
}
func (s *MediaObjectCleanupService) runOnce() {
	now := time.Now()
	// 先把到期对象标记为 deleting，再分批执行外部删除；
	// 数据库状态是可恢复检查点，进程退出不会丢失待清理任务。
	_ = s.db.Model(&models.MediaObject{}).
		Where("(status = ? AND expires_at IS NOT NULL AND expires_at <= ?) OR (status = ? AND created_at <= ?)",

			models.MediaObjectStatusUploaded, now,

			models.MediaObjectStatusUploading, now.Add(-staleUploadingTTL)).
		Updates(map[string]interface{}{

			"status": models.MediaObjectStatusDeleting,

			"next_retry_at": now,

			"updated_at": now,
		}).Error
	var rows []models.MediaObject
	if err := s.db.
		Where("status = ? AND (next_retry_at IS NULL OR next_retry_at <= ?)", models.MediaObjectStatusDeleting, now).
		Order("id ASC").
		Limit(100).
		Find(&rows).Error; err != nil {

		log.Printf("[MediaCleanup] query failed: %v", err)

		return
	}
	for i := range rows {

		s.deleteOne(&rows[i])
	}
}
func (s *MediaObjectCleanupService) deleteOne(item *models.MediaObject) {
	ctx, cancel := context.WithTimeout(context.Background(), 30*time.Second)
	defer cancel()
	err := s.deleteStoredObject(ctx, item)
	now := time.Now()
	if err == nil {

		// 云端 Delete 和数据库更新不原子；重复删除必须按幂等处理，

		// 因而本地不存在和云端对象已消失都视为清理成功。

		if dbErr := s.db.Model(&models.MediaObject{}).Where("id = ?", item.ID).Updates(map[string]interface{}{

			"status": models.MediaObjectStatusDeleted,

			"deleted_at": now,

			"next_retry_at": nil,

			"last_error": "",

			"updated_at": now,
		}).Error; dbErr != nil {

			log.Printf("[MediaCleanup] mark deleted failed media_id=%s err=%v", item.MediaID, dbErr)

		}

		return
	}
	retryCount := item.RetryCount + 1
	next := now.Add(mediaCleanupBackoff(retryCount))
	if dbErr := s.db.Model(&models.MediaObject{}).Where("id = ?", item.ID).Updates(map[string]interface{}{

		"retry_count": retryCount,

		"last_error": truncateMediaValue(err.Error(), 512),

		"next_retry_at": next,

		"updated_at": now,
	}).Error; dbErr != nil {

		log.Printf("[MediaCleanup] mark retry failed media_id=%s err=%v", item.MediaID, dbErr)
	}
	log.Printf("[MediaCleanup] delete failed media_id=%s provider=%s retry=%d err=%v", item.MediaID, item.Provider, retryCount, err)
}
func (s *MediaObjectCleanupService) deleteStoredObject(ctx context.Context, item *models.MediaObject) error {
	if item.Provider == StorageProviderLocal {

		path, ok := localMediaObjectPath(s.uploadDir, item.ObjectKey)

		if !ok {

			return fmt.Errorf("invalid local media object path")

		}

		if err := os.Remove(path); err != nil && !errors.Is(err, os.ErrNotExist) {

			return err

		}

		return nil
	}
	var yamlCfg config.StorageConfig
	if config.GlobalConfig != nil {

		yamlCfg = config.GlobalConfig.Storage
	}
	cfg := LoadStorageForRuntime(s.db, yamlCfg)
	cfg.Provider = item.Provider
	if item.Provider == StorageProviderS3 && strings.TrimSpace(item.RemoteUploadID) != "" {

		if err := AbortS3MultipartUpload(ctx, cfg, item.ObjectKey, item.RemoteUploadID); err != nil {

			// The upload can already be completed or removed by S3 lifecycle.

			// Deleting the final key is still safe and keeps cleanup idempotent.

			log.Printf("[MediaCleanup] abort multipart media_id=%s err=%v", item.MediaID, err)

		}
	}
	return DeleteObject(ctx, cfg, item.ObjectKey)
}
func localMediaObjectPath(uploadDir, objectKey string) (string, bool) {
	if uploadDir == "" {

		uploadDir = "./uploads"
	}
	cleanKey, ok := cleanObjectKey(objectKey)
	if !ok || !strings.HasPrefix(cleanKey, "uploads/") {

		return "", false
	}
	relative := strings.TrimPrefix(cleanKey, "uploads/")
	baseAbs, err := filepath.Abs(uploadDir)
	if err != nil {

		return "", false
	}
	targetAbs, err := filepath.Abs(filepath.Join(baseAbs, filepath.FromSlash(relative)))
	if err != nil {

		return "", false
	}
	// 解析绝对路径后再次做 Rel 边界检查，防止 objectKey 中的 .. 逃逸上传目录。
	rel, err := filepath.Rel(baseAbs, targetAbs)
	if err != nil || rel == ".." || strings.HasPrefix(rel, ".."+string(os.PathSeparator)) || filepath.IsAbs(rel) {

		return "", false
	}
	return targetAbs, true
}
func mediaCleanupBackoff(retryCount int) time.Duration {
	switch retryCount {
	case 1:

		return time.Minute
	case 2:

		return 10 * time.Minute
	case 3:

		return time.Hour
	default:

		return 6 * time.Hour
	}
}
