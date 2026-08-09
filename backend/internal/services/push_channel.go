// 文件用途：实现可复用的后端业务服务和领域逻辑。
// 核心逻辑：协调数据库、缓存、队列和外部服务，集中处理事务、幂等、重试和错误传播。

package services

import "strings"

const (
	PushChannelUnknown  = "unknown"
	PushChannelAPNs     = "apns"
	PushChannelAPNsVoIP = "apns_voip"
	PushChannelFCM      = "fcm"
	PushChannelHMS      = "hms"
	PushChannelJPush    = "jpush"
	PushChannelXiaomi   = "xiaomi"
	PushChannelOppo     = "oppo"
	PushChannelWebPush  = "webpush"
)

const androidPushDeviceIDSuffixPrefix = ":push:"

var androidPushChannels = []string{
	PushChannelJPush,
	PushChannelFCM,
	PushChannelHMS,
	PushChannelXiaomi,
	PushChannelOppo,
}

// NormalizePushChannel
func NormalizePushChannel(channel, deviceType string) string {
	value := strings.ToLower(strings.TrimSpace(channel))
	switch value {
	case PushChannelAPNs:
		return PushChannelAPNs
	case PushChannelAPNsVoIP, "apns-voip", "voip":
		return PushChannelAPNsVoIP
	case PushChannelFCM:
		return PushChannelFCM
	case PushChannelHMS, "huawei":
		return PushChannelHMS
	case PushChannelJPush, "jiguang", "aurora":
		return PushChannelJPush
	case PushChannelXiaomi, "mi", "mipush":
		return PushChannelXiaomi
	case PushChannelOppo, "opush", "heytap":
		return PushChannelOppo
	case PushChannelWebPush, "web", "h5":
		return PushChannelWebPush
	}

	switch strings.ToLower(strings.TrimSpace(deviceType)) {
	case "ios":
		return PushChannelAPNs
	case "android":
		//

		return PushChannelFCM
	default:
		return PushChannelUnknown
	}
}

// NormalizeExplicitPushChannel
//

func NormalizeExplicitPushChannel(channel, deviceType string) string {
	if strings.TrimSpace(channel) != "" {
		return NormalizePushChannel(channel, "")
	}
	return NormalizePushChannel("", deviceType)
}

// IsAndroidPushChannel reports whether channel is an Android vendor channel.
func IsAndroidPushChannel(channel string) bool {
	switch NormalizePushChannel(channel, "") {
	case PushChannelJPush, PushChannelFCM, PushChannelHMS, PushChannelXiaomi, PushChannelOppo:
		return true
	default:
		return false
	}
}

// PushStorageDeviceID

func PushStorageDeviceID(deviceID, channel string) string {
	base := LogicalPushDeviceID(deviceID)
	if base == "" {
		return ""
	}
	normalized := NormalizePushChannel(channel, "")
	if normalized == PushChannelAPNsVoIP {
		return base + ":voip"
	}
	if IsAndroidPushChannel(normalized) {
		return base + androidPushDeviceIDSuffixPrefix + normalized
	}
	return base
}

// LogicalPushDeviceID
func LogicalPushDeviceID(deviceID string) string {
	value := strings.TrimSpace(deviceID)
	if value == "" {
		return ""
	}
	if strings.HasSuffix(value, ":voip") {
		return strings.TrimSuffix(value, ":voip")
	}
	for _, channel := range androidPushChannels {
		suffix := androidPushDeviceIDSuffixPrefix + channel
		if strings.HasSuffix(value, suffix) {
			return strings.TrimSuffix(value, suffix)
		}
	}
	return value
}

// PushStorageDeviceIDs
func PushStorageDeviceIDs(deviceID string) []string {
	base := LogicalPushDeviceID(deviceID)
	if base == "" {
		return []string{}
	}
	ids := []string{base, base + ":voip"}
	for _, channel := range androidPushChannels {
		ids = append(ids, base+androidPushDeviceIDSuffixPrefix+channel)
	}
	seen := make(map[string]struct{}, len(ids)+1)
	if original := strings.TrimSpace(deviceID); original != "" {
		ids = append(ids, original)
	}
	out := make([]string, 0, len(ids))
	for _, id := range ids {
		if id == "" {
			continue
		}
		if _, ok := seen[id]; ok {
			continue
		}
		seen[id] = struct{}{}
		out = append(out, id)
	}
	return out
}
