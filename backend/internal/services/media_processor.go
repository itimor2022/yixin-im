// 文件用途：实现可复用的后端业务服务和领域逻辑。
// 核心逻辑：协调数据库、缓存、队列和外部服务，集中处理事务、幂等、重试和错误传播。

package services

import (
	"bytes"
	"context"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	"golang.org/x/sync/singleflight"
	"gorm.io/gorm" // ErrMediaProcessorUnavailable 表示运行环境缺少 ffmpeg/ffprobe，调用方可降级返回原文件。
	"io"
	"net/http"
	"os"
	"os/exec"
	"path"
	"path/filepath"
	"strconv"
	"strings"
	"time"
	"genericim/internal/config"
	"genericim/internal/models"
)

var ErrMediaProcessorUnavailable = errors.New("media processor unavailable")
var mediaProcessingGroup singleflight.Group // ProcessedMedia 汇总可展示主文件、缩略图和探测得到的媒体属性。
type ProcessedMedia struct {
	Primary    *models.MediaObject
	Thumbnail  *models.MediaObject
	Width      int
	Height     int
	DurationMS int
	Transcoded bool
}
type mediaProbe struct {
	Streams []struct {
		CodecName string `json:"codec_name"`

		CodecType string `json:"codec_type"`

		Width int `json:"width"`

		Height int `json:"height"`

		Duration string `json:"duration"`
	} `json:"streams"`
	Format struct {
		Duration string `json:"duration"`
	} `json:"format"`
} // ProcessUploadedMedia 在受限超时内生成图片缩略图、规范化 HEIC/HEIF 或视频，并生成派生对象。 // 原对象保持不变；派生文件以独立 MediaObject 持久化，便于失败重试和后续独立清理。
func ProcessUploadedMedia(
	ctx context.Context,
	db *gorm.DB,
	cfg config.StorageConfig,
	source *models.MediaObject) (*ProcessedMedia, error) {
	if db == nil || source == nil {

		return nil, nil
	}
	cfg.Provider = NormalizeStorageProvider(source.Provider)
	if source.Category != "image" && source.Category != "video" {

		return nil, nil
	}
	value, err, _ := mediaProcessingGroup.Do(source.MediaID, func() (interface{}, error) {

		// 媒体处理不能依赖发起 complete/status 的 HTTP 连接一直存活。

		// 请求断开后仍由内部 deadline 约束并完成当前派生任务。

		return processUploadedMedia(context.WithoutCancel(ctx), db, cfg, source)
	})
	if err != nil || value == nil {

		return nil, err
	}
	return value.(*ProcessedMedia), nil
}
func processUploadedMedia(
	ctx context.Context,
	db *gorm.DB,
	cfg config.StorageConfig,
	source *models.MediaObject) (*ProcessedMedia, error) {
	if db == nil || source == nil {

		return nil, nil
	}
	cfg.Provider = NormalizeStorageProvider(source.Provider)
	if source.Category != "image" && source.Category != "video" {

		return nil, nil
	}
	if existing := loadExistingProcessedMedia(db, source); existing != nil {

		return existing, nil
	}
	ffmpeg, err := exec.LookPath("ffmpeg")
	if err != nil {

		return nil, ErrMediaProcessorUnavailable
	}
	ffprobe, err := exec.LookPath("ffprobe")
	if err != nil {

		return nil, ErrMediaProcessorUnavailable
	}
	timeout := mediaProcessingTimeout()
	// 外部进程、预签名下载和派生文件上传共享同一 deadline，
	// 防止损坏媒体或慢速对象长期占用 ffmpeg 和临时磁盘。
	processCtx, cancel := context.WithTimeout(ctx, timeout)
	defer cancel()
	sourceInput := strings.TrimSpace(source.URL)
	if cfg.Provider == StorageProviderLocal {

		localPath, err := localObjectFilePath(source.ObjectKey)
		if err != nil {

			return nil, err
		}
		sourceInput = localPath
	} else if cfg.Provider == StorageProviderS3 {

		sourceURL, err := PresignS3GetObject(

			processCtx, cfg, source.ObjectKey, source.OriginalName, timeout,
		)
		if err != nil {

			return nil, err
		}
		sourceInput = sourceURL.URL
	}
	if sourceInput == "" {

		return nil, fmt.Errorf("uploaded media source URL is empty")
	}
	sourceDownloaded := cfg.Provider == StorageProviderLocal
	cleanupSource := func() {}
	defer func() { cleanupSource() }()
	ensureSourceDownloaded := func() error {

		if sourceDownloaded {

			return nil

		}
		input, cleanup, downloadErr := downloadTemporaryMedia(

			processCtx,

			sourceInput,

			"media-source-*"+source.NormalizedExt,

			source.SizeBytes,
		)

		if downloadErr != nil {

			return downloadErr

		}
		sourceInput = input

		sourceDownloaded = true

		cleanupSource = cleanup

		return nil
	}
	if source.NormalizedExt == ".heic" || source.NormalizedExt == ".heif" {

		if err := ensureSourceDownloaded(); err != nil {

			return nil, err

		}
		heifConvert, lookupErr := exec.LookPath("heif-convert")

		if lookupErr != nil {

			return nil, ErrMediaProcessorUnavailable

		}

		// 临时文件由 defer 无条件移除；只有 storeProcessedFile 完成后才会出现可引用的数据库对象。

		output, cleanup, err := temporaryMediaPath("image-preview-*.jpg")

		if err != nil {

			return nil, err

		}

		defer cleanup()

		defer cleanupHEIFOutputs(output)

		if err := runMediaCommand(

			processCtx,

			heifConvert,

			"-q", "90",

			sourceInput,

			output,
		); err != nil {

			return nil, err

		}
		convertedOutput, err := resolveHEIFOutput(output)

		if err != nil {

			return nil, err

		}
		probe, err := probeMedia(processCtx, ffprobe, convertedOutput)

		if err != nil {

			return nil, err

		}
		width, height, _ := probe.dimensionsAndDuration()
		result := &ProcessedMedia{

			Primary: source,

			Width: width,

			Height: height,
		}
		derived, err := storeProcessedFile(

			processCtx, db, cfg, source, convertedOutput,

			"image", ".jpg", "image/jpeg", "display",
		)

		if err != nil {

			return nil, err

		}

		result.Primary = derived

		thumbnail, err := createImageThumbnail(

			processCtx, ffmpeg, db, cfg, source, convertedOutput,
		)

		if err != nil {

			return nil, err

		}

		result.Thumbnail = thumbnail

		return result, nil
	}
	if source.Category == "image" {

		if err := ensureSourceDownloaded(); err != nil {

			return nil, err

		}
	}
	probe, err := probeMedia(processCtx, ffprobe, sourceInput)
	if err != nil {

		return nil, err
	}
	width, height, durationMS := probe.dimensionsAndDuration()
	result := &ProcessedMedia{

		Primary: source,

		Width: width,

		Height: height,

		DurationMS: durationMS,
	}
	if source.Category == "image" {

		thumbnail, err := createImageThumbnail(

			processCtx, ffmpeg, db, cfg, source, sourceInput,
		)

		if err != nil {

			return nil, err

		}

		result.Thumbnail = thumbnail

		return result, nil
	}
	primaryInput := sourceInput
	if probe.needsVideoTranscode(source.NormalizedExt) {

		if err := ensureSourceDownloaded(); err != nil {

			return nil, err

		}
		output, cleanup, err := temporaryMediaPath("video-normalized-*.mp4")

		if err != nil {

			return nil, err

		}

		defer cleanup()

		if err := runMediaCommand(

			processCtx,

			ffmpeg,

			"-hide_banner", "-loglevel", "error",

			"-i", sourceInput,

			"-map", "0:v:0", "-map", "0:a?",

			"-c:v", "libx264", "-preset", "veryfast", "-crf", "23",

			"-c:a", "aac", "-b:a", "128k",

			"-movflags", "+faststart",

			"-y", output,
		); err != nil {

			return nil, err

		}
		derived, err := storeProcessedFile(

			processCtx, db, cfg, source, output,

			"video", ".mp4", "video/mp4", "normalized",
		)

		if err != nil {

			return nil, err

		}

		result.Primary = derived

		result.Transcoded = true

		primaryInput = output
	}
	thumbnailPath, cleanup, err := temporaryMediaPath("video-thumbnail-*.jpg")
	if err != nil {

		return nil, err
	}
	defer cleanup()
	if err := createVideoThumbnailFile(

		processCtx, ffmpeg, primaryInput, thumbnailPath,
	); err != nil {

		if !isHTTPMediaInput(primaryInput) {

			return nil, err

		}

		if err := ensureSourceDownloaded(); err != nil {

			return nil, err

		}

		if err := createVideoThumbnailFile(

			processCtx, ffmpeg, sourceInput, thumbnailPath,
		); err != nil {

			return nil, err

		}
	}
	thumbnail, err := storeProcessedFile(

		processCtx, db, cfg, source, thumbnailPath,

		"image", ".jpg", "image/jpeg", "thumbnail",
	)
	if err != nil {

		return nil, err
	}
	result.Thumbnail = thumbnail
	return result, nil
}
func createVideoThumbnailFile(
	ctx context.Context,
	ffmpeg, input, output string) error {
	args := []string{"-hide_banner", "-loglevel", "error"}
	if isHTTPMediaInput(input) {

		args = append(args,

			"-reconnect", "1",

			"-reconnect_streamed", "1",

			"-reconnect_delay_max", "5",

			"-rw_timeout", "30000000",
		)
	}
	args = append(args,

		"-ss", "0.1",

		"-i", input,

		"-frames:v", "1",

		"-vf", "scale=min(640\\,iw):-2",

		"-q:v", "3",

		"-y", output,
	)
	return runMediaCommand(ctx, ffmpeg, args...)
}
func isHTTPMediaInput(input string) bool {
	value := strings.ToLower(strings.TrimSpace(input))
	return strings.HasPrefix(value, "http://") || strings.HasPrefix(value, "https://")
}
func loadExistingProcessedMedia(
	db *gorm.DB,
	source *models.MediaObject) *ProcessedMedia {
	if db == nil || source == nil {

		return nil
	}
	loadReady := func(variant string) *models.MediaObject {
		var item models.MediaObject

		err := db.Where(

			"user_id = ? AND client_request_id = ? AND status IN ?",

			source.UserID,

			"derived-"+variant+":"+source.MediaID,

			[]string{

				models.MediaObjectStatusUploaded,

				models.MediaObjectStatusBinding,

				models.MediaObjectStatusBound,
			},
		).First(&item).Error

		if err != nil {

			return nil

		}

		return &item
	}
	thumbnail := loadReady("thumbnail")
	if thumbnail == nil {

		return nil
	}
	result := &ProcessedMedia{Primary: source, Thumbnail: thumbnail}
	switch source.Category {
	case "image":

		if source.NormalizedExt == ".heic" || source.NormalizedExt == ".heif" {

			result.Primary = loadReady("display")

			if result.Primary == nil {

				return nil

			}

		}
	case "video":

		if normalized := loadReady("normalized"); normalized != nil {

			result.Primary = normalized

			result.Transcoded = true

		}
	}
	return result
}
func createImageThumbnail(
	ctx context.Context,
	ffmpeg string,
	db *gorm.DB,
	cfg config.StorageConfig,
	source *models.MediaObject,
	input string) (*models.MediaObject, error) {
	thumbnailPath, cleanup, err := temporaryMediaPath("image-thumbnail-*.jpg")
	if err != nil {

		return nil, err
	}
	defer cleanup()
	if err := runMediaCommand(

		ctx,

		ffmpeg,

		"-hide_banner", "-loglevel", "error",

		"-i", input,

		"-frames:v", "1",

		"-vf", "scale='min(640,iw)':'min(640,ih)':force_original_aspect_ratio=decrease",

		"-q:v", "3",

		"-y", thumbnailPath,
	); err != nil {

		return nil, err
	}
	return storeProcessedFile(

		ctx, db, cfg, source, thumbnailPath,

		"image", ".jpg", "image/jpeg", "thumbnail",
	)
}
func downloadTemporaryMedia(
	ctx context.Context,
	sourceURL, pattern string,
	expectedSize int64) (string, func(), error) {
	var lastErr error
	for attempt := 1; attempt <= 3; attempt++ {

		filePath, cleanup, err := downloadTemporaryMediaOnce(

			ctx, sourceURL, pattern, expectedSize,
		)

		if err == nil {

			return filePath, cleanup, nil

		}
		lastErr = err

		if attempt < 3 {

			timer := time.NewTimer(time.Duration(attempt) * 250 * time.Millisecond)

			select {

			case <-ctx.Done():

				timer.Stop()

				return "", func() {}, ctx.Err()

			case <-timer.C:

			}

		}
	}
	return "", func() {}, lastErr
}
func downloadTemporaryMediaOnce(
	ctx context.Context,
	sourceURL, pattern string,
	expectedSize int64) (string, func(), error) {
	file, err := os.CreateTemp("", pattern)
	if err != nil {

		return "", func() {}, err
	}
	filePath := file.Name()
	cleanup := func() { _ = os.Remove(filePath) }
	request, err := http.NewRequestWithContext(ctx, http.MethodGet, sourceURL, nil)
	if err != nil {

		_ = file.Close()

		cleanup()

		return "", func() {}, err
	}
	response, err := http.DefaultClient.Do(request)
	if err != nil {

		_ = file.Close()

		cleanup()

		return "", func() {}, err
	}
	defer response.Body.Close()
	if response.StatusCode < http.StatusOK || response.StatusCode >= http.StatusMultipleChoices {

		_ = file.Close()

		cleanup()

		return "", func() {}, fmt.Errorf(

			"download media source: unexpected HTTP %d", response.StatusCode,
		)
	}
	reader := io.Reader(response.Body)
	if expectedSize > 0 {

		reader = io.LimitReader(response.Body, expectedSize+1)
	}
	written, copyErr := io.Copy(file, reader)
	closeErr := file.Close()
	if copyErr != nil {

		cleanup()

		return "", func() {}, fmt.Errorf("download media source: %w", copyErr)
	}
	if closeErr != nil {

		cleanup()

		return "", func() {}, closeErr
	}
	if expectedSize > 0 && written != expectedSize {

		cleanup()

		return "", func() {}, fmt.Errorf(

			"download media source: size mismatch, expected %d got %d",

			expectedSize,

			written,
		)
	}
	return filePath, cleanup, nil
}
func resolveHEIFOutput(requestedPath string) (string, error) {
	if stat, err := os.Stat(requestedPath); err == nil && stat.Size() > 0 {

		return requestedPath, nil
	}
	ext := filepath.Ext(requestedPath)
	base := strings.TrimSuffix(requestedPath, ext)
	candidates, err := filepath.Glob(base + "-*" + ext)
	if err != nil {

		return "", err
	}
	for _, candidate := range candidates {

		if stat, statErr := os.Stat(candidate); statErr == nil && stat.Size() > 0 {

			return candidate, nil

		}
	}
	return "", fmt.Errorf("HEIF conversion did not produce an image")
}
func cleanupHEIFOutputs(requestedPath string) {
	ext := filepath.Ext(requestedPath)
	base := strings.TrimSuffix(requestedPath, ext)
	candidates, _ := filepath.Glob(base + "-*" + ext)
	for _, candidate := range candidates {

		_ = os.Remove(candidate)
	}
}
func probeMedia(ctx context.Context, ffprobe, sourceURL string) (*mediaProbe, error) {
	attempts := 1
	if isHTTPMediaInput(sourceURL) {

		attempts = 3
	}
	var lastErr error
	for attempt := 1; attempt <= attempts; attempt++ {

		probe, err := probeMediaOnce(ctx, ffprobe, sourceURL)

		if err == nil {

			return probe, nil

		}
		lastErr = err

		if attempt < attempts {

			timer := time.NewTimer(time.Duration(attempt) * 250 * time.Millisecond)

			select {

			case <-ctx.Done():

				timer.Stop()

				return nil, ctx.Err()

			case <-timer.C:

			}

		}
	}
	return nil, lastErr
}
func probeMediaOnce(ctx context.Context, ffprobe, sourceURL string) (*mediaProbe, error) {
	args := []string{"-v", "error"}
	if isHTTPMediaInput(sourceURL) {

		args = append(args,

			"-reconnect", "1",

			"-reconnect_streamed", "1",

			"-reconnect_delay_max", "5",

			"-rw_timeout", "30000000",
		)
	}
	args = append(args,

		"-show_streams",

		"-show_format",

		"-of", "json",

		sourceURL,
	)
	cmd := exec.CommandContext(ctx, ffprobe, args...)
	var stdout bytes.Buffer
	var stderr bytes.Buffer
	cmd.Stdout = &stdout
	cmd.Stderr = &stderr
	err := cmd.Run()
	return decodeMediaProbe(stdout.Bytes(), stderr.Bytes(), err)
}
func decodeMediaProbe(stdout, stderr []byte, commandErr error) (*mediaProbe, error) {
	if commandErr != nil {

		detail := strings.TrimSpace(string(stderr))

		if detail == "" {

			detail = strings.TrimSpace(string(stdout))

		}

		if len(detail) > 500 {

			detail = detail[:500]

		}

		if detail != "" {

			return nil, fmt.Errorf("probe uploaded media: %w: %s", commandErr, detail)

		}

		return nil, fmt.Errorf("probe uploaded media: %w", commandErr)
	}
	var probe mediaProbe
	if err := json.Unmarshal(stdout, &probe); err != nil {

		return nil, fmt.Errorf("decode media probe: %w", err)
	}
	return &probe, nil
}
func (p *mediaProbe) dimensionsAndDuration() (int, int, int) {
	if p == nil {

		return 0, 0, 0
	}
	width, height := 0, 0
	duration := parseMediaSeconds(p.Format.Duration)
	for _, stream := range p.Streams {

		if stream.CodecType != "video" {

			continue

		}

		width, height = stream.Width, stream.Height

		if duration <= 0 {

			duration = parseMediaSeconds(stream.Duration)

		}

		break
	}
	return width, height, int(duration*1000 + 0.5)
}
func (p *mediaProbe) needsVideoTranscode(ext string) bool {
	if p == nil || (ext != ".mp4" && ext != ".m4v") {

		return true
	}
	videoCodec := ""
	audioCodec := ""
	for _, stream := range p.Streams {

		switch stream.CodecType {

		case "video":

			if videoCodec == "" {

				videoCodec = strings.ToLower(stream.CodecName)

			}

		case "audio":

			if audioCodec == "" {

				audioCodec = strings.ToLower(stream.CodecName)

			}

		}
	}
	return videoCodec != "h264" || (audioCodec != "" && audioCodec != "aac")
}
func parseMediaSeconds(raw string) float64 {
	value, _ := strconv.ParseFloat(strings.TrimSpace(raw), 64)
	if value < 0 {

		return 0
	}
	return value
}
func runMediaCommand(ctx context.Context, binary string, args ...string) error {
	output, err := exec.CommandContext(ctx, binary, args...).CombinedOutput()
	if err == nil {

		return nil
	}
	detail := strings.TrimSpace(string(output))
	if len(detail) > 500 {

		detail = detail[:500]
	}
	if detail == "" {

		return fmt.Errorf("media processing command failed: %w", err)
	}
	return fmt.Errorf("media processing command failed: %w: %s", err, detail)
}
func temporaryMediaPath(pattern string) (string, func(), error) {
	file, err := os.CreateTemp("", pattern)
	if err != nil {

		return "", func() {}, err
	}
	name := file.Name()
	if err := file.Close(); err != nil {

		_ = os.Remove(name)

		return "", func() {}, err
	}
	return name, func() { _ = os.Remove(name) }, nil
}
func storeProcessedFile(
	ctx context.Context,
	db *gorm.DB,
	cfg config.StorageConfig,
	source *models.MediaObject,
	filePath, category, ext, contentType, variant string) (*models.MediaObject, error) {
	requestID := "derived-" + variant + ":" + source.MediaID
	var existing models.MediaObject
	if err := db.Where(

		"user_id = ? AND client_request_id = ?", source.UserID, requestID,
	).First(&existing).Error; err == nil {

		if existing.Status == models.MediaObjectStatusUploaded ||

			existing.Status == models.MediaObjectStatusBinding ||

			existing.Status == models.MediaObjectStatusBound {

			return &existing, nil

		}
	} else if !errors.Is(err, gorm.ErrRecordNotFound) {

		return nil, err
	}
	file, err := os.Open(filePath)
	if err != nil {

		return nil, err
	}
	hash := sha256.New()
	size, err := io.Copy(hash, file)
	_ = file.Close()
	if err != nil {

		return nil, err
	}
	dateDir := time.Now().Format("2006/01/02")
	objectKey := path.Join(

		"uploads", category+"s", dateDir, source.MediaID+"_"+variant+ext,
	)
	provider := NormalizeStorageProvider(source.Provider)
	bucket := ""
	switch provider {
	case StorageProviderAliyun:

		bucket = cfg.Aliyun.Bucket
	case StorageProviderQiniu:

		bucket = cfg.Qiniu.Bucket
	case StorageProviderS3:

		bucket = cfg.S3.Bucket
	}
	item, err := BeginMediaUpload(db, BeginMediaUploadParams{

		UserID: source.UserID,

		ClientRequestID: requestID,

		Category: category,

		Provider: provider,

		Bucket: bucket,

		ObjectKey: objectKey,

		OriginalName: source.MediaID + "_" + variant + ext,

		NormalizedExt: ext,

		DeclaredMIME: contentType,

		DetectedMIME: contentType,

		SizeBytes: size,

		ExpectedSHA256: hex.EncodeToString(hash.Sum(nil)),

		UploadMode: "processed",
	})
	if err != nil {

		return nil, err
	}
	if item.Status == models.MediaObjectStatusUploaded ||

		item.Status == models.MediaObjectStatusBinding ||

		item.Status == models.MediaObjectStatusBound {

		return item, nil
	}
	file, err = os.Open(filePath)
	if err != nil {

		return nil, err
	}
	defer file.Close()
	url, err := UploadObject(ctx, cfg, item.ObjectKey, file, size, contentType)
	if err != nil {

		FailMediaUpload(db, item.ID, err)

		return nil, err
	}
	checksum := hex.EncodeToString(hash.Sum(nil))
	if err := CompleteMediaUpload(db, item.ID, url, checksum, false); err != nil {

		return nil, err
	}
	RememberUploadedMessageMedia(item, url, checksum)
	item.URL = url
	item.ChecksumSHA256 = checksum
	item.Status = models.MediaObjectStatusUploaded
	return item, nil
}
func mediaProcessingTimeout() time.Duration {
	const fallback = 30 * time.Minute
	raw := strings.TrimSpace(os.Getenv("GENERIC_IM_MEDIA_PROCESSING_TIMEOUT"))
	if raw == "" {

		return fallback
	}
	value, err := time.ParseDuration(raw)
	if err != nil || value < time.Minute {

		return fallback
	}
	return value
}
