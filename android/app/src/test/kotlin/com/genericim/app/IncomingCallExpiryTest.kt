package com.genericim.app

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class IncomingCallExpiryTest {
    private val nowMillis = 1_752_667_200_000L // 2025-07-16T12:00:00Z

    @Test
    fun expiredRfc3339IncomingCallIsSuppressed() {
        val data = mapOf(
            "type" to "incoming_call",
            "expires_at" to "2025-07-16T11:59:59Z",
        )

        assertTrue(IncomingCallExpiry.isExpired(data, nowMillis))
        assertEquals(0L, IncomingCallExpiry.remainingMillis(data, nowMillis))
    }

    @Test
    fun liveRfc3339IncomingCallReturnsRemainingTtl() {
        val data = mapOf(
            "type" to "incoming_call",
            "expires_at" to "2025-07-16T12:00:30Z",
        )

        assertFalse(IncomingCallExpiry.isExpired(data, nowMillis))
        assertEquals(30_000L, IncomingCallExpiry.remainingMillis(data, nowMillis))
    }

    @Test
    fun supportsUnixSecondsAndMilliseconds() {
        val seconds = mapOf(
            "type" to "incoming_call",
            "expires_at" to "1752667230",
        )
        val milliseconds = mapOf(
            "type" to "incoming_call",
            "expires_at" to "1752667230000",
        )

        assertEquals(30_000L, IncomingCallExpiry.remainingMillis(seconds, nowMillis))
        assertEquals(30_000L, IncomingCallExpiry.remainingMillis(milliseconds, nowMillis))
    }

    @Test
    fun missingInvalidOrNonCallExpiryKeepsLegacyCompatibility() {
        assertFalse(IncomingCallExpiry.isExpired(mapOf("type" to "incoming_call"), nowMillis))
        assertFalse(
            IncomingCallExpiry.isExpired(
                mapOf("type" to "incoming_call", "expires_at" to "invalid"),
                nowMillis,
            ),
        )
        assertNull(
            IncomingCallExpiry.remainingMillis(
                mapOf("type" to "new_message", "expires_at" to "1752667199"),
                nowMillis,
            ),
        )
    }
}
