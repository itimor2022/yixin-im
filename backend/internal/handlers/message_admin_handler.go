package handlers

import (
	"context"
	"gaoranim/pkg/response"
	"math"
	"regexp"
	"sort"
	"strconv"
	"time"

	"github.com/gin-gonic/gin"
	"go.mongodb.org/mongo-driver/bson"
	"go.mongodb.org/mongo-driver/bson/primitive"
	"go.mongodb.org/mongo-driver/mongo"
	"go.mongodb.org/mongo-driver/mongo/options"
	"gorm.io/gorm"
)

type MessageAdminHandler struct {
	db      *gorm.DB
	mongoDB *mongo.Database
}

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

	ctx := context.Background()
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
