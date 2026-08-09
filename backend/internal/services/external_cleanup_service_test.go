// 文件用途：验证 external_cleanup_service_test.go 对应模块的正常流程、异常处理和回归行为。
// 核心逻辑：覆盖输入校验、状态变化、错误返回、边界条件和并发幸命。

package services

import (
	"errors"
	"testing"
	"genericim/internal/config"
)

func TestBuildAllowedHostSet(t *testing.T) {
	set := buildAllowedHostSet([]string{
		"cdn.example.com",
		"https://oss.example.com",
		"api.example.invalid:8443",
		" ",
	})
	if _, ok := set["cdn.example.com"]; !ok {
		t.Fatalf("expected cdn.example.com in allowed set")
	}
	if _, ok := set["oss.example.com"]; !ok {
		t.Fatalf("expected oss.example.com in allowed set")
	}
	if _, ok := set["api.example.invalid"]; !ok {
		t.Fatalf("expected api.example.invalid in allowed set")
	}
}

func TestIsAllowedExternalURL(t *testing.T) {
	s := &ExternalCleanupService{
		allowedHosts: buildAllowedHostSet([]string{"cdn.example.com"}),
	}
	if !s.isAllowedExternalURL("https://cdn.example.com/path/file.png") {
		t.Fatalf("expected allowed URL to pass")
	}
	if s.isAllowedExternalURL("https://evil.example.com/path/file.png") {
		t.Fatalf("expected disallowed host to fail")
	}
	if s.isAllowedExternalURL("ftp://cdn.example.com/path/file.png") {
		t.Fatalf("expected non-http scheme to fail")
	}
}

func TestTryDeleteObjectStorageReturnsNoMatchForOtherHost(t *testing.T) {
	var cfg config.StorageConfig
	cfg.Provider = StorageProviderQiniu
	cfg.Qiniu.PublicBaseURL = "cdn.example.com"
	cfg.Qiniu.UseHTTPS = true

	s := &ExternalCleanupService{}
	err := s.tryDeleteObjectStorage(cfg, "https://other.example.com/uploads/images/a.png")
	if !errors.Is(err, errObjectStorageURLNotMatched) {
		t.Fatalf("error = %v, want %v", err, errObjectStorageURLNotMatched)
	}
}
