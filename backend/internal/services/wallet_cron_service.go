package services

import (
	"log"
	"time"

	"gaoranim/internal/models"

	"gorm.io/gorm"
	"gorm.io/gorm/clause"
)

// WalletCronService 钱包定时任务服务
type WalletCronService struct {
	db       *gorm.DB
	stopChan chan struct{}
}

func NewWalletCronService(db *gorm.DB) *WalletCronService {
	return &WalletCronService{
		db:       db,
		stopChan: make(chan struct{}),
	}
}

// Start 启动定时任务（每分钟执行一次）
func (s *WalletCronService) Start() {
	go func() {
		ticker := time.NewTicker(1 * time.Minute)
		defer ticker.Stop()

		// 启动时立即执行一次
		s.processExpiredRedPackets()
		s.processExpiredTransfers()

		for {
			select {
			case <-ticker.C:
				s.processExpiredRedPackets()
				s.processExpiredTransfers()
			case <-s.stopChan:
				log.Println("[WalletCron] 定时任务已停止")
				return
			}
		}
	}()
	log.Println("[WalletCron] 定时任务已启动")
}

// Stop 停止定时任务
func (s *WalletCronService) Stop() {
	close(s.stopChan)
}

// processExpiredRedPackets 处理过期红包 —— 退还剩余金额给发送者
func (s *WalletCronService) processExpiredRedPackets() {
	var redPackets []models.RedPacket
	s.db.Where("status = ? AND expired_at < ?", models.RedPacketStatusActive, time.Now()).
		Limit(100).
		Find(&redPackets)

	if len(redPackets) == 0 {
		return
	}

	log.Printf("[WalletCron] 发现 %d 个过期红包待处理", len(redPackets))

	for _, rp := range redPackets {
		s.refundExpiredRedPacket(rp)
	}
}

// refundExpiredRedPacket 退还单个过期红包
func (s *WalletCronService) refundExpiredRedPacket(rp models.RedPacket) {
	tx := s.db.Begin()
	defer func() {
		if r := recover(); r != nil {
			tx.Rollback()
		}
	}()

	// FOR UPDATE 锁定红包
	var redPacket models.RedPacket
	if err := tx.Clauses(clause.Locking{Strength: "UPDATE"}).
		First(&redPacket, rp.ID).Error; err != nil {
		tx.Rollback()
		return
	}

	// 再次检查状态（可能已被其他协程处理）
	if redPacket.Status != models.RedPacketStatusActive {
		tx.Rollback()
		return
	}

	refundAmount := redPacket.RemainingAmount
	if refundAmount <= 0 {
		// 没有剩余金额，直接标记过期
		tx.Model(&redPacket).Updates(map[string]interface{}{
			"status":     models.RedPacketStatusExpired,
			"updated_at": time.Now(),
		})
		tx.Commit()
		return
	}

	// FOR UPDATE 锁定发送者钱包
	var wallet models.Wallet
	if err := tx.Clauses(clause.Locking{Strength: "UPDATE"}).
		Where("user_id = ?", redPacket.SenderID).First(&wallet).Error; err != nil {
		tx.Rollback()
		log.Printf("[WalletCron] 红包 %s 发送者钱包不存在", redPacket.UUID)
		return
	}

	newBalance := wallet.Balance + refundAmount

	// 原子退还余额
	if err := tx.Model(&wallet).Updates(map[string]interface{}{
		"balance":    gorm.Expr("balance + ?", refundAmount),
		"updated_at": time.Now(),
	}).Error; err != nil {
		tx.Rollback()
		log.Printf("[WalletCron] 红包 %s 退款失败: %v", redPacket.UUID, err)
		return
	}

	// 标记红包过期
	if err := tx.Model(&redPacket).Updates(map[string]interface{}{
		"status":           models.RedPacketStatusExpired,
		"remaining_amount": 0,
		"updated_at":       time.Now(),
	}).Error; err != nil {
		tx.Rollback()
		log.Printf("[WalletCron] 红包 %s 状态更新失败: %v", redPacket.UUID, err)
		return
	}

	// 记录退款交易
	if err := tx.Create(&models.Transaction{
		UserID:       redPacket.SenderID,
		Type:         models.TransactionTypeRefund,
		Amount:       refundAmount,
		BalanceAfter: newBalance,
		RelatedID:    redPacket.UUID,
		Remark:       "红包过期退回",
		CreatedAt:    time.Now(),
	}).Error; err != nil {
		tx.Rollback()
		log.Printf("[WalletCron] 红包 %s 交易记录失败: %v", redPacket.UUID, err)
		return
	}

	if err := tx.Commit().Error; err != nil {
		log.Printf("[WalletCron] 红包 %s 提交失败: %v", redPacket.UUID, err)
		return
	}

	log.Printf("[WalletCron] 红包 %s 已过期退回 %.2f 元", redPacket.UUID, refundAmount)
}

