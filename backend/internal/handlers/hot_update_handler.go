package handlers

import (
	"hash/fnv"
	"net/http"
	"net/url"
	"regexp"
	"strconv"
	"strings"
	"time"

	"gaoranim/internal/middleware"
	"gaoranim/internal/models"
	"gaoranim/pkg/response"

	"github.com/gin-gonic/gin"
	"github.com/google/uuid"
	"gorm.io/gorm"
)

type HotUpdateHandler struct {
	db *gorm.DB
}

func NewHotUpdateHandler(db *gorm.DB) *HotUpdateHandler {
	return &HotUpdateHandler{db: db}
}

type hotUpdatePatchUpsertRequest struct {
	Name string `json:"name"`

	Description  string `json:"description"`
	Platform     string `json:"platform"`
	Channel      string `json:"channel"`
	DeliveryMode string `json:"delivery_mode"`

	MinAppVersion  string `json:"min_app_version"`
	MaxAppVersion  string `json:"max_app_version"`
	MinBuildNumber *int   `json:"min_build_number"`
	MaxBuildNumber *int   `json:"max_build_number"`

	TargetAppVersion string `json:"target_app_version"`
	PatchVersion     string `json:"patch_version"`
	PatchURL         string `json:"patch_url"`
	PatchHash        string `json:"patch_hash"`
	ReleaseNotes     string `json:"release_notes"`

	RolloutPercentage *int  `json:"rollout_percentage"`
	IsMandatory       *bool `json:"is_mandatory"`
	Priority          *int  `json:"priority"`

	StartAt *time.Time `json:"start_at"`
	EndAt   *time.Time `json:"end_at"`
}

type hotUpdatePatchReportCreateRequest struct {
	PatchID    uint64 `json:"patch_id"`
	PatchRefID string `json:"patch_ref_id"`

	Platform string `json:"platform"`
	Channel  string `json:"channel"`

	AppVersion  string `json:"app_version"`
	BuildNumber int    `json:"build_number"`
	DeviceID    string `json:"device_id"`
	UserUUID    string `json:"user_uuid"`

	Status  string `json:"status"`
	Message string `json:"message"`
}

