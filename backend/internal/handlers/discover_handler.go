// 文件用途：实现后端 HTTP 接口的请求处理和统一响应。
// 核心逻辑：绑定参数，校验身份与权限，调用业务服务并持久化关键状态。

package handlers

import (
	"github.com/gin-gonic/gin"
	"gorm.io/gorm"
	"net/http"
	neturl "net/url"
	"strings"
	"genericim/internal/models"
	"genericim/pkg/response"
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

type discoverBannerRequest struct {
	Title    string `json:"title"`
	ImageURL string `json:"image_url"`
	URL      string `json:"url"`
	Sort     *int   `json:"sort"`
	Enabled  *bool  `json:"enabled"`
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

func (h *DiscoverHandler) GetAppDiscoverBanners(c *gin.Context) {
	var banners []models.DiscoverBanner
	if err := h.db.
		Where("enabled = ?", true).
		Order("sort ASC, created_at DESC, id DESC").
		Limit(5).
		Find(&banners).Error; err != nil {
		response.Error(c, http.StatusInternalServerError, "获取发现页轮播图失败")
		return
	}
	response.Success(c, banners)
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

func (h *DiscoverHandler) ListDiscoverBanners(c *gin.Context) {
	var banners []models.DiscoverBanner
	if err := h.db.
		Order("sort ASC, created_at DESC, id DESC").
		Find(&banners).Error; err != nil {
		response.Error(c, http.StatusInternalServerError, "获取发现页轮播图配置失败")
		return
	}
	response.Success(c, banners)
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

func (h *DiscoverHandler) CreateDiscoverBanner(c *gin.Context) {
	var req discoverBannerRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		response.BadRequest(c, "参数错误")
		return
	}

	banner, err := buildDiscoverBannerFromRequest(req, nil)
	if err != nil {
		response.Error(c, http.StatusBadRequest, err.Error())
		return
	}
	if err := h.db.Create(&banner).Error; err != nil {
		response.Error(c, http.StatusInternalServerError, "创建发现页轮播图失败")
		return
	}
	response.SuccessWithMessage(c, "创建成功", banner)
	h.broadcastDiscoverContentUpdated("banner_created", banner.ID, banner.Enabled)
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

func (h *DiscoverHandler) UpdateDiscoverBanner(c *gin.Context) {
	id := c.Param("id")

	var banner models.DiscoverBanner
	if err := h.db.First(&banner, id).Error; err != nil {
		response.Error(c, http.StatusNotFound, "发现页轮播图不存在")
		return
	}

	var req discoverBannerRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		response.BadRequest(c, "参数错误")
		return
	}

	updatedBanner, err := buildDiscoverBannerFromRequest(req, &banner)
	if err != nil {
		response.Error(c, http.StatusBadRequest, err.Error())
		return
	}
	updates := map[string]interface{}{
		"title":      updatedBanner.Title,
		"image_url":  updatedBanner.ImageURL,
		"url":        updatedBanner.URL,
		"sort":       updatedBanner.Sort,
		"enabled":    updatedBanner.Enabled,
		"updated_at": gorm.Expr("CURRENT_TIMESTAMP"),
	}
	if err := h.db.Model(&banner).Updates(updates).Error; err != nil {
		response.Error(c, http.StatusInternalServerError, "更新发现页轮播图失败")
		return
	}
	if err := h.db.First(&banner, id).Error; err != nil {
		response.Error(c, http.StatusInternalServerError, "刷新发现页轮播图失败")
		return
	}
	response.SuccessWithMessage(c, "更新成功", banner)
	h.broadcastDiscoverContentUpdated("banner_updated", banner.ID, banner.Enabled)
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

func (h *DiscoverHandler) DeleteDiscoverBanner(c *gin.Context) {
	id := c.Param("id")
	result := h.db.Delete(&models.DiscoverBanner{}, id)
	if result.Error != nil {
		response.Error(c, http.StatusInternalServerError, "删除发现页轮播图失败")
		return
	}
	if result.RowsAffected == 0 {
		response.Error(c, http.StatusNotFound, "发现页轮播图不存在")
		return
	}
	response.SuccessWithMessage(c, "删除成功", nil)
	h.broadcastDiscoverContentUpdated("banner_deleted", 0, false)
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

func (h *DiscoverHandler) broadcastDiscoverContentUpdated(action string, id uint64, enabled bool) {
	if h.hub == nil {
		return
	}
	payload := map[string]interface{}{
		"type":   "discover_items_updated",
		"action": action,
	}
	if id > 0 {
		payload["banner_id"] = id
		payload["enabled"] = enabled
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

func buildDiscoverBannerFromRequest(req discoverBannerRequest, existing *models.DiscoverBanner) (models.DiscoverBanner, error) {
	title := strings.TrimSpace(req.Title)
	if title == "" {
		return models.DiscoverBanner{}, simpleDiscoverError("请输入标题")
	}
	imageURL := strings.TrimSpace(req.ImageURL)
	if imageURL == "" {
		return models.DiscoverBanner{}, simpleDiscoverError("请上传轮播图片")
	}
	finalURL := ""
	if strings.TrimSpace(req.URL) != "" {
		normalizedURL, err := normalizeDiscoverURL(req.URL)
		if err != nil {
			return models.DiscoverBanner{}, err
		}
		finalURL = normalizedURL
	}
	banner := models.DiscoverBanner{
		Title:    title,
		ImageURL: imageURL,
		URL:      finalURL,
		Sort:     0,
		Enabled:  true,
	}
	if existing != nil {
		banner.ID = existing.ID
		banner.Sort = existing.Sort
		banner.Enabled = existing.Enabled
	}
	if req.Sort != nil {
		banner.Sort = *req.Sort
	}
	if req.Enabled != nil {
		banner.Enabled = *req.Enabled
	}
	return banner, nil
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
