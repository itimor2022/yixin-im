// 文件用途：实现可复用的后端业务服务和领域逻辑。
// 核心逻辑：协调数据库、缓存、队列和外部服务，集中处理事务、幂等、重试和错误传播。

package services

import (
	"context"
	"errors"
	"fmt"
	"gorm.io/gorm"
	"io"
	"net"
	"net/http"
	"net/url"
	"strings"
	"time"
	"genericim/internal/config"
	"genericim/internal/models"
)

var errObjectStorageURLNotMatched = errors.New("object storage url not matched")

// ExternalCleanupService
type ExternalCleanupService struct {
	db               *gorm.DB
	client           *http.Client
	ticker           *time.Ticker
	stopCh           chan struct{}
	doneCh           chan struct{}
	batchSize        int
	maxRetry         int
	enableHTTPDelete bool
	allowedHosts     map[string]struct{}
}

func NewExternalCleanupService(db *gorm.DB, enableHTTPDelete bool, allowedHosts []string) *ExternalCleanupService {
	return &ExternalCleanupService{
		db: db,
		client: &http.Client{
			Timeout: 8 * time.Second,
		},
		stopCh:           make(chan struct{}),
		doneCh:           make(chan struct{}),
		batchSize:        100,
		maxRetry:         6,
		enableHTTPDelete: enableHTTPDelete,
		allowedHosts:     buildAllowedHostSet(allowedHosts),
	}
}

func (s *ExternalCleanupService) Start() {
	if s == nil || s.db == nil {
		return
	}
	s.ticker = time.NewTicker(30 * time.Second)
	go s.loop()
}

func (s *ExternalCleanupService) Stop() {
	if s == nil {
		return
	}
	select {
	case <-s.stopCh:
		return
	default:
		close(s.stopCh)
	}
	<-s.doneCh
}

func (s *ExternalCleanupService) loop() {
	defer close(s.doneCh)
	defer func() {
		if s.ticker != nil {
			s.ticker.Stop()
		}
	}()
	s.processBatch()
	for {
		select {
		case <-s.stopCh:
			return
		case <-s.ticker.C:
			s.processBatch()
		}
	}
}

func (s *ExternalCleanupService) processBatch() {
	now := time.Now()
	var tasks []models.AccountDeletionExternalTask
	if err := s.db.
		Where("status IN ? AND(next_retry_at IS NULL OR next_retry_at <= ?)",
			[]string{models.AccountDeletionExternalTaskPending, models.AccountDeletionExternalTaskRetrying},
			now,
		).
		Order("id ASC").
		Limit(s.batchSize).
		Find(&tasks).Error; err != nil {
		return
	}
	if len(tasks) == 0 {
		return
	}
	storageCfg := s.currentStorageConfig()
	for _, task := range tasks {

		if err := s.tryDeleteObjectStorage(storageCfg, task.ResourceURL); err == nil {
			s.markSuccess(task.ID)
			continue
		} else if !errors.Is(err, errObjectStorageURLNotMatched) {
			s.markRetryOrFailed(task, err)
			continue
		}
		if !s.enableHTTPDelete {
			s.markManualRequired(task.ID, "http_delete_disabled")
			continue
		}
		if !s.isAllowedExternalURL(task.ResourceURL) {
			s.markManualRequired(task.ID, "host_not_allowed")
			continue
		}
		if err := s.tryDelete(task.ResourceURL); err == nil {
			s.markSuccess(task.ID)
			continue
		} else {
			s.markRetryOrFailed(task, err)
		}
	}
}

func (s *ExternalCleanupService) currentStorageConfig() config.StorageConfig {
	var yamlCfg config.StorageConfig
	if config.GlobalConfig != nil {
		yamlCfg = config.GlobalConfig.Storage
	}
	return LoadStorageForRuntime(s.db, yamlCfg)
}

func (s *ExternalCleanupService) tryDeleteObjectStorage(storageCfg config.StorageConfig, resourceURL string) error {
	objectKey, ok := ObjectKeyFromPublicURL(storageCfg, resourceURL)
	if !ok {
		return errObjectStorageURLNotMatched
	}
	ctx, cancel := context.WithTimeout(context.Background(), 15*time.Second)
	defer cancel()
	return DeleteObject(ctx, storageCfg, objectKey)
}

