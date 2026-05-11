package handlers

import (
	"fmt"
	"io"
	"net/http"
	"os"
	"path/filepath"
	"strings"
	"time"

	"gaoranim/internal/models"
	"gaoranim/pkg/response"

	"github.com/gin-gonic/gin"
	"github.com/google/uuid"
	"gorm.io/gorm"
)

// UploadHandler 文件上传处理
type UploadHandler struct {
	db        *gorm.DB
	uploadDir string
	baseURL   string
}

func NewUploadHandler(db *gorm.DB, uploadDir, baseURL string) *UploadHandler {
	// 确保上传目录存在
	os.MkdirAll(uploadDir, 0755)
	os.MkdirAll(filepath.Join(uploadDir, "images"), 0755)
	os.MkdirAll(filepath.Join(uploadDir, "videos"), 0755)
	os.MkdirAll(filepath.Join(uploadDir, "avatars"), 0755)
	os.MkdirAll(filepath.Join(uploadDir, "discover"), 0755)
	os.MkdirAll(filepath.Join(uploadDir, "voices"), 0755)
	os.MkdirAll(filepath.Join(uploadDir, "files"), 0755)

	// 去掉末尾斜杠，保证 baseURL+"/uploads/..." 格式正确
	baseURL = strings.TrimRight(baseURL, "/")

	return &UploadHandler{
		db:        db,
		uploadDir: uploadDir,
		baseURL:   baseURL,
	}
}

// mediaURL 将相对路径拼成完整访问 URL；baseURL 为空时返回相对路径（保持向后兼容）
func (h *UploadHandler) mediaURL(relativePath string) string {
	if h.baseURL == "" {
		return relativePath
	}
	return h.baseURL + relativePath
}

func (h *UploadHandler) setMediaHeaders(c *gin.Context) {
	if strings.HasPrefix(h.baseURL, "https://") {
		c.Header("Cross-Origin-Resource-Policy", "cross-origin")
	}
	c.Header("Cache-Control", "public, max-age=31536000, immutable")
}

// 允许的图片类型
var allowedImageTypes = map[string]bool{
	"image/jpeg":               true,
	"image/jpg":                true,
	"image/png":                true,
	"image/gif":                true,
	"image/webp":               true,
	"image/heic":               true, // iOS Live Photo
	"image/heif":               true, // iOS Live Photo
	"application/octet-stream": true, // 某些情况下 HEIC 会被识别为此类型
}

// 允许的视频类型
var allowedVideoTypes = map[string]bool{
	"video/mp4":       true,
	"video/quicktime": true,
	"video/x-msvideo": true,
	"video/webm":      true,
}

// 允许的音频类型
var allowedAudioTypes = map[string]bool{
	"audio/mpeg":               true, // mp3
	"audio/mp4":                true, // m4a
	"audio/x-m4a":              true, // m4a
	"audio/aac":                true, // aac
	"audio/wav":                true, // wav
	"audio/ogg":                true, // ogg
	"audio/webm":               true, // webm audio
	"application/octet-stream": true, // 某些情况下会被识别为此类型
}

// UploadDiscoverIcon 上传发现页图标
func (h *UploadHandler) UploadDiscoverIcon(c *gin.Context) {
	file, header, err := c.Request.FormFile("file")
	if err != nil {
		response.Error(c, http.StatusBadRequest, "请选择图片")
		return
	}
	defer file.Close()

	contentType := header.Header.Get("Content-Type")
	if !allowedImageTypes[contentType] {
		response.Error(c, http.StatusBadRequest, "不支持的图片格式")
		return
	}

	// 发现页图标限制 5MB
	if header.Size > 5*1024*1024 {
		response.Error(c, http.StatusBadRequest, "图标大小不能超过5MB")
		return
	}

	ext := filepath.Ext(header.Filename)
	if ext == "" {
		ext = ".png"
	}
	filename := fmt.Sprintf("discover_%s_%d%s", uuid.New().String()[:8], time.Now().UnixMilli(), ext)

	dateDir := time.Now().Format("2006/01/02")
	saveDir := filepath.Join(h.uploadDir, "discover", dateDir)
	os.MkdirAll(saveDir, 0755)

	savePath := filepath.Join(saveDir, filename)
	out, err := os.Create(savePath)
	if err != nil {
		response.Error(c, http.StatusInternalServerError, "保存图标失败")
		return
	}
	defer out.Close()

	if _, err := io.Copy(out, file); err != nil {
		response.Error(c, http.StatusInternalServerError, "保存图标失败")
		return
	}

	url := h.mediaURL(fmt.Sprintf("/uploads/discover/%s/%s", dateDir, filename))

	response.Success(c, gin.H{
		"url":      url,
		"filename": filename,
		"size":     header.Size,
		"type":     "discover_icon",
	})
}

