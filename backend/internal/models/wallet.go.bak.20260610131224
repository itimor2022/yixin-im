package models

import (
	"time"

	"golang.org/x/crypto/bcrypt"
	"gorm.io/gorm"
)

// Wallet 钱包表
type Wallet struct {
	ID            uint64         `gorm:"primaryKey;autoIncrement" json:"id"`
	UserID        uint64         `gorm:"uniqueIndex;not null" json:"user_id"`
	Balance       float64        `gorm:"type:decimal(12,2);default:0" json:"balance"`
	FrozenBalance float64        `gorm:"type:decimal(12,2);default:0" json:"frozen_balance"` // 冻结金额
	PayPassword   string         `gorm:"type:varchar(100)" json:"-"`                         // 支付密码
	IsLocked      bool           `gorm:"type:tinyint(1);default:0" json:"is_locked"`         // 是否锁定
	CreatedAt     time.Time      `gorm:"type:datetime;not null" json:"created_at"`
	UpdatedAt     time.Time      `gorm:"type:datetime;not null" json:"updated_at"`
	DeletedAt     gorm.DeletedAt `gorm:"index" json:"-"`
}

func (Wallet) TableName() string {
	return "wallets"
}

// SetPayPassword 设置支付密码
func (w *Wallet) SetPayPassword(password string) error {
	hashedPassword, err := bcrypt.GenerateFromPassword([]byte(password), bcrypt.DefaultCost)
	if err != nil {
		return err
	}
	w.PayPassword = string(hashedPassword)
	return nil
}

// CheckPayPassword 验证支付密码
func (w *Wallet) CheckPayPassword(password string) bool {
	if w.PayPassword == "" {
		return false
	}
	err := bcrypt.CompareHashAndPassword([]byte(w.PayPassword), []byte(password))
	return err == nil
}

// HasPayPassword 是否已设置支付密码
func (w *Wallet) HasPayPassword() bool {
	return w.PayPassword != ""
}

// Transaction 交易记录表
type Transaction struct {
	ID              uint64    `gorm:"primaryKey;autoIncrement" json:"id"`
	UserID          uint64    `gorm:"index;not null" json:"user_id"`
	Type            string    `gorm:"type:varchar(30);not null;index" json:"type"` // recharge, withdraw, transfer_out, transfer_in, red_packet_send, red_packet_receive, membership_purchase
	Amount          float64   `gorm:"type:decimal(12,2);not null" json:"amount"`
	BalanceAfter    float64   `gorm:"type:decimal(12,2);not null" json:"balance_after"`
	RelatedID       string    `gorm:"type:varchar(50);index" json:"related_id"` // 关联ID（红包ID/转账ID等）
	RelatedUserID   *uint64   `gorm:"index" json:"related_user_id"`             // 关联用户
	RelatedUserName string    `gorm:"type:varchar(100)" json:"related_user_name"`
	Remark          string    `gorm:"type:varchar(200)" json:"remark"`
	CreatedAt       time.Time `gorm:"type:datetime;not null;index" json:"created_at"`
}

func (Transaction) TableName() string {
	return "transactions"
}

// 交易类型常量
const (
	TransactionTypeRecharge           = "recharge"
	TransactionTypeWithdraw           = "withdraw"
	TransactionTypeTransferOut        = "transfer_out"
	TransactionTypeTransferIn         = "transfer_in"
	TransactionTypeRedPacketSend      = "red_packet_send"
	TransactionTypeRedPacketReceive   = "red_packet_receive"
	TransactionTypeRefund             = "refund"              // 退款（红包过期、转账退回）
	TransactionTypeAdminRecharge      = "admin_recharge"      // 管理员充值
	TransactionTypeAdminDeduct        = "admin_deduct"        // 管理员扣减
	TransactionTypeRechargeRejected   = "recharge_rejected"   // 充值被拒绝
	TransactionTypeMembershipPurchase = "membership_purchase" // 购买会员
)

// RedPacket 红包表
type RedPacket struct {
	ID              uint64    `gorm:"primaryKey;autoIncrement" json:"id"`
	UUID            string    `gorm:"type:char(36);uniqueIndex;not null" json:"uuid"`
	SenderID        uint64    `gorm:"index;not null" json:"sender_id"`
	ChatID          string    `gorm:"type:varchar(50);index;not null" json:"chat_id"`
	Type            string    `gorm:"type:varchar(20);not null" json:"type"` // normal, lucky (拼手气)
	TotalAmount     float64   `gorm:"type:decimal(12,2);not null" json:"total_amount"`
	TotalCount      int       `gorm:"not null" json:"total_count"`
	RemainingAmount float64   `gorm:"type:decimal(12,2);not null" json:"remaining_amount"`
	RemainingCount  int       `gorm:"not null" json:"remaining_count"`
	Message         string    `gorm:"type:varchar(100)" json:"message"`
	Status          string    `gorm:"type:varchar(20);not null;default:'active';index" json:"status"` // active, finished, expired
	ExpiredAt       time.Time `gorm:"type:datetime;not null;index" json:"expired_at"`
	CreatedAt       time.Time `gorm:"type:datetime;not null" json:"created_at"`
	UpdatedAt       time.Time `gorm:"type:datetime;not null" json:"updated_at"`
}

