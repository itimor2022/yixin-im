package handlers

import (
	"encoding/json"
	"log"
	"net/http"
	"strconv"

	"gaoranim/internal/models"
	"gaoranim/internal/ws"
	"gaoranim/pkg/response"

	"github.com/gin-gonic/gin"
	"github.com/google/uuid"
	"gorm.io/gorm"
)

type MomentHandler struct {
	db  *gorm.DB
	hub *ws.Hub
}

func NewMomentHandler(db *gorm.DB, hub *ws.Hub) *MomentHandler {
	return &MomentHandler{db: db, hub: hub}
}

// getUserByUUID 通过 JWT 中的 UUID 获取用户
func (h *MomentHandler) getUserByUUID(c *gin.Context) (*models.User, error) {
	userUUID, exists := c.Get("user_id")
	if !exists {
		return nil, gorm.ErrRecordNotFound
	}

	var user models.User
	if err := h.db.Where("uuid = ?", userUUID.(string)).First(&user).Error; err != nil {
		return nil, err
	}
	return &user, nil
}

// MomentListItem 动态列表项（包含用户信息）
type MomentListItem struct {
	ID             uint64   `json:"id"`
	UUID           string   `json:"uuid"`
	UserID         uint64   `json:"user_id"`
	UserName       string   `json:"user_name"`
	UserAvatar     string   `json:"user_avatar"`
	Content        string   `json:"content"`
	ContentType    int8     `json:"content_type"`
	MediaUrls      []string `json:"media_urls"`
	VideoThumbnail string   `json:"video_thumbnail"`
	Topics         []string `json:"topics"`
	Visibility     int8     `json:"visibility"`
	Status         int8     `json:"status"`
	ReviewReason   string   `json:"review_reason,omitempty"`
	LikeCount      int      `json:"like_count"`
	CommentCount   int      `json:"comment_count"`
	ShareCount     int      `json:"share_count"`
	IsLiked        bool     `json:"is_liked"`
	Location       string   `json:"location"`
	CreatedAt      string   `json:"created_at"`
}

// GetMomentList 获取动态广场列表（公开动态）
func (h *MomentHandler) GetMomentList(c *gin.Context) {
	page, _ := strconv.Atoi(c.DefaultQuery("page", "1"))
	pageSize, _ := strconv.Atoi(c.DefaultQuery("page_size", "20"))
	topic := c.Query("topic")    // 按话题筛选
	userID := c.Query("user_id") // 按用户筛选

	// 获取当前用户ID（如果已登录）
	var currentUID uint64
	if userUUID := c.GetString("user_id"); userUUID != "" {
		var currentUser models.User
		if err := h.db.Where("uuid = ?", userUUID).First(&currentUser).Error; err == nil {
			currentUID = currentUser.ID
		}
	}

	offset := (page - 1) * pageSize

	query := h.db.Model(&models.Moment{}).
		Where("status = ?", models.MomentStatusNormal).
		Where("visibility = ?", models.VisibilityPublic) // 只显示公开动态

	// 过滤屏蔽的动态和用户（如果用户已登录）
	if currentUID > 0 {
		// 获取屏蔽的动态ID
		var blockedMomentIDs []uint64
		h.db.Model(&models.MomentBlock{}).Where("user_id = ?", currentUID).Pluck("moment_id", &blockedMomentIDs)
		if len(blockedMomentIDs) > 0 {
			query = query.Where("id NOT IN ?", blockedMomentIDs)
		}

		// 获取屏蔽的用户ID
		var blockedUserIDs []uint64
		h.db.Model(&models.UserMomentBlock{}).Where("user_id = ?", currentUID).Pluck("blocked_user_id", &blockedUserIDs)
		if len(blockedUserIDs) > 0 {
			query = query.Where("user_id NOT IN ?", blockedUserIDs)
		}
	}

	// 按话题筛选
	if topic != "" {
		query = query.Where("JSON_CONTAINS(topics, ?)", `"`+topic+`"`)
	}

	// 按用户筛选
	if userID != "" {
		query = query.Where("user_id = ?", userID)
	}

	var total int64
	query.Count(&total)

	var moments []models.Moment
	if err := query.Order("created_at DESC").Offset(offset).Limit(pageSize).Find(&moments).Error; err != nil {
		response.Error(c, http.StatusInternalServerError, "查询失败")
		return
	}

	// 获取用户信息
	userIDs := make([]uint64, 0, len(moments))
	for _, m := range moments {
		userIDs = append(userIDs, m.UserID)
	}

	var users []models.User
	if len(userIDs) > 0 {
		h.db.Where("id IN ?", userIDs).Find(&users)
	}
	userMap := make(map[uint64]models.User)
	for _, u := range users {
		userMap[u.ID] = u
	}

	// 获取当前用户点赞状态
	likedMap := make(map[uint64]bool)
	if currentUID > 0 {
		momentIDs := make([]uint64, 0, len(moments))
		for _, m := range moments {
			momentIDs = append(momentIDs, m.ID)
		}
		var likes []models.MomentLike
		h.db.Where("user_id = ? AND moment_id IN ?", currentUID, momentIDs).Find(&likes)
		for _, l := range likes {
			likedMap[l.MomentID] = true
		}
	}

	// 构建响应
	result := make([]MomentListItem, 0, len(moments))
	for _, m := range moments {
		user := userMap[m.UserID]

		// 解析 JSON 字段
		var mediaUrls []string
		var topics []string
		json.Unmarshal(m.MediaUrls, &mediaUrls)
		json.Unmarshal(m.Topics, &topics)

		item := MomentListItem{
			ID:             m.ID,
			UUID:           m.UUID,
			UserID:         m.UserID,
			UserName:       user.Nickname,
			Content:        m.Content,
			ContentType:    m.ContentType,
			MediaUrls:      mediaUrls,
			VideoThumbnail: m.VideoThumbnail,
			Topics:         topics,
			Visibility:     m.Visibility,
			Status:         m.Status,
			ReviewReason:   m.ReviewReason,
			LikeCount:      m.LikeCount,
			CommentCount:   m.CommentCount,
			ShareCount:     m.ShareCount,
			IsLiked:        likedMap[m.ID],
			Location:       m.Location,
			CreatedAt:      m.CreatedAt.Format("2006-01-02T15:04:05Z07:00"),
		}

		item.UserAvatar = user.Avatar

		result = append(result, item)
	}

	response.Success(c, gin.H{
		"list":      result,
		"total":     total,
		"page":      page,
		"page_size": pageSize,
	})
}

