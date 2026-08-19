package com.genericim.ma100

object AndroidNotificationIdentity {
    const val fcmAutomaticNotificationId = 0

    fun messageTag(notificationId: Int): String {
        return "genericim-message-$notificationId"
    }
}
