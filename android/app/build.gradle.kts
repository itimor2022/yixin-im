import java.util.Properties
import org.gradle.api.GradleException

fun projectStringProp(name: String): String {
    return (project.findProperty(name) as? String)?.trim().orEmpty()
}

fun parseBoolValue(raw: String?, defaultValue: Boolean = false): Boolean {
    val value = raw?.trim()?.lowercase() ?: return defaultValue
    return value == "1" || value == "true" || value == "yes" || value == "on"
}

fun resolvedStringProp(
    name: String,
    localProps: Properties,
    envName: String = name,
): String {
    val fromProject = projectStringProp(name)
    if (fromProject.isNotBlank()) {
        return fromProject
    }
    val fromEnv = System.getenv(envName)?.trim().orEmpty()
    if (fromEnv.isNotBlank()) {
        return fromEnv
    }
    return localProps.getProperty(name, "").trim()
}

fun resolvedBoolProp(
    name: String,
    localProps: Properties,
    envName: String = name,
    defaultValue: Boolean = false,
): Boolean {
    // Highest priority: -P passed from command line.
    val fromStartParameter = gradle.startParameter.projectProperties[name]
    if (!fromStartParameter.isNullOrBlank()) {
        return parseBoolValue(fromStartParameter, defaultValue)
    }

    val fromEnv = System.getenv(envName)
    if (!fromEnv.isNullOrBlank()) {
        return parseBoolValue(fromEnv, defaultValue)
    }

    val fromLocal = localProps.getProperty(name, "").trim()
    if (fromLocal.isNotBlank()) {
        return parseBoolValue(fromLocal, defaultValue)
    }

    // Fallback: gradle.properties in repo.
    val fromProject = projectStringProp(name)
    if (fromProject.isNotBlank()) {
        return parseBoolValue(fromProject, defaultValue)
    }

    return defaultValue
}

fun ensureRequiredPropsWhenEnabled(enabled: Boolean, props: Map<String, String>) {
    if (!enabled) return
    val missing = props.filterValues { it.isBlank() }.keys.toList()
    if (missing.isNotEmpty()) {
        throw GradleException(
            "[VendorPush] ENABLE_VENDOR_PUSH_SDK=true requires non-empty properties: ${missing.joinToString(", ")}",
        )
    }
}

plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
    id("com.google.gms.google-services")
}

// Load signing config from keystore.properties when present, fallback to env vars.
val keystorePropertiesFile = rootProject.file("keystore.properties")
val keystoreProperties = Properties()
if (keystorePropertiesFile.exists()) {
    keystoreProperties.load(keystorePropertiesFile.inputStream())
}

// Optional local-only vendor properties file.
// Useful for keeping vendor secrets out of shared gradle.properties.
val vendorLocalPropertiesFile = rootProject.file("gradle.vendor.local.properties")
val vendorLocalProperties = Properties()
if (vendorLocalPropertiesFile.exists()) {
    vendorLocalProperties.load(vendorLocalPropertiesFile.inputStream())
}

// ============================================================
// 老设备兼容开关（LEGACY_COMPAT）
// ============================================================
// 一个开关同时控制两项配置，方便在"兼容包"和"精简包"之间切换。
//
//   LEGACY_COMPAT=true  （默认，兼容包）
//     · minSdk = 26  → 支持 Android 8.0 及以上（含 Android 10）
//                       解决"Android 10 及以下老设备安装时提示解析包错误"
//     · abiFilters   = arm64-v8a + armeabi-v7a  → 兼容 32 位老 CPU 设备
//     · APK 大小增加约 40~60%（多打一份 native so）
//
//   LEGACY_COMPAT=false （精简包，恢复原始行为）
//     · minSdk = 30  → 仅支持 Android 11+
//     · abiFilters   = arm64-v8a only
//     · APK 更小，适合上架应用商店 / 分发给主流机型
//
// ─── 三种切换方式（按优先级从高到低）───
//
// 1) 直接调 gradle 命令：
//      cd android
//      ./gradlew assembleRelease -PLEGACY_COMPAT=false
//
// 2) 环境变量（推荐给 flutter build 命令用）：
//      LEGACY_COMPAT=false flutter build apk --release       # 精简包
//      flutter build apk --release                            # 默认兼容包
//
// 3) 修改 android/gradle.properties 里的 LEGACY_COMPAT 值（长期切换）
//
// 默认值设成 true 是为了不再让老机用户装不上；如你想恢复原来的行为，
// 传 LEGACY_COMPAT=false 即可，或把 defaultValue 改成 false。
val legacyCompat = resolvedBoolProp("LEGACY_COMPAT", vendorLocalProperties, defaultValue = true)

