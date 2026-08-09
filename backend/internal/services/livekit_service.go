// 文件用途：实现可复用的后端业务服务和领域逻辑。
// 核心逻辑：协调数据库、缓存、队列和外部服务，集中处理事务、幂等、重试和错误传播。

package services

import (
	"fmt"
	"github.com/golang-jwt/jwt/v5"
	"strings"
	"time"
)

type LiveKitService struct {
	Enabled     bool
	ServerURL   string
	APIKey      string
	APISecret   string
	TokenExpire int
}

type liveKitVideoGrant struct {
	RoomJoin       bool   `json:"roomJoin"`
	Room           string `json:"room"`
	CanPublish     bool   `json:"canPublish"`
	CanSubscribe   bool   `json:"canSubscribe"`
	CanPublishData bool   `json:"canPublishData"`
}

type liveKitAccessClaims struct {
	Name  string            `json:"name,omitempty"`
	Video liveKitVideoGrant `json:"video"`
	jwt.RegisteredClaims
}

func NewLiveKitService(enabled bool, serverURL, apiKey, apiSecret string, tokenExpire int) *LiveKitService {
	return &LiveKitService{
		Enabled:     enabled,
		ServerURL:   strings.TrimSpace(serverURL),
		APIKey:      strings.TrimSpace(apiKey),
		APISecret:   strings.TrimSpace(apiSecret),
		TokenExpire: tokenExpire,
	}
}

func (s *LiveKitService) IsConfigured() bool {
	return strings.TrimSpace(s.ServerURL) != "" &&
		strings.TrimSpace(s.APIKey) != "" &&
		strings.TrimSpace(s.APISecret) != ""
}

func (s *LiveKitService) GenerateJoinToken(roomName, identity, name string, canPublish bool) (string, error) {
	roomName = strings.TrimSpace(roomName)
	identity = strings.TrimSpace(identity)
	if !s.IsConfigured() {
		return "", fmt.Errorf("livekit not configured")
	}
	if roomName == "" || identity == "" {
		return "", fmt.Errorf("livekit room and identity are required")
	}
	expire := s.TokenExpire
	if expire <= 0 {
		expire = 3600
	}
	now := time.Now()
	claims := liveKitAccessClaims{
		Name: strings.TrimSpace(name),
		Video: liveKitVideoGrant{
			RoomJoin:       true,
			Room:           roomName,
			CanPublish:     canPublish,
			CanSubscribe:   true,
			CanPublishData: true,
		},
		RegisteredClaims: jwt.RegisteredClaims{
			Issuer:    s.APIKey,
			Subject:   identity,
			NotBefore: jwt.NewNumericDate(now.Add(-time.Minute)),
			ExpiresAt: jwt.NewNumericDate(now.Add(time.Duration(expire) * time.Second)),
			IssuedAt:  jwt.NewNumericDate(now),
		},
	}
	token := jwt.NewWithClaims(jwt.SigningMethodHS256, claims)
	return token.SignedString([]byte(s.APISecret))
}

func (s *LiveKitService) GetExpireTime() time.Duration {
	expire := s.TokenExpire
	if expire <= 0 {
		expire = 3600
	}
	return time.Duration(expire) * time.Second
}
