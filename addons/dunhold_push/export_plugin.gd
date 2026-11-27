@tool
extends EditorExportPlugin
## Eksport wtyczki DunholdPush na Androida (#30, ADR 0012). Działa tylko przy budowie Gradle (preset
## debug i AAB). AAR buduje `bash .github/scripts/build_push_plugin.sh`; bez niego eksport idzie bez
## wtyczki (gra bez pusha), z ostrzeżeniem w logu. Konfigurację Firebase bierze z FirebaseConfig.PATH.

const AAR := "dunhold_push/bin/dunhold_push.aar"
## Ta sama wersja co `compileOnly` w tools/android/push_plugin/build.gradle.kts.
const FIREBASE_MESSAGING := "com.google.firebase:firebase-messaging:24.1.0"


func _get_name() -> String:
	return "DunholdPush"


func _supports_platform(platform: EditorExportPlatform) -> bool:
	return platform is EditorExportPlatformAndroid


func _has_aar() -> bool:
	return FileAccess.file_exists("res://addons/" + AAR)


func _get_android_libraries(_platform: EditorExportPlatform, _debug: bool) -> PackedStringArray:
	if not _has_aar():
		push_warning("DunholdPush: brak %s, eksport bez powiadomień" % AAR)
		return PackedStringArray()
	return PackedStringArray([AAR])


func _get_android_dependencies(_platform: EditorExportPlatform, _debug: bool) -> PackedStringArray:
	return PackedStringArray([FIREBASE_MESSAGING]) if _has_aar() else PackedStringArray()


func _get_android_manifest_application_element_contents(_platform: EditorExportPlatform, _debug: bool) -> String:
	if not _has_aar() or not FileAccess.file_exists(FirebaseConfig.PATH):
		return ""
	var package_name := str(get_option("package/unique_name"))
	var config := FirebaseConfig.for_package(FileAccess.get_file_as_string(FirebaseConfig.PATH), package_name)
	if config.is_empty():
		push_warning("DunholdPush: google-services.json bez pakietu z presetu, eksport bez pusha")
	return FirebaseConfig.manifest_entries(config)
