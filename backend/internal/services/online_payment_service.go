package services

import (
	"context"
	"crypto/rsa"
	"encoding/json"
	"fmt"
	"math"
	"net/http"
	"net/url"
	"os"
	"strconv"
	"strings"
	"sync"
	"time"

	"gaoranim/internal/config"
	"gaoranim/internal/models"

	"github.com/gin-gonic/gin"
	"github.com/google/uuid"
	"github.com/smartwalle/alipay/v3"
	"github.com/wechatpay-apiv3/wechatpay-go/core"
	"github.com/wechatpay-apiv3/wechatpay-go/core/auth/verifiers"
	"github.com/wechatpay-apiv3/wechatpay-go/core/downloader"
	"github.com/wechatpay-apiv3/wechatpay-go/core/notify"
	"github.com/wechatpay-apiv3/wechatpay-go/core/option"
	"github.com/wechatpay-apiv3/wechatpay-go/services/payments"
	"github.com/wechatpay-apiv3/wechatpay-go/services/payments/app"
	"github.com/wechatpay-apiv3/wechatpay-go/services/payments/h5"
	"github.com/wechatpay-apiv3/wechatpay-go/services/payments/native"
	"github.com/wechatpay-apiv3/wechatpay-go/utils"
	"gorm.io/gorm"
	"gorm.io/gorm/clause"
)

// OnlinePaymentService 微信/支付宝充值下单与回调入账
type OnlinePaymentService struct {
	cfg *config.Config
	db  *gorm.DB

	payCfgMu    sync.Mutex
	payCached   config.PaymentConfig
	payCachedAt time.Time

	wxMu      sync.Mutex
	wxCli     *core.Client
	wxCfgSig  string
	aliMu     sync.Mutex
	aliCli    *alipay.Client
	aliCfgSig string
}

func NewOnlinePaymentService(cfg *config.Config, db *gorm.DB) *OnlinePaymentService {
	return &OnlinePaymentService{cfg: cfg, db: db}
}

// InvalidatePaymentCache 管理后台保存支付配置后调用，使新配置立即生效
func (s *OnlinePaymentService) InvalidatePaymentCache() {
	s.payCfgMu.Lock()
	s.payCachedAt = time.Time{}
	s.payCfgMu.Unlock()
	s.wxMu.Lock()
	s.wxCli = nil
	s.wxCfgSig = ""
	s.wxMu.Unlock()
	s.aliMu.Lock()
	s.aliCli = nil
	s.aliCfgSig = ""
	s.aliMu.Unlock()
}

func (s *OnlinePaymentService) paymentCfg() config.PaymentConfig {
	s.payCfgMu.Lock()
	defer s.payCfgMu.Unlock()
	if !s.payCachedAt.IsZero() && time.Since(s.payCachedAt) < 5*time.Second {
		return s.payCached
	}
	p := LoadPaymentForRuntime(s.db, s.cfg.Payment)
	s.payCached = p
	s.payCachedAt = time.Now()
	return p
}

func (s *OnlinePaymentService) Enabled() bool {
	p := s.paymentCfg()
	if !p.Enabled {
		return false
	}
	return p.Wechat.Enabled || p.Alipay.Enabled
}

func (s *OnlinePaymentService) notifyBase() string {
	b := strings.TrimSpace(s.paymentCfg().NotifyBaseURL)
	if b != "" {
		return strings.TrimRight(b, "/")
	}
	b = strings.TrimSpace(s.cfg.Server.BaseURL)
	return strings.TrimRight(b, "/")
}

func (s *OnlinePaymentService) wechatNotifyURL() string {
	return s.notifyBase() + "/api/v1/payment/notify/wechat"
}

func (s *OnlinePaymentService) alipayNotifyURL() string {
	return s.notifyBase() + "/api/v1/payment/notify/alipay"
}

