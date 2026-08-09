// 文件用途：验证 link_preview_handler_test.go 对应模块的正常流程、异常处理和回归行为。
// 核心逻辑：覆盖输入校验、状态变化、错误返回、边界条件和并发幸命。

package handlers

import (
	"errors"
	"net"
	"net/http"
	"net/url"
	"testing"
)

func TestNormalizeLinkPreviewURL(t *testing.T) {
	t.Parallel()
	tests := []struct {
		name      string
		raw       string
		want      string
		wantError bool
		wantSafe  bool
	}{
		{name: "adds https scheme", raw: "example.com/path?q=1", want: "https://example.com/path?q=1"},
		{name: "keeps https url", raw: "https://example.com/a", want: "https://example.com/a"},
		{name: "rejects unsupported scheme", raw: "file:///etc/passwd", wantError: true},
		{name: "rejects credentials", raw: "https://user:pass@example.com", wantError: true},
		{name: "rejects localhost", raw: "http://localhost:8080", wantError: true, wantSafe: true},
		{name: "rejects loopback ip", raw: "http://127.0.0.1/admin", wantError: true, wantSafe: true},
		{name: "rejects private ip", raw: "http://10.1.2.3", wantError: true, wantSafe: true},
		{name: "rejects link local metadata ip", raw: "http://169.254.169.254/latest/meta-data", wantError: true, wantSafe: true},
		{name: "rejects ipv6 loopback", raw: "http://[::1]/", wantError: true, wantSafe: true},
	}
	for _, tc := range tests {
		tc := tc
		t.Run(tc.name, func(t *testing.T) {
			t.Parallel()
			got, err := normalizeLinkPreviewURL(tc.raw)
			if tc.wantError {
				if err == nil {
					t.Fatalf("expected error, got nil")
				}
				if tc.wantSafe && !errors.Is(err, errUnsafeLinkPreviewURL) {
					t.Fatalf("expected unsafe url error, got %v", err)
				}
				return
			}
			if err != nil {
				t.Fatalf("unexpected error: %v", err)
			}
			if got.String() != tc.want {
				t.Fatalf("url=%q, want %q", got.String(), tc.want)
			}
		})
	}
}

func TestLinkPreviewPublicRoutableIPGuard(t *testing.T) {
	t.Parallel()
	tests := []struct {
		ip   string
		want bool
	}{
		{ip: "93.184.216.34", want: true},
		{ip: "127.0.0.1", want: false},
		{ip: "10.0.0.1", want: false},
		{ip: "100.64.1.1", want: false},
		{ip: "172.16.0.1", want: false},
		{ip: "192.168.1.1", want: false},
		{ip: "169.254.169.254", want: false},
		{ip: "198.18.0.1", want: false},
		{ip: "203.0.113.10", want: false},
		{ip: "::1", want: false},
		{ip: "fc00::1", want: false},
		{ip: "fe80::1", want: false},
		{ip: "2001:db8::1", want: false},
	}
	for _, tc := range tests {
		tc := tc
		t.Run(tc.ip, func(t *testing.T) {
			t.Parallel()
			got := isPublicRoutableLinkPreviewIP(net.ParseIP(tc.ip))
			if got != tc.want {
				t.Fatalf("isPublicRoutableLinkPreviewIP(%s)=%v, want %v", tc.ip, got, tc.want)
			}
		})
	}
}

func TestCheckLinkPreviewRedirectBlocksUnsafeTarget(t *testing.T) {
	t.Parallel()

	target, err := url.Parse("http://127.0.0.1:8080/admin")
	if err != nil {
		t.Fatal(err)
	}
	err = checkLinkPreviewRedirect(&http.Request{URL: target}, nil)
	if !errors.Is(err, errUnsafeLinkPreviewURL) {
		t.Fatalf("expected unsafe redirect error, got %v", err)
	}
}

func TestCheckLinkPreviewRedirectStopsAfterFiveHops(t *testing.T) {
	t.Parallel()

	target, err := url.Parse("https://example.com/next")
	if err != nil {
		t.Fatal(err)
	}
	via := make([]*http.Request, 5)
	err = checkLinkPreviewRedirect(&http.Request{URL: target}, via)
	if !errors.Is(err, http.ErrUseLastResponse) {
		t.Fatalf("expected ErrUseLastResponse, got %v", err)
	}
}

func TestSafeLinkPreviewAssetURL(t *testing.T) {
	t.Parallel()
	tests := []struct {
		name string
		base string
		rel  string
		want string
	}{
		{
			name: "keeps public absolute url",
			base: "https://example.com/page",
			rel:  "https://cdn.example.com/og.png",
			want: "https://cdn.example.com/og.png",
		},
		{
			name: "resolves relative url",
			base: "https://example.com/posts/1",
			rel:  "/img/og.png",
			want: "https://example.com/img/og.png",
		},
		{
			name: "resolves scheme relative url",
			base: "https://example.com/posts/1",
			rel:  "//cdn.example.com/icon.ico",
			want: "https://cdn.example.com/icon.ico",
		},
		{
			name: "drops data url",
			base: "https://example.com/page",
			rel:  "data:image/svg+xml,<svg></svg>",
			want: "",
		},
		{
			name: "drops localhost url",
			base: "https://example.com/page",
			rel:  "http://localhost:8080/og.png",
			want: "",
		},
		{
			name: "drops private ip url",
			base: "https://example.com/page",
			rel:  "http://192.168.1.10/og.png",
			want: "",
		},
	}
	for _, tc := range tests {
		tc := tc
		t.Run(tc.name, func(t *testing.T) {
			t.Parallel()
			if got := safeLinkPreviewAssetURL(tc.base, tc.rel); got != tc.want {
				t.Fatalf("safeLinkPreviewAssetURL()=%q, want %q", got, tc.want)
			}
		})
	}
}
