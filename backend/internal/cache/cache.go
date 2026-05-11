package cache

import (
	"context"
	"encoding/json"
	"fmt"
	"sync/atomic"
	"time"

	"github.com/redis/go-redis/v9"
)

// Cache Redis缓存层
type Cache struct {
	client *redis.Client
}

var rateLimitMemberSeq uint64

func (c *Cache) Ping(ctx context.Context) error {
	if c == nil || c.client == nil {
		return fmt.Errorf("redis client is nil")
	}
	return c.client.Ping(ctx).Err()
}

func (c *Cache) ListLen(ctx context.Context, key string) (int64, error) {
	if c == nil || c.client == nil {
		return 0, fmt.Errorf("redis client is nil")
	}
	return c.client.LLen(ctx, key).Result()
}

func (c *Cache) SortedSetLen(ctx context.Context, key string) (int64, error) {
	if c == nil || c.client == nil {
		return 0, fmt.Errorf("redis client is nil")
	}
	return c.client.ZCard(ctx, key).Result()
}

// 缓存Key前缀
const (
	KeyUser        = "user:"         // 用户信息
	KeyUserToken   = "user:token:"   // 用户Token
	KeyUserOnline  = "user:online:"  // 用户在线状态
	KeyChat        = "chat:"         // 会话信息
	KeyChatMembers = "chat:members:" // 会话成员
	KeyMsgSeq      = "msg:seq:"      // 消息序号
	KeyVerifyCode  = "verify:code:"  // 验证码
	KeyRateLimit   = "rate:"         // 限流
)

// 缓存过期时间
const (
	TTLUser       = 30 * time.Minute
	TTLChat       = 30 * time.Minute
	TTLOnline     = 5 * time.Minute
	TTLVerifyCode = 5 * time.Minute
	TTLToken      = 7 * 24 * time.Hour
)

// NewCache 创建缓存实例
func NewCache(client *redis.Client) *Cache {
	return &Cache{client: client}
}

// --- 通用方法 ---

// Set 设置缓存
func (c *Cache) Set(ctx context.Context, key string, value interface{}, ttl time.Duration) error {
	data, err := json.Marshal(value)
	if err != nil {
		return err
	}
	return c.client.Set(ctx, key, data, ttl).Err()
}

// Get 获取缓存
func (c *Cache) Get(ctx context.Context, key string, dest interface{}) error {
	data, err := c.client.Get(ctx, key).Bytes()
	if err != nil {
		return err
	}
	return json.Unmarshal(data, dest)
}

// Delete 删除缓存
func (c *Cache) Delete(ctx context.Context, keys ...string) error {
	return c.client.Del(ctx, keys...).Err()
}

// Exists 检查key是否存在
func (c *Cache) Exists(ctx context.Context, key string) bool {
	return c.client.Exists(ctx, key).Val() > 0
}

// --- 用户相关 ---

// SetUser 缓存用户信息
func (c *Cache) SetUser(ctx context.Context, userID string, user interface{}) error {
	return c.Set(ctx, KeyUser+userID, user, TTLUser)
}

// GetUser 获取用户信息
func (c *Cache) GetUser(ctx context.Context, userID string, dest interface{}) error {
	return c.Get(ctx, KeyUser+userID, dest)
}

// DeleteUser 删除用户缓存
func (c *Cache) DeleteUser(ctx context.Context, userID string) error {
	return c.Delete(ctx, KeyUser+userID)
}

// SetUserToken 设置用户Token
func (c *Cache) SetUserToken(ctx context.Context, userID, token string) error {
	return c.client.Set(ctx, KeyUserToken+userID, token, TTLToken).Err()
}

// GetUserToken 获取用户Token
func (c *Cache) GetUserToken(ctx context.Context, userID string) (string, error) {
	return c.client.Get(ctx, KeyUserToken+userID).Result()
}

// SetUserOnline 设置用户在线状态
func (c *Cache) SetUserOnline(ctx context.Context, userID string, deviceID string) error {
	key := KeyUserOnline + userID
	return c.client.HSet(ctx, key, deviceID, time.Now().Unix()).Err()
}

// RemoveUserOnline 移除用户在线状态
func (c *Cache) RemoveUserOnline(ctx context.Context, userID, deviceID string) error {
	return c.client.HDel(ctx, KeyUserOnline+userID, deviceID).Err()
}

// IsUserOnline 检查用户是否在线
func (c *Cache) IsUserOnline(ctx context.Context, userID string) bool {
	return c.client.HLen(ctx, KeyUserOnline+userID).Val() > 0
}

