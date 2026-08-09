package com.genericim.app

import android.content.Context

object VendorPushStore {
    private const val prefsName = "vendor_push"
    private const val keyPendingChannel = "pending_channel"
    private const val keyPendingToken = "pending_token"

    fun savePendingToken(context: Context, channel: String, token: String) {
        if (channel.isBlank() || token.isBlank()) return
        context.applicationContext
            .getSharedPreferences(prefsName, Context.MODE_PRIVATE)
            .edit()
            .putString(keyPendingChannel, channel)
            .putString(keyPendingToken, token)
            .apply()
    }

    fun consumePendingToken(context: Context): Pair<String, String>? {
        val prefs = context.applicationContext.getSharedPreferences(prefsName, Context.MODE_PRIVATE)
        val channel = prefs.getString(keyPendingChannel, null)?.trim().orEmpty()
        val token = prefs.getString(keyPendingToken, null)?.trim().orEmpty()
        if (channel.isBlank() || token.isBlank()) return null

        prefs.edit()
            .remove(keyPendingChannel)
            .remove(keyPendingToken)
            .apply()
        return Pair(channel, token)
    }
}
