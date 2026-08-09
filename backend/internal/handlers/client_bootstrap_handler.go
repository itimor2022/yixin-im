// 文件用途：实现后端 HTTP 接口的请求处理和统一响应。
// 核心逻辑：绑定参数，校验身份与权限，调用业务服务并持久化关键状态。

package handlers

import (
	"encoding/json"
	"fmt"
	"github.com/gin-gonic/gin"
	"gorm.io/gorm"
	"net"
	"net/url"
	"sort"
	"strings"
	"genericim/internal/config"
	"genericim/internal/models"
	"genericim/pkg/response"
)

type ClientBootstrapHandler struct {
	cfg *config.Config
	db  *gorm.DB
}

func NewClientBootstrapHandler(cfg *config.Config, db *gorm.DB) *ClientBootstrapHandler {
	return &ClientBootstrapHandler{cfg: cfg, db: db}
}

type clientBootstrapPayload struct {
	Version       int                                  `json:"version"`
	TTLSeconds    int                                  `json:"ttl_seconds"`
	APIEndpoints  []config.ClientEndpointConfig        `json:"api_endpoints"`
	WSEndpoints   []config.ClientEndpointConfig        `json:"ws_endpoints"`
	MediaBaseURLs []string                             `json:"media_base_urls"`
	Strategy      config.ClientBootstrapStrategyConfig `json:"strategy"`
}

