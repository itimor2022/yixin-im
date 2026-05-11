package services

import (
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"strings"

	"gaoranim/internal/config"
	"gaoranim/internal/models"

	"gorm.io/gorm"
)

// LoadPaymentForRuntime 优先使用 system_settings.payment_gateway JSON，并与 yaml 中非空项合并（便于只改部分字段）。
func LoadPaymentForRuntime(db *gorm.DB, yamlCfg config.PaymentConfig) config.PaymentConfig {
	if db == nil {
		return yamlCfg
	}
	var row models.SystemSetting
	if err := db.Where("`key` = ?", models.SettingPaymentGateway).First(&row).Error; err != nil {
		return yamlCfg
	}
	raw := strings.TrimSpace(row.Value)
	if raw == "" || raw == "{}" {
		return yamlCfg
	}
	var dbCfg config.PaymentConfig
	if err := json.Unmarshal([]byte(raw), &dbCfg); err != nil {
		return yamlCfg
	}
	return paymentFillZeros(dbCfg, yamlCfg)
}

// paymentFillZeros DB 中已写字段优先生效；空字段用 yaml 补全（不覆盖 enabled 等布尔含义，布尔仅以 DB 为准）。
func paymentFillZeros(db, yaml config.PaymentConfig) config.PaymentConfig {
	out := db
	if out.NotifyBaseURL == "" {
		out.NotifyBaseURL = yaml.NotifyBaseURL
	}
	if out.MinAmount == 0 {
		out.MinAmount = yaml.MinAmount
	}
	if out.MaxAmount == 0 {
		out.MaxAmount = yaml.MaxAmount
	}
	w := out.Wechat
	yw := yaml.Wechat
	if w.MchID == "" {
		w.MchID = yw.MchID
	}
	if w.MchAPIv3Key == "" {
		w.MchAPIv3Key = yw.MchAPIv3Key
	}
	if w.MchCertificateSerial == "" {
		w.MchCertificateSerial = yw.MchCertificateSerial
	}
	if w.AppID == "" {
		w.AppID = yw.AppID
	}
	if w.PrivateKeyPath == "" && w.PrivateKeyPEM == "" {
		w.PrivateKeyPath = yw.PrivateKeyPath
		w.PrivateKeyPEM = yw.PrivateKeyPEM
	}
	if w.H5AppName == "" {
		w.H5AppName = yw.H5AppName
	}
	if w.H5AppURL == "" {
		w.H5AppURL = yw.H5AppURL
	}
	if w.H5BundleID == "" {
		w.H5BundleID = yw.H5BundleID
	}
	if w.H5PackageName == "" {
		w.H5PackageName = yw.H5PackageName
	}
	out.Wechat = w
	a := out.Alipay
	ya := yaml.Alipay
	if a.AppID == "" {
		a.AppID = ya.AppID
	}
	if a.PrivateKeyPath == "" && a.AppPrivateKeyPEM == "" {
		a.PrivateKeyPath = ya.PrivateKeyPath
		a.AppPrivateKeyPEM = ya.AppPrivateKeyPEM
	}
	if a.AlipayPublicKeyPath == "" && a.AlipayPublicKeyPEM == "" {
		a.AlipayPublicKeyPath = ya.AlipayPublicKeyPath
		a.AlipayPublicKeyPEM = ya.AlipayPublicKeyPEM
	}
	if a.ReturnURL == "" {
		a.ReturnURL = ya.ReturnURL
	}
	out.Alipay = a
	return out
}

func paymentConfigFingerprint(p config.PaymentConfig) string {
	b, _ := json.Marshal(p)
	h := sha256.Sum256(b)
	return hex.EncodeToString(h[:])
}

func paymentWechatSig(w interface{}) string {
	b, _ := json.Marshal(w)
	h := sha256.Sum256(b)
	return hex.EncodeToString(h[:])
}

func paymentAlipaySig(a interface{}) string {
	b, _ := json.Marshal(a)
	h := sha256.Sum256(b)
	return hex.EncodeToString(h[:])
}
