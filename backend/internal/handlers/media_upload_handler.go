// 文件用途：实现后端 HTTP 接口的请求处理和统一响应。
// 核心逻辑：绑定参数，校验身份与权限，调用业务服务并持久化关键状态。

package handlers

import (
	"bytes"
	"context"
	"encoding/base64"
	"encoding/binary"
	"encoding/hex"
	"fmt"
	"github.com/gin-gonic/gin"
	"github.com/google/uuid"
	"gorm.io/gorm"
	"mime"
	"net/http"
	"path/filepath"
	"sort"
	"strings"
	"time"
	"unicode/utf8"
	"genericim/internal/config"
	"genericim/internal/models"
	"genericim/internal/services"
	"genericim/pkg/response"
)

const (
	directUploadSingleLimit = int64(100 * 1024 * 1024)
	directUploadPartSize    = int64(16 * 1024 * 1024)
	directUploadURLTTL      = 10 * time.Minute
	directAccessURLTTL      = 10 * time.Minute
	mediaAccessBatchLimit   = 200
) // MediaUploadHandler 管理客户端直传 S3 的会话、完成校验和受控访问地址。 // 客户端声明只用于初始化，文件是否可信以完成阶段读取到的 S3 元数据和文件内容为准。
type MediaUploadHandler struct {
	db *gorm.DB
} // NewMediaUploadHandler 创建媒体直传处理器。
func NewMediaUploadHandler(db *gorm.DB) *MediaUploadHandler {
	return &MediaUploadHandler{db: db}
}

type initMediaUploadRequest struct {
	ClientRequestID string `json:"client_request_id"`
	Category        string `json:"category"`
	FileName        string `json:"file_name"`
	Size            int64  `json:"size"`
	MIMEType        string `json:"mime_type"`
	ChecksumSHA256  string `json:"checksum_sha256"`
}

type batchMediaAccessRequest struct {
	MediaIDs []string `json:"media_ids"`
}

type batchMediaAccessItem struct {
	MediaID   string      `json:"media_id"`
	URL       string      `json:"url"`
	ExpiresAt interface{} `json:"expires_at"`
}

