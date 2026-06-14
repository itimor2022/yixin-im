package ws

import (
	"encoding/json"
	"log"
	"strings"
	"sync"
	"time"

	"gaoranim/internal/privacy"

	"github.com/google/uuid"
	"github.com/gorilla/websocket"
	"gorm.io/gorm"
)

const (
	writeWait        = 10 * time.Second
	maxMessageSize   = 65536
	sendBufferSize   = 4096
	chatAuthCacheTTL = 2 * time.Second
)

var (
	PongWait   = 30 * time.Second
	PingPeriod = (PongWait * 9) / 10
)

func SetHeartbeatTimeout(seconds int) {
	if seconds < 10 {
		seconds = 10
	}
	if seconds > 600 {
		seconds = 600
	}
	PongWait = time.Duration(seconds) * time.Second
	PingPeriod = (PongWait * 9) / 10
	log.Printf("[WS] Heartbeat timeout set to %d seconds", seconds)
}

// Client WebSocket客户端
type Client struct {
	ID              string
	UserID          string
	DeviceID        string
	DeviceType      string
	conn            *websocket.Conn
	hub             *Hub
	send            chan []byte
	subscribedChats []string
	authResultCache map[string]bool
	authCheckedAt   map[string]time.Time
	closed          bool
	closeMu         sync.Mutex
}

// NewClient 创建新客户端
func NewClient(hub *Hub, conn *websocket.Conn, userID, deviceID, deviceType string) *Client {
	return &Client{
		ID:              uuid.New().String(),
		UserID:          userID,
		DeviceID:        deviceID,
		DeviceType:      deviceType,
		conn:            conn,
		hub:             hub,
		send:            make(chan []byte, sendBufferSize),
		subscribedChats: make([]string, 0),
		authResultCache: make(map[string]bool),
		authCheckedAt:   make(map[string]time.Time),
	}
}

// Start 启动客户端读写协程
func (c *Client) Start() {
	go c.writePump()
	go c.readPump()
}

// readPump 读取消息
func (c *Client) readPump() {
	defer func() {
		c.hub.Unregister(c)
	}()

	c.conn.SetReadLimit(maxMessageSize)
	c.conn.SetReadDeadline(time.Now().Add(PongWait))
	c.conn.SetPongHandler(func(string) error {
		c.conn.SetReadDeadline(time.Now().Add(PongWait))
		return nil
	})

	for {
		_, message, err := c.conn.ReadMessage()
		if err != nil {
			if websocket.IsUnexpectedCloseError(err, websocket.CloseGoingAway, websocket.CloseAbnormalClosure) {
				log.Printf("[WS Client] Read error: %v", err)
			}
			break
		}

		// 处理消息
		c.handleMessage(message)
	}
}

// writePump 写入消息
func (c *Client) writePump() {
	ticker := time.NewTicker(PingPeriod)
	defer func() {
		ticker.Stop()
		c.conn.Close()
	}()

	for {
		select {
		case message, ok := <-c.send:
			c.conn.SetWriteDeadline(time.Now().Add(writeWait))
			if !ok {
				// 通道已关闭
				c.conn.WriteMessage(websocket.CloseMessage, []byte{})
				return
			}

			// 发送当前消息
			if err := c.conn.WriteMessage(websocket.TextMessage, message); err != nil {
				return
			}

			// 立即发送缓冲区中的其他消息（每条消息独立发送）
			n := len(c.send)
			for i := 0; i < n; i++ {
				msg := <-c.send
				if err := c.conn.WriteMessage(websocket.TextMessage, msg); err != nil {
					return
				}
			}

		case <-ticker.C:
			c.conn.SetWriteDeadline(time.Now().Add(writeWait))
			if err := c.conn.WriteMessage(websocket.PingMessage, nil); err != nil {
				return
			}
			// ========== 新增：心跳时续期 Redis 路由 TTL ==========
			// 保持用户路由在 Redis 中不过期，防止长连接被误判为离线
			if c.hub != nil && c.hub.cluster != nil {
				c.hub.cluster.RefreshUserTTL(c.UserID)
			}
			// ========== 新增结束 ==========
		}
	}
}

