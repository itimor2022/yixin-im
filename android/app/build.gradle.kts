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

fun ensureAnyVendorConfiguredWhenEnabled(enabled: Boolean, props: Map<String, String>) {
	if (!enabled) return
	if (props.values.all { it.isBlank() }) {
		throw GradleException(
			"[VendorPush] ENABLE_VENDOR_PUSH_SDK=true requires at least one vendor SDK dependency.",
		)
	}
}

fun ensureRequiredPropsForDependency(dependencyName: String, dependency: String, props: Map<String, String>) {
	if (dependency.isBlank()) return
	val missing = props.filterValues { it.isBlank() }.keys.toList()
	if (missing.isNotEmpty()) {
		throw GradleException(
			"[VendorPush] $dependencyName is configured but missing required properties: ${missing.joinToString(", ")}",
		)
	}
}

plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

val googleServicesFile = file("google-services.json")
if (googleServicesFile.exists()) {
    apply(plugin = "com.google.gms.google-services")
}

// Load signing config from keystore.properties when present, fallback to env vars.
val keystorePropertiesFile = rootProject.file("keystore.properties")
val keystoreProperties = Properties()
if (keystorePropertiesFile.exists()) {
    keystoreProperties.load(keystorePropertiesFile.inputStream())
}
val hasReleaseKeystore = keystorePropertiesFile.exists() &&
    resolvedStringProp("storeFile", keystoreProperties, "STORE_FILE").isNotBlank()

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
val disableReleaseShrink = parseBoolValue(projectStringProp("GENERIC_IM_DISABLE_RELEASE_SHRINK"), false)
val enableEmulatorAbis = parseBoolValue(projectStringProp("GENERIC_IM_ENABLE_EMULATOR_ABIS"), false)
val hmsPushSdk = resolvedStringProp("HMS_PUSH_SDK", vendorLocalProperties)
val hmsCompileSdk = hmsPushSdk.ifBlank { "com.huawei.hms:push:6.13.0.301" }
val jpushSdk = resolvedStringProp("JPUSH_SDK", vendorLocalProperties)
val jcoreSdk = resolvedStringProp("JCORE_SDK", vendorLocalProperties)
val xiaomiPushSdk = resolvedStringProp("XIAOMI_PUSH_SDK", vendorLocalProperties)
val oppoPushSdk = resolvedStringProp("OPPO_PUSH_SDK", vendorLocalProperties)
val pushHmsAppId = resolvedStringProp("PUSH_HMS_APP_ID", vendorLocalProperties)
val pushJpushAppKey = resolvedStringProp("PUSH_JPUSH_APP_KEY", vendorLocalProperties)
val pushJpushChannel = resolvedStringProp("PUSH_JPUSH_CHANNEL", vendorLocalProperties).ifBlank { "default" }
val pushXiaomiAppId = resolvedStringProp("PUSH_XIAOMI_APP_ID", vendorLocalProperties)
val pushXiaomiAppKey = resolvedStringProp("PUSH_XIAOMI_APP_KEY", vendorLocalProperties)
val pushOppoAppKey = resolvedStringProp("PUSH_OPPO_APP_KEY", vendorLocalProperties)
val pushOppoAppSecret = resolvedStringProp("PUSH_OPPO_APP_SECRET", vendorLocalProperties)

ensureAnyVendorConfiguredWhenEnabled(
	enableVendorPushSdk,
	mapOf(
		"HMS_PUSH_SDK" to hmsPushSdk,
		"JPUSH_SDK" to jpushSdk,
		"JCORE_SDK" to jcoreSdk,
		"XIAOMI_PUSH_SDK" to xiaomiPushSdk,
		"OPPO_PUSH_SDK" to oppoPushSdk,
	),
)

if (enableVendorPushSdk) {
	ensureRequiredPropsForDependency(
		"HMS_PUSH_SDK",
		hmsPushSdk,
		mapOf("PUSH_HMS_APP_ID" to pushHmsAppId),
	)
	ensureRequiredPropsForDependency(
		"JPUSH_SDK",
		jpushSdk,
		mapOf(
			"JCORE_SDK" to jcoreSdk,
			"PUSH_JPUSH_APP_KEY" to pushJpushAppKey,
		),
	)
	ensureRequiredPropsForDependency(
		"XIAOMI_PUSH_SDK",
		xiaomiPushSdk,
		mapOf(
			"PUSH_XIAOMI_APP_ID" to pushXiaomiAppId,
			"PUSH_XIAOMI_APP_KEY" to pushXiaomiAppKey,
		),
	)
	ensureRequiredPropsForDependency(
		"OPPO_PUSH_SDK",
		oppoPushSdk,
		mapOf(
			"PUSH_OPPO_APP_KEY" to pushOppoAppKey,
			"PUSH_OPPO_APP_SECRET" to pushOppoAppSecret,
		),
	)
}

