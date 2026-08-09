// 文件用途：实现后端 HTTP 接口的请求处理和统一响应。
// 核心逻辑：绑定参数，校验身份与权限，调用业务服务并持久化关键状态。

package handlers

import (
	"github.com/gin-gonic/gin"
	"strconv"
	"strings"
	"genericim/internal/models"
	"genericim/internal/services"
	"genericim/pkg/response"
)

type ServiceOperationHandler struct {
	conversation *services.ServiceConversationService
	operation    *services.ServiceOperationService
}

func NewServiceOperationHandler(conversation *services.ServiceConversationService, operation *services.ServiceOperationService) *ServiceOperationHandler {
	return &ServiceOperationHandler{conversation: conversation, operation: operation}
}

func (h *ServiceOperationHandler) currentAgent(c *gin.Context) (*models.ServiceAgent, bool) {
	agent, _, err := h.conversation.CurrentAgent(c.GetString("user_id"))
	if err != nil {
		response.Forbidden(c, "仅已启用的官方客服可访问")
		return nil, false
	}
	return agent, true
}

func (h *ServiceOperationHandler) ListQuickReplies(c *gin.Context) {
	agent, ok := h.currentAgent(c)
	if !ok {
		return
	}
	includeDisabled := c.Query("include_disabled") == "true"
	result, err := h.operation.ListQuickReplies(c.Request.Context(), agent, c.Query("keyword"), c.Query("category"), includeDisabled)
	if err != nil {
		respondServiceWorkbenchError(c, err)
		return
	}
	response.Success(c, result)
}

func (h *ServiceOperationHandler) CreateQuickReply(c *gin.Context) {
	agent, ok := h.currentAgent(c)
	if !ok {
		return
	}
	var req services.ServiceQuickReplyInput
	if err := c.ShouldBindJSON(&req); err != nil {
		response.BadRequest(c, "请填写完整的快捷回复")
		return
	}
	result, err := h.operation.CreateQuickReply(c.Request.Context(), agent, req)
	if err != nil {
		respondServiceWorkbenchError(c, err)
		return
	}
	response.Success(c, result)
}

func (h *ServiceOperationHandler) UpdateQuickReply(c *gin.Context) {
	agent, ok := h.currentAgent(c)
	if !ok {
		return
	}
	var req services.ServiceQuickReplyInput
	if err := c.ShouldBindJSON(&req); err != nil {
		response.BadRequest(c, "请填写完整的快捷回复")
		return
	}
	result, err := h.operation.UpdateQuickReply(c.Request.Context(), agent, c.Param("uuid"), req)
	if err != nil {
		respondServiceWorkbenchError(c, err)
		return
	}
	response.Success(c, result)
}

func (h *ServiceOperationHandler) DeleteQuickReply(c *gin.Context) {
	agent, ok := h.currentAgent(c)
	if !ok {
		return
	}
	if err := h.operation.DeleteQuickReply(c.Request.Context(), agent, c.Param("uuid")); err != nil {
		respondServiceWorkbenchError(c, err)
		return
	}
	response.Success(c, gin.H{"success": true})
}

func (h *ServiceOperationHandler) ListCustomers(c *gin.Context) {
	agent, ok := h.currentAgent(c)
	if !ok {
		return
	}
	page, _ := strconv.Atoi(c.DefaultQuery("page", "1"))
	pageSize, _ := strconv.Atoi(c.DefaultQuery("page_size", "30"))
	result, err := h.operation.ListCustomers(c.Request.Context(), agent, c.Query("keyword"), page, pageSize)
	if err != nil {
		respondServiceWorkbenchError(c, err)
		return
	}
	response.Success(c, result)
}

func (h *ServiceOperationHandler) GetCustomer(c *gin.Context) {
	agent, ok := h.currentAgent(c)
	if !ok {
		return
	}
	result, err := h.operation.GetCustomer(c.Request.Context(), agent, c.Param("uuid"))
	if err != nil {
		respondServiceWorkbenchError(c, err)
		return
	}
	response.Success(c, result)
}

func (h *ServiceOperationHandler) UpdateCustomerProfile(c *gin.Context) {
	agent, ok := h.currentAgent(c)
	if !ok {
		return
	}
	var req services.ServiceCustomerProfileInput
	if err := c.ShouldBindJSON(&req); err != nil {
		response.BadRequest(c, "客户标签或备注格式不正确")
		return
	}
	result, err := h.operation.UpdateCustomerProfile(c.Request.Context(), agent, c.Param("uuid"), req)
	if err != nil {
		respondServiceWorkbenchError(c, err)
		return
	}
	response.Success(c, result)
}

func (h *ServiceOperationHandler) ListFollowUps(c *gin.Context) {
	agent, ok := h.currentAgent(c)
	if !ok {
		return
	}
	result, err := h.operation.ListFollowUps(c.Request.Context(), agent, c.Query("customer_uuid"), c.Query("status"))
	if err != nil {
		respondServiceWorkbenchError(c, err)
		return
	}
	response.Success(c, result)
}

func (h *ServiceOperationHandler) CreateFollowUp(c *gin.Context) {
	agent, ok := h.currentAgent(c)
	if !ok {
		return
	}
	var req services.ServiceFollowUpInput
	if err := c.ShouldBindJSON(&req); err != nil || strings.TrimSpace(req.Content) == "" || req.DueAt.IsZero() {
		response.BadRequest(c, "请填写跟进内容和提醒时间")
		return
	}
	result, err := h.operation.CreateFollowUp(c.Request.Context(), agent, c.Param("uuid"), req)
	if err != nil {
		respondServiceWorkbenchError(c, err)
		return
	}
	response.Success(c, result)
}

func (h *ServiceOperationHandler) UpdateFollowUp(c *gin.Context) {
	agent, ok := h.currentAgent(c)
	if !ok {
		return
	}
	var req services.ServiceFollowUpUpdateInput
	if err := c.ShouldBindJSON(&req); err != nil {
		response.BadRequest(c, "跟进任务格式不正确")
		return
	}
	result, err := h.operation.UpdateFollowUp(c.Request.Context(), agent, c.Param("uuid"), req)
	if err != nil {
		respondServiceWorkbenchError(c, err)
		return
	}
	response.Success(c, result)
}
