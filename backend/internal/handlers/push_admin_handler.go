// 文件用途：实现后端 HTTP 接口的请求处理和统一响应。
// 核心逻辑：绑定参数，校验身份与权限，调用业务服务并持久化关键状态。

package handlers

import (
	"github.com/gin-gonic/gin"
	"gorm.io/gorm"
	"net/http"
	"strconv"
	"strings"
	"time"
	"genericim/internal/models"
	"genericim/internal/services"
	"genericim/pkg/response"
)

type PushAdminHandler struct {
	db   *gorm.DB
	push *services.PushService
}

func NewPushAdminHandler(db *gorm.DB, push *services.PushService) *PushAdminHandler {
	return &PushAdminHandler{db: db, push: push}
}

var invalidPushTokenErrorPattern = "invalid|unregistered|baddevicetoken|not[ _-]?registered"

func (h *PushAdminHandler) SendTest(c *gin.Context) {
	if h.push == nil {
		response.Error(c, http.StatusServiceUnavailable, "推送服务未初始化")
		return
	}

	var req struct {
		UserID   uint64                 `json:"user_id"`
		DeviceID uint64                 `json:"device_id"`
		Scene    string                 `json:"scene"`
		Title    string                 `json:"title"`
		Body     string                 `json:"body"`
		Data     map[string]interface{} `json:"data"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		response.BadRequest(c, "参数错误")
		return
	}
	scene := strings.TrimSpace(req.Scene)
	if scene == "" {
		scene = "system_notice"
	}
	title := strings.TrimSpace(req.Title)
	if title == "" {
		title = "推送测试"
	}
	body := strings.TrimSpace(req.Body)
	if body == "" {
		body = "这是一条后台推送测试消息"
	}
	data := req.Data
	if data == nil {
		data = map[string]interface{}{}
	}
	data["type"] = scene
	data["scene"] = scene
	data["tested_at"] = formatAdminTime(time.Now())

	var submitted int64
	if req.DeviceID > 0 {
		var device models.UserDevice
		if err := h.db.First(&device, req.DeviceID).Error; err != nil {
			response.Error(c, http.StatusNotFound, "设备不存在")
			return
		}
		if strings.TrimSpace(device.PushToken) == "" {
			response.Error(c, http.StatusBadRequest, "设备没有绑定推送 token")
			return
		}
		if err := h.push.PushToDevice(device, title, body, data); err != nil {
			response.Error(c, http.StatusBadRequest, err.Error())
			return
		}
		submitted = 1
	} else {
		if req.UserID == 0 {
			response.BadRequest(c, "请选择用户或设备")
			return
		}
		var user models.User
		if err := h.db.First(&user, req.UserID).Error; err != nil {
			response.Error(c, http.StatusNotFound, "用户不存在")
			return
		}
		if err := h.db.Model(&models.UserDevice{}).
			Where("user_id = ? AND push_token != ''", user.ID).
			Count(&submitted).Error; err != nil {
			response.Error(c, http.StatusInternalServerError, "查询推送设备失败")
			return
		}
		if submitted == 0 {
			response.Error(c, http.StatusBadRequest, "用户没有绑定推送 token")
			return
		}
		if err := h.push.PushToUser(user.ID, title, body, data); err != nil {
			response.Error(c, http.StatusInternalServerError, err.Error())
			return
		}
	}
	response.Success(c, gin.H{
		"submitted_devices": submitted,
		"scene":             scene,
		"submitted_at":      formatAdminTime(time.Now()),
	})
}

func (h *PushAdminHandler) ListLogs(c *gin.Context) {
	page, _ := strconv.Atoi(c.DefaultQuery("page", "1"))
	pageSize, _ := strconv.Atoi(c.DefaultQuery("page_size", "20"))
	if page <= 0 {
		page = 1
	}
	if pageSize <= 0 || pageSize > 100 {
		pageSize = 20
	}
	query := h.db.Model(&models.PushDeliveryLog{})
	if userID := strings.TrimSpace(c.Query("user_id")); userID != "" {
		query = query.Where("user_id = ?", userID)
	}
	if deviceID := strings.TrimSpace(c.Query("device_id")); deviceID != "" {
		query = query.Where("device_id = ?", deviceID)
	}
	if channel := strings.TrimSpace(c.Query("channel")); channel != "" {
		query = query.Where("channel = ?", channel)
	}
	if success := strings.TrimSpace(c.Query("success")); success != "" {
		query = query.Where("success = ?", success == "1" || strings.EqualFold(success, "true"))
	}

	var total int64
	if err := query.Count(&total).Error; err != nil {
		response.Error(c, http.StatusInternalServerError, "查询推送日志失败")
		return
	}

	var logs []models.PushDeliveryLog
	if err := query.Order("occurred_at DESC, id DESC").
		Offset((page - 1) * pageSize).
		Limit(pageSize).
		Find(&logs).Error; err != nil {
		response.Error(c, http.StatusInternalServerError, "查询推送日志失败")
		return
	}
	list := make([]gin.H, 0, len(logs))
	for _, item := range logs {
		list = append(list, gin.H{
			"id":          item.ID,
			"user_id":     item.UserID,
			"device_id":   item.DeviceID,
			"device_key":  item.DeviceKey,
			"channel":     item.Channel,
			"provider":    item.Provider,
			"scene":       item.Scene,
			"request_id":  item.RequestID,
			"success":     item.Success,
			"error":       item.Error,
			"title":       item.Title,
			"body":        item.Body,
			"occurred_at": formatAdminTime(item.OccurredAt),
		})
	}
	response.Success(c, gin.H{
		"list":      list,
		"total":     total,
		"page":      page,
		"page_size": pageSize,
	})
}

func (h *PushAdminHandler) ListDevices(c *gin.Context) {
	page, _ := strconv.Atoi(c.DefaultQuery("page", "1"))
	pageSize, _ := strconv.Atoi(c.DefaultQuery("page_size", "20"))
	if page <= 0 {
		page = 1
	}
	if pageSize <= 0 || pageSize > 100 {
		pageSize = 20
	}
	query := h.db.Model(&models.UserDevice{})
	if userID := strings.TrimSpace(c.Query("user_id")); userID != "" {
		query = query.Where("user_id = ?", userID)
	}
	if channel := strings.TrimSpace(c.Query("channel")); channel != "" {
		query = query.Where("push_channel = ?", channel)
	}
	if bound := strings.TrimSpace(c.Query("bound")); bound != "" {
		if bound == "1" || strings.EqualFold(bound, "true") {
			query = query.Where("push_token IS NOT NULL AND push_token != ''")
		} else if bound == "0" || strings.EqualFold(bound, "false") {
			query = query.Where("push_token = '' OR push_token IS NULL")
		}
	}
	if keyword := strings.TrimSpace(c.Query("keyword")); keyword != "" {
		like := "%" + keyword + "%"
		query = query.Where(
			"device_id LIKE ? OR device_name LIKE ? OR brand LIKE ? OR model LIKE ? OR app_version LIKE ?",
			like, like, like, like, like,
		)
	}

	var total int64
	if err := query.Count(&total).Error; err != nil {
		response.Error(c, http.StatusInternalServerError, "查询推送设备失败")
		return
	}

	var devices []models.UserDevice
	if err := query.Order("last_active DESC, id DESC").
		Offset((page - 1) * pageSize).
		Limit(pageSize).
		Find(&devices).Error; err != nil {
		response.Error(c, http.StatusInternalServerError, "查询推送设备失败")
		return
	}
	deviceIDs := make([]uint64, 0, len(devices))
	userIDs := make([]uint64, 0, len(devices))
	for _, item := range devices {
		deviceIDs = append(deviceIDs, item.ID)
		userIDs = append(userIDs, item.UserID)
	}
	usersByID := make(map[uint64]models.User, len(userIDs))
	if len(userIDs) > 0 {
		var users []models.User
		_ = h.db.Where("id IN ?", userIDs).Find(&users).Error
		for _, user := range users {
			usersByID[user.ID] = user
		}
	}
	latestPushByDevice := make(map[uint64]models.PushDeliveryLog, len(deviceIDs))
	if len(deviceIDs) > 0 {
		var logs []models.PushDeliveryLog
		_ = h.db.Where("device_id IN ?", deviceIDs).
			Order("occurred_at DESC, id DESC").
			Find(&logs).Error
		for _, item := range logs {
			if _, exists := latestPushByDevice[item.DeviceID]; !exists {
				latestPushByDevice[item.DeviceID] = item
			}
		}
	}
	sevenDaysAgo := time.Now().Add(-7 * 24 * time.Hour)
	failureCountByDevice := make(map[uint64]int64, len(deviceIDs))
	if len(deviceIDs) > 0 {
		type failureCountRow struct {
			DeviceID uint64 `gorm:"column:device_id"`
			Count    int64  `gorm:"column:count"`
		}
		var rows []failureCountRow
		_ = h.db.Model(&models.PushDeliveryLog{}).
			Select("device_id, COUNT(*) AS count").
			Where("device_id IN ? AND success = ? AND occurred_at >= ?", deviceIDs, false, sevenDaysAgo).
			Group("device_id").
			Scan(&rows).Error
		for _, item := range rows {
			failureCountByDevice[item.DeviceID] = item.Count
		}
	}
	list := make([]gin.H, 0, len(devices))
	for _, item := range devices {
		pushToken := strings.TrimSpace(item.PushToken)
		row := gin.H{
			"id":                    item.ID,
			"user_id":               item.UserID,
			"device_id":             item.DeviceID,
			"device_type":           item.DeviceType,
			"brand":                 item.Brand,
			"model":                 item.Model,
			"push_channel":          item.PushChannel,
			"device_name":           item.DeviceName,
			"app_version":           item.AppVersion,
			"push_token_bound":      pushToken != "",
			"push_token_length":     len(pushToken),
			"push_token_updated_at": formatAdminTimePtr(item.PushTokenUpdatedAt),
			"ip":                    item.IP,
			"last_active":           formatAdminTime(item.LastActive),
			"created_at":            formatAdminTime(item.CreatedAt),
			"failed_7d":             failureCountByDevice[item.ID],
		}
		if user, ok := usersByID[item.UserID]; ok {
			row["user"] = gin.H{
				"id":       user.ID,
				"uuid":     user.UUID,
				"username": user.Username,
				"nickname": user.Nickname,
				"status":   user.Status,
			}
		}
		if latestPush, ok := latestPushByDevice[item.ID]; ok {
			row["last_push"] = gin.H{
				"id":          latestPush.ID,
				"channel":     latestPush.Channel,
				"scene":       latestPush.Scene,
				"success":     latestPush.Success,
				"error":       latestPush.Error,
				"occurred_at": formatAdminTime(latestPush.OccurredAt),
			}
		}
		list = append(list, row)
	}
	response.Success(c, gin.H{
		"list":      list,
		"total":     total,
		"page":      page,
		"page_size": pageSize,
	})
}

func (h *PushAdminHandler) DisableDeviceToken(c *gin.Context) {
	deviceID := c.Param("id")
	var device models.UserDevice
	if err := h.db.First(&device, deviceID).Error; err != nil {
		response.Error(c, http.StatusNotFound, "设备不存在")
		return
	}
	if strings.TrimSpace(device.PushToken) == "" {
		response.Success(c, gin.H{
			"id":       device.ID,
			"disabled": false,
			"message":  "设备没有绑定推送 token",
		})
		return
	}
	if err := h.db.Model(&models.UserDevice{}).
		Where("id = ?", device.ID).
		Updates(map[string]interface{}{
			"push_token":            "",
			"push_token_hash":       nil,
			"push_token_updated_at": nil,
		}).Error; err != nil {
		response.Error(c, http.StatusInternalServerError, "停用推送 token 失败")
		return
	}
	now := time.Now()
	_ = h.db.Create(&models.PushDeliveryLog{
		UserID:     device.UserID,
		DeviceID:   device.ID,
		DeviceKey:  device.DeviceID,
		Channel:    device.PushChannel,
		Provider:   device.PushChannel,
		Scene:      "admin_disable_token",
		Success:    false,
		Error:      "admin disabled push token",
		Title:      "推送 token 已停用",
		Body:       "管理员在后台停用了该设备推送 token",
		OccurredAt: now,
		CreatedAt:  now,
	}).Error

	response.Success(c, gin.H{
		"id":          device.ID,
		"user_id":     device.UserID,
		"device_key":  device.DeviceID,
		"channel":     device.PushChannel,
		"disabled":    true,
		"disabled_at": formatAdminTime(now),
	})
}

func (h *PushAdminHandler) CleanupInvalidDeviceTokens(c *gin.Context) {
	var req struct {
		Hours       int    `json:"hours"`
		MinFailures int    `json:"min_failures"`
		Channel     string `json:"channel"`
		Confirm     bool   `json:"confirm"`
		DryRun      bool   `json:"dry_run"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		response.BadRequest(c, "参数错误")
		return
	}
	if !req.Confirm && !req.DryRun {
		response.BadRequest(c, "请先确认清理操作")
		return
	}
	if req.Hours <= 0 || req.Hours > 720 {
		req.Hours = 168
	}
	if req.MinFailures <= 0 || req.MinFailures > 20 {
		req.MinFailures = 3
	}
	since := time.Now().Add(-time.Duration(req.Hours) * time.Hour)
	channel := strings.TrimSpace(req.Channel)

	type candidateRow struct {
		DeviceID     uint64 `gorm:"column:device_id"`
		FailureCount int64  `gorm:"column:failure_count"`
	}
	candidateQuery := h.db.Model(&models.PushDeliveryLog{}).
		Select("device_id, COUNT(*) AS failure_count").
		Where("occurred_at >= ? AND success = ? AND device_id > 0 AND LOWER(error) REGEXP ?", since, false, invalidPushTokenErrorPattern)
	if channel != "" {
		candidateQuery = candidateQuery.Where("channel = ?", channel)
	}
	var candidates []candidateRow
	if err := candidateQuery.Group("device_id").
		Having("COUNT(*) >= ?", req.MinFailures).
		Scan(&candidates).Error; err != nil {
		response.Error(c, http.StatusInternalServerError, "查询无效 token 失败")
		return
	}
	candidateIDs := make([]uint64, 0, len(candidates))
	failureCountByID := make(map[uint64]int64, len(candidates))
	for _, item := range candidates {
		candidateIDs = append(candidateIDs, item.DeviceID)
		failureCountByID[item.DeviceID] = item.FailureCount
	}

	var devices []models.UserDevice
	if len(candidateIDs) > 0 {
		query := h.db.Where("id IN ? AND push_token IS NOT NULL AND push_token != ''", candidateIDs)
		if channel != "" {
			query = query.Where("push_channel = ?", channel)
		}
		if err := query.Find(&devices).Error; err != nil {
			response.Error(c, http.StatusInternalServerError, "查询设备失败")
			return
		}
	}
	deviceIDs := make([]uint64, 0, len(devices))
	items := make([]gin.H, 0, len(devices))
	for _, device := range devices {
		deviceIDs = append(deviceIDs, device.ID)
		items = append(items, gin.H{
			"id":                device.ID,
			"user_id":           device.UserID,
			"device_key":        device.DeviceID,
			"channel":           device.PushChannel,
			"failure_count":     failureCountByID[device.ID],
			"last_active":       formatAdminTime(device.LastActive),
			"token_updated_at":  formatAdminTimePtr(device.PushTokenUpdatedAt),
			"push_token_length": len(strings.TrimSpace(device.PushToken)),
		})
	}
	cleared := int64(0)
	if !req.DryRun && len(deviceIDs) > 0 {
		result := h.db.Model(&models.UserDevice{}).
			Where("id IN ?", deviceIDs).
			Updates(map[string]interface{}{
				"push_token":            "",
				"push_token_hash":       nil,
				"push_token_updated_at": nil,
			})
		if result.Error != nil {
			response.Error(c, http.StatusInternalServerError, "清理无效 token 失败")
			return
		}
		cleared = result.RowsAffected
		now := time.Now()
		for _, device := range devices {
			_ = h.db.Create(&models.PushDeliveryLog{
				UserID:     device.UserID,
				DeviceID:   device.ID,
				DeviceKey:  device.DeviceID,
				Channel:    device.PushChannel,
				Provider:   device.PushChannel,
				Scene:      "admin_cleanup_invalid_token",
				Success:    false,
				Error:      "admin cleaned invalid push token",
				Title:      "推送 token 已清理",
				Body:       "后台按无效 token 失败规则清理",
				OccurredAt: now,
				CreatedAt:  now,
			}).Error
		}
	}
	response.Success(c, gin.H{
		"dry_run":       req.DryRun,
		"hours":         req.Hours,
		"min_failures":  req.MinFailures,
		"channel":       channel,
		"matched_count": len(devices),
		"cleared_count": cleared,
		"items":         items,
	})
}

