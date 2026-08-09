// 文件用途：实现后端 HTTP 接口的请求处理和统一响应。
// 核心逻辑：绑定参数，校验身份与权限，调用业务服务并持久化关键状态。

package handlers

import (
	"encoding/json"
	"github.com/gin-gonic/gin"
	"gorm.io/gorm"
	"log"
	"sort"
	"strconv"
	"sync"
	"time"
	"genericim/internal/models"
)

const (
	callMetricCreateTotal              = "call_create_total"
	callMetricEndTotal                 = "call_end_total"
	callMetricStaleCleanupTotal        = "call_stale_cleanup_total"
	callMetricReplacedTotal            = "call_replaced_total"
	callMetricHeartbeatTimeoutTotal    = "call_heartbeat_timeout_total"
	callMetricCreateBlockedActiveTotal = "call_create_blocked_active_total"
)

type callMetricsCollector struct {
	mu                sync.Mutex
	counters          map[string]int64
	releaseLatencies  []int64
	maxLatencySamples int
}

func newCallMetricsCollector() *callMetricsCollector {
	return &callMetricsCollector{
		counters:          make(map[string]int64),
		maxLatencySamples: 2048,
	}
}

func (m *callMetricsCollector) Inc(name string) {
	if name == "" {
		return
	}
	m.mu.Lock()
	defer m.mu.Unlock()
	m.counters[name]++
}

func (m *callMetricsCollector) ObserveReleaseLatency(latencyMS int64) {
	if latencyMS < 0 {
		latencyMS = 0
	}
	m.mu.Lock()
	defer m.mu.Unlock()
	m.releaseLatencies = append(m.releaseLatencies, latencyMS)
	if len(m.releaseLatencies) > m.maxLatencySamples {
		excess := len(m.releaseLatencies) - m.maxLatencySamples
		copy(m.releaseLatencies, m.releaseLatencies[excess:])
		m.releaseLatencies = m.releaseLatencies[:m.maxLatencySamples]
	}
}

func (m *callMetricsCollector) Snapshot() gin.H {
	m.mu.Lock()
	defer m.mu.Unlock()
	counters := map[string]int64{
		callMetricCreateTotal:              m.counters[callMetricCreateTotal],
		callMetricEndTotal:                 m.counters[callMetricEndTotal],
		callMetricStaleCleanupTotal:        m.counters[callMetricStaleCleanupTotal],
		callMetricReplacedTotal:            m.counters[callMetricReplacedTotal],
		callMetricHeartbeatTimeoutTotal:    m.counters[callMetricHeartbeatTimeoutTotal],
		callMetricCreateBlockedActiveTotal: m.counters[callMetricCreateBlockedActiveTotal],
	}
	latencies := append([]int64(nil), m.releaseLatencies...)
	sort.Slice(latencies, func(i, j int) bool { return latencies[i] < latencies[j] })
	return gin.H{
		"counters": counters,
		"release_latency_ms": gin.H{
			"count": len(latencies),
			"avg":   averageInt64(latencies),
			"p95":   percentileInt64(latencies, 95),
			"p99":   percentileInt64(latencies, 99),
			"max":   maxInt64(latencies),
		},
		"sample_window": len(latencies),
	}
}

func averageInt64(values []int64) int64 {
	if len(values) == 0 {
		return 0
	}
	var sum int64
	for _, value := range values {
		sum += value
	}
	return sum / int64(len(values))
}

func maxInt64(values []int64) int64 {
	if len(values) == 0 {
		return 0
	}
	return values[len(values)-1]
}

func percentileInt64(values []int64, percentile int) int64 {
	if len(values) == 0 {
		return 0
	}
	if percentile <= 0 {
		return values[0]
	}
	if percentile >= 100 {
		return values[len(values)-1]
	}
	idx := (len(values)*percentile + 99) / 100
	if idx <= 0 {
		idx = 1
	}
	if idx > len(values) {
		idx = len(values)
	}
	return values[idx-1]
}

var callMetrics = newCallMetricsCollector()

