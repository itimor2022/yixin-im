// 文件用途：实现后端 HTTP 接口的请求处理和统一响应。
// 核心逻辑：绑定参数，校验身份与权限，调用业务服务并持久化关键状态。

package handlers

import (
	"encoding/base64"
	"encoding/json"
	"errors"
	"fmt"
	"github.com/gin-gonic/gin"
	"gorm.io/gorm"
	"gorm.io/gorm/clause"
	"net/http"
	"strconv"
	"strings"
	"time"
	"genericim/internal/config"
	"genericim/internal/middleware"
	"genericim/internal/models"
	"genericim/internal/services"
	"genericim/pkg/response"
)

// adminTransactionCursor 钱包后台查看用户流水时使用的游标，与客户端接口同结构。
type adminTransactionCursor struct {
	CreatedAt string `json:"t"`
	ID        uint64 `json:"i"`
}

func encodeAdminTransactionCursor(tx models.Transaction) string {
	payload, err := json.Marshal(adminTransactionCursor{
		CreatedAt: tx.CreatedAt.UTC().Format(time.RFC3339Nano),
		ID:        tx.ID,
	})
	if err != nil {
		return ""
	}
	return base64.RawURLEncoding.EncodeToString(payload)
}

func decodeAdminTransactionCursor(raw string) (time.Time, uint64, error) {
	data, err := base64.RawURLEncoding.DecodeString(strings.TrimSpace(raw))
	if err != nil {
		return time.Time{}, 0, err
	}
	var cursor adminTransactionCursor
	if err := json.Unmarshal(data, &cursor); err != nil {
		return time.Time{}, 0, err
	}
	createdAt, err := time.Parse(time.RFC3339Nano, cursor.CreatedAt)
	if err != nil {
		return time.Time{}, 0, err
	}
	if cursor.ID == 0 {
		return time.Time{}, 0, gorm.ErrInvalidData
	}
	return createdAt, cursor.ID, nil
}

type WalletAdminHandler struct {
	db     *gorm.DB
	cfg    *config.Config
	paySvc *services.OnlinePaymentService
}

func NewWalletAdminHandler(db *gorm.DB, cfg *config.Config, paySvc *services.OnlinePaymentService) *WalletAdminHandler {
	return &WalletAdminHandler{db: db, cfg: cfg, paySvc: paySvc}
}

// ListWithdrawRequests 获取提现申请列表
func (h *WalletAdminHandler) ListWithdrawRequests(c *gin.Context) {
	page := getQueryInt(c, "page", 1)
	pageSize := getQueryInt(c, "page_size", 20)
	status := c.Query("status")
	query := h.db.Model(&models.WithdrawRequest{})
	if status != "" {
		query = query.Where("status = ?", status)
	}

	var total int64
	query.Count(&total)

	var requests []models.WithdrawRequest
	query.Order("created_at DESC").
		Offset((page - 1) * pageSize).
		Limit(pageSize).
		Find(&requests)

	// 获取用户和方式信息
	result := make([]gin.H, len(requests))
	for i, req := range requests {
		var user models.User
		h.db.First(&user, req.UserID)

		var method models.WithdrawMethod
		h.db.First(&method, req.MethodID)
		item := gin.H{
			"id":            req.ID,
			"user_id":       user.UUID,
			"user_name":     user.Nickname,
			"username":      user.Username,
			"avatar":        user.Avatar,
			"method_name":   method.Name,
			"amount":        req.Amount,
			"fee":           req.Fee,
			"actual_amount": req.ActualAmount,
			"form_data":     req.FormData,
			"status":        req.Status,
			"remark":        req.Remark,
			"created_at":    req.CreatedAt,
			"reviewed_at":   req.ReviewedAt,
		}
		result[i] = item
	}
	response.Success(c, gin.H{
		"list":      result,
		"total":     total,
		"page":      page,
		"page_size": pageSize,
	})
}

