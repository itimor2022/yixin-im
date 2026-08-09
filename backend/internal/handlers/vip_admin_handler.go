// 文件用途：实现后端 HTTP 接口的请求处理和统一响应。
// 核心逻辑：绑定参数，校验身份与权限，调用业务服务并持久化关键状态。

package handlers

import (
	"encoding/json"
	"github.com/gin-gonic/gin"
	"gorm.io/gorm"
	"net/http"
	"strconv"
	"strings"
	"time"
	"genericim/internal/models"
	"genericim/internal/services"
	"genericim/pkg/response"
)

type VipAdminHandler struct {
	db     *gorm.DB
	vipSvc *services.VipService
}

func NewVipAdminHandler(db *gorm.DB) *VipAdminHandler {
	return &VipAdminHandler{
		db:     db,
		vipSvc: services.NewVipService(db),
	}
}

type vipPlanSaveRequest struct {
	Code          string                    `json:"code"`
	Name          string                    `json:"name"`
	Level         int8                      `json:"level"`
	DurationDays  int                       `json:"duration_days"`
	Price         float64                   `json:"price"`
	OriginalPrice float64                   `json:"original_price"`
	Benefits      *services.VipEntitlements `json:"benefits"`
	Description   string                    `json:"description"`
	Sort          int                       `json:"sort"`
	Enabled       *bool                     `json:"enabled"`
}

func (h *VipAdminHandler) ListPlans(c *gin.Context) {
	var plans []models.VipPlan
	query := h.db.Model(&models.VipPlan{})
	if enabled := strings.TrimSpace(c.Query("enabled")); enabled != "" {
		query = query.Where("enabled = ?", enabled == "true" || enabled == "1")
	}
	if err := query.Order("sort ASC, id ASC").Find(&plans).Error; err != nil {
		response.ServerError(c, "获取会员套餐失败")
		return
	}
	items := make([]gin.H, 0, len(plans))
	for _, plan := range plans {
		items = append(items, vipPlanResponse(plan))
	}
	response.Success(c, items)
}

func (h *VipAdminHandler) GetFreeEntitlements(c *gin.Context) {
	response.Success(c, h.vipSvc.FreeEntitlements())
}

func (h *VipAdminHandler) SaveFreeEntitlements(c *gin.Context) {
	var req services.VipEntitlements
	if err := c.ShouldBindJSON(&req); err != nil {
		response.BadRequest(c, "参数错误")
		return
	}
	entitlements, err := h.vipSvc.SaveFreeEntitlements(req)
	if err != nil {
		response.ServerError(c, "保存普通用户额度失败")
		return
	}
	response.Success(c, entitlements)
}

func (h *VipAdminHandler) CreatePlan(c *gin.Context) {
	var req vipPlanSaveRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		response.BadRequest(c, "参数错误")
		return
	}
	plan, ok := h.buildPlanFromRequest(c, req, nil)
	if !ok {
		return
	}
	if err := h.db.Create(&plan).Error; err != nil {
		response.Error(c, http.StatusBadRequest, "保存会员套餐失败")
		return
	}
	response.Success(c, vipPlanResponse(plan))
}

func (h *VipAdminHandler) UpdatePlan(c *gin.Context) {
	id, err := strconv.ParseUint(c.Param("id"), 10, 64)
	if err != nil || id == 0 {
		response.BadRequest(c, "参数错误")
		return
	}
	var plan models.VipPlan
	if err := h.db.First(&plan, id).Error; err != nil {
		response.NotFound(c, "会员套餐不存在")
		return
	}
	var req vipPlanSaveRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		response.BadRequest(c, "参数错误")
		return
	}
	updated, ok := h.buildPlanFromRequest(c, req, &plan)
	if !ok {
		return
	}
	if err := h.db.Save(&updated).Error; err != nil {
		response.Error(c, http.StatusBadRequest, "保存会员套餐失败")
		return
	}
	response.Success(c, vipPlanResponse(updated))
}