type callAuditEvent struct {
	CallID    uint64
	EventType string
	ActorID   *uint64
	CallerID  uint64
	CalleeID  uint64

	OldStatus string
	NewStatus string
	Reason    string
	Duration  int
	LatencyMS int64
	RequestID string
	Payload   map[string]interface{}
}

func callActorPtr(id uint64) *uint64 {
	if id == 0 {
		return nil
	}
	v := id
	return &v
}

func requestIDFromContext(c *gin.Context) string {
	if c == nil || c.Request == nil {
		return ""
	}
	if requestID := c.GetHeader("X-Request-Id"); requestID != "" {
		return requestID
	}
	return c.GetHeader("X-Request-ID")
}

func callReleaseEventTypeFromReason(reason string) string {
	if reason == "heartbeat_timeout" {
		return "heartbeat_timeout"
	}
	if reason == "timeout" {
		return "ringing_timeout"
	}
	if reason == "client_replaced" {
		return "client_replaced"
	}
	if reason == "admin_force_end" {
		return "admin_force_end"
	}
	return "end"
}

func recordCallObservability(db *gorm.DB, event callAuditEvent) {
	recordCallMetricForEvent(event)
	writeCallAuditEvent(db, event)
}

func recordCallMetricForEvent(event callAuditEvent) {
	switch event.EventType {
	case "create":
		callMetrics.Inc(callMetricCreateTotal)
	case "end", "cancel", "reject", "admin_force_end":
		callMetrics.Inc(callMetricEndTotal)
		callMetrics.ObserveReleaseLatency(event.LatencyMS)
	case "ringing_timeout":
		callMetrics.Inc(callMetricEndTotal)
		callMetrics.Inc(callMetricStaleCleanupTotal)
		callMetrics.ObserveReleaseLatency(event.LatencyMS)
	case "heartbeat_timeout":
		callMetrics.Inc(callMetricEndTotal)
		callMetrics.Inc(callMetricStaleCleanupTotal)
		callMetrics.Inc(callMetricHeartbeatTimeoutTotal)
		callMetrics.ObserveReleaseLatency(event.LatencyMS)
	case "client_replaced":
		callMetrics.Inc(callMetricEndTotal)
		callMetrics.Inc(callMetricReplacedTotal)
		callMetrics.ObserveReleaseLatency(event.LatencyMS)
	case "create_blocked_active":
		callMetrics.Inc(callMetricCreateBlockedActiveTotal)
	}
}

func writeCallAuditEvent(db *gorm.DB, event callAuditEvent) {
	payloadJSON := ""
	if len(event.Payload) > 0 {
		if data, err := json.Marshal(event.Payload); err == nil {
			payloadJSON = string(data)
		}
	}
	model := models.CallEvent{
		CallID:    event.CallID,
		EventType: event.EventType,
		ActorID:   event.ActorID,
		CallerID:  event.CallerID,
		CalleeID:  event.CalleeID,
		OldStatus: event.OldStatus,
		NewStatus: event.NewStatus,
		Reason:    event.Reason,
		Duration:  event.Duration,
		LatencyMS: event.LatencyMS,
		RequestID: event.RequestID,
		Payload:   payloadJSON,
		CreatedAt: time.Now(),
	}

	logCallTransition(model)
	if db == nil {
		return
	}
	if err := db.Create(&model).Error; err != nil {
		log.Printf("[CallAudit] write failed call_id=%d action=%s err=%v", event.CallID, event.EventType, err)
	}
}

func logCallTransition(event models.CallEvent) {
	actorID := ""
	if event.ActorID != nil {
		actorID = strconv.FormatUint(*event.ActorID, 10)
	}
	log.Printf(
		"call_id=%d action=%s caller_id=%d callee_id=%d old_status=%s new_status=%s actor_id=%s reason=%s duration=%d latency_ms=%d request_id=%s",
		event.CallID,
		event.EventType,
		event.CallerID,
		event.CalleeID,
		event.OldStatus,
		event.NewStatus,
		actorID,
		event.Reason,
		event.Duration,
		event.LatencyMS,
		event.RequestID,
	)
}
