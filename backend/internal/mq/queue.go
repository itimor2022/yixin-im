// 文件用途：定义异步消息队列的生产、消费和任务分发。
// 核心逻辑：统一队列名称、优先级、worker 生命周期和失败处理。

package mq

import (
	"context"
	"encoding/json"
	"fmt"
	"log"
	"strconv"
	"sync"
	"time"

	"github.com/redis/go-redis/v9"
)

// MessageQueue 消息队列 - 基于Redis实现高性能消息队列
type MessageQueue struct {
	// redis is the broad Cmdable interface so the same MessageQueue works
	// against either a standalone Redis or a Redis Cluster connection.
	redis       redis.Cmdable
	handlers    map[string]Handler
	mu          sync.RWMutex
	workerCount int
	ctx         context.Context
	cancel      context.CancelFunc
	// shardCount > 1 means queue names are appended with `:{0..shardCount-1}`
	// so each shard lives on a deterministic Redis Cluster slot; one worker
	// pops from one shard, so BRPop never blocks waiting for a key on the
	// wrong shard. sharded mode is only meaningful with Cluster.
	shardCount int
}

// Handler 消息处理器
type Handler func(ctx context.Context, msg *QueueMessage) error

// QueueMessage 队列消息
type QueueMessage struct {
	ID        string          `json:"id"`
	Type      string          `json:"type"`
	Payload   json.RawMessage `json:"payload"`
	Priority  int             `json:"priority"`
	Retry     int             `json:"retry"`
	MaxRetry  int             `json:"max_retry"`
	CreatedAt int64           `json:"created_at"`
}

// 队列名称常量
const (
	QueueMessageSend = "mq:message:send" // 消息发送队列
	QueueMessageSync = "mq:message:sync" // 消息同步队列
	QueuePushNotify  = "mq:push:notify"  // 推送通知队列
	QueueUserStatus  = "mq:user:status"  // 用户状态队列
	QueueDelayed     = "mq:delayed"      // 延迟队列
	QueueDead        = "mq:dead"         // 死信队列
)

// NewMessageQueue 创建消息队列
//
// shardCount defaults to 1 (legacy behaviour: a single queue name per logical
// queue). On Redis Cluster deployments set shardCount>1 so each shard has its
// own hash-tagged key and each worker can BRPop deterministically.
func NewMessageQueue(rdb redis.Cmdable, workerCount int, shardCount int) *MessageQueue {
	if shardCount < 1 {
		shardCount = 1
	}
	ctx, cancel := context.WithCancel(context.Background())
	return &MessageQueue{
		redis:       rdb,
		handlers:    make(map[string]Handler),
		workerCount: workerCount,
		ctx:         ctx,
		cancel:      cancel,
		shardCount:  shardCount,
	}
}

// queueName builds the concrete Redis key for a logical queue + shard index.
// sharded=true with shard N produces `base:{N}`; sharded=false produces `base`.
// Hash tag `{N}` keeps the key on a deterministic Cluster slot so a worker
// attached to shard N always reads from the same shard.
func (mq *MessageQueue) queueName(base string, shard int) string {
	if mq.shardCount <= 1 {
		return base
	}
	return fmt.Sprintf("%s:{%d}", base, shard)
}

// allShards returns the concrete keys for every shard of `base`. When
// sharding is disabled the slice is just `[base]`.
func (mq *MessageQueue) allShards(base string) []string {
	if mq.shardCount <= 1 {
		return []string{base}
	}
	out := make([]string, mq.shardCount)
	for i := 0; i < mq.shardCount; i++ {
		out[i] = fmt.Sprintf("%s:{%d}", base, i)
	}
	return out
}

// RegisterHandler 注册消息处理器
func (mq *MessageQueue) RegisterHandler(msgType string, handler Handler) {
	mq.mu.Lock()
	defer mq.mu.Unlock()
	mq.handlers[msgType] = handler
}

// Publish 发布消息到队列
//
// 在 Cluster + sharded 模式下，按消息 ID 哈希到固定 shard，确保同一会话的
// 消息顺序在同一 worker 中被处理（顺序只是"同一分片内"保证，跨分片不保证）。
func (mq *MessageQueue) Publish(ctx context.Context, queue string, msg *QueueMessage) error {
	if msg.ID == "" {
		msg.ID = generateID()
	}
	if msg.CreatedAt == 0 {
		msg.CreatedAt = time.Now().UnixMilli()
	}
	if msg.MaxRetry == 0 {
		msg.MaxRetry = 3
	}

	data, err := json.Marshal(msg)
	if err != nil {
		return err
	}

	// 根据优先级选择队列
	targetQueue := queue
	if msg.Priority > 0 {
		targetQueue = queue + ":high"
	}
	shard := mq.pickShard(msg.ID)
	return mq.redis.LPush(ctx, mq.queueName(targetQueue, shard), data).Err()
}

// pickShard returns the shard index for a given message identifier. The hash
// uses the same FNV-like routine as the rest of the package; deterministic and
// cheap. sharded=false always returns 0 (the only shard).
func (mq *MessageQueue) pickShard(id string) int {
	if mq.shardCount <= 1 {
		return 0
	}
	var h uint32 = 2166136261
	for i := 0; i < len(id); i++ {
		h ^= uint32(id[i])
		h *= 16777619
	}
	return int(h % uint32(mq.shardCount))
}

// PublishDelayed

func (mq *MessageQueue) PublishDelayed(ctx context.Context, msg *QueueMessage, delay time.Duration) error {
	if msg.ID == "" {
		msg.ID = generateID()
	}
	msg.CreatedAt = time.Now().UnixMilli()

	data, err := json.Marshal(msg)
	if err != nil {
		return err
	}

	// 使用有序集合实现延迟队列
	score := float64(time.Now().Add(delay).UnixMilli())
	return mq.redis.ZAdd(ctx, QueueDelayed, redis.Z{
		Score:  score,
		Member: data,
	}).Err()
}

