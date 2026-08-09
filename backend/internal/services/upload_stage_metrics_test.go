// 文件用途：验证 upload_stage_metrics_test.go 对应模块的正常流程、异常处理和回归行为。
// 核心逻辑：覆盖输入校验、状态变化、错误返回、边界条件和并发幸命。

package services

import (
	"errors"
	"testing"
	"time"
)

func TestUploadStageMetricsAggregatesSuccessAndFailure(t *testing.T) {
	stage := "test_stage_metrics_aggregate"
	RecordUploadStage(stage, time.Now().Add(-2*time.Millisecond), nil)
	RecordUploadStage(stage, time.Now().Add(-3*time.Millisecond), errors.New("failed"))
	snapshot := GetUploadStageMetrics()
	for _, metric := range snapshot.Stages {

		if metric.Stage != stage {

			continue

		}

		if metric.Count != 2 || metric.Failed != 1 {

			t.Fatalf("unexpected aggregate: %+v", metric)

		}

		if metric.AverageMS <= 0 || metric.MaxMS <= 0 || metric.LastSuccess {

			t.Fatalf("unexpected timings/status: %+v", metric)

		}

		return
	}
	t.Fatalf("stage %q not found in snapshot", stage)
}