func (h *HotUpdateHandler) ListPatches(c *gin.Context) {
	page, _ := strconv.Atoi(strings.TrimSpace(c.DefaultQuery("page", "1")))
	pageSize, _ := strconv.Atoi(strings.TrimSpace(c.DefaultQuery("page_size", "20")))
	if page < 1 {
		page = 1
	}
	if pageSize < 1 {
		pageSize = 20
	}
	if pageSize > 100 {
		pageSize = 100
	}

	status := strings.TrimSpace(c.Query("status"))
	platform := strings.TrimSpace(c.Query("platform"))
	channel := strings.TrimSpace(c.Query("channel"))
	deliveryMode := strings.TrimSpace(c.Query("delivery_mode"))
	keyword := strings.TrimSpace(c.Query("keyword"))

	query := h.db.Model(&models.HotUpdatePatch{})
	if status != "" {
		normalizedStatus := normalizeHotUpdatePatchStatus(status)
		if normalizedStatus == "" {
			response.Error(c, http.StatusBadRequest, "invalid status")
			return
		}
		query = query.Where("status = ?", normalizedStatus)
	}
	if platform != "" {
		normalizedPlatform := normalizeHotUpdatePlatform(platform)
		if normalizedPlatform == "" {
			response.Error(c, http.StatusBadRequest, "invalid platform")
			return
		}
		query = query.Where("platform = ?", normalizedPlatform)
	}
	if channel != "" {
		query = query.Where("channel = ?", normalizeHotUpdateChannel(channel))
	}
	if deliveryMode != "" {
		normalizedDeliveryMode := normalizeHotUpdateDeliveryMode(deliveryMode)
		if normalizedDeliveryMode == "" {
			response.Error(c, http.StatusBadRequest, "invalid delivery_mode")
			return
		}
		query = applyHotUpdateDeliveryModeFilter(query, normalizedDeliveryMode)
	}
	if keyword != "" {
		like := "%" + keyword + "%"
		query = query.Where("name LIKE ? OR patch_id LIKE ? OR patch_version LIKE ?", like, like, like)
	}

	var total int64
	if err := query.Count(&total).Error; err != nil {
		response.Error(c, http.StatusInternalServerError, "failed to load patches")
		return
	}

	var list []models.HotUpdatePatch
	if err := query.
		Order("priority DESC, id DESC").
		Offset((page - 1) * pageSize).
		Limit(pageSize).
		Find(&list).Error; err != nil {
		response.Error(c, http.StatusInternalServerError, "failed to load patches")
		return
	}
	for i := range list {
		normalizeHotUpdatePatchRecord(&list[i])
	}

	response.Success(c, gin.H{
		"list":      list,
		"total":     total,
		"page":      page,
		"page_size": pageSize,
	})
}
func (h *HotUpdateHandler) GetPatch(c *gin.Context) {
	id := strings.TrimSpace(c.Param("id"))
	var patch models.HotUpdatePatch
	if err := h.db.Where("id = ?", id).First(&patch).Error; err != nil {
		response.Error(c, http.StatusNotFound, "patch not found")
		return
	}
	normalizeHotUpdatePatchRecord(&patch)
	response.Success(c, patch)
}
func (h *HotUpdateHandler) CreatePatch(c *gin.Context) {
	var req hotUpdatePatchUpsertRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		response.Error(c, http.StatusBadRequest, "invalid parameters")
		return
	}

	adminID := middleware.GetAdminID(c)
	values, err := buildPatchFromRequest(req, nil, adminID, true)
	if err != nil {
		response.Error(c, http.StatusBadRequest, err.Error())
		return
	}

	patch := models.HotUpdatePatch{
		PatchID:           readString(values, "patch_id"),
		Name:              readString(values, "name"),
		Description:       readString(values, "description"),
		Platform:          readString(values, "platform"),
		Channel:           readString(values, "channel"),
		DeliveryMode:      readString(values, "delivery_mode"),
		MinAppVersion:     readString(values, "min_app_version"),
		MaxAppVersion:     readString(values, "max_app_version"),
		MinBuildNumber:    readInt(values, "min_build_number"),
		MaxBuildNumber:    readInt(values, "max_build_number"),
		TargetAppVersion:  readString(values, "target_app_version"),
		PatchVersion:      readString(values, "patch_version"),
		PatchURL:          readString(values, "patch_url"),
		PatchHash:         readString(values, "patch_hash"),
		ReleaseNotes:      readString(values, "release_notes"),
		RolloutPercentage: readInt(values, "rollout_percentage"),
		IsMandatory:       readBool(values, "is_mandatory"),
		Priority:          readInt(values, "priority"),
		Status:            readString(values, "status"),
		StartAt:           readTimePtr(values, "start_at"),
		EndAt:             readTimePtr(values, "end_at"),
		CreatedBy:         uint64(readInt(values, "created_by")),
		UpdatedBy:         uint64(readInt(values, "updated_by")),
	}

	if err := h.db.Create(&patch).Error; err != nil {
		response.Error(c, http.StatusInternalServerError, "failed to create patch")
		return
	}

	response.SuccessWithMessage(c, "created", patch)
}
func (h *HotUpdateHandler) UpdatePatch(c *gin.Context) {
	id := strings.TrimSpace(c.Param("id"))
	var patch models.HotUpdatePatch
	if err := h.db.Where("id = ?", id).First(&patch).Error; err != nil {
		response.Error(c, http.StatusNotFound, "patch not found")
		return
	}

	var req hotUpdatePatchUpsertRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		response.Error(c, http.StatusBadRequest, "invalid parameters")
		return
	}

	adminID := middleware.GetAdminID(c)
	updated, err := buildPatchFromRequest(req, &patch, adminID, false)
	if err != nil {
		response.Error(c, http.StatusBadRequest, err.Error())
		return
	}

	if err := h.db.Model(&patch).Updates(updated).Error; err != nil {
		response.Error(c, http.StatusInternalServerError, "failed to update patch")
		return
	}

	if err := h.db.Where("id = ?", patch.ID).First(&patch).Error; err != nil {
		response.Error(c, http.StatusInternalServerError, "failed to reload patch")
		return
	}
	normalizeHotUpdatePatchRecord(&patch)
	response.SuccessWithMessage(c, "updated", patch)
}
func (h *HotUpdateHandler) DeletePatch(c *gin.Context) {
	id := strings.TrimSpace(c.Param("id"))
	result := h.db.Delete(&models.HotUpdatePatch{}, id)
	if result.Error != nil {
		response.Error(c, http.StatusInternalServerError, "failed to delete patch")
		return
	}
	if result.RowsAffected == 0 {
		response.Error(c, http.StatusNotFound, "patch not found")
		return
	}
	response.SuccessWithMessage(c, "deleted", nil)
}
func (h *HotUpdateHandler) PublishPatch(c *gin.Context) {
	h.updatePatchStatus(c, models.HotUpdatePatchStatusPublished)
}

func (h *HotUpdateHandler) PausePatch(c *gin.Context) {
	h.updatePatchStatus(c, models.HotUpdatePatchStatusPaused)
}

func (h *HotUpdateHandler) RollbackPatch(c *gin.Context) {
	h.updatePatchStatus(c, models.HotUpdatePatchStatusRolledBack)
}

