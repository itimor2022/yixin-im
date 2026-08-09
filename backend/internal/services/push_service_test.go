// 文件用途：验证 push_service_test.go 对应模块的正常流程、异常处理和回归行为。
// 核心逻辑：覆盖输入校验、状态变化、错误返回、边界条件和并发幸命。

package services

import (
	"encoding/json"
	"fmt"
	"net/url"
	"strconv"
	"strings"
	"testing"
	"time"
	"genericim/internal/models"
)

func TestBuildIncomingCallPushPayloadNormalizesContract(t *testing.T) {
	t.Parallel()
	now := time.Date(2026, 7, 23, 12, 0, 0, 0, time.UTC)

	payload, err := buildIncomingCallPushPayload("", " 123 ", true, map[string]interface{}{
		"caller_id":    "caller-1",
		"room_name":    "room-123",
		"rtc_provider": "livekit",
		"expires_at":   now.Add(30 * time.Second),
	}, now)
	if err != nil {
		t.Fatalf("buildIncomingCallPushPayload() error=%v", err)
	}
	assertInterfaceStringValue(t, payload, "type", "incoming_call")
	assertInterfaceStringValue(t, payload, "call_id", "123")
	assertInterfaceStringValue(t, payload, "caller_name", "未知来电")
	assertInterfaceStringValue(t, payload, "caller_id", "caller-1")
	assertInterfaceStringValue(t, payload, "call_type", "video")
	assertInterfaceStringValue(t, payload, "channel_name", "room-123")
	assertInterfaceStringValue(t, payload, "room_name", "room-123")
	if payload["is_video"] != true {
		t.Fatalf("is_video=%v, want true", payload["is_video"])
	}
}

func TestBuildIncomingCallPushPayloadRejectsMissingBusinessFields(t *testing.T) {
	t.Parallel()
	now := time.Date(2026, 7, 23, 12, 0, 0, 0, time.UTC)

	_, err := buildIncomingCallPushPayload("Alice", "123", false, map[string]interface{}{
		"expires_at": now.Add(30 * time.Second),
	}, now)
	if err == nil {
		t.Fatal("buildIncomingCallPushPayload() error=nil, want contract error")
	}
	for _, field := range []string{"caller_id", "channel_name"} {
		if !strings.Contains(err.Error(), field) {
			t.Fatalf("error=%q, want field %q", err, field)
		}
	}
}

func TestValidateIncomingCallVoIPPayloadRejectsExpiredCall(t *testing.T) {
	t.Parallel()
	now := time.Date(2026, 7, 23, 12, 0, 0, 0, time.UTC)
	err := validateIncomingCallVoIPPayload(map[string]interface{}{
		"type":         "incoming_call",
		"call_id":      "123",
		"caller_id":    "caller-1",
		"caller_name":  "Alice",
		"channel_name": "room-123",
		"call_type":    "voice",
		"expires_at":   now.Add(-time.Second),
	}, now)
	if err == nil || !strings.Contains(err.Error(), "not in the future") {
		t.Fatalf("validateIncomingCallVoIPPayload() error=%v, want expired error", err)
	}
}

func TestWebPushNotificationURLIncomingCallIncludesRTCProvider(t *testing.T) {
	t.Parallel()
	got := webPushNotificationURL(map[string]interface{}{
		"type":         "incoming_call",
		"call_id":      "123",
		"channel_name": "call_abc",
		"room_name":    "call_abc",
		"provider":     "livekit",
		"rtc_provider": "livekit",
		"caller_id":    "u1",
		"caller_name":  "Alice",
		"call_type":    "video",
	})

	parsed, err := url.Parse(got)
	if err != nil {
		t.Fatalf("parse url: %v", err)
	}
	if parsed.Path != "/call" {
		t.Fatalf("path=%q, want /call", parsed.Path)
	}
	query := parsed.Query()
	assertQueryValue(t, query, "mode", "incoming")
	assertQueryValue(t, query, "call_id", "123")
	assertQueryValue(t, query, "channel_name", "call_abc")
	assertQueryValue(t, query, "room_name", "call_abc")
	assertQueryValue(t, query, "provider", "livekit")
	assertQueryValue(t, query, "rtc_provider", "livekit")
	assertQueryValue(t, query, "caller_id", "u1")
	assertQueryValue(t, query, "caller_name", "Alice")
	assertQueryValue(t, query, "call_type", "video")
}

func assertQueryValue(t *testing.T, values url.Values, key, want string) {
	t.Helper()
	if got := values.Get(key); got != want {
		t.Fatalf("%s=%q, want %q", key, got, want)
	}
}

