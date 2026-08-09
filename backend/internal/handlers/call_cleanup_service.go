// 文件用途：实现后端 HTTP 接口的请求处理和统一响应。
// 核心逻辑：绑定参数，校验身份与权限，调用业务服务并持久化关键状态。

package handlers

import (
	"context"
	"gorm.io/gorm"
	"log"
	"sync"
	"time"
	"genericim/internal/models"
	"genericim/internal/services"
)

// CallCleanupService releases stale one-to-one calls that were left active
// after network loss, app kill, or a missed client-side hangup callback.

type CallCleanupService struct {
	db        *gorm.DB
	wsHub     WebSocketHub
	msgSvc    *services.MessageService
	ticker    *time.Ticker
	stopCh    chan struct{}
	doneCh    chan struct{}
	stopOnce  sync.Once
	started   bool
	batchSize int
}

func NewCallCleanupService(db *gorm.DB, wsHub WebSocketHub, msgSvc *services.MessageService) *CallCleanupService {
	return &CallCleanupService{
		db:        db,
		wsHub:     wsHub,
		msgSvc:    msgSvc,
		stopCh:    make(chan struct{}),
		doneCh:    make(chan struct{}),
		batchSize: 100,
	}
}

func (s *CallCleanupService) Start() {
	if s == nil || s.db == nil || s.started {
		return
	}
	s.started = true
	s.ticker = time.NewTicker(callCleanupInterval)
	go s.loop()
	log.Println("[CallCleanup] 定时清理任务已启动")
}

func (s *CallCleanupService) Stop() {
	if s == nil || !s.started {
		return
	}
	s.stopOnce.Do(func() {
		close(s.stopCh)
		<-s.doneCh
	})
}

func (s *CallCleanupService) loop() {
	defer close(s.doneCh)
	defer func() {
		if s.ticker != nil {
			s.ticker.Stop()
		}
		log.Println("[CallCleanup] 定时清理任务已停止")
	}()
	s.processStaleCalls()
	for {
		select {
		case <-s.stopCh:
			return
		case <-s.ticker.C:
			s.processStaleCalls()
		}
	}
}

func (s *CallCleanupService) processStaleCalls() {
	now := time.Now()
	var calls []models.Call
	if err := s.db.Where(
		"(status = ? AND start_time <= ?) OR(status = ? AND COALESCE(last_heartbeat_at, connect_time, start_time) <= ?)",
		"calling",
		now.Add(-callRingingTimeout),
		"connected",
		now.Add(-callHeartbeatStale),
	).Limit(s.batchSize).Find(&calls).Error; err != nil {
		log.Printf("[CallCleanup] 查询残留通话失败: %v", err)
		return
	}
	if len(calls) == 0 {
		return
	}
	cleaned := 0

	for _, call := range calls {
		if s.finalizeStaleCall(call, now) {
			cleaned++
		}
	}
	if cleaned > 0 {
		log.Printf("[CallCleanup] 已自动释放 %d 个残留通话", cleaned)
	}
}

func staleCallCleanupDecision(call models.Call, now time.Time) (status string, reason string, duration int, ok bool) {
	if isStaleCallingCall(call, now) {
		return "missed", "timeout", 0, true
	}
	if isStaleConnectedCall(call, now) {
		return "ended", "heartbeat_timeout", callConnectedDurationSeconds(call, now), true
	}
	return "", "", 0, false
}

func (s *CallCleanupService) finalizeStaleCall(call models.Call, now time.Time) bool {
	startedAt := time.Now()
	oldStatus := call.Status
	status, reason, duration, ok := staleCallCleanupDecision(call, now)
	if !ok {
		return false
	}
	result := s.db.Model(&models.Call{}).
		Where("id = ? AND status = ?", call.ID, call.Status).
		Updates(map[string]interface{}{
			"status":     status,
			"end_time":   now,
			"duration":   duration,
			"end_reason": reason,
			"updated_at": now,
		})
	if result.Error != nil {
		log.Printf("[CallCleanup] 释放残留通话失败 call_id=%d err=%v", call.ID, result.Error)
		return false
	}
	if result.RowsAffected == 0 {
		return false
	}
	call.Status = status
	call.EndTime = callTimePtr(now)
	call.Duration = duration
	call.EndReason = reason
	eventType := "ringing_timeout"
	if reason == "heartbeat_timeout" {
		eventType = "heartbeat_timeout"
	}
	recordCallObservability(s.db, callAuditEvent{
		CallID:    uint64(call.ID),
		EventType: eventType,
		CallerID:  call.CallerID,
		CalleeID:  call.CalleeID,
		OldStatus: oldStatus,
		NewStatus: call.Status,
		Reason:    call.EndReason,
		Duration:  call.Duration,
		LatencyMS: time.Since(startedAt).Milliseconds(),
		Payload: map[string]interface{}{
			"cleanup_service": true,
		},
	})
	s.notifyCleanedCall(call)
	return true
}

func (s *CallCleanupService) notifyCleanedCall(call models.Call) {
	var caller, callee models.User
	if err := s.db.First(&caller, call.CallerID).Error; err != nil {
		return
	}
	if err := s.db.First(&callee, call.CalleeID).Error; err != nil {
		return
	}
	if s.wsHub != nil {
		releasePayload := callReleasePayload(call)
		s.wsHub.SendToUser(caller.UUID, map[string]interface{}{
			"type": "call_released",
			"data": releasePayload,
		})
		s.wsHub.SendToUser(callee.UUID, map[string]interface{}{
			"type": "call_released",
			"data": releasePayload,
		})

		switch call.Status {
		case "missed":
			s.wsHub.SendToUser(caller.UUID, map[string]interface{}{
				"type": "call_rejected",
				"data": map[string]interface{}{
					"call_id": call.ID,
					"reason":  call.EndReason,
				},
			})
			s.wsHub.SendToUser(callee.UUID, map[string]interface{}{
				"type": "call_cancelled",
				"data": map[string]interface{}{
					"call_id": call.ID,
					"reason":  call.EndReason,
				},
			})
		default:
			payload := map[string]interface{}{
				"call_id":  call.ID,
				"reason":   call.EndReason,
				"duration": call.Duration,
			}
			s.wsHub.SendToUser(caller.UUID, map[string]interface{}{
				"type": "call_ended",
				"data": payload,
			})
			s.wsHub.SendToUser(callee.UUID, map[string]interface{}{
				"type": "call_ended",
				"data": payload,
			})
		}
	}
	if s.msgSvc != nil {
		h := &CallHandler{db: s.db, wsHub: s.wsHub, msgService: s.msgSvc}
		h.sendCallMessage(context.Background(), &caller, &callee, &call)
	}
}
