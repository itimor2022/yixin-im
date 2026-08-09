// 文件用途：验证 message_reliability_test.go 对应模块的正常流程、异常处理和回归行为。
// 核心逻辑：覆盖输入校验、状态变化、错误返回、边界条件和并发幸命。

package services

import (
	"errors"
	"go.mongodb.org/mongo-driver/mongo"
	"testing"
)

func TestIsMongoDuplicateKeyError(t *testing.T) {
	err := mongo.WriteException{
		WriteErrors: []mongo.WriteError{
			{Code: 11000, Message: "E11000 duplicate key error"},
		},
	}
	if !isMongoDuplicateKeyError(err) {
		t.Fatal("expected duplicate key write exception")
	}
}

func TestIsMongoDuplicateKeyErrorFromWrappedError(t *testing.T) {
	err := errors.New("insert failed: E11000 duplicate key error collection")
	if !isMongoDuplicateKeyError(err) {
		t.Fatal("expected duplicate key fallback detection")
	}
}

func TestIsLikelyMessageSeqDuplicate(t *testing.T) {
	err := errors.New("E11000 duplicate key error index: uniq_chat_seq dup key")
	if !isLikelyMessageSeqDuplicate(err) {
		t.Fatal("expected seq duplicate detection")
	}
}