func TestBuildFCMRequestBodyIncomingCallIsDataOnly(t *testing.T) {
	t.Parallel()
	got := buildFCMRequestBody("token-1", "Alice", "来电: 视频通话", map[string]interface{}{
		"type":         "incoming_call",
		"call_id":      "123",
		"channel_name": "call_abc",
		"caller_name":  "Alice",
		"is_video":     true,
	})
	message := assertMapValue(t, got, "message")
	if _, ok := message["notification"]; ok {
		t.Fatalf("incoming_call FCM should be data-only, got notification=%v", message["notification"])
	}
	android := assertMapValue(t, message, "android")
	if _, ok := android["notification"]; ok {
		t.Fatalf("incoming_call FCM should not include android.notification")
	}
	assertInterfaceStringValue(t, android, "priority", "high")
	assertInterfaceStringValue(t, android, "ttl", "30s")
	data := assertStringMapValue(t, message, "data")
	assertStringValue(t, data, "type", "incoming_call")
	assertStringValue(t, data, "call_id", "123")
	assertStringValue(t, data, "title", "Alice")
	assertStringValue(t, data, "body", "来电: 视频通话")
	assertStringValue(t, data, "is_video", "true")
}

func TestIncomingCallPushTTLUsesAuthoritativeExpiry(t *testing.T) {
	t.Parallel()
	now := time.Date(2026, 7, 17, 0, 0, 0, 0, time.UTC)
	tests := []struct {
		name string
		data map[string]interface{}
		want int64
		ok   bool
	}{
		{
			name: "non call has no override",
			data: map[string]interface{}{"type": "new_message"},
			ok:   false,
		},
		{
			name: "legacy call is capped",
			data: map[string]interface{}{"type": "incoming_call"},
			want: 30,
			ok:   true,
		},
		{
			name: "rfc3339 rounds remaining fraction up",
			data: map[string]interface{}{
				"type":       "incoming_call",
				"expires_at": now.Add(12300 * time.Millisecond).Format(time.RFC3339Nano),
			},
			want: 13,
			ok:   true,
		},
		{
			name: "long expiry cannot exceed ringing window",
			data: map[string]interface{}{
				"type":       "incoming_call",
				"expires_at": now.Add(time.Hour),
			},
			want: 30,
			ok:   true,
		},
		{
			name: "expired call uses shortest provider ttl",
			data: map[string]interface{}{
				"type":       "incoming_call",
				"expires_at": now.Add(-time.Second).Unix(),
			},
			want: 1,
			ok:   true,
		},
		{
			name: "unix milliseconds",
			data: map[string]interface{}{
				"type":       "incoming_call",
				"expires_at": now.Add(20 * time.Second).UnixMilli(),
			},
			want: 20,
			ok:   true,
		},
	}
	for _, test := range tests {
		t.Run(test.name, func(t *testing.T) {
			t.Parallel()
			got, ok := incomingCallPushTTLSeconds(test.data, now)
			if ok != test.ok || got != test.want {
				t.Fatalf("incomingCallPushTTLSeconds()=(%d,%v), want(%d,%v)", got, ok, test.want, test.ok)
			}
		})
	}
}

func TestBuildHMSRequestBodyIncomingCallUsesShortTTL(t *testing.T) {
	t.Parallel()
	got := buildHMSRequestBody("token-hms", "Alice", "来电: 语音通话", map[string]interface{}{
		"type":    "incoming_call",
		"call_id": "305",
	})
	message := assertMapValue(t, got, "message")
	if _, ok := message["notification"]; ok {
		t.Fatalf("incoming_call HMS should be data-only, got notification=%v", message["notification"])
	}
	android := assertMapValue(t, message, "android")
	assertInterfaceStringValue(t, android, "urgency", "HIGH")
	assertInterfaceStringValue(t, android, "ttl", "30s")
}

func TestBuildFCMRequestBodyMessageRevokedIsDataOnly(t *testing.T) {
	t.Parallel()
	got := buildFCMRequestBody(
		"token-1",
		"消息已撤回",
		"一条未读消息已被撤回",
		messageRevokedPushData(" chat-205 ", " msg-205 "),
	)
	message := assertMapValue(t, got, "message")
	if _, ok := message["notification"]; ok {
		t.Fatalf("message_revoked FCM should be data-only, got notification=%v", message["notification"])
	}
	data := assertStringMapValue(t, message, "data")
	assertStringValue(t, data, "type", "message_revoked")
	assertStringValue(t, data, "chat_id", "chat-205")
	assertStringValue(t, data, "msg_id", "msg-205")
	assertStringValue(t, data, "message_id", "msg-205")
	assertStringValue(t, data, "scene", "message_revoked")
	assertStringValue(t, data, "push_category", "service_notice")
	assertStringValue(t, data, "message_category", "service_notice")
	assertStringValue(t, data, "notification_id", "48082")
}