func (s *OnlinePaymentService) alipayReturnURL(outTradeNo string) string {
	p := s.paymentCfg()
	base := strings.TrimSpace(p.Alipay.ReturnURL)
	if base == "" {
		base = strings.TrimSpace(s.cfg.Server.BaseURL)
		if base != "" {
			base = strings.TrimRight(base, "/") + "/wallet/payment-result"
		} else {
			base = "/wallet/payment-result"
		}
	}
	if outTradeNo == "" {
		return base
	}
	u, err := url.Parse(base)
	if err != nil {
		sep := "?"
		if strings.Contains(base, "?") {
			sep = "&"
		}
		return base + sep + "out_trade_no=" + url.QueryEscape(outTradeNo)
	}
	q := u.Query()
	q.Set("out_trade_no", outTradeNo)
	u.RawQuery = q.Encode()
	return u.String()
}

func (s *OnlinePaymentService) minMax() (min, max float64) {
	p := s.paymentCfg()
	min, max = p.MinAmount, p.MaxAmount
	if min <= 0 {
		min = 0.01
	}
	if max <= 0 {
		max = 50000
	}
	return min, max
}

// Options 供 App 展示可用渠道（不含密钥）
func (s *OnlinePaymentService) Options() gin.H {
	p := s.paymentCfg()
	requirePhone := false
	if s.db != nil {
		var row models.SystemSetting
		if err := s.db.Where("`key` = ?", models.SettingRequirePhoneBind).First(&row).Error; err == nil && row.Value == "true" {
			requirePhone = true
		}
	}
	return gin.H{
		"enabled":            s.Enabled(),
		"wechat_enabled":     p.Enabled && p.Wechat.Enabled,
		"alipay_enabled":     p.Enabled && p.Alipay.Enabled,
		"wechat_app_id":      p.Wechat.AppID,
		"min_amount":         func() float64 { a, _ := s.minMax(); return a }(),
		"max_amount":         func() float64 { _, b := s.minMax(); return b }(),
		"require_phone_bind": requirePhone,
	}
}

func (s *OnlinePaymentService) ensureWechatClient(ctx context.Context) (*core.Client, error) {
	w := s.paymentCfg().Wechat
	if !w.Enabled || w.MchID == "" || w.MchAPIv3Key == "" || w.MchCertificateSerial == "" || w.AppID == "" {
		return nil, fmt.Errorf("微信支付未正确配置")
	}
	if w.PrivateKeyPEM == "" && w.PrivateKeyPath == "" {
		return nil, fmt.Errorf("微信支付未配置私钥（PEM 文本或文件路径）")
	}
	sig := paymentWechatSig(w)
	s.wxMu.Lock()
	defer s.wxMu.Unlock()
	if s.wxCli != nil && s.wxCfgSig == sig {
		return s.wxCli, nil
	}
	var pkAny interface{}
	var err error
	if w.PrivateKeyPEM != "" {
		pkAny, err = utils.LoadPrivateKey(strings.TrimSpace(w.PrivateKeyPEM))
	} else {
		pkAny, err = utils.LoadPrivateKeyWithPath(w.PrivateKeyPath)
	}
	if err != nil {
		return nil, fmt.Errorf("加载微信商户私钥失败: %w", err)
	}
	rsaKey, ok := pkAny.(*rsa.PrivateKey)
	if !ok || rsaKey == nil {
		return nil, fmt.Errorf("微信商户私钥不是有效的 RSA 私钥")
	}
	cli, err := core.NewClient(ctx,
		option.WithWechatPayAutoAuthCipher(w.MchID, w.MchCertificateSerial, rsaKey, w.MchAPIv3Key),
	)
	if err != nil {
		return nil, err
	}
	s.wxCli = cli
	s.wxCfgSig = sig
	return cli, nil
}

