import java.io.FileInputStream
import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Release signing. The upload keystore and its passwords live OUTSIDE the
// repo: NAADH_KEY_PROPERTIES (a path), else ~/.naadh-release/key.properties.
// That file holds storeFile, storePassword, keyAlias and keyPassword.
val keyPropertiesFile: File = System.getenv("NAADH_KEY_PROPERTIES")
    ?.let { file(it) }
    ?: File(System.getProperty("user.home"), ".naadh-release/key.properties")
val keyProperties = Properties().apply {
    if (keyPropertiesFile.exists()) {
        FileInputStream(keyPropertiesFile).use { load(it) }
    }
}
val hasUploadKey = keyPropertiesFile.exists()

android {
    namespace = "com.alieninnovations.alien_reader_app"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.alieninnovations.alien_reader_app"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        if (hasUploadKey) {
            create("upload") {
                storeFile = file(keyProperties.getProperty("storeFile"))
                storePassword = keyProperties.getProperty("storePassword")
                keyAlias = keyProperties.getProperty("keyAlias")
                keyPassword = keyProperties.getProperty("keyPassword")
            }
        }
    }

    buildTypes {
        release {
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro",
            )
            signingConfig = if (hasUploadKey) {
                signingConfigs.getByName("upload")
            } else {
                logger.warn(
                    "WARNING: no upload key at $keyPropertiesFile. This release " +
                        "build is signed with the DEBUG key and cannot be " +
                        "uploaded to Play.",
                )
                signingConfigs.getByName("debug")
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
