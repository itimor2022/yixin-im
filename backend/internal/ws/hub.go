package ws

import (
	"encoding/json"
	"log"
	"sync"
	"sync/atomic"
	"time"

	"gaoranim/internal/privacy"
	"gaoranim/internal/shard"

	"gorm.io/gorm"
)

// Hub WebSocket连接管理中心
// 使用分片设计支持百万级连接
type Hub struct {
	// 数据库引用
	db *gorm.DB

	// 用户连接映射 userID -> []*Client
	clients *shard.ShardedMap[*ClientSet]

	// 会话订阅映射 chatID -> []*Client
	chatSubscribers *shard.ShardedMap[*ClientSet]

	// 注册通道
	register chan *Client

	// 注销通道
	unregister chan *Client

	// 广播消息
	broadcast chan *BroadcastMessage

	// 在线用户数
	onlineCount int64

	// 运行状态
	running bool
	mu      sync.RWMutex
}

// ClientSet 客户端集合（线程安全）
type ClientSet struct {
	sync.RWMutex
	clients map[*Client]struct{}
}

func NewClientSet() *ClientSet {
	return &ClientSet{
		clients: make(map[*Client]struct{}),
	}
}

func (cs *ClientSet) Add(c *Client) {
	cs.Lock()
	cs.clients[c] = struct{}{}
	cs.Unlock()
}

func (cs *ClientSet) Remove(c *Client) {
	cs.Lock()
	delete(cs.clients, c)
	cs.Unlock()
}

func (cs *ClientSet) Len() int {
	cs.RLock()
	defer cs.RUnlock()
	return len(cs.clients)
}

func (cs *ClientSet) Range(f func(*Client)) {
	cs.RLock()
	defer cs.RUnlock()
	for c := range cs.clients {
		f(c)
	}
}

// BroadcastMessage 广播消息
type BroadcastMessage struct {
	Type      string      `json:"type"`
	ChatID    string      `json:"chat_id,omitempty"`
	UserIDs   []string    `json:"user_ids,omitempty"`
	All       bool        `json:"-"`
	Data      interface{} `json:"data"`
	ExcludeID string      `json:"-"` // 排除的客户端ID
}

// Hub 默认工作协程数量
// 注册/注销 worker: 处理连接建立和断开
// 广播 worker: 处理消息推送
const (
	defaultRegisterWorkers  = 8  // 注册/注销处理协程数
	defaultBroadcastWorkers = 16 // 广播消息处理协程数（需要更多，因为涉及遍历和发送）
)

// NewHub 创建Hub
func NewHub(db *gorm.DB) *Hub {
	return &Hub{
		db:              db,
		clients:         shard.NewShardedMap[*ClientSet](64),
		chatSubscribers: shard.NewShardedMap[*ClientSet](64),
		register:        make(chan *Client, 5000),
		unregister:      make(chan *Client, 5000),
		broadcast:       make(chan *BroadcastMessage, 50000),
	}
}

// Run 启动Hub - 多协程并行处理
func (h *Hub) Run() {
	h.mu.Lock()
	h.running = true
	h.mu.Unlock()

	log.Printf("[WS Hub] Starting with %d register workers, %d broadcast workers...",
		defaultRegisterWorkers, defaultBroadcastWorkers)

	// 启动多个 worker 处理注册/注销
	for i := 0; i < defaultRegisterWorkers; i++ {
		go h.registerWorker(i)
	}

	// 启动多个 worker 处理广播（广播需要更多worker，因为涉及遍历发送）
	for i := 0; i < defaultBroadcastWorkers; i++ {
		go h.broadcastWorker(i)
	}

	// 主协程保持运行
	select {}
}

// registerWorker 注册/注销处理 worker
func (h *Hub) registerWorker(id int) {
	log.Printf("[WS Hub] Register worker %d started", id)
	for {
		select {
		case client := <-h.register:
			h.handleRegister(client)
		case client := <-h.unregister:
			h.handleUnregister(client)
		}
	}
}

// broadcastWorker 广播消息处理 worker
func (h *Hub) broadcastWorker(id int) {
	log.Printf("[WS Hub] Broadcast worker %d started", id)
	for message := range h.broadcast {
		h.handleBroadcast(message)
	}
}