func (h *MediaUploadHandler) Init(c *gin.Context) {
	var req initMediaUploadRequest
	if err := c.ShouldBindJSON(&req); err != nil {

		response.BadRequest(c, "上传参数格式错误")

		return
	}
	user, ok := h.currentUser(c)
	if !ok {

		return
	}
	category, contentType, ext, err := normalizeDirectUploadMetadata(req.Category, req.FileName, req.MIMEType)
	if err != nil {

		response.BadRequest(c, err.Error())

		return
	}
	if req.Size <= 0 {

		response.BadRequest(c, "文件不能为空")

		return
	}
	if maxSize := getUploadLimitBytes(h.db, user.ID, category); req.Size > maxSize {

		response.BadRequest(c, fmt.Sprintf("文件大小不能超过%dMB", maxSize/1024/1024))

		return
	}
	checksum := strings.ToLower(strings.TrimSpace(req.ChecksumSHA256))
	if checksum != "" && !isSHA256Hex(checksum) {

		response.BadRequest(c, "checksum_sha256 格式错误")

		return
	}
	if category == "image" && checksum == "" {

		response.BadRequest(c, "图片直传必须提供 checksum_sha256")

		return
	}
	if category == "image" && !h.allowChatImageDirectUpload(c, user) {

		return
	}
	cfg := h.storageConfig()
	if services.NormalizeStorageProvider(cfg.Provider) != services.StorageProviderS3 {

		response.ErrorWithData(c, response.CodeDirectUploadStorageUnavailable, "当前未启用 Amazon S3 直传", gin.H{

			"reason": "storage_unavailable",

			"fallback": "proxy_upload",
		})

		return
	}
	if err := services.ValidateStorageConfig(cfg); err != nil {

		response.ErrorWithData(c, response.CodeDirectUploadStorageUnavailable, "Amazon S3 配置不可用", gin.H{

			"reason": "storage_unavailable",

			"fallback": "proxy_upload",
		})

		return
	}
	mode := "single"
	partSize := int64(0)
	if req.Size >= directUploadSingleLimit {

		mode = "multipart"

		partSize = directUploadPartSize
	}
	dateDir := time.Now().Format("2006/01/02")
	objectKey := buildUploadObjectKey(

		directUploadDirectory(category),

		dateDir,

		fmt.Sprintf("%s_%d%s", uuid.NewString()[:8], time.Now().UnixMilli(), ext),
	)
	dbStartedAt := time.Now()
	// client_request_id 是上传幂等键：网络重试返回同一任务，但不能换文件名、
	// MIME 或校验和复用，避免预签名地址被偷换成另一份内容。
	item, err := services.BeginMediaUpload(h.db, services.BeginMediaUploadParams{

		UserID: user.ID,

		ClientRequestID: strings.TrimSpace(req.ClientRequestID),

		Category: category,

		Provider: services.StorageProviderS3,

		Bucket: cfg.S3.Bucket,

		ObjectKey: objectKey,

		OriginalName: req.FileName,

		NormalizedExt: ext,

		DeclaredMIME: contentType,

		DetectedMIME: contentType,

		SizeBytes: req.Size,

		ExpectedSHA256: checksum,

		UploadMode: mode,

		PartSizeBytes: partSize,
	})
	services.RecordUploadStage("direct_init_db", dbStartedAt, err)
	if err != nil {

		response.BadRequest(c, err.Error())

		return
	}
	if item.Provider != services.StorageProviderS3 || (item.UploadMode != "" && item.UploadMode != mode) {

		response.Error(c, http.StatusConflict, "上传请求 ID 已被其他上传任务使用")

		return
	}
	if item.OriginalName != strings.TrimSpace(req.FileName) ||

		item.DeclaredMIME != contentType ||

		item.ExpectedSHA256 != checksum {

		response.Error(c, http.StatusConflict, "上传请求 ID 已被其他文件使用")

		return
	}
	if item.Status == models.MediaObjectStatusUploaded || item.Status == models.MediaObjectStatusBound {

		// Object completion is the client ACK boundary. Media processing can
		// download the full S3 object and run ffmpeg, so it must never hold this
		// request open or a successfully uploaded message appears to fail.
		response.Success(c, h.completedPayload(c.Request.Context(), cfg, item))

		return
	}
	if item.Status != models.MediaObjectStatusUploading {

		response.Error(c, http.StatusConflict, "上传任务当前不可继续")

		return
	}
	if mode == "multipart" {

		if strings.TrimSpace(item.RemoteUploadID) == "" {

			// S3 和 MySQL 无法组成分布式事务。若 S3 会话创建后数据库落库失败，

			// 立即 Abort 作为补偿，后台清理仍会处理遗漏的上传任务。

			uploadID, createErr := services.CreateS3MultipartUpload(c.Request.Context(), cfg, item.ObjectKey, contentType)

			if createErr != nil {

				services.FailMediaUpload(h.db, item.ID, createErr)

				response.Error(c, http.StatusServiceUnavailable, "创建 S3 分片上传失败")

				return

			}

			if err := h.db.Model(&models.MediaObject{}).Where("id = ? AND status = ?", item.ID, models.MediaObjectStatusUploading).
				Updates(map[string]interface{}{

					"remote_upload_id": uploadID,

					"upload_mode": mode,

					"part_size_bytes": partSize,

					"updated_at": time.Now(),
				}).Error; err != nil {

				_ = services.AbortS3MultipartUpload(context.Background(), cfg, item.ObjectKey, uploadID)

				response.ServerError(c, "保存分片上传任务失败")

				return

			}

			item.RemoteUploadID = uploadID

			item.UploadMode = mode

			item.PartSizeBytes = partSize

		}
		payload := h.uploadPayload(item)

		payload["part_count"] = directUploadPartCount(item.SizeBytes, item.PartSizeBytes)

		response.Success(c, payload)

		return
	}
	presigned, err := services.PresignS3PutObject(

		c.Request.Context(), cfg, item.ObjectKey, item.SizeBytes, item.DeclaredMIME, item.ExpectedSHA256, directUploadURLTTL,
	)
	if err != nil {

		response.Error(c, http.StatusServiceUnavailable, "生成 S3 上传地址失败")

		return
	}
	payload := h.uploadPayload(item)
	payload["put_url"] = presigned.URL
	payload["headers"] = presigned.Headers
	payload["url_expires_at"] = presigned.ExpiresAt
	response.Success(c, payload)
}
func (h *MediaUploadHandler) allowChatImageDirectUpload(c *gin.Context, user *models.User) bool {
	cfg := services.LoadChatImageDirectUploadConfig(h.db)
	if !cfg.Enabled {

		response.ErrorWithData(c, response.CodeDirectUploadDisabled, "聊天图片直传未启用", gin.H{

			"reason": "disabled",

			"fallback": "proxy_upload",
		})

		return false
	}
	platform := services.NormalizeDirectUploadPlatform(c.GetHeader("X-Client-Platform"))
	if !services.IsDirectUploadPlatformAllowed(platform, cfg.Platforms) {

		response.ErrorWithData(c, response.CodeDirectUploadPlatformDisabled, "当前客户端平台未启用图片直传", gin.H{

			"reason": "platform_disabled",

			"platform": platform,

			"fallback": "proxy_upload",
		})

		return false
	}
	if !services.IsUserInDirectUploadRollout(user.UUID, cfg.RolloutPercent) {

		response.ErrorWithData(c, response.CodeDirectUploadRolloutExcluded, "当前账号未进入图片直传灰度", gin.H{

			"reason": "rollout_excluded",

			"fallback": "proxy_upload",
		})

		return false
	}
	return true
}

type presignPartsRequest struct {
	PartNumbers []int32 `json:"part_numbers"`
}