// Optional vendor SDK dependency switch.
// Disabled by default to keep current builds stable.
val enableVendorPushSdk = resolvedBoolProp("ENABLE_VENDOR_PUSH_SDK", vendorLocalProperties, defaultValue = false)
val hmsPushSdk = resolvedStringProp("HMS_PUSH_SDK", vendorLocalProperties)
val xiaomiPushSdk = resolvedStringProp("XIAOMI_PUSH_SDK", vendorLocalProperties)
val oppoPushSdk = resolvedStringProp("OPPO_PUSH_SDK", vendorLocalProperties)
val pushHmsAppId = resolvedStringProp("PUSH_HMS_APP_ID", vendorLocalProperties)
val pushXiaomiAppId = resolvedStringProp("PUSH_XIAOMI_APP_ID", vendorLocalProperties)
val pushXiaomiAppKey = resolvedStringProp("PUSH_XIAOMI_APP_KEY", vendorLocalProperties)
val pushOppoAppKey = resolvedStringProp("PUSH_OPPO_APP_KEY", vendorLocalProperties)
val pushOppoAppSecret = resolvedStringProp("PUSH_OPPO_APP_SECRET", vendorLocalProperties)

ensureRequiredPropsWhenEnabled(
    enableVendorPushSdk,
    mapOf(
        "HMS_PUSH_SDK" to hmsPushSdk,
        "XIAOMI_PUSH_SDK" to xiaomiPushSdk,
        "OPPO_PUSH_SDK" to oppoPushSdk,
        "PUSH_HMS_APP_ID" to pushHmsAppId,
        "PUSH_XIAOMI_APP_ID" to pushXiaomiAppId,
        "PUSH_XIAOMI_APP_KEY" to pushXiaomiAppKey,
        "PUSH_OPPO_APP_KEY" to pushOppoAppKey,
        "PUSH_OPPO_APP_SECRET" to pushOppoAppSecret,
    ),
)

android {
    namespace = "com.yixinim.app"
    compileSdk = 36
    ndkVersion = flutter.ndkVersion

    compileOptions {
        isCoreLibraryDesugaringEnabled = true
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    defaultConfig {
        // 注意：这里的 applicationId 是"新的 v2 版本"，与旧的 com.yixinim.app 并存。
        // namespace 依然保留 com.yixinim.app，是为了不移动 Kotlin 源码物理路径
        // (AndroidManifest 里的 android:name=".MainActivity" 走 namespace 解析)。
        // Android 12+ AGP 允许 applicationId 与 namespace 不同，属于官方推荐做法。
        applicationId = "com.yixinim.app.v2"
        // 由 LEGACY_COMPAT 决定 minSdk：
        //   兼容包 → 26（Android 8.0+，含 Android 10 用户）
        //   精简包 → 30（Android 11+，原始行为）
        minSdk = if (legacyCompat) 26 else 30
        targetSdk = 36
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        multiDexEnabled = true

        // Vendor push placeholders (from gradle.properties or -P).
        manifestPlaceholders["PUSH_HMS_APP_ID"] = pushHmsAppId
        manifestPlaceholders["PUSH_XIAOMI_APP_ID"] = pushXiaomiAppId
        manifestPlaceholders["PUSH_XIAOMI_APP_KEY"] = pushXiaomiAppKey
        manifestPlaceholders["PUSH_OPPO_APP_KEY"] = pushOppoAppKey
        manifestPlaceholders["PUSH_OPPO_APP_SECRET"] = pushOppoAppSecret
    }

    signingConfigs {
        create("release") {
            keyAlias = (keystoreProperties["keyAlias"] as? String) ?: System.getenv("KEY_ALIAS") ?: ""
            keyPassword = (keystoreProperties["keyPassword"] as? String) ?: System.getenv("KEY_PASSWORD") ?: ""
            storePassword = (keystoreProperties["storePassword"] as? String) ?: System.getenv("STORE_PASSWORD") ?: ""
            val storePath = (keystoreProperties["storeFile"] as? String) ?: System.getenv("STORE_FILE")
            storeFile = storePath?.let { file(it) }
        }
    }

    buildTypes {
        release {
            isMinifyEnabled = true
            isShrinkResources = true
            // ABI 过滤：兼容包多打一份 32 位 so，精简包只打 arm64。
            // 打印一行方便在打包终端 / CI 日志里确认这次打的是哪种包。
            val buildLabel = if (legacyCompat) "LEGACY (minSdk=26, arm64-v8a + armeabi-v7a)"
                             else "MODERN (minSdk=30, arm64-v8a only)"
            println("[build.gradle.kts] release APK build mode: $buildLabel")
            ndk {
                abiFilters.clear()
                abiFilters.add("arm64-v8a")
                if (legacyCompat) {
                    abiFilters.add("armeabi-v7a")
                }
            }
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro",
            )
            signingConfig = signingConfigs.getByName("release")
            isDebuggable = false
        }
        debug {
            isMinifyEnabled = false
            isShrinkResources = false
        }
    }

    androidResources {
        localeFilters += listOf("zh", "en")
    }

    packaging {
        jniLibs {
            // Compress native .so inside APK to reduce file size of distributed package.
            useLegacyPackaging = true
            // x86 / x86_64 一律排除（模拟器才用得到，实体设备极其罕见）。
            // armeabi-v7a 只在"精简包"模式下排除；兼容包模式要保留它。
            val jniExcludes = mutableListOf("lib/x86/**", "lib/x86_64/**")
            if (!legacyCompat) {
                jniExcludes += "lib/armeabi-v7a/**"
            }
            excludes += jniExcludes
        }
    }
}

flutter {
    source = "../.."
}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")

    if (enableVendorPushSdk) {
        add("implementation", hmsPushSdk)
        add("implementation", xiaomiPushSdk)
        add("implementation", oppoPushSdk)
    }
}
