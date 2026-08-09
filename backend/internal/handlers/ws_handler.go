// 文件用途：实现后端 HTTP 接口的请求处理和统一响应。
// 核心逻辑：绑定参数，校验身份与权限，调用业务服务并持久化关键状态。

package handlers

import (
	"github.com/gin-gonic/gin"
	"github.com/gorilla/websocket"
	"gorm.io/gorm"
	"log"
	"net/http"
	"net/url"
	"strings"
	"time"
	"genericim/internal/config"
	"genericim/internal/middleware"
	"genericim/internal/models"
	"genericim/internal/ws"
)

// HandleWebSocket WebSocket连接处理
func HandleWebSocket(hub *ws.Hub, cfg config.WebSocketConfig, db *gorm.DB) gin.HandlerFunc {
	upgrader := websocket.Upgrader{
		ReadBufferSize:  cfg.ReadBufferSize,
		WriteBufferSize: cfg.WriteBufferSize,
		CheckOrigin: func(r *http.Request) bool {
			return isWebSocketOriginAllowed(r.Header.Get("Origin"), cfg.AllowedOrigins)
		},
	}
	return func(c *gin.Context) {
		// 获取用户信息
		userID := middleware.GetUserID(c)
		deviceID := middleware.GetDeviceID(c)
		deviceType := c.Query("device_type")
		if userID == "" {
			c.JSON(http.StatusUnauthorized, gin.H{"error": "unauthorized"})
			return
		}

		// 升级HTTP连接为WebSocket
		conn, err := upgrader.Upgrade(c.Writer, c.Request, nil)
		if err != nil {
			log.Printf("WebSocket upgrade error: %v", err)
			return
		}

		// 获取用户数据库ID
		var user models.User
		if err := db.Where("uuid = ?", userID).First(&user).Error; err == nil {
			// 更新或创建设备记录
			now := time.Now()
			clientIP := c.ClientIP()

			var device models.UserDevice
			result := db.Where("user_id = ? AND device_id = ?", user.ID, deviceID).First(&device)
			if result.Error == gorm.ErrRecordNotFound {
				// 创建新设备记录
				device = models.UserDevice{
					UserID:     user.ID,
					DeviceID:   deviceID,
					DeviceType: deviceType,
					DeviceName: deviceType,
					IP:         clientIP,
					LastActive: now,
					CreatedAt:  now,
				}
				db.Create(&device)
				log.Printf("[WS] New device registered: user=%s, device=%s, ip=%s", userID, deviceID, clientIP)
			} else {
				// 更新设备活跃时间和IP
				db.Model(&device).Updates(map[string]interface{}{
					"last_active": now,
					"ip":          clientIP,
					"device_type": deviceType,
				})
				log.Printf("[WS] Device updated: user=%s, device=%s, ip=%s", userID, deviceID, clientIP)
			}

			// 同时更新用户的 last_seen
			db.Model(&user).Update("last_seen", now)
		}

		// 创建客户端
		client := ws.NewClient(hub, conn, userID, deviceID, deviceType)

		// 注册客户端
		hub.Register(client)

		// 启动读写协程
		client.Start()
	}
}

func isWebSocketOriginAllowed(origin string, allowedOrigins []string) bool {
	origin = strings.TrimSpace(origin)
	if origin == "" {
		return true
	}
	if len(allowedOrigins) == 0 {
		return true
	}

	parsed, err := url.Parse(origin)
	if err != nil || parsed.Scheme == "" || parsed.Host == "" {
		return false
	}
	normalizedOrigin := strings.ToLower(parsed.Scheme + "://" + parsed.Host)
	for _, allowed := range allowedOrigins {
		allowed = strings.TrimSpace(allowed)
		if allowed == "" {
			continue
		}
		if allowed == "*" {
			return true
		}
		allowedURL, err := url.Parse(allowed)
		if err != nil || allowedURL.Scheme == "" || allowedURL.Host == "" {
			continue
		}
		if normalizedOrigin == strings.ToLower(allowedURL.Scheme+"://"+allowedURL.Host) {
			return true
		}
	}
	return false
}
