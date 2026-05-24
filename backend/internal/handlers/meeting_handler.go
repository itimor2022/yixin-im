package handlers

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"strconv"
	"strings"
	"time"

	"gaoranim/internal/models"
	"gaoranim/internal/services"
	"gaoranim/internal/textutil"
	"gaoranim/pkg/response"

	"github.com/gin-gonic/gin"
	"github.com/google/uuid"
	"gorm.io/gorm"
	"gorm.io/gorm/clause"
)

var errMeetingParticipantKicked = errors.New("meeting participant kicked")
var errMeetingCapacityReached = errors.New("meeting capacity reached")
var errMeetingNotActive = errors.New("meeting not active")
var errMeetingJoinApprovalRequired = errors.New("meeting join approval required")

type MeetingWebSocketHub interface {
	SendToUser(userID string, data interface{})
	SendToUserCluster(userID string, data interface{}) // ★ 集群版，跨节点路由
}

// MeetingHandler 群会议处理器（MVP）
type MeetingHandler struct {
	db           *gorm.DB
	agoraService *services.AgoraService
	wsHub        MeetingWebSocketHub
	pushService  *services.PushService
	msgService   *services.MessageService
}

func NewMeetingHandler(db *gorm.DB, agoraService *services.AgoraService, wsHub MeetingWebSocketHub, pushService *services.PushService, msgService *services.MessageService) *MeetingHandler {
	return &MeetingHandler{
		db:           db,
		agoraService: agoraService,
		wsHub:        wsHub,
		pushService:  pushService,
		msgService:   msgService,
	}
}

func (h *MeetingHandler) getAgoraConfigFromDB() (enabled bool, appID, appCertificate string, tokenExpire int) {
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

type CreateMeetingRequest struct {
	ChatID          string   `json:"chat_id"`
	Title           string   `json:"title"`
	MeetingType     string   `json:"meeting_type"`
	CallType        string   `json:"call_type"`
	InviteeUserIDs  []string `json:"invitee_user_ids"`
	MaxParticipants int      `json:"max_participants"`
}

func (h *MeetingHandler) CreateMeeting(c *gin.Context) {
	userUUID := c.GetString("user_id")

	var req CreateMeetingRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		response.BadRequest(c, "参数错误")
		return
	}

	meetingType, ok := normalizeMeetingType(req.MeetingType, req.CallType)
	if !ok {
		response.BadRequest(c, "meeting_type 仅支持 voice/video")
		return
	}

	maxParticipants := req.MaxParticipants
	if maxParticipants <= 0 {
		maxParticipants = 16
	}
	if maxParticipants > 200 {
		maxParticipants = 200
	}

	enabled, appID, appCertificate, tokenExpire := h.getAgoraConfigFromDB()
	if !enabled {
		response.BadRequest(c, "音视频服务未启用")
		return
	}

	creator, err := h.getUserByUUID(userUUID)
	if err != nil {
		response.NotFound(c, "用户不存在")
		return
	}

	var chat *models.Chat
	if strings.TrimSpace(req.ChatID) != "" {
		cItem, err := h.getChatByUUID(req.ChatID)
		if err != nil {
			response.NotFound(c, "群聊不存在")
			return
		}
		if cItem.Type != 2 && cItem.Type != 3 {
			response.BadRequest(c, "仅支持在群聊/频道内发起会议")
			return
		}
		if !h.isChatMember(cItem.ID, creator.ID) {
			response.Forbidden(c, "无权限在该群发起会议")
			return
		}
		chat = cItem
	}

	invitees := h.resolveInvitees(req.InviteeUserIDs, creator.ID, chat)

	now := time.Now()
	meetingUUID := uuid.New().String()
	channelName := generateMeetingChannelName(meetingUUID)
	meeting := &models.Meeting{
		UUID:            meetingUUID,
		ChannelName:     channelName,
		CreatorID:       creator.ID,
		Title:           strings.TrimSpace(req.Title),
		MeetingType:     meetingType,
		Status:          models.MeetingStatusActive,
		MaxParticipants: maxParticipants,
		StartTime:       now,
	}
	if chat != nil {
		meeting.ChatID = chat.ID
	}

	if err := h.db.Transaction(func(tx *gorm.DB) error {
		if err := tx.Create(meeting).Error; err != nil {
			return err
		}

		joinedAt := now
		host := &models.MeetingParticipant{
			MeetingID: meeting.ID,
			UserID:    creator.ID,
			Role:      models.MeetingParticipantRoleHost,
			Status:    models.MeetingParticipantStatusJoined,
			JoinedAt:  &joinedAt,
		}
		if err := tx.Create(host).Error; err != nil {
			return err
		}

		if len(invitees) > 0 {
			participants := make([]models.MeetingParticipant, 0, len(invitees))
			invites := make([]models.MeetingInvite, 0, len(invitees))
			for _, user := range invitees {
				participants = append(participants, models.MeetingParticipant{
					MeetingID: meeting.ID,
					UserID:    user.ID,
					Role:      models.MeetingParticipantRoleMember,
					Status:    models.MeetingParticipantStatusInvited,
					InviterID: creator.ID,
				})
				invites = append(invites, models.MeetingInvite{
					MeetingID:  meeting.ID,
					InviterID:  creator.ID,
					InviteeID:  user.ID,
					InviteType: models.MeetingInviteTypeInvite,
					Status:     models.MeetingInviteStatusPending,
				})
			}

			if err := tx.Create(&participants).Error; err != nil {
				return err
			}
			if err := tx.Create(&invites).Error; err != nil {
				return err
			}
		}
		return nil
	}); err != nil {
		response.ServerError(c, "创建会议失败")
		return
	}

	agoraSvc := services.NewAgoraService(enabled, appID, appCertificate, tokenExpire)
	token, err := agoraSvc.GenerateRTCToken(channelName, toAgoraUID(creator.ID), services.RolePublisher)
	if err != nil {
		response.ServerError(c, "生成Token失败")
		return
	}

	chatUUID := ""
	if chat != nil {
		chatUUID = chat.UUID
	}
	for _, invitee := range invitees {
		h.wsHub.SendToUserCluster(invitee.UUID, map[string]interface{}{
			"type": "meeting_invite",
			"data": gin.H{
				"meeting_id":     meeting.UUID,
				"channel_name":   meeting.ChannelName,
				"meeting_type":   meeting.MeetingType,
				"title":          meeting.Title,
				"chat_id":        chatUUID,
				"inviter_id":     creator.UUID,
				"inviter_name":   creator.Nickname,
				"inviter_avatar": creator.Avatar,
				"start_time":     meeting.StartTime,
			},
		})

		if h.pushService != nil {
			go h.pushService.PushToUser(invitee.ID, creator.Nickname, "邀请你加入群会议", map[string]interface{}{
				"type":       "meeting_invite",
				"meeting_id": meeting.UUID,
			})
		}
	}

	if chat != nil {
		startEvent := map[string]interface{}{
			"type": "meeting_started",
			"data": gin.H{
				"meeting_id":   meeting.UUID,
				"chat_id":      chatUUID,
				"title":        meeting.Title,
				"meeting_type": meeting.MeetingType,
				"channel_name": meeting.ChannelName,
				"host_user_id": creator.UUID,
				"host_name":    creator.Nickname,
				"host_avatar":  creator.Avatar,
				"start_time":   meeting.StartTime,
			},
		}
		for _, memberUUID := range h.getChatMemberUUIDs(chat.ID, 0) {
			h.wsHub.SendToUserCluster(memberUUID, startEvent)
		}

		h.sendMeetingSystemMessage(
			c.Request.Context(),
			chat,
			map[string]interface{}{
				"type":         "meeting_started",
				"meeting_id":   meeting.UUID,
				"chat_id":      chatUUID,
				"title":        meeting.Title,
				"meeting_type": meeting.MeetingType,
				"channel_name": meeting.ChannelName,
				"host_user_id": creator.UUID,
				"host_name":    creator.Nickname,
				"host_avatar":  creator.Avatar,
				"start_time":   meeting.StartTime,
			},
			func() string {
				meetingLabel := "视频群会议"
				if meeting.MeetingType == models.MeetingTypeVoice {
					meetingLabel = "语音群会议"
				}
				if strings.TrimSpace(meeting.Title) != "" {
					return creator.Nickname + "发起了" + meetingLabel + "：" + meeting.Title
				}
				return creator.Nickname + "发起了" + meetingLabel
			}(),
			h.getChatMemberUUIDs(chat.ID, 0),
		)
	}

	response.Success(c, gin.H{
		"meeting_id":       meeting.UUID,
		"channel_name":     meeting.ChannelName,
		"meeting_type":     meeting.MeetingType,
		"chat_id":          chatUUID,
		"title":            meeting.Title,
		"token":            token,
		"app_id":           appID,
		"agora_uid":        toAgoraUID(creator.ID),
		"max_participants": meeting.MaxParticipants,
		"invite_count":     len(invitees),
		"start_time":       meeting.StartTime,
	})
}

