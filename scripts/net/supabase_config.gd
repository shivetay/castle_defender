class_name SupabaseConfig
extends RefCounted
## Adres projektu Supabase i klucz publishable (#22) z pliku `res://config/supabase.json`.
## Pliku nie ma w repo (`.gitignore`, zasada „nie commituj kluczy Supabase”): lokalnie tworzy go
## właścicielka według `config/supabase.example.json`, a przy eksporcie APK workflow zapisuje go
## ze zmiennych repozytorium. Bez pliku albo z nieprawidłowym kluczem gra działa offline.
## Klient przyjmuje wyłącznie klucz publishable (albo dawny klucz `anon`); klucz serwera
## (`sb_secret_…`, JWT z rolą `service_role`) jest odrzucany, nawet gdyby trafił do pliku.

const PATH := "res://config/supabase.json"

var url := ""
var key := ""


static func load_from(path: String = PATH) -> SupabaseConfig:
	if not FileAccess.file_exists(path):
		return SupabaseConfig.new()
	return parse(FileAccess.get_file_as_string(path))


static func parse(text: String) -> SupabaseConfig:
	var c := SupabaseConfig.new()
	var data: Variant = parse_json(text)
	if data is Dictionary:
		var d := data as Dictionary
		c.url = str(d.get("url", "")).strip_edges().trim_suffix("/")
		c.key = str(d.get("publishable_key", "")).strip_edges()
	return c


## Czy da się połączyć: adres HTTPS i klucz, który wolno mieć w kliencie.
func is_ready() -> bool:
	return url.begins_with("https://") and url.length() > 8 and is_client_key(key)


## Klucz dozwolony w kliencie: nowy publishable albo dawny JWT z rolą `anon`.
static func is_client_key(k: String) -> bool:
	if k.begins_with("sb_publishable_"):
		return k.length() > 15
	if k.begins_with("sb_"):
		return false  # sb_secret_… i inne klucze serwera
	var parts := k.split(".")
	if parts.size() != 3:
		return false
	var payload: Variant = parse_json(base64url_decode(parts[1]))
	return payload is Dictionary and str((payload as Dictionary).get("role", "")) == "anon"


## JSON bez wpisów w logu przy błędzie (odpowiedzi serwera i pliki nie trafiają do logów); null, gdy zepsuty.
static func parse_json(text: String) -> Variant:
	var j := JSON.new()
	return j.data if j.parse(text) == OK else null


static func base64url_decode(s: String) -> String:
	var b := s.replace("-", "+").replace("_", "/")
	while b.length() % 4 != 0:
		b += "="
	return Marshalls.base64_to_utf8(b)