func (s *OnlinePaymentService) ensureAlipayClient() (*alipay.Client, error) {
	a := s.paymentCfg().Alipay
	hasPriv := a.AppPrivateKeyPEM != "" || a.PrivateKeyPath != ""
	hasPub := a.AlipayPublicKeyPEM != "" || a.AlipayPublicKeyPath != ""
	if !a.Enabled || a.AppID == "" || !hasPriv || !hasPub {
		return nil, fmt.Errorf("支付宝未正确配置")
	}
	sig := paymentAlipaySig(a)
	s.aliMu.Lock()
	defer s.aliMu.Unlock()
	if s.aliCli != nil && s.aliCfgSig == sig {
		return s.aliCli, nil
	}
	var keyPEM []byte
	var err error
	if a.AppPrivateKeyPEM != "" {
		keyPEM = []byte(strings.TrimSpace(a.AppPrivateKeyPEM))
	} else {
		keyPEM, err = os.ReadFile(a.PrivateKeyPath)
		if err != nil {
			return nil, fmt.Errorf("读取支付宝应用私钥失败: %w", err)
		}
	}
	cli, err := alipay.New(a.AppID, string(keyPEM), a.IsProduction)
	if err != nil {
		return nil, err
	}
	var aliPub []byte
	if a.AlipayPublicKeyPEM != "" {
		aliPub = []byte(strings.TrimSpace(a.AlipayPublicKeyPEM))
	} else {
		aliPub, err = os.ReadFile(a.AlipayPublicKeyPath)
		if err != nil {
			return nil, fmt.Errorf("读取支付宝公钥文件失败: %w", err)
		}
	}
	if err := cli.LoadAliPayPublicKey(string(aliPub)); err != nil {
		return nil, fmt.Errorf("加载支付宝公钥失败: %w", err)
	}
	s.aliCli = cli
	s.aliCfgSig = sig
	return s.aliCli, nil
}

func (s *OnlinePaymentService) wechatNotifyHandler() (*notify.Handler, error) {
	w := s.paymentCfg().Wechat
	mgr := downloader.MgrInstance()
	visitor := mgr.GetCertificateVisitor(w.MchID)
	if visitor == nil {
		return nil, fmt.Errorf("微信证书未就绪，请先成功发起一次下单或检查商户配置")
	}
	v := verifiers.NewSHA256WithRSAVerifier(visitor)
	return notify.NewRSANotifyHandler(w.MchAPIv3Key, v)
}

func amountToCents(amount float64) int64 {
	return int64(math.Round(amount * 100))
}

func genOutTradeNo() string {
	return strings.ReplaceAll(uuid.New().String(), "-", "")
}

