// 文件用途：验证 jwt_test.go 对应模块的正常流程、异常处理和回归行为。
// 核心逻辑：覆盖输入校验、状态变化、错误返回、边界条件和并发幸命。

package jwt

import (
	"testing"
	"time"
	"genericim/internal/config"
)

func TestGenerateTokenIsUniqueWithinSameSecond(t *testing.T) {
	original := config.GlobalConfig
	config.GlobalConfig = &config.Config{
		JWT: config.JWTConfig{
			Secret: "jwt-unit-test-secret",
			Expire: time.Hour,
		},
	}
	t.Cleanup(func() {
		config.GlobalConfig = original
	})

	first, err := GenerateToken("user-a", "device-a", 7)
	if err != nil {
		t.Fatalf("generate first token: %v", err)
	}
	second, err := GenerateToken("user-a", "device-a", 7)
	if err != nil {
		t.Fatalf("generate second token: %v", err)
	}
	if first == second {
		t.Fatal("tokens issued in the same second must be unique")
	}

	firstClaims, err := ParseToken(first)
	if err != nil {
		t.Fatalf("parse first token: %v", err)
	}
	secondClaims, err := ParseToken(second)
	if err != nil {
		t.Fatalf("parse second token: %v", err)
	}
	if firstClaims.ID == "" || secondClaims.ID == "" || firstClaims.ID == secondClaims.ID {
		t.Fatalf("unexpected token IDs: first=%q second=%q", firstClaims.ID, secondClaims.ID)
	}
}
