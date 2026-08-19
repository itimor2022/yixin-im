package com.genericim.ma100

import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import androidx.core.app.NotificationCompat
import androidx.core.app.RemoteInput
import java.util.UUID

object NotificationReplyAction {
    private const val replyResultKey = "notification_reply_text"

    fun addTo(
        context: Context,
        builder: NotificationCompat.Builder,
        notificationId: Int,
        data: Map<String, String>,
    ) {
        if (data["type"]?.trim() != "new_message") return
        val chatId = data["chat_id"]?.trim().orEmpty()
        if (chatId.isEmpty()) return

        // Use an Activity PendingIntent directly. Modern Android/Huawei builds
        // may reject startActivity() when it is attempted later from a
        // background BroadcastReceiver, even though the receiver originated
        // from a visible notification action.
        val intent = Intent(context, MainActivity::class.java).apply {
            action = "com.genericim.ma100.action.NOTIFICATION_REPLY"
            // Keep every RemoteInput dispatch distinct so Huawei delivers a
            // fresh onNewIntent instead of only reusing the task.
            this.data = Uri.parse(
                "genericim-notification-reply://send/$notificationId/${UUID.randomUUID()}",
            )
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP or Intent.FLAG_ACTIVITY_SINGLE_TOP)
            putExtra("type", "notification_reply")
            putExtra("chat_id", chatId)
            putExtra("chat_type", data["chat_type"]?.trim().orEmpty())
            putExtra("client_msg_id", UUID.randomUUID().toString())
            putExtra("notification_id", notificationId)
            putExtra("push_tap", "notification_reply")
        }
        val pendingIntent = PendingIntent.getActivity(
            context,
            notificationId + 1,
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or mutablePendingIntentFlag(),
        )
        val remoteInput = RemoteInput.Builder(replyResultKey)
            .setLabel("回复")
            .build()
        builder.addAction(
            NotificationCompat.Action.Builder(
                android.R.drawable.ic_menu_send,
                "回复",
                pendingIntent,
            )
                .addRemoteInput(remoteInput)
                .setAllowGeneratedReplies(true)
                .setSemanticAction(NotificationCompat.Action.SEMANTIC_ACTION_REPLY)
                .build(),
        )
    }

    fun replyText(intent: Intent): String =
        RemoteInput.getResultsFromIntent(intent)
            ?.getCharSequence(replyResultKey)
            ?.toString()
            ?.trim()
            .orEmpty()

    private fun mutablePendingIntentFlag(): Int =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) PendingIntent.FLAG_MUTABLE else 0
}
