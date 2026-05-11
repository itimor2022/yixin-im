package services

import (
	"encoding/json"
	"strings"

	"gaoranim/internal/config"
	"gaoranim/internal/models"

	"gorm.io/gorm"
)

// LoadSMSForRuntime 合并 system_settings.sms_gateway 与 yaml。
func LoadSMSForRuntime(db *gorm.DB, yamlCfg config.SMSConfig) config.SMSConfig {
	if db == nil {
		return yamlCfg
	}
	var row models.SystemSetting
	if err := db.Where("`key` = ?", models.SettingSmsGateway).First(&row).Error; err != nil {
		return yamlCfg
	}
	raw := strings.TrimSpace(row.Value)
	if raw == "" || raw == "{}" {
		return yamlCfg
	}
	var dbCfg config.SMSConfig
	if err := json.Unmarshal([]byte(raw), &dbCfg); err != nil {
		return yamlCfg
	}
	return smsFillZeros(dbCfg, yamlCfg)
}

func smsFillZeros(db, yaml config.SMSConfig) config.SMSConfig {
	out := db
	if out.Provider == "" {
		out.Provider = yaml.Provider
	}
	if out.MessageTemplate == "" {
		out.MessageTemplate = yaml.MessageTemplate
	}
	sb := out.SMSBao
	ysb := yaml.SMSBao
	if sb.User == "" {
		sb.User = ysb.User
	}
	if sb.Password == "" {
		sb.Password = ysb.Password
	}
	out.SMSBao = sb

	al := out.Aliyun
	yal := yaml.Aliyun
	if al.AccessKeyID == "" {
		al.AccessKeyID = yal.AccessKeyID
	}
	if al.AccessKeySecret == "" {
		al.AccessKeySecret = yal.AccessKeySecret
	}
	if al.Region == "" {
		al.Region = yal.Region
	}
	if al.SignName == "" {
		al.SignName = yal.SignName
	}
	if al.TemplateCode == "" {
		al.TemplateCode = yal.TemplateCode
	}
	out.Aliyun = al

	tc := out.Tencent
	ytc := yaml.Tencent
	if tc.SecretID == "" {
		tc.SecretID = ytc.SecretID
	}
	if tc.SecretKey == "" {
		tc.SecretKey = ytc.SecretKey
	}
	if tc.Region == "" {
		tc.Region = ytc.Region
	}
	if tc.SdkAppID == "" {
		tc.SdkAppID = ytc.SdkAppID
	}
	if tc.SignName == "" {
		tc.SignName = ytc.SignName
	}
	if tc.TemplateID == "" {
		tc.TemplateID = ytc.TemplateID
	}
	out.Tencent = tc
	return out
}

// SMSSendReady 是否已配置可发送（用于 App 展示「可发短信」）。
func SMSSendReady(db *gorm.DB, yamlCfg config.SMSConfig) bool {
	c := LoadSMSForRuntime(db, yamlCfg)
	if !c.Enabled {
		return false
	}
	switch strings.ToLower(strings.TrimSpace(c.Provider)) {
	case "smsbao":
		return c.SMSBao.User != "" && c.SMSBao.Password != ""
	case "aliyun":
		a := c.Aliyun
		return a.AccessKeyID != "" && a.AccessKeySecret != "" && a.SignName != "" && a.TemplateCode != ""
	case "tencent":
		t := c.Tencent
		return t.SecretID != "" && t.SecretKey != "" && t.SdkAppID != "" && t.SignName != "" && t.TemplateID != ""
	default:
		return false
	}
}
