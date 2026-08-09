// 文件用途：验证 upload_handler_test.go 对应模块的正常流程、异常处理和回归行为。
// 核心逻辑：覆盖输入校验、状态变化、错误返回、边界条件和并发幸命。

package handlers

import (
	"archive/zip"
	"bytes"
	"mime/multipart"
	"net/textproto"
	"path/filepath"
	"strings"
	"testing"
)

type memoryMultipartFile struct {
	*bytes.Reader
}

func (f memoryMultipartFile) Close() error {
	return nil
}
func newMemoryMultipartFile(data []byte) multipart.File {
	return memoryMultipartFile{Reader: bytes.NewReader(data)}
}
func uploadTestHeader(filename, contentType string) *multipart.FileHeader {
	header := make(textproto.MIMEHeader)
	header.Set("Content-Type", contentType)
	return &multipart.FileHeader{

		Filename: filename,

		Header: header,

		Size: 32,
	}
}
func TestValidateImageUploadRejectsSpoofedJPEG(t *testing.T) {
	t.Parallel()
	file := newMemoryMultipartFile([]byte("<script>alert(1)</script>"))
	header := uploadTestHeader("avatar.jpg", "image/jpeg")
	if _, _, err := validateImageUpload(file, header); err == nil {

		t.Fatal("expected spoofed jpeg to be rejected")
	}
}
func TestValidateImageUploadNormalizesExtension(t *testing.T) {
	t.Parallel()
	file := newMemoryMultipartFile([]byte("\x89PNG\r\n\x1a\n\x00\x00\x00\rIHDR"))
	header := uploadTestHeader("avatar.jpg", "image/png")
	contentType, ext, err := validateImageUpload(file, header)
	if err != nil {

		t.Fatalf("unexpected error: %v", err)
	}
	if contentType != "image/png" || ext != ".png" {

		t.Fatalf("contentType=%q ext=%q, want image/png .png", contentType, ext)
	}
}
func TestValidateImageUploadAcceptsAVIFBrand(t *testing.T) {
	t.Parallel()
	file := newMemoryMultipartFile([]byte{

		0x00, 0x00, 0x00, 0x18,

		'f', 't', 'y', 'p',

		'a', 'v', 'i', 'f',

		0x00, 0x00, 0x00, 0x00,

		'a', 'v', 'i', 'f',

		'm', 'i', 'f', '1',
	})
	header := uploadTestHeader("photo.avif", "image/avif")
	contentType, ext, err := validateImageUpload(file, header)
	if err != nil {

		t.Fatalf("unexpected error: %v", err)
	}
	if contentType != "image/avif" || ext != ".avif" {

		t.Fatalf("contentType=%q ext=%q, want image/avif .avif", contentType, ext)
	}
}
func TestValidateVideoUploadAcceptsOctetStreamMP4(t *testing.T) {
	t.Parallel()
	file := newMemoryMultipartFile([]byte{

		0x00, 0x00, 0x00, 0x18,

		'f', 't', 'y', 'p',

		'i', 's', 'o', 'm',

		0x00, 0x00, 0x02, 0x00,

		'i', 's', 'o', 'm',

		'i', 's', 'o', '2',

		'a', 'v', 'c', '1',
	})
	header := uploadTestHeader("clip.mp4", "application/octet-stream")
	contentType, ext, err := validateVideoUpload(file, header)
	if err != nil {

		t.Fatalf("unexpected error: %v", err)
	}
	if contentType != "video/mp4" || ext != ".mp4" {

		t.Fatalf("contentType=%q ext=%q, want video/mp4 .mp4", contentType, ext)
	}
}
func TestValidateVideoUploadAcceptsOctetStreamM4V(t *testing.T) {
	t.Parallel()
	file := newMemoryMultipartFile([]byte{

		0x00, 0x00, 0x00, 0x18,

		'f', 't', 'y', 'p',

		'M', '4', 'V', ' ',

		0x00, 0x00, 0x02, 0x00,

		'M', '4', 'V', ' ',

		'i', 's', 'o', 'm',

		'a', 'v', 'c', '1',
	})
	header := uploadTestHeader("clip.m4v", "application/octet-stream")
	contentType, ext, err := validateVideoUpload(file, header)
	if err != nil {

		t.Fatalf("unexpected error: %v", err)
	}
	if contentType != "video/mp4" || ext != ".mp4" {

		t.Fatalf("contentType=%q ext=%q, want video/mp4 .mp4", contentType, ext)
	}
}
func TestValidateVideoUploadRejectsSpoofedOctetStreamMP4(t *testing.T) {
	t.Parallel()
	file := newMemoryMultipartFile([]byte("<script>alert(1)</script>"))
	header := uploadTestHeader("clip.mp4", "application/octet-stream")
	if _, _, err := validateVideoUpload(file, header); err == nil {

		t.Fatal("expected spoofed mp4 to be rejected")
	}
}
func TestSafeGenericFileExtDowngradesActiveContent(t *testing.T) {
	t.Parallel()
	for _, name := range []string{"page.html", "image.svg", "script.js", "style.css"} {

		name := name

		t.Run(name, func(t *testing.T) {

			t.Parallel()

			if got := safeGenericFileExt(name); got != ".bin" {

				t.Fatalf("safeGenericFileExt(%q)=%q, want .bin", name, got)

			}

		})
	}
}
func TestValidateGenericFileUploadAcceptsPDF(t *testing.T) {
	data := []byte("%PDF-1.7\n1 0 obj\n<<>>\nendobj\n")
	file := newMemoryMultipartFile(data)
	header := uploadTestHeader("report.pdf", "application/pdf")
	header.Size = int64(len(data))
	contentType, ext, err := validateGenericFileUpload(file, header)
	if err != nil {

		t.Fatalf("unexpected error: %v", err)
	}
	if contentType != "application/pdf" || ext != ".pdf" {

		t.Fatalf("contentType=%q ext=%q", contentType, ext)
	}
}
func TestValidateGenericFileUploadRejectsSpoofedAndDangerousNames(t *testing.T) {
	for _, name := range []string{"report.pdf.exe", "payload.exe.pdf"} {

		file := newMemoryMultipartFile([]byte("%PDF-1.7\n"))
		header := uploadTestHeader(name, "application/pdf")

		header.Size = 9

		if _, _, err := validateGenericFileUpload(file, header); err == nil {

			t.Fatalf("expected %q to be rejected", name)

		}
	}
	file := newMemoryMultipartFile([]byte("<script>alert(1)</script>"))
	header := uploadTestHeader("report.pdf", "application/pdf")
	header.Size = 25
	if _, _, err := validateGenericFileUpload(file, header); err == nil {

		t.Fatal("expected spoofed pdf to be rejected")
	}
}
func TestValidateGenericFileUploadAcceptsDOCXStructure(t *testing.T) {
	var buffer bytes.Buffer
	writer := zip.NewWriter(&buffer)
	for _, name := range []string{"[Content_Types].xml", "word/document.xml"} {

		entry, err := writer.Create(name)

		if err != nil {

			t.Fatal(err)

		}

		if _, err := entry.Write([]byte("<xml/>")); err != nil {

			t.Fatal(err)

		}
	}
	if err := writer.Close(); err != nil {

		t.Fatal(err)
	}
	data := buffer.Bytes()
	file := newMemoryMultipartFile(data)
	header := uploadTestHeader(

		"document.docx",

		"application/vnd.openxmlformats-officedocument.wordprocessingml.document",
	)
	header.Size = int64(len(data))
	contentType, ext, err := validateGenericFileUpload(file, header)
	if err != nil {

		t.Fatalf("unexpected error: %v", err)
	}
	if contentType != "application/vnd.openxmlformats-officedocument.wordprocessingml.document" || ext != ".docx" {

		t.Fatalf("contentType=%q ext=%q", contentType, ext)
	}
}
func TestSafeLocalUploadPathStaysUnderBaseDir(t *testing.T) {
	t.Parallel()
	base := t.TempDir()
	got, err := safeLocalUploadPath(base, "images/2026/06/avatar.png")
	if err != nil {

		t.Fatalf("unexpected error: %v", err)
	}
	rel, err := filepath.Rel(base, got)
	if err != nil {

		t.Fatalf("rel: %v", err)
	}
	if strings.HasPrefix(rel, "..") || filepath.IsAbs(rel) {

		t.Fatalf("path escaped base dir: %s", got)
	}
}
func TestSafeLocalUploadPathRejectsTraversal(t *testing.T) {
	t.Parallel()
	base := t.TempDir()
	for _, rel := range []string{"../evil.png", "..\\evil.png", "uploads/../../evil.png"} {

		rel := rel

		t.Run(rel, func(t *testing.T) {

			t.Parallel()

			if _, err := safeLocalUploadPath(base, rel); err == nil {

				t.Fatalf("expected traversal path %q to be rejected", rel)

			}

		})
	}
}