type MeetingIDRequest struct {
	MeetingID string `json:"meeting_id" binding:"required"`
}

func (h *MeetingHandler) JoinMeeting(c *gin.Context) {
	userUUID := c.GetString("user_id")

	var req MeetingIDRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		response.BadRequest(c, "参数错误")
		return
	}

	enabled, appID, appCertificate, tokenExpire := h.getAgoraConfigFromDB()
	if !enabled {
		response.BadRequest(c, "音视频服务未启用")
		return
	}

	user, err := h.getUserByUUID(userUUID)
	if err != nil {
		response.NotFound(c, "用户不存在")
		return
	}

	meeting, err := h.getMeetingByUUID(req.MeetingID)
	if err != nil {
		response.NotFound(c, "会议不存在")
		return
	}
	if meeting.Status != models.MeetingStatusActive {
		response.BadRequest(c, "会议已结束")
		return
	}

	now := time.Now()
	approvalRequired := false
	hostID := meeting.CreatorID
	if err := h.db.Transaction(func(tx *gorm.DB) error {
		lockedMeeting, err := h.lockMeetingForUpdate(tx, meeting.ID)
		if err != nil {
			return err
		}
		if lockedMeeting.Status != models.MeetingStatusActive {
			return errMeetingNotActive
		}

		hostID = lockedMeeting.CreatorID

		hasHostInvite, err := h.hasHostInviteTx(tx, lockedMeeting.ID, user.ID)
		if err != nil {
			return err
		}

		var participant models.MeetingParticipant
		participantErr := tx.Where("meeting_id = ? AND user_id = ?", meeting.ID, user.ID).First(&participant).Error
		if participantErr != nil && participantErr != gorm.ErrRecordNotFound {
			return participantErr
		}
		if participantErr == nil && participant.Status == models.MeetingParticipantStatusKicked {
			return errMeetingParticipantKicked
		}

		canDirectJoin := hasHostInvite || participantErr == nil
		if !canDirectJoin {
			if lockedMeeting.ChatID == 0 || !h.isChatMember(lockedMeeting.ChatID, user.ID) {
				return gorm.ErrRecordNotFound
			}
			if err := h.upsertJoinRequestTx(tx, lockedMeeting, user.ID, hostID, now); err != nil {
				return err
			}
			approvalRequired = true
			return nil
		}

		if participantErr == gorm.ErrRecordNotFound {
			var joinedCount int64
			if err := tx.Model(&models.MeetingParticipant{}).
				Where("meeting_id = ? AND status = ?", meeting.ID, models.MeetingParticipantStatusJoined).
				Count(&joinedCount).Error; err != nil {
				return err
			}
			if isMeetingCapacityReached(lockedMeeting.MaxParticipants, joinedCount) {
				return errMeetingCapacityReached
			}
			joinedAt := now
			if err := tx.Create(&models.MeetingParticipant{
				MeetingID: meeting.ID,
				UserID:    user.ID,
				Role:      models.MeetingParticipantRoleMember,
				Status:    models.MeetingParticipantStatusJoined,
				InviterID: hostID,
				JoinedAt:  &joinedAt,
			}).Error; err != nil {
				return err
			}
		} else if participant.Status != models.MeetingParticipantStatusJoined {
			var joinedCount int64
			if err := tx.Model(&models.MeetingParticipant{}).
				Where("meeting_id = ? AND status = ?", meeting.ID, models.MeetingParticipantStatusJoined).
				Count(&joinedCount).Error; err != nil {
				return err
			}
			if isMeetingCapacityReached(lockedMeeting.MaxParticipants, joinedCount) {
				return errMeetingCapacityReached
			}
			updates := map[string]interface{}{
				"status":  models.MeetingParticipantStatusJoined,
				"left_at": nil,
			}
			if participant.JoinedAt == nil || participant.Status != models.MeetingParticipantStatusJoined {
				updates["joined_at"] = now
			}
			if err := tx.Model(&models.MeetingParticipant{}).
				Where("id = ?", participant.ID).
				Updates(updates).Error; err != nil {
				return err
			}
		}

		if err := tx.Model(&models.MeetingInvite{}).
			Where(
				"meeting_id = ? AND invitee_id = ? AND status = ? AND (invite_type = ? OR invite_type = '' OR invite_type IS NULL)",
				meeting.ID,
				user.ID,
				models.MeetingInviteStatusPending,
				models.MeetingInviteTypeInvite,
			).
			Updates(map[string]interface{}{
				"status":       models.MeetingInviteStatusAccepted,
				"responded_at": now,
			}).Error; err != nil {
			return err
		}

		return nil
	}); err != nil {
		if err == errMeetingNotActive {
			response.BadRequest(c, "会议已结束")
			return
		}
		if err == errMeetingCapacityReached {
			response.BadRequest(c, "会议人数已满")
			return
		}
		if err == gorm.ErrRecordNotFound {
			response.Forbidden(c, "没有加入该会议的权限")
			return
		}
		if err == errMeetingParticipantKicked {
			response.Forbidden(c, "你已被移出会议，请等待主持人重新邀请")
			return
		}
		response.ServerError(c, "加入会议失败")
		return
	}

	if approvalRequired {
		host, err := h.getUserByID(hostID)
		if err == nil {
			h.notifyHostJoinRequest(meeting, host, user, now)
		}
		response.SuccessWithMessage(c, "已提交入会申请，请等待主持人确认", gin.H{
			"meeting_id":        meeting.UUID,
			"approval_required": true,
		})
		return
	}

	tokenSvc := services.NewAgoraService(enabled, appID, appCertificate, tokenExpire)
	token, err := tokenSvc.GenerateRTCToken(meeting.ChannelName, toAgoraUID(user.ID), services.RolePublisher)
	if err != nil {
		response.ServerError(c, "生成 Token 失败")
		return
	}

	for _, uid := range h.getParticipantUUIDs(meeting.ID, user.ID) {
		h.wsHub.SendToUserCluster(uid, map[string]interface{}{
			"type": "meeting_member_joined",
			"data": gin.H{
				"meeting_id":   meeting.UUID,
				"user_id":      user.UUID,
				"user_name":    user.Nickname,
				"user_avatar":  user.Avatar,
				"joined_at":    now,
				"meeting_type": meeting.MeetingType,
			},
		})
	}

	response.Success(c, gin.H{
		"meeting_id":   meeting.UUID,
		"channel_name": meeting.ChannelName,
		"meeting_type": meeting.MeetingType,
		"token":        token,
		"app_id":       appID,
		"agora_uid":    toAgoraUID(user.ID),
	})
}

type ReviewJoinRequest struct {
	MeetingID    string `json:"meeting_id" binding:"required"`
	TargetUserID string `json:"target_user_id" binding:"required"`
	Approve      *bool  `json:"approve" binding:"required"`
	Reason       string `json:"reason"`
}