android {
    namespace = "com.genericim.app"
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
        applicationId = "com.genericim.app"
        // Android 10 / EMUI 10.1 devices report API 29.
        minSdk = 29
        targetSdk = 36
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        multiDexEnabled = true

        // Vendor push placeholders (from gradle.properties or -P).
        manifestPlaceholders["PUSH_HMS_APP_ID"] = pushHmsAppId
        manifestPlaceholders["PUSH_HMS_SERVICE_ENABLED"] =
            (enableVendorPushSdk && hmsPushSdk.isNotBlank()).toString()
        manifestPlaceholders["PUSH_JPUSH_APP_KEY"] = pushJpushAppKey
        manifestPlaceholders["PUSH_JPUSH_CHANNEL"] = pushJpushChannel
        manifestPlaceholders["PUSH_XIAOMI_APP_ID"] = pushXiaomiAppId
        manifestPlaceholders["PUSH_XIAOMI_APP_KEY"] = pushXiaomiAppKey
        manifestPlaceholders["PUSH_OPPO_APP_KEY"] = pushOppoAppKey
        manifestPlaceholders["PUSH_OPPO_APP_SECRET"] = pushOppoAppSecret
    }

    signingConfigs {
        create("release") {
            keyAlias = resolvedStringProp("keyAlias", keystoreProperties, "KEY_ALIAS")
            keyPassword = resolvedStringProp("keyPassword", keystoreProperties, "KEY_PASSWORD")
            storePassword = resolvedStringProp("storePassword", keystoreProperties, "STORE_PASSWORD")
            val storePath = resolvedStringProp("storeFile", keystoreProperties, "STORE_FILE")
            storeFile = storePath.takeIf { it.isNotBlank() }?.let { file(it) }
        }
    }

    buildTypes {
        release {
            isMinifyEnabled = !disableReleaseShrink
            isShrinkResources = !disableReleaseShrink
            // Keep production release arm64-only. Emulator packaging opts into
            // x86_64 explicitly without increasing normal mobile artifacts.
            ndk {
                abiFilters.clear()
                abiFilters.add("arm64-v8a")
                if (enableEmulatorAbis) {
                    abiFilters.add("x86_64")
                }
            }
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro",
            )
            signingConfig = if (hasReleaseKeystore) {
                signingConfigs.getByName("release")
            } else {
                signingConfigs.getByName("debug")
            }
            isDebuggable = false
        }
        debug {
            isMinifyEnabled = false
            isShrinkResources = false
            signingConfig = if (hasReleaseKeystore) {
                signingConfigs.getByName("release")
            } else {
                signingConfigs.getByName("debug")
            }
        }
    }

    androidResources {
        localeFilters += listOf("zh", "en")
    }

    packaging {
        resources {
            excludes += listOf("META-INF/versions/9/OSGI-INF/MANIFEST.MF")
        }
        jniLibs {
            excludes += listOf(
                "lib/armeabi-v7a/**",
                "lib/x86/**",
                // Unused Agora optional extensions. Keep core RTC, wrapper,
                // and base codec libraries for call stability.
                "lib/**/libagora_ai_echo_cancellation_extension.so",
                "lib/**/libagora_ai_echo_cancellation_ll_extension.so",
                "lib/**/libagora_ai_noise_suppression_extension.so",
                "lib/**/libagora_ai_noise_suppression_ll_extension.so",
                "lib/**/libagora_audio_beauty_extension.so",
                "lib/**/libagora_clear_vision_extension.so",
                "lib/**/libagora_content_inspect_extension.so",
                "lib/**/libagora_face_capture_extension.so",
                "lib/**/libagora_face_detection_extension.so",
                "lib/**/libagora_lip_sync_extension.so",
                "lib/**/libagora_screen_capture_extension.so",
                "lib/**/libagora_segmentation_extension.so",
                "lib/**/libagora_spatial_audio_extension.so",
                "lib/**/libagora_video_av1_decoder_extension.so",
                "lib/**/libagora_video_av1_encoder_extension.so",
                "lib/**/libagora_video_quality_analyzer_extension.so",
            )
            if (!enableEmulatorAbis) {
                excludes += "lib/x86_64/**"
            }
        }
    }
}

flutter {
    source = "../.."
}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
    implementation("androidx.fragment:fragment-ktx:1.7.1")
    testImplementation("junit:junit:4.13.2")

    if (!enableVendorPushSdk || hmsPushSdk.isBlank()) {
        add("compileOnly", hmsCompileSdk)
    }

	if (enableVendorPushSdk) {
		if (hmsPushSdk.isNotBlank()) {
			add("implementation", hmsPushSdk)
			add("implementation", "org.bouncycastle:bcprov-jdk18on:1.84")
		}
		if (jpushSdk.isNotBlank()) {
			add("implementation", jpushSdk)
		}
		if (jcoreSdk.isNotBlank()) {
			add("implementation", jcoreSdk)
		}
		if (xiaomiPushSdk.isNotBlank()) {
			add("implementation", xiaomiPushSdk)
		}
		if (oppoPushSdk.isNotBlank()) {
			add("implementation", oppoPushSdk)
		}
	}
}