func (h *HotUpdateHandler) updatePatchStatus(c *gin.Context, targetStatus string) {
	id := strings.TrimSpace(c.Param("id"))
	var patch models.HotUpdatePatch
	if err := h.db.Where("id = ?", id).First(&patch).Error; err != nil {
		response.Error(c, http.StatusNotFound, "patch not found")
		return
	}

	now := time.Now()
	adminID := middleware.GetAdminID(c)
	updates := map[string]interface{}{
		"status":     targetStatus,
		"updated_by": adminID,
	}

	switch targetStatus {
	case models.HotUpdatePatchStatusPublished:
		if strings.TrimSpace(patch.PatchVersion) == "" {
			response.Error(c, http.StatusBadRequest, "patch_version is required before publish")
			return
		}
		if normalizeHotUpdateDeliveryMode(patch.DeliveryMode) == models.HotUpdatePatchDeliveryModeSelfHosted &&
			patch.Platform == models.HotUpdatePatchPlatformAll {
			response.Error(c, http.StatusBadRequest, "self_hosted does not support platform=all; create Android and iOS patches separately")
			return
		}
		if normalizeHotUpdateDeliveryMode(patch.DeliveryMode) == models.HotUpdatePatchDeliveryModeSelfHosted &&
			strings.TrimSpace(patch.PatchURL) == "" {
			response.Error(c, http.StatusBadRequest, "patch_url is required before publish for self_hosted")
			return
		}
		if patch.RolloutPercentage <= 0 {
			response.Error(c, http.StatusBadRequest, "rollout_percentage must be between 1 and 100 before publish")
			return
		}
		updates["published_at"] = now
		updates["paused_at"] = nil
		updates["rollback_at"] = nil
	case models.HotUpdatePatchStatusPaused:
		updates["paused_at"] = now
	case models.HotUpdatePatchStatusRolledBack:
		updates["rollback_at"] = now
	}

	if err := h.db.Model(&patch).Updates(updates).Error; err != nil {
		response.Error(c, http.StatusInternalServerError, "failed to update patch status")
		return
	}
	response.SuccessWithMessage(c, "status updated", nil)
}
func (h *HotUpdateHandler) CheckPatch(c *gin.Context) {
	platform := normalizeHotUpdatePlatform(c.DefaultQuery("platform", ""))
	channel := normalizeHotUpdateChannel(c.DefaultQuery("channel", "stable"))
	appVersion := strings.TrimSpace(c.Query("app_version"))
	buildNumber, _ := strconv.Atoi(strings.TrimSpace(c.DefaultQuery("build_number", "0")))

	deviceID := strings.TrimSpace(c.Query("device_id"))
	userUUID := strings.TrimSpace(c.Query("user_uuid"))
	clientIP := strings.TrimSpace(c.ClientIP())
	supportsShorebird := parseHotUpdateBoolFlag(c.Query("supports_shorebird"))

	if platform == "" {
		response.Error(c, http.StatusBadRequest, "platform is required")
		return
	}

	now := time.Now()
	var candidates []models.HotUpdatePatch
	if err := h.db.
		Where("status = ?", models.HotUpdatePatchStatusPublished).
		Where("channel = ?", channel).
		Where("(platform = ? OR platform = ?)", platform, models.HotUpdatePatchPlatformAll).
		Order("priority DESC, published_at DESC, id DESC").
		Find(&candidates).Error; err != nil {
		response.Error(c, http.StatusInternalServerError, "failed to check patch")
		return
	}

	completedPatchIDs, err := h.loadClientCompletedPatchIDs(candidates, deviceID, userUUID)
	if err != nil {
		response.Error(c, http.StatusInternalServerError, "failed to check patch")
		return
	}

	for _, patch := range candidates {
		if normalizeHotUpdateDeliveryMode(patch.DeliveryMode) == models.HotUpdatePatchDeliveryModeSelfHosted &&
			patch.Platform == models.HotUpdatePatchPlatformAll {
			continue
		}
		if _, completed := completedPatchIDs[patch.ID]; completed {
			continue
		}
		if normalizeHotUpdateDeliveryMode(patch.DeliveryMode) == models.HotUpdatePatchDeliveryModeShorebird &&
			!supportsShorebird {
			continue
		}
		if !isPatchEligibleForClient(patch, appVersion, buildNumber, now) {
			continue
		}
		seed := buildRolloutSeed(patch.PatchID, userUUID, deviceID, clientIP)
		inRollout, _ := isInRollout(seed, patch.RolloutPercentage)
		if !inRollout {
			continue
		}

		response.Success(c, gin.H{
			"has_patch": true,
			"patch": gin.H{
				"id":                 patch.ID,
				"patch_id":           patch.PatchID,
				"name":               patch.Name,
				"description":        patch.Description,
				"platform":           patch.Platform,
				"channel":            patch.Channel,
				"delivery_mode":      normalizeHotUpdateDeliveryMode(patch.DeliveryMode),
				"target_app_version": patch.TargetAppVersion,
				"patch_version":      patch.PatchVersion,
				"patch_url":          patch.PatchURL,
				"patch_hash":         patch.PatchHash,
				"release_notes":      patch.ReleaseNotes,
				"is_mandatory":       patch.IsMandatory,
				"rollout_percentage": patch.RolloutPercentage,
			},
		})
		return
	}

	response.Success(c, gin.H{
		"has_patch": false,
	})
}
func (h *HotUpdateHandler) ReportPatchResult(c *gin.Context) {
	var req hotUpdatePatchReportCreateRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		response.Error(c, http.StatusBadRequest, "invalid parameters")
		return
	}

	status := normalizeHotUpdateReportStatus(req.Status)
	if status == "" {
		response.Error(c, http.StatusBadRequest, "invalid report status")
		return
	}

	if req.PatchID == 0 && strings.TrimSpace(req.PatchRefID) == "" {
		response.Error(c, http.StatusBadRequest, "patch_id or patch_ref_id is required")
		return
	}

	var patch models.HotUpdatePatch
	var found bool
	if req.PatchID > 0 {
		if err := h.db.Where("id = ?", req.PatchID).First(&patch).Error; err == nil {
			found = true
		}
	}
	if !found {
		patchRefID := strings.TrimSpace(req.PatchRefID)
		if patchRefID != "" {
			if err := h.db.Where("patch_id = ?", patchRefID).First(&patch).Error; err == nil {
				found = true
			}
		}
	}
	if !found {
		response.Error(c, http.StatusNotFound, "patch not found")
		return
	}

	platform := normalizeHotUpdatePlatform(req.Platform)
	if platform == "" || platform == models.HotUpdatePatchPlatformAll {
		if patch.Platform != models.HotUpdatePatchPlatformAll {
			platform = patch.Platform
		}
	}
	if platform == "" || platform == models.HotUpdatePatchPlatformAll {
		platform = models.HotUpdatePatchPlatformAndroid
	}

	channel := normalizeHotUpdateChannel(req.Channel)
	if strings.TrimSpace(req.Channel) == "" && strings.TrimSpace(patch.Channel) != "" {
		channel = normalizeHotUpdateChannel(patch.Channel)
	}

	userUUID := strings.TrimSpace(c.GetString("user_id"))
	if userUUID == "" {
		userUUID = truncateText(strings.TrimSpace(req.UserUUID), 36)
	}
	deviceID := strings.TrimSpace(c.GetString("device_id"))
	if deviceID == "" {
		deviceID = truncateText(strings.TrimSpace(req.DeviceID), 128)
	}

	report := models.HotUpdatePatchReport{
		PatchID:      patch.ID,
		PatchRefID:   patch.PatchID,
		PatchVersion: strings.TrimSpace(patch.PatchVersion),
		Platform:     platform,
		Channel:      channel,
		DeliveryMode: normalizeHotUpdateDeliveryMode(patch.DeliveryMode),
		AppVersion:   truncateText(strings.TrimSpace(req.AppVersion), 64),
		BuildNumber:  clampNonNegative(req.BuildNumber),
		DeviceID:     deviceID,
		UserUUID:     userUUID,
		Status:       status,
		Message:      truncateText(strings.TrimSpace(req.Message), 500),
		ClientIP:     truncateText(strings.TrimSpace(c.ClientIP()), 64),
	}

	if err := h.db.Create(&report).Error; err != nil {
		response.Error(c, http.StatusInternalServerError, "failed to save patch report")
		return
	}

	response.Success(c, gin.H{
		"id": report.ID,
	})
}
func (h *HotUpdateHandler) ListPatchReports(c *gin.Context) {
	page, _ := strconv.Atoi(strings.TrimSpace(c.DefaultQuery("page", "1")))
	pageSize, _ := strconv.Atoi(strings.TrimSpace(c.DefaultQuery("page_size", "20")))
	if page < 1 {
		page = 1
	}
	if pageSize < 1 {
		pageSize = 20
	}
	if pageSize > 100 {
		pageSize = 100
	}

	statusText := strings.TrimSpace(c.Query("status"))
	platformText := strings.TrimSpace(c.Query("platform"))
	channel := strings.TrimSpace(c.Query("channel"))
	deliveryModeText := strings.TrimSpace(c.Query("delivery_mode"))
	patchRefID := strings.TrimSpace(c.Query("patch_ref_id"))
	userUUID := strings.TrimSpace(c.Query("user_uuid"))
	deviceID := strings.TrimSpace(c.Query("device_id"))
	keyword := strings.TrimSpace(c.Query("keyword"))

	query := h.db.Model(&models.HotUpdatePatchReport{})

	if statusText != "" {
		status := normalizeHotUpdateReportStatus(statusText)
		if status == "" {
			response.Error(c, http.StatusBadRequest, "invalid status")
			return
		}
		query = query.Where("status = ?", status)
	}

	if platformText != "" {
		platform := normalizeHotUpdatePlatform(platformText)
		if platform == "" {
			response.Error(c, http.StatusBadRequest, "invalid platform")
			return
		}
		query = query.Where("platform = ?", platform)
	}

	if channel != "" {
		query = query.Where("channel = ?", normalizeHotUpdateChannel(channel))
	}
	if deliveryModeText != "" {
		deliveryMode := normalizeHotUpdateDeliveryMode(deliveryModeText)
		if deliveryMode == "" {
			response.Error(c, http.StatusBadRequest, "invalid delivery_mode")
			return
		}
		query = applyHotUpdateDeliveryModeFilter(query, deliveryMode)
	}
	if patchRefID != "" {
		query = query.Where("patch_ref_id = ?", patchRefID)
	}
	if userUUID != "" {
		query = query.Where("user_uuid = ?", userUUID)
	}
	if deviceID != "" {
		query = query.Where("device_id = ?", deviceID)
	}
	if patchIDText := strings.TrimSpace(c.Query("patch_id")); patchIDText != "" {
		patchID, err := strconv.ParseUint(patchIDText, 10, 64)
		if err != nil {
			response.Error(c, http.StatusBadRequest, "invalid patch_id")
			return
		}
		query = query.Where("patch_id = ?", patchID)
	}
	if keyword != "" {
		like := "%" + keyword + "%"
		query = query.Where(
			"patch_ref_id LIKE ? OR patch_version LIKE ? OR user_uuid LIKE ? OR device_id LIKE ? OR message LIKE ?",
			like,
			like,
			like,
			like,
			like,
		)
	}

	var total int64
	if err := query.Count(&total).Error; err != nil {
		response.Error(c, http.StatusInternalServerError, "failed to load patch reports")
		return
	}

	var list []models.HotUpdatePatchReport
	if err := query.
		Order("id DESC").
		Offset((page - 1) * pageSize).
		Limit(pageSize).
		Find(&list).Error; err != nil {
		response.Error(c, http.StatusInternalServerError, "failed to load patch reports")
		return
	}
	for i := range list {
		normalizeHotUpdatePatchReportRecord(&list[i])
	}

	response.Success(c, gin.H{
		"list":      list,
		"total":     total,
		"page":      page,
		"page_size": pageSize,
	})
}
func buildPatchFromRequest(req hotUpdatePatchUpsertRequest, existing *models.HotUpdatePatch, adminID uint64, isCreate bool) (map[string]interface{}, error) {
	name := strings.TrimSpace(req.Name)
	if isCreate && name == "" {
		return nil, errText("name is required")
	}
	if len([]rune(name)) > 120 {
		return nil, errText("name must not exceed 120 characters")
	}

	platform := normalizeHotUpdatePlatform(req.Platform)
	if platform == "" && isCreate {
		platform = models.HotUpdatePatchPlatformAndroid
	}
	if platform == "" && existing != nil {
		platform = existing.Platform
	}
	if platform == "" {
		platform = models.HotUpdatePatchPlatformAndroid
	}

	channel := normalizeHotUpdateChannel(req.Channel)
	if channel == "" {
		channel = "stable"
	}

	rawDeliveryMode := strings.TrimSpace(req.DeliveryMode)
	deliveryMode := ""
	if rawDeliveryMode != "" {
		deliveryMode = normalizeHotUpdateDeliveryMode(rawDeliveryMode)
		if deliveryMode == "" {
			return nil, errText("delivery_mode must be self_hosted or shorebird")
		}
	}
	if deliveryMode == "" && existing != nil {
		deliveryMode = normalizeHotUpdateDeliveryMode(existing.DeliveryMode)
	}
	if deliveryMode == "" {
		deliveryMode = models.HotUpdatePatchDeliveryModeSelfHosted
	}

	minBuild := readOptionalInt(req.MinBuildNumber, 0)
	maxBuild := readOptionalInt(req.MaxBuildNumber, 0)
	if minBuild < 0 || maxBuild < 0 {
		return nil, errText("build numbers must not be negative")
	}
	if minBuild > 0 && maxBuild > 0 && minBuild > maxBuild {
		return nil, errText("min_build_number must not be greater than max_build_number")
	}

	rollout := readOptionalInt(req.RolloutPercentage, 100)
	if rollout < 0 || rollout > 100 {
		return nil, errText("rollout_percentage must be between 0 and 100")
	}

	priority := readOptionalInt(req.Priority, 0)
	isMandatory := readOptionalBool(req.IsMandatory, false)

	minVersion := strings.TrimSpace(req.MinAppVersion)
	maxVersion := strings.TrimSpace(req.MaxAppVersion)
	if minVersion != "" && maxVersion != "" && compareVersion(minVersion, maxVersion) > 0 {
		return nil, errText("min_app_version must not be greater than max_app_version")
	}

	patchVersion := strings.TrimSpace(req.PatchVersion)
	patchURL := strings.TrimSpace(req.PatchURL)
	patchHash := strings.TrimSpace(req.PatchHash)
	if len(patchURL) > 500 {
		return nil, errText("patch_url is too long")
	}
	if len(patchHash) > 128 {
		return nil, errText("patch_hash is too long")
	}
	if isCreate && patchVersion == "" {
		return nil, errText("patch_version is required")
	}
	if deliveryMode == models.HotUpdatePatchDeliveryModeSelfHosted {
		if platform == models.HotUpdatePatchPlatformAll {
			return nil, errText("self_hosted does not support platform=all; create Android and iOS patches separately")
		}
		if patchURL == "" {
			return nil, errText("patch_url is required for self_hosted")
		}
		if err := validateHotUpdatePatchURL(platform, patchURL); err != nil {
			return nil, err
		}
	} else {
		patchURL = ""
		patchHash = ""
	}
	if err := validateHotUpdatePatchHash(patchHash); err != nil {
		return nil, err
	}
	if req.StartAt != nil && req.EndAt != nil && req.StartAt.After(*req.EndAt) {
		return nil, errText("start_at must not be later than end_at")
	}

	updates := map[string]interface{}{
		"name":               name,
		"description":        strings.TrimSpace(req.Description),
		"platform":           platform,
		"channel":            channel,
		"delivery_mode":      deliveryMode,
		"min_app_version":    minVersion,
		"max_app_version":    maxVersion,
		"min_build_number":   minBuild,
		"max_build_number":   maxBuild,
		"target_app_version": strings.TrimSpace(req.TargetAppVersion),
		"patch_version":      patchVersion,
		"patch_url":          patchURL,
		"patch_hash":         patchHash,
		"release_notes":      strings.TrimSpace(req.ReleaseNotes),
		"rollout_percentage": rollout,
		"is_mandatory":       isMandatory,
		"priority":           priority,
		"start_at":           req.StartAt,
		"end_at":             req.EndAt,
		"updated_by":         adminID,
	}

	if isCreate {
		patchID := uuid.NewString()
		updates["patch_id"] = patchID
		updates["status"] = models.HotUpdatePatchStatusDraft
		updates["created_by"] = adminID
	}

	if isCreate {
		return updates, nil
	}

	// Keep the previous name when the update payload only changes partial fields.
	if updates["name"] == "" && existing != nil {
		updates["name"] = existing.Name
	}
	if updates["patch_version"] == "" && existing != nil {
		updates["patch_version"] = existing.PatchVersion
	}

	return updates, nil
}
func readOptionalInt(v *int, defaultValue int) int {
	if v == nil {
		return defaultValue
	}
	return *v
}

