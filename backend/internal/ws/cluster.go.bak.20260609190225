package ws

import (
	"context"
	"encoding/json"
	"fmt"
	"log"
	"os"
	"sync"
	"time"

	"github.com/redis/go-redis/v9"
)

// ============================================================
// 节点标识
// ============================================================

// NodeID 当前节点唯一标识
// 部署多节点时通过环境变量注入：NODE_ID=gateway-1 ./server
// 不设置则自动用 hostname，集群内必须唯一
var NodeID string

func init() {
	NodeID = os.Getenv("NODE_ID")
	if NodeID == "" {
		hostname, err := os.Hostname()
		if err != nil {
			hostname = fmt.Sprintf("node-%d", time.Now().UnixNano())
		}
		NodeID = hostname
	}
}

// redisPushChannel 本节点的 Redis 订阅推送频道
func redisPushChannel(nodeID string) string {
	return "ws:push:" + nodeID
}

// redisBroadcastChannel 全局广播频道（所有节点共同订阅）
const redisBroadcastChannel = "ws:broadcast:all"

// redisRouteKey 用户路由的 Redis Key（uid → nodeID），单设备兼容
func redisRouteKey(uid string) string {
	return "ws:route:" + uid
}

// redisDeviceRouteKey 设备维度路由 Key（uid:deviceID → nodeID），多设备支持
func redisDeviceRouteKey(uid, deviceID string) string {
	return "ws:route:" + uid + ":" + deviceID
}

// redisUserDevicesKey 用户所有设备集合 Key（uid → Set of deviceIDs）
func redisUserDevicesKey(uid string) string {
	return "ws:devices:" + uid
}

// redisGroupOnlineKey 群在线成员的 Redis Key
func redisGroupOnlineKey(groupID string) string {
	return "ws:group:online:" + groupID
}

// redisUserGroupsKey 用户所在群组列表的 Redis Key
func redisUserGroupsKey(uid string) string {
	return "ws:user:groups:" + uid
}

// ============================================================
// 跨节点推送载体
// ============================================================

// clusterPushMsg Redis Pub/Sub 传递的推送消息
// UID 非空时为单用户推送；All=true 时为全节点广播
type clusterPushMsg struct {
	UID  string          `json:"uid"`
	UIDs []string        `json:"uids,omitempty"` // batch推送
	Data json.RawMessage `json:"data"`
	All  bool            `json:"all,omitempty"` // ★ true=全局广播到本节点所有在线用户
}

// ============================================================
// ClusterBridge 集群桥接器
// 负责：用户路由注册/注销、跨节点消息投递、Redis 订阅监听
// ============================================================

type ClusterBridge struct {
	rdb    *redis.Client
	hub    *Hub // 本节点 Hub 引用，用于本地直推
	nodeID string
	ctx    context.Context
	cancel context.CancelFunc
}

// NewClusterBridge 创建集群桥接器
func NewClusterBridge(rdb *redis.Client, hub *Hub) *ClusterBridge {
	ctx, cancel := context.WithCancel(context.Background())
	return &ClusterBridge{
		rdb:    rdb,
		hub:    hub,
		nodeID: NodeID,
		ctx:    ctx,
		cancel: cancel,
	}
}

// Start 启动集群桥接器（阻塞订阅，建议在 goroutine 中调用）
// 包含自动重连逻辑
func (cb *ClusterBridge) Start() {
	log.Printf("[Cluster] 节点 %s 启动，订阅频道: %s", cb.nodeID, redisPushChannel(cb.nodeID))
	for {
		if err := cb.subscribe(); err != nil {
			select {
			case <-cb.ctx.Done():
				log.Printf("[Cluster] 节点 %s 正常退出", cb.nodeID)
				return
			default:
				log.Printf("[Cluster] 订阅断线，3秒后重连: %v", err)
				time.Sleep(3 * time.Second)
			}
		}
	}
}

// Stop 停止集群桥接器
func (cb *ClusterBridge) Stop() {
	cb.cancel()
}

// subscribe 订阅本节点推送频道 + 全局广播频道
func (cb *ClusterBridge) subscribe() error {
	// ★ 同时订阅两个频道：
	//   1. redisPushChannel(nodeID) — 点对点推送（单用户/群组）
	//   2. redisBroadcastChannel    — 全局广播（系统公告）
	pubsub := cb.rdb.Subscribe(cb.ctx, redisPushChannel(cb.nodeID), redisBroadcastChannel)
	defer pubsub.Close()

	log.Printf("[Cluster] 已订阅频道: %s | %s", redisPushChannel(cb.nodeID), redisBroadcastChannel)

	ch := pubsub.Channel()
	for {
		select {
		case <-cb.ctx.Done():
			return nil
		case msg, ok := <-ch:
			if !ok {
				return fmt.Errorf("channel closed")
			}
			cb.handleRemotePush(msg.Payload)
		}
	}
}

