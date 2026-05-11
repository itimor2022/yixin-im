package handlers

import (
	"net/http"
	"time"

	"gaoranim/internal/models"
	"gaoranim/pkg/response"

	"github.com/gin-gonic/gin"
	"gorm.io/gorm"
)

type CallAdminHandler struct {
	db *gorm.DB
}

func NewCallAdminHandler(db *gorm.DB) *CallAdminHandler {
	return &CallAdminHandler{db: db}
}

// ListCalls 获取通话记录列表
func (h *CallAdminHandler) ListCalls(c *gin.Context) {
	page := getQueryInt(c, "page", 1)
	pageSize := getQueryInt(c, "page_size", 20)
	callType := c.Query("type")     // audio, video
	status := c.Query("status")     // pending, ringing, connected, ended, missed, rejected, cancelled
	userID := c.Query("user_id")
	startDate := c.Query("start_date")
	endDate := c.Query("end_date")

	query := h.db.Model(&models.Call{})

	if callType != "" {
		query = query.Where("call_type = ?", callType)
	}

	if status != "" {
		query = query.Where("status = ?", status)
	}

	if userID != "" {
		var user models.User
		if h.db.Where("uuid = ?", userID).First(&user).Error == nil {
			query = query.Where("caller_id = ? OR callee_id = ?", user.ID, user.ID)
		}
	}

	if startDate != "" {
		if t, err := time.Parse("2006-01-02", startDate); err == nil {
			query = query.Where("created_at >= ?", t)
		}
	}

	if endDate != "" {
		if t, err := time.Parse("2006-01-02", endDate); err == nil {
			query = query.Where("created_at < ?", t.AddDate(0, 0, 1))
		}
	}

	var total int64
	query.Count(&total)

	var calls []models.Call
	query.Order("created_at DESC").
		Offset((page - 1) * pageSize).
		Limit(pageSize).
		Find(&calls)

	result := make([]gin.H, len(calls))
	for i, call := range calls {
		var caller, callee models.User
		h.db.First(&caller, call.CallerID)
		h.db.First(&callee, call.CalleeID)

		result[i] = gin.H{
			"id":            call.ID,
			"channel_name":  call.ChannelName,
			"type":          call.CallType,
			"status":        call.Status,
			"caller_id":     caller.UUID,
			"caller_name":   caller.Nickname,
			"caller_avatar": caller.Avatar,
			"callee_id":     callee.UUID,
			"callee_name":   callee.Nickname,
			"callee_avatar": callee.Avatar,
			"duration":      call.Duration,
			"started_at":    call.StartTime,
			"ended_at":      call.EndTime,
			"created_at":    call.CreatedAt,
		}
	}

	response.Success(c, gin.H{
		"list":      result,
		"total":     total,
		"page":      page,
		"page_size": pageSize,
	})
}

// GetCallDetail 获取通话详情
func (h *CallAdminHandler) GetCallDetail(c *gin.Context) {
	callID := c.Param("id")

	var call models.Call
	if err := h.db.First(&call, callID).Error; err != nil {
		response.Error(c, http.StatusNotFound, "通话记录不存在")
		return
	}

	var caller, callee models.User
	h.db.First(&caller, call.CallerID)
	h.db.First(&callee, call.CalleeID)

	response.Success(c, gin.H{
		"id":            call.ID,
		"channel_name":  call.ChannelName,
		"type":          call.CallType,
		"status":        call.Status,
		"caller_id":     caller.UUID,
		"caller_name":   caller.Nickname,
		"caller_avatar": caller.Avatar,
		"callee_id":     callee.UUID,
		"callee_name":   callee.Nickname,
		"callee_avatar": callee.Avatar,
		"duration":      call.Duration,
		"started_at":    call.StartTime,
		"ended_at":      call.EndTime,
		"created_at":    call.CreatedAt,
	})
}

