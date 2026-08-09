// 文件用途：实现后端 HTTP 接口的请求处理和统一响应。
// 核心逻辑：绑定参数，校验身份与权限，调用业务服务并持久化关键状态。

package handlers

import (
	"context"
	"errors"
	"github.com/gin-gonic/gin"
	"go.mongodb.org/mongo-driver/bson"
	"go.mongodb.org/mongo-driver/mongo"
	"go.mongodb.org/mongo-driver/mongo/options"
	"gorm.io/gorm"
	"runtime"
	"sort"
	"strconv"
	"strings"
	"sync"
	"time"
	"genericim/internal/cache"
	"genericim/internal/config"
	"genericim/internal/models"
	"genericim/internal/mq"
	"genericim/internal/services"
	"genericim/internal/ws"
	"genericim/pkg/response"
)

var serverStartedAt = time.Now()

const (
	defaultHealthTrendHours   = 24
	maxHealthTrendHours       = 168
	healthSnapshotRetention   = 7 * 24 * time.Hour
	defaultSnapshotSampleSpan = 5 * time.Minute
	freshHealthSnapshotMaxAge = 2 * time.Minute
)

type StatsHandler struct {
	db           *gorm.DB
	mongoDB      *mongo.Database
	cache        *cache.Cache
	hub          *ws.Hub
	snapshotOnce sync.Once
}

