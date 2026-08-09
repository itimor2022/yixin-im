// 文件用途：实现后端 HTTP 接口的请求处理和统一响应。
// 核心逻辑：绑定参数，校验身份与权限，调用业务服务并持久化关键状态。

package handlers

import (
	"crypto/sha256"
	"encoding/hex"
	"github.com/gin-gonic/gin"
	"log"
	"strings"
	"time"
	cachepkg "genericim/internal/cache"
	"genericim/pkg/response"
)

const (
	loginThrottleWindow       = 15 * time.Minute
	loginThrottleIPLimit      = 60
	loginThrottleAccountLimit = 10
)

func checkLoginThrottle(c *gin.Context, store *cachepkg.Cache, scope, identifier string) bool {
	if store == nil {
		return true
	}
	if !checkLoginThrottleKey(c, store, loginThrottleIPKey(scope, c.ClientIP()), loginThrottleIPLimit) {
		return false
	}
	accountKey := loginThrottleAccountKey(scope, identifier)
	if accountKey == "" {
		return true
	}
	return checkLoginThrottleKey(c, store, accountKey, loginThrottleAccountLimit)
}

func checkLoginThrottleKey(c *gin.Context, store *cachepkg.Cache, key string, limit int) bool {
	count, err := store.RateLimitCount(c.Request.Context(), key, loginThrottleWindow)
	if err != nil {
		log.Printf("login throttle error: %v", err)
		return true
	}
	if count >= int64(limit) {
		response.TooManyRequests(c, "请求过于频繁，请稍后再试")
		c.Abort()
		return false
	}
	return true
}

func recordLoginFailure(c *gin.Context, store *cachepkg.Cache, scope, identifier string) {
	if store == nil {
		return
	}

	recordLoginThrottleKey(c, store, loginThrottleIPKey(scope, c.ClientIP()))
	if accountKey := loginThrottleAccountKey(scope, identifier); accountKey != "" {
		recordLoginThrottleKey(c, store, accountKey)
	}
}

func recordLoginThrottleKey(c *gin.Context, store *cachepkg.Cache, key string) {
	if err := store.RecordRateLimit(c.Request.Context(), key, loginThrottleWindow); err != nil {
		log.Printf("record login throttle error: %v", err)
	}
}

func clearLoginAccountThrottle(c *gin.Context, store *cachepkg.Cache, scope, identifier string) {
	if store == nil {
		return
	}
	accountKey := loginThrottleAccountKey(scope, identifier)
	if accountKey == "" {
		return
	}
	if err := store.Delete(c.Request.Context(), cachepkg.KeyRateLimit+accountKey); err != nil {
		log.Printf("clear login throttle error: %v", err)
	}
}

func loginThrottleIPKey(scope, ip string) string {
	return "login:" + strings.TrimSpace(scope) + ":ip:" + strings.TrimSpace(ip)
}

func loginThrottleAccountKey(scope, identifier string) string {
	normalized := strings.ToLower(strings.TrimSpace(identifier))
	if normalized == "" {
		return ""
	}
	sum := sha256.Sum256([]byte(normalized))
	return "login:" + strings.TrimSpace(scope) + ":acct:" + hex.EncodeToString(sum[:])
}