// GetMoment 获取单个动态详情
func (h *MomentHandler) GetMoment(c *gin.Context) {
	momentID := c.Param("id")

	var moment models.Moment
	if err := h.db.Where("id = ? OR uuid = ?", momentID, momentID).First(&moment).Error; err != nil {
		response.Error(c, http.StatusNotFound, "动态不存在")
		return
	}

	if moment.Status != models.MomentStatusNormal {
		response.Error(c, http.StatusNotFound, "动态已删除")
		return
	}

	// 获取当前用户（可能未登录）
	currentUserID, _ := c.Get("user_id")
	var currentUser models.User
	if currentUserID != nil && currentUserID.(string) != "" {
		h.db.Where("uuid = ?", currentUserID).First(&currentUser)
	}

	// 可见性校验
	if moment.Visibility == models.VisibilityPrivate {
		// 仅自己可见
		if currentUser.ID == 0 || currentUser.ID != moment.UserID {
			response.Error(c, http.StatusForbidden, "无权查看该动态")
			return
		}
	} else if moment.Visibility == models.VisibilityContacts {
		// 仅联系人可见
		if currentUser.ID == 0 {
			response.Error(c, http.StatusForbidden, "无权查看该动态")
			return
		}
		if currentUser.ID != moment.UserID {
			var contactCount int64
			h.db.Model(&models.Contact{}).Where(
				"(user_id = ? AND contact_id = ?) OR (user_id = ? AND contact_id = ?)",
				moment.UserID, currentUser.ID, currentUser.ID, moment.UserID,
			).Count(&contactCount)
			if contactCount == 0 {
				response.Error(c, http.StatusForbidden, "无权查看该动态")
				return
			}
		}
	}

	// 获取作者信息
	var user models.User
	h.db.First(&user, moment.UserID)

	// 解析媒体和话题
	var mediaUrls []string
	json.Unmarshal(moment.MediaUrls, &mediaUrls)
	var topics []string
	json.Unmarshal(moment.Topics, &topics)

	isLiked := false
	if currentUser.ID > 0 {
		var like models.MomentLike
		if err := h.db.Where("moment_id = ? AND user_id = ?", moment.ID, currentUser.ID).First(&like).Error; err == nil {
			isLiked = true
		}
	}

	response.Success(c, MomentListItem{
		ID:             moment.ID,
		UUID:           moment.UUID,
		UserID:         moment.UserID,
		UserName:       user.Nickname,
		UserAvatar:     user.Avatar,
		Content:        moment.Content,
		ContentType:    moment.ContentType,
		MediaUrls:      mediaUrls,
		VideoThumbnail: moment.VideoThumbnail,
		Topics:         topics,
		Visibility:     moment.Visibility,
		Status:         moment.Status,
		ReviewReason:   moment.ReviewReason,
		LikeCount:      moment.LikeCount,
		CommentCount:   moment.CommentCount,
		ShareCount:     moment.ShareCount,
		IsLiked:        isLiked,
		Location:       moment.Location,
		CreatedAt:      moment.CreatedAt.Format("2006-01-02 15:04:05"),
	})
}

