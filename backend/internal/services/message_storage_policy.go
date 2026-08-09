// 文件用途：实现可复用的后端业务服务和领域逻辑。
// 核心逻辑：协调数据库、缓存、队列和外部服务，集中处理事务、幂等、重试和错误传播。

package services

import (
	"strings"
	"time"
	"genericim/internal/models"
)

const defaultMessageRetentionMonths = 120

type MessageRecoveryCapabilities struct {
	RetentionMonths   int    `json:"retention_months"`
	IdempotencyMonths int    `json:"idempotency_months"`
	E2EERecoveryMode  string `json:"e2ee_recovery_mode"`
}

func normalizeMessageRetentionMonths(months int) int {
	if months <= 0 {
		return defaultMessageRetentionMonths
	}
	return months
}

// messageCollectionNames
//

func messageCollectionNames(chatID string, now time.Time, retentionMonths int) []string {
	retentionMonths = normalizeMessageRetentionMonths(retentionMonths)
	names := make([]string, 0, retentionMonths+1)
	seen := make(map[string]struct{}, retentionMonths+1)
	for i := 0; i < retentionMonths; i++ {
		name := models.GetMessageCollection(chatID, now.AddDate(0, -i, 0))
		if _, exists := seen[name]; exists {
			continue
		}
		seen[name] = struct{}{}
		names = append(names, name)
	}
	if _, exists := seen["messages"]; !exists {
		names = append(names, "messages")
	}
	return names
}

func isMessageCollectionInsideRetention(name string, now time.Time, retentionMonths int) bool {
	if name == "messages" {
		return true
	}
	if !strings.HasPrefix(name, "messages_") || len(name) != len("messages_200601") {
		return false
	}
	parsed, err := time.ParseInLocation("messages_200601", name, now.Location())
	if err != nil {
		return false
	}
	oldest := time.Date(now.Year(), now.Month(), 1, 0, 0, 0, 0, now.Location()).
		AddDate(0, -(normalizeMessageRetentionMonths(retentionMonths) - 1), 0)
	return !parsed.Before(oldest) && !parsed.After(now)
}

func (s *MessageService) RecoveryCapabilities() MessageRecoveryCapabilities {
	retentionMonths := defaultMessageRetentionMonths
	idempotencyMonths := defaultMessageRetentionMonths
	if s != nil {
		retentionMonths = normalizeMessageRetentionMonths(s.retentionMonths)
		idempotencyMonths = s.idempotencyMonths
		if idempotencyMonths < retentionMonths {
			idempotencyMonths = retentionMonths
		}
	}
	return MessageRecoveryCapabilities{
		RetentionMonths: retentionMonths, IdempotencyMonths: idempotencyMonths,
		E2EERecoveryMode: "trusted_device_rewrap",
	}
}