func (h *MediaUploadHandler) PresignParts(c *gin.Context) {
	item, cfg, ok := h.ownedUploadingItem(c)
	if !ok {

		return
	}
	if item.UploadMode != "multipart" || strings.TrimSpace(item.RemoteUploadID) == "" {

		response.BadRequest(c, "当前任务不是分片上传")

		return
	}
	var req presignPartsRequest
	if err := c.ShouldBindJSON(&req); err != nil || len(req.PartNumbers) == 0 || len(req.PartNumbers) > 100 {

		response.BadRequest(c, "每次需申请 1 到 100 个分片地址")

		return
	}
	maxPart := directUploadPartCount(item.SizeBytes, item.PartSizeBytes)
	seen := make(map[int32]struct{}, len(req.PartNumbers))
	parts := make([]gin.H, 0, len(req.PartNumbers))
	for _, number := range req.PartNumbers {

		if number < 1 || int(number) > maxPart {

			response.BadRequest(c, "分片编号超出范围")

			return

		}

		if _, exists := seen[number]; exists {

			continue

		}

		seen[number] = struct{}{}
		presigned, err := services.PresignS3UploadPart(

			c.Request.Context(), cfg, item.ObjectKey, item.RemoteUploadID, number, directUploadURLTTL,
		)

		if err != nil {

			response.Error(c, http.StatusServiceUnavailable, "生成 S3 分片地址失败")

			return

		}
		parts = append(parts, gin.H{

			"part_number": number,

			"put_url": presigned.URL,

			"headers": presigned.Headers,

			"url_expires_at": presigned.ExpiresAt,
		})
	}
	response.Success(c, gin.H{"upload_id": item.MediaID, "parts": parts})
}
func (h *MediaUploadHandler) Status(c *gin.Context) {
	item, cfg, ok := h.ownedItem(c)
	if !ok {

		return
	}
	payload := h.uploadPayload(item)
	if item.Status == models.MediaObjectStatusUploaded || item.Status == models.MediaObjectStatusBound {

		response.Success(c, h.completedPayload(c.Request.Context(), cfg, item))

		return
	}
	if item.UploadMode == "multipart" && strings.TrimSpace(item.RemoteUploadID) != "" {

		parts, err := services.ListS3MultipartParts(c.Request.Context(), cfg, item.ObjectKey, item.RemoteUploadID)

		if err != nil {

			response.Error(c, http.StatusServiceUnavailable, "读取 S3 分片状态失败")

			return

		}

		payload["uploaded_parts"] = parts

		payload["part_count"] = directUploadPartCount(item.SizeBytes, item.PartSizeBytes)
	}
	response.Success(c, payload)
}
func (h *MediaUploadHandler) Complete(c *gin.Context) {
	item, cfg, ok := h.ownedItem(c)
	if !ok {

		return
	}
	services.RecordUploadStage("direct_client_upload_wait", item.CreatedAt, nil)
	if item.Status == models.MediaObjectStatusUploaded || item.Status == models.MediaObjectStatusBound {

		response.Success(c, h.completedPayload(c.Request.Context(), cfg, item))

		return
	}
	if item.Status != models.MediaObjectStatusUploading {

		response.Error(c, http.StatusConflict, "上传任务当前不可完成")

		return
	}
	var info services.S3ObjectInfo
	var err error
	haveObjectInfo := false
	if item.UploadMode == "multipart" {

		parts, err := services.ListS3MultipartParts(c.Request.Context(), cfg, item.ObjectKey, item.RemoteUploadID)

		if err != nil {

			// S3 removes the multipart upload ID after a successful complete.

			// If the process crashed before updating MySQL, the final object is

			// authoritative and lets a retry finish idempotently.

			// 分片合并成功后 S3 会删除 upload ID；若进程恰好在更新 MySQL 前退出，

			// 最终对象的存在即为恢复依据，使 Complete 重试能够幂等收敛。

			info, err = services.HeadS3Object(c.Request.Context(), cfg, item.ObjectKey)

			if err != nil {

				response.Error(c, http.StatusServiceUnavailable, "读取 S3 分片状态失败")

				return

			}
			haveObjectInfo = true

		} else {

			if err := validateCompletedParts(item, parts); err != nil {

				response.BadRequest(c, err.Error())

				return

			}

			sort.Slice(parts, func(i, j int) bool { return parts[i].PartNumber < parts[j].PartNumber })

			if err := services.CompleteS3MultipartUpload(

				c.Request.Context(), cfg, item.ObjectKey, item.RemoteUploadID, parts,
			); err != nil {

				response.Error(c, http.StatusServiceUnavailable, "合并 S3 分片失败")

				return

			}

		}
	}
	if !haveObjectInfo {

		info, err = services.HeadS3Object(c.Request.Context(), cfg, item.ObjectKey)

		if err != nil {

			response.BadRequest(c, "S3 中尚未找到完整文件")

			return

		}
	}
	// Complete is the direct-upload ACK boundary and must stay metadata-only.
	// For single PUTs, PresignS3PutObject signs the expected SHA-256 into
	// X-Amz-Checksum-Sha256, so S3 verifies the body while accepting the PUT.
	// HeadObject verifies the durable size and MIME metadata.
	//
	// Downloading the object again here for a checksum, signature, thumbnail or
	// image-resource probe defeats direct upload, consumes server bandwidth and
	// can outlive the reverse-proxy timeout. Deeper scanning belongs in an
	// asynchronous quarantine/processing worker after this durable ACK.
	if err := validateDirectObject(item, info); err != nil {

		services.FailMediaUpload(h.db, item.ID, err)

		response.BadRequest(c, err.Error())

		return
	}
	checksum := directObjectChecksum(item, info)
	url := services.StorageObjectPublicURL(cfg, item.ObjectKey)
	dbStartedAt := time.Now()
	if err := services.CompleteMediaUpload(h.db, item.ID, url, checksum, false); err != nil {

		services.RecordUploadStage("direct_complete_db", dbStartedAt, err)

		response.ServerError(c, "保存上传结果失败")

		return
	}
	services.RememberUploadedMessageMedia(item, url, checksum)
	services.RecordUploadStage("direct_complete_db", dbStartedAt, nil)
	item.URL = url
	item.ChecksumSHA256 = checksum
	item.Status = models.MediaObjectStatusUploaded
	// Return the durable uploaded object immediately. Synchronous thumbnailing
	// or transcoding turns direct upload back into a server-side full download
	// and regularly exceeds the reverse-proxy timeout for videos.
	response.Success(c, h.completedPayload(c.Request.Context(), cfg, item))
}
func (h *MediaUploadHandler) Abort(c *gin.Context) {
	item, cfg, ok := h.ownedItem(c)
	if !ok {

		return
	}
	if item.Status == models.MediaObjectStatusDeleted {

		response.Success(c, gin.H{"upload_id": item.MediaID, "status": item.Status})

		return
	}
	if item.Status == models.MediaObjectStatusBound || item.Status == models.MediaObjectStatusBinding {

		// binding/bound 表示业务消息已经取得所有权，上传接口不能再删除底层对象。

		response.Error(c, http.StatusConflict, "已发送的媒体不能取消上传")

		return
	}
	var err error
	if item.UploadMode == "multipart" && strings.TrimSpace(item.RemoteUploadID) != "" && item.Status == models.MediaObjectStatusUploading {

		err = services.AbortS3MultipartUpload(c.Request.Context(), cfg, item.ObjectKey, item.RemoteUploadID)
	} else {

		err = services.DeleteObject(c.Request.Context(), cfg, item.ObjectKey)
	}
	if err != nil {

		services.FailMediaUpload(h.db, item.ID, err)

		response.Error(c, http.StatusServiceUnavailable, "取消上传失败，后台将继续清理")

		return
	}
	now := time.Now()
	if err := h.db.Model(&models.MediaObject{}).Where("id = ?", item.ID).Updates(map[string]interface{}{

		"status": models.MediaObjectStatusDeleted,

		"deleted_at": now,

		"next_retry_at": nil,

		"remote_upload_id": "",

		"last_error": "",

		"updated_at": now,
	}).Error; err != nil {

		response.ServerError(c, "更新上传状态失败")

		return
	}
	response.Success(c, gin.H{"upload_id": item.MediaID, "status": models.MediaObjectStatusDeleted})
}
func (h *MediaUploadHandler) AccessURL(c *gin.Context) {
	user, ok := h.currentUser(c)
	if !ok {

		return
	}
	var item models.MediaObject
	if err := h.db.Where("media_id = ?", strings.TrimSpace(c.Param("id"))).First(&item).Error; err != nil {

		response.Error(c, http.StatusNotFound, "媒体文件不存在")

		return
	}
	if item.Status != models.MediaObjectStatusUploaded &&

		item.Status != models.MediaObjectStatusBinding &&

		item.Status != models.MediaObjectStatusBound {

		response.Error(c, http.StatusNotFound, "媒体文件不可访问")

		return
	}
	allowed := item.UserID == user.ID
	// 非上传者只能凭当前会话成员关系访问消息媒体；短时预签名 URL
	// 将授权窗口限制在 directAccessURLTTL 内，成员关系变化后需重新鉴权。
	if !allowed && item.BusinessType == "message" && strings.TrimSpace(item.BusinessScopeID) != "" {
		var chat models.Chat

		if err := h.db.Where("uuid = ?", item.BusinessScopeID).Select("id").First(&chat).Error; err == nil {
			var count int64

			_ = h.db.Model(&models.ChatMember{}).
				Where("chat_id = ? AND user_id = ?", chat.ID, user.ID).
				Count(&count).Error

			allowed = count > 0

		}
	}
	if !allowed {

		response.Error(c, http.StatusForbidden, "无权访问该媒体文件")

		return
	}
	if item.Provider != services.StorageProviderS3 {

		response.Success(c, gin.H{"media_id": item.MediaID, "url": item.URL, "expires_at": nil})

		return
	}
	cfg := h.storageConfig()
	cfg.Provider = services.StorageProviderS3
	presigned, err := services.PresignS3GetObject(

		c.Request.Context(), cfg, item.ObjectKey, item.OriginalName, directAccessURLTTL,
	)
	if err != nil {

		response.Error(c, http.StatusServiceUnavailable, "生成媒体访问地址失败")

		return
	}
	response.Success(c, gin.H{

		"media_id": item.MediaID,

		"url": presigned.URL,

		"expires_at": presigned.ExpiresAt,
	})
}