// PublishMoment 发布动态
func (h *MomentHandler) PublishMoment(c *gin.Context) {
	// 检查是否允许发布动态
	var enableMomentPostSetting models.SystemSetting
	if err := h.db.Where("`key` = ?", models.SettingEnableMomentPost).First(&enableMomentPostSetting).Error; err == nil {
		if isSystemSettingFalse(enableMomentPostSetting.Value) {
			response.Error(c, http.StatusForbidden, "广场发布功能已关闭，仅支持浏览")
			return
		}
	}

	userUUID, _ := c.Get("user_id")

	// 通过 UUID 查询用户
	var user models.User
	if err := h.db.Where("uuid = ?", userUUID.(string)).First(&user).Error; err != nil {
		response.Error(c, http.StatusUnauthorized, "用户不存在")
		return
	}
	uid := user.ID

	var req struct {
		Content          string   `json:"content"`
		ContentType      int8     `json:"content_type"`
		MediaUrls        []string `json:"media_urls"`
		VideoThumbnail   string   `json:"video_thumbnail"`
		Topics           []string `json:"topics"`
		Visibility       int8     `json:"visibility"`
		SelectedContacts []uint64 `json:"selected_contacts"`
		Location         string   `json:"location"`
	}

	if err := c.ShouldBindJSON(&req); err != nil {
		response.Error(c, http.StatusBadRequest, "参数错误")
		return
	}

	// 内容检查（违禁词过滤）
	filteredContent, blocked := h.filterContent(req.Content)
	if blocked {
		response.Error(c, http.StatusBadRequest, "内容包含违禁词，无法发布")
		return
	}

	// 默认值
	if req.ContentType == 0 {
		req.ContentType = models.ContentTypeText
	}
	if req.Visibility == 0 {
		req.Visibility = models.VisibilityPublic
	}

	// JSON 编码
	mediaUrlsJSON, _ := json.Marshal(req.MediaUrls)
	topicsJSON, _ := json.Marshal(req.Topics)
	selectedContactsJSON, _ := json.Marshal(req.SelectedContacts)

	moment := models.Moment{
		UUID:             uuid.New().String(),
		UserID:           uid,
		Content:          filteredContent,
		ContentType:      req.ContentType,
		MediaUrls:        mediaUrlsJSON,
		VideoThumbnail:   req.VideoThumbnail,
		Topics:           topicsJSON,
		Visibility:       req.Visibility,
		SelectedContacts: selectedContactsJSON,
		Location:         req.Location,
		Status:           models.MomentStatusNormal,
	}

	var reviewSetting models.SystemSetting
	reviewEnabled := false
	if err := h.db.Where("`key` = ?", models.SettingMomentPostReviewEnabled).First(&reviewSetting).Error; err == nil {
		reviewEnabled = isSystemSettingTrue(reviewSetting.Value)
	}
	log.Printf("[Moment Publish Debug] build=2026-04-14-verify reviewSetting=%q reviewEnabled=%v userID=%d", reviewSetting.Value, reviewEnabled, uid)
	if reviewEnabled {
		moment.Status = models.MomentStatusPending
	}

	if err := h.db.Select(
		"UUID",
		"UserID",
		"Content",
		"ContentType",
		"MediaUrls",
		"VideoThumbnail",
		"Topics",
		"Visibility",
		"SelectedContacts",
		"Location",
		"Status",
	).Create(&moment).Error; err != nil {
		response.Error(c, http.StatusInternalServerError, "发布失败")
		return
	}

	// 更新或创建话题
	for _, topicName := range req.Topics {
		if topicName == "" {
			continue
		}
		var topic models.Topic
		result := h.db.Where("name = ?", topicName).First(&topic)
		if result.Error != nil {
			// 话题不存在，创建新话题
			newTopic := models.Topic{
				Name:      topicName,
				PostCount: 1,
				Status:    1,
			}
			h.db.Create(&newTopic)
		} else {
			// 话题存在，更新计数
			h.db.Model(&topic).UpdateColumn("post_count", gorm.Expr("post_count + 1"))
		}
	}

	// 构建响应
	item := MomentListItem{
		ID:             moment.ID,
		UUID:           moment.UUID,
		UserID:         uid,
		UserName:       user.Nickname,
		Content:        moment.Content,
		ContentType:    moment.ContentType,
		MediaUrls:      req.MediaUrls,
		VideoThumbnail: moment.VideoThumbnail,
		Topics:         req.Topics,
		Visibility:     moment.Visibility,
		Status:         moment.Status,
		ReviewReason:   moment.ReviewReason,
		LikeCount:      0,
		CommentCount:   0,
		ShareCount:     0,
		IsLiked:        false,
		Location:       moment.Location,
		CreatedAt:      moment.CreatedAt.Format("2006-01-02T15:04:05Z07:00"),
	}
	item.UserAvatar = user.Avatar

	if reviewEnabled {
		response.SuccessWithMessage(c, "动态已提交审核", item)
		return
	}

	response.Success(c, item)
}

// DeleteMoment 删除动态
func (h *MomentHandler) DeleteMoment(c *gin.Context) {
	momentID := c.Param("id")
	user, err := h.getUserByUUID(c)
	if err != nil {
		response.Error(c, http.StatusUnauthorized, "用户不存在")
		return
	}
	uid := user.ID

	var moment models.Moment
	if err := h.db.First(&moment, momentID).Error; err != nil {
		response.Error(c, http.StatusNotFound, "动态不存在")
		return
	}

	// 检查权限
	if moment.UserID != uid {
		response.Error(c, http.StatusForbidden, "无权删除")
		return
	}

	// 软删除
	moment.Status = models.MomentStatusDeleted
	h.db.Save(&moment)

	response.SuccessWithMessage(c, "删除成功", nil)
}

