// 文件用途：实现后端 HTTP 接口的请求处理和统一响应。
// 核心逻辑：绑定参数，校验身份与权限，调用业务服务并持久化关键状态。

package handlers

import (
	"context"
	"errors"
	"fmt"
	"github.com/gin-gonic/gin"
	"github.com/google/uuid"
	"gorm.io/gorm"
	"gorm.io/gorm/clause"
	"strconv"
	"strings"
	"time"
	"genericim/internal/models"
	"genericim/internal/services"
	"genericim/pkg/response"
)

type WebSocketHub interface {
	SendToUser(userID string, data interface{})
}

// CallHandler 管理一对一通话状态机和 RTC 凭据。 // MySQL 中的 Call 状态是权威值；WebSocket、厂商推送和聊天记录均在状态提交后派生。
type CallHandler struct {
	db             *gorm.DB
	agoraService   *services.AgoraService
	liveKitService *services.LiveKitService
	wsHub          WebSocketHub
	msgService     *services.MessageService
	pushService    *services.PushService
}

// NewCallHandler 创建通话处理器。
func NewCallHandler(db *gorm.DB, agoraService *services.AgoraService, liveKitService *services.LiveKitService, wsHub WebSocketHub, msgService *services.MessageService, pushService *services.PushService) *CallHandler {
	return &CallHandler{

		db: db,

		agoraService: agoraService,

		liveKitService: liveKitService,

		wsHub: wsHub,

		msgService: msgService,

		pushService: pushService,
	}
}
func (h *CallHandler) GetAgoraConfig(c *gin.Context) {
	h.GetRTCConfig(c)
}
func (h *CallHandler) GetRTCConfig(c *gin.Context) {
	enabled, appID, _, _ := h.getAgoraConfigFromDB()
	liveKitEnabled, liveKitServerURL, _, _, _ := h.getLiveKitConfigFromDB()
	provider := h.getDefaultRTCProviderFromDB()
	response.Success(c, gin.H{

		"enabled": enabled || liveKitEnabled,

		"provider": provider,

		"rtc_provider": provider,

		"app_id": appID,

		"agora_enabled": enabled,

		"livekit_enabled": liveKitEnabled,

		"livekit_server_url": liveKitServerURL,
	})
}
func (h *CallHandler) getAgoraConfigFromDB() (enabled bool, appID, appCertificate string, tokenExpire int) {
	enabled = h.agoraService.Enabled
	appID = h.agoraService.AppID
	appCertificate = h.agoraService.AppCertificate
	tokenExpire = h.agoraService.TokenExpire
	var settings []models.SystemSetting
	h.db.Where("`key` IN ?", []string{

		models.SettingAgoraEnabled,

		models.SettingAgoraAppID,

		models.SettingAgoraAppCertificate,

		models.SettingAgoraTokenExpire,
	}).Find(&settings)
	for _, s := range settings {

		switch s.Key {

		case models.SettingAgoraEnabled:

			enabled = s.Value == "true" || s.Value == "1"

		case models.SettingAgoraAppID:

			if s.Value != "" {

				appID = s.Value

			}

		case models.SettingAgoraAppCertificate:

			if s.Value != "" {

				appCertificate = s.Value

			}

		case models.SettingAgoraTokenExpire:

			if v, err := strconv.Atoi(s.Value); err == nil && v > 0 {

				tokenExpire = v

			}

		}
	}
	if appID == "" || appCertificate == "" {

		enabled = false
	}
	return
}
func (h *CallHandler) getLiveKitConfigFromDB() (enabled bool, serverURL, apiKey, apiSecret string, tokenExpire int) {
	if h.liveKitService != nil {

		enabled = h.liveKitService.Enabled

		serverURL = h.liveKitService.ServerURL

		apiKey = h.liveKitService.APIKey

		apiSecret = h.liveKitService.APISecret

		tokenExpire = h.liveKitService.TokenExpire
	}
	var settings []models.SystemSetting
	h.db.Where("`key` IN ?", []string{

		models.SettingLiveKitEnabled,

		models.SettingLiveKitServerURL,

		models.SettingLiveKitAPIKey,

		models.SettingLiveKitAPISecret,

		models.SettingLiveKitTokenExpire,
	}).Find(&settings)
	for _, s := range settings {

		switch s.Key {

		case models.SettingLiveKitEnabled:

			enabled = s.Value == "true" || s.Value == "1"

		case models.SettingLiveKitServerURL:

			if strings.TrimSpace(s.Value) != "" {

				serverURL = strings.TrimSpace(s.Value)

			}

		case models.SettingLiveKitAPIKey:

			if strings.TrimSpace(s.Value) != "" {

				apiKey = strings.TrimSpace(s.Value)

			}

		case models.SettingLiveKitAPISecret:

			if strings.TrimSpace(s.Value) != "" {

				apiSecret = strings.TrimSpace(s.Value)

			}

		case models.SettingLiveKitTokenExpire:

			if v, err := strconv.Atoi(s.Value); err == nil && v > 0 {

				tokenExpire = v

			}

		}
	}
	if serverURL == "" || apiKey == "" || apiSecret == "" {

		enabled = false
	}
	if tokenExpire <= 0 {

		tokenExpire = 3600
	}
	return
}
func (h *CallHandler) getDefaultRTCProviderFromDB() string {
	provider := models.RTCProviderAgora
	var setting models.SystemSetting
	if err := h.db.Where("`key` = ?", models.SettingRTCProvider).First(&setting).Error; err == nil {

		provider = normalizeRTCProvider(setting.Value)
	}
	if provider == "" {

		return models.RTCProviderAgora
	}
	return provider
}
func normalizeRTCProvider(provider string) string {
	switch strings.ToLower(strings.TrimSpace(provider)) {
	case models.RTCProviderLiveKit:

		return models.RTCProviderLiveKit
	case models.RTCProviderAgora, "":

		return models.RTCProviderAgora
	default:

		return ""
	}
}
func effectiveRTCProvider(provider string) string {
	normalized := normalizeRTCProvider(provider)
	if normalized == "" {

		return models.RTCProviderAgora
	}
	return normalized
}
func (h *CallHandler) buildCallRTCResponse(provider, channelName string, user models.User, base gin.H) (gin.H, error) {
	provider = effectiveRTCProvider(provider)
	if base == nil {

		base = gin.H{}
	}
	base["provider"] = provider
	base["rtc_provider"] = provider
	base["channel_name"] = channelName
	base["room_name"] = channelName
	base["identity"] = user.UUID
	switch provider {
	case models.RTCProviderLiveKit:

		enabled, serverURL, apiKey, apiSecret, tokenExpire := h.getLiveKitConfigFromDB()

		if !enabled {

			return nil, fmt.Errorf("livekit not configured")

		}
		liveKitSvc := services.NewLiveKitService(enabled, serverURL, apiKey, apiSecret, tokenExpire)
		token, err := liveKitSvc.GenerateJoinToken(channelName, user.UUID, user.Nickname, true)

		if err != nil {

			return nil, err

		}

		base["server_url"] = serverURL

		base["token"] = token

		return base, nil
	default:

		enabled, appID, appCertificate, tokenExpire := h.getAgoraConfigFromDB()

		if !enabled {

			return nil, fmt.Errorf("agora not configured")

		}
		agoraSvc := services.NewAgoraService(enabled, appID, appCertificate, tokenExpire)
		agoraUID := toAgoraUID(user.ID)
		token, err := agoraSvc.GenerateRTCToken(channelName, agoraUID, services.RolePublisher)

		if err != nil {

			return nil, err

		}

		base["app_id"] = appID

		base["token"] = token

		base["agora_uid"] = agoraUID

		return base, nil
	}
}