func (h *MeetingHandler) ReviewJoinRequest(c *gin.Context) {
	userUUID := c.GetString("user_id")

	var req ReviewJoinRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		response.BadRequest(c, "参数错误")
		return
	}

	reviewer, err := h.getUserByUUID(userUUID)
	if err != nil {
		response.NotFound(c, "用户不存在")
		return
	}

	meeting, err := h.getMeetingByUUID(req.MeetingID)
	if err != nil {
		response.NotFound(c, "会议不存在")
		return
	}
	if meeting.Status != models.MeetingStatusActive {
		response.BadRequest(c, "会议已结束")
		return
	}
	if meeting.CreatorID != reviewer.ID {
		response.Forbidden(c, "仅会议主持人可以审批入会申请")
		return
	}

	target, err := h.getUserByUUID(req.TargetUserID)
	if err != nil {
		response.NotFound(c, "申请用户不存在")
		return
	}

	now := time.Now()
	approved := req.Approve != nil && *req.Approve
	if err := h.db.Transaction(func(tx *gorm.DB) error {
		lockedMeeting, err := h.lockMeetingForUpdate(tx, meeting.ID)
		if err != nil {
			return err
		}
		if lockedMeeting.Status != models.MeetingStatusActive {
			return errMeetingNotActive
		}

		var joinReq models.MeetingInvite
		if err := tx.Where(
			"meeting_id = ? AND inviter_id = ? AND invite_type = ? AND status = ?",
			meeting.ID,
			target.ID,
			models.MeetingInviteTypeJoinRequest,
			models.MeetingInviteStatusPending,
		).Order("id DESC").First(&joinReq).Error; err != nil {
			return err
		}

		nextStatus := models.MeetingInviteStatusRejected
		if approved {
			nextStatus = models.MeetingInviteStatusAccepted

			var participant models.MeetingParticipant
			participantErr := tx.Where("meeting_id = ? AND user_id = ?", meeting.ID, target.ID).First(&participant).Error
			if participantErr != nil && participantErr != gorm.ErrRecordNotFound {
				return participantErr
			}
			if participantErr == nil && participant.Status == models.MeetingParticipantStatusKicked {
				return errMeetingParticipantKicked
			}

			if participantErr == gorm.ErrRecordNotFound {
				var joinedCount int64
				if err := tx.Model(&models.MeetingParticipant{}).
					Where("meeting_id = ? AND status = ?", meeting.ID, models.MeetingParticipantStatusJoined).
					Count(&joinedCount).Error; err != nil {
					return err
				}
				if isMeetingCapacityReached(lockedMeeting.MaxParticipants, joinedCount) {
					return errMeetingCapacityReached
				}
				joinedAt := now
				if err := tx.Create(&models.MeetingParticipant{
					MeetingID: meeting.ID,
					UserID:    target.ID,
					Role:      models.MeetingParticipantRoleMember,
					Status:    models.MeetingParticipantStatusJoined,
					InviterID: reviewer.ID,
					JoinedAt:  &joinedAt,
				}).Error; err != nil {
					return err
				}
			} else if participant.Status != models.MeetingParticipantStatusJoined {
				var joinedCount int64
				if err := tx.Model(&models.MeetingParticipant{}).
					Where("meeting_id = ? AND status = ?", meeting.ID, models.MeetingParticipantStatusJoined).
					Count(&joinedCount).Error; err != nil {
					return err
				}
				if isMeetingCapacityReached(lockedMeeting.MaxParticipants, joinedCount) {
					return errMeetingCapacityReached
				}
				if err := tx.Model(&models.MeetingParticipant{}).
					Where("id = ?", participant.ID).
					Updates(map[string]interface{}{
						"status":    models.MeetingParticipantStatusJoined,
						"joined_at": now,
						"left_at":   nil,
					}).Error; err != nil {
					return err
				}
			}
		}

		return tx.Model(&models.MeetingInvite{}).
			Where("id = ?", joinReq.ID).
			Updates(map[string]interface{}{
				"status":       nextStatus,
				"responded_at": now,
			}).Error
	}); err != nil {
		if err == gorm.ErrRecordNotFound {
			response.NotFound(c, "未找到待审批的入会申请")
			return
		}
		if err == errMeetingNotActive {
			response.BadRequest(c, "会议已结束")
			return
		}
		if err == errMeetingCapacityReached {
			response.BadRequest(c, "会议人数已满")
			return
		}
		if err == errMeetingParticipantKicked {
			response.Forbidden(c, "该用户已被移出会议")
			return
		}
		response.ServerError(c, "审批失败")
		return
	}

	reason := strings.TrimSpace(req.Reason)
	h.wsHub.SendToUserCluster(target.UUID, map[string]interface{}{
		"type": "meeting_join_request_reviewed",
		"data": gin.H{
			"meeting_id":     meeting.UUID,
			"target_user_id": target.UUID,
			"reviewer_id":    reviewer.UUID,
			"reviewer_name":  reviewer.Nickname,
			"approved":       approved,
			"reason":         reason,
			"reviewed_at":    now,
		},
	})

	if h.pushService != nil {
		statusText := "已拒绝你的会议加入申请"
		if approved {
			statusText = "已同意你的会议加入申请"
		}
		go h.pushService.PushToUser(target.ID, reviewer.Nickname, statusText, map[string]interface{}{
			"type":          "meeting_join_request_reviewed",
			"meeting_id":    meeting.UUID,
			"approved":      approved,
			"reviewer_name": reviewer.Nickname,
		})
	}

	if approved {
		for _, uid := range h.getParticipantUUIDs(meeting.ID, target.ID) {
			h.wsHub.SendToUserCluster(uid, map[string]interface{}{
				"type": "meeting_member_joined",
				"data": gin.H{
					"meeting_id":   meeting.UUID,
					"user_id":      target.UUID,
					"user_name":    target.Nickname,
					"user_avatar":  target.Avatar,
					"joined_at":    now,
					"meeting_type": meeting.MeetingType,
				},
			})
		}
	}

	response.Success(c, gin.H{
		"meeting_id":      meeting.UUID,
		"target_user_id":  target.UUID,
		"approved":        approved,
		"reviewed_at":     now,
		"approval_reason": reason,
	})
}

func (h *MeetingHandler) GetActiveMeeting(c *gin.Context) {
	userUUID := c.GetString("user_id")
	chatUUID := strings.TrimSpace(c.Query("chat_id"))
	if chatUUID == "" {
		response.BadRequest(c, "缺少 chat_id")
		return
	}

	user, err := h.getUserByUUID(userUUID)
	if err != nil {
		response.NotFound(c, "用户不存在")
		return
	}
	chat, err := h.getChatByUUID(chatUUID)
	if err != nil {
		response.NotFound(c, "群聊不存在")
		return
	}
	if !h.isChatMember(chat.ID, user.ID) {
		response.Forbidden(c, "无权查看该群聊会议")
		return
	}

	var meeting models.Meeting
	if err := h.db.Where("chat_id = ? AND status = ?", chat.ID, models.MeetingStatusActive).
		Order("start_time DESC").
		First(&meeting).Error; err != nil {
		if err == gorm.ErrRecordNotFound {
			response.Success(c, gin.H{"has_active": false})
			return
		}
		response.ServerError(c, "查询群会议状态失败")
		return
	}

	host, _ := h.getUserByID(meeting.CreatorID)
	hostUUID := ""
	hostName := ""
	hostAvatar := ""
	if host != nil {
		hostUUID = host.UUID
		hostName = host.Nickname
		hostAvatar = host.Avatar
	}

	response.Success(c, gin.H{
		"has_active":     true,
		"meeting_id":     meeting.UUID,
		"chat_id":        chat.UUID,
		"title":          meeting.Title,
		"meeting_type":   meeting.MeetingType,
		"channel_name":   meeting.ChannelName,
		"start_time":     meeting.StartTime,
		"host_user_id":   hostUUID,
		"host_name":      hostName,
		"host_avatar":    hostAvatar,
		"max_members":    meeting.MaxParticipants,
		"current_status": meeting.Status,
	})
}

type LeaveMeetingRequest struct {
	MeetingID string `json:"meeting_id" binding:"required"`
	Reason    string `json:"reason"`
}

