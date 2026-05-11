package services

import "testing"

func TestBuildAllowedHostSet(t *testing.T) {
	set := buildAllowedHostSet([]string{
		"cdn.example.com",
		"https://oss.example.com",
		"api.example.com:8443",
		" ",
	})

	if _, ok := set["cdn.example.com"]; !ok {
		t.Fatalf("expected cdn.example.com in allowed set")
	}
	if _, ok := set["oss.example.com"]; !ok {
		t.Fatalf("expected oss.example.com in allowed set")
	}
	if _, ok := set["api.example.com"]; !ok {
		t.Fatalf("expected api.example.com in allowed set")
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
