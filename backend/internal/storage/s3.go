package storage

import (
	"bytes"
	"context"
	"fmt"
	"path/filepath"
	"strings"
	"time"

	"github.com/aws/aws-sdk-go-v2/aws"
	"github.com/aws/aws-sdk-go-v2/config"
	"github.com/aws/aws-sdk-go-v2/credentials"
	"github.com/aws/aws-sdk-go-v2/feature/s3/manager"
	"github.com/aws/aws-sdk-go-v2/service/s3"
	"github.com/google/uuid"
)

// S3Storage AWS S3 存储层
type S3Storage struct {
	client     *s3.Client
	uploader   *manager.Uploader
	bucket     string
	cdnBaseURL string
	region     string
}

// S3Config S3 配置
type S3Config struct {
	Region          string `yaml:"region"`
	Bucket          string `yaml:"bucket"`
	AccessKeyID     string `yaml:"access_key_id"`
	SecretAccessKey string `yaml:"secret_access_key"`
	CDNBaseURL      string `yaml:"cdn_base_url"`
	Endpoint        string `yaml:"endpoint"`
}

// NewS3Storage 初始化 S3 存储
func NewS3Storage(cfg S3Config) (*S3Storage, error) {
	opts := []func(*config.LoadOptions) error{
		config.WithRegion(cfg.Region),
		config.WithCredentialsProvider(
			credentials.NewStaticCredentialsProvider(cfg.AccessKeyID, cfg.SecretAccessKey, ""),
		),
	}

	awsCfg, err := config.LoadDefaultConfig(context.Background(), opts...)
	if err != nil {
		return nil, fmt.Errorf("S3 config error: %w", err)
	}

	var client *s3.Client
	if cfg.Endpoint != "" {
		client = s3.NewFromConfig(awsCfg, func(o *s3.Options) {
			o.BaseEndpoint = aws.String(cfg.Endpoint)
			o.UsePathStyle = true
		})
	} else {
		client = s3.NewFromConfig(awsCfg)
	}

	uploader := manager.NewUploader(client, func(u *manager.Uploader) {
		u.PartSize = 10 * 1024 * 1024
		u.Concurrency = 4
	})

	return &S3Storage{
		client:     client,
		uploader:   uploader,
		bucket:     cfg.Bucket,
		cdnBaseURL: strings.TrimRight(cfg.CDNBaseURL, "/"),
		region:     cfg.Region,
	}, nil
}

// UploadResult 上传结果
type UploadResult struct {
	URL  string
	Key  string
	Size int64
}

// Upload 上传文件到 S3
// category: images / videos / avatars / voices / files / discover
func (s *S3Storage) Upload(ctx context.Context, data []byte, category, filename, contentType string) (*UploadResult, error) {
	date := time.Now().Format("2006/01/02")
	ext := filepath.Ext(filename)
	if ext == "" {
		ext = extensionByContentType(contentType)
	}
	uniqueName := fmt.Sprintf("%s_%d%s", uuid.New().String()[:8], time.Now().UnixMilli(), ext)
	key := fmt.Sprintf("%s/%s/%s", category, date, uniqueName)

	_, err := s.uploader.Upload(ctx, &s3.PutObjectInput{
		Bucket:      aws.String(s.bucket),
		Key:         aws.String(key),
		Body:        bytes.NewReader(data),
		ContentType: aws.String(contentType),
	})
	if err != nil {
		return nil, fmt.Errorf("S3 upload failed: %w", err)
	}

	return &UploadResult{URL: s.buildURL(key), Key: key, Size: int64(len(data))}, nil
}

// Delete 删除 S3 对象
func (s *S3Storage) Delete(ctx context.Context, key string) error {
	_, err := s.client.DeleteObject(ctx, &s3.DeleteObjectInput{
		Bucket: aws.String(s.bucket),
		Key:    aws.String(key),
	})
	return err
}

// buildURL 构建访问 URL
func (s *S3Storage) buildURL(key string) string {
	if s.cdnBaseURL != "" {
		return s.cdnBaseURL + "/" + key
	}
	return fmt.Sprintf("https://%s.s3.%s.amazonaws.com/%s", s.bucket, s.region, key)
}

// extensionByContentType 根据 MIME 类型推断扩展名
func extensionByContentType(ct string) string {
	switch ct {
	case "image/jpeg", "image/jpg":
		return ".jpg"
	case "image/png":
		return ".png"
	case "image/gif":
		return ".gif"
	case "image/webp":
		return ".webp"
	case "image/heic", "image/heif":
		return ".heic"
	case "video/mp4":
		return ".mp4"
	case "video/quicktime":
		return ".mov"
	case "video/webm":
		return ".webm"
	case "audio/mpeg":
		return ".mp3"
	case "audio/mp4", "audio/x-m4a":
		return ".m4a"
	case "audio/aac":
		return ".aac"
	case "audio/wav":
		return ".wav"
	case "audio/ogg":
		return ".ogg"
	default:
		return ""
	}
}
