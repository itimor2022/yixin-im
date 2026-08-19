package com.genericim.ma100

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.os.Build
import android.os.Bundle
import android.util.Log
import androidx.core.app.NotificationCompat
import com.huawei.hms.push.HmsMessageService
import com.huawei.hms.push.RemoteMessage
import java.net.HttpURLConnection
import java.net.URL
import org.json.JSONObject

class GenericHmsMessageService : HmsMessageService() {
    override fun onNewToken(token: String?) {
        handleToken(token)
    }

    override fun onNewToken(token: String?, bundle: Bundle?) {
        handleToken(token)
    }

    override fun onMessageReceived(message: RemoteMessage?) {
        Log.i(tag, "HMS message received")
        val data = parseData(message)
        if (data["type"]?.trim() == revokedMessageType) {
            cancelRevokedMessageNotification(data)
            return
        }
        if (IncomingCallExpiry.isExpired(data)) {
            Log.i(tag, "HMS expired incoming call suppressed call=${data["call_id"]?.trim().orEmpty()}")
            return
        }
        showNotification(data)
    }

    private fun handleToken(token: String?) {
        val normalized = token?.trim().orEmpty()
        if (normalized.isBlank()) {
            Log.w(tag, "HMS token callback was empty")
            return
        }
        VendorPushStore.savePendingToken(applicationContext, "hms", normalized)
        Log.i(tag, "HMS token callback stored")
    }

    private fun parseData(message: RemoteMessage?): Map<String, String> {
        val out = linkedMapOf<String, String>()
        message?.dataOfMap?.forEach { (key, value) ->
            if (!key.isNullOrBlank() && value != null) {
                out[key] = value.toString()
            }
        }

        val rawData = message?.data?.trim().orEmpty()
        if (rawData.isNotBlank()) {
            try {
                val json = JSONObject(rawData)
                val keys = json.keys()
                while (keys.hasNext()) {
                    val key = keys.next()
                    if (key.isNotBlank() && !json.isNull(key)) {
                        out[key] = json.optString(key)
                    }
                }
            } catch (e: Exception) {
                Log.w(tag, "HMS data parse failed: ${e.message}")
            }
        }
        val notification = message?.notification
        if (notification != null) {
            val title = notification.title?.trim().orEmpty()
            val body = notification.body?.trim().orEmpty()
            val imageUrl = notification.imageUrl?.toString()?.trim().orEmpty()
            if (title.isNotBlank() && out["title"].isNullOrBlank()) {
                out["title"] = title
            }
            if (body.isNotBlank() && out["body"].isNullOrBlank()) {
                out["body"] = body
            }
            if (imageUrl.isNotBlank() && out["image_url"].isNullOrBlank()) {
                out["image_url"] = imageUrl
            }
        }
        return out
    }

    private fun showNotification(data: Map<String, String>) {
        if (!NotificationPreferenceStore.isMasterEnabled(applicationContext)) {
            Log.i(tag, "HMS notification skipped: master disabled")
            return
        }
        if (!canPostNotifications()) {
            Log.w(tag, "HMS notification skipped: notification permission denied")
            return
        }

        val receivedAt = System.currentTimeMillis()
        val imageUrl = notificationImageUrl(data)
        if (imageUrl.isNotBlank()) {
            Thread {
                showNotificationInternal(data, loadBitmap(imageUrl), receivedAt)
            }.start()
            return
        }

        showNotificationInternal(data, null, receivedAt)
    }

    private fun showNotificationInternal(data: Map<String, String>, picture: Bitmap?, receivedAt: Long) {
        if (!NotificationPreferenceStore.isMasterEnabled(applicationContext)) {
            Log.i(tag, "HMS notification skipped after load: master disabled")
            return
        }
        if (IncomingCallExpiry.isExpired(data)) {
            Log.i(tag, "HMS incoming call expired before display call=${data["call_id"]?.trim().orEmpty()}")
            return
        }
        val title = LegacyTextRepair.repair(data["title"]).takeIf { it.isNotBlank() }
            ?: applicationInfo.loadLabel(packageManager).toString()
        val body = LegacyTextRepair.repair(data["body"]).takeIf { it.isNotBlank() } ?: return
        val chatId = data["chat_id"]?.trim().orEmpty()
        if (RevokedNotificationStore.wasRevokedAfter(applicationContext, chatId, receivedAt)) {
            Log.i(tag, "HMS stale notification suppressed after revoke chat=$chatId")
            return
        }
        RevokedNotificationStore.clear(applicationContext, chatId)

        val channelId = notificationChannelId(data["type"]?.trim().orEmpty())
        ensureNotificationChannel(channelId)
        val notificationId = data["notification_id"]?.toIntOrNull()
            ?: (System.currentTimeMillis() % Int.MAX_VALUE).toInt()
        val pendingIntent = PendingIntent.getActivity(
            this,
            notificationId,
            buildLaunchIntent(data),
            PendingIntent.FLAG_UPDATE_CURRENT or immutablePendingIntentFlag(),
        )
        val builder = NotificationCompat.Builder(this, channelId)
            .setSmallIcon(R.drawable.ic_notification)
            .setContentTitle(title)
            .setContentText(body)
            .setPriority(NotificationCompat.PRIORITY_HIGH)
            .setDefaults(NotificationCompat.DEFAULT_ALL)
            .setAutoCancel(true)
            .setVisibility(NotificationCompat.VISIBILITY_PRIVATE)
            .setContentIntent(pendingIntent)
            .setExtras(notificationExtras(data))

        IncomingCallExpiry.remainingMillis(data)?.let { remainingMillis ->
            if (remainingMillis > 0L) {
                builder.setTimeoutAfter(remainingMillis)
            }
        }

        NotificationReplyAction.addTo(this, builder, notificationId, data)

        if (picture != null) {
            builder
                .setLargeIcon(picture)
                .setStyle(
                    NotificationCompat.BigPictureStyle()
                        .bigPicture(picture)
                        .setSummaryText(body),
                )
        } else {
            builder.setStyle(NotificationCompat.BigTextStyle().bigText(body))
        }

        val manager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        manager.notify(notificationId, builder.build())
        Log.i(tag, "HMS notification shown id=$notificationId")
    }