// UpdateMoment 更新动态（主要用于修改可见性）
func (h *MomentHandler) UpdateMoment(c *gin.Context) {
	momentID := c.Param("id")
	user, err := h.getUserByUUID(c)
	if err != nil {
		response.Error(c, http.StatusUnauthorized, "用户不存在")
		return
	}
	uid := user.ID

	var req struct {
		Visibility *int8 `json:"visibility"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		response.Error(c, http.StatusBadRequest, "参数错误")
		return
	}

	var moment models.Moment
	if err := h.db.First(&moment, momentID).Error; err != nil {
		response.Error(c, http.StatusNotFound, "动态不存在")
		return
	}

	if moment.UserID != uid {
		response.Error(c, http.StatusForbidden, "无权修改")
		return
	}

	if req.Visibility != nil {
		moment.Visibility = *req.Visibility
	}

	h.db.Save(&moment)
	response.Success(c, moment)
}

// LikeMoment 点赞动态
func (h *MomentHandler) LikeMoment(c *gin.Context) {
	momentID := c.Param("id")
	user, err := h.getUserByUUID(c)
	if err != nil {
		response.Error(c, http.StatusUnauthorized, "用户不存在")
		return
	}
	uid := user.ID

	mid, parseErr := strconv.ParseUint(momentID, 10, 64)
	if parseErr != nil || mid == 0 {
		response.BadRequest(c, "参数错误")
		return
	}

	// 检查是否已点赞
	var existing models.MomentLike
	if err := h.db.Where("moment_id = ? AND user_id = ?", mid, uid).First(&existing).Error; err == nil {
		response.Error(c, http.StatusBadRequest, "已点赞")
		return
	}

	// 创建点赞记录
	like := models.MomentLike{
		MomentID: mid,
		UserID:   uid,
	}
	h.db.Create(&like)

	// 更新点赞数
	h.db.Model(&models.Moment{}).Where("id = ?", mid).
		UpdateColumn("like_count", gorm.Expr("like_count + 1"))

	// 发送 WebSocket 通知给动态作者
	var moment models.Moment
	if err := h.db.First(&moment, mid).Error; err == nil && moment.UserID != uid {
		// 获取动态作者的 UUID
		var author models.User
		if err := h.db.First(&author, moment.UserID).Error; err == nil {
			h.hub.SendToUserCluster(author.UUID, map[string]interface{}{
				"type":        "moment_like",
				"moment_id":   mid,
				"user_id":     uid,
				"user_name":   user.Nickname,
				"user_avatar": user.Avatar,
			})
		}
	}

	response.SuccessWithMessage(c, "点赞成功", nil)
}

// UnlikeMoment 取消点赞
func (h *MomentHandler) UnlikeMoment(c *gin.Context) {
	momentID := c.Param("id")
	user, err := h.getUserByUUID(c)
	if err != nil {
		response.Error(c, http.StatusUnauthorized, "用户不存在")
		return
	}
	uid := user.ID

	mid, _ := strconv.ParseUint(momentID, 10, 64)

	// 删除点赞记录
	result := h.db.Where("moment_id = ? AND user_id = ?", mid, uid).Delete(&models.MomentLike{})
	if result.RowsAffected > 0 {
		// 更新点赞数
		h.db.Model(&models.Moment{}).Where("id = ?", mid).
			UpdateColumn("like_count", gorm.Expr("GREATEST(like_count - 1, 0)"))
	}

	response.SuccessWithMessage(c, "取消点赞", nil)
}

// GetHotTopics 获取热门话题
func (h *MomentHandler) GetHotTopics(c *gin.Context) {
	var topics []models.Topic
	h.db.Where("status = 1").
		Order("is_hot DESC, post_count DESC, sort DESC").
		Limit(20).
		Find(&topics)

	result := make([]gin.H, 0, len(topics))
	for _, t := range topics {
		result = append(result, gin.H{
			"id":         t.ID,
			"name":       t.Name,
			"icon":       t.Icon,
			"post_count": t.PostCount,
			"is_hot":     t.IsHot,
		})
	}

	response.Success(c, gin.H{"list": result})
}

// GetComments 获取动态评论
func (h *MomentHandler) GetComments(c *gin.Context) {
	momentID := c.Param("id")
	page, _ := strconv.Atoi(c.DefaultQuery("page", "1"))
	pageSize, _ := strconv.Atoi(c.DefaultQuery("page_size", "20"))

	offset := (page - 1) * pageSize

	var total int64
	h.db.Model(&models.MomentComment{}).
		Where("moment_id = ? AND parent_id IS NULL AND status = 1", momentID).
		Count(&total)

	var comments []models.MomentComment
	h.db.Where("moment_id = ? AND parent_id IS NULL AND status = 1", momentID).
		Order("created_at DESC").
		Offset(offset).
		Limit(pageSize).
		Find(&comments)

	// 获取用户信息
	userIDs := make([]uint64, 0)
	commentIDs := make([]uint64, 0)
	for _, c := range comments {
		userIDs = append(userIDs, c.UserID)
		commentIDs = append(commentIDs, c.ID)
	}

	var users []models.User
	if len(userIDs) > 0 {
		h.db.Where("id IN ?", userIDs).Find(&users)
	}
	userMap := make(map[uint64]models.User)
	for _, u := range users {
		userMap[u.ID] = u
	}

	// 获取子评论
	var replies []models.MomentComment
	if len(commentIDs) > 0 {
		h.db.Where("parent_id IN ? AND status = 1", commentIDs).
			Order("created_at ASC").
			Find(&replies)
		for _, r := range replies {
			userIDs = append(userIDs, r.UserID)
		}
		// 重新获取用户
		var replyUsers []models.User
		h.db.Where("id IN ?", userIDs).Find(&replyUsers)
		for _, u := range replyUsers {
			userMap[u.ID] = u
		}
	}

	// 构建回复映射
	replyMap := make(map[uint64][]gin.H)
	for _, r := range replies {
		user := userMap[r.UserID]
		replyItem := gin.H{
			"id":          r.ID,
			"user_id":     r.UserID,
			"user_name":   user.Nickname,
			"user_avatar": user.Avatar,
			"content":     r.Content,
			"like_count":  r.LikeCount,
			"created_at":  r.CreatedAt.Format("2006-01-02T15:04:05Z07:00"),
		}
		replyMap[*r.ParentID] = append(replyMap[*r.ParentID], replyItem)
	}

	result := make([]gin.H, 0, len(comments))
	for _, c := range comments {
		user := userMap[c.UserID]
		item := gin.H{
			"id":          c.ID,
			"user_id":     c.UserID,
			"user_name":   user.Nickname,
			"user_avatar": user.Avatar,
			"content":     c.Content,
			"like_count":  c.LikeCount,
			"created_at":  c.CreatedAt.Format("2006-01-02T15:04:05Z07:00"),
			"replies":     replyMap[c.ID],
		}
		result = append(result, item)
	}

	response.Success(c, gin.H{
		"list":      result,
		"total":     total,
		"page":      page,
		"page_size": pageSize,
	})
}

// AddComment 添加评论
func (h *MomentHandler) AddComment(c *gin.Context) {
	momentID := c.Param("id")
	user, err := h.getUserByUUID(c)
	if err != nil {
		response.Error(c, http.StatusUnauthorized, "用户不存在")
		return
	}
	uid := user.ID

	var req struct {
		Content   string  `json:"content" binding:"required"`
		ParentID  *uint64 `json:"parent_id"`
		ReplyToID *uint64 `json:"reply_to_id"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		response.Error(c, http.StatusBadRequest, "参数错误")
		return
	}

	// 违禁词过滤
	filteredContent, blocked := h.filterContent(req.Content)
	if blocked {
		response.Error(c, http.StatusBadRequest, "评论包含违禁词")
		return
	}

	mid, parseCommentErr := strconv.ParseUint(momentID, 10, 64)
	if parseCommentErr != nil || mid == 0 {
		response.BadRequest(c, "参数错误")
		return
	}

	// 验证动态存在
	var targetMoment models.Moment
	if err := h.db.Where("id = ?", mid).First(&targetMoment).Error; err != nil {
		response.NotFound(c, "动态不存在")
		return
	}

	comment := models.MomentComment{
		UUID:      uuid.New().String(),
		MomentID:  mid,
		UserID:    uid,
		ParentID:  req.ParentID,
		ReplyToID: req.ReplyToID,
		Content:   filteredContent,
		Status:    1,
	}

	if err := h.db.Create(&comment).Error; err != nil {
		response.Error(c, http.StatusInternalServerError, "评论失败")
		return
	}

	// 更新评论数
	h.db.Model(&models.Moment{}).Where("id = ?", mid).
		UpdateColumn("comment_count", gorm.Expr("comment_count + 1"))

	// 发送 WebSocket 通知
	var moment models.Moment
	if err := h.db.First(&moment, mid).Error; err == nil {
		// 判断是评论还是回复
		if req.ReplyToID != nil {
			// 回复：通知被回复的用户
			var parentComment models.MomentComment
			if h.db.First(&parentComment, *req.ReplyToID).Error == nil && parentComment.UserID != uid {
				var targetUser models.User
				if h.db.First(&targetUser, parentComment.UserID).Error == nil {
					h.hub.SendToUserCluster(targetUser.UUID, map[string]interface{}{
						"type":        "moment_reply",
						"moment_id":   mid,
						"comment_id":  comment.ID,
						"user_id":     uid,
						"user_name":   user.Nickname,
						"user_avatar": user.Avatar,
						"content":     comment.Content,
					})
				}
			}
		} else if moment.UserID != uid {
			// 评论：通知动态作者
			var author models.User
			if h.db.First(&author, moment.UserID).Error == nil {
				h.hub.SendToUserCluster(author.UUID, map[string]interface{}{
					"type":        "moment_comment",
					"moment_id":   mid,
					"comment_id":  comment.ID,
					"user_id":     uid,
					"user_name":   user.Nickname,
					"user_avatar": user.Avatar,
					"content":     comment.Content,
				})
			}
		}
	}

	response.Success(c, gin.H{
		"id":          comment.ID,
		"moment_id":   mid,
		"user_id":     uid,
		"user_name":   user.Nickname,
		"user_avatar": user.Avatar,
		"content":     comment.Content,
		"like_count":  0,
		"created_at":  comment.CreatedAt.Format("2006-01-02T15:04:05Z07:00"),
	})
}