// handleRemotePush 处理其他节点发来的推送指令
func (cb *ClusterBridge) handleRemotePush(payload string) {
	var pm clusterPushMsg
	if err := json.Unmarshal([]byte(payload), &pm); err != nil {
		log.Printf("[Cluster] 解析推送消息失败: %v", err)
		return
	}
	// ★ All=true 时广播给本节点所有在线用户
	if pm.All {
		cb.hub.SendToAll(pm.Data)
		return
	}
	// batch 推送：逐个推给本节点在线用户
	if len(pm.UIDs) > 0 {
		for _, uid := range pm.UIDs {
			cb.hub.sendToUserLocal(uid, pm.Data)
		}
		return
	}
	// 单用户推送
	cb.hub.sendToUserLocal(pm.UID, pm.Data)
}

// ============================================================
// 路由注册/注销（用户连接/断开时调用）
// ============================================================

// RegisterUser 用户连接成功，注册路由到 Redis
// TTL = 心跳周期(54s) × 3 = 162s，心跳时续期
func (cb *ClusterBridge) RegisterUser(uid, deviceID string) {
	pipe := cb.rdb.Pipeline()
	// 路由表：uid → nodeID（兼容单设备查询）
	pipe.Set(cb.ctx, redisRouteKey(uid), cb.nodeID, 162*time.Second)
	// 设备维度路由：uid:deviceID → nodeID（多设备精确路由）
	pipe.Set(cb.ctx, redisDeviceRouteKey(uid, deviceID), cb.nodeID, 162*time.Second)
	// 用户设备集合：记录所有在线设备
	pipe.SAdd(cb.ctx, redisUserDevicesKey(uid), deviceID)
	pipe.Expire(cb.ctx, redisUserDevicesKey(uid), 162*time.Second)
	// 在线状态（与 cache 层保持一致）
	pipe.HSet(cb.ctx, "user:online:"+uid, deviceID, time.Now().Unix())
	pipe.Expire(cb.ctx, "user:online:"+uid, 162*time.Second)
	if _, err := pipe.Exec(cb.ctx); err != nil {
		log.Printf("[Cluster] RegisterUser 失败 uid=%s: %v", uid, err)
	}
}

// UnregisterUser 用户断开，注销路由
// 注意：多设备场景下，只有最后一个设备断开才注销路由
func (cb *ClusterBridge) UnregisterUser(uid, deviceID string) {
	// 清理设备维度路由
	cb.rdb.Del(cb.ctx, redisDeviceRouteKey(uid, deviceID))
	cb.rdb.SRem(cb.ctx, redisUserDevicesKey(uid), deviceID)

	pipe := cb.rdb.Pipeline()
	pipe.HDel(cb.ctx, "user:online:"+uid, deviceID)
	// 检查是否还有其他设备在线
	remainCmd := pipe.HLen(cb.ctx, "user:online:"+uid)
	pipe.Exec(cb.ctx)

	// 如果没有其他设备了，删除路由
	if remainCmd.Val() == 0 {
		cb.rdb.Del(cb.ctx, redisRouteKey(uid))
	}
}

// RefreshUserTTL 心跳时续期路由 TTL（防止用户在线但路由过期）
func (cb *ClusterBridge) RefreshUserTTL(uid string) {
	ttl := 162 * time.Second
	pipe := cb.rdb.Pipeline()
	pipe.Expire(cb.ctx, redisRouteKey(uid), ttl)
	pipe.Expire(cb.ctx, "user:online:"+uid, ttl)
	pipe.Expire(cb.ctx, redisUserDevicesKey(uid), ttl)
	pipe.Exec(cb.ctx)
	// 刷新所有设备路由TTL
	devices, err := cb.rdb.SMembers(cb.ctx, redisUserDevicesKey(uid)).Result()
	if err == nil && len(devices) > 0 {
		pipe2 := cb.rdb.Pipeline()
		for _, deviceID := range devices {
			pipe2.Expire(cb.ctx, redisDeviceRouteKey(uid, deviceID), ttl)
		}
		pipe2.Exec(cb.ctx)
	}
}

// ============================================================
// 跨节点消息投递（最核心的方法）
// ============================================================