// ReviewWithdrawRequest 审核提现申请
func (h *WalletAdminHandler) ReviewWithdrawRequest(c *gin.Context) {

	requestID := c.Param("id")

	var req struct {
		Action string `json:"action" binding:"required,oneof=approve reject complete"`
		Remark string `json:"remark"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		response.Error(c, http.StatusBadRequest, "参数错误")
		return
	}
	adminID := middleware.GetAdminID(c)
	now := time.Now()
	tx := h.db.Begin()
	defer func() {
		if r := recover(); r != nil {
			tx.Rollback()
		}
	}()

	//

	var withdrawReq models.WithdrawRequest
	if err := tx.Clauses(clause.Locking{Strength: "UPDATE"}).First(&withdrawReq, requestID).Error; err != nil {
		tx.Rollback()
		response.Error(c, http.StatusNotFound, "申请不存在")
		return
	}

	switch req.Action {
	case "approve":
		if withdrawReq.Status != models.WithdrawStatusPending {
			tx.Rollback()
			response.Error(c, http.StatusBadRequest, "申请已处理")
			return
		}
		withdrawReq.Status = models.WithdrawStatusApproved
		withdrawReq.ReviewedBy = &adminID
		withdrawReq.ReviewedAt = &now
		withdrawReq.Remark = req.Remark

	case "reject":
		if withdrawReq.Status != models.WithdrawStatusPending {
			tx.Rollback()
			response.Error(c, http.StatusBadRequest, "申请已处理")
			return
		}
		withdrawReq.Status = models.WithdrawStatusRejected
		withdrawReq.ReviewedBy = &adminID
		withdrawReq.ReviewedAt = &now
		withdrawReq.Remark = req.Remark

		// FOR UPDATE 锁定钱包行，退还冻结金额
		var wallet models.Wallet
		if err := tx.Clauses(clause.Locking{Strength: "UPDATE"}).
			Where("user_id = ?", withdrawReq.UserID).First(&wallet).Error; err != nil {
			tx.Rollback()
			response.Error(c, http.StatusInternalServerError, "用户钱包不存在")
			return
		}
		if wallet.FrozenBalance < withdrawReq.Amount {
			tx.Rollback()
			response.Error(c, http.StatusBadRequest, "冻结余额不足")
			return
		}
		newBalance := wallet.Balance + withdrawReq.Amount
		if err := tx.Model(&wallet).Updates(map[string]interface{}{
			"frozen_balance": gorm.Expr("frozen_balance - ?", withdrawReq.Amount),
			"balance":        gorm.Expr("balance + ?", withdrawReq.Amount),
			"updated_at":     time.Now(),
		}).Error; err != nil {
			tx.Rollback()
			response.Error(c, http.StatusInternalServerError, "退还余额失败")
			return
		}
		rejectRemark := "提现被拒绝-退回"
		if req.Remark != "" {
			rejectRemark += "：" + req.Remark
		}
		if err := tx.Create(&models.Transaction{
			UserID: withdrawReq.UserID, Type: models.TransactionTypeRefund,
			Amount: withdrawReq.Amount, BalanceAfter: newBalance,
			Remark: rejectRemark, CreatedAt: time.Now(),
		}).Error; err != nil {
			tx.Rollback()
			response.Error(c, http.StatusInternalServerError, "记录交易失败")
			return
		}

	case "complete":
		if withdrawReq.Status != models.WithdrawStatusApproved {
			tx.Rollback()
			response.Error(c, http.StatusBadRequest, "请先审核通过")
			return
		}
		withdrawReq.Status = models.WithdrawStatusCompleted
		withdrawReq.Remark = req.Remark

		// FOR UPDATE 锁定钱包行，扣除冻结金额
		var wallet models.Wallet
		if err := tx.Clauses(clause.Locking{Strength: "UPDATE"}).
			Where("user_id = ?", withdrawReq.UserID).First(&wallet).Error; err != nil {
			tx.Rollback()
			response.Error(c, http.StatusInternalServerError, "用户钱包不存在")
			return
		}
		if wallet.FrozenBalance < withdrawReq.Amount {
			tx.Rollback()
			response.Error(c, http.StatusBadRequest, "冻结余额不足")
			return
		}
		if err := tx.Model(&wallet).Updates(map[string]interface{}{
			"frozen_balance": gorm.Expr("frozen_balance - ?", withdrawReq.Amount),
			"updated_at":     time.Now(),
		}).Error; err != nil {
			tx.Rollback()
			response.Error(c, http.StatusInternalServerError, "扣除冻结余额失败")
			return
		}
		if err := tx.Create(&models.Transaction{
			UserID: withdrawReq.UserID, Type: models.TransactionTypeWithdraw,
			Amount: -withdrawReq.Amount, BalanceAfter: wallet.Balance,
			Remark: "提现成功", CreatedAt: time.Now(),
		}).Error; err != nil {
			tx.Rollback()
			response.Error(c, http.StatusInternalServerError, "记录交易失败")
			return
		}
	}
	withdrawReq.UpdatedAt = now
	if err := tx.Save(&withdrawReq).Error; err != nil {
		tx.Rollback()
		response.Error(c, http.StatusInternalServerError, "操作失败")
		return
	}
	if err := tx.Commit().Error; err != nil {
		response.Error(c, http.StatusInternalServerError, "操作失败")
		return
	}
	response.Success(c, gin.H{"message": "操作成功"})
}

// GetWithdrawStats 获取提现统计
func (h *WalletAdminHandler) GetWithdrawStats(c *gin.Context) {
	var pendingCount, approvedCount, completedCount, rejectedCount int64
	var totalAmount float64

	h.db.Model(&models.WithdrawRequest{}).Where("status = ?", models.WithdrawStatusPending).Count(&pendingCount)
	h.db.Model(&models.WithdrawRequest{}).Where("status = ?", models.WithdrawStatusApproved).Count(&approvedCount)
	h.db.Model(&models.WithdrawRequest{}).Where("status = ?", models.WithdrawStatusCompleted).Count(&completedCount)
	h.db.Model(&models.WithdrawRequest{}).Where("status = ?", models.WithdrawStatusRejected).Count(&rejectedCount)
	h.db.Model(&models.WithdrawRequest{}).Where("status = ?", models.WithdrawStatusCompleted).Select("COALESCE(SUM(actual_amount), 0)").Scan(&totalAmount)
	response.Success(c, gin.H{
		"pending_count":   pendingCount,
		"approved_count":  approvedCount,
		"completed_count": completedCount,
		"rejected_count":  rejectedCount,
		"total_amount":    totalAmount,
	})
}

// ListWithdrawMethods 获取提现方式列表（管理端）
func (h *WalletAdminHandler) ListWithdrawMethods(c *gin.Context) {
	var methods []models.WithdrawMethod
	h.db.Unscoped().Order("sort ASC").Find(&methods)
	response.Success(c, methods)
}

// CreateWithdrawMethod 创建提现方式
func (h *WalletAdminHandler) CreateWithdrawMethod(c *gin.Context) {
	var req struct {
		Name      string  `json:"name" binding:"required"`
		Icon      string  `json:"icon"`
		Fields    string  `json:"fields" binding:"required"`
		MinAmount float64 `json:"min_amount"`
		MaxAmount float64 `json:"max_amount"`
		Fee       float64 `json:"fee"`
		Sort      int     `json:"sort"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		response.Error(c, http.StatusBadRequest, "参数错误")
		return
	}
	method := models.WithdrawMethod{
		Name:      req.Name,
		Icon:      req.Icon,
		Fields:    req.Fields,
		MinAmount: req.MinAmount,
		MaxAmount: req.MaxAmount,
		Fee:       req.Fee,
		Sort:      req.Sort,
		Status:    1,
		CreatedAt: time.Now(),
		UpdatedAt: time.Now(),
	}
	if err := h.db.Create(&method).Error; err != nil {
		response.Error(c, http.StatusInternalServerError, "创建失败")
		return
	}
	response.Success(c, method)
}