func (RedPacket) TableName() string {
	return "red_packets"
}

// 红包类型常量
const (
	RedPacketTypeNormal = "normal"
	RedPacketTypeLucky  = "lucky"
)

// 红包状态常量
const (
	RedPacketStatusActive   = "active"
	RedPacketStatusFinished = "finished"
	RedPacketStatusExpired  = "expired"
)

// RedPacketClaim 红包领取记录表
type RedPacketClaim struct {
	ID          uint64    `gorm:"primaryKey;autoIncrement" json:"id"`
	RedPacketID uint64    `gorm:"uniqueIndex:idx_rp_user;not null" json:"red_packet_id"` // 联合唯一索引防重复领取
	UserID      uint64    `gorm:"uniqueIndex:idx_rp_user;not null" json:"user_id"`       // 联合唯一索引防重复领取
	Amount      float64   `gorm:"type:decimal(12,2);not null" json:"amount"`
	IsBest      bool      `gorm:"type:tinyint(1);default:0" json:"is_best"` // 是否手气最佳
	CreatedAt   time.Time `gorm:"type:datetime;not null" json:"created_at"`
}

func (RedPacketClaim) TableName() string {
	return "red_packet_claims"
}

// Transfer 转账表
type Transfer struct {
	ID         uint64     `gorm:"primaryKey;autoIncrement" json:"id"`
	UUID       string     `gorm:"type:char(36);uniqueIndex;not null" json:"uuid"`
	SenderID   uint64     `gorm:"index;not null" json:"sender_id"`
	ReceiverID uint64     `gorm:"index;not null" json:"receiver_id"`
	Amount     float64    `gorm:"type:decimal(12,2);not null" json:"amount"`
	Remark     string     `gorm:"type:varchar(100)" json:"remark"`
	Status     string     `gorm:"type:varchar(20);not null;default:'pending';index" json:"status"` // pending, accepted, rejected, expired
	ExpiredAt  time.Time  `gorm:"type:datetime;not null;index" json:"expired_at"`
	AcceptedAt *time.Time `gorm:"type:datetime" json:"accepted_at"`
	CreatedAt  time.Time  `gorm:"type:datetime;not null" json:"created_at"`
	UpdatedAt  time.Time  `gorm:"type:datetime;not null" json:"updated_at"`
}

func (Transfer) TableName() string {
	return "transfers"
}

// 转账状态常量
const (
	TransferStatusPending  = "pending"
	TransferStatusAccepted = "accepted"
	TransferStatusRejected = "rejected"
	TransferStatusExpired  = "expired"
)

// WithdrawMethod 提现方式配置表
type WithdrawMethod struct {
	ID        uint64         `gorm:"primaryKey;autoIncrement" json:"id"`
	Name      string         `gorm:"type:varchar(50);not null" json:"name"` // 支付宝、微信、银行卡
	Icon      string         `gorm:"type:varchar(200)" json:"icon"`         // 图标
	Fields    string         `gorm:"type:text" json:"fields"`               // JSON格式的表单字段配置
	MinAmount float64        `gorm:"type:decimal(12,2);default:1" json:"min_amount"`
	MaxAmount float64        `gorm:"type:decimal(12,2);default:50000" json:"max_amount"`
	Fee       float64        `gorm:"type:decimal(5,2);default:0" json:"fee"` // 手续费百分比
	Status    int8           `gorm:"type:tinyint;default:1" json:"status"`   // 1启用 0禁用
	Sort      int            `gorm:"type:int;default:0" json:"sort"`
	CreatedAt time.Time      `gorm:"type:datetime;not null" json:"created_at"`
	UpdatedAt time.Time      `gorm:"type:datetime;not null" json:"updated_at"`
	DeletedAt gorm.DeletedAt `gorm:"index" json:"-"`
}

func (WithdrawMethod) TableName() string {
	return "withdraw_methods"
}

