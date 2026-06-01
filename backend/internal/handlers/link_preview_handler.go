package handlers

import (
	"io"
	"net/http"
	"net/url"
	"regexp"
	"strings"
	"time"

	"gaoranim/pkg/response"

	"github.com/gin-gonic/gin"
)

// LinkPreviewHandler 处理链接预览请求
type LinkPreviewHandler struct{}

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

	// 补充协议头
	if !strings.HasPrefix(rawURL, "http://") && !strings.HasPrefix(rawURL, "https://") {
		rawURL = "https://" + rawURL
	}

	// 验证URL格式
	if _, err := url.ParseRequestURI(rawURL); err != nil {
		response.Error(c, http.StatusBadRequest, "无效的URL格式")
		return
	}

	client := &http.Client{
		Timeout: 8 * time.Second,
		CheckRedirect: func(req *http.Request, via []*http.Request) error {
			if len(via) >= 5 {
				return http.ErrUseLastResponse
			}
			return nil
		},
	}

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
		preview.Image = resolveURL(pageURL, v)
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
		return resolveURL(pageURL, strings.TrimSpace(m[1]))
	}
	re2 := regexp.MustCompile(`(?i)<link[^>]+href=["']([^"']+)["'][^>]*rel=["'](?:shortcut icon|icon)["']`)
	if m := re2.FindStringSubmatch(html); len(m) > 1 {
		return resolveURL(pageURL, strings.TrimSpace(m[1]))
	}
	// 默认 /favicon.ico
	u, err := url.Parse(pageURL)
	if err != nil {
		return ""
	}
	return u.Scheme + "://" + u.Host + "/favicon.ico"
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
