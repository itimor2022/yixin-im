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
    //ndkVersion = flutter.ndkVersion

    compileOptions {
        isCoreLibraryDesugaringEnabled = true
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    defaultConfig {
        applicationId = "com.yixinim.app"
        minSdk = 30
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
            // Keep release arm64-only to reduce package size.
            ndk {
                abiFilters.clear()
                abiFilters.add("arm64-v8a")
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
            excludes += listOf("lib/armeabi-v7a/**", "lib/x86/**")
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
