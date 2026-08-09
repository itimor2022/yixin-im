// 文件用途：验证 user_handler_delete_account_cleanup_test.go 对应模块的正常流程、异常处理和回归行为。
// 核心逻辑：覆盖输入校验、状态变化、错误返回、边界条件和并发幸命。

package handlers

import (
	"os"
	"path/filepath"
	"testing"
)

func TestResolveDeleteAccountUploadLocalPath(t *testing.T) {
	root := t.TempDir()
	tests := []struct {
		name    string
		raw     string
		wantOK  bool
		wantRel string
	}{
		{
			name:    "relative uploads path",
			raw:     "/uploads/images/2026/04/21/a.png",
			wantOK:  true,
			wantRel: filepath.FromSlash("images/2026/04/21/a.png"),
		},
		{
			name:    "absolute media url",
			raw:     "https://cdn.example.com/uploads/videos/2026/04/21/v.mp4?x=1",
			wantOK:  true,
			wantRel: filepath.FromSlash("videos/2026/04/21/v.mp4"),
		},
		{
			name:   "reject traversal",
			raw:    "/uploads/images/../../secret.txt",
			wantOK: false,
		},
		{
			name:   "reject unknown top folder",
			raw:    "/uploads/tmp/a.txt",
			wantOK: false,
		},
		{
			name:    "windows slash path",
			raw:     "\\uploads\\avatars\\u1.png",
			wantOK:  true,
			wantRel: filepath.FromSlash("avatars/u1.png"),
		},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			got, ok := resolveDeleteAccountUploadLocalPath(root, tt.raw)
			if ok != tt.wantOK {
				t.Fatalf("ok mismatch: want=%v got=%v path=%s", tt.wantOK, ok, got)
			}
			if !tt.wantOK {
				return
			}
			wantAbs, err := filepath.Abs(filepath.Join(root, tt.wantRel))
			if err != nil {
				t.Fatalf("build expected abs path failed: %v", err)
			}
			if got != wantAbs {
				t.Fatalf("path mismatch: want=%s got=%s", wantAbs, got)
			}
		})
	}
}

func TestDeleteAccountUploadFiles_DedupeAndDelete(t *testing.T) {
	root := t.TempDir()
	fileRel := filepath.FromSlash("images/2026/04/21/sample.png")
	fileAbs := filepath.Join(root, fileRel)
	if err := os.MkdirAll(filepath.Dir(fileAbs), 0o755); err != nil {
		t.Fatalf("mkdir failed: %v", err)
	}
	if err := os.WriteFile(fileAbs, []byte("x"), 0o644); err != nil {
		t.Fatalf("write file failed: %v", err)
	}
	h := &UserHandler{uploadDir: root}
	deleted, failed := h.deleteAccountUploadFiles([]string{
		"/uploads/images/2026/04/21/sample.png",
		"https://cdn.example.com/uploads/images/2026/04/21/sample.png",
		"/uploads/tmp/not-allowed.txt",
	})
	if deleted != 1 {
		t.Fatalf("deleted count mismatch: want=1 got=%d", deleted)
	}
	if failed != 0 {
		t.Fatalf("failed count mismatch: want=0 got=%d", failed)
	}
	if _, err := os.Stat(fileAbs); !os.IsNotExist(err) {
		t.Fatalf("file should be deleted, stat err=%v", err)
	}
}

func TestCollectDeleteAccountExternalMediaRefs(t *testing.T) {
	root := t.TempDir()
	h := &UserHandler{uploadDir: root}
	got := h.collectDeleteAccountExternalMediaRefs([]string{
		"/uploads/images/2026/04/21/a.png",
		"https://cdn.example.com/uploads/images/2026/04/21/b.png",
		"https://oss.example.com/path/x.png?token=1",
		"https://oss.example.com/path/x.png?token=1#frag",
		"ftp://bad.example.com/a.png",
		"",
	})
	if len(got) != 1 {
		t.Fatalf("expected 1 external ref, got %d(%v)", len(got), got)
	}
	if got[0] != "https://oss.example.com/path/x.png?token=1" {
		t.Fatalf("unexpected external ref: %v", got[0])
	}
}
