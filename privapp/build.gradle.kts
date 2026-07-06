plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
}

// Kotlin 2.3.0 removed the kotlinOptions DSL; use compilerOptions (matches the
// parent app's convention). JVM 21 matches the JDK 21 toolchain.
kotlin {
    compilerOptions {
        jvmTarget.set(org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_21)
    }
}

android {
    namespace = "io.carrierims.applier"
    compileSdk = 36

    defaultConfig {
        applicationId = "io.carrierims.applier"
        minSdk = 33
        targetSdk = 36
        versionCode = 1
        versionName = "1.0.0"
    }

    buildTypes {
        release {
            // A system priv-app's privileges come from privileged="true" + the
            // privapp-permissions XML, not from the signing key, so a plain
            // self-signed release build is sufficient. Sign with the debug key
            // (always present) to avoid needing a release keystore.
            signingConfig = signingConfigs.getByName("debug")
            isMinifyEnabled = false
        }
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_21
        targetCompatibility = JavaVersion.VERSION_21
    }

    buildFeatures {
        buildConfig = false
    }
}

dependencies {
    // No external dependencies: the priv-app uses only the Android framework
    // (org.json, android.telephony.*) which is part of the platform.
}
