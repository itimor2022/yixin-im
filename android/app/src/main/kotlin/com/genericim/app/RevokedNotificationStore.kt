package com.genericim.ma100

import android.content.Context

/**
 * Short-lived tombstones stop an already queued vendor/native notification
 * tap from reopening content after that message notification was revoked.
 * A later notification for the same chat clears the tombstone.
 */
object RevokedNotificationStore {
    private const val preferencesName = "revoked_message_notifications"
    private const val ttlMillis = 24L * 60L * 60L * 1000L

    fun mark(context: Context, chatId: String, messageId: String = "") {
        val normalized = chatId.trim()
        if (normalized.isEmpty()) return
        val now = System.currentTimeMillis()
        val editor = preferences(context).edit().putLong(chatKey(normalized), now)
        val normalizedMessageId = messageId.trim()
        if (normalizedMessageId.isNotEmpty()) {
            editor.putLong(messageKey(normalized, normalizedMessageId), now)
        }
        editor.apply()
    }

    fun clear(context: Context, chatId: String) {
        val normalized = chatId.trim()
        if (normalized.isEmpty()) return
        preferences(context).edit().remove(chatKey(normalized)).apply()
    }

    fun isRevoked(context: Context, chatId: String, messageId: String = ""): Boolean {
        val normalized = chatId.trim()
        if (normalized.isEmpty()) return false
        val preferences = preferences(context)
        val normalizedMessageId = messageId.trim()
        val messageRevokedAt = if (normalizedMessageId.isEmpty()) {
            0L
        } else {
            preferences.getLong(messageKey(normalized, normalizedMessageId), 0L)
        }
        if (isFresh(messageRevokedAt)) return true
        if (messageRevokedAt > 0L) {
            preferences.edit().remove(messageKey(normalized, normalizedMessageId)).apply()
        }
        val revokedAt = preferences.getLong(chatKey(normalized), 0L)
        if (revokedAt <= 0L) return false
        if (isFresh(revokedAt)) return true
        preferences.edit().remove(chatKey(normalized)).apply()
        return false
    }

    fun wasRevokedAfter(context: Context, chatId: String, receivedAt: Long): Boolean {
        val normalized = chatId.trim()
        if (normalized.isEmpty()) return false
        return preferences(context).getLong(chatKey(normalized), 0L) >= receivedAt
    }

    private fun isFresh(timestamp: Long): Boolean =
        timestamp > 0L && System.currentTimeMillis() - timestamp <= ttlMillis

    private fun chatKey(chatId: String) = "chat:$chatId"
    private fun messageKey(chatId: String, messageId: String) = "message:$chatId:$messageId"

    private fun preferences(context: Context) = context.getSharedPreferences(
        preferencesName,
        Context.MODE_PRIVATE,
    )
}
