extends TestCase
## Klient Supabase (#22) bez sieci: konfiguracja (tylko klucz publishable), sesja, odpowiedzi Auth,
## tryb offline z rosnącą przerwą i nagłówki REST.

const C := preload("res://scripts/net/supabase_client.gd")
const PATH := "user://test_session.json"
const URL := "https://abc.supabase.co"
const KEY := "sb_publishable_test123"


static func _jwt(role: String) -> String:
	var payload := Marshalls.utf8_to_base64(JSON.stringify({"role": role})).replace("=", "")
	return "eyJhbGciOiJIUzI1NiJ9." + payload.replace("+", "-").replace("/", "_") + ".podpis"


static func _auth_body(token: String, expires_in: int) -> String:
	return JSON.stringify({
		"access_token": token, "refresh_token": "r-" + token, "expires_in": expires_in,
		"user": {"id": "00000000-0000-0000-0000-00000000000a", "is_anonymous": true},
	})


func _client() -> SupabaseClient:
	SupabaseSession.clear(PATH)
	var c := SupabaseClient.new()
	c.setup(SupabaseConfig.parse(JSON.stringify({"url": URL, "publishable_key": KEY})), PATH)
	return c


func test_config_accepts_only_client_keys() -> bool:
	var ok := SupabaseConfig.parse(JSON.stringify({"url": URL + "/", "publishable_key": " " + KEY}))
	assert_true(ok.is_ready(), "adres HTTPS i klucz publishable")
	assert_eq(ok.url, URL, "bez końcowego ukośnika")
	assert_true(not SupabaseConfig.is_client_key(_jwt("anon")), "dawny klucz JWT odrzucony (jak w CI)")
	assert_true(not SupabaseConfig.is_client_key(_jwt("service_role")), "service_role odrzucony")
	assert_true(not SupabaseConfig.is_client_key("sb_secret_abc"), "klucz sekretny odrzucony")
	assert_true(not SupabaseConfig.is_client_key(""), "pusty klucz")
	var http := SupabaseConfig.parse(JSON.stringify({"url": "http://abc.supabase.co", "publishable_key": KEY}))
	assert_true(not http.is_ready(), "tylko HTTPS")
	assert_true(not SupabaseConfig.parse("nie json").is_ready(), "zepsuty plik to offline")
	assert_true(not SupabaseConfig.load_from("res://config/nie_ma.json").is_ready(), "brak pliku to offline")
	return true


func test_session_from_response_and_refresh() -> bool:
	var s := SupabaseSession.from_auth_response(JSON.parse_string(_auth_body("t1", 3600)) as Dictionary, 1000)
	assert_true(s != null, "pełna odpowiedź daje sesję")
	assert_eq(s.expires_at, 4600, "wygaśnięcie z expires_in")
	assert_true(not s.needs_refresh(4000), "token jeszcze ważny")
	assert_true(s.needs_refresh(4600 - SupabaseSession.REFRESH_MARGIN_S), "odświeżenie przed wygaśnięciem")
	assert_true(SupabaseSession.from_auth_response({"access_token": "x"}, 0) == null, "niepełna odpowiedź")
	assert_eq(s.save(PATH), OK, "zapis sesji")
	var back := SupabaseSession.load_from(PATH)
	assert_true(back != null and back.to_dict() == s.to_dict(), "sesja po wczytaniu taka sama")
	SupabaseSession.clear(PATH)
	assert_true(SupabaseSession.load_from(PATH) == null, "po usunięciu brak sesji")
	return true


func test_outcomes_and_backoff() -> bool:
	assert_eq(C.outcome_of(HTTPRequest.RESULT_SUCCESS, 200), C.Outcome.OK, "200")
	assert_eq(C.outcome_of(HTTPRequest.RESULT_SUCCESS, 400), C.Outcome.REJECTED, "400 odrzuca")
	assert_eq(C.outcome_of(HTTPRequest.RESULT_SUCCESS, 429), C.Outcome.NETWORK, "429 to ponowienie")
	assert_eq(C.outcome_of(HTTPRequest.RESULT_SUCCESS, 503), C.Outcome.NETWORK, "5xx to ponowienie")
	assert_eq(C.outcome_of(HTTPRequest.RESULT_CANT_CONNECT, 0), C.Outcome.NETWORK, "brak sieci")
	assert_eq(C.retry_delay(1), 5, "pierwsza przerwa")
	assert_eq(C.retry_delay(3), 30, "rośnie")
	assert_eq(C.retry_delay(99), 300, "do pięciu minut")
	return true