// Send 发送消息
func (c *Client) Send(data []byte) {
	c.closeMu.Lock()
	if c.closed {
		c.closeMu.Unlock()
		return
	}
	c.closeMu.Unlock()

	select {
	case c.send <- data:
	default:
		// 缓冲区满，丢弃消息
		log.Printf("[WS Client] Send buffer full, dropping message for user %s", c.UserID)
	}
}

// Close 关闭客户端
func (c *Client) Close() {
	c.closeMu.Lock()
	defer c.closeMu.Unlock()

	if c.closed {
		return
	}
	c.closed = true
	close(c.send)
}

// WSMessage WebSocket消息格式
type WSMessage struct {
	Type string          `json:"type"`
	Seq  int64           `json:"seq,omitempty"`
	Data json.RawMessage `json:"data,omitempty"`
}

// handleMessage 处理接收到的消息
func (c *Client) handleMessage(data []byte) {
	var msg WSMessage
	if err := json.Unmarshal(data, &msg); err != nil {
		log.Printf("[WS Client] Invalid message format: %v", err)
		c.sendError("invalid_message", "消息格式错误")
		return
	}

	switch msg.Type {
	case "ping":
		c.conn.SetReadDeadline(time.Now().Add(PongWait))
		c.sendPong(msg.Seq)

	case "subscribe":
		c.handleSubscribe(msg.Data)

	case "unsubscribe":
		c.handleUnsubscribe(msg.Data)

	case "message":
		c.handleSendMessage(msg.Data)

	case "typing":
		c.handleTyping(msg.Data)

	case "read":
		c.handleReadReceipt(msg.Data)

	case "online":
		c.handleOnlineStatus(msg.Data)

	default:
		c.sendError("unknown_type", "未知的消息类型")
	}
}

// sendPong 发送pong响应
func (c *Client) sendPong(seq int64) {
	resp := map[string]interface{}{
		"type": "pong",
		"seq":  seq,
		"time": time.Now().UnixMilli(),
	}
	data, _ := json.Marshal(resp)
	c.Send(data)
}

// sendError 发送错误消息
func (c *Client) sendError(code, message string) {
	resp := map[string]interface{}{
		"type":    "error",
		"code":    code,
		"message": message,
	}
	data, _ := json.Marshal(resp)
	c.Send(data)
}

// sendSuccess 发送成功消息
func (c *Client) sendSuccess(msgType string, payload interface{}) {
	resp := map[string]interface{}{
		"type": msgType,
		"data": payload,
	}
	data, _ := json.Marshal(resp)
	c.Send(data)
}

// 订阅请求
type subscribeRequest struct {
	ChatIDs []string `json:"chat_ids"`
}

func normalizeChatIDs(raw []string) []string {
	if len(raw) == 0 {
		return []string{}
	}
	out := make([]string, 0, len(raw))
	seen := make(map[string]struct{}, len(raw))
	for _, chatID := range raw {
		id := strings.TrimSpace(chatID)
		if id == "" {
			continue
		}
		if _, ok := seen[id]; ok {
			continue
		}
		seen[id] = struct{}{}
		out = append(out, id)
	}
	return out
}

func (c *Client) filterAuthorizedChatIDs(chatIDs []string) (authorized []string, rejected []string, err error) {
	normalized := normalizeChatIDs(chatIDs)
	if len(normalized) == 0 {
		return []string{}, []string{}, nil
	}
	if c.hub == nil || c.hub.db == nil {
		return nil, nil, gorm.ErrInvalidDB
	}

	type chatUUIDRow struct {
		ChatUUID string `gorm:"column:chat_uuid"`
	}

	var rows []chatUUIDRow
	if err := c.hub.db.Table("chat_members cm").
		Select("ch.uuid AS chat_uuid").
		Joins("JOIN users u ON u.id = cm.user_id").
		Joins("JOIN chats ch ON ch.id = cm.chat_id").
		Where("u.uuid = ? AND ch.uuid IN ?", c.UserID, normalized).
		Where("ch.deleted_at IS NULL").
		Where("ch.status = ?", 0).
		Scan(&rows).Error; err != nil {
		return nil, nil, err
	}

	allowedSet := make(map[string]struct{}, len(rows))
	for _, row := range rows {
		if row.ChatUUID != "" {
			allowedSet[row.ChatUUID] = struct{}{}
		}
	}

	authorized = make([]string, 0, len(normalized))
	rejected = make([]string, 0, len(normalized))
	for _, chatID := range normalized {
		if _, ok := allowedSet[chatID]; ok {
			authorized = append(authorized, chatID)
			continue
		}
		rejected = append(rejected, chatID)
	}
	return authorized, rejected, nil
}

