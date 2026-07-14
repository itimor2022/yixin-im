package middleware

import (
	"context"
	"log"
	"net/http"
	"net/url"
	"os"
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

// CORS 跨域中间件（严格白名单模式）
//
// allowedOrigins 为空时降级为 `*` 但强制关闭 credentials —— 适合 Nginx 前面已经做过
// CORS 的开发/内网场景；配置了白名单则严格匹配，且允许 credentials（JWT via cookie）。
//
// 修复要点：原实现无条件把请求 Origin 反射到 Access-Control-Allow-Origin，同时开
// Allow-Credentials，等价于关掉了跨站保护（任何站点都能带用户 cookie 打你）。
func CORS(allowedOrigins ...string) gin.HandlerFunc {
	allowed := make(map[string]bool, len(allowedOrigins))
	for _, o := range allowedOrigins {
		if o != "" {
			allowed[strings.TrimRight(o, "/")] = true
		}
	}
	hasWhitelist := len(allowed) > 0

	return func(c *gin.Context) {
		origin := c.GetHeader("Origin")
		if origin == "" {
			c.Next()
			return
		}

		originKey := strings.TrimRight(origin, "/")

		if hasWhitelist {
			if !allowed[originKey] {
				// 不在白名单，直接放弃写 CORS 头。浏览器会自行拦截。
				// 预检请求也直接 204，避免暴露服务器信息。
				if c.Request.Method == http.MethodOptions {
					c.AbortWithStatus(http.StatusNoContent)
					return
				}
				c.Next()
				return
			}
			c.Header("Access-Control-Allow-Origin", origin)
			c.Header("Access-Control-Allow-Credentials", "true")
		} else {
			// 开发模式：无白名单则回 `*`，但必须关掉 credentials（浏览器规范要求）
			c.Header("Access-Control-Allow-Origin", "*")
		}
		c.Header("Access-Control-Allow-Methods", "GET, POST, PUT, DELETE, OPTIONS, PATCH")
		c.Header("Access-Control-Allow-Headers", "Origin, Content-Type, Authorization, X-Requested-With, Accept, X-Request-Id")
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

// MediaSecurityHeaders 给 /uploads 静态目录加安全响应头。
//
// 目的：
//   - X-Content-Type-Options: nosniff  —— 禁止浏览器嗅探 Content-Type，
//     防止 image.jpg.html 被当 HTML 解析、eval 掉里面的 <script>。
//   - Content-Security-Policy: 只允许自身域展示媒体，同时禁止内联脚本，
//     即便被塞了 HTML 也执行不了 JS。
//   - Content-Disposition: 对于 /uploads/files/... 的通用附件路径，强制 attachment
//     下载，绝不 inline 打开。图片/视频/头像等业务白名单目录不做强制下载，
//     否则前端 <img> 无法展示。
//   - X-Frame-Options: DENY —— 防止上传目录被别的站 iframe 内嵌做 clickjacking。
func MediaSecurityHeaders() gin.HandlerFunc {
	return func(c *gin.Context) {
		c.Header("X-Content-Type-Options", "nosniff")
		c.Header("X-Frame-Options", "DENY")
		c.Header("Content-Security-Policy", "default-src 'none'; img-src 'self' data:; media-src 'self'; sandbox")
		// 只对通用附件路径强制下载；图片、视频、头像等仍走 inline，才能被前端展示。
		if strings.Contains(c.Request.URL.Path, "/uploads/files/") {
			c.Header("Content-Disposition", "attachment")
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

		ctx := context.WithValue(c.Request.Context(), "client_ip", c.ClientIP())
		c.Request = c.Request.WithContext(ctx)

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

// RateLimit 全局 IP 限流中间件
//
// 之前设的 100000/秒 相当于没设，容易被 DDoS 打穿；改为每 IP 每秒 300 次的滑动窗口。
// 说明：
//   - Gin 的 ClientIP() 只有在 engine.SetTrustedProxies() 正确配置后才能真正拿到真实 IP，
//     否则外网用户能通过 X-Forwarded-For 头伪造 IP 绕过限流。main.go 已按 config
//     里的 trusted_proxies 显式设置，这里可以放心用。
//   - 阈值可通过环境变量 YIXIN_IP_RATE_LIMIT 覆盖，方便应急调整。
func RateLimit(cache *cache.Cache) gin.HandlerFunc {
	limit := 300
	if v := strings.TrimSpace(getEnv("YIXIN_IP_RATE_LIMIT", "")); v != "" {
		if n, err := strconv.Atoi(v); err == nil && n > 0 {
			limit = n
		}
	}
	return func(c *gin.Context) {
		key := "ip:" + c.ClientIP()
		allowed, err := cache.RateLimit(c.Request.Context(), key, limit, time.Second)
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

// getEnv 读取环境变量，未设置时返回默认值。middleware 层复用工具。
func getEnv(key, def string) string {
	if v, ok := os.LookupEnv(key); ok {
		return v
	}
	return def
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

// AdminIPBlockedCode 管理员 IP 不在白名单时返回的业务码
// 前端据此将后台所有界面跳转到 404 页面
const AdminIPBlockedCode = 40403

// AdminAuth 管理员认证中间件
func AdminAuth(db *gorm.DB) gin.HandlerFunc {
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

		// IP 白名单校验：白名单不匹配时，后台所有界面跳转 404
		// 同时装载角色 code（用于 demo_admin 类只读账号的写保护）
		roleCode := resolveRoleCodeFallback(claims.Role)
		if db != nil {
			var admin models.Admin
			if err := db.Select("id", "username", "role", "whitelist_ips").First(&admin, claims.AdminID).Error; err == nil {
				if !admin.IsIPAllowed(c.ClientIP()) {
					c.AbortWithStatusJSON(http.StatusNotFound, gin.H{
						"code":    AdminIPBlockedCode,
						"message": "页面不存在",
					})
					return
				}
				// 查询角色权限码（内置 super_admin 直接给 R_SUPER）
				if admin.Role == "super_admin" {
					roleCode = models.RoleCodeSuper
				} else {
					var role models.Role
					if err := db.Select("code").Where("`key` = ?", admin.Role).First(&role).Error; err == nil && role.Code != "" {
						roleCode = role.Code
					}
				}
			}
		}

		c.Set("admin_id", claims.AdminID)
		c.Set("admin_username", claims.Username)
		c.Set("admin_role", claims.Role)
		c.Set("admin_role_code", roleCode)

		c.Next()
	}
}

// isValidAdminRole 判断 role 字段是否合法
// 由于角色现已可动态扩展，这里只做基本非空校验；具体权限由 admin_role_code 决定
func isValidAdminRole(role string) bool {
	return strings.TrimSpace(role) != ""
}

// resolveRoleCodeFallback 在无法查询数据库时，给内置角色兜底返回权限码
func resolveRoleCodeFallback(role string) string {
	switch role {
	case "super_admin":
		return models.RoleCodeSuper
	case "admin", "operator":
		return models.RoleCodeAdmin
	case "demo_admin":
		return models.RoleCodeDemo
	default:
		return models.RoleCodeAdmin
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

// GetAdminRole 从上下文获取管理员角色 key（用于 UI 展示/审计）
func GetAdminRole(c *gin.Context) string {
	role, exists := c.Get("admin_role")
	if !exists {
		return ""
	}
	return role.(string)
}

// GetAdminRoleCode 从上下文获取当前管理员的权限码（R_SUPER/R_ADMIN/R_DEMO）
func GetAdminRoleCode(c *gin.Context) string {
	v, exists := c.Get("admin_role_code")
	if !exists {
		return models.RoleCodeAdmin
	}
	return v.(string)
}

// IsDemoAdmin 判断当前登录管理员是否为只读演示账号
func IsDemoAdmin(c *gin.Context) bool {
	return GetAdminRoleCode(c) == models.RoleCodeDemo
}

// RequireWriteRole 写操作权限中间件 - 只读账号（R_DEMO）无法写入
func RequireWriteRole() gin.HandlerFunc {
	return func(c *gin.Context) {
		switch GetAdminRoleCode(c) {
		case models.RoleCodeSuper, models.RoleCodeAdmin:
			c.Next()
		case models.RoleCodeDemo:
			response.Forbidden(c, "演示账号无法执行此操作")
			c.Abort()
		default:
			response.Forbidden(c, "无权限执行此操作")
			c.Abort()
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
