import java.io.FileInputStream
import java.util.Properties

plugins {
    id("com.android.application")
    // START: FlutterFire Configuration
    id("com.google.gms.google-services")
    // END: FlutterFire Configuration
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Release signing: android/key.properties (never in git, see android/.gitignore)
//   storeFile=<path to the Play upload keystore .jks, relative to android/app or absolute>
//   storePassword=...
//   keyAlias=...
//   keyPassword=...
// Without it a release build FAILS (it is never signed with the debug key).
val keystorePropertiesFile = rootProject.file("key.properties")
val keystoreProperties = Properties()
val releaseSigningKeys = listOf("storeFile", "storePassword", "keyAlias", "keyPassword")
val hasReleaseSigning: Boolean = keystorePropertiesFile.exists().also { exists ->
    if (exists) FileInputStream(keystorePropertiesFile).use { keystoreProperties.load(it) }
} && releaseSigningKeys.all { !keystoreProperties.getProperty(it).isNullOrBlank() }

android {
    namespace = "com.chalakcharmart.chalakchar_mart"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
        isCoreLibraryDesugaringEnabled = true
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.chalakcharmart.chalakchar_mart"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        if (hasReleaseSigning) {
            create("release") {
                storeFile = file(keystoreProperties.getProperty("storeFile"))
                storePassword = keystoreProperties.getProperty("storePassword")
                keyAlias = keystoreProperties.getProperty("keyAlias")
                keyPassword = keystoreProperties.getProperty("keyPassword")
            }
        }
    }

    buildTypes {
        release {
            // Only the real upload key. No key.properties -> no signing config
            // here, and the check below stops the build.
            if (hasReleaseSigning) {
                signingConfig = signingConfigs.getByName("release")
            }
        }
    }
}

// Fail any release APK/AAB build without android/key.properties, instead of
// producing an unsigned or debug-signed file. Debug builds are unaffected.
gradle.taskGraph.whenReady {
    val releaseTask = allTasks.any { task ->
        val name = task.name
        (name.startsWith("assemble") || name.startsWith("bundle") || name.startsWith("package")) &&
            name.contains("Release")
    }
    if (releaseTask && !hasReleaseSigning) {
        throw GradleException(
            "Release signing is not configured: android/key.properties is missing or incomplete " +
                "(needs ${releaseSigningKeys.joinToString()}). The release build is never signed with the debug key."
        )
    }
}

flutter {
    source = "../.."
}
dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
}
