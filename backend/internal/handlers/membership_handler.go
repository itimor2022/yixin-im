package handlers

import (
	"encoding/json"
	"fmt"
	"net/http"
	"time"

	"gaoranim/internal/models"
	"gaoranim/pkg/response"

	"github.com/gin-gonic/gin"
	"gorm.io/gorm"
	"gorm.io/gorm/clause"
)

type MembershipHandler struct {
	db *gorm.DB
}

func NewMembershipHandler(db *gorm.DB) *MembershipHandler {
	return &MembershipHandler{db: db}
}

func (h *MembershipHandler) getUserIDFromContext(c *gin.Context) (uint64, error) {
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

func (h *MembershipHandler) GetMyMembership(c *gin.Context) {
	userID, err := h.getUserIDFromContext(c)
	if err != nil {
		response.Error(c, http.StatusUnauthorized, "用户未登录")
		return
	}

	membership, err := h.getDisplayMembership(userID)
	if err != nil && err != gorm.ErrRecordNotFound {
		response.Error(c, http.StatusInternalServerError, "获取会员信息失败")
		return
	}

	plans, err := h.listEnabledPlans()
	if err != nil {
		response.Error(c, http.StatusInternalServerError, "获取套餐失败")
		return
	}

	response.Success(c, gin.H{
		"membership": h.buildMembershipPayload(membership),
		"plans":      plans,
	})
}

func (h *MembershipHandler) ListPlans(c *gin.Context) {
	plans, err := h.listEnabledPlans()
	if err != nil {
		response.Error(c, http.StatusInternalServerError, "获取套餐失败")
		return
	}
	response.Success(c, plans)
}

func (h *MembershipHandler) Purchase(c *gin.Context) {
	userID, err := h.getUserIDFromContext(c)
	if err != nil {
		response.Error(c, http.StatusUnauthorized, "用户未登录")
		return
	}

	var req struct {
		PlanID uint64 `json:"plan_id" binding:"required"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		response.Error(c, http.StatusBadRequest, "参数错误")
		return
	}

	tx := h.db.Begin()
	defer func() {
		if r := recover(); r != nil {
			tx.Rollback()
		}
	}()

	var plan models.MembershipPlan
	if err := tx.Where("id = ? AND status = ?", req.PlanID, models.MembershipPlanStatusEnabled).First(&plan).Error; err != nil {
		tx.Rollback()
		response.Error(c, http.StatusNotFound, "会员套餐不存在")
		return
	}

	var wallet models.Wallet
	if err := tx.Clauses(clause.Locking{Strength: "UPDATE"}).Where("user_id = ?", userID).First(&wallet).Error; err != nil {
		tx.Rollback()
		response.Error(c, http.StatusBadRequest, "钱包不存在，请先开通钱包")
		return
	}

	if wallet.Balance < plan.Price {
		tx.Rollback()
		response.Error(c, http.StatusBadRequest, "余额不足，请先充值")
		return
	}

	now := time.Now()
	order := models.MembershipOrder{
		OrderNo:    fmt.Sprintf("MP%s%04d", now.Format("20060102150405"), userID%10000),
		UserID:     userID,
		PlanID:     plan.ID,
		Amount:     plan.Price,
		PayChannel: "wallet",
		Status:     models.MembershipOrderStatusPaid,
		Remark:     "钱包购买会员",
		PaidAt:     &now,
		CreatedAt:  now,
		UpdatedAt:  now,
	}
	if err := tx.Create(&order).Error; err != nil {
		tx.Rollback()
		response.Error(c, http.StatusInternalServerError, "创建订单失败")
		return
	}

	newBalance := wallet.Balance - plan.Price
	if err := tx.Model(&wallet).Updates(map[string]interface{}{
		"balance":    gorm.Expr("balance - ?", plan.Price),
		"updated_at": now,
	}).Error; err != nil {
		tx.Rollback()
		response.Error(c, http.StatusInternalServerError, "扣款失败")
		return
	}

	remark := fmt.Sprintf("购买会员：%s", plan.Name)
	membershipOrderID := order.ID
	transaction := models.Transaction{
		UserID:       userID,
		Type:         "membership_purchase",
		Amount:       -plan.Price,
		BalanceAfter: newBalance,
		RelatedID:    order.OrderNo,
		Remark:       remark,
		CreatedAt:    now,
	}
	if err := tx.Create(&transaction).Error; err != nil {
		tx.Rollback()
		response.Error(c, http.StatusInternalServerError, "记录交易失败")
		return
	}

	var current models.UserMembership
	membershipExists := tx.Where(
		"user_id = ? AND status = ? AND start_at <= ? AND expire_at > ?",
		userID,
		models.MembershipStatusActive,
		now,
		now,
	).Order("expire_at DESC").First(&current).Error == nil
	startAt := now
	if membershipExists {
		startAt = current.ExpireAt
	}
	expireAt := startAt.AddDate(0, 0, plan.DurationDays)

	newMembership := models.UserMembership{
		UserID:    userID,
		PlanID:    plan.ID,
		Status:    models.MembershipStatusActive,
		Source:    "wallet",
		OrderID:   &membershipOrderID,
		AutoRenew: false,
		StartAt:   startAt,
		ExpireAt:  expireAt,
		CreatedAt: now,
		UpdatedAt: now,
	}
	if err := tx.Create(&newMembership).Error; err != nil {
		tx.Rollback()
		response.Error(c, http.StatusInternalServerError, "开通会员失败")
		return
	}

	if err := tx.Model(&models.User{}).Where("id = ?", userID).Updates(map[string]interface{}{
		"nickname_color": fmt.Sprintf("premium:%s", plan.BadgeColor),
		"premium_type":   plan.Slug,
	}).Error; err != nil {
		tx.Rollback()
		response.Error(c, http.StatusInternalServerError, "同步会员标识失败")
		return
	}

	if err := tx.Commit().Error; err != nil {
		response.Error(c, http.StatusInternalServerError, "购买失败")
		return
	}

	newMembership.Plan = plan
	response.Success(c, gin.H{
		"order": gin.H{
			"id":         order.ID,
			"order_no":   order.OrderNo,
			"amount":     order.Amount,
			"status":     order.Status,
			"created_at": order.CreatedAt,
		},
		"membership": h.buildMembershipPayload(&newMembership),
	})
}

func (h *MembershipHandler) getDisplayMembership(userID uint64) (*models.UserMembership, error) {
	now := time.Now()

	var membership models.UserMembership
	err := h.db.Preload("Plan").Where(
		"user_id = ? AND status = ? AND start_at <= ? AND expire_at > ?",
		userID,
		models.MembershipStatusActive,
		now,
		now,
	).Order("expire_at DESC").First(&membership).Error
	if err == nil {
		return &membership, nil
	}
	if err != nil && err != gorm.ErrRecordNotFound {
		return nil, err
	}

	var latest models.UserMembership
	err = h.db.Preload("Plan").Where("user_id = ?", userID).Order("updated_at DESC, id DESC").First(&latest).Error
	if err != nil {
		return nil, err
	}

	if latest.Status == models.MembershipStatusActive && latest.ExpireAt.Before(now) {
		_ = h.db.Model(&latest).Updates(map[string]interface{}{
			"status":     models.MembershipStatusExpired,
			"updated_at": now,
		}).Error
		latest.Status = models.MembershipStatusExpired
	}
	return &latest, nil
}

func (h *MembershipHandler) listEnabledPlans() ([]gin.H, error) {
	var plans []models.MembershipPlan
	if err := h.db.Where("status = ?", models.MembershipPlanStatusEnabled).Order("sort ASC, id ASC").Find(&plans).Error; err != nil {
		return nil, err
	}
	list := make([]gin.H, 0, len(plans))
	for _, plan := range plans {
		features := []string{}
		if plan.Features != "" {
			_ = json.Unmarshal([]byte(plan.Features), &features)
		}
		list = append(list, gin.H{
			"id":             plan.ID,
			"name":           plan.Name,
			"slug":           plan.Slug,
			"duration_days":  plan.DurationDays,
			"price":          plan.Price,
			"original_price": plan.OriginalPrice,
			"badge_label":    plan.BadgeLabel,
			"badge_color":    plan.BadgeColor,
			"description":    plan.Description,
			"features":       features,
			"status":         plan.Status,
		})
	}
	return list, nil
}

func (h *MembershipHandler) buildMembershipPayload(membership *models.UserMembership) gin.H {
	if membership == nil {
		return gin.H{
			"active": false,
		}
	}
	features := []string{}
	if membership.Plan.Features != "" {
		_ = json.Unmarshal([]byte(membership.Plan.Features), &features)
	}
	return gin.H{
		"active":       membership.Status == models.MembershipStatusActive && !membership.StartAt.After(time.Now()) && membership.ExpireAt.After(time.Now()),
		"status":       membership.Status,
		"source":       membership.Source,
		"start_at":     membership.StartAt,
		"expire_at":    membership.ExpireAt,
		"auto_renew":   membership.AutoRenew,
		"plan_id":      membership.PlanID,
		"plan_name":    membership.Plan.Name,
		"badge_label":  membership.Plan.BadgeLabel,
		"badge_color":  membership.Plan.BadgeColor,
		"premium_type": membership.Plan.Slug,
		"features":     features,
	}
}