// filterContent 违禁词过滤（委托给包级共享函数 filterContentWithDB）
func (h *MomentHandler) filterContent(content string) (string, bool) {
	return filterContentWithDB(h.db, content)
}

// GetMyMoments 获取我发布的动态
func (h *MomentHandler) GetMyMoments(c *gin.Context) {
	user, err := h.getUserByUUID(c)
	if err != nil {
		response.Error(c, http.StatusUnauthorized, "请先登录")
		return
	}

	page, _ := strconv.Atoi(c.DefaultQuery("page", "1"))
	pageSize, _ := strconv.Atoi(c.DefaultQuery("page_size", "20"))
	offset := (page - 1) * pageSize

	var moments []models.Moment
	var total int64

	query := h.db.Model(&models.Moment{}).Where("user_id = ? AND status IN ?", user.ID, []int8{
		models.MomentStatusPending,
		models.MomentStatusNormal,
		models.MomentStatusHidden,
	})
	query.Count(&total)
	query.Order("created_at DESC").Offset(offset).Limit(pageSize).Find(&moments)

	// 获取点赞状态
	likedMap := make(map[uint64]bool)
	if len(moments) > 0 {
		momentIDs := make([]uint64, 0, len(moments))
		for _, m := range moments {
			momentIDs = append(momentIDs, m.ID)
		}
		var likes []models.MomentLike
		h.db.Where("user_id = ? AND moment_id IN ?", user.ID, momentIDs).Find(&likes)
		for _, l := range likes {
			likedMap[l.MomentID] = true
		}
	}

	// 构建响应
	items := make([]MomentListItem, 0, len(moments))
	for _, m := range moments {
		var mediaUrls []string
		if m.MediaUrls != nil {
			json.Unmarshal(m.MediaUrls, &mediaUrls)
		}
		if mediaUrls == nil {
			mediaUrls = []string{}
		}
		var topics []string
		if m.Topics != nil {
			json.Unmarshal(m.Topics, &topics)
		}
		if topics == nil {
			topics = []string{}
		}

		items = append(items, MomentListItem{
			ID:             m.ID,
			UUID:           m.UUID,
			UserID:         m.UserID,
			UserName:       user.Nickname,
			UserAvatar:     user.Avatar,
			Content:        m.Content,
			ContentType:    m.ContentType,
			MediaUrls:      mediaUrls,
			VideoThumbnail: m.VideoThumbnail,
			Topics:         topics,
			Visibility:     m.Visibility,
			Status:         m.Status,
			ReviewReason:   m.ReviewReason,
			LikeCount:      m.LikeCount,
			CommentCount:   m.CommentCount,
			ShareCount:     m.ShareCount,
			IsLiked:        likedMap[m.ID],
			Location:       m.Location,
			CreatedAt:      m.CreatedAt.Format("2006-01-02 15:04:05"),
		})
	}

	response.Success(c, gin.H{
		"list":  items,
		"total": total,
		"page":  page,
	})
}