func test_signup_success_goes_online_and_saves() -> bool:
	var c := _client()
	var states: Array[int] = []
	c.state_changed.connect(func(st: int) -> void: states.append(st))
	c.handle_auth(C.Call.SIGNUP, HTTPRequest.RESULT_SUCCESS, 200, _auth_body("t1", 3600))
	assert_true(c.is_online(), "online po założeniu konta")
	assert_eq(c.user_id(), "00000000-0000-0000-0000-00000000000a", "id konta")
	assert_eq(states, [C.State.ONLINE] as Array[int], "sygnał stanu")
	assert_true(SupabaseSession.load_from(PATH) != null, "sesja zapisana na telefonie")
	var h := c.rest_headers()
	assert_true(h.has("apikey: " + KEY) and h.has("Authorization: Bearer t1"), "nagłówki REST z tokenem gracza")
	SupabaseSession.clear(PATH)
	c.free()
	return true


func test_network_error_keeps_session_and_backs_off() -> bool:
	var c := _client()
	c.handle_auth(C.Call.SIGNUP, HTTPRequest.RESULT_SUCCESS, 200, _auth_body("t1", 3600))
	c.handle_auth(C.Call.REFRESH, HTTPRequest.RESULT_TIMEOUT, 0, "")
	assert_eq(c.state, C.State.OFFLINE, "offline")
	assert_true(c.session != null, "sesja zostaje na ponowienie")
	assert_eq(c._retry_left, 5.0, "pierwsza przerwa")
	c.handle_auth(C.Call.REFRESH, HTTPRequest.RESULT_SUCCESS, 502, "")
	assert_eq(c._retry_left, 15.0, "druga przerwa dłuższa")
	SupabaseSession.clear(PATH)
	c.free()
	return true


## Odrzucony token odświeżania: konta anonimowego nie odzyskamy, więc od razu zakładamy nowe.
func test_rejected_refresh_starts_new_account() -> bool:
	var c := _client()
	c.handle_auth(C.Call.SIGNUP, HTTPRequest.RESULT_SUCCESS, 200, _auth_body("t1", 3600))
	c.handle_auth(C.Call.REFRESH, HTTPRequest.RESULT_SUCCESS, 400,
			JSON.stringify({"code": 400, "error_code": "refresh_token_not_found", "msg": "Invalid Refresh Token"}))
	assert_true(c.session == null and SupabaseSession.load_from(PATH) == null, "stara sesja usunięta")
	assert_eq(c._retry_left, 0.0, "nowe konto bez czekania")
	c.handle_auth(C.Call.SIGNUP, HTTPRequest.RESULT_SUCCESS, 422, "{}")
	assert_true(c._retry_left > 0.0, "odrzucone zakładanie konta czeka (np. wyłączone konta anonimowe)")
	c.free()
	return true


