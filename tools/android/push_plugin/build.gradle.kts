// Biblioteka AAR wtyczki DunholdPush. Godot i Firebase są `compileOnly`: Godot daje swoją bibliotekę
// w szablonie budowy, a Firebase Messaging dokłada eksport (addons/dunhold_push/export_plugin.gd,
// _get_android_dependencies), więc wersje trzymamy w jednym miejscu: tu i w FIREBASE_MESSAGING tam.
plugins {
    id("com.android.library") version "8.7.3"
    id("org.jetbrains.kotlin.android") version "2.0.21"
}

android {
    namespace = "com.shivetay.dunhold.push"
    compileSdk = 35

    defaultConfig {
        minSdk = 24
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    buildTypes {
        release {
            isMinifyEnabled = false
        }
    }
}

kotlin {
    jvmToolchain(17)
}

dependencies {
    // ta sama wersja co silnik (config/features w project.godot)
    compileOnly("org.godotengine:godot:4.7.2.stable")
    compileOnly("com.google.firebase:firebase-messaging:24.1.0")
}
