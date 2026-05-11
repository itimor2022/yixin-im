package com.yixinim.app

import android.Manifest
import android.app.NotificationChannel
import android.app.NotificationManager
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.provider.Settings
import android.view.WindowManager
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.lang.reflect.Proxy
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors

class MainActivity : FlutterActivity() {
    private val notificationPermissionRequestCode = 9101
    private val hotUpdateChannelName = "com.gaoranim/hot_update"
    private val pushVendorChannelName = "com.gaoranim/push_vendor"
    private val settingsChannelName = "com.gaoranim/settings"

    private var pushVendorChannel: MethodChannel? = null
    private var pendingNotificationPermissionResult: MethodChannel.Result? = null
    private var oppoCallbackProxy: Any? = null
    private val pushExecutor: ExecutorService = Executors.newSingleThreadExecutor()
    private val mainHandler = Handler(Looper.getMainLooper())

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        setupHotUpdateChannel(flutterEngine)
        setupPushVendorChannel(flutterEngine)
        setupSettingsChannel(flutterEngine)
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        createNotificationChannel()
        setupHighRefreshRate()
    }

    override fun onDestroy() {
        pendingNotificationPermissionResult?.success(false)
        pendingNotificationPermissionResult = null
        pushExecutor.shutdownNow()
        oppoCallbackProxy = null
        pushVendorChannel = null
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
                        "xiaomi" to isClassAvailable("com.xiaomi.mipush.sdk.MiPushClient"),
                        "oppo" to isClassAvailable("com.heytap.msp.push.HeytapPushManager"),
                    )
                    val configReady = mapOf(
                        "hms" to readHmsAppId().isNotBlank(),
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
                            "supported_channels" to listOf("fcm", "hms", "xiaomi", "oppo"),
                            "sdk_available" to sdkAvailable,
                            "config_ready" to configReady,
                            "message" to "vendor_push_init_completed",
                        ),
                    )
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

                "getVendorSdkStatus" -> {
                    result.success(
                        mapOf(
                            "hms" to isClassAvailable("com.huawei.hms.aaid.HmsInstanceId"),
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
                    "requestNotificationPermission" -> requestNotificationPermission(result)
                    "openNotificationSettings" -> result.success(openNotificationSettings())
                    else -> result.notImplemented()
                }
            }
    }

    private fun requestNotificationPermission(result: MethodChannel.Result) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU) {
            result.success(true)
            return
        }

        if (ContextCompat.checkSelfPermission(
                this,
                Manifest.permission.POST_NOTIFICATIONS,
            ) == PackageManager.PERMISSION_GRANTED
        ) {
            result.success(true)
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
            metaData.getString(key)?.trim()
                ?: metaData.getInt(key).takeIf { it != 0 }?.toString()
                ?: metaData.getBoolean(key).takeIf { it }?.toString()
                ?: ""
        } catch (_: Throwable) {
            ""
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
                "gaoranim_messages",
                "消息通知",
                NotificationManager.IMPORTANCE_HIGH,
            ).apply {
                description = "聊天消息、语音视频通话和会议提醒"
                setShowBadge(true)
                enableVibration(true)
            }

            val backgroundChannel = NotificationChannel(
                "gaoranim_background",
                "后台消息服务",
                NotificationManager.IMPORTANCE_LOW,
            ).apply {
                description = "用于保持消息连接，确保后台也能及时接收新消息"
                setShowBadge(false)
            }

            val notificationManager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            notificationManager.createNotificationChannels(listOf(messageChannel, backgroundChannel))
        }
    }
}
