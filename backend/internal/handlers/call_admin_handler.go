// 文件用途：实现后端 HTTP 接口的请求处理和统一响应。
// 核心逻辑：绑定参数，校验身份与权限，调用业务服务并持久化关键状态。

package handlers

import (
	"context"
	"encoding/json"
	"errors"
	"github.com/gin-gonic/gin"
	"gorm.io/gorm"
	"gorm.io/gorm/clause"
	"net/http"
	"strconv"
	"time"
	"genericim/internal/middleware"
	"genericim/internal/models"
	"genericim/internal/services"
	"genericim/pkg/response"
)

type CallAdminHandler struct {
	db         *gorm.DB
	wsHub      WebSocketHub
	msgService *services.MessageService
}

func NewCallAdminHandler(db *gorm.DB, wsHub ...WebSocketHub) *CallAdminHandler {
	handler := &CallAdminHandler{db: db}
	if len(wsHub) > 0 {
		handler.wsHub = wsHub[0]
	}
	return handler
}

func NewCallAdminHandlerWithServices(db *gorm.DB, wsHub WebSocketHub, msgService *services.MessageService) *CallAdminHandler {
	return &CallAdminHandler{db: db, wsHub: wsHub, msgService: msgService}
}

// ListCalls 获取通话记录列表
func (h *CallAdminHandler) ListCalls(c *gin.Context) {
	page := getQueryInt(c, "page", 1)
	pageSize := getQueryInt(c, "page_size", 20)
	callType := c.Query("type") // audio, video
	status := c.Query("status") // pending, ringing, connected, ended, missed, rejected, cancelled
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

		result[i] = buildCallAdminResponse(call, caller, callee)
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
	result := buildCallAdminResponse(call, caller, callee)
	result["recent_events"] = h.recentCallEvents(call.ID, 20)
	response.Success(c, result)
}

