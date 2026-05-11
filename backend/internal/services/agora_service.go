package services

import (
	"fmt"
	"time"

	rtctokenbuilder2 "github.com/AgoraIO/Tools/DynamicKey/AgoraDynamicKey/go/src/rtctokenbuilder2"
)

// AgoraService 声网服务
type AgoraService struct {
	Enabled        bool
	AppID          string
	AppCertificate string
	TokenExpire    int
}

// 权限常量
const (
	RolePublisher  = 1 // 主播，可以发布流
	RoleSubscriber = 2 // 观众，只能订阅流
)

// NewAgoraService 创建声网服务
func NewAgoraService(enabled bool, appID, appCertificate string, tokenExpire int) *AgoraService {
	return &AgoraService{
		Enabled:        enabled,
		AppID:          appID,
		AppCertificate: appCertificate,
		TokenExpire:    tokenExpire,
	}
}

// IsConfigured 检查是否已配置
func (s *AgoraService) IsConfigured() bool {
	return s.AppID != "" && s.AppCertificate != ""
}

// GenerateRTCToken 生成 RTC Token（用于音视频通话）
func (s *AgoraService) GenerateRTCToken(channelName string, uid uint32, role int) (string, error) {
	if !s.IsConfigured() {
		return "", fmt.Errorf("agora not configured")
	}

	tokenExpireInSeconds := uint32(s.TokenExpire)
	privilegeExpireInSeconds := uint32(s.TokenExpire)

	// 使用官方 SDK 生成 Token
	token, err := rtctokenbuilder2.BuildTokenWithUid(
		s.AppID,
		s.AppCertificate,
		channelName,
		uid,
		rtctokenbuilder2.RolePublisher,
		tokenExpireInSeconds,
		privilegeExpireInSeconds,
	)
	if err != nil {
		return "", fmt.Errorf("生成Token失败: %v", err)
	}

	return token, nil
}

// GenerateRTCTokenWithAccount 使用账号生成 Token
func (s *AgoraService) GenerateRTCTokenWithAccount(channelName string, account string, role int) (string, error) {
	if !s.IsConfigured() {
		return "", fmt.Errorf("agora not configured")
	}

	tokenExpireInSeconds := uint32(s.TokenExpire)
	privilegeExpireInSeconds := uint32(s.TokenExpire)

	token, err := rtctokenbuilder2.BuildTokenWithUserAccount(
		s.AppID,
		s.AppCertificate,
		channelName,
		account,
		rtctokenbuilder2.RolePublisher,
		tokenExpireInSeconds,
		privilegeExpireInSeconds,
	)
	if err != nil {
		return "", fmt.Errorf("生成Token失败: %v", err)
	}

	return token, nil
}

// GetExpireTime 获取过期时间
func (s *AgoraService) GetExpireTime() time.Duration {
	return time.Duration(s.TokenExpire) * time.Second
}
