// 文件用途：实现后端 HTTP 接口的请求处理和统一响应。
// 核心逻辑：绑定参数，校验身份与权限，调用业务服务并持久化关键状态。

package handlers

import (
	"github.com/gin-gonic/gin"
	"net/http"
	"strings"
	"time"
	"genericim/internal/models"
	"genericim/pkg/response"
)

func firstNonEmptyText(values ...string) string {
	for _, v := range values {
		if strings.TrimSpace(v) != "" {
			return strings.TrimSpace(v)
		}
	}
	return ""
}

// GetUserDiagnostics returns a read-only health snapshot for one user.
func (h *UserMgmtHandler) GetUserDiagnostics(c *gin.Context) {
	userID := c.Param("id")

	var user models.User
	if err := h.db.First(&user, userID).Error; err != nil {
		response.Error(c, http.StatusNotFound, "用户不存在")
		return
	}
	now := time.Now()
	onlineThreshold := now.Add(-5 * time.Minute)
	isOnline := h.hub != nil && h.hub.IsUserOnline(user.UUID)

	var devices []models.UserDevice
	if err := h.db.Where("user_id = ?", user.ID).
		Order("last_active DESC").
		Find(&devices).Error; err != nil {
		response.Error(c, http.StatusInternalServerError, "查询设备失败")
		return
	}

	var pushLogs []models.PushDeliveryLog
	h.db.Where("user_id = ?", user.ID).
		Order("occurred_at DESC").
		Limit(20).
		Find(&pushLogs)
	latestPushByDevice := make(map[uint64]models.PushDeliveryLog, len(pushLogs))
	for _, item := range pushLogs {
		if _, exists := latestPushByDevice[item.DeviceID]; !exists {
			latestPushByDevice[item.DeviceID] = item
		}
	}
	deviceList := make([]gin.H, 0, len(devices))
	pushBoundCount := 0
	activeDeviceCount := 0
	for _, d := range devices {
		pushToken := strings.TrimSpace(d.PushToken)
		if pushToken != "" {
			pushBoundCount++
		}
		activeRecently := d.LastActive.After(onlineThreshold)
		if activeRecently {
			activeDeviceCount++
			isOnline = true
		}
		deviceList = append(deviceList, gin.H{
			"id":                d.ID,
			"device_id":         d.DeviceID,
			"device_type":       d.DeviceType,
			"device_name":       d.DeviceName,
			"device_ip":         d.IP,
			"push_channel":      d.PushChannel,
			"push_token_bound":  pushToken != "",
			"push_token_length": len(pushToken),
			"last_active":       formatAdminTime(d.LastActive),
			"active_recently":   activeRecently,
			"created_at":        formatAdminTime(d.CreatedAt),
		})
		if latestPush, ok := latestPushByDevice[d.ID]; ok {
			deviceList[len(deviceList)-1]["last_push"] = gin.H{
				"success":     latestPush.Success,
				"channel":     latestPush.Channel,
				"title":       latestPush.Title,
				"body":        latestPush.Body,
				"error":       latestPush.Error,
				"occurred_at": formatAdminTime(latestPush.OccurredAt),
			}
		}
	}

	var sessions []models.UserSession
	if err := h.db.Where("user_id = ?", user.ID).
		Order("last_active DESC").
		Limit(10).
		Find(&sessions).Error; err != nil {
		response.Error(c, http.StatusInternalServerError, "查询登录会话失败")
		return
	}
	sessionList := make([]gin.H, 0, len(sessions))
	for _, s := range sessions {
		sessionList = append(sessionList, gin.H{
			"id":          s.ID,
			"device_id":   s.DeviceID,
			"device_type": s.DeviceType,
			"device_name": s.DeviceName,
			"ip":          s.IP,
			"location":    s.Location,
			"last_active": formatAdminTime(s.LastActive),
			"created_at":  formatAdminTime(s.CreatedAt),
		})
	}

	var pushSetting models.UserPushSetting
	pushShowPreview := true
	pushSettingFound := false
	if err := h.db.Where("user_id = ?", user.ID).First(&pushSetting).Error; err == nil {
		pushShowPreview = pushSetting.ShowPreview
		pushSettingFound = true
	}

	var contactCount int64
	h.db.Model(&models.Contact{}).Where("user_id = ? AND status = 1", user.ID).Count(&contactCount)

	var chatCount int64
	h.db.Model(&models.UserChat{}).Where("user_id = ?", user.ID).Count(&chatCount)

	var unreadTotal int64
	h.db.Model(&models.UserChat{}).
		Where("user_id = ?", user.ID).
		Select("COALESCE(SUM(unread_count), 0)").
		Scan(&unreadTotal)

	var recentChats []models.UserChat
	h.db.Where("user_id = ?", user.ID).
		Order("sort_time DESC").
		Limit(5).
		Find(&recentChats)
	recentChatList := make([]gin.H, 0, len(recentChats))
	for _, uc := range recentChats {
		recentChatList = append(recentChatList, gin.H{
			"chat_id":         uc.ChatID,
			"target_id":       uc.TargetID,
			"last_msg_seq":    uc.LastMsgSeq,
			"last_msg_text":   uc.LastMsgText,
			"last_msg_type":   uc.LastMsgType,
			"last_msg_sender": uc.LastMsgSender,
			"last_msg_time":   formatAdminTimePtr(uc.LastMsgTime),
			"unread_count":    uc.UnreadCount,
			"is_muted":        uc.IsMuted,
			"is_pinned":       uc.IsPinned,
		})
	}
	checks := make([]gin.H, 0, 8)
	addCheck := func(level, title, detail string) {
		checks = append(checks, gin.H{"level": level, "title": title, "detail": detail})
	}

	switch user.Status {
	case models.UserStatusNormal:
		addCheck("ok", "账号状态正常", "用户账号可正常登录和使用。")
	case models.UserStatusBanned:
		addCheck("warning", "账号已禁言", firstNonEmptyText(user.BanReason, "用户可登录，但可能无法发送消息。"))
	case models.UserStatusDisabled:
		addCheck("error", "账号已冻结/禁用", firstNonEmptyText(user.BanReason, "用户无法正常使用，需要先解冻。"))
	default:
		addCheck("warning", "账号状态异常", "请确认账号审核或状态配置。")
	}
	if len(devices) == 0 {
		addCheck("warning", "没有登录设备", "用户可能长期未登录，推送 token 也无法绑定。")
	} else if activeDeviceCount == 0 {
		addCheck("info", "最近 5 分钟无活跃设备", "如果用户在线但收不到消息，请优先检查 WebSocket 重连和客户端网络。")
	}
	if pushBoundCount == 0 {
		addCheck("warning", "未绑定推送 token", "离线状态下无法收到 APNs/FCM/厂商推送。")
	} else {
		addCheck("ok", "推送 token 已绑定", "至少有一个设备已上传推送 token。")
	}
	if len(pushLogs) > 0 {
		latestPush := pushLogs[0]
		if latestPush.Success {
			addCheck("ok", "最近推送成功", "最近一次推送通道为 "+latestPush.Channel+"，时间 "+formatAdminTime(latestPush.OccurredAt)+"。")
		} else {
			addCheck("error", "最近推送失败", firstNonEmptyText(latestPush.Error, "最近一次推送失败，但未记录到具体错误。"))
		}
	} else if pushBoundCount > 0 {
		addCheck("info", "暂无推送投递记录", "可点击测试推送后刷新诊断，查看通道返回结果。")
	}
	if len(sessions) == 0 {
		addCheck("info", "没有有效登录会话记录", "如果用户称已登录，请检查 token 刷新或设备登录记录。")
	}
	response.Success(c, gin.H{
		"user": gin.H{
			"id":         user.ID,
			"uuid":       user.UUID,
			"username":   user.Username,
			"nickname":   user.Nickname,
			"phone":      user.Phone,
			"avatar":     user.Avatar,
			"status":     user.Status,
			"ban_reason": user.BanReason,
			"banned_at":  user.BannedAt,
			"is_online":  isOnline,
			"last_seen":  formatAdminTime(user.LastSeen),
			"created_at": formatAdminTime(user.CreatedAt),
			"updated_at": formatAdminTime(user.UpdatedAt),
		},
		"summary": gin.H{
			"device_count":        len(devices),
			"active_device_count": activeDeviceCount,
			"push_bound_count":    pushBoundCount,
			"session_count":       len(sessions),
			"contact_count":       contactCount,
			"chat_count":          chatCount,
			"unread_total":        unreadTotal,
			"push_setting_found":  pushSettingFound,
			"push_show_preview":   pushShowPreview,
			"diagnosed_at":        formatAdminTime(now),
		},
		"devices":      deviceList,
		"sessions":     sessionList,
		"recent_chats": recentChatList,
		"push_logs":    pushLogsToDiagnostic(pushLogs),
		"checks":       checks,
	})
}

