package jwt

import (
	"errors"
	"time"

	"gaoranim/internal/config"

	"github.com/golang-jwt/jwt/v5"
)

// Claims JWT声明（用户端）
type Claims struct {
	UserID         string `json:"user_id"`
	DeviceID       string `json:"device_id"`
	SessionVersion int64  `json:"session_version,omitempty"`
	jwt.RegisteredClaims
}

// AdminClaims 管理员JWT声明
type AdminClaims struct {
	AdminID  uint64 `json:"admin_id"`
	Username string `json:"username"`
	Role     string `json:"role"`
	jwt.RegisteredClaims
}

// GenerateToken 生成用户Token
func GenerateToken(userID, deviceID string, sessionVersion ...int64) (string, error) {
	cfg := config.GlobalConfig.JWT
	version := int64(0)
	if len(sessionVersion) > 0 {
		version = sessionVersion[0]
	}

	claims := &Claims{
		UserID:         userID,
		DeviceID:       deviceID,
		SessionVersion: version,
		RegisteredClaims: jwt.RegisteredClaims{
			ExpiresAt: jwt.NewNumericDate(time.Now().Add(cfg.Expire)),
			IssuedAt:  jwt.NewNumericDate(time.Now()),
			Issuer:    "gaoranim",
		},
	}

	token := jwt.NewWithClaims(jwt.SigningMethodHS256, claims)
	return token.SignedString([]byte(cfg.Secret))
}

// GenerateAdminToken 生成管理员Token
func GenerateAdminToken(adminID uint64, username, role string) (string, error) {
	cfg := config.GlobalConfig.JWT

	claims := &AdminClaims{
		AdminID:  adminID,
		Username: username,
		Role:     role,
		RegisteredClaims: jwt.RegisteredClaims{
			ExpiresAt: jwt.NewNumericDate(time.Now().Add(cfg.Expire)),
			IssuedAt:  jwt.NewNumericDate(time.Now()),
			Issuer:    "gaoranim-admin",
		},
	}

	token := jwt.NewWithClaims(jwt.SigningMethodHS256, claims)
	return token.SignedString([]byte(cfg.Secret))
}

// ParseToken 解析Token
func ParseToken(tokenString string) (*Claims, error) {
	cfg := config.GlobalConfig.JWT

	token, err := jwt.ParseWithClaims(tokenString, &Claims{}, func(token *jwt.Token) (interface{}, error) {
		if _, ok := token.Method.(*jwt.SigningMethodHMAC); !ok {
			return nil, errors.New("invalid signing method")
		}
		return []byte(cfg.Secret), nil
	})

	if err != nil {
		return nil, err
	}

	if claims, ok := token.Claims.(*Claims); ok && token.Valid {
		return claims, nil
	}

	return nil, errors.New("invalid token")
}

// RefreshToken 刷新用户Token
func RefreshToken(tokenString string) (string, error) {
	// 先走常规解析（未过期）
	claims, err := ParseToken(tokenString)
	if err == nil {
		return GenerateToken(claims.UserID, claims.DeviceID, claims.SessionVersion)
	}

	// 再尝试“允许过期”的刷新解析（签名必须有效）
	refreshClaims, refreshErr := parseTokenForRefresh(tokenString)
	if refreshErr != nil {
		return "", refreshErr
	}
	return GenerateToken(refreshClaims.UserID, refreshClaims.DeviceID, refreshClaims.SessionVersion)
}

// ParseTokenForRefresh 解析可用于刷新流程的 token（允许过期，但校验签名与刷新窗口）
func ParseTokenForRefresh(tokenString string) (*Claims, error) {
	return parseTokenForRefresh(tokenString)
}

// parseTokenForRefresh 允许已过期 token 参与刷新，但仍要求签名有效
// 并限制过期后的可刷新窗口，避免无限续期。
func parseTokenForRefresh(tokenString string) (*Claims, error) {
	cfg := config.GlobalConfig.JWT
	parser := jwt.NewParser(jwt.WithoutClaimsValidation())

	token, err := parser.ParseWithClaims(tokenString, &Claims{}, func(token *jwt.Token) (interface{}, error) {
		if _, ok := token.Method.(*jwt.SigningMethodHMAC); !ok {
			return nil, errors.New("invalid signing method")
		}
		return []byte(cfg.Secret), nil
	})
	if err != nil {
		return nil, err
	}

	claims, ok := token.Claims.(*Claims)
	if !ok || claims == nil {
		return nil, errors.New("invalid token claims")
	}
	if claims.Issuer != "gaoranim" {
		return nil, errors.New("invalid token issuer")
	}
	if claims.ExpiresAt == nil {
		return nil, errors.New("invalid token exp")
	}

	now := time.Now()
	exp := claims.ExpiresAt.Time
	refreshWindow := cfg.RefreshExpire
	if refreshWindow <= 0 {
		refreshWindow = cfg.Expire
	}
	// 允许在配置的刷新窗口内刷新，防止 token 无限续期。
	if now.After(exp.Add(refreshWindow)) {
		return nil, errors.New("token refresh window expired")
	}

	return claims, nil
}

// ParseAdminToken 解析管理员Token
func ParseAdminToken(tokenString string) (*AdminClaims, error) {
	cfg := config.GlobalConfig.JWT

	token, err := jwt.ParseWithClaims(tokenString, &AdminClaims{}, func(token *jwt.Token) (interface{}, error) {
		if _, ok := token.Method.(*jwt.SigningMethodHMAC); !ok {
			return nil, errors.New("invalid signing method")
		}
		return []byte(cfg.Secret), nil
	})

	if err != nil {
		return nil, err
	}

	if claims, ok := token.Claims.(*AdminClaims); ok && token.Valid {
		return claims, nil
	}

	return nil, errors.New("invalid token")
}