func (h *PushAdminHandler) Stats(c *gin.Context) {
	hours, _ := strconv.Atoi(c.DefaultQuery("hours", "24"))
	if hours <= 0 || hours > 168 {
		hours = 24
	}
	since := time.Now().Add(-time.Duration(hours) * time.Hour)

	var summary struct {
		Total   int64 `gorm:"column:total"`
		Success int64 `gorm:"column:success"`
		Failed  int64 `gorm:"column:failed"`
	}
	if err := h.db.Model(&models.PushDeliveryLog{}).
		Select("COUNT(*) AS total, COALESCE(SUM(CASE WHEN success = 1 THEN 1 ELSE 0 END), 0) AS success, COALESCE(SUM(CASE WHEN success = 0 THEN 1 ELSE 0 END), 0) AS failed").
		Where("occurred_at >= ?", since).
		Scan(&summary).Error; err != nil {
		response.Error(c, http.StatusInternalServerError, "查询推送统计失败")
		return
	}
	successRate := 0.0
	if summary.Total > 0 {
		successRate = float64(summary.Success) * 100 / float64(summary.Total)
	}

	type aggregateRow struct {
		Name    string  `gorm:"column:name" json:"name"`
		Total   int64   `gorm:"column:total" json:"total"`
		Success int64   `gorm:"column:success" json:"success"`
		Failed  int64   `gorm:"column:failed" json:"failed"`
		Rate    float64 `json:"rate"`
	}
	scanAggregate := func(columnExpr string, args ...interface{}) []aggregateRow {
		rows := make([]aggregateRow, 0)
		query := h.db.Model(&models.PushDeliveryLog{}).
			Select(columnExpr+" AS name, COUNT(*) AS total, COALESCE(SUM(CASE WHEN success = 1 THEN 1 ELSE 0 END), 0) AS success, COALESCE(SUM(CASE WHEN success = 0 THEN 1 ELSE 0 END), 0) AS failed").
			Where("occurred_at >= ?", since)
		if len(args) > 0 {
			query = query.Where(args[0], args[1:]...)
		}
		if err := query.Group("name").Order("total DESC").Limit(20).Scan(&rows).Error; err != nil {
			return []aggregateRow{}
		}
		for i := range rows {
			if strings.TrimSpace(rows[i].Name) == "" {
				rows[i].Name = "unknown"
			}
			if rows[i].Total > 0 {
				rows[i].Rate = float64(rows[i].Success) * 100 / float64(rows[i].Total)
			}
		}
		return rows
	}
	channelStats := scanAggregate("COALESCE(NULLIF(channel, ''), 'unknown')")
	sceneStats := scanAggregate("COALESCE(NULLIF(scene, ''), 'unknown')")
	versionStats := make([]aggregateRow, 0)
	_ = h.db.Model(&models.PushDeliveryLog{}).
		Joins("LEFT JOIN user_devices ON user_devices.id = push_delivery_logs.device_id").
		Select("COALESCE(NULLIF(user_devices.app_version, ''), 'unknown') AS name, COUNT(*) AS total, COALESCE(SUM(CASE WHEN push_delivery_logs.success = 1 THEN 1 ELSE 0 END), 0) AS success, COALESCE(SUM(CASE WHEN push_delivery_logs.success = 0 THEN 1 ELSE 0 END), 0) AS failed").
		Where("push_delivery_logs.occurred_at >= ?", since).
		Group("name").
		Order("total DESC").
		Limit(10).
		Scan(&versionStats).Error
	for i := range versionStats {
		if versionStats[i].Total > 0 {
			versionStats[i].Rate = float64(versionStats[i].Success) * 100 / float64(versionStats[i].Total)
		}
	}

	var invalidDeviceCount int64
	_ = h.db.Model(&models.UserDevice{}).
		Where("push_token = '' OR push_token IS NULL").
		Count(&invalidDeviceCount).Error

	var invalidTokenFailures int64
	_ = h.db.Model(&models.PushDeliveryLog{}).
		Where("occurred_at >= ? AND success = 0 AND LOWER(error) REGEXP ?", since, invalidPushTokenErrorPattern).
		Count(&invalidTokenFailures).Error

	var recentFailures []models.PushDeliveryLog
	_ = h.db.Where("occurred_at >= ? AND success = 0", since).
		Order("occurred_at DESC, id DESC").
		Limit(8).
		Find(&recentFailures).Error
	recentFailureList := make([]gin.H, 0, len(recentFailures))
	for _, item := range recentFailures {
		recentFailureList = append(recentFailureList, gin.H{
			"id":          item.ID,
			"user_id":     item.UserID,
			"device_id":   item.DeviceID,
			"device_key":  item.DeviceKey,
			"channel":     item.Channel,
			"scene":       item.Scene,
			"error":       item.Error,
			"occurred_at": formatAdminTime(item.OccurredAt),
		})
	}
	unhealthyChannels := 0
	for _, item := range channelStats {
		if item.Total >= 5 && item.Rate < 80 {
			unhealthyChannels++
		}
	}
	response.Success(c, gin.H{
		"hours":                  hours,
		"total":                  summary.Total,
		"success":                summary.Success,
		"failed":                 summary.Failed,
		"success_rate":           successRate,
		"invalid_device_count":   invalidDeviceCount,
		"invalid_token_failures": invalidTokenFailures,
		"unhealthy_channels":     unhealthyChannels,
		"channel_stats":          channelStats,
		"scene_stats":            sceneStats,
		"app_version_stats":      versionStats,
		"recent_failures":        recentFailureList,
	})
}