// CreateOnlinePayment 创建第三方支付订单；clientPlatform: android|ios|web|windows|macos|linux
func (s *OnlinePaymentService) CreateOnlinePayment(ctx context.Context, userID uint64, amount float64, channel, clientPlatform, clientIP string) (gin.H, error) {
	if !s.Enabled() {
		return nil, fmt.Errorf("在线支付未启用")
	}
	minA, maxA := s.minMax()
	if amount < minA || amount > maxA {
		return nil, fmt.Errorf("金额需在 %.2f～%.2f 之间", minA, maxA)
	}
	var w models.Wallet
	if err := s.db.Where("user_id = ?", userID).First(&w).Error; err != nil {
		if err == gorm.ErrRecordNotFound {
			return nil, fmt.Errorf("请先进入钱包完成初始化")
		}
		return nil, err
	}
	if w.IsLocked {
		return nil, fmt.Errorf("钱包已锁定")
	}

	cents := amountToCents(amount)
	outNo := genOutTradeNo()

	order := models.ThirdPartyPaymentOrder{
		OutTradeNo:     outNo,
		UserID:         userID,
		Channel:        channel,
		ClientPlatform: clientPlatform,
		Status:         models.TPPayStatusPending,
		Amount:         amount,
		AmountCents:    cents,
		CreatedAt:      time.Now(),
		UpdatedAt:      time.Now(),
	}
	if err := s.db.Create(&order).Error; err != nil {
		return nil, err
	}

	cny := "CNY"
	total := cents
	desc := core.String("钱包充值")
	notifyWX := s.wechatNotifyURL()
	notifyAli := s.alipayNotifyURL()
	pay := s.paymentCfg()

	resp := gin.H{
		"out_trade_no":    outNo,
		"amount":          amount,
		"channel":         channel,
		"client_platform": clientPlatform,
		"wechat_app_id":   pay.Wechat.AppID,
	}

	switch channel {
	case models.TPPayChannelWechat:
		if !pay.Wechat.Enabled {
			return nil, fmt.Errorf("微信支付未启用")
		}
		cli, err := s.ensureWechatClient(ctx)
		if err != nil {
			return nil, err
		}
		switch clientPlatform {
		case "android", "ios":
			order.PayMode = "app"
			svc := app.AppApiService{Client: cli}
			prepay, _, err := svc.PrepayWithRequestPayment(ctx, app.PrepayRequest{
				Appid:       core.String(pay.Wechat.AppID),
				Mchid:       core.String(pay.Wechat.MchID),
				Description: desc,
				OutTradeNo:  core.String(outNo),
				NotifyUrl:   core.String(notifyWX),
				Amount: &app.Amount{
					Total:    &total,
					Currency: &cny,
				},
			})
			if err != nil {
				return nil, err
			}
			resp["pay_mode"] = "app"
			resp["wechat_app"] = gin.H{
				"app_id":        pay.Wechat.AppID,
				"partner_id":    prepay.PartnerId,
				"prepay_id":     prepay.PrepayId,
				"package_value": prepay.Package,
				"nonce_str":     prepay.NonceStr,
				"time_stamp":    prepay.TimeStamp,
				"sign":          prepay.Sign,
			}
		case "web":
			order.PayMode = "h5"
			svc := h5.H5ApiService{Client: cli}
			wcfg := pay.Wechat
			h5t := "Wap"
			appName := wcfg.H5AppName
			if appName == "" {
				appName = "IM"
			}
			appURL := wcfg.H5AppURL
			if appURL == "" {
				appURL = s.notifyBase()
			}
			h5info := &h5.H5Info{Type: &h5t, AppName: &appName, AppUrl: &appURL}
			if wcfg.H5BundleID != "" {
				h5info.BundleId = &wcfg.H5BundleID
			}
			if wcfg.H5PackageName != "" {
				h5info.PackageName = &wcfg.H5PackageName
			}
			ip := clientIP
			if ip == "" {
				ip = "127.0.0.1"
			}
			h5r, _, err := svc.Prepay(ctx, h5.PrepayRequest{
				Appid:       core.String(pay.Wechat.AppID),
				Mchid:       core.String(pay.Wechat.MchID),
				Description: desc,
				OutTradeNo:  core.String(outNo),
				NotifyUrl:   core.String(notifyWX),
				Amount: &h5.Amount{
					Total:    &total,
					Currency: &cny,
				},
				SceneInfo: &h5.SceneInfo{
					PayerClientIp: &ip,
					H5Info:        h5info,
				},
			})
			if err != nil {
				return nil, err
			}
			resp["pay_mode"] = "h5"
			if h5r.H5Url != nil {
				resp["wechat_h5_url"] = *h5r.H5Url
			}
		default:
			// windows、macos、linux 或未知：Native 扫码
			order.PayMode = "native"
			svc := native.NativeApiService{Client: cli}
			nr, _, err := svc.Prepay(ctx, native.PrepayRequest{
				Appid:       core.String(pay.Wechat.AppID),
				Mchid:       core.String(pay.Wechat.MchID),
				Description: desc,
				OutTradeNo:  core.String(outNo),
				NotifyUrl:   core.String(notifyWX),
				Amount: &native.Amount{
					Total:    &total,
					Currency: &cny,
				},
			})
			if err != nil {
				return nil, err
			}
			resp["pay_mode"] = "native"
			if nr.CodeUrl != nil {
				resp["wechat_code_url"] = *nr.CodeUrl
			}
		}
	case models.TPPayChannelAlipay:
		if !pay.Alipay.Enabled {
			return nil, fmt.Errorf("支付宝未启用")
		}
		cli, err := s.ensureAlipayClient()
		if err != nil {
			return nil, err
		}
		baseTrade := alipay.Trade{
			NotifyURL:   notifyAli,
			ReturnURL:   s.alipayReturnURL(outNo),
			Subject:     "钱包充值",
			OutTradeNo:  outNo,
			TotalAmount: fmt.Sprintf("%.2f", amount),
		}
		switch clientPlatform {
		case "android", "ios":
			order.PayMode = "app"
			baseTrade.ProductCode = "QUICK_MSECURITY_PAY"
			payParam, err := cli.TradeAppPay(alipay.TradeAppPay{Trade: baseTrade})
			if err != nil {
				return nil, err
			}
			resp["pay_mode"] = "app"
			resp["alipay_order_string"] = payParam
		case "web":
			order.PayMode = "page"
			baseTrade.ProductCode = "FAST_INSTANT_TRADE_PAY"
			u, err := cli.TradePagePay(alipay.TradePagePay{Trade: baseTrade})
			if err != nil {
				return nil, err
			}
			resp["pay_mode"] = "page"
			resp["alipay_pay_url"] = u.String()
		default:
			// 桌面端：当面付预创建，返回二维码内容
			order.PayMode = "precreate"
			baseTrade.ProductCode = "FACE_TO_FACE_PAYMENT"
			pr, err := cli.TradePreCreate(context.Background(), alipay.TradePreCreate{Trade: baseTrade})
			if err != nil {
				return nil, err
			}
			if pr != nil && pr.QRCode != "" {
				resp["pay_mode"] = "precreate"
				resp["alipay_qr_code"] = pr.QRCode
			} else {
				return nil, fmt.Errorf("支付宝预下单无二维码")
			}
		}
	default:
		return nil, fmt.Errorf("不支持的支付渠道")
	}

	extra, _ := json.Marshal(resp)
	pm, _ := resp["pay_mode"].(string)
	order.PayMode = pm
	_ = s.db.Model(&order).Updates(map[string]interface{}{
		"pay_mode":   order.PayMode,
		"extra_json": string(extra),
		"updated_at": time.Now(),
	})

	return resp, nil
}