// UpdateWithdrawMethod 更新提现方式
func (h *WalletAdminHandler) UpdateWithdrawMethod(c *gin.Context) {
	methodID := c.Param("id")

	var method models.WithdrawMethod
	if err := h.db.First(&method, methodID).Error; err != nil {
		response.Error(c, http.StatusNotFound, "提现方式不存在")
		return
	}

	var req struct {
		Name      *string  `json:"name"`
		Icon      *string  `json:"icon"`
		Fields    *string  `json:"fields"`
		MinAmount *float64 `json:"min_amount"`
		MaxAmount *float64 `json:"max_amount"`
		Fee       *float64 `json:"fee"`
		Sort      *int     `json:"sort"`
		Status    *int8    `json:"status"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		response.Error(c, http.StatusBadRequest, "参数错误")
		return
	}
	updates := map[string]interface{}{"updated_at": time.Now()}
	if req.Name != nil {
		updates["name"] = *req.Name
	}
	if req.Icon != nil {
		updates["icon"] = *req.Icon
	}
	if req.Fields != nil {
		updates["fields"] = *req.Fields
	}
	if req.MinAmount != nil {
		updates["min_amount"] = *req.MinAmount
	}
	if req.MaxAmount != nil {
		updates["max_amount"] = *req.MaxAmount
	}
	if req.Fee != nil {
		updates["fee"] = *req.Fee
	}
	if req.Sort != nil {
		updates["sort"] = *req.Sort
	}
	if req.Status != nil {
		updates["status"] = *req.Status
	}
	if err := h.db.Model(&method).Updates(updates).Error; err != nil {
		response.Error(c, http.StatusInternalServerError, "更新失败")
		return
	}
	h.db.First(&method, methodID)
	response.Success(c, method)
}

// DeleteWithdrawMethod 删除提现方式
func (h *WalletAdminHandler) DeleteWithdrawMethod(c *gin.Context) {
	methodID := c.Param("id")
	if err := h.db.Delete(&models.WithdrawMethod{}, methodID).Error; err != nil {
		response.Error(c, http.StatusInternalServerError, "删除失败")
		return
	}
	response.Success(c, gin.H{"message": "删除成功"})
}

// ListUserWallets 获取用户钱包列表
func (h *WalletAdminHandler) ListUserWallets(c *gin.Context) {
	page := getQueryInt(c, "page", 1)
	pageSize := getQueryInt(c, "page_size", 20)
	keyword := c.Query("keyword") // 用户名/昵称搜索

	// 查询有钱包的用户
	query := h.db.Model(&models.Wallet{})

	// 如果有关键词，先查找匹配的用户ID
	var userIDs []uint64
	if keyword != "" {
		h.db.Model(&models.User{}).
			Where("username LIKE ? OR nickname LIKE ?", "%"+keyword+"%", "%"+keyword+"%").
			Pluck("id", &userIDs)
		if len(userIDs) == 0 {
			response.Success(c, gin.H{
				"list":      []gin.H{},
				"total":     0,
				"page":      page,
				"page_size": pageSize,
			})
			return
		}
		query = query.Where("user_id IN ?", userIDs)
	}

	// 排除 user_id 为 0 的无效记录
	query = query.Where("user_id > 0")

	var total int64
	query.Count(&total)

	var wallets []models.Wallet
	query.Order("created_at DESC").
		Offset((page - 1) * pageSize).
		Limit(pageSize).
		Find(&wallets)
	result := make([]gin.H, 0, len(wallets))
	for _, wallet := range wallets {
		var user models.User
		if err := h.db.First(&user, wallet.UserID).Error; err != nil {
			// 跳过找不到用户的记录
			continue
		}

		result = append(result, gin.H{
			"user_id":          user.UUID,
			"user_name":        user.Nickname,
			"username":         user.Username,
			"avatar":           user.Avatar,
			"balance":          wallet.Balance,
			"frozen_balance":   wallet.FrozenBalance,
			"has_pay_password": wallet.HasPayPassword(),
			"is_locked":        wallet.IsLocked,
			"created_at":       wallet.CreatedAt,
		})
	}
	response.Success(c, gin.H{
		"list":      result,
		"total":     total,
		"page":      page,
		"page_size": pageSize,
	})
}

// GetUserWallet 获取用户钱包信息（通过用户名或UUID）
func (h *WalletAdminHandler) GetUserWallet(c *gin.Context) {
	userID := c.Param("user_id")

	// 查找用户（支持UUID或用户名）
	var user models.User
	if err := h.db.Where("uuid = ? OR username = ?", userID, userID).First(&user).Error; err != nil {
		response.Error(c, http.StatusNotFound, "用户不存在")
		return
	}

	// 查找钱包
	var wallet models.Wallet
	if err := h.db.Where("user_id = ?", user.ID).First(&wallet).Error; err != nil {
		// 如果钱包不存在，返回空钱包信息
		response.Success(c, gin.H{
			"user_id":          user.UUID,
			"user_name":        user.Nickname,
			"username":         user.Username,
			"avatar":           user.Avatar,
			"balance":          0,
			"frozen_balance":   0,
			"has_pay_password": false,
			"is_locked":        false,
		})
		return
	}
	response.Success(c, gin.H{
		"user_id":          user.UUID,
		"user_name":        user.Nickname,
		"username":         user.Username,
		"avatar":           user.Avatar,
		"balance":          wallet.Balance,
		"frozen_balance":   wallet.FrozenBalance,
		"has_pay_password": wallet.HasPayPassword(),
		"is_locked":        wallet.IsLocked,
		"created_at":       wallet.CreatedAt,
	})
}

// UpdateUserBalance 修改用户余额
func (h *WalletAdminHandler) UpdateUserBalance(c *gin.Context) {
	userID := c.Param("user_id")

	var req struct {
		Amount float64 `json:"amount" binding:"required"` // 正数为增加，负数为扣减
		Remark string  `json:"remark"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		response.Error(c, http.StatusBadRequest, "参数错误")
		return
	}
	if req.Amount == 0 {
		response.Error(c, http.StatusBadRequest, "调整金额不能为0")
		return
	}

	// 查找用户
	var user models.User
	if err := h.db.Where("uuid = ?", userID).First(&user).Error; err != nil {
		response.Error(c, http.StatusNotFound, "用户不存在")
		return
	}

	//

	tx := h.db.Begin()
	defer func() {
		if r := recover(); r != nil {
			tx.Rollback()
		}
	}()

	// FOR UPDATE 锁定钱包行
	var wallet models.Wallet
	if err := tx.Clauses(clause.Locking{Strength: "UPDATE"}).
		Where("user_id = ?", user.ID).First(&wallet).Error; err != nil {
		if !errors.Is(err, gorm.ErrRecordNotFound) {
			tx.Rollback()
			response.Error(c, http.StatusInternalServerError, "获取钱包失败")
			return
		}
		wallet = models.Wallet{
			UserID:    user.ID,
			Balance:   0,
			CreatedAt: time.Now(),
			UpdatedAt: time.Now(),
		}
		if err := tx.Create(&wallet).Error; err != nil {
			tx.Rollback()
			response.Error(c, http.StatusInternalServerError, "创建钱包失败")
			return
		}
	}

	// 锁定后检查扣减是否足够
	if req.Amount < 0 && wallet.Balance+req.Amount < 0 {
		tx.Rollback()
		response.Error(c, http.StatusBadRequest, "余额不足")
		return
	}

	// 原子更新余额
	newBalance := wallet.Balance + req.Amount
	if err := tx.Model(&wallet).Updates(map[string]interface{}{
		"balance":    gorm.Expr("balance + ?", req.Amount),
		"updated_at": time.Now(),
	}).Error; err != nil {
		tx.Rollback()
		response.Error(c, http.StatusInternalServerError, "更新失败")
		return
	}

	// 记录交易 — 使用专用管理员操作类型
	txType := "admin_recharge"
	remark := "管理员充值"
	if req.Amount < 0 {
		txType = "admin_deduct"
		remark = "管理员扣减"
	}
	if req.Remark != "" {
		remark = req.Remark
	}
	transaction := models.Transaction{
		UserID:       user.ID,
		Type:         txType,
		Amount:       req.Amount,
		BalanceAfter: newBalance,
		Remark:       remark,
		CreatedAt:    time.Now(),
	}
	if err := tx.Create(&transaction).Error; err != nil {
		tx.Rollback()
		response.Error(c, http.StatusInternalServerError, "记录交易失败")
		return
	}
	if err := tx.Commit().Error; err != nil {
		response.Error(c, http.StatusInternalServerError, "操作失败")
		return
	}
	response.Success(c, gin.H{
		"message":     "操作成功",
		"new_balance": newBalance,
	})
}