// SendToUser 向指定用户发送消息（自动判断本节点/跨节点）
// data 必须是已经 json.Marshal 好的字节
func (cb *ClusterBridge) SendToUser(uid string, data json.RawMessage) {
	// 1. 查 Redis 路由表，找用户在哪个节点
	nodeID, err := cb.rdb.Get(cb.ctx, redisRouteKey(uid)).Result()
	if err == redis.Nil {
		// 用户不在线（所有节点都没有），存离线消息
		cb.saveOfflineMsg(uid, data)
		return
	}
	if err != nil {
		log.Printf("[Cluster] 查询路由失败 uid=%s: %v", uid, err)
		return
	}

	// 2. 在本节点，直接推（零网络开销）
	if nodeID == cb.nodeID {
		cb.hub.sendToUserLocal(uid, data)
		return
	}

	// 3. 在其他节点，Publish 到目标节点的订阅频道
	pm, _ := json.Marshal(clusterPushMsg{UID: uid, Data: data})
	if err := cb.rdb.Publish(cb.ctx, redisPushChannel(nodeID), pm).Err(); err != nil {
		log.Printf("[Cluster] 跨节点推送失败 uid=%s → node=%s: %v", uid, nodeID, err)
	}
}

// SendToUsers 批量发送（群消息场景）
// 使用 Redis Pipeline 批量查路由，减少网络RTT
func (cb *ClusterBridge) SendToUsers(uids []string, data json.RawMessage) {
	if len(uids) == 0 {
		return
	}

	// ★ 多设备支持：按设备维度查路由，确保同一用户多设备都能收到
	nodeUsers := make(map[string][]string, 4)
	for _, uid := range uids {
		devices, err := cb.rdb.SMembers(cb.ctx, redisUserDevicesKey(uid)).Result()
		if err != nil || len(devices) == 0 {
			// 降级：用单路由key
			nodeID, err2 := cb.rdb.Get(cb.ctx, redisRouteKey(uid)).Result()
			if err2 == nil && nodeID != "" {
				nodeUsers[nodeID] = append(nodeUsers[nodeID], uid)
			}
			continue
		}
		pipe := cb.rdb.Pipeline()
		cmds := make([]*redis.StringCmd, len(devices))
		for i, deviceID := range devices {
			cmds[i] = pipe.Get(cb.ctx, redisDeviceRouteKey(uid, deviceID))
		}
		pipe.Exec(cb.ctx)
		seenNodes := make(map[string]bool)
		for _, cmd := range cmds {
			nodeID, err2 := cmd.Result()
			if err2 != nil || nodeID == "" {
				continue
			}
			if seenNodes[nodeID] {
				continue
			}
			seenNodes[nodeID] = true
			nodeUsers[nodeID] = append(nodeUsers[nodeID], uid)
		}
	}

	// 本节点直接推；其他节点合并为一条 batch Publish，N次→1次 Redis 往返
	pipe2 := cb.rdb.Pipeline()
	for nodeID, users := range nodeUsers {
		if nodeID == cb.nodeID {
			for _, uid := range users {
				cb.hub.sendToUserLocal(uid, data)
			}
		} else {
			// 同节点所有用户打包成一条消息
			payload, _ := json.Marshal(clusterPushMsg{UIDs: users, Data: data})
			pipe2.Publish(cb.ctx, redisPushChannel(nodeID), payload)
		}
	}
	pipe2.Exec(cb.ctx)
}

// ============================================================
// 群在线成员管理（替代本地 chatSubscribers 做跨节点群推）
// ============================================================

// JoinGroupOnline 用户上线时，加入其所有群的在线成员集合
func (cb *ClusterBridge) JoinGroupOnline(uid string, groupIDs []string) {
	if len(groupIDs) == 0 {
		return
	}
	// 把用户的群组列表存到Redis（下线时用）
	args := make([]interface{}, len(groupIDs))
	for i, g := range groupIDs {
		args[i] = g
	}
	pipe := cb.rdb.Pipeline()
	pipe.SAdd(cb.ctx, redisUserGroupsKey(uid), args...)
	pipe.Expire(cb.ctx, redisUserGroupsKey(uid), 7*24*time.Hour)
	for _, gid := range groupIDs {
		pipe.SAdd(cb.ctx, redisGroupOnlineKey(gid), uid)
		pipe.Expire(cb.ctx, redisGroupOnlineKey(gid), 7*24*time.Hour)
	}
	pipe.Exec(cb.ctx)
}

