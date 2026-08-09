package com.genericim.app

import android.Manifest
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.KeyguardManager
import android.app.ActivityManager
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.ClipData
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.os.PowerManager
import android.provider.Settings
import android.util.Log
import android.webkit.MimeTypeMap
import android.view.WindowManager
import androidx.core.app.NotificationCompat
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.lang.reflect.Proxy
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors
import org.json.JSONObject

class MainActivity : FlutterFragmentActivity() {
    private val notificationPermissionRequestCode = 9101
    private val hotUpdateChannelName = "com.genericim/hot_update"
    private val pushVendorChannelName = "com.genericim/push_vendor"
    private val settingsChannelName = "com.genericim/settings"
    private val messageNotificationChannelName = "com.genericim/message_notifications"
    private val deepLinkChannelName = "com.genericim/deep_link"
    private val fileOpenChannelName = "com.genericim/file_open"

    private var pushVendorChannel: MethodChannel? = null
    private var deepLinkChannel: MethodChannel? = null
    private var voiceProximityBridge: VoiceProximityBridge? = null
    private var pendingDeepLink: String? = null
    private var pendingNotificationPermissionResult: MethodChannel.Result? = null
    private var pendingNotificationTap: Map<String, Any>? = null
    private var isActivityResumed = false
    private var oppoCallbackProxy: Any? = null
    private val pushExecutor: ExecutorService = Executors.newSingleThreadExecutor()
    private val mainHandler = Handler(Looper.getMainLooper())
    private val notificationReplyTraceLock = Any()

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        setupHotUpdateChannel(flutterEngine)
        setupPushVendorChannel(flutterEngine)
        setupSettingsChannel(flutterEngine)
        setupMessageNotificationChannel(flutterEngine)
        setupDeepLinkChannel(flutterEngine)
        setupFileOpenChannel(flutterEngine)
        voiceProximityBridge = VoiceProximityBridge(
            this,
            flutterEngine.dartExecutor.binaryMessenger,
        )
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        captureDeepLink(intent, emitToFlutter = false)
        captureNotificationTap(intent, emitToFlutter = false)
        super.onCreate(savedInstanceState)
        createNotificationChannel()
        setupHighRefreshRate()
        mainHandler.postDelayed({ emitPendingNotificationTap() }, 800)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        captureDeepLink(intent, emitToFlutter = true)
        captureNotificationTap(intent, emitToFlutter = true)
    }

    override fun onResume() {
        super.onResume()
        isActivityResumed = true
    }

    override fun onPause() {
        isActivityResumed = false
        super.onPause()
    }

    override fun onDestroy() {
        pendingNotificationPermissionResult?.success(false)
        pendingNotificationPermissionResult = null
        pushExecutor.shutdownNow()
        oppoCallbackProxy = null
        pushVendorChannel = null
        deepLinkChannel = null
        voiceProximityBridge?.dispose()
        voiceProximityBridge = null
        super.onDestroy()
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray,
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == notificationPermissionRequestCode) {
            val granted = grantResults.isNotEmpty() && grantResults[0] == PackageManager.PERMISSION_GRANTED
            pendingNotificationPermissionResult?.success(granted)
            pendingNotificationPermissionResult = null
        }
    }

    private fun setupHotUpdateChannel(flutterEngine: FlutterEngine) {
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, hotUpdateChannelName)
            .setMethodCallHandler { call: MethodCall, result: MethodChannel.Result ->
                when (call.method) {
                    "isSupported" -> {
                        result.success(
                            mapOf(
                                "available" to true,
                                "sdkIntegrated" to true,
                                "platform" to "android",
                                "message" to "self_hosted_updater_ready",
                            ),
                        )
                    }

                    "applyPatch" -> {
                        result.success(applyAndroidPatch(call.arguments))
                    }

                    else -> result.notImplemented()
                }
            }
    }

    private fun setupPushVendorChannel(flutterEngine: FlutterEngine) {
        pushVendorChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, pushVendorChannelName)
        pushVendorChannel?.setMethodCallHandler { call: MethodCall, result: MethodChannel.Result ->
            when (call.method) {
                "initializeVendorPush" -> {
                    val manufacturer = (Build.MANUFACTURER ?: "").lowercase()
                    val brand = (Build.BRAND ?: "").lowercase()
                    val preferredChannel = resolvePreferredPushChannel(manufacturer, brand)
                    val sdkAvailable = mapOf(
                        "fcm" to true,
                        "hms" to isClassAvailable("com.huawei.hms.aaid.HmsInstanceId"),
                        "jpush" to isClassAvailable("cn.jpush.android.api.JPushInterface"),
                        "xiaomi" to isClassAvailable("com.xiaomi.mipush.sdk.MiPushClient"),
                        "oppo" to isClassAvailable("com.heytap.msp.push.HeytapPushManager"),
                    )
                    val configReady = mapOf(
                        "hms" to readHmsAppId().isNotBlank(),
                        "jpush" to readMetaData("PUSH_JPUSH_APP_KEY").isNotBlank(),
                        "xiaomi" to (readMetaData("PUSH_XIAOMI_APP_ID").isNotBlank() &&
                            readMetaData("PUSH_XIAOMI_APP_KEY").isNotBlank()),
                        "oppo" to (readMetaData("PUSH_OPPO_APP_KEY").isNotBlank() &&
                            readMetaData("PUSH_OPPO_APP_SECRET").isNotBlank()),
                    )

                    var autoRequested = false
                    if (preferredChannel != "fcm") {
                        val request = requestVendorToken(preferredChannel)
                        autoRequested = request.first
                    }

                    result.success(
                        mapOf(
                            "integrated" to autoRequested,
                            "manufacturer" to manufacturer,
                            "brand" to brand,
                            "preferred_channel" to preferredChannel,
                            "supported_channels" to listOf("fcm", "hms", "jpush", "xiaomi", "oppo"),
                            "sdk_available" to sdkAvailable,
                            "config_ready" to configReady,
                            "message" to "vendor_push_init_completed",
                        ),
                    )
                    mainHandler.post { emitPendingVendorToken() }
                }

                "getPreferredPushChannel" -> {
                    val manufacturer = (Build.MANUFACTURER ?: "").lowercase()
                    val brand = (Build.BRAND ?: "").lowercase()
                    result.success(resolvePreferredPushChannel(manufacturer, brand))
                }

                "requestVendorToken" -> {
                    val requestedChannel = ((call.arguments as? Map<*, *>)?.get("channel") as? String)
                        ?.trim()?.lowercase().orEmpty()
                    val channel = if (requestedChannel.isNotBlank()) {
                        requestedChannel
                    } else {
                        resolvePreferredPushChannel(
                            (Build.MANUFACTURER ?: "").lowercase(),
                            (Build.BRAND ?: "").lowercase(),
                        )
                    }
                    val request = requestVendorToken(channel)
                    result.success(
                        mapOf(
                            "started" to request.first,
                            "channel" to channel,
                            "message" to request.second,
                        ),
                    )
                }

                "consumePendingVendorToken" -> {
                    val pending = VendorPushStore.consumePendingToken(applicationContext)
                    result.success(
                        if (pending == null) {
                            null
                        } else {
                            mapOf(
                                "channel" to pending.first,
                                "token" to pending.second,
                            )
                        },
                    )
                }

                "consumePendingNotificationTap" -> {
                    result.success(consumePendingNotificationTap())
                }

                "recordNotificationReplyTrace" -> {
                    val payload = call.arguments as? Map<*, *>
                    result.success(
                        recordNotificationReplyTrace(
                            payload?.get("stage")?.toString().orEmpty(),
                            payload,
                        ),
                    )
                }

                "getVendorSdkStatus" -> {
                    result.success(
                        mapOf(
                            "hms" to isClassAvailable("com.huawei.hms.aaid.HmsInstanceId"),
                            "jpush" to isClassAvailable("cn.jpush.android.api.JPushInterface"),
                            "xiaomi" to isClassAvailable("com.xiaomi.mipush.sdk.MiPushClient"),
                            "oppo" to isClassAvailable("com.heytap.msp.push.HeytapPushManager"),
                        ),
                    )
                }

                else -> result.notImplemented()
            }
        }
    }

    private fun setupSettingsChannel(flutterEngine: FlutterEngine) {
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, settingsChannelName)
            .setMethodCallHandler { call: MethodCall, result: MethodChannel.Result ->
                when (call.method) {
                    "getNotificationPermissionStatus" -> result.success(notificationPermissionStatus())
                    "getBackgroundRestrictionStatus" -> result.success(backgroundRestrictionStatus())
                    "requestNotificationPermission" -> requestNotificationPermission(result)
                    "openNotificationSettings" -> result.success(openNotificationSettings())
                    "openBatterySettings" -> result.success(openBatterySettings())
                    "openAutoStartSettings" -> result.success(openAutoStartSettings())
                    else -> result.notImplemented()
                }
            }
    }

    private fun setupMessageNotificationChannel(flutterEngine: FlutterEngine) {
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, messageNotificationChannelName)
            .setMethodCallHandler { call: MethodCall, result: MethodChannel.Result ->
                when (call.method) {
                    "showMessageNotification" -> result.success(showNativeMessageNotification(call.arguments))
                    "cancelMessageNotification" -> result.success(cancelNativeMessageNotification(call.arguments))
                    "setNotificationMasterEnabled" -> {
                        val enabled = (call.arguments as? Map<*, *>)?.get("enabled") == true
                        NotificationPreferenceStore.setMasterEnabled(applicationContext, enabled)
                        result.success(mapOf("updated" to true, "enabled" to enabled))
                    }
                    else -> result.notImplemented()
                }
            }
    }

    private fun setupDeepLinkChannel(flutterEngine: FlutterEngine) {
        deepLinkChannel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            deepLinkChannelName,
        )
        deepLinkChannel?.setMethodCallHandler { call: MethodCall, result: MethodChannel.Result ->
            when (call.method) {
                "getInitialLink" -> {
                    result.success(pendingDeepLink)
                    pendingDeepLink = null
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun setupFileOpenChannel(flutterEngine: FlutterEngine) {
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, fileOpenChannelName)
            .setMethodCallHandler { call: MethodCall, result: MethodChannel.Result ->
                when (call.method) {
                    "openFile" -> result.success(openLocalFile(call.arguments))
                    else -> result.notImplemented()
                }
            }
    }

    private fun openLocalFile(arguments: Any?): Map<String, Any> {
        val payload = arguments as? Map<*, *> ?: return mapOf(
            "opened" to false,
            "reason" to "invalid_arguments",
        )
        val rawPath = payload["path"]?.toString()?.trim().orEmpty()
        val fileName = payload["file_name"]?.toString()?.trim().orEmpty()
        if (rawPath.isBlank()) {
            return mapOf("opened" to false, "reason" to "invalid_path")
        }

        return try {
            val file = File(rawPath).canonicalFile
            val allowedRoots = buildList {
                add(filesDir.canonicalFile)
                add(cacheDir.canonicalFile)
                getExternalFilesDirs(null).filterNotNull().forEach { add(it.canonicalFile) }
                externalCacheDirs.filterNotNull().forEach { add(it.canonicalFile) }
            }
            val isOwnedFile = allowedRoots.any { root ->
                file.path == root.path || file.path.startsWith(root.path + File.separator)
            }
            if (!file.exists() || !file.isFile || !isOwnedFile) {
                return mapOf("opened" to false, "reason" to "file_unavailable")
            }

            val displayName = fileName.ifBlank { file.name }
            val extension = displayName.substringAfterLast('.', "").lowercase()
            val mimeType = MimeTypeMap.getSingleton()
                .getMimeTypeFromExtension(extension)
                ?: when (extension) {
                    "zip" -> "application/zip"
                    "rar" -> "application/vnd.rar"
                    "7z" -> "application/x-7z-compressed"
                    else -> "application/octet-stream"
                }
            val uri = FileProvider.getUriForFile(
                this,
                "$packageName.provider",
                file,
            )
            val viewIntent = Intent(Intent.ACTION_VIEW).apply {
                setDataAndType(uri, mimeType)
                clipData = ClipData.newRawUri(displayName, uri)
                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
            }
            if (viewIntent.resolveActivity(packageManager) == null) {
                return mapOf("opened" to false, "reason" to "no_handler")
            }
            val chooser = Intent.createChooser(viewIntent, "选择打开方式").apply {
                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
            }
            startActivity(chooser)
            mapOf("opened" to true, "reason" to "chooser_started", "mime_type" to mimeType)
        } catch (error: Exception) {
            Log.w("GenericIMFileOpen", "open file failed", error)
            mapOf("opened" to false, "reason" to "open_failed")
        }
    }

    private fun captureDeepLink(intent: Intent?, emitToFlutter: Boolean) {
        val rawLink = intent?.dataString?.trim().orEmpty()
        if (!rawLink.startsWith("genericim://", ignoreCase = true)) return
        pendingDeepLink = rawLink
        if (emitToFlutter) {
            deepLinkChannel?.invokeMethod("onLink", rawLink)
        }
    }

    private fun showNativeMessageNotification(arguments: Any?): Map<String, Any> {
        if (!NotificationPreferenceStore.isMasterEnabled(applicationContext)) {
            Log.i(nativeNotificationTag, "message notification skipped: master disabled")
            return mapOf("shown" to false, "reason" to "master_disabled")
        }
        if (!canPostNotifications()) {
            Log.w(nativeNotificationTag, "message notification skipped: permission denied")
            return mapOf("shown" to false, "reason" to "permission_denied")
        }

        val payload = arguments as? Map<*, *> ?: return mapOf(
            "shown" to false,
            "reason" to "invalid_arguments",
        )
        val chatId = payload["chat_id"]?.toString()?.trim().orEmpty()
        val messageId = payload["message_id"]?.toString()?.trim().orEmpty()
        val activeChatMatches = payload["active_chat_matches"] == true ||
            payload["active_chat_matches"]?.toString()?.toBooleanStrictOrNull() == true
        if (activeChatMatches && isCurrentChatActuallyVisible()) {
            Log.i(nativeNotificationTag, "message notification suppressed: visible chat=$chatId")
            return mapOf("shown" to false, "reason" to "active_chat_visible")
        }
        RevokedNotificationStore.clear(applicationContext, chatId)
        val title = LegacyTextRepair.repair(payload["title"]?.toString()).ifBlank {
            applicationInfo.loadLabel(packageManager).toString()
        }
        val body = LegacyTextRepair.repair(payload["body"]?.toString())
        if (body.isBlank()) {
            Log.w(nativeNotificationTag, "message notification skipped: empty body")
            return mapOf("shown" to false, "reason" to "empty_body")
        }

        createNotificationChannel()
        val notificationId = nativeMessageNotificationId(chatId)
        val intent = packageManager.getLaunchIntentForPackage(packageName)
            ?: Intent(this, MainActivity::class.java)
        intent.addFlags(Intent.FLAG_ACTIVITY_CLEAR_TOP or Intent.FLAG_ACTIVITY_SINGLE_TOP)
        intent.putExtra("push_tap", "native_message")
        if (chatId.isNotBlank()) {
            intent.putExtra("type", "new_message")
            intent.putExtra("chat_id", chatId)
            intent.putExtra("chat_type", payload["chat_type"]?.toString()?.trim().orEmpty())
            if (messageId.isNotBlank()) intent.putExtra("message_id", messageId)
        }
        val pendingIntent = PendingIntent.getActivity(
            this,
            notificationId,
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or immutablePendingIntentFlag(),
        )

        val unreadCount = (payload["unread_count"] as? Number)?.toInt()
            ?: payload["unread_count"]?.toString()?.toIntOrNull()
        val builder = NotificationCompat.Builder(this, messageChannelId)
            .setSmallIcon(R.drawable.ic_notification)
            .setContentTitle(title)
            .setContentText(body)
            .setStyle(NotificationCompat.BigTextStyle().bigText(body))
            .setPriority(NotificationCompat.PRIORITY_HIGH)
            .setCategory(NotificationCompat.CATEGORY_MESSAGE)
            .setDefaults(NotificationCompat.DEFAULT_ALL)
            .setAutoCancel(true)
            .setShowWhen(true)
            .setVisibility(NotificationCompat.VISIBILITY_PRIVATE)
            .setContentIntent(pendingIntent)
            .setExtras(Bundle().apply { putString("chat_id", chatId) })
            .apply {
                if (unreadCount != null && unreadCount > 0) {
                    setNumber(unreadCount)
                }
            }
        NotificationReplyAction.addTo(
            this,
            builder,
            notificationId,
            mapOf(
                "type" to "new_message",
                "chat_id" to chatId,
                "chat_type" to payload["chat_type"]?.toString()?.trim().orEmpty(),
            ),
        )
        val notification = builder.build()

        val manager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        manager.notify(notificationId, notification)
        Log.i(nativeNotificationTag, "message notification shown id=$notificationId chat=$chatId")
        return mapOf("shown" to true, "notification_id" to notificationId)
    }

    private fun cancelNativeMessageNotification(arguments: Any?): Map<String, Any> {
        val payload = arguments as? Map<*, *> ?: return mapOf(
            "cancelled" to false,
            "reason" to "invalid_arguments",
        )
        val chatId = payload["chat_id"]?.toString()?.trim().orEmpty()
        val messageId = payload["message_id"]?.toString()?.trim().orEmpty()
        val markRevoked = payload["mark_revoked"] != false &&
            payload["mark_revoked"]?.toString()?.toBooleanStrictOrNull() != false
        if (chatId.isBlank()) {
            return mapOf("cancelled" to false, "reason" to "invalid_chat_id")
        }

        val notificationId = nativeMessageNotificationId(chatId)
        val manager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        manager.cancel(notificationId)
        manager.cancel(
            AndroidNotificationIdentity.messageTag(notificationId),
            AndroidNotificationIdentity.fcmAutomaticNotificationId,
        )
        if (markRevoked) {
            RevokedNotificationStore.mark(applicationContext, chatId, messageId)
        }
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
        Log.i(nativeNotificationTag, "message notification cancelled id=$notificationId chat=$chatId")
        return mapOf("cancelled" to true, "notification_id" to notificationId)
    }

    private fun requestNotificationPermission(result: MethodChannel.Result) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU) {
            result.success(canPostNotifications())
            return
        }

        if (ContextCompat.checkSelfPermission(
                this,
                Manifest.permission.POST_NOTIFICATIONS,
            ) == PackageManager.PERMISSION_GRANTED
        ) {
            result.success(canPostNotifications())
            return
        }

        pendingNotificationPermissionResult?.success(false)
        pendingNotificationPermissionResult = result
        ActivityCompat.requestPermissions(
            this,
            arrayOf(Manifest.permission.POST_NOTIFICATIONS),
            notificationPermissionRequestCode,
        )
    }

    private fun canPostNotifications(): Boolean {
        return AndroidNotificationPermission.canPost(this)
    }

    private fun notificationPermissionStatus(): Map<String, Any> {
        val runtimeGranted = AndroidNotificationPermission.runtimeGranted(this)
        val systemEnabled = AndroidNotificationPermission.systemEnabled(this)
        return mapOf(
            "runtime_granted" to runtimeGranted,
            "system_enabled" to systemEnabled,
            "enabled" to (runtimeGranted && systemEnabled),
        )
    }

    private fun isCurrentChatActuallyVisible(): Boolean {
        val power = getSystemService(Context.POWER_SERVICE) as PowerManager
        val keyguard = getSystemService(Context.KEYGUARD_SERVICE) as KeyguardManager
        return isActivityResumed && power.isInteractive && !keyguard.isKeyguardLocked
    }

    private fun backgroundRestrictionStatus(): Map<String, Any> {
        val power = getSystemService(Context.POWER_SERVICE) as PowerManager
        val activity = getSystemService(Context.ACTIVITY_SERVICE) as ActivityManager
        return mapOf(
            "ignoring_battery_optimizations" to power.isIgnoringBatteryOptimizations(packageName),
            "background_restricted" to if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                activity.isBackgroundRestricted
            } else {
                false
            },
        )
    }

    private fun openNotificationSettings(): Boolean {
        return try {
            val intent = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                Intent(Settings.ACTION_APP_NOTIFICATION_SETTINGS).apply {
                    putExtra(Settings.EXTRA_APP_PACKAGE, packageName)
                }
            } else {
                Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS).apply {
                    data = Uri.parse("package:$packageName")
                }
            }
            intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            startActivity(intent)
            true
        } catch (_: Exception) {
            try {
                val fallback = Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS).apply {
                    data = Uri.parse("package:$packageName")
                    addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                }
                startActivity(fallback)
                true
            } catch (_: Exception) {
                false
            }
        }
    }

    private fun openBatterySettings(): Boolean {
        val intents = listOf(
            Intent(Settings.ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS),
            Intent(Settings.ACTION_BATTERY_SAVER_SETTINGS),
            Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS).apply {
                data = Uri.parse("package:$packageName")
            },
        )
        return startFirstAvailable(intents)
    }

    private fun openAutoStartSettings(): Boolean {
        val manufacturer = (Build.MANUFACTURER ?: "").lowercase()
        val intents = mutableListOf<Intent>()

        when {
            manufacturer.contains("huawei") || manufacturer.contains("honor") -> {
                intents += componentIntent(
                    "com.huawei.systemmanager",
                    "com.huawei.systemmanager.startupmgr.ui.StartupNormalAppListActivity",
                )
                intents += componentIntent(
                    "com.huawei.systemmanager",
                    "com.huawei.systemmanager.optimize.process.ProtectActivity",
                )
            }
            manufacturer.contains("xiaomi") || manufacturer.contains("redmi") -> {
                intents += componentIntent(
                    "com.miui.securitycenter",
                    "com.miui.permcenter.autostart.AutoStartManagementActivity",
                )
                intents += componentIntent(
                    "com.miui.powerkeeper",
                    "com.miui.powerkeeper.ui.HiddenAppsConfigActivity",
                )
            }
            manufacturer.contains("oppo") || manufacturer.contains("oneplus") || manufacturer.contains("realme") -> {
                intents += componentIntent(
                    "com.coloros.safecenter",
                    "com.coloros.safecenter.permission.startup.StartupAppListActivity",
                )
                intents += componentIntent(
                    "com.oplus.battery",
                    "com.oplus.powermanager.fuelgaue.PowerUsageModelActivity",
                )
            }
            manufacturer.contains("vivo") || manufacturer.contains("iqoo") -> {
                intents += componentIntent(
                    "com.iqoo.secure",
                    "com.iqoo.secure.ui.phoneoptimize.AddWhiteListActivity",
                )
                intents += componentIntent(
                    "com.vivo.permissionmanager",
                    "com.vivo.permissionmanager.activity.BgStartUpManagerActivity",
                )
            }
            manufacturer.contains("samsung") -> {
                intents += Intent("com.samsung.android.sm.ACTION_BATTERY").setPackage("com.samsung.android.lool")
            }
        }

        intents += Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS).apply {
            data = Uri.parse("package:$packageName")
        }
        return startFirstAvailable(intents)
    }

    private fun componentIntent(packageName: String, className: String): Intent {
        return Intent().apply {
            component = ComponentName(packageName, className)
        }
    }

    private fun startFirstAvailable(intents: List<Intent>): Boolean {
        for (intent in intents) {
            try {
                intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                startActivity(intent)
                return true
            } catch (_: Exception) {
            }
        }
        return false
    }

    private fun applyAndroidPatch(arguments: Any?): Map<String, Any> {
        val payload = arguments as? Map<*, *>
        if (payload == null) {
            return mapOf(
                "success" to false,
                "requires_restart" to false,
                "message" to "patch_params_invalid",
            )
        }

        val localFilePath = payload["local_file_path"]?.toString()?.trim().orEmpty()
        val patchUrl = payload["patch_url"]?.toString()?.trim().orEmpty()

        return when {
            localFilePath.isNotBlank() -> installDownloadedApk(localFilePath)
            patchUrl.isNotBlank() -> openPatchUrl(patchUrl)
            else -> mapOf(
                "success" to false,
                "requires_restart" to false,
                "message" to "patch_url_missing",
            )
        }
    }

    private fun installDownloadedApk(localFilePath: String): Map<String, Any> {
        val file = File(localFilePath)
        if (!file.exists() || !file.isFile) {
            return mapOf(
                "success" to false,
                "requires_restart" to false,
                "message" to "patch_file_missing",
            )
        }

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O && !packageManager.canRequestPackageInstalls()) {
            return if (openUnknownAppsSettings()) {
                mapOf(
                    "success" to false,
                    "requires_restart" to false,
                    "message" to "android_install_permission_required",
                )
            } else {
                mapOf(
                    "success" to false,
                    "requires_restart" to false,
                    "message" to "android_install_permission_settings_failed",
                )
            }
        }

        return try {
            val authority = "$packageName.hotupdate.fileprovider"
            val uri = FileProvider.getUriForFile(this, authority, file)
            val intent = Intent(Intent.ACTION_VIEW).apply {
                setDataAndType(uri, "application/vnd.android.package-archive")
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                putExtra(Intent.EXTRA_NOT_UNKNOWN_SOURCE, true)
                putExtra(Intent.EXTRA_INSTALLER_PACKAGE_NAME, packageName)
            }

            if (intent.resolveActivity(packageManager) == null) {
                mapOf(
                    "success" to false,
                    "requires_restart" to false,
                    "message" to "android_installer_not_found",
                )
            } else {
                startActivity(intent)
                mapOf(
                    "success" to true,
                    "requires_restart" to true,
                    "message" to "android_installer_opened",
                )
            }
        } catch (t: Throwable) {
            mapOf(
                "success" to false,
                "requires_restart" to false,
                "message" to "android_installer_launch_failed:${t.message ?: "unknown"}",
            )
        }
    }

    private fun openPatchUrl(rawUrl: String): Map<String, Any> {
        val uri = runCatching { Uri.parse(rawUrl) }.getOrNull()
            ?: return mapOf(
                "success" to false,
                "requires_restart" to false,
                "message" to "patch_url_invalid",
            )
        if (uri.scheme?.lowercase() != "https" ||
            uri.host.isNullOrBlank() ||
            !uri.userInfo.isNullOrBlank() ||
            !(uri.path ?: "").lowercase().endsWith(".apk")
        ) {
            return mapOf(
                "success" to false,
                "requires_restart" to false,
                "message" to "patch_url_invalid",
            )
        }

        return try {
            val intent = Intent(Intent.ACTION_VIEW, uri).apply {
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            }
            if (intent.resolveActivity(packageManager) == null) {
                mapOf(
                    "success" to false,
                    "requires_restart" to false,
                    "message" to "patch_url_open_failed",
                )
            } else {
                startActivity(intent)
                mapOf(
                    "success" to true,
                    "requires_restart" to true,
                    "message" to "android_external_update_opened",
                )
            }
        } catch (t: Throwable) {
            mapOf(
                "success" to false,
                "requires_restart" to false,
                "message" to "patch_url_open_failed:${t.message ?: "unknown"}",
            )
        }
    }

    private fun openUnknownAppsSettings(): Boolean {
        return try {
            val intent = Intent(
                Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES,
                Uri.parse("package:$packageName"),
            ).apply {
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            }
            startActivity(intent)
            true
        } catch (_: Throwable) {
            false
        }
    }

    private fun requestVendorToken(channel: String): Pair<Boolean, String> {
        return when (channel) {
            "hms" -> requestHmsToken()
            "jpush" -> requestJPushToken()
            "xiaomi" -> requestXiaomiToken()
            "oppo" -> requestOppoToken()
            "fcm" -> Pair(false, "fcm_managed_by_flutter_firebase")
            else -> Pair(false, "unsupported_channel")
        }
    }

    private fun requestHmsToken(): Pair<Boolean, String> {
        if (!isClassAvailable("com.huawei.hms.aaid.HmsInstanceId")) {
            return Pair(false, "hms_sdk_not_found")
        }

        val appId = readHmsAppId()
        if (appId.isBlank()) {
            return Pair(false, "hms_app_id_not_configured")
        }

        pushExecutor.execute {
            try {
                val clazz = Class.forName("com.huawei.hms.aaid.HmsInstanceId")
                val getInstance = clazz.getMethod("getInstance", Context::class.java)
                val instance = getInstance.invoke(null, applicationContext)
                val getToken = clazz.getMethod("getToken", String::class.java, String::class.java)
                val token = getToken.invoke(instance, appId, "HCM") as? String
                if (!token.isNullOrBlank()) {
                    notifyVendorToken("hms", token)
                } else {
                    notifyVendorRegistrationFailed("hms", "hms_token_empty")
                }
            } catch (t: Throwable) {
                notifyVendorRegistrationFailed("hms", "hms_token_error:${t.message ?: "unknown"}")
            }
        }
        return Pair(true, "hms_token_request_started")
    }

    private fun requestJPushToken(): Pair<Boolean, String> {
        if (!isClassAvailable("cn.jpush.android.api.JPushInterface")) {
            return Pair(false, "jpush_sdk_not_found")
        }

        if (readMetaData("PUSH_JPUSH_APP_KEY").isBlank()) {
            return Pair(false, "jpush_app_key_not_configured")
        }

        pushExecutor.execute {
            try {
                val clazz = Class.forName("cn.jpush.android.api.JPushInterface")
                runCatching {
                    val setDebugMode = clazz.getMethod("setDebugMode", Boolean::class.javaPrimitiveType)
                    setDebugMode.invoke(null, false)
                }
                runCatching {
                    val init = clazz.getMethod("init", Context::class.java)
                    init.invoke(null, applicationContext)
                }.getOrElse { throw it }

                val getRegistrationId = clazz.getMethod("getRegistrationID", Context::class.java)
                var token = ""
                var attempts = 0
                while (token.isBlank() && attempts < 8) {
                    val value = getRegistrationId.invoke(null, applicationContext) as? String
                    if (!value.isNullOrBlank()) {
                        token = value
                        break
                    }
                    attempts += 1
                    Thread.sleep(1200)
                }

                if (token.isNotBlank()) {
                    notifyVendorToken("jpush", token)
                } else {
                    notifyVendorRegistrationFailed("jpush", "jpush_registration_id_empty")
                }
            } catch (t: Throwable) {
                notifyVendorRegistrationFailed("jpush", "jpush_token_error:${t.message ?: "unknown"}")
            }
        }
        return Pair(true, "jpush_token_request_started")
    }

    private fun requestXiaomiToken(): Pair<Boolean, String> {
        if (!isClassAvailable("com.xiaomi.mipush.sdk.MiPushClient")) {
            return Pair(false, "xiaomi_sdk_not_found")
        }

        val appId = readMetaData("PUSH_XIAOMI_APP_ID")
        val appKey = readMetaData("PUSH_XIAOMI_APP_KEY")
        if (appId.isBlank() || appKey.isBlank()) {
            return Pair(false, "xiaomi_app_id_or_key_missing")
        }

        pushExecutor.execute {
            try {
                val clazz = Class.forName("com.xiaomi.mipush.sdk.MiPushClient")
                val registerPush = clazz.getMethod(
                    "registerPush",
                    Context::class.java,
                    String::class.java,
                    String::class.java,
                )
                val getRegId = clazz.getMethod("getRegId", Context::class.java)
                registerPush.invoke(null, applicationContext, appId, appKey)

                var token = ""
                var attempts = 0
                while (token.isBlank() && attempts < 6) {
                    val value = getRegId.invoke(null, applicationContext) as? String
                    if (!value.isNullOrBlank()) {
                        token = value
                        break
                    }
                    attempts += 1
                    Thread.sleep(1200)
                }

                if (token.isNotBlank()) {
                    notifyVendorToken("xiaomi", token)
                } else {
                    notifyVendorRegistrationFailed("xiaomi", "xiaomi_token_empty")
                }
            } catch (t: Throwable) {
                notifyVendorRegistrationFailed("xiaomi", "xiaomi_token_error:${t.message ?: "unknown"}")
            }
        }
        return Pair(true, "xiaomi_token_request_started")
    }

    private fun requestOppoToken(): Pair<Boolean, String> {
        if (!isClassAvailable("com.heytap.msp.push.HeytapPushManager")) {
            return Pair(false, "oppo_sdk_not_found")
        }

        val appKey = readMetaData("PUSH_OPPO_APP_KEY")
        val appSecret = readMetaData("PUSH_OPPO_APP_SECRET")
        if (appKey.isBlank() || appSecret.isBlank()) {
            return Pair(false, "oppo_app_key_or_secret_missing")
        }

        pushExecutor.execute {
            try {
                val managerClazz = Class.forName("com.heytap.msp.push.HeytapPushManager")
                val callbackInterface = Class.forName("com.heytap.msp.push.callback.ICallBackResultService")

                runCatching {
                    val initMethod = managerClazz.getMethod(
                        "init",
                        Context::class.java,
                        Boolean::class.javaPrimitiveType,
                    )
                    initMethod.invoke(null, applicationContext, true)
                }

                val callback = Proxy.newProxyInstance(
                    callbackInterface.classLoader,
                    arrayOf(callbackInterface),
                ) { _, method, args ->
                    if (method.name.equals("onRegister", ignoreCase = true)) {
                        val code = (args?.getOrNull(0) as? Number)?.toInt() ?: -1
                        val registerId = (args?.getOrNull(1) as? String).orEmpty()
                        if (code == 0 && registerId.isNotBlank()) {
                            notifyVendorToken("oppo", registerId)
                        } else {
                            notifyVendorRegistrationFailed("oppo", "oppo_register_failed:$code")
                        }
                    }
                    null
                }
                oppoCallbackProxy = callback

                val registerMethod = managerClazz.getMethod(
                    "register",
                    Context::class.java,
                    String::class.java,
                    String::class.java,
                    callbackInterface,
                )
                registerMethod.invoke(null, applicationContext, appKey, appSecret, callback)

                // Try polling register id in case callback is delayed.
                val candidateMethods = listOf("getRegisterID", "getRegisterId")
                var token = ""
                var attempts = 0
                while (token.isBlank() && attempts < 8) {
                    for (name in candidateMethods) {
                        val value = runCatching {
                            val withContext = runCatching {
                                val m = managerClazz.getMethod(name, Context::class.java)
                                m.invoke(null, applicationContext)
                            }.getOrNull()
                            val withoutContext = runCatching {
                                val m = managerClazz.getMethod(name)
                                m.invoke(null)
                            }.getOrNull()
                            (withContext ?: withoutContext) as? String
                        }.getOrNull()

                        if (!value.isNullOrBlank()) {
                            token = value
                            break
                        }
                    }
                    if (token.isNotBlank()) {
                        break
                    }
                    attempts += 1
                    Thread.sleep(1200)
                }

                if (token.isNotBlank()) {
                    notifyVendorToken("oppo", token)
                }
            } catch (t: Throwable) {
                notifyVendorRegistrationFailed("oppo", "oppo_token_error:${t.message ?: "unknown"}")
            }
        }
        return Pair(true, "oppo_token_request_started")
    }

    private fun notifyVendorToken(channel: String, token: String) {
        VendorPushStore.savePendingToken(applicationContext, channel, token)
        mainHandler.post {
            pushVendorChannel?.invokeMethod(
                "onToken",
                mapOf(
                    "channel" to channel,
                    "token" to token,
                ),
            )
        }
    }

    private fun emitPendingVendorToken() {
        val pending = VendorPushStore.consumePendingToken(applicationContext) ?: return
        notifyVendorToken(pending.first, pending.second)
    }

    private fun consumePendingNotificationTap(): Map<String, Any>? {
        val pending = pendingNotificationTap ?: return null
        pendingNotificationTap = null
        if (pending["type"]?.toString()?.trim() == "notification_reply") {
            recordNotificationReplyTrace("native_consumed", pending)
        }
        return pending
    }

    private fun captureNotificationTap(intent: Intent?, emitToFlutter: Boolean) {
        val data = notificationTapDataFromIntent(intent) ?: return
        val chatId = data["chat_id"]?.toString()?.trim().orEmpty()
        val messageId = (data["message_id"] ?: data["msg_id"])?.toString()?.trim().orEmpty()
        if (chatId.isNotBlank() && RevokedNotificationStore.isRevoked(applicationContext, chatId, messageId)) {
            pendingNotificationTap = null
            Log.i(nativeNotificationTag, "revoked notification tap ignored chat=$chatId")
            return
        }
        pendingNotificationTap = data
        if (data["type"]?.toString()?.trim() == "notification_reply") {
            recordNotificationReplyTrace("native_captured", data)
        }
        Log.i(nativeNotificationTag, "notification tap captured keys=${data.keys.joinToString(",")}")
        if (emitToFlutter) {
            mainHandler.post { emitPendingNotificationTap() }
        }
    }

    private fun emitPendingNotificationTap() {
        val pending = pendingNotificationTap ?: return
        val channel = pushVendorChannel ?: return
        if (pending["type"]?.toString()?.trim() == "notification_reply") {
            recordNotificationReplyTrace("native_emit", pending)
        }
        channel.invokeMethod(
            "onNotificationTap",
            pending,
            object : MethodChannel.Result {
                override fun success(result: Any?) {
                    if (pending["type"]?.toString()?.trim() == "notification_reply") {
                        recordNotificationReplyTrace("native_emit_ack", pending)
                    }
                    if (pendingNotificationTap === pending) {
                        pendingNotificationTap = null
                    }
                }

                override fun error(errorCode: String, errorMessage: String?, errorDetails: Any?) {
                    Log.w(nativeNotificationTag, "notification tap emit failed: $errorCode $errorMessage")
                }

                override fun notImplemented() {
                    Log.w(nativeNotificationTag, "notification tap emit skipped: Flutter handler not ready")
                }
            },
        )
    }

    private fun notificationTapDataFromIntent(intent: Intent?): Map<String, Any>? {
        val extras = intent?.extras ?: return null
        val data = linkedMapOf<String, Any>()
        for (key in extras.keySet()) {
            if (key.isBlank() || isSystemIntentExtra(key)) {
                continue
            }
            val value = extras.get(key) ?: continue
            data[key] = when (value) {
                is String -> value
                is Boolean -> value
                is Int -> value
                is Long -> value
                is Float -> value
                is Double -> value
                else -> value.toString()
            }
        }
        val replyText = NotificationReplyAction.replyText(intent).take(4000)
        if (replyText.isNotEmpty()) {
            data["reply_text"] = replyText
        }
        if (!isNotificationTapPayload(data)) {
            return null
        }
        data["tap_source"] = data["tap_source"] ?: "android_intent"
        return data
    }

    private fun recordNotificationReplyTrace(stage: String, details: Map<*, *>?): Map<String, Any> {
        val normalizedStage = stage.trim().take(64).replace(Regex("[^a-zA-Z0-9_.-]"), "_")
        if (normalizedStage.isBlank()) {
            return mapOf("recorded" to false, "reason" to "invalid_stage")
        }
        return try {
            val root = getExternalFilesDir(null) ?: filesDir
            val traceFile = File(root, "qa/notification-reply-trace.jsonl")
            traceFile.parentFile?.mkdirs()
            val entry = JSONObject().apply {
                put("ts_ms", System.currentTimeMillis())
                put("stage", normalizedStage)
                val allowedKeys = setOf(
                    "attempt",
                    "account_active",
                    "auth_status",
                    "code",
                    "handler_ready",
                    "reply_length",
                    "result",
                    "reason",
                )
                details?.forEach { (rawKey, rawValue) ->
                    val key = rawKey?.toString().orEmpty()
                    if (key in allowedKeys && rawValue != null) {
                        put(key, rawValue.toString().take(80))
                    }
                }
                val chatId = details?.get("chat_id")?.toString()?.trim().orEmpty()
                if (chatId.isNotEmpty()) put("chat_ref", Integer.toHexString(chatId.hashCode()))
                val clientMsgId = details?.get("client_msg_id")?.toString()?.trim().orEmpty()
                if (clientMsgId.isNotEmpty()) put("client_ref", clientMsgId.takeLast(8))
                val replyText = details?.get("reply_text")?.toString().orEmpty()
                if (replyText.isNotEmpty() && !has("reply_length")) {
                    put("reply_length", replyText.length)
                }
            }
            synchronized(notificationReplyTraceLock) {
                if (traceFile.exists() && traceFile.length() > 64 * 1024) {
                    traceFile.writeText("")
                }
                traceFile.appendText(entry.toString() + "\n")
            }
            mapOf("recorded" to true, "path" to traceFile.absolutePath)
        } catch (error: Exception) {
            Log.w(nativeNotificationTag, "notification reply trace failed", error)
            mapOf("recorded" to false, "reason" to "write_failed")
        }
    }

    private fun isNotificationTapPayload(data: Map<String, Any>): Boolean {
        for (key in notificationTapKeys) {
            if (!data[key]?.toString().isNullOrBlank()) {
                return true
            }
        }
        return false
    }

    private fun isSystemIntentExtra(key: String): Boolean {
        return key.startsWith("android.") ||
            key.startsWith("google.") ||
            key.startsWith("gcm.") ||
            key == "profile"
    }

    private fun notifyVendorRegistrationFailed(channel: String, reason: String) {
        mainHandler.post {
            pushVendorChannel?.invokeMethod(
                "onRegistrationFailed",
                mapOf(
                    "channel" to channel,
                    "reason" to reason,
                ),
            )
        }
    }

    private fun resolvePreferredPushChannel(manufacturer: String, brand: String): String {
        val m = "$manufacturer $brand"
        return when {
            isClassAvailable("cn.jpush.android.api.JPushInterface") &&
                readMetaData("PUSH_JPUSH_APP_KEY").isNotBlank() -> "jpush"
            m.contains("huawei") || m.contains("honor") -> "hms"
            m.contains("xiaomi") || m.contains("redmi") -> "xiaomi"
            m.contains("oppo") || m.contains("oneplus") || m.contains("realme") -> "oppo"
            else -> "fcm"
        }
    }

    private fun isClassAvailable(className: String): Boolean {
        return try {
            Class.forName(className)
            true
        } catch (_: Throwable) {
            false
        }
    }

    private fun readHmsAppId(): String {
        val custom = readMetaData("PUSH_HMS_APP_ID")
        if (custom.isNotBlank()) return custom

        // Huawei config commonly stores value as "appid=123456789".
        val fromHuaweiMeta = readMetaData("com.huawei.hms.client.appid")
        return fromHuaweiMeta.removePrefix("appid=").trim()
    }

    private fun readMetaData(key: String): String {
        return try {
            val applicationInfo = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                packageManager.getApplicationInfo(
                    packageName,
                    PackageManager.ApplicationInfoFlags.of(PackageManager.GET_META_DATA.toLong()),
                )
            } else {
                @Suppress("DEPRECATION")
                packageManager.getApplicationInfo(packageName, PackageManager.GET_META_DATA)
            }
            val metaData = applicationInfo.metaData ?: return ""
            if (!metaData.containsKey(key)) return ""
            when (val value = metaData.get(key)) {
                is String -> value.trim()
                is Number -> value.toString().trim()
                is Boolean -> if (value) value.toString() else ""
                else -> value?.toString()?.trim().orEmpty()
            }
        } catch (_: Throwable) {
            ""
        }
    }

    private fun nativeMessageNotificationId(chatId: String): Int {
        if (chatId.isBlank()) {
            return (System.currentTimeMillis() % Int.MAX_VALUE).toInt()
        }
        var hash = 0
        for (char in chatId) {
            hash = (hash * 31 + char.code) and 0x3fffffff
        }
        return 10000 + (hash % 80000)
    }

    private fun immutablePendingIntentFlag(): Int {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            PendingIntent.FLAG_IMMUTABLE
        } else {
            0
        }
    }

    private fun setupHighRefreshRate() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            window.attributes.layoutInDisplayCutoutMode =
                WindowManager.LayoutParams.LAYOUT_IN_DISPLAY_CUTOUT_MODE_ALWAYS

            val supportedModes = display?.supportedModes ?: return
            var highestRefreshRate = 60f
            var preferredMode: android.view.Display.Mode? = null

            for (mode in supportedModes) {
                if (mode.refreshRate > highestRefreshRate) {
                    highestRefreshRate = mode.refreshRate
                    preferredMode = mode
                }
            }

            preferredMode?.let {
                val params = window.attributes
                params.preferredDisplayModeId = it.modeId
                window.attributes = params
            }
        }
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val messageChannel = NotificationChannel(
                messageChannelId,
                "消息通知",
                NotificationManager.IMPORTANCE_HIGH,
            ).apply {
                description = "私聊、群聊和频道消息"
                setShowBadge(true)
                enableVibration(true)
            }

            val callChannel = NotificationChannel(
                callChannelId,
                "来电通知",
                NotificationManager.IMPORTANCE_HIGH,
            ).apply {
                description = "语音和视频通话来电"
                setShowBadge(true)
                enableVibration(true)
            }

            val backgroundChannel = NotificationChannel(
                "genericim_background",
                "后台消息服务",
                NotificationManager.IMPORTANCE_LOW,
            ).apply {
                description = "用于保持消息连接，确保后台也能及时接收新消息"
                setShowBadge(false)
            }

            val announcementChannel = NotificationChannel(
                "genericim_announcements_v1",
                "群公告通知",
                NotificationManager.IMPORTANCE_HIGH,
            ).apply {
                description = "群聊和系统公告"
                setShowBadge(true)
                enableVibration(true)
            }

            val meetingChannel = NotificationChannel(
                "genericim_meetings_v1",
                "会议通知",
                NotificationManager.IMPORTANCE_HIGH,
            ).apply {
                description = "会议邀请和会议状态"
                setShowBadge(true)
                enableVibration(true)
            }

            val notificationManager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            notificationManager.createNotificationChannels(
                listOf(
                    messageChannel,
                    callChannel,
                    announcementChannel,
                    meetingChannel,
                    backgroundChannel,
                ),
            )
        }
    }

    companion object {
        private const val nativeNotificationTag = "GenericIMNativeNotify"
        private const val messageChannelId = "genericim_messages"
        private const val callChannelId = "genericim_calls_v1"
        private val notificationTapKeys = setOf(
            "type",
            "chat_id",
            "chat_type",
            "message_id",
            "notification_id",
            "announcement_id",
            "sender_id",
            "call_id",
            "meeting_id",
            "push_tap",
        )
    }
}
