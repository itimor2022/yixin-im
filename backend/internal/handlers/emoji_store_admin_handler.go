// 文件用途：实现后端 HTTP 接口的请求处理和统一响应。
// 核心逻辑：绑定参数，校验身份与权限，调用业务服务并持久化关键状态。

package handlers

import (
	"errors"
	"github.com/gin-gonic/gin"
	"gorm.io/gorm"
	"net/http"
	"strconv"
	"strings"
	"time"
	"genericim/internal/models"
	"genericim/pkg/response"
)

type EmojiStoreAdminHandler struct {
	db *gorm.DB
}

func NewEmojiStoreAdminHandler(db *gorm.DB) *EmojiStoreAdminHandler {
	return &EmojiStoreAdminHandler{db: db}
}

func (h *EmojiStoreAdminHandler) ensureSeedCatalogIfEmpty() {
	seeds := defaultEmojiStoreCatalogSeeds()
	for i, seed := range seeds {
		var existing models.EmojiStorePackCatalog
		err := h.db.Where("pack_id = ?", seed.PackID).First(&existing).Error
		if err == nil {
			if existing.IsBuiltIn {
				_ = h.db.Model(&existing).Updates(map[string]interface{}{
					"name":          seed.Name,
					"description":   seed.Description,
					"preview_emoji": seed.PreviewEmoji,
					"preview_file":  seed.PreviewFile,
					"sticker_files": encodeJSON(seed.StickerFiles),
					"sort_order":    i + 1,
					"is_active":     true,
				}).Error
			}
			continue
		}
		if !errors.Is(err, gorm.ErrRecordNotFound) {
			continue
		}
		row := models.EmojiStorePackCatalog{
			PackID:       seed.PackID,
			Name:         seed.Name,
			Description:  seed.Description,
			PreviewEmoji: seed.PreviewEmoji,
			PreviewFile:  seed.PreviewFile,
			StickerFiles: encodeJSON(seed.StickerFiles),
			SortOrder:    i + 1,
			IsBuiltIn:    true,
			IsActive:     true,
		}
		_ = h.db.Create(&row).Error
	}
}

func (h *EmojiStoreAdminHandler) ListPacks(c *gin.Context) {
	h.ensureSeedCatalogIfEmpty()
	keyword := strings.TrimSpace(c.Query("keyword"))
	activeQuery := strings.TrimSpace(c.Query("is_active"))
	query := h.db.Model(&models.EmojiStorePackCatalog{})
	if keyword != "" {
		like := "%" + keyword + "%"
		query = query.Where("pack_id LIKE ? OR name LIKE ? OR description LIKE ?", like, like, like)
	}
	if activeQuery != "" {
		if active, err := strconv.ParseBool(activeQuery); err == nil {
			query = query.Where("is_active = ?", active)
		}
	}

	var total int64
	if err := query.Count(&total).Error; err != nil {
		response.Error(c, http.StatusInternalServerError, "获取表情包失败")
		return
	}

	var rows []models.EmojiStorePackCatalog
	if err := query.Order("sort_order ASC, id ASC").Find(&rows).Error; err != nil {
		response.Error(c, http.StatusInternalServerError, "获取表情包失败")
		return
	}
	list := make([]gin.H, 0, len(rows))
	for _, row := range rows {
		id := trimAndClampRunes(row.PackID, emojiStoreMaxPackIDRunes)
		name := trimAndClampRunes(row.Name, emojiStoreMaxPackNameRunes)
		if id == "" || name == "" {
			continue
		}
		description := trimAndClampRunes(row.Description, emojiStoreMaxPackDescRunes)
		previewEmoji := trimAndClampRunes(row.PreviewEmoji, 16)
		previewFile := trimAndClampRunes(row.PreviewFile, emojiStoreMaxPackIDRunes)
		files := sanitizeStringList(
			interfaceSliceToStringSlice(decodeJSONList(row.StickerFiles)),
			emojiStoreMaxStickerFiles,
			emojiStoreMaxPackIDRunes,
			nil,
		)
		if len(files) == 0 {
			continue
		}
		if previewFile == "" {
			previewFile = files[0]
		}

		list = append(list, gin.H{
			"id":            row.ID,
			"pack_id":       id,
			"name":          name,
			"description":   description,
			"preview_emoji": previewEmoji,
			"preview_file":  previewFile,
			"sticker_files": files,
			"sort_order":    row.SortOrder,
			"is_built_in":   row.IsBuiltIn,
			"is_active":     row.IsActive,
			"created_at":    row.CreatedAt,
			"updated_at":    row.UpdatedAt,
		})
	}
	response.Success(c, gin.H{
		"list":  list,
		"total": total,
	})
}

type saveEmojiStorePackRequest struct {
	PackID       string   `json:"pack_id"`
	Name         string   `json:"name"`
	Description  string   `json:"description"`
	PreviewEmoji string   `json:"preview_emoji"`
	PreviewFile  string   `json:"preview_file"`
	StickerFiles []string `json:"sticker_files"`
	SortOrder    int      `json:"sort_order"`
	IsBuiltIn    bool     `json:"is_built_in"`
	IsActive     *bool    `json:"is_active"`
}

