plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
    id("com.google.gms.google-services")
}

android {
    namespace = "com.ironlink.app"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
        isCoreLibraryDesugaringEnabled = true
    }

    defaultConfig {
        // A second copy of the app, side by side, for two-party testing.
        //
        // Android isolates data by package, so a build with a different
        // applicationId installs alongside the real one with its own session,
        // its own Signal keys and its own message store — which is what
        // testing a conversation needs, and what a single install cannot give.
        //
        // `com.example.ironlink` is not arbitrary: google-services.json already
        // registers it as a second Firebase client, so the test copy signs in
        // with no console changes and no second Firebase project.
        //
        // Off by default. Nothing about a normal build changes, and the flag
        // has to be passed explicitly:
        //
        //   flutter build apk --release -Pandroid.injected.testInstance=true
        //
        // Never ship a build made with this. It is a different application id,
        // so an update would install beside the real app rather than over it.
        val testInstance = project.findProperty("testInstance") == "true"
        applicationId = if (testInstance) "com.example.ironlink" else "com.ironlink.app"
        // Both copies carry the same visible name. Renaming one would need
        // AGP's resValues feature turned on for the whole project, which is a
        // real change to the shipped build for a cosmetic gain in a test
        // affordance. They are told apart by package, which is how anything
        // driving them refers to them anyway.
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    buildTypes {
        release {
            // TODO: Add your own signing config for the release build.
            // Signing with the debug keys for now, so `flutter run --release` works.
            signingConfig = signingConfigs.getByName("debug")

            // R8 needs telling which of ML Kit's five script recognizers this
            // app actually uses. Without these rules the release build fails
            // outright at :app:minifyReleaseWithR8 with eight missing classes —
            // which it did, unnoticed, because nothing here had ever built a
            // release APK. See proguard-rules.pro for the reasoning.
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro",
            )
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

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
}