func (c *Client) isChatSubscribed(chatID string) bool {
	for _, id := range c.subscribedChats {
		if id == chatID {
			return true
		}
	}
	return false
}

func (c *Client) isUserAuthorizedForChat(chatID string) bool {
	now := time.Now()
	if checkedAt, ok := c.authCheckedAt[chatID]; ok {
		if now.Sub(checkedAt) <= chatAuthCacheTTL {
			if cached, exists := c.authResultCache[chatID]; exists {
				return cached
			}
		}
	}

	if c.hub == nil || c.hub.db == nil {
		return false
	}
	var count int64
	if err := c.hub.db.Table("chat_members cm").
		Joins("JOIN users u ON u.id = cm.user_id").
		Joins("JOIN chats ch ON ch.id = cm.chat_id").
		Where("u.uuid = ?", c.UserID).
		Where("ch.uuid = ?", chatID).
		Where("ch.deleted_at IS NULL").
		Where("ch.status = ?", 0).
		Count(&count).Error; err != nil {
		log.Printf("[WS] auth check failed user=%s chat=%s err=%v", c.UserID, chatID, err)
		c.authResultCache[chatID] = false
		c.authCheckedAt[chatID] = now
		return false
	}
	allowed := count > 0
	c.authResultCache[chatID] = allowed
	c.authCheckedAt[chatID] = now
	return allowed
}

// handleSubscribe 处理订阅请求
func (c *Client) handleSubscribe(data json.RawMessage) {
	var req subscribeRequest
	if err := json.Unmarshal(data, &req); err != nil {
		c.sendError("invalid_data", "订阅数据格式错误")
		return
	}

	authorizedChatIDs, rejectedChatIDs, err := c.filterAuthorizedChatIDs(req.ChatIDs)
	if err != nil {
		c.sendError("service_unavailable", "订阅失败，请稍后重试")
		return
	}
	if len(authorizedChatIDs) == 0 && len(rejectedChatIDs) > 0 {
		c.sendError("forbidden", "无权订阅该会话")
		return
	}

	for _, chatID := range authorizedChatIDs {
		c.hub.SubscribeChat(c, chatID)
		c.authResultCache[chatID] = true
		c.authCheckedAt[chatID] = time.Now()

		// ========== 新增：订阅会话时同步加入集群群在线成员 ==========
		// 让其他节点也能感知到该用户在此群在线
		if c.hub.cluster != nil {
			c.hub.cluster.JoinGroupOnlineOne(c.UserID, chatID)
		}
		// ========== 新增结束 ==========
	}
	for _, chatID := range rejectedChatIDs {
		c.authResultCache[chatID] = false
		c.authCheckedAt[chatID] = time.Now()
	}

	c.sendSuccess("subscribed", map[string]interface{}{
		"chat_ids":          authorizedChatIDs,
		"rejected_chat_ids": rejectedChatIDs,
	})
}

// handleUnsubscribe 处理取消订阅
func (c *Client) handleUnsubscribe(data json.RawMessage) {
	var req subscribeRequest
	if err := json.Unmarshal(data, &req); err != nil {
		c.sendError("invalid_data", "数据格式错误")
		return
	}

	for _, chatID := range normalizeChatIDs(req.ChatIDs) {
		c.hub.UnsubscribeChat(c, chatID)
		delete(c.authResultCache, chatID)
		delete(c.authCheckedAt, chatID)

		// ========== 新增：取消订阅时同步退出集群群在线成员 ==========
		if c.hub.cluster != nil {
			c.hub.cluster.LeaveGroupOnlineOne(c.UserID, chatID)
		}
		// ========== 新增结束 ==========
	}

	c.sendSuccess("unsubscribed", map[string]interface{}{
		"chat_ids": normalizeChatIDs(req.ChatIDs),
	})
}

// handleSendMessage 处理发送消息（通过消息队列）
func (c *Client) handleSendMessage(data json.RawMessage) {
	// 消息发送通过HTTP API，这里只做确认
	c.sendSuccess("message_received", map[string]interface{}{
		"status": "queued",
	})
}