func TestBuildHMSRequestBodyMessageRevokedIsDataOnly(t *testing.T) {
	t.Parallel()
	got := buildHMSRequestBody(
		"token-hms",
		"消息已撤回",
		"一条未读消息已被撤回",
		messageRevokedPushData("chat-357", "message-357"),
	)
	message := assertMapValue(t, got, "message")
	if _, ok := message["notification"]; ok {
		t.Fatalf("message_revoked HMS should be data-only, got notification=%v", message["notification"])
	}
	rawData, ok := message["data"].(string)
	if !ok || strings.TrimSpace(rawData) == "" {
		t.Fatalf("message_revoked HMS data is missing: %v", message["data"])
	}
	var data map[string]interface{}
	if err := json.Unmarshal([]byte(rawData), &data); err != nil {
		t.Fatalf("decode message_revoked HMS data: %v", err)
	}
	assertInterfaceStringValue(t, data, "type", "message_revoked")
	assertInterfaceStringValue(t, data, "scene", "message_revoked")
	assertInterfaceStringValue(t, data, "chat_id", "chat-357")
	assertInterfaceStringValue(t, data, "msg_id", "message-357")
	assertInterfaceStringValue(t, data, "message_id", "message-357")
	assertInterfaceStringValue(t, data, "push_category", "service_notice")
	assertInterfaceStringValue(t, data, "message_category", "service_notice")
	assertInterfaceStringValue(t, data, "title", "消息已撤回")
	assertInterfaceStringValue(t, data, "body", "一条未读消息已被撤回")
}

func TestChatNotificationIDMatchesAndroidContract(t *testing.T) {
	t.Parallel()
	if got := chatNotificationID("chat-205"); got != 48082 {
		t.Fatalf("chatNotificationID(chat-205)=%d, want 48082", got)
	}
	if got := chatNotificationID("chat-205"); got < 10000 || got > 89999 {
		t.Fatalf("chatNotificationID(chat-205)=%d, want bounded ID", got)
	}
}

func TestPushNotificationPrivacyTextHidesSenderAndContent(t *testing.T) {
	t.Parallel()

	title, body := pushNotificationPrivacyText(false, "Alice", "private body")
	if title != "新消息" || body != "您收到一条新消息" {
		t.Fatalf("hidden preview=(%q, %q), want generic text", title, body)
	}

	title, body = pushNotificationPrivacyText(true, "Alice", "private body")
	if title != "Alice" || body != "private body" {
		t.Fatalf("visible preview=(%q, %q), want original text", title, body)
	}
}

func TestNewMessagePushDataHidesMediaWhenPreviewIsDisabled(t *testing.T) {
	t.Parallel()
	hidden := newMessagePushData(
		false,
		" chat-private ",
		" private ",
		" message-private ",
		"https://cdn.example.com/private.jpg",
	)
	assertInterfaceStringValue(t, hidden, "type", "new_message")
	assertInterfaceStringValue(t, hidden, "scene", "new_message")
	assertInterfaceStringValue(t, hidden, "chat_id", "chat-private")
	assertInterfaceStringValue(t, hidden, "chat_type", "private")
	assertInterfaceStringValue(t, hidden, "msg_id", "message-private")
	assertInterfaceStringValue(t, hidden, "message_id", "message-private")
	for _, key := range []string{"image_url", "thumbnail", "media_url", "image"} {
		if value, ok := hidden[key]; ok {
			t.Fatalf("preview-off payload leaked %s=%v", key, value)
		}
	}
	visible := newMessagePushData(
		true,
		"chat-visible",
		"group",
		"message-visible",
		"https://cdn.example.com/visible.jpg",
	)
	for _, key := range []string{"image_url", "thumbnail", "media_url", "image"} {
		assertInterfaceStringValue(t, visible, key, "https://cdn.example.com/visible.jpg")
	}
}

func TestBuildFCMRequestBodyNewMessageUsesClientGatedDataOnly(t *testing.T) {
	t.Parallel()
	pushData := newMessagePushData(
		true,
		"c1",
		"private",
		"message-1",
		"https://cdn.example.com/a.jpg",
	)
	got := buildFCMRequestBodyForClient(
		"token-1",
		"Bob",
		"hello",
		pushData,
		true,
	)
	message := assertMapValue(t, got, "message")
	if _, ok := message["notification"]; ok {
		t.Fatal("new-message FCM payload must be data-only so the client master switch can gate display")
	}
	android := assertMapValue(t, message, "android")
	if _, ok := android["notification"]; ok {
		t.Fatal("new-message Android payload must not contain an automatic notification")
	}
	assertInterfaceStringValue(t, android, "priority", "high")
	notificationID := chatNotificationID("c1")
	data := assertStringMapValue(t, message, "data")
	assertStringValue(t, data, "type", "new_message")
	assertStringValue(t, data, "title", "Bob")
	assertStringValue(t, data, "body", "hello")
	assertStringValue(t, data, "image_url", "https://cdn.example.com/a.jpg")
	assertStringValue(t, data, "notification_id", strconv.Itoa(notificationID))
}

func TestBuildFCMRequestBodyLegacyNewMessageKeepsAutomaticNotification(t *testing.T) {
	t.Parallel()
	got := buildFCMRequestBody("token-legacy", "Bob", "hello", newMessagePushData(
		true,
		"legacy-chat",
		"private",
		"legacy-message",
		"",
	))
	message := assertMapValue(t, got, "message")
	notification := assertStringMapValue(t, message, "notification")
	assertStringValue(t, notification, "title", "Bob")
	assertStringValue(t, notification, "body", "hello")
}

