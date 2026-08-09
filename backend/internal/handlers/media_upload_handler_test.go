// 文件用途：验证 media_upload_handler_test.go 对应模块的正常流程、异常处理和回归行为。
// 核心逻辑：覆盖输入校验、状态变化、错误返回、边界条件和并发幸命。

package handlers

import (
	"encoding/base64"
	"strings"
	"testing"
	"genericim/internal/models"
	"genericim/internal/services"
)

func TestNormalizeMediaAccessIDs(t *testing.T) {
	got := normalizeMediaAccessIDs([]string{" a ", "", "b", "a", "  b  ", "c"})
	want := []string{"a", "b", "c"}
	if len(got) != len(want) {
		t.Fatalf("ids=%v want=%v", got, want)
	}
	for index := range want {
		if got[index] != want[index] {
			t.Fatalf("ids=%v want=%v", got, want)
		}
	}
}

func TestNormalizeDirectUploadMetadata(t *testing.T) {
	tests := []struct {
		name string

		category string

		fileName string

		mimeType string

		wantMIME string

		wantError bool
	}{

		{name: "mp4", category: "video", fileName: "clip.mp4", mimeType: "video/mp4", wantMIME: "video/mp4"},

		{name: "docx legacy mime", category: "file", fileName: "report.docx", mimeType: "application/msword", wantMIME: "application/vnd.openxmlformats-officedocument.wordprocessingml.document"},

		{name: "safe pdf", category: "file", fileName: "report.pdf", mimeType: "application/pdf", wantMIME: "application/pdf"},

		{name: "dangerous double suffix", category: "file", fileName: "invoice.exe.pdf", mimeType: "application/pdf", wantError: true},

		{name: "executable", category: "file", fileName: "tool.exe", mimeType: "application/octet-stream", wantError: true},

		{name: "mismatched video", category: "video", fileName: "clip.mp4", mimeType: "video/webm", wantError: true},
	}
	for _, tt := range tests {

		t.Run(tt.name, func(t *testing.T) {

			_, mimeType, _, err := normalizeDirectUploadMetadata(tt.category, tt.fileName, tt.mimeType)

			if tt.wantError {

				if err == nil {

					t.Fatal("expected validation error")

				}

				return

			}

			if err != nil {

				t.Fatalf("unexpected error: %v", err)

			}

			if mimeType != tt.wantMIME {

				t.Fatalf("mime=%q want=%q", mimeType, tt.wantMIME)

			}

		})
	}
}
func TestValidateCompletedParts(t *testing.T) {
	item := &models.MediaObject{

		SizeBytes: 34,

		PartSizeBytes: 16,
	}
	parts := []services.S3UploadedPart{

		{PartNumber: 1, ETag: `"a"`, Size: 16},

		{PartNumber: 2, ETag: `"b"`, Size: 16},

		{PartNumber: 3, ETag: `"c"`, Size: 2},
	}
	if err := validateCompletedParts(item, parts); err != nil {

		t.Fatalf("valid parts rejected: %v", err)
	}
	parts[1].PartNumber = 3
	if err := validateCompletedParts(item, parts); err == nil {

		t.Fatal("expected non-consecutive parts to fail")
	}
}
func TestDirectUploadPartCountAtP1Boundary(t *testing.T) {
	if got := directUploadPartCount(directUploadSingleLimit, directUploadPartSize); got != 7 {

		t.Fatalf("part count=%d want=7", got)
	}
	if got := directUploadPartCount(directUploadSingleLimit+directUploadPartSize, directUploadPartSize); got != 8 {

		t.Fatalf("part count=%d want=8", got)
	}
}
func TestValidateDirectObjectSHA256(t *testing.T) {
	raw := make([]byte, 32)
	for i := range raw {

		raw[i] = byte(i)
	}
	expected := checksumBase64ToHex(base64.StdEncoding.EncodeToString(raw))
	item := &models.MediaObject{

		SizeBytes: 100,

		DeclaredMIME: "video/mp4",

		ExpectedSHA256: expected,
	}
	info := services.S3ObjectInfo{

		Size: 100,

		ContentType: "video/mp4",

		ChecksumSHA256: base64.StdEncoding.EncodeToString(raw),
	}
	if err := validateDirectObject(item, info); err != nil {

		t.Fatalf("valid object rejected: %v", err)
	}
	info.ChecksumSHA256 = ""
	if err := validateDirectObject(item, info); err != nil {

		t.Fatalf("query-signed checksum with empty HEAD checksum rejected: %v", err)
	}
	if got := directObjectChecksum(item, info); got != expected {

		t.Fatalf("checksum=%q want query-signed expected=%q", got, expected)
	}
	info.ChecksumSHA256 = base64.StdEncoding.EncodeToString(append([]byte{0xff}, raw[1:]...))
	if err := validateDirectObject(item, info); err == nil || !strings.Contains(err.Error(), "SHA-256") {

		t.Fatalf("expected checksum mismatch error, got %v", err)
	}
}
func TestValidateDirectObjectSignature(t *testing.T) {
	tests := []struct {
		name string

		item models.MediaObject

		prefix []byte

		wantFail bool
	}{

		{

			name: "mp4",

			item: models.MediaObject{Category: "video", NormalizedExt: ".mp4"},

			prefix: []byte{0, 0, 0, 24, 'f', 't', 'y', 'p', 'i', 's', 'o', 'm'},
		},

		{

			name: "pdf",

			item: models.MediaObject{Category: "file", NormalizedExt: ".pdf"},

			prefix: []byte("%PDF-1.7"),
		},

		{

			name: "fake pdf",

			item: models.MediaObject{Category: "file", NormalizedExt: ".pdf"},

			prefix: []byte("MZ executable"),

			wantFail: true,
		},
	}
	for _, tt := range tests {

		t.Run(tt.name, func(t *testing.T) {

			err := validateDirectObjectSignature(&tt.item, tt.prefix)

			if tt.wantFail && err == nil {

				t.Fatal("expected signature validation failure")

			}

			if !tt.wantFail && err != nil {

				t.Fatalf("unexpected signature validation error: %v", err)

			}

		})
	}
}
func TestValidateDirectImageResourcesRejectsPixelBomb(t *testing.T) {
	pngHeader := make([]byte, 24)
	copy(pngHeader, []byte("\x89PNG\r\n\x1a\n"))
	copy(pngHeader[12:16], []byte("IHDR"))
	pngHeader[16] = 0x00
	pngHeader[17] = 0x00
	pngHeader[18] = 0x75
	pngHeader[19] = 0x30 // 30000
	pngHeader[20] = 0x00
	pngHeader[21] = 0x00
	pngHeader[22] = 0x75
	pngHeader[23] = 0x30 // 30000
	item := &models.MediaObject{Category: "image", NormalizedExt: ".png"}
	if err := validateDirectImageResources(item, pngHeader); err == nil {

		t.Fatal("expected oversized pixel dimensions to be rejected")
	}
}
func TestValidateDirectImageResourcesAcceptsSmallPNG(t *testing.T) {
	pngHeader := make([]byte, 24)
	copy(pngHeader, []byte("\x89PNG\r\n\x1a\n"))
	copy(pngHeader[12:16], []byte("IHDR"))
	pngHeader[18] = 0x04
	pngHeader[19] = 0x00 // 1024
	pngHeader[22] = 0x03
	pngHeader[23] = 0x00 // 768
	item := &models.MediaObject{Category: "image", NormalizedExt: ".png"}
	if err := validateDirectImageResources(item, pngHeader); err != nil {

		t.Fatalf("valid PNG rejected: %v", err)
	}
}
