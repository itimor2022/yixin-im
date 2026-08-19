package com.genericim.ma100

import android.Manifest
import android.app.AppOpsManager
import android.content.Context
import android.content.pm.PackageManager
import android.os.Build
import android.os.Process
import androidx.core.app.NotificationManagerCompat
import androidx.core.content.ContextCompat

internal object AndroidNotificationPermission {
    fun runtimeGranted(context: Context): Boolean {
        return Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU ||
            ContextCompat.checkSelfPermission(
                context,
                Manifest.permission.POST_NOTIFICATIONS,
            ) == PackageManager.PERMISSION_GRANTED
    }

    fun systemEnabled(context: Context): Boolean {
        return NotificationManagerCompat.from(context).areNotificationsEnabled() &&
            appOpEnabled(context)
    }

    fun canPost(context: Context): Boolean {
        return runtimeGranted(context) && systemEnabled(context)
    }

    private fun appOpEnabled(context: Context): Boolean {
        val manager = context.getSystemService(Context.APP_OPS_SERVICE) as? AppOpsManager
            ?: return true
        val mode = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            manager.unsafeCheckOpNoThrow(
                postNotificationOp,
                Process.myUid(),
                context.packageName,
            )
        } else {
            @Suppress("DEPRECATION")
            manager.checkOpNoThrow(
                postNotificationOp,
                Process.myUid(),
                context.packageName,
            )
        }
        return mode == AppOpsManager.MODE_ALLOWED || mode == AppOpsManager.MODE_DEFAULT
    }

    private const val postNotificationOp = "android:post_notification"
}
