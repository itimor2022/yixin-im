package handlers

import (
	"context"
	"errors"
	"runtime"
	"time"

	"gaoranim/internal/cache"
	"gaoranim/internal/models"
	"gaoranim/internal/mq"
	"gaoranim/pkg/response"

	"github.com/gin-gonic/gin"
	"go.mongodb.org/mongo-driver/bson"
	"go.mongodb.org/mongo-driver/mongo"
	"gorm.io/gorm"
)

var serverStartedAt = time.Now()

type StatsHandler struct {
	db      *gorm.DB
	mongoDB *mongo.Database
	cache   *cache.Cache
}

func NewStatsHandler(db *gorm.DB, mongoDB *mongo.Database, cache *cache.Cache) *StatsHandler {
	return &StatsHandler{db: db, mongoDB: mongoDB, cache: cache}
}

// GetDashboardStats 获取仪表盘统计数据
func (h *StatsHandler) GetDashboardStats(c *gin.Context) {
	var totalUsers int64
	var onlineUsers int64
	var newUsersToday int64
	var totalGroups int64
	var totalChannels int64

	if err := h.db.Model(&models.User{}).Count(&totalUsers).Error; err != nil {
		response.Error(c, 500, "获取统计失败")
		return
	}
	if err := h.db.Model(&models.UserDevice{}).
		Where("last_active > ?", time.Now().Add(-5*time.Minute)).
		Distinct("user_id").
		Count(&onlineUsers).Error; err != nil {
		response.Error(c, 500, "获取统计失败")
		return
	}
	if err := h.db.Model(&models.User{}).
		Where("DATE(created_at) = CURDATE()").
		Count(&newUsersToday).Error; err != nil {
		response.Error(c, 500, "获取统计失败")
		return
	}
	if err := h.db.Model(&models.Chat{}).Where("type = ?", 2).Count(&totalGroups).Error; err != nil {
		response.Error(c, 500, "获取统计失败")
		return
	}
	if err := h.db.Model(&models.Chat{}).Where("type = ?", 3).Count(&totalChannels).Error; err != nil {
		response.Error(c, 500, "获取统计失败")
		return
	}

	response.Success(c, gin.H{
		"total_users":     totalUsers,
		"online_users":    onlineUsers,
		"new_users_today": newUsersToday,
		"total_groups":    totalGroups,
		"total_channels":  totalChannels,
	})
}

// GetUserStats 获取用户统计
func (h *StatsHandler) GetUserStats(c *gin.Context) {
	// 从查询参数获取天数，默认7天
	daysStr := c.DefaultQuery("days", "7")
	days := 7
	switch daysStr {
	case "30":
		days = 30
	case "90":
		days = 90
	case "7":
		days = 7
	default:
		days = 7
	}

	// 按天统计新增用户
	type DailyStat struct {
		Date  string `json:"date"`
		Count int64  `json:"count"`
	}

	var dailyStats []DailyStat
	now := time.Now()
	start := time.Date(now.Year(), now.Month(), now.Day(), 0, 0, 0, 0, now.Location()).AddDate(0, 0, -(days-1))
	end := time.Date(now.Year(), now.Month(), now.Day(), 0, 0, 0, 0, now.Location()).AddDate(0, 0, 1)

	if err := h.db.Model(&models.User{}).
		Select("DATE_FORMAT(created_at, '%Y-%m-%d') as date, COUNT(*) as count").
		Where("created_at >= ? AND created_at < ?", start, end).
		Group("DATE(created_at)").
		Order("date").
		Scan(&dailyStats).Error; err != nil {
		response.Error(c, 500, "获取统计失败")
		return
	}

	// 用户状态分布
	type StatusStat struct {
		Status int8  `json:"status"`
		Count  int64 `json:"count"`
	}

	var statusStats []StatusStat
	if err := h.db.Model(&models.User{}).
		Select("status, COUNT(*) as count").
		Group("status").
		Scan(&statusStats).Error; err != nil {
		response.Error(c, 500, "获取统计失败")
		return
	}

	response.Success(c, gin.H{
		"daily_new_users": dailyStats,
		"status_stats":    statusStats,
	})
}

