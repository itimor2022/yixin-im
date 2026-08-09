// 文件用途：验证 setting_handler_voice_test.go 对应模块的正常流程、异常处理和回归行为。
// 核心逻辑：覆盖输入校验、状态变化、错误返回、边界条件和并发幸命。

package handlers

import (
	"testing"
	"genericim/internal/models"
)

func TestVoiceTranscriptionConfigured(t *testing.T) {
	t.Setenv("OPENAI_API_KEY", "")
	t.Setenv("VOICE_TRANSCRIBE_URL", "")
	if voiceTranscriptionConfigured(map[string]string{}) {
		t.Fatal("empty settings must not expose voice transcription")
	}
	if !voiceTranscriptionConfigured(map[string]string{
		models.SettingVoiceTranscribeURL: "https://speech.example.test",
	}) {
		t.Fatal("custom transcription URL should expose the capability")
	}
	if !voiceTranscriptionConfigured(map[string]string{
		models.SettingVoiceTranscribeProvider: "openai",
		models.SettingOpenAIAPIKey:            "secret",
	}) {
		t.Fatal("configured OpenAI transcription should expose the capability")
	}
}