func TestSupportsClientGatedFCMNotifications(t *testing.T) {
	t.Parallel()
	tests := map[string]bool{
		"":           false,
		"5.0.0":      false,
		"5.0.0+25":   false,
		"5.0.0+26":   true,
		"5.0.0+1026": true,
		"5.0.1+1":    true,
		"5.1.0+1":    true,
		"6.0.0+1":    true,
		"4.9.9+999":  false,
		"invalid":    false,
	}
	for version, want := range tests {
		if got := supportsClientGatedFCMNotifications(version); got != want {
			t.Fatalf("supportsClientGatedFCMNotifications(%q)=%v, want %v", version, got, want)
		}
	}
}

func TestSupportsClientGatedFCMNotificationsByBusinessType(t *testing.T) {
	t.Parallel()
	if !supportsClientGatedFCMNotificationsForType("5.0.0+26", "new_message") {
		t.Fatal("build 26 must keep the message client gate")
	}
	if !supportsClientGatedFCMNotificationsForType("5.0.0+26", "chat_announcement") {
		t.Fatal("build 26 must keep the announcement client gate")
	}
	if supportsClientGatedFCMNotificationsForType("5.0.0+26", "meeting_invite") {
		t.Fatal("build 26 cannot receive data-only meetings because it has no local renderer")
	}
	for _, dataType := range []string{
		"meeting_invite",
		"meeting_join_request",
		"meeting_join_request_reviewed",
		"meeting_status",
	} {
		if !supportsClientGatedFCMNotificationsForType("5.0.0+27", dataType) {
			t.Fatalf("build 27 must gate %s locally", dataType)
		}
	}
	if supportsClientGatedFCMNotificationsForType("5.0.0+27", "friend_request") {
		t.Fatal("unsupported notification types must retain their existing protocol")
	}
}

func TestMeetingPushUsesStableIdentityAndVersionGatedDataOnly(t *testing.T) {
	t.Parallel()
	data := map[string]interface{}{
		"type":       "meeting_invite",
		"meeting_id": "meeting-349",
	}
	ensureStablePushNotificationIdentity(data)
	notificationID := meetingNotificationID("meeting_invite", "meeting-349")
	if got := data["notification_id"]; got != notificationID {
		t.Fatalf("notification_id=%v, want %d", got, notificationID)
	}
	if notificationID < 1000000 || notificationID > 1899999 {
		t.Fatalf("meeting notification ID out of range: %d", notificationID)
	}
	if notificationID == meetingNotificationID("meeting_join_request", "meeting-349") {
		t.Fatal("different meeting event types must not share an identity")
	}
	legacy := buildFCMRequestBodyForClient(
		"legacy-token",
		"Host",
		"Invite you to join group meeting",
		data,
		false,
	)
	legacyMessage := assertMapValue(t, legacy, "message")
	legacyNotification := assertStringMapValue(t, legacyMessage, "notification")
	assertStringValue(t, legacyNotification, "title", "Host")
	legacyAndroid := assertMapValue(t, legacyMessage, "android")
	legacyAndroidNotification := assertStringMapValue(t, legacyAndroid, "notification")
	assertStringValue(t, legacyAndroidNotification, "channel_id", "genericim_meetings_v1")
	assertStringValue(t, legacyAndroidNotification, "tag", fmt.Sprintf("genericim-meeting-%d", notificationID))
	gated := buildFCMRequestBodyForClient(
		"new-token",
		"Host",
		"Invite you to join group meeting",
		data,
		true,
	)
	gatedMessage := assertMapValue(t, gated, "message")
	if _, ok := gatedMessage["notification"]; ok {
		t.Fatal("build 27 meeting push must be data-only for the local master gate")
	}
	gatedAndroid := assertMapValue(t, gatedMessage, "android")
	if _, ok := gatedAndroid["notification"]; ok {
		t.Fatal("build 27 meeting Android payload must not auto-display")
	}
	gatedData := assertStringMapValue(t, gatedMessage, "data")
	assertStringValue(t, gatedData, "type", "meeting_invite")
	assertStringValue(t, gatedData, "meeting_id", "meeting-349")
	assertStringValue(t, gatedData, "notification_id", strconv.Itoa(notificationID))
	assertStringValue(t, gatedData, "title", "Host")
	assertStringValue(t, gatedData, "body", "Invite you to join group meeting")
}

