// 文件用途：验证 message_search_test.go 对应模块的正常流程、异常处理和回归行为。
// 核心逻辑：覆盖输入校验、状态变化、错误返回、边界条件和并发幸命。

package services

import (
	"go.mongodb.org/mongo-driver/bson"
	"testing"
	"time"
)

func TestBuildMessageSearchFilterAppliesVisibilityAndFilters(t *testing.T) {
	messageType := 5
	start := time.Date(2026, time.July, 1, 0, 0, 0, 0, time.FixedZone("CST", 8*60*60))
	end := start.AddDate(0, 0, 8)
	filter := buildMessageSearchFilter("chat-1", "user-1", MessageSearchOptions{
		Keyword:     " report.* ",
		SenderID:    "sender-1",
		MessageType: &messageType,
		StartAt:     &start,
		EndAt:       &end,
	})
	if filter["chat_id"] != "chat-1" || filter["sender_id"] != "sender-1" || filter["type"] != messageType {
		t.Fatalf("unexpected basic filters: %#v", filter)
	}
	for _, field := range []string{"deleted_for", "burned_for"} {
		value, ok := filter[field].(bson.M)
		if !ok || value["$ne"] != "user-1" {
			t.Fatalf("%s visibility filter=%#v", field, filter[field])
		}
	}
	createdAt, ok := filter["created_at"].(bson.M)
	if !ok || !createdAt["$gte"].(time.Time).Equal(start.UTC()) || !createdAt["$lt"].(time.Time).Equal(end.UTC()) {
		t.Fatalf("created_at filter=%#v", filter["created_at"])
	}
	orFilters, ok := filter["$or"].([]bson.M)
	if !ok || len(orFilters) < 2 {
		t.Fatalf("keyword filters=%#v", filter["$or"])
	}
	textPattern := orFilters[0]["content.text"].(bson.M)
	if textPattern["$regex"] != `report\.\*` {
		t.Fatalf("keyword was not regex escaped: %#v", textPattern)
	}
}

func TestBuildMessageSearchFilterAllowsFilterOnlySearch(t *testing.T) {
	messageType := 2
	filter := buildMessageSearchFilter("chat-2", "user-2", MessageSearchOptions{MessageType: &messageType})
	if _, exists := filter["$or"]; exists {
		t.Fatalf("empty keyword should not add text predicate: %#v", filter)
	}
	if filter["type"] != messageType {
		t.Fatalf("message type filter missing: %#v", filter)
	}
}
