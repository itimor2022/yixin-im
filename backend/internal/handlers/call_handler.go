package handlers

import (
	"context"
	"fmt"
	"strconv"
	"strings"
	"time"

	"github.com/gin-gonic/gin"
	"github.com/google/uuid"
	"gorm.io/gorm"
	"gorm.io/gorm/clause"

	"gaoranim/internal/models"
	"gaoranim/internal/services"
	"gaoranim/pkg/response"
)

type WebSocketHub interface {
	SendToUser(userID string, data interface{})
	SendToUserCluster(userID string, data interface{}) // ★ 集群版，跨节点路由
}

// CallHandler
type CallHandler struct {
	db           *gorm.DB
	agoraService *services.AgoraService
	wsHub        WebSocketHub
	msgService   *services.MessageService
	pushService  *services.PushService
}

// NewCallHandler
func NewCallHandler(db *gorm.DB, agoraService *services.AgoraService, wsHub WebSocketHub, msgService *services.MessageService, pushService *services.PushService) *CallHandler {
	return &CallHandler{
		db:           db,
		agoraService: agoraService,
		wsHub:        wsHub,
		msgService:   msgService,
		pushService:  pushService,
	}
}

func (h *CallHandler) GetAgoraConfig(c *gin.Context) {
	enabled, appID, _, _ := h.getAgoraConfigFromDB()

	response.Success(c, gin.H{
		"enabled": enabled,
		"app_id":  appID,
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

func isTerminalCallStatus(status string) bool {
	switch status {
	case "ended", "rejected", "cancelled", "missed":
		return true
	default:
		return false
	}
}

func (h *CallHandler) CreateCall(c *gin.Context) {
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

	enabled, appID, appCertificate, tokenExpire := h.getAgoraConfigFromDB()
	if !enabled {
		response.BadRequest(c, "音视频通话未启用")
		return
	}

	var caller models.User
	if err := h.db.Where("uuid = ?", userID).First(&caller).Error; err != nil {
		response.NotFound(c, "用户不存在")
		return
	}

	var callee models.User
	if err := h.db.Where("uuid = ?", req.TargetUserID).First(&callee).Error; err != nil {
		response.NotFound(c, "目标用户不存在")
		return
	}

	if callee.Status != models.UserStatusNormal {
		response.Forbidden(c, "target user is unavailable")
		return
	}

	channelName := generateChannelName(userID, req.TargetUserID)
	agoraSvc := services.NewAgoraService(enabled, appID, appCertificate, tokenExpire)
	token, err := agoraSvc.GenerateRTCToken(channelName, 0, services.RolePublisher)
	if err != nil {
		response.ServerError(c, "生成通话 Token 失败")
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
	if err := tx.Clauses(clause.Locking{Strength: "UPDATE"}).
		Where("id IN ?", lockedUserIDs).
		Order("id ASC").
		Find(&[]models.User{}).Error; err != nil {
		tx.Rollback()
		response.ServerError(c, "failed to create call")
		return
	}

	activeSince := time.Now().Add(-2 * time.Hour)
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
		response.BadRequest(c, "user is already in a call")
		return
	}

	call := &models.Call{
		ChannelName: channelName,
		CallerID:    caller.ID,
		CalleeID:    callee.ID,
		CallType:    req.CallType,
		Status:      "calling",
		StartTime:   time.Now(),
	}
	if err := tx.Create(call).Error; err != nil {
		tx.Rollback()
		response.ServerError(c, "failed to create call")
		return
	}
	if err := tx.Commit().Error; err != nil {
		response.ServerError(c, "failed to create call")
		return
	}

	h.wsHub.SendToUserCluster(req.TargetUserID, map[string]interface{}{
		"type": "incoming_call",
		"data": map[string]interface{}{
			"call_id":       call.ID,
			"channel_name":  channelName,
			"caller_id":     userID,
			"caller_name":   caller.Nickname,
			"caller_avatar": caller.Avatar,
			"call_type":     req.CallType,
		},
	})

	if h.pushService != nil {
		isVideo := req.CallType == "video"
		go h.pushService.PushIncomingCall(callee.ID, caller.Nickname, fmt.Sprintf("%d", call.ID), isVideo, map[string]interface{}{
			"channel_name":  channelName,
			"caller_id":     caller.UUID,
			"caller_avatar": caller.Avatar,
		})
	}

	response.Success(c, gin.H{
		"call_id":      call.ID,
		"channel_name": channelName,
		"token":        token,
		"app_id":       appID,
	})
}

type AcceptCallRequest struct {
	CallID uint `json:"call_id" binding:"required"`
}

func (h *CallHandler) AcceptCall(c *gin.Context) {
	userID := c.GetString("user_id")

	var req AcceptCallRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		response.BadRequest(c, "参数错误")
		return
	}

	enabled, appID, appCertificate, tokenExpire := h.getAgoraConfigFromDB()
	if !enabled {
		response.BadRequest(c, "音视频通话未启用")
		return
	}

	var callee models.User
	if err := h.db.Where("uuid = ?", userID).First(&callee).Error; err != nil {
		response.NotFound(c, "用户不存在")
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

	var call models.Call
	if err := tx.Clauses(clause.Locking{Strength: "UPDATE"}).First(&call, req.CallID).Error; err != nil {
		tx.Rollback()
		response.NotFound(c, "通话不存在")
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

	agoraSvc := services.NewAgoraService(enabled, appID, appCertificate, tokenExpire)
	token, err := agoraSvc.GenerateRTCToken(call.ChannelName, 0, services.RolePublisher)
	if err != nil {
		tx.Rollback()
		response.ServerError(c, "生成通话 Token 失败")
		return
	}

	call.Status = "connected"
	call.ConnectTime = time.Now()
	if err := tx.Save(&call).Error; err != nil {
		tx.Rollback()
		response.ServerError(c, "failed to accept call")
		return
	}
	if err := tx.Commit().Error; err != nil {
		response.ServerError(c, "failed to accept call")
		return
	}

	var caller models.User
	h.db.First(&caller, call.CallerID)
	h.wsHub.SendToUserCluster(caller.UUID, map[string]interface{}{
		"type": "call_accepted",
		"data": map[string]interface{}{
			"call_id": call.ID,
		},
	})

	response.Success(c, gin.H{
		"call_id":      call.ID,
		"channel_name": call.ChannelName,
		"token":        token,
		"app_id":       appID,
	})
}

type RejectCallRequest struct {
	CallID uint   `json:"call_id" binding:"required"`
	Reason string `json:"reason"` // busy/decline
}

func (h *CallHandler) RejectCall(c *gin.Context) {
	userID := c.GetString("user_id")

	var req RejectCallRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		response.BadRequest(c, "参数错误")
		return
	}

	var callee models.User
	if err := h.db.Where("uuid = ?", userID).First(&callee).Error; err != nil {
		response.NotFound(c, "用户不存在")
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
		response.NotFound(c, "通话不存在")
		return
	}
	if call.CalleeID != callee.ID {
		tx.Rollback()
		response.Forbidden(c, "无权操作")
		return
	}
	if isTerminalCallStatus(call.Status) {
		tx.Rollback()
		response.Success(c, gin.H{
			"message":  "call already finished",
			"duration": call.Duration,
		})
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

	call.Status = "rejected"
	call.EndTime = time.Now()
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

	var caller models.User
	h.db.First(&caller, call.CallerID)
	h.wsHub.SendToUserCluster(caller.UUID, map[string]interface{}{
		"type": "call_rejected",
		"data": map[string]interface{}{
			"call_id": call.ID,
			"reason":  reason,
		},
	})
	h.sendCallMessage(c.Request.Context(), &caller, &callee, &call)

	response.Success(c, gin.H{"message": "拒绝成功"})
}

type EndCallRequest struct {
	CallID uint   `json:"call_id" binding:"required"`
	Reason string `json:"reason"` // hangup/timeout/error
}

func (h *CallHandler) EndCall(c *gin.Context) {
	userID := c.GetString("user_id")

	var req EndCallRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		response.BadRequest(c, "参数错误")
		return
	}

	var user models.User
	if err := h.db.Where("uuid = ?", userID).First(&user).Error; err != nil {
		response.NotFound(c, "用户不存在")
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
		response.NotFound(c, "通话不存在")
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
		response.Success(c, gin.H{
			"message":  "call already finished",
			"duration": call.Duration,
		})
		return
	}

	call.Status = "ended"
	call.EndTime = time.Now()
	call.EndReason = reason
	if !call.ConnectTime.IsZero() {
		call.Duration = int(call.EndTime.Sub(call.ConnectTime).Seconds())
	}
	if err := tx.Save(&call).Error; err != nil {
		tx.Rollback()
		response.ServerError(c, "failed to end call")
		return
	}
	if err := tx.Commit().Error; err != nil {
		response.ServerError(c, "failed to end call")
		return
	}

	var otherUserID uint64
	if call.CallerID == user.ID {
		otherUserID = call.CalleeID
	} else {
		otherUserID = call.CallerID
	}

	var otherUser models.User
	h.db.First(&otherUser, otherUserID)
	h.wsHub.SendToUserCluster(otherUser.UUID, map[string]interface{}{
		"type": "call_ended",
		"data": map[string]interface{}{
			"call_id":  call.ID,
			"reason":   reason,
			"duration": call.Duration,
		},
	})

	var caller, callee models.User
	h.db.First(&caller, call.CallerID)
	h.db.First(&callee, call.CalleeID)
	h.sendCallMessage(c.Request.Context(), &caller, &callee, &call)

	response.Success(c, gin.H{
		"message":  "通话已结束",
		"duration": call.Duration,
	})
}

// CancelCall
func (h *CallHandler) CancelCall(c *gin.Context) {
	userID := c.GetString("user_id")
	callID := c.Param("call_id")

	var caller models.User
	if err := h.db.Where("uuid = ?", userID).First(&caller).Error; err != nil {
		response.NotFound(c, "用户不存在")
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
		response.NotFound(c, "通话不存在")
		return
	}
	if call.CallerID != caller.ID {
		tx.Rollback()
		response.Forbidden(c, "无权操作")
		return
	}
	if isTerminalCallStatus(call.Status) {
		tx.Rollback()
		response.Success(c, gin.H{
			"message":  "call already finished",
			"duration": call.Duration,
		})
		return
	}
	if call.Status != "calling" {
		tx.Rollback()
		response.BadRequest(c, "call is not waiting for cancellation")
		return
	}

	call.Status = "cancelled"
	call.EndTime = time.Now()
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

	var callee models.User
	h.db.First(&callee, call.CalleeID)
	h.wsHub.SendToUserCluster(callee.UUID, map[string]interface{}{
		"type": "call_cancelled",
		"data": map[string]interface{}{
			"call_id": call.ID,
		},
	})
	h.sendCallMessage(c.Request.Context(), &caller, &callee, &call)

	response.Success(c, gin.H{"message": "取消成功"})
}

func (h *CallHandler) GetCallHistory(c *gin.Context) {
	userID := c.GetString("user_id")

	var user models.User
	if err := h.db.Where("uuid = ?", userID).First(&user).Error; err != nil {
		response.NotFound(c, "用户不存在")
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
			"id":          call.ID,
			"user_id":     otherUser.UUID,
			"user_name":   otherUser.Nickname,
			"user_avatar": otherUser.Avatar,
			"call_type":   call.CallType,
			"is_outgoing": isOutgoing,
			"status":      call.Status,
			"duration":    call.Duration,
			"start_time":  call.StartTime,
			"end_time":    call.EndTime,
		})
	}

	response.Success(c, gin.H{
		"list": result,
	})
}

func (h *CallHandler) GetToken(c *gin.Context) {
	userID := c.GetString("user_id")
	channelName := c.Query("channel_name")

	if channelName == "" {
		response.BadRequest(c, "缺少 channel_name")
		return
	}

	enabled, appID, appCertificate, tokenExpire := h.getAgoraConfigFromDB()
	if !enabled {
		response.BadRequest(c, "音视频通话未启用")
		return
	}

	var user models.User
	if err := h.db.Where("uuid = ?", userID).First(&user).Error; err != nil {
		response.NotFound(c, "用户不存在")
		return
	}

	agoraSvc := services.NewAgoraService(enabled, appID, appCertificate, tokenExpire)
	token, err := agoraSvc.GenerateRTCToken(channelName, 0, services.RolePublisher)
	if err != nil {
		response.ServerError(c, "生成通话 Token 失败")
		return
	}

	response.Success(c, gin.H{
		"token":  token,
		"app_id": appID,
	})
}

func generateChannelName(userID1, userID2 string) string {
	if userID1 > userID2 {
		userID1, userID2 = userID2, userID1
	}
	return fmt.Sprintf("call_%s_%s_%d", userID1[:8], userID2[:8], time.Now().Unix())
}

// sendCallMessage
func (h *CallHandler) sendCallMessage(ctx context.Context, caller, callee *models.User, call *models.Call) {
	if h.msgService == nil {
		return
	}

	now := call.EndTime
	if now.IsZero() {
		now = time.Now()
	}

	chat, err := h.getOrCreatePrivateChatForCall(caller, callee, now)
	if err != nil || chat == nil {
		return
	}

	callType := "语音通话"
	if call.CallType == "video" {
		callType = "视频通话"
	}

	var messageText string
	switch call.EndReason {
	case "hangup", "remote_hangup":
		duration := call.Duration
		minutes := duration / 60
		seconds := duration % 60
		messageText = fmt.Sprintf("%s %02d:%02d", callType, minutes, seconds)
	case "decline":
		messageText = fmt.Sprintf("%s declined", callType)
	case "busy":
		messageText = fmt.Sprintf("%s busy", callType)
	case "timeout":
		messageText = fmt.Sprintf("%s missed", callType)
	case "cancelled":
		messageText = fmt.Sprintf("%s cancelled", callType)
	default:
		if call.Duration > 0 {
			minutes := call.Duration / 60
			seconds := call.Duration % 60
			messageText = fmt.Sprintf("%s %02d:%02d", callType, minutes, seconds)
		} else {
			messageText = fmt.Sprintf("%s missed", callType)
		}
	}

	params := &services.SendMessageParams{
		ChatID:   chat.UUID,
		MsgID:    fmt.Sprintf("call:%d", call.ID),
		SenderID: caller.UUID,
		Type:     models.MsgTypeCall,
		Content: map[string]interface{}{
			"text":      messageText,
			"call_type": call.CallType,
			"duration":  call.Duration,
			"status":    call.EndReason,
		},
	}

	msg, err := h.msgService.SendMessage(ctx, params, caller.Nickname, caller.Avatar, caller.NicknameColor, caller.PremiumType, caller.EmojiAvatar, []string{caller.UUID, callee.UUID})
	if err != nil || msg == nil {
		return
	}

	h.db.Model(&models.UserChat{}).
		Where("chat_id = ?", chat.ID).
		Updates(map[string]interface{}{
			"last_msg_text": messageText,
			"last_msg_type": models.MsgTypeCall,
			"last_msg_time": msg.CreatedAt,
			"sort_time":     msg.CreatedAt,
		})
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
		UUID:        uuid.NewString(),
		Type:        1,
		MemberCount: 2,
		InviteLink:  uuid.NewString()[:8],
		CreatedAt:   now,
		UpdatedAt:   now,
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
		ChatID:    chat.ID,
		UserID:    caller.ID,
		Role:      0,
		JoinedAt:  now,
		UpdatedAt: now,
	}).Error; err != nil {
		tx.Rollback()
		return nil, err
	}
	if err := tx.Create(&models.ChatMember{
		ChatID:    chat.ID,
		UserID:    callee.ID,
		Role:      0,
		JoinedAt:  now,
		UpdatedAt: now,
	}).Error; err != nil {
		tx.Rollback()
		return nil, err
	}
	if err := tx.Create(&models.UserChat{
		UserID:    caller.ID,
		ChatID:    chat.ID,
		TargetID:  callee.ID,
		SortTime:  now,
		UpdatedAt: now,
	}).Error; err != nil {
		tx.Rollback()
		return nil, err
	}
	if err := tx.Create(&models.UserChat{
		UserID:    callee.ID,
		ChatID:    chat.ID,
		TargetID:  caller.ID,
		SortTime:  now,
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
				"target_id":   targetID,
				"updated_at":  effectiveTime,
				"sort_time":   effectiveTime,
				"is_archived": false,
			}).Error
	}

	return h.db.Create(&models.UserChat{
		UserID:    userID,
		ChatID:    chatID,
		TargetID:  targetID,
		SortTime:  effectiveTime,
		UpdatedAt: effectiveTime,
	}).Error
}
