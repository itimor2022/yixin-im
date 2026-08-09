package com.genericim.app

import android.content.Context

/**
 * Process-independent notification preferences used by vendor push services.
 *
 * Flutter keeps the account-scoped source of truth and mirrors the active
 * account's master switch here. This final native gate prevents an older push
 * backend from bypassing a user's local opt-out.
 */
object NotificationPreferenceStore {
    private const val preferencesName = "genericim_notification_preferences"
    private const val masterEnabledKey = "master_enabled"

    fun isMasterEnabled(context: Context): Boolean =
        context.getSharedPreferences(preferencesName, Context.MODE_PRIVATE)
            .getBoolean(masterEnabledKey, true)

    fun setMasterEnabled(context: Context, enabled: Boolean) {
        context.getSharedPreferences(preferencesName, Context.MODE_PRIVATE)
            .edit()
            .putBoolean(masterEnabledKey, enabled)
            .apply()
    }
}