// GetMyLikes 获取我点赞的动态
func (h *MomentHandler) GetMyLikes(c *gin.Context) {
	user, err := h.getUserByUUID(c)
	if err != nil {
		response.Error(c, http.StatusUnauthorized, "请先登录")
		return
	}

	page, _ := strconv.Atoi(c.DefaultQuery("page", "1"))
	pageSize, _ := strconv.Atoi(c.DefaultQuery("page_size", "20"))
	offset := (page - 1) * pageSize

	// 获取点赞记录
	var likes []models.MomentLike
	var total int64
	h.db.Model(&models.MomentLike{}).Where("user_id = ?", user.ID).Count(&total)
	h.db.Where("user_id = ?", user.ID).Order("created_at DESC").Offset(offset).Limit(pageSize).Find(&likes)

	momentIDs := make([]uint64, 0, len(likes))
	for _, l := range likes {
		momentIDs = append(momentIDs, l.MomentID)
	}

	var moments []models.Moment
	if len(momentIDs) > 0 {
		h.db.Where("id IN ? AND status = ?", momentIDs, models.MomentStatusNormal).Find(&moments)
	}

	// 获取用户信息
	userIDs := make([]uint64, 0, len(moments))
	for _, m := range moments {
		userIDs = append(userIDs, m.UserID)
	}
	userMap := make(map[uint64]*models.User)
	if len(userIDs) > 0 {
		var users []models.User
		h.db.Where("id IN ?", userIDs).Find(&users)
		for i := range users {
			userMap[users[i].ID] = &users[i]
		}
	}

	// 构建响应
	items := make([]MomentListItem, 0, len(moments))
	for _, m := range moments {
		var mediaUrls []string
		json.Unmarshal(m.MediaUrls, &mediaUrls)
		var topics []string
		json.Unmarshal(m.Topics, &topics)

		userName := ""
		userAvatar := ""
		if u, ok := userMap[m.UserID]; ok {
			userName = u.Nickname
			userAvatar = u.Avatar
		}

		items = append(items, MomentListItem{
			ID:             m.ID,
			UUID:           m.UUID,
			UserID:         m.UserID,
			UserName:       userName,
			UserAvatar:     userAvatar,
			Content:        m.Content,
			ContentType:    m.ContentType,
			MediaUrls:      mediaUrls,
			VideoThumbnail: m.VideoThumbnail,
			Topics:         topics,
			Visibility:     m.Visibility,
			LikeCount:      m.LikeCount,
			CommentCount:   m.CommentCount,
			ShareCount:     m.ShareCount,
			IsLiked:        true,
			Location:       m.Location,
			CreatedAt:      m.CreatedAt.Format("2006-01-02 15:04:05"),
		})
	}

	response.Success(c, gin.H{
		"list":  items,
		"total": total,
		"page":  page,
	})
}

// CommentItem 评论项
type CommentItem struct {
	ID          uint64  `json:"id"`
	UUID        string  `json:"uuid"`
	MomentID    uint64  `json:"moment_id"`
	MomentUUID  string  `json:"moment_uuid"`
	Content     string  `json:"content"`
	UserID      uint64  `json:"user_id"`
	UserName    string  `json:"user_name"`
	UserAvatar  string  `json:"user_avatar"`
	ParentID    *uint64 `json:"parent_id"`
	ReplyToID   *uint64 `json:"reply_to_id"`
	ReplyToName string  `json:"reply_to_name"`
	LikeCount   int     `json:"like_count"`
	CreatedAt   string  `json:"created_at"`
	MomentBrief string  `json:"moment_brief"` // 动态简介
	Type        string  `json:"type"`         // sent/received_reply/received_comment
}