func (h *ClientBootstrapHandler) GetBootstrap(c *gin.Context) {
	// HTTP 响应禁用中间缓存；payload 中的 TTL 仅用于客户端端点选择结果的本地缓存。
	c.Header("Cache-Control", "no-store")
	response.Success(c, h.payload(c))
}
func (h *ClientBootstrapHandler) payload(c *gin.Context) clientBootstrapPayload {
	// 数据库配置是运行时权威来源，YAML 仅为缺省值；随后再按客户端网络环境重写不可达地址。
	cfg := h.runtimeConfig()
	baseURL := externalBaseURL(c, h.cfg)
	wsURL := websocketURLFromBase(baseURL)
	apiEndpoints := normalizeClientEndpoints(

		cfg.APIEndpoints,

		baseURL,

		"/api/v1/ping",

		h.cfg.Server.Mode,
	)
	apiEndpoints = rewriteAndroidEmulatorEndpoints(apiEndpoints, baseURL)
	if isWebBootstrapRequest(c) {

		apiEndpoints = rewritePrivateWebEndpoints(apiEndpoints, baseURL)
	}
	wsEndpoints := normalizeClientEndpoints(

		cfg.WSEndpoints,

		wsURL,

		"",

		h.cfg.Server.Mode,
	)
	wsEndpoints = rewriteAndroidEmulatorEndpoints(wsEndpoints, wsURL)
	if isWebBootstrapRequest(c) {

		wsEndpoints = rewritePrivateWebEndpoints(wsEndpoints, wsURL)
	}
	mediaFallbackURL := mediaBaseURL(baseURL, h.cfg)
	if isWebBootstrapRequest(c) && isPrivateDevelopmentURL(mediaFallbackURL) {

		mediaFallbackURL = baseURL
	}
	if isAndroidEmulatorURL(mediaFallbackURL) && !isAndroidEmulatorURL(baseURL) {

		mediaFallbackURL = baseURL
	}
	mediaURLs := normalizeBaseURLs(cfg.MediaBaseURLs, h.cfg.Server.Mode)
	if len(mediaURLs) == 0 {

		mediaURLs = normalizeBaseURLs([]string{mediaFallbackURL}, h.cfg.Server.Mode)
	}
	mediaURLs = rewriteAndroidEmulatorBaseURLs(mediaURLs, mediaFallbackURL)
	if isWebBootstrapRequest(c) {

		mediaURLs = rewritePrivateWebBaseURLs(mediaURLs, mediaFallbackURL)
	}
	return clientBootstrapPayload{

		Version: defaultInt(cfg.Version, 1),

		TTLSeconds: defaultInt(cfg.TTLSeconds, 300),

		APIEndpoints: apiEndpoints,

		WSEndpoints: wsEndpoints,

		MediaBaseURLs: mediaURLs,

		Strategy: config.ClientBootstrapStrategyConfig{

			ConnectTimeoutMS: defaultInt(cfg.Strategy.ConnectTimeoutMS, 5000),

			HealthTimeoutMS: defaultInt(cfg.Strategy.HealthTimeoutMS, 3000),

			FailThreshold: defaultInt(cfg.Strategy.FailThreshold, 1),

			CooldownSeconds: defaultInt(cfg.Strategy.CooldownSeconds, 60),

			PreferLastSuccess: true,
		},
	}
}
func (h *ClientBootstrapHandler) runtimeConfig() config.ClientBootstrapConfig {
	if h == nil || h.cfg == nil {

		return config.ClientBootstrapConfig{}
	}
	cfg := h.cfg.ClientBootstrap
	if h.db == nil {

		return cfg
	}
	var setting models.SystemSetting
	if err := h.db.Where("`key` = ?", models.SettingClientBootstrap).First(&setting).Error; err != nil {

		return cfg
	}
	raw := strings.TrimSpace(setting.Value)
	if raw == "" || raw == "{}" {

		return cfg
	}
	var dbCfg config.ClientBootstrapConfig
	if err := json.Unmarshal([]byte(raw), &dbCfg); err != nil {

		return cfg
	}
	// 允许后台只覆盖部分字段，未配置项继续继承部署时的 YAML 默认值。
	return fillClientBootstrapDefaults(dbCfg, cfg)
}
func fillClientBootstrapDefaults(dbCfg, yamlCfg config.ClientBootstrapConfig) config.ClientBootstrapConfig {
	out := dbCfg
	if out.Version <= 0 {

		out.Version = yamlCfg.Version
	}
	if out.TTLSeconds <= 0 {

		out.TTLSeconds = yamlCfg.TTLSeconds
	}
	if len(out.APIEndpoints) == 0 {

		out.APIEndpoints = yamlCfg.APIEndpoints
	}
	if len(out.WSEndpoints) == 0 {

		out.WSEndpoints = yamlCfg.WSEndpoints
	}
	if len(out.MediaBaseURLs) == 0 {

		out.MediaBaseURLs = yamlCfg.MediaBaseURLs
	}
	if out.Strategy.ConnectTimeoutMS <= 0 {

		out.Strategy.ConnectTimeoutMS = yamlCfg.Strategy.ConnectTimeoutMS
	}
	if out.Strategy.HealthTimeoutMS <= 0 {

		out.Strategy.HealthTimeoutMS = yamlCfg.Strategy.HealthTimeoutMS
	}
	if out.Strategy.FailThreshold <= 0 {

		out.Strategy.FailThreshold = yamlCfg.Strategy.FailThreshold
	}
	if out.Strategy.CooldownSeconds <= 0 {

		out.Strategy.CooldownSeconds = yamlCfg.Strategy.CooldownSeconds
	}
	if !out.Strategy.PreferLastSuccess {

		out.Strategy.PreferLastSuccess = yamlCfg.Strategy.PreferLastSuccess
	}
	return out
}
func externalBaseURL(c *gin.Context, cfg *config.Config) string {
	if cfg != nil {

		if value := strings.TrimSpace(cfg.Server.BaseURL); value != "" {

			if isWebBootstrapRequest(c) && isPrivateDevelopmentURL(value) {

				requestURL := requestExternalBaseURL(c, cfg)

				if requestURL != "" {

					return requestURL

				}

			}

			if isAndroidEmulatorURL(value) {

				requestURL := requestExternalBaseURL(c, cfg)

				if requestURL != "" && !isAndroidEmulatorURL(requestURL) {

					return requestURL

				}

			}

			return strings.TrimRight(value, "/")

		}
	}
	return requestExternalBaseURL(c, cfg)
}
func requestExternalBaseURL(c *gin.Context, cfg *config.Config) string {
	proto := strings.TrimSpace(c.GetHeader("X-Forwarded-Proto"))
	if proto == "" {

		proto = "http"

		if c.Request != nil && c.Request.TLS != nil {

			proto = "https"

		}
	}
	host := ""
	if c.Request != nil {

		host = strings.TrimSpace(c.Request.Host)
	}
	if host == "" {

		host = "localhost"

		if cfg != nil && cfg.Server.Port > 0 {

			host = fmt.Sprintf("localhost:%d", cfg.Server.Port)

		}
	}
	return strings.TrimRight(proto+"://"+host, "/")
}
func mediaBaseURL(baseURL string, cfg *config.Config) string {
	if cfg != nil {

		if value := strings.TrimSpace(cfg.Storage.Local.BaseURL); value != "" {

			return strings.TrimRight(value, "/")

		}
	}
	return baseURL
}
func websocketURLFromBase(baseURL string) string {
	if baseURL == "" {

		return ""
	}
	wsURL := strings.TrimRight(baseURL, "/") + "/api/v1/ws"
	if strings.HasPrefix(wsURL, "https://") {

		return "wss://" + strings.TrimPrefix(wsURL, "https://")
	}
	if strings.HasPrefix(wsURL, "http://") {

		return "ws://" + strings.TrimPrefix(wsURL, "http://")
	}
	return wsURL
}
func normalizeClientEndpoints(
	configured []config.ClientEndpointConfig,
	fallbackURL string,
	defaultHealthPath string,
	serverMode string) []config.ClientEndpointConfig {
	endpoints := configured
	if len(endpoints) == 0 && strings.TrimSpace(fallbackURL) != "" {

		endpoints = []config.ClientEndpointConfig{{

			ID: "default",

			URL: fallbackURL,

			Priority: 10,

			HealthPath: defaultHealthPath,
		}}
	}
	out := make([]config.ClientEndpointConfig, 0, len(endpoints))
	seen := make(map[string]struct{}, len(endpoints))
	for i, endpoint := range endpoints {

		// release 模式会在这里过滤明文地址，避免把不安全端点下发给正式客户端。

		endpoint.URL = strings.TrimRight(strings.TrimSpace(endpoint.URL), "/")

		if endpoint.URL == "" || !isAllowedClientEndpointURL(endpoint.URL, serverMode) {

			continue

		}

		if _, ok := seen[endpoint.URL]; ok {

			continue

		}

		seen[endpoint.URL] = struct{}{}

		if strings.TrimSpace(endpoint.ID) == "" {

			endpoint.ID = fmt.Sprintf("endpoint-%d", i+1)

		}

		if endpoint.Priority <= 0 {

			endpoint.Priority = (i + 1) * 10

		}

		if endpoint.HealthPath == "" {

			endpoint.HealthPath = defaultHealthPath

		}
		out = append(out, endpoint)
	}
	sort.SliceStable(out, func(i, j int) bool {

		return out[i].Priority < out[j].Priority
	})
	return out
}
func normalizeBaseURLs(values []string, serverMode string) []string {
	out := make([]string, 0, len(values))
	seen := make(map[string]struct{}, len(values))
	for _, value := range values {

		value = strings.TrimRight(strings.TrimSpace(value), "/")

		if value == "" || !isAllowedHTTPClientURL(value, serverMode) {

			continue

		}

		if _, ok := seen[value]; ok {

			continue

		}

		seen[value] = struct{}{}
		out = append(out, value)
	}
	return out
}
func rewriteAndroidEmulatorEndpoints(
	endpoints []config.ClientEndpointConfig,
	fallbackURL string) []config.ClientEndpointConfig {
	if len(endpoints) == 0 {

		return endpoints
	}
	out := make([]config.ClientEndpointConfig, 0, len(endpoints))
	for _, endpoint := range endpoints {

		endpoint.URL = rewriteAndroidEmulatorURL(endpoint.URL, fallbackURL)
		out = append(out, endpoint)
	}
	return out
}
func rewriteAndroidEmulatorBaseURLs(values []string, fallbackURL string) []string {
	if len(values) == 0 {

		return values
	}
	out := make([]string, 0, len(values))
	for _, value := range values {

		out = append(out, rewriteAndroidEmulatorURL(value, fallbackURL))
	}
	return out
}
func isWebBootstrapRequest(c *gin.Context) bool {
	if c == nil {

		return false
	}
	if strings.EqualFold(

		strings.TrimSpace(c.GetHeader("X-Client-Platform")),

		"web",
	) {

		return true
	}
	return strings.TrimSpace(c.GetHeader("Origin")) != ""
}
func rewritePrivateWebEndpoints(
	endpoints []config.ClientEndpointConfig,
	fallbackURL string) []config.ClientEndpointConfig {
	if len(endpoints) == 0 {

		return endpoints
	}
	out := make([]config.ClientEndpointConfig, 0, len(endpoints))
	for _, endpoint := range endpoints {

		endpoint.URL = rewritePrivateWebURL(endpoint.URL, fallbackURL)
		out = append(out, endpoint)
	}
	return out
}
func rewritePrivateWebBaseURLs(values []string, fallbackURL string) []string {
	if len(values) == 0 {

		return values
	}
	out := make([]string, 0, len(values))
	for _, value := range values {

		out = append(out, rewritePrivateWebURL(value, fallbackURL))
	}
	return out
}
func rewritePrivateWebURL(rawURL, fallbackURL string) string {
	// 浏览器无法访问服务端所在机器的 localhost/私网地址，改用本次请求可达的外部地址。
	parsedRaw, err := url.Parse(strings.TrimSpace(rawURL))
	if err != nil || parsedRaw.Hostname() == "" ||

		!isPrivateDevelopmentHost(parsedRaw.Hostname()) {

		return rawURL
	}
	parsedFallback, err := url.Parse(strings.TrimSpace(fallbackURL))
	if err != nil || parsedFallback.Hostname() == "" {

		return rawURL
	}
	return strings.TrimRight(fallbackURL, "/")
}
func isPrivateDevelopmentHost(host string) bool {
	host = strings.TrimSpace(strings.Trim(host, "[]"))
	if strings.EqualFold(host, "localhost") {

		return true
	}
	ip := net.ParseIP(host)
	return ip != nil && (ip.IsLoopback() || ip.IsPrivate())
}
func isPrivateDevelopmentURL(rawURL string) bool {
	parsed, err := url.Parse(strings.TrimSpace(rawURL))
	return err == nil &&

		parsed.Hostname() != "" &&

		isPrivateDevelopmentHost(parsed.Hostname())
}
func rewriteAndroidEmulatorURL(rawURL, fallbackURL string) string {
	parsedRaw, err := url.Parse(strings.TrimSpace(rawURL))
	if err != nil || parsedRaw.Host == "" || !isAndroidEmulatorHost(parsedRaw.Host) {

		return rawURL
	}
	parsedFallback, err := url.Parse(strings.TrimSpace(fallbackURL))
	if err != nil || parsedFallback.Host == "" || isAndroidEmulatorHost(parsedFallback.Host) {

		return rawURL
	}
	return strings.TrimRight(fallbackURL, "/")
}
func isAndroidEmulatorURL(rawURL string) bool {
	parsed, err := url.Parse(strings.TrimSpace(rawURL))
	if err != nil || parsed.Host == "" {

		return false
	}
	return isAndroidEmulatorHost(parsed.Host)
}
func isAndroidEmulatorHost(host string) bool {
	parsedHost := strings.TrimSpace(host)
	if parsedHost == "" {

		return false
	}
	if strings.Contains(parsedHost, ":") {

		if splitHost, _, found := strings.Cut(parsedHost, ":"); found {

			parsedHost = splitHost

		}
	}
	return parsedHost == "10.0.2.2"
}
func isAllowedClientEndpointURL(rawURL, serverMode string) bool {
	parsed, err := url.Parse(rawURL)
	if err != nil || parsed.Host == "" || parsed.User != nil {

		return false
	}
	switch parsed.Scheme {
	case "https", "wss":

		return true
	case "http", "ws":

		return !strings.EqualFold(strings.TrimSpace(serverMode), "release")
	default:

		return false
	}
}
func isAllowedHTTPClientURL(rawURL, serverMode string) bool {
	parsed, err := url.Parse(rawURL)
	if err != nil || parsed.Host == "" || parsed.User != nil {

		return false
	}
	switch parsed.Scheme {
	case "https":

		return true
	case "http":

		return !strings.EqualFold(strings.TrimSpace(serverMode), "release")
	default:

		return false
	}
}
func defaultInt(value, fallback int) int {
	if value > 0 {

		return value
	}
	return fallback
}
