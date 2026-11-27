// Wtyczka Android v2 „DunholdPush” (#30, ADR 0012): FCM i lokalne powiadomienia dla Godota.
// Budowa: bash .github/scripts/build_push_plugin.sh (AAR trafia do addons/dunhold_push/bin/).
pluginManagement {
    repositories {
        google()
        mavenCentral()
        gradlePluginPortal()
    }
}

dependencyResolutionManagement {
    repositories {
        google()
        mavenCentral()
    }
}

rootProject.name = "dunhold_push"
