// 文件用途：实现后端 HTTP 接口的请求处理和统一响应。
// 核心逻辑：绑定参数，校验身份与权限，调用业务服务并持久化关键状态。

package handlers

import (
	"encoding/json"
	"github.com/gin-gonic/gin"
	"gorm.io/gorm"
	"net/http"
	"strconv"
	"time"
	"genericim/internal/models"
	"genericim/pkg/response"
)

type MomentMgmtHandler struct {
	db *gorm.DB
}

func NewMomentMgmtHandler(db *gorm.DB) *MomentMgmtHandler {
	return &MomentMgmtHandler{db: db}
}

func getMomentStatusText(status int8) string {
	switch status {
	case models.MomentStatusPending:
		return "待审核"
	case models.MomentStatusNormal:
		return "正常"
	case models.MomentStatusHidden:
		return "隐藏"
	case models.MomentStatusDeleted:
		return "已删除"
	default:
		return "未知"
	}
}

// ==================== 动态管理 ====================

// AdminMomentItem 后台动态列表项
type AdminMomentItem struct {
	ID             uint64   `json:"id"`
	UUID           string   `json:"uuid"`
	UserID         uint64   `json:"user_id"`
	UserName       string   `json:"user_name"`
	UserAvatar     *string  `json:"user_avatar"`
	Content        string   `json:"content"`
	ContentType    int8     `json:"content_type"`
	MediaUrls      []string `json:"media_urls"`
	Topics         []string `json:"topics"`
	Visibility     int8     `json:"visibility"`
	Status         int8     `json:"status"`
	StatusText     string   `json:"status_text"`
	ReviewReason   string   `json:"review_reason,omitempty"`
	ReviewedBy     *uint64  `json:"reviewed_by,omitempty"`
	ReviewedByName string   `json:"reviewed_by_name,omitempty"`
	ReviewedAt     string   `json:"reviewed_at,omitempty"`
	LikeCount      int      `json:"like_count"`
	CommentCount   int      `json:"comment_count"`
	ViewCount      int      `json:"view_count"`
	CreatedAt      string   `json:"created_at"`
}

