package handlers

import (
	"fmt"
	"io"
	"net/http"
	"os"
	"path/filepath"
	"strings"
	"time"

	"gaoranim/internal/storage"
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
	s3        *storage.S3Storage // nil 时降级为本地存储
}

func NewUploadHandler(db *gorm.DB, uploadDir, baseURL string, s3Storage *storage.S3Storage) *UploadHandler {
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
		s3:        s3Storage,
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

// uploadToStorage 统一上传入口：优先 S3，降级本地存储
// 返回 (accessURL, error)
func (h *UploadHandler) uploadToStorage(c *gin.Context, data []byte, category, filename, contentType string) (accessURL string, err error) {
	if h.s3 != nil {
		// S3 上传
		result, err := h.s3.Upload(c.Request.Context(), data, category, filename, contentType)
		if err != nil {
			return "", err
		}
		return result.URL, nil
	}
	// 降级：本地存储
	dateDir := time.Now().Format("2006/01/02")
	ext := filepath.Ext(filename)
	if ext == "" {
		switch contentType {
		case "image/jpeg", "image/jpg":
			ext = ".jpg"
		case "image/png":
			ext = ".png"
		case "image/webp":
			ext = ".webp"
		case "image/gif":
			ext = ".gif"
		}
	}
	uniqueName := fmt.Sprintf("%s_%d%s", uuid.New().String()[:8], time.Now().UnixMilli(), ext)
	saveDir := filepath.Join(h.uploadDir, category, dateDir)
	os.MkdirAll(saveDir, 0755)
	savePath := filepath.Join(saveDir, uniqueName)
	if err := os.WriteFile(savePath, data, 0644); err != nil {
		return "", err
	}
	return h.mediaURL(fmt.Sprintf("/uploads/%s/%s/%s", category, dateDir, uniqueName)), nil
}

// 允许的图片类型
var allowedImageTypes = map[string]bool{
	"image/jpeg": true,
	"image/jpg":  true,
	"image/png":  true,
	"image/gif":  true,
	"image/webp": true,
	"image/heic": true, // iOS Live Photo
	"image/heif": true, // iOS Live Photo
	// ★ application/octet-stream 已移除，改由魔数验证兜底
}

// detectImageTypeByMagic 通过魔数验证文件是否为合法图片（防伪造 Content-Type）
func detectImageTypeByMagic(data []byte) bool {
	if len(data) < 4 {
		return false
	}
	// JPEG: FF D8 FF
	if data[0] == 0xFF && data[1] == 0xD8 && data[2] == 0xFF {
		return true
	}
	// PNG: 89 50 4E 47
	if data[0] == 0x89 && data[1] == 0x50 && data[2] == 0x4E && data[3] == 0x47 {
		return true
	}
	// GIF: 47 49 46 38
	if data[0] == 0x47 && data[1] == 0x49 && data[2] == 0x46 && data[3] == 0x38 {
		return true
	}
	// WebP: 52 49 46 46 ... 57 45 42 50
	if len(data) >= 12 && data[0] == 0x52 && data[1] == 0x49 && data[2] == 0x46 && data[3] == 0x46 &&
		data[8] == 0x57 && data[9] == 0x45 && data[10] == 0x42 && data[11] == 0x50 {
		return true
	}
	// HEIC/HEIF: ftyp box at offset 4
	if len(data) >= 12 && data[4] == 0x66 && data[5] == 0x74 && data[6] == 0x79 && data[7] == 0x70 {
		return true
	}
	return false
}

// detectAudioTypeByMagic 通过魔数验证文件是否为合法音频
func detectAudioTypeByMagic(data []byte) bool {
	if len(data) < 4 {
		return false
	}
	// MP3: FF FB / FF F3 / FF F2 / ID3
	if (data[0] == 0xFF && (data[1] == 0xFB || data[1] == 0xF3 || data[1] == 0xF2)) ||
		(data[0] == 0x49 && data[1] == 0x44 && data[2] == 0x33) {
		return true
	}
	// M4A/AAC: ftyp
	if len(data) >= 8 && data[4] == 0x66 && data[5] == 0x74 && data[6] == 0x79 && data[7] == 0x70 {
		return true
	}
	// WAV: RIFF...WAVE
	if len(data) >= 12 && data[0] == 0x52 && data[1] == 0x49 && data[2] == 0x46 && data[3] == 0x46 &&
		data[8] == 0x57 && data[9] == 0x41 && data[10] == 0x56 && data[11] == 0x45 {
		return true
	}
	return false
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
	// ★ application/octet-stream 已移除，改由魔数验证兜底
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
	// ★ 魔数验证：防止伪造 Content-Type 上传危险文件
	magicBuf := make([]byte, 16)
	if n, _ := file.Read(magicBuf); n > 0 {
		if !detectImageTypeByMagic(magicBuf[:n]) {
			response.Error(c, http.StatusBadRequest, "文件内容与类型不符")
			return
		}
		file.Seek(0, 0)
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
	// 读取文件内容
	fileData, err := io.ReadAll(file)
	if err != nil {
		response.Error(c, http.StatusInternalServerError, "读取文件失败")
		return
	}

	// 上传（S3 或本地）
	url, err := h.uploadToStorage(c, fileData, "discover", header.Filename, contentType)
	if err != nil {
		response.Error(c, http.StatusInternalServerError, "上传失败")
		return
	}

	response.Success(c, gin.H{
		"url":      url,
		"filename": header.Filename,
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
	// ★ 魔数验证：防止伪造 Content-Type 上传危险文件
	magicBuf := make([]byte, 16)
	if n, _ := file.Read(magicBuf); n > 0 {
		if !detectImageTypeByMagic(magicBuf[:n]) {
			response.Error(c, http.StatusBadRequest, "文件内容与类型不符")
			return
		}
		file.Seek(0, 0)
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
	// 读取文件内容
	fileData, err := io.ReadAll(file)
	if err != nil {
		response.Error(c, http.StatusInternalServerError, "读取文件失败")
		return
	}

	// 上传（S3 或本地）
	url, err := h.uploadToStorage(c, fileData, "images", header.Filename, contentType)
	if err != nil {
		response.Error(c, http.StatusInternalServerError, "上传文件失败")
		return
	}

	response.Success(c, gin.H{
		"url":      url,
		"filename": header.Filename,
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
	// 读取文件内容
	fileData, err := io.ReadAll(file)
	if err != nil {
		response.Error(c, http.StatusInternalServerError, "读取文件失败")
		return
	}

	// 上传（S3 或本地）
	url, err := h.uploadToStorage(c, fileData, "videos", header.Filename, contentType)
	if err != nil {
		response.Error(c, http.StatusInternalServerError, "上传失败")
		return
	}

	response.Success(c, gin.H{
		"url":      url,
		"filename": header.Filename,
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
	// ★ 魔数验证：防止伪造 Content-Type 上传危险文件
	magicBuf := make([]byte, 16)
	if n, _ := file.Read(magicBuf); n > 0 {
		if !detectImageTypeByMagic(magicBuf[:n]) {
			response.Error(c, http.StatusBadRequest, "文件内容与类型不符")
			return
		}
		file.Seek(0, 0)
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

	// 读取文件内容
	fileData, err := io.ReadAll(file)
	if err != nil {
		response.Error(c, http.StatusInternalServerError, "读取文件失败")
		return
	}

	// 上传到 S3 或本地存储
	contentType = header.Header.Get("Content-Type")
	if contentType == "" {
		contentType = "image/jpeg"
	}
	url, err := h.uploadToStorage(c, fileData, "avatars", filename, contentType)
	if err != nil {
		response.Error(c, http.StatusInternalServerError, "上传文件失败")
		return
	}

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

		// ★ 魔数验证：防止伪造 Content-Type 上传危险文件
		magicBuf := make([]byte, 16)
		if n, _ := file.Read(magicBuf); n > 0 {
			if !detectImageTypeByMagic(magicBuf[:n]) {
				file.Close()
				continue
			}
			file.Seek(0, 0)
		}

		// 生成文件名
		ext := filepath.Ext(header.Filename)
		if ext == "" {
			ext = ".jpg"
		}
		ext = strings.ToLower(ext)
		filename := fmt.Sprintf("%s_%d%s", uuid.New().String()[:8], time.Now().UnixNano(), ext)

		// 读取文件内容
		fileData, readErr := io.ReadAll(file)
		file.Close()
		if readErr != nil {
			continue
		}

		// 上传到 S3 或本地存储
		url, err := h.uploadToStorage(c, fileData, "images", filename, contentType)
		if err != nil {
			continue
		}

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
	// ★ 魔数验证：防止伪造 Content-Type 上传危险文件
	magicBuf := make([]byte, 16)
	if n, _ := file.Read(magicBuf); n > 0 {
		if !detectAudioTypeByMagic(magicBuf[:n]) {
			response.Error(c, http.StatusBadRequest, "文件内容与类型不符")
			return
		}
		file.Seek(0, 0)
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
	// 读取文件内容
	fileData, err := io.ReadAll(file)
	if err != nil {
		response.Error(c, http.StatusInternalServerError, "读取文件失败")
		return
	}

	// 上传（S3 或本地）
	url, err := h.uploadToStorage(c, fileData, "voices", header.Filename, contentType)
	if err != nil {
		response.Error(c, http.StatusInternalServerError, "上传失败")
		return
	}

	response.Success(c, gin.H{
		"url":      url,
		"filename": header.Filename,
		"size":     header.Size,
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

	contentType := header.Header.Get("Content-Type")

	// 读取文件内容
	fileData, err := io.ReadAll(file)
	if err != nil {
		response.Error(c, http.StatusInternalServerError, "读取文件失败")
		return
	}

	// 上传（S3 或本地）
	url, err := h.uploadToStorage(c, fileData, "files", header.Filename, contentType)
	if err != nil {
		response.Error(c, http.StatusInternalServerError, "上传失败")
		return
	}

	response.Success(c, gin.H{
		"url":          url,
		"filename":     header.Filename,
		"originalName": header.Filename,
		"size":         header.Size,
		"type":         "file",
	})
}