func (h *VipAdminHandler) ListUsers(c *gin.Context) {
	page := getQueryInt(c, "page", 1)
	pageSize := getQueryInt(c, "page_size", 20)
	if pageSize > 100 {
		pageSize = 100
	}
	keyword := strings.TrimSpace(c.Query("keyword"))
	level := strings.TrimSpace(c.Query("level"))
	status := strings.TrimSpace(c.Query("status"))
	query := h.db.Table("users u").
		Select(`u.id, u.uuid, u.username, u.nickname, u.avatar, u.phone, m.level, m.status AS vip_status, m.expired_at, m.plan_id, p.name AS plan_name`)
	query = query.Joins("LEFT JOIN user_vip_memberships m ON m.user_id = u.id")
	query = query.Joins("LEFT JOIN vip_plans p ON p.id = m.plan_id")
	if keyword != "" {
		like := "%" + keyword + "%"
		query = query.Where("u.uuid LIKE ? OR u.username LIKE ? OR u.nickname LIKE ? OR u.phone LIKE ?", like, like, like, like)
	}
	if level != "" {
		query = query.Where("COALESCE(m.level, 0) = ?", level)
	}
	if status != "" {
		if status == "none" {
			query = query.Where("m.id IS NULL")
		} else {
			query = query.Where("m.status = ?", status)
		}
	}

	var total int64
	query.Count(&total)

	var rows []struct {
		ID        uint64     `json:"id"`
		UUID      string     `json:"uuid"`
		Username  string     `json:"username"`
		Nickname  string     `json:"nickname"`
		Avatar    string     `json:"avatar"`
		Phone     *string    `json:"phone"`
		Level     *int8      `json:"level"`
		VipStatus *string    `json:"vip_status"`
		ExpiredAt *time.Time `json:"expired_at"`
		PlanID    *uint64    `json:"plan_id"`
		PlanName  *string    `json:"plan_name"`
	}
	if err := query.Order("u.id DESC").
		Offset((page - 1) * pageSize).
		Limit(pageSize).
		Scan(&rows).Error; err != nil {
		response.ServerError(c, "获取会员用户失败")
		return
	}
	items := make([]gin.H, 0, len(rows))
	now := time.Now()
	for _, row := range rows {
		lv := int8(models.VipLevelFree)
		if row.Level != nil {
			lv = *row.Level
		}
		vipStatus := ""
		if row.VipStatus != nil {
			vipStatus = *row.VipStatus
		}
		isActive := vipStatus == models.VipMembershipStatusActive && row.ExpiredAt != nil && row.ExpiredAt.After(now)
		items = append(items, gin.H{
			"id":         row.ID,
			"uuid":       row.UUID,
			"username":   row.Username,
			"nickname":   row.Nickname,
			"avatar":     row.Avatar,
			"phone":      row.Phone,
			"level":      lv,
			"level_name": services.LevelName(lv),
			"vip_status": vipStatus,
			"is_active":  isActive,
			"expired_at": row.ExpiredAt,
			"plan_id":    row.PlanID,
			"plan_name":  row.PlanName,
		})
	}
	response.Success(c, gin.H{
		"list":      items,
		"total":     total,
		"page":      page,
		"page_size": pageSize,
	})
}

func (h *VipAdminHandler) GrantUser(c *gin.Context) {
	user, ok := h.resolveUser(c.Param("user_id"))
	if !ok {
		response.NotFound(c, "用户不存在")
		return
	}
	var req struct {
		PlanID uint64 `json:"plan_id" binding:"required"`
		Days   int    `json:"days"`
		Remark string `json:"remark"`
	}
	if err := c.ShouldBindJSON(&req); err != nil || req.PlanID == 0 {
		response.BadRequest(c, "请选择会员套餐")
		return
	}
	status, err := h.vipSvc.GrantMembership(user.ID, req.PlanID, req.Days, strings.TrimSpace(req.Remark))
	if err != nil {
		response.Error(c, http.StatusBadRequest, err.Error())
		return
	}
	response.Success(c, vipStatusResponse(status))
}

func (h *VipAdminHandler) CancelUser(c *gin.Context) {
	user, ok := h.resolveUser(c.Param("user_id"))
	if !ok {
		response.NotFound(c, "用户不存在")
		return
	}
	var req struct {
		Remark string `json:"remark"`
	}
	_ = c.ShouldBindJSON(&req)
	status, err := h.vipSvc.CancelMembership(user.ID, strings.TrimSpace(req.Remark))
	if err != nil {
		response.Error(c, http.StatusBadRequest, "取消会员失败")
		return
	}
	response.Success(c, vipStatusResponse(status))
}

func (h *VipAdminHandler) FreezeUser(c *gin.Context) {
	user, ok := h.resolveUser(c.Param("user_id"))
	if !ok {
		response.NotFound(c, "用户不存在")
		return
	}
	var req struct {
		Remark string `json:"remark"`
	}
	_ = c.ShouldBindJSON(&req)
	status, err := h.vipSvc.FreezeMembership(user.ID, strings.TrimSpace(req.Remark))
	if err != nil {
		response.Error(c, http.StatusBadRequest, err.Error())
		return
	}
	response.Success(c, vipStatusResponse(status))
}

