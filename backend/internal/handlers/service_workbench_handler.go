// 文件用途：实现后端 HTTP 接口的请求处理和统一响应。
// 核心逻辑：绑定参数，校验身份与权限，调用业务服务并持久化关键状态。

package handlers

import (
	"errors"
	"github.com/gin-gonic/gin"
	"log"
	"net/http"
	"strconv"
	"strings"
	"genericim/internal/models"
	"genericim/internal/services"
	"genericim/pkg/response"
)

type ServiceWorkbenchHandler struct {
	service *services.ServiceConversationService
}

func NewServiceWorkbenchHandler(service *services.ServiceConversationService) *ServiceWorkbenchHandler {
	return &ServiceWorkbenchHandler{service: service}
}

func (h *ServiceWorkbenchHandler) currentAgent(c *gin.Context) (*models.ServiceAgent, *models.User, bool) {
	agent, user, err := h.service.CurrentAgent(c.GetString("user_id"))
	if err != nil {
		response.Forbidden(c, "仅已启用的官方客服可访问")
		return nil, nil, false
	}
	return agent, user, true
}

func (h *ServiceWorkbenchHandler) GetPresence(c *gin.Context) {
	agent, _, ok := h.currentAgent(c)
	if !ok {
		return
	}
	result, err := h.service.Presence(c.Request.Context(), agent)
	if err != nil {
		respondServiceWorkbenchError(c, err)
		return
	}
	response.Success(c, result)
}

type servicePresenceRequest struct {
	Presence string `json:"presence" binding:"required"`
}

func (h *ServiceWorkbenchHandler) UpdatePresence(c *gin.Context) {
	agent, _, ok := h.currentAgent(c)
	if !ok {
		return
	}
	var req servicePresenceRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		response.BadRequest(c, "请选择有效的客服状态")
		return
	}
	result, err := h.service.UpdatePresence(c.Request.Context(), agent, req.Presence)
	if err != nil {
		respondServiceWorkbenchError(c, err)
		return
	}
	response.Success(c, result)
}

func (h *ServiceWorkbenchHandler) Heartbeat(c *gin.Context) {
	agent, _, ok := h.currentAgent(c)
	if !ok {
		return
	}
	result, err := h.service.Heartbeat(c.Request.Context(), agent)
	if err != nil {
		respondServiceWorkbenchError(c, err)
		return
	}
	response.Success(c, result)
}

func (h *ServiceWorkbenchHandler) GetAvailableAgents(c *gin.Context) {
	agent, _, ok := h.currentAgent(c)
	if !ok {
		return
	}
	result, err := h.service.AvailableAgents(c.Request.Context(), agent)
	if err != nil {
		respondServiceWorkbenchError(c, err)
		return
	}
	response.Success(c, result)
}

func (h *ServiceWorkbenchHandler) ListConversations(c *gin.Context) {
	agent, _, ok := h.currentAgent(c)
	if !ok {
		return
	}
	page, _ := strconv.Atoi(c.DefaultQuery("page", "1"))
	pageSize, _ := strconv.Atoi(c.DefaultQuery("page_size", "50"))
	result, err := h.service.List(c.Request.Context(), agent, services.ServiceConversationListOptions{
		Queue: c.DefaultQuery("status", "serving"), Keyword: c.Query("keyword"), Page: page, PageSize: pageSize,
	})
	if err != nil {
		respondServiceWorkbenchError(c, err)
		return
	}
	response.Success(c, result)
}

func (h *ServiceWorkbenchHandler) GetConversation(c *gin.Context) {
	agent, _, ok := h.currentAgent(c)
	if !ok {
		return
	}
	result, err := h.service.Get(c.Request.Context(), agent, c.Param("uuid"))
	if err != nil {
		respondServiceWorkbenchError(c, err)
		return
	}
	response.Success(c, result)
}

func (h *ServiceWorkbenchHandler) ClaimConversation(c *gin.Context) {
	agent, _, ok := h.currentAgent(c)
	if !ok {
		return
	}
	result, err := h.service.Claim(c.Request.Context(), agent, c.Param("uuid"))
	if err != nil {
		respondServiceWorkbenchError(c, err)
		return
	}
	response.Success(c, result)
}

func (h *ServiceWorkbenchHandler) AcceptConversation(c *gin.Context) {
	agent, _, ok := h.currentAgent(c)
	if !ok {
		return
	}
	result, err := h.service.Accept(c.Request.Context(), agent, c.Param("uuid"))
	if err != nil {
		respondServiceWorkbenchError(c, err)
		return
	}
	response.Success(c, result)
}

type serviceTransferRequest struct {
	AgentID uint64 `json:"agent_id" binding:"required"`
	Reason  string `json:"reason" binding:"required"`
}