func NewStatsHandler(db *gorm.DB, mongoDB *mongo.Database, cache *cache.Cache, hub ...*ws.Hub) *StatsHandler {
	h := &StatsHandler{db: db, mongoDB: mongoDB, cache: cache}
	if len(hub) > 0 {

		h.hub = hub[0]
	}
	return h
} // GetDashboardStats 获取仪表盘统计数据
func (h *StatsHandler) GetDashboardStats(c *gin.Context) {
	var totalUsers int64
	var onlineUsers int64
	var newUsersToday int64
	var totalGroups int64
	var totalChannels int64
	// 在线用户口径是最近 5 分钟有活跃设备的去重用户数，不等同于当前 WebSocket 连接数。
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
		Where("created_at >= CURDATE() AND created_at < DATE_ADD(CURDATE(), INTERVAL 1 DAY)").
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

		"total_users": totalUsers,

		"online_users": onlineUsers,

		"new_users_today": newUsersToday,

		"total_groups": totalGroups,

		"total_channels": totalChannels,
	})
} // GetUserStats 获取用户统计
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
		Date string `json:"date"`

		Count int64 `json:"count"`
	}
	dailyStats := make([]DailyStat, 0)
	now := time.Now()
	start := time.Date(now.Year(), now.Month(), now.Day(), 0, 0, 0, 0, now.Location()).AddDate(0, 0, -(days - 1))
	end := time.Date(now.Year(), now.Month(), now.Day(), 0, 0, 0, 0, now.Location()).AddDate(0, 0, 1)
	if err := h.db.Model(&models.User{}).
		Select("DATE_FORMAT(created_at, '%Y-%m-%d') as date, COUNT(*) as count").
		Where("created_at >= ? AND created_at < ?", start, end).
		Group("DATE_FORMAT(created_at, '%Y-%m-%d')").
		Order("date").
		Scan(&dailyStats).Error; err != nil {

		response.Error(c, 500, "获取统计失败")

		return
	}
	// 用户状态分布
	type StatusStat struct {
		Status int8 `json:"status"`

		Count int64 `json:"count"`
	}
	statusStats := make([]StatusStat, 0)
	if err := h.db.Model(&models.User{}).
		Select("status, COUNT(*) as count").
		Group("status").
		Scan(&statusStats).Error; err != nil {

		response.Error(c, 500, "获取统计失败")

		return
	}
	response.Success(c, gin.H{

		"daily_new_users": dailyStats,

		"status_stats": statusStats,
	})
} // GetMessageStats 获取消息统计（从 MongoDB 获取真实数据）
func (h *StatsHandler) GetMessageStats(c *gin.Context) {
	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()
	totalMessages := int64(0)
	messagesToday := int64(0)
	typeCountMap := make(map[string]int64)
	// 消息类型统计
	messageTypes := []gin.H{

		{"type": "text", "count": 0, "percent": 0},

		{"type": "image", "count": 0, "percent": 0},

		{"type": "voice", "count": 0, "percent": 0},

		{"type": "video", "count": 0, "percent": 0},

		{"type": "file", "count": 0, "percent": 0},

		{"type": "other", "count": 0, "percent": 0},
	}
	if h.mongoDB != nil {

		now := time.Now()
		startOfToday := startOfLocalDay(now)

		// 总量覆盖最近 12 个月分表和兼容用 messages 表；单个集合失败时保留其他集合的可用统计。

		for _, collectionName := range h.messageStatsCollections(ctx, now, 12) {

			collection := h.mongoDB.Collection(collectionName)
			count, err := collection.CountDocuments(ctx, bson.M{})

			if err == nil {

				totalMessages += count

			}
			todayCount, err := collection.CountDocuments(ctx, bson.M{

				"created_at": bson.M{"$gte": startOfToday},
			})

			if err == nil {

				messagesToday += todayCount

			}

			for key, value := range aggregateMessageTypes(ctx, collection) {

				typeCountMap[key] += value

			}

		}
	}
	for i, mt := range messageTypes {

		typeName := mt["type"].(string)

		if count, ok := typeCountMap[typeName]; ok && totalMessages > 0 {

			percent := float64(count) * 100 / float64(totalMessages)

			messageTypes[i] = gin.H{

				"type": typeName,

				"count": count,

				"percent": int(percent),
			}

		}
	}
	response.Success(c, gin.H{

		"total_messages": totalMessages,

		"messages_today": messagesToday,

		"peak_messages": 0,

		"peak_time": "-",

		"message_types": messageTypes,
	})
}
func startOfLocalDay(t time.Time) time.Time {
	return time.Date(t.Year(), t.Month(), t.Day(), 0, 0, 0, 0, t.Location())
}
func (h *StatsHandler) messageStatsCollections(ctx context.Context, now time.Time, months int) []string {
	if h == nil || h.mongoDB == nil {

		return []string{}
	}
	if months <= 0 {

		months = 12
	}
	want := make(map[string]struct{}, months+1)
	// 只统计约定时间窗内的月分表，同时纳入迁移前的固定集合。
	for i := 0; i < months; i++ {

		want[models.GetMessageCollection("", now.AddDate(0, -i, 0))] = struct{}{}
	}
	want["messages"] = struct{}{}
	names, err := h.mongoDB.ListCollectionNames(ctx, bson.M{

		"name": bson.M{"$in": mapKeys(want)},
	})
	if err != nil {

		names = []string{}
	}
	if len(names) == 0 {

		names = []string{"messages"}
	}
	seen := make(map[string]struct{}, len(names))
	result := make([]string, 0, len(names))
	for _, name := range names {

		if _, ok := seen[name]; ok {

			continue

		}

		seen[name] = struct{}{}
		result = append(result, name)
	}
	sort.Sort(sort.Reverse(sort.StringSlice(result)))
	return result
}
func mapKeys(values map[string]struct{}) []string {
	keys := make([]string, 0, len(values))
	for key := range values {

		keys = append(keys, key)
	}
	sort.Strings(keys)
	return keys
}
func aggregateMessageTypes(ctx context.Context, collection *mongo.Collection) map[string]int64 {
	counts := make(map[string]int64)
	if collection == nil {

		return counts
	}
	pipeline := []bson.M{

		{"$group": bson.M{

			"_id": "$type",

			"count": bson.M{"$sum": 1},
		}},
	}
	cursor, err := collection.Aggregate(ctx, pipeline, options.Aggregate().SetAllowDiskUse(true))
	if err != nil {

		return counts
	}
	defer cursor.Close(ctx)
	for cursor.Next(ctx) {
		var result struct {
			ID interface{} `bson:"_id"`

			Count int64 `bson:"count"`
		}

		if cursor.Decode(&result) != nil {

			continue

		}

		counts[messageStatsTypeName(result.ID)] += result.Count
	}
	return counts
}
func messageStatsTypeName(raw interface{}) string {
	switch v := raw.(type) {
	case int:

		return messageStatsTypeNameFromInt(v)
	case int32:

		return messageStatsTypeNameFromInt(int(v))
	case int64:

		return messageStatsTypeNameFromInt(int(v))
	case float64:

		return messageStatsTypeNameFromInt(int(v))
	case string:

		switch strings.ToLower(strings.TrimSpace(v)) {

		case "1", "text":

			return "text"

		case "2", "image":

			return "image"

		case "3", "video":

			return "video"

		case "4", "voice", "audio":

			return "voice"

		case "5", "file":

			return "file"

		default:

			return "other"

		}
	default:

		return "other"
	}
}
func messageStatsTypeNameFromInt(value int) string {
	switch value {
	case models.MsgTypeText:

		return "text"
	case models.MsgTypeImage:

		return "image"
	case models.MsgTypeVideo:

		return "video"
	case models.MsgTypeVoice:

		return "voice"
	case models.MsgTypeFile:

		return "file"
	default:

		return "other"
	}
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
func statusSeverity(status string) int {
	switch status {
	case "error":

		return 2
	case "warning":

		return 1
	default:

		return 0
	}
}
func worseStatus(a, b string) string {
	if statusSeverity(b) > statusSeverity(a) {

		return b
	}
	return a
}
func dependencyHealthPayload(name string, err error, extra gin.H) gin.H {
	status := runtimeStatusName(err)
	payload := gin.H{

		"name": name,

		"status": status,

		"error": runtimeErrorMessage(err),
	}
	for k, v := range extra {

		payload[k] = v
	}
	return payload
}
func (h *StatsHandler) storageHealthPayload() gin.H {
	var yamlCfg config.StorageConfig
	if config.GlobalConfig != nil {

		yamlCfg = config.GlobalConfig.Storage
	}
	cfg := services.LoadStorageForRuntime(h.db, yamlCfg)
	err := services.ValidateStorageConfig(cfg)
	provider := services.NormalizeStorageProvider(cfg.Provider)
	publicBaseURL := strings.TrimRight(strings.TrimSpace(cfg.Local.BaseURL), "/")
	bucket := ""
	endpoint := ""
	switch provider {
	case services.StorageProviderAliyun:

		endpoint = strings.TrimSpace(cfg.Aliyun.Endpoint)
		bucket = strings.TrimSpace(cfg.Aliyun.Bucket)
		publicBaseURL = strings.TrimRight(strings.TrimSpace(cfg.Aliyun.PublicBaseURL), "/")
	case services.StorageProviderQiniu:

		endpoint = strings.TrimRight(strings.TrimSpace(cfg.Qiniu.UploadURL), "/")
		bucket = strings.TrimSpace(cfg.Qiniu.Bucket)
		publicBaseURL = strings.TrimRight(strings.TrimSpace(cfg.Qiniu.PublicBaseURL), "/")
	case services.StorageProviderS3:

		endpoint = strings.TrimRight(strings.TrimSpace(cfg.S3.Endpoint), "/")
		bucket = strings.TrimSpace(cfg.S3.Bucket)
		publicBaseURL = strings.TrimRight(strings.TrimSpace(cfg.S3.PublicBaseURL), "/")
	}
	return gin.H{

		"name": "Storage",

		"status": runtimeStatusName(err),

		"error": runtimeErrorMessage(err),

		"provider": provider,

		"endpoint": endpoint,

		"bucket": bucket,

		"public_base_url": publicBaseURL,
	}
}
func (h *StatsHandler) pushHealthPayload(since time.Time) gin.H {
	var total, failed int64
	// 推送健康度仅基于 since 之后的投递日志；没有样本时成功率保持 0，而非推断为 100%。
	if h.db != nil {

		_ = h.db.Model(&models.PushDeliveryLog{}).
			Where("occurred_at >= ?", since).
			Count(&total).Error

		_ = h.db.Model(&models.PushDeliveryLog{}).
			Where("occurred_at >= ? AND success = ?", since, false).
			Count(&failed).Error
	}
	status := "ok"
	if total > 0 {

		rate := float64(failed) / float64(total)

		if rate >= 0.5 {

			status = "error"

		} else if rate > 0 {

			status = "warning"

		}
	}
	return gin.H{

		"name": "Push",

		"status": status,

		"total": total,

		"failed": failed,

		"success_rate": func() float64 {

			if total == 0 {

				return 0

			}

			return float64(total-failed) * 100 / float64(total)

		}(),
	}
}
func (h *StatsHandler) uploadHealthPayload(since time.Time) gin.H {
	var total, failed int64
	recentFailureList := make([]gin.H, 0)
	if h.db != nil {

		_ = h.db.Model(&models.UploadLog{}).
			Where("created_at >= ?", since).
			Count(&total).Error

		_ = h.db.Model(&models.UploadLog{}).
			Where("created_at >= ? AND success = ?", since, false).
			Count(&failed).Error
		var recentFailures []models.UploadLog

		_ = h.db.Where("created_at >= ? AND success = ?", since, false).
			Order("created_at DESC, id DESC").
			Limit(5).
			Find(&recentFailures).Error

		for _, item := range recentFailures {

			recentFailureList = append(recentFailureList, gin.H{

				"id": item.ID,

				"actor_type": item.ActorType,

				"user_id": item.UserID,

				"admin_id": item.AdminID,

				"media_type": item.MediaType,

				"provider": item.Provider,

				"error": item.Error,

				"created_at": formatAdminTime(item.CreatedAt),
			})

		}
	}
	status := "ok"
	if total > 0 {

		rate := float64(failed) / float64(total)

		if rate >= 0.5 {

			status = "error"

		} else if failed > 0 {

			status = "warning"

		}
	}
	successRate := 0.0
	failureRate := 0.0
	if total > 0 {

		successRate = float64(total-failed) * 100 / float64(total)
		failureRate = float64(failed) * 100 / float64(total)
	}
	return gin.H{

		"name": "Upload",

		"status": status,

		"total": total,

		"failed": failed,

		"success_rate": successRate,

		"failure_rate": failureRate,

		"recent_failures": recentFailureList,

		"error": "",
	}
}
func healthPayloadStatus(payload gin.H) string {
	if status, ok := payload["status"].(string); ok && status != "" {

		return status
	}
	return "ok"
}
func healthPayloadInt64(payload gin.H, key string) int64 {
	value, ok := payload[key]
	if !ok || value == nil {

		return 0
	}
	switch v := value.(type) {
	case int:

		return int64(v)
	case int64:

		return v
	case int32:

		return int64(v)
	case uint:

		return int64(v)
	case uint64:

		return int64(v)
	case uint32:

		return int64(v)
	case float64:

		return int64(v)
	case float32:

		return int64(v)
	default:

		return 0
	}
}
func buildHealthMetricSnapshot(
	now time.Time,
	overall string,
	mysqlErr error,
	mongoErr error,
	redisErr error,
	storage gin.H,
	upload gin.H,
	wsPayload gin.H,
	push gin.H,
	queuePayload gin.H,
	mem runtime.MemStats) models.HealthMetricSnapshot {
	return models.HealthMetricSnapshot{

		Status: overall,

		MysqlStatus: runtimeStatusName(mysqlErr),

		MongoStatus: runtimeStatusName(mongoErr),

		RedisStatus: runtimeStatusName(redisErr),

		StorageStatus: healthPayloadStatus(storage),

		UploadStatus: healthPayloadStatus(upload),

		WebsocketStatus: healthPayloadStatus(wsPayload),

		PushStatus: healthPayloadStatus(push),

		QueueStatus: healthPayloadStatus(queuePayload),

		QueueMessageSend: healthPayloadInt64(queuePayload, "message_send"),

		QueueMessageSync: healthPayloadInt64(queuePayload, "message_sync"),

		QueuePushNotify: healthPayloadInt64(queuePayload, "push_notify"),

		QueueDelayed: healthPayloadInt64(queuePayload, "delayed"),

		QueueDead: healthPayloadInt64(queuePayload, "dead"),

		UploadTotal: healthPayloadInt64(upload, "total"),

		UploadFailed: healthPayloadInt64(upload, "failed"),

		PushTotal: healthPayloadInt64(push, "total"),

		PushFailed: healthPayloadInt64(push, "failed"),

		WSOnlineConnections: healthPayloadInt64(wsPayload, "online_connections"),

		WSOnlineUsers: healthPayloadInt64(wsPayload, "online_users"),

		WSTotalDisconnects: healthPayloadInt64(wsPayload, "total_disconnects"),

		WSDroppedMessages: healthPayloadInt64(wsPayload, "dropped_messages"),

		Goroutines: int64(runtime.NumGoroutine()),

		MemoryAllocMB: int64(mb(mem.Alloc)),

		CreatedAt: now,
	}
}
func (h *StatsHandler) saveHealthMetricSnapshot(snapshot models.HealthMetricSnapshot) {
	if h == nil || h.db == nil {

		return
	}
	_ = h.db.Create(&snapshot).Error
}
func (h *StatsHandler) hasFreshHealthMetricSnapshot(now time.Time, maxAge time.Duration) bool {
	if h == nil || h.db == nil {

		return false
	}
	var latest models.HealthMetricSnapshot
	err := h.db.Select("created_at").
		Order("created_at DESC, id DESC").
		First(&latest).Error
	if err != nil || latest.CreatedAt.IsZero() {

		return false
	}
	return now.Sub(latest.CreatedAt) < maxAge
}
func (h *StatsHandler) saveHealthMetricSnapshotIfStale(snapshot models.HealthMetricSnapshot, maxAge time.Duration) {
	if h == nil || h.db == nil {

		return
	}
	if h.hasFreshHealthMetricSnapshot(snapshot.CreatedAt, maxAge) {

		return
	}
	h.saveHealthMetricSnapshot(snapshot)
}
func (h *StatsHandler) cleanupOldHealthMetricSnapshots(now time.Time) {
	if h == nil || h.db == nil {

		return
	}
	_ = h.db.Where("created_at < ?", now.Add(-healthSnapshotRetention)).
		Delete(&models.HealthMetricSnapshot{}).Error
}
func (h *StatsHandler) collectHealthMetricSnapshot(ctx context.Context, now time.Time) models.HealthMetricSnapshot {
	checkSince := now.Add(-15 * time.Minute)
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
	queueMessageSend := h.redisListLen(ctx, mq.QueueMessageSend) + h.redisListLen(ctx, mq.QueueMessageSend+":high")
	queueMessageSync := h.redisListLen(ctx, mq.QueueMessageSync) + h.redisListLen(ctx, mq.QueueMessageSync+":high")
	queuePushNotify := h.redisListLen(ctx, mq.QueuePushNotify) + h.redisListLen(ctx, mq.QueuePushNotify+":high")
	queueDelayed := h.redisSortedSetLen(ctx, mq.QueueDelayed)
	queueDead := h.redisListLen(ctx, mq.QueueDead)
	queueStatus := "ok"
	if queueDead > 0 {

		queueStatus = "warning"
	}
	var mem runtime.MemStats
	runtime.ReadMemStats(&mem)
	storage := h.storageHealthPayload()
	push := h.pushHealthPayload(checkSince)
	upload := h.uploadHealthPayload(checkSince)
	wsPayload := gin.H{

		"name": "WebSocket",

		"status": "warning",

		"error": "WebSocket Hub 未初始化",
	}
	if h.hub != nil {

		wsStats := h.hub.GetStats()
		wsPayload = gin.H{

			"name": "WebSocket",

			"status": "ok",

			"online_connections": wsStats["online_connections"],

			"online_users": wsStats["online_users"],

			"active_chats": wsStats["active_chats"],

			"total_disconnects": wsStats["total_disconnects"],

			"dropped_messages": wsStats["dropped_messages"],

			"last_connected_at": wsStats["last_connected_at"],

			"last_disconnected_at": wsStats["last_disconnected_at"],

			"register_queue_len": wsStats["register_queue_len"],

			"unregister_queue_len": wsStats["unregister_queue_len"],

			"broadcast_queue_len": wsStats["broadcast_queue_len"],

			"error": "",
		}
	}
	queuePayload := gin.H{

		"name": "Queue",

		"status": queueStatus,

		"message_send": queueMessageSend,

		"message_sync": queueMessageSync,

		"push_notify": queuePushNotify,

		"delayed": queueDelayed,

		"dead": queueDead,

		"error": "",
	}
	components := []gin.H{

		dependencyHealthPayload("MySQL", mysqlErr, gin.H{}),

		dependencyHealthPayload("MongoDB", mongoErr, gin.H{}),

		dependencyHealthPayload("Redis", redisErr, gin.H{}),

		storage,

		upload,

		wsPayload,

		push,

		queuePayload,
	}
	overall := "ok"
	for _, item := range components {

		if status, _ := item["status"].(string); status != "" {

			overall = worseStatus(overall, status)

		}
	}
	return buildHealthMetricSnapshot(now, overall, mysqlErr, mongoErr, redisErr, storage, upload, wsPayload, push, queuePayload, mem)
}
func (h *StatsHandler) captureAndSaveHealthMetricSnapshot() {
	ctx, cancel := context.WithTimeout(context.Background(), 2*time.Second)
	defer cancel()
	now := time.Now()
	h.saveHealthMetricSnapshot(h.collectHealthMetricSnapshot(ctx, now))
	h.cleanupOldHealthMetricSnapshots(now)
}
func (h *StatsHandler) ensureFreshHealthMetricSnapshot(now time.Time) {
	if h == nil || h.db == nil || h.hasFreshHealthMetricSnapshot(now, freshHealthSnapshotMaxAge) {

		return
	}
	h.captureAndSaveHealthMetricSnapshot()
}
func (h *StatsHandler) StartHealthSnapshotSampler() {
	if h == nil || h.db == nil {

		return
	}
	h.snapshotOnce.Do(func() {

		go func() {

			h.captureAndSaveHealthMetricSnapshot()
			ticker := time.NewTicker(defaultSnapshotSampleSpan)

			defer ticker.Stop()

			for range ticker.C {

				h.captureAndSaveHealthMetricSnapshot()

			}

		}()
	})
} // GetHealthDetail returns the admin health dashboard payload.
func (h *StatsHandler) GetHealthDetail(c *gin.Context) {
	now := time.Now()
	uptime := now.Sub(serverStartedAt)
	checkSince := now.Add(-15 * time.Minute)
	ctx, cancel := context.WithTimeout(c.Request.Context(), 2*time.Second)
	defer cancel()
	var mysqlErr error
	mysqlExtra := gin.H{}
	if h.db == nil {

		mysqlErr = gorm.ErrInvalidDB
	} else if sqlDB, err := h.db.DB(); err != nil {

		mysqlErr = err
	} else {

		mysqlErr = sqlDB.PingContext(ctx)
		stats := sqlDB.Stats()

		mysqlExtra["open_connections"] = stats.OpenConnections

		mysqlExtra["in_use"] = stats.InUse

		mysqlExtra["idle"] = stats.Idle

		mysqlExtra["max_open_connections"] = stats.MaxOpenConnections
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
	queueMessageSend := h.redisListLen(ctx, mq.QueueMessageSend) + h.redisListLen(ctx, mq.QueueMessageSend+":high")
	queueMessageSync := h.redisListLen(ctx, mq.QueueMessageSync) + h.redisListLen(ctx, mq.QueueMessageSync+":high")
	queuePushNotify := h.redisListLen(ctx, mq.QueuePushNotify) + h.redisListLen(ctx, mq.QueuePushNotify+":high")
	queueDelayed := h.redisSortedSetLen(ctx, mq.QueueDelayed)
	queueDead := h.redisListLen(ctx, mq.QueueDead)
	queueStatus := "ok"
	if queueDead > 0 {

		queueStatus = "warning"
	}
	var mem runtime.MemStats
	runtime.ReadMemStats(&mem)
	storage := h.storageHealthPayload()
	push := h.pushHealthPayload(checkSince)
	upload := h.uploadHealthPayload(checkSince)
	wsPayload := gin.H{

		"name": "WebSocket",

		"status": "warning",

		"error": "WebSocket Hub 未初始化",
	}
	if h.hub != nil {

		wsStats := h.hub.GetStats()
		wsPayload = gin.H{

			"name": "WebSocket",

			"status": "ok",

			"online_connections": wsStats["online_connections"],

			"online_users": wsStats["online_users"],

			"active_chats": wsStats["active_chats"],

			"total_connections": wsStats["total_connections"],

			"total_disconnects": wsStats["total_disconnects"],

			"dropped_messages": wsStats["dropped_messages"],

			"last_connected_at": wsStats["last_connected_at"],

			"last_disconnected_at": wsStats["last_disconnected_at"],

			"register_queue_len": wsStats["register_queue_len"],

			"unregister_queue_len": wsStats["unregister_queue_len"],

			"broadcast_queue_len": wsStats["broadcast_queue_len"],

			"error": "",
		}
	}
	queuePayload := gin.H{

		"name": "Queue",

		"status": queueStatus,

		"message_send": queueMessageSend,

		"message_sync": queueMessageSync,

		"push_notify": queuePushNotify,

		"delayed": queueDelayed,

		"dead": queueDead,

		"error": "",
	}
	if queueDead > 0 {

		queuePayload["error"] = "存在死信队列，请检查消息/推送消费日志"
	}
	components := []gin.H{

		dependencyHealthPayload("MySQL", mysqlErr, mysqlExtra),

		dependencyHealthPayload("MongoDB", mongoErr, gin.H{}),

		dependencyHealthPayload("Redis", redisErr, gin.H{}),

		storage,

		upload,

		wsPayload,

		push,

		queuePayload,
	}
	overall := "ok"
	for _, item := range components {

		if status, _ := item["status"].(string); status != "" {

			overall = worseStatus(overall, status)

		}
	}
	h.saveHealthMetricSnapshotIfStale(

		buildHealthMetricSnapshot(now, overall, mysqlErr, mongoErr, redisErr, storage, upload, wsPayload, push, queuePayload, mem),

		freshHealthSnapshotMaxAge,
	)
	h.cleanupOldHealthMetricSnapshots(now)
	response.Success(c, gin.H{

		"status": overall,

		"server_time": now.Format("2006-01-02 15:04:05"),

		"started_at": serverStartedAt.Format("2006-01-02 15:04:05"),

		"uptime_text": uptime.Truncate(time.Second).String(),

		"runtime": gin.H{

			"go_version": runtime.Version(),

			"os": runtime.GOOS,

			"arch": runtime.GOARCH,

			"goroutines": runtime.NumGoroutine(),

			"cpu_num": runtime.NumCPU(),

			"memory_alloc_mb": mb(mem.Alloc),

			"memory_sys_mb": mb(mem.Sys),

			"heap_inuse_mb": mb(mem.HeapInuse),

			"gc_count": mem.NumGC,
		},

		"components": components,

		"summary": gin.H{

			"mysql_status": runtimeStatusName(mysqlErr),

			"mongo_status": runtimeStatusName(mongoErr),

			"redis_status": runtimeStatusName(redisErr),

			"storage": storage,

			"upload": upload,

			"websocket": wsPayload,

			"push": push,

			"queue": queuePayload,

			"check_window": "15m",
		},
	})
} // GetHealthTrend returns compact historical health metrics for admin charts.
func (h *StatsHandler) GetHealthTrend(c *gin.Context) {
	if h == nil || h.db == nil {

		response.Error(c, 500, "数据库未初始化")

		return
	}
	hours := defaultHealthTrendHours
	if raw := strings.TrimSpace(c.Query("hours")); raw != "" {

		if parsed, err := strconv.Atoi(raw); err == nil {

			hours = parsed

		}
	}
	if hours < 1 {

		hours = 1
	}
	if hours > maxHealthTrendHours {

		hours = maxHealthTrendHours
	}
	now := time.Now()
	h.ensureFreshHealthMetricSnapshot(now)
	var list []models.HealthMetricSnapshot
	if err := h.db.Where("created_at >= ?", now.Add(-time.Duration(hours)*time.Hour)).
		Order("created_at ASC, id ASC").
		Find(&list).Error; err != nil {

		response.Error(c, 500, "读取健康趋势失败")

		return
	}
	response.Success(c, gin.H{

		"hours": hours,

		"sample_interval_minutes": int(defaultSnapshotSampleSpan.Minutes()),

		"list": list,
	})
} // GetRuntimeStatus returns backend process and dependency health.
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

		"server_time": now.Format("2006-01-02 15:04:05"),

		"started_at": serverStartedAt.Format("2006-01-02 15:04:05"),

		"uptime_seconds": int64(uptime.Seconds()),

		"uptime_text": uptime.Truncate(time.Second).String(),

		"go_version": runtime.Version(),

		"os": runtime.GOOS,

		"arch": runtime.GOARCH,

		"goroutines": runtime.NumGoroutine(),

		"cpu_num": runtime.NumCPU(),

		"memory_alloc_mb": mb(mem.Alloc),

		"memory_sys_mb": mb(mem.Sys),

		"heap_inuse_mb": mb(mem.HeapInuse),

		"gc_count": mem.NumGC,

		"mysql_status": runtimeStatusName(mysqlErr),

		"mysql_error": runtimeErrorMessage(mysqlErr),

		"mongo_status": runtimeStatusName(mongoErr),

		"mongo_error": runtimeErrorMessage(mongoErr),

		"redis_status": runtimeStatusName(redisErr),

		"redis_error": runtimeErrorMessage(redisErr),

		"queue_message_send": queueMessageSend,

		"queue_message_sync": queueMessageSync,

		"queue_push_notify": queuePushNotify,

		"queue_delayed": queueDelayed,

		"queue_dead": queueDead,
	})
}