// UploadImage 上传图片
func (h *UploadHandler) UploadImage(c *gin.Context) {
	file, header, err := c.Request.FormFile("file")
	if err != nil {
		response.Error(c, http.StatusBadRequest, "请选择文件")
		return
	}
	defer file.Close()

	// 检查文件类型
	contentType := header.Header.Get("Content-Type")
	if !allowedImageTypes[contentType] {
		response.Error(c, http.StatusBadRequest, "不支持的图片格式")
		return
	}

	// 获取用户ID并检查会员上传限制
	userUUID := c.GetString("user_id")
	var user models.User
	if err := h.db.Where("uuid = ?", userUUID).First(&user).Error; err != nil {
		response.Error(c, http.StatusUnauthorized, "用户未登录")
		return
	}

	// 检查文件大小
	maxSize := getUploadLimitBytes(h.db, user.ID, "image")
	if header.Size > maxSize {
		response.Error(c, http.StatusBadRequest, fmt.Sprintf("图片大小不能超过%dMB", maxSize/1024/1024))
		return
	}

	// 生成文件名
	ext := filepath.Ext(header.Filename)
	if ext == "" {
		ext = ".jpg"
	}
	filename := fmt.Sprintf("%s_%d%s", uuid.New().String()[:8], time.Now().UnixMilli(), ext)

	// 按日期分目录
	dateDir := time.Now().Format("2006/01/02")
	saveDir := filepath.Join(h.uploadDir, "images", dateDir)
	os.MkdirAll(saveDir, 0755)

	savePath := filepath.Join(saveDir, filename)

	// 保存文件
	out, err := os.Create(savePath)
	if err != nil {
		response.Error(c, http.StatusInternalServerError, "保存文件失败")
		return
	}
	defer out.Close()

	if _, err := io.Copy(out, file); err != nil {
		response.Error(c, http.StatusInternalServerError, "保存文件失败")
		return
	}

	// 返回相对路径（前端根据平台拼接 host）
	url := h.mediaURL(fmt.Sprintf("/uploads/images/%s/%s", dateDir, filename))

	response.Success(c, gin.H{
		"url":      url,
		"filename": filename,
		"size":     header.Size,
		"type":     "image",
	})
}

// UploadVideo 上传视频
func (h *UploadHandler) UploadVideo(c *gin.Context) {
	file, header, err := c.Request.FormFile("file")
	if err != nil {
		response.Error(c, http.StatusBadRequest, "请选择文件")
		return
	}
	defer file.Close()

	// 检查文件类型
	contentType := header.Header.Get("Content-Type")
	if !allowedVideoTypes[contentType] {
		response.Error(c, http.StatusBadRequest, "不支持的视频格式")
		return
	}

	// 获取用户ID并检查会员上传限制
	userUUID := c.GetString("user_id")
	var user models.User
	if err := h.db.Where("uuid = ?", userUUID).First(&user).Error; err != nil {
		response.Error(c, http.StatusUnauthorized, "用户未登录")
		return
	}

	// 检查文件大小
	maxSize := getUploadLimitBytes(h.db, user.ID, "video")
	if header.Size > maxSize {
		response.Error(c, http.StatusBadRequest, fmt.Sprintf("视频大小不能超过%dMB", maxSize/1024/1024))
		return
	}

	// 生成文件名
	ext := filepath.Ext(header.Filename)
	if ext == "" {
		ext = ".mp4"
	}
	filename := fmt.Sprintf("%s_%d%s", uuid.New().String()[:8], time.Now().UnixMilli(), ext)

	// 按日期分目录
	dateDir := time.Now().Format("2006/01/02")
	saveDir := filepath.Join(h.uploadDir, "videos", dateDir)
	os.MkdirAll(saveDir, 0755)

	savePath := filepath.Join(saveDir, filename)

	// 保存文件
	out, err := os.Create(savePath)
	if err != nil {
		response.Error(c, http.StatusInternalServerError, "保存文件失败")
		return
	}
	defer out.Close()

	if _, err := io.Copy(out, file); err != nil {
		response.Error(c, http.StatusInternalServerError, "保存文件失败")
		return
	}

	// 返回相对路径
	url := h.mediaURL(fmt.Sprintf("/uploads/videos/%s/%s", dateDir, filename))

	response.Success(c, gin.H{
		"url":      url,
		"filename": filename,
		"size":     header.Size,
		"type":     "video",
	})
}