// GetMyComments 获取我的评论相关
func (h *MomentHandler) GetMyComments(c *gin.Context) {
	user, err := h.getUserByUUID(c)
	if err != nil {
		response.Error(c, http.StatusUnauthorized, "请先登录")
		return
	}

	commentType := c.DefaultQuery("type", "all") // sent, received_reply, received_comment, all

	var comments []models.MomentComment
	var total int64

	switch commentType {
	case "sent":
		// 我发送的评论
		h.db.Model(&models.MomentComment{}).Where("user_id = ? AND status = 1", user.ID).Count(&total)
		h.db.Where("user_id = ? AND status = 1", user.ID).Order("created_at DESC").Limit(50).Find(&comments)
	case "received_reply":
		// 收到的回复（别人回复我的评论）
		var myCommentIDs []uint64
		h.db.Model(&models.MomentComment{}).Where("user_id = ?", user.ID).Pluck("id", &myCommentIDs)
		if len(myCommentIDs) > 0 {
			h.db.Model(&models.MomentComment{}).Where("parent_id IN ? AND user_id != ? AND status = 1", myCommentIDs, user.ID).Count(&total)
			h.db.Where("parent_id IN ? AND user_id != ? AND status = 1", myCommentIDs, user.ID).Order("created_at DESC").Limit(50).Find(&comments)
		}
	case "received_comment":
		// 收到的评论（别人评论我的动态）
		var myMomentIDs []uint64
		h.db.Model(&models.Moment{}).Where("user_id = ?", user.ID).Pluck("id", &myMomentIDs)
		if len(myMomentIDs) > 0 {
			h.db.Model(&models.MomentComment{}).Where("moment_id IN ? AND user_id != ? AND status = 1", myMomentIDs, user.ID).Count(&total)
			h.db.Where("moment_id IN ? AND user_id != ? AND status = 1", myMomentIDs, user.ID).Order("created_at DESC").Limit(50).Find(&comments)
		}
	default:
		// 全部（收到的回复 + 收到的评论）
		var myCommentIDs []uint64
		h.db.Model(&models.MomentComment{}).Where("user_id = ?", user.ID).Pluck("id", &myCommentIDs)
		var myMomentIDs []uint64
		h.db.Model(&models.Moment{}).Where("user_id = ?", user.ID).Pluck("id", &myMomentIDs)

		query := h.db.Model(&models.MomentComment{}).Where("status = 1")
		if len(myCommentIDs) > 0 && len(myMomentIDs) > 0 {
			query = query.Where("(parent_id IN ? OR moment_id IN ?) AND user_id != ?", myCommentIDs, myMomentIDs, user.ID)
		} else if len(myCommentIDs) > 0 {
			query = query.Where("parent_id IN ? AND user_id != ?", myCommentIDs, user.ID)
		} else if len(myMomentIDs) > 0 {
			query = query.Where("moment_id IN ? AND user_id != ?", myMomentIDs, user.ID)
		} else {
			response.Success(c, gin.H{"list": []CommentItem{}, "total": 0})
			return
		}
		query.Count(&total)
		query.Order("created_at DESC").Limit(50).Find(&comments)
	}

	// 获取用户信息
	userIDs := make([]uint64, 0, len(comments))
	momentIDs := make([]uint64, 0, len(comments))
	for _, cm := range comments {
		userIDs = append(userIDs, cm.UserID)
		momentIDs = append(momentIDs, cm.MomentID)
		if cm.ReplyToID != nil {
			userIDs = append(userIDs, *cm.ReplyToID)
		}
	}

	userMap := make(map[uint64]*models.User)
	if len(userIDs) > 0 {
		var users []models.User
		h.db.Where("id IN ?", userIDs).Find(&users)
		for i := range users {
			userMap[users[i].ID] = &users[i]
		}
	}

	momentMap := make(map[uint64]*models.Moment)
	if len(momentIDs) > 0 {
		var moments []models.Moment
		h.db.Where("id IN ?", momentIDs).Find(&moments)
		for i := range moments {
			momentMap[moments[i].ID] = &moments[i]
		}
	}

	// 构建响应
	items := make([]CommentItem, 0, len(comments))
	for _, cm := range comments {
		userName := ""
		userAvatar := ""
		if u, ok := userMap[cm.UserID]; ok {
			userName = u.Nickname
			userAvatar = u.Avatar
		}

		replyToName := ""
		if cm.ReplyToID != nil {
			if u, ok := userMap[*cm.ReplyToID]; ok {
				replyToName = u.Nickname
			}
		}

		momentBrief := ""
		momentUUID := ""
		if m, ok := momentMap[cm.MomentID]; ok {
			runes := []rune(m.Content)
			if len(runes) > 50 {
				momentBrief = string(runes[:50]) + "..."
			} else {
				momentBrief = m.Content
			}
			momentUUID = m.UUID
		}

		itemType := "received_comment"
		if cm.UserID == user.ID {
			itemType = "sent"
		} else if cm.ParentID != nil {
			itemType = "received_reply"
		}

		items = append(items, CommentItem{
			ID:          cm.ID,
			UUID:        cm.UUID,
			MomentID:    cm.MomentID,
			MomentUUID:  momentUUID,
			Content:     cm.Content,
			UserID:      cm.UserID,
			UserName:    userName,
			UserAvatar:  userAvatar,
			ParentID:    cm.ParentID,
			ReplyToID:   cm.ReplyToID,
			ReplyToName: replyToName,
			LikeCount:   cm.LikeCount,
			CreatedAt:   cm.CreatedAt.Format("2006-01-02 15:04:05"),
			MomentBrief: momentBrief,
			Type:        itemType,
		})
	}

	response.Success(c, gin.H{
		"list":  items,
		"total": total,
	})
}

// LikeNotificationItem 点赞通知项
type LikeNotificationItem struct {
	ID          uint64 `json:"id"`
	MomentID    uint64 `json:"moment_id"`
	MomentUUID  string `json:"moment_uuid"`
	UserID      uint64 `json:"user_id"`
	UserName    string `json:"user_name"`
	UserAvatar  string `json:"user_avatar"`
	MomentBrief string `json:"moment_brief"`
	CreatedAt   string `json:"created_at"`
	Type        string `json:"type"` // like
}

// GetReceivedLikes 获取收到的点赞
func (h *MomentHandler) GetReceivedLikes(c *gin.Context) {
	user, err := h.getUserByUUID(c)
	if err != nil {
		response.Error(c, http.StatusUnauthorized, "请先登录")
		return
	}

	// 获取我的动态ID
	var myMomentIDs []uint64
	h.db.Model(&models.Moment{}).Where("user_id = ?", user.ID).Pluck("id", &myMomentIDs)

	if len(myMomentIDs) == 0 {
		response.Success(c, gin.H{"list": []LikeNotificationItem{}, "total": 0})
		return
	}

	// 获取别人对我动态的点赞
	var likes []models.MomentLike
	var total int64
	h.db.Model(&models.MomentLike{}).Where("moment_id IN ? AND user_id != ?", myMomentIDs, user.ID).Count(&total)
	h.db.Where("moment_id IN ? AND user_id != ?", myMomentIDs, user.ID).Order("created_at DESC").Limit(50).Find(&likes)

	// 获取用户信息
	userIDs := make([]uint64, 0, len(likes))
	momentIDs := make([]uint64, 0, len(likes))
	for _, l := range likes {
		userIDs = append(userIDs, l.UserID)
		momentIDs = append(momentIDs, l.MomentID)
	}

	userMap := make(map[uint64]*models.User)
	if len(userIDs) > 0 {
		var users []models.User
		h.db.Where("id IN ?", userIDs).Find(&users)
		for i := range users {
			userMap[users[i].ID] = &users[i]
		}
	}

	momentMap := make(map[uint64]*models.Moment)
	if len(momentIDs) > 0 {
		var moments []models.Moment
		h.db.Where("id IN ?", momentIDs).Find(&moments)
		for i := range moments {
			momentMap[moments[i].ID] = &moments[i]
		}
	}

	// 构建响应
	items := make([]LikeNotificationItem, 0, len(likes))
	for _, l := range likes {
		userName := ""
		userAvatar := ""
		if u, ok := userMap[l.UserID]; ok {
			userName = u.Nickname
			userAvatar = u.Avatar
		}

		momentBrief := ""
		momentUUID := ""
		if m, ok := momentMap[l.MomentID]; ok {
			runes := []rune(m.Content)
			if len(runes) > 30 {
				momentBrief = string(runes[:30]) + "..."
			} else {
				momentBrief = m.Content
			}
			momentUUID = m.UUID
		}

		items = append(items, LikeNotificationItem{
			ID:          l.ID,
			MomentID:    l.MomentID,
			MomentUUID:  momentUUID,
			UserID:      l.UserID,
			UserName:    userName,
			UserAvatar:  userAvatar,
			MomentBrief: momentBrief,
			CreatedAt:   l.CreatedAt.Format("2006-01-02 15:04:05"),
			Type:        "like",
		})
	}

	response.Success(c, gin.H{
		"list":  items,
		"total": total,
	})
}

