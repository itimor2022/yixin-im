package mq

import (
	"context"
	"crypto/rand"
	"encoding/hex"
	"encoding/json"
	"log"
	"strconv"
	"sync"
	"time"

	"github.com/redis/go-redis/v9"
)

// MessageQueue 消息队列 - 基于Redis实现高性能消息队列
type MessageQueue struct {
	redis       *redis.Client
	handlers    map[string]Handler
	mu          sync.RWMutex
	workerCount int
	ctx         context.Context
	cancel      context.CancelFunc
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
	QueueDelayed      = "mq:delayed"         // 延迟队列
	QueueDead         = "mq:dead"            // 死信队列
	QueueUserChatSync = "mq:user_chat:sync"  // 会话预览异步更新队列
)

// NewMessageQueue 创建消息队列
func NewMessageQueue(rdb *redis.Client, workerCount int) *MessageQueue {
	ctx, cancel := context.WithCancel(context.Background())
	return &MessageQueue{
		redis:       rdb,
		handlers:    make(map[string]Handler),
		workerCount: workerCount,
		ctx:         ctx,
		cancel:      cancel,
	}
}

// RegisterHandler 注册消息处理器
func (mq *MessageQueue) RegisterHandler(msgType string, handler Handler) {
	mq.mu.Lock()
	defer mq.mu.Unlock()
	mq.handlers[msgType] = handler
}

// Publish 发布消息到队列
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

	return mq.redis.LPush(ctx, targetQueue, data).Err()
}

// PublishDelayed 发布延迟消息
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
	log.Printf("[MQ] Starting message queue with %d workers", mq.workerCount)

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
func (mq *MessageQueue) worker(id int, queues []string) {
	log.Printf("[MQ] Worker %d started", id)

	// 构建队列列表（包含高优先级队列）
	allQueues := make([]string, 0, len(queues)*2)
	for _, q := range queues {
		allQueues = append(allQueues, q+":high") // 优先处理高优先级
		allQueues = append(allQueues, q)
	}

	for {
		select {
		case <-mq.ctx.Done():
			log.Printf("[MQ] Worker %d stopped", id)
			return
		default:
		}

		// 使用BRPOP阻塞获取消息
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
			// 指数退避重试
			delay := time.Duration(msg.Retry*msg.Retry) * time.Second
			mq.PublishDelayed(context.Background(), msg, delay)
		} else {
			// 移入死信队列
			data, _ := json.Marshal(msg)
			mq.redis.LPush(context.Background(), QueueDead, data)
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
		// 从延迟队列移除
		if mq.redis.ZRem(mq.ctx, QueueDelayed, data).Val() == 0 {
			continue // 已被其他worker处理
		}

		// 解析并重新发布
		var msg QueueMessage
		if err := json.Unmarshal([]byte(data), &msg); err != nil {
			continue
		}

		// 根据消息类型发布到对应队列
		queue := getQueueByType(msg.Type)
		mq.redis.LPush(mq.ctx, queue, data)
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
	case "user_chat_sync":
		return QueueUserChatSync
	default:
		return QueueMessageSend
	}
}

// 生成消息ID - 使用 crypto/rand 保证高并发下全局唯一
func generateID() string {
	b := make([]byte, 12)
	if _, err := rand.Read(b); err != nil {
		// 降级方案：时间戳 base36，极端情况下不崩溃
		return strconv.FormatInt(time.Now().UnixNano(), 36)
	}
	return time.Now().Format("20060102150405") + hex.EncodeToString(b)
}

func formatFloat(f float64) string {
	return strconv.FormatFloat(f, 'f', 0, 64)
}
