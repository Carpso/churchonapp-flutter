import java.util.Properties
import java.io.FileInputStream

plugins {
    id("com.android.application")
    id("kotlin-android")
    id("dev.flutter.flutter-gradle-plugin")
    id("com.google.gms.google-services")
}

val keystorePropertiesFile = rootProject.file("key.properties")
val keystoreProperties = Properties()
if (keystorePropertiesFile.exists()) {
    keystoreProperties.load(keystorePropertiesFile.inputStream())
}

android {
    namespace = "com.churchonapp.churchonapp"
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
            val storeFileProp = keystoreProperties.getProperty("storeFile")
            val storePasswordProp = keystoreProperties.getProperty("storePassword")
            val keyAliasProp = keystoreProperties.getProperty("keyAlias")
            val keyPasswordProp = keystoreProperties.getProperty("keyPassword")
            val storeFileEnv = System.getenv("STORE_FILE") ?: System.getenv("storeFile") ?: storeFileProp
            val storePasswordEnv = System.getenv("STORE_PASSWORD") ?: System.getenv("storePassword") ?: storePasswordProp
            val keyAliasEnv = System.getenv("KEY_ALIAS") ?: System.getenv("keyAlias") ?: keyAliasProp
            val keyPasswordEnv = System.getenv("KEY_PASSWORD") ?: System.getenv("keyPassword") ?: keyPasswordProp
            require(storeFileEnv != null) { "STORE_FILE env var or key.properties required for release signing" }
            require(storePasswordEnv != null) { "STORE_PASSWORD env var or key.properties required for release signing" }
            require(keyAliasEnv != null) { "KEY_ALIAS env var or key.properties required for release signing" }
            require(keyPasswordEnv != null) { "KEY_PASSWORD env var or key.properties required for release signing" }
            storeFile = file(storeFileEnv)
            storePassword = storePasswordEnv
            keyAlias = keyAliasEnv
            keyPassword = keyPasswordEnv
        }
    }

    defaultConfig {
        applicationId = "com.churchonapp.churchonapp"
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
