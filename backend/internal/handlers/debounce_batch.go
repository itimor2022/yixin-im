// 文件用途：为消息派生任务提供“静默窗口 + 最大等待”防抖参数，避免长突发期间在 ACK 峰值中途执行批处理。
// 核心逻辑：每次新任务都把执行时间推迟到静默窗口之后，但连续流量最多等待 2 秒，防止任务无限饥饿。

package handlers

import "time"

const messageBatchMaxDelay = 2 * time.Second

func nextDebounceDelay(firstSeen time.Time, quietDelay time.Duration) time.Duration {
	if quietDelay <= 0 {
		quietDelay = time.Millisecond
	}
	maxRemaining := messageBatchMaxDelay - time.Since(firstSeen)
	if maxRemaining <= 0 {
		return 0
	}
	if quietDelay < maxRemaining {
		return quietDelay
	}
	return maxRemaining
}