func (h *MeetingHandler) LeaveMeeting(c *gin.Context) {
	userUUID := c.GetString("user_id")

	var req LeaveMeetingRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		response.BadRequest(c, "参数错误")
		return
	}

	user, err := h.getUserByUUID(userUUID)
	if err != nil {
		response.NotFound(c, "用户不存在")
		return
	}

	meeting, err := h.getMeetingByUUID(req.MeetingID)
	if err != nil {
		response.NotFound(c, "会议不存在")
		return
	}

	var me models.MeetingParticipant
	if err := h.db.Where("meeting_id = ? AND user_id = ?", meeting.ID, user.ID).First(&me).Error; err != nil {
		response.SuccessWithMessage(c, "已离开", gin.H{"meeting_id": meeting.UUID})
		return
	}

	now := time.Now()
	ended := false
	if err := h.db.Transaction(func(tx *gorm.DB) error {
		if err := tx.Model(&models.MeetingParticipant{}).
			Where("id = ?", me.ID).
			Updates(map[string]interface{}{
				"status":  models.MeetingParticipantStatusLeft,
				"left_at": now,
			}).Error; err != nil {
			return err
		}

		var joinedCount int64
		if err := tx.Model(&models.MeetingParticipant{}).
			Where("meeting_id = ? AND status = ?", meeting.ID, models.MeetingParticipantStatusJoined).
			Count(&joinedCount).Error; err != nil {
			return err
		}

		shouldEnd := me.Role == models.MeetingParticipantRoleHost || joinedCount == 0
		if !shouldEnd {
			return nil
		}

		reason := strings.TrimSpace(req.Reason)
		if reason == "" {
			if me.Role == models.MeetingParticipantRoleHost {
				reason = "host_left"
			} else {
				reason = "empty_room"
			}
		}
		if err := h.endMeetingTx(tx, meeting, reason, now); err != nil {
			return err
		}
		ended = true
		return nil
	}); err != nil {
		response.ServerError(c, "离开会议失败")
		return
	}

	if ended {
		h.notifyMeetingEnded(meeting, strings.TrimSpace(req.Reason))
	} else {
		for _, uid := range h.getParticipantUUIDs(meeting.ID, user.ID) {
			h.wsHub.SendToUserCluster(uid, map[string]interface{}{
				"type": "meeting_member_left",
				"data": gin.H{
					"meeting_id": meeting.UUID,
					"user_id":    user.UUID,
					"user_name":  user.Nickname,
					"left_at":    now,
				},
			})
		}
	}

	response.Success(c, gin.H{
		"meeting_id": meeting.UUID,
		"ended":      ended,
	})
}

type InviteMeetingRequest struct {
	MeetingID      string   `json:"meeting_id" binding:"required"`
	InviteeUserIDs []string `json:"invitee_user_ids" binding:"required"`
}

func (h *MeetingHandler) InviteMembers(c *gin.Context) {
	userUUID := c.GetString("user_id")

	var req InviteMeetingRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		response.BadRequest(c, "参数错误")
		return
	}
	if len(req.InviteeUserIDs) == 0 {
		response.BadRequest(c, "invitee_user_ids 不能为空")
		return
	}

	inviter, err := h.getUserByUUID(userUUID)
	if err != nil {
		response.NotFound(c, "用户不存在")
		return
	}

	meeting, err := h.getMeetingByUUID(req.MeetingID)
	if err != nil {
		response.NotFound(c, "会议不存在")
		return
	}
	if meeting.Status != models.MeetingStatusActive {
		response.BadRequest(c, "会议已结束")
		return
	}

	var inviterParticipant models.MeetingParticipant
	if err := h.db.Where("meeting_id = ? AND user_id = ?", meeting.ID, inviter.ID).First(&inviterParticipant).Error; err != nil {
		response.Forbidden(c, "你不在会议中")
		return
	}
	if inviterParticipant.Role != models.MeetingParticipantRoleHost {
		response.Forbidden(c, "仅主持人可邀请")
		return
	}

	var chat *models.Chat
	if meeting.ChatID > 0 {
		chat = &models.Chat{}
		if err := h.db.First(chat, meeting.ChatID).Error; err != nil {
			response.NotFound(c, "会议关联群聊不存在")
			return
		}
	}
	invitees := h.resolveInvitees(req.InviteeUserIDs, inviter.ID, chat)
	if len(invitees) == 0 {
		response.Success(c, gin.H{
			"meeting_id":    meeting.UUID,
			"invited_count": 0,
		})
		return
	}

	now := time.Now()
	created := make([]models.User, 0, len(invitees))
	if err := h.db.Transaction(func(tx *gorm.DB) error {
		for _, invitee := range invitees {
			var participant models.MeetingParticipant
			err := tx.Where("meeting_id = ? AND user_id = ?", meeting.ID, invitee.ID).First(&participant).Error
			if err != nil {
				if err != gorm.ErrRecordNotFound {
					return err
				}
				if err := tx.Create(&models.MeetingParticipant{
					MeetingID: meeting.ID,
					UserID:    invitee.ID,
					Role:      models.MeetingParticipantRoleMember,
					Status:    models.MeetingParticipantStatusInvited,
					InviterID: inviter.ID,
				}).Error; err != nil {
					return err
				}
			} else {
				if participant.Status == models.MeetingParticipantStatusJoined {
					continue
				}
				if err := tx.Model(&models.MeetingParticipant{}).
					Where("id = ?", participant.ID).
					Updates(map[string]interface{}{
						"status":      models.MeetingParticipantStatusInvited,
						"inviter_id":  inviter.ID,
						"left_at":     nil,
						"joined_at":   nil,
						"muted_audio": false,
						"muted_video": false,
					}).Error; err != nil {
					return err
				}
			}

			if err := tx.Create(&models.MeetingInvite{
				MeetingID:  meeting.ID,
				InviterID:  inviter.ID,
				InviteeID:  invitee.ID,
				InviteType: models.MeetingInviteTypeInvite,
				Status:     models.MeetingInviteStatusPending,
			}).Error; err != nil {
				return err
			}
			created = append(created, invitee)
		}
		return nil
	}); err != nil {
		response.ServerError(c, "邀请失败")
		return
	}

	chatUUID := ""
	if meeting.ChatID > 0 {
		var chat models.Chat
		if err := h.db.First(&chat, meeting.ChatID).Error; err == nil {
			chatUUID = chat.UUID
		}
	}

	for _, invitee := range created {
		h.wsHub.SendToUserCluster(invitee.UUID, map[string]interface{}{
			"type": "meeting_invite",
			"data": gin.H{
				"meeting_id":     meeting.UUID,
				"channel_name":   meeting.ChannelName,
				"meeting_type":   meeting.MeetingType,
				"title":          meeting.Title,
				"chat_id":        chatUUID,
				"inviter_id":     inviter.UUID,
				"inviter_name":   inviter.Nickname,
				"inviter_avatar": inviter.Avatar,
				"start_time":     meeting.StartTime,
			},
		})
		if h.pushService != nil {
			go h.pushService.PushToUser(invitee.ID, inviter.Nickname, "邀请你加入群会议", map[string]interface{}{
				"type":       "meeting_invite",
				"meeting_id": meeting.UUID,
			})
		}
	}

	if meeting.ChatID > 0 && h.msgService != nil && len(created) > 0 {
		var chat models.Chat
		if err := h.db.First(&chat, meeting.ChatID).Error; err == nil {
			targets := make([]string, 0, len(created))
			for _, invitee := range created {
				targets = append(targets, invitee.UUID)
			}
			h.sendMeetingSystemMessage(
				c.Request.Context(),
				&chat,
				map[string]interface{}{
					"type":           "meeting_invite",
					"meeting_id":     meeting.UUID,
					"channel_name":   meeting.ChannelName,
					"meeting_type":   meeting.MeetingType,
					"title":          meeting.Title,
					"chat_id":        chat.UUID,
					"inviter_id":     inviter.UUID,
					"inviter_name":   inviter.Nickname,
					"inviter_avatar": inviter.Avatar,
					"start_time":     meeting.StartTime,
				},
				func() string {
					meetingLabel := "视频群会议"
					if meeting.MeetingType == models.MeetingTypeVoice {
						meetingLabel = "语音群会议"
					}
					if strings.TrimSpace(meeting.Title) != "" {
						return inviter.Nickname + "邀请你加入" + meetingLabel + "：" + meeting.Title
					}
					return inviter.Nickname + "邀请你加入" + meetingLabel
				}(),
				targets,
			)
		}
	}

	response.Success(c, gin.H{
		"meeting_id":    meeting.UUID,
		"invited_count": len(created),
		"invite_at":     now,
	})
}

type EndMeetingRequest struct {
	MeetingID string `json:"meeting_id" binding:"required"`
	Reason    string `json:"reason"`
}

