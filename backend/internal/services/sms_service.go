package services

import (
	"context"
	"crypto/md5"
	"crypto/rand"
	"encoding/hex"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"net/url"
	"strings"
	"sync"
	"time"

	"gaoranim/internal/config"

	"github.com/aliyun/alibaba-cloud-sdk-go/services/dysmsapi"
	"github.com/tencentcloud/tencentcloud-sdk-go/tencentcloud/common"
	"github.com/tencentcloud/tencentcloud-sdk-go/tencentcloud/common/profile"
	sms "github.com/tencentcloud/tencentcloud-sdk-go/tencentcloud/sms/v20210111"
	"gorm.io/gorm"
)

// SMSService 短信发送（验证码），配置来自 yaml + DB 合并
type SMSService struct {
	cfg *config.Config
	db  *gorm.DB

	mu       sync.Mutex
	cached   config.SMSConfig
	cachedAt time.Time
	cacheTTL time.Duration
}

var smsHTTPClient = &http.Client{Timeout: 10 * time.Second}

func NewSMSService(cfg *config.Config, db *gorm.DB) *SMSService {
	return &SMSService{cfg: cfg, db: db, cacheTTL: 5 * time.Second}
}

// CanSend 当前合并配置是否可发短信（绑定验证码等）
func (s *SMSService) CanSend() bool {
	if s == nil || s.cfg == nil {
		return false
	}
	return SMSSendReady(s.db, s.cfg.SMS)
}

// InvalidateSMSCache 管理后台保存短信配置后调用
func (s *SMSService) InvalidateSMSCache() {
	s.mu.Lock()
	s.cachedAt = time.Time{}
	s.mu.Unlock()
}

func (s *SMSService) smsCfg() config.SMSConfig {
	s.mu.Lock()
	defer s.mu.Unlock()
	if !s.cachedAt.IsZero() && time.Since(s.cachedAt) < s.cacheTTL {
		return s.cached
	}
	if s.cfg == nil {
		return config.SMSConfig{}
	}
	c := LoadSMSForRuntime(s.db, s.cfg.SMS)
	s.cached = c
	s.cachedAt = time.Now()
	return c
}

// SendOTP 发送验证码短信（绑定手机等）
func (s *SMSService) SendOTP(ctx context.Context, phone, code string) error {
	c := s.smsCfg()
	if !c.Enabled {
		return fmt.Errorf("短信服务未启用")
	}
	p := strings.ToLower(strings.TrimSpace(c.Provider))
	switch p {
	case "smsbao":
		return s.sendSMSBao(ctx, c, phone, code)
	case "aliyun":
		return s.sendAliyun(ctx, c, phone, code)
	case "tencent":
		return s.sendTencent(ctx, c, phone, code)
	default:
		return fmt.Errorf("不支持的短信渠道: %s", c.Provider)
	}
}

func (s *SMSService) sendSMSBao(ctx context.Context, c config.SMSConfig, phone, code string) error {
	u := c.SMSBao.User
	pw := c.SMSBao.Password
	if u == "" || pw == "" {
		return fmt.Errorf("短信宝账号未配置")
	}
	h := md5.Sum([]byte(pw))
	phex := hex.EncodeToString(h[:])
	msg := strings.ReplaceAll(c.MessageTemplate, "{code}", code)
	if strings.TrimSpace(msg) == "" {
		msg = fmt.Sprintf("【验证】您的验证码是 %s，5分钟内有效。", code)
	}
	q := url.Values{}
	q.Set("u", u)
	q.Set("p", phex)
	q.Set("m", phone)
	q.Set("c", msg)
	req, err := http.NewRequestWithContext(ctx, http.MethodGet, "https://api.smsbao.com/sms?"+q.Encode(), nil)
	if err != nil {
		return err
	}
	resp, err := smsHTTPClient.Do(req)
	if err != nil {
		return err
	}
	defer resp.Body.Close()
	body, _ := io.ReadAll(resp.Body)
	st := strings.TrimSpace(string(body))
	if st == "0" {
		return nil
	}
	return fmt.Errorf("短信宝错误码: %s", st)
}

func (s *SMSService) sendAliyun(_ context.Context, c config.SMSConfig, phone, code string) error {
	a := c.Aliyun
	if a.AccessKeyID == "" || a.AccessKeySecret == "" || a.SignName == "" || a.TemplateCode == "" {
		return fmt.Errorf("阿里云短信未完整配置")
	}
	region := a.Region
	if region == "" {
		region = "cn-hangzhou"
	}
	client, err := dysmsapi.NewClientWithAccessKey(region, a.AccessKeyID, a.AccessKeySecret)
	if err != nil {
		return err
	}
	req := dysmsapi.CreateSendSmsRequest()
	req.PhoneNumbers = phone
	req.SignName = a.SignName
	req.TemplateCode = a.TemplateCode
	param, _ := json.Marshal(map[string]string{"code": code})
	req.TemplateParam = string(param)
	resp, err := client.SendSms(req)
	if err != nil {
		return err
	}
	if resp.Code != "OK" {
		return fmt.Errorf("阿里云短信: %s %s", resp.Code, resp.Message)
	}
	return nil
}

func (s *SMSService) sendTencent(_ context.Context, c config.SMSConfig, phone, code string) error {
	t := c.Tencent
	if t.SecretID == "" || t.SecretKey == "" || t.SdkAppID == "" || t.SignName == "" || t.TemplateID == "" {
		return fmt.Errorf("腾讯云短信未完整配置")
	}
	region := t.Region
	if region == "" {
		region = "ap-guangzhou"
	}
	cred := common.NewCredential(t.SecretID, t.SecretKey)
	cli, err := sms.NewClient(cred, region, profile.NewClientProfile())
	if err != nil {
		return err
	}
	req := sms.NewSendSmsRequest()
	mobile := phone
	if !strings.HasPrefix(mobile, "+") {
		mobile = "+86" + mobile
	}
	req.PhoneNumberSet = []*string{common.StringPtr(mobile)}
	req.SmsSdkAppId = common.StringPtr(t.SdkAppID)
	req.SignName = common.StringPtr(t.SignName)
	req.TemplateId = common.StringPtr(t.TemplateID)
	req.TemplateParamSet = []*string{common.StringPtr(code)}
	resp, err := cli.SendSms(req)
	if err != nil {
		return err
	}
	if resp == nil || resp.Response == nil || len(resp.Response.SendStatusSet) == 0 {
		return fmt.Errorf("腾讯云短信无有效返回")
	}
	st := resp.Response.SendStatusSet[0]
	if st.Code != nil && *st.Code != "Ok" {
		msg := ""
		if st.Message != nil {
			msg = *st.Message
		}
		return fmt.Errorf("腾讯云短信: %s", msg)
	}
	return nil
}

// GenPhoneBindCode 生成 6 位数字验证码
func GenPhoneBindCode() string {
	var b [4]byte
	_, _ = rand.Read(b[:])
	n := int(b[0])<<24 | int(b[1])<<16 | int(b[2])<<8 | int(b[3])
	if n < 0 {
		n = -n
	}
	return fmt.Sprintf("%06d", n%1000000)
}

// NormalizeCNMobile 归一化中国大陆手机号（11 位，1 开头）
func NormalizeCNMobile(s string) string {
	var d strings.Builder
	for _, r := range s {
		if r >= '0' && r <= '9' {
			d.WriteRune(r)
		}
	}
	x := d.String()
	if len(x) == 13 && strings.HasPrefix(x, "861") {
		x = x[2:]
	}
	if len(x) == 11 && x[0] == '1' {
		return x
	}
	return ""
}
