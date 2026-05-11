package handlers

import (
	"context"
	"encoding/json"
	"fmt"
	"log"
	"math"
	"math/rand"
	"net/http"
	"strings"
	"time"

	"gaoranim/internal/models"
	"gaoranim/internal/services"
	"gaoranim/internal/ws"
	"gaoranim/pkg/response"

	"github.com/gin-gonic/gin"
	"github.com/google/uuid"
	"gorm.io/gorm"
	"gorm.io/gorm/clause"
)

type WalletHandler struct {
	db         *gorm.DB
	hub        *ws.Hub
	msgService *services.MessageService
}

func (h *WalletHandler) getMessageCryptoMode() string {
	if h == nil || h.db == nil {
		return models.MessageCryptoModePlain
	}

	var setting models.SystemSetting
	if err := h.db.
		Where("`key` = ?", models.SettingMessageCryptoMode).
		Select("value").
		First(&setting).Error; err != nil {
		return models.MessageCryptoModePlain
	}

	return normalizeMessageCryptoMode(setting.Value)
}

func (h *WalletHandler) walletChatMessagesBlocked() bool {
	return h.getMessageCryptoMode() == models.MessageCryptoModeStrict
}

func (h *WalletHandler) rejectWalletChatMessageInStrictMode(c *gin.Context, feature string) bool {
	if !h.walletChatMessagesBlocked() {
		return false
	}

	response.BadRequest(c, fmt.Sprintf("严格加密模式下，当前暂不支持通过聊天发送%s", feature))
	return true
}

func (h *WalletHandler) sendChatMessageWithRetry(
	ctx context.Context,
	params *services.SendMessageParams,
	senderName string,
	senderAvatar string,
	senderNicknameColor string,
	senderPremiumType string,
	senderEmojiAvatar string,
	targetUserIDs []string,
) {
	if h.msgService == nil {
		return
	}

	result, err := h.msgService.SendMessageWithResult(
		ctx,
		params,
		senderName,
		senderAvatar,
		senderNicknameColor,
		senderPremiumType,
		senderEmojiAvatar,
		targetUserIDs,
	)
	if err == nil {
		h.updateWalletChatPreview(params, senderName, result)
		return
	}

	retryResult, retryErr := h.msgService.SendMessageWithResult(
		ctx,
		params,
		senderName,
		senderAvatar,
		senderNicknameColor,
		senderPremiumType,
		senderEmojiAvatar,
		targetUserIDs,
	)
	if retryErr != nil {
		log.Printf("[wallet] send chat message failed msg_id=%s chat_id=%s: %v", params.MsgID, params.ChatID, retryErr)
		return
	}
	h.updateWalletChatPreview(params, senderName, retryResult)
}

func (h *WalletHandler) updateWalletChatPreview(params *services.SendMessageParams, senderName string, result *services.SendMessageResult) {
	if h == nil || h.db == nil || params == nil || result == nil || result.Message == nil || result.Duplicate {
		return
	}

	var chat models.Chat
	if err := h.db.Where("uuid = ?", params.ChatID).First(&chat).Error; err != nil {
		log.Printf("[wallet] update chat preview skipped chat_id=%s err=%v", params.ChatID, err)
		return
	}

	var sender models.User
	if err := h.db.Where("uuid = ?", params.SenderID).Select("id").First(&sender).Error; err != nil {
		log.Printf("[wallet] update chat preview skipped sender_id=%s err=%v", params.SenderID, err)
		return
	}

	msg := result.Message
	lastMsgText := walletPreviewText(msg.Type, params.Content)
	h.db.Model(&models.UserChat{}).
		Where("chat_id = ?", chat.ID).
		Updates(map[string]interface{}{
			"last_msg_text":   lastMsgText,
			"last_msg_type":   msg.Type,
			"last_msg_time":   msg.CreatedAt,
			"last_msg_seq":    msg.Seq,
			"last_msg_sender": senderName,
			"sort_time":       msg.CreatedAt,
		})

	h.db.Model(&models.UserChat{}).
		Where("chat_id = ? AND user_id != ?", chat.ID, sender.ID).
		UpdateColumn("unread_count", gorm.Expr("unread_count + 1"))
}

func walletPreviewText(msgType int, content map[string]interface{}) string {
	switch msgType {
	case models.MsgTypeRedPacket:
		return "[红包]"
	case models.MsgTypeTransfer:
		return "[转账]"
	case models.MsgTypeSystem:
		if text, ok := content["text"].(string); ok && strings.Contains(text, "red_packet_claimed") {
			return "[红包领取]"
		}
		if text, ok := content["text"].(string); ok && strings.Contains(text, "transfer_accepted") {
			return "[转账已收款]"
		}
		return "[系统消息]"
	default:
		if text, ok := content["text"].(string); ok {
			return text
		}
		return "[消息]"
	}
}

func NewWalletHandler(db *gorm.DB, hub *ws.Hub, msgService *services.MessageService) *WalletHandler {
	return &WalletHandler{
		db:         db,
		hub:        hub,
		msgService: msgService,
	}
}

func (h *WalletHandler) validateRedPacketChat(chatID string, senderID uint64) (*models.Chat, []string, error) {
	var chat models.Chat
	if err := h.db.Where("uuid = ?", chatID).First(&chat).Error; err != nil {
		return nil, nil, fmt.Errorf("会话不存在")
	}
	if chat.Status == models.ChatStatusBanned {
		return nil, nil, fmt.Errorf("该群组已被管理员封禁，无法发送红包")
	}
	if chat.Status == models.ChatStatusDissolved {
		return nil, nil, fmt.Errorf("该群组已被解散")
	}
	if chat.Type == 3 {
		return nil, nil, fmt.Errorf("频道不支持发送红包")
	}

	var senderMember models.ChatMember
	if err := h.db.Where("chat_id = ? AND user_id = ?", chat.ID, senderID).First(&senderMember).Error; err != nil {
		return nil, nil, fmt.Errorf("您不是该会话成员")
	}
	if chat.Type == 2 && !chat.CanSendMessage && senderMember.Role < 1 {
		return nil, nil, fmt.Errorf("群组已开启全员禁言，仅管理员可发红包")
	}
	if senderMember.IsMuted {
		if senderMember.MuteEndTime != nil && time.Now().After(*senderMember.MuteEndTime) {
			h.db.Model(&senderMember).Updates(map[string]interface{}{
				"is_muted":      false,
				"mute_end_time": nil,
			})
		} else {
			muteMsg := "您已被禁言"
			if senderMember.MuteEndTime != nil {
				muteMsg = fmt.Sprintf("您已被禁言至 %s", senderMember.MuteEndTime.Format("2006-01-02 15:04"))
			}
			return nil, nil, fmt.Errorf("%s", muteMsg)
		}
	}

	var memberUserIDs []uint64
	h.db.Model(&models.ChatMember{}).
		Where("chat_id = ? AND user_id != ?", chat.ID, senderID).
		Pluck("user_id", &memberUserIDs)
	if chat.Type == 1 {
		if len(memberUserIDs) == 0 {
			return nil, nil, fmt.Errorf("私聊会话异常")
		}
		var blockCount int64
		h.db.Model(&models.UserBlock{}).
			Where("user_id IN ? AND blocked_user_id = ?", memberUserIDs, senderID).
			Count(&blockCount)
		if blockCount > 0 {
			return nil, nil, fmt.Errorf("消息发送失败")
		}
	}

	var targetUserIDs []string
	if len(memberUserIDs) > 0 {
		h.db.Model(&models.User{}).Where("id IN ?", memberUserIDs).Pluck("uuid", &targetUserIDs)
	}
	return &chat, targetUserIDs, nil
}

