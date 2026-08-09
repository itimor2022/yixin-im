// 文件用途：实现后端 HTTP 接口的请求处理和统一响应。
// 核心逻辑：绑定参数，校验身份与权限，调用业务服务并持久化关键状态。

package handlers

import (
	"github.com/gin-gonic/gin"
	"log"
	"strconv"
	"time"
	cachepkg "genericim/internal/cache"
	"genericim/pkg/response"
)

const (
	payPasswordThrottleWindow = 15 * time.Minute
	payPasswordThrottleLimit  = 5
)

func checkPayPasswordThrottle(c *gin.Context, store *cachepkg.Cache, userID uint64) bool {
	if store == nil {

		return true
	}

	count, err := store.RateLimitCount(c.Request.Context(), payPasswordThrottleKey(userID), payPasswordThrottleWindow)
	if err != nil {

		log.Printf("pay password throttle error: %v", err)
		return true
	}
	if count >= payPasswordThrottleLimit {
		response.TooManyRequests(c, "支付密码错误次数过多，请稍后再试")
		c.Abort()
		return false
	}
	return true
}

func recordPayPasswordFailure(c *gin.Context, store *cachepkg.Cache, userID uint64) {
	if store == nil {
		return
	}
	if err := store.RecordRateLimit(c.Request.Context(), payPasswordThrottleKey(userID), payPasswordThrottleWindow); err != nil {
		log.Printf("record pay password failure error: %v", err)
	}
}

func clearPayPasswordFailures(c *gin.Context, store *cachepkg.Cache, userID uint64) {
	if store == nil {
		return
	}
	if err := store.Delete(c.Request.Context(), cachepkg.KeyRateLimit+payPasswordThrottleKey(userID)); err != nil {
		log.Printf("clear pay password failures error: %v", err)
	}
}

func payPasswordThrottleKey(userID uint64) string {

	return "wallet:paypwd:user:" + strconv.FormatUint(userID, 10)
}
