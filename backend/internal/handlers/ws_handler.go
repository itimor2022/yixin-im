package handlers

import (
	"log"
	"net/http"
	"time"

	"gaoranim/internal/config"
	"gaoranim/internal/middleware"
	"gaoranim/internal/models"
	"gaoranim/internal/ws"

	"github.com/gin-gonic/gin"
	"github.com/gorilla/websocket"
	"gorm.io/gorm"
)

// HandleWebSocket WebSocket连接处理
func HandleWebSocket(hub *ws.Hub, cfg config.WebSocketConfig, db *gorm.DB, allowedOrigins ...string) gin.HandlerFunc {
	upgrader := websocket.Upgrader{
		ReadBufferSize:  cfg.ReadBufferSize,
		WriteBufferSize: cfg.WriteBufferSize,
		CheckOrigin: func(r *http.Request) bool {
			return true // 安全由 JWT token 认证保证，无需限制 Origin
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
