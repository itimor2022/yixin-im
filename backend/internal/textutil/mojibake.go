// 文件用途：提供文本清洗、乱码识别和编码兼容工具。
// 核心逻辑：统一处理输入文本的规范化和异常字符，保证持久化与响应一致。

package textutil

import (
	"regexp"
	"strings"
)

var legacyCallDurationPattern = regexp.MustCompile(`\d{1,2}:\d{2}(?::\d{2})?`)

var (
	legacySystemSenderMojibake = string([]rune{0x7eef, 0x837b, 0x7cba, 0x5a11, 0x581f, 0x4f05})
	legacyVoiceCallMojibake    = string([]rune{0x7487, 0xe162, 0x7176, 0x95ab, 0x6c33, 0x763d})
	legacyVideoCallMojibake    = string([]rune{0x7459, 0x55db, 0xe576, 0x95ab, 0x6c33, 0x763d})
	legacyCallRequiredMarkerA  = string([]rune{0x95ab})
	legacyCallRequiredMarkerB  = string([]rune{0x763d})
	legacyVoiceCallMarkerA     = string([]rune{0x7487})
	legacyVoiceCallMarkerB     = string([]rune{0x7176})
	legacyVideoCallMarker      = string([]rune{0x7459})
	legacyVideoCallMarkerB     = string([]rune{0x55db})
	legacyVideoCallMarkerAlt   = string([]rune{0xe576})
)

// RepairLegacyMojibakeText

func RepairLegacyMojibakeText(text string) string {
	repaired := strings.TrimSpace(text)
	if repaired == "" {
		return ""
	}

	repaired = strings.ReplaceAll(repaired, legacySystemSenderMojibake, "系统消息")
	repaired = strings.ReplaceAll(repaired, legacyVoiceCallMojibake, "语音通话")
	repaired = strings.ReplaceAll(repaired, legacyVideoCallMojibake, "视频通话")
	if strings.Contains(repaired, "语音通话") || strings.Contains(repaired, "视频通话") {

		if normalized := normalizeLegacyCallStatusText(repaired); normalized != "" {
			return normalized
		}
	}
	if looksLikeLegacyMojibakeCallText(repaired) {
		label := "语音通话"
		if strings.Contains(repaired, legacyVideoCallMarker) || strings.Contains(repaired, legacyVideoCallMarkerAlt) {
			label = "视频通话"
		}
		if duration := legacyCallDurationPattern.FindString(repaired); duration != "" {
			return label + " " + duration
		}
		lower := strings.ToLower(repaired)
		switch {
		case strings.Contains(lower, "cancelled"), strings.Contains(lower, "canceled"), strings.Contains(repaired, "已取消"), strings.Contains(repaired, "取消"):
			return label + " 已取消"
		case strings.Contains(lower, "declined"), strings.Contains(lower, "rejected"), strings.Contains(repaired, "已拒绝"), strings.Contains(repaired, "拒绝"):
			return label + " 已拒绝"
		case strings.Contains(lower, "busy"), strings.Contains(repaired, "对方忙"):
			return label + " 对方忙"
		case strings.Contains(lower, "missed"), strings.Contains(lower, "no answer"), strings.Contains(repaired, "未接"):
			return label + " 未接"
		}
		return label
	}
	return repaired
}

func normalizeLegacyCallStatusText(text string) string {
	label := ""
	switch {
	case strings.Contains(text, "视频通话"):
		label = "视频通话"
	case strings.Contains(text, "语音通话"):
		label = "语音通话"
	default:
		return ""
	}
	if duration := legacyCallDurationPattern.FindString(text); duration != "" {
		return label + " " + duration
	}
	lower := strings.ToLower(text)
	switch {
	case strings.Contains(lower, "cancelled"), strings.Contains(lower, "canceled"), strings.Contains(text, "已取消"), strings.Contains(text, "取消"):
		return label + " 已取消"
	case strings.Contains(lower, "declined"), strings.Contains(lower, "rejected"), strings.Contains(text, "已拒绝"), strings.Contains(text, "拒绝"):
		return label + " 已拒绝"
	case strings.Contains(lower, "busy"), strings.Contains(text, "对方忙"):
		return label + " 对方忙"
	case strings.Contains(lower, "missed"), strings.Contains(lower, "no answer"), strings.Contains(text, "未接"):
		return label + " 未接"
	default:
		return ""
	}
}

func looksLikeLegacyMojibakeCallText(text string) bool {
	if !(strings.Contains(text, legacyCallRequiredMarkerA) && strings.Contains(text, legacyCallRequiredMarkerB)) {
		return false
	}
	return strings.Contains(text, legacyVoiceCallMarkerA) ||
		strings.Contains(text, legacyVoiceCallMarkerB) ||
		strings.Contains(text, legacyVideoCallMarker) ||
		strings.Contains(text, legacyVideoCallMarkerB) ||
		strings.Contains(text, legacyVideoCallMarkerAlt)
}