func (s *ExternalCleanupService) tryDelete(resourceURL string) error {
	rawURL := strings.TrimSpace(resourceURL)
	if !strings.HasPrefix(rawURL, "http://") && !strings.HasPrefix(rawURL, "https://") {
		return fmt.Errorf("unsupported external url: %s", rawURL)
	}

	req, err := http.NewRequest(http.MethodDelete, rawURL, nil)
	if err != nil {
		return err
	}
	resp, err := s.client.Do(req)
	if err != nil {
		return err
	}
	defer resp.Body.Close()
	_, _ = io.Copy(io.Discard, resp.Body)
	if (resp.StatusCode >= 200 && resp.StatusCode < 300) || resp.StatusCode == http.StatusNotFound || resp.StatusCode == http.StatusGone {
		return nil
	}
	return fmt.Errorf("delete status=%d", resp.StatusCode)
}

func retryBackoffDuration(retryCount int) time.Duration {
	if retryCount <= 0 {
		return time.Minute
	}
	d := time.Minute * time.Duration(1<<(retryCount-1))
	if d > 6*time.Hour {
		return 6 * time.Hour
	}
	return d
}

func trimAndClamp(v string, maxLen int) string {
	s := strings.TrimSpace(v)
	if maxLen <= 0 || len(s) <= maxLen {
		return s
	}
	return s[:maxLen]
}

func buildAllowedHostSet(hosts []string) map[string]struct{} {
	out := make(map[string]struct{}, len(hosts))
	for _, item := range hosts {
		host := strings.TrimSpace(strings.ToLower(item))
		if host == "" {
			continue
		}
		if strings.Contains(host, "://") {
			if parsed, err := url.Parse(host); err == nil {
				host = strings.ToLower(strings.TrimSpace(parsed.Hostname()))
			}
		}
		if h, _, err := net.SplitHostPort(host); err == nil {
			host = strings.ToLower(strings.TrimSpace(h))
		}
		if host == "" {
			continue
		}
		out[host] = struct{}{}
	}
	return out
}

func (s *ExternalCleanupService) isAllowedExternalURL(rawURL string) bool {
	if len(s.allowedHosts) == 0 {
		return false
	}
	parsed, err := url.Parse(strings.TrimSpace(rawURL))
	if err != nil || parsed == nil {
		return false
	}
	if parsed.Scheme != "http" && parsed.Scheme != "https" {
		return false
	}
	host := strings.ToLower(strings.TrimSpace(parsed.Hostname()))
	if host == "" {
		return false
	}
	_, ok := s.allowedHosts[host]
	return ok
}

func (s *ExternalCleanupService) markSuccess(taskID uint64) {
	finishedAt := time.Now()
	_ = s.db.Model(&models.AccountDeletionExternalTask{}).Where("id = ?", taskID).Updates(map[string]interface{}{
		"status":      models.AccountDeletionExternalTaskSuccess,
		"finished_at": finishedAt,
		"last_error":  "",
		"updated_at":  finishedAt,
	}).Error
}

func (s *ExternalCleanupService) markRetryOrFailed(task models.AccountDeletionExternalTask, err error) {

	retryCount := task.RetryCount + 1
	lastError := trimAndClamp(err.Error(), 500)
	if retryCount >= s.maxRetry {
		finishedAt := time.Now()
		_ = s.db.Model(&models.AccountDeletionExternalTask{}).Where("id = ?", task.ID).Updates(map[string]interface{}{
			"status":      models.AccountDeletionExternalTaskFailed,
			"retry_count": retryCount,
			"last_error":  lastError,
			"finished_at": finishedAt,
			"updated_at":  finishedAt,
		}).Error
		return
	}
	nextRetryAt := time.Now().Add(retryBackoffDuration(retryCount))
	_ = s.db.Model(&models.AccountDeletionExternalTask{}).Where("id = ?", task.ID).Updates(map[string]interface{}{
		"status":        models.AccountDeletionExternalTaskRetrying,
		"retry_count":   retryCount,
		"next_retry_at": nextRetryAt,
		"last_error":    lastError,
		"updated_at":    time.Now(),
	}).Error
}

func (s *ExternalCleanupService) markManualRequired(taskID uint64, reason string) {
	finishedAt := time.Now()
	_ = s.db.Model(&models.AccountDeletionExternalTask{}).Where("id = ?", taskID).Updates(map[string]interface{}{
		"status":      models.AccountDeletionExternalTaskManual,
		"last_error":  trimAndClamp(reason, 500),
		"finished_at": finishedAt,
		"updated_at":  finishedAt,
	}).Error
}
