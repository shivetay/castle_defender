class_name SupabaseSession
extends RefCounted
## Sesja konta Supabase (#22): token dostępu, token odświeżania, czas wygaśnięcia i id gracza.
## Leży w `user://session.json`, czyli w prywatnym katalogu aplikacji na telefonie. Tokenów
## nigdy nie wypisujemy do logów (skill `user-data-privacy`). „Zacznij od nowa” jej nie kasuje: nowa gra
## to ten sam gracz i to samo konto, a nowy zamek nadpisuje stary na serwerze (#23).

const PATH := "user://session.json"
## Odświeżaj token tyle sekund przed wygaśnięciem.
const REFRESH_MARGIN_S := 60

var access_token := ""
var refresh_token := ""
## Chwila wygaśnięcia tokenu dostępu (sekundy uniksowe).
var expires_at := 0
var user_id := ""
var is_anonymous := true


## Sesja z odpowiedzi `/auth/v1/signup` albo `/auth/v1/token`; null, gdy odpowiedź jest niepełna.
static func from_auth_response(d: Dictionary, now_s: int) -> SupabaseSession:
	var s := SupabaseSession.new()
	s.access_token = str(d.get("access_token", ""))
	s.refresh_token = str(d.get("refresh_token", ""))
	var expires_in := int(d.get("expires_in", 0))
	s.expires_at = int(d.get("expires_at", now_s + expires_in))
	var user: Variant = d.get("user", {})
	if user is Dictionary:
		s.user_id = str((user as Dictionary).get("id", ""))
		s.is_anonymous = bool((user as Dictionary).get("is_anonymous", true))
	return s if s.is_valid() else null


func is_valid() -> bool:
	return not access_token.is_empty() and not refresh_token.is_empty() and not user_id.is_empty() \
			and expires_at > 0


func needs_refresh(now_s: int) -> bool:
	return now_s >= expires_at - REFRESH_MARGIN_S


func to_dict() -> Dictionary:
	return {
		"access_token": access_token,
		"refresh_token": refresh_token,
		"expires_at": expires_at,
		"user": {"id": user_id, "is_anonymous": is_anonymous},
	}


static func from_dict(d: Dictionary) -> SupabaseSession:
	return from_auth_response(d, 0)


## Zapis atomowy jak w `SaveGame.write`: pełny plik tymczasowy, poprzedni plik → .bak, .tmp → plik.
## Gra zabita w trakcie zapisu (Android ubija aplikację w tle) zostawia całą sesję w jednym z tych
## plików (`load_from` je sprawdza), a nie pusty plik, po którym klient założyłby nowe konto.
## `rename` nie nadpisuje istniejącego pliku na każdej platformie, więc stary plik najpierw odchodzi.
func save(path: String = PATH) -> Error:
	var tmp := path + ".tmp"
	var f := FileAccess.open(tmp, FileAccess.WRITE)
	if f == null:
		return FileAccess.get_open_error()
	f.store_string(JSON.stringify(to_dict()))
	f.close()
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(path + ".bak")
		var err := DirAccess.rename_absolute(path, path + ".bak")
		if err != OK:
			return err
	return DirAccess.rename_absolute(tmp, path)


## Sesja z pliku, a gdy go nie ma albo jest nieczytelny, z pełnego .tmp (najnowszy) albo z .bak
## (zapis przerwany między zmianami nazw). Null, gdy żaden plik nie daje ważnej sesji.
static func load_from(path: String = PATH) -> SupabaseSession:
	for p: String in [path, path + ".tmp", path + ".bak"]:
		if not FileAccess.file_exists(p):
			continue
		var data: Variant = SupabaseConfig.parse_json(FileAccess.get_file_as_string(p))
		var s: SupabaseSession = from_dict(data as Dictionary) if data is Dictionary else null
		if s != null:
			return s
	return null


static func clear(path: String = PATH) -> void:
	for p: String in [path, path + ".tmp", path + ".bak"]:
		if FileAccess.file_exists(p):
			DirAccess.remove_absolute(p)
