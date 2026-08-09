// 文件用途：实现可复用的后端业务服务和领域逻辑。
// 核心逻辑：协调数据库、缓存、队列和外部服务，集中处理事务、幂等、重试和错误传播。

package services

import (
	"context"
	"fmt"
	"mime"
	"net/mail"
	"net/smtp"
	"strconv"
	"strings"
	"genericim/internal/config"
)

// EmailService sends registration verification codes without exposing them to
// API responses or application logs.
type EmailService struct {
	cfg *config.Config
}

func NewEmailService(cfg *config.Config) *EmailService {
	return &EmailService{cfg: cfg}
}

func EmailSendReady(c config.EmailConfig, serverMode string) bool {
	if !c.Enabled {
		return false
	}
	switch strings.ToLower(strings.TrimSpace(c.Provider)) {
	case "console":
		return strings.EqualFold(strings.TrimSpace(serverMode), "debug")
	case "smtp":
		return strings.TrimSpace(c.SMTP.Host) != "" &&
			c.SMTP.Port > 0 &&
			NormalizeEmailAddress(c.FromAddress) != ""
	default:
		return false
	}
}

func (s *EmailService) CanSend() bool {
	return s != nil && s.cfg != nil && EmailSendReady(s.cfg.Email, s.cfg.Server.Mode)
}

func NormalizeEmailAddress(raw string) string {
	raw = strings.TrimSpace(raw)
	if raw == "" || len(raw) > 254 || strings.ContainsAny(raw, "\r\n") {
		return ""
	}
	parsed, err := mail.ParseAddress(raw)
	if err != nil || !strings.EqualFold(parsed.Address, raw) {
		return ""
	}
	parts := strings.Split(parsed.Address, "@")
	if len(parts) != 2 || parts[0] == "" || !strings.Contains(parts[1], ".") {
		return ""
	}
	return strings.ToLower(parsed.Address)
}

func (s *EmailService) SendOTP(ctx context.Context, recipient, code string) error {
	if s == nil || s.cfg == nil {
		return fmt.Errorf("邮件服务未配置")
	}
	c := s.cfg.Email
	if !c.Enabled {
		return fmt.Errorf("邮件服务未启用")
	}
	select {
	case <-ctx.Done():
		return ctx.Err()
	default:
	}

	switch strings.ToLower(strings.TrimSpace(c.Provider)) {
	case "console":
		if !strings.EqualFold(strings.TrimSpace(s.cfg.Server.Mode), "debug") {
			return fmt.Errorf("console 邮件通道仅允许在 debug 模式使用")
		}
		return nil
	case "smtp":
		return sendSMTPEmail(c, recipient, code)
	default:
		return fmt.Errorf("不支持的邮件通道: %s", c.Provider)
	}
}

func sendSMTPEmail(c config.EmailConfig, recipient, code string) error {
	to := NormalizeEmailAddress(recipient)
	from := NormalizeEmailAddress(c.FromAddress)
	if to == "" || from == "" || !EmailSendReady(c, "release") {
		return fmt.Errorf("SMTP 邮件配置或收件地址无效")
	}
	subject := strings.ReplaceAll(c.SubjectTemplate, "{code}", code)
	if strings.TrimSpace(subject) == "" {
		subject = "注册验证码"
	}
	subject = strings.NewReplacer("\r", " ", "\n", " ").Replace(subject)
	body := strings.ReplaceAll(c.BodyTemplate, "{code}", code)
	if strings.TrimSpace(body) == "" {
		body = fmt.Sprintf("您的注册验证码是 %s，5 分钟内有效。", code)
	}
	fromHeader := (&mail.Address{Name: c.FromName, Address: from}).String()
	message := strings.Join([]string{
		"From: " + fromHeader,
		"To: " + to,
		"Subject: " + mime.QEncoding.Encode("UTF-8", subject),
		"MIME-Version: 1.0",
		"Content-Type: text/plain; charset=UTF-8",
		"Content-Transfer-Encoding: 8bit",
		"",
		body,
	}, "\r\n")
	host := strings.TrimSpace(c.SMTP.Host)
	address := host + ":" + strconv.Itoa(c.SMTP.Port)
	var auth smtp.Auth
	if strings.TrimSpace(c.SMTP.Username) != "" {
		auth = smtp.PlainAuth("", c.SMTP.Username, c.SMTP.Password, host)
	}
	return smtp.SendMail(address, auth, from, []string{to}, []byte(message))
}