func readOptionalBool(v *bool, defaultValue bool) bool {
	if v == nil {
		return defaultValue
	}
	return *v
}

func readString(values map[string]interface{}, key string) string {
	raw, ok := values[key]
	if !ok || raw == nil {
		return ""
	}
	v, ok := raw.(string)
	if !ok {
		return ""
	}
	return v
}

func readInt(values map[string]interface{}, key string) int {
	raw, ok := values[key]
	if !ok || raw == nil {
		return 0
	}
	switch v := raw.(type) {
	case int:
		return v
	case int32:
		return int(v)
	case int64:
		return int(v)
	case uint:
		return int(v)
	case uint32:
		return int(v)
	case uint64:
		return int(v)
	default:
		return 0
	}
}

func readBool(values map[string]interface{}, key string) bool {
	raw, ok := values[key]
	if !ok || raw == nil {
		return false
	}
	v, ok := raw.(bool)
	if !ok {
		return false
	}
	return v
}

func readTimePtr(values map[string]interface{}, key string) *time.Time {
	raw, ok := values[key]
	if !ok || raw == nil {
		return nil
	}
	v, ok := raw.(*time.Time)
	if !ok {
		return nil
	}
	return v
}

func errText(msg string) error {
	return &validationError{text: msg}
}

type validationError struct {
	text string
}

