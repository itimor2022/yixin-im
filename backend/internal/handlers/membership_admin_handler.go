package handlers

import (
	"encoding/json"
	"net/http"
	"time"

	"gaoranim/internal/middleware"
	"gaoranim/internal/models"
	"gaoranim/pkg/response"

	"github.com/gin-gonic/gin"
	"gorm.io/gorm"
)

type MembershipAdminHandler struct {
	db *gorm.DB
}

func NewMembershipAdminHandler(db *gorm.DB) *MembershipAdminHandler {
	return &MembershipAdminHandler{db: db}
}

func (h *MembershipAdminHandler) ListPlans(c *gin.Context) {
	var plans []models.MembershipPlan
	if err := h.db.Order("sort ASC, id ASC").Find(&plans).Error; err != nil {
		response.Error(c, http.StatusInternalServerError, "获取套餐失败")
		return
	}
	response.Success(c, plans)
}

func (h *MembershipAdminHandler) SavePlan(c *gin.Context) {
	var req struct {
		ID            uint64   `json:"id"`
		Name          string   `json:"name"`
		Slug          string   `json:"slug"`
		DurationDays  int      `json:"duration_days"`
		Price         float64  `json:"price"`
		OriginalPrice float64  `json:"original_price"`
		BadgeLabel    string   `json:"badge_label"`
		BadgeColor    string   `json:"badge_color"`
		Description   string   `json:"description"`
		Features      []string `json:"features"`
		Status        int8     `json:"status"`
		Sort          int      `json:"sort"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		response.Error(c, http.StatusBadRequest, "参数错误")
		return
	}
	if req.Name == "" || req.Slug == "" || req.DurationDays <= 0 || req.Price <= 0 {
		response.Error(c, http.StatusBadRequest, "请完善套餐信息")
		return
	}
	now := time.Now()
	featuresJSON := normalizePlanFeatures(req.Features)
	if req.ID == 0 {
		plan := models.MembershipPlan{
			Name:          req.Name,
			Slug:          req.Slug,
			DurationDays:  req.DurationDays,
			Price:         req.Price,
			OriginalPrice: req.OriginalPrice,
			BadgeLabel:    req.BadgeLabel,
			BadgeColor:    req.BadgeColor,
			Description:   req.Description,
			Features:      featuresJSON,
			Status:        req.Status,
			Sort:          req.Sort,
			CreatedAt:     now,
			UpdatedAt:     now,
		}
		if plan.Status != models.MembershipPlanStatusDisabled {
			plan.Status = models.MembershipPlanStatusEnabled
		}
		if err := h.db.Create(&plan).Error; err != nil {
			response.Error(c, http.StatusInternalServerError, "创建套餐失败")
			return
		}
		response.Success(c, plan)
		return
	}
	updates := map[string]interface{}{
		"name":           req.Name,
		"slug":           req.Slug,
		"duration_days":  req.DurationDays,
		"price":          req.Price,
		"original_price": req.OriginalPrice,
		"badge_label":    req.BadgeLabel,
		"badge_color":    req.BadgeColor,
		"description":    req.Description,
		"features":       featuresJSON,
		"status":         req.Status,
		"sort":           req.Sort,
		"updated_at":     now,
	}
	if err := h.db.Model(&models.MembershipPlan{}).Where("id = ?", req.ID).Updates(updates).Error; err != nil {
		response.Error(c, http.StatusInternalServerError, "更新套餐失败")
		return
	}
	response.Success(c, gin.H{"id": req.ID})
}

func (h *MembershipAdminHandler) ListUserMemberships(c *gin.Context) {
	page := getQueryInt(c, "page", 1)
	pageSize := getQueryInt(c, "page_size", 20)
	keyword := c.Query("keyword")

	query := h.db.Model(&models.UserMembership{}).
		Joins("LEFT JOIN users ON users.id = user_memberships.user_id").
		Joins("LEFT JOIN membership_plans ON membership_plans.id = user_memberships.plan_id")

	if keyword != "" {
		like := "%" + keyword + "%"
		query = query.Where("users.username LIKE ? OR users.nickname LIKE ?", like, like)
	}

	var total int64
	query.Count(&total)

	type row struct {
		ID        uint64    `json:"id"`
		UserID    uint64    `json:"user_id"`
		Username  string    `json:"username"`
		Nickname  string    `json:"nickname"`
		Avatar    string    `json:"avatar"`
		PlanName  string    `json:"plan_name"`
		Status    string    `json:"status"`
		Source    string    `json:"source"`
		StartAt   time.Time `json:"start_at"`
		ExpireAt  time.Time `json:"expire_at"`
		CreatedAt time.Time `json:"created_at"`
	}
	var list []row
	if err := query.Select("user_memberships.id, user_memberships.user_id, users.username, users.nickname, users.avatar, membership_plans.name AS plan_name, user_memberships.status, user_memberships.source, user_memberships.start_at, user_memberships.expire_at, user_memberships.created_at").
		Order("user_memberships.created_at DESC").Offset((page - 1) * pageSize).Limit(pageSize).Scan(&list).Error; err != nil {
		response.Error(c, http.StatusInternalServerError, "获取会员列表失败")
		return
	}
	response.Success(c, gin.H{
		"list":      list,
		"total":     total,
		"page":      page,
		"page_size": pageSize,
	})
}

func (h *MembershipAdminHandler) GrantMembership(c *gin.Context) {
	userID := c.Param("user_id")
	var req struct {
		PlanID uint64 `json:"plan_id" binding:"required"`
		Days   int    `json:"days"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		response.Error(c, http.StatusBadRequest, "参数错误")
		return
	}

	var user models.User
	if err := h.db.First(&user, userID).Error; err != nil {
		response.Error(c, http.StatusNotFound, "用户不存在")
		return
	}
	var plan models.MembershipPlan
	if err := h.db.First(&plan, req.PlanID).Error; err != nil {
		response.Error(c, http.StatusNotFound, "套餐不存在")
		return
	}
	if req.Days <= 0 {
		req.Days = plan.DurationDays
	}
	now := time.Now()
	membership := models.UserMembership{
		UserID:    user.ID,
		PlanID:    plan.ID,
		Status:    models.MembershipStatusActive,
		Source:    "admin",
		AutoRenew: false,
		StartAt:   now,
		ExpireAt:  now.AddDate(0, 0, req.Days),
		CreatedAt: now,
		UpdatedAt: now,
	}
	if err := h.db.Create(&membership).Error; err != nil {
		response.Error(c, http.StatusInternalServerError, "赠送失败")
		return
	}
	_ = h.db.Model(&models.User{}).Where("id = ?", user.ID).Updates(map[string]interface{}{
		"nickname_color": "premium:#F59E0B",
		"premium_type":   plan.Slug,
	}).Error
	response.Success(c, membership)
}