// SearchMoments 搜索动态
func (h *MomentHandler) SearchMoments(c *gin.Context) {
	keyword := c.Query("keyword")
	if keyword == "" {
		response.Error(c, http.StatusBadRequest, "请输入搜索关键词")
		return
	}

	page, _ := strconv.Atoi(c.DefaultQuery("page", "1"))
	pageSize, _ := strconv.Atoi(c.DefaultQuery("page_size", "20"))
	offset := (page - 1) * pageSize

	var moments []models.Moment
	var total int64

	query := h.db.Model(&models.Moment{}).
		Where("status = ? AND visibility = ?", models.MomentStatusNormal, models.VisibilityPublic).
		Where("content LIKE ? OR JSON_CONTAINS(topics, ?)", "%"+keyword+"%", `"`+keyword+`"`)

	query.Count(&total)
	query.Order("created_at DESC").Offset(offset).Limit(pageSize).Find(&moments)

	// 获取用户信息
	userIDs := make([]uint64, 0, len(moments))
	for _, m := range moments {
		userIDs = append(userIDs, m.UserID)
	}
	userMap := make(map[uint64]*models.User)
	if len(userIDs) > 0 {
		var users []models.User
		h.db.Where("id IN ?", userIDs).Find(&users)
		for i := range users {
			userMap[users[i].ID] = &users[i]
		}
	}

	// 构建响应
	items := make([]MomentListItem, 0, len(moments))
	for _, m := range moments {
		var mediaUrls []string
		json.Unmarshal(m.MediaUrls, &mediaUrls)
		var topics []string
		json.Unmarshal(m.Topics, &topics)

		userName := ""
		userAvatar := ""
		if u, ok := userMap[m.UserID]; ok {
			userName = u.Nickname
			userAvatar = u.Avatar
		}

		items = append(items, MomentListItem{
			ID:             m.ID,
			UUID:           m.UUID,
			UserID:         m.UserID,
			UserName:       userName,
			UserAvatar:     userAvatar,
			Content:        m.Content,
			ContentType:    m.ContentType,
			MediaUrls:      mediaUrls,
			VideoThumbnail: m.VideoThumbnail,
			Topics:         topics,
			Visibility:     m.Visibility,
			LikeCount:      m.LikeCount,
			CommentCount:   m.CommentCount,
			ShareCount:     m.ShareCount,
			IsLiked:        false,
			Location:       m.Location,
			CreatedAt:      m.CreatedAt.Format("2006-01-02 15:04:05"),
		})
	}

	response.Success(c, gin.H{
		"list":  items,
		"total": total,
		"page":  page,
	})
}

// BlockMoment 屏蔽动态
func (h *MomentHandler) BlockMoment(c *gin.Context) {
	momentID := c.Param("id")
	user, err := h.getUserByUUID(c)
	if err != nil {
		response.Error(c, http.StatusUnauthorized, "请先登录")
		return
	}

	// 检查动态是否存在
	var moment models.Moment
	if err := h.db.First(&moment, momentID).Error; err != nil {
		response.Error(c, http.StatusNotFound, "动态不存在")
		return
	}

	// 不能屏蔽自己的动态
	if moment.UserID == user.ID {
		response.Error(c, http.StatusBadRequest, "不能屏蔽自己的动态")
		return
	}

	// 创建屏蔽记录
	block := models.MomentBlock{
		UserID:   user.ID,
		MomentID: moment.ID,
	}

	// 使用 FirstOrCreate 避免重复
	if err := h.db.Where("user_id = ? AND moment_id = ?", user.ID, moment.ID).FirstOrCreate(&block).Error; err != nil {
		response.Error(c, http.StatusInternalServerError, "屏蔽失败")
		return
	}

	response.SuccessWithMessage(c, "已屏蔽此动态", nil)
}

// BlockUser 屏蔽用户动态
func (h *MomentHandler) BlockUser(c *gin.Context) {
	blockedUserID := c.Param("userId")
	user, err := h.getUserByUUID(c)
	if err != nil {
		response.Error(c, http.StatusUnauthorized, "请先登录")
		return
	}

	// 检查用户是否存在
	var blockedUser models.User
	if err := h.db.First(&blockedUser, blockedUserID).Error; err != nil {
		response.Error(c, http.StatusNotFound, "用户不存在")
		return
	}

	// 不能屏蔽自己
	if blockedUser.ID == user.ID {
		response.Error(c, http.StatusBadRequest, "不能屏蔽自己")
		return
	}

	// 创建屏蔽记录
	block := models.UserMomentBlock{
		UserID:        user.ID,
		BlockedUserID: blockedUser.ID,
	}

	// 使用 FirstOrCreate 避免重复
	if err := h.db.Where("user_id = ? AND blocked_user_id = ?", user.ID, blockedUser.ID).FirstOrCreate(&block).Error; err != nil {
		response.Error(c, http.StatusInternalServerError, "屏蔽失败")
		return
	}

	response.SuccessWithMessage(c, "已屏蔽此用户的动态", nil)
}
