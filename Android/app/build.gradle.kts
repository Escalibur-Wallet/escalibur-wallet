plugins {
    alias(libs.plugins.android.application)
    alias(libs.plugins.kotlin.compose)
}

android {
    namespace = "app.escalibur.wallet"
    compileSdk = 37

    defaultConfig {
        applicationId = "app.escalibur.wallet"
        // Android 9: o StrongBox e o BiometricPrompt existem a partir dele, e o nucleo em Swift
        // e compilado para android28 (tools/android/compilar-nucleo.sh).
        minSdk = 28
        targetSdk = 36
        versionCode = 1
        versionName = "1.0.0"
        // O nucleo so existe para arm64 (todos os aparelhos Android atuais e o emulador do Mac
        // com chip da Apple).
        ndk { abiFilters += listOf("arm64-v8a") }
    }

    buildTypes {
        release {
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(getDefaultProguardFile("proguard-android-optimize.txt"), "proguard-rules.pro")
        }
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    buildFeatures {
        compose = true
        buildConfig = true
    }

    packaging {
        // As bibliotecas nativas ficam descomprimidas e alinhadas no APK (o carregador le
        // direto dele), e o .so do nucleo ja vem sem simbolos de depuracao.
        jniLibs { useLegacyPackaging = false }
    }
}

dependencies {
    implementation(platform(libs.compose.bom))
    implementation(libs.compose.ui)
    implementation(libs.compose.material3)
    implementation(libs.compose.ui.tooling.preview)
    implementation(libs.activity.compose)
    implementation(libs.biometric)
}