// ResetUserPayPassword 重置用户支付密码
func (h *WalletAdminHandler) ResetUserPayPassword(c *gin.Context) {
	userID := c.Param("user_id")

	var req struct {
		NewPassword string `json:"new_password" binding:"required,len=6"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		response.Error(c, http.StatusBadRequest, "请输入6位数字密码")
		return
	}

	// 查找用户
	var user models.User
	if err := h.db.Where("uuid = ?", userID).First(&user).Error; err != nil {
		response.Error(c, http.StatusNotFound, "用户不存在")
		return
	}

	// 查找或创建钱包
	var wallet models.Wallet
	if err := h.db.Where("user_id = ?", user.ID).First(&wallet).Error; err != nil {
		wallet = models.Wallet{
			UserID:    user.ID,
			Balance:   0,
			CreatedAt: time.Now(),
			UpdatedAt: time.Now(),
		}
		h.db.Create(&wallet)
	}

	// 设置新密码
	if err := wallet.SetPayPassword(req.NewPassword); err != nil {
		response.Error(c, http.StatusInternalServerError, "设置密码失败")
		return
	}
	wallet.UpdatedAt = time.Now()
	if err := h.db.Save(&wallet).Error; err != nil {
		response.Error(c, http.StatusInternalServerError, "保存失败")
		return
	}
	response.Success(c, gin.H{"message": "支付密码重置成功"})
}

// ClearUserPayPassword 清除用户支付密码
func (h *WalletAdminHandler) ClearUserPayPassword(c *gin.Context) {
	userID := c.Param("user_id")

	// 查找用户
	var user models.User
	if err := h.db.Where("uuid = ?", userID).First(&user).Error; err != nil {
		response.Error(c, http.StatusNotFound, "用户不存在")
		return
	}

	// 查找钱包
	var wallet models.Wallet
	if err := h.db.Where("user_id = ?", user.ID).First(&wallet).Error; err != nil {
		response.Error(c, http.StatusNotFound, "用户钱包不存在")
		return
	}

	// 清除密码
	wallet.PayPassword = ""
	wallet.UpdatedAt = time.Now()
	if err := h.db.Save(&wallet).Error; err != nil {
		response.Error(c, http.StatusInternalServerError, "操作失败")
		return
	}
	response.Success(c, gin.H{"message": "支付密码已清除"})
}

// GetUserTransactions 获取用户交易记录
func (h *WalletAdminHandler) GetUserTransactions(c *gin.Context) {
	userID := c.Param("user_id")
	rawPage, hasPage := c.GetQuery("page")
	page := 1
	if rawPage != "" {
		if parsed, err := strconv.Atoi(rawPage); err == nil && parsed > 0 {
			page = parsed
		}
	}
	pageSize := getQueryInt(c, "page_size", 20)
	if pageSize <= 0 {
		pageSize = 20
	}
	if pageSize > 100 {
		pageSize = 100
	}
	cursorToken := strings.TrimSpace(c.Query("cursor"))
	txType := c.Query("type")
	// 后台表格优先用 cursor 翻页；没传 page 也走游标，避免深分页。
	useCursor := cursorToken != "" || !hasPage
	var cursorCreatedAt time.Time
	var cursorID uint64
	if cursorToken != "" {
		var err error
		cursorCreatedAt, cursorID, err = decodeAdminTransactionCursor(cursorToken)
		if err != nil || cursorID == 0 {
			response.BadRequest(c, "无效游标")
			return
		}
	}

	// 查找用户
	var user models.User
	if err := h.db.Where("uuid = ?", userID).First(&user).Error; err != nil {
		response.Error(c, http.StatusNotFound, "用户不存在")
		return
	}
	query := h.db.Model(&models.Transaction{}).Where("user_id = ?", user.ID)
	if txType != "" {
		query = query.Where("type = ?", txType)
	}
	if useCursor && cursorToken != "" {
		// 游标条件必须与 (created_at, id) 降序排序严格对应，避免同时间落库的交易重复或遗漏。
		query = query.Where("(created_at < ? OR (created_at = ? AND id < ?))", cursorCreatedAt, cursorCreatedAt, cursorID)
	}

	limit := pageSize
	if useCursor {
		limit = pageSize + 1
	}
	var transactions []models.Transaction
	query.Order("created_at DESC, id DESC").
		Limit(limit).
		Find(&transactions)
	hasMore := false
	if useCursor && len(transactions) > pageSize {
		hasMore = true
		transactions = transactions[:pageSize]
	}
	nextCursor := ""
	if hasMore && len(transactions) > 0 {
		nextCursor = encodeAdminTransactionCursor(transactions[len(transactions)-1])
	}
	// 旧 page 模式保留 OFFSET；后台分页器仍在用。
	if !useCursor && page > 1 {
		offset := (page - 1) * pageSize
		query = query.Offset(offset)
		if err := query.Find(&transactions).Error; err != nil {
			response.Error(c, http.StatusInternalServerError, "查询失败")
			return
		}
	}

	// 获取关联用户信息
	result := make([]gin.H, len(transactions))
	for i, tx := range transactions {
		item := gin.H{
			"id":            tx.ID,
			"type":          tx.Type,
			"amount":        tx.Amount,
			"balance_after": tx.BalanceAfter,
			"related_id":    tx.RelatedID,
			"remark":        tx.Remark,
			"created_at":    tx.CreatedAt,
		}
		if tx.RelatedUserID != nil {
			var relatedUser models.User
			if h.db.First(&relatedUser, *tx.RelatedUserID).Error == nil {
				item["related_user"] = gin.H{
					"id":       relatedUser.UUID,
					"nickname": relatedUser.Nickname,
					"avatar":   relatedUser.Avatar,
				}
			}
		}

		result[i] = item
	}
	resp := gin.H{
		"user_id":     user.UUID,
		"user_name":   user.Nickname,
		"list":        result,
		"page":        page,
		"page_size":   pageSize,
		"has_more":    hasMore,
		"next_cursor": nextCursor,
	}
	// 后台保留 total，方便表格展示总数。
	if !useCursor {
		var total int64
		query.Count(&total)
		resp["total"] = total
	}
	response.Success(c, resp)
}

// LockUserWallet 锁定用户钱包
func (h *WalletAdminHandler) LockUserWallet(c *gin.Context) {
	userID := c.Param("user_id")

	var user models.User
	if err := h.db.Where("uuid = ?", userID).First(&user).Error; err != nil {
		response.Error(c, http.StatusNotFound, "用户不存在")
		return
	}

	var wallet models.Wallet
	if err := h.db.Where("user_id = ?", user.ID).First(&wallet).Error; err != nil {
		response.Error(c, http.StatusNotFound, "用户钱包不存在")
		return
	}
	wallet.IsLocked = true
	wallet.UpdatedAt = time.Now()
	if err := h.db.Save(&wallet).Error; err != nil {
		response.Error(c, http.StatusInternalServerError, "操作失败")
		return
	}
	response.Success(c, gin.H{"message": "钱包已锁定"})
}

// UnlockUserWallet 解锁用户钱包
func (h *WalletAdminHandler) UnlockUserWallet(c *gin.Context) {
	userID := c.Param("user_id")

	var user models.User
	if err := h.db.Where("uuid = ?", userID).First(&user).Error; err != nil {
		response.Error(c, http.StatusNotFound, "用户不存在")
		return
	}

	var wallet models.Wallet
	if err := h.db.Where("user_id = ?", user.ID).First(&wallet).Error; err != nil {
		response.Error(c, http.StatusNotFound, "用户钱包不存在")
		return
	}
	wallet.IsLocked = false
	wallet.UpdatedAt = time.Now()
	if err := h.db.Save(&wallet).Error; err != nil {
		response.Error(c, http.StatusInternalServerError, "操作失败")
		return
	}
	response.Success(c, gin.H{"message": "钱包已解锁"})
}

// GetWalletStats 获取钱包统计
func (h *WalletAdminHandler) GetWalletStats(c *gin.Context) {
	var totalBalance, totalFrozen float64
	var walletCount int64
	var redPacketCount, transferCount int64
	var redPacketAmount, transferAmount float64

	h.db.Model(&models.Wallet{}).Count(&walletCount)
	h.db.Model(&models.Wallet{}).Select("COALESCE(SUM(balance), 0)").Scan(&totalBalance)
	h.db.Model(&models.Wallet{}).Select("COALESCE(SUM(frozen_balance), 0)").Scan(&totalFrozen)
	h.db.Model(&models.RedPacket{}).Count(&redPacketCount)
	h.db.Model(&models.RedPacket{}).Select("COALESCE(SUM(total_amount), 0)").Scan(&redPacketAmount)
	h.db.Model(&models.Transfer{}).Count(&transferCount)
	h.db.Model(&models.Transfer{}).Select("COALESCE(SUM(amount), 0)").Scan(&transferAmount)
	response.Success(c, gin.H{
		"wallet_count":      walletCount,
		"total_balance":     totalBalance,
		"total_frozen":      totalFrozen,
		"red_packet_count":  redPacketCount,
		"red_packet_amount": redPacketAmount,
		"transfer_count":    transferCount,
		"transfer_amount":   transferAmount,
	})
}

// ========== 红包记录管理 ==========

// ListRedPackets 获取红包记录列表
func (h *WalletAdminHandler) ListRedPackets(c *gin.Context) {
	page := getQueryInt(c, "page", 1)
	pageSize := getQueryInt(c, "page_size", 20)
	status := c.Query("status")
	userID := c.Query("user_id")
	query := h.db.Model(&models.RedPacket{})
	if status != "" {
		query = query.Where("status = ?", status)
	}
	if userID != "" {
		var user models.User
		if h.db.Where("uuid = ?", userID).First(&user).Error == nil {
			query = query.Where("sender_id = ?", user.ID)
		}
	}

	var total int64
	query.Count(&total)

	var redPackets []models.RedPacket
	query.Order("created_at DESC").
		Offset((page - 1) * pageSize).
		Limit(pageSize).
		Find(&redPackets)
	result := make([]gin.H, len(redPackets))
	for i, rp := range redPackets {
		var sender models.User
		h.db.First(&sender, rp.SenderID)

		// 获取领取数
		var claimCount int64
		h.db.Model(&models.RedPacketClaim{}).Where("red_packet_id = ?", rp.ID).Count(&claimCount)

		result[i] = gin.H{
			"id":               rp.UUID,
			"sender_id":        sender.UUID,
			"sender_name":      sender.Nickname,
			"sender_avatar":    sender.Avatar,
			"chat_id":          rp.ChatID,
			"type":             rp.Type,
			"total_amount":     rp.TotalAmount,
			"total_count":      rp.TotalCount,
			"remaining_amount": rp.RemainingAmount,
			"remaining_count":  rp.RemainingCount,
			"claim_count":      claimCount,
			"message":          rp.Message,
			"status":           rp.Status,
			"expired_at":       rp.ExpiredAt,
			"created_at":       rp.CreatedAt,
		}
	}
	response.Success(c, gin.H{
		"list":      result,
		"total":     total,
		"page":      page,
		"page_size": pageSize,
	})
}

// GetRedPacketDetail 获取红包详情
func (h *WalletAdminHandler) GetRedPacketDetail(c *gin.Context) {
	redPacketID := c.Param("id")

	var redPacket models.RedPacket
	if err := h.db.Where("uuid = ?", redPacketID).First(&redPacket).Error; err != nil {
		response.Error(c, http.StatusNotFound, "红包不存在")
		return
	}

	var sender models.User
	h.db.First(&sender, redPacket.SenderID)

	// 获取领取记录
	var claims []models.RedPacketClaim
	h.db.Where("red_packet_id = ?", redPacket.ID).Order("created_at").Find(&claims)
	claimList := make([]gin.H, len(claims))
	for i, claim := range claims {
		var user models.User
		h.db.First(&user, claim.UserID)
		claimList[i] = gin.H{
			"user_id":     user.UUID,
			"user_name":   user.Nickname,
			"user_avatar": user.Avatar,
			"amount":      claim.Amount,
			"is_best":     claim.IsBest,
			"created_at":  claim.CreatedAt,
		}
	}
	response.Success(c, gin.H{
		"id":               redPacket.UUID,
		"sender_id":        sender.UUID,
		"sender_name":      sender.Nickname,
		"sender_avatar":    sender.Avatar,
		"chat_id":          redPacket.ChatID,
		"type":             redPacket.Type,
		"total_amount":     redPacket.TotalAmount,
		"total_count":      redPacket.TotalCount,
		"remaining_amount": redPacket.RemainingAmount,
		"remaining_count":  redPacket.RemainingCount,
		"message":          redPacket.Message,
		"status":           redPacket.Status,
		"claims":           claimList,
		"expired_at":       redPacket.ExpiredAt,
		"created_at":       redPacket.CreatedAt,
	})
}

// RefundRedPacket 退还红包（强制退回剩余金额）
func (h *WalletAdminHandler) RefundRedPacket(c *gin.Context) {
	redPacketID := c.Param("id")
	tx := h.db.Begin()
	defer func() {
		if r := recover(); r != nil {
			tx.Rollback()
		}
	}()

	// FOR UPDATE 锁定红包行
	var redPacket models.RedPacket
	if err := tx.Clauses(clause.Locking{Strength: "UPDATE"}).
		Where("uuid = ?", redPacketID).First(&redPacket).Error; err != nil {
		tx.Rollback()
		response.Error(c, http.StatusNotFound, "红包不存在")
		return
	}
	if redPacket.RemainingAmount <= 0 {
		tx.Rollback()
		response.Error(c, http.StatusBadRequest, "红包已无剩余金额")
		return
	}

	// FOR UPDATE 锁定发送者钱包
	var wallet models.Wallet
	if err := tx.Clauses(clause.Locking{Strength: "UPDATE"}).
		Where("user_id = ?", redPacket.SenderID).First(&wallet).Error; err != nil {
		tx.Rollback()
		response.Error(c, http.StatusInternalServerError, "获取钱包失败")
		return
	}
	refundAmount := redPacket.RemainingAmount
	newBalance := wallet.Balance + refundAmount

	// 原子更新钱包余额
	if err := tx.Model(&wallet).Updates(map[string]interface{}{
		"balance":    gorm.Expr("balance + ?", refundAmount),
		"updated_at": time.Now(),
	}).Error; err != nil {
		tx.Rollback()
		response.Error(c, http.StatusInternalServerError, "退款失败")
		return
	}

	// 更新红包状态
	if err := tx.Model(&redPacket).Updates(map[string]interface{}{
		"remaining_amount": 0,
		"remaining_count":  0,
		"status":           models.RedPacketStatusExpired,
		"updated_at":       time.Now(),
	}).Error; err != nil {
		tx.Rollback()
		response.Error(c, http.StatusInternalServerError, "更新红包状态失败")
		return
	}

	// 记录交易
	if err := tx.Create(&models.Transaction{
		UserID:       redPacket.SenderID,
		Type:         models.TransactionTypeRefund,
		Amount:       refundAmount,
		BalanceAfter: newBalance,
		RelatedID:    redPacket.UUID,
		Remark:       "红包退款(管理员操作)",
		CreatedAt:    time.Now(),
	}).Error; err != nil {
		tx.Rollback()
		response.Error(c, http.StatusInternalServerError, "记录交易失败")
		return
	}
	if err := tx.Commit().Error; err != nil {
		response.Error(c, http.StatusInternalServerError, "退款失败")
		return
	}
	response.Success(c, gin.H{
		"message":       "退款成功",
		"refund_amount": refundAmount,
	})
}

// ========== 转账记录管理 ==========

// ListTransfers 获取转账记录列表
func (h *WalletAdminHandler) ListTransfers(c *gin.Context) {
	page := getQueryInt(c, "page", 1)
	pageSize := getQueryInt(c, "page_size", 20)
	status := c.Query("status")
	userID := c.Query("user_id")
	query := h.db.Model(&models.Transfer{})
	if status != "" {
		query = query.Where("status = ?", status)
	}
	if userID != "" {
		var user models.User
		if h.db.Where("uuid = ?", userID).First(&user).Error == nil {
			query = query.Where("sender_id = ? OR receiver_id = ?", user.ID, user.ID)
		}
	}

	var total int64
	query.Count(&total)

	var transfers []models.Transfer
	query.Order("created_at DESC").
		Offset((page - 1) * pageSize).
		Limit(pageSize).
		Find(&transfers)
	result := make([]gin.H, len(transfers))
	for i, tf := range transfers {
		var sender, receiver models.User
		h.db.First(&sender, tf.SenderID)
		h.db.First(&receiver, tf.ReceiverID)

		result[i] = gin.H{
			"id":              tf.UUID,
			"sender_id":       sender.UUID,
			"sender_name":     sender.Nickname,
			"sender_avatar":   sender.Avatar,
			"receiver_id":     receiver.UUID,
			"receiver_name":   receiver.Nickname,
			"receiver_avatar": receiver.Avatar,
			"amount":          tf.Amount,
			"remark":          tf.Remark,
			"status":          tf.Status,
			"expired_at":      tf.ExpiredAt,
			"accepted_at":     tf.AcceptedAt,
			"created_at":      tf.CreatedAt,
		}
	}
	response.Success(c, gin.H{
		"list":      result,
		"total":     total,
		"page":      page,
		"page_size": pageSize,
	})
}

// GetTransferDetail 获取转账详情
func (h *WalletAdminHandler) GetTransferDetail(c *gin.Context) {
	transferID := c.Param("id")

	var transfer models.Transfer
	if err := h.db.Where("uuid = ?", transferID).First(&transfer).Error; err != nil {
		response.Error(c, http.StatusNotFound, "转账不存在")
		return
	}

	var sender, receiver models.User
	h.db.First(&sender, transfer.SenderID)
	h.db.First(&receiver, transfer.ReceiverID)
	response.Success(c, gin.H{
		"id":              transfer.UUID,
		"sender_id":       sender.UUID,
		"sender_name":     sender.Nickname,
		"sender_avatar":   sender.Avatar,
		"receiver_id":     receiver.UUID,
		"receiver_name":   receiver.Nickname,
		"receiver_avatar": receiver.Avatar,
		"amount":          transfer.Amount,
		"remark":          transfer.Remark,
		"status":          transfer.Status,
		"expired_at":      transfer.ExpiredAt,
		"accepted_at":     transfer.AcceptedAt,
		"created_at":      transfer.CreatedAt,
	})
}

// RefundTransfer 退回转账（强制退回给发送者）
func (h *WalletAdminHandler) RefundTransfer(c *gin.Context) {
	transferID := c.Param("id")
	tx := h.db.Begin()
	defer func() {
		if r := recover(); r != nil {
			tx.Rollback()
		}
	}()

	// FOR UPDATE 锁定转账行
	var transfer models.Transfer
	if err := tx.Clauses(clause.Locking{Strength: "UPDATE"}).
		Where("uuid = ?", transferID).First(&transfer).Error; err != nil {
		tx.Rollback()
		response.Error(c, http.StatusNotFound, "转账不存在")
		return
	}
	if transfer.Status != models.TransferStatusPending {
		tx.Rollback()
		response.Error(c, http.StatusBadRequest, "转账已处理，无法退回")
		return
	}

	// FOR UPDATE 锁定发送者钱包
	var wallet models.Wallet
	if err := tx.Clauses(clause.Locking{Strength: "UPDATE"}).
		Where("user_id = ?", transfer.SenderID).First(&wallet).Error; err != nil {
		tx.Rollback()
		response.Error(c, http.StatusInternalServerError, "获取钱包失败")
		return
	}
	newBalance := wallet.Balance + transfer.Amount

	// 原子更新余额
	if err := tx.Model(&wallet).Updates(map[string]interface{}{
		"balance":    gorm.Expr("balance + ?", transfer.Amount),
		"updated_at": time.Now(),
	}).Error; err != nil {
		tx.Rollback()
		response.Error(c, http.StatusInternalServerError, "退款失败")
		return
	}

	// 更新转账状态
	if err := tx.Model(&transfer).Updates(map[string]interface{}{
		"status":     models.TransferStatusRejected,
		"updated_at": time.Now(),
	}).Error; err != nil {
		tx.Rollback()
		response.Error(c, http.StatusInternalServerError, "更新转账状态失败")
		return
	}

	// 用 tx 查询接收者信息（修复之前用 h.db 的 bug）
	var receiver models.User
	tx.First(&receiver, transfer.ReceiverID)
	if err := tx.Create(&models.Transaction{
		UserID:          transfer.SenderID,
		Type:            models.TransactionTypeRefund,
		Amount:          transfer.Amount,
		BalanceAfter:    newBalance,
		RelatedID:       transfer.UUID,
		RelatedUserID:   &transfer.ReceiverID,
		RelatedUserName: receiver.Nickname,
		Remark:          "转账退回(管理员操作)",
		CreatedAt:       time.Now(),
	}).Error; err != nil {
		tx.Rollback()
		response.Error(c, http.StatusInternalServerError, "记录交易失败")
		return
	}
	if err := tx.Commit().Error; err != nil {
		response.Error(c, http.StatusInternalServerError, "退回失败")
		return
	}
	response.Success(c, gin.H{
		"message":       "退回成功",
		"refund_amount": transfer.Amount,
	})
}

// ========== 钱包设置 ==========

// GetWalletSettings 获取钱包设置
func (h *WalletAdminHandler) GetWalletSettings(c *gin.Context) {
	keys := []string{
		models.SettingWalletCurrency, models.SettingWalletCurrencyName,
		models.SettingRedPacketExpireHours, models.SettingTransferExpireHours,
		models.SettingWalletNotice, models.SettingRechargeNotice,
		models.SettingWithdrawNotice, models.SettingRechargeReview,
	}
	var settings []models.SystemSetting
	h.db.Where("`key` IN ?", keys).Find(&settings)
	result := make(map[string]string)
	for _, s := range settings {
		result[s.Key] = s.Value
	}
	// 设置默认值
	if result[models.SettingWalletCurrency] == "" {
		result[models.SettingWalletCurrency] = "¥"
	}
	if result[models.SettingWalletCurrencyName] == "" {
		result[models.SettingWalletCurrencyName] = "人民币"
	}
	if result[models.SettingRedPacketExpireHours] == "" {
		result[models.SettingRedPacketExpireHours] = "24"
	}
	if result[models.SettingTransferExpireHours] == "" {
		result[models.SettingTransferExpireHours] = "24"
	}
	if result[models.SettingRechargeReview] == "" {
		result[models.SettingRechargeReview] = "0"
	}
	response.Success(c, result)
}

// SaveWalletSettings 保存钱包设置
func (h *WalletAdminHandler) SaveWalletSettings(c *gin.Context) {
	var req map[string]string
	if err := c.ShouldBindJSON(&req); err != nil {
		response.Error(c, http.StatusBadRequest, "参数错误")
		return
	}
	allowed := map[string]bool{
		models.SettingWalletCurrency: true, models.SettingWalletCurrencyName: true,
		models.SettingRedPacketExpireHours: true, models.SettingTransferExpireHours: true,
		models.SettingWalletNotice: true, models.SettingRechargeNotice: true,
		models.SettingWithdrawNotice: true, models.SettingRechargeReview: true,
	}
	now := time.Now()
	for key, value := range req {
		if !allowed[key] {
			continue
		}
		var setting models.SystemSetting
		if h.db.Where("`key` = ?", key).First(&setting).Error != nil {
			h.db.Create(&models.SystemSetting{Key: key, Value: value, Type: "string", CreatedAt: now, UpdatedAt: now})
		} else {
			h.db.Model(&setting).Updates(map[string]interface{}{"value": value, "updated_at": now})
		}
	}
	response.Success(c, gin.H{"message": "保存成功"})
}

func (h *WalletAdminHandler) GetPaymentGatewayConfig(c *gin.Context) {
	if h.cfg == nil {
		response.Success(c, config.PaymentConfig{})
		return
	}
	cfg := services.LoadPaymentForRuntime(h.db, h.cfg.Payment)
	if middleware.GetAdminRole(c) == "demo_admin" {
		cfg = maskPaymentConfigForDemo(cfg)
	}
	response.Success(c, cfg)
}

func maskPaymentConfigForDemo(cfg config.PaymentConfig) config.PaymentConfig {
	cfg.Wechat.MchAPIv3Key = maskSecret(cfg.Wechat.MchAPIv3Key)
	cfg.Wechat.PrivateKeyPath = maskSecret(cfg.Wechat.PrivateKeyPath)
	cfg.Wechat.PrivateKeyPEM = maskSecret(cfg.Wechat.PrivateKeyPEM)
	cfg.Alipay.PrivateKeyPath = maskSecret(cfg.Alipay.PrivateKeyPath)
	cfg.Alipay.AppPrivateKeyPEM = maskSecret(cfg.Alipay.AppPrivateKeyPEM)
	cfg.Alipay.AlipayPublicKeyPath = maskSecret(cfg.Alipay.AlipayPublicKeyPath)
	cfg.Alipay.AlipayPublicKeyPEM = maskSecret(cfg.Alipay.AlipayPublicKeyPEM)
	return cfg
}

func (h *WalletAdminHandler) SavePaymentGatewayConfig(c *gin.Context) {
	var cfg config.PaymentConfig
	if err := c.ShouldBindJSON(&cfg); err != nil {
		response.Error(c, http.StatusBadRequest, "参数错误")
		return
	}
	raw, err := json.Marshal(cfg)
	if err != nil {
		response.Error(c, http.StatusBadRequest, "序列化失败")
		return
	}
	now := time.Now()
	setting := models.SystemSetting{
		Key:       models.SettingPaymentGateway,
		Value:     string(raw),
		Type:      "json",
		CreatedAt: now,
		UpdatedAt: now,
	}
	if err := h.db.Where("`key` = ?", models.SettingPaymentGateway).Assign(map[string]interface{}{
		"value":      setting.Value,
		"type":       setting.Type,
		"updated_at": setting.UpdatedAt,
	}).FirstOrCreate(&setting).Error; err != nil {
		response.Error(c, http.StatusInternalServerError, "保存失败")
		return
	}
	if h.paySvc != nil {
		h.paySvc.InvalidatePaymentCache()
	}
	response.Success(c, cfg)
}

// ========== 充值方式管理 ==========

// ListRechargeMethods 获取充值方式列表
func (h *WalletAdminHandler) ListRechargeMethods(c *gin.Context) {
	var methods []models.RechargeMethod
	h.db.Order("sort ASC, id ASC").Find(&methods)
	response.Success(c, methods)
}

// CreateRechargeMethod 创建充值方式
func (h *WalletAdminHandler) CreateRechargeMethod(c *gin.Context) {
	var req models.RechargeMethod
	if err := c.ShouldBindJSON(&req); err != nil {
		response.Error(c, http.StatusBadRequest, "参数错误")
		return
	}
	req.ID = 0 // 清除客户端传入的 ID，让数据库自增
	req.CreatedAt = time.Now()
	req.UpdatedAt = time.Now()
	if err := h.db.Create(&req).Error; err != nil {
		response.Error(c, http.StatusInternalServerError, "创建失败")
		return
	}
	response.Success(c, req)
}

// UpdateRechargeMethod 更新充值方式
func (h *WalletAdminHandler) UpdateRechargeMethod(c *gin.Context) {
	id := c.Param("id")
	var method models.RechargeMethod
	if err := h.db.First(&method, id).Error; err != nil {
		response.Error(c, http.StatusNotFound, "充值方式不存在")
		return
	}
	var req struct {
		Name        *string  `json:"name"`
		Icon        *string  `json:"icon"`
		Type        *string  `json:"type"`
		QRCodeURL   *string  `json:"qrcode_url"`
		AccountInfo *string  `json:"account_info"`
		MinAmount   *float64 `json:"min_amount"`
		MaxAmount   *float64 `json:"max_amount"`
		Remark      *string  `json:"remark"`
		Status      *int8    `json:"status"`
		Sort        *int     `json:"sort"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		response.Error(c, http.StatusBadRequest, "参数错误")
		return
	}
	updates := map[string]interface{}{"updated_at": time.Now()}
	if req.Name != nil {
		updates["name"] = *req.Name
	}
	if req.Icon != nil {
		updates["icon"] = *req.Icon
	}
	if req.Type != nil {
		updates["type"] = *req.Type
	}
	if req.QRCodeURL != nil {
		updates["qrcode_url"] = *req.QRCodeURL
	}
	if req.AccountInfo != nil {
		updates["account_info"] = *req.AccountInfo
	}
	if req.MinAmount != nil {
		updates["min_amount"] = *req.MinAmount
	}
	if req.MaxAmount != nil {
		updates["max_amount"] = *req.MaxAmount
	}
	if req.Remark != nil {
		updates["remark"] = *req.Remark
	}
	if req.Status != nil {
		updates["status"] = *req.Status
	}
	if req.Sort != nil {
		updates["sort"] = *req.Sort
	}
	if err := h.db.Model(&method).Updates(updates).Error; err != nil {
		response.Error(c, http.StatusInternalServerError, "更新失败")
		return
	}
	h.db.First(&method, id)
	response.Success(c, method)
}

