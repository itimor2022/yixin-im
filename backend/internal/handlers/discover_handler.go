package handlers

import (
	"net/http"
	neturl "net/url"
	"strings"

	"gaoranim/internal/models"
	"gaoranim/pkg/response"

	"github.com/gin-gonic/gin"
	"gorm.io/gorm"
)

type DiscoverWebSocketHub interface {
	SendToAll(data interface{})
}

type DiscoverHandler struct {
	db  *gorm.DB
	hub DiscoverWebSocketHub
}

func NewDiscoverHandler(db *gorm.DB, hub DiscoverWebSocketHub) *DiscoverHandler {
	return &DiscoverHandler{db: db, hub: hub}
}

type discoverItemRequest struct {
	Title   string `json:"title"`
	IconURL string `json:"icon_url"`
	URL     string `json:"url"`
	Sort    *int   `json:"sort"`
	Enabled *bool  `json:"enabled"`
}

func (h *DiscoverHandler) GetAppDiscoverItems(c *gin.Context) {
	var items []models.DiscoverItem
	if err := h.db.
		Where("enabled = ?", true).
		Order("sort ASC, created_at DESC, id DESC").
		Find(&items).Error; err != nil {
		response.Error(c, http.StatusInternalServerError, "获取发现页入口失败")
		return
	}

	response.Success(c, items)
}

func (h *DiscoverHandler) ListDiscoverItems(c *gin.Context) {
	var items []models.DiscoverItem
	if err := h.db.
		Order("sort ASC, created_at DESC, id DESC").
		Find(&items).Error; err != nil {
		response.Error(c, http.StatusInternalServerError, "获取发现页配置失败")
		return
	}

	response.Success(c, items)
}

func (h *DiscoverHandler) CreateDiscoverItem(c *gin.Context) {
	var req discoverItemRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		response.BadRequest(c, "参数错误")
		return
	}

	item, err := buildDiscoverItemFromRequest(req, nil)
	if err != nil {
		response.Error(c, http.StatusBadRequest, err.Error())
		return
	}

	if err := h.db.Create(&item).Error; err != nil {
		response.Error(c, http.StatusInternalServerError, "创建发现页入口失败")
		return
	}

	response.SuccessWithMessage(c, "创建成功", item)
	h.broadcastDiscoverItemsUpdated("created", &item)
}

func (h *DiscoverHandler) UpdateDiscoverItem(c *gin.Context) {
	id := c.Param("id")

	var item models.DiscoverItem
	if err := h.db.First(&item, id).Error; err != nil {
		response.Error(c, http.StatusNotFound, "发现页入口不存在")
		return
	}

	var req discoverItemRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		response.BadRequest(c, "参数错误")
		return
	}

	updatedItem, err := buildDiscoverItemFromRequest(req, &item)
	if err != nil {
		response.Error(c, http.StatusBadRequest, err.Error())
		return
	}

	updates := map[string]interface{}{
		"title":      updatedItem.Title,
		"icon_url":   updatedItem.IconURL,
		"url":        updatedItem.URL,
		"sort":       updatedItem.Sort,
		"enabled":    updatedItem.Enabled,
		"updated_at": gorm.Expr("CURRENT_TIMESTAMP"),
	}

	if err := h.db.Model(&item).Updates(updates).Error; err != nil {
		response.Error(c, http.StatusInternalServerError, "更新发现页入口失败")
		return
	}

	if err := h.db.First(&item, id).Error; err != nil {
		response.Error(c, http.StatusInternalServerError, "刷新发现页入口失败")
		return
	}

	response.SuccessWithMessage(c, "更新成功", item)
	h.broadcastDiscoverItemsUpdated("updated", &item)
}

func (h *DiscoverHandler) DeleteDiscoverItem(c *gin.Context) {
	id := c.Param("id")

	result := h.db.Delete(&models.DiscoverItem{}, id)
	if result.Error != nil {
		response.Error(c, http.StatusInternalServerError, "删除发现页入口失败")
		return
	}
	if result.RowsAffected == 0 {
		response.Error(c, http.StatusNotFound, "发现页入口不存在")
		return
	}

	response.SuccessWithMessage(c, "删除成功", nil)
	h.broadcastDiscoverItemsUpdated("deleted", nil)
}

func (h *DiscoverHandler) broadcastDiscoverItemsUpdated(action string, item *models.DiscoverItem) {
	if h.hub == nil {
		return
	}

	payload := map[string]interface{}{
		"type":   "discover_items_updated",
		"action": action,
	}
	if item != nil {
		payload["item_id"] = item.ID
		payload["enabled"] = item.Enabled
	}

	h.hub.SendToAll(payload)
}

func buildDiscoverItemFromRequest(req discoverItemRequest, existing *models.DiscoverItem) (models.DiscoverItem, error) {
	title := strings.TrimSpace(req.Title)
	if title == "" {
		return models.DiscoverItem{}, simpleDiscoverError("请输入标题")
	}

	finalURL, err := normalizeDiscoverURL(req.URL)
	if err != nil {
		return models.DiscoverItem{}, err
	}

	item := models.DiscoverItem{
		Title:   title,
		IconURL: strings.TrimSpace(req.IconURL),
		URL:     finalURL,
		Sort:    0,
		Enabled: true,
	}
	if existing != nil {
		item.ID = existing.ID
		item.Sort = existing.Sort
		item.Enabled = existing.Enabled
	}
	if req.Sort != nil {
		item.Sort = *req.Sort
	}
	if req.Enabled != nil {
		item.Enabled = *req.Enabled
	}

	return item, nil
}

func normalizeDiscoverURL(raw string) (string, error) {
	urlText := strings.TrimSpace(raw)
	if urlText == "" {
		return "", errDiscoverURLRequired()
	}

	if !strings.HasPrefix(urlText, "http://") && !strings.HasPrefix(urlText, "https://") {
		urlText = "https://" + urlText
	}

	parsed, err := neturl.ParseRequestURI(urlText)
	if err != nil || parsed.Host == "" {
		return "", errDiscoverURLInvalid()
	}
	if parsed.Scheme != "http" && parsed.Scheme != "https" {
		return "", errDiscoverURLInvalid()
	}

	return parsed.String(), nil
}

func errDiscoverURLRequired() error {
	return simpleDiscoverError("请输入访问网址")
}

func errDiscoverURLInvalid() error {
	return simpleDiscoverError("请输入有效的 http/https 网址")
}

type simpleDiscoverError string

func (e simpleDiscoverError) Error() string {
	return string(e)
}