## Sesja przetrwa ponowne uruchomienie: nowy klient czyta ją z pliku i nie zakłada drugiego konta.
func test_session_survives_restart() -> bool:
	var c := _client()
	c.handle_auth(C.Call.SIGNUP, HTTPRequest.RESULT_SUCCESS, 200, _auth_body("t1", 3600))
	c.free()
	assert_true(not FileAccess.file_exists(PATH + ".tmp"), "po zapisie nie zostaje plik tymczasowy")
	var back := SupabaseSession.load_from(PATH)
	assert_true(back != null, "sesja na telefonie po restarcie")
	assert_eq(back.user_id, "00000000-0000-0000-0000-00000000000a", "to samo konto")
	assert_eq(back.refresh_token, "r-t1", "ten sam token odświeżania")
	# drugi zapis (po odświeżeniu) podmienia plik w całości
	var s2 := SupabaseSession.from_auth_response(JSON.parse_string(_auth_body("t2", 3600)) as Dictionary, 0)
	assert_eq(s2.save(PATH), OK, "podmiana sesji")
	assert_eq(SupabaseSession.load_from(PATH).access_token, "t2", "nowy token po podmianie")
	assert_true(FileAccess.file_exists(PATH + ".bak"), "poprzednia sesja odłożona do .bak (rename bez nadpisania)")
	# przerwa między zmianami nazw: plik główny już w .bak, a nowa sesja jeszcze w .tmp
	var s3 := SupabaseSession.from_auth_response(JSON.parse_string(_auth_body("t3", 3600)) as Dictionary, 0)
	var f := FileAccess.open(PATH + ".tmp", FileAccess.WRITE)
	f.store_string(JSON.stringify(s3.to_dict()))
	f.close()
	DirAccess.remove_absolute(PATH + ".bak")
	DirAccess.rename_absolute(PATH, PATH + ".bak")
	assert_eq(SupabaseSession.load_from(PATH).access_token, "t3", "najnowsza sesja z .tmp")
	DirAccess.remove_absolute(PATH + ".tmp")
	assert_eq(SupabaseSession.load_from(PATH).access_token, "t2", "bez .tmp: sesja z .bak")
	assert_eq(s3.save(PATH), OK, "zapis bez pliku głównego")
	assert_eq(SupabaseSession.load_from(PATH).access_token, "t3", "plik główny znowu najnowszy")
	SupabaseSession.clear(PATH)
	assert_true(not FileAccess.file_exists(PATH + ".bak") and not FileAccess.file_exists(PATH + ".tmp"),
			"czyszczenie usuwa też .bak i .tmp")
	assert_true(SupabaseSession.load_from(PATH) == null, "po czyszczeniu brak sesji")
	return true


## Odmowa bez kodu Auth (np. pośrednik w sieci) nie kasuje konta: ponowienie jak przy braku sieci.
func test_unknown_refresh_rejection_keeps_account() -> bool:
	var c := _client()
	c.handle_auth(C.Call.SIGNUP, HTTPRequest.RESULT_SUCCESS, 200, _auth_body("t1", 3600))
	c.handle_auth(C.Call.REFRESH, HTTPRequest.RESULT_SUCCESS, 400, "{}")
	assert_true(c.session != null and SupabaseSession.load_from(PATH) != null, "sesja zostaje")
	assert_eq(c._retry_left, 5.0, "ponowienie z przerwą")
	c.handle_auth(C.Call.REFRESH, HTTPRequest.RESULT_SUCCESS, 404, "<html>")
	assert_true(c.session != null, "404 z HTML też nie kasuje")
	assert_true(C.refresh_token_dead(400, JSON.stringify({"error": "invalid_grant"})), "starszy format GoTrue")
	assert_true(C.refresh_token_dead(403, JSON.stringify({"error_code": "user_not_found"})), "konto usunięte")
	assert_true(not C.refresh_token_dead(500, JSON.stringify({"error_code": "session_not_found"})), "5xx nigdy")
	assert_true(not C.refresh_token_dead(400, JSON.stringify({"error_code": "over_request_rate_limit"})),
			"inny kod nie kasuje")
	SupabaseSession.clear(PATH)
	c.free()
	return true


func test_bad_body_is_not_a_session() -> bool:
	var c := _client()
	c.handle_auth(C.Call.SIGNUP, HTTPRequest.RESULT_SUCCESS, 200, "<html>")
	assert_eq(c.state, C.State.OFFLINE, "zła odpowiedź to offline")
	assert_true(c.session == null, "bez sesji")
	c.free()
	return true


func test_settings_shows_connection_state() -> bool:
	assert_eq(SettingsPanel.net_note(C.State.DISABLED), SettingsPanel.OFFLINE_NOTE, "bez serwera")
	assert_eq(SettingsPanel.net_note(C.State.ONLINE), "Połączono z serwerem", "online")
	for s: int in [C.State.CONNECTING, C.State.OFFLINE]:
		assert_true(not PixelFont._normalize(SettingsPanel.net_note(s)).contains("?"), "znaki z fontu: %d" % s)
	for s: int in [C.State.DISABLED, C.State.CONNECTING, C.State.ONLINE, C.State.OFFLINE]:
		assert_true(PixelFont.text_width(SettingsPanel.net_note(s)) <= 300, "mieści się: %d" % s)
	return true
