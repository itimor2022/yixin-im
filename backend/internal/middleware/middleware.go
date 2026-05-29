package middleware

import (
	"log"
	"net/http"
	"net/url"
	"strconv"
	"strings"
	"time"

	"gaoranim/internal/authsession"
	"gaoranim/internal/cache"
	"gaoranim/internal/models"
	"gaoranim/pkg/jwt"
	"gaoranim/pkg/response"

	"github.com/gin-gonic/gin"
	"gorm.io/gorm"
)

// Logger 日志中间件
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
	}
}

// CORS 跨域中间件（白名单模式，支持多域名动态匹配）
// allowedOrigins 为空时降级为 * （开发模式）
func CORS(allowedOrigins ...string) gin.HandlerFunc {
	allowed := make(map[string]bool, len(allowedOrigins))
	for _, o := range allowedOrigins {
		if o != "" {
			allowed[strings.TrimRight(o, "/")] = true
		}
	}

	return func(c *gin.Context) {
		origin := c.GetHeader("Origin")
		if origin == "" {
			c.Next()
			return
		}

		// 放行所有来源，安全由 JWT 认证保证，支持任意域名/CDN/Cloudflare
		c.Header("Access-Control-Allow-Origin", origin)
		c.Header("Access-Control-Allow-Methods", "GET, POST, PUT, DELETE, OPTIONS, PATCH")
		c.Header("Access-Control-Allow-Headers", "Origin, Content-Type, Authorization, X-Requested-With, Accept, X-Request-Id")
		c.Header("Access-Control-Allow-Credentials", "true")
		c.Header("Access-Control-Expose-Headers", "Content-Length, Content-Type")
		c.Header("Access-Control-Max-Age", "86400")
		c.Header("Vary", "Origin")

		if c.Request.Method == http.MethodOptions {
			c.AbortWithStatus(http.StatusNoContent)
			return
		}

		c.Next()
	}
}

func MediaCORS(baseURL string) gin.HandlerFunc {
	return func(c *gin.Context) {
		origin := c.GetHeader("Origin")
		allowOrigin := "*"
		if baseURL != "" && origin != "" {
			// 精确匹配或同源子路径
			base := strings.TrimRight(baseURL, "/")
			if strings.TrimRight(origin, "/") == base {
				allowOrigin = origin
			}
		}
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
}

// Auth 认证中间件
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
}

// OptionalAuth tries to authenticate the current user but does not reject
// anonymous requests when no token or an invalid token is provided.
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
}

// RequirePhoneBind enforces the global "require_phone_bind" system setting for
// authenticated user APIs. The current user and phone-bind endpoints must stay
// reachable, otherwise an unbound user could not finish the required binding.
//
// ★ 集群改造：优先读 Redis 缓存，避免每次请求都查 MySQL。
//   - system_setting  缓存 10 分钟（TTLSystemSetting）
//   - user phone 状态 缓存 5  分钟（TTLUserPhone）
func RequirePhoneBind(db *gorm.DB, ca *cache.Cache) gin.HandlerFunc {
	return func(c *gin.Context) {
		if db == nil || shouldSkipPhoneBindGuard(c) {
			c.Next()
			return
		}

		// ★ Step 1: 读系统设置（Redis → MySQL fallback）
		enabled, ok := requirePhoneBindEnabled(c, db, ca)
		if !ok {
			// 查询出错，放行（降级策略，不阻断业务）
			c.Next()
			return
		}
		if !enabled {
			c.Next()
			return
		}

		// ★ Step 2: 检查当前用户手机绑定状态（Redis → MySQL fallback）
		userUUID := strings.TrimSpace(c.GetString("user_id"))
		if userUUID == "" {
			response.Unauthorized(c, "请先登录")
			c.Abort()
			return
		}

		hasPhone, ok := userHasPhone(c, db, ca, userUUID)
		if !ok {
			response.Unauthorized(c, "用户不存在")
			c.Abort()
			return
		}
		if !hasPhone {
			response.Forbidden(c, "请先绑定手机号")
			c.Abort()
			return
		}

		c.Next()
	}
}

// requirePhoneBindEnabled 查询 require_phone_bind 系统设置。
// 返回 (enabled bool, ok bool)，ok=false 表示查询异常需要降级。
// ★ Redis缓存 10 分钟，miss 时查 MySQL 并回写。
func requirePhoneBindEnabled(c *gin.Context, db *gorm.DB, ca *cache.Cache) (bool, bool) {
	ctx := c.Request.Context()
	const settingKey = models.SettingRequirePhoneBind

	// 1. 读缓存
	if ca != nil {
		if val, found := ca.GetSystemSetting(ctx, settingKey); found {
			return isTruthySetting(val), true
		}
	}

	// 2. 缓存未命中，查 MySQL
	var setting models.SystemSetting
	if err := db.Where("`key` = ?", settingKey).First(&setting).Error; err != nil {
		// key 不存在视为未开启，同时缓存空值防止穿透
		if ca != nil {
			_ = ca.SetSystemSetting(ctx, settingKey, "false")
		}
		return false, true
	}

	// 3. 回写缓存
	if ca != nil {
		_ = ca.SetSystemSetting(ctx, settingKey, setting.Value)
	}

	return isTruthySetting(setting.Value), true
}

