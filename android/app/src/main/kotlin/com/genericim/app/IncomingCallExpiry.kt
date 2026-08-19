package com.genericim.ma100

import java.time.Instant

object IncomingCallExpiry {
    private const val incomingCallType = "incoming_call"

    fun expiresAtMillis(data: Map<String, String>): Long? {
        if (data["type"]?.trim() != incomingCallType) return null
        val raw = data["expires_at"]?.trim().orEmpty()
        if (raw.isEmpty()) return null
        raw.toLongOrNull()?.let { numeric ->
            return if (numeric in 1..9_999_999_999L) numeric * 1000L else numeric
        }
        return try {
            Instant.parse(raw).toEpochMilli()
        } catch (_: Exception) {
            null
        }
    }

    fun isExpired(data: Map<String, String>, nowMillis: Long = System.currentTimeMillis()): Boolean {
        val expiresAt = expiresAtMillis(data) ?: return false
        return expiresAt <= nowMillis
    }

    fun remainingMillis(data: Map<String, String>, nowMillis: Long = System.currentTimeMillis()): Long? {
        val expiresAt = expiresAtMillis(data) ?: return null
        return (expiresAt - nowMillis).coerceAtLeast(0L)
    }
}