func (e *validationError) Error() string {
	return e.text
}

func normalizeHotUpdatePlatform(platform string) string {
	switch strings.ToLower(strings.TrimSpace(platform)) {
	case models.HotUpdatePatchPlatformAndroid:
		return models.HotUpdatePatchPlatformAndroid
	case models.HotUpdatePatchPlatformIOS:
		return models.HotUpdatePatchPlatformIOS
	case models.HotUpdatePatchPlatformAll:
		return models.HotUpdatePatchPlatformAll
	default:
		return ""
	}
}

func normalizeHotUpdateChannel(channel string) string {
	value := strings.ToLower(strings.TrimSpace(channel))
	if value == "" {
		return "stable"
	}
	return value
}

func normalizeHotUpdatePatchStatus(status string) string {
	switch strings.ToLower(strings.TrimSpace(status)) {
	case models.HotUpdatePatchStatusDraft:
		return models.HotUpdatePatchStatusDraft
	case models.HotUpdatePatchStatusPublished:
		return models.HotUpdatePatchStatusPublished
	case models.HotUpdatePatchStatusPaused:
		return models.HotUpdatePatchStatusPaused
	case models.HotUpdatePatchStatusRolledBack:
		return models.HotUpdatePatchStatusRolledBack
	default:
		return ""
	}
}