type CreateCallRequest struct {
	TargetUserID string `json:"target_user_id" binding:"required"`
	CallType     string `json:"call_type" binding:"required"` // voice/video
}

func normalizeCallType(raw string) string {
	switch strings.ToLower(strings.TrimSpace(raw)) {
	case "voice", "audio":

		return "voice"
	case "video":

		return "video"
	default:

		return ""
	}
}
func resolveCallMediaState(
	currentType string,
	requestedType string,
	requestedVideo *bool) (string, bool, error) {
	nextType := normalizeCallType(currentType)
	requestedType = strings.ToLower(strings.TrimSpace(requestedType))
	if requestedType != "" && requestedType != "voice" && requestedType != "video" {

		return "", false, errors.New("invalid call type")
	}
	if requestedType == "video" && nextType != "video" {

		return "", false, errors.New("voice call cannot be upgraded to video")
	}
	if requestedType == "voice" {

		nextType = "voice"
	}
	videoEnabled := nextType == "video"
	if requestedVideo != nil {

		videoEnabled = *requestedVideo && nextType == "video"
	}
	return nextType, videoEnabled, nil
}
func isTerminalCallStatus(status string) bool {
	switch status {
	case "ended", "rejected", "cancelled", "missed", "failed":

		return true
	default:

		return false
	}
}

const (
	callRingingTimeout  = 30 * time.Second
	callActiveWindow    = 2 * time.Hour
	callHeartbeatStale  = 90 * time.Second
	callCleanupInterval = time.Second
)

func isStaleCallingCall(call models.Call, now time.Time) bool {
	return call.Status == "calling" &&

		!call.StartTime.IsZero() &&

		!call.StartTime.After(now.Add(-callRingingTimeout))
}
func isStaleConnectedCall(call models.Call, now time.Time) bool {
	if call.Status != "connected" {

		return false
	}
	lastSeen := call.LastHeartbeatAt
	if lastSeen == nil {

		lastSeen = call.ConnectTime
	}
	if lastSeen == nil {
		startTime := call.StartTime

		lastSeen = &startTime
	}
	if lastSeen == nil || lastSeen.IsZero() {

		return false
	}
	return !lastSeen.After(now.Add(-callHeartbeatStale))
}
func isReverseSimultaneousCall(
	call models.Call,
	requestCallerID uint64,
	requestCalleeID uint64,
	now time.Time) bool {
	return call.Status == "calling" &&

		call.CallerID == requestCalleeID &&

		call.CalleeID == requestCallerID &&

		!isStaleCallingCall(call, now)
}
func callEndTimeValue(call models.Call) time.Time {
	if call.EndTime != nil && !call.EndTime.IsZero() {

		return *call.EndTime
	}
	return time.Now()
}
func callConnectedDurationSeconds(call models.Call, endTime time.Time) int {
	if call.ConnectTime == nil || call.ConnectTime.IsZero() {

		return 0
	}
	return int(endTime.Sub(*call.ConnectTime).Seconds())
}
func callTimePtr(t time.Time) *time.Time {
	return &t
}
func replacementCallStatusAndDuration(call models.Call, now time.Time) (string, int) {
	if call.Status == "calling" {

		return "cancelled", 0
	}
	return "ended", callConnectedDurationSeconds(call, now)
}
func finishActiveCallForRelease(call *models.Call, reason string, now time.Time) {
	if reason == "" {

		reason = "hangup"
	}
	if call.Status == "calling" {

		call.Status = "cancelled"

		call.EndReason = "cancelled"

		call.Duration = 0
	} else {

		call.Status = "ended"

		call.EndReason = reason

		call.Duration = callConnectedDurationSeconds(*call, now)
	}
	call.EndTime = callTimePtr(now)
}
func callReleasePayload(call models.Call) gin.H {
	return gin.H{

		"call_id": call.ID,

		"status": call.Status,

		"reason": call.EndReason,

		"duration": call.Duration,

		"released": true,

		"released_at": call.EndTime,
	}
}
func callReleaseResponse(message string, call models.Call) gin.H {
	payload := callReleasePayload(call)
	payload["message"] = message
	return payload
}
func (h *CallHandler) sendCallReleasedEvent(userUUID string, call models.Call) {
	if h == nil || h.wsHub == nil || userUUID == "" {

		return
	}
	h.wsHub.SendToUser(userUUID, map[string]interface{}{

		"type": "call_released",

		"data": callReleasePayload(call),
	})
}

type replacedCallSnapshot struct {
	Call      models.Call
	OldStatus string
}