func (h *MeetingHandler) EndMeeting(c *gin.Context) {
	userUUID := c.GetString("user_id")

	var req EndMeetingRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		response.BadRequest(c, "参数错误")
		return
	}

	user, err := h.getUserByUUID(userUUID)
	if err != nil {
		response.NotFound(c, "用户不存在")
		return
	}
	meeting, err := h.getMeetingByUUID(req.MeetingID)
	if err != nil {
		response.NotFound(c, "会议不存在")
		return
	}

	var participant models.MeetingParticipant
	if err := h.db.Where("meeting_id = ? AND user_id = ?", meeting.ID, user.ID).First(&participant).Error; err != nil {
		response.Forbidden(c, "你不在会议中")
		return
	}
	if participant.Role != models.MeetingParticipantRoleHost && meeting.CreatorID != user.ID {
		response.Forbidden(c, "仅主持人可结束会议")
		return
	}

	if meeting.Status == models.MeetingStatusEnded {
		response.Success(c, gin.H{"meeting_id": meeting.UUID, "status": meeting.Status})
		return
	}

	now := time.Now()
	reason := strings.TrimSpace(req.Reason)
	if reason == "" {
		reason = "host_end"
	}
	if err := h.db.Transaction(func(tx *gorm.DB) error {
		return h.endMeetingTx(tx, meeting, reason, now)
	}); err != nil {
		response.ServerError(c, "结束会议失败")
		return
	}

	h.notifyMeetingEnded(meeting, reason)

	response.Success(c, gin.H{
		"meeting_id": meeting.UUID,
		"status":     models.MeetingStatusEnded,
		"end_reason": reason,
	})
}

func (h *MeetingHandler) GetToken(c *gin.Context) {
	userUUID := c.GetString("user_id")
	meetingID := strings.TrimSpace(c.Query("meeting_id"))
	if meetingID == "" {
		response.BadRequest(c, "缺少 meeting_id")
		return
	}

	enabled, appID, appCertificate, tokenExpire := h.getAgoraConfigFromDB()
	if !enabled {
		response.BadRequest(c, "音视频服务未启用")
		return
	}

	user, err := h.getUserByUUID(userUUID)
	if err != nil {
		response.NotFound(c, "用户不存在")
		return
	}
	meeting, err := h.getMeetingByUUID(meetingID)
	if err != nil {
		response.NotFound(c, "会议不存在")
		return
	}
	if meeting.Status != models.MeetingStatusActive {
		response.BadRequest(c, "会议已结束")
		return
	}

	var participant models.MeetingParticipant
	if err := h.db.Where("meeting_id = ? AND user_id = ?", meeting.ID, user.ID).First(&participant).Error; err != nil {
		response.Forbidden(c, "无权限获取会议 token")
		return
	}
	if participant.Status != models.MeetingParticipantStatusJoined {
		response.Forbidden(c, "请先加入会议")
		return
	}

	agoraSvc := services.NewAgoraService(enabled, appID, appCertificate, tokenExpire)
	token, err := agoraSvc.GenerateRTCToken(meeting.ChannelName, toAgoraUID(user.ID), services.RolePublisher)
	if err != nil {
		response.ServerError(c, "生成Token失败")
		return
	}

	response.Success(c, gin.H{
		"meeting_id":   meeting.UUID,
		"channel_name": meeting.ChannelName,
		"meeting_type": meeting.MeetingType,
		"token":        token,
		"app_id":       appID,
		"agora_uid":    toAgoraUID(user.ID),
	})
}

func (h *MeetingHandler) GetMeetingDetail(c *gin.Context) {
	userUUID := c.GetString("user_id")
	meetingID := strings.TrimSpace(c.Query("meeting_id"))
	if meetingID == "" {
		response.BadRequest(c, "缺少 meeting_id")
		return
	}

	user, err := h.getUserByUUID(userUUID)
	if err != nil {
		response.NotFound(c, "用户不存在")
		return
	}
	meeting, err := h.getMeetingByUUID(meetingID)
	if err != nil {
		response.NotFound(c, "会议不存在")
		return
	}

	if !h.canAccessMeeting(meeting, user.ID) {
		response.Forbidden(c, "无权限查看会议")
		return
	}

	type row struct {
		models.MeetingParticipant
		UserUUID string `gorm:"column:user_uuid"`
		Nickname string `gorm:"column:nickname"`
		Avatar   string `gorm:"column:avatar"`
	}
	var rows []row
	h.db.Table("meeting_participants mp").
		Select("mp.*, u.uuid AS user_uuid, u.nickname, u.avatar").
		Joins("JOIN users u ON u.id = mp.user_id").
		Where("mp.meeting_id = ?", meeting.ID).
		Order("mp.role DESC, mp.updated_at DESC").
		Find(&rows)

	participants := make([]gin.H, 0, len(rows))
	for _, item := range rows {
		participants = append(participants, gin.H{
			"user_id":     item.UserUUID,
			"agora_uid":   toAgoraUID(item.UserID),
			"user_name":   item.Nickname,
			"user_avatar": item.Avatar,
			"role":        item.Role,
			"status":      item.Status,
			"joined_at":   item.JoinedAt,
			"left_at":     item.LeftAt,
			"muted_audio": item.MutedAudio,
			"muted_video": item.MutedVideo,
		})
	}

	chatUUID := ""
	if meeting.ChatID > 0 {
		var chat models.Chat
		if err := h.db.First(&chat, meeting.ChatID).Error; err == nil {
			chatUUID = chat.UUID
		}
	}

	response.Success(c, gin.H{
		"meeting_id":       meeting.UUID,
		"chat_id":          chatUUID,
		"title":            meeting.Title,
		"meeting_type":     meeting.MeetingType,
		"status":           meeting.Status,
		"channel_name":     meeting.ChannelName,
		"max_participants": meeting.MaxParticipants,
		"start_time":       meeting.StartTime,
		"end_time":         meeting.EndTime,
		"duration":         meeting.Duration,
		"end_reason":       meeting.EndReason,
		"participants":     participants,
	})
}

type UpdateMeetingTitleRequest struct {
	MeetingID string `json:"meeting_id" binding:"required"`
	Title     string `json:"title" binding:"required"`
}

func (h *MeetingHandler) UpdateMeetingTitle(c *gin.Context) {
	userUUID := c.GetString("user_id")

	var req UpdateMeetingTitleRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		response.BadRequest(c, "参数错误")
		return
	}

	title := strings.TrimSpace(req.Title)
	if title == "" {
		response.BadRequest(c, "会议名称不能为空")
		return
	}
	if len(title) > 100 {
		response.BadRequest(c, "会议名称不能超过100个字符")
		return
	}

	operator, err := h.getUserByUUID(userUUID)
	if err != nil {
		response.NotFound(c, "用户不存在")
		return
	}
	meeting, err := h.getMeetingByUUID(req.MeetingID)
	if err != nil {
		response.NotFound(c, "会议不存在")
		return
	}
	if meeting.Status != models.MeetingStatusActive {
		response.BadRequest(c, "会议已结束")
		return
	}

	participant, err := h.getMeetingParticipant(meeting.ID, operator.ID)
	if err != nil {
		response.Forbidden(c, "你不在会议中")
		return
	}
	if participant.Role != models.MeetingParticipantRoleHost {
		response.Forbidden(c, "仅主持人可修改会议名称")
		return
	}

	oldTitle := strings.TrimSpace(meeting.Title)
	if oldTitle == title {
		response.Success(c, gin.H{
			"meeting_id": meeting.UUID,
			"title":      meeting.Title,
		})
		return
	}

	if err := h.db.Model(&models.Meeting{}).
		Where("id = ?", meeting.ID).
		Update("title", title).Error; err != nil {
		response.ServerError(c, "修改会议名称失败")
		return
	}
	meeting.Title = title

	now := time.Now()
	eventData := gin.H{
		"meeting_id":    meeting.UUID,
		"title":         meeting.Title,
		"old_title":     oldTitle,
		"operator_id":   operator.UUID,
		"operator_name": operator.Nickname,
		"updated_at":    now,
	}
	for _, uid := range h.getParticipantUUIDs(meeting.ID, 0) {
		h.wsHub.SendToUserCluster(uid, map[string]interface{}{
			"type": "meeting_title_updated",
			"data": eventData,
		})
	}

	if meeting.ChatID > 0 {
		var chat models.Chat
		if err := h.db.First(&chat, meeting.ChatID).Error; err == nil {
			label := "视频群会议"
			if meeting.MeetingType == models.MeetingTypeVoice {
				label = "语音群会议"
			}
			preview := operator.Nickname + "修改了" + label + "名称"
			if strings.TrimSpace(meeting.Title) != "" {
				preview = preview + "：" + meeting.Title
			}
			h.sendMeetingSystemMessage(
				c.Request.Context(),
				&chat,
				map[string]interface{}{
					"type":          "meeting_title_updated",
					"meeting_id":    meeting.UUID,
					"chat_id":       chat.UUID,
					"title":         meeting.Title,
					"old_title":     oldTitle,
					"operator_id":   operator.UUID,
					"operator_name": operator.Nickname,
					"updated_at":    now,
				},
				preview,
				h.getChatMemberUUIDs(chat.ID, 0),
			)
		}
	}

	response.Success(c, gin.H{
		"meeting_id": meeting.UUID,
		"title":      meeting.Title,
	})
}