func buildCallAdminResponse(call models.Call, caller, callee models.User) gin.H {
	rtcProvider := effectiveRTCProvider(call.RTCProvider)
	return gin.H{
		"id":                   call.ID,
		"channel_name":         call.ChannelName,
		"room_name":            call.ChannelName,
		"provider":             rtcProvider,
		"rtc_provider":         rtcProvider,
		"type":                 call.CallType,
		"status":               call.Status,
		"caller_id":            caller.UUID,
		"caller_name":          caller.Nickname,
		"caller_avatar":        caller.Avatar,
		"callee_id":            callee.UUID,
		"callee_name":          callee.Nickname,
		"callee_avatar":        callee.Avatar,
		"duration":             call.Duration,
		"end_reason":           call.EndReason,
		"connect_time":         call.ConnectTime,
		"last_heartbeat_at":    call.LastHeartbeatAt,
		"released_by_cleanup":  call.EndReason == "timeout" || call.EndReason == "heartbeat_timeout",
		"replaced_by_new_call": call.EndReason == "client_replaced",
		"started_at":           call.StartTime,
		"ended_at":             call.EndTime,
		"created_at":           call.CreatedAt,
	}
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
		"observability":   callMetrics.Snapshot(),
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
			"id":                call.ID,
			"type":              call.CallType,
			"status":            call.Status,
			"is_outgoing":       isOutgoing,
			"other_user_id":     otherUser.UUID,
			"other_user_name":   otherUser.Nickname,
			"other_user_avatar": otherUser.Avatar,
			"duration":          call.Duration,
			"created_at":        call.CreatedAt,
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

func buildCallEventResponse(event models.CallEvent) gin.H {
	var payload interface{}
	if event.Payload != "" {
		var decoded interface{}
		if err := json.Unmarshal([]byte(event.Payload), &decoded); err == nil {
			payload = decoded
		} else {
			payload = event.Payload
		}
	}

	var actorID interface{}
	if event.ActorID != nil {
		actorID = *event.ActorID
	}
	return gin.H{
		"id":         event.ID,
		"call_id":    event.CallID,
		"event_type": event.EventType,
		"actor_id":   actorID,
		"caller_id":  event.CallerID,
		"callee_id":  event.CalleeID,
		"old_status": event.OldStatus,
		"new_status": event.NewStatus,
		"reason":     event.Reason,
		"duration":   event.Duration,
		"latency_ms": event.LatencyMS,
		"request_id": event.RequestID,
		"payload":    payload,
		"created_at": event.CreatedAt,
	}
}

func (h *CallAdminHandler) recentCallEvents(callID uint, limit int) []gin.H {
	if limit <= 0 {
		limit = 20
	}
	if limit > 100 {
		limit = 100
	}

	var events []models.CallEvent
	h.db.Where("call_id = ?", callID).
		Order("created_at DESC, id DESC").
		Limit(limit).
		Find(&events)
	result := make([]gin.H, len(events))
	for i, event := range events {
		result[i] = buildCallEventResponse(event)
	}
	return result
}

func (h *CallAdminHandler) GetObservabilityMetrics(c *gin.Context) {
	now := time.Now()
	var activeCalls, staleRinging, staleConnected int64
	h.db.Model(&models.Call{}).
		Where("status IN ?", []string{"calling", "connected"}).
		Count(&activeCalls)
	h.db.Model(&models.Call{}).
		Where("status = ? AND start_time <= ?", "calling", now.Add(-callRingingTimeout)).
		Count(&staleRinging)
	h.db.Model(&models.Call{}).
		Where("status = ? AND COALESCE(last_heartbeat_at, connect_time, start_time) <= ?", "connected", now.Add(-callHeartbeatStale)).
		Count(&staleConnected)
	response.Success(c, gin.H{
		"metrics":           callMetrics.Snapshot(),
		"db_active_calls":   activeCalls,
		"stale_ringing":     staleRinging,
		"stale_connected":   staleConnected,
		"stale_candidates":  staleRinging + staleConnected,
		"cleanup_interval":  callCleanupInterval.String(),
		"ringing_timeout":   callRingingTimeout.String(),
		"heartbeat_timeout": callHeartbeatStale.String(),
	})
}

func (h *CallAdminHandler) ListCallEvents(c *gin.Context) {
	page := getQueryInt(c, "page", 1)
	pageSize := getQueryInt(c, "page_size", 20)
	if page < 1 {
		page = 1
	}
	if pageSize < 1 {
		pageSize = 20
	}
	if pageSize > 100 {
		pageSize = 100
	}
	query := h.db.Model(&models.CallEvent{})
	if rawCallID := c.Query("call_id"); rawCallID != "" {
		if callID, err := strconv.ParseUint(rawCallID, 10, 64); err == nil {
			query = query.Where("call_id = ?", callID)
		}
	}
	if eventType := c.Query("event_type"); eventType != "" {
		query = query.Where("event_type = ?", eventType)
	}
	if reason := c.Query("reason"); reason != "" {
		query = query.Where("reason = ?", reason)
	}
	if requestID := c.Query("request_id"); requestID != "" {
		query = query.Where("request_id = ?", requestID)
	}
	if userUUID := c.Query("user_id"); userUUID != "" {
		var user models.User
		if err := h.db.Where("uuid = ?", userUUID).First(&user).Error; err != nil {
			response.Error(c, http.StatusNotFound, "用户不存在")
			return
		}
		query = query.Where("caller_id = ? OR callee_id = ? OR actor_id = ?", user.ID, user.ID, user.ID)
	}

	var total int64
	query.Count(&total)

	var events []models.CallEvent
	query.Order("created_at DESC, id DESC").
		Offset((page - 1) * pageSize).
		Limit(pageSize).
		Find(&events)
	result := make([]gin.H, len(events))
	for i, event := range events {
		result[i] = buildCallEventResponse(event)
	}
	response.Success(c, gin.H{
		"list":      result,
		"total":     total,
		"page":      page,
		"page_size": pageSize,
	})
}

func (h *CallAdminHandler) GetUserActiveCall(c *gin.Context) {
	userUUID := c.Param("user_id")
	var user models.User
	if err := h.db.Where("uuid = ?", userUUID).First(&user).Error; err != nil {
		response.Error(c, http.StatusNotFound, "用户不存在")
		return
	}

	var call models.Call
	if err := h.db.Where(
		"status IN ? AND(caller_id = ? OR callee_id = ?)",
		[]string{"calling", "connected"},
		user.ID,
		user.ID,
	).Order("id DESC").First(&call).Error; err != nil {
		if errors.Is(err, gorm.ErrRecordNotFound) {
			response.Success(c, gin.H{
				"user_id": user.UUID,
				"active":  false,
			})
			return
		}
		response.Error(c, http.StatusInternalServerError, "查询失败")
		return
	}

	var caller, callee models.User
	h.db.First(&caller, call.CallerID)
	h.db.First(&callee, call.CalleeID)
	result := buildCallAdminResponse(call, caller, callee)
	result["active"] = true
	result["user_id"] = user.UUID
	result["role"] = "caller"
	if call.CalleeID == user.ID {
		result["role"] = "callee"
	}
	result["recent_events"] = h.recentCallEvents(call.ID, 20)
	response.Success(c, result)
}

type adminForceEndResult struct {
	Call            models.Call
	Caller          models.User
	Callee          models.User
	AlreadyTerminal bool
}

func (h *CallAdminHandler) forceEndCallByID(callID interface{}, actorID uint64, requestID string, startedAt time.Time) (*adminForceEndResult, int, string) {
	tx := h.db.Begin()
	if tx.Error != nil {
		return nil, http.StatusInternalServerError, "强制结束失败"
	}
	defer func() {
		if r := recover(); r != nil {
			tx.Rollback()
			panic(r)
		}
	}()

	var call models.Call
	if err := tx.Clauses(clause.Locking{Strength: "UPDATE"}).First(&call, callID).Error; err != nil {
		tx.Rollback()
		return nil, http.StatusNotFound, "通话记录不存在"
	}
	if isTerminalCallStatus(call.Status) {
		tx.Rollback()
		result := &adminForceEndResult{Call: call, AlreadyTerminal: true}
		h.db.First(&result.Caller, call.CallerID)
		h.db.First(&result.Callee, call.CalleeID)
		return result, 0, ""
	}
	if call.Status != "calling" && call.Status != "connected" {
		tx.Rollback()
		return nil, http.StatusBadRequest, "当前状态不支持强制结束"
	}
	now := time.Now()
	oldStatus := call.Status
	status, duration := adminForceEndStatusAndDuration(call, now)
	call.Status = status
	call.EndTime = callTimePtr(now)
	call.EndReason = "admin_force_end"
	call.Duration = duration
	if err := tx.Save(&call).Error; err != nil {
		tx.Rollback()
		return nil, http.StatusInternalServerError, "强制结束失败"
	}
	if err := tx.Commit().Error; err != nil {
		return nil, http.StatusInternalServerError, "强制结束失败"
	}

	recordCallObservability(h.db, callAuditEvent{
		CallID:    uint64(call.ID),
		EventType: "admin_force_end",
		ActorID:   callActorPtr(actorID),
		CallerID:  call.CallerID,
		CalleeID:  call.CalleeID,
		OldStatus: oldStatus,
		NewStatus: call.Status,
		Reason:    call.EndReason,
		Duration:  call.Duration,
		LatencyMS: time.Since(startedAt).Milliseconds(),
		RequestID: requestID,
	})
	result := &adminForceEndResult{Call: call}
	h.db.First(&result.Caller, call.CallerID)
	h.db.First(&result.Callee, call.CalleeID)
	h.notifyForceEndedCall(call, result.Caller, result.Callee)
	if h.msgService != nil {
		callHandler := &CallHandler{db: h.db, wsHub: h.wsHub, msgService: h.msgService}
		callHandler.sendCallMessage(context.Background(), &result.Caller, &result.Callee, &call)
	}
	return result, 0, ""
}

func (h *CallAdminHandler) ForceEndUserActiveCall(c *gin.Context) {
	userUUID := c.Param("user_id")
	var user models.User
	if err := h.db.Where("uuid = ?", userUUID).First(&user).Error; err != nil {
		response.Error(c, http.StatusNotFound, "用户不存在")
		return
	}

	var call models.Call
	if err := h.db.Where(
		"status IN ? AND(caller_id = ? OR callee_id = ?)",
		[]string{"calling", "connected"},
		user.ID,
		user.ID,
	).Order("id DESC").First(&call).Error; err != nil {
		if errors.Is(err, gorm.ErrRecordNotFound) {
			response.Success(c, gin.H{
				"user_id":  user.UUID,
				"active":   false,
				"released": false,
			})
			return
		}
		response.Error(c, http.StatusInternalServerError, "查询失败")
		return
	}

	result, code, message := h.forceEndCallByID(call.ID, middleware.GetAdminID(c), requestIDFromContext(c), time.Now())
	if message != "" {
		response.Error(c, code, message)
		return
	}
	response.Success(c, gin.H{
		"user_id":          user.UUID,
		"released":         !result.AlreadyTerminal,
		"already_terminal": result.AlreadyTerminal,
		"call":             buildCallAdminResponse(result.Call, result.Caller, result.Callee),
	})
}

func adminStaleCleanupDecision(call models.Call, now time.Time, ringingThreshold, connectedThreshold time.Duration) (string, string, int, bool) {
	if call.Status == "calling" && !call.StartTime.IsZero() && !call.StartTime.After(now.Add(-ringingThreshold)) {
		return "missed", "timeout", 0, true
	}
	if call.Status != "connected" {
		return "", "", 0, false
	}
	lastSeen := call.LastHeartbeatAt
	if lastSeen == nil {
		lastSeen = call.ConnectTime
	}
	if lastSeen == nil {
		startTime := call.StartTime
		lastSeen = &startTime
	}
	if lastSeen == nil || lastSeen.IsZero() || lastSeen.After(now.Add(-connectedThreshold)) {
		return "", "", 0, false
	}
	return "ended", "heartbeat_timeout", callConnectedDurationSeconds(call, now), true
}

func (h *CallAdminHandler) CleanupStaleCalls(c *gin.Context) {
	ringingSeconds := getQueryInt(c, "ringing_seconds", int(callRingingTimeout.Seconds()))
	connectedSeconds := getQueryInt(c, "connected_seconds", int(callHeartbeatStale.Seconds()))
	limit := getQueryInt(c, "limit", 100)
	var req struct {
		RingingSeconds   int `json:"ringing_seconds"`
		ConnectedSeconds int `json:"connected_seconds"`
		Limit            int `json:"limit"`
	}
	if c.Request != nil && c.Request.ContentLength > 0 {
		if err := c.ShouldBindJSON(&req); err != nil {
			response.Error(c, http.StatusBadRequest, "参数错误")
			return
		}
		if req.RingingSeconds > 0 {
			ringingSeconds = req.RingingSeconds
		}
		if req.ConnectedSeconds > 0 {
			connectedSeconds = req.ConnectedSeconds
		}
		if req.Limit > 0 {
			limit = req.Limit
		}
	}
	if ringingSeconds < 1 {
		ringingSeconds = 1
	}
	if connectedSeconds < 1 {
		connectedSeconds = 1
	}
	if limit < 1 {
		limit = 100
	}
	if limit > 500 {
		limit = 500
	}
	now := time.Now()
	ringingThreshold := time.Duration(ringingSeconds) * time.Second
	connectedThreshold := time.Duration(connectedSeconds) * time.Second

	var calls []models.Call
	if err := h.db.Where(
		"(status = ? AND start_time <= ?) OR(status = ? AND COALESCE(last_heartbeat_at, connect_time, start_time) <= ?)",
		"calling",
		now.Add(-ringingThreshold),
		"connected",
		now.Add(-connectedThreshold),
	).Limit(limit).Find(&calls).Error; err != nil {
		response.Error(c, http.StatusInternalServerError, "查询失败")
		return
	}
	adminID := middleware.GetAdminID(c)
	requestID := requestIDFromContext(c)
	cleanedIDs := make([]uint, 0, len(calls))
	cleanupSvc := &CallCleanupService{db: h.db, wsHub: h.wsHub, msgSvc: h.msgService}
	for _, call := range calls {
		startedAt := time.Now()
		oldStatus := call.Status
		status, reason, duration, ok := adminStaleCleanupDecision(call, now, ringingThreshold, connectedThreshold)
		if !ok {
			continue
		}
		result := h.db.Model(&models.Call{}).
			Where("id = ? AND status = ?", call.ID, oldStatus).
			Updates(map[string]interface{}{
				"status":     status,
				"end_time":   now,
				"duration":   duration,
				"end_reason": reason,
				"updated_at": now,
			})
		if result.Error != nil || result.RowsAffected == 0 {
			continue
		}
		call.Status = status
		call.EndTime = callTimePtr(now)
		call.Duration = duration
		call.EndReason = reason
		recordCallObservability(h.db, callAuditEvent{
			CallID:    uint64(call.ID),
			EventType: callReleaseEventTypeFromReason(reason),
			ActorID:   callActorPtr(adminID),
			CallerID:  call.CallerID,
			CalleeID:  call.CalleeID,
			OldStatus: oldStatus,
			NewStatus: call.Status,
			Reason:    call.EndReason,
			Duration:  call.Duration,
			LatencyMS: time.Since(startedAt).Milliseconds(),
			RequestID: requestID,
			Payload: map[string]interface{}{
				"admin_cleanup":     true,
				"ringing_seconds":   ringingSeconds,
				"connected_seconds": connectedSeconds,
			},
		})
		cleanupSvc.notifyCleanedCall(call)
		cleanedIDs = append(cleanedIDs, call.ID)
	}
	response.Success(c, gin.H{
		"checked":           len(calls),
		"cleaned":           len(cleanedIDs),
		"cleaned_call_ids":  cleanedIDs,
		"ringing_seconds":   ringingSeconds,
		"connected_seconds": connectedSeconds,
	})
}

func adminForceEndStatusAndDuration(call models.Call, now time.Time) (string, int) {
	if call.Status == "calling" {
		return "cancelled", 0
	}
	return "ended", callConnectedDurationSeconds(call, now)
}

// ForceEndCall 强制结束仍处于呼叫中/通话中的记录，并通知双方客户端释放 UI。
func (h *CallAdminHandler) ForceEndCall(c *gin.Context) {
	result, code, message := h.forceEndCallByID(c.Param("id"), middleware.GetAdminID(c), requestIDFromContext(c), time.Now())
	if message != "" {
		response.Error(c, code, message)
		return
	}
	message = "已强制结束通话"
	if result.AlreadyTerminal {
		message = "通话已结束"
	}
	response.Success(c, gin.H{
		"message":          message,
		"duration":         result.Call.Duration,
		"status":           result.Call.Status,
		"already_terminal": result.AlreadyTerminal,
	})
}

func (h *CallAdminHandler) notifyForceEndedCall(call models.Call, caller, callee models.User) {
	if h.wsHub == nil {
		return
	}
	releasePayload := callReleasePayload(call)
	h.wsHub.SendToUser(caller.UUID, map[string]interface{}{
		"type": "call_released",
		"data": releasePayload,
	})
	h.wsHub.SendToUser(callee.UUID, map[string]interface{}{
		"type": "call_released",
		"data": releasePayload,
	})
	if call.Status == "cancelled" {
		h.wsHub.SendToUser(caller.UUID, map[string]interface{}{
			"type": "call_rejected",
			"data": map[string]interface{}{
				"call_id": call.ID,
				"reason":  call.EndReason,
			},
		})
		h.wsHub.SendToUser(callee.UUID, map[string]interface{}{
			"type": "call_cancelled",
			"data": map[string]interface{}{
				"call_id": call.ID,
				"reason":  call.EndReason,
			},
		})
		return
	}
	payload := map[string]interface{}{
		"call_id":  call.ID,
		"reason":   call.EndReason,
		"duration": call.Duration,
	}
	h.wsHub.SendToUser(caller.UUID, map[string]interface{}{
		"type": "call_ended",
		"data": payload,
	})
	h.wsHub.SendToUser(callee.UUID, map[string]interface{}{
		"type": "call_ended",
		"data": payload,
	})
}

// DeleteCall

func (h *CallAdminHandler) DeleteCall(c *gin.Context) {
	callID := c.Param("id")
	if err := h.db.Delete(&models.Call{}, callID).Error; err != nil {
		response.Error(c, http.StatusInternalServerError, "删除失败")
		return
	}
	response.Success(c, gin.H{"message": "删除成功"})
}

// BatchDeleteCalls 批量

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