func (h *WalletHandler) findTransferChat(senderID, receiverID uint64) (*models.Chat, error) {
	var chat models.Chat
	err := h.db.Raw(`
		SELECT c.* FROM chats c
		INNER JOIN chat_members cm1 ON c.id = cm1.chat_id AND cm1.user_id = ?
		INNER JOIN chat_members cm2 ON c.id = cm2.chat_id AND cm2.user_id = ?
		WHERE c.type = 1 AND c.deleted_at IS NULL
		LIMIT 1
	`, senderID, receiverID).Scan(&chat).Error
	if err != nil {
		return nil, err
	}
	if chat.ID == 0 {
		return nil, gorm.ErrRecordNotFound
	}
	if chat.Status == models.ChatStatusBanned || chat.Status == models.ChatStatusDissolved {
		return nil, fmt.Errorf("会话不可用")
	}

	var blockCount int64
	h.db.Model(&models.UserBlock{}).
		Where("user_id = ? AND blocked_user_id = ?", receiverID, senderID).
		Count(&blockCount)
	if blockCount > 0 {
		return nil, fmt.Errorf("消息发送失败")
	}
	return &chat, nil
}

// GetWallet 获取钱包信息
func (h *WalletHandler) GetWallet(c *gin.Context) {
	userID, err := h.getUserIDFromContext(c)
	if err != nil {
		response.Error(c, http.StatusUnauthorized, "用户未登录")
		return
	}

	wallet, err := h.getOrCreateWallet(userID)
	if err != nil {
		response.Error(c, http.StatusInternalServerError, "获取钱包失败")
		return
	}

	response.Success(c, gin.H{
		"id":               wallet.ID,
		"balance":          wallet.Balance,
		"frozen_balance":   wallet.FrozenBalance,
		"has_pay_password": wallet.HasPayPassword(),
		"is_locked":        wallet.IsLocked,
		"created_at":       wallet.CreatedAt,
	})
}

// SetPayPassword 设置支付密码
func (h *WalletHandler) SetPayPassword(c *gin.Context) {
	userID, err := h.getUserIDFromContext(c)
	if err != nil {
		response.Error(c, http.StatusUnauthorized, "用户未登录")
		return
	}

	var req struct {
		Password    string `json:"password" binding:"required,len=6"`
		OldPassword string `json:"old_password"` // 修改密码时需要
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		response.Error(c, http.StatusBadRequest, "请输入6位数字密码")
		return
	}

	wallet, err := h.getOrCreateWallet(userID)
	if err != nil {
		response.Error(c, http.StatusInternalServerError, "获取钱包失败")
		return
	}

	// 如果已有密码，需要验证旧密码
	if wallet.HasPayPassword() {
		if req.OldPassword == "" {
			response.Error(c, http.StatusBadRequest, "请输入旧密码")
			return
		}
		if !wallet.CheckPayPassword(req.OldPassword) {
			response.Error(c, http.StatusBadRequest, "旧密码错误")
			return
		}
	}

	// 设置新密码
	if err := wallet.SetPayPassword(req.Password); err != nil {
		response.Error(c, http.StatusInternalServerError, "设置密码失败")
		return
	}

	if err := h.db.Save(&wallet).Error; err != nil {
		response.Error(c, http.StatusInternalServerError, "保存失败")
		return
	}

	response.Success(c, gin.H{"message": "设置成功"})
}

// VerifyPayPassword 验证支付密码
func (h *WalletHandler) VerifyPayPassword(c *gin.Context) {
	userID, err := h.getUserIDFromContext(c)
	if err != nil {
		response.Error(c, http.StatusUnauthorized, "用户未登录")
		return
	}

	var req struct {
		Password string `json:"password" binding:"required"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		response.Error(c, http.StatusBadRequest, "请输入密码")
		return
	}

	wallet, err := h.getOrCreateWallet(userID)
	if err != nil {
		response.Error(c, http.StatusInternalServerError, "获取钱包失败")
		return
	}

	if !wallet.HasPayPassword() {
		response.Error(c, http.StatusBadRequest, "未设置支付密码")
		return
	}

	if !wallet.CheckPayPassword(req.Password) {
		response.Error(c, http.StatusBadRequest, "密码错误")
		return
	}

	response.Success(c, gin.H{"valid": true})
}

// GetTransactions 获取交易记录
func (h *WalletHandler) GetTransactions(c *gin.Context) {
	userID, err := h.getUserIDFromContext(c)
	if err != nil {
		response.Error(c, http.StatusUnauthorized, "用户未登录")
		return
	}
	page := getQueryInt(c, "page", 1)
	pageSize := getQueryInt(c, "page_size", 20)
	txType := c.Query("type")

	query := h.db.Model(&models.Transaction{}).Where("user_id = ?", userID)
	if txType != "" {
		query = query.Where("type = ?", txType)
	}

	var total int64
	query.Count(&total)

	var transactions []models.Transaction
	query.Order("created_at DESC").
		Offset((page - 1) * pageSize).
		Limit(pageSize).
		Find(&transactions)

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
			var user models.User
			if h.db.First(&user, *tx.RelatedUserID).Error == nil {
				item["related_user"] = gin.H{
					"id":       user.UUID,
					"nickname": user.Nickname,
					"avatar":   user.Avatar,
				}
			}
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

// Recharge 充值（模拟）
func (h *WalletHandler) Recharge(c *gin.Context) {
	userID, err := h.getUserIDFromContext(c)
	if err != nil {
		response.Error(c, http.StatusUnauthorized, "用户未登录")
		return
	}

	var req struct {
		Amount float64 `json:"amount" binding:"required,gt=0"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		response.Error(c, http.StatusBadRequest, "请输入有效金额")
		return
	}

	// 事务内操作：锁定钱包行 -> 更新余额 -> 记录交易
	tx := h.db.Begin()
	defer func() {
		if r := recover(); r != nil {
			tx.Rollback()
		}
	}()

	// FOR UPDATE 锁定钱包行
	var wallet models.Wallet
	if err := tx.Clauses(clause.Locking{Strength: "UPDATE"}).
		Where("user_id = ?", userID).First(&wallet).Error; err != nil {
		// 钱包不存在则创建
		tx.Rollback()
		w, createErr := h.getOrCreateWallet(userID)
		if createErr != nil {
			response.Error(c, http.StatusInternalServerError, "获取钱包失败")
			return
		}
		// 重新开事务
		tx = h.db.Begin()
		if err := tx.Clauses(clause.Locking{Strength: "UPDATE"}).
			Where("user_id = ?", userID).First(&wallet).Error; err != nil {
			tx.Rollback()
			_ = w
			response.Error(c, http.StatusInternalServerError, "获取钱包失败")
			return
		}
	}

	// 原子更新余额
	newBalance := wallet.Balance + req.Amount
	if err := tx.Model(&wallet).Updates(map[string]interface{}{
		"balance":    gorm.Expr("balance + ?", req.Amount),
		"updated_at": time.Now(),
	}).Error; err != nil {
		tx.Rollback()
		response.Error(c, http.StatusInternalServerError, "充值失败")
		return
	}

	// 记录交易
	transaction := models.Transaction{
		UserID:       userID,
		Type:         models.TransactionTypeRecharge,
		Amount:       req.Amount,
		BalanceAfter: newBalance,
		Remark:       "充值",
		CreatedAt:    time.Now(),
	}
	if err := tx.Create(&transaction).Error; err != nil {
		tx.Rollback()
		response.Error(c, http.StatusInternalServerError, "充值失败")
		return
	}

	if err := tx.Commit().Error; err != nil {
		response.Error(c, http.StatusInternalServerError, "充值失败")
		return
	}

	response.Success(c, gin.H{
		"balance": newBalance,
		"message": "充值成功",
	})
}