// GetCallStats 获取通话统计
func (h *CallAdminHandler) GetCallStats(c *gin.Context) {
	var totalCalls, audioCalls, videoCalls int64
	var connectedCalls, missedCalls, rejectedCalls, cancelledCalls int64
	var totalDuration int64

	h.db.Model(&models.Call{}).Count(&totalCalls)
	h.db.Model(&models.Call{}).Where("call_type = ?", "voice").Count(&audioCalls)
	h.db.Model(&models.Call{}).Where("call_type = ?", "video").Count(&videoCalls)

	h.db.Model(&models.Call{}).Where("status = ?", "ended").Count(&connectedCalls)
	h.db.Model(&models.Call{}).Where("status = ?", "missed").Count(&missedCalls)
	h.db.Model(&models.Call{}).Where("status = ?", "rejected").Count(&rejectedCalls)
	h.db.Model(&models.Call{}).Where("status = ?", "cancelled").Count(&cancelledCalls)

	h.db.Model(&models.Call{}).Where("status = ?", "ended").Select("COALESCE(SUM(duration), 0)").Scan(&totalDuration)

	// 今日统计
	today := time.Now().Truncate(24 * time.Hour)
	var todayCalls, todayConnected int64
	var todayDuration int64
	h.db.Model(&models.Call{}).Where("created_at >= ?", today).Count(&todayCalls)
	h.db.Model(&models.Call{}).Where("created_at >= ? AND status = ?", today, "ended").Count(&todayConnected)
	h.db.Model(&models.Call{}).Where("created_at >= ? AND status = ?", today, "ended").Select("COALESCE(SUM(duration), 0)").Scan(&todayDuration)

	response.Success(c, gin.H{
		"total_calls":     totalCalls,
		"audio_calls":     audioCalls,
		"video_calls":     videoCalls,
		"connected_calls": connectedCalls,
		"missed_calls":    missedCalls,
		"rejected_calls":  rejectedCalls,
		"cancelled_calls": cancelledCalls,
		"total_duration":  totalDuration,
		"today_calls":     todayCalls,
		"today_connected": todayConnected,
		"today_duration":  todayDuration,
	})
}

// GetUserCallHistory 获取用户通话记录
func (h *CallAdminHandler) GetUserCallHistory(c *gin.Context) {
	userUUID := c.Param("user_id")
	page := getQueryInt(c, "page", 1)
	pageSize := getQueryInt(c, "page_size", 20)

	var user models.User
	if err := h.db.Where("uuid = ?", userUUID).First(&user).Error; err != nil {
		response.Error(c, http.StatusNotFound, "用户不存在")
		return
	}

	query := h.db.Model(&models.Call{}).Where("caller_id = ? OR callee_id = ?", user.ID, user.ID)

	var total int64
	query.Count(&total)

	var calls []models.Call
	query.Order("created_at DESC").
		Offset((page - 1) * pageSize).
		Limit(pageSize).
		Find(&calls)

	result := make([]gin.H, len(calls))
	for i, call := range calls {
		var caller, callee models.User
		h.db.First(&caller, call.CallerID)
		h.db.First(&callee, call.CalleeID)

		// 判断用户是主叫还是被叫
		isOutgoing := call.CallerID == user.ID
		var otherUser models.User
		if isOutgoing {
			otherUser = callee
		} else {
			otherUser = caller
		}

		result[i] = gin.H{
			"id":               call.ID,
			"type":             call.CallType,
			"status":           call.Status,
			"is_outgoing":      isOutgoing,
			"other_user_id":    otherUser.UUID,
			"other_user_name":  otherUser.Nickname,
			"other_user_avatar": otherUser.Avatar,
			"duration":         call.Duration,
			"created_at":       call.CreatedAt,
		}
	}

	response.Success(c, gin.H{
		"user_id":   user.UUID,
		"user_name": user.Nickname,
		"list":      result,
		"total":     total,
		"page":      page,
		"page_size": pageSize,
	})
}

// DeleteCall 删除通话记录
func (h *CallAdminHandler) DeleteCall(c *gin.Context) {
	callID := c.Param("id")

	if err := h.db.Delete(&models.Call{}, callID).Error; err != nil {
		response.Error(c, http.StatusInternalServerError, "删除失败")
		return
	}

	response.Success(c, gin.H{"message": "删除成功"})
}

// BatchDeleteCalls 批量删除通话记录
func (h *CallAdminHandler) BatchDeleteCalls(c *gin.Context) {
	var req struct {
		IDs []uint64 `json:"ids" binding:"required"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		response.Error(c, http.StatusBadRequest, "参数错误")
		return
	}

	if err := h.db.Delete(&models.Call{}, req.IDs).Error; err != nil {
		response.Error(c, http.StatusInternalServerError, "删除失败")
		return
	}

	response.Success(c, gin.H{
		"message": "删除成功",
		"count":   len(req.IDs),
	})
}