type MuteMeetingMemberRequest struct {
	MeetingID    string `json:"meeting_id" binding:"required"`
	TargetUserID string `json:"target_user_id" binding:"required"`
	MutedAudio   *bool  `json:"muted_audio"`
	MutedVideo   *bool  `json:"muted_video"`
}

func (h *MeetingHandler) MuteMember(c *gin.Context) {
	userUUID := c.GetString("user_id")

	var req MuteMeetingMemberRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		response.BadRequest(c, "参数错误")
		return
	}
	if req.MutedAudio == nil && req.MutedVideo == nil {
		response.BadRequest(c, "请至少传入 muted_audio 或 muted_video")
		return
	}

	operator, err := h.getUserByUUID(userUUID)
	if err != nil {
		response.NotFound(c, "用户不存在")
		return
	}
	meeting, err := h.getMeetingByUUID(req.MeetingID)
	if err != nil {
		response.NotFound(c, "会议不存在")
		return
	}
	if meeting.Status != models.MeetingStatusActive {
		response.BadRequest(c, "会议已结束")
		return
	}

	operatorParticipant, err := h.getMeetingParticipant(meeting.ID, operator.ID)
	if err != nil {
		response.Forbidden(c, "你不在会议中")
		return
	}
	if operatorParticipant.Role != models.MeetingParticipantRoleHost {
		response.Forbidden(c, "仅主持人可操作")
		return
	}

	targetUser, err := h.getUserByUUID(req.TargetUserID)
	if err != nil {
		response.NotFound(c, "目标成员不存在")
		return
	}
	targetParticipant, err := h.getMeetingParticipant(meeting.ID, targetUser.ID)
	if err != nil {
		response.NotFound(c, "目标成员不在会议中")
		return
	}
	if targetParticipant.Role == models.MeetingParticipantRoleHost && targetUser.ID != operator.ID {
		response.Forbidden(c, "不能操作主持人")
		return
	}
	if targetParticipant.Status == models.MeetingParticipantStatusKicked {
		response.BadRequest(c, "目标成员已被移出")
		return
	}

	updates := map[string]interface{}{}
	if req.MutedAudio != nil {
		updates["muted_audio"] = *req.MutedAudio
	}
	if req.MutedVideo != nil {
		updates["muted_video"] = *req.MutedVideo
	}
	if len(updates) == 0 {
		response.BadRequest(c, "没有可更新字段")
		return
	}

	if err := h.db.Model(&models.MeetingParticipant{}).
		Where("id = ?", targetParticipant.ID).
		Updates(updates).Error; err != nil {
		response.ServerError(c, "更新成员状态失败")
		return
	}

	if req.MutedAudio != nil {
		targetParticipant.MutedAudio = *req.MutedAudio
	}
	if req.MutedVideo != nil {
		targetParticipant.MutedVideo = *req.MutedVideo
	}

	now := time.Now()
	eventData := gin.H{
		"meeting_id":     meeting.UUID,
		"target_user_id": targetUser.UUID,
		"operator_id":    operator.UUID,
		"muted_audio":    targetParticipant.MutedAudio,
		"muted_video":    targetParticipant.MutedVideo,
		"updated_at":     now,
	}
	for _, uid := range h.getParticipantUUIDs(meeting.ID, 0) {
		h.wsHub.SendToUserCluster(uid, map[string]interface{}{
			"type": "meeting_member_muted",
			"data": eventData,
		})
	}

	response.Success(c, gin.H{
		"meeting_id":     meeting.UUID,
		"target_user_id": targetUser.UUID,
		"muted_audio":    targetParticipant.MutedAudio,
		"muted_video":    targetParticipant.MutedVideo,
	})
}

type KickMeetingMemberRequest struct {
	MeetingID    string `json:"meeting_id" binding:"required"`
	TargetUserID string `json:"target_user_id" binding:"required"`
}

func (h *MeetingHandler) KickMember(c *gin.Context) {
	userUUID := c.GetString("user_id")

	var req KickMeetingMemberRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		response.BadRequest(c, "参数错误")
		return
	}

	operator, err := h.getUserByUUID(userUUID)
	if err != nil {
		response.NotFound(c, "用户不存在")
		return
	}
	meeting, err := h.getMeetingByUUID(req.MeetingID)
	if err != nil {
		response.NotFound(c, "会议不存在")
		return
	}
	if meeting.Status != models.MeetingStatusActive {
		response.BadRequest(c, "会议已结束")
		return
	}

	operatorParticipant, err := h.getMeetingParticipant(meeting.ID, operator.ID)
	if err != nil {
		response.Forbidden(c, "你不在会议中")
		return
	}
	if operatorParticipant.Role != models.MeetingParticipantRoleHost {
		response.Forbidden(c, "仅主持人可操作")
		return
	}

	targetUser, err := h.getUserByUUID(req.TargetUserID)
	if err != nil {
		response.NotFound(c, "目标成员不存在")
		return
	}
	if targetUser.ID == operator.ID {
		response.BadRequest(c, "请使用离开会议操作自己")
		return
	}
	targetParticipant, err := h.getMeetingParticipant(meeting.ID, targetUser.ID)
	if err != nil {
		response.NotFound(c, "目标成员不在会议中")
		return
	}
	if targetParticipant.Role == models.MeetingParticipantRoleHost {
		response.Forbidden(c, "不能移出主持人")
		return
	}

	now := time.Now()
	if targetParticipant.Status != models.MeetingParticipantStatusKicked {
		if err := h.db.Transaction(func(tx *gorm.DB) error {
			if err := tx.Model(&models.MeetingParticipant{}).
				Where("id = ?", targetParticipant.ID).
				Updates(map[string]interface{}{
					"status":  models.MeetingParticipantStatusKicked,
					"left_at": now,
				}).Error; err != nil {
				return err
			}

			if err := tx.Model(&models.MeetingInvite{}).
				Where("meeting_id = ? AND invitee_id = ? AND status = ?",
					meeting.ID, targetUser.ID, models.MeetingInviteStatusPending).
				Updates(map[string]interface{}{
					"status":       models.MeetingInviteStatusCanceled,
					"responded_at": now,
				}).Error; err != nil {
				return err
			}
			return nil
		}); err != nil {
			response.ServerError(c, "移出成员失败")
			return
		}
	}

	memberLeftData := gin.H{
		"meeting_id":  meeting.UUID,
		"user_id":     targetUser.UUID,
		"user_name":   targetUser.Nickname,
		"left_at":     now,
		"action":      "kicked",
		"operator_id": operator.UUID,
	}
	for _, uid := range h.getParticipantUUIDs(meeting.ID, 0) {
		h.wsHub.SendToUserCluster(uid, map[string]interface{}{
			"type": "meeting_member_left",
			"data": memberLeftData,
		})
	}
	h.wsHub.SendToUserCluster(targetUser.UUID, map[string]interface{}{
		"type": "meeting_member_kicked",
		"data": gin.H{
			"meeting_id":  meeting.UUID,
			"operator_id": operator.UUID,
			"kicked_at":   now,
		},
	})

	response.Success(c, gin.H{
		"meeting_id":     meeting.UUID,
		"target_user_id": targetUser.UUID,
		"status":         models.MeetingParticipantStatusKicked,
	})
}

type TransferMeetingHostRequest struct {
	MeetingID    string `json:"meeting_id" binding:"required"`
	TargetUserID string `json:"target_user_id" binding:"required"`
}

