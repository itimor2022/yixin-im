// 文件用途：实现后端 HTTP 接口的请求处理和统一响应。
// 核心逻辑：绑定参数，校验身份与权限，调用业务服务并持久化关键状态。

package handlers

import (
	"github.com/gin-gonic/gin"
	"gorm.io/gorm"
	"net/http"
	"strconv"
	"strings"
	"genericim/internal/models"
	"genericim/internal/services"
	"genericim/pkg/response"
)

type VipHandler struct {
	db     *gorm.DB
	vipSvc *services.VipService
}

func NewVipHandler(db *gorm.DB) *VipHandler {
	return &VipHandler{
		db:     db,
		vipSvc: services.NewVipService(db),
	}
}

func (h *VipHandler) ListPlans(c *gin.Context) {
	compliance := loadIOSComplianceConfig(h.db)
	if compliance.Enabled && !compliance.VIPEnabled && isIOSClientRequest(c, h.db, 0) {
		response.Success(c, []gin.H{})
		return
	}
	plans, err := h.vipSvc.ListEnabledPlans()
	if err != nil {
		response.ServerError(c, "获取会员套餐失败")
		return
	}
	items := make([]gin.H, 0, len(plans))
	for _, plan := range plans {
		items = append(items, vipPlanResponse(plan))
	}
	response.Success(c, items)
}

func (h *VipHandler) GetStatus(c *gin.Context) {
	user, ok := h.currentUser(c)
	if !ok {
		return
	}
	status, err := h.vipSvc.GetStatus(user.ID)
	if err != nil {
		response.ServerError(c, "获取会员状态失败")
		return
	}
	response.Success(c, vipStatusResponse(status))
}

func (h *VipHandler) CheckCreatePermission(c *gin.Context) {
	user, ok := h.currentUser(c)
	if !ok {
		return
	}
	chatType, err := strconv.Atoi(strings.TrimSpace(c.DefaultQuery("type", "2")))
	if err != nil || (chatType != 2 && chatType != 3) {
		response.BadRequest(c, "参数错误")
		return
	}
	check, err := h.vipSvc.CanCreateChat(user.ID, int8(chatType))
	if err != nil {
		response.ServerError(c, "校验会员权限失败")
		return
	}
	response.Success(c, check)
}

func (h *VipHandler) Purchase(c *gin.Context) {
	user, ok := h.currentUser(c)
	if !ok {
		return
	}
	compliance := loadIOSComplianceConfig(h.db)
	if compliance.Enabled && !compliance.VIPEnabled && isIOSClientRequest(c, h.db, user.ID) {
		response.Forbidden(c, "当前 iOS 版本暂不提供会员购买")
		return
	}
	var req struct {
		PlanID uint64 `json:"plan_id" binding:"required"`
	}
	if err := c.ShouldBindJSON(&req); err != nil || req.PlanID == 0 {
		response.BadRequest(c, "请选择会员套餐")
		return
	}
	order, status, err := h.vipSvc.PurchaseWithWallet(user.ID, req.PlanID)
	if err != nil {
		response.Error(c, http.StatusBadRequest, err.Error())
		return
	}
	response.Success(c, gin.H{
		"order":  order,
		"status": vipStatusResponse(status),
	})
}

func (h *VipHandler) ListMyOrders(c *gin.Context) {
	user, ok := h.currentUser(c)
	if !ok {
		return
	}
	page := getQueryInt(c, "page", 1)
	pageSize := getQueryInt(c, "page_size", 20)
	if pageSize > 100 {
		pageSize = 100
	}
	query := h.db.Table("vip_orders o").
		Joins("LEFT JOIN vip_plans p ON p.id = o.plan_id").
		Where("o.user_id = ?", user.ID)
	var total int64
	query.Count(&total)

	var rows []struct {
		models.VipOrder
		PlanName  string `json:"plan_name"`
		PlanLevel int8   `json:"plan_level"`
	}
	if err := query.Select(`o.*, p.name AS plan_name, p.level AS plan_level`).
		Order("o.created_at DESC").
		Offset((page - 1) * pageSize).
		Limit(pageSize).
		Scan(&rows).Error; err != nil {
		response.ServerError(c, "获取会员订单失败")
		return
	}
	items := make([]gin.H, 0, len(rows))
	for _, row := range rows {
		items = append(items, gin.H{
			"id":             row.ID,
			"order_no":       row.OrderNo,
			"plan_id":        row.PlanID,
			"plan_name":      row.PlanName,
			"plan_level":     row.PlanLevel,
			"amount":         row.Amount,
			"pay_method":     row.PayMethod,
			"status":         row.Status,
			"paid_at":        row.PaidAt,
			"transaction_id": row.TransactionID,
			"remark":         row.Remark,
			"created_at":     row.CreatedAt,
		})
	}
	response.Success(c, gin.H{
		"list":      items,
		"total":     total,
		"page":      page,
		"page_size": pageSize,
	})
}

func (h *VipHandler) currentUser(c *gin.Context) (models.User, bool) {
	var user models.User
	userUUID := strings.TrimSpace(c.GetString("user_id"))
	if userUUID == "" {
		response.Unauthorized(c, "请先登录")
		return user, false
	}
	if err := h.db.Where("uuid = ?", userUUID).First(&user).Error; err != nil {
		response.NotFound(c, "用户不存在")
		return user, false
	}
	return user, true
}

func vipPlanResponse(plan models.VipPlan) gin.H {
	return gin.H{
		"id":             plan.ID,
		"code":           plan.Code,
		"name":           plan.Name,
		"level":          plan.Level,
		"level_name":     services.LevelName(plan.Level),
		"duration_days":  plan.DurationDays,
		"price":          plan.Price,
		"original_price": plan.OriginalPrice,
		"benefits":       services.MergeVipEntitlements(plan.Level, plan.BenefitsJSON),
		"description":    plan.Description,
		"sort":           plan.Sort,
		"enabled":        plan.Enabled,
		"created_at":     plan.CreatedAt,
		"updated_at":     plan.UpdatedAt,
	}
}

func vipStatusResponse(status services.VipStatus) gin.H {
	var membership interface{}
	if status.Membership != nil {
		membership = status.Membership
	}
	var plan interface{}
	if status.Plan != nil {
		plan = vipPlanResponse(*status.Plan)
	}
	return gin.H{
		"level":        status.Level,
		"level_name":   status.LevelName,
		"is_active":    status.IsActive,
		"badge":        status.Badge,
		"badge_icon":   status.BadgeIcon,
		"expired_at":   status.ExpiredAt,
		"membership":   membership,
		"plan":         plan,
		"entitlements": status.Entitlements,
	}
}
