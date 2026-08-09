// 文件用途：验证 livekit_service_test.go 对应模块的正常流程、异常处理和回归行为。
// 核心逻辑：覆盖输入校验、状态变化、错误返回、边界条件和并发幸命。

package services

import (
	"github.com/golang-jwt/jwt/v5"
	"testing"
	"time"
)

func TestLiveKitServiceGenerateJoinToken(t *testing.T) {
	t.Parallel()
	service := NewLiveKitService(
		true,
		" wss://livekit.example.com ",
		" api-key ",
		" api-secret ",
		7200,
	)

	tokenString, err := service.GenerateJoinToken(" room-a ", " user-1 ", " Alice ", true)
	if err != nil {
		t.Fatalf("GenerateJoinToken returned error: %v", err)
	}
	claims := &liveKitAccessClaims{}
	token, err := jwt.ParseWithClaims(tokenString, claims, func(token *jwt.Token) (interface{}, error) {
		if token.Method != jwt.SigningMethodHS256 {
			t.Fatalf("signing method=%v, want HS256", token.Method.Alg())
		}
		return []byte("api-secret"), nil
	})
	if err != nil {
		t.Fatalf("parse token: %v", err)
	}
	if !token.Valid {
		t.Fatalf("token should be valid")
	}
	if claims.Issuer != "api-key" {
		t.Fatalf("issuer=%q, want api-key", claims.Issuer)
	}
	if claims.Subject != "user-1" {
		t.Fatalf("subject=%q, want user-1", claims.Subject)
	}
	if claims.Name != "Alice" {
		t.Fatalf("name=%q, want Alice", claims.Name)
	}
	if claims.Video.Room != "room-a" {
		t.Fatalf("room=%q, want room-a", claims.Video.Room)
	}
	if !claims.Video.RoomJoin || !claims.Video.CanPublish || !claims.Video.CanSubscribe || !claims.Video.CanPublishData {
		t.Fatalf("video grant should allow join/publish/subscribe/data: %+v", claims.Video)
	}
	if claims.ExpiresAt == nil || time.Until(claims.ExpiresAt.Time) < 7100*time.Second {
		t.Fatalf("expires_at should use configured token expiry, got %v", claims.ExpiresAt)
	}
}

func TestLiveKitServiceGenerateJoinTokenValidation(t *testing.T) {
	t.Parallel()
	tests := []struct {
		name     string
		service  *LiveKitService
		roomName string
		identity string
	}{
		{
			name:     "not configured",
			service:  NewLiveKitService(true, "wss://livekit.example.com", "api-key", "", 3600),
			roomName: "room-a",
			identity: "user-1",
		},
		{
			name:     "missing room",
			service:  NewLiveKitService(true, "wss://livekit.example.com", "api-key", "api-secret", 3600),
			roomName: "",
			identity: "user-1",
		},
		{
			name:     "missing identity",
			service:  NewLiveKitService(true, "wss://livekit.example.com", "api-key", "api-secret", 3600),
			roomName: "room-a",
			identity: "",
		},
	}
	for _, tc := range tests {
		tc := tc
		t.Run(tc.name, func(t *testing.T) {
			t.Parallel()
			if _, err := tc.service.GenerateJoinToken(tc.roomName, tc.identity, "", true); err == nil {
				t.Fatalf("expected error, got nil")
			}
		})
	}
}

func TestLiveKitServiceGetExpireTimeDefaults(t *testing.T) {
	t.Parallel()
	if got := NewLiveKitService(true, "url", "key", "secret", 0).GetExpireTime(); got != time.Hour {
		t.Fatalf("default expire=%s, want 1h", got)
	}
	if got := NewLiveKitService(true, "url", "key", "secret", 90).GetExpireTime(); got != 90*time.Second {
		t.Fatalf("custom expire=%s, want 90s", got)
	}
}