func normalizeHotUpdatePatchRecord(patch *models.HotUpdatePatch) {
	if patch == nil {
		return
	}
	patch.DeliveryMode = normalizeHotUpdateDeliveryMode(patch.DeliveryMode)
	if patch.DeliveryMode == "" {
		patch.DeliveryMode = models.HotUpdatePatchDeliveryModeSelfHosted
	}
}

func normalizeHotUpdatePatchReportRecord(report *models.HotUpdatePatchReport) {
	if report == nil {
		return
	}
	report.DeliveryMode = normalizeHotUpdateDeliveryMode(report.DeliveryMode)
	if report.DeliveryMode == "" {
		report.DeliveryMode = models.HotUpdatePatchDeliveryModeSelfHosted
	}
}

func normalizeHotUpdateDeliveryMode(mode string) string {
	switch strings.ToLower(strings.TrimSpace(mode)) {
	case "", models.HotUpdatePatchDeliveryModeSelfHosted:
		return models.HotUpdatePatchDeliveryModeSelfHosted
	case models.HotUpdatePatchDeliveryModeShorebird:
		return models.HotUpdatePatchDeliveryModeShorebird
	default:
		return ""
	}
}

func applyHotUpdateDeliveryModeFilter(query *gorm.DB, deliveryMode string) *gorm.DB {
	if deliveryMode == models.HotUpdatePatchDeliveryModeSelfHosted {
		return query.Where("(delivery_mode = ? OR delivery_mode = '' OR delivery_mode IS NULL)", deliveryMode)
	}
	return query.Where("delivery_mode = ?", deliveryMode)
}