// ListMoments 获取所有动态列表（后台）
func (h *MomentMgmtHandler) ListMoments(c *gin.Context) {
	page, _ := strconv.Atoi(c.DefaultQuery("page", "1"))
	pageSize, _ := strconv.Atoi(c.DefaultQuery("page_size", "20"))
	keyword := c.Query("keyword")
	status := c.Query("status")
	userID := c.Query("user_id")
	onlyPending := c.DefaultQuery("only_pending", "false") == "true"
	withReviewReason := c.DefaultQuery("with_review_reason", "false") == "true"

	offset := (page - 1) * pageSize

	query := h.db.Model(&models.Moment{})

	// 关键词搜索
	if keyword != "" {
		query = query.Where("content LIKE ?", "%"+keyword+"%")
	}

	// 状态筛选
	if status != "" {
		query = query.Where("status = ?", status)
	}
	if onlyPending {
		query = query.Where("status = ?", models.MomentStatusPending)
	}
	if withReviewReason {
		query = query.Where("review_reason <> ''")
	}

	// 用户筛选
	if userID != "" {
		query = query.Where("user_id = ?", userID)
	}

	var total int64
	query.Count(&total)

	var moments []models.Moment
	orderExpr := "CASE WHEN status = 0 THEN 0 ELSE 1 END, created_at DESC"
	if err := query.Order(orderExpr).Offset(offset).Limit(pageSize).Find(&moments).Error; err != nil {
		response.Error(c, http.StatusInternalServerError, "查询失败")
		return
	}

	// 获取用户信息
	userIDs := make([]uint64, 0, len(moments))
	reviewerIDs := make([]uint64, 0, len(moments))
	for _, m := range moments {
		userIDs = append(userIDs, m.UserID)
		if m.ReviewedBy != nil {
			reviewerIDs = append(reviewerIDs, *m.ReviewedBy)
		}
	}

	var users []models.User
	if len(userIDs) > 0 {
		h.db.Where("id IN ?", userIDs).Find(&users)
	}
	userMap := make(map[uint64]models.User)
	for _, u := range users {
		userMap[u.ID] = u
	}
	adminMap := make(map[uint64]models.Admin)
	if len(reviewerIDs) > 0 {
		var admins []models.Admin
		h.db.Where("id IN ?", reviewerIDs).Find(&admins)
		for _, admin := range admins {
			adminMap[admin.ID] = admin
		}
	}

	// 构建响应
	result := make([]AdminMomentItem, 0, len(moments))
	for _, m := range moments {
		user := userMap[m.UserID]

		var mediaUrls []string
		var topics []string
		json.Unmarshal(m.MediaUrls, &mediaUrls)
		json.Unmarshal(m.Topics, &topics)
		item := AdminMomentItem{
			ID:           m.ID,
			UUID:         m.UUID,
			UserID:       m.UserID,
			UserName:     user.Nickname,
			Content:      m.Content,
			ContentType:  m.ContentType,
			MediaUrls:    mediaUrls,
			Topics:       topics,
			Visibility:   m.Visibility,
			Status:       m.Status,
			StatusText:   getMomentStatusText(m.Status),
			ReviewReason: m.ReviewReason,
			ReviewedBy:   m.ReviewedBy,
			LikeCount:    m.LikeCount,
			CommentCount: m.CommentCount,
			ViewCount:    m.ViewCount,
			CreatedAt:    m.CreatedAt.Format("2006-01-02 15:04:05"),
		}
		if m.ReviewedBy != nil {
			if admin, ok := adminMap[*m.ReviewedBy]; ok {
				item.ReviewedByName = admin.Nickname
				if item.ReviewedByName == "" {
					item.ReviewedByName = admin.Username
				}
			}
		}
		if m.ReviewedAt != nil {
			item.ReviewedAt = m.ReviewedAt.Format("2006-01-02 15:04:05")
		}
		if user.Avatar != "" {
			item.UserAvatar = &user.Avatar
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

// UpdateMomentStatus 更新动态状态（隐藏/恢复）
func (h *MomentMgmtHandler) UpdateMomentStatus(c *gin.Context) {

	momentID := c.Param("id")

	var req struct {
		Status int8   `json:"status" binding:"oneof=0 1 2 3"`
		Reason string `json:"reason"` // 处理原因
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
	moment.Status = req.Status
	adminIDValue, _ := c.Get("admin_id")
	if adminID, ok := adminIDValue.(uint64); ok {
		moment.ReviewedBy = &adminID
	}
	now := time.Now()
	moment.ReviewedAt = &now
	if req.Status == models.MomentStatusNormal {
		moment.ReviewReason = ""
	} else {
		moment.ReviewReason = req.Reason
	}
	h.db.Save(&moment)
	response.SuccessWithMessage(c, "更新成功", nil)
}

// DeleteMoment 删除动态（后台硬删除）
func (h *MomentMgmtHandler) DeleteMoment(c *gin.Context) {

	momentID := c.Param("id")

	// 删除相关数据
	h.db.Where("moment_id = ?", momentID).Delete(&models.MomentLike{})
	h.db.Where("moment_id = ?", momentID).Delete(&models.MomentComment{})
	h.db.Delete(&models.Moment{}, momentID)
	response.SuccessWithMessage(c, "删除成功", nil)
}

// ==================== 话题管理 ====================

// ListTopics 获取话题列表
func (h *MomentMgmtHandler) ListTopics(c *gin.Context) {
	page, _ := strconv.Atoi(c.DefaultQuery("page", "1"))
	pageSize, _ := strconv.Atoi(c.DefaultQuery("page_size", "20"))
	keyword := c.Query("keyword")
	offset := (page - 1) * pageSize

	query := h.db.Model(&models.Topic{})
	if keyword != "" {
		query = query.Where("name LIKE ?", "%"+keyword+"%")
	}

	var total int64
	query.Count(&total)

	var topics []models.Topic
	query.Order("sort DESC, post_count DESC").Offset(offset).Limit(pageSize).Find(&topics)
	response.Success(c, gin.H{
		"list":      topics,
		"total":     total,
		"page":      page,
		"page_size": pageSize,
	})
}

// CreateTopic 创建话题
func (h *MomentMgmtHandler) CreateTopic(c *gin.Context) {
	var req struct {
		Name        string `json:"name" binding:"required"`
		Description string `json:"description"`
		Icon        string `json:"icon"`
		CoverImage  string `json:"cover_image"`
		IsHot       bool   `json:"is_hot"`
		IsOfficial  bool   `json:"is_official"`
		Sort        int    `json:"sort"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		response.Error(c, http.StatusBadRequest, "参数错误")
		return
	}

	// 检查是否已存在
	var existing models.Topic
	if err := h.db.Where("name = ?", req.Name).First(&existing).Error; err == nil {
		response.Error(c, http.StatusBadRequest, "话题已存在")
		return
	}
	topic := models.Topic{
		Name:        req.Name,
		Description: req.Description,
		Icon:        req.Icon,
		CoverImage:  req.CoverImage,
		IsHot:       req.IsHot,
		IsOfficial:  req.IsOfficial,
		Sort:        req.Sort,
		Status:      1,
	}
	if err := h.db.Create(&topic).Error; err != nil {
		response.Error(c, http.StatusInternalServerError, "创建失败")
		return
	}
	response.Success(c, topic)
}

// UpdateTopic 更新话题
func (h *MomentMgmtHandler) UpdateTopic(c *gin.Context) {
	topicID := c.Param("id")

	var req struct {
		Name        *string `json:"name"`
		Description *string `json:"description"`
		Icon        *string `json:"icon"`
		CoverImage  *string `json:"cover_image"`
		IsHot       *bool   `json:"is_hot"`
		IsOfficial  *bool   `json:"is_official"`
		Status      *int8   `json:"status"`
		Sort        *int    `json:"sort"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		response.Error(c, http.StatusBadRequest, "参数错误")
		return
	}

	var topic models.Topic
	if err := h.db.First(&topic, topicID).Error; err != nil {
		response.Error(c, http.StatusNotFound, "话题不存在")
		return
	}
	updates := make(map[string]interface{})
	if req.Name != nil {
		updates["name"] = *req.Name
	}
	if req.Description != nil {
		updates["description"] = *req.Description
	}
	if req.Icon != nil {
		updates["icon"] = *req.Icon
	}
	if req.CoverImage != nil {
		updates["cover_image"] = *req.CoverImage
	}
	if req.IsHot != nil {
		updates["is_hot"] = *req.IsHot
	}
	if req.IsOfficial != nil {
		updates["is_official"] = *req.IsOfficial
	}
	if req.Status != nil {
		updates["status"] = *req.Status
	}
	if req.Sort != nil {
		updates["sort"] = *req.Sort
	}
	h.db.Model(&topic).Updates(updates)
	h.db.First(&topic, topicID)
	response.Success(c, topic)
}

// DeleteTopic 删除话题
func (h *MomentMgmtHandler) DeleteTopic(c *gin.Context) {
	topicID := c.Param("id")
	h.db.Delete(&models.Topic{}, topicID)
	response.SuccessWithMessage(c, "删除成功", nil)
}

// ==================== 违禁词管理 ====================

// ListBannedWords 获取违禁词列表
func (h *MomentMgmtHandler) ListBannedWords(c *gin.Context) {
	page, _ := strconv.Atoi(c.DefaultQuery("page", "1"))
	pageSize, _ := strconv.Atoi(c.DefaultQuery("page_size", "20"))
	keyword := c.Query("keyword")
	category := c.Query("category")
	offset := (page - 1) * pageSize

	query := h.db.Model(&models.BannedWord{})
	if keyword != "" {
		query = query.Where("word LIKE ?", "%"+keyword+"%")
	}
	if category != "" {
		query = query.Where("category = ?", category)
	}

	var total int64
	query.Count(&total)

	var words []models.BannedWord
	query.Order("created_at DESC").Offset(offset).Limit(pageSize).Find(&words)
	response.Success(c, gin.H{
		"list":      words,
		"total":     total,
		"page":      page,
		"page_size": pageSize,
	})
}

// CreateBannedWord 创建违禁词
func (h *MomentMgmtHandler) CreateBannedWord(c *gin.Context) {
	var req struct {
		Word        string `json:"word" binding:"required"`
		Category    string `json:"category"`
		Level       int8   `json:"level"`
		Replacement string `json:"replacement"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		response.Error(c, http.StatusBadRequest, "参数错误")
		return
	}

	// 默认分类和级别
	if req.Category == "" {
		req.Category = models.BannedCategoryOther
	}
	if req.Level == 0 {
		req.Level = models.BannedLevelFilter
	}

	// 检查是否已存在
	var existing models.BannedWord
	if err := h.db.Where("word = ?", req.Word).First(&existing).Error; err == nil {
		response.Error(c, http.StatusBadRequest, "违禁词已存在")
		return
	}
	word := models.BannedWord{
		Word:        req.Word,
		Category:    req.Category,
		Level:       req.Level,
		Replacement: req.Replacement,
		Status:      1,
	}
	if err := h.db.Create(&word).Error; err != nil {
		response.Error(c, http.StatusInternalServerError, "创建失败")
		return
	}
	response.Success(c, word)
}

// UpdateBannedWord 更新违禁词
func (h *MomentMgmtHandler) UpdateBannedWord(c *gin.Context) {
	wordID := c.Param("id")

	var req struct {
		Word        *string `json:"word"`
		Category    *string `json:"category"`
		Level       *int8   `json:"level"`
		Replacement *string `json:"replacement"`
		Status      *int8   `json:"status"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		response.Error(c, http.StatusBadRequest, "参数错误")
		return
	}

	var word models.BannedWord
	if err := h.db.First(&word, wordID).Error; err != nil {
		response.Error(c, http.StatusNotFound, "违禁词不存在")
		return
	}
	updates := make(map[string]interface{})
	if req.Word != nil {
		updates["word"] = *req.Word
	}
	if req.Category != nil {
		updates["category"] = *req.Category
	}
	if req.Level != nil {
		updates["level"] = *req.Level
	}
	if req.Replacement != nil {
		updates["replacement"] = *req.Replacement
	}
	if req.Status != nil {
		updates["status"] = *req.Status
	}
	h.db.Model(&word).Updates(updates)
	h.db.First(&word, wordID)
	response.Success(c, word)
}

// DeleteBannedWord 删除违禁词
func (h *MomentMgmtHandler) DeleteBannedWord(c *gin.Context) {
	wordID := c.Param("id")
	h.db.Delete(&models.BannedWord{}, wordID)
	response.SuccessWithMessage(c, "删除成功", nil)
}

// BatchCreateBannedWords 批量创建违禁词
func (h *MomentMgmtHandler) BatchCreateBannedWords(c *gin.Context) {
	var req struct {
		Words    []string `json:"words" binding:"required"`
		Category string   `json:"category"`
		Level    int8     `json:"level"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		response.Error(c, http.StatusBadRequest, "参数错误")
		return
	}
	if req.Category == "" {
		req.Category = models.BannedCategoryOther
	}
	if req.Level == 0 {
		req.Level = models.BannedLevelFilter
	}
	created := 0
	for _, w := range req.Words {
		if w == "" {
			continue
		}
		var existing models.BannedWord
		if h.db.Where("word = ?", w).First(&existing).Error == nil {
			continue
		}
		word := models.BannedWord{
			Word:     w,
			Category: req.Category,
			Level:    req.Level,
			Status:   1,
		}
		if h.db.Create(&word).Error == nil {
			created++
		}
	}
	response.SuccessWithMessage(c, "批量创建成功", gin.H{"created": created})
}

// GetMomentStats 获取动态统计
func (h *MomentMgmtHandler) GetMomentStats(c *gin.Context) {
	var totalMoments int64
	var todayMoments int64
	var totalComments int64
	var totalLikes int64

	h.db.Model(&models.Moment{}).Where("status = 1").Count(&totalMoments)
	h.db.Model(&models.Moment{}).
		Where("status = 1 AND created_at >= CURDATE() AND created_at < DATE_ADD(CURDATE(), INTERVAL 1 DAY)").
		Count(&todayMoments)
	h.db.Model(&models.MomentComment{}).Where("status = 1").Count(&totalComments)
	h.db.Model(&models.MomentLike{}).Count(&totalLikes)

	// 话题统计
	var totalTopics int64
	var hotTopics int64
	h.db.Model(&models.Topic{}).Where("status = 1").Count(&totalTopics)
	h.db.Model(&models.Topic{}).Where("status = 1 AND is_hot = 1").Count(&hotTopics)

	// 违禁词统计
	var totalBannedWords int64
	var totalHitCount int64
	h.db.Model(&models.BannedWord{}).Where("status = 1").Count(&totalBannedWords)
	h.db.Model(&models.BannedWord{}).Select("SUM(hit_count)").Scan(&totalHitCount)
	response.Success(c, gin.H{
		"moments": gin.H{
			"total":    totalMoments,
			"today":    todayMoments,
			"comments": totalComments,
			"likes":    totalLikes,
		},
		"topics": gin.H{
			"total": totalTopics,
			"hot":   hotTopics,
		},
		"banned_words": gin.H{
			"total":     totalBannedWords,
			"hit_count": totalHitCount,
		},
	})
}