func pushLogsToDiagnostic(items []models.PushDeliveryLog) []gin.H {
	out := make([]gin.H, 0, len(items))
	for _, item := range items {
		out = append(out, gin.H{
			"id":          item.ID,
			"device_id":   item.DeviceID,
			"device_key":  item.DeviceKey,
			"channel":     item.Channel,
			"success":     item.Success,
			"error":       item.Error,
			"title":       item.Title,
			"body":        item.Body,
			"occurred_at": formatAdminTime(item.OccurredAt),
		})
	}
	return out
}

// SendTestPush submits a diagnostic push notification to one user.
func (h *UserMgmtHandler) SendTestPush(c *gin.Context) {
	if h.push == nil {
		response.Error(c, http.StatusServiceUnavailable, "推送服务未初始化")
		return
	}
	userID := c.Param("id")
	var user models.User
	if err := h.db.First(&user, userID).Error; err != nil {
		response.Error(c, http.StatusNotFound, "用户不存在")
		return
	}

	var pushDeviceCount int64
	if err := h.db.Model(&models.UserDevice{}).
		Where("user_id = ? AND push_token != ''", user.ID).
		Count(&pushDeviceCount).Error; err != nil {
		response.Error(c, http.StatusInternalServerError, "查询推送设备失败")
		return
	}
	if pushDeviceCount == 0 {
		response.Error(c, http.StatusBadRequest, "用户没有绑定推送 token")
		return
	}
	now := time.Now()
	err := h.push.PushToUser(
		user.ID,
		"推送诊断",
		"这是一条后台测试推送，用于验证当前设备推送通道。",
		map[string]interface{}{
			"type":         "push_diagnostic",
			"user_id":      user.UUID,
			"diagnosed_at": formatAdminTime(now),
		},
	)
	if err != nil {
		response.Error(c, http.StatusInternalServerError, err.Error())
		return
	}
	response.Success(c, gin.H{
		"user_id":           user.ID,
		"uuid":              user.UUID,
		"push_device_count": pushDeviceCount,
		"submitted_at":      formatAdminTime(now),
	})
}
