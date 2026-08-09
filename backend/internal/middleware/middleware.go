// 文件用途：提供 HTTP 请求链路中的通用中间件。
// 核心逻辑：在处理器前执行跨域、认证、限流、角色和写操作保护。

package middleware

import (
	"github.com/gin-gonic/gin"
	"gorm.io/gorm"
	"log"
	"net/http"
	"net/url"
	"strings"
	"time"
	"genericim/internal/authsession"
	"genericim/internal/cache"
	"genericim/internal/config"
	"genericim/internal/models"
	"genericim/pkg/jwt"
	"genericim/pkg/response"
)

const slowRequestThreshold = 2 * time.Second // Logger 日志中间件
func Logger() gin.HandlerFunc {
	return func(c *gin.Context) {

		start := time.Now()
		path := c.Request.URL.Path

		raw := c.Request.URL.RawQuery

		c.Next()
		latency := time.Since(start)
		clientIP := c.ClientIP()
		method := c.Request.Method

		statusCode := c.Writer.Status()

		if raw != "" {

			path = path + "?" + redactSensitiveQuery(raw)

		}

		log.Printf("[GIN] %3d | %13v | %15s | %-7s %s",

			statusCode,

			latency,

			clientIP,

			method,

			path,
		)

		if latency >= slowRequestThreshold {

			log.Printf("[SLOW REQUEST] %3d | %13v | %15s | %-7s %s",

				statusCode,

				latency,

				clientIP,

				method,

				path,
			)

		}
	}
} // CORS 跨域中间件
func CORS() gin.HandlerFunc {
	return func(c *gin.Context) {

		allowOrigin := allowedCORSOrigin(c.GetHeader("Origin"))

		c.Header("Access-Control-Allow-Origin", allowOrigin)

		if allowOrigin != "*" {

			c.Header("Access-Control-Allow-Credentials", "true")

			c.Writer.Header().Add("Vary", "Origin")

		}

		c.Header("Access-Control-Allow-Methods", "GET, POST, PUT, DELETE, OPTIONS, PATCH")

		c.Header("Access-Control-Allow-Headers", "Origin, Content-Type, Authorization, X-Requested-With, Accept, X-Request-Id, X-Client-Platform")

		c.Header("Access-Control-Expose-Headers", "Content-Length, Content-Type")

		c.Header("Access-Control-Max-Age", "86400")

		if c.Request.Method == "OPTIONS" {

			c.AbortWithStatus(http.StatusNoContent)

			return

		}

		c.Next()
	}
}
func allowedCORSOrigin(origin string) string {
	cfg := config.GlobalConfig
	if cfg == nil || len(cfg.Server.AllowedOrigins) == 0 {

		return "*"
	}
	origin = strings.TrimSpace(origin)
	if origin == "" {

		return cfg.Server.AllowedOrigins[0]
	}
	for _, allowed := range cfg.Server.AllowedOrigins {

		allowed = strings.TrimSpace(allowed)

		if allowed == "*" {

			return "*"

		}

		if isSameCORSOrigin(origin, allowed) {

			return origin

		}
	}
	return cfg.Server.AllowedOrigins[0]
}
func isSameCORSOrigin(origin, allowed string) bool {
	if strings.EqualFold(origin, allowed) {

		return true
	}
	normalizedOrigin, ok := normalizeCORSOrigin(origin)
	if !ok {

		return false
	}
	normalizedAllowed, ok := normalizeCORSOrigin(allowed)
	if !ok {

		return false
	}
	return normalizedOrigin == normalizedAllowed
}
func normalizeCORSOrigin(raw string) (string, bool) {
	parsed, err := url.Parse(strings.TrimSpace(raw))
	if err != nil || parsed.Scheme == "" || parsed.Host == "" {

		return "", false
	}
	return strings.ToLower(parsed.Scheme + "://" + parsed.Host), true
}
func MediaCORS(baseURL string) gin.HandlerFunc {
	allowOrigin := "*"
	return func(c *gin.Context) {

		c.Header("Access-Control-Allow-Origin", allowOrigin)

		c.Header("Access-Control-Allow-Methods", "GET, HEAD, OPTIONS")

		c.Header("Access-Control-Allow-Headers", "Origin, Content-Type, Authorization, Accept, Range")

		c.Header("Access-Control-Expose-Headers", "Content-Length, Content-Type, Accept-Ranges, Content-Range")

		c.Header("Access-Control-Max-Age", "86400")

		c.Header("Cross-Origin-Resource-Policy", "cross-origin")

		c.Header("Timing-Allow-Origin", allowOrigin)

		if c.Request.Method == "OPTIONS" {

			c.AbortWithStatus(http.StatusNoContent)

			return

		}

		c.Next()
	}
} // Auth 认证中间件
func Auth(cache *cache.Cache) gin.HandlerFunc {
	return func(c *gin.Context) {

		tokenString := extractUserToken(c)

		if tokenString == "" {

			response.Unauthorized(c, "请先登录")

			c.Abort()

			return

		}

		if err := authenticateUserToken(c, cache, tokenString); err != nil {

			response.Unauthorized(c, err.Error())

			c.Abort()

			return

		}

		c.Next()
	}
} // OptionalAuth tries to authenticate the current user but does not reject // anonymous requests when no token or an invalid token is provided. // 这是显式的匿名降级边界：下游只能把 user_id 的存在作为“已认证”依据， // 不能因为请求携带过 token 就授予登录用户权限。
func OptionalAuth(cache *cache.Cache) gin.HandlerFunc {
	return func(c *gin.Context) {

		tokenString := extractUserToken(c)

		if tokenString == "" {

			c.Next()

			return

		}

		if err := authenticateUserToken(c, cache, tokenString); err != nil {

			c.Next()

			return

		}

		c.Next()
	}
} // RequirePhoneBind enforces the global "require_phone_bind" system setting for // authenticated user APIs. The current user and phone-bind endpoints must stay // reachable, otherwise an unbound user could not finish the required binding.
func RequirePhoneBind(db *gorm.DB) gin.HandlerFunc {
	return func(c *gin.Context) {

		if db == nil || shouldSkipPhoneBindGuard(c) {

			c.Next()

			return

		}
		var setting models.SystemSetting

		if err := db.Where("`key` = ?", models.SettingRequirePhoneBind).First(&setting).Error; err != nil {

			c.Next()

			return

		}

		if !isTruthySetting(setting.Value) {

			c.Next()

			return

		}
		userUUID := strings.TrimSpace(c.GetString("user_id"))

		if userUUID == "" {

			response.Unauthorized(c, "请先登录")

			c.Abort()

			return

		}
		var user models.User

		if err := db.Select("id", "uuid", "phone").Where("uuid = ?", userUUID).First(&user).Error; err != nil {

			response.Unauthorized(c, "用户不存在")

			c.Abort()

			return

		}

		if user.Phone == nil || strings.TrimSpace(*user.Phone) == "" {

			response.ForbiddenWithCode(c, response.CodePhoneBindRequired, "请先绑定手机号")

			c.Abort()

			return

		}

		c.Next()
	}
}
func shouldSkipPhoneBindGuard(c *gin.Context) bool {
	path := c.FullPath()
	if path == "" {

		path = c.Request.URL.Path
	}
	method := c.Request.Method
	if method == http.MethodGet && path == "/api/v1/user/me" {

		return true
	}
	if method == http.MethodPost && (path == "/api/v1/user/phone/send-bind-code" || path == "/api/v1/user/phone/bind") {

		return true
	}
	return false
}
func isTruthySetting(v string) bool {
	switch strings.ToLower(strings.TrimSpace(v)) {
	case "true", "1", "yes", "on":

		return true
	default:

		return false
	}
}
func allowsQueryToken(c *gin.Context) bool {
	// query token 仅为 WebSocket 握手兼容；普通 HTTP 禁止从 URL 取凭据，
	// 避免 token 进入访问日志、代理缓存和 Referer。
	if strings.HasSuffix(c.Request.URL.Path, "/ws") {

		return true
	}
	return strings.EqualFold(c.GetHeader("Upgrade"), "websocket")
}
func extractUserToken(c *gin.Context) string {
	authHeader := c.GetHeader("Authorization")
	if authHeader != "" {

		parts := strings.SplitN(authHeader, " ", 2)

		if len(parts) == 2 && parts[0] == "Bearer" {

			return parts[1]

		}
	}
	if allowsQueryToken(c) {

		return c.Query("token")
	}
	return ""
}
func authenticateUserToken(c *gin.Context, cache *cache.Cache, tokenString string) error {
	// JWT 只证明签名和声明有效；服务端会话状态还负责冻结、改密、登出和 token 轮换后的即时撤销。
	claims, err := jwt.ParseToken(tokenString)
	if err != nil {

		return errUnauthorized("Token无效或已过期")
	}
	if authError := authsession.ValidateUserTokenStateWithToken(c.Request.Context(), cache, claims, tokenString); authError != "" {

		return errUnauthorized(authError)
	}
	// 下游 Handler 信任这两个上下文值作为用户与设备身份，因此只能在两层校验均通过后写入。
	c.Set("user_id", claims.UserID)
	c.Set("device_id", claims.DeviceID)
	return nil
}
func errUnauthorized(message string) error {
	return unauthorizedError(message)
}

