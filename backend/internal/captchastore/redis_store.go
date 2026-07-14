// Package captchastore 提供基于 Redis 的 base64Captcha.Store 实现。
//
// 为什么必须换掉默认的 DefaultMemStore：
//   - DefaultMemStore 是 base64Captcha 自带的 LRU 内存缓存，每台 Gin 进程都是独立的一份；
//   - 集群 / 多副本部署时，前端可能从节点 A 拿到验证码，登录请求却走到了节点 B，
//     导致"验证码错误或已过期"—— 用户看到的是随机的登录失败，无法排查；
//   - LRU 也没有严格 TTL，容量满时会淘汰刚发的验证码，早高峰体验很差。
//
// Redis 存储把 captcha id → answer 集中到一台 Redis 上，任何节点都能校验，
// 并且用了 5 分钟的 TTL（跟短信验证码保持一致），到期自动过期。
package captchastore

import (
	"context"
	"fmt"
	"strings"
	"time"

	"github.com/mojocn/base64Captcha"
	"github.com/redis/go-redis/v9"
)

// 前缀 + 默认 TTL。同一进程可能同时有登录/注册两种验证码，用同一个前缀即可。
const (
	defaultKeyPrefix = "captcha:"
	defaultTTL       = 5 * time.Minute
)

// RedisStore 实现 base64Captcha.Store（Set/Get/Verify），底层用 Redis。
type RedisStore struct {
	client *redis.Client
	prefix string
	ttl    time.Duration
}

// New 创建一个 RedisStore。client 为 nil 时会 panic —— 调用方需保证已初始化。
// 传入 prefix 为空则使用 "captcha:"，ttl <= 0 则使用 5 分钟。
func New(client *redis.Client, prefix string, ttl time.Duration) *RedisStore {
	if client == nil {
		panic("captchastore: nil redis client")
	}
	if prefix == "" {
		prefix = defaultKeyPrefix
	}
	if ttl <= 0 {
		ttl = defaultTTL
	}
	return &RedisStore{client: client, prefix: prefix, ttl: ttl}
}

// 编译期确保 RedisStore 实现了 base64Captcha.Store 接口。
var _ base64Captcha.Store = (*RedisStore)(nil)

func (s *RedisStore) key(id string) string {
	return s.prefix + id
}

// Set 将 id → value 写入 Redis，附带 TTL。
// 用 3 秒的固定超时避免慢 Redis 拖住登录请求 goroutine。
func (s *RedisStore) Set(id, value string) error {
	if id == "" {
		return fmt.Errorf("captchastore: empty id")
	}
	ctx, cancel := context.WithTimeout(context.Background(), 3*time.Second)
	defer cancel()
	return s.client.Set(ctx, s.key(id), value, s.ttl).Err()
}

// Get 读取 id 对应的 value。clear=true 时读取后立即删除（一次性使用）。
// 找不到或异常时返回空字符串（base64Captcha 语义要求）。
func (s *RedisStore) Get(id string, clear bool) string {
	if id == "" {
		return ""
	}
	ctx, cancel := context.WithTimeout(context.Background(), 3*time.Second)
	defer cancel()
	val, err := s.client.Get(ctx, s.key(id)).Result()
	if err != nil {
		return ""
	}
	if clear {
		// 尽力删除，删失败也没关系，TTL 会兜底。
		_ = s.client.Del(ctx, s.key(id)).Err()
	}
	return val
}

// Verify 校验 answer 是否与 Redis 里 id 对应的值一致。
// 大小写不敏感 + 空白裁剪，兼容不同前端处理方式。
// clear=true 时无论成功失败都会删除，防止重放。
func (s *RedisStore) Verify(id, answer string, clear bool) bool {
	stored := s.Get(id, clear)
	if stored == "" {
		return false
	}
	return strings.EqualFold(strings.TrimSpace(stored), strings.TrimSpace(answer))
}
