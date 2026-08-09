// 文件用途：实现后端 HTTP 接口的请求处理和统一响应。
// 核心逻辑：绑定参数，校验身份与权限，调用业务服务并持久化关键状态。

package handlers

import (
	"github.com/gin-gonic/gin"
	"genericim/pkg/response"
)

func (h *MessageHandler) GetRecoveryCapabilities(c *gin.Context) {
	if h == nil || h.msgService == nil {
		response.ServerError(c, "消息恢复能力尚未初始化")
		return
	}
	response.Success(c, h.msgService.RecoveryCapabilities())
}