func (h *MeetingHandler) TransferHost(c *gin.Context) {
	userUUID := c.GetString("user_id")

	var req TransferMeetingHostRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		response.BadRequest(c, "参数错误")
		return
	}

	currentHost, err := h.getUserByUUID(userUUID)
	if err != nil {
		response.NotFound(c, "用户不存在")
		return
	}
	meeting, err := h.getMeetingByUUID(req.MeetingID)
	if err != nil {
		response.NotFound(c, "会议不存在")
		return
	}
	if meeting.Status != models.MeetingStatusActive {
		response.BadRequest(c, "会议已结束")
		return
	}

	hostParticipant, err := h.getMeetingParticipant(meeting.ID, currentHost.ID)
	if err != nil || hostParticipant.Role != models.MeetingParticipantRoleHost {
		response.Forbidden(c, "仅主持人可操作")
		return
	}

	targetUser, err := h.getUserByUUID(req.TargetUserID)
	if err != nil {
		response.NotFound(c, "目标成员不存在")
		return
	}
	targetParticipant, err := h.getMeetingParticipant(meeting.ID, targetUser.ID)
	if err != nil {
		response.NotFound(c, "目标成员不在会议中")
		return
	}
	if targetUser.ID == currentHost.ID {
		response.BadRequest(c, "已是主持人")
		return
	}
	if targetParticipant.Status != models.MeetingParticipantStatusJoined {
		response.BadRequest(c, "仅可转移给已加入会议的成员")
		return
	}

	if err := h.db.Transaction(func(tx *gorm.DB) error {
		if err := tx.Model(&models.MeetingParticipant{}).
			Where("meeting_id = ? AND user_id = ?", meeting.ID, currentHost.ID).
			Update("role", models.MeetingParticipantRoleMember).Error; err != nil {
			return err
		}
		if err := tx.Model(&models.MeetingParticipant{}).
			Where("meeting_id = ? AND user_id = ?", meeting.ID, targetUser.ID).
			Updates(map[string]interface{}{
				"role":        models.MeetingParticipantRoleHost,
				"muted_audio": false,
				"muted_video": false,
			}).Error; err != nil {
			return err
		}
		if err := tx.Model(&models.Meeting{}).
			Where("id = ?", meeting.ID).
			Update("creator_id", targetUser.ID).Error; err != nil {
			return err
		}
		return nil
	}); err != nil {
		response.ServerError(c, "转移主持人失败")
		return
	}

	now := time.Now()
	eventData := gin.H{
		"meeting_id":       meeting.UUID,
		"from_user_id":     currentHost.UUID,
		"from_user_name":   currentHost.Nickname,
		"target_user_id":   targetUser.UUID,
		"target_user_name": targetUser.Nickname,
		"updated_at":       now,
	}
	for _, uid := range h.getParticipantUUIDs(meeting.ID, 0) {
		h.wsHub.SendToUserCluster(uid, map[string]interface{}{
			"type": "meeting_host_changed",
			"data": eventData,
		})
	}

	response.Success(c, gin.H{
		"meeting_id":       meeting.UUID,
		"host_user_id":     targetUser.UUID,
		"host_user_name":   targetUser.Nickname,
		"previous_host_id": currentHost.UUID,
	})
}

func (h *MeetingHandler) getUserByUUID(userUUID string) (*models.User, error) {
	var user models.User
	if err := h.db.Where("uuid = ?", userUUID).First(&user).Error; err != nil {
		return nil, err
	}
	return &user, nil
}

func (h *MeetingHandler) getUserByID(userID uint64) (*models.User, error) {
	var user models.User
	if err := h.db.Where("id = ?", userID).First(&user).Error; err != nil {
		return nil, err
	}
	return &user, nil
}

func (h *MeetingHandler) getMeetingParticipant(meetingID, userID uint64) (*models.MeetingParticipant, error) {
	var participant models.MeetingParticipant
	if err := h.db.Where("meeting_id = ? AND user_id = ?", meetingID, userID).First(&participant).Error; err != nil {
		return nil, err
	}
	return &participant, nil
}

func (h *MeetingHandler) getChatByUUID(chatUUID string) (*models.Chat, error) {
	var chat models.Chat
	if err := h.db.Where("uuid = ?", chatUUID).First(&chat).Error; err != nil {
		return nil, err
	}
	return &chat, nil
}

func (h *MeetingHandler) isChatMember(chatID, userID uint64) bool {
	var count int64
	h.db.Model(&models.ChatMember{}).Where("chat_id = ? AND user_id = ?", chatID, userID).Count(&count)
	return count > 0
}

func (h *MeetingHandler) hasHostInviteTx(tx *gorm.DB, meetingID, userID uint64) (bool, error) {
	var count int64
	if err := tx.Model(&models.MeetingInvite{}).
		Where(
			"meeting_id = ? AND invitee_id = ? AND status = ? AND (invite_type = ? OR invite_type = '' OR invite_type IS NULL)",
			meetingID,
			userID,
			models.MeetingInviteStatusPending,
			models.MeetingInviteTypeInvite,
		).
		Count(&count).Error; err != nil {
		return false, err
	}
	return count > 0, nil
}

func (h *MeetingHandler) upsertJoinRequestTx(tx *gorm.DB, meeting *models.Meeting, requesterID, hostID uint64, now time.Time) error {
	var pending models.MeetingInvite
	err := tx.Where(
		"meeting_id = ? AND inviter_id = ? AND invite_type = ? AND status = ?",
		meeting.ID,
		requesterID,
		models.MeetingInviteTypeJoinRequest,
		models.MeetingInviteStatusPending,
	).Order("id DESC").First(&pending).Error
	if err == nil {
		return tx.Model(&models.MeetingInvite{}).
			Where("id = ?", pending.ID).
			Update("updated_at", now).Error
	}
	if err != gorm.ErrRecordNotFound {
		return err
	}
	return tx.Create(&models.MeetingInvite{
		MeetingID:  meeting.ID,
		InviterID:  requesterID,
		InviteeID:  hostID,
		InviteType: models.MeetingInviteTypeJoinRequest,
		Status:     models.MeetingInviteStatusPending,
	}).Error
}

func (h *MeetingHandler) notifyHostJoinRequest(meeting *models.Meeting, host, requester *models.User, requestedAt time.Time) {
	if host == nil || requester == nil {
		return
	}
	if host.ID == requester.ID {
		return
	}

	chatUUID := ""
	if meeting.ChatID > 0 {
		var chat models.Chat
		if err := h.db.First(&chat, meeting.ChatID).Error; err == nil {
			chatUUID = chat.UUID
		}
	}

	h.wsHub.SendToUserCluster(host.UUID, map[string]interface{}{
		"type": "meeting_join_request",
		"data": gin.H{
			"meeting_id":      meeting.UUID,
			"chat_id":         chatUUID,
			"meeting_type":    meeting.MeetingType,
			"request_user_id": requester.UUID,
			"request_name":    requester.Nickname,
			"request_avatar":  requester.Avatar,
			"requested_at":    requestedAt,
		},
	})

	if h.pushService != nil {
		go h.pushService.PushToUser(host.ID, requester.Nickname, "有人申请加入群会议", map[string]interface{}{
			"type":            "meeting_join_request",
			"meeting_id":      meeting.UUID,
			"request_user_id": requester.UUID,
		})
	}
}

func (h *MeetingHandler) resolveInvitees(inviteeUUIDs []string, selfUserID uint64, chat *models.Chat) []models.User {
	if len(inviteeUUIDs) == 0 {
		return nil
	}

	normalized := make([]string, 0, len(inviteeUUIDs))
	seen := make(map[string]struct{}, len(inviteeUUIDs))
	for _, item := range inviteeUUIDs {
		v := strings.TrimSpace(item)
		if v == "" {
			continue
		}
		if _, ok := seen[v]; ok {
			continue
		}
		seen[v] = struct{}{}
		normalized = append(normalized, v)
	}
	if len(normalized) == 0 {
		return nil
	}

	var users []models.User
	h.db.Where("uuid IN ?", normalized).Find(&users)
	if len(users) == 0 {
		return nil
	}

	allowedByChat := map[uint64]struct{}{}
	if chat != nil {
		var members []struct {
			UserID uint64 `gorm:"column:user_id"`
		}
		candidateIDs := make([]uint64, 0, len(users))
		for _, u := range users {
			candidateIDs = append(candidateIDs, u.ID)
		}
		h.db.Table("chat_members").
			Select("user_id").
			Where("chat_id = ? AND user_id IN ?", chat.ID, candidateIDs).
			Find(&members)
		for _, m := range members {
			allowedByChat[m.UserID] = struct{}{}
		}
	}

	result := make([]models.User, 0, len(users))
	for _, u := range users {
		if u.ID == selfUserID {
			continue
		}
		if chat != nil {
			if _, ok := allowedByChat[u.ID]; !ok {
				continue
			}
		}
		result = append(result, u)
	}
	return result
}

func (h *MeetingHandler) getMeetingByUUID(meetingUUID string) (*models.Meeting, error) {
	var meeting models.Meeting
	if err := h.db.Where("uuid = ?", meetingUUID).First(&meeting).Error; err != nil {
		return nil, err
	}
	return &meeting, nil
}