// processExpiredTransfers 处理过期转账 —— 退还金额给发送者
func (s *WalletCronService) processExpiredTransfers() {
	var transfers []models.Transfer
	s.db.Where("status = ? AND expired_at < ?", models.TransferStatusPending, time.Now()).
		Limit(100).
		Find(&transfers)

	if len(transfers) == 0 {
		return
	}

	log.Printf("[WalletCron] 发现 %d 个过期转账待处理", len(transfers))

	for _, tf := range transfers {
		s.refundExpiredTransfer(tf)
	}
}

// refundExpiredTransfer 退还单个过期转账
func (s *WalletCronService) refundExpiredTransfer(tf models.Transfer) {
	tx := s.db.Begin()
	defer func() {
		if r := recover(); r != nil {
			tx.Rollback()
		}
	}()

	// FOR UPDATE 锁定转账行
	var transfer models.Transfer
	if err := tx.Clauses(clause.Locking{Strength: "UPDATE"}).
		First(&transfer, tf.ID).Error; err != nil {
		tx.Rollback()
		return
	}

	if transfer.Status != models.TransferStatusPending {
		tx.Rollback()
		return
	}

	// FOR UPDATE 锁定发送者钱包
	var wallet models.Wallet
	if err := tx.Clauses(clause.Locking{Strength: "UPDATE"}).
		Where("user_id = ?", transfer.SenderID).First(&wallet).Error; err != nil {
		tx.Rollback()
		log.Printf("[WalletCron] 转账 %s 发送者钱包不存在", transfer.UUID)
		return
	}

	newBalance := wallet.Balance + transfer.Amount

	// 原子退还余额
	if err := tx.Model(&wallet).Updates(map[string]interface{}{
		"balance":    gorm.Expr("balance + ?", transfer.Amount),
		"updated_at": time.Now(),
	}).Error; err != nil {
		tx.Rollback()
		log.Printf("[WalletCron] 转账 %s 退款失败: %v", transfer.UUID, err)
		return
	}

	// 标记转账过期
	if err := tx.Model(&transfer).Updates(map[string]interface{}{
		"status":     models.TransferStatusExpired,
		"updated_at": time.Now(),
	}).Error; err != nil {
		tx.Rollback()
		log.Printf("[WalletCron] 转账 %s 状态更新失败: %v", transfer.UUID, err)
		return
	}

	// 记录退款交易
	if err := tx.Create(&models.Transaction{
		UserID:       transfer.SenderID,
		Type:         models.TransactionTypeRefund,
		Amount:       transfer.Amount,
		BalanceAfter: newBalance,
		RelatedID:    transfer.UUID,
		Remark:       "转账过期退回",
		CreatedAt:    time.Now(),
	}).Error; err != nil {
		tx.Rollback()
		log.Printf("[WalletCron] 转账 %s 交易记录失败: %v", transfer.UUID, err)
		return
	}

	if err := tx.Commit().Error; err != nil {
		log.Printf("[WalletCron] 转账 %s 提交失败: %v", transfer.UUID, err)
		return
	}

	log.Printf("[WalletCron] 转账 %s 已过期退回 %.2f 元", transfer.UUID, transfer.Amount)
}
