// 文件用途：验证 online_payment_service_test.go 对应模块的正常流程、异常处理和回归行为。
// 核心逻辑：覆盖输入校验、状态变化、错误返回、边界条件和并发幸命。

package services

import (
	"github.com/smartwalle/alipay/v3"
	"github.com/wechatpay-apiv3/wechatpay-go/services/payments"
	"testing"
	"genericim/internal/config"
	"genericim/internal/models"
)

func TestValidPaymentFulfillmentRejectsUntrustedInputs(t *testing.T) {
	t.Parallel()
	order := models.ThirdPartyPaymentOrder{
		OutTradeNo:  "order-1",
		Channel:     models.TPPayChannelWechat,
		AmountCents: 1234,
	}
	tests := []struct {
		name          string
		providerTxnID string
		channel       string
		paidCents     int64
		wantErr       bool
	}{
		{name: "valid", providerTxnID: "wx-txn-1", channel: models.TPPayChannelWechat, paidCents: 1234},
		{name: "channel mismatch", providerTxnID: "wx-txn-1", channel: models.TPPayChannelAlipay, paidCents: 1234, wantErr: true},
		{name: "missing provider transaction", providerTxnID: " ", channel: models.TPPayChannelWechat, paidCents: 1234, wantErr: true},
		{name: "missing amount", providerTxnID: "wx-txn-1", channel: models.TPPayChannelWechat, paidCents: 0, wantErr: true},
		{name: "amount mismatch", providerTxnID: "wx-txn-1", channel: models.TPPayChannelWechat, paidCents: 1200, wantErr: true},
	}
	for _, tc := range tests {
		tc := tc
		t.Run(tc.name, func(t *testing.T) {
			t.Parallel()
			err := validPaymentFulfillment(order, tc.providerTxnID, tc.channel, tc.paidCents)
			if tc.wantErr && err == nil {
				t.Fatal("expected error, got nil")
			}
			if !tc.wantErr && err != nil {
				t.Fatalf("unexpected error: %v", err)
			}
		})
	}
}

func TestValidateWeChatPaidTransaction(t *testing.T) {
	t.Parallel()
	svc := paymentValidationTestService()
	tx := payments.Transaction{
		Appid:         strPtr("wx-app"),
		Mchid:         strPtr("mch-1"),
		OutTradeNo:    strPtr("order-1"),
		TransactionId: strPtr("wx-txn-1"),
		Amount:        &payments.TransactionAmount{Total: int64Ptr(1234)},
	}
	if err := svc.validateWeChatPaidTransaction(tx); err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	tx.Appid = strPtr("other-app")
	if err := svc.validateWeChatPaidTransaction(tx); err == nil {
		t.Fatal("expected appid mismatch error")
	}
	tx.Appid = strPtr("wx-app")
	tx.TransactionId = nil
	if err := svc.validateWeChatPaidTransaction(tx); err == nil {
		t.Fatal("expected missing transaction id error")
	}
}

func TestValidateAlipayPaidNotification(t *testing.T) {
	t.Parallel()
	svc := paymentValidationTestService()
	n := &alipay.Notification{
		AppId:       "ali-app",
		OutTradeNo:  "order-1",
		TradeNo:     "ali-txn-1",
		TotalAmount: "12.34",
	}

	cents, err := svc.validateAlipayPaidNotification(n)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if cents != 1234 {
		t.Fatalf("cents=%d, want 1234", cents)
	}
	n.TotalAmount = "not-money"
	if _, err := svc.validateAlipayPaidNotification(n); err == nil {
		t.Fatal("expected invalid amount error")
	}
	n.TotalAmount = "12.34"
	n.AppId = "other-app"
	if _, err := svc.validateAlipayPaidNotification(n); err == nil {
		t.Fatal("expected app_id mismatch error")
	}
}

func paymentValidationTestService() *OnlinePaymentService {
	var cfg config.Config
	cfg.Payment.Wechat.AppID = "wx-app"
	cfg.Payment.Wechat.MchID = "mch-1"
	cfg.Payment.Alipay.AppID = "ali-app"
	return NewOnlinePaymentService(&cfg, nil)
}

func strPtr(v string) *string {
	return &v
}

func int64Ptr(v int64) *int64 {
	return &v
}