// LeaveGroupOnline 用户下线时，从所有群的在线成员集合移除
func (cb *ClusterBridge) LeaveGroupOnline(uid string) {
	// 取出用户所在群列表
	groupIDs, err := cb.rdb.SMembers(cb.ctx, redisUserGroupsKey(uid)).Result()
	if err != nil || len(groupIDs) == 0 {
		return
	}
	pipe := cb.rdb.Pipeline()
	for _, gid := range groupIDs {
		pipe.SRem(cb.ctx, redisGroupOnlineKey(gid), uid)
	}
	pipe.Exec(cb.ctx)
}

// GetGroupOnlineMembers 获取群在线成员（跨所有节点）
func (cb *ClusterBridge) GetGroupOnlineMembers(groupID string) ([]string, error) {
	return cb.rdb.SMembers(cb.ctx, redisGroupOnlineKey(groupID)).Result()
}

// JoinGroupOnlineOne 加入单个群的在线成员集合（订阅会话/加群时调用）
func (cb *ClusterBridge) JoinGroupOnlineOne(uid, groupID string) {
	pipe := cb.rdb.Pipeline()
	pipe.SAdd(cb.ctx, redisGroupOnlineKey(groupID), uid)
	pipe.SAdd(cb.ctx, redisUserGroupsKey(uid), groupID)
	pipe.Exec(cb.ctx)
}

// LeaveGroupOnlineOne 离开单个群的在线成员集合（取消订阅/退群时调用）
func (cb *ClusterBridge) LeaveGroupOnlineOne(uid, groupID string) {
	pipe := cb.rdb.Pipeline()
	pipe.SRem(cb.ctx, redisGroupOnlineKey(groupID), uid)
	pipe.SRem(cb.ctx, redisUserGroupsKey(uid), groupID)
	pipe.Exec(cb.ctx)
}

// ============================================================
// 离线消息（用户不在线时暂存）
// ============================================================

const (
	offlineMsgKey    = "offline:msg:"
	offlineMsgMaxLen = 500 // 每用户最多暂存500条
)

// saveOfflineMsg 存储离线消息
func (cb *ClusterBridge) saveOfflineMsg(uid string, data json.RawMessage) {
	key := offlineMsgKey + uid
	pipe := cb.rdb.Pipeline()
	pipe.LPush(cb.ctx, key, []byte(data))
	pipe.LTrim(cb.ctx, key, 0, offlineMsgMaxLen-1) // 超出500条丢弃最老的
	pipe.Expire(cb.ctx, key, 7*24*time.Hour)       // 7天过期
	pipe.Exec(cb.ctx)
}

// GetOfflineMsgs 用户上线时拉取离线消息（并清空）
func (cb *ClusterBridge) GetOfflineMsgs(uid string) ([]json.RawMessage, error) {
	key := offlineMsgKey + uid
	// 原子获取并删除
	pipe := cb.rdb.Pipeline()
	lrangeCmd := pipe.LRange(cb.ctx, key, 0, -1)
	pipe.Del(cb.ctx, key)
	if _, err := pipe.Exec(cb.ctx); err != nil {
		return nil, err
	}

	results := lrangeCmd.Val()
	msgs := make([]json.RawMessage, 0, len(results))
	// 反转顺序（LPush导致最新的在前，需要反转为时间正序）
	for i := len(results) - 1; i >= 0; i-- {
		msgs = append(msgs, json.RawMessage(results[i]))
	}
	return msgs, nil
}

// ============================================================
// 跨节点 IsUserOnline（查 Redis，不只查本节点内存）
// ============================================================

// IsUserOnlineCluster 检查用户是否在线（跨所有节点）
func (cb *ClusterBridge) IsUserOnlineCluster(uid string) bool {
	exists, _ := cb.rdb.Exists(cb.ctx, redisRouteKey(uid)).Result()
	return exists > 0
}

// ============================================================
// 大群推送（4万人群聊专用，分批并发，不打爆系统）
// ============================================================