func (h *CallHandler) expireStaleActiveCalls(tx *gorm.DB, userIDs []uint64, now time.Time) error {
	if len(userIDs) == 0 {

		return nil
	}
	if err := tx.Model(&models.Call{}).
		Where(

			"status = ? AND start_time <= ? AND (caller_id IN ? OR callee_id IN ?)",

			"calling",

			now.Add(-callRingingTimeout),

			userIDs,

			userIDs,
		).
		Updates(map[string]interface{}{

			"status": "missed",

			"end_time": now,

			"end_reason": "timeout",

			"updated_at": now,
		}).Error; err != nil {

		return err
	}
	return tx.Model(&models.Call{}).
		Where(

			"status = ? AND COALESCE(last_heartbeat_at, connect_time, start_time) <= ? AND (caller_id IN ? OR callee_id IN ?)",

			"connected",

			now.Add(-callHeartbeatStale),

			userIDs,

			userIDs,
		).
		Updates(map[string]interface{}{

			"status": "ended",

			"end_time": now,

			"end_reason": "heartbeat_timeout",

			"updated_at": now,
		}).Error
}
func (h *CallHandler) replaceCallerActiveCallsForNewCall(tx *gorm.DB, callerID uint64, now time.Time) ([]replacedCallSnapshot, error) {
	var activeCalls []models.Call
	if err := tx.Clauses(clause.Locking{Strength: "UPDATE"}).
		Where(

			"status IN ? AND (caller_id = ? OR callee_id = ?)",

			[]string{"calling", "connected"},

			callerID,

			callerID,
		).
		Find(&activeCalls).Error; err != nil {

		return nil, err
	}
	replaced := make([]replacedCallSnapshot, 0, len(activeCalls))
	for _, call := range activeCalls {
		oldStatus := call.Status

		status, duration := replacementCallStatusAndDuration(call, now)

		if err := tx.Model(&models.Call{}).
			Where("id = ? AND status IN ?", call.ID, []string{"calling", "connected"}).
			Updates(map[string]interface{}{

				"status": status,

				"end_time": now,

				"duration": duration,

				"end_reason": "client_replaced",

				"updated_at": now,
			}).Error; err != nil {

			return nil, err

		}

		call.Status = status

		call.EndTime = callTimePtr(now)

		call.Duration = duration

		call.EndReason = "client_replaced"

		replaced = append(replaced, replacedCallSnapshot{Call: call, OldStatus: oldStatus})
	}
	return replaced, nil
}
func (h *CallHandler) notifyReplacedCalls(calls []replacedCallSnapshot, replacedUserID uint64) {
	for _, replaced := range calls {
		call := replaced.Call

		otherUserID := call.CalleeID

		if call.CalleeID == replacedUserID {

			otherUserID = call.CallerID

		}
		var otherUser models.User
		if err := h.db.First(&otherUser, otherUserID).Error; err != nil || otherUser.UUID == "" {

			continue

		}

		h.sendCallReleasedEvent(otherUser.UUID, call)

		if call.Status == "cancelled" {

			h.wsHub.SendToUser(otherUser.UUID, map[string]interface{}{

				"type": "call_cancelled",

				"data": map[string]interface{}{

					"call_id": call.ID,

					"reason": call.EndReason,
				},
			})

			continue

		}

		h.wsHub.SendToUser(otherUser.UUID, map[string]interface{}{

			"type": "call_ended",

			"data": map[string]interface{}{

				"call_id": call.ID,

				"reason": call.EndReason,

				"duration": call.Duration,
			},
		})
	}
}
func (h *CallHandler) hasUserBlockRelation(db *gorm.DB, userID1, userID2 uint64) (bool, error) {
	var count int64
	err := db.Model(&models.UserBlock{}).
		Where(

			"(user_id = ? AND blocked_user_id = ?) OR (user_id = ? AND blocked_user_id = ?)",

			userID1,

			userID2,

			userID2,

			userID1,
		).
		Count(&count).Error
	return count > 0, err
}
func (h *CallHandler) CreateCall(c *gin.Context) {
	requestStartedAt := time.Now()
	requestID := requestIDFromContext(c)
	userID := c.GetString("user_id")
	var req CreateCallRequest
	if err := c.ShouldBindJSON(&req); err != nil {

		response.BadRequest(c, "参数错误")

		return
	}
	req.CallType = normalizeCallType(req.CallType)
	if req.CallType == "" {

		response.BadRequest(c, "call_type must be voice or video")

		return
	}
	if strings.TrimSpace(req.TargetUserID) == userID {

		response.BadRequest(c, "cannot call yourself")

		return
	}
	rtcProvider := h.getDefaultRTCProviderFromDB()
	var caller models.User
	if err := h.db.Where("uuid = ?", userID).First(&caller).Error; err != nil {

		response.NotFound(c, "user not found")

		return
	}
	var callee models.User
	if err := h.db.Where("uuid = ?", req.TargetUserID).First(&callee).Error; err != nil {

		response.NotFound(c, "target user not found")

		return
	}
	if callee.Status != models.UserStatusNormal {

		response.Forbidden(c, "target user is unavailable")

		return
	}
	channelName := generateChannelName(userID, req.TargetUserID)
	rtcResponse, err := h.buildCallRTCResponse(rtcProvider, channelName, caller, gin.H{})
	if err != nil {

		response.BadRequest(c, "audio/video service is not configured")

		return
	}
	tx := h.db.Begin()
	if tx.Error != nil {

		response.ServerError(c, "failed to create call")

		return
	}
	defer func() {

		if r := recover(); r != nil {

			tx.Rollback()

			panic(r)

		}
	}()
	lockedUserIDs := []uint64{caller.ID}
	if callee.ID != caller.ID {

		lockedUserIDs = append(lockedUserIDs, callee.ID)
	}
	// 始终按用户 ID 排序锁定双方，既串行化“每人仅一通活跃通话”的检查，
	// 也避免两个相反方向的并发呼叫以不同锁顺序产生死锁。
	if err := tx.Clauses(clause.Locking{Strength: "UPDATE"}).
		Where("id IN ?", lockedUserIDs).
		Order("id ASC").
		Find(&[]models.User{}).Error; err != nil {

		tx.Rollback()

		response.ServerError(c, "failed to create call")

		return
	}
	now := time.Now()
	if err := h.expireStaleActiveCalls(tx, lockedUserIDs, now); err != nil {

		tx.Rollback()

		response.ServerError(c, "failed to create call")

		return
	}
	blocked, err := h.hasUserBlockRelation(tx, caller.ID, callee.ID)
	if err != nil {

		tx.Rollback()

		response.ServerError(c, "failed to create call")

		return
	}
	if blocked {

		tx.Rollback()

		response.Forbidden(c, "你与对方存在屏蔽关系，无法发起通话")

		return
	}
	// If both users press call at nearly the same time, the request that
	// acquires the ordered user locks second becomes the answer to the first
	// request. Reuse and connect the original call instead of cancelling it and
	// creating a second call_id.
	// 双方同时呼叫时复用先创建的 call_id，并将后取得锁的请求解释为接听，
	// 防止生成两条互相竞争的振铃记录。
	var arbitratedCall models.Call
	arbitrationErr := tx.Clauses(clause.Locking{Strength: "UPDATE"}).
		Where(

			"status = ? AND caller_id = ? AND callee_id = ?",

			"calling",

			callee.ID,

			caller.ID,
		).
		Order("id ASC").
		First(&arbitratedCall).Error
	if arbitrationErr == nil && isReverseSimultaneousCall(arbitratedCall, caller.ID, callee.ID, now) {
		arbitratedProvider := effectiveRTCProvider(arbitratedCall.RTCProvider)
		arbitratedRTC, buildErr := h.buildCallRTCResponse(

			arbitratedProvider,

			arbitratedCall.ChannelName,

			caller,

			gin.H{

				"call_id": arbitratedCall.ID,

				"arbitrated": true,

				"role": "callee",
			},
		)

		if buildErr != nil {

			tx.Rollback()

			response.BadRequest(c, "audio/video service is not configured")

			return

		}
		connectedAt := time.Now()

		arbitratedCall.Status = "connected"

		arbitratedCall.ConnectTime = callTimePtr(connectedAt)

		arbitratedCall.LastHeartbeatAt = callTimePtr(connectedAt)

		if err := tx.Save(&arbitratedCall).Error; err != nil {

			tx.Rollback()

			response.ServerError(c, "failed to create call")

			return

		}

		if err := tx.Commit().Error; err != nil {

			response.ServerError(c, "failed to create call")

			return

		}

		recordCallObservability(h.db, callAuditEvent{

			CallID: uint64(arbitratedCall.ID),

			EventType: "simultaneous_arbitrated",

			ActorID: callActorPtr(caller.ID),

			CallerID: arbitratedCall.CallerID,

			CalleeID: arbitratedCall.CalleeID,

			OldStatus: "calling",

			NewStatus: arbitratedCall.Status,

			Reason: "reverse_call_reused",

			LatencyMS: time.Since(requestStartedAt).Milliseconds(),

			RequestID: requestID,
		})

		h.wsHub.SendToUser(callee.UUID, map[string]interface{}{

			"type": "call_accepted",

			"data": map[string]interface{}{

				"call_id": arbitratedCall.ID,

				"channel_name": arbitratedCall.ChannelName,

				"room_name": arbitratedCall.ChannelName,

				"provider": arbitratedProvider,

				"rtc_provider": arbitratedProvider,

				"arbitrated": true,
			},
		})

		response.Success(c, arbitratedRTC)

		return
	}
	if arbitrationErr != nil && !errors.Is(arbitrationErr, gorm.ErrRecordNotFound) {

		tx.Rollback()

		response.ServerError(c, "failed to create call")

		return
	}
	activeSince := now.Add(-callActiveWindow)
	var activeCallCount int64
	if err := tx.Model(&models.Call{}).
		Where("status IN ? AND start_time > ? AND (caller_id IN ? OR callee_id IN ?)",

			[]string{"calling", "connected"},

			activeSince,

			[]uint64{caller.ID, callee.ID},

			[]uint64{caller.ID, callee.ID},
		).
		Count(&activeCallCount).Error; err != nil {

		tx.Rollback()

		response.ServerError(c, "failed to create call")

		return
	}
	if activeCallCount > 0 {

		tx.Rollback()

		recordCallObservability(h.db, callAuditEvent{

			EventType: "create_blocked_active",

			ActorID: callActorPtr(caller.ID),

			CallerID: caller.ID,

			CalleeID: callee.ID,

			Reason: "active_call_exists",

			LatencyMS: time.Since(requestStartedAt).Milliseconds(),

			RequestID: requestID,

			Payload: map[string]interface{}{

				"active_count": activeCallCount,

				"target_user_uuid": req.TargetUserID,
			},
		})

		response.BadRequest(c, "\u5f53\u524d\u8d26\u53f7\u6216\u5bf9\u65b9\u6b63\u5728\u901a\u8bdd\u4e2d")

		return
	}
	call := &models.Call{

		ChannelName: channelName,

		RTCProvider: rtcProvider,

		CallerID: caller.ID,

		CalleeID: callee.ID,

		CallType: req.CallType,

		Status: "calling",

		StartTime: now,
	}
	expiresAt := now.Add(callRingingTimeout)
	if err := tx.Create(call).Error; err != nil {

		tx.Rollback()

		response.ServerError(c, "failed to create call")

		return
	}
	if err := tx.Commit().Error; err != nil {

		response.ServerError(c, "failed to create call")

		return
	}
	// 状态提交后再发实时事件和离线推送；通知失败不能回滚已创建通话，
	// 客户端可通过 GetActiveCall 读取权威状态恢复。
	recordCallObservability(h.db, callAuditEvent{

		CallID: uint64(call.ID),

		EventType: "create",

		ActorID: callActorPtr(caller.ID),

		CallerID: call.CallerID,

		CalleeID: call.CalleeID,

		NewStatus: call.Status,

		Reason: "create",

		LatencyMS: time.Since(requestStartedAt).Milliseconds(),

		RequestID: requestID,

		Payload: map[string]interface{}{

			"call_type": call.CallType,

			"rtc_provider": call.RTCProvider,

			"channel_name": call.ChannelName,
		},
	})
	h.wsHub.SendToUser(req.TargetUserID, map[string]interface{}{

		"type": "incoming_call",

		"data": map[string]interface{}{

			"call_id": call.ID,

			"channel_name": channelName,

			"room_name": channelName,

			"provider": rtcProvider,

			"rtc_provider": rtcProvider,

			"caller_id": userID,

			"caller_name": caller.Nickname,

			"caller_avatar": caller.Avatar,

			"call_type": req.CallType,

			"expires_at": expiresAt,
		},
	})
	if h.pushService != nil {
		isVideo := req.CallType == "video"

		go h.pushService.PushIncomingCall(callee.ID, caller.Nickname, fmt.Sprintf("%d", call.ID), isVideo, map[string]interface{}{

			"channel_name": channelName,

			"room_name": channelName,

			"provider": rtcProvider,

			"rtc_provider": rtcProvider,

			"caller_id": caller.UUID,

			"caller_avatar": caller.Avatar,

			"expires_at": expiresAt,
		})
	}
	rtcResponse["call_id"] = call.ID
	rtcResponse["expires_at"] = expiresAt
	response.Success(c, rtcResponse)
}