func parseHotUpdateBoolFlag(raw string) bool {
	switch strings.ToLower(strings.TrimSpace(raw)) {
	case "1", "true", "yes", "y", "on":
		return true
	default:
		return false
	}
}

func (h *HotUpdateHandler) loadClientCompletedPatchIDs(candidates []models.HotUpdatePatch, deviceID, userUUID string) (map[uint64]struct{}, error) {
	completed := make(map[uint64]struct{})
	if len(candidates) == 0 {
		return completed, nil
	}

	scopedDeviceID := strings.TrimSpace(deviceID)
	scopedUserUUID := strings.TrimSpace(userUUID)
	if scopedDeviceID == "" && scopedUserUUID == "" {
		return completed, nil
	}

	patchIDs := make([]uint64, 0, len(candidates))
	for _, patch := range candidates {
		if patch.ID == 0 {
			continue
		}
		patchIDs = append(patchIDs, patch.ID)
	}
	if len(patchIDs) == 0 {
		return completed, nil
	}

	statuses := []string{
		models.HotUpdatePatchReportStatusInstallConfirmed,
		models.HotUpdatePatchReportStatusApplySuccess,
	}
	query := h.db.
		Model(&models.HotUpdatePatchReport{}).
		Where("patch_id IN ?", patchIDs).
		Where("status IN ?", statuses)
	if scopedDeviceID != "" {
		query = query.Where("device_id = ?", scopedDeviceID)
	} else {
		query = query.Where("user_uuid = ?", scopedUserUUID)
	}

	var installedIDs []uint64
	if err := query.Distinct("patch_id").Pluck("patch_id", &installedIDs).Error; err != nil {
		return nil, err
	}
	for _, id := range installedIDs {
		completed[id] = struct{}{}
	}
	return completed, nil
}

func normalizeHotUpdateReportStatus(status string) string {
	switch strings.ToLower(strings.TrimSpace(status)) {
	case models.HotUpdatePatchReportStatusCheckHit:
		return models.HotUpdatePatchReportStatusCheckHit
	case models.HotUpdatePatchReportStatusDeferred:
		return models.HotUpdatePatchReportStatusDeferred
	case models.HotUpdatePatchReportStatusApplySuccess:
		return models.HotUpdatePatchReportStatusApplySuccess
	case models.HotUpdatePatchReportStatusInstallStarted:
		return models.HotUpdatePatchReportStatusInstallStarted
	case models.HotUpdatePatchReportStatusInstallConfirmed:
		return models.HotUpdatePatchReportStatusInstallConfirmed
	case models.HotUpdatePatchReportStatusApplyFailed:
		return models.HotUpdatePatchReportStatusApplyFailed
	case models.HotUpdatePatchReportStatusSDKNotIntegrated:
		return models.HotUpdatePatchReportStatusSDKNotIntegrated
	case models.HotUpdatePatchReportStatusSDKNotAvailable:
		return models.HotUpdatePatchReportStatusSDKNotAvailable
	default:
		return ""
	}
}

func truncateText(input string, maxRunes int) string {
	if maxRunes <= 0 {
		return ""
	}
	items := []rune(input)
	if len(items) <= maxRunes {
		return input
	}
	return string(items[:maxRunes])
}

func clampNonNegative(v int) int {
	if v < 0 {
		return 0
	}
	return v
}

func isPatchEligibleForClient(patch models.HotUpdatePatch, appVersion string, buildNumber int, now time.Time) bool {
	if patch.RolloutPercentage <= 0 {
		return false
	}
	if patch.StartAt != nil && now.Before(*patch.StartAt) {
		return false
	}
	if patch.EndAt != nil && now.After(*patch.EndAt) {
		return false
	}

	version := strings.TrimSpace(appVersion)
	if patch.MinAppVersion != "" && compareVersion(version, patch.MinAppVersion) < 0 {
		return false
	}
	if patch.MaxAppVersion != "" && compareVersion(version, patch.MaxAppVersion) > 0 {
		return false
	}
	if patch.MinBuildNumber > 0 && buildNumber > 0 && buildNumber < patch.MinBuildNumber {
		return false
	}
	if patch.MaxBuildNumber > 0 && buildNumber > patch.MaxBuildNumber {
		return false
	}
	if targetVersion := strings.TrimSpace(patch.TargetAppVersion); targetVersion != "" {
		currentVersion := strings.TrimSpace(appVersion)
		if currentVersion == "" {
			currentVersion = "0.0.0"
		}
		if buildNumber > 0 {
			currentVersion = currentVersion + "+" + strconv.Itoa(buildNumber)
		}
		if compareVersion(currentVersion, targetVersion) >= 0 {
			return false
		}
	}
	return true
}