// userHasPhone 查询用户是否已绑定手机号。
// 返回 (hasPhone bool, ok bool)，ok=false 表示用户不存在。
// ★ Redis缓存 5 分钟，miss 时查 MySQL 并回写。
func userHasPhone(c *gin.Context, db *gorm.DB, ca *cache.Cache, userUUID string) (bool, bool) {
	ctx := c.Request.Context()

	// 1. 读缓存
	if ca != nil {
		if status, found := ca.GetUserPhoneStatus(ctx, userUUID); found {
			return status.HasPhone, true
		}
	}

	// 2. 缓存未命中，查 MySQL（只查 phone 字段，最小化查询开销）
	var user models.User
	if err := db.Select("id", "uuid", "phone").Where("uuid = ?", userUUID).First(&user).Error; err != nil {
		return false, false
	}

	// 3. 构建状态并回写缓存
	status := &cache.UserPhoneStatus{
		HasPhone: user.Phone != nil && strings.TrimSpace(*user.Phone) != "",
	}
	if status.HasPhone {
		status.Phone = *user.Phone
	}
	if ca != nil {
		_ = ca.SetUserPhoneStatus(ctx, userUUID, status)
	}

	return status.HasPhone, true
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
	claims, err := jwt.ParseToken(tokenString)
	if err != nil {
		return errUnauthorized("Token无效或已过期")
	}

	if authError := authsession.ValidateUserTokenStateWithToken(c.Request.Context(), cache, claims, tokenString); authError != "" {
		return errUnauthorized(authError)
	}

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
}

// RateLimit 限流中间件
func RateLimit(cache *cache.Cache) gin.HandlerFunc {
	return func(c *gin.Context) {
		key := "ip:" + c.ClientIP()

		// 每秒100个请求
		allowed, err := cache.RateLimit(c.Request.Context(), key, 100000, time.Second)
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
}

// WalletRateLimit 钱包操作专用限流（基于用户ID，更严格）
func WalletRateLimit(c *cache.Cache, limit int, window time.Duration) gin.HandlerFunc {
	return func(ctx *gin.Context) {
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
}

// UserRateLimit 用户维度限流（已登录用户，防止单用户刷接口）
// key 格式: user:rl:<userID>:<path>，基于 Redis 滑窗，集群下天然共享
func UserRateLimit(ca *cache.Cache, limit int, window time.Duration) gin.HandlerFunc {
	return func(c *gin.Context) {
		userID := c.GetString("user_id")
		if userID == "" {
			c.Next()
			return
		}
		key := "user:rl:" + userID + ":" + c.FullPath()
		allowed, err := ca.RateLimit(c.Request.Context(), key, limit, window)
		if err != nil {
			log.Printf("[RateLimit] UserRateLimit error userID=%s path=%s: %v", userID, c.FullPath(), err)
			c.Next()
			return
		}
		if !allowed {
			response.TooManyRequests(c, "操作过于频繁，请稍后再试")
			c.Abort()
			return
		}
		c.Next()
	}
}

// GetUserID 从上下文获取用户ID
func GetUserID(c *gin.Context) string {
	userID, exists := c.Get("user_id")
	if !exists {
		return ""
	}
	return userID.(string)
}

// GetDeviceID 从上下文获取设备ID
func GetDeviceID(c *gin.Context) string {
	deviceID, exists := c.Get("device_id")
	if !exists {
		return ""
	}
	return deviceID.(string)
}

// AdminAuth 管理员认证中间件
func AdminAuth() gin.HandlerFunc {
	return func(c *gin.Context) {
		authHeader := c.GetHeader("Authorization")
		if authHeader == "" {
			response.Unauthorized(c, "请先登录")
			c.Abort()
			return
		}

		parts := strings.SplitN(authHeader, " ", 2)
		if len(parts) != 2 || parts[0] != "Bearer" {
			response.Unauthorized(c, "Token格式错误")
			c.Abort()
			return
		}

		tokenString := parts[1]

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

		c.Set("admin_id", claims.AdminID)
		c.Set("admin_username", claims.Username)
		c.Set("admin_role", claims.Role)

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
}

// RequireRole 角色校验中间件
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
}

// GetAdminID 从上下文获取管理员ID
func GetAdminID(c *gin.Context) uint64 {
	adminID, exists := c.Get("admin_id")
	if !exists {
		return 0
	}
	return adminID.(uint64)
}

// GetAdminRole 从上下文获取管理员角色
func GetAdminRole(c *gin.Context) string {
	role, exists := c.Get("admin_role")
	if !exists {
		return ""
	}
	return role.(string)
}

// RequireWriteRole 写操作权限中间件 - 禁止演示管理员
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
}

// InternalOnly 仅允许内网 IP 访问（用于 /metrics 等敏感端点）
// 允许：127.0.0.1、::1、10.x.x.x、172.16-31.x.x、192.168.x.x
func InternalOnly() gin.HandlerFunc {
	return func(c *gin.Context) {
		ip := c.ClientIP()
		if !isInternalIP(ip) {
			c.AbortWithStatusJSON(http.StatusForbidden, gin.H{
				"code":    403,
				"message": "forbidden",
			})
			return
		}
		c.Next()
	}
}

// isInternalIP 判断是否为内网 IP
func isInternalIP(ip string) bool {
	// IPv6 loopback
	if ip == "::1" {
		return true
	}
	parts := strings.Split(ip, ".")
	if len(parts) != 4 {
		return false
	}
	first, err1 := strconv.Atoi(parts[0])
	second, err2 := strconv.Atoi(parts[1])
	if err1 != nil || err2 != nil {
		return false
	}
	switch {
	case first == 127:
		return true // 127.0.0.0/8 loopback
	case first == 10:
		return true // 10.0.0.0/8
	case first == 172 && second >= 16 && second <= 31:
		return true // 172.16.0.0/12
	case first == 192 && second == 168:
		return true // 192.168.0.0/16
	default:
		return false
	}
}
