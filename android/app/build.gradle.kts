plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
    id("com.google.gms.google-services")
}

android {
    namespace = "com.churchonapp.app"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = "28.1.13356709"

    compileOptions {
        isCoreLibraryDesugaringEnabled = true
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    signingConfigs {
        create("release") {
            val keystorePath = System.getenv("STORE_FILE") ?: System.getenv("storeFile") ?: "churchonapp_release.keystore"
            storeFile = file(keystorePath)
            storePassword = System.getenv("STORE_PASSWORD") ?: System.getenv("storePassword") ?: "123456"
            keyAlias = System.getenv("KEY_ALIAS") ?: System.getenv("keyAlias") ?: "my-key-alias"
            keyPassword = System.getenv("KEY_PASSWORD") ?: System.getenv("keyPassword") ?: "123456"
        }
    }

    defaultConfig {
        applicationId = "com.churchonapp.app"
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        multiDexEnabled = true
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.getByName("release")
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(getDefaultProguardFile("proguard-android-optimize.txt"), "proguard-rules.pro")
        }
    }

    packaging {
        jniLibs {
            keepDebugSymbols.add("/**/*.so")
        }
    }
}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
}

flutter {
    source = "../.."
}