func TestSystemAnnouncementPushUsesPersistedIdentityAndBuild28Gate(t *testing.T) {
	t.Parallel()
	data := systemAnnouncementPushData(88, "maintenance")
	assertInterfaceStringValue(t, data, "type", "system_announcement")
	assertInterfaceStringValue(t, data, "scene", "system_notice")
	assertInterfaceStringValue(t, data, "subtype", "maintenance")
	assertInterfaceStringValue(t, data, "push_category", "service_notice")
	if got := data["broadcast_id"]; got != uint64(88) {
		t.Fatalf("broadcast_id=%v, want 88", got)
	}
	notificationID := systemAnnouncementNotificationID("88")
	if got := data["notification_id"]; got != notificationID {
		t.Fatalf("notification_id=%v, want %d", got, notificationID)
	}
	if notificationID < 2000000 || notificationID > 2899999 {
		t.Fatalf("system notification ID out of range: %d", notificationID)
	}
	if supportsClientGatedFCMNotificationsForType("5.0.0+27", "system_announcement") {
		t.Fatal("build 27 has no local system-announcement renderer")
	}
	if !supportsClientGatedFCMNotificationsForType("5.0.0+28", "system_announcement") {
		t.Fatal("build 28 must gate system announcements locally")
	}
	legacy := buildFCMRequestBodyForClient(
		"legacy-system-token",
		"维护通知",
		"今晚进行系统维护",
		data,
		false,
	)
	legacyMessage := assertMapValue(t, legacy, "message")
	legacyAndroid := assertMapValue(t, legacyMessage, "android")
	legacyNotification := assertStringMapValue(t, legacyAndroid, "notification")
	assertStringValue(t, legacyNotification, "channel_id", "genericim_announcements_v1")
	assertStringValue(t, legacyNotification, "tag", fmt.Sprintf("genericim-system-announcement-%d", notificationID))
	gated := buildFCMRequestBodyForClient(
		"build28-system-token",
		"维护通知",
		"今晚进行系统维护",
		data,
		true,
	)
	gatedMessage := assertMapValue(t, gated, "message")
	if _, ok := gatedMessage["notification"]; ok {
		t.Fatal("build 28 system announcement must be data-only")
	}
	gatedAndroid := assertMapValue(t, gatedMessage, "android")
	if _, ok := gatedAndroid["notification"]; ok {
		t.Fatal("build 28 system announcement must not auto-display")
	}
	gatedData := assertStringMapValue(t, gatedMessage, "data")
	assertStringValue(t, gatedData, "type", "system_announcement")
	assertStringValue(t, gatedData, "broadcast_id", "88")
	assertStringValue(t, gatedData, "notification_id", strconv.Itoa(notificationID))
	assertStringValue(t, gatedData, "title", "维护通知")
	assertStringValue(t, gatedData, "body", "今晚进行系统维护")
	hms := buildHMSRequestBody("hms-system-token", "维护通知", "今晚进行系统维护", data)
	hmsMessage := assertMapValue(t, hms, "message")
	hmsAndroid := assertMapValue(t, hmsMessage, "android")
	assertInterfaceStringValue(t, hmsAndroid, "urgency", "HIGH")
	hmsData := assertJSONStringMapValue(t, hmsMessage, "data")
	assertInterfaceStringValue(t, hmsData, "type", "system_announcement")
	if got := int(hmsData["notification_id"].(float64)); got != notificationID {
		t.Fatalf("HMS notification_id=%d, want %d", got, notificationID)
	}
}

func TestPushNotificationChannelIDSeparatesBusinessTypes(t *testing.T) {
	t.Parallel()
	if got := pushNotificationChannelID("new_message"); got != "genericim_messages" {
		t.Fatalf("message channel=%q", got)
	}
	if got := pushNotificationChannelID("chat_announcement"); got != "genericim_announcements_v1" {
		t.Fatalf("announcement channel=%q", got)
	}
	if got := pushNotificationChannelID("incoming_call"); got != "genericim_calls_v1" {
		t.Fatalf("call channel=%q", got)
	}
	if got := pushNotificationChannelID("call_missed"); got != "genericim_calls_v1" {
		t.Fatalf("missed-call channel=%q", got)
	}
	if got := pushNotificationChannelID("meeting_invite"); got != "genericim_meetings_v1" {
		t.Fatalf("meeting channel=%q", got)
	}
	if got := pushNotificationChannelID("meeting_join_request_reviewed"); got != "genericim_meetings_v1" {
		t.Fatalf("meeting reviewed channel=%q", got)
	}
}

func TestNormalizePushDisplayTextRepairsLegacyCallMojibake(t *testing.T) {
	t.Parallel()
	got := normalizePushDisplayText(string([]rune{0x7487, 0xe162, 0x7176, 0x95ab, 0x6c33, 0x763d}) + " 00:02")
	if got != "语音通话 00:02" {
		t.Fatalf("normalizePushDisplayText()=%q, want %q", got, "语音通话 00:02")
	}
}

func TestBuildFCMRequestBodyUsesThumbnailAliasForNotificationImage(t *testing.T) {
	t.Parallel()
	got := buildFCMRequestBody("token-1", "Bob", "hello", map[string]interface{}{
		"type":      "friend_request",
		"chat_id":   "c1",
		"thumbnail": "https://cdn.example.com/thumb.jpg",
	})
	message := assertMapValue(t, got, "message")
	notification := assertStringMapValue(t, message, "notification")
	assertStringValue(t, notification, "image", "https://cdn.example.com/thumb.jpg")
	android := assertMapValue(t, message, "android")
	androidNotification := assertStringMapValue(t, android, "notification")
	assertStringValue(t, androidNotification, "image", "https://cdn.example.com/thumb.jpg")
}

