// 文件用途：实现后端 HTTP 接口的请求处理和统一响应。
// 核心逻辑：绑定参数，校验身份与权限，调用业务服务并持久化关键状态。

package handlers

import (
	"context"
	"errors"
	"fmt"
	"github.com/gin-gonic/gin"
	"io"
	"net"
	"net/http"
	"net/netip"
	"net/url"
	"regexp"
	"strings"
	"time"
	"genericim/pkg/response"
)

// LinkPreviewHandler 处理链接预览请求
type LinkPreviewHandler struct{}

var errUnsafeLinkPreviewURL = errors.New("unsafe link preview url")

var linkPreviewBlockedIPPrefixes = []netip.Prefix{
	mustLinkPreviewPrefix("0.0.0.0/8"),
	mustLinkPreviewPrefix("10.0.0.0/8"),
	mustLinkPreviewPrefix("100.64.0.0/10"),
	mustLinkPreviewPrefix("127.0.0.0/8"),
	mustLinkPreviewPrefix("169.254.0.0/16"),
	mustLinkPreviewPrefix("172.16.0.0/12"),
	mustLinkPreviewPrefix("192.0.0.0/24"),
	mustLinkPreviewPrefix("192.0.2.0/24"),
	mustLinkPreviewPrefix("192.168.0.0/16"),
	mustLinkPreviewPrefix("198.18.0.0/15"),
	mustLinkPreviewPrefix("198.51.100.0/24"),
	mustLinkPreviewPrefix("203.0.113.0/24"),
	mustLinkPreviewPrefix("224.0.0.0/4"),
	mustLinkPreviewPrefix("240.0.0.0/4"),
	mustLinkPreviewPrefix("::/128"),
	mustLinkPreviewPrefix("::1/128"),
	mustLinkPreviewPrefix("fc00::/7"),
	mustLinkPreviewPrefix("fe80::/10"),
	mustLinkPreviewPrefix("ff00::/8"),
	mustLinkPreviewPrefix("2001:db8::/32"),
}

func NewLinkPreviewHandler() *LinkPreviewHandler {
	return &LinkPreviewHandler{}
}

// LinkPreviewResponse 链接预览响应
type LinkPreviewResponse struct {
	URL         string `json:"url"`
	Title       string `json:"title"`
	Description string `json:"description"`
	Image       string `json:"image"`
	SiteName    string `json:"site_name"`
	Favicon     string `json:"favicon"`
}

// GetPreview 获取链接预览数据
func (h *LinkPreviewHandler) GetPreview(c *gin.Context) {
	rawURL := c.Query("url")
	if rawURL == "" {
		response.Error(c, http.StatusBadRequest, "url 参数不能为空")
		return
	}

	parsedURL, err := normalizeLinkPreviewURL(rawURL)
	if err != nil {
		response.Error(c, http.StatusBadRequest, "无效的URL格式")
		return
	}
	rawURL = parsedURL.String()
	client := newLinkPreviewHTTPClient()

	req, err := http.NewRequest("GET", rawURL, nil)
	if err != nil {
		// 无法访问时返回基本信息（不报错，前端降级显示）
		response.Success(c, LinkPreviewResponse{URL: rawURL})
		return
	}

	// 模拟浏览器请求头
	req.Header.Set("User-Agent", "Mozilla/5.0 (compatible; LinkPreviewBot/1.0)")
	req.Header.Set("Accept", "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8")
	req.Header.Set("Accept-Language", "zh-CN,zh;q=0.9,en;q=0.8")

	resp, err := client.Do(req)
	if err != nil {
		if errors.Is(err, errUnsafeLinkPreviewURL) {
			response.Error(c, http.StatusBadRequest, "不允许预览内网或本地地址")
			return
		}
		response.Success(c, LinkPreviewResponse{URL: rawURL})
		return
	}
	defer resp.Body.Close()

	// 限制读取 512KB，防止超大页面
	body, err := io.ReadAll(io.LimitReader(resp.Body, 512*1024))
	if err != nil {
		response.Success(c, LinkPreviewResponse{URL: rawURL})
		return
	}
	preview := parseLinkPreview(rawURL, string(body))
	response.Success(c, preview)
}

func normalizeLinkPreviewURL(rawURL string) (*url.URL, error) {
	rawURL = strings.TrimSpace(rawURL)
	if rawURL == "" {
		return nil, fmt.Errorf("empty url")
	}

	parsed, err := url.Parse(rawURL)
	if err != nil {
		return nil, err
	}
	if parsed.Scheme == "" {
		if parsed.Host == "" {
			parsed, err = url.Parse("https://" + rawURL)
			if err != nil {
				return nil, err
			}
		} else {
			parsed.Scheme = "https"
		}
	}
	if err := validateLinkPreviewURL(parsed); err != nil {
		return nil, err
	}
	return parsed, nil
}

