package authsession

import (
	"context"
	"crypto/sha256"
	"encoding/hex"
	"strings"
	"time"

	"gaoranim/internal/cache"
	"gaoranim/internal/config"
	jwtpkg "gaoranim/pkg/jwt"
)

func sessionVersionKey(userUUID string) string {
	return "user:session_version:" + userUUID
}

func logoutAfterKey(userUUID string) string {
	return "user:logout_after:" + userUUID
}

func passwordResetKey(userUUID string) string {
	return "user:pwd_reset:" + userUUID
}

func tokenRevokedKey(userUUID, token string) string {
	sum := sha256.Sum256([]byte(token))
	return "user:token_revoked:" + userUUID + ":" + hex.EncodeToString(sum[:])
}

func deviceLogoutAfterKey(userUUID, deviceID string) string {
	return "user:device_logout_after:" + userUUID + ":" + strings.TrimSpace(deviceID)
}

func authStateTTL() time.Duration {
	cfg := config.GlobalConfig.JWT
	ttl := cfg.Expire + cfg.RefreshExpire
	if cfg.RefreshExpire <= 0 {
		ttl = cfg.Expire + cfg.Expire
	}
	if ttl <= 0 {
		return cache.TTLToken
	}
	return ttl + time.Hour
}

func IssueUserSession(ctx context.Context, c *cache.Cache, userUUID string) int64 {
	sessionVersion := time.Now().Unix()
	if c == nil || userUUID == "" {
		return sessionVersion
	}

	_ = c.Delete(ctx, passwordResetKey(userUUID))
	_ = c.Set(ctx, sessionVersionKey(userUUID), sessionVersion, authStateTTL())
	return sessionVersion
}

func EnsureLoginSession(ctx context.Context, c *cache.Cache, userUUID string) int64 {
	sessionVersion := time.Now().Unix()
	if c == nil || userUUID == "" {
		return sessionVersion
	}

	_ = c.Delete(ctx, passwordResetKey(userUUID))
	var existing int64
	if err := c.Get(ctx, sessionVersionKey(userUUID), &existing); err == nil && existing > 0 {
		return existing
	}

	_ = c.Set(ctx, sessionVersionKey(userUUID), sessionVersion, authStateTTL())
	return sessionVersion
}

func MarkPasswordReset(ctx context.Context, c *cache.Cache, userUUID string) int64 {
	sessionVersion := time.Now().Unix()
	if c == nil || userUUID == "" {
		return sessionVersion
	}

	ttl := authStateTTL()
	_ = c.Set(ctx, passwordResetKey(userUUID), true, ttl)
	_ = c.Set(ctx, sessionVersionKey(userUUID), sessionVersion, ttl)
	return sessionVersion
}

func InvalidateUserSession(ctx context.Context, c *cache.Cache, userUUID string) int64 {
	sessionVersion := time.Now().Unix()
	if c == nil || userUUID == "" {
		return sessionVersion
	}

	ttl := authStateTTL()
	_ = c.Set(ctx, logoutAfterKey(userUUID), sessionVersion, ttl)
	_ = c.Set(ctx, sessionVersionKey(userUUID), sessionVersion, ttl)
	return sessionVersion
}

func InvalidateDeviceSession(ctx context.Context, c *cache.Cache, userUUID, deviceID string) int64 {
	sessionVersion := time.Now().Unix()
	deviceID = strings.TrimSpace(deviceID)
	if c == nil || userUUID == "" || deviceID == "" {
		return sessionVersion
	}
	_ = c.Set(ctx, deviceLogoutAfterKey(userUUID, deviceID), sessionVersion, authStateTTL())
	return sessionVersion
}

func RevokeUserToken(ctx context.Context, c *cache.Cache, userUUID, rawToken string) {
	rawToken = strings.TrimSpace(rawToken)
	if c == nil || userUUID == "" || rawToken == "" {
		return
	}
	_ = c.Set(ctx, tokenRevokedKey(userUUID, rawToken), true, authStateTTL())
}

func ValidateUserTokenStateWithToken(ctx context.Context, c *cache.Cache, claims *jwtpkg.Claims, rawToken string) string {
	authError := ValidateUserTokenState(ctx, c, claims)
	if authError != "" {
		return authError
	}
	rawToken = strings.TrimSpace(rawToken)
	if c == nil || claims == nil || rawToken == "" {
		return ""
	}
	if c.Exists(ctx, tokenRevokedKey(claims.UserID, rawToken)) {
		return "登录态已失效，请重新登录"
	}
	return ""
}

func ValidateUserTokenState(ctx context.Context, c *cache.Cache, claims *jwtpkg.Claims) string {
	if c == nil || claims == nil {
		return ""
	}

	frozenKey := "user:frozen:" + claims.UserID
	if c.Exists(ctx, frozenKey) {
		return "您的账号已被冻结"
	}

	if c.Exists(ctx, passwordResetKey(claims.UserID)) {
		return "密码已被修改，请重新登录"
	}

	var logoutAfter int64
	if err := c.Get(ctx, logoutAfterKey(claims.UserID), &logoutAfter); err == nil && claims.IssuedAt != nil {
		if claims.IssuedAt.Time.Unix() <= logoutAfter {
			return "登录态已失效，请重新登录"
		}
	}
	if claims.DeviceID != "" && claims.IssuedAt != nil {
		var deviceLogoutAfter int64
		if err := c.Get(ctx, deviceLogoutAfterKey(claims.UserID, claims.DeviceID), &deviceLogoutAfter); err == nil {
			if claims.IssuedAt.Time.Unix() <= deviceLogoutAfter {
				return "当前设备登录态已失效，请重新登录"
			}
		}
	}

	var sessionVersion int64
	if err := c.Get(ctx, sessionVersionKey(claims.UserID), &sessionVersion); err == nil {
		if sessionVersion > 0 && claims.SessionVersion > 0 && claims.SessionVersion < sessionVersion {
			return "会话已更新，请重新登录"
		}
	}

	return ""
}