func sanitizePackSaveRequest(req saveEmojiStorePackRequest) (saveEmojiStorePackRequest, error) {
	req.PackID = trimAndClampRunes(req.PackID, emojiStoreMaxPackIDRunes)
	req.Name = trimAndClampRunes(req.Name, emojiStoreMaxPackNameRunes)
	req.Description = trimAndClampRunes(req.Description, emojiStoreMaxPackDescRunes)
	req.PreviewEmoji = trimAndClampRunes(req.PreviewEmoji, 16)
	req.PreviewFile = trimAndClampRunes(req.PreviewFile, emojiStoreMaxPackIDRunes)
	req.StickerFiles = sanitizeStringList(
		req.StickerFiles,
		emojiStoreMaxStickerFiles,
		emojiStoreMaxPackIDRunes,
		nil,
	)
	if req.PackID == "" {
		return req, gorm.ErrInvalidData
	}
	if req.Name == "" {
		return req, gorm.ErrInvalidData
	}
	if len(req.StickerFiles) == 0 {
		return req, gorm.ErrInvalidData
	}
	if req.PreviewFile == "" {
		req.PreviewFile = req.StickerFiles[0]
	}
	return req, nil
}

func (h *EmojiStoreAdminHandler) CreatePack(c *gin.Context) {
	var req saveEmojiStorePackRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		response.Error(c, http.StatusBadRequest, "参数错误")
		return
	}
	req, err := sanitizePackSaveRequest(req)
	if err != nil {
		response.Error(c, http.StatusBadRequest, "请完善表情包信息")
		return
	}
	now := time.Now()
	isActive := true
	if req.IsActive != nil {
		isActive = *req.IsActive
	}
	row := models.EmojiStorePackCatalog{
		PackID:       req.PackID,
		Name:         req.Name,
		Description:  req.Description,
		PreviewEmoji: req.PreviewEmoji,
		PreviewFile:  req.PreviewFile,
		StickerFiles: encodeJSON(req.StickerFiles),
		SortOrder:    req.SortOrder,
		IsBuiltIn:    req.IsBuiltIn,
		IsActive:     isActive,
		CreatedAt:    now,
		UpdatedAt:    now,
	}
	if err := h.db.Create(&row).Error; err != nil {
		response.Error(c, http.StatusBadRequest, "创建失败，pack_id 可能已存在")
		return
	}
	response.Success(c, row)
}

func (h *EmojiStoreAdminHandler) UpdatePack(c *gin.Context) {
	id := c.Param("id")
	var row models.EmojiStorePackCatalog
	if err := h.db.First(&row, id).Error; err != nil {
		response.Error(c, http.StatusNotFound, "表情包不存在")
		return
	}

	var req saveEmojiStorePackRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		response.Error(c, http.StatusBadRequest, "参数错误")
		return
	}
	req, err := sanitizePackSaveRequest(req)
	if err != nil {
		response.Error(c, http.StatusBadRequest, "请完善表情包信息")
		return
	}
	updates := map[string]interface{}{
		"pack_id":       req.PackID,
		"name":          req.Name,
		"description":   req.Description,
		"preview_emoji": req.PreviewEmoji,
		"preview_file":  req.PreviewFile,
		"sticker_files": encodeJSON(req.StickerFiles),
		"sort_order":    req.SortOrder,
		"is_built_in":   req.IsBuiltIn,
		"updated_at":    time.Now(),
	}
	if req.IsActive != nil {
		updates["is_active"] = *req.IsActive
	}
	if err := h.db.Model(&models.EmojiStorePackCatalog{}).Where("id = ?", row.ID).Updates(updates).Error; err != nil {
		response.Error(c, http.StatusBadRequest, "更新失败，pack_id 可能已存在")
		return
	}

	var latest models.EmojiStorePackCatalog
	_ = h.db.First(&latest, row.ID).Error
	response.Success(c, latest)
}

func (h *EmojiStoreAdminHandler) SetPackActive(c *gin.Context) {
	id := c.Param("id")
	var req struct {
		IsActive bool `json:"is_active"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		response.Error(c, http.StatusBadRequest, "参数错误")
		return
	}
	if err := h.db.Model(&models.EmojiStorePackCatalog{}).Where("id = ?", id).Updates(map[string]interface{}{
		"is_active":  req.IsActive,
		"updated_at": time.Now(),
	}).Error; err != nil {
		response.Error(c, http.StatusInternalServerError, "更新失败")
		return
	}
	response.Success(c, gin.H{"id": id, "is_active": req.IsActive})
}

func (h *EmojiStoreAdminHandler) DeletePack(c *gin.Context) {
	id := c.Param("id")
	result := h.db.Delete(&models.EmojiStorePackCatalog{}, id)
	if result.Error != nil {
		response.Error(c, http.StatusInternalServerError, "删除失败")
		return
	}
	if result.RowsAffected == 0 {
		response.Error(c, http.StatusNotFound, "表情包不存在")
		return
	}
	response.Success(c, gin.H{"id": id})
}