func TestAttachPushImageAliases(t *testing.T) {
	t.Parallel()
	data := map[string]interface{}{}
	attachPushImageAliases(data, "https://cdn.example.com/thumb.jpg")

	assertInterfaceStringValue(t, data, "image_url", "https://cdn.example.com/thumb.jpg")
	assertInterfaceStringValue(t, data, "thumbnail", "https://cdn.example.com/thumb.jpg")
	assertInterfaceStringValue(t, data, "media_url", "https://cdn.example.com/thumb.jpg")
	assertInterfaceStringValue(t, data, "image", "https://cdn.example.com/thumb.jpg")
}

func TestPushClassificationUsesConfiguredCategory(t *testing.T) {
	t.Parallel()
	service := &PushService{
		androidConfig: AndroidPushConfig{
			ChatCategory:      "chat_private",
			ServiceCategory:   "service_notice",
			MarketingCategory: "marketing",
		},
	}
	chat := service.withPushClassification(map[string]interface{}{"type": "new_message"})
	assertInterfaceStringValue(t, chat, "push_category", "chat_private")
	assertInterfaceStringValue(t, chat, "message_category", "chat_private")
	system := service.withPushClassification(map[string]interface{}{"scene": "friend_request"})
	assertInterfaceStringValue(t, system, "push_category", "service_notice")
	marketing := service.withPushClassification(map[string]interface{}{"scene": "marketing_notice"})
	assertInterfaceStringValue(t, marketing, "push_category", "marketing")
	explicit := service.withPushClassification(map[string]interface{}{
		"scene":         "group_notice",
		"push_category": "group_notice",
	})
	assertInterfaceStringValue(t, explicit, "push_category", "group_notice")
	assertInterfaceStringValue(t, explicit, "message_category", "group_notice")
}

func TestChatAnnouncementPushContractSeparatesBusinessChannel(t *testing.T) {
	t.Parallel()
	data := chatAnnouncementPushData("  group-1  ", 42)
	assertInterfaceStringValue(t, data, "type", "chat_announcement")
	assertInterfaceStringValue(t, data, "scene", "group_notice")
	assertInterfaceStringValue(t, data, "chat_id", "group-1")
	assertInterfaceStringValue(t, data, "chat_type", "group")
	assertInterfaceStringValue(t, data, "push_category", "group_notice")
	assertInterfaceStringValue(t, data, "message_category", "group_notice")
	if got := data["announcement_id"]; got != uint64(42) {
		t.Fatalf("announcement_id=%v, want 42", got)
	}
	notificationID := announcementNotificationID("group-1", 42)
	if got := data["notification_id"]; got != notificationID {
		t.Fatalf("notification_id=%v, want %d", got, notificationID)
	}
	fcm := buildFCMRequestBody("fcm-token", "群公告", "群内发布了新公告", data)
	message := assertMapValue(t, fcm, "message")
	android := assertMapValue(t, message, "android")
	androidNotification := assertStringMapValue(t, android, "notification")
	assertStringValue(t, androidNotification, "channel_id", "genericim_announcements_v1")
	assertStringValue(t, androidNotification, "tag", fmt.Sprintf("genericim-announcement-%d", notificationID))
	fcmData := assertStringMapValue(t, message, "data")
	assertStringValue(t, fcmData, "type", "chat_announcement")
	assertStringValue(t, fcmData, "chat_id", "group-1")
	assertStringValue(t, fcmData, "notification_id", strconv.Itoa(notificationID))
	gatedFCM := buildFCMRequestBodyForClient(
		"fcm-token-new",
		"群公告",
		"群内发布了新公告",
		data,
		true,
	)
	gatedMessage := assertMapValue(t, gatedFCM, "message")
	if _, ok := gatedMessage["notification"]; ok {
		t.Fatal("new-client announcement must be data-only for the local master gate")
	}
	gatedAndroid := assertMapValue(t, gatedMessage, "android")
	if _, ok := gatedAndroid["notification"]; ok {
		t.Fatal("new-client announcement must not use an automatic Android notification")
	}
	gatedData := assertStringMapValue(t, gatedMessage, "data")
	assertStringValue(t, gatedData, "title", "群公告")
	assertStringValue(t, gatedData, "body", "群内发布了新公告")
	assertStringValue(t, gatedData, "notification_id", strconv.Itoa(notificationID))
	hms := buildHMSRequestBody("hms-token", "群公告", "群内发布了新公告", data)
	hmsMessage := assertMapValue(t, hms, "message")
	hmsAndroid := assertMapValue(t, hmsMessage, "android")
	assertInterfaceStringValue(t, hmsAndroid, "urgency", "HIGH")
	hmsData := assertJSONStringMapValue(t, hmsMessage, "data")
	assertInterfaceStringValue(t, hmsData, "type", "chat_announcement")
	assertInterfaceStringValue(t, hmsData, "scene", "group_notice")
	assertInterfaceStringValue(t, hmsData, "chat_id", "group-1")
	assertInterfaceStringValue(t, hmsData, "message_category", "group_notice")
	if got := int(hmsData["notification_id"].(float64)); got != notificationID {
		t.Fatalf("HMS notification_id=%d, want %d", got, notificationID)
	}
}