// FulfillIfPaid 幂等入账
func (s *OnlinePaymentService) FulfillIfPaid(outTradeNo, providerTxnID, channel string, paidCents int64) error {
	return s.db.Transaction(func(tx *gorm.DB) error {
		var order models.ThirdPartyPaymentOrder
		if err := tx.Clauses(clause.Locking{Strength: "UPDATE"}).
			Where("out_trade_no = ?", outTradeNo).First(&order).Error; err != nil {
			return err
		}
		if order.Status == models.TPPayStatusPaid {
			return nil
		}
		if order.Status != models.TPPayStatusPending {
			return fmt.Errorf("订单状态不可支付: %s", order.Status)
		}
		if paidCents > 0 && paidCents != order.AmountCents {
			return fmt.Errorf("金额不一致")
		}

		var wallet models.Wallet
		if err := tx.Clauses(clause.Locking{Strength: "UPDATE"}).
			Where("user_id = ?", order.UserID).First(&wallet).Error; err != nil {
			if err == gorm.ErrRecordNotFound {
				wallet = models.Wallet{
					UserID: order.UserID, Balance: 0,
					CreatedAt: time.Now(), UpdatedAt: time.Now(),
				}
				if err := tx.Create(&wallet).Error; err != nil {
					return err
				}
			} else {
				return err
			}
		}

		newBal := wallet.Balance + order.Amount
		if err := tx.Model(&wallet).Updates(map[string]interface{}{
			"balance":    gorm.Expr("balance + ?", order.Amount),
			"updated_at": time.Now(),
		}).Error; err != nil {
			return err
		}

		now := time.Now()
		if err := tx.Create(&models.Transaction{
			UserID:       order.UserID,
			Type:         models.TransactionTypeRecharge,
			Amount:       order.Amount,
			BalanceAfter: newBal,
			RelatedID:    outTradeNo,
			Remark:       fmt.Sprintf("在线充值(%s)", channel),
			CreatedAt:    now,
		}).Error; err != nil {
			return err
		}

		return tx.Model(&order).Updates(map[string]interface{}{
			"status":          models.TPPayStatusPaid,
			"provider_txn_id": providerTxnID,
			"paid_at":         now,
			"updated_at":      now,
		}).Error
	})
}

