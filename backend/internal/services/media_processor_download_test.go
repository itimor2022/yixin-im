// 文件用途：验证 media_processor_download_test.go 对应模块的正常流程、异常处理和回归行为。
// 核心逻辑：覆盖输入校验、状态变化、错误返回、边界条件和并发幸命。

package services

import (
	"context"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"strconv"
	"sync/atomic"
	"testing"
)

func TestDownloadTemporaryMedia(t *testing.T) {
	const content = "private-media-object"
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {

		_, _ = w.Write([]byte(content))
	}))
	defer server.Close()
	filePath, cleanup, err := downloadTemporaryMedia(

		context.Background(),

		server.URL,

		"media-processor-test-*",

		int64(len(content)),
	)
	if err != nil {

		t.Fatalf("downloadTemporaryMedia: %v", err)
	}
	defer cleanup()
	got, err := os.ReadFile(filePath)
	if err != nil {

		t.Fatalf("read temporary media: %v", err)
	}
	if string(got) != content {

		t.Fatalf("temporary media = %q, want %q", got, content)
	}
}
func TestDownloadTemporaryMediaRejectsSizeMismatch(t *testing.T) {
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {

		_, _ = w.Write([]byte("too-long"))
	}))
	defer server.Close()
	if _, _, err := downloadTemporaryMedia(

		context.Background(),

		server.URL,

		"media-processor-test-*",

		3,
	); err == nil {

		t.Fatal("expected size mismatch error")
	}
}
func TestDownloadTemporaryMediaRetriesTruncatedResponses(t *testing.T) {
	const content = "complete-private-media"
	var attempts atomic.Int32
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {

		current := attempts.Add(1)

		w.Header().Set("Content-Length", strconv.Itoa(len(content)))

		if current < 3 {

			_, _ = w.Write([]byte(content[:5]))

			return

		}

		_, _ = w.Write([]byte(content))
	}))
	defer server.Close()
	filePath, cleanup, err := downloadTemporaryMedia(

		context.Background(),

		server.URL,

		"media-processor-retry-*",

		int64(len(content)),
	)
	if err != nil {

		t.Fatalf("downloadTemporaryMedia: %v", err)
	}
	defer cleanup()
	got, err := os.ReadFile(filePath)
	if err != nil {

		t.Fatal(err)
	}
	if string(got) != content || attempts.Load() != 3 {

		t.Fatalf("content=%q attempts=%d", got, attempts.Load())
	}
}
func TestResolveHEIFOutputSelectsFirstImageAndCleansAll(t *testing.T) {
	tempDir := t.TempDir()
	requested := filepath.Join(tempDir, "preview.jpg")
	if err := os.WriteFile(requested, nil, 0o600); err != nil {

		t.Fatal(err)
	}
	first := filepath.Join(tempDir, "preview-1.jpg")
	second := filepath.Join(tempDir, "preview-2.jpg")
	if err := os.WriteFile(first, []byte("first"), 0o600); err != nil {

		t.Fatal(err)
	}
	if err := os.WriteFile(second, []byte("second"), 0o600); err != nil {

		t.Fatal(err)
	}
	got, err := resolveHEIFOutput(requested)
	if err != nil {

		t.Fatalf("resolveHEIFOutput: %v", err)
	}
	if got != first {

		t.Fatalf("resolved output = %q, want %q", got, first)
	}
	cleanupHEIFOutputs(requested)
	for _, candidate := range []string{first, second} {

		if _, err := os.Stat(candidate); !os.IsNotExist(err) {

			t.Fatalf("expected %q to be removed", candidate)

		}
	}
}