// SendRedPacket 发红包
func (h *WalletHandler) SendRedPacket(c *gin.Context) {
	userID, err := h.getUserIDFromContext(c)
	if err != nil {
		response.Error(c, http.StatusUnauthorized, "用户未登录")
		return
	}

	var req struct {
		ChatID      string  `json:"chat_id" binding:"required"`
		Type        string  `json:"type" binding:"required,oneof=normal lucky"`
		TotalAmount float64 `json:"total_amount" binding:"required,gt=0"`
		TotalCount  int     `json:"total_count" binding:"required,gt=0"`
		Message     string  `json:"message"`
		PayPassword string  `json:"pay_password" binding:"required"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		response.Error(c, http.StatusBadRequest, "参数错误")
		return
	}

	// 验证金额
	if req.TotalAmount < 0.01*float64(req.TotalCount) {
		response.Error(c, http.StatusBadRequest, "红包金额不能少于0.01元/个")
		return
	}

	// 检查钱包是否锁定
	if h.checkWalletLocked(userID) {
		response.Error(c, http.StatusForbidden, "钱包已锁定，无法操作")
		return
	}

	// 预先验证支付密码
	walletCheck, err := h.getOrCreateWallet(userID)
	if err != nil {
		response.Error(c, http.StatusInternalServerError, "获取钱包失败")
		return
	}
	if !walletCheck.CheckPayPassword(req.PayPassword) {
		response.Error(c, http.StatusBadRequest, "支付密码错误")
		return
	}

	// 获取发送者信息
	var sender models.User
	if err := h.db.First(&sender, userID).Error; err != nil {
		response.Error(c, http.StatusInternalServerError, "获取用户信息失败")
		return
	}

	chat, targetUserIDs, err := h.validateRedPacketChat(req.ChatID, userID)
	if err != nil {
		response.Error(c, http.StatusForbidden, err.Error())
		return
	}
	if h.rejectWalletChatMessageInStrictMode(c, "红包") {
		return
	}

	// 事务内操作：锁定钱包 -> 验证余额 -> 扣减 -> 创建红包 -> 记录交易
	tx := h.db.Begin()
	defer func() {
		if r := recover(); r != nil {
			tx.Rollback()
		}
	}()

	// FOR UPDATE 锁定钱包行
	var wallet models.Wallet
	if err := tx.Clauses(clause.Locking{Strength: "UPDATE"}).
		Where("user_id = ?", userID).First(&wallet).Error; err != nil {
		tx.Rollback()
		response.Error(c, http.StatusInternalServerError, "获取钱包失败")
		return
	}

	// 锁定后验证余额
	if wallet.Balance < req.TotalAmount {
		tx.Rollback()
		response.Error(c, http.StatusBadRequest, "余额不足")
		return
	}

	// 原子扣减余额
	newBalance := wallet.Balance - req.TotalAmount
	if err := tx.Model(&wallet).Updates(map[string]interface{}{
		"balance":    gorm.Expr("balance - ?", req.TotalAmount),
		"updated_at": time.Now(),
	}).Error; err != nil {
		tx.Rollback()
		response.Error(c, http.StatusInternalServerError, "发送失败")
		return
	}

	// 创建红包
	redPacket := models.RedPacket{
		UUID:            uuid.New().String(),
		SenderID:        userID,
		ChatID:          req.ChatID,
		Type:            req.Type,
		TotalAmount:     req.TotalAmount,
		TotalCount:      req.TotalCount,
		RemainingAmount: req.TotalAmount,
		RemainingCount:  req.TotalCount,
		Message:         req.Message,
		Status:          models.RedPacketStatusActive,
		ExpiredAt:       time.Now().Add(h.getExpireHours(models.SettingRedPacketExpireHours, 24)),
		CreatedAt:       time.Now(),
		UpdatedAt:       time.Now(),
	}
	if redPacket.Message == "" {
		redPacket.Message = "恭喜发财，大吉大利"
	}
	if err := tx.Create(&redPacket).Error; err != nil {
		tx.Rollback()
		response.Error(c, http.StatusInternalServerError, "发送失败")
		return
	}

	// 记录交易
	transaction := models.Transaction{
		UserID:       userID,
		Type:         models.TransactionTypeRedPacketSend,
		Amount:       -req.TotalAmount,
		BalanceAfter: newBalance,
		RelatedID:    redPacket.UUID,
		Remark:       "发出红包",
		CreatedAt:    time.Now(),
	}
	if err := tx.Create(&transaction).Error; err != nil {
		tx.Rollback()
		response.Error(c, http.StatusInternalServerError, "发送失败")
		return
	}

	if err := tx.Commit().Error; err != nil {
		response.Error(c, http.StatusInternalServerError, "发送失败")
		return
	}

	// 构建红包消息内容
	redPacketContent := map[string]interface{}{
		"id":            redPacket.UUID,
		"sender_id":     sender.UUID,
		"sender_name":   sender.Nickname,
		"sender_avatar": sender.Avatar,
		"type":          redPacket.Type,
		"total_amount":  redPacket.TotalAmount,
		"total_count":   redPacket.TotalCount,
		"message":       redPacket.Message,
		"status":        redPacket.Status,
		"created_at":    redPacket.CreatedAt.Format(time.RFC3339),
	}

	if chat != nil && h.msgService != nil {
		contentJSON, _ := json.Marshal(redPacketContent)
		params := &services.SendMessageParams{
			ChatID:   req.ChatID,
			MsgID:    fmt.Sprintf("red_packet:%s", redPacket.UUID),
			SenderID: sender.UUID,
			Type:     models.MsgTypeRedPacket,
			Content: map[string]interface{}{
				"text": string(contentJSON),
			},
		}
		h.sendChatMessageWithRetry(context.Background(), params, sender.Nickname, sender.Avatar, sender.NicknameColor, sender.PremiumType, sender.EmojiAvatar, targetUserIDs)
	}

	response.Success(c, gin.H{
		"id":            redPacket.UUID,
		"sender_id":     sender.UUID,
		"sender_name":   sender.Nickname,
		"sender_avatar": sender.Avatar,
		"chat_id":       redPacket.ChatID,
		"type":          redPacket.Type,
		"total_amount":  redPacket.TotalAmount,
		"total_count":   redPacket.TotalCount,
		"message":       redPacket.Message,
		"status":        redPacket.Status,
		"created_at":    redPacket.CreatedAt,
	})
}

// ClaimRedPacket 领取红包
func (h *WalletHandler) ClaimRedPacket(c *gin.Context) {
	userID, err := h.getUserIDFromContext(c)
	if err != nil {
		response.Error(c, http.StatusUnauthorized, "用户未登录")
		return
	}
	redPacketID := c.Param("id")

	// 获取领取者信息
	var claimer models.User
	if err := h.db.First(&claimer, userID).Error; err != nil {
		response.Error(c, http.StatusBadRequest, "用户不存在")
		return
	}

	// 开始事务 - 所有检查和操作都在事务内进行
	tx := h.db.Begin()
	defer func() {
		if r := recover(); r != nil {
			tx.Rollback()
		}
	}()

	// 使用行锁查找红包，防止并发问题
	var redPacket models.RedPacket
	if err := tx.Clauses(clause.Locking{Strength: "UPDATE"}).Where("uuid = ?", redPacketID).First(&redPacket).Error; err != nil {
		tx.Rollback()
		response.Error(c, http.StatusNotFound, "红包不存在")
		return
	}

	// 检查状态
	if redPacket.Status != models.RedPacketStatusActive {
		tx.Rollback()
		if redPacket.Status == models.RedPacketStatusExpired {
			response.Error(c, http.StatusBadRequest, "红包已过期")
		} else {
			response.Error(c, http.StatusBadRequest, "红包已被领完")
		}
		return
	}

	// 检查是否过期
	if time.Now().After(redPacket.ExpiredAt) {
		tx.Model(&redPacket).Update("status", models.RedPacketStatusExpired)
		tx.Commit()
		response.Error(c, http.StatusBadRequest, "红包已过期")
		return
	}

	// 检查剩余数量
	if redPacket.RemainingCount <= 0 {
		tx.Model(&redPacket).Update("status", models.RedPacketStatusFinished)
		tx.Commit()
		response.Error(c, http.StatusBadRequest, "红包已被领完")
		return
	}

	// 在事务内检查是否已领取（使用行锁防止并发）
	var existClaim models.RedPacketClaim
	if tx.Where("red_packet_id = ? AND user_id = ?", redPacket.ID, userID).First(&existClaim).Error == nil {
		tx.Rollback()
		response.Error(c, http.StatusBadRequest, "您已领取过该红包")
		return
	}

	// 计算领取金额
	var claimAmount float64
	if redPacket.Type == models.RedPacketTypeLucky {
		// 拼手气红包 - 随机金额
		claimAmount = h.calculateLuckyAmount(redPacket.RemainingAmount, redPacket.RemainingCount)
	} else {
		// 普通红包 - 平均金额（使用剩余金额/剩余数量，确保最后一个能领完）
		if redPacket.RemainingCount == 1 {
			// 最后一个红包，领取全部剩余金额
			claimAmount = math.Round(redPacket.RemainingAmount*100) / 100
		} else {
			claimAmount = math.Round(redPacket.TotalAmount/float64(redPacket.TotalCount)*100) / 100
		}
	}

	// 确保领取金额不超过剩余金额
	if claimAmount > redPacket.RemainingAmount {
		claimAmount = math.Round(redPacket.RemainingAmount*100) / 100
	}

	// FOR UPDATE 锁定用户钱包
	var wallet models.Wallet
	if err := tx.Clauses(clause.Locking{Strength: "UPDATE"}).
		Where("user_id = ?", userID).First(&wallet).Error; err != nil {
		// 钱包不存在，创建一个
		wallet = models.Wallet{
			UserID:    userID,
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

	// 更新红包
	updateData := map[string]interface{}{
		"remaining_amount": redPacket.RemainingAmount - claimAmount,
		"remaining_count":  redPacket.RemainingCount - 1,
		"updated_at":       time.Now(),
	}
	if redPacket.RemainingCount-1 == 0 {
		updateData["status"] = models.RedPacketStatusFinished
	}
	if err := tx.Model(&redPacket).Updates(updateData).Error; err != nil {
		tx.Rollback()
		response.Error(c, http.StatusInternalServerError, "领取失败")
		return
	}

	// 更新本地变量以便后续使用
	redPacket.RemainingAmount -= claimAmount
	redPacket.RemainingCount--
	if redPacket.RemainingCount == 0 {
		redPacket.Status = models.RedPacketStatusFinished
	}

	// 创建领取记录
	claim := models.RedPacketClaim{
		RedPacketID: redPacket.ID,
		UserID:      userID,
		Amount:      claimAmount,
		CreatedAt:   time.Now(),
	}

	// 检查是否是手气最佳（最后一个领取时计算）
	if redPacket.RemainingCount == 0 && redPacket.Type == models.RedPacketTypeLucky {
		var claims []models.RedPacketClaim
		tx.Where("red_packet_id = ?", redPacket.ID).Find(&claims)
		claims = append(claims, claim)

		maxAmount := claimAmount
		maxIdx := len(claims) - 1
		for i, c := range claims {
			if c.Amount > maxAmount {
				maxAmount = c.Amount
				maxIdx = i
			}
		}
		if maxIdx == len(claims)-1 {
			claim.IsBest = true
		} else {
			tx.Model(&claims[maxIdx]).Update("is_best", true)
		}
	}

	if err := tx.Create(&claim).Error; err != nil {
		tx.Rollback()
		response.Error(c, http.StatusInternalServerError, "领取失败")
		return
	}

	// 原子更新用户余额
	newBalance := wallet.Balance + claimAmount
	if err := tx.Model(&wallet).Updates(map[string]interface{}{
		"balance":    gorm.Expr("balance + ?", claimAmount),
		"updated_at": time.Now(),
	}).Error; err != nil {
		tx.Rollback()
		response.Error(c, http.StatusInternalServerError, "领取失败")
		return
	}

	// 记录交易
	var sender models.User
	h.db.First(&sender, redPacket.SenderID)

	transaction := models.Transaction{
		UserID:          userID,
		Type:            models.TransactionTypeRedPacketReceive,
		Amount:          claimAmount,
		BalanceAfter:    newBalance,
		RelatedID:       redPacket.UUID,
		RelatedUserID:   &redPacket.SenderID,
		RelatedUserName: sender.Nickname,
		Remark:          "领取红包",
		CreatedAt:       time.Now(),
	}
	if err := tx.Create(&transaction).Error; err != nil {
		tx.Rollback()
		response.Error(c, http.StatusInternalServerError, "领取失败")
		return
	}

	// 提交事务
	if err := tx.Commit().Error; err != nil {
		response.Error(c, http.StatusInternalServerError, "领取失败")
		return
	}

	// 严格加密模式下不再追加明文钱包系统通知，避免绕过消息加密策略。
	if h.walletChatMessagesBlocked() {
		response.Success(c, gin.H{
			"amount":  claimAmount,
			"is_best": claim.IsBest,
			"message": "领取成功",
		})
		return
	}

	// 发送红包领取通知到聊天
	if h.msgService != nil && redPacket.ChatID != "" {
		// 构建领取通知内容
		claimNotice := map[string]interface{}{
			"type":            "red_packet_claimed",
			"red_packet_id":   redPacket.UUID,
			"claimer_id":      claimer.UUID,
			"claimer_name":    claimer.Nickname,
			"claimer_avatar":  claimer.Avatar,
			"sender_id":       sender.UUID,
			"sender_name":     sender.Nickname,
			"amount":          claimAmount,
			"is_best":         claim.IsBest,
			"remaining_count": redPacket.RemainingCount,
			"total_count":     redPacket.TotalCount,
		}
		contentJSON, _ := json.Marshal(claimNotice)

		// 获取聊天成员
		var chatMembers []models.ChatMember
		h.db.Where("chat_id = (SELECT id FROM chats WHERE uuid = ?)", redPacket.ChatID).Find(&chatMembers)

		targetUserIDs := make([]string, 0)
		for _, member := range chatMembers {
			var memberUser models.User
			if h.db.First(&memberUser, member.UserID).Error == nil {
				targetUserIDs = append(targetUserIDs, memberUser.UUID)
			}
		}

		if len(targetUserIDs) > 0 {
			params := &services.SendMessageParams{
				ChatID:   redPacket.ChatID,
				MsgID:    fmt.Sprintf("red_packet_claimed:%s:%s", redPacket.UUID, claimer.UUID),
				SenderID: claimer.UUID,
				Type:     models.MsgTypeSystem,
				Content: map[string]interface{}{
					"text": string(contentJSON),
				},
			}
			h.sendChatMessageWithRetry(context.Background(), params, claimer.Nickname, claimer.Avatar, claimer.NicknameColor, claimer.PremiumType, claimer.EmojiAvatar, targetUserIDs)
		}
	}

	response.Success(c, gin.H{
		"amount":  claimAmount,
		"is_best": claim.IsBest,
		"message": "领取成功",
	})
}

// GetRedPacket 获取红包详情
func (h *WalletHandler) GetRedPacket(c *gin.Context) {
	userID, err := h.getUserIDFromContext(c)
	if err != nil {
		response.Error(c, http.StatusUnauthorized, "用户未登录")
		return
	}
	redPacketID := c.Param("id")

	var redPacket models.RedPacket
	if err := h.db.Where("uuid = ?", redPacketID).First(&redPacket).Error; err != nil {
		response.Error(c, http.StatusNotFound, "红包不存在")
		return
	}

	// 获取发送者信息
	var sender models.User
	h.db.First(&sender, redPacket.SenderID)

	// 检查是否已领取
	var claim models.RedPacketClaim
	isClaimed := h.db.Where("red_packet_id = ? AND user_id = ?", redPacket.ID, userID).First(&claim).Error == nil

	// 获取领取列表
	var claims []models.RedPacketClaim
	h.db.Where("red_packet_id = ?", redPacket.ID).Order("created_at").Find(&claims)

	claimList := make([]gin.H, len(claims))
	for i, c := range claims {
		var user models.User
		h.db.First(&user, c.UserID)
		claimList[i] = gin.H{
			"user_id":     user.UUID,
			"user_name":   user.Nickname,
			"user_avatar": user.Avatar,
			"amount":      c.Amount,
			"is_best":     c.IsBest,
			"created_at":  c.CreatedAt,
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
		"is_claimed":       isClaimed,
		"claimed_amount":   claim.Amount,
		"claims":           claimList,
		"expired_at":       redPacket.ExpiredAt,
		"created_at":       redPacket.CreatedAt,
	})
}

// SendTransfer 发起转账
func (h *WalletHandler) SendTransfer(c *gin.Context) {
	userID, err := h.getUserIDFromContext(c)
	if err != nil {
		response.Error(c, http.StatusUnauthorized, "用户未登录")
		return
	}

	var req struct {
		ReceiverID  string  `json:"receiver_id" binding:"required"`
		Amount      float64 `json:"amount" binding:"required,gt=0"`
		Remark      string  `json:"remark"`
		PayPassword string  `json:"pay_password" binding:"required"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		response.Error(c, http.StatusBadRequest, "参数错误")
		return
	}

	// 检查钱包是否锁定
	if h.checkWalletLocked(userID) {
		response.Error(c, http.StatusForbidden, "钱包已锁定，无法操作")
		return
	}

	// 查找接收者
	var receiver models.User
	if err := h.db.Where("uuid = ?", req.ReceiverID).First(&receiver).Error; err != nil {
		response.Error(c, http.StatusNotFound, "用户不存在")
		return
	}

	if receiver.ID == userID {
		response.Error(c, http.StatusBadRequest, "不能给自己转账")
		return
	}

	// 预先验证支付密码
	walletCheck, err := h.getOrCreateWallet(userID)
	if err != nil {
		response.Error(c, http.StatusInternalServerError, "获取钱包失败")
		return
	}
	if !walletCheck.CheckPayPassword(req.PayPassword) {
		response.Error(c, http.StatusBadRequest, "支付密码错误")
		return
	}

	// 获取发送者信息
	var sender models.User
	h.db.First(&sender, userID)

	chat, err := h.findTransferChat(sender.ID, receiver.ID)
	if err != nil {
		response.Error(c, http.StatusBadRequest, "私聊会话不存在或不可用")
		return
	}
	if h.rejectWalletChatMessageInStrictMode(c, "转账") {
		return
	}

	// 事务内操作：锁定钱包 -> 验证余额 -> 扣减 -> 创建转账 -> 记录交易
	tx := h.db.Begin()
	defer func() {
		if r := recover(); r != nil {
			tx.Rollback()
		}
	}()

	// FOR UPDATE 锁定钱包行
	var wallet models.Wallet
	if err := tx.Clauses(clause.Locking{Strength: "UPDATE"}).
		Where("user_id = ?", userID).First(&wallet).Error; err != nil {
		tx.Rollback()
		response.Error(c, http.StatusInternalServerError, "获取钱包失败")
		return
	}

	// 锁定后验证余额
	if wallet.Balance < req.Amount {
		tx.Rollback()
		response.Error(c, http.StatusBadRequest, "余额不足")
		return
	}

	// 原子扣减余额
	newBalance := wallet.Balance - req.Amount
	if err := tx.Model(&wallet).Updates(map[string]interface{}{
		"balance":    gorm.Expr("balance - ?", req.Amount),
		"updated_at": time.Now(),
	}).Error; err != nil {
		tx.Rollback()
		response.Error(c, http.StatusInternalServerError, "转账失败")
		return
	}

	// 创建转账记录
	transfer := models.Transfer{
		UUID:       uuid.New().String(),
		SenderID:   userID,
		ReceiverID: receiver.ID,
		Amount:     req.Amount,
		Remark:     req.Remark,
		Status:     models.TransferStatusPending,
		ExpiredAt:  time.Now().Add(h.getExpireHours(models.SettingTransferExpireHours, 24)),
		CreatedAt:  time.Now(),
		UpdatedAt:  time.Now(),
	}
	if err := tx.Create(&transfer).Error; err != nil {
		tx.Rollback()
		response.Error(c, http.StatusInternalServerError, "转账失败")
		return
	}

	// 记录交易
	transaction := models.Transaction{
		UserID:          userID,
		Type:            models.TransactionTypeTransferOut,
		Amount:          -req.Amount,
		BalanceAfter:    newBalance,
		RelatedID:       transfer.UUID,
		RelatedUserID:   &receiver.ID,
		RelatedUserName: receiver.Nickname,
		Remark:          "转账-转出",
		CreatedAt:       time.Now(),
	}
	if err := tx.Create(&transaction).Error; err != nil {
		tx.Rollback()
		response.Error(c, http.StatusInternalServerError, "转账失败")
		return
	}

	if err := tx.Commit().Error; err != nil {
		response.Error(c, http.StatusInternalServerError, "转账失败")
		return
	}

	// 构建转账消息内容
	transferContent := map[string]interface{}{
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
		"expired_at":      transfer.ExpiredAt.Format(time.RFC3339),
		"created_at":      transfer.CreatedAt.Format(time.RFC3339),
	}

	if h.msgService != nil {
		contentJSON, _ := json.Marshal(transferContent)
		params := &services.SendMessageParams{
			ChatID:   chat.UUID,
			MsgID:    fmt.Sprintf("transfer:%s", transfer.UUID),
			SenderID: sender.UUID,
			Type:     models.MsgTypeTransfer,
			Content: map[string]interface{}{
				"text": string(contentJSON),
			},
		}
		h.sendChatMessageWithRetry(context.Background(), params, sender.Nickname, sender.Avatar, sender.NicknameColor, sender.PremiumType, sender.EmojiAvatar, []string{receiver.UUID})
	}

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
		"created_at":      transfer.CreatedAt,
	})
}

