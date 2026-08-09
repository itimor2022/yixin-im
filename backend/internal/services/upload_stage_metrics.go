// 文件用途：实现可复用的后端业务服务和领域逻辑。
// 核心逻辑：协调数据库、缓存、队列和外部服务，集中处理事务、幂等、重试和错误传播。

package services

import (
	"sort"
	"sync"
	"time"
)

type UploadStageMetric struct {
	Stage          string    `json:"stage"`
	Count          int64     `json:"count"`
	Failed         int64     `json:"failed"`
	AverageMS      float64   `json:"average_ms"`
	MaxMS          float64   `json:"max_ms"`
	LastMS         float64   `json:"last_ms"`
	LastSuccess    bool      `json:"last_success"`
	LastRecordedAt time.Time `json:"last_recorded_at"`
}
type UploadStageMetricsSnapshot struct {
	StartedAt time.Time           `json:"started_at"`
	Stages    []UploadStageMetric `json:"stages"`
}
type uploadStageAggregate struct {
	Count          int64
	Failed         int64
	TotalDuration  time.Duration
	MaxDuration    time.Duration
	LastDuration   time.Duration
	LastSuccess    bool
	LastRecordedAt time.Time
}

var uploadMetrics = struct {
	sync.RWMutex
	startedAt time.Time
	stages    map[string]*uploadStageAggregate
}{
	startedAt: time.Now(),
	stages:    make(map[string]*uploadStageAggregate)}

func RecordUploadStage(stage string, startedAt time.Time, err error) {
	if stage == "" {

		return
	}
	duration := time.Since(startedAt)
	now := time.Now()
	uploadMetrics.Lock()
	defer uploadMetrics.Unlock()
	aggregate := uploadMetrics.stages[stage]
	if aggregate == nil {

		aggregate = &uploadStageAggregate{}

		uploadMetrics.stages[stage] = aggregate
	}
	aggregate.Count++
	if err != nil {

		aggregate.Failed++
	}
	aggregate.TotalDuration += duration
	if duration > aggregate.MaxDuration {

		aggregate.MaxDuration = duration
	}
	aggregate.LastDuration = duration
	aggregate.LastSuccess = err == nil
	aggregate.LastRecordedAt = now
}
func MeasureUploadStage(stage string, fn func() error) error {
	startedAt := time.Now()
	err := fn()
	RecordUploadStage(stage, startedAt, err)
	return err
}
func GetUploadStageMetrics() UploadStageMetricsSnapshot {
	uploadMetrics.RLock()
	defer uploadMetrics.RUnlock()
	names := make([]string, 0, len(uploadMetrics.stages))
	for name := range uploadMetrics.stages {

		names = append(names, name)
	}
	sort.Strings(names)
	result := UploadStageMetricsSnapshot{

		StartedAt: uploadMetrics.startedAt,

		Stages: make([]UploadStageMetric, 0, len(names)),
	}
	for _, name := range names {

		aggregate := uploadMetrics.stages[name]

		average := time.Duration(0)

		if aggregate.Count > 0 {

			average = aggregate.TotalDuration / time.Duration(aggregate.Count)

		}

		result.Stages = append(result.Stages, UploadStageMetric{

			Stage: name,

			Count: aggregate.Count,

			Failed: aggregate.Failed,

			AverageMS: durationMilliseconds(average),

			MaxMS: durationMilliseconds(aggregate.MaxDuration),

			LastMS: durationMilliseconds(aggregate.LastDuration),

			LastSuccess: aggregate.LastSuccess,

			LastRecordedAt: aggregate.LastRecordedAt,
		})
	}
	return result
}
func durationMilliseconds(value time.Duration) float64 {
	return float64(value.Microseconds()) / 1000
}