type AcceptCallRequest struct {
	CallID uint `json:"call_id" binding:"required"`
}

func (h *CallHandler) AcceptCall(c *gin.Context) {
	requestStartedAt := time.Now()
	requestID := requestIDFromContext(c)
	userID := c.GetString("user_id")
	var req AcceptCallRequest
	if err := c.ShouldBindJSON(&req); err != nil {

		response.BadRequest(c, "参数错误")

		return
	}
	var callee models.User
	if err := h.db.Where("uuid = ?", userID).First(&callee).Error; err != nil {

		response.NotFound(c, "user not found")

		return
	}
	tx := h.db.Begin()
	if tx.Error != nil {

		response.ServerError(c, "failed to accept call")

		return
	}
	defer func() {

		if r := recover(); r != nil {

			tx.Rollback()

			panic(r)

		}
	}()
	// Call 行锁是接听、拒绝、取消与超时清理的共同仲裁点，
	// 锁内的操作者和状态检查保证只有一个状态分支成功。
	var call models.Call
	if err := tx.Clauses(clause.Locking{Strength: "UPDATE"}).First(&call, req.CallID).Error; err != nil {

		tx.Rollback()

		response.NotFound(c, "call not found")

		return
	}
	if call.CalleeID != callee.ID {

		tx.Rollback()

		response.Forbidden(c, "无权操作")

		return
	}
	if call.Status != "calling" {

		tx.Rollback()

		response.BadRequest(c, "call is not waiting for answer")

		return
	}
	now := time.Now()
	if isStaleCallingCall(call, now) {
		oldStatus := call.Status

		call.Status = "missed"

		call.EndTime = callTimePtr(now)

		call.EndReason = "timeout"

		if err := tx.Save(&call).Error; err != nil {

			tx.Rollback()

			response.ServerError(c, "failed to accept call")

			return

		}

		if err := tx.Commit().Error; err != nil {

			response.ServerError(c, "failed to accept call")

			return

		}

		recordCallObservability(h.db, callAuditEvent{

			CallID: uint64(call.ID),

			EventType: "ringing_timeout",

			ActorID: callActorPtr(callee.ID),

			CallerID: call.CallerID,

			CalleeID: call.CalleeID,

			OldStatus: oldStatus,

			NewStatus: call.Status,

			Reason: call.EndReason,

			Duration: call.Duration,

			LatencyMS: time.Since(requestStartedAt).Milliseconds(),

			RequestID: requestID,
		})
		var caller models.User

		h.db.First(&caller, call.CallerID)

		h.wsHub.SendToUser(caller.UUID, map[string]interface{}{

			"type": "call_rejected",

			"data": map[string]interface{}{

				"call_id": call.ID,

				"reason": "timeout",
			},
		})

		h.sendCallMessage(c.Request.Context(), &caller, &callee, &call)

		response.BadRequest(c, "call timed out")

		return
	}
	blocked, err := h.hasUserBlockRelation(tx, call.CallerID, call.CalleeID)
	if err != nil {

		tx.Rollback()

		response.ServerError(c, "failed to accept call")

		return
	}
	if blocked {
		oldStatus := call.Status

		call.Status = "rejected"

		call.EndTime = callTimePtr(time.Now())

		call.EndReason = "blocked"

		if err := tx.Save(&call).Error; err != nil {

			tx.Rollback()

			response.ServerError(c, "failed to accept call")

			return

		}

		if err := tx.Commit().Error; err != nil {

			response.ServerError(c, "failed to accept call")

			return

		}

		recordCallObservability(h.db, callAuditEvent{

			CallID: uint64(call.ID),

			EventType: "reject",

			ActorID: callActorPtr(callee.ID),

			CallerID: call.CallerID,

			CalleeID: call.CalleeID,

			OldStatus: oldStatus,

			NewStatus: call.Status,

			Reason: call.EndReason,

			Duration: call.Duration,

			LatencyMS: time.Since(requestStartedAt).Milliseconds(),

			RequestID: requestID,
		})
		var caller models.User

		h.db.First(&caller, call.CallerID)

		h.wsHub.SendToUser(caller.UUID, map[string]interface{}{

			"type": "call_rejected",

			"data": map[string]interface{}{

				"call_id": call.ID,

				"reason": "blocked",
			},
		})

		response.Forbidden(c, "你与对方存在屏蔽关系，无法接听通话")

		return
	}
	rtcProvider := effectiveRTCProvider(call.RTCProvider)
	rtcResponse, err := h.buildCallRTCResponse(rtcProvider, call.ChannelName, callee, gin.H{

		"call_id": call.ID,
	})
	if err != nil {

		tx.Rollback()

		response.BadRequest(c, "audio/video service is not configured")

		return
	}
	oldStatus := call.Status
	call.Status = "connected"
	connectedAt := time.Now()
	call.ConnectTime = callTimePtr(connectedAt)
	call.LastHeartbeatAt = callTimePtr(connectedAt)
	if err := tx.Save(&call).Error; err != nil {

		tx.Rollback()

		response.ServerError(c, "failed to accept call")

		return
	}
	if err := tx.Commit().Error; err != nil {

		response.ServerError(c, "failed to accept call")

		return
	}
	// connected 已落库后才通知呼叫方，避免对方先进入 RTC 房间却查不到权威状态。
	recordCallObservability(h.db, callAuditEvent{

		CallID: uint64(call.ID),

		EventType: "accept",

		ActorID: callActorPtr(callee.ID),

		CallerID: call.CallerID,

		CalleeID: call.CalleeID,

		OldStatus: oldStatus,

		NewStatus: call.Status,

		Reason: "accepted",

		LatencyMS: time.Since(requestStartedAt).Milliseconds(),

		RequestID: requestID,
	})
	var caller models.User
	h.db.First(&caller, call.CallerID)
	h.wsHub.SendToUser(caller.UUID, map[string]interface{}{

		"type": "call_accepted",

		"data": map[string]interface{}{

			"call_id": call.ID,

			"channel_name": call.ChannelName,

			"room_name": call.ChannelName,

			"provider": rtcProvider,

			"rtc_provider": rtcProvider,

			"connected_at": connectedAt,
		},
	})
	rtcResponse["connected_at"] = connectedAt
	response.Success(c, rtcResponse)
}

