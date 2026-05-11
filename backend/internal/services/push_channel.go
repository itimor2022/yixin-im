package services

import "strings"

const (
	PushChannelUnknown = "unknown"
	PushChannelAPNs    = "apns"
	PushChannelFCM     = "fcm"
	PushChannelHMS     = "hms"
	PushChannelXiaomi  = "xiaomi"
	PushChannelOppo    = "oppo"
)

// NormalizePushChannel normalizes push channel names from client and server.
func NormalizePushChannel(channel, deviceType string) string {
	value := strings.ToLower(strings.TrimSpace(channel))
	switch value {
	case PushChannelAPNs:
		return PushChannelAPNs
	case PushChannelFCM:
		return PushChannelFCM
	case PushChannelHMS, "huawei":
		return PushChannelHMS
	case PushChannelXiaomi, "mi", "mipush":
		return PushChannelXiaomi
	case PushChannelOppo, "opush", "heytap":
		return PushChannelOppo
	}

	switch strings.ToLower(strings.TrimSpace(deviceType)) {
	case "ios":
		return PushChannelAPNs
	case "android":
		// Keep FCM as Android default until vendor token SDKs are enabled.
		return PushChannelFCM
	default:
		return PushChannelUnknown
	}
}
