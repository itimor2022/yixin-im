// 文件用途：验证 message_handler_unit_test.go 对应模块的正常流程、异常处理和回归行为。
// 核心逻辑：覆盖输入校验、状态变化、错误返回、边界条件和并发幸命。

package handlers

import (
	"context"
	"encoding/json"
	"strings"
	"testing"
	"time"
	"genericim/internal/config"
	"genericim/internal/models"
)

func TestShouldFanOutRealtimeReceipts(t *testing.T) {
	tests := []struct {
		name     string
		chatType int8
		want     bool
	}{
		{name: "private", chatType: 1, want: true},
		{name: "group", chatType: 2, want: false},
		{name: "channel", chatType: 3, want: false},
		{name: "unknown", chatType: 0, want: false},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			if got := shouldFanOutRealtimeReceipts(tt.chatType); got != tt.want {
				t.Fatalf("shouldFanOutRealtimeReceipts(%d)=%v, want %v", tt.chatType, got, tt.want)
			}
		})
	}
}

func TestForwardMessageRequestAcceptsClientMessageID(t *testing.T) {
	var request ForwardMessageRequest
	err := json.Unmarshal([]byte(`{ 		"source_chat_id":"source-1", "source_msg_id":"message-1", "target_chat_id":"target-1", "client_msg_id":"forward-attempt-1" 	}`), &request)
	if err != nil {
		t.Fatalf("unmarshal forward request: %v", err)
	}
	if request.ClientMsgID != "forward-attempt-1" {
		t.Fatalf("client_msg_id=%q", request.ClientMsgID)
	}
}

func TestValidateMessageMentionsRejectsForgedAndOversizedTargets(t *testing.T) {
	allowed := []string{"member-a", "member-b", "member-c"}

	validated, ok := validateMessageMentions(
		[]string{"member-a", "member-a", "member-b"},
		2,
		allowed...,
	)
	if !ok || len(validated) != 2 || validated[0] != "member-a" || validated[1] != "member-b" {
		t.Fatalf("validated=%v ok=%v, want deduplicated members", validated, ok)
	}
	for name, raw := range map[string][]string{
		"non_member": {"member-a", "outsider"},
		"over_limit": {"member-a", "member-b", "member-c"},
		"sentinel":   {mentionAllSentinel},
		"empty":      {" "},
	} {
		t.Run(name, func(t *testing.T) {
			if got, valid := validateMessageMentions(raw, 2, allowed...); valid {
				t.Fatalf("validateMessageMentions(%v)=(%v,true), want rejection", raw, got)
			}
		})
	}
}

func TestCanUseMentionAllRequiresGroupAdministrator(t *testing.T) {
	for _, tc := range []struct {
		name     string
		chatType int8
		role     int8
		want     bool
	}{
		{name: "private owner-shaped role", chatType: 1, role: 2, want: false},
		{name: "group member", chatType: 2, role: 0, want: false},
		{name: "group admin", chatType: 2, role: 1, want: true},
		{name: "group owner", chatType: 2, role: 2, want: true},
		{name: "channel admin", chatType: 3, role: 1, want: true},
	} {
		t.Run(tc.name, func(t *testing.T) {
			if got := canUseMentionAll(tc.chatType, tc.role); got != tc.want {
				t.Fatalf("canUseMentionAll(%d,%d)=%v, want %v", tc.chatType, tc.role, got, tc.want)
			}
		})
	}
}

func TestValidateTextMessageLengthUsesUnicodeCharacters(t *testing.T) {
	if !validateTextMessageLength(models.MsgTypeText, map[string]interface{}{
		"text": strings.Repeat("界", maxTextMessageRunes),
	}) {
		t.Fatal("5000 Unicode characters should be accepted")
	}
	if validateTextMessageLength(models.MsgTypeText, map[string]interface{}{
		"text": strings.Repeat("界", maxTextMessageRunes+1),
	}) {
		t.Fatal("5001 Unicode characters should be rejected")
	}
	if !validateTextMessageLength(models.MsgTypeImage, map[string]interface{}{
		"text": strings.Repeat("界", maxTextMessageRunes+1),
	}) {
		t.Fatal("non-text message captions are outside the text-message limit")
	}
}

func TestMessageSearchFilterValidation(t *testing.T) {
	for _, messageType := range []int{
		models.MsgTypeText,
		models.MsgTypeImage,
		models.MsgTypeFile,
		models.MsgTypeSystem,
	} {
		if !supportedSearchMessageType(messageType) {
			t.Fatalf("message type %d should be searchable", messageType)
		}
	}
	for _, messageType := range []int{0, 7, 9, 15, 100} {
		if supportedSearchMessageType(messageType) {
			t.Fatalf("message type %d should be rejected", messageType)
		}
	}

	parsed, err := parseMessageSearchTime("2026-07-18T08:00:00+08:00")
	if err != nil || parsed == nil || parsed.Location() != time.UTC || parsed.Hour() != 0 {
		t.Fatalf("parsed time=%v err=%v", parsed, err)
	}
	if _, err := parseMessageSearchTime("2026-07-18"); err == nil {
		t.Fatal("date-only search boundary should be rejected")
	}
}