// GetMessageStats 获取消息统计（从 MongoDB 获取真实数据）
func (h *StatsHandler) GetMessageStats(c *gin.Context) {
	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()

	var totalMessages int64 = 0
	var messagesToday int64 = 0

	// 消息类型统计
	messageTypes := []gin.H{
		{"type": "text", "count": 0, "percent": 0},
		{"type": "image", "count": 0, "percent": 0},
		{"type": "voice", "count": 0, "percent": 0},
		{"type": "video", "count": 0, "percent": 0},
		{"type": "file", "count": 0, "percent": 0},
		{"type": "other", "count": 0, "percent": 0},
	}

	// 如果 MongoDB 可用，获取真实数据
	if h.mongoDB != nil {
		messagesCol := h.mongoDB.Collection("messages")

		// 获取总消息数
		count, err := messagesCol.CountDocuments(ctx, bson.M{})
		if err == nil {
			totalMessages = count
		}

		// 获取今日消息数
		startOfToday := time.Now().Truncate(24 * time.Hour)
		todayCount, err := messagesCol.CountDocuments(ctx, bson.M{
			"created_at": bson.M{"$gte": startOfToday},
		})
		if err == nil {
			messagesToday = todayCount
		}

		// 获取消息类型分布
		if totalMessages > 0 {
			typeCountMap := make(map[string]int64)

			// 聚合查询消息类型
			pipeline := []bson.M{
				{"$group": bson.M{
					"_id":   "$type",
					"count": bson.M{"$sum": 1},
				}},
			}

			cursor, err := messagesCol.Aggregate(ctx, pipeline)
			if err == nil {
				defer cursor.Close(ctx)

				for cursor.Next(ctx) {
					var result struct {
						ID    string `bson:"_id"`
						Count int64  `bson:"count"`
					}
					if cursor.Decode(&result) == nil {
						typeCountMap[result.ID] = result.Count
					}
				}
			}

			// 计算百分比
			for i, mt := range messageTypes {
				typeName := mt["type"].(string)
				if count, ok := typeCountMap[typeName]; ok {
					percent := float64(count) * 100 / float64(totalMessages)
					messageTypes[i] = gin.H{
						"type":    typeName,
						"count":   count,
						"percent": int(percent),
					}
				}
			}
		}
	}

	response.Success(c, gin.H{
		"total_messages": totalMessages,
		"messages_today": messagesToday,
		"peak_messages":  0,
		"peak_time":      "-",
		"message_types":  messageTypes,
	})
}

func runtimeStatusName(err error) string {
	if err != nil {
		return "error"
	}
	return "ok"
}

func runtimeErrorMessage(err error) string {
	if err != nil {
		return err.Error()
	}
	return ""
}

func mb(v uint64) uint64 {
	return v / 1024 / 1024
}

func (h *StatsHandler) redisListLen(ctx context.Context, key string) int64 {
	if h.cache == nil {
		return 0
	}
	n, err := h.cache.ListLen(ctx, key)
	if err != nil {
		return 0
	}
	return n
}

func (h *StatsHandler) redisSortedSetLen(ctx context.Context, key string) int64 {
	if h.cache == nil {
		return 0
	}
	n, err := h.cache.SortedSetLen(ctx, key)
	if err != nil {
		return 0
	}
	return n
}

// GetRuntimeStatus returns backend process and dependency health.
func (h *StatsHandler) GetRuntimeStatus(c *gin.Context) {
	now := time.Now()
	uptime := now.Sub(serverStartedAt)

	ctx, cancel := context.WithTimeout(c.Request.Context(), 2*time.Second)
	defer cancel()

	var mysqlErr error
	if h.db == nil {
		mysqlErr = gorm.ErrInvalidDB
	} else if sqlDB, err := h.db.DB(); err != nil {
		mysqlErr = err
	} else {
		mysqlErr = sqlDB.PingContext(ctx)
	}

	var mongoErr error
	if h.mongoDB == nil {
		mongoErr = errors.New("MongoDB 未配置")
	} else {
		mongoErr = h.mongoDB.Client().Ping(ctx, nil)
	}

	var redisErr error
	if h.cache == nil {
		redisErr = errors.New("Redis 未配置")
	} else {
		redisErr = h.cache.Ping(ctx)
	}

	var mem runtime.MemStats
	runtime.ReadMemStats(&mem)

	queueMessageSend := h.redisListLen(ctx, mq.QueueMessageSend) + h.redisListLen(ctx, mq.QueueMessageSend+":high")
	queueMessageSync := h.redisListLen(ctx, mq.QueueMessageSync) + h.redisListLen(ctx, mq.QueueMessageSync+":high")
	queuePushNotify := h.redisListLen(ctx, mq.QueuePushNotify) + h.redisListLen(ctx, mq.QueuePushNotify+":high")
	queueDelayed := h.redisSortedSetLen(ctx, mq.QueueDelayed)
	queueDead := h.redisListLen(ctx, mq.QueueDead)

	response.Success(c, gin.H{
		"server_time":     now.Format("2006-01-02 15:04:05"),
		"started_at":      serverStartedAt.Format("2006-01-02 15:04:05"),
		"uptime_seconds":  int64(uptime.Seconds()),
		"uptime_text":     uptime.Truncate(time.Second).String(),
		"go_version":      runtime.Version(),
		"os":              runtime.GOOS,
		"arch":            runtime.GOARCH,
		"goroutines":      runtime.NumGoroutine(),
		"cpu_num":         runtime.NumCPU(),
		"memory_alloc_mb": mb(mem.Alloc),
		"memory_sys_mb":   mb(mem.Sys),
		"heap_inuse_mb":   mb(mem.HeapInuse),
		"gc_count":        mem.NumGC,
		"mysql_status":    runtimeStatusName(mysqlErr),
		"mysql_error":     runtimeErrorMessage(mysqlErr),
		"mongo_status":    runtimeStatusName(mongoErr),
		"mongo_error":     runtimeErrorMessage(mongoErr),
		"redis_status":    runtimeStatusName(redisErr),
		"redis_error":     runtimeErrorMessage(redisErr),
		"queue_message_send": queueMessageSend,
		"queue_message_sync": queueMessageSync,
		"queue_push_notify":  queuePushNotify,
		"queue_delayed":      queueDelayed,
		"queue_dead":         queueDead,
	})
}
