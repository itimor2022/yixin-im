// 文件用途：验证 middleware_test.go 对应模块的正常流程、异常处理和回归行为。
// 核心逻辑：覆盖输入校验、状态变化、错误返回、边界条件和并发幸命。

package middleware

import (
	"github.com/gin-gonic/gin"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
	"genericim/internal/config"
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

func TestAllowedCORSOrigin(t *testing.T) {
	old := config.GlobalConfig
	defer func() { config.GlobalConfig = old }()
	config.GlobalConfig = nil
	if got := allowedCORSOrigin("https://evil.example"); got != "*" {
		t.Fatalf("empty config should keep wildcard compatibility, got %q", got)
	}
	config.GlobalConfig = &config.Config{
		Server: config.ServerConfig{
			AllowedOrigins: []string{"https://app.example.com", "https://h5.example.com"},
		},
	}
	if got := allowedCORSOrigin("https://h5.example.com"); got != "https://h5.example.com" {
		t.Fatalf("expected matching origin, got %q", got)
	}
	config.GlobalConfig.Server.AllowedOrigins = []string{"https://admin.example.com/"}
	if got := allowedCORSOrigin("https://admin.example.com"); got != "https://admin.example.com" {
		t.Fatalf("expected normalized origin match, got %q", got)
	}
	config.GlobalConfig.Server.AllowedOrigins = []string{"https://admin.example.com/app"}
	if got := allowedCORSOrigin("https://admin.example.com"); got != "https://admin.example.com" {
		t.Fatalf("expected origin-only match, got %q", got)
	}
	config.GlobalConfig.Server.AllowedOrigins = []string{"https://app.example.com", "https://h5.example.com"}
	if got := allowedCORSOrigin("https://evil.example"); got != "https://app.example.com" {
		t.Fatalf("expected fallback allowed origin, got %q", got)
	}
	config.GlobalConfig.Server.AllowedOrigins = []string{"https://app.example.com", "http://web.example.com", "https://web.example.com"}
	if got := allowedCORSOrigin("http://web.example.com"); got != "http://web.example.com" {
		t.Fatalf("expected web origin, got %q", got)
	}
}

func TestCORSPreflightAllowsConfiguredAdminOrigin(t *testing.T) {
	old := config.GlobalConfig
	defer func() { config.GlobalConfig = old }()
	config.GlobalConfig = &config.Config{
		Server: config.ServerConfig{
			AllowedOrigins: []string{"http://admin.example.com", "https://admin.example.com"},
		},
	}
	gin.SetMode(gin.TestMode)
	router := gin.New()
	router.Use(CORS())
	router.GET("/api/v1/admin/settings", func(c *gin.Context) {
		c.Status(http.StatusOK)
	})
	req := httptest.NewRequest(http.MethodOptions, "/api/v1/admin/settings", nil)
	req.Header.Set("Origin", "http://admin.example.com")
	req.Header.Set("Access-Control-Request-Method", http.MethodGet)
	rec := httptest.NewRecorder()
	router.ServeHTTP(rec, req)
	if rec.Code != http.StatusNoContent {
		t.Fatalf("expected preflight status 204, got %d", rec.Code)
	}
	if got := rec.Header().Get("Access-Control-Allow-Origin"); got != "http://admin.example.com" {
		t.Fatalf("expected admin origin, got %q", got)
	}
	if got := rec.Header().Get("Access-Control-Allow-Credentials"); got != "true" {
		t.Fatalf("expected credentials to be allowed for explicit origin, got %q", got)
	}
}

func TestCORSPreflightAllowsConfiguredWebOrigin(t *testing.T) {
	old := config.GlobalConfig
	defer func() { config.GlobalConfig = old }()
	config.GlobalConfig = &config.Config{
		Server: config.ServerConfig{
			AllowedOrigins: []string{"https://app.example.com", "http://web.example.com", "https://web.example.com"},
		},
	}
	gin.SetMode(gin.TestMode)
	router := gin.New()
	router.Use(CORS())
	router.GET("/api/v1/app/settings", func(c *gin.Context) {
		c.Status(http.StatusOK)
	})
	req := httptest.NewRequest(http.MethodOptions, "/api/v1/app/settings", nil)
	req.Header.Set("Origin", "http://web.example.com")
	req.Header.Set("Access-Control-Request-Method", http.MethodGet)
	req.Header.Set("Access-Control-Request-Headers", "content-type, x-client-platform")
	rec := httptest.NewRecorder()
	router.ServeHTTP(rec, req)
	if rec.Code != http.StatusNoContent {
		t.Fatalf("expected preflight status 204, got %d", rec.Code)
	}
	if got := rec.Header().Get("Access-Control-Allow-Origin"); got != "http://web.example.com" {
		t.Fatalf("expected web origin, got %q", got)
	}
	if got := rec.Header().Get("Access-Control-Allow-Credentials"); got != "true" {
		t.Fatalf("expected credentials to be allowed for explicit origin, got %q", got)
	}
	if got := strings.ToLower(rec.Header().Get("Access-Control-Allow-Headers")); !strings.Contains(got, "x-client-platform") {
		t.Fatalf("expected Flutter Web client platform header to be allowed, got %q", got)
	}
}