// GetUserOnlineDevices 获取用户在线设备
func (c *Cache) GetUserOnlineDevices(ctx context.Context, userID string) ([]string, error) {
	result, err := c.client.HKeys(ctx, KeyUserOnline+userID).Result()
	if err != nil {
		return nil, err
	}
	return result, nil
}

// --- 会话相关 ---

// SetChat 缓存会话信息
func (c *Cache) SetChat(ctx context.Context, chatID string, chat interface{}) error {
	return c.Set(ctx, KeyChat+chatID, chat, TTLChat)
}

// GetChat 获取会话信息
func (c *Cache) GetChat(ctx context.Context, chatID string, dest interface{}) error {
	return c.Get(ctx, KeyChat+chatID, dest)
}

// SetChatMembers 缓存会话成员
func (c *Cache) SetChatMembers(ctx context.Context, chatID string, memberIDs []string) error {
	key := KeyChatMembers + chatID
	if len(memberIDs) == 0 {
		return nil
	}

	members := make([]interface{}, len(memberIDs))
	for i, id := range memberIDs {
		members[i] = id
	}

	pipe := c.client.Pipeline()
	pipe.Del(ctx, key)
	pipe.SAdd(ctx, key, members...)
	pipe.Expire(ctx, key, TTLChat)
	_, err := pipe.Exec(ctx)
	return err
}

// GetChatMembers 获取会话成员
func (c *Cache) GetChatMembers(ctx context.Context, chatID string) ([]string, error) {
	return c.client.SMembers(ctx, KeyChatMembers+chatID).Result()
}

// IsChatMember 检查是否是会话成员
func (c *Cache) IsChatMember(ctx context.Context, chatID, userID string) bool {
	return c.client.SIsMember(ctx, KeyChatMembers+chatID, userID).Val()
}

// --- 消息序号 ---

// GetNextMsgSeq 获取下一个消息序号（原子操作）
func (c *Cache) GetNextMsgSeq(ctx context.Context, chatID string) (uint64, error) {
	return c.client.Incr(ctx, KeyMsgSeq+chatID).Uint64()
}

// GetCurrentMsgSeq 获取当前消息序号
func (c *Cache) GetCurrentMsgSeq(ctx context.Context, chatID string) (uint64, error) {
	result, err := c.client.Get(ctx, KeyMsgSeq+chatID).Uint64()
	if err == redis.Nil {
		return 0, nil
	}
	return result, err
}

// SetCurrentMsgSeq 设置当前消息序号（用于 Redis 序号丢失后的兜底校准）
func (c *Cache) SetCurrentMsgSeq(ctx context.Context, chatID string, seq uint64) error {
	return c.client.Set(ctx, KeyMsgSeq+chatID, seq, 0).Err()
}

// --- 验证码 ---

// SetVerifyCode 设置验证码
func (c *Cache) SetVerifyCode(ctx context.Context, phone, code string) error {
	return c.client.Set(ctx, KeyVerifyCode+phone, code, TTLVerifyCode).Err()
}

// GetVerifyCode 获取验证码
func (c *Cache) GetVerifyCode(ctx context.Context, phone string) (string, error) {
	return c.client.Get(ctx, KeyVerifyCode+phone).Result()
}

// DeleteVerifyCode 删除验证码
func (c *Cache) DeleteVerifyCode(ctx context.Context, phone string) error {
	return c.client.Del(ctx, KeyVerifyCode+phone).Err()
}

// --- 限流 ---

// RateLimit 限流检查（滑动窗口）
func (c *Cache) RateLimit(ctx context.Context, key string, limit int, window time.Duration) (bool, error) {
	now := time.Now().UnixMilli()
	windowStart := now - window.Milliseconds()

	rateKey := KeyRateLimit + key

	pipe := c.client.Pipeline()
	// 移除窗口外的记录
	pipe.ZRemRangeByScore(ctx, rateKey, "0", fmt.Sprintf("%d", windowStart))
	// 计数
	countCmd := pipe.ZCard(ctx, rateKey)
	// 添加当前请求
	member := fmt.Sprintf("%d-%d", now, atomic.AddUint64(&rateLimitMemberSeq, 1))
	pipe.ZAdd(ctx, rateKey, redis.Z{Score: float64(now), Member: member})
	// 设置过期时间
	pipe.Expire(ctx, rateKey, window)

	if _, err := pipe.Exec(ctx); err != nil {
		return false, err
	}

	return countCmd.Val() < int64(limit), nil
}