func buildRolloutSeed(patchID, userUUID, deviceID, clientIP string) string {
	base := strings.TrimSpace(userUUID)
	if base == "" {
		base = strings.TrimSpace(deviceID)
	}
	if base == "" {
		base = strings.TrimSpace(clientIP)
	}
	if base == "" {
		base = "anonymous"
	}
	if strings.TrimSpace(patchID) == "" {
		patchID = "patch"
	}
	return patchID + "|" + base
}

func isInRollout(seed string, percentage int) (bool, int) {
	hasher := fnv.New32a()
	_, _ = hasher.Write([]byte(seed))
	bucket := int(hasher.Sum32() % 100)
	if percentage >= 100 {
		return true, bucket
	}
	if percentage <= 0 {
		return false, bucket
	}
	return bucket < percentage, bucket
}

var versionDigitPattern = regexp.MustCompile(`\d+`)
var hotUpdateHashPattern = regexp.MustCompile(`^(?i:(sha256:[a-f0-9]{64}|sha1:[a-f0-9]{40}|md5:[a-f0-9]{32}|[a-f0-9]{64}|[a-f0-9]{40}|[a-f0-9]{32}))$`)

func validateHotUpdatePatchURL(platform, raw string) error {
	value := strings.TrimSpace(raw)
	if value == "" {
		return nil
	}
	if !strings.Contains(value, "://") {
		value = "https://" + value
	}

	parsed, err := url.Parse(value)
	if err != nil || parsed == nil || parsed.Scheme == "" {
		return errText("invalid patch_url format")
	}

	scheme := strings.ToLower(strings.TrimSpace(parsed.Scheme))
	switch scheme {
	case "http", "https":
		if platform == models.HotUpdatePatchPlatformIOS &&
			!strings.HasSuffix(strings.ToLower(parsed.Path), ".plist") {
			return errText("ios patch_url must be a manifest.plist or itms-services link")
		}
	case "itms-services":
		if platform == models.HotUpdatePatchPlatformAndroid {
			return errText("android does not support itms-services patch_url")
		}
		embeddedURL := strings.TrimSpace(parsed.Query().Get("url"))
		if embeddedURL == "" {
			return errText("ios patch_url must contain a manifest.plist url")
		}
		decodedURL, err := url.QueryUnescape(embeddedURL)
		if err == nil && strings.TrimSpace(decodedURL) != "" {
			embeddedURL = strings.TrimSpace(decodedURL)
		}
		embeddedParsed, err := url.Parse(embeddedURL)
		if err != nil || embeddedParsed == nil {
			return errText("ios patch_url must contain a valid manifest.plist url")
		}
		embeddedScheme := strings.ToLower(strings.TrimSpace(embeddedParsed.Scheme))
		if embeddedScheme != "http" && embeddedScheme != "https" {
			return errText("ios patch_url must point to an http/https manifest.plist url")
		}
		if !strings.HasSuffix(strings.ToLower(embeddedParsed.Path), ".plist") {
			return errText("ios patch_url must point to a manifest.plist url")
		}
	default:
		return errText("patch_url only supports http/https, and iOS also supports itms-services")
	}

	return nil
}
func validateHotUpdatePatchHash(raw string) error {
	value := strings.TrimSpace(raw)
	if value == "" {
		return nil
	}
	if !hotUpdateHashPattern.MatchString(value) {
		return errText("invalid patch_hash format; only sha256/sha1/md5 are supported")
	}
	return nil
}
func compareVersion(left, right string) int {
	leftParts := extractVersionParts(left)
	rightParts := extractVersionParts(right)
	maxLen := len(leftParts)
	if len(rightParts) > maxLen {
		maxLen = len(rightParts)
	}
	for i := 0; i < maxLen; i++ {
		lv := 0
		rv := 0
		if i < len(leftParts) {
			lv = leftParts[i]
		}
		if i < len(rightParts) {
			rv = rightParts[i]
		}
		if lv > rv {
			return 1
		}
		if lv < rv {
			return -1
		}
	}
	return 0
}

func extractVersionParts(input string) []int {
	text := strings.TrimSpace(input)
	if text == "" {
		return []int{0}
	}
	matches := versionDigitPattern.FindAllString(text, -1)
	if len(matches) == 0 {
		return []int{0}
	}
	result := make([]int, 0, len(matches))
	for _, item := range matches {
		v, err := strconv.Atoi(item)
		if err != nil {
			result = append(result, 0)
			continue
		}
		result = append(result, v)
	}
	return result
}
