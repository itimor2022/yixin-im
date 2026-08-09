// 文件用途：实现后端 HTTP 接口的请求处理和统一响应。
// 核心逻辑：绑定参数，校验身份与权限，调用业务服务并持久化关键状态。

package handlers

import (
	"context"
	"github.com/gin-gonic/gin"
	"net/http"
	cachepkg "genericim/internal/cache"
	"genericim/pkg/response"
)

const smsVerifyAttemptLimit = 5

func allowSMSVerifyAttempt(c *gin.Context, store *cachepkg.Cache, scope string, revokeKeys ...string) bool {
	if store == nil {
		response.ServerError(c, "验证服务异常")
		return false
	}
	attemptKey := "verify:attempt:" + scope
	allowed, err := store.RateLimit(c.Request.Context(), attemptKey, smsVerifyAttemptLimit, cachepkg.TTLVerifyCode)
	if err != nil {
		response.Error(c, http.StatusServiceUnavailable, "验证服务暂不可用，请稍后再试")
		return false
	}
	if allowed {
		return true
	}
	if len(revokeKeys) > 0 {
		_ = store.Delete(c.Request.Context(), revokeKeys...)
	}
	response.Error(c, http.StatusTooManyRequests, "验证码错误次数过多，请重新获取")
	return false
}

func clearSMSVerifyAttempts(ctx context.Context, store *cachepkg.Cache, scopes ...string) {
	if store == nil || len(scopes) == 0 {
		return
	}
	keys := make([]string, 0, len(scopes))
	for _, scope := range scopes {
		if scope == "" {
			continue
		}
		keys = append(keys, "verify:attempt:"+scope)
	}
	if len(keys) == 0 {
		return
	}
	_ = store.Delete(ctx, keys...)
}
