import java.util.Properties
import java.io.FileInputStream
import org.gradle.api.tasks.compile.JavaCompile

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Production signing comes from android/key.properties (gitignored, never
// committed). A debug-signed release is available only through an explicit
// local Gradle property for non-production validation.
val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
val productionSigningConfigured = keystorePropertiesFile.isFile
val allowDebugReleaseSigning =
    project.findProperty("codar.debugReleaseSigning")?.toString() == "true" ||
        System.getenv("CODAR_DEBUG_RELEASE_SIGNING") == "true"

if (productionSigningConfigured) {
    keystoreProperties.load(FileInputStream(keystorePropertiesFile))
}

tasks.configureEach {
    if (name.contains("release", ignoreCase = true)) {
        doFirst {
            if (!productionSigningConfigured && !allowDebugReleaseSigning) {
                throw GradleException(
                    "Production release signing requires android/key.properties. " +
                        "For local non-production validation, pass " +
                        "-Pcodar.debugReleaseSigning=true.",
                )
            }
            if (productionSigningConfigured) {
                val required = listOf("keyAlias", "keyPassword", "storeFile", "storePassword")
                val missing = required.filter {
                    keystoreProperties.getProperty(it)?.trim().isNullOrEmpty()
                }
                if (missing.isNotEmpty()) {
                    throw GradleException(
                        "android/key.properties is missing: ${missing.joinToString(", ")}",
                    )
                }
                val storeFile = project.file(
                    keystoreProperties.getProperty("storeFile").orEmpty().trim(),
                )
                if (!storeFile.isFile) {
                    throw GradleException(
                        "Signing keystore does not exist: ${storeFile.absolutePath}",
                    )
                }
            }
        }
    }
}

// integration_test is a dev-only plugin. Flutter may include its generated
// registrant entry even though the class is not on the release Java classpath.
// Remove only that generated release entry; integration tests remain unchanged.
tasks.withType<JavaCompile>().configureEach {
    if (name.contains("Release", ignoreCase = true)) {
        doFirst {
            val registrant = project.file(
                "src/main/java/io/flutter/plugins/GeneratedPluginRegistrant.java",
            )
            if (registrant.isFile) {
                val source = registrant.readText()
                val integrationTestBlock = Regex(
                    "    try \\{\\R" +
                        "      flutterEngine\\.getPlugins\\(\\)\\.add\\(new " +
                        "dev\\.flutter\\.plugins\\.integration_test\\.IntegrationTestPlugin\\(\\)\\);\\R" +
                        "    \\} catch \\(Exception e\\) \\{\\R" +
                        "      Log\\.e\\(TAG, \"Error registering plugin integration_test.*?\\R" +
                        "    \\}\\R",
                    setOf(RegexOption.DOT_MATCHES_ALL),
                )
                registrant.writeText(source.replace(integrationTestBlock, ""))
            }
        }
    }
}

android {
    namespace = "com.codar.codar"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "com.codar.codar"
        minSdk = 24
        targetSdk = flutter.targetSdkVersion
        ndk {
            abiFilters += listOf("arm64-v8a")
        }
        // Uses the version code from pubspec.yaml. When using split APKs, 1000 * ABI_VERSION
        // is added automatically by Flutter. (https://developer.android.com/studio/bundle/configure-apk-splits#configure-APK-versions)
        // You can force using the value of versionCode by specifying the `-P force-version-code-ignoring-abi=true`
        // flag during build.
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    packagingOptions {
        jniLibs {
            excludes += listOf(
                "**/armeabi-v7a/**",
                "**/x86/**",
                "**/x86_64/**",
            )
        }
    }

    signingConfigs {
        create("release") {
            if (productionSigningConfigured) {
                keyAlias = keystoreProperties.getProperty("keyAlias").orEmpty()
                keyPassword = keystoreProperties.getProperty("keyPassword").orEmpty()
                val storePath = keystoreProperties.getProperty("storeFile").orEmpty()
                storeFile = if (storePath.isEmpty()) null else file(storePath)
                storePassword = keystoreProperties.getProperty("storePassword").orEmpty()
            }
        }
    }

    buildTypes {
        release {
            signingConfig = when {
                productionSigningConfigured -> signingConfigs.getByName("release")
                allowDebugReleaseSigning -> signingConfigs.getByName("debug")
                else -> signingConfigs.getByName("release")
            }
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}