type UpdateCallMediaStateRequest struct {
	CallID       uint   `json:"call_id" binding:"required"`
	CallType     string `json:"call_type"`
	VideoEnabled *bool  `json:"video_enabled"`
}

// UpdateCallMediaState synchronizes camera state and one-way video-to-voice // downgrade with the other participant. Voice calls cannot be upgraded without // negotiating a new call and video calls cannot be downgraded back to video.
func (h *CallHandler) UpdateCallMediaState(c *gin.Context) {
	userUUID := c.GetString("user_id")
	var req UpdateCallMediaStateRequest
	if err := c.ShouldBindJSON(&req); err != nil {

		response.BadRequest(c, "invalid parameters")

		return
	}
	var user models.User
	if err := h.db.Where("uuid = ?", userUUID).First(&user).Error; err != nil {

		response.NotFound(c, "user not found")

		return
	}
	tx := h.db.Begin()
	if tx.Error != nil {

		response.ServerError(c, "failed to update call media state")

		return
	}
	var call models.Call
	if err := tx.Clauses(clause.Locking{Strength: "UPDATE"}).First(&call, req.CallID).Error; err != nil {

		tx.Rollback()

		response.NotFound(c, "call not found")

		return
	}
	if call.CallerID != user.ID && call.CalleeID != user.ID {

		tx.Rollback()

		response.Forbidden(c, "permission denied")

		return
	}
	if call.Status != "connected" {

		tx.Rollback()

		response.BadRequest(c, "call is not connected")

		return
	}
	nextType, videoEnabled, mediaErr := resolveCallMediaState(

		call.CallType,

		req.CallType,

		req.VideoEnabled,
	)
	if mediaErr != nil {

		tx.Rollback()

		response.BadRequest(c, mediaErr.Error())

		return
	}
	if nextType != call.CallType {

		call.CallType = nextType

		if err := tx.Model(&call).Update("call_type", "voice").Error; err != nil {

			tx.Rollback()

			response.ServerError(c, "failed to update call media state")

			return

		}
	}
	if err := tx.Commit().Error; err != nil {

		response.ServerError(c, "failed to update call media state")

		return
	}
	otherID := call.CalleeID
	if user.ID == call.CalleeID {

		otherID = call.CallerID
	}
	var other models.User
	if err := h.db.First(&other, otherID).Error; err == nil {

		h.wsHub.SendToUser(other.UUID, map[string]interface{}{

			"type": "call_media_changed",

			"data": map[string]interface{}{

				"call_id": call.ID,

				"call_type": call.CallType,

				"video_enabled": videoEnabled,
			},
		})
	}
	response.Success(c, gin.H{

		"call_id": call.ID,

		"call_type": call.CallType,

		"video_enabled": videoEnabled,
	})
}

type RejectCallRequest struct {
	CallID uint   `json:"call_id" binding:"required"`
	Reason string `json:"reason"` // busy/decline
}