// BatchAccessURLs resolves a whole active message window with one authorization
// request. This prevents image-heavy groups from hitting the global API rate
// limiter with one access-url request per message.
func (h *MediaUploadHandler) BatchAccessURLs(c *gin.Context) {
	user, ok := h.currentUser(c)
	if !ok {
		return
	}
	var req batchMediaAccessRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		response.BadRequest(c, "媒体访问参数格式错误")
		return
	}
	mediaIDs := normalizeMediaAccessIDs(req.MediaIDs)
	if len(mediaIDs) == 0 {
		response.BadRequest(c, "媒体 ID 不能为空")
		return
	}
	if len(mediaIDs) > mediaAccessBatchLimit {
		response.BadRequest(c, fmt.Sprintf("单次最多获取%d个媒体访问地址", mediaAccessBatchLimit))
		return
	}

	var items []models.MediaObject
	if err := h.db.
		Where("media_id IN ? AND status IN ?", mediaIDs, []string{
			models.MediaObjectStatusUploaded,
			models.MediaObjectStatusBinding,
			models.MediaObjectStatusBound,
		}).
		Find(&items).Error; err != nil {
		response.ServerError(c, "查询媒体文件失败")
		return
	}

	scopeIDs := make([]string, 0)
	scopeSeen := make(map[string]struct{})
	for i := range items {
		item := &items[i]
		scopeID := strings.TrimSpace(item.BusinessScopeID)
		if item.UserID == user.ID || item.BusinessType != "message" || scopeID == "" {
			continue
		}
		if _, exists := scopeSeen[scopeID]; exists {
			continue
		}
		scopeSeen[scopeID] = struct{}{}
		scopeIDs = append(scopeIDs, scopeID)
	}
	allowedScopes := make(map[string]struct{}, len(scopeIDs))
	if len(scopeIDs) > 0 {
		var memberScopes []string
		if err := h.db.Table("chats").
			Select("chats.uuid").
			Joins("JOIN chat_members ON chat_members.chat_id = chats.id").
			Where("chat_members.user_id = ? AND chats.uuid IN ?", user.ID, scopeIDs).
			Pluck("chats.uuid", &memberScopes).Error; err != nil {
			response.ServerError(c, "校验媒体访问权限失败")
			return
		}
		for _, scopeID := range memberScopes {
			allowedScopes[scopeID] = struct{}{}
		}
	}

	cfg := h.storageConfig()
	cfg.Provider = services.StorageProviderS3
	byID := make(map[string]*models.MediaObject, len(items))
	for i := range items {
		byID[items[i].MediaID] = &items[i]
	}
	resolved := make([]batchMediaAccessItem, 0, len(items))
	for _, mediaID := range mediaIDs {
		item := byID[mediaID]
		if item == nil {
			continue
		}
		allowed := item.UserID == user.ID
		if !allowed && item.BusinessType == "message" {
			_, allowed = allowedScopes[strings.TrimSpace(item.BusinessScopeID)]
		}
		if !allowed {
			continue
		}
		if item.Provider != services.StorageProviderS3 {
			resolved = append(resolved, batchMediaAccessItem{
				MediaID: item.MediaID, URL: item.URL, ExpiresAt: nil,
			})
			continue
		}
		presigned, err := services.PresignS3GetObject(
			c.Request.Context(), cfg, item.ObjectKey, item.OriginalName, directAccessURLTTL,
		)
		if err != nil {
			continue
		}
		resolved = append(resolved, batchMediaAccessItem{
			MediaID: item.MediaID, URL: presigned.URL, ExpiresAt: presigned.ExpiresAt,
		})
	}
	response.Success(c, gin.H{"items": resolved})
}