// DeleteRechargeMethod 删除充值方式
func (h *WalletAdminHandler) DeleteRechargeMethod(c *gin.Context) {
	id := c.Param("id")
	if err := h.db.Delete(&models.RechargeMethod{}, id).Error; err != nil {
		response.Error(c, http.StatusInternalServerError, "删除失败")
		return
	}
	response.Success(c, gin.H{"message": "删除成功"})
}

// ========== 人工充值审核 ==========

// ListRechargeOrders 充值订单列表
func (h *WalletAdminHandler) ListRechargeOrders(c *gin.Context) {
	page := getQueryInt(c, "page", 1)
	pageSize := getQueryInt(c, "page_size", 20)
	status := c.Query("status")
	query := h.db.Model(&models.RechargeOrder{})
	if status != "" {
		query = query.Where("status = ?", status)
	}

	var total int64
	query.Count(&total)

	var orders []models.RechargeOrder
	query.Order("created_at DESC").Offset((page - 1) * pageSize).Limit(pageSize).Find(&orders)
	result := make([]gin.H, len(orders))
	for i, o := range orders {
		var user models.User
		h.db.First(&user, o.UserID)
		var method models.RechargeMethod
		h.db.First(&method, o.MethodID)
		result[i] = gin.H{
			"id": o.ID, "user_id": user.UUID, "user_name": user.Nickname,
			"username": user.Username, "avatar": user.Avatar,
			"method_name": method.Name, "amount": o.Amount,
			"proof_image": o.ProofImage, "status": o.Status,
			"remark": o.Remark, "reviewed_by": o.ReviewedBy,
			"reviewed_at": o.ReviewedAt, "created_at": o.CreatedAt,
		}
	}
	response.Success(c, gin.H{"list": result, "total": total, "page": page, "page_size": pageSize})
}

