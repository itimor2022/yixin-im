package handlers

import (
	"context"
	"math"
	"regexp"
	"sort"
	"strconv"
	"time"

	"gaoranim/internal/ws" // 引入集群 ws 依赖定义
	"gaoranim/pkg/response"

	"github.com/gin-gonic/gin"
	"go.mongodb.org/mongo-driver/bson"
	"go.mongodb.org/mongo-driver/bson/primitive"
	"go.mongodb.org/mongo-driver/mongo"
	"go.mongodb.org/mongo-driver/mongo/options"
	"gorm.io/gorm"
)

// AdminHubInstance 全局桥接实例：main.go 加上 handlers.AdminHubInstance = hub 即可完美联动
var AdminHubInstance *ws.Hub

type MessageAdminHandler struct {
	db      *gorm.DB
	mongoDB *mongo.Database
}

// NewMessageAdminHandler 保持原汁原味 2 个参数，main.go 编译 100% 顺畅通过
func NewMessageAdminHandler(db *gorm.DB, mongoDB *mongo.Database) *MessageAdminHandler {
	return &MessageAdminHandler{db: db, mongoDB: mongoDB}
}

// getMessageCollections 获取所有消息集合（包括分片集合），按名称倒序排列
func (h *MessageAdminHandler) getMessageCollections(ctx context.Context) []string {
	collections, err := h.mongoDB.ListCollectionNames(ctx, bson.M{
		"name": bson.M{"$regex": "^messages"},
	})
	if err != nil {
		return []string{"messages"}
	}
	sort.Sort(sort.Reverse(sort.StringSlice(collections)))
	seen := make(map[string]struct{}, len(collections))
	unique := make([]string, 0, len(collections))
	for _, name := range collections {
		if _, ok := seen[name]; !ok {
			seen[name] = struct{}{}
			unique = append(unique, name)
		}
	}
	if len(unique) == 0 {
		return []string{"messages"}
	}
	return unique
}

func (h *MessageAdminHandler) SearchMessages(c *gin.Context) {
	page, _ := strconv.Atoi(c.DefaultQuery("page", "1"))
	pageSize, _ := strconv.Atoi(c.DefaultQuery("page_size", "20"))
	keyword := c.Query("keyword")
	chatID := c.Query("chat_id")
	senderID := c.Query("sender_id")
	msgType := c.Query("type")
	startDate := c.Query("start_date")
	endDate := c.Query("end_date")

	if page < 1 {
		page = 1
	}
	if pageSize < 1 || pageSize > 100 {
		pageSize = 20
	}

	filter := bson.M{}

	if keyword != "" {
		filter["content.text"] = bson.M{"$regex": regexp.QuoteMeta(keyword), "$options": "i"}
	}
	if chatID != "" {
		filter["chat_id"] = chatID
	}
	if senderID != "" {
		filter["sender_id"] = senderID
	}
	if msgType != "" {
		t, err := strconv.Atoi(msgType)
		if err == nil {
			filter["type"] = t
		}
	}
	if startDate != "" {
		if t, err := time.Parse("2006-01-02", startDate); err == nil {
			if _, ok := filter["created_at"]; !ok {
				filter["created_at"] = bson.M{}
			}
			filter["created_at"].(bson.M)["$gte"] = t
		}
	}
	if endDate != "" {
		if t, err := time.Parse("2006-01-02", endDate); err == nil {
			if _, ok := filter["created_at"]; !ok {
				filter["created_at"] = bson.M{}
			}
			filter["created_at"].(bson.M)["$lte"] = t.Add(24 * time.Hour)
		}
	}

	ctx, cancel := context.WithTimeout(context.Background(), 30*time.Second)
	defer cancel()
	collectionNames := h.getMessageCollections(ctx)

	var total int64
	for _, name := range collectionNames {
		cnt, err := h.mongoDB.Collection(name).CountDocuments(ctx, filter)
		if err == nil {
			total += cnt
		}
	}

	skip := int64((page - 1) * pageSize)
	opts := options.Find().
		SetSort(bson.D{{Key: "created_at", Value: -1}}).
		SetLimit(int64(pageSize))

	var messages []bson.M
	var skipped int64

	for _, name := range collectionNames {
		if int64(len(messages)) >= int64(pageSize) {
			break
		}

		cnt, _ := h.mongoDB.Collection(name).CountDocuments(ctx, filter)
		if skipped+cnt <= skip {
			skipped += cnt
			continue
		}

		localSkip := int64(0)
		if skipped < skip {
			localSkip = skip - skipped
			skipped = skip
		}

		remaining := int64(pageSize) - int64(len(messages))
		localOpts := options.Find().
			SetSort(bson.D{{Key: "created_at", Value: -1}}).
			SetSkip(localSkip).
			SetLimit(remaining)

		cursor, err := h.mongoDB.Collection(name).Find(ctx, filter, localOpts)
		if err != nil {
			continue
		}

		var batch []bson.M
		if err := cursor.All(ctx, &batch); err != nil {
			cursor.Close(ctx)
			continue
		}
		cursor.Close(ctx)

		messages = append(messages, batch...)
		skipped += cnt
	}

	_ = opts

	for i := range messages {
		if id, ok := messages[i]["_id"].(primitive.ObjectID); ok {
			messages[i]["id"] = id.Hex()
			delete(messages[i], "_id")
		}
	}

	response.Success(c, gin.H{
		"list":        messages,
		"total":       total,
		"page":        page,
		"page_size":   pageSize,
		"total_pages": int(math.Ceil(float64(total) / float64(pageSize))),
	})
}