func (h *CallHandler) RejectCall(c *gin.Context) {
	requestStartedAt := time.Now()
	requestID := requestIDFromContext(c)
	userID := c.GetString("user_id")
	var req RejectCallRequest
	if err := c.ShouldBindJSON(&req); err != nil {

		response.BadRequest(c, "参数错误")

		return
	}
	var callee models.User
	if err := h.db.Where("uuid = ?", userID).First(&callee).Error; err != nil {

		response.NotFound(c, "user not found")

		return
	}
	tx := h.db.Begin()
	if tx.Error != nil {

		response.ServerError(c, "failed to reject call")

		return
	}
	defer func() {

		if r := recover(); r != nil {

			tx.Rollback()

			panic(r)

		}
	}()
	var call models.Call
	if err := tx.Clauses(clause.Locking{Strength: "UPDATE"}).First(&call, req.CallID).Error; err != nil {

		tx.Rollback()

		response.NotFound(c, "call not found")

		return
	}
	if call.CalleeID != callee.ID {

		tx.Rollback()

		response.Forbidden(c, "无权操作")

		return
	}
	if isTerminalCallStatus(call.Status) {

		// 终态请求按幂等成功返回，不重复计算时长、写聊天记录或发送释放事件。

		tx.Rollback()

		response.Success(c, callReleaseResponse("call already finished", call))

		return
	}
	reason := req.Reason
	if reason == "" {

		reason = "decline"
	}
	if call.Status != "calling" {

		tx.Rollback()

		response.BadRequest(c, "call is not waiting for rejection")

		return
	}
	oldStatus := call.Status
	call.Status = "rejected"
	call.EndTime = callTimePtr(time.Now())
	call.EndReason = reason
	if err := tx.Save(&call).Error; err != nil {

		tx.Rollback()

		response.ServerError(c, "failed to reject call")

		return
	}
	if err := tx.Commit().Error; err != nil {

		response.ServerError(c, "failed to reject call")

		return
	}
	recordCallObservability(h.db, callAuditEvent{

		CallID: uint64(call.ID),

		EventType: "reject",

		ActorID: callActorPtr(callee.ID),

		CallerID: call.CallerID,

		CalleeID: call.CalleeID,

		OldStatus: oldStatus,

		NewStatus: call.Status,

		Reason: call.EndReason,

		Duration: call.Duration,

		LatencyMS: time.Since(requestStartedAt).Milliseconds(),

		RequestID: requestID,
	})
	var caller models.User
	h.db.First(&caller, call.CallerID)
	h.sendCallReleasedEvent(caller.UUID, call)
	h.wsHub.SendToUser(caller.UUID, map[string]interface{}{

		"type": "call_rejected",

		"data": map[string]interface{}{

			"call_id": call.ID,

			"reason": reason,
		},
	})
	h.sendCallMessage(c.Request.Context(), &caller, &callee, &call)
	response.Success(c, callReleaseResponse("拒绝成功", call))
}

type EndCallRequest struct {
	CallID uint   `json:"call_id" binding:"required"`
	Reason string `json:"reason"` // hangup/timeout/error
}

func (h *CallHandler) EndCall(c *gin.Context) {
	requestStartedAt := time.Now()
	requestID := requestIDFromContext(c)
	userID := c.GetString("user_id")
	var req EndCallRequest
	if err := c.ShouldBindJSON(&req); err != nil {

		response.BadRequest(c, "参数错误")

		return
	}
	var user models.User
	if err := h.db.Where("uuid = ?", userID).First(&user).Error; err != nil {

		response.NotFound(c, "user not found")

		return
	}
	tx := h.db.Begin()
	if tx.Error != nil {

		response.ServerError(c, "failed to end call")

		return
	}
	defer func() {

		if r := recover(); r != nil {

			tx.Rollback()

			panic(r)

		}
	}()
	var call models.Call
	if err := tx.Clauses(clause.Locking{Strength: "UPDATE"}).First(&call, req.CallID).Error; err != nil {

		tx.Rollback()

		response.NotFound(c, "call not found")

		return
	}
	if call.CallerID != user.ID && call.CalleeID != user.ID {

		tx.Rollback()

		response.Forbidden(c, "无权操作")

		return
	}
	reason := req.Reason
	if reason == "" {

		reason = "hangup"
	}
	if isTerminalCallStatus(call.Status) {

		tx.Rollback()

		response.Success(c, callReleaseResponse("call already finished", call))

		return
	}
	endedAt := time.Now()
	oldStatus := call.Status
	finishActiveCallForRelease(&call, reason, endedAt)
	if err := tx.Save(&call).Error; err != nil {

		tx.Rollback()

		response.ServerError(c, "failed to end call")

		return
	}
	if err := tx.Commit().Error; err != nil {

		response.ServerError(c, "failed to end call")

		return
	}
	recordCallObservability(h.db, callAuditEvent{

		CallID: uint64(call.ID),

		EventType: "end",

		ActorID: callActorPtr(user.ID),

		CallerID: call.CallerID,

		CalleeID: call.CalleeID,

		OldStatus: oldStatus,

		NewStatus: call.Status,

		Reason: call.EndReason,

		Duration: call.Duration,

		LatencyMS: time.Since(requestStartedAt).Milliseconds(),

		RequestID: requestID,
	})
	var otherUserID uint64
	if call.CallerID == user.ID {

		otherUserID = call.CalleeID
	} else {

		otherUserID = call.CallerID
	}
	var otherUser models.User
	h.db.First(&otherUser, otherUserID)
	h.sendCallReleasedEvent(otherUser.UUID, call)
	if call.Status == "cancelled" {

		h.wsHub.SendToUser(otherUser.UUID, map[string]interface{}{

			"type": "call_cancelled",

			"data": map[string]interface{}{

				"call_id": call.ID,

				"reason": call.EndReason,
			},
		})
	} else {

		h.wsHub.SendToUser(otherUser.UUID, map[string]interface{}{

			"type": "call_ended",

			"data": map[string]interface{}{

				"call_id": call.ID,

				"reason": call.EndReason,

				"duration": call.Duration,
			},
		})
	}
	var caller, callee models.User
	h.db.First(&caller, call.CallerID)
	h.db.First(&callee, call.CalleeID)
	h.sendCallMessage(c.Request.Context(), &caller, &callee, &call)
	response.Success(c, callReleaseResponse("call ended", call))
}

type CallHeartbeatRequest struct {
	CallID uint `json:"call_id" binding:"required"`
}