func TestResolveVoiceTranscribeURL(t *testing.T) {
	oldConfig := config.GlobalConfig
	t.Cleanup(func() {
		config.GlobalConfig = oldConfig
	})
	config.GlobalConfig = &config.Config{
		Server: config.ServerConfig{BaseURL: "https://api.example.com/base"},
	}
	got, err := resolveVoiceTranscribeURL("/uploads/voices/a.m4a")
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	want := "https://api.example.com/base/uploads/voices/a.m4a"
	if got != want {
		t.Fatalf("url=%q, want %q", got, want)
	}
	got, err = resolveVoiceTranscribeURL("https://cdn.example.com/voice.m4a")
	if err != nil {
		t.Fatalf("unexpected absolute url error: %v", err)
	}
	if got != "https://cdn.example.com/voice.m4a" {
		t.Fatalf("absolute url=%q", got)
	}
}

func TestResolveVoiceTranscribeURLRequiresBaseForRelative(t *testing.T) {
	oldConfig := config.GlobalConfig
	t.Cleanup(func() {
		config.GlobalConfig = oldConfig
	})
	config.GlobalConfig = nil

	if _, err := resolveVoiceTranscribeURL("/uploads/voices/a.m4a"); err == nil {
		t.Fatal("expected error for relative voice url without base url")
	}
}

func TestDownloadVoiceForTranscriptionBlocksUnsafeURL(t *testing.T) {
	t.Parallel()

	_, _, err := downloadVoiceForTranscription(context.Background(), "http://127.0.0.1/voice.m4a")
	if err == nil {
		t.Fatal("expected unsafe url error")
	}
	if !strings.Contains(err.Error(), "不安全") {
		t.Fatalf("error=%q, want unsafe url message", err.Error())
	}
}

func TestMessageAckPayloadAddsReliableSendMetadata(t *testing.T) {
	msg := &models.Message{
		MsgID:     "server-msg-1",
		ChatID:    "chat-1",
		Seq:       42,
		SenderID:  "user-1",
		Type:      models.MsgTypeText,
		Status:    models.MsgStatusSent,
		CreatedAt: time.Date(2026, 6, 21, 10, 0, 0, 0, time.UTC),
		UpdatedAt: time.Date(2026, 6, 21, 10, 0, 0, 0, time.UTC),
	}
	payload := messageAckPayload(msg, false, "client-msg-1")
	if payload["msg_id"] != "server-msg-1" {
		t.Fatalf("msg_id=%v", payload["msg_id"])
	}
	if payload["client_msg_id"] != "client-msg-1" {
		t.Fatalf("client_msg_id=%v", payload["client_msg_id"])
	}
	if payload["server_msg_id"] != "server-msg-1" {
		t.Fatalf("server_msg_id=%v", payload["server_msg_id"])
	}
	if payload["server_seq"] != float64(42) && payload["server_seq"] != uint64(42) {
		t.Fatalf("server_seq=%v", payload["server_seq"])
	}
	if payload["duplicate"] != false {
		t.Fatalf("duplicate=%v", payload["duplicate"])
	}
	if payload["ack_status"] != "sent" {
		t.Fatalf("ack_status=%v", payload["ack_status"])
	}
}

func TestMessageAckPayloadMarksDuplicate(t *testing.T) {
	msg := &models.Message{
		MsgID:  "client-msg-1",
		ChatID: "chat-1",
		Seq:    7,
		Status: models.MsgStatusSent,
	}
	payload := messageAckPayload(msg, true, "client-msg-1")
	if payload["duplicate"] != true {
		t.Fatalf("duplicate=%v", payload["duplicate"])
	}
	if payload["ack_status"] != "duplicate" {
		t.Fatalf("ack_status=%v", payload["ack_status"])
	}
}

func TestCurrentMessageSenderDisplayUsesLatestProfile(t *testing.T) {
	msg := &models.Message{
		SenderID:            "user-1",
		SenderName:          "旧昵称",
		SenderAvatar:        "/uploads/avatars/old.png",
		SenderNicknameColor: "#111111",
		SenderEmojiAvatar:   "old-emoji",
	}
	currentUser := models.User{
		UUID:          "user-1",
		Nickname:      "新昵称",
		Avatar:        "/uploads/avatars/new.png",
		NicknameColor: "#222222",
		EmojiAvatar:   "new-emoji",
	}
	display := currentMessageSenderDisplay(msg, currentUser, true)
	if display.name != currentUser.Nickname {
		t.Fatalf("name=%q, want %q", display.name, currentUser.Nickname)
	}
	if display.avatar != currentUser.Avatar {
		t.Fatalf("avatar=%q, want %q", display.avatar, currentUser.Avatar)
	}
	if display.nicknameColor != currentUser.NicknameColor {
		t.Fatalf("nicknameColor=%q, want %q", display.nicknameColor, currentUser.NicknameColor)
	}
	if display.emojiAvatar != currentUser.EmojiAvatar {
		t.Fatalf("emojiAvatar=%q, want %q", display.emojiAvatar, currentUser.EmojiAvatar)
	}
}

func TestCurrentMessageSenderDisplayKeepsAnonymousProfileHidden(t *testing.T) {
	msg := &models.Message{
		SenderID:       "user-1",
		SenderName:     "匿名用户",
		SenderAvatar:   "/uploads/avatars/old.png",
		SenderDeviceID: "device-1",
		IsAnonymous:    true,
	}
	currentUser := models.User{
		UUID:     "user-1",
		Nickname: "真实昵称",
		Avatar:   "/uploads/avatars/new.png",
	}
	display := currentMessageSenderDisplay(msg, currentUser, true)
	if display.id != "anonymous" || display.avatar != "" || display.deviceID != "" {
		t.Fatalf("anonymous sender leaked profile: %+v", display)
	}
	if display.name != "匿名用户" {
		t.Fatalf("anonymous name=%q", display.name)
	}
}