// 正在输入请求
type typingRequest struct {
	ChatID string `json:"chat_id"`
	Action string `json:"action"` // start/stop
}

// handleTyping 处理正在输入状态
func (c *Client) handleTyping(data json.RawMessage) {
	var req typingRequest
	if err := json.Unmarshal(data, &req); err != nil {
		return
	}
	req.ChatID = strings.TrimSpace(req.ChatID)
	if req.ChatID == "" {
		return
	}
	if req.Action != "start" && req.Action != "stop" {
		return
	}
	if !c.isChatSubscribed(req.ChatID) {
		c.sendError("forbidden", "未订阅该会话")
		return
	}
	if !c.isUserAuthorizedForChat(req.ChatID) {
		if c.hub != nil {
			c.hub.UnsubscribeChat(c, req.ChatID)
		}
		c.sendError("forbidden", "无权访问该会话")
		return
	}
	if c.hub == nil {
		return
	}

	userName := ""
	if req.Action == "start" && c.hub != nil && c.hub.db != nil {
		var row struct {
			Nickname string `gorm:"column:nickname"`
		}
		if err := c.hub.db.Table("users").
			Select("nickname").
			Where("uuid = ?", c.UserID).
			Take(&row).Error; err == nil {
			userName = row.Nickname
		}
	}

	// ========== 改动：typing 广播改用集群模式，跨节点通知会话所有成员 ==========
	// 改造前：c.hub.SendToChat(req.ChatID, ..., c.ID)  仅本节点
	// 改造后：BroadcastToGroupCluster 自动跨节点路由
	c.hub.BroadcastToGroupCluster(req.ChatID, map[string]interface{}{
		"type":      "typing",
		"chat_id":   req.ChatID,
		"user_id":   c.UserID,
		"user_name": userName,
		"action":    req.Action,
	})
	// ========== 改动结束 ==========
}

// 已读回执请求
type readRequest struct {
	ChatID string `json:"chat_id"`
	MsgSeq uint64 `json:"msg_seq"`
}

// handleReadReceipt 处理已读回执
func (c *Client) handleReadReceipt(data json.RawMessage) {
	var req readRequest
	if err := json.Unmarshal(data, &req); err != nil {
		return
	}
	req.ChatID = strings.TrimSpace(req.ChatID)
	if req.ChatID == "" {
		return
	}
	if !c.isChatSubscribed(req.ChatID) {
		c.sendError("forbidden", "未订阅该会话")
		return
	}
	if !c.isUserAuthorizedForChat(req.ChatID) {
		if c.hub != nil {
			c.hub.UnsubscribeChat(c, req.ChatID)
		}
		c.sendError("forbidden", "无权访问该会话")
		return
	}
	if c.hub == nil {
		return
	}

	// ========== 改动：已读回执广播改用集群模式，跨节点通知会话所有成员 ==========
	// 改造前：c.hub.SendToChat(req.ChatID, ..., c.ID)  仅本节点
	// 改造后：BroadcastToGroupCluster 自动跨节点路由
	c.hub.BroadcastToGroupCluster(req.ChatID, map[string]interface{}{
		"type":    "read",
		"chat_id": req.ChatID,
		"user_id": c.UserID,
		"msg_seq": req.MsgSeq,
	})
	// ========== 改动结束 ==========
}

// handleOnlineStatus 处理在线状态查询
func (c *Client) handleOnlineStatus(data json.RawMessage) {
	var req struct {
		UserIDs []string `json:"user_ids"`
	}
	if err := json.Unmarshal(data, &req); err != nil {
		return
	}

	status := make(map[string]bool)
	for _, uid := range req.UserIDs {
		visible, err := privacy.CanViewerSeeOnlineStatusByUUID(c.hub.db, c.UserID, uid)
		if err != nil || !visible {
			status[uid] = false
			continue
		}
		// ========== 改动：在线状态查询改用集群模式，跨所有节点判断 ==========
		// 改造前：c.hub.IsUserOnline(uid)  仅本节点
		// 改造后：IsUserOnlineCluster 查 Redis，感知全集群在线状态
		status[uid] = c.hub.IsUserOnlineCluster(uid)
		// ========== 改动结束 ==========
	}

	c.sendSuccess("online_status", status)
}
