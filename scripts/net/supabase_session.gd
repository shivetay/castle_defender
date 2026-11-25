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


## Zapis atomowy: najpierw plik tymczasowy, potem podmiana. Gra zabita w trakcie zapisu (Android
## ubija aplikację w tle) zostawia starą, całą sesję, a nie pusty plik, po którym klient założyłby
## nowe konto, a stare zostałoby bez gracza.
func save(path: String = PATH) -> Error:
	var tmp := path + ".tmp"
	var f := FileAccess.open(tmp, FileAccess.WRITE)
	if f == null:
		return FileAccess.get_open_error()
	f.store_string(JSON.stringify(to_dict()))
	f.close()
	return DirAccess.rename_absolute(tmp, path)


## Sesja z pliku; null, gdy pliku nie ma albo jest nieczytelny.
static func load_from(path: String = PATH) -> SupabaseSession:
	if not FileAccess.file_exists(path):
		return null
	var data: Variant = SupabaseConfig.parse_json(FileAccess.get_file_as_string(path))
	return from_dict(data as Dictionary) if data is Dictionary else null


static func clear(path: String = PATH) -> void:
	for p: String in [path, path + ".tmp"]:
		if FileAccess.file_exists(p):
			DirAccess.remove_absolute(p)
