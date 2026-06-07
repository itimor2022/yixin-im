package handlers

import (
	"strconv"
	"time"

	"gaoranim/internal/models"
	"gaoranim/pkg/response"

	"github.com/gin-gonic/gin"
	"gorm.io/gorm"
)

// PopupAnnouncementHandler 启动弹窗公告处理器
type PopupAnnouncementHandler struct {
	db *gorm.DB
}

func NewPopupAnnouncementHandler(db *gorm.DB) *PopupAnnouncementHandler {
	return &PopupAnnouncementHandler{db: db}
}

type popupAnnouncementRequest struct {
	Title    string `json:"title"`
	Content  string `json:"content"`
	ImageURL string `json:"image_url"`
	LinkURL  string `json:"link_url"`
	Enabled  *bool  `json:"enabled"`
}

// GetActivePopupAnnouncement 用户端：取当前启用的最新一条公告
func (h *PopupAnnouncementHandler) GetActivePopupAnnouncement(c *gin.Context) {
	var item models.PopupAnnouncement
	err := h.db.Where("enabled = 1").Order("id DESC").First(&item).Error
	if err != nil {
		// 没有启用的公告，返回空对象（前端据此不弹）
		response.Success(c, nil)
		return
	}
	response.Success(c, item)
}

// AdminListPopupAnnouncements 后台：分页列表
func (h *PopupAnnouncementHandler) AdminListPopupAnnouncements(c *gin.Context) {
	page, _ := strconv.Atoi(c.DefaultQuery("page", "1"))
	pageSize, _ := strconv.Atoi(c.DefaultQuery("page_size", "20"))
	if page < 1 {
		page = 1
	}
	if pageSize < 1 || pageSize > 200 {
		pageSize = 20
	}

	q := h.db.Model(&models.PopupAnnouncement{})
	var total int64
	q.Count(&total)

	var rows []models.PopupAnnouncement
	q.Order("id DESC").Offset((page - 1) * pageSize).Limit(pageSize).Find(&rows)

	response.SuccessWithPage(c, rows, total, page, pageSize)
}

// AdminCreatePopupAnnouncement 后台：新建
func (h *PopupAnnouncementHandler) AdminCreatePopupAnnouncement(c *gin.Context) {
	var req popupAnnouncementRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		response.BadRequest(c, "参数错误")
		return
	}
	if req.Content == "" {
		response.BadRequest(c, "公告内容不能为空")
		return
	}

	now := time.Now()
	item := models.PopupAnnouncement{
		Title:     req.Title,
		Content:   req.Content,
		ImageURL:  req.ImageURL,
		LinkURL:   req.LinkURL,
		Enabled:   0,
		CreatedAt: now,
		UpdatedAt: now,
	}
	if req.Enabled != nil && *req.Enabled {
		item.Enabled = 1
	}

	if err := h.db.Select("Title", "Content", "ImageURL", "LinkURL", "Enabled", "CreatedAt", "UpdatedAt").
		Create(&item).Error; err != nil {
		response.ServerError(c, "创建失败")
		return
	}
	response.Success(c, item)
}

// AdminUpdatePopupAnnouncement 后台：更新
func (h *PopupAnnouncementHandler) AdminUpdatePopupAnnouncement(c *gin.Context) {
	id, _ := strconv.ParseUint(c.Param("id"), 10, 64)
	var item models.PopupAnnouncement
	if err := h.db.First(&item, id).Error; err != nil {
		response.NotFound(c, "公告不存在")
		return
	}

	var req popupAnnouncementRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		response.BadRequest(c, "参数错误")
		return
	}

	updates := map[string]interface{}{
		"title":      req.Title,
		"content":    req.Content,
		"image_url":  req.ImageURL,
		"link_url":   req.LinkURL,
		"updated_at": time.Now(),
	}
	if req.Enabled != nil {
		if *req.Enabled {
			updates["enabled"] = 1
		} else {
			updates["enabled"] = 0
		}
	}

	if err := h.db.Model(&item).Updates(updates).Error; err != nil {
		response.ServerError(c, "更新失败")
		return
	}
	response.Success(c, item)
}

// AdminDeletePopupAnnouncement 后台：删除
func (h *PopupAnnouncementHandler) AdminDeletePopupAnnouncement(c *gin.Context) {
	id, _ := strconv.ParseUint(c.Param("id"), 10, 64)
	if err := h.db.Delete(&models.PopupAnnouncement{}, id).Error; err != nil {
		response.ServerError(c, "删除失败")
		return
	}
	response.Success(c, nil)
}