// UploadAvatar 上传头像
func (h *UploadHandler) UploadAvatar(c *gin.Context) {
	file, header, err := c.Request.FormFile("file")
	if err != nil {
		response.Error(c, http.StatusBadRequest, "请选择文件")
		return
	}
	defer file.Close()

	// 检查文件类型
	contentType := header.Header.Get("Content-Type")
	if !allowedImageTypes[contentType] {
		response.Error(c, http.StatusBadRequest, "不支持的图片格式")
		return
	}

	// 检查文件大小 (最大 5MB)
	if header.Size > 5*1024*1024 {
		response.Error(c, http.StatusBadRequest, "头像大小不能超过5MB")
		return
	}

	// 获取用户ID
	userID, _ := c.Get("user_id")
	uid, _ := userID.(uint64)

	// 生成文件名
	ext := filepath.Ext(header.Filename)
	if ext == "" {
		ext = ".jpg"
	}
	filename := fmt.Sprintf("avatar_%d_%d%s", uid, time.Now().UnixMilli(), ext)

	savePath := filepath.Join(h.uploadDir, "avatars", filename)

	// 保存文件
	out, err := os.Create(savePath)
	if err != nil {
		response.Error(c, http.StatusInternalServerError, "保存文件失败")
		return
	}
	defer out.Close()

	if _, err := io.Copy(out, file); err != nil {
		response.Error(c, http.StatusInternalServerError, "保存文件失败")
		return
	}

	// 返回相对路径
	url := h.mediaURL(fmt.Sprintf("/uploads/avatars/%s", filename))

	response.Success(c, gin.H{
		"url":      url,
		"filename": filename,
		"size":     header.Size,
		"type":     "avatar",
	})
}

// UploadMultipleImages 批量上传图片
func (h *UploadHandler) UploadMultipleImages(c *gin.Context) {
	form, err := c.MultipartForm()
	if err != nil {
		response.Error(c, http.StatusBadRequest, "请选择文件")
		return
	}

	files := form.File["files"]
	if len(files) == 0 {
		response.Error(c, http.StatusBadRequest, "请选择文件")
		return
	}

	if len(files) > 9 {
		response.Error(c, http.StatusBadRequest, "最多上传9张图片")
		return
	}

	dateDir := time.Now().Format("2006/01/02")
	saveDir := filepath.Join(h.uploadDir, "images", dateDir)
	os.MkdirAll(saveDir, 0755)

	var results []gin.H

	for _, header := range files {
		// 检查文件类型
		contentType := header.Header.Get("Content-Type")
		if !allowedImageTypes[contentType] {
			continue
		}

		// 检查文件大小
		if header.Size > 10*1024*1024 {
			continue
		}

		file, err := header.Open()
		if err != nil {
			continue
		}

		// 生成文件名
		ext := filepath.Ext(header.Filename)
		if ext == "" {
			ext = ".jpg"
		}
		ext = strings.ToLower(ext)
		filename := fmt.Sprintf("%s_%d%s", uuid.New().String()[:8], time.Now().UnixNano(), ext)
		savePath := filepath.Join(saveDir, filename)

		// 保存文件
		out, err := os.Create(savePath)
		if err != nil {
			file.Close()
			continue
		}

		if _, err := io.Copy(out, file); err != nil {
			file.Close()
			out.Close()
			continue
		}

		file.Close()
		out.Close()

		url := h.mediaURL(fmt.Sprintf("/uploads/images/%s/%s", dateDir, filename))
		results = append(results, gin.H{
			"url":      url,
			"filename": filename,
			"size":     header.Size,
		})
	}

	if len(results) == 0 {
		response.Error(c, http.StatusBadRequest, "没有文件上传成功")
		return
	}

	response.Success(c, gin.H{
		"files": results,
		"count": len(results),
	})
}