// AcceptTransfer 接收转账
func (h *WalletHandler) AcceptTransfer(c *gin.Context) {
	userID, err := h.getUserIDFromContext(c)
	if err != nil {
		response.Error(c, http.StatusUnauthorized, "用户未登录")
		return
	}
	transferID := c.Param("id")

	// 确保接收者钱包存在
	h.getOrCreateWallet(userID)

	// 事务内操作：锁定转账行 + 钱包行 -> 验证 -> 更新
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

	// 验证是接收者
	if transfer.ReceiverID != userID {
		tx.Rollback()
		response.Error(c, http.StatusForbidden, "无权操作")
		return
	}

	// 检查状态（在锁定后检查，防止并发）
	if transfer.Status != models.TransferStatusPending {
		tx.Rollback()
		response.Error(c, http.StatusBadRequest, "转账已处理")
		return
	}

	// 检查过期
	if time.Now().After(transfer.ExpiredAt) {
		tx.Model(&transfer).Update("status", models.TransferStatusExpired)
		tx.Commit()
		response.Error(c, http.StatusBadRequest, "转账已过期")
		return
	}

	// FOR UPDATE 锁定钱包行
	var wallet models.Wallet
	if err := tx.Clauses(clause.Locking{Strength: "UPDATE"}).
		Where("user_id = ?", userID).First(&wallet).Error; err != nil {
		tx.Rollback()
		response.Error(c, http.StatusInternalServerError, "获取钱包失败")
		return
	}

	// 更新转账状态
	now := time.Now()
	if err := tx.Model(&transfer).Updates(map[string]interface{}{
		"status":      models.TransferStatusAccepted,
		"accepted_at": now,
		"updated_at":  now,
	}).Error; err != nil {
		tx.Rollback()
		response.Error(c, http.StatusInternalServerError, "接收失败")
		return
	}

	// 原子更新余额
	newBalance := wallet.Balance + transfer.Amount
	if err := tx.Model(&wallet).Updates(map[string]interface{}{
		"balance":    gorm.Expr("balance + ?", transfer.Amount),
		"updated_at": time.Now(),
	}).Error; err != nil {
		tx.Rollback()
		response.Error(c, http.StatusInternalServerError, "接收失败")
		return
	}

	// 记录交易
	var sender models.User
	h.db.First(&sender, transfer.SenderID)

	transaction := models.Transaction{
		UserID:          userID,
		Type:            models.TransactionTypeTransferIn,
		Amount:          transfer.Amount,
		BalanceAfter:    newBalance,
		RelatedID:       transfer.UUID,
		RelatedUserID:   &transfer.SenderID,
		RelatedUserName: sender.Nickname,
		Remark:          "转账-转入",
		CreatedAt:       time.Now(),
	}
	if err := tx.Create(&transaction).Error; err != nil {
		tx.Rollback()
		response.Error(c, http.StatusInternalServerError, "接收失败")
		return
	}

	if err := tx.Commit().Error; err != nil {
		response.Error(c, http.StatusInternalServerError, "接收失败")
		return
	}

	// 发送收款通知给转账发送者
	if h.msgService != nil {
		var receiver models.User
		h.db.First(&receiver, userID)

		if h.walletChatMessagesBlocked() {
			response.Success(c, gin.H{
				"message": "收款成功",
				"amount":  transfer.Amount,
			})
			return
		}

		// 通过 chat_members 查找私聊会话
		var chatID uint64
		row := h.db.Raw(`
			SELECT c.id FROM chats c
			INNER JOIN chat_members cm1 ON c.id = cm1.chat_id AND cm1.user_id = ?
			INNER JOIN chat_members cm2 ON c.id = cm2.chat_id AND cm2.user_id = ?
			WHERE c.type = 1 AND c.deleted_at IS NULL
			LIMIT 1
		`, sender.ID, receiver.ID).Row()
		if row.Scan(&chatID) == nil && chatID > 0 {
			var chat models.Chat
			if h.db.First(&chat, chatID).Error == nil {
				notice := map[string]interface{}{
					"type":          "transfer_accepted",
					"transfer_id":   transfer.UUID,
					"sender_id":     sender.UUID,
					"sender_name":   sender.Nickname,
					"receiver_id":   receiver.UUID,
					"receiver_name": receiver.Nickname,
					"amount":        transfer.Amount,
				}
				contentJSON, _ := json.Marshal(notice)
				params := &services.SendMessageParams{
					ChatID:   chat.UUID,
					MsgID:    fmt.Sprintf("transfer_accepted:%s", transfer.UUID),
					SenderID: receiver.UUID,
					Type:     models.MsgTypeSystem,
					Content: map[string]interface{}{
						"text": string(contentJSON),
					},
				}
				h.sendChatMessageWithRetry(context.Background(), params, receiver.Nickname, receiver.Avatar, receiver.NicknameColor, receiver.PremiumType, receiver.EmojiAvatar, []string{sender.UUID, receiver.UUID})
			}
		}
	}

	response.Success(c, gin.H{
		"message": "收款成功",
		"amount":  transfer.Amount,
	})
}

