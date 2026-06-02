package cache

import (
	"context"
	"encoding/json"
	"fmt"
	"strconv"
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

	// ★ 新增Key前缀
	KeySystemSetting = "sys:setting:" // 系统设置
	KeyUserPhone     = "user:phone:"  // 用户手机号绑定状态
)

// 缓存过期时间
const (
	TTLUser       = 30 * time.Minute
	TTLChat       = 30 * time.Minute
	TTLOnline     = 5 * time.Minute
	TTLVerifyCode = 5 * time.Minute
	TTLToken      = 7 * 24 * time.Hour

	// ★ 新增TTL
	TTLSystemSetting = 10 * time.Minute // 系统设置，变化极少
	TTLUserPhone     = 5 * time.Minute  // 用户手机绑定状态
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
// GetRaw 获取原始字符串值
func (c *Cache) GetRaw(ctx context.Context, key string) (string, error) {
	if c == nil || c.client == nil {
		return "", fmt.Errorf("cache unavailable")
	}
	return c.client.Get(ctx, key).Result()
}

// SetRaw 设置原始字符串值
func (c *Cache) SetRaw(ctx context.Context, key string, value string, ttlSeconds int) error {
	if c == nil || c.client == nil {
		return fmt.Errorf("cache unavailable")
	}
	return c.client.Set(ctx, key, value, time.Duration(ttlSeconds)*time.Second).Err()
}

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

// ★ --- 系统设置缓存 ---

// GetSystemSetting 从缓存获取系统设置值
// 返回 (value, found)，found=false 表示缓存未命中需要查DB
func (c *Cache) GetSystemSetting(ctx context.Context, key string) (string, bool) {
	if c == nil || c.client == nil {
		return "", false
	}
	var val string
	if err := c.Get(ctx, KeySystemSetting+key, &val); err != nil {
		return "", false
	}
	return val, true
}

// SetSystemSetting 将系统设置写入缓存
func (c *Cache) SetSystemSetting(ctx context.Context, key, value string) error {
	if c == nil || c.client == nil {
		return nil
	}
	return c.Set(ctx, KeySystemSetting+key, value, TTLSystemSetting)
}

// DeleteSystemSetting 使系统设置缓存失效（管理员修改设置时调用）
func (c *Cache) DeleteSystemSetting(ctx context.Context, key string) error {
	if c == nil || c.client == nil {
		return nil
	}
	return c.Delete(ctx, KeySystemSetting+key)
}

// ★ --- 用户手机绑定状态缓存 ---

// UserPhoneStatus 用户手机绑定状态（缓存结构体，只存必要字段避免缓存大对象）
type UserPhoneStatus struct {
	HasPhone bool   `json:"has_phone"`
	Phone    string `json:"phone,omitempty"` // 可选，用于展示
}

// GetUserPhoneStatus 从缓存获取用户手机绑定状态
// 返回 (status, found)
func (c *Cache) GetUserPhoneStatus(ctx context.Context, userUUID string) (*UserPhoneStatus, bool) {
	if c == nil || c.client == nil {
		return nil, false
	}
	var status UserPhoneStatus
	if err := c.Get(ctx, KeyUserPhone+userUUID, &status); err != nil {
		return nil, false
	}
	return &status, true
}

// SetUserPhoneStatus 缓存用户手机绑定状态
func (c *Cache) SetUserPhoneStatus(ctx context.Context, userUUID string, status *UserPhoneStatus) error {
	if c == nil || c.client == nil || status == nil {
		return nil
	}
	return c.Set(ctx, KeyUserPhone+userUUID, status, TTLUserPhone)
}

// DeleteUserPhoneStatus 使用户手机绑定状态缓存失效（用户绑定/换绑手机时调用）
func (c *Cache) DeleteUserPhoneStatus(ctx context.Context, userUUID string) error {
	if c == nil || c.client == nil {
		return nil
	}
	return c.Delete(ctx, KeyUserPhone+userUUID)
}

// ★ --- 群组信息缓存 ---

const (
	KeyChatInfo       = "chat:info:"        // 群组完整信息 by UUID
	KeyChatMemberInfo = "chat:member:"      // 单个成员信息 chat:member:{chatID}:{userID}
	KeyChatMemberUUIDs = "chat:muuids:"     // 群成员UUID SET
	KeyChatMemberIDMap = "chat:midmap:"     // 群成员 ID->UUID HASH
	KeyChatMutedSet   = "chat:muted:"       // 群内muted用户ID SET
	KeyUserInfo       = "user:info:"        // 用户核心信息 by UUID

	TTLChatInfo    = 10 * time.Minute
	TTLChatMember  = 10 * time.Minute
	TTLUserInfo    = 30 * time.Minute
	TTLMutedSet    = 5 * time.Minute
)

// SetChatInfo 缓存群组完整信息
func (c *Cache) SetChatInfo(ctx context.Context, chatUUID string, chat interface{}) error {
	if c == nil || c.client == nil {
		return nil
	}
	return c.Set(ctx, KeyChatInfo+chatUUID, chat, TTLChatInfo)
}

// GetChatInfo 获取群组缓存信息，未命中返回 redis.Nil
func (c *Cache) GetChatInfo(ctx context.Context, chatUUID string, dest interface{}) error {
	if c == nil || c.client == nil {
		return fmt.Errorf("cache unavailable")
	}
	return c.Get(ctx, KeyChatInfo+chatUUID, dest)
}

// DeleteChatInfo 删除群组缓存（群信息变更时调用）
func (c *Cache) DeleteChatInfo(ctx context.Context, chatUUID string) error {
	if c == nil || c.client == nil {
		return nil
	}
	return c.Delete(ctx, KeyChatInfo+chatUUID)
}

// SetChatMemberInfo 缓存单个成员信息
func (c *Cache) SetChatMemberInfo(ctx context.Context, chatID, userID string, member interface{}) error {
	if c == nil || c.client == nil {
		return nil
	}
	return c.Set(ctx, KeyChatMemberInfo+chatID+":"+userID, member, TTLChatMember)
}

// GetChatMemberInfo 获取单个成员缓存
func (c *Cache) GetChatMemberInfo(ctx context.Context, chatID, userID string, dest interface{}) error {
	if c == nil || c.client == nil {
		return fmt.Errorf("cache unavailable")
	}
	return c.Get(ctx, KeyChatMemberInfo+chatID+":"+userID, dest)
}

// DeleteChatMemberInfo 删除成员缓存（成员信息变更时调用）
func (c *Cache) DeleteChatMemberInfo(ctx context.Context, chatID, userID string) error {
	if c == nil || c.client == nil {
		return nil
	}
	return c.Delete(ctx, KeyChatMemberInfo+chatID+":"+userID)
}

// SetChatMemberIDMap 缓存群成员 ID->UUID 映射（HASH结构）
// key: chat:midmap:{chatID}  field: strconv.FormatUint(id,10)  value: uuid
func (c *Cache) SetChatMemberIDMap(ctx context.Context, chatID string, idToUUID map[string]string) error {
	if c == nil || c.client == nil || len(idToUUID) == 0 {
		return nil
	}
	key := KeyChatMemberIDMap + chatID
	pipe := c.client.Pipeline()
	pipe.Del(ctx, key)
	// HSet 接受 map[string]interface{}
	fields := make(map[string]interface{}, len(idToUUID))
	for k, v := range idToUUID {
		fields[k] = v
	}
	pipe.HSet(ctx, key, fields)
	pipe.Expire(ctx, key, TTLChatMember)
	_, err := pipe.Exec(ctx)
	return err
}

// GetChatMemberUUIDs 从 ID->UUID HASH 批量获取 UUID 列表
func (c *Cache) GetChatMemberUUIDs(ctx context.Context, chatID string, ids []string) ([]string, error) {
	if c == nil || c.client == nil || len(ids) == 0 {
		return nil, fmt.Errorf("cache unavailable")
	}
	key := KeyChatMemberIDMap + chatID
	vals, err := c.client.HMGet(ctx, key, ids...).Result()
	if err != nil {
		return nil, err
	}
	uuids := make([]string, 0, len(vals))
	for _, v := range vals {
		if v != nil {
			if s, ok := v.(string); ok && s != "" {
				uuids = append(uuids, s)
			}
		}
	}
	// 如果有 nil（缓存不完整）则返回 error 触发 fallback
	if len(uuids) != len(ids) {
		return nil, fmt.Errorf("cache incomplete")
	}
	return uuids, nil
}

// SetChatMemberAllIDs 缓存群全部成员 ID 列表（用于发消息时获取推送目标）
// 使用 Redis SET 存储成员 userID 字符串
func (c *Cache) SetChatMemberAllIDs(ctx context.Context, chatID string, userIDs []string) error {
	if c == nil || c.client == nil || len(userIDs) == 0 {
		return nil
	}
	key := KeyChatMemberUUIDs + chatID
	members := make([]interface{}, len(userIDs))
	for i, id := range userIDs {
		members[i] = id
	}
	pipe := c.client.Pipeline()
	pipe.Del(ctx, key)
	pipe.SAdd(ctx, key, members...)
	pipe.Expire(ctx, key, TTLChatMember)
	_, err := pipe.Exec(ctx)
	return err
}

// GetChatMemberAllIDs 获取群全部成员 ID 列表
func (c *Cache) GetChatMemberAllIDs(ctx context.Context, chatID string) ([]string, error) {
	if c == nil || c.client == nil {
		return nil, fmt.Errorf("cache unavailable")
	}
	key := KeyChatMemberUUIDs + chatID
	vals, err := c.client.SMembers(ctx, key).Result()
	if err != nil {
		return nil, err
	}
	if len(vals) == 0 {
		return nil, fmt.Errorf("cache miss")
	}
	return vals, nil
}

// SetChatMutedIDs 缓存群内所有 muted 用户 ID（SET结构，通常极少）
func (c *Cache) SetChatMutedIDs(ctx context.Context, chatID string, mutedIDs []string) error {
	if c == nil || c.client == nil {
		return nil
	}
	key := KeyChatMutedSet + chatID
	pipe := c.client.Pipeline()
	pipe.Del(ctx, key)
	if len(mutedIDs) > 0 {
		members := make([]interface{}, len(mutedIDs))
		for i, id := range mutedIDs {
			members[i] = id
		}
		pipe.SAdd(ctx, key, members...)
	}
	// 即使空集合也设置 TTL，避免每次都穿透
	pipe.Set(ctx, key+":loaded", "1", TTLMutedSet)
	pipe.Expire(ctx, key, TTLMutedSet)
	_, err := pipe.Exec(ctx)
	return err
}

// GetChatMutedIDs 获取群内 muted 用户 ID SET
// 返回 (ids, loaded)，loaded=false 表示缓存未命中
func (c *Cache) GetChatMutedIDs(ctx context.Context, chatID string) (map[string]bool, bool) {
	if c == nil || c.client == nil {
		return nil, false
	}
	key := KeyChatMutedSet + chatID
	// 先检查是否已加载过（区分空集合和未命中）
	loaded := c.client.Get(ctx, key+":loaded").Val() == "1"
	if !loaded {
		return nil, false
	}
	vals, err := c.client.SMembers(ctx, key).Result()
	if err != nil {
		return nil, false
	}
	result := make(map[string]bool, len(vals))
	for _, v := range vals {
		result[v] = true
	}
	return result, true
}

// InvalidateChatMutedIDs 使群 muted 缓存失效（禁言/解禁时调用）
func (c *Cache) InvalidateChatMutedIDs(ctx context.Context, chatID string) error {
	if c == nil || c.client == nil {
		return nil
	}
	return c.Delete(ctx, KeyChatMutedSet+chatID, KeyChatMutedSet+chatID+":loaded")
}

// InvalidateChatMembers 使群成员相关所有缓存失效（加人/踢人时调用）
func (c *Cache) InvalidateChatMembers(ctx context.Context, chatID string) error {
	if c == nil || c.client == nil {
		return nil
	}
	return c.Delete(ctx,
		KeyChatMemberUUIDs+chatID,
		KeyChatMemberIDMap+chatID,
		KeyChatMutedSet+chatID,
		KeyChatMutedSet+chatID+":loaded",
	)
}

// SetUserInfo 缓存用户核心信息（by UUID）
func (c *Cache) SetUserInfo(ctx context.Context, userUUID string, user interface{}) error {
	if c == nil || c.client == nil {
		return nil
	}
	return c.Set(ctx, KeyUserInfo+userUUID, user, TTLUserInfo)
}

// GetUserInfo 获取用户缓存（by UUID）
func (c *Cache) GetUserInfo(ctx context.Context, userUUID string, dest interface{}) error {
	if c == nil || c.client == nil {
		return fmt.Errorf("cache unavailable")
	}
	return c.Get(ctx, KeyUserInfo+userUUID, dest)
}

// DeleteUserInfo 使用户缓存失效（用户信息变更时调用）
func (c *Cache) DeleteUserInfo(ctx context.Context, userUUID string) error {
	if c == nil || c.client == nil {
		return nil
	}
	return c.Delete(ctx, KeyUserInfo+userUUID)
}

// ★ 阶段二：ChatLastMsg Redis缓存（写优先，异步刷MySQL）
const (
	KeyChatLastMsg = "chat:lastmsg:" // chat:lastmsg:{chatID} → JSON
	TTLChatLastMsg = 30 * time.Minute
)

// SetChatLastMsg 写入/更新 chat_last_msg 缓存
func (c *Cache) SetChatLastMsg(ctx context.Context, chatID string, data interface{}) error {
	if c == nil || c.client == nil {
		return nil
	}
	return c.Set(ctx, KeyChatLastMsg+chatID, data, TTLChatLastMsg)
}

// GetChatLastMsg 读取 chat_last_msg 缓存
func (c *Cache) GetChatLastMsg(ctx context.Context, chatID string, dest interface{}) error {
	if c == nil || c.client == nil {
		return fmt.Errorf("cache unavailable")
	}
	return c.Get(ctx, KeyChatLastMsg+chatID, dest)
}

// DeleteChatLastMsg 使 chat_last_msg 缓存失效
func (c *Cache) DeleteChatLastMsg(ctx context.Context, chatID string) error {
	if c == nil || c.client == nil {
		return nil
	}
	return c.Delete(ctx, KeyChatLastMsg+chatID)
}

// ★ 阶段二：推送设备缓存（减少MySQL压力）
const (
	KeyPushableUsers  = "push:users"          // 有有效push_token的用户ID SET（全局）
	KeyUserPushSetting = "push:setting:"      // push:setting:{userID} → "0"/"1" (show_preview)
	TTLPushableUsers  = 10 * time.Minute
	TTLUserPushSetting = 30 * time.Minute
)

// AddPushableUser 标记用户有有效设备（注册/更新token时调用）
func (c *Cache) AddPushableUser(ctx context.Context, userID string) error {
	if c == nil || c.client == nil {
		return nil
	}
	return c.client.SAdd(ctx, KeyPushableUsers, userID).Err()
}

// RemovePushableUser 移除用户的可推送标记（token失效时调用）
func (c *Cache) RemovePushableUser(ctx context.Context, userID string) error {
	if c == nil || c.client == nil {
		return nil
	}
	return c.client.SRem(ctx, KeyPushableUsers, userID).Err()
}

// IsPushableUsersLoaded 检查可推送用户集合是否已加载
func (c *Cache) IsPushableUsersLoaded(ctx context.Context) bool {
	if c == nil || c.client == nil {
		return false
	}
	exists, _ := c.client.Exists(ctx, KeyPushableUsers).Result()
	return exists > 0
}

// LoadPushableUsers 批量初始化可推送用户集合
func (c *Cache) LoadPushableUsers(ctx context.Context, userIDs []string) error {
	if c == nil || c.client == nil || len(userIDs) == 0 {
		return nil
	}
	args := make([]interface{}, len(userIDs))
	for i, id := range userIDs {
		args[i] = id
	}
	pipe := c.client.Pipeline()
	pipe.SAdd(ctx, KeyPushableUsers, args...)
	pipe.Expire(ctx, KeyPushableUsers, TTLPushableUsers)
	_, err := pipe.Exec(ctx)
	return err
}

// FilterPushableUsers 从候选用户ID列表中过滤出有有效设备的用户
func (c *Cache) FilterPushableUsers(ctx context.Context, userIDs []uint64) ([]uint64, error) {
	if c == nil || c.client == nil {
		return userIDs, nil // 降级：返回全部
	}
	if len(userIDs) == 0 {
		return nil, nil
	}
	// 用 SMISMEMBER 批量检查
	args := make([]interface{}, len(userIDs))
	for i, id := range userIDs {
		args[i] = strconv.FormatUint(id, 10)
	}
	results, err := c.client.SMIsMember(ctx, KeyPushableUsers, args...).Result()
	if err != nil {
		return userIDs, nil // 降级：返回全部
	}
	filtered := make([]uint64, 0)
	for i, ok := range results {
		if ok {
			filtered = append(filtered, userIDs[i])
		}
	}
	return filtered, nil
}

// SetUserPushSetting 缓存用户推送设置
func (c *Cache) SetUserPushSetting(ctx context.Context, userID string, showPreview bool) error {
	if c == nil || c.client == nil {
		return nil
	}
	val := "1"
	if !showPreview {
		val = "0"
	}
	return c.client.Set(ctx, KeyUserPushSetting+userID, val, TTLUserPushSetting).Err()
}

// GetUserPushSetting 获取用户推送设置，返回 (showPreview, found)
func (c *Cache) GetUserPushSetting(ctx context.Context, userID string) (bool, bool) {
	if c == nil || c.client == nil {
		return true, false
	}
	val, err := c.client.Get(ctx, KeyUserPushSetting+userID).Result()
	if err != nil {
		return true, false
	}
	return val == "1", true
}

// ============================================================
// F-04B 时间线模型 - 大群消息预览缓存
// ============================================================

const (
	chatLastSeqTTL = 7 * 24 * time.Hour // 7天
	chatLastMsgTTL = 7 * 24 * time.Hour
)

func chatLastSeqKey(chatID string) string {
	return "chat:last_seq:" + chatID
}

func chatLastMsgKey(chatID string) string {
	return "chat:lastmsg:" + chatID
}

// SetChatLastSeq 更新群最新消息序号
func (c *Cache) SetChatLastSeq(ctx context.Context, chatID string, seq uint64) error {
	return c.client.Set(ctx, chatLastSeqKey(chatID), seq, chatLastSeqTTL).Err()
}

// GetChatLastSeq 获取群最新消息序号
func (c *Cache) GetChatLastSeq(ctx context.Context, chatID string) (uint64, error) {
	val, err := c.client.Get(ctx, chatLastSeqKey(chatID)).Uint64()
	if err == redis.Nil {
		return 0, nil
	}
	return val, err
}


// BatchGetChatLastSeq Pipeline批量获取多个群的最新序号
func (c *Cache) BatchGetChatLastSeq(ctx context.Context, chatIDs []string) (map[string]uint64, error) {
	if len(chatIDs) == 0 {
		return nil, nil
	}
	pipe := c.client.Pipeline()
	cmds := make([]*redis.StringCmd, len(chatIDs))
	for i, id := range chatIDs {
		cmds[i] = pipe.Get(ctx, chatLastSeqKey(id))
	}
	pipe.Exec(ctx)

	result := make(map[string]uint64, len(chatIDs))
	for i, cmd := range cmds {
		val, err := cmd.Uint64()
		if err == nil {
			result[chatIDs[i]] = val
		}
	}
	return result, nil
}

// BatchGetChatLastMsg Pipeline批量获取多个群的最新消息预览
func (c *Cache) BatchGetChatLastMsg(ctx context.Context, chatIDs []string) (map[string][]byte, error) {
	if len(chatIDs) == 0 {
		return nil, nil
	}
	pipe := c.client.Pipeline()
	cmds := make([]*redis.StringCmd, len(chatIDs))
	for i, id := range chatIDs {
		cmds[i] = pipe.Get(ctx, chatLastMsgKey(id))
	}
	pipe.Exec(ctx)

	result := make(map[string][]byte, len(chatIDs))
	for i, cmd := range cmds {
		val, err := cmd.Bytes()
		if err == nil {
			result[chatIDs[i]] = val
		}
	}
	return result, nil
}