func (h *MembershipAdminHandler) CancelMembership(c *gin.Context) {
	id := c.Param("id")
	now := time.Now()
	updates := map[string]interface{}{
		"status":       models.MembershipStatusCancelled,
		"cancelled_at": now,
		"updated_at":   now,
	}
	if err := h.db.Model(&models.UserMembership{}).Where("id = ?", id).Updates(updates).Error; err != nil {
		response.Error(c, http.StatusInternalServerError, "取消失败")
		return
	}
	response.Success(c, gin.H{"id": id})
}

func (h *MembershipAdminHandler) ListOrders(c *gin.Context) {
	page := getQueryInt(c, "page", 1)
	pageSize := getQueryInt(c, "page_size", 20)
	query := h.db.Model(&models.MembershipOrder{}).
		Joins("LEFT JOIN users ON users.id = membership_orders.user_id").
		Joins("LEFT JOIN membership_plans ON membership_plans.id = membership_orders.plan_id")
	var total int64
	query.Count(&total)

	type row struct {
		ID         uint64     `json:"id"`
		OrderNo    string     `json:"order_no"`
		Username   string     `json:"username"`
		Nickname   string     `json:"nickname"`
		PlanName   string     `json:"plan_name"`
		Amount     float64    `json:"amount"`
		PayChannel string     `json:"pay_channel"`
		Status     string     `json:"status"`
		PaidAt     *time.Time `json:"paid_at"`
		CreatedAt  time.Time  `json:"created_at"`
	}
	var list []row
	if err := query.Select("membership_orders.id, membership_orders.order_no, users.username, users.nickname, membership_plans.name AS plan_name, membership_orders.amount, membership_orders.pay_channel, membership_orders.status, membership_orders.paid_at, membership_orders.created_at").
		Order("membership_orders.created_at DESC").Offset((page - 1) * pageSize).Limit(pageSize).Scan(&list).Error; err != nil {
		response.Error(c, http.StatusInternalServerError, "获取订单失败")
		return
	}
	response.Success(c, gin.H{
		"list":      list,
		"total":     total,
		"page":      page,
		"page_size": pageSize,
	})
}

func (h *MembershipAdminHandler) GetSummary(c *gin.Context) {
	var totalUsers int64
	var activeUsers int64
	var totalRevenue float64

	h.db.Model(&models.UserMembership{}).Count(&totalUsers)
	h.db.Model(&models.UserMembership{}).Where("status = ? AND expire_at > ?", models.MembershipStatusActive, time.Now()).Count(&activeUsers)
	h.db.Model(&models.MembershipOrder{}).Where("status = ?", models.MembershipOrderStatusPaid).Select("COALESCE(SUM(amount),0)").Scan(&totalRevenue)

	response.Success(c, gin.H{
		"total_users":   totalUsers,
		"active_users":  activeUsers,
		"total_revenue": totalRevenue,
		"can_write":     middleware.GetAdminRole(c) != "demo_admin",
	})
}

func normalizePlanFeatures(payload any) string {
	if payload == nil {
		return "[]"
	}
	bytes, err := json.Marshal(payload)
	if err != nil {
		return "[]"
	}
	return string(bytes)
}
