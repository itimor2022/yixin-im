// 文件用途：验证 client_bootstrap_handler_test.go 对应模块的正常流程、异常处理和回归行为。
// 核心逻辑：覆盖输入校验、状态变化、错误返回、边界条件和并发幸命。

package handlers

import (
	"github.com/gin-gonic/gin"
	"net/http/httptest"
	"testing"
	"genericim/internal/config"
)

func TestRewriteAndroidEmulatorURLForBrowserReachableFallback(t *testing.T) {
	got := rewriteAndroidEmulatorURL(

		"http://10.0.2.2:8080",

		"http://localhost:8080",
	)
	if got != "http://localhost:8080" {

		t.Fatalf("rewriteAndroidEmulatorURL() = %q, want localhost fallback", got)
	}
}
func TestRewriteAndroidEmulatorURLKeepsEmulatorFallback(t *testing.T) {
	got := rewriteAndroidEmulatorURL(

		"ws://10.0.2.2:8080/api/v1/ws",

		"ws://10.0.2.2:8080/api/v1/ws",
	)
	if got != "ws://10.0.2.2:8080/api/v1/ws" {

		t.Fatalf("rewriteAndroidEmulatorURL() = %q, want original emulator URL", got)
	}
}
func TestRewriteAndroidEmulatorEndpoints(t *testing.T) {
	endpoints := []config.ClientEndpointConfig{

		{ID: "local-api", URL: "http://10.0.2.2:8080", Priority: 10},

		{ID: "public-api", URL: "https://api.example.com", Priority: 20},
	}
	got := rewriteAndroidEmulatorEndpoints(endpoints, "http://localhost:8080")
	if got[0].URL != "http://localhost:8080" {

		t.Fatalf("first endpoint URL = %q, want localhost fallback", got[0].URL)
	}
	if got[1].URL != "https://api.example.com" {

		t.Fatalf("second endpoint URL = %q, want unchanged public URL", got[1].URL)
	}
}
func TestRewritePrivateWebEndpointsUsesCurrentRequestBase(t *testing.T) {
	endpoints := []config.ClientEndpointConfig{

		{ID: "stale-lan-api", URL: "http://192.168.1.100:8080", Priority: 10},

		{ID: "public-api", URL: "https://api.example.com", Priority: 20},
	}
	got := rewritePrivateWebEndpoints(endpoints, "http://127.0.0.1:8080")
	if got[0].URL != "http://127.0.0.1:8080" {

		t.Fatalf("private endpoint URL = %q, want current request base", got[0].URL)
	}
	if got[1].URL != "https://api.example.com" {

		t.Fatalf("public endpoint URL = %q, want unchanged", got[1].URL)
	}
}
func TestRewritePrivateWebURLPreservesPublicEndpoint(t *testing.T) {
	got := rewritePrivateWebURL(

		"wss://imapi.example.com/api/v1/ws",

		"ws://127.0.0.1:8080/api/v1/ws",
	)
	if got != "wss://imapi.example.com/api/v1/ws" {

		t.Fatalf("rewritePrivateWebURL() = %q, want public endpoint unchanged", got)
	}
}
func TestIsWebBootstrapRequestAcceptsBrowserOrigin(t *testing.T) {
	gin.SetMode(gin.TestMode)
	recorder := httptest.NewRecorder()
	ctx, _ := gin.CreateTestContext(recorder)
	ctx.Request = httptest.NewRequest(

		"GET",

		"http://127.0.0.1:8080/api/v1/client/bootstrap",

		nil,
	)
	ctx.Request.Header.Set("Origin", "http://127.0.0.1:5185")
	if !isWebBootstrapRequest(ctx) {

		t.Fatal("expected a browser Origin header to identify a web bootstrap request")
	}
}
func TestExternalBaseURLUsesRequestHostForBrowserWhenConfiguredForEmulator(t *testing.T) {
	gin.SetMode(gin.TestMode)
	recorder := httptest.NewRecorder()
	ctx, _ := gin.CreateTestContext(recorder)
	ctx.Request = httptest.NewRequest(

		"GET",

		"http://localhost:8080/api/v1/client/bootstrap",

		nil,
	)
	ctx.Request.Host = "localhost:8080"
	cfg := &config.Config{}
	cfg.Server.BaseURL = "http://10.0.2.2:8080"
	cfg.Server.Port = 8080
	got := externalBaseURL(ctx, cfg)
	if got != "http://localhost:8080" {

		t.Fatalf("externalBaseURL() = %q, want browser request host", got)
	}
}
func TestExternalBaseURLUsesRequestHostForWebWhenConfiguredForStaleLAN(t *testing.T) {
	gin.SetMode(gin.TestMode)
	recorder := httptest.NewRecorder()
	ctx, _ := gin.CreateTestContext(recorder)
	ctx.Request = httptest.NewRequest(

		"GET",

		"http://127.0.0.1:8080/api/v1/client/bootstrap",

		nil,
	)
	ctx.Request.Host = "127.0.0.1:8080"
	ctx.Request.Header.Set("X-Client-Platform", "web")
	cfg := &config.Config{}
	cfg.Server.BaseURL = "http://192.168.1.100:8080"
	cfg.Server.Port = 8080
	got := externalBaseURL(ctx, cfg)
	if got != "http://127.0.0.1:8080" {

		t.Fatalf("externalBaseURL() = %q, want current web request host", got)
	}
}
func TestExternalBaseURLKeepsEmulatorHostForEmulatorRequest(t *testing.T) {
	gin.SetMode(gin.TestMode)
	recorder := httptest.NewRecorder()
	ctx, _ := gin.CreateTestContext(recorder)
	ctx.Request = httptest.NewRequest(

		"GET",

		"http://10.0.2.2:8080/api/v1/client/bootstrap",

		nil,
	)
	ctx.Request.Host = "10.0.2.2:8080"
	cfg := &config.Config{}
	cfg.Server.BaseURL = "http://10.0.2.2:8080"
	cfg.Server.Port = 8080
	got := externalBaseURL(ctx, cfg)
	if got != "http://10.0.2.2:8080" {

		t.Fatalf("externalBaseURL() = %q, want emulator base URL", got)
	}
}