func TestAnnouncementNotificationIDIsStableAndSeparated(t *testing.T) {
	t.Parallel()
	first := announcementNotificationID("group-1", 42)
	if first != announcementNotificationID(" group-1 ", 42) {
		t.Fatal("announcement notification ID must be stable after chat normalization")
	}
	if first == announcementNotificationID("group-1", 43) {
		t.Fatal("different announcements must not share a notification ID")
	}
	if first < 100000 || first > 899999 {
		t.Fatalf("announcement notification ID=%d, want 100000..899999", first)
	}
	if first == chatNotificationID("group-1") {
		t.Fatal("announcement and chat message notification ranges must be separate")
	}
}

func TestPushQuietHoursSupportsOvernightWindow(t *testing.T) {
	t.Parallel()
	if !isNowInQuietHours(time.Date(2026, 6, 25, 23, 10, 0, 0, time.Local), "22:00", "08:00") {
		t.Fatalf("23:10 should be inside quiet hours")
	}
	if !isNowInQuietHours(time.Date(2026, 6, 25, 7, 59, 0, 0, time.Local), "22:00", "08:00") {
		t.Fatalf("07:59 should be inside quiet hours")
	}
	if isNowInQuietHours(time.Date(2026, 6, 25, 12, 0, 0, 0, time.Local), "22:00", "08:00") {
		t.Fatalf("12:00 should be outside quiet hours")
	}
}

func TestNormalizePushProviderSetting(t *testing.T) {
	t.Parallel()
	if got := normalizePushProviderSetting("Getui", "jpush"); got != "getui" {
		t.Fatalf("provider=%q, want getui", got)
	}
	if got := normalizePushProviderSetting("", "jpush"); got != "jpush" {
		t.Fatalf("empty provider=%q, want jpush", got)
	}
	if got := normalizePushProviderSetting("bad", "none"); got != "none" {
		t.Fatalf("bad provider=%q, want none", got)
	}
}

func TestBuildHMSRequestBodyUsesDataMessagePayload(t *testing.T) {
	t.Parallel()
	got := buildHMSRequestBody("token-1", "Bob", "hello", map[string]interface{}{
		"type":      "new_message",
		"chat_id":   "c1",
		"image_url": "https://cdn.example.com/a.jpg",
	})
	message := assertMapValue(t, got, "message")
	if _, ok := message["notification"]; ok {
		t.Fatalf("HMS should use app-handled data message, got notification=%v", message["notification"])
	}
	android := assertMapValue(t, message, "android")
	assertInterfaceStringValue(t, android, "urgency", "HIGH")
	assertInterfaceStringValue(t, android, "ttl", "86400s")
	if _, ok := android["notification"]; ok {
		t.Fatalf("HMS should not include android.notification, got %v", android["notification"])
	}
	if _, ok := android["data"]; ok {
		t.Fatalf("HMS data should be top-level message.data, got android.data=%v", android["data"])
	}
	data := assertJSONStringMapValue(t, message, "data")
	assertInterfaceStringValue(t, data, "type", "new_message")
	assertInterfaceStringValue(t, data, "chat_id", "c1")
	assertInterfaceStringValue(t, data, "image_url", "https://cdn.example.com/a.jpg")
	assertInterfaceStringValue(t, data, "title", "Bob")
	assertInterfaceStringValue(t, data, "body", "hello")
}