// handleRegister 处理客户端注册
func (h *Hub) handleRegister(client *Client) {
	userID := client.UserID

	// 获取或创建用户的客户端集合
	clientSet, ok := h.clients.Get(userID)
	isNewOnline := !ok || clientSet.Len() == 0 // 用户是否是新上线

	if !ok {
		clientSet = NewClientSet()
		h.clients.Set(userID, clientSet)
	}

	clientSet.Add(client)
	atomic.AddInt64(&h.onlineCount, 1)

	log.Printf("[WS Hub] Client registered: userID=%s, deviceID=%s, total=%d",
		userID, client.DeviceID, atomic.LoadInt64(&h.onlineCount))

	// 如果用户是新上线，广播在线状态
	if isNewOnline {
		h.broadcastUserStatus(userID, true)
	}
}

// handleUnregister 处理客户端注销
func (h *Hub) handleUnregister(client *Client) {
	userID := client.UserID
	isGoingOffline := false

	// 从用户客户端集合中移除
	if clientSet, ok := h.clients.Get(userID); ok {
		clientSet.Remove(client)
		if clientSet.Len() == 0 {
			h.clients.Delete(userID)
			isGoingOffline = true // 用户所有设备都离线了
		}
	}

	// 从所有订阅的会话中移除
	for _, chatID := range client.subscribedChats {
		if subs, ok := h.chatSubscribers.Get(chatID); ok {
			subs.Remove(client)
			if subs.Len() == 0 {
				h.chatSubscribers.Delete(chatID)
			}
		}
	}

	atomic.AddInt64(&h.onlineCount, -1)
	client.Close()

	log.Printf("[WS Hub] Client unregistered: userID=%s, total=%d",
		userID, atomic.LoadInt64(&h.onlineCount))

	// 如果用户完全离线，更新 last_seen 并广播离线状态
	if isGoingOffline {
		// 更新用户最后在线时间
		if h.db != nil {
			h.db.Table("users").Where("uuid = ?", userID).Update("last_seen", time.Now())
		}
		h.broadcastUserStatus(userID, false)
	}
}

// broadcastUserStatus 广播用户在线状态变化（仅通知同聊天室的用户，避免 O(N^2) 广播风暴）
func (h *Hub) broadcastUserStatus(userID string, isOnline bool) {
	data, _ := json.Marshal(map[string]interface{}{
		"type":      "user_status",
		"user_id":   userID,
		"is_online": isOnline,
	})

	// 只通知与该用户有共同聊天的在线用户
	notified := make(map[string]bool)
	h.chatSubscribers.Range(func(chatID string, subs *ClientSet) bool {
		hasUser := false
		subs.Range(func(c *Client) {
			if c.UserID == userID {
				hasUser = true
			}
		})
		if hasUser {
			subs.Range(func(c *Client) {
				if c.UserID != userID && !notified[c.UserID] {
					if h.db != nil {
						visible, err := privacy.CanViewerSeeOnlineStatusByUUID(h.db, c.UserID, userID)
						if err != nil || !visible {
							return
						}
					}
					c.Send(data)
					notified[c.UserID] = true
				}
			})
		}
		return true
	})

	log.Printf("[WS Hub] Broadcast user status: userID=%s, isOnline=%v", userID, isOnline)
}

// handleBroadcast 处理广播消息
func (h *Hub) handleBroadcast(msg *BroadcastMessage) {
	// 只序列化 Data 字段，而不是整个 BroadcastMessage
	data, err := json.Marshal(msg.Data)
	if err != nil {
		log.Printf("[WS Hub] Failed to marshal broadcast data: %v", err)
		return
	}

	log.Printf("[WS Hub] Broadcasting: type=%s, userIDs=%v, chatID=%s, data=%s",
		msg.Type, msg.UserIDs, msg.ChatID, string(data))

	if msg.All {
		h.sendToAll(data, msg.ExcludeID)
		return
	}

	// 发送给特定用户
	if len(msg.UserIDs) > 0 {
		seen := make(map[string]struct{}, len(msg.UserIDs))
		for _, userID := range msg.UserIDs {
			if _, ok := seen[userID]; ok {
				continue
			}
			seen[userID] = struct{}{}
			h.sendToUser(userID, data, msg.ExcludeID)
		}
		return
	}

	// 发送给会话订阅者
	if msg.ChatID != "" {
		h.sendToChat(msg.ChatID, data, msg.ExcludeID)
		return
	}
}

// sendToUser 发送消息给用户的所有设备
func (h *Hub) sendToUser(userID string, data []byte, excludeID string) {
	if clientSet, ok := h.clients.Get(userID); ok {
		clientSet.Range(func(c *Client) {
			if c.ID != excludeID {
				c.Send(data)
			}
		})
	}
}

// sendToChat 发送消息给会话的所有订阅者
func (h *Hub) sendToChat(chatID string, data []byte, excludeID string) {
	if subs, ok := h.chatSubscribers.Get(chatID); ok {
		subs.Range(func(c *Client) {
			if c.ID != excludeID {
				c.Send(data)
			}
		})
	}
}