type unauthorizedError string

func (e unauthorizedError) Error() string {
	return string(e)
}
func redactSensitiveQuery(raw string) string {
	if raw == "" {

		return ""
	}
	values, err := url.ParseQuery(raw)
	if err != nil {

		return redactSensitiveQueryFallback(raw)
	}
	for key := range values {

		if isSensitiveQueryKey(key) {

			values[key] = []string{"***"}

		}
	}
	return values.Encode()
}
func redactSensitiveQueryFallback(raw string) string {
	parts := strings.Split(raw, "&")
	for i, part := range parts {

		key, _, found := strings.Cut(part, "=")

		if found && isSensitiveQueryKey(key) {

			parts[i] = key + "=***"

		}
	}
	return strings.Join(parts, "&")
}
func isSensitiveQueryKey(key string) bool {
	key = strings.ToLower(strings.TrimSpace(key))
	switch key {
	case "token", "access_token", "refresh_token", "auth_token", "authorization":

		return true
	default:

		return strings.Contains(key, "secret") || strings.Contains(key, "password")
	}
} // RateLimit 限流中间件
func RateLimit(cache *cache.Cache) gin.HandlerFunc {
	return func(c *gin.Context) {

		if cache == nil {

			c.Next()

			return

		}

		// 根据IP限流

		key := "ip:" + c.ClientIP()

		// 每秒100个请求

		allowed, err := cache.RateLimit(c.Request.Context(), key, 100, time.Second)

		if err != nil {

			log.Printf("Rate limit error: %v", err)

			c.Next()

			return

		}

		if !allowed {

			response.TooManyRequests(c, "请求过于频繁，请稍后再试")

			c.Abort()

			return

		}

		c.Next()
	}
} // WalletRateLimit 钱包操作专用限流（基于用户ID，更严格）
func WalletRateLimit(c *cache.Cache, limit int, window time.Duration) gin.HandlerFunc {
	return func(ctx *gin.Context) {

		if c == nil {

			ctx.Next()

			return

		}
		userID := ctx.GetString("user_id")

		if userID == "" {

			ctx.Next()

			return

		}
		key := "wallet:" + userID + ":" + ctx.FullPath()
		allowed, err := c.RateLimit(ctx.Request.Context(), key, limit, window)

		if err != nil {

			log.Printf("Wallet rate limit error: %v", err)

			ctx.Next()

			return

		}

		if !allowed {

			response.TooManyRequests(ctx, "操作过于频繁，请稍后再试")

			ctx.Abort()

			return

		}

		ctx.Next()
	}
} // UploadInitRateLimit limits upload initialization by both authenticated user and IP.
func UploadInitRateLimit(c *cache.Cache, userLimit, ipLimit int, window time.Duration) gin.HandlerFunc {
	return func(ctx *gin.Context) {

		if c == nil {

			ctx.Next()

			return

		}
		keys := make([]struct {
			key string

			limit int
		}, 0, 2)

		if userID := ctx.GetString("user_id"); userID != "" && userLimit > 0 {

			keys = append(keys, struct {
				key string

				limit int
			}{"upload:init:user:" + userID, userLimit})

		}

		if ip := ctx.ClientIP(); ip != "" && ipLimit > 0 {

			keys = append(keys, struct {
				key string

				limit int
			}{"upload:init:ip:" + ip, ipLimit})

		}

		for _, item := range keys {

			allowed, err := c.RateLimit(ctx.Request.Context(), item.key, item.limit, window)

			if err != nil {

				log.Printf("Upload init rate limit error: %v", err)

				continue

			}

			if !allowed {

				ctx.JSON(http.StatusTooManyRequests, response.Response{

					Code: response.CodeDirectUploadRateLimited,

					Message: "上传请求过于频繁，请稍后再试",
				})

				ctx.Abort()

				return

			}

		}

		ctx.Next()
	}
} // GetUserID 从上下文获取用户ID
func GetUserID(c *gin.Context) string {
	userID, exists := c.Get("user_id")
	if !exists {

		return ""
	}
	return userID.(string)
} // GetDeviceID 从上下文获取设备ID
func GetDeviceID(c *gin.Context) string {
	deviceID, exists := c.Get("device_id")
	if !exists {

		return ""
	}
	return deviceID.(string)
} // AdminAuth 管理员认证中间件
func AdminAuth(dbOpt ...*gorm.DB) gin.HandlerFunc {
	var db *gorm.DB
	if len(dbOpt) > 0 {

		db = dbOpt[0]
	}
	return func(c *gin.Context) {

		// 获取Token

		authHeader := c.GetHeader("Authorization")

		if authHeader == "" {

			response.Unauthorized(c, "请先登录")

			c.Abort()

			return

		}

		// 解析Token

		parts := strings.SplitN(authHeader, " ", 2)

		if len(parts) != 2 || parts[0] != "Bearer" {

			response.Unauthorized(c, "Token格式错误")

			c.Abort()

			return

		}
		tokenString := parts[1]

		// 验证管理员Token

		claims, err := jwt.ParseAdminToken(tokenString)

		if err != nil {

			response.Unauthorized(c, "Token无效或已过期")

			c.Abort()

			return

		}

		if !isValidAdminRole(claims.Role) {

			response.Forbidden(c, "管理员角色无效")

			c.Abort()

			return

		}
		adminUsername := claims.Username

		adminRole := claims.Role

		if db != nil {

			// JWT 中角色只是登录时快照；数据库状态是管理员是否存在、启用及当前角色的权威来源。
			var admin models.Admin

			if err := db.Select("id", "username", "role", "status").First(&admin, claims.AdminID).Error; err != nil {

				response.Unauthorized(c, "管理员不存在或已被删除")

				c.Abort()

				return

			}

			if admin.Status != 1 {

				response.Forbidden(c, "管理员已被禁用")

				c.Abort()

				return

			}

			if strings.TrimSpace(admin.Username) != claims.Username {

				response.Unauthorized(c, "管理员身份已变更，请重新登录")

				c.Abort()

				return

			}

			if !isValidAdminRole(admin.Role) {

				response.Forbidden(c, "管理员角色无效")

				c.Abort()

				return

			}
			adminUsername = admin.Username

			adminRole = admin.Role

		}

		// 设置管理员信息到上下文

		c.Set("admin_id", claims.AdminID)

		c.Set("admin_username", adminUsername)

		c.Set("admin_role", adminRole)

		c.Next()
	}
}
func isValidAdminRole(role string) bool {
	switch role {
	case "super_admin", "admin", "operator", "demo_admin":

		return true
	default:

		return false
	}
} // RequireRole 角色校验中间件
func RequireRole(roles ...string) gin.HandlerFunc {
	return func(c *gin.Context) {

		role, exists := c.Get("admin_role")

		if !exists {

			response.Forbidden(c, "无权限")

			c.Abort()

			return

		}
		adminRole := role.(string)

		for _, r := range roles {

			if adminRole == r {

				c.Next()

				return

			}

		}

		response.Forbidden(c, "无权限执行此操作")

		c.Abort()
	}
} // GetAdminID 从上下文获取管理员ID
func GetAdminID(c *gin.Context) uint64 {
	adminID, exists := c.Get("admin_id")
	if !exists {

		return 0
	}
	return adminID.(uint64)
} // GetAdminRole 从上下文获取管理员角色
func GetAdminRole(c *gin.Context) string {
	role, exists := c.Get("admin_role")
	if !exists {

		return ""
	}
	return role.(string)
} // RequireWriteRole 写操作权限中间件 - 禁止演示管理员
func RequireWriteRole() gin.HandlerFunc {
	return func(c *gin.Context) {

		role := GetAdminRole(c)

		switch role {

		case "super_admin", "admin", "operator":

			c.Next()

			return

		case "demo_admin":

			response.Forbidden(c, "演示账号无法执行此操作")

			c.Abort()

			return

		default:

			response.Forbidden(c, "无权限执行此操作")

			c.Abort()

			return

		}
	}
} // BlockDemoAdminWrites globally protects admin write endpoints for demo accounts. // Keep this on the authenticated /admin group so newly added write routes are safe by default.
func BlockDemoAdminWrites() gin.HandlerFunc {
	return func(c *gin.Context) {

		switch c.Request.Method {

		case http.MethodGet, http.MethodHead, http.MethodOptions:

			c.Next()

			return

		}

		if GetAdminRole(c) == "demo_admin" {

			response.Forbidden(c, "演示账号只能查看，无法执行新增、修改、删除或审核操作")

			c.Abort()

			return

		}

		c.Next()
	}
}
