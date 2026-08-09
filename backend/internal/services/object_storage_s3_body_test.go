// 文件用途：验证 S3 代理上传在传输重试时可安全回卷请求体。
// 核心逻辑：不可 seek 的流落到临时文件，并可从头重复读取且校验长度。

package services

import (
	"bytes"
	"io"
	"testing"
)

type nonSeekReader struct {
	io.Reader
}

func TestPrepareRetryableS3UploadBodySpoolsNonSeekableReader(t *testing.T) {
	content := []byte("retryable-s3-body")
	body, cleanup, err := prepareRetryableS3UploadBody(
		nonSeekReader{Reader: bytes.NewReader(content)},
		int64(len(content)),
	)
	if err != nil {
		t.Fatal(err)
	}
	defer cleanup()

	for attempt := 0; attempt < 2; attempt++ {
		if _, err := body.Seek(0, io.SeekStart); err != nil {
			t.Fatal(err)
		}
		got, err := io.ReadAll(body)
		if err != nil {
			t.Fatal(err)
		}
		if !bytes.Equal(got, content) {
			t.Fatalf("attempt %d body=%q, want %q", attempt, got, content)
		}
	}
}

func TestPrepareRetryableS3UploadBodyRejectsSizeMismatch(t *testing.T) {
	body, cleanup, err := prepareRetryableS3UploadBody(
		nonSeekReader{Reader: bytes.NewReader([]byte("short"))},
		100,
	)
	cleanup()
	if err == nil {
		t.Fatalf("expected size mismatch, got body=%v", body)
	}
}
