// 文件用途：实现后端 HTTP 接口的请求处理和统一响应。
// 核心逻辑：绑定参数，校验身份与权限，调用业务服务并持久化关键状态。

package handlers

import (
	"errors"
	"github.com/gin-gonic/gin"
	"github.com/google/uuid"
	"gorm.io/gorm"
	"gorm.io/gorm/clause" // 好友申请状态只沿 pending -> accepted/rejected/expired 单向流转，过期申请不能再次审批。
	"log"
	"net/http"
	"sort"
	"strings"
	"time"
	"genericim/internal/models"
	"genericim/pkg/response"
)

const friendRequestLifetime = 7 * 24 * time.Hour

var (
	errFriendRequestAlreadyContact = errors.New("already contacts")
	errFriendRequestForbidden      = errors.New("friend request forbidden")
	errFriendRequestExpired        = errors.New("friend request expired")
	errFriendRequestNotPending     = errors.New("friend request is not pending")
)

type sendFriendRequestPayload struct {
	UserID  string `json:"user_id" binding:"required"`
	Message string `json:"message"`
}

func friendRequestIsExpired(request *models.FriendRequest, now time.Time) bool {
	return request != nil && request.Status == models.FriendRequestPending && !request.ExpiresAt.After(now)
}
func expireFriendRequest(tx *gorm.DB, request *models.FriendRequest, now time.Time) error {
	if !friendRequestIsExpired(request, now) {

		return nil
	}
	if err := tx.Model(request).Updates(map[string]interface{}{

		"status": models.FriendRequestExpired,

		"updated_at": now,
	}).Error; err != nil {

		return err
	}
	request.Status = models.FriendRequestExpired
	request.UpdatedAt = now
	return nil
}
func expirePendingFriendRequests(tx *gorm.DB, userID uint64, now time.Time) error {
	return tx.Model(&models.FriendRequest{}).
		Where("status = ? AND expires_at <= ? AND (sender_id = ? OR recipient_id = ?)", models.FriendRequestPending, now, userID, userID).
		Updates(map[string]interface{}{

			"status": models.FriendRequestExpired,

			"updated_at": now,
		}).Error
}
func lockFriendRequestUsers(tx *gorm.DB, firstID, secondID uint64) error {
	// 两个方向的好友操作都按用户 ID 升序加锁，避免 A->B 与 B->A 并发时形成锁顺序反转。
	ids := []uint64{firstID, secondID}
	sort.Slice(ids, func(i, j int) bool { return ids[i] < ids[j] })
	var users []models.User
	return tx.Clauses(clause.Locking{Strength: "UPDATE"}).
		Where("id IN ?", ids).
		Order("id ASC").
		Select("id").
		Find(&users).Error
}
func areContacts(tx *gorm.DB, firstID, secondID uint64) (bool, error) {
	var count int64
	err := tx.Model(&models.Contact{}).
		Where("user_id = ? AND contact_user_id = ? AND status = 1", firstID, secondID).
		Count(&count).Error
	return count > 0, err
}
func ensureMutualContacts(tx *gorm.DB, firstID, secondID uint64, now time.Time) error {
	// 联系人表按方向存储，接受好友申请时要在同一事务内补齐双向关系。
	if _, err := ensureContactRelation(tx, firstID, secondID, now); err != nil {

		return err
	}
	if _, err := ensureContactRelation(tx, secondID, firstID, now); err != nil {

		return err
	}
	return nil
}
func (h *ContactHandler) friendRequestResponse(request *models.FriendRequest, viewerID uint64) gin.H {
	item := gin.H{

		"id": request.UUID,

		"message": request.Message,

		"status": request.Status,

		"expires_at": request.ExpiresAt,

		"responded_at": request.RespondedAt,

		"created_at": request.CreatedAt,

		"updated_at": request.UpdatedAt,

		"direction": "incoming",
	}
	otherID := request.SenderID
	if request.SenderID == viewerID {

		item["direction"] = "outgoing"

		otherID = request.RecipientID
	}
	var user models.User
	if err := h.db.Where("id = ?", otherID).First(&user).Error; err == nil {

		item["user"] = gin.H{

			"id": user.ID,

			"uuid": user.UUID,

			"nickname": user.Nickname,

			"username": user.Username,

			"avatar": user.Avatar,

			"bio": user.Bio,

			"emoji_avatar": user.EmojiAvatar,

			"nickname_color": user.NicknameColor,
		}
	}
	return item
}
func (h *ContactHandler) notifyFriendRequest(request *models.FriendRequest, eventType string) {
	if h.hub == nil || request == nil {

		return
	}
	var users []models.User
	if err := h.db.Where("id IN ?", []uint64{request.SenderID, request.RecipientID}).Find(&users).Error; err != nil {

		return
	}
	for _, user := range users {

		h.hub.SendToUser(user.UUID, map[string]interface{}{

			"type": eventType,

			"request": h.friendRequestResponse(request, user.ID),
		})
	}
}
func (h *ContactHandler) SendFriendRequest(c *gin.Context) {
	var payload sendFriendRequestPayload
	if err := c.ShouldBindJSON(&payload); err != nil {

		response.BadRequest(c, "参数错误")

		return
	}
	payload.UserID = strings.TrimSpace(payload.UserID)
	payload.Message = strings.TrimSpace(payload.Message)
	if len([]rune(payload.Message)) > 200 {

		response.BadRequest(c, "验证消息不能超过200个字符")

		return
	}
	var sender models.User
	if err := h.db.Where("uuid = ?", c.GetString("user_id")).First(&sender).Error; err != nil {

		response.Unauthorized(c, "请先登录")

		return
	}
	var recipient models.User
	if err := h.db.Where("uuid = ?", payload.UserID).First(&recipient).Error; err != nil {

		response.NotFound(c, "用户不存在")

		return
	}
	if sender.ID == recipient.ID {

		response.BadRequest(c, "不能向自己发送好友申请")

		return
	}
	now := time.Now()
	switch loadFriendAddMode(h.db) {
	case models.FriendAddModeDisabled:

		response.Forbidden(c, "管理员已关闭添加好友功能")

		return
	case models.FriendAddModeDirect:

		if contacts, err := areContacts(h.db, sender.ID, recipient.ID); err != nil {

			response.ServerError(c, "添加好友失败")

			return

		} else if contacts {

			response.BadRequest(c, "已经是联系人")

			return

		}

		if err := h.db.Transaction(func(tx *gorm.DB) error {

			if err := lockFriendRequestUsers(tx, sender.ID, recipient.ID); err != nil {

				return err

			}

			return ensureMutualContacts(tx, sender.ID, recipient.ID, now)

		}); err != nil {

			response.ServerError(c, "添加好友失败")

			return

		}

		if err := h.sendContactAddedSystemMessage(c, &sender, &recipient); err != nil {

			// 联系人关系已经成功建立，系统消息失败不回滚。

			log.Printf("[Contact] sendContactAddedSystemMessage failed: %v", err)

		}
		result := models.FriendRequest{

			UUID: uuid.NewString(),

			SenderID: sender.ID,

			RecipientID: recipient.ID,

			Message: payload.Message,

			Status: models.FriendRequestAccepted,

			ExpiresAt: now,

			RespondedAt: &now,

			CreatedAt: now,

			UpdatedAt: now,
		}

		response.Success(c, gin.H{

			"request": h.friendRequestResponse(&result, sender.ID),

			"created": true,

			"auto_accepted": true,

			"direct_added": true,
		})

		return
	}
	var result models.FriendRequest
	created := false
	autoAccepted := false
	err := h.db.Transaction(func(tx *gorm.DB) error {

		// 锁住双方后再检查关系和申请状态，保证反向申请、重复请求与建联只产生一个最终结果。

		if err := lockFriendRequestUsers(tx, sender.ID, recipient.ID); err != nil {

			return err

		}

		if contacts, err := areContacts(tx, sender.ID, recipient.ID); err != nil {

			return err

		} else if contacts {

			return errFriendRequestAlreadyContact

		}

		if err := expirePendingFriendRequests(tx, sender.ID, now); err != nil {

			return err

		}

		if err := expirePendingFriendRequests(tx, recipient.ID, now); err != nil {

			return err

		}
		var reverse models.FriendRequest

		reverseErr := tx.Clauses(clause.Locking{Strength: "UPDATE"}).
			Where("sender_id = ? AND recipient_id = ? AND status = ?", recipient.ID, sender.ID, models.FriendRequestPending).
			Order("id DESC").First(&reverse).Error

		if reverseErr == nil {

			// 对方已有待处理申请时直接接受，并在同一事务中补齐双向联系人关系。

			if err := tx.Model(&reverse).Updates(map[string]interface{}{

				"status": models.FriendRequestAccepted,

				"responded_at": &now,

				"updated_at": now,
			}).Error; err != nil {

				return err

			}

			if err := ensureMutualContacts(tx, sender.ID, recipient.ID, now); err != nil {

				return err

			}

			reverse.Status = models.FriendRequestAccepted

			reverse.RespondedAt = &now

			reverse.UpdatedAt = now

			result = reverse

			autoAccepted = true

			return nil

		}

		if !errors.Is(reverseErr, gorm.ErrRecordNotFound) {

			return reverseErr

		}
		var existing models.FriendRequest

		existingErr := tx.Where("sender_id = ? AND recipient_id = ? AND status = ?", sender.ID, recipient.ID, models.FriendRequestPending).
			Order("id DESC").First(&existing).Error

		if existingErr == nil {

			result = existing

			return nil

		}

		if !errors.Is(existingErr, gorm.ErrRecordNotFound) {

			return existingErr

		}
		result = models.FriendRequest{

			UUID: uuid.NewString(),

			SenderID: sender.ID,

			RecipientID: recipient.ID,

			Message: payload.Message,

			Status: models.FriendRequestPending,

			ExpiresAt: now.Add(friendRequestLifetime),

			CreatedAt: now,

			UpdatedAt: now,
		}

		if err := tx.Create(&result).Error; err != nil {

			return err

		}
		created = true

		return nil
	})
	if err != nil {

		if errors.Is(err, errFriendRequestAlreadyContact) {

			response.BadRequest(c, "已经是联系人")

			return

		}

		response.ServerError(c, "发送好友申请失败")

		return
	}
	// WebSocket 通知放在事务提交之后，客户端不会收到随后又被回滚的状态。
	eventType := "friend_request_changed"
	if created {

		eventType = "friend_request_created"
	}
	h.notifyFriendRequest(&result, eventType)
	response.Success(c, gin.H{

		"request": h.friendRequestResponse(&result, sender.ID),

		"created": created,

		"auto_accepted": autoAccepted,
	})
}
func (h *ContactHandler) ListFriendRequests(c *gin.Context) {
	var user models.User
	if err := h.db.Where("uuid = ?", c.GetString("user_id")).First(&user).Error; err != nil {

		response.Unauthorized(c, "请先登录")

		return
	}
	now := time.Now()
	if err := expirePendingFriendRequests(h.db, user.ID, now); err != nil {

		response.ServerError(c, "读取好友申请失败")

		return
	}
	box := strings.ToLower(strings.TrimSpace(c.DefaultQuery("box", "incoming")))
	status := strings.ToLower(strings.TrimSpace(c.Query("status")))
	query := h.db.Model(&models.FriendRequest{})
	if box == "outgoing" {

		query = query.Where("sender_id = ?", user.ID)
	} else {

		box = "incoming"

		query = query.Where("recipient_id = ?", user.ID)
	}
	if status != "" {

		query = query.Where("status = ?", status)
	}
	var requests []models.FriendRequest
	if err := query.Order("created_at DESC").Limit(200).Find(&requests).Error; err != nil {

		response.ServerError(c, "读取好友申请失败")

		return
	}
	items := make([]gin.H, 0, len(requests))
	for i := range requests {

		items = append(items, h.friendRequestResponse(&requests[i], user.ID))
	}
	response.Success(c, gin.H{"list": items, "box": box})
}
func (h *ContactHandler) reviewFriendRequest(c *gin.Context, accept bool) {
	var reviewer models.User
	if err := h.db.Where("uuid = ?", c.GetString("user_id")).First(&reviewer).Error; err != nil {

		response.Unauthorized(c, "请先登录")

		return
	}
	if loadFriendAddMode(h.db) == models.FriendAddModeDisabled {

		response.Forbidden(c, "管理员已关闭添加好友功能")

		return
	}
	now := time.Now()
	var request models.FriendRequest
	if err := h.db.Where("uuid = ?", c.Param("id")).First(&request).Error; err != nil {

		response.NotFound(c, "好友申请不存在")

		return
	}
	expired := false
	err := h.db.Transaction(func(tx *gorm.DB) error {

		// 审批时重新锁定申请记录并复核状态，防止重复点击或并发审批覆盖已完成结果。

		if request.RecipientID != reviewer.ID {

			return errFriendRequestForbidden

		}

		if err := lockFriendRequestUsers(tx, request.SenderID, request.RecipientID); err != nil {

			return err

		}

		if err := tx.Clauses(clause.Locking{Strength: "UPDATE"}).Where("uuid = ?", c.Param("id")).First(&request).Error; err != nil {

			return err

		}

		if err := expireFriendRequest(tx, &request, now); err != nil {

			return err

		}

		if request.Status == models.FriendRequestExpired {

			expired = true

			return nil

		}

		if request.Status == models.FriendRequestAccepted && accept {

			return nil

		}

		if request.Status != models.FriendRequestPending {

			return errFriendRequestNotPending

		}
		nextStatus := models.FriendRequestRejected

		if accept {

			nextStatus = models.FriendRequestAccepted

			if err := ensureMutualContacts(tx, request.SenderID, request.RecipientID, now); err != nil {

				return err

			}

		}

		if err := tx.Model(&request).Updates(map[string]interface{}{

			"status": nextStatus,

			"responded_at": &now,

			"updated_at": now,
		}).Error; err != nil {

			return err

		}

		request.Status = nextStatus

		request.RespondedAt = &now

		request.UpdatedAt = now

		return nil
	})
	if err != nil {

		switch {

		case errors.Is(err, gorm.ErrRecordNotFound):

			response.NotFound(c, "好友申请不存在")

		case errors.Is(err, errFriendRequestForbidden):

			response.Error(c, http.StatusForbidden, "无权处理该好友申请")

		case errors.Is(err, errFriendRequestNotPending):

			response.BadRequest(c, "好友申请已处理")

		default:

			response.ServerError(c, "处理好友申请失败")

		}

		return
	}
	if expired {

		h.notifyFriendRequest(&request, "friend_request_changed")

		response.BadRequest(c, "好友申请已过期，请重新发送")

		return
	}
	// WebSocket 通知发生在事务提交后；通知失败不应回滚已经确定的好友关系。
	h.notifyFriendRequest(&request, "friend_request_changed")
	response.Success(c, h.friendRequestResponse(&request, reviewer.ID))
}
func (h *ContactHandler) AcceptFriendRequest(c *gin.Context) {
	h.reviewFriendRequest(c, true)
}
func (h *ContactHandler) RejectFriendRequest(c *gin.Context) {
	h.reviewFriendRequest(c, false)
}