func (h *VipAdminHandler) UnfreezeUser(c *gin.Context) {
	user, ok := h.resolveUser(c.Param("user_id"))
	if !ok {
		response.NotFound(c, "用户不存在")
		return
	}
	var req struct {
		Remark string `json:"remark"`
	}
	_ = c.ShouldBindJSON(&req)
	status, err := h.vipSvc.UnfreezeMembership(user.ID, strings.TrimSpace(req.Remark))
	if err != nil {
		response.Error(c, http.StatusBadRequest, err.Error())
		return
	}
	response.Success(c, vipStatusResponse(status))
}

func (h *VipAdminHandler) ListOrders(c *gin.Context) {
	page := getQueryInt(c, "page", 1)
	pageSize := getQueryInt(c, "page_size", 20)
	if pageSize > 100 {
		pageSize = 100
	}
	status := strings.TrimSpace(c.Query("status"))
	keyword := strings.TrimSpace(c.Query("keyword"))
	query := h.db.Table("vip_orders o").
		Select(`o.*, u.uuid AS user_uuid, u.username, u.nickname, p.name AS plan_name, p.level AS plan_level`).
		Joins("LEFT JOIN users u ON u.id = o.user_id").
		Joins("LEFT JOIN vip_plans p ON p.id = o.plan_id")
	if status != "" {
		query = query.Where("o.status = ?", status)
	}
	if keyword != "" {
		like := "%" + keyword + "%"
		query = query.Where("o.order_no LIKE ? OR u.uuid LIKE ? OR u.username LIKE ? OR u.nickname LIKE ?", like, like, like, like)
	}

	var total int64
	query.Count(&total)

	var rows []struct {
		models.VipOrder
		UserUUID  string `json:"user_uuid"`
		Username  string `json:"username"`
		Nickname  string `json:"nickname"`
		PlanName  string `json:"plan_name"`
		PlanLevel int8   `json:"plan_level"`
	}
	if err := query.Order("o.created_at DESC").
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
			"user_id":        row.UserID,
			"user_uuid":      row.UserUUID,
			"username":       row.Username,
			"nickname":       row.Nickname,
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

func (h *VipAdminHandler) buildPlanFromRequest(c *gin.Context, req vipPlanSaveRequest, existing *models.VipPlan) (models.VipPlan, bool) {
	now := time.Now()
	plan := models.VipPlan{CreatedAt: now}
	if existing != nil {
		plan = *existing
	}
	code := strings.TrimSpace(req.Code)
	name := strings.TrimSpace(req.Name)
	if existing == nil && code == "" {
		response.BadRequest(c, "套餐编码不能为空")
		return plan, false
	}
	if code != "" {
		plan.Code = code
	}
	if name == "" {
		response.BadRequest(c, "套餐名称不能为空")
		return plan, false
	}
	level := services.NormalizeVipLevel(req.Level)
	if level == models.VipLevelFree {
		response.BadRequest(c, "请选择 VIP 或 SVIP 等级")
		return plan, false
	}
	if req.DurationDays <= 0 {
		response.BadRequest(c, "有效期必须大于 0 天")
		return plan, false
	}
	if req.Price < 0 || req.OriginalPrice < 0 {
		response.BadRequest(c, "价格不能小于 0")
		return plan, false
	}
	benefits := services.DefaultVipEntitlements(level)
	if req.Benefits != nil {
		benefits = *req.Benefits
		benefits.Badge = strings.TrimSpace(benefits.Badge)
		benefits.BadgeIcon = strings.TrimSpace(benefits.BadgeIcon)
		if benefits.Badge == "" {
			benefits.Badge = services.LevelName(level)
		}
	}
	benefitsJSON, _ := json.Marshal(benefits)
	enabled := true
	if existing != nil {
		enabled = existing.Enabled
	}
	if req.Enabled != nil {
		enabled = *req.Enabled
	}
	plan.Name = name
	plan.Level = level
	plan.DurationDays = req.DurationDays
	plan.Price = req.Price
	plan.OriginalPrice = req.OriginalPrice
	plan.BenefitsJSON = string(benefitsJSON)
	plan.Description = strings.TrimSpace(req.Description)
	plan.Sort = req.Sort
	plan.Enabled = enabled
	plan.UpdatedAt = now
	return plan, true
}

func (h *VipAdminHandler) resolveUser(value string) (models.User, bool) {
	var user models.User
	value = strings.TrimSpace(value)
	if value == "" {
		return user, false
	}
	query := h.db.Model(&models.User{})
	if id, err := strconv.ParseUint(value, 10, 64); err == nil && id > 0 {
		if err := query.Where("id = ? OR short_id = ?", id, id).First(&user).Error; err == nil {
			return user, true
		}
	}
	if err := query.Where("uuid = ? OR username = ? OR phone = ?", value, value, value).First(&user).Error; err != nil {
		return user, false
	}
	return user, true
}
