// 文件用途：验证 media_processor_test.go 对应模块的正常流程、异常处理和回归行为。
// 核心逻辑：覆盖输入校验、状态变化、错误返回、边界条件和并发幸命。

package services

import (
	"errors"
	"testing"
)

func TestMediaProbeKeepsH264AACMP4(t *testing.T) {
	probe := &mediaProbe{}
	probe.Format.Duration = "5.005"
	probe.Streams = append(

		probe.Streams,

		struct {
			CodecName string `json:"codec_name"`

			CodecType string `json:"codec_type"`

			Width int `json:"width"`

			Height int `json:"height"`

			Duration string `json:"duration"`
		}{CodecName: "h264", CodecType: "video", Width: 1920, Height: 1080},

		struct {
			CodecName string `json:"codec_name"`

			CodecType string `json:"codec_type"`

			Width int `json:"width"`

			Height int `json:"height"`

			Duration string `json:"duration"`
		}{CodecName: "aac", CodecType: "audio"},
	)
	if probe.needsVideoTranscode(".mp4") {

		t.Fatal("H.264/AAC MP4 should not be transcoded")
	}
	width, height, duration := probe.dimensionsAndDuration()
	if width != 1920 || height != 1080 || duration != 5005 {

		t.Fatalf("metadata=%dx%d/%d", width, height, duration)
	}
}
func TestMediaProbeTranscodesIncompatibleInputs(t *testing.T) {
	probe := &mediaProbe{}
	probe.Streams = append(

		probe.Streams,

		struct {
			CodecName string `json:"codec_name"`

			CodecType string `json:"codec_type"`

			Width int `json:"width"`

			Height int `json:"height"`

			Duration string `json:"duration"`
		}{CodecName: "vp9", CodecType: "video"},
	)
	if !probe.needsVideoTranscode(".webm") {

		t.Fatal("WebM must be normalized to MP4")
	}
	if !probe.needsVideoTranscode(".mp4") {

		t.Fatal("VP9 MP4 must be normalized to H.264")
	}
}
func TestDecodeMediaProbeIgnoresSuccessfulStderrWarnings(t *testing.T) {
	probe, err := decodeMediaProbe(

		[]byte(`{"streams":[{"codec_name":"h264","codec_type":"video","width":640,"height":360}],"format":{"duration":"4.008"}}`),

		[]byte("[tls] transient warning emitted on stderr"),

		nil,
	)
	if err != nil {

		t.Fatalf("decodeMediaProbe: %v", err)
	}
	width, height, duration := probe.dimensionsAndDuration()
	if width != 640 || height != 360 || duration != 4008 {

		t.Fatalf("metadata=%dx%d/%d", width, height, duration)
	}
}
func TestDecodeMediaProbeIncludesCommandStderrOnFailure(t *testing.T) {
	_, err := decodeMediaProbe(nil, []byte("remote input failed"), errors.New("exit status 1"))
	if err == nil || err.Error() != "probe uploaded media: exit status 1: remote input failed" {

		t.Fatalf("error=%v", err)
	}
}
func TestIsHTTPMediaInput(t *testing.T) {
	for _, input := range []string{"https://s3.example/media.mp4", " HTTP://localhost/image.jpg "} {

		if !isHTTPMediaInput(input) {

			t.Fatalf("expected HTTP input: %q", input)

		}
	}
	if isHTTPMediaInput(`C:\temp\media.mp4`) {

		t.Fatal("local file must not be treated as HTTP input")
	}
}