func normalizeMediaAccessIDs(values []string) []string {
	result := make([]string, 0, len(values))
	seen := make(map[string]struct{}, len(values))
	for _, value := range values {
		mediaID := strings.TrimSpace(value)
		if mediaID == "" {
			continue
		}
		if _, exists := seen[mediaID]; exists {
			continue
		}
		seen[mediaID] = struct{}{}
		result = append(result, mediaID)
	}
	return result
}

func (h *MediaUploadHandler) currentUser(c *gin.Context) (*models.User, bool) {
	userUUID := strings.TrimSpace(c.GetString("user_id"))
	var user models.User
	if userUUID == "" || h.db.Where("uuid = ?", userUUID).First(&user).Error != nil {

		response.Error(c, http.StatusUnauthorized, "用户未登录")

		return nil, false
	}
	return &user, true
}
func (h *MediaUploadHandler) storageConfig() config.StorageConfig {
	var yamlCfg config.StorageConfig
	if config.GlobalConfig != nil {

		yamlCfg = config.GlobalConfig.Storage
	}
	return services.LoadStorageForRuntime(h.db, yamlCfg)
}
func (h *MediaUploadHandler) ownedItem(c *gin.Context) (*models.MediaObject, config.StorageConfig, bool) {
	user, ok := h.currentUser(c)
	if !ok {

		return nil, config.StorageConfig{}, false
	}
	var item models.MediaObject
	// 所有状态、完成和取消操作都同时限定 media_id 与 user_id，
	// 防止仅凭可猜测/泄露的媒体 ID 操作其他用户的上传会话。
	if err := h.db.Where("media_id = ? AND user_id = ?", strings.TrimSpace(c.Param("id")), user.ID).
		First(&item).Error; err != nil {

		response.Error(c, http.StatusNotFound, "上传任务不存在")

		return nil, config.StorageConfig{}, false
	}
	cfg := h.storageConfig()
	cfg.Provider = item.Provider
	return &item, cfg, true
}
func (h *MediaUploadHandler) ownedUploadingItem(c *gin.Context) (*models.MediaObject, config.StorageConfig, bool) {
	item, cfg, ok := h.ownedItem(c)
	if !ok {

		return nil, config.StorageConfig{}, false
	}
	if item.Status != models.MediaObjectStatusUploading {

		response.Error(c, http.StatusConflict, "上传任务当前不可继续")

		return nil, config.StorageConfig{}, false
	}
	return item, cfg, true
}
func (h *MediaUploadHandler) uploadPayload(item *models.MediaObject) gin.H {
	return gin.H{

		"upload_id": item.MediaID,

		"media_id": item.MediaID,

		"mode": item.UploadMode,

		"status": item.Status,

		"category": item.Category,

		"file_name": item.OriginalName,

		"size": item.SizeBytes,

		"mime_type": item.DeclaredMIME,

		"part_size": item.PartSizeBytes,

		"session_expires_at": item.ExpiresAt,
	}
}
func (h *MediaUploadHandler) completedPayload(
	ctx context.Context,
	cfg config.StorageConfig,
	item *models.MediaObject) gin.H {
	payload := h.uploadPayload(item)
	payload["url"] = item.URL
	payload["checksum"] = item.ChecksumSHA256
	if item.Provider == services.StorageProviderS3 {

		if presigned, err := services.PresignS3GetObject(

			ctx,

			cfg,

			item.ObjectKey,

			item.OriginalName,

			directAccessURLTTL,
		); err == nil {

			payload["url"] = presigned.URL

			payload["url_expires_at"] = presigned.ExpiresAt

		}
	}
	return payload
}
func normalizeDirectUploadMetadata(category, fileName, rawMIME string) (string, string, string, error) {
	category = strings.ToLower(strings.TrimSpace(category))
	fileName = strings.TrimSpace(fileName)
	if fileName == "" || len(fileName) > 255 || strings.ContainsAny(fileName, "\x00\r\n") {

		return "", "", "", fmt.Errorf("文件名不合法")
	}
	ext := strings.ToLower(filepath.Ext(fileName))
	contentType := strings.ToLower(strings.TrimSpace(rawMIME))
	if parsed, _, err := mime.ParseMediaType(contentType); err == nil {

		contentType = strings.ToLower(parsed)
	}
	if contentType == "" {

		contentType = "application/octet-stream"
	}
	switch category {
	case "image":

		rules := map[string]string{

			".jpg": "image/jpeg", ".jpeg": "image/jpeg", ".png": "image/png",

			".gif": "image/gif", ".webp": "image/webp", ".avif": "image/avif",

			".heic": "image/heic", ".heif": "image/heif",
		}
		want, ok := rules[ext]

		if !ok || (contentType != want && contentType != "application/octet-stream") {

			return "", "", "", fmt.Errorf("不支持的图片格式")

		}

		if ext == ".jpeg" {

			ext = ".jpg"

		}

		return category, want, ext, nil
	case "video":

		rules := map[string]string{

			".mp4": "video/mp4", ".m4v": "video/x-m4v", ".mov": "video/quicktime",

			".webm": "video/webm", ".avi": "video/x-msvideo",
		}
		want, ok := rules[ext]

		matches := contentType == want || contentType == "application/octet-stream" ||

			(ext == ".m4v" && contentType == "video/mp4")

		if !ok || !matches {

			return "", "", "", fmt.Errorf("不支持的视频格式")

		}

		return category, want, ext, nil
	case "voice":

		rules := map[string]string{

			".m4a": "audio/mp4", ".mp3": "audio/mpeg", ".aac": "audio/aac",

			".wav": "audio/wav", ".ogg": "audio/ogg", ".webm": "audio/webm",
		}
		want, ok := rules[ext]

		if !ok || (contentType != want && contentType != "application/octet-stream") {

			return "", "", "", fmt.Errorf("不支持的音频格式")

		}

		return category, want, ext, nil
	case "file":

		rule, ok := allowedGenericFiles[ext]

		if !ok {

			return "", "", "", fmt.Errorf("不支持的文件格式")

		}
		segments := strings.Split(strings.ToLower(filepath.Base(fileName)), ".")

		for _, segment := range segments[:len(segments)-1] {

			if dangerousFileNameSegments[strings.TrimSpace(segment)] {

				return "", "", "", fmt.Errorf("文件名包含危险的双后缀")

			}

		}

		if contentType != "application/octet-stream" && contentType != rule.contentType &&

			!(rule.kind == "docx" && contentType == "application/msword") &&

			!(rule.kind == "xlsx" && contentType == "application/vnd.ms-excel") &&

			!(rule.kind == "pptx" && contentType == "application/vnd.ms-powerpoint") &&

			!(rule.kind == "text" && strings.HasPrefix(contentType, "text/")) &&

			!((rule.kind == "zip" || rule.kind == "docx" || rule.kind == "xlsx" || rule.kind == "pptx") &&

				(contentType == "application/zip" || contentType == "application/x-zip-compressed")) {

			return "", "", "", fmt.Errorf("文件扩展名与 MIME 类型不匹配")

		}

		return category, rule.contentType, ext, nil
	default:

		return "", "", "", fmt.Errorf("仅支持 image、video、voice、file")
	}
}
func directUploadDirectory(category string) string {
	switch category {
	case "image":

		return "images"
	case "video":

		return "videos"
	case "voice":

		return "voices"
	default:

		return "files"
	}
}
func directUploadPartCount(size, partSize int64) int {
	if size <= 0 || partSize <= 0 {

		return 0
	}
	return int((size + partSize - 1) / partSize)
}
func validateCompletedParts(item *models.MediaObject, parts []services.S3UploadedPart) error {
	expected := directUploadPartCount(item.SizeBytes, item.PartSizeBytes)
	if len(parts) != expected {

		return fmt.Errorf("分片尚未上传完整：%d/%d", len(parts), expected)
	}
	sort.Slice(parts, func(i, j int) bool { return parts[i].PartNumber < parts[j].PartNumber })
	var total int64
	for index, part := range parts {

		if part.PartNumber != int32(index+1) || strings.TrimSpace(part.ETag) == "" {

			return fmt.Errorf("S3 分片编号或 ETag 不完整")

		}

		if index < len(parts)-1 && part.Size != item.PartSizeBytes {

			return fmt.Errorf("S3 分片大小不正确")

		}

		if part.Size <= 0 || part.Size > item.PartSizeBytes {

			return fmt.Errorf("S3 分片大小不正确")

		}

		total += part.Size
	}
	if total != item.SizeBytes {

		return fmt.Errorf("S3 分片总大小校验失败")
	}
	return nil
}
func validateDirectObject(item *models.MediaObject, info services.S3ObjectInfo) error {
	if info.Size != item.SizeBytes {

		return fmt.Errorf("S3 对象大小校验失败")
	}
	gotMIME := strings.ToLower(strings.TrimSpace(info.ContentType))
	if parsed, _, err := mime.ParseMediaType(gotMIME); err == nil {

		gotMIME = strings.ToLower(parsed)
	}
	if gotMIME != strings.ToLower(strings.TrimSpace(item.DeclaredMIME)) {

		return fmt.Errorf("S3 对象 MIME 类型校验失败")
	}
	if expected := strings.ToLower(strings.TrimSpace(item.ExpectedSHA256)); expected != "" {

		actual := checksumBase64ToHex(info.ChecksumSHA256)

		// AWS S3 can omit this value from HeadObject for some endpoint and
		// compatibility combinations. The checksum was still query-signed into
		// the single PUT URL and enforced when S3 accepted the object.
		if actual != "" && actual != expected {

			return fmt.Errorf("S3 对象 SHA-256 校验失败")

		}
	}
	return nil
}
func directObjectChecksum(item *models.MediaObject, info services.S3ObjectInfo) string {
	if actual := checksumBase64ToHex(info.ChecksumSHA256); actual != "" {

		return actual
	}
	if item == nil {

		return ""
	}
	return strings.ToLower(strings.TrimSpace(item.ExpectedSHA256))
}
func validateDirectObjectSignature(item *models.MediaObject, prefix []byte) error {
	if len(prefix) == 0 {

		return fmt.Errorf("S3 对象内容为空")
	}
	ext := strings.ToLower(strings.TrimSpace(item.NormalizedExt))
	valid := false
	switch item.Category {
	case "image":

		switch ext {

		case ".jpg":

			valid = len(prefix) >= 3 && prefix[0] == 0xff && prefix[1] == 0xd8 && prefix[2] == 0xff

		case ".png":

			valid = bytes.HasPrefix(prefix, []byte("\x89PNG\r\n\x1a\n"))

		case ".gif":

			valid = bytes.HasPrefix(prefix, []byte("GIF87a")) || bytes.HasPrefix(prefix, []byte("GIF89a"))

		case ".webp":

			valid = len(prefix) >= 12 && string(prefix[:4]) == "RIFF" && string(prefix[8:12]) == "WEBP"

		case ".avif", ".heic", ".heif":

			valid = len(prefix) >= 12 && string(prefix[4:8]) == "ftyp"

		}
	case "video":

		switch ext {

		case ".mp4", ".m4v", ".mov":

			valid = len(prefix) >= 12 && string(prefix[4:8]) == "ftyp"

		case ".webm":

			valid = len(prefix) >= 4 && bytes.Equal(prefix[:4], []byte{0x1a, 0x45, 0xdf, 0xa3})

		case ".avi":

			valid = len(prefix) >= 12 && string(prefix[:4]) == "RIFF" && string(prefix[8:12]) == "AVI "

		}
	case "voice":

		switch ext {

		case ".mp3":

			valid = bytes.HasPrefix(prefix, []byte("ID3")) ||

				(len(prefix) >= 2 && prefix[0] == 0xff && (prefix[1]&0xe0) == 0xe0)

		case ".m4a":

			valid = len(prefix) >= 12 && string(prefix[4:8]) == "ftyp"

		case ".aac":

			valid = len(prefix) >= 2 && prefix[0] == 0xff && (prefix[1]&0xf0) == 0xf0

		case ".wav":

			valid = len(prefix) >= 12 && string(prefix[:4]) == "RIFF" && string(prefix[8:12]) == "WAVE"

		case ".ogg":

			valid = bytes.HasPrefix(prefix, []byte("OggS"))

		case ".webm":

			valid = len(prefix) >= 4 && bytes.Equal(prefix[:4], []byte{0x1a, 0x45, 0xdf, 0xa3})

		}
	case "file":

		switch ext {

		case ".pdf":

			valid = bytes.HasPrefix(prefix, []byte("%PDF-"))

		case ".docx", ".xlsx", ".pptx", ".zip":

			valid = bytes.HasPrefix(prefix, []byte("PK\x03\x04")) ||

				bytes.HasPrefix(prefix, []byte("PK\x05\x06"))

		case ".txt", ".csv":

			valid = utf8.Valid(prefix) && !bytes.Contains(prefix, []byte{0})

		}
	}
	if !valid {

		return fmt.Errorf("文件实际内容与扩展名不匹配")
	}
	return nil
}