// ReviewRechargeOrder 审核充值订单
func (h *WalletAdminHandler) ReviewRechargeOrder(c *gin.Context) {

	orderID := c.Param("id")
	var req struct {
		Action string `json:"action" binding:"required,oneof=approve reject"`
		Remark string `json:"remark"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		response.Error(c, http.StatusBadRequest, "参数错误")
		return
	}
	adminID := middleware.GetAdminID(c)
	now := time.Now()
	tx := h.db.Begin()
	defer func() {
		if r := recover(); r != nil {
			tx.Rollback()
		}
	}()

	var order models.RechargeOrder
	if err := tx.Clauses(clause.Locking{Strength: "UPDATE"}).First(&order, orderID).Error; err != nil {
		tx.Rollback()
		response.Error(c, http.StatusNotFound, "订单不存在")
		return
	}
	if order.Status != models.RechargeOrderPending {
		tx.Rollback()
		response.Error(c, http.StatusBadRequest, "订单已处理")
		return
	}
	order.ReviewedBy = &adminID
	order.ReviewedAt = &now
	order.Remark = req.Remark
	order.UpdatedAt = now

	if req.Action == "approve" {
		order.Status = models.RechargeOrderApproved
		// FOR UPDATE 锁定用户钱包并充值
		var wallet models.Wallet
		if err := tx.Clauses(clause.Locking{Strength: "UPDATE"}).
			Where("user_id = ?", order.UserID).First(&wallet).Error; err != nil {
			if !errors.Is(err, gorm.ErrRecordNotFound) {
				tx.Rollback()
				response.Error(c, http.StatusInternalServerError, "获取钱包失败")
				return
			}
			// 创建钱包
			wallet = models.Wallet{UserID: order.UserID, Balance: 0, CreatedAt: now, UpdatedAt: now}
			if err := tx.Create(&wallet).Error; err != nil {
				tx.Rollback()
				response.Error(c, http.StatusInternalServerError, "创建钱包失败")
				return
			}
		}
		newBalance := wallet.Balance + order.Amount
		if err := tx.Model(&wallet).Updates(map[string]interface{}{
			"balance": gorm.Expr("balance + ?", order.Amount), "updated_at": now,
		}).Error; err != nil {
			tx.Rollback()
			response.Error(c, http.StatusInternalServerError, "充值失败")
			return
		}
		if err := tx.Create(&models.Transaction{
			UserID: order.UserID, Type: models.TransactionTypeRecharge,
			Amount: order.Amount, BalanceAfter: newBalance,
			Remark: "充值(审核通过)", CreatedAt: now,
		}).Error; err != nil {
			tx.Rollback()
			response.Error(c, http.StatusInternalServerError, "记录交易失败")
			return
		}
	} else {
		order.Status = models.RechargeOrderRejected
		// 记录拒绝的交易记录（包含拒绝原因）
		rejectRemark := fmt.Sprintf("充值 ¥%.2f 被拒绝", order.Amount)
		if req.Remark != "" {
			rejectRemark = fmt.Sprintf("充值 ¥%.2f 被拒绝：%s", order.Amount, req.Remark)
		}
		// 获取用户当前余额用于记录
		var userWallet models.Wallet
		var curBalance float64
		if tx.Where("user_id = ?", order.UserID).First(&userWallet).Error == nil {
			curBalance = userWallet.Balance
		}
		if err := tx.Create(&models.Transaction{
			UserID: order.UserID, Type: models.TransactionTypeRechargeRejected,
			Amount: 0, BalanceAfter: curBalance,
			RelatedID: fmt.Sprintf("%d", order.ID),
			Remark:    rejectRemark, CreatedAt: now,
		}).Error; err != nil {
			tx.Rollback()
			response.Error(c, http.StatusInternalServerError, "记录交易失败")
			return
		}
	}
	if err := tx.Save(&order).Error; err != nil {
		tx.Rollback()
		response.Error(c, http.StatusInternalServerError, "操作失败")
		return
	}
	if err := tx.Commit().Error; err != nil {
		response.Error(c, http.StatusInternalServerError, "操作失败")
		return
	}
	response.Success(c, gin.H{"message": "操作成功"})
}