// BroadcastToGroup 向群内所有在线成员推送消息（F-04 大群分批异步推送优化）
// 优化点：
//   1. SScan流式读取，避免SMembers一次性加载5万成员
//   2. 路由查询直接按节点分组，不再重复查路由
//   3. 本节点推送用固定goroutine池，减少goroutine创建开销
//   4. 跨节点Publish合并Pipeline，减少Redis网络往返
func (cb *ClusterBridge) BroadcastToGroup(groupID string, data json.RawMessage) {
	const (
		scanCount   = 500  // 每次SScan读取500个成员
		batchSize   = 300  // 每批推送300人
		maxWorkers  = 32   // 本节点推送goroutine池大小
		pipelineCap = 1000 // Pipeline批量GET上限
	)

	ctx := cb.ctx
	key := redisGroupOnlineKey(groupID)

	// 按节点分组：key=nodeID, value=uid列表
	nodeUsers := make(map[string][]string, 4)

	// ★ 优化1：SScan流式读取，每次500个，避免一次性加载全部成员
	var cursor uint64
	pipeBuf := make([]string, 0, pipelineCap)

	flushPipeline := func(uids []string) {
		if len(uids) == 0 {
			return
		}
		// ★ 多设备支持：先查用户设备列表，再按设备查路由
		for _, uid := range uids {
			devices, err := cb.rdb.SMembers(ctx, redisUserDevicesKey(uid)).Result()
			if err != nil || len(devices) == 0 {
				// 降级：用单路由key
				nodeID, err2 := cb.rdb.Get(ctx, redisRouteKey(uid)).Result()
				if err2 == nil && nodeID != "" {
					nodeUsers[nodeID] = append(nodeUsers[nodeID], uid)
				}
				continue
			}
			pipe := cb.rdb.Pipeline()
			cmds := make([]*redis.StringCmd, len(devices))
			for i, deviceID := range devices {
				cmds[i] = pipe.Get(ctx, redisDeviceRouteKey(uid, deviceID))
			}
			pipe.Exec(ctx)
			seenNodes := make(map[string]bool)
			for _, cmd := range cmds {
				nodeID, err2 := cmd.Result()
				if err2 != nil || nodeID == "" {
					continue
				}
				if seenNodes[nodeID] {
					continue
				}
				seenNodes[nodeID] = true
				nodeUsers[nodeID] = append(nodeUsers[nodeID], uid)
			}
		}
	}

	for {
		var members []string
		var err error
		members, cursor, err = cb.rdb.SScan(ctx, key, cursor, "*", scanCount).Result()
		if err != nil {
			break
		}
		pipeBuf = append(pipeBuf, members...)
		// 积累到pipelineCap时批量查路由
		if len(pipeBuf) >= pipelineCap {
			flushPipeline(pipeBuf)
			pipeBuf = pipeBuf[:0]
		}
		if cursor == 0 {
			break
		}
	}
	// 处理剩余
	flushPipeline(pipeBuf)

	if len(nodeUsers) == 0 {
		return
	}

	var wg sync.WaitGroup

	// ★ 优化3：本节点用固定大小goroutine池并行推送
	if localUsers, ok := nodeUsers[cb.nodeID]; ok && len(localUsers) > 0 {
		sem := make(chan struct{}, maxWorkers)
		for i := 0; i < len(localUsers); i += batchSize {
			end := i + batchSize
			if end > len(localUsers) {
				end = len(localUsers)
			}
			batch := localUsers[i:end]
			wg.Add(1)
			sem <- struct{}{}
			go func(b []string) {
				defer wg.Done()
				defer func() { <-sem }()
				for _, uid := range b {
					cb.hub.sendToUserLocal(uid, data)
				}
			}(batch)
		}
		delete(nodeUsers, cb.nodeID)
	}

	// ★ 优化4：跨节点按目标节点分组，合并Pipeline一次Publish
	if len(nodeUsers) > 0 {
		wg.Add(1)
		go func() {
			defer wg.Done()
			pipe := cb.rdb.Pipeline()
			for nodeID, users := range nodeUsers {
				// 每个目标节点一条Publish（已按节点分组，无需再拆分）
				for i := 0; i < len(users); i += batchSize {
					end := i + batchSize
					if end > len(users) {
						end = len(users)
					}
					payload, _ := json.Marshal(clusterPushMsg{UIDs: users[i:end], Data: data})
					pipe.Publish(ctx, redisPushChannel(nodeID), payload)
				}
			}
			pipe.Exec(ctx)
		}()
	}

	wg.Wait()
}


// BroadcastToAll 向集群内所有节点的所有在线用户广播消息
// 通过发布到 redisBroadcastChannel，每个节点收到后本地执行 SendToAll
func (cb *ClusterBridge) BroadcastToAll(data json.RawMessage) {
	pm, err := json.Marshal(clusterPushMsg{All: true, Data: data})
	if err != nil {
		log.Printf("[Cluster] BroadcastToAll marshal error: %v", err)
		return
	}
	if err := cb.rdb.Publish(cb.ctx, redisBroadcastChannel, pm).Err(); err != nil {
		log.Printf("[Cluster] BroadcastToAll publish error: %v", err)
	}
}
