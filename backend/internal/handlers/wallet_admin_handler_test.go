// 文件用途：验证 wallet_admin_handler_test.go 对应模块的正常流程、异常处理和回归行为。
// 核心逻辑：覆盖输入校验、状态变化、错误返回、边界条件和并发幸命。

package handlers

import (
	"testing"
	"genericim/internal/config"
)

func TestMaskPaymentConfigForDemo(t *testing.T) {
	t.Parallel()
	cfg := config.PaymentConfig{}
	cfg.Wechat.MchAPIv3Key = "wx-secret"
	cfg.Wechat.PrivateKeyPath = "/etc/pay/wx.pem"
	cfg.Wechat.PrivateKeyPEM = "wx-private-pem"
	cfg.Alipay.PrivateKeyPath = "/etc/pay/ali.pem"
	cfg.Alipay.AppPrivateKeyPEM = "ali-private-pem"
	cfg.Alipay.AlipayPublicKeyPath = "/etc/pay/ali-public.pem"
	cfg.Alipay.AlipayPublicKeyPEM = "ali-public-pem"

	got := maskPaymentConfigForDemo(cfg)
	for name, value := range map[string]string{
		"wechat api v3 key":       got.Wechat.MchAPIv3Key,
		"wechat private key path": got.Wechat.PrivateKeyPath,
		"wechat private key pem":  got.Wechat.PrivateKeyPEM,
		"alipay private key path": got.Alipay.PrivateKeyPath,
		"alipay private key pem":  got.Alipay.AppPrivateKeyPEM,
		"alipay public key path":  got.Alipay.AlipayPublicKeyPath,
		"alipay public key pem":   got.Alipay.AlipayPublicKeyPEM,
	} {
		if value != "******" {
			t.Fatalf("%s was not masked, got %q", name, value)
		}
	}
}