    private fun notificationExtras(data: Map<String, String>): Bundle {
        return Bundle().apply {
            for ((key, value) in data) {
                putString(key, value)
            }
        }
    }

    private fun cancelRevokedMessageNotification(data: Map<String, String>) {
        val manager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        val chatId = data["chat_id"]?.trim().orEmpty()
        val messageId = (data["message_id"] ?: data["msg_id"])?.trim().orEmpty()
        RevokedNotificationStore.mark(applicationContext, chatId, messageId)
        val notificationId = data["notification_id"]?.toIntOrNull()
        if (notificationId != null) {
            manager.cancel(notificationId)
            manager.cancel(
                AndroidNotificationIdentity.messageTag(notificationId),
                AndroidNotificationIdentity.fcmAutomaticNotificationId,
            )
        }

        // Older builds generated random IDs and did not persist chat_id. While
        // rolling out the stable-ID protocol, remove those unscoped message
        // notifications as a privacy-safe fallback.
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            for (active in manager.activeNotifications) {
                val notification = active.notification
                if (notification.channelId != messageChannelId) continue
                val activeChatId = notification.extras?.getString("chat_id")?.trim().orEmpty()
                if (activeChatId.isEmpty() || activeChatId == chatId) {
                    manager.cancel(active.tag, active.id)
                }
            }
        }
        Log.i(tag, "HMS revoked-message notification cancelled id=$notificationId")
    }

    private fun notificationImageUrl(data: Map<String, String>): String {
        val keys = listOf("image_url", "thumbnail", "media_url", "image", "last_msg_media_url")
        for (key in keys) {
            val value = data[key]?.trim().orEmpty()
            if (value.startsWith("http://") || value.startsWith("https://")) {
                return value
            }
        }
        return ""
    }

    private fun loadBitmap(imageUrl: String): Bitmap? {
        return try {
            val connection = URL(imageUrl).openConnection() as HttpURLConnection
            connection.connectTimeout = 4000
            connection.readTimeout = 4000
            connection.instanceFollowRedirects = true
            connection.inputStream.use { input ->
                BitmapFactory.decodeStream(input)
            }
        } catch (e: Exception) {
            Log.w(tag, "HMS notification image load failed: ${e.message}")
            null
        }
    }

    private fun buildLaunchIntent(data: Map<String, String>): Intent {
        val intent = packageManager.getLaunchIntentForPackage(packageName)
            ?: Intent(this, MainActivity::class.java)
        intent.addFlags(Intent.FLAG_ACTIVITY_CLEAR_TOP or Intent.FLAG_ACTIVITY_SINGLE_TOP)
        intent.putExtra("push_tap", "hms")
        for ((key, value) in data) {
            intent.putExtra(key, value)
        }
        return intent
    }

    private fun ensureNotificationChannel(channelId: String) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) {
            return
        }
        val manager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        if (manager.getNotificationChannel(channelId) != null) {
            return
        }
        val channelName = when (channelId) {
            announcementChannelId -> "群公告通知"
            callChannelId -> "来电通知"
            meetingChannelId -> "会议通知"
            else -> "消息通知"
        }
        val channel = NotificationChannel(
            channelId,
            channelName,
            NotificationManager.IMPORTANCE_HIGH,
        ).apply {
            description = when (channelId) {
                announcementChannelId -> "群聊和系统公告"
                callChannelId -> "语音和视频通话来电"
                meetingChannelId -> "会议邀请和会议状态"
                else -> "私聊、群聊和频道消息"
            }
            setShowBadge(true)
            enableVibration(true)
        }
        manager.createNotificationChannel(channel)
    }

    private fun canPostNotifications(): Boolean {
        return AndroidNotificationPermission.canPost(this)
    }

    private fun notificationChannelId(type: String): String {
        return when (type) {
            "chat_announcement", "system_announcement", "group_notice" -> announcementChannelId
            "incoming_call", "call_missed", "missed_call" -> callChannelId
            "meeting_invite", "meeting_join_request", "meeting_join_request_reviewed", "meeting_status" -> meetingChannelId
            else -> messageChannelId
        }
    }

    private fun immutablePendingIntentFlag(): Int {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            PendingIntent.FLAG_IMMUTABLE
        } else {
            0
        }
    }

    companion object {
        private const val tag = "GenericIMHmsPush"
        private const val messageChannelId = "genericim_messages"
        private const val announcementChannelId = "genericim_announcements_v1"
        private const val callChannelId = "genericim_calls_v1"
        private const val meetingChannelId = "genericim_meetings_v1"
        private const val revokedMessageType = "message_revoked"
    }
}