// DeleteAdminMessage 后台管理员彻底删除单条消息记录并下发同步擦除信号
func (h *MessageAdminHandler) DeleteAdminMessage(c *gin.Context) {
	idHex := c.Query("id") // 对应后台传来的 MongoDB hex 字符串 id
	chatID := c.Query("chat_id")

	if idHex == "" || chatID == "" {
		response.BadRequest(c, "缺少必要参数 id 或 chat_id")
		return
	}

	// 将 hex 字符串转化为 MongoDB 的 ObjectID
	objID, err := primitive.ObjectIDFromHex(idHex)
	if err != nil {
		response.BadRequest(c, "参数 id 格式不正确")
		return
	}

	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()

	now := time.Now()
	var deleted bool
	var foundMsg bson.M

	// 过滤条件：精确匹配 ObjectID
	findFilter := bson.M{"_id": objID}

	// 1. 跨 12 个月动态分表扫描并提取真正的 msg_id，同时执行物理删除
	for i := 0; i < 12; i++ {
		t := now.AddDate(0, -i, 0)
		collectionName := "messages_" + chatID + "_" + t.Format("200601")
		if i == 0 {
			collectionName = "messages_" + chatID
		}

		col := h.mongoDB.Collection(collectionName)
		if len(foundMsg) == 0 {
			_ = col.FindOne(ctx, findFilter).Decode(&foundMsg)
		}

		res, err := col.DeleteOne(ctx, findFilter)
		if err == nil && res.DeletedCount > 0 {
			deleted = true
			break
		}
	}

	// 2. 扫全量集合兜底
	if !deleted {
		fallbackCollections := h.getMessageCollections(ctx)
		for _, name := range fallbackCollections {
			col := h.mongoDB.Collection(name)
			if len(foundMsg) == 0 {
				_ = col.FindOne(ctx, findFilter).Decode(&foundMsg)
			}
			res, err := col.DeleteOne(ctx, findFilter)
			if err == nil && res.DeletedCount > 0 {
				deleted = true
				break
			}
		}
	}

	if !deleted {
		response.BadRequest(c, "未找到该消息或删除失败")
		return
	}

	// 3. 从查到的实体里获取 APP 前端需要识别的真正的独立 msg_id UUID
	finalMsgID, _ := foundMsg["msg_id"].(string)
	if finalMsgID == "" {
		// 如果消息实体里碰巧没存 msg_id，则降级用 idHex 字符串去匹配
		finalMsgID = idHex
	}

	// 4. 🌟 组织向对应房间推送 admin_message_delete 通知
	pushPayload := map[string]interface{}{
		"type":    "admin_message_delete", // 完美对齐你在 Flutter 里加好的 3 行代码
		"chat_id": chatID,
		"msg_id":  finalMsgID,
	}

	// 5. 🌟 完美的集群长连接实时派发：通知当前聊天室里的所有端
	if AdminHubInstance != nil {
		var memberUUIDs []string
		err := h.db.Table("user_chats").
			Select("users.uuid").
			Joins("join chats on user_chats.chat_id = chats.id").
			Joins("join users on user_chats.user_id = users.id").
			Where("chats.uuid = ? AND user_chats.deleted_at IS NULL", chatID).
			Pluck("users.uuid", &memberUUIDs).Error

		if err == nil && len(memberUUIDs) > 0 {
			AdminHubInstance.SendToUsersCluster(memberUUIDs, pushPayload)
		} else {
			AdminHubInstance.BroadcastToGroupCluster(chatID, pushPayload)
		}
	}

	response.Success(c, "消息删除成功")
}