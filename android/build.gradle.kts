import java.util.Properties

fun rootResolvedStringProp(name: String, localProps: Properties): String {
    val fromProject = (findProperty(name) as? String)?.trim().orEmpty()
    if (fromProject.isNotBlank()) {
        return fromProject
    }
    val fromEnv = System.getenv(name)?.trim().orEmpty()
    if (fromEnv.isNotBlank()) {
        return fromEnv
    }
    return localProps.getProperty(name, "").trim()
}

// Optional local-only vendor properties file.
// Used for private build-time keys/repo URLs without committing to VCS.
val vendorLocalPropertiesFile = rootProject.file("gradle.vendor.local.properties")
val vendorLocalProperties = Properties()
if (vendorLocalPropertiesFile.exists()) {
    vendorLocalProperties.load(vendorLocalPropertiesFile.inputStream())
}

val huaweiPushRepo = "https://developer.huawei.com/repo/"
val oppoPushRepo = rootResolvedStringProp("OPPO_PUSH_MAVEN_REPO", vendorLocalProperties)
    .ifBlank { "https://maven.heytapmcs.com/repository/maven-public/" }
val xiaomiPushRepo = rootResolvedStringProp("XIAOMI_PUSH_MAVEN_REPO", vendorLocalProperties)

allprojects {
    repositories {
        google()
        mavenCentral()

        // Huawei Push SDK (scoped by group).
        exclusiveContent {
            forRepository {
                maven(url = huaweiPushRepo)
            }
            filter {
                includeGroupByRegex("com\\.huawei(\\..+)?")
            }
        }

        // OPPO / Heytap Push SDK (customizable repo, scoped by group).
        exclusiveContent {
            forRepository {
                maven(url = oppoPushRepo)
            }
            filter {
                includeGroup("com.heytap.msp")
            }
        }

        // Optional custom Xiaomi repo (scoped by group).
        if (xiaomiPushRepo.isNotBlank()) {
            exclusiveContent {
                forRepository {
                    maven(url = xiaomiPushRepo)
                }
                filter {
                    includeGroupByRegex("com\\.xiaomi(\\..+)?")
                }
            }
        }
    }
}

fun extractManifestPackage(project: Project): String? {
    val manifestFile = project.file("src/main/AndroidManifest.xml")
    if (!manifestFile.exists()) return null

    val content = manifestFile.readText()
    return Regex("""package="([^"]+)"""").find(content)?.groupValues?.getOrNull(1)
}

fun setAndroidNamespaceIfMissing(project: Project) {
    val android = project.extensions.findByName("android") ?: return
    val getNamespace = android.javaClass.methods.firstOrNull {
        it.name == "getNamespace" && it.parameterCount == 0
    } ?: return
    val setNamespace = android.javaClass.methods.firstOrNull {
        it.name == "setNamespace" && it.parameterCount == 1
    } ?: return

    val currentNamespace = getNamespace.invoke(android) as? String
    if (!currentNamespace.isNullOrBlank()) return

    val manifestPackage = extractManifestPackage(project) ?: return
    setNamespace.invoke(android, manifestPackage)
}

// Fix older Android plugin dependencies, including isar_flutter_libs.
subprojects {
    plugins.withId("com.android.application") {
        setAndroidNamespaceIfMissing(project)
    }

    plugins.withId("com.android.library") {
        setAndroidNamespaceIfMissing(project)
    }

    afterEvaluate {
        setAndroidNamespaceIfMissing(project)

        if (project.hasProperty("android")) {
            val android = project.extensions.getByName("android")
            if (android is com.android.build.gradle.BaseExtension) {
                android.compileSdkVersion(36)
            }
        }
    }
}

val newBuildDir: Directory =
    rootProject.layout.buildDirectory
        .dir("../../build")
        .get()
rootProject.layout.buildDirectory.value(newBuildDir)

subprojects {
    val newSubprojectBuildDir: Directory = newBuildDir.dir(project.name)
    project.layout.buildDirectory.value(newSubprojectBuildDir)
}

subprojects {
    project.evaluationDependsOn(":app")
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
