class_name FirebaseConfig
extends RefCounted
## Konfiguracja Firebase dla eksportu Androida (#30, ADR 0012). Czyta `google-services.json` (pobrany
## z konsoli Firebase, w repo go nie ma: `config/google-services.json` w .gitignore, w CI z sekretu)
## i wybiera aplikację o nazwie pakietu z presetu. Wynik trafia do manifestu jako wpisy `meta-data`,
## z których wtyczka DunholdPush startuje Firebase. To identyfikatory aplikacji, a nie sekrety, ale nie
## trzymamy ich w repo. Bez pliku albo bez pasującego pakietu wynik jest pusty i gra działa bez pusha.

const PATH := "res://config/google-services.json"
## Prefiks wpisów w manifeście (DunholdPush.META w Kotlinie).
const META := "dunhold.firebase."
const KEYS: Array[String] = ["app_id", "api_key", "project_id", "sender_id"]


## Wpisy dla pakietu `package_name`: app_id, api_key, project_id, sender_id; pusty słownik, gdy
## plik jest zły, nie ma tego pakietu albo któraś wartość ma znaki spoza bezpiecznego zestawu.
static func for_package(json_text: String, package_name: String) -> Dictionary:
	var parser := JSON.new()
	if parser.parse(json_text) != OK:  # bez JSON.parse_string: zły plik nie sypie ERROR do logu
		return {}
	var data: Variant = parser.data
	if not data is Dictionary:
		return {}
	var root := data as Dictionary
	var info: Variant = root.get("project_info")
	var clients: Variant = root.get("client")
	if not info is Dictionary or not clients is Array:
		return {}
	for c: Variant in clients as Array:
		if not c is Dictionary:
			continue
		var client := c as Dictionary
		var ci: Variant = client.get("client_info")
		if not ci is Dictionary:
			continue
		var android: Variant = (ci as Dictionary).get("android_client_info")
		if not android is Dictionary or str((android as Dictionary).get("package_name", "")) != package_name:
			continue
		var api_key := ""
		var keys: Variant = client.get("api_key")
		if keys is Array and not (keys as Array).is_empty() and (keys as Array)[0] is Dictionary:
			api_key = str(((keys as Array)[0] as Dictionary).get("current_key", ""))
		var out := {
			"app_id": str((ci as Dictionary).get("mobilesdk_app_id", "")),
			"api_key": api_key,
			"project_id": str((info as Dictionary).get("project_id", "")),
			"sender_id": str((info as Dictionary).get("project_number", "")),
		}
		for k: String in KEYS:
			if not is_safe(str(out[k])):
				return {}
		return out
	return {}


## Wartość do atrybutu XML bez escapowania: niepusta, do 200 znaków, litery, cyfry i `-_:.`.
static func is_safe(value: String) -> bool:
	if value.is_empty() or value.length() > 200:
		return false
	for i in value.length():
		var ch := value.unicode_at(i)
		var ok := (ch >= 48 and ch <= 57) or (ch >= 65 and ch <= 90) or (ch >= 97 and ch <= 122) \
				or ch == 45 or ch == 95 or ch == 58 or ch == 46
		if not ok:
			return false
	return true


## Wpisy `meta-data` do elementu `application` manifestu (pusty tekst bez konfiguracji).
static func manifest_entries(config: Dictionary) -> String:
	if config.is_empty():
		return ""
	var out := ""
	for k: String in KEYS:
		out += "<meta-data android:name=\"%s%s\" android:value=\"%s\" />\n" % [META, k, str(config.get(k, ""))]
	return out