// UploadVoice 上传语音消息
func (h *UploadHandler) UploadVoice(c *gin.Context) {
	file, header, err := c.Request.FormFile("file")
	if err != nil {
		response.Error(c, http.StatusBadRequest, "请选择文件")
		return
	}
	defer file.Close()

	// 检查文件类型
	contentType := header.Header.Get("Content-Type")
	if !allowedAudioTypes[contentType] {
		response.Error(c, http.StatusBadRequest, "不支持的音频格式")
		return
	}

	// 获取用户ID并检查会员上传限制
	userUUID := c.GetString("user_id")
	var user models.User
	if err := h.db.Where("uuid = ?", userUUID).First(&user).Error; err != nil {
		response.Error(c, http.StatusUnauthorized, "用户未登录")
		return
	}

	// 检查文件大小
	maxSize := getUploadLimitBytes(h.db, user.ID, "voice")
	if header.Size > maxSize {
		response.Error(c, http.StatusBadRequest, fmt.Sprintf("语音大小不能超过%dMB", maxSize/1024/1024))
		return
	}

	// 获取时长参数（毫秒）
	durationStr := c.PostForm("duration")
	duration := 0
	if durationStr != "" {
		fmt.Sscanf(durationStr, "%d", &duration)
	}

	// 生成文件名
	ext := filepath.Ext(header.Filename)
	if ext == "" {
		ext = ".m4a"
	}
	filename := fmt.Sprintf("%s_%d%s", uuid.New().String()[:8], time.Now().UnixMilli(), ext)

	// 按日期分目录
	dateDir := time.Now().Format("2006/01/02")
	saveDir := filepath.Join(h.uploadDir, "voices", dateDir)
	os.MkdirAll(saveDir, 0755)

	savePath := filepath.Join(saveDir, filename)

	// 保存文件
	out, err := os.Create(savePath)
	if err != nil {
		response.Error(c, http.StatusInternalServerError, "保存文件失败")
		return
	}
	defer out.Close()

	if _, err := io.Copy(out, file); err != nil {
		response.Error(c, http.StatusInternalServerError, "保存文件失败")
		return
	}

	// 返回相对路径
	url := h.mediaURL(fmt.Sprintf("/uploads/voices/%s/%s", dateDir, filename))

	response.Success(c, gin.H{
		"url":      url,
		"filename": filename,
		"size":     header.Size,
		"duration": duration,
		"type":     "voice",
	})
}

// UploadFile 上传文件
func (h *UploadHandler) UploadFile(c *gin.Context) {
	file, header, err := c.Request.FormFile("file")
	if err != nil {
		response.Error(c, http.StatusBadRequest, "请选择文件")
		return
	}
	defer file.Close()

	// 获取用户ID并检查会员上传限制
	userUUID := c.GetString("user_id")
	var user models.User
	if err := h.db.Where("uuid = ?", userUUID).First(&user).Error; err != nil {
		response.Error(c, http.StatusUnauthorized, "用户未登录")
		return
	}

	// 检查文件大小
	maxSize := getUploadLimitBytes(h.db, user.ID, "file")
	if header.Size > maxSize {
		response.Error(c, http.StatusBadRequest, fmt.Sprintf("文件大小不能超过%dMB", maxSize/1024/1024))
		return
	}

	// 生成文件名（保留原始扩展名）
	ext := filepath.Ext(header.Filename)
	filename := fmt.Sprintf("%s_%d%s", uuid.New().String()[:8], time.Now().UnixMilli(), ext)

	// 按日期分目录
	dateDir := time.Now().Format("2006/01/02")
	saveDir := filepath.Join(h.uploadDir, "files", dateDir)
	os.MkdirAll(saveDir, 0755)

	savePath := filepath.Join(saveDir, filename)

	// 保存文件
	out, err := os.Create(savePath)
	if err != nil {
		response.Error(c, http.StatusInternalServerError, "保存文件失败")
		return
	}
	defer out.Close()

	if _, err := io.Copy(out, file); err != nil {
		response.Error(c, http.StatusInternalServerError, "保存文件失败")
		return
	}

	// 返回相对路径
	url := h.mediaURL(fmt.Sprintf("/uploads/files/%s/%s", dateDir, filename))

	response.Success(c, gin.H{
		"url":          url,
		"filename":     filename,
		"originalName": header.Filename,
		"size":         header.Size,
		"type":         "file",
	})
}