// RejectTransfer 拒收转账
func (h *WalletHandler) RejectTransfer(c *gin.Context) {
	userID, err := h.getUserIDFromContext(c)
	if err != nil {
		response.Error(c, http.StatusUnauthorized, "用户未登录")
		return
	}
	transferID := c.Param("id")

	// 事务内操作：锁定转账行 + 发送者钱包行 -> 验证 -> 退款
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

	if transfer.ReceiverID != userID {
		tx.Rollback()
		response.Error(c, http.StatusForbidden, "无权操作")
		return
	}

	// 锁定后检查状态
	if transfer.Status != models.TransferStatusPending {
		tx.Rollback()
		response.Error(c, http.StatusBadRequest, "转账已处理")
		return
	}

	// 更新转账状态
	if err := tx.Model(&transfer).Updates(map[string]interface{}{
		"status":     models.TransferStatusRejected,
		"updated_at": time.Now(),
	}).Error; err != nil {
		tx.Rollback()
		response.Error(c, http.StatusInternalServerError, "操作失败")
		return
	}

	// FOR UPDATE 锁定发送者钱包行并退款
	var senderWallet models.Wallet
	if err := tx.Clauses(clause.Locking{Strength: "UPDATE"}).
		Where("user_id = ?", transfer.SenderID).First(&senderWallet).Error; err != nil {
		tx.Rollback()
		response.Error(c, http.StatusInternalServerError, "退款失败")
		return
	}

	newBalance := senderWallet.Balance + transfer.Amount
	if err := tx.Model(&senderWallet).Updates(map[string]interface{}{
		"balance":    gorm.Expr("balance + ?", transfer.Amount),
		"updated_at": time.Now(),
	}).Error; err != nil {
		tx.Rollback()
		response.Error(c, http.StatusInternalServerError, "操作失败")
		return
	}

	// 获取接收者信息
	var receiver models.User
	h.db.First(&receiver, userID)

	// 记录退款交易
	refundTx := models.Transaction{
		UserID:          transfer.SenderID,
		Type:            models.TransactionTypeRefund,
		Amount:          transfer.Amount,
		BalanceAfter:    newBalance,
		RelatedID:       transfer.UUID,
		RelatedUserID:   &userID,
		RelatedUserName: receiver.Nickname,
		Remark:          "转账被拒收-退回",
		CreatedAt:       time.Now(),
	}
	if err := tx.Create(&refundTx).Error; err != nil {
		tx.Rollback()
		response.Error(c, http.StatusInternalServerError, "操作失败")
		return
	}

	if err := tx.Commit().Error; err != nil {
		response.Error(c, http.StatusInternalServerError, "操作失败")
		return
	}

	response.Success(c, gin.H{"message": "已拒收"})
}