func (h *ServiceWorkbenchHandler) TransferConversation(c *gin.Context) {
	agent, _, ok := h.currentAgent(c)
	if !ok {
		return
	}
	var req serviceTransferRequest
	if err := c.ShouldBindJSON(&req); err != nil || strings.TrimSpace(req.Reason) == "" {
		response.BadRequest(c, "请选择目标客服并填写转接原因")
		return
	}
	result, err := h.service.Transfer(c.Request.Context(), agent, c.Param("uuid"), req.AgentID, req.Reason)
	if err != nil {
		respondServiceWorkbenchError(c, err)
		return
	}
	response.Success(c, result)
}

type serviceStatusRequest struct {
	Status string `json:"status" binding:"required"`
}

func (h *ServiceWorkbenchHandler) ChangeConversationStatus(c *gin.Context) {
	agent, _, ok := h.currentAgent(c)
	if !ok {
		return
	}
	var req serviceStatusRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		response.BadRequest(c, "请选择有效的会话状态")
		return
	}
	result, err := h.service.ChangeStatus(c.Request.Context(), agent, c.Param("uuid"), req.Status)
	if err != nil {
		respondServiceWorkbenchError(c, err)
		return
	}
	response.Success(c, result)
}

type serviceCloseRequest struct {
	Reason string `json:"reason"`
}

func (h *ServiceWorkbenchHandler) CloseConversation(c *gin.Context) {
	agent, _, ok := h.currentAgent(c)
	if !ok {
		return
	}
	var req serviceCloseRequest
	_ = c.ShouldBindJSON(&req)
	result, err := h.service.Close(c.Request.Context(), agent, c.Param("uuid"), req.Reason)
	if err != nil {
		respondServiceWorkbenchError(c, err)
		return
	}
	response.Success(c, result)
}

func (h *ServiceWorkbenchHandler) ReopenConversation(c *gin.Context) {
	agent, _, ok := h.currentAgent(c)
	if !ok {
		return
	}
	result, err := h.service.Reopen(c.Request.Context(), agent, c.Param("uuid"))
	if err != nil {
		respondServiceWorkbenchError(c, err)
		return
	}
	response.Success(c, result)
}

func (h *ServiceWorkbenchHandler) MarkConversationRead(c *gin.Context) {
	agent, _, ok := h.currentAgent(c)
	if !ok {
		return
	}
	if err := h.service.MarkRead(c.Request.Context(), agent, c.Param("uuid")); err != nil {
		respondServiceWorkbenchError(c, err)
		return
	}
	response.Success(c, gin.H{"success": true})
}

func (h *ServiceWorkbenchHandler) GetMessages(c *gin.Context) {
	agent, _, ok := h.currentAgent(c)
	if !ok {
		return
	}
	beforeSeq, _ := strconv.Atoi(c.Query("before_seq"))
	limit, _ := strconv.Atoi(c.DefaultQuery("limit", "50"))
	result, err := h.service.Messages(c.Request.Context(), agent, c.Param("uuid"), beforeSeq, limit)
	if err != nil {
		respondServiceWorkbenchError(c, err)
		return
	}
	response.Success(c, result)
}

type serviceSendMessageRequest struct {
	Text  string `json:"text" binding:"required"`
	MsgID string `json:"msg_id"`
}

func (h *ServiceWorkbenchHandler) SendMessage(c *gin.Context) {
	agent, user, ok := h.currentAgent(c)
	if !ok {
		return
	}
	var req serviceSendMessageRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		response.BadRequest(c, "回复内容不能为空")
		return
	}
	result, err := h.service.SendText(c.Request.Context(), agent, user, c.Param("uuid"), req.Text, req.MsgID)
	if err != nil {
		respondServiceWorkbenchError(c, err)
		return
	}
	response.Success(c, result)
}

func respondServiceWorkbenchError(c *gin.Context, err error) {
	log.Printf("[ServiceWorkbench] request failed method=%s path=%s err=%v", c.Request.Method, c.Request.URL.Path, err)
	switch {
	case errors.Is(err, services.ErrServiceAgentForbidden):
		response.Forbidden(c, "无权操作该服务会话")
	case errors.Is(err, services.ErrServiceConversationNotFound):
		response.NotFound(c, "服务会话不存在")
	case errors.Is(err, services.ErrServiceConversationConflict):
		response.Error(c, http.StatusConflict, "会话状态已变化，请刷新后重试")
	case errors.Is(err, services.ErrServiceAgentAtCapacity):
		response.Error(c, http.StatusConflict, "当前客服接待数已达到上限")
	case errors.Is(err, services.ErrServiceInvalidTransition):
		response.BadRequest(c, "当前会话状态不支持此操作")
	case errors.Is(err, services.ErrServiceEncryptionUnsupported):
		response.Error(c, http.StatusConflict, "严格端到端加密模式下暂不支持网页客服代发，请先调整客服会话加密策略")
	default:
		response.ServerError(c, "客服工作台服务暂时不可用")
	}
}
