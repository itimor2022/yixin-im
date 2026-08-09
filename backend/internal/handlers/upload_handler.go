// 文件用途：实现后端 HTTP 接口的请求处理和统一响应。
// 核心逻辑：绑定参数，校验身份与权限，调用业务服务并持久化关键状态。

package handlers

import (
	"archive/zip"
	"bytes"
	"crypto/sha256"
	"encoding/hex"
	"fmt"
	"github.com/gin-gonic/gin"
	"github.com/google/uuid"
	"gorm.io/gorm" // UploadHandler 文件上传处理
	"io"
	"log"
	"mime"
	"mime/multipart"
	"net/http"
	"os"
	objectpath "path"
	"path/filepath"
	"strings"
	"time"
	"genericim/internal/config"
	"genericim/internal/models"
	"genericim/internal/services"
	"genericim/pkg/response"
)

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
	os.MkdirAll(filepath.Join(uploadDir, "vip", "badges"), 0755)
	os.MkdirAll(filepath.Join(uploadDir, "voices"), 0755)
	os.MkdirAll(filepath.Join(uploadDir, "files"), 0755)
	// 去掉末尾斜杠，保证 baseURL+"/uploads/..." 格式正确
	baseURL = strings.TrimRight(baseURL, "/")
	return &UploadHandler{

		db: db,

		uploadDir: uploadDir,

		baseURL: baseURL,
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
func (h *UploadHandler) currentStorageConfig() config.StorageConfig {
	var yamlCfg config.StorageConfig
	if config.GlobalConfig != nil {

		yamlCfg = config.GlobalConfig.Storage
	}
	return services.LoadStorageForRuntime(h.db, yamlCfg)
}

type savedUploadObject struct {
	URL      string
	MediaID  string
	Checksum string
}

func (h *UploadHandler) saveUploadedObject(
	c *gin.Context,
	r io.Reader,
	objectKey,
	contentType string,
	size int64,
	mediaType,
	originalName string) (savedUploadObject, error) {
	startedAt := time.Now()
	objectKey = strings.TrimLeft(objectpath.Clean(strings.ReplaceAll(objectKey, "\\", "/")), "/")
	if objectKey == "." || objectKey == "" {

		return savedUploadObject{}, fmt.Errorf("上传路径不能为空")
	}
	storageCfg := h.currentStorageConfig()
	provider := services.NormalizeStorageProvider(storageCfg.Provider)
	finish := func(url string, err error) {

		h.recordUploadLog(c, uploadLogParams{

			MediaType: mediaType,

			Provider: provider,

			ObjectKey: objectKey,

			URL: url,

			ContentType: contentType,

			Size: size,

			Success: err == nil,

			Err: err,

			StartedAt: startedAt,
		})
	}
	if err := services.ValidateStorageConfig(storageCfg); err != nil {

		finish("", err)

		return savedUploadObject{}, err
	}
	var userID uint64
	var adminID uint64
	if raw, ok := c.Get("upload_user_id"); ok {

		userID, _ = raw.(uint64)
	}
	if raw, ok := c.Get("admin_id"); ok {

		adminID, _ = raw.(uint64)
	}
	clientRequestID := strings.TrimSpace(c.GetHeader("X-Upload-Request-ID"))
	if clientRequestID == "" {

		clientRequestID = strings.TrimSpace(c.PostForm("client_request_id"))
	}
	legacyAutoBind := clientRequestID == ""
	// 新客户端以 request ID 获得可重试的 uploaded 对象，再由具体业务显式绑定；
	// 无 request ID 的旧客户端保持“上传即绑定”，避免清理任务误删历史接口刚返回的文件。
	bucket := ""
	switch provider {
	case services.StorageProviderAliyun:

		bucket = storageCfg.Aliyun.Bucket
	case services.StorageProviderQiniu:

		bucket = storageCfg.Qiniu.Bucket
	case services.StorageProviderS3:

		bucket = storageCfg.S3.Bucket
	}
	mediaObject, err := services.BeginMediaUpload(h.db, services.BeginMediaUploadParams{

		UserID: userID,

		AdminID: adminID,

		ClientRequestID: clientRequestID,

		Category: mediaType,

		Provider: provider,

		Bucket: bucket,

		ObjectKey: objectKey,

		OriginalName: originalName,

		NormalizedExt: strings.ToLower(filepath.Ext(objectKey)),

		DeclaredMIME: contentType,

		DetectedMIME: contentType,

		SizeBytes: size,
	})
	if err != nil {

		finish("", err)

		return savedUploadObject{}, err
	}
	objectKey = mediaObject.ObjectKey
	if mediaObject.Status == models.MediaObjectStatusUploaded || mediaObject.Status == models.MediaObjectStatusBound {

		// 幂等重试直接返回首次上传结果，不再次写云存储或本地文件。

		finish(mediaObject.URL, nil)

		return savedUploadObject{

			URL: mediaObject.URL,

			MediaID: mediaObject.MediaID,

			Checksum: mediaObject.ChecksumSHA256,
		}, nil
	}
	if mediaObject.Status != models.MediaObjectStatusUploading {
		err := fmt.Errorf("上传请求当前状态不可重试")

		finish("", err)

		return savedUploadObject{}, err
	}
	hasher := sha256.New()
	// 摘要在真实写入流上同步计算，避免为了校验再次读取大文件。
	reader := io.TeeReader(r, hasher)
	if provider != services.StorageProviderLocal {

		url, err := services.UploadObject(c.Request.Context(), storageCfg, objectKey, reader, size, contentType)

		if err == nil {
			checksum := hex.EncodeToString(hasher.Sum(nil))
			err = services.CompleteMediaUpload(h.db, mediaObject.ID, url, checksum, legacyAutoBind)

			if err == nil {
				if !legacyAutoBind {
					services.RememberUploadedMessageMedia(mediaObject, url, checksum)
				}

				finish(url, nil)

				return savedUploadObject{URL: url, MediaID: mediaObject.MediaID, Checksum: checksum}, nil

			}

		}

		services.FailMediaUpload(h.db, mediaObject.ID, err)

		finish(url, err)

		return savedUploadObject{}, err
	}
	relativePath := strings.TrimPrefix(objectKey, "uploads/")
	savePath, err := safeLocalUploadPath(h.uploadDir, relativePath)
	if err != nil {

		services.FailMediaUpload(h.db, mediaObject.ID, err)

		finish("", err)

		return savedUploadObject{}, err
	}
	if err := os.MkdirAll(filepath.Dir(savePath), 0755); err != nil {

		services.FailMediaUpload(h.db, mediaObject.ID, err)

		finish("", err)

		return savedUploadObject{}, err
	}
	if err := os.Chmod(filepath.Dir(savePath), 0755); err != nil {

		services.FailMediaUpload(h.db, mediaObject.ID, err)

		finish("", err)

		return savedUploadObject{}, err
	}
	out, err := os.Create(savePath)
	if err != nil {

		services.FailMediaUpload(h.db, mediaObject.ID, err)

		finish("", err)

		return savedUploadObject{}, err
	}
	if _, err := io.Copy(out, reader); err != nil {

		_ = out.Close()

		services.FailMediaUpload(h.db, mediaObject.ID, err)

		finish("", err)

		return savedUploadObject{}, err
	}
	if err := out.Close(); err != nil {

		services.FailMediaUpload(h.db, mediaObject.ID, err)

		finish("", err)

		return savedUploadObject{}, err
	}
	if err := os.Chmod(savePath, 0644); err != nil {

		services.FailMediaUpload(h.db, mediaObject.ID, err)

		finish("", err)

		return savedUploadObject{}, err
	}
	baseURL := strings.TrimRight(strings.TrimSpace(storageCfg.Local.BaseURL), "/")
	if baseURL == "" {

		baseURL = h.baseURL
	}
	url := services.PublicObjectURL(baseURL, objectKey, true)
	checksum := hex.EncodeToString(hasher.Sum(nil))
	if err := services.CompleteMediaUpload(h.db, mediaObject.ID, url, checksum, legacyAutoBind); err != nil {

		services.FailMediaUpload(h.db, mediaObject.ID, err)

		finish("", err)

		return savedUploadObject{}, err
	}
	if !legacyAutoBind {
		services.RememberUploadedMessageMedia(mediaObject, url, checksum)
	}
	finish(url, nil)
	return savedUploadObject{URL: url, MediaID: mediaObject.MediaID, Checksum: checksum}, nil
}

type uploadLogParams struct {
	MediaType   string
	Provider    string
	ObjectKey   string
	URL         string
	FileName    string
	ContentType string
	Size        int64
	Success     bool
	Err         error
	StartedAt   time.Time
}

func (h *UploadHandler) recordUploadLog(c *gin.Context, params uploadLogParams) {
	if h == nil {

		return
	}
	recordUploadOutcome(h.db, c, params)
}
func recordUploadOutcome(db *gorm.DB, c *gin.Context, params uploadLogParams) {
	if db == nil || c == nil {

		return
	}
	actorType := "user"
	var userID uint64
	var adminID uint64
	if raw, ok := c.Get("upload_user_id"); ok {

		if id, ok := raw.(uint64); ok {

			userID = id

		}
	}
	if raw, ok := c.Get("admin_id"); ok {

		if id, ok := raw.(uint64); ok {

			adminID = id

			actorType = "admin"

		}
	}
	errText := ""
	if params.Err != nil {

		errText = truncateOpsLogText(params.Err.Error(), 512)
	}
	startedAt := params.StartedAt
	if startedAt.IsZero() {

		startedAt = time.Now()
	}
	logItem := models.UploadLog{

		ActorType: actorType,

		UserID: userID,

		AdminID: adminID,

		MediaType: truncateOpsLogText(strings.TrimSpace(params.MediaType), 30),

		Provider: truncateOpsLogText(strings.TrimSpace(params.Provider), 20),

		ObjectKey: truncateOpsLogText(strings.TrimSpace(params.ObjectKey), 500),

		URL: truncateOpsLogText(strings.TrimSpace(params.URL), 800),

		FileName: truncateOpsLogText(uploadLogFileName(params), 255),

		ContentType: truncateOpsLogText(strings.TrimSpace(params.ContentType), 120),

		Size: params.Size,

		Success: params.Success,

		Error: errText,

		DurationMS: time.Since(startedAt).Milliseconds(),

		IP: truncateOpsLogText(c.ClientIP(), 50),

		UserAgent: truncateOpsLogText(c.Request.UserAgent(), 500),

		CreatedAt: time.Now(),
	}
	_ = db.Create(&logItem).Error
}
func uploadLogFileName(params uploadLogParams) string {
	if name := strings.TrimSpace(params.FileName); name != "" {

		return name
	}
	key := strings.TrimSpace(strings.ReplaceAll(params.ObjectKey, "\\", "/"))
	if key == "" {

		return ""
	}
	return objectpath.Base(key)
}
func safeLocalUploadPath(baseDir, relativePath string) (string, error) {
	baseAbs, err := filepath.Abs(baseDir)
	if err != nil {

		return "", err
	}
	cleaned := strings.TrimLeft(objectpath.Clean(strings.ReplaceAll(relativePath, "\\", "/")), "/")
	if cleaned == "" || cleaned == "." || filepath.IsAbs(cleaned) {

		return "", fmt.Errorf("invalid upload path")
	}
	targetAbs, err := filepath.Abs(filepath.Join(append([]string{baseAbs}, strings.Split(cleaned, "/")...)...))
	if err != nil {

		return "", err
	}
	// Clean 只能规范字符串，Rel 检查才是最终目录边界，防止绝对路径和 .. 穿越。
	rel, err := filepath.Rel(baseAbs, targetAbs)
	if err != nil || rel == ".." || strings.HasPrefix(rel, ".."+string(os.PathSeparator)) || filepath.IsAbs(rel) {

		return "", fmt.Errorf("upload path escapes base directory")
	}
	return targetAbs, nil
}
func buildUploadObjectKey(parts ...string) string {
	cleaned := make([]string, 0, len(parts)+1)
	cleaned = append(cleaned, "uploads")
	for _, part := range parts {

		part = strings.Trim(part, "/\\")

		if part == "" {

			continue

		}
		cleaned = append(cleaned, part)
	}
	return objectpath.Join(cleaned...)
}
func truncateOpsLogText(value string, limit int) string {
	value = strings.TrimSpace(value)
	if limit <= 0 || len(value) <= limit {

		return value
	}
	return value[:limit]
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
	"image/avif":               true,
	"application/octet-stream": true, // 某些情况下 HEIC 会被识别为此类型
}

// 允许的视频类型
var allowedVideoTypes = map[string]bool{
	"video/mp4":                true,
	"video/x-m4v":              true,
	"video/quicktime":          true,
	"video/x-msvideo":          true,
	"video/webm":               true,
	"application/octet-stream": true}

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

const p0S3ProxyUploadLimitBytes int64 = 100 * 1024 * 1024

func (h *UploadHandler) effectiveProxyUploadLimit(entitlementLimit int64, mediaType string) int64 {
	if entitlementLimit <= 0 {

		return entitlementLimit
	}
	if mediaType != "video" && mediaType != "file" {

		return entitlementLimit
	}
	if services.NormalizeStorageProvider(h.currentStorageConfig().Provider) != services.StorageProviderS3 {

		return entitlementLimit
	}
	if entitlementLimit > p0S3ProxyUploadLimitBytes {

		return p0S3ProxyUploadLimitBytes
	}
	return entitlementLimit
}
func normalizedUploadContentType(header *multipart.FileHeader) string {
	contentType := strings.TrimSpace(strings.ToLower(header.Header.Get("Content-Type")))
	if contentType == "" {

		return "application/octet-stream"
	}
	if mediaType, _, err := mime.ParseMediaType(contentType); err == nil {

		return strings.ToLower(mediaType)
	}
	return contentType
}
func sniffUploadContent(file multipart.File) (string, error) {
	buf := make([]byte, 512)
	n, err := file.Read(buf)
	if err != nil && err != io.EOF {

		return "", err
	}
	if seeker, ok := file.(io.Seeker); ok {

		if _, err := seeker.Seek(0, io.SeekStart); err != nil {

			return "", err

		}
	}
	return http.DetectContentType(buf[:n]), nil
}
func uploadHasISOBaseMediaBrand(file multipart.File, allowedBrands map[string]bool) (bool, error) {
	buf := make([]byte, 4096)
	n, err := file.Read(buf)
	if err != nil && err != io.EOF {

		return false, err
	}
	if seeker, ok := file.(io.Seeker); ok {

		if _, err := seeker.Seek(0, io.SeekStart); err != nil {

			return false, err

		}
	}
	data := buf[:n]
	for i := 4; i+8 <= len(data) && i < 1024; i++ {

		if string(data[i:i+4]) != "ftyp" {

			continue

		}

		for j := i + 4; j+4 <= len(data) && j <= i+32; j += 4 {

			if allowedBrands[string(data[j:j+4])] {

				return true, nil

			}

		}

		return false, nil
	}
	return false, nil
}
func uploadLooksLikeWebM(file multipart.File) (bool, error) {
	buf := make([]byte, 4)
	n, err := file.Read(buf)
	if err != nil && err != io.EOF {

		return false, err
	}
	if seeker, ok := file.(io.Seeker); ok {

		if _, err := seeker.Seek(0, io.SeekStart); err != nil {

			return false, err

		}
	}
	return n >= 4 && bytes.Equal(buf[:4], []byte{0x1A, 0x45, 0xDF, 0xA3}), nil
}
func uploadLooksLikeRIFF(file multipart.File, format string) (bool, error) {
	buf := make([]byte, 12)
	n, err := file.Read(buf)
	if err != nil && err != io.EOF {

		return false, err
	}
	if seeker, ok := file.(io.Seeker); ok {

		if _, err := seeker.Seek(0, io.SeekStart); err != nil {

			return false, err

		}
	}
	return n >= 12 && string(buf[0:4]) == "RIFF" && string(buf[8:12]) == format, nil
}
func uploadLooksLikeOgg(file multipart.File) (bool, error) {
	buf := make([]byte, 4)
	n, err := file.Read(buf)
	if err != nil && err != io.EOF {

		return false, err
	}
	if seeker, ok := file.(io.Seeker); ok {

		if _, err := seeker.Seek(0, io.SeekStart); err != nil {

			return false, err

		}
	}
	return n >= 4 && string(buf[:4]) == "OggS", nil
}
func uploadLooksLikeAAC(file multipart.File) (bool, error) {
	buf := make([]byte, 2)
	n, err := file.Read(buf)
	if err != nil && err != io.EOF {

		return false, err
	}
	if seeker, ok := file.(io.Seeker); ok {

		if _, err := seeker.Seek(0, io.SeekStart); err != nil {

			return false, err

		}
	}
	return n >= 2 && buf[0] == 0xFF && (buf[1]&0xF0) == 0xF0, nil
}
func validateImageUpload(file multipart.File, header *multipart.FileHeader) (string, string, error) {
	// multipart 声明和文件名都由客户端控制，必须以文件头嗅探/容器 brand
	// 交叉验证后再确定服务端使用的 MIME 与扩展名。
	declared := normalizedUploadContentType(header)
	if !allowedImageTypes[declared] {

		return "", "", fmt.Errorf("不支持的图片格式")
	}
	sniffed, err := sniffUploadContent(file)
	if err != nil {

		return "", "", fmt.Errorf("读取图片失败")
	}
	ext := strings.ToLower(filepath.Ext(header.Filename))
	switch sniffed {
	case "image/jpeg":

		return "image/jpeg", ".jpg", nil
	case "image/png":

		return "image/png", ".png", nil
	case "image/gif":

		return "image/gif", ".gif", nil
	case "image/webp":

		return "image/webp", ".webp", nil
	case "image/avif":

		return "image/avif", ".avif", nil
	default:

		if ext == ".avif" {

			ok, brandErr := uploadHasISOBaseMediaBrand(file, map[string]bool{

				"avif": true,

				"avis": true,
			})

			if brandErr != nil {

				return "", "", fmt.Errorf("读取图片失败")

			}

			if ok {

				return "image/avif", ".avif", nil

			}

		}

		if ext == ".heic" || ext == ".heif" {

			ok, brandErr := uploadHasISOBaseMediaBrand(file, map[string]bool{

				"heic": true,

				"heix": true,

				"hevc": true,

				"hevx": true,

				"mif1": true,

				"msf1": true,
			})

			if brandErr != nil {

				return "", "", fmt.Errorf("读取图片失败")

			}

			if ok {

				if declared == "image/heif" || ext == ".heif" {

					return "image/heif", ".heif", nil

				}

				return "image/heic", ".heic", nil

			}

		}

		return "", "", fmt.Errorf("不支持的图片格式")
	}
}
func validateVideoUpload(file multipart.File, header *multipart.FileHeader) (string, string, error) {
	declared := normalizedUploadContentType(header)
	if !allowedVideoTypes[declared] {

		return "", "", fmt.Errorf("不支持的视频格式")
	}
	sniffed, err := sniffUploadContent(file)
	if err != nil {

		return "", "", fmt.Errorf("读取视频失败")
	}
	ext := strings.ToLower(filepath.Ext(header.Filename))
	if strings.HasPrefix(sniffed, "video/") {

		if declared == "video/webm" || ext == ".webm" {

			return "video/webm", ".webm", nil

		}

		if declared == "video/x-msvideo" || ext == ".avi" {

			return "video/x-msvideo", ".avi", nil

		}

		if declared == "video/quicktime" || ext == ".mov" {

			return "video/quicktime", ".mov", nil

		}

		return "video/mp4", ".mp4", nil
	}
	if declared == "video/mp4" || declared == "video/x-m4v" || declared == "video/quicktime" || ext == ".mp4" || ext == ".m4v" || ext == ".mov" {

		ok, brandErr := uploadHasISOBaseMediaBrand(file, map[string]bool{

			"isom": true,

			"iso2": true,

			"avc1": true,

			"mp41": true,

			"mp42": true,

			"qt  ": true,

			"M4V ": true,

			"M4A ": true,
		})

		if brandErr != nil {

			return "", "", fmt.Errorf("读取视频失败")

		}

		if ok {

			if declared == "video/quicktime" || ext == ".mov" {

				return "video/quicktime", ".mov", nil

			}

			return "video/mp4", ".mp4", nil

		}
	}
	if declared == "video/webm" || ext == ".webm" {

		ok, webmErr := uploadLooksLikeWebM(file)

		if webmErr != nil {

			return "", "", fmt.Errorf("读取视频失败")

		}

		if ok {

			return "video/webm", ".webm", nil

		}
	}
	if declared == "video/x-msvideo" || ext == ".avi" {

		ok, riffErr := uploadLooksLikeRIFF(file, "AVI ")

		if riffErr != nil {

			return "", "", fmt.Errorf("读取视频失败")

		}

		if ok {

			return "video/x-msvideo", ".avi", nil

		}
	}
	return "", "", fmt.Errorf("不支持的视频格式")
}
func validateAudioUpload(file multipart.File, header *multipart.FileHeader) (string, string, error) {
	declared := normalizedUploadContentType(header)
	if !allowedAudioTypes[declared] {

		return "", "", fmt.Errorf("不支持的音频格式")
	}
	sniffed, err := sniffUploadContent(file)
	if err != nil {

		return "", "", fmt.Errorf("读取音频失败")
	}
	ext := strings.ToLower(filepath.Ext(header.Filename))
	switch {
	case sniffed == "audio/mpeg":

		return "audio/mpeg", ".mp3", nil
	case strings.HasPrefix(sniffed, "audio/"):

		switch sniffed {

		case "audio/wave", "audio/wav", "audio/x-wav":

			return "audio/wav", ".wav", nil

		case "audio/ogg":

			return "audio/ogg", ".ogg", nil

		case "audio/mp4", "audio/x-m4a":

			return "audio/mp4", ".m4a", nil

		case "audio/aac":

			return "audio/aac", ".aac", nil

		default:

			if ext == ".m4a" || ext == ".aac" || ext == ".wav" || ext == ".ogg" || ext == ".webm" || ext == ".mp3" {

				return declared, ext, nil

			}

		}

		return declared, ".m4a", nil
	case sniffed == "application/ogg":

		return "audio/ogg", ".ogg", nil
	case sniffed == "video/webm" || declared == "audio/webm":

		ok, webmErr := uploadLooksLikeWebM(file)

		if webmErr != nil {

			return "", "", fmt.Errorf("读取音频失败")

		}

		if ok {

			return "audio/webm", ".webm", nil

		}
	case ext == ".m4a" || declared == "audio/mp4" || declared == "audio/x-m4a":

		ok, brandErr := uploadHasISOBaseMediaBrand(file, map[string]bool{

			"M4A ": true,

			"mp42": true,

			"isom": true,

			"iso2": true,
		})

		if brandErr != nil {

			return "", "", fmt.Errorf("读取音频失败")

		}

		if ok {

			return "audio/mp4", ".m4a", nil

		}
	case ext == ".wav" || declared == "audio/wav":

		ok, riffErr := uploadLooksLikeRIFF(file, "WAVE")

		if riffErr != nil {

			return "", "", fmt.Errorf("读取音频失败")

		}

		if ok {

			return "audio/wav", ".wav", nil

		}
	case ext == ".ogg" || declared == "audio/ogg":

		ok, oggErr := uploadLooksLikeOgg(file)

		if oggErr != nil {

			return "", "", fmt.Errorf("读取音频失败")

		}

		if ok {

			return "audio/ogg", ".ogg", nil

		}
	case ext == ".aac" || declared == "audio/aac":

		ok, aacErr := uploadLooksLikeAAC(file)

		if aacErr != nil {

			return "", "", fmt.Errorf("读取音频失败")

		}

		if ok {

			return "audio/aac", ".aac", nil

		}
	}
	return "", "", fmt.Errorf("不支持的音频格式")
}
func safeGenericFileExt(filename string) string {
	ext := strings.ToLower(filepath.Ext(filename))
	switch ext {
	case "", ".html", ".htm", ".js", ".mjs", ".css", ".svg", ".xml", ".xhtml", ".php", ".jsp", ".asp", ".aspx":

		return ".bin"
	default:

		return ext
	}
}

var allowedGenericFiles = map[string]struct {
	contentType string
	kind        string
}{
	".pdf":  {contentType: "application/pdf", kind: "pdf"},
	".docx": {contentType: "application/vnd.openxmlformats-officedocument.wordprocessingml.document", kind: "docx"},
	".xlsx": {contentType: "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet", kind: "xlsx"},
	".pptx": {contentType: "application/vnd.openxmlformats-officedocument.presentationml.presentation", kind: "pptx"},
	".txt":  {contentType: "text/plain", kind: "text"},
	".csv":  {contentType: "text/csv", kind: "text"},
	".zip":  {contentType: "application/zip", kind: "zip"}}
var dangerousFileNameSegments = map[string]bool{
	"exe": true, "msi": true, "apk": true, "bat": true, "cmd": true,
	"ps1": true, "sh": true, "com": true, "dll": true, "jar": true,
	"js": true, "mjs": true, "html": true, "htm": true, "svg": true,
	"xml": true, "php": true, "jsp": true, "asp": true, "aspx": true,
	"docm": true, "xlsm": true, "pptm": true, "scr": true, "lnk": true,
	"reg": true, "iso": true, "dmg": true}

func validateGenericFileUpload(file multipart.File, header *multipart.FileHeader) (string, string, error) {
	name := strings.TrimSpace(header.Filename)
	if name == "" || header.Size <= 0 {

		return "", "", fmt.Errorf("文件不能为空")
	}
	if len(name) > 255 || strings.ContainsAny(name, "\x00\r\n") {

		return "", "", fmt.Errorf("文件名不合法")
	}
	ext := strings.ToLower(filepath.Ext(name))
	rule, ok := allowedGenericFiles[ext]
	if !ok {

		return "", "", fmt.Errorf("不支持的文件格式")
	}
	segments := strings.Split(strings.ToLower(filepath.Base(name)), ".")
	// 双后缀检查阻止 report.pdf.exe 一类伪装；后续仍会校验实际容器结构。
	for _, segment := range segments[:len(segments)-1] {

		if dangerousFileNameSegments[strings.TrimSpace(segment)] {

			return "", "", fmt.Errorf("文件名包含危险的双后缀")

		}
	}
	declared := normalizedUploadContentType(header)
	sniffed, err := sniffUploadContent(file)
	if err != nil {

		return "", "", fmt.Errorf("读取文件失败")
	}
	switch rule.kind {
	case "pdf":

		if sniffed != "application/pdf" {

			return "", "", fmt.Errorf("文件内容不是有效的 PDF")

		}
	case "docx", "xlsx", "pptx":

		if err := validateOfficeZipContainer(file, header.Size, rule.kind); err != nil {

			return "", "", err

		}
	case "zip":

		if err := validateZipArchive(file, header.Size, ""); err != nil {

			return "", "", err

		}
	case "text":

		if !strings.HasPrefix(sniffed, "text/") && sniffed != "application/octet-stream" {

			return "", "", fmt.Errorf("文件内容不是有效的文本")

		}
	}
	if declared != "application/octet-stream" &&

		declared != rule.contentType &&

		!(rule.kind == "docx" && declared == "application/msword") &&

		!(rule.kind == "xlsx" && declared == "application/vnd.ms-excel") &&

		!(rule.kind == "pptx" && declared == "application/vnd.ms-powerpoint") &&

		!(rule.kind == "text" && strings.HasPrefix(declared, "text/")) &&

		!((rule.kind == "zip" || rule.kind == "docx" || rule.kind == "xlsx" || rule.kind == "pptx") &&

			(declared == "application/zip" || declared == "application/x-zip-compressed")) {

		return "", "", fmt.Errorf("文件扩展名与 MIME 类型不匹配")
	}
	return rule.contentType, ext, nil
}
func validateOfficeZipContainer(file multipart.File, size int64, kind string) error {
	return validateZipArchive(file, size, kind)
}
func validateZipArchive(file multipart.File, size int64, officeKind string) error {
	readerAt, ok := file.(io.ReaderAt)
	if !ok || size <= 0 {

		return fmt.Errorf("无法校验压缩文件结构")
	}
	reader, err := zip.NewReader(readerAt, size)
	if err != nil {

		return fmt.Errorf("压缩文件结构无效")
	}
	if len(reader.File) == 0 || len(reader.File) > 10000 {

		return fmt.Errorf("压缩文件条目数量不合法")
	}
	var totalExpanded uint64
	hasContentTypes := false
	hasOfficeRoot := officeKind == ""
	requiredRoot := officeKind
	if officeKind == "docx" {

		requiredRoot = "word"
	} else if officeKind == "xlsx" {

		requiredRoot = "xl"
	} else if officeKind == "pptx" {

		requiredRoot = "ppt"
	}
	for _, entry := range reader.File {
		name := strings.ReplaceAll(entry.Name, "\\", "/")
		cleanName := objectpath.Clean(name)

		if cleanName == ".." || strings.HasPrefix(cleanName, "../") || strings.HasPrefix(name, "/") {

			return fmt.Errorf("压缩文件包含不安全路径")

		}

		// 同时限制条目路径、总展开体积和压缩比，防止 Zip Slip 与压缩炸弹。

		totalExpanded += entry.UncompressedSize64

		if totalExpanded > 1024*1024*1024 || (size > 0 && totalExpanded > uint64(size)*20) {

			return fmt.Errorf("压缩文件展开后体积过大")

		}

		if cleanName == "[Content_Types].xml" {

			hasContentTypes = true

		}

		if requiredRoot != "" && strings.HasPrefix(cleanName, requiredRoot+"/") {

			hasOfficeRoot = true

		}
	}
	if officeKind != "" && (!hasContentTypes || !hasOfficeRoot) {

		return fmt.Errorf("Office 文件结构与扩展名不匹配")
	}
	return nil
}

// UploadDiscoverIcon 上传发现页图标
func (h *UploadHandler) UploadDiscoverIcon(c *gin.Context) {
	file, header, err := c.Request.FormFile("file")
	if err != nil {

		response.Error(c, http.StatusBadRequest, "请选择图片")

		return
	}
	defer file.Close()
	contentType, ext, err := validateImageUpload(file, header)
	if err != nil {

		response.Error(c, http.StatusBadRequest, "不支持的图片格式")

		return
	}
	// 发现页图标限制 5MB
	if header.Size > 5*1024*1024 {

		response.Error(c, http.StatusBadRequest, "图标大小不能超过5MB")

		return
	}
	filename := fmt.Sprintf("discover_%s_%d%s", uuid.New().String()[:8], time.Now().UnixMilli(), ext)
	dateDir := time.Now().Format("2006/01/02")
	saved, err := h.saveUploadedObject(c, file, buildUploadObjectKey("discover", dateDir, filename), contentType, header.Size, "discover_icon", header.Filename)
	if err != nil {

		response.Error(c, http.StatusInternalServerError, "保存图标失败")

		return
	}
	response.Success(c, gin.H{

		"url": saved.URL,

		"media_id": saved.MediaID,

		"checksum": saved.Checksum,

		"filename": filename,

		"size": header.Size,

		"type": "discover_icon",
	})
}

// UploadDiscoverBanner 上传发现页轮播图
func (h *UploadHandler) UploadDiscoverBanner(c *gin.Context) {
	file, header, err := c.Request.FormFile("file")
	if err != nil {

		response.Error(c, http.StatusBadRequest, "请选择图片")

		return
	}
	defer file.Close()
	contentType, ext, err := validateImageUpload(file, header)
	if err != nil {

		response.Error(c, http.StatusBadRequest, "不支持的图片格式")

		return
	}
	if header.Size > 8*1024*1024 {

		response.Error(c, http.StatusBadRequest, "轮播图片大小不能超过8MB")

		return
	}
	filename := fmt.Sprintf("discover_banner_%s_%d%s", uuid.New().String()[:8], time.Now().UnixMilli(), ext)
	dateDir := time.Now().Format("2006/01/02")
	saved, err := h.saveUploadedObject(c, file, buildUploadObjectKey("discover", dateDir, filename), contentType, header.Size, "discover_banner", header.Filename)
	if err != nil {

		response.Error(c, http.StatusInternalServerError, "保存轮播图片失败")

		return
	}
	response.Success(c, gin.H{

		"url": saved.URL,

		"media_id": saved.MediaID,

		"checksum": saved.Checksum,

		"filename": filename,

		"size": header.Size,

		"type": "discover_banner",
	})
}

// UploadVipBadgeIcon 上传会员小图标
func (h *UploadHandler) UploadVipBadgeIcon(c *gin.Context) {
	file, header, err := c.Request.FormFile("file")
	if err != nil {

		response.Error(c, http.StatusBadRequest, "请选择图片")

		return
	}
	defer file.Close()
	contentType, ext, err := validateImageUpload(file, header)
	if err != nil {

		response.Error(c, http.StatusBadRequest, "不支持的图片格式")

		return
	}
	if header.Size > 2*1024*1024 {

		response.Error(c, http.StatusBadRequest, "会员小图大小不能超过2MB")

		return
	}
	filename := fmt.Sprintf("vip_badge_%s_%d%s", uuid.New().String()[:8], time.Now().UnixMilli(), ext)
	dateDir := time.Now().Format("2006/01/02")
	saved, err := h.saveUploadedObject(c, file, buildUploadObjectKey("vip", "badges", dateDir, filename), contentType, header.Size, "vip_badge", header.Filename)
	if err != nil {

		response.Error(c, http.StatusInternalServerError, "保存会员小图失败")

		return
	}
	response.Success(c, gin.H{

		"url": saved.URL,

		"media_id": saved.MediaID,

		"checksum": saved.Checksum,

		"filename": filename,

		"size": header.Size,

		"type": "vip_badge_icon",
	})
}

// UploadAdminImage uploads general images from the admin console.
func (h *UploadHandler) UploadAdminImage(c *gin.Context) {
	file, header, err := c.Request.FormFile("file")
	if err != nil {

		response.Error(c, http.StatusBadRequest, "请选择图片")

		return
	}
	defer file.Close()
	contentType, ext, err := validateImageUpload(file, header)
	if err != nil {

		response.Error(c, http.StatusBadRequest, "不支持的图片格式")

		return
	}
	if header.Size > 10*1024*1024 {

		response.Error(c, http.StatusBadRequest, "图片大小不能超过10MB")

		return
	}
	filename := fmt.Sprintf("%s_%d%s", uuid.New().String()[:8], time.Now().UnixMilli(), ext)
	dateDir := time.Now().Format("2006/01/02")
	saved, err := h.saveUploadedObject(c, file, buildUploadObjectKey("admin", "images", dateDir, filename), contentType, header.Size, "admin_image", header.Filename)
	if err != nil {

		response.Error(c, http.StatusInternalServerError, "保存图片失败")

		return
	}
	response.Success(c, gin.H{

		"url": saved.URL,

		"media_id": saved.MediaID,

		"checksum": saved.Checksum,

		"filename": filename,

		"size": header.Size,

		"type": "admin_image",
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
	contentType, ext, err := validateImageUpload(file, header)
	if err != nil {

		response.Error(c, http.StatusBadRequest, "不支持的图片格式")

		return
	}
	// 获取用户ID并检查上传限制
	userUUID := c.GetString("user_id")
	var user models.User
	if err := h.db.Where("uuid = ?", userUUID).First(&user).Error; err != nil {

		response.Error(c, http.StatusUnauthorized, "用户未登录")

		return
	}
	c.Set("upload_user_id", user.ID)
	// 检查文件大小
	maxSize := getUploadLimitBytes(h.db, user.ID, "image")
	if header.Size > maxSize {

		response.Error(c, http.StatusBadRequest, fmt.Sprintf("图片大小不能超过%dMB", maxSize/1024/1024))

		return
	}
	// 生成文件名
	filename := fmt.Sprintf("%s_%d%s", uuid.New().String()[:8], time.Now().UnixMilli(), ext)
	// 按日期分目录
	dateDir := time.Now().Format("2006/01/02")
	saved, err := h.saveUploadedObject(c, file, buildUploadObjectKey("images", dateDir, filename), contentType, header.Size, "image", header.Filename)
	if err != nil {

		response.Error(c, http.StatusInternalServerError, "保存文件失败")

		return
	}
	response.Success(c, gin.H{

		"url": saved.URL,

		"media_id": saved.MediaID,

		"checksum": saved.Checksum,

		"mime_type": contentType,

		"filename": filename,

		"size": header.Size,

		"type": "image",
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
	contentType, ext, err := validateVideoUpload(file, header)
	if err != nil {

		response.Error(c, http.StatusBadRequest, "不支持的视频格式")

		return
	}
	// 获取用户ID并检查上传限制
	userUUID := c.GetString("user_id")
	var user models.User
	if err := h.db.Where("uuid = ?", userUUID).First(&user).Error; err != nil {

		response.Error(c, http.StatusUnauthorized, "用户未登录")

		return
	}
	c.Set("upload_user_id", user.ID)
	// 检查文件大小
	maxSize := h.effectiveProxyUploadLimit(getUploadLimitBytes(h.db, user.ID, "video"), "video")
	if header.Size > maxSize {

		response.Error(c, http.StatusBadRequest, fmt.Sprintf("视频大小不能超过%dMB", maxSize/1024/1024))

		return
	}
	// 生成文件名
	filename := fmt.Sprintf("%s_%d%s", uuid.New().String()[:8], time.Now().UnixMilli(), ext)
	// 按日期分目录
	dateDir := time.Now().Format("2006/01/02")
	saved, err := h.saveUploadedObject(c, file, buildUploadObjectKey("videos", dateDir, filename), contentType, header.Size, "video", header.Filename)
	if err != nil {

		response.Error(c, http.StatusInternalServerError, "保存文件失败")

		return
	}
	payload := gin.H{

		"url": saved.URL,

		"media_id": saved.MediaID,

		"checksum": saved.Checksum,

		"mime_type": contentType,

		"filename": filename,

		"size": header.Size,

		"type": "video",
	}
	if strings.TrimSpace(saved.MediaID) != "" {

		var source models.MediaObject
		if err := h.db.Where("media_id = ?", saved.MediaID).First(&source).Error; err == nil {

			cfg := h.currentStorageConfig()
			cfg.Provider = source.Provider
			processed, processErr := services.ProcessUploadedMedia(

				c.Request.Context(), h.db, cfg, &source,
			)
			if processErr != nil {

				log.Printf(

					"[MediaProcessing] proxy video media_id=%s provider=%s failed: %v",

					source.MediaID, source.Provider, processErr,
				)
			} else if processed != nil && processed.Primary != nil {

				payload["url"] = processed.Primary.URL
				payload["media_id"] = processed.Primary.MediaID
				if processed.Primary.MediaID != source.MediaID {

					payload["source_media_id"] = source.MediaID
					payload["processed"] = true
					payload["transcoded"] = processed.Transcoded
				}
				if processed.Width > 0 {

					payload["width"] = processed.Width
				}
				if processed.Height > 0 {

					payload["height"] = processed.Height
				}
				if processed.DurationMS > 0 {

					payload["duration"] = processed.DurationMS
				}
				if processed.Thumbnail != nil {

					payload["thumbnail_media_id"] = processed.Thumbnail.MediaID
					payload["thumbnail"] = processed.Thumbnail.URL
				}
			}
		}
	}
	response.Success(c, payload)
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
	contentType, ext, err := validateImageUpload(file, header)
	if err != nil {

		response.Error(c, http.StatusBadRequest, "不支持的图片格式")

		return
	}
	// 检查文件大小 (最大 5MB)
	if header.Size > 5*1024*1024 {

		response.Error(c, http.StatusBadRequest, "头像大小不能超过5MB")

		return
	}
	// 获取用户ID
	userUUID := c.GetString("user_id")
	var user models.User
	if err := h.db.Where("uuid = ?", userUUID).First(&user).Error; err != nil {

		response.Error(c, http.StatusUnauthorized, "用户未登录")

		return
	}
	c.Set("upload_user_id", user.ID)
	// 生成文件名
	filename := fmt.Sprintf("avatar_%d_%d%s", user.ID, time.Now().UnixMilli(), ext)
	saved, err := h.saveUploadedObject(c, file, buildUploadObjectKey("avatars", filename), contentType, header.Size, "avatar", header.Filename)
	if err != nil {

		response.Error(c, http.StatusInternalServerError, "保存文件失败")

		return
	}
	response.Success(c, gin.H{

		"url": saved.URL,

		"media_id": saved.MediaID,

		"checksum": saved.Checksum,

		"filename": filename,

		"size": header.Size,

		"type": "avatar",
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
	var results []gin.H
	var failed []gin.H
	userUUID := c.GetString("user_id")
	var user models.User
	if err := h.db.Where("uuid = ?", userUUID).First(&user).Error; err != nil {

		response.Error(c, http.StatusUnauthorized, "用户未登录")

		return
	}
	c.Set("upload_user_id", user.ID)
	maxSize := getUploadLimitBytes(h.db, user.ID, "image")
	for _, header := range files {
		fail := func(message string) {

			failed = append(failed, gin.H{

				"filename": header.Filename,

				"size": header.Size,

				"error": message,
			})

		}

		if header.Size > maxSize {

			fail(fmt.Sprintf("图片大小不能超过%dMB", maxSize/1024/1024))

			continue

		}
		file, err := header.Open()

		if err != nil {

			fail("打开文件失败")

			continue

		}
		contentType, ext, err := validateImageUpload(file, header)

		if err != nil {

			file.Close()

			fail("不支持的图片格式")

			continue

		}

		// 生成文件名

		filename := fmt.Sprintf("%s_%d%s", uuid.New().String()[:8], time.Now().UnixNano(), ext)
		saved, err := h.saveUploadedObject(c, file, buildUploadObjectKey("images", dateDir, filename), contentType, header.Size, "image", header.Filename)

		file.Close()

		if err != nil {

			fail("保存文件失败")

			continue

		}
		results = append(results, gin.H{

			"url": saved.URL,

			"media_id": saved.MediaID,

			"checksum": saved.Checksum,

			"mime_type": contentType,

			"filename": filename,

			"original": header.Filename,

			"size": header.Size,

			"type": "image",
		})
	}
	if len(results) == 0 {

		c.JSON(http.StatusBadRequest, response.Response{

			Code: response.CodeBadRequest,

			Message: "没有文件上传成功",

			Data: gin.H{

				"files": results,

				"count": len(results),

				"failed": failed,

				"failed_count": len(failed),
			},
		})

		return
	}
	response.Success(c, gin.H{

		"files": results,

		"count": len(results),

		"failed": failed,

		"failed_count": len(failed),
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
	contentType, ext, err := validateAudioUpload(file, header)
	if err != nil {

		response.Error(c, http.StatusBadRequest, "不支持的音频格式")

		return
	}
	// 获取用户ID并检查上传限制
	userUUID := c.GetString("user_id")
	var user models.User
	if err := h.db.Where("uuid = ?", userUUID).First(&user).Error; err != nil {

		response.Error(c, http.StatusUnauthorized, "用户未登录")

		return
	}
	c.Set("upload_user_id", user.ID)
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
	filename := fmt.Sprintf("%s_%d%s", uuid.New().String()[:8], time.Now().UnixMilli(), ext)
	// 按日期分目录
	dateDir := time.Now().Format("2006/01/02")
	saved, err := h.saveUploadedObject(c, file, buildUploadObjectKey("voices", dateDir, filename), contentType, header.Size, "voice", header.Filename)
	if err != nil {

		response.Error(c, http.StatusInternalServerError, "保存文件失败")

		return
	}
	response.Success(c, gin.H{

		"url": saved.URL,

		"media_id": saved.MediaID,

		"checksum": saved.Checksum,

		"mime_type": contentType,

		"filename": filename,

		"size": header.Size,

		"duration": duration,

		"type": "voice",
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
	contentType, ext, err := validateGenericFileUpload(file, header)
	if err != nil {

		response.Error(c, http.StatusBadRequest, err.Error())

		return
	}
	// 获取用户ID并检查上传限制
	userUUID := c.GetString("user_id")
	var user models.User
	if err := h.db.Where("uuid = ?", userUUID).First(&user).Error; err != nil {

		response.Error(c, http.StatusUnauthorized, "用户未登录")

		return
	}
	c.Set("upload_user_id", user.ID)
	// 检查文件大小
	maxSize := h.effectiveProxyUploadLimit(getUploadLimitBytes(h.db, user.ID, "file"), "file")
	if header.Size > maxSize {

		response.Error(c, http.StatusBadRequest, fmt.Sprintf("文件大小不能超过%dMB", maxSize/1024/1024))

		return
	}
	// 生成文件名（仅保留服务端白名单校验后的扩展名）
	filename := fmt.Sprintf("%s_%d%s", uuid.New().String()[:8], time.Now().UnixMilli(), ext)
	// 按日期分目录
	dateDir := time.Now().Format("2006/01/02")
	saved, err := h.saveUploadedObject(c, file, buildUploadObjectKey("files", dateDir, filename), contentType, header.Size, "file", header.Filename)
	if err != nil {

		response.Error(c, http.StatusInternalServerError, "保存文件失败")

		return
	}
	response.Success(c, gin.H{

		"url": saved.URL,

		"media_id": saved.MediaID,

		"checksum": saved.Checksum,

		"mime_type": contentType,

		"filename": filename,

		"originalName": header.Filename,

		"size": header.Size,

		"type": "file",
	})
}
