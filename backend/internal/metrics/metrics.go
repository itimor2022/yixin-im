package metrics

import (
	"github.com/prometheus/client_golang/prometheus"
	"github.com/prometheus/client_golang/prometheus/promauto"
)

// ★ 所有指标统一在此注册，业务层直接调用

var (
	// HTTP 请求总数（按方法、路径、状态码）
	HTTPRequestTotal = promauto.NewCounterVec(
		prometheus.CounterOpts{
			Name: "gaoranim_http_requests_total",
			Help: "HTTP 请求总数",
		},
		[]string{"method", "path", "status"},
	)

	// HTTP 请求延迟（按方法、路径）
	HTTPRequestDuration = promauto.NewHistogramVec(
		prometheus.HistogramOpts{
			Name:    "gaoranim_http_request_duration_seconds",
			Help:    "HTTP 请求延迟",
			Buckets: []float64{0.01, 0.05, 0.1, 0.3, 0.5, 1.0, 2.0, 5.0},
		},
		[]string{"method", "path"},
	)

	// WebSocket 当前连接数
	WSConnectionsActive = promauto.NewGauge(
		prometheus.GaugeOpts{
			Name: "gaoranim_ws_connections_active",
			Help: "当前 WebSocket 活跃连接数",
		},
	)

	// 消息发送总数（按消息类型）
	MessageSentTotal = promauto.NewCounterVec(
		prometheus.CounterOpts{
			Name: "gaoranim_messages_sent_total",
			Help: "消息发送总数",
		},
		[]string{"type"},
	)

	// MQ 消息处理总数（按队列、结果）
	MQMessageTotal = promauto.NewCounterVec(
		prometheus.CounterOpts{
			Name: "gaoranim_mq_messages_total",
			Help: "MQ 消息处理总数",
		},
		[]string{"queue", "result"},
	)

	// Redis 缓存命中/未命中
	CacheHitTotal = promauto.NewCounterVec(
		prometheus.CounterOpts{
			Name: "gaoranim_cache_operations_total",
			Help: "Redis 缓存操作总数",
		},
		[]string{"operation", "result"},
	)

	// 推送通知发送总数（按渠道、结果）
	PushSentTotal = promauto.NewCounterVec(
		prometheus.CounterOpts{
			Name: "gaoranim_push_sent_total",
			Help: "推送通知发送总数",
		},
		[]string{"channel", "result"},
	)

	// 限流触发总数（按类型）
	RateLimitTotal = promauto.NewCounterVec(
		prometheus.CounterOpts{
			Name: "gaoranim_rate_limit_triggered_total",
			Help: "限流触发总数",
		},
		[]string{"type"},
	)
)