func validateLinkPreviewURL(parsed *url.URL) error {
	if parsed == nil {
		return fmt.Errorf("empty url")
	}
	if parsed.Scheme != "http" && parsed.Scheme != "https" {
		return fmt.Errorf("unsupported scheme")
	}
	if parsed.Opaque != "" || parsed.User != nil {
		return fmt.Errorf("unsupported url")
	}
	host := strings.TrimSpace(parsed.Hostname())
	if host == "" {
		return fmt.Errorf("empty host")
	}
	if isBlockedLinkPreviewHostname(host) {
		return errUnsafeLinkPreviewURL
	}
	if ip := net.ParseIP(host); ip != nil && !isPublicRoutableLinkPreviewIP(ip) {
		return errUnsafeLinkPreviewURL
	}
	return nil
}

func newLinkPreviewHTTPClient() *http.Client {
	return newSafeOutboundHTTPClient(8 * time.Second)
}

func newSafeOutboundHTTPClient(timeout time.Duration) *http.Client {
	dialer := &net.Dialer{Timeout: 5 * time.Second}
	transport := &http.Transport{
		Proxy:                 nil,
		DialContext:           safeLinkPreviewDialContext(dialer),
		TLSHandshakeTimeout:   5 * time.Second,
		ResponseHeaderTimeout: timeout,
		ExpectContinueTimeout: time.Second,
	}
	return &http.Client{
		Timeout:       timeout,
		Transport:     transport,
		CheckRedirect: checkLinkPreviewRedirect,
	}
}

func safeLinkPreviewDialContext(dialer *net.Dialer) func(context.Context, string, string) (net.Conn, error) {
	return func(ctx context.Context, network, address string) (net.Conn, error) {
		host, port, err := net.SplitHostPort(address)
		if err != nil {
			return nil, err
		}
		if isBlockedLinkPreviewHostname(host) {
			return nil, errUnsafeLinkPreviewURL
		}

		ips, err := net.DefaultResolver.LookupIPAddr(ctx, host)
		if err != nil {
			return nil, err
		}
		for _, item := range ips {
			if !isPublicRoutableLinkPreviewIP(item.IP) {
				return nil, errUnsafeLinkPreviewURL
			}
		}

		var lastErr error
		for _, item := range ips {
			conn, err := dialer.DialContext(ctx, network, net.JoinHostPort(item.IP.String(), port))
			if err == nil {
				return conn, nil
			}
			lastErr = err
		}
		if lastErr == nil {
			lastErr = errUnsafeLinkPreviewURL
		}
		return nil, lastErr
	}
}

func checkLinkPreviewRedirect(req *http.Request, via []*http.Request) error {
	if len(via) >= 5 {
		return http.ErrUseLastResponse
	}
	if err := validateLinkPreviewURL(req.URL); err != nil {
		if errors.Is(err, errUnsafeLinkPreviewURL) {
			return err
		}
		return http.ErrUseLastResponse
	}
	return nil
}

func isBlockedLinkPreviewHostname(host string) bool {
	host = strings.TrimSuffix(strings.ToLower(strings.TrimSpace(host)), ".")
	return host == "localhost" || strings.HasSuffix(host, ".localhost")
}

func isPublicRoutableLinkPreviewIP(ip net.IP) bool {
	addr, ok := netip.AddrFromSlice(ip)
	if !ok {
		return false
	}
	addr = addr.Unmap()
	if !addr.IsValid() || !addr.IsGlobalUnicast() {
		return false
	}
	for _, prefix := range linkPreviewBlockedIPPrefixes {
		if prefix.Contains(addr) {
			return false
		}
	}
	return true
}

func mustLinkPreviewPrefix(raw string) netip.Prefix {
	prefix, err := netip.ParsePrefix(raw)
	if err != nil {
		panic(err)
	}
	return prefix
}

// parseLinkPreview 解析 HTML 提取预览数据
func parseLinkPreview(pageURL, html string) LinkPreviewResponse {
	preview := LinkPreviewResponse{URL: pageURL}

	// 标题：OG > <title>
	if v := getOgContent(html, "og:title"); v != "" {
		preview.Title = v
	} else if v := getTagContent(html, "title"); v != "" {
		preview.Title = v
	}

	// 描述：OG > meta description
	if v := getOgContent(html, "og:description"); v != "" {
		preview.Description = v
	} else if v := getMetaNameContent(html, "description"); v != "" {
		preview.Description = v
	}

	// 图片
	if v := getOgContent(html, "og:image"); v != "" {
		preview.Image = safeLinkPreviewAssetURL(pageURL, v)
	}

	// 站点名称
	if v := getOgContent(html, "og:site_name"); v != "" {
		preview.SiteName = v
	}

	// Favicon
	preview.Favicon = getFavicon(html, pageURL)
	return preview
}