func (h *MeetingHandler) lockMeetingForUpdate(tx *gorm.DB, meetingID uint64) (*models.Meeting, error) {
	var meeting models.Meeting
	if err := tx.Clauses(clause.Locking{Strength: "UPDATE"}).
		Where("id = ?", meetingID).
		First(&meeting).Error; err != nil {
		return nil, err
	}
	return &meeting, nil
}

func (h *MeetingHandler) getParticipantUUIDs(meetingID uint64, excludeUserID uint64) []string {
	type row struct {
		UserUUID string `gorm:"column:user_uuid"`
	}
	var rows []row
	query := h.db.Table("meeting_participants mp").
		Select("u.uuid AS user_uuid").
		Joins("JOIN users u ON u.id = mp.user_id").
		Where("mp.meeting_id = ? AND mp.status != ?", meetingID, models.MeetingParticipantStatusKicked)
	if excludeUserID > 0 {
		query = query.Where("mp.user_id != ?", excludeUserID)
	}
	query.Find(&rows)

	result := make([]string, 0, len(rows))
	for _, item := range rows {
		if item.UserUUID != "" {
			result = append(result, item.UserUUID)
		}
	}
	return result
}

func (h *MeetingHandler) getChatMemberUUIDs(chatID uint64, excludeUserID uint64) []string {
	type row struct {
		UserUUID string `gorm:"column:user_uuid"`
	}
	var rows []row
	query := h.db.Table("chat_members cm").
		Select("u.uuid AS user_uuid").
		Joins("JOIN users u ON u.id = cm.user_id").
		Where("cm.chat_id = ?", chatID)
	if excludeUserID > 0 {
		query = query.Where("cm.user_id != ?", excludeUserID)
	}
	query.Find(&rows)

	result := make([]string, 0, len(rows))
	for _, item := range rows {
		if item.UserUUID != "" {
			result = append(result, item.UserUUID)
		}
	}
	return result
}

func (h *MeetingHandler) sendMeetingSystemMessage(
	ctx context.Context,
	chat *models.Chat,
	payload map[string]interface{},
	previewText string,
	targetUserIDs []string,
) {
	if h.msgService == nil || chat == nil {
		return
	}

	body, err := json.Marshal(payload)
	if err != nil {
		return
	}

	params := &services.SendMessageParams{
		ChatID:   chat.UUID,
		SenderID: "system",
		Type:     models.MsgTypeSystem,
		Content: map[string]interface{}{
			"text": string(body),
		},
	}

	if len(targetUserIDs) == 0 {
		targetUserIDs = h.getChatMemberUUIDs(chat.ID, 0)
	}

	msg, err := h.msgService.SendMessage(ctx, params, "系统消息", "", "", "", "", targetUserIDs)
	if err != nil {
		return
	}

	if previewText == "" {
		return
	}

	userIDs := make([]uint64, 0, len(targetUserIDs))
	if len(targetUserIDs) > 0 {
		h.db.Model(&models.User{}).Where("uuid IN ?", targetUserIDs).Pluck("id", &userIDs)
	} else {
		h.db.Model(&models.ChatMember{}).Where("chat_id = ?", chat.ID).Pluck("user_id", &userIDs)
	}
	if len(userIDs) == 0 {
		return
	}

	truncated := textutil.TruncateRunes(previewText, 100)

	h.db.Model(&models.UserChat{}).
		Where("chat_id = ? AND user_id IN ?", chat.ID, userIDs).
		Updates(map[string]interface{}{
			"last_msg_text":   truncated,
			"last_msg_type":   models.MsgTypeSystem,
			"last_msg_time":   msg.CreatedAt,
			"last_msg_seq":    msg.Seq,
			"last_msg_sender": "",
			"sort_time":       msg.CreatedAt,
		})
}

func (h *MeetingHandler) endMeetingTx(tx *gorm.DB, meeting *models.Meeting, reason string, endAt time.Time) error {
	if meeting.Status == models.MeetingStatusEnded {
		return nil
	}

	duration := int(endAt.Sub(meeting.StartTime).Seconds())
	if duration < 0 {
		duration = 0
	}
	if err := tx.Model(&models.Meeting{}).
		Where("id = ?", meeting.ID).
		Updates(map[string]interface{}{
			"status":     models.MeetingStatusEnded,
			"end_time":   endAt,
			"duration":   duration,
			"end_reason": reason,
		}).Error; err != nil {
		return err
	}

	if err := tx.Model(&models.MeetingParticipant{}).
		Where("meeting_id = ? AND status = ?", meeting.ID, models.MeetingParticipantStatusJoined).
		Updates(map[string]interface{}{
			"status":  models.MeetingParticipantStatusLeft,
			"left_at": endAt,
		}).Error; err != nil {
		return err
	}

	meeting.Status = models.MeetingStatusEnded
	meeting.EndTime = &endAt
	meeting.Duration = duration
	meeting.EndReason = reason
	return nil
}

func (h *MeetingHandler) notifyMeetingEnded(meeting *models.Meeting, reason string) {
	if strings.TrimSpace(reason) == "" {
		reason = meeting.EndReason
	}
	chatUUID := ""
	if meeting.ChatID > 0 {
		var chat models.Chat
		if err := h.db.First(&chat, meeting.ChatID).Error; err == nil {
			chatUUID = chat.UUID
		}
	}
	targets := make(map[string]struct{})
	for _, uid := range h.getParticipantUUIDs(meeting.ID, 0) {
		targets[uid] = struct{}{}
	}
	if meeting.ChatID > 0 {
		for _, uid := range h.getChatMemberUUIDs(meeting.ChatID, 0) {
			targets[uid] = struct{}{}
		}
	}

	for uid := range targets {
		h.wsHub.SendToUserCluster(uid, map[string]interface{}{
			"type": "meeting_ended",
			"data": gin.H{
				"meeting_id":   meeting.UUID,
				"chat_id":      chatUUID,
				"meeting_type": meeting.MeetingType,
				"title":        meeting.Title,
				"end_reason":   reason,
				"end_time":     meeting.EndTime,
				"duration":     meeting.Duration,
			},
		})
	}

	if meeting.ChatID > 0 && h.msgService != nil {
		var chat models.Chat
		if err := h.db.First(&chat, meeting.ChatID).Error; err == nil {
			label := "视频群会议"
			if meeting.MeetingType == models.MeetingTypeVoice {
				label = "语音群会议"
			}
			preview := label + "已结束"
			if strings.TrimSpace(reason) != "" {
				preview = preview + "：" + reason
			}
			h.sendMeetingSystemMessage(
				context.Background(),
				&chat,
				map[string]interface{}{
					"type":         "meeting_ended",
					"meeting_id":   meeting.UUID,
					"chat_id":      chat.UUID,
					"meeting_type": meeting.MeetingType,
					"title":        meeting.Title,
					"end_reason":   reason,
					"end_time":     meeting.EndTime,
					"duration":     meeting.Duration,
				},
				preview,
				h.getChatMemberUUIDs(chat.ID, 0),
			)
		}
	}
}

func (h *MeetingHandler) canAccessMeeting(meeting *models.Meeting, userID uint64) bool {
	var participant models.MeetingParticipant
	if err := h.db.Where("meeting_id = ? AND user_id = ?", meeting.ID, userID).First(&participant).Error; err == nil {
		return participant.Status != models.MeetingParticipantStatusKicked
	}
	if meeting.ChatID > 0 {
		return h.isChatMember(meeting.ChatID, userID)
	}
	return false
}

func normalizeMeetingType(meetingType, callType string) (string, bool) {
	t := strings.TrimSpace(meetingType)
	if t == "" {
		t = strings.TrimSpace(callType)
	}
	switch t {
	case models.MeetingTypeVoice, models.MeetingTypeVideo:
		return t, true
	default:
		return "", false
	}
}

func generateMeetingChannelName(meetingUUID string) string {
	prefix := meetingUUID
	if len(prefix) > 8 {
		prefix = prefix[:8]
	}
	return fmt.Sprintf("meeting_%s_%d", prefix, time.Now().Unix())
}

func toAgoraUID(userID uint64) uint32 {
	if userID == 0 {
		return 0
	}
	maxPlusOne := uint64(^uint32(0)) + 1
	return uint32(userID % maxPlusOne)
}

func isMeetingCapacityReached(maxParticipants int, joinedCount int64) bool {
	return maxParticipants > 0 && joinedCount >= int64(maxParticipants)
}