const (
	maxDirectImageDimension = uint64(20000)
	maxDirectImagePixels    = uint64(80_000_000)
	maxDirectGIFFrames      = 300
)

func validateDirectImageResources(item *models.MediaObject, data []byte) error {
	if item == nil || item.Category != "image" {

		return nil
	}
	width, height, frameCount, ok := directImageDimensionsAndFrames(

		strings.ToLower(strings.TrimSpace(item.NormalizedExt)),

		data,
	)
	if !ok || width == 0 || height == 0 {

		return fmt.Errorf("无法读取图片尺寸，已拒绝该文件")
	}
	if width > maxDirectImageDimension || height > maxDirectImageDimension ||

		width > maxDirectImagePixels/height {

		return fmt.Errorf("图片尺寸或像素总量超出安全限制")
	}
	if frameCount > maxDirectGIFFrames {

		return fmt.Errorf("GIF 帧数超出安全限制")
	}
	return nil
}
func directImageDimensionsAndFrames(ext string, data []byte) (uint64, uint64, int, bool) {
	switch ext {
	case ".jpg":

		width, height, ok := jpegDimensions(data)

		return width, height, 1, ok
	case ".png":

		if len(data) < 24 || !bytes.HasPrefix(data, []byte("\x89PNG\r\n\x1a\n")) {

			return 0, 0, 0, false

		}

		return uint64(binary.BigEndian.Uint32(data[16:20])),

			uint64(binary.BigEndian.Uint32(data[20:24])), 1, true
	case ".gif":

		return gifDimensionsAndFrames(data)
	case ".webp":

		width, height, ok := webPDimensions(data)

		return width, height, 1, ok
	case ".avif", ".heic", ".heif":

		width, height, ok := isoBMFFImageDimensions(data)

		return width, height, 1, ok
	default:

		return 0, 0, 0, false
	}
}
func jpegDimensions(data []byte) (uint64, uint64, bool) {
	if len(data) < 4 || data[0] != 0xff || data[1] != 0xd8 {

		return 0, 0, false
	}
	for offset := 2; offset+3 < len(data); {

		if data[offset] != 0xff {

			offset++

			continue

		}

		for offset < len(data) && data[offset] == 0xff {

			offset++

		}

		if offset >= len(data) {

			break

		}
		marker := data[offset]

		offset++

		if marker == 0xd8 || marker == 0xd9 {

			continue

		}

		if offset+2 > len(data) {

			break

		}
		segmentLength := int(binary.BigEndian.Uint16(data[offset : offset+2]))

		if segmentLength < 2 || offset+segmentLength > len(data) {

			return 0, 0, false

		}

		if (marker >= 0xc0 && marker <= 0xc3) ||

			(marker >= 0xc5 && marker <= 0xc7) ||

			(marker >= 0xc9 && marker <= 0xcb) ||

			(marker >= 0xcd && marker <= 0xcf) {

			if segmentLength < 7 {

				return 0, 0, false

			}
			height := uint64(binary.BigEndian.Uint16(data[offset+3 : offset+5]))
			width := uint64(binary.BigEndian.Uint16(data[offset+5 : offset+7]))

			return width, height, width > 0 && height > 0

		}

		offset += segmentLength
	}
	return 0, 0, false
}
func gifDimensionsAndFrames(data []byte) (uint64, uint64, int, bool) {
	if len(data) < 13 ||

		(!bytes.HasPrefix(data, []byte("GIF87a")) && !bytes.HasPrefix(data, []byte("GIF89a"))) {

		return 0, 0, 0, false
	}
	width := uint64(binary.LittleEndian.Uint16(data[6:8]))
	height := uint64(binary.LittleEndian.Uint16(data[8:10]))
	offset := 13
	if data[10]&0x80 != 0 {

		offset += 3 * (1 << ((data[10] & 0x07) + 1))
	}
	frames := 0
	skipSubBlocks := func() bool {

		for {

			if offset >= len(data) {

				return false

			}
			size := int(data[offset])

			offset++

			if size == 0 {

				return true

			}

			if offset+size > len(data) {

				return false

			}

			offset += size

		}
	}
	for offset < len(data) {

		switch data[offset] {

		case 0x3b:

			return width, height, frames, frames > 0

		case 0x21:

			offset += 2

			if offset > len(data) || !skipSubBlocks() {

				return 0, 0, 0, false

			}

		case 0x2c:

			frames++

			offset++

			if offset+9 > len(data) {

				return 0, 0, 0, false

			}
			packed := data[offset+8]

			offset += 9

			if packed&0x80 != 0 {

				offset += 3 * (1 << ((packed & 0x07) + 1))

			}

			if offset >= len(data) {

				return 0, 0, 0, false

			}

			offset++ // LZW minimum code size

			if !skipSubBlocks() {

				return 0, 0, 0, false

			}

		default:

			return 0, 0, 0, false

		}
	}
	return 0, 0, 0, false
}
func webPDimensions(data []byte) (uint64, uint64, bool) {
	if len(data) < 30 || string(data[:4]) != "RIFF" || string(data[8:12]) != "WEBP" {

		return 0, 0, false
	}
	switch string(data[12:16]) {
	case "VP8X":

		width := uint64(data[24]) | uint64(data[25])<<8 | uint64(data[26])<<16

		height := uint64(data[27]) | uint64(data[28])<<8 | uint64(data[29])<<16

		return width + 1, height + 1, true
	case "VP8 ":

		if data[23] != 0x9d || data[24] != 0x01 || data[25] != 0x2a {

			return 0, 0, false

		}
		width := uint64(binary.LittleEndian.Uint16(data[26:28]) & 0x3fff)
		height := uint64(binary.LittleEndian.Uint16(data[28:30]) & 0x3fff)

		return width, height, width > 0 && height > 0
	case "VP8L":

		if len(data) < 25 || data[20] != 0x2f {

			return 0, 0, false

		}
		bits := uint32(data[21]) |

			uint32(data[22])<<8 |

			uint32(data[23])<<16 |

			uint32(data[24])<<24

		width := uint64(bits&0x3fff) + 1

		height := uint64((bits>>14)&0x3fff) + 1

		return width, height, true
	}
	return 0, 0, false
}
func isoBMFFImageDimensions(data []byte) (uint64, uint64, bool) {
	for offset := 4; offset+16 <= len(data); offset++ {

		if string(data[offset:offset+4]) != "ispe" {

			continue

		}
		width := uint64(binary.BigEndian.Uint32(data[offset+8 : offset+12]))
		height := uint64(binary.BigEndian.Uint32(data[offset+12 : offset+16]))

		if width > 0 && height > 0 {

			return width, height, true

		}
	}
	return 0, 0, false
}
func checksumBase64ToHex(value string) string {
	raw, err := base64.StdEncoding.DecodeString(strings.TrimSpace(value))
	if err != nil || len(raw) == 0 {

		return ""
	}
	return hex.EncodeToString(raw)
}
func isSHA256Hex(value string) bool {
	if len(value) != 64 {

		return false
	}
	_, err := hex.DecodeString(value)
	return err == nil
}