// getOgContent 获取 og: 属性的 content
func getOgContent(html, property string) string {
	escaped := regexp.QuoteMeta(property)
	// property=... content=...
	re1 := regexp.MustCompile(`(?i)<meta[^>]+property=["']` + escaped + `["'][^>]*content=["']([^"']+)["']`)
	if m := re1.FindStringSubmatch(html); len(m) > 1 {
		return decodeHTMLEntities(strings.TrimSpace(m[1]))
	}
	// content=... property=...
	re2 := regexp.MustCompile(`(?i)<meta[^>]+content=["']([^"']+)["'][^>]*property=["']` + escaped + `["']`)
	if m := re2.FindStringSubmatch(html); len(m) > 1 {
		return decodeHTMLEntities(strings.TrimSpace(m[1]))
	}
	return ""
}

// getMetaNameContent 获取 meta name 的 content
func getMetaNameContent(html, name string) string {
	escaped := regexp.QuoteMeta(name)
	re1 := regexp.MustCompile(`(?i)<meta[^>]+name=["']` + escaped + `["'][^>]*content=["']([^"']+)["']`)
	if m := re1.FindStringSubmatch(html); len(m) > 1 {
		return decodeHTMLEntities(strings.TrimSpace(m[1]))
	}
	re2 := regexp.MustCompile(`(?i)<meta[^>]+content=["']([^"']+)["'][^>]*name=["']` + escaped + `["']`)
	if m := re2.FindStringSubmatch(html); len(m) > 1 {
		return decodeHTMLEntities(strings.TrimSpace(m[1]))
	}
	return ""
}

// getTagContent 获取 HTML 标签内容
func getTagContent(html, tag string) string {
	re := regexp.MustCompile(`(?i)<` + tag + `[^>]*>([^<]+)<\/` + tag + `>`)
	if m := re.FindStringSubmatch(html); len(m) > 1 {
		return decodeHTMLEntities(strings.TrimSpace(m[1]))
	}
	return ""
}

// getFavicon 获取 favicon URL
func getFavicon(html, pageURL string) string {
	// link rel=icon href=...
	re1 := regexp.MustCompile(`(?i)<link[^>]+rel=["'](?:shortcut icon|icon)["'][^>]*href=["']([^"']+)["']`)
	if m := re1.FindStringSubmatch(html); len(m) > 1 {
		return safeLinkPreviewAssetURL(pageURL, strings.TrimSpace(m[1]))
	}
	re2 := regexp.MustCompile(`(?i)<link[^>]+href=["']([^"']+)["'][^>]*rel=["'](?:shortcut icon|icon)["']`)
	if m := re2.FindStringSubmatch(html); len(m) > 1 {
		return safeLinkPreviewAssetURL(pageURL, strings.TrimSpace(m[1]))
	}
	// 默认 /favicon.ico
	u, err := url.Parse(pageURL)
	if err != nil {
		return ""
	}
	return safeLinkPreviewAssetURL(pageURL, u.Scheme+"://"+u.Host+"/favicon.ico")
}

func safeLinkPreviewAssetURL(base, rel string) string {
	resolved := resolveURL(base, strings.TrimSpace(rel))
	parsed, err := url.Parse(resolved)
	if err != nil || parsed == nil {
		return ""
	}
	if parsed.Scheme != "http" && parsed.Scheme != "https" {
		return ""
	}
	if parsed.Opaque != "" || parsed.User != nil {
		return ""
	}
	host := strings.TrimSpace(parsed.Hostname())
	if host == "" || isBlockedLinkPreviewHostname(host) {
		return ""
	}
	if ip := net.ParseIP(host); ip != nil && !isPublicRoutableLinkPreviewIP(ip) {
		return ""
	}
	return parsed.String()
}

// resolveURL 将相对URL转为绝对URL
func resolveURL(base, rel string) string {
	if strings.HasPrefix(rel, "http://") || strings.HasPrefix(rel, "https://") {
		return rel
	}
	if strings.HasPrefix(rel, "data:") || strings.HasPrefix(rel, "//") {
		if strings.HasPrefix(rel, "//") {
			u, err := url.Parse(base)
			if err != nil {
				return rel
			}
			return u.Scheme + ":" + rel
		}
		return rel
	}
	b, err := url.Parse(base)
	if err != nil {
		return rel
	}
	r, err := url.Parse(rel)
	if err != nil {
		return rel
	}
	return b.ResolveReference(r).String()
}

// decodeHTMLEntities 解码常见 HTML 实体
func decodeHTMLEntities(s string) string {
	r := strings.NewReplacer(
		"&amp;", "&",
		"&lt;", "<",
		"&gt;", ">",
		"&quot;", `"`,
		"&#39;", "'",
		"&apos;", "'",
		"&#x27;", "'",
		"&#x2F;", "/",
		"&nbsp;", " ",
	)
	return r.Replace(s)
}
