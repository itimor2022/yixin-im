package com.genericim.ma100

object LegacyTextRepair {
    private val callDurationPattern = Regex("""\d{1,2}:\d{2}(?::\d{2})?""")
    private val legacySystemSenderMojibake = stringFromCodePoints(0x7eef, 0x837b, 0x7cba, 0x5a11, 0x581f, 0x4f05)
    private val legacyVoiceCallMojibake = stringFromCodePoints(0x7487, 0xe162, 0x7176, 0x95ab, 0x6c33, 0x763d)
    private val legacyVideoCallMojibake = stringFromCodePoints(0x7459, 0x55db, 0xe576, 0x95ab, 0x6c33, 0x763d)
    private val legacyCallRequiredMarkerA = stringFromCodePoints(0x95ab)
    private val legacyCallRequiredMarkerB = stringFromCodePoints(0x763d)
    private val legacyVoiceCallMarkerA = stringFromCodePoints(0x7487)
    private val legacyVoiceCallMarkerB = stringFromCodePoints(0x7176)
    private val legacyVideoCallMarker = stringFromCodePoints(0x7459)
    private val legacyVideoCallMarkerB = stringFromCodePoints(0x55db)
    private val legacyVideoCallMarkerAlt = stringFromCodePoints(0xe576)

    fun repair(value: String?): String {
        var repaired = value?.trim().orEmpty()
        if (repaired.isBlank()) {
            return ""
        }

        repaired = repaired
            .replace(legacySystemSenderMojibake, "系统消息")
            .replace(legacyVoiceCallMojibake, "语音通话")
            .replace(legacyVideoCallMojibake, "视频通话")

        if (looksLikeLegacyCallText(repaired)) {
            val label = if (repaired.contains(legacyVideoCallMarker) || repaired.contains(legacyVideoCallMarkerAlt)) {
                "视频通话"
            } else {
                "语音通话"
            }
            val duration = callDurationPattern.find(repaired)?.value
            return if (duration.isNullOrBlank()) label else "$label $duration"
        }

        return repaired
    }

    private fun looksLikeLegacyCallText(value: String): Boolean {
        if (!value.contains(legacyCallRequiredMarkerA) || !value.contains(legacyCallRequiredMarkerB)) {
            return false
        }
        return value.contains(legacyVoiceCallMarkerA) ||
            value.contains(legacyVoiceCallMarkerB) ||
            value.contains(legacyVideoCallMarker) ||
            value.contains(legacyVideoCallMarkerB) ||
            value.contains(legacyVideoCallMarkerAlt)
    }

    private fun stringFromCodePoints(vararg codePoints: Int): String {
        return codePoints.joinToString(separator = "") { Character.toString(it) }
    }
}