// HandleWeChatNotify HTTP 回调
func (s *OnlinePaymentService) HandleWeChatNotify(w http.ResponseWriter, r *http.Request) {
	ctx := r.Context()
	if _, err := s.ensureWechatClient(ctx); err != nil {
		http.Error(w, "wechat not ready", http.StatusServiceUnavailable)
		return
	}
	h, err := s.wechatNotifyHandler()
	if err != nil {
		http.Error(w, err.Error(), http.StatusInternalServerError)
		return
	}
	var tx payments.Transaction
	nreq, err := h.ParseNotifyRequest(ctx, r, &tx)
	if err != nil {
		http.Error(w, "invalid notify", http.StatusBadRequest)
		return
	}
	if nreq.EventType != "TRANSACTION.SUCCESS" {
		w.WriteHeader(http.StatusOK)
		_, _ = w.Write([]byte(`{"code":"SUCCESS","message":"OK"}`))
		return
	}
	if tx.TradeState == nil || *tx.TradeState != "SUCCESS" || tx.OutTradeNo == nil {
		w.WriteHeader(http.StatusOK)
		_, _ = w.Write([]byte(`{"code":"SUCCESS","message":"OK"}`))
		return
	}
	var cents int64
	if tx.Amount != nil && tx.Amount.Total != nil {
		cents = *tx.Amount.Total
	}
	tid := ""
	if tx.TransactionId != nil {
		tid = *tx.TransactionId
	}
	if err := s.FulfillIfPaid(*tx.OutTradeNo, tid, models.TPPayChannelWechat, cents); err != nil {
		// 仍返回 SUCCESS 避免微信重试风暴；需日志监控人工对账
		fmt.Printf("[OnlinePay] wechat fulfill err: %v\n", err)
	}
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(http.StatusOK)
	_, _ = w.Write([]byte(`{"code":"SUCCESS","message":"成功"}`))
}

// HandleAlipayNotify HTTP 回调
func (s *OnlinePaymentService) HandleAlipayNotify(w http.ResponseWriter, r *http.Request) {
	cli, err := s.ensureAlipayClient()
	if err != nil {
		http.Error(w, "alipay not ready", http.StatusServiceUnavailable)
		return
	}
	if err := r.ParseForm(); err != nil {
		http.Error(w, "bad form", http.StatusBadRequest)
		return
	}
	n, err := cli.DecodeNotification(r.Form)
	if err != nil {
		http.Error(w, "verify fail", http.StatusBadRequest)
		return
	}
	if n.TradeStatus != alipay.TradeStatusSuccess {
		alipay.ACKNotification(w)
		return
	}
	cents := int64(0)
	if n.TotalAmount != "" {
		if f, err := strconv.ParseFloat(n.TotalAmount, 64); err == nil {
			cents = amountToCents(f)
		}
	}
	if err := s.FulfillIfPaid(n.OutTradeNo, n.TradeNo, models.TPPayChannelAlipay, cents); err != nil {
		fmt.Printf("[OnlinePay] alipay fulfill err: %v\n", err)
	}
	alipay.ACKNotification(w)
}

// GetUserOrder 用户查询自己的订单状态
func (s *OnlinePaymentService) GetUserOrder(userID uint64, outTradeNo string) (*models.ThirdPartyPaymentOrder, error) {
	var o models.ThirdPartyPaymentOrder
	if err := s.db.Where("out_trade_no = ? AND user_id = ?", outTradeNo, userID).First(&o).Error; err != nil {
		return nil, err
	}
	return &o, nil
}
