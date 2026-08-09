// 文件用途：实现后端 HTTP 接口的请求处理和统一响应。
// 核心逻辑：绑定参数，校验身份与权限，调用业务服务并持久化关键状态。

package handlers

import (
	"fmt"
	"github.com/gin-gonic/gin"
	"gorm.io/gorm"
	"net/http"
	"genericim/internal/models"
	"genericim/internal/services"
	"genericim/pkg/response"
)

type OnlinePaymentHandler struct {
	svc *services.OnlinePaymentService
	db  *gorm.DB
}

func NewOnlinePaymentHandler(svc *services.OnlinePaymentService, db *gorm.DB) *OnlinePaymentHandler {
	return &OnlinePaymentHandler{svc: svc, db: db}
}

func (h *OnlinePaymentHandler) Options(c *gin.Context) {
	response.Success(c, h.svc.Options())
}

func (h *OnlinePaymentHandler) Create(c *gin.Context) {
	if !h.svc.Enabled() {
		response.Error(c, http.StatusServiceUnavailable, "在线支付未启用或未配置")
		return
	}
	userID, err := h.getUserID(c)
	if err != nil {
		response.Error(c, http.StatusUnauthorized, "用户未登录")
		return
	}
	if ok, msg := RequirePhoneBindIfPolicy(h.db, userID, "使用在线支付"); !ok {
		response.Error(c, http.StatusForbidden, msg)
		return
	}
	var req struct {
		Amount         float64 `json:"amount" binding:"required,gt=0"`
		Channel        string  `json:"channel" binding:"required,oneof=wechat alipay"`
		ClientPlatform string  `json:"client_platform" binding:"required"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		response.Error(c, http.StatusBadRequest, "参数错误")
		return
	}
	switch req.ClientPlatform {
	case "android", "ios", "web", "windows", "macos", "linux":
	default:
		response.Error(c, http.StatusBadRequest, "client_platform 无效")
		return
	}
	res, err := h.svc.CreateOnlinePayment(c.Request.Context(), userID, req.Amount, req.Channel, req.ClientPlatform, c.ClientIP())
	if err != nil {
		response.Error(c, http.StatusBadRequest, err.Error())
		return
	}
	response.Success(c, res)
}

func (h *OnlinePaymentHandler) QueryOrder(c *gin.Context) {
	userID, err := h.getUserID(c)
	if err != nil {
		response.Error(c, http.StatusUnauthorized, "用户未登录")
		return
	}
	out := c.Param("out_trade_no")
	if out == "" {
		response.Error(c, http.StatusBadRequest, "缺少订单号")
		return
	}
	o, err := h.svc.GetUserOrder(userID, out)
	if err != nil {
		response.Error(c, http.StatusNotFound, "订单不存在")
		return
	}
	response.Success(c, gin.H{
		"out_trade_no": o.OutTradeNo,
		"status":       o.Status,
		"amount":       o.Amount,
		"channel":      o.Channel,
		"pay_mode":     o.PayMode,
		"created_at":   o.CreatedAt,
		"paid_at":      o.PaidAt,
	})
}

func (h *OnlinePaymentHandler) WeChatNotify(c *gin.Context) {
	h.svc.HandleWeChatNotify(c.Writer, c.Request)
}

func (h *OnlinePaymentHandler) AlipayNotify(c *gin.Context) {
	h.svc.HandleAlipayNotify(c.Writer, c.Request)
}

func (h *OnlinePaymentHandler) getUserID(c *gin.Context) (uint64, error) {
	userUUID := c.GetString("user_id")
	if userUUID == "" {
		return 0, fmt.Errorf("missing user")
	}
	var user models.User
	if err := h.db.Where("uuid = ?", userUUID).First(&user).Error; err != nil {
		return 0, err
	}
	return user.ID, nil
}