// GetTransfer 获取转账详情
func (h *WalletHandler) GetTransfer(c *gin.Context) {
	userID, err := h.getUserIDFromContext(c)
	if err != nil {
		response.Error(c, http.StatusUnauthorized, "用户未登录")
		return
	}
	transferID := c.Param("id")

	var transfer models.Transfer
	if err := h.db.Where("uuid = ?", transferID).First(&transfer).Error; err != nil {
		response.Error(c, http.StatusNotFound, "转账不存在")
		return
	}

	// 验证权限
	if transfer.SenderID != userID && transfer.ReceiverID != userID {
		response.Error(c, http.StatusForbidden, "无权查看")
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

// GetWalletSettings 获取钱包设置（App端）
func (h *WalletHandler) GetWalletSettings(c *gin.Context) {
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

// GetRechargeMethods 获取充值方式列表（App端）
func (h *WalletHandler) GetRechargeMethods(c *gin.Context) {
	var methods []models.RechargeMethod
	h.db.Where("status = 1").Order("sort ASC, id ASC").Find(&methods)
	response.Success(c, methods)
}

// CreateRechargeOrder 用户提交充值订单（上传凭证）
func (h *WalletHandler) CreateRechargeOrder(c *gin.Context) {
	userID, err := h.getUserIDFromContext(c)
	if err != nil {
		response.Error(c, http.StatusUnauthorized, "用户未登录")
		return
	}

	var req struct {
		MethodID   uint64  `json:"method_id" binding:"required"`
		Amount     float64 `json:"amount" binding:"required,gt=0"`
		ProofImage string  `json:"proof_image"` // 付款凭证截图URL
		Remark     string  `json:"remark"`      // 备注
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		response.Error(c, http.StatusBadRequest, "参数错误")
		return
	}

	// 验证充值方式
	var method models.RechargeMethod
	if err := h.db.First(&method, req.MethodID).Error; err != nil {
		response.Error(c, http.StatusNotFound, "充值方式不存在")
		return
	}

	// 验证金额范围
	if req.Amount < method.MinAmount || req.Amount > method.MaxAmount {
		response.Error(c, http.StatusBadRequest, fmt.Sprintf("充值金额需在%.0f-%.0f之间", method.MinAmount, method.MaxAmount))
		return
	}

	order := models.RechargeOrder{
		UserID:     userID,
		MethodID:   req.MethodID,
		Amount:     req.Amount,
		ProofImage: req.ProofImage,
		Remark:     req.Remark,
		Status:     models.RechargeOrderPending,
		CreatedAt:  time.Now(),
		UpdatedAt:  time.Now(),
	}
	if err := h.db.Create(&order).Error; err != nil {
		response.Error(c, http.StatusInternalServerError, "提交失败")
		return
	}

	response.Success(c, gin.H{
		"id":      order.ID,
		"amount":  order.Amount,
		"status":  order.Status,
		"message": "充值申请已提交，等待审核",
	})
}

// GetRechargeOrders 用户查询自己的充值订单
func (h *WalletHandler) GetRechargeOrders(c *gin.Context) {
	userID, err := h.getUserIDFromContext(c)
	if err != nil {
		response.Error(c, http.StatusUnauthorized, "用户未登录")
		return
	}

	var orders []models.RechargeOrder
	h.db.Where("user_id = ?", userID).Order("created_at DESC").Limit(50).Find(&orders)

	result := make([]gin.H, len(orders))
	for i, o := range orders {
		var method models.RechargeMethod
		h.db.First(&method, o.MethodID)
		result[i] = gin.H{
			"id":          o.ID,
			"method_name": method.Name,
			"amount":      o.Amount,
			"proof_image": o.ProofImage,
			"remark":      o.Remark,
			"status":      o.Status,
			"created_at":  o.CreatedAt,
		}
	}
	response.Success(c, result)
}

// GetWithdrawMethods 获取提现方式列表
func (h *WalletHandler) GetWithdrawMethods(c *gin.Context) {
	var methods []models.WithdrawMethod
	h.db.Where("status = 1").Order("sort ASC").Find(&methods)

	response.Success(c, methods)
}

// CreateWithdrawRequest 发起提现申请
func (h *WalletHandler) CreateWithdrawRequest(c *gin.Context) {
	userID, err := h.getUserIDFromContext(c)
	if err != nil {
		response.Error(c, http.StatusUnauthorized, "用户未登录")
		return
	}

	var req struct {
		MethodID    uint64  `json:"method_id" binding:"required"`
		Amount      float64 `json:"amount" binding:"required,gt=0"`
		FormData    string  `json:"form_data" binding:"required"`
		PayPassword string  `json:"pay_password" binding:"required"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		response.Error(c, http.StatusBadRequest, "参数错误")
		return
	}

	// 检查钱包是否锁定
	if h.checkWalletLocked(userID) {
		response.Error(c, http.StatusForbidden, "钱包已锁定，无法操作")
		return
	}

	// 查找提现方式
	var method models.WithdrawMethod
	if err := h.db.First(&method, req.MethodID).Error; err != nil {
		response.Error(c, http.StatusNotFound, "提现方式不存在")
		return
	}

	// 验证金额范围
	if req.Amount < method.MinAmount || req.Amount > method.MaxAmount {
		response.Error(c, http.StatusBadRequest, fmt.Sprintf("提现金额需在%.2f-%.2f之间", method.MinAmount, method.MaxAmount))
		return
	}

	// 预先验证支付密码
	walletCheck, err := h.getOrCreateWallet(userID)
	if err != nil {
		response.Error(c, http.StatusInternalServerError, "获取钱包失败")
		return
	}
	if !walletCheck.CheckPayPassword(req.PayPassword) {
		response.Error(c, http.StatusBadRequest, "支付密码错误")
		return
	}

	// 计算手续费
	fee := req.Amount * method.Fee / 100
	actualAmount := req.Amount - fee

	// 事务内操作：锁定钱包 -> 验证余额 -> 冻结 -> 创建申请
	tx := h.db.Begin()
	defer func() {
		if r := recover(); r != nil {
			tx.Rollback()
		}
	}()

	// FOR UPDATE 锁定钱包行
	var wallet models.Wallet
	if err := tx.Clauses(clause.Locking{Strength: "UPDATE"}).
		Where("user_id = ?", userID).First(&wallet).Error; err != nil {
		tx.Rollback()
		response.Error(c, http.StatusInternalServerError, "获取钱包失败")
		return
	}

	// 锁定后验证余额
	if wallet.Balance < req.Amount {
		tx.Rollback()
		response.Error(c, http.StatusBadRequest, "余额不足")
		return
	}

	// 原子冻结余额
	if err := tx.Model(&wallet).Updates(map[string]interface{}{
		"balance":        gorm.Expr("balance - ?", req.Amount),
		"frozen_balance": gorm.Expr("frozen_balance + ?", req.Amount),
		"updated_at":     time.Now(),
	}).Error; err != nil {
		tx.Rollback()
		response.Error(c, http.StatusInternalServerError, "提现失败")
		return
	}

	// 创建提现申请
	withdrawReq := models.WithdrawRequest{
		UserID:       userID,
		MethodID:     req.MethodID,
		Amount:       req.Amount,
		Fee:          fee,
		ActualAmount: actualAmount,
		FormData:     req.FormData,
		Status:       models.WithdrawStatusPending,
		CreatedAt:    time.Now(),
		UpdatedAt:    time.Now(),
	}
	if err := tx.Create(&withdrawReq).Error; err != nil {
		tx.Rollback()
		response.Error(c, http.StatusInternalServerError, "提现失败")
		return
	}

	if err := tx.Commit().Error; err != nil {
		response.Error(c, http.StatusInternalServerError, "提现失败")
		return
	}

	response.Success(c, gin.H{
		"id":            withdrawReq.ID,
		"amount":        withdrawReq.Amount,
		"fee":           withdrawReq.Fee,
		"actual_amount": withdrawReq.ActualAmount,
		"status":        withdrawReq.Status,
		"message":       "提现申请已提交",
	})
}

// 辅助函数

// getUserIDFromContext 从上下文获取用户ID（从UUID转换为数据库ID）
func (h *WalletHandler) getUserIDFromContext(c *gin.Context) (uint64, error) {
	userUUID := c.GetString("user_id")
	if userUUID == "" {
		return 0, fmt.Errorf("user_id not found in context")
	}

	var user models.User
	if err := h.db.Where("uuid = ?", userUUID).First(&user).Error; err != nil {
		return 0, err
	}
	return user.ID, nil
}

func (h *WalletHandler) getOrCreateWallet(userID uint64) (*models.Wallet, error) {
	var wallet models.Wallet
	err := h.db.Where("user_id = ?", userID).First(&wallet).Error
	if err == gorm.ErrRecordNotFound {
		wallet = models.Wallet{
			UserID:    userID,
			Balance:   0,
			CreatedAt: time.Now(),
			UpdatedAt: time.Now(),
		}
		if err := h.db.Create(&wallet).Error; err != nil {
			return nil, err
		}
	} else if err != nil {
		return nil, err
	}
	return &wallet, nil
}

// getExpireHours 从系统设置读取过期小时数
func (h *WalletHandler) getExpireHours(key string, defaultHours int) time.Duration {
	var setting models.SystemSetting
	if h.db.Where("`key` = ?", key).First(&setting).Error == nil && setting.Value != "" {
		n := 0
		for _, c := range setting.Value {
			if c >= '0' && c <= '9' {
				n = n*10 + int(c-'0')
			}
		}
		if n > 0 {
			return time.Duration(n) * time.Hour
		}
	}
	return time.Duration(defaultHours) * time.Hour
}

// checkWalletLocked 检查钱包是否锁定
func (h *WalletHandler) checkWalletLocked(userID uint64) bool {
	var wallet models.Wallet
	if h.db.Where("user_id = ?", userID).First(&wallet).Error == nil {
		return wallet.IsLocked
	}
	return false
}

func (h *WalletHandler) calculateLuckyAmount(remaining float64, count int) float64 {
	if count == 1 {
		return math.Round(remaining*100) / 100
	}

	// 二倍均值法
	avg := remaining / float64(count)
	max := avg * 2
	min := 0.01

	amount := min + rand.Float64()*(max-min)
	amount = math.Round(amount*100) / 100

	// 确保剩余金额足够分配
	if remaining-amount < 0.01*float64(count-1) {
		amount = remaining - 0.01*float64(count-1)
	}

	return math.Max(0.01, math.Round(amount*100)/100)
}

func getQueryInt(c *gin.Context, key string, defaultVal int) int {
	val := c.Query(key)
	if val == "" {
		return defaultVal
	}
	var result int
	fmt.Sscanf(val, "%d", &result)
	if result <= 0 {
		return defaultVal
	}
	return result
}