// WithdrawRequest 提现申请表
type WithdrawRequest struct {
	ID           uint64     `gorm:"primaryKey;autoIncrement" json:"id"`
	UserID       uint64     `gorm:"index;not null" json:"user_id"`
	MethodID     uint64     `gorm:"index;not null" json:"method_id"`
	Amount       float64    `gorm:"type:decimal(12,2);not null" json:"amount"`
	Fee          float64    `gorm:"type:decimal(12,2);default:0" json:"fee"`
	ActualAmount float64    `gorm:"type:decimal(12,2);not null" json:"actual_amount"`                // 实际到账金额
	FormData     string     `gorm:"type:text" json:"form_data"`                                      // JSON格式的表单数据
	Status       string     `gorm:"type:varchar(20);not null;default:'pending';index" json:"status"` // pending, approved, rejected, completed
	Remark       string     `gorm:"type:varchar(200)" json:"remark"`                                 // 审核备注
	ReviewedBy   *uint64    `gorm:"index" json:"reviewed_by"`                                        // 审核管理员
	ReviewedAt   *time.Time `gorm:"type:datetime" json:"reviewed_at"`
	CreatedAt    time.Time  `gorm:"type:datetime;not null;index" json:"created_at"`
	UpdatedAt    time.Time  `gorm:"type:datetime;not null" json:"updated_at"`
}

func (WithdrawRequest) TableName() string {
	return "withdraw_requests"
}

// 提现状态常量
const (
	WithdrawStatusPending   = "pending"
	WithdrawStatusApproved  = "approved"
	WithdrawStatusRejected  = "rejected"
	WithdrawStatusCompleted = "completed"
)

// ========== 钱包设置常量（复用 SystemSetting 表）==========
const (
	SettingWalletCurrency       = "wallet_currency"         // 货币符号，默认 ¥
	SettingWalletCurrencyName   = "wallet_currency_name"    // 货币名称，默认 人民币
	SettingRedPacketExpireHours = "red_packet_expire_hours" // 红包过期时间（小时），默认 24
	SettingTransferExpireHours  = "transfer_expire_hours"   // 转账过期时间（小时），默认 24
	SettingWalletNotice         = "wallet_notice"           // 钱包公告
	SettingRechargeNotice       = "recharge_notice"         // 充值公告
	SettingWithdrawNotice       = "withdraw_notice"         // 提现公告
	SettingRechargeReview       = "recharge_review"         // 充值是否需要人工审核：0=自动 1=人工
)

// RechargeMethod 充值方式配置表
type RechargeMethod struct {
	ID          uint64         `gorm:"primaryKey;autoIncrement" json:"id"`
	Name        string         `gorm:"type:varchar(50);not null" json:"name"` // 支付宝、微信、银行卡、USDT
	Icon        string         `gorm:"type:varchar(200)" json:"icon"`         // 图标
	Type        string         `gorm:"type:varchar(20);not null" json:"type"` // qrcode=二维码 bank=银行卡 manual=人工
	QRCodeURL   string         `gorm:"type:varchar(500)" json:"qrcode_url"`   // 二维码图片URL
	AccountInfo string         `gorm:"type:text" json:"account_info"`         // 账户信息（JSON）
	MinAmount   float64        `gorm:"type:decimal(12,2);default:1" json:"min_amount"`
	MaxAmount   float64        `gorm:"type:decimal(12,2);default:50000" json:"max_amount"`
	Remark      string         `gorm:"type:varchar(500)" json:"remark"`      // 充值说明
	Status      int8           `gorm:"type:tinyint;default:1" json:"status"` // 1启用 0禁用
	Sort        int            `gorm:"type:int;default:0" json:"sort"`
	CreatedAt   time.Time      `gorm:"type:datetime;not null" json:"created_at"`
	UpdatedAt   time.Time      `gorm:"type:datetime;not null" json:"updated_at"`
	DeletedAt   gorm.DeletedAt `gorm:"index" json:"-"`
}

func (RechargeMethod) TableName() string {
	return "recharge_methods"
}

// RechargeOrder 充值订单表（人工审核充值）
type RechargeOrder struct {
	ID         uint64     `gorm:"primaryKey;autoIncrement" json:"id"`
	UserID     uint64     `gorm:"index;not null" json:"user_id"`
	MethodID   uint64     `gorm:"index;not null" json:"method_id"`
	Amount     float64    `gorm:"type:decimal(12,2);not null" json:"amount"`
	ProofImage string     `gorm:"type:varchar(500)" json:"proof_image"`                            // 付款凭证截图
	Status     string     `gorm:"type:varchar(20);not null;default:'pending';index" json:"status"` // pending, approved, rejected
	Remark     string     `gorm:"type:varchar(200)" json:"remark"`
	ReviewedBy *uint64    `gorm:"index" json:"reviewed_by"`
	ReviewedAt *time.Time `gorm:"type:datetime" json:"reviewed_at"`
	CreatedAt  time.Time  `gorm:"type:datetime;not null;index" json:"created_at"`
	UpdatedAt  time.Time  `gorm:"type:datetime;not null" json:"updated_at"`
}

func (RechargeOrder) TableName() string {
	return "recharge_orders"
}

// 充值订单状态
const (
	RechargeOrderPending  = "pending"
	RechargeOrderApproved = "approved"
	RechargeOrderRejected = "rejected"
)