func (h *Hub) sendToAll(data []byte, excludeID string) {
	h.clients.Range(func(_ string, clientSet *ClientSet) bool {
		clientSet.Range(func(c *Client) {
			if c.ID != excludeID {
				c.Send(data)
			}
		})
		return true
	})
}

// Register 注册客户端
func (h *Hub) Register(client *Client) {
	h.register <- client
}

// Unregister 注销客户端
func (h *Hub) Unregister(client *Client) {
	h.unregister <- client
}

// Broadcast 广播消息
func (h *Hub) Broadcast(msg *BroadcastMessage) {
	h.broadcast <- msg
}

// SubscribeChat 订阅会话（幂等：已订阅则跳过）
func (h *Hub) SubscribeChat(client *Client, chatID string) {
	// 检查是否已订阅，防止重复加入 subscribedChats 切片
	for _, id := range client.subscribedChats {
		if id == chatID {
			return
		}
	}
	subs, ok := h.chatSubscribers.Get(chatID)
	if !ok {
		subs = NewClientSet()
		h.chatSubscribers.Set(chatID, subs)
	}
	subs.Add(client)
	client.subscribedChats = append(client.subscribedChats, chatID)
}

// UnsubscribeChat 取消订阅会话
func (h *Hub) UnsubscribeChat(client *Client, chatID string) {
	if subs, ok := h.chatSubscribers.Get(chatID); ok {
		subs.Remove(client)
	}

	// 从客户端的订阅列表中移除
	for i, id := range client.subscribedChats {
		if id == chatID {
			client.subscribedChats = append(client.subscribedChats[:i], client.subscribedChats[i+1:]...)
			break
		}
	}
}

// SendToUser 发送消息给指定用户
func (h *Hub) SendToUser(userID string, data interface{}) {
	h.Broadcast(&BroadcastMessage{
		UserIDs: []string{userID},
		Data:    data,
	})
}

// SendToUsers 发送消息给多个用户
func (h *Hub) SendToUsers(userIDs []string, data interface{}) {
	h.Broadcast(&BroadcastMessage{
		UserIDs: userIDs,
		Data:    data,
	})
}

// SendToChat 发送消息给会话
func (h *Hub) SendToChat(chatID string, data interface{}, excludeID string) {
	h.Broadcast(&BroadcastMessage{
		ChatID:    chatID,
		Data:      data,
		ExcludeID: excludeID,
	})
}

func (h *Hub) SendToAll(data interface{}) {
	h.Broadcast(&BroadcastMessage{
		All:  true,
		Data: data,
	})
}

// GetChatOnlineCount 获取聊天室在线人数（通过已订阅的 WebSocket 客户端计数）
func (h *Hub) GetChatOnlineCount(chatID string) int {
	if subs, ok := h.chatSubscribers.Get(chatID); ok {
		seen := make(map[string]bool)
		count := 0
		subs.Range(func(c *Client) {
			if !seen[c.UserID] {
				seen[c.UserID] = true
				count++
			}
		})
		return count
	}
	return 0
}

// IsUserOnline 检查用户是否在线
func (h *Hub) IsUserOnline(userID string) bool {
	if clientSet, ok := h.clients.Get(userID); ok {
		return clientSet.Len() > 0
	}
	return false
}

// GetUserDeviceCount 获取用户在线设备数
func (h *Hub) GetUserDeviceCount(userID string) int {
	if clientSet, ok := h.clients.Get(userID); ok {
		return clientSet.Len()
	}
	return 0
}

// DisconnectUser 断开指定用户的所有 WebSocket 连接
func (h *Hub) DisconnectUser(userID string) {
	if clientSet, ok := h.clients.Get(userID); ok {
		clientSet.RLock()
		clients := make([]*Client, 0, len(clientSet.clients))
		for c := range clientSet.clients {
			clients = append(clients, c)
		}
		clientSet.RUnlock()
		for _, c := range clients {
			h.unregister <- c
		}
	}
}

// GetOnlineCount 获取在线总数
func (h *Hub) GetOnlineCount() int64 {
	return atomic.LoadInt64(&h.onlineCount)
}

// GetStats 获取统计信息
func (h *Hub) GetStats() map[string]interface{} {
	return map[string]interface{}{
		"online_connections": atomic.LoadInt64(&h.onlineCount),
		"online_users":       h.clients.Count(),
		"active_chats":       h.chatSubscribers.Count(),
		"timestamp":          time.Now().Unix(),
	}
}
