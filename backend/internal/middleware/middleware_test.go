package middleware

import (
	"net/http"
	"net/http/httptest"
	"testing"

	"github.com/gin-gonic/gin"
)

func TestRedactSensitiveQuery(t *testing.T) {
	got := redactSensitiveQuery("token=abc123&chat_id=c1&access_token=def456&password=pw")
	if got != "access_token=%2A%2A%2A&chat_id=c1&password=%2A%2A%2A&token=%2A%2A%2A" {
		t.Fatalf("redactSensitiveQuery()=%q", got)
	}
}

func TestAllowsQueryTokenOnlyForWebSocket(t *testing.T) {
	gin.SetMode(gin.TestMode)

	wsCtx, _ := gin.CreateTestContext(httptest.NewRecorder())
	wsCtx.Request = httptest.NewRequest(http.MethodGet, "/api/ws?token=abc", nil)
	if !allowsQueryToken(wsCtx) {
		t.Fatal("expected /api/ws to allow query token")
	}

	normalCtx, _ := gin.CreateTestContext(httptest.NewRecorder())
	normalCtx.Request = httptest.NewRequest(http.MethodGet, "/api/user/profile?token=abc", nil)
	if allowsQueryToken(normalCtx) {
		t.Fatal("expected normal API path to reject query token")
	}
}