func (h *CallHandler) HeartbeatCall(c *gin.Context) {
	userID := c.GetString("user_id")
	var req CallHeartbeatRequest
	if err := c.ShouldBindJSON(&req); err != nil {

		response.BadRequest(c, "invalid parameters")

		return
	}
	var user models.User
	if err := h.db.Where("uuid = ?", userID).First(&user).Error; err != nil {

		response.NotFound(c, "user not found")

		return
	}
	now := time.Now()
	var call models.Call
	if err := h.db.First(&call, req.CallID).Error; err != nil {

		response.NotFound(c, "call not found")

		return
	}
	if call.CallerID != user.ID && call.CalleeID != user.ID {

		response.Forbidden(c, "no permission to access call")

		return
	}
	if isTerminalCallStatus(call.Status) {

		response.Success(c, gin.H{

			"active": false,

			"status": call.Status,
		})

		return
	}
	if call.Status != "connected" {

		response.Success(c, gin.H{

			"active": true,

			"status": call.Status,
		})

		return
	}
	// 条件更新只延长仍为 connected 的通话；与终态转换并发时不会复活已结束记录。
	if err := h.db.Model(&models.Call{}).
		Where("id = ? AND status = ?", call.ID, "connected").
		Update("last_heartbeat_at", now).Error; err != nil {

		response.ServerError(c, "failed to update call heartbeat")

		return
	}
	response.Success(c, gin.H{

		"active": true,

		"status": "connected",
	})
}
func (h *CallHandler) GetActiveCall(c *gin.Context) {
	userID := c.GetString("user_id")
	var user models.User
	if err := h.db.Where("uuid = ?", userID).First(&user).Error; err != nil {

		response.NotFound(c, "user not found")

		return
	}
	now := time.Now()
	tx := h.db.Begin()
	if tx.Error != nil {

		response.ServerError(c, "failed to check active call")

		return
	}
	if err := h.expireStaleActiveCalls(tx, []uint64{user.ID}, now); err != nil {

		tx.Rollback()

		response.ServerError(c, "failed to check active call")

		return
	}
	if err := tx.Commit().Error; err != nil {

		response.ServerError(c, "failed to check active call")

		return
	}
	var call models.Call
	if err := h.db.Where(

		"status IN ? AND (caller_id = ? OR callee_id = ?)",

		[]string{"calling", "connected"},

		user.ID,

		user.ID,
	).Order("id DESC").First(&call).Error; err != nil {

		if !errors.Is(err, gorm.ErrRecordNotFound) {

			response.ServerError(c, "failed to check active call")

			return

		}

		response.Success(c, gin.H{"active": false})

		return
	}
	remoteID := call.CalleeID
	role := "caller"
	if call.CalleeID == user.ID {

		remoteID = call.CallerID

		role = "callee"
	}
	var remote models.User
	_ = h.db.First(&remote, remoteID).Error
	response.Success(c, gin.H{

		"active": true,

		"call_id": call.ID,

		"status": call.Status,

		"call_type": call.CallType,

		"role": role,

		"start_time": call.StartTime,

		"connect_time": call.ConnectTime,

		"channel_name": call.ChannelName,

		"room_name": call.ChannelName,

		"provider": effectiveRTCProvider(call.RTCProvider),

		"rtc_provider": effectiveRTCProvider(call.RTCProvider),

		"remote_id": remote.UUID,

		"remote_name": remote.Nickname,

		"remote_avatar": remote.Avatar,
	})
}

// CancelCall
func (h *CallHandler) CancelCall(c *gin.Context) {
	requestStartedAt := time.Now()
	requestID := requestIDFromContext(c)
	userID := c.GetString("user_id")
	callID := c.Param("call_id")
	var caller models.User
	if err := h.db.Where("uuid = ?", userID).First(&caller).Error; err != nil {

		response.NotFound(c, "user not found")

		return
	}
	tx := h.db.Begin()
	if tx.Error != nil {

		response.ServerError(c, "failed to cancel call")

		return
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

		response.NotFound(c, "call not found")

		return
	}
	if call.CallerID != caller.ID {

		tx.Rollback()

		response.Forbidden(c, "无权操作")

		return
	}
	if isTerminalCallStatus(call.Status) {

		tx.Rollback()

		response.Success(c, callReleaseResponse("call already finished", call))

		return
	}
	if call.Status != "calling" {

		tx.Rollback()

		response.BadRequest(c, "call is not waiting for cancellation")

		return
	}
	oldStatus := call.Status
	call.Status = "cancelled"
	call.EndTime = callTimePtr(time.Now())
	call.EndReason = "cancelled"
	if err := tx.Save(&call).Error; err != nil {

		tx.Rollback()

		response.ServerError(c, "failed to cancel call")

		return
	}
	if err := tx.Commit().Error; err != nil {

		response.ServerError(c, "failed to cancel call")

		return
	}
	recordCallObservability(h.db, callAuditEvent{

		CallID: uint64(call.ID),

		EventType: "cancel",

		ActorID: callActorPtr(caller.ID),

		CallerID: call.CallerID,

		CalleeID: call.CalleeID,

		OldStatus: oldStatus,

		NewStatus: call.Status,

		Reason: call.EndReason,

		Duration: call.Duration,

		LatencyMS: time.Since(requestStartedAt).Milliseconds(),

		RequestID: requestID,
	})
	var callee models.User
	h.db.First(&callee, call.CalleeID)
	h.sendCallReleasedEvent(callee.UUID, call)
	h.wsHub.SendToUser(callee.UUID, map[string]interface{}{

		"type": "call_cancelled",

		"data": map[string]interface{}{

			"call_id": call.ID,

			"reason": call.EndReason,
		},
	})
	h.sendCallMessage(c.Request.Context(), &caller, &callee, &call)
	response.Success(c, callReleaseResponse("取消成功", call))
}
func (h *CallHandler) GetCallHistory(c *gin.Context) {
	userID := c.GetString("user_id")
	var user models.User
	if err := h.db.Where("uuid = ?", userID).First(&user).Error; err != nil {

		response.NotFound(c, "user not found")

		return
	}
	var calls []models.Call
	h.db.Where("caller_id = ? OR callee_id = ?", user.ID, user.ID).
		Order("start_time DESC").
		Limit(50).
		Find(&calls)
	var result []gin.H
	for _, call := range calls {
		var otherUser models.User

		isOutgoing := call.CallerID == user.ID

		if isOutgoing {

			h.db.First(&otherUser, call.CalleeID)

		} else {

			h.db.First(&otherUser, call.CallerID)

		}
		result = append(result, gin.H{

			"id": call.ID,

			"user_id": otherUser.UUID,

			"user_name": otherUser.Nickname,

			"user_avatar": otherUser.Avatar,

			"call_type": call.CallType,

			"is_outgoing": isOutgoing,

			"status": call.Status,

			"duration": call.Duration,

			"start_time": call.StartTime,

			"end_time": call.EndTime,
		})
	}
	response.Success(c, gin.H{

		"list": result,
	})
}
func (h *CallHandler) GetToken(c *gin.Context) {
	userID := c.GetString("user_id")
	channelName := strings.TrimSpace(c.Query("channel_name"))
	if channelName == "" {

		channelName = strings.TrimSpace(c.Query("room_name"))
	}
	if channelName == "" {

		response.BadRequest(c, "missing channel_name or room_name")

		return
	}
	var user models.User
	if err := h.db.Where("uuid = ?", userID).First(&user).Error; err != nil {

		response.NotFound(c, "user not found")

		return
	}
	var call models.Call
	if err := h.db.Where(

		"channel_name = ? AND (caller_id = ? OR callee_id = ?)",

		channelName,

		user.ID,

		user.ID,
	).Order("id DESC").First(&call).Error; err != nil {

		response.Forbidden(c, "no permission to access call token")

		return
	}
	if isTerminalCallStatus(call.Status) {

		response.BadRequest(c, "call already finished")

		return
	}
	rtcResponse, err := h.buildCallRTCResponse(call.RTCProvider, call.ChannelName, user, gin.H{

		"call_id": call.ID,
	})
	if err != nil {

		response.BadRequest(c, "audio/video service is not configured")

		return
	}
	response.Success(c, rtcResponse)
}
func generateChannelName(userID1, userID2 string) string {
	if userID1 > userID2 {

		userID1, userID2 = userID2, userID1
	}
	uniqueSuffix := strings.ReplaceAll(uuid.NewString(), "-", "")[:12]
	return fmt.Sprintf(

		"call_%s_%s_%s",

		callChannelParticipantPrefix(userID1),

		callChannelParticipantPrefix(userID2),

		uniqueSuffix,
	)
}
func callChannelParticipantPrefix(userID string) string {
	normalized := strings.TrimSpace(userID)
	if normalized == "" {

		return "unknown"
	}
	if len(normalized) > 8 {

		return normalized[:8]
	}
	return normalized
}