func TestBuildPushDeliveryPlansOrdersAndroidFallbackCandidates(t *testing.T) {
	t.Parallel()
	now := time.Date(2026, 6, 27, 10, 0, 0, 0, time.UTC)
	devices := []models.UserDevice{
		{ID: 1, DeviceID: "ios-1", DeviceType: "ios", PushChannel: PushChannelAPNs, PushToken: "apns-token", LastActive: now},
		{ID: 2, DeviceID: "phone-1:push:hms", DeviceType: "android", PushChannel: PushChannelHMS, PushToken: "hms-token", LastActive: now.Add(-time.Minute)},
		{ID: 3, DeviceID: "phone-1:push:fcm", DeviceType: "android", PushChannel: PushChannelFCM, PushToken: "fcm-token", LastActive: now.Add(-2 * time.Minute)},
		{ID: 4, DeviceID: "phone-2:push:oppo", DeviceType: "android", PushChannel: PushChannelOppo, PushToken: "oppo-token", LastActive: now},
	}
	plans := buildPushDeliveryPlans(devices, AndroidPushConfig{
		PrimaryProvider:  PushChannelFCM,
		FallbackProvider: PushChannelHMS,
	})
	if len(plans) != 3 {
		t.Fatalf("plan count=%d, want 3", len(plans))
	}
	if len(plans[0].devices) != 1 || plans[0].devices[0].PushChannel != PushChannelAPNs {
		t.Fatalf("first plan=%v, want apns single plan", plans[0].devices)
	}
	phoneOne := plans[1].devices
	if len(phoneOne) != 2 {
		t.Fatalf("phone one candidates=%d, want 2: %v", len(phoneOne), phoneOne)
	}
	if phoneOne[0].PushChannel != PushChannelFCM || phoneOne[1].PushChannel != PushChannelHMS {
		t.Fatalf("phone one order=%s,%s; want fcm,hms", phoneOne[0].PushChannel, phoneOne[1].PushChannel)
	}
	phoneTwo := plans[2].devices
	if len(phoneTwo) != 1 || phoneTwo[0].PushChannel != PushChannelOppo {
		t.Fatalf("phone two plan=%v, want oppo single plan", phoneTwo)
	}
}

func TestBuildPushDeliveryPlansKeepsLatestDevicePerChannel(t *testing.T) {
	t.Parallel()
	now := time.Date(2026, 6, 27, 10, 0, 0, 0, time.UTC)
	devices := []models.UserDevice{
		{ID: 1, DeviceID: "phone-1:push:hms", DeviceType: "android", PushChannel: PushChannelHMS, PushToken: "old-token", LastActive: now},
		{ID: 2, DeviceID: "phone-1:push:hms", DeviceType: "android", PushChannel: PushChannelHMS, PushToken: "new-token", LastActive: now.Add(time.Minute)},
		{ID: 3, DeviceID: "phone-1:push:fcm", DeviceType: "android", PushChannel: PushChannelFCM, PushToken: "fcm-token", LastActive: now},
	}
	plans := buildPushDeliveryPlans(devices, AndroidPushConfig{
		PrimaryProvider:  PushChannelHMS,
		FallbackProvider: PushChannelFCM,
	})
	if len(plans) != 1 {
		t.Fatalf("plan count=%d, want 1", len(plans))
	}
	candidates := plans[0].devices
	if len(candidates) != 2 {
		t.Fatalf("candidate count=%d, want 2", len(candidates))
	}
	if candidates[0].PushChannel != PushChannelHMS || candidates[0].PushToken != "new-token" {
		t.Fatalf("primary candidate=%s/%s, want hms/new-token", candidates[0].PushChannel, candidates[0].PushToken)
	}
	if candidates[1].PushChannel != PushChannelFCM {
		t.Fatalf("fallback candidate=%s, want fcm", candidates[1].PushChannel)
	}
}

func assertMapValue(t *testing.T, values map[string]interface{}, key string) map[string]interface{} {
	t.Helper()
	got, ok := values[key].(map[string]interface{})
	if !ok {
		t.Fatalf("%s=%T, want map[string]interface{}", key, values[key])
	}
	return got
}

func assertStringMapValue(t *testing.T, values map[string]interface{}, key string) map[string]string {
	t.Helper()
	got, ok := values[key].(map[string]string)
	if !ok {
		t.Fatalf("%s=%T, want map[string]string", key, values[key])
	}
	return got
}

func assertStringValue(t *testing.T, values map[string]string, key, want string) {
	t.Helper()
	if got := values[key]; got != want {
		t.Fatalf("%s=%q, want %q", key, got, want)
	}
}

func assertJSONStringMapValue(t *testing.T, values map[string]interface{}, key string) map[string]interface{} {
	t.Helper()
	raw, ok := values[key].(string)
	if !ok {
		t.Fatalf("%s=%T, want string", key, values[key])
	}
	var got map[string]interface{}
	if err := json.Unmarshal([]byte(raw), &got); err != nil {
		t.Fatalf("parse %s json: %v", key, err)
	}
	return got
}

func assertInterfaceStringValue(t *testing.T, values map[string]interface{}, key, want string) {
	t.Helper()
	got, ok := values[key].(string)
	if !ok {
		t.Fatalf("%s=%T, want string", key, values[key])
	}
	if got != want {
		t.Fatalf("%s=%q, want %q", key, got, want)
	}
}

func assertInterfaceBoolValue(t *testing.T, values map[string]interface{}, key string, want bool) {
	t.Helper()
	got, ok := values[key].(bool)
	if !ok {
		t.Fatalf("%s=%T, want bool", key, values[key])
	}
	if got != want {
		t.Fatalf("%s=%v, want %v", key, got, want)
	}
}

func assertInterfaceIntValue(t *testing.T, values map[string]interface{}, key string, want int) {
	t.Helper()
	got, ok := values[key].(int)
	if !ok {
		t.Fatalf("%s=%T, want int", key, values[key])
	}
	if got != want {
		t.Fatalf("%s=%v, want %v", key, got, want)
	}
}
