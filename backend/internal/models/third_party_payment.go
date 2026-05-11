package models

import "time"

// ThirdPartyPaymentOrder 微信/支付宝在线充值订单（异步通知入账）
type ThirdPartyPaymentOrder struct {
	ID             uint64     `gorm:"primaryKey;autoIncrement" json:"id"`
	OutTradeNo     string     `gorm:"uniqueIndex;size:64;not null" json:"out_trade_no"`
	UserID         uint64     `gorm:"index;not null" json:"user_id"`
	Channel        string     `gorm:"size:16;not null;index" json:"channel"`           // wechat | alipay
	ClientPlatform string     `gorm:"size:16;not null" json:"client_platform"`         // android ios web windows macos linux
	PayMode        string     `gorm:"size:24;not null" json:"pay_mode"`                // app h5 native wap page precreate
	Amount         float64    `gorm:"type:decimal(12,2);not null" json:"amount"`
	AmountCents    int64      `gorm:"not null" json:"amount_cents"`
	Status         string     `gorm:"size:20;not null;default:'pending';index" json:"status"`
	ProviderTxnID  string     `gorm:"size:64" json:"provider_txn_id"`
	ExtraJSON      string     `gorm:"type:text" json:"extra_json,omitempty"`
	CreatedAt      time.Time  `gorm:"type:datetime;not null;index" json:"created_at"`
	UpdatedAt      time.Time  `gorm:"type:datetime;not null" json:"updated_at"`
	PaidAt         *time.Time `gorm:"type:datetime" json:"paid_at,omitempty"`
}

func (ThirdPartyPaymentOrder) TableName() string {
	return "third_party_payment_orders"
}

const (
	TPPayChannelWechat = "wechat"
	TPPayChannelAlipay = "alipay"

	TPPayStatusPending = "pending"
	TPPayStatusPaid    = "paid"
	TPPayStatusClosed  = "closed"
	TPPayStatusFailed  = "failed"
)