// Start 启动消费者
func (mq *MessageQueue) Start(queues ...string) {
	log.Printf("[MQ] Starting message queue with %d workers (shards=%d)", mq.workerCount, mq.shardCount)

	// 启动工作协程
	for i := 0; i < mq.workerCount; i++ {
		go mq.worker(i, queues)
	}

	// 启动延迟队列处理
	go mq.processDelayed()
}

// Stop 停止消费者
func (mq *MessageQueue) Stop() {
	mq.cancel()
}

// worker 工作协程
//
// 在 sharded 模式下每个 worker 只 BRPop 自己负责的 shard（按 worker id %
// shardCount），保证 BRPop 的所有 key 落在同一 Cluster slot 上。
// 非 sharded 模式下行为不变：每个 worker 监听全部队列。
func (mq *MessageQueue) worker(id int, queues []string) {
	log.Printf("[MQ] Worker %d started", id)

	var allQueues []string
	if mq.shardCount <= 1 {
		allQueues = make([]string, 0, len(queues)*2)
		for _, q := range queues {
			allQueues = append(allQueues, q+":high") // 优先处理高优先级
			allQueues = append(allQueues, q)
		}
	} else {
		shard := id % mq.shardCount
		allQueues = make([]string, 0, len(queues)*2)
		for _, q := range queues {
			allQueues = append(allQueues, mq.queueName(q+":high", shard))
			allQueues = append(allQueues, mq.queueName(q, shard))
		}
	}
	for {
		select {
		case <-mq.ctx.Done():
			log.Printf("[MQ] Worker %d stopped", id)
			return
		default:
		}

		//

		result, err := mq.redis.BRPop(mq.ctx, time.Second, allQueues...).Result()
		if err != nil {
			if err != redis.Nil {
				log.Printf("[MQ] Worker %d error: %v", id, err)
			}
			continue
		}
		if len(result) < 2 {
			continue
		}

		// 解析消息
		var msg QueueMessage
		if err := json.Unmarshal([]byte(result[1]), &msg); err != nil {
			log.Printf("[MQ] Invalid message format: %v", err)
			continue
		}

		// 处理消息
		mq.processMessage(&msg)
	}
}

// processMessage 处理消息
func (mq *MessageQueue) processMessage(msg *QueueMessage) {
	mq.mu.RLock()
	handler, ok := mq.handlers[msg.Type]
	mq.mu.RUnlock()
	if !ok {

		log.Printf("[MQ] No handler for message type: %s", msg.Type)
		return
	}

	// 创建超时上下文
	ctx, cancel := context.WithTimeout(mq.ctx, 30*time.Second)
	defer cancel()

	// 执行处理器
	if err := handler(ctx, msg); err != nil {
		log.Printf("[MQ] Handler error for %s: %v", msg.Type, err)

		// 重试逻辑
		msg.Retry++
		if msg.Retry <= msg.MaxRetry {
			//

			delay := time.Duration(msg.Retry*msg.Retry) * time.Second
			mq.PublishDelayed(context.Background(), msg, delay)
		} else {
			// 移入死信队列（沿用原 shard，让 BRPop 还能继续看到）
			data, _ := json.Marshal(msg)
			shard := mq.pickShard(msg.ID)
			mq.redis.LPush(context.Background(), mq.queueName(QueueDead, shard), data)
			log.Printf("[MQ] Message moved to dead queue: %s", msg.ID)
		}
	}
}

// processDelayed 处理延迟队列
func (mq *MessageQueue) processDelayed() {
	ticker := time.NewTicker(100 * time.Millisecond)
	defer ticker.Stop()
	for {
		select {
		case <-mq.ctx.Done():
			return
		case <-ticker.C:
			mq.checkDelayed()
		}
	}
}

// checkDelayed 检查延迟消息
func (mq *MessageQueue) checkDelayed() {
	now := float64(time.Now().UnixMilli())

	// 获取到期的消息
	results, err := mq.redis.ZRangeByScore(mq.ctx, QueueDelayed, &redis.ZRangeBy{
		Min:   "-inf",
		Max:   formatFloat(now),
		Count: 100,
	}).Result()
	if err != nil || len(results) == 0 {
		return
	}
	for _, data := range results {
		//
		if mq.redis.ZRem(mq.ctx, QueueDelayed, data).Val() == 0 {
			continue // 已被其他worker处理
		}

		// 解析并重新发布
		var msg QueueMessage
		if err := json.Unmarshal([]byte(data), &msg); err != nil {
			continue
		}

		//

		queue := getQueueByType(msg.Type)
		shard := mq.pickShard(msg.ID)
		mq.redis.LPush(mq.ctx, mq.queueName(queue, shard), data)
	}
}

// 根据消息类型获取队列
func getQueueByType(msgType string) string {
	switch msgType {
	case "send_message":
		return QueueMessageSend
	case "sync_message":
		return QueueMessageSync
	case "push_notify":
		return QueuePushNotify
	case "user_status":
		return QueueUserStatus
	default:
		return QueueMessageSend
	}
}

// 生成消息ID
func generateID() string {
	return time.Now().Format("20060102150405") + randomString(8)
}

func randomString(n int) string {
	const letters = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"
	b := make([]byte, n)
	for i := range b {
		b[i] = letters[time.Now().UnixNano()%int64(len(letters))]
	}
	return string(b)
}

func formatFloat(f float64) string {
	return strconv.FormatFloat(f, 'f', 0, 64)
}