// sendCallMessage
func (h *CallHandler) sendCallMessage(ctx context.Context, caller, callee *models.User, call *models.Call) {
	if h.msgService == nil {

		return
	}
	now := time.Now()
	if call.EndTime != nil && !call.EndTime.IsZero() {

		now = *call.EndTime
	} else {

		now = time.Now()
	}
	chat, err := h.getOrCreatePrivateChatForCall(caller, callee, now)
	if err != nil || chat == nil {

		return
	}
	messageText := buildCallMessageText(call)
	params := &services.SendMessageParams{

		ChatID: chat.UUID,

		MsgID: fmt.Sprintf("call:%d", call.ID),

		SenderID: caller.UUID,

		Type: models.MsgTypeCall,

		Content: map[string]interface{}{

			"text": messageText,

			"call_type": call.CallType,

			"duration": call.Duration,

			"status": call.EndReason,
		},
	}
	msg, err := h.msgService.SendMessage(ctx, params, caller.Nickname, caller.Avatar, caller.NicknameColor, caller.EmojiAvatar, []string{caller.UUID, callee.UUID})
	if err != nil || msg == nil {

		return
	}
	h.db.Model(&models.UserChat{}).
		Where("chat_id = ?", chat.ID).
		Updates(map[string]interface{}{

			"last_msg_text": messageText,

			"last_msg_type": models.MsgTypeCall,

			"last_msg_time": msg.CreatedAt,

			"last_msg_seq": msg.Seq,

			"last_msg_sender": caller.Nickname,

			"last_msg_media_url": "",

			"sort_time": msg.CreatedAt,
		})
}
func buildCallMessageText(call *models.Call) string {
	callType := "语音通话"
	if call != nil && call.CallType == "video" {

		callType = "视频通话"
	}
	if call == nil {

		return fmt.Sprintf("%s 未接", callType)
	}
	switch call.EndReason {
	case "hangup", "remote_hangup":

		minutes := call.Duration / 60

		seconds := call.Duration % 60

		return fmt.Sprintf("%s %02d:%02d", callType, minutes, seconds)
	case "decline":

		return fmt.Sprintf("%s 已拒绝", callType)
	case "busy":

		return fmt.Sprintf("%s 对方忙", callType)
	case "timeout":

		return fmt.Sprintf("%s 未接", callType)
	case "cancelled":

		return fmt.Sprintf("%s 已取消", callType)
	case "admin_force_end", "heartbeat_timeout", "client_replaced":

		if call.Duration > 0 {
			minutes := call.Duration / 60

			seconds := call.Duration % 60

			return fmt.Sprintf("%s %02d:%02d", callType, minutes, seconds)

		}

		return fmt.Sprintf("%s 已结束", callType)
	default:

		if call.Duration > 0 {
			minutes := call.Duration / 60

			seconds := call.Duration % 60

			return fmt.Sprintf("%s %02d:%02d", callType, minutes, seconds)

		}

		return fmt.Sprintf("%s 未接", callType)
	}
}
func (h *CallHandler) getOrCreatePrivateChatForCall(caller, callee *models.User, now time.Time) (*models.Chat, error) {
	var chat models.Chat
	err := h.db.Raw(` 

SELECT c.* FROM chats c 

JOIN chat_members cm1 ON c.id = cm1.chat_id AND cm1.user_id = ? 

JOIN chat_members cm2 ON c.id = cm2.chat_id AND cm2.user_id = ? 

WHERE c.type = 1 

LIMIT 1 
`, caller.ID, callee.ID).Scan(&chat).Error
	if err == nil && chat.ID > 0 {

		if err := h.ensureCallUserChatRecord(chat.ID, caller.ID, callee.ID, now); err != nil {

			return nil, err

		}

		if err := h.ensureCallUserChatRecord(chat.ID, callee.ID, caller.ID, now); err != nil {

			return nil, err

		}

		return &chat, nil
	}
	chat = models.Chat{

		UUID: uuid.NewString(),

		Type: 1,

		MemberCount: 2,

		InviteLink: uuid.NewString()[:8],

		CreatedAt: now,

		UpdatedAt: now,
	}
	tx := h.db.Begin()
	if tx.Error != nil {

		return nil, tx.Error
	}
	defer func() {

		if r := recover(); r != nil {

			tx.Rollback()

			panic(r)

		}
	}()
	if err := tx.Create(&chat).Error; err != nil {

		tx.Rollback()

		return nil, err
	}
	if err := tx.Create(&models.ChatMember{

		ChatID: chat.ID,

		UserID: caller.ID,

		Role: 0,

		JoinedAt: now,

		UpdatedAt: now,
	}).Error; err != nil {

		tx.Rollback()

		return nil, err
	}
	if err := tx.Create(&models.ChatMember{

		ChatID: chat.ID,

		UserID: callee.ID,

		Role: 0,

		JoinedAt: now,

		UpdatedAt: now,
	}).Error; err != nil {

		tx.Rollback()

		return nil, err
	}
	if err := tx.Create(&models.UserChat{

		UserID: caller.ID,

		ChatID: chat.ID,

		TargetID: callee.ID,

		SortTime: now,

		UpdatedAt: now,
	}).Error; err != nil {

		tx.Rollback()

		return nil, err
	}
	if err := tx.Create(&models.UserChat{

		UserID: callee.ID,

		ChatID: chat.ID,

		TargetID: caller.ID,

		SortTime: now,

		UpdatedAt: now,
	}).Error; err != nil {

		tx.Rollback()

		return nil, err
	}
	if err := tx.Commit().Error; err != nil {

		return nil, err
	}
	return &chat, nil
}
func (h *CallHandler) ensureCallUserChatRecord(chatID, userID, targetID uint64, sortTime time.Time) error {
	effectiveTime := sortTime
	if effectiveTime.IsZero() {

		effectiveTime = time.Now()
	}
	var userChat models.UserChat
	if err := h.db.Where("chat_id = ? AND user_id = ?", chatID, userID).First(&userChat).Error; err == nil {

		return h.db.Model(&models.UserChat{}).
			Where("id = ?", userChat.ID).
			Updates(map[string]interface{}{

				"target_id": targetID,

				"updated_at": effectiveTime,

				"sort_time": effectiveTime,

				"is_archived": false,
			}).Error
	}
	return h.db.Create(&models.UserChat{

		UserID: userID,

		ChatID: chatID,

		TargetID: targetID,

		SortTime: effectiveTime,

		UpdatedAt: effectiveTime,
	}).Error
}
