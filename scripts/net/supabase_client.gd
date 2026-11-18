class_name SupabaseClient
extends Node
## Połączenie z Supabase (#22): anonimowe konto gracza, odświeżanie tokenu i tryb offline.
## Gra działa bez sieci tak samo jak dotąd (zapis na telefonie); klient tylko próbuje się połączyć
## i ponawia próby z rosnącą przerwą. Bez `config/supabase.json` (albo z kluczem, którego nie wolno
## mieć w kliencie) stoi w stanie DISABLED i nie wysyła niczego.
## Klient nie jest zaufany (skill `pvp-anti-cheat`): to konto służy tylko do zapisu własnych danych
## przez RLS, a wynik ataku, łup i ranking liczy serwer. Tokenów i odpowiedzi API nie logujemy.
## Po wejściu w ONLINE może wysłać zamek z `map_seed` (#166 / część #23).

signal state_changed(state: int)

enum State { DISABLED, CONNECTING, ONLINE, OFFLINE }
## Jak skończyło się żądanie do Auth.
enum Outcome { OK, REJECTED, NETWORK }
enum Call { NONE, SIGNUP, REFRESH }
## Kroki zapisu zamku z seedem (#166).
enum CastleCall { NONE, GET, INSERT, UPDATE }

## Przerwy między kolejnymi próbami połączenia (s); ostatnia się powtarza.
const RETRY_S: Array[int] = [5, 15, 30, 60, 120, 300]
const TIMEOUT_S := 15.0
const SIGNUP_PATH := "/auth/v1/signup"
const REFRESH_PATH := "/auth/v1/token?grant_type=refresh_token"

var state: int = State.DISABLED
var config: SupabaseConfig
var session: SupabaseSession
var session_path := SupabaseSession.PATH

var _failures := 0
var _retry_left := 0.0
var _pending: int = Call.NONE
var _http: HTTPRequest
var _rest: HTTPRequest
var _castle_call: int = CastleCall.NONE
var _castle_map_seed := 0
var _castle_save_version := 0
var _castle_data: Dictionary = {}


## Konfiguracja przed dodaniem do drzewa (w testach inna ścieżka sesji); bez niej `_ready` czyta plik.
func setup(c: SupabaseConfig, path: String = SupabaseSession.PATH) -> void:
	config = c
	session_path = path


func _ready() -> void:
	if config == null:
		config = SupabaseConfig.load_from()
	if not config.is_ready():
		_set_state(State.DISABLED)
		return
	_http = HTTPRequest.new()
	_http.timeout = TIMEOUT_S
	add_child(_http)
	_http.request_completed.connect(_on_request_completed)
	_rest = HTTPRequest.new()
	_rest.timeout = TIMEOUT_S
	add_child(_rest)
	_rest.request_completed.connect(_on_rest_completed)
	session = SupabaseSession.load_from(session_path)
	connect_now()


func _process(delta: float) -> void:
	if _pending != Call.NONE:
		return
	if state == State.OFFLINE:
		_retry_left -= delta
		if _retry_left <= 0.0:
			connect_now()
	elif state == State.ONLINE and session != null and session.needs_refresh(_now()):
		connect_now()


func is_online() -> bool:
	return state == State.ONLINE


## Id konta gracza (uuid z Supabase Auth) albo pusty tekst, gdy nie ma sesji.
func user_id() -> String:
	return session.user_id if session != null else ""


## Ważna sesja: gotowe. Sesja do odświeżenia: token odświeżania. Brak sesji: nowe konto anonimowe.
func connect_now() -> void:
	if state == State.DISABLED and (config == null or not config.is_ready()):
		return
	if _pending != Call.NONE or _http == null:
		return
	if session != null and not session.needs_refresh(_now()):
		_failures = 0
		_set_state(State.ONLINE)
		return
	_set_state(State.CONNECTING)
	if session != null:
		_send(Call.REFRESH, REFRESH_PATH, {"refresh_token": session.refresh_token})
	else:
		_send(Call.SIGNUP, SIGNUP_PATH, {})


## Nagłówki zapytań do REST API w imieniu gracza (#23): klucz publishable i token konta.
func rest_headers() -> PackedStringArray:
	return headers_for(config.key, session.access_token if session != null else "")


## Wysyła zamek z `map_seed` (#166). Bez sieci / w trakcie innego zapisu — no-op.
func sync_castle(map_seed: int, save_version: int, data: Dictionary) -> void:
	if not is_online() or _rest == null or _castle_call != CastleCall.NONE:
		return
	if not CastleSync.is_valid_map_seed(map_seed) or user_id().is_empty():
		return
	_castle_map_seed = map_seed
	_castle_save_version = save_version
	_castle_data = data
	_castle_call = CastleCall.GET
	var err := _rest.request(config.url + CastleSync.own_path(user_id()) + "&select=" + CastleSync.SELECT_OWN,
			rest_headers(), HTTPClient.METHOD_GET)
	if err != OK:
		_castle_call = CastleCall.NONE


# --- Logika bez sieci (testy) ------------------------------------------------------------------

static func headers_for(key: String, access_token: String) -> PackedStringArray:
	var h := PackedStringArray(["apikey: " + key, "Content-Type: application/json"])
	h.append("Authorization: Bearer " + (access_token if not access_token.is_empty() else key))
	return h


## Przerwa przed kolejną próbą po `failures` nieudanych z rzędu (od 1).
static func retry_delay(failures: int) -> int:
	return RETRY_S[clampi(failures - 1, 0, RETRY_S.size() - 1)]


## OK: 2xx. REJECTED: serwer odrzucił dane (zły albo zużyty token odświeżania). NETWORK: brak
## sieci, przekroczony czas, 408/429 albo błąd serwera; wtedy spróbujemy później z tym samym tokenem.
static func outcome_of(result: int, code: int) -> int:
	if result != HTTPRequest.RESULT_SUCCESS:
		return Outcome.NETWORK
	if code >= 200 and code < 300:
		return Outcome.OK
	if code >= 400 and code < 500 and code != 408 and code != 429:
		return Outcome.REJECTED
	return Outcome.NETWORK


## Obsługa odpowiedzi Auth (bez sieci, wołana też z testów).
func handle_auth(call: int, result: int, code: int, body: String) -> void:
	_pending = Call.NONE
	var outcome := outcome_of(result, code)
	if outcome == Outcome.OK:
		var data: Variant = SupabaseConfig.parse_json(body)
		var s: SupabaseSession = SupabaseSession.from_auth_response(data as Dictionary, _now()) \
				if data is Dictionary else null
		if s != null:
			session = s
			session.save(session_path)
			_failures = 0
			_set_state(State.ONLINE)
			return
		outcome = Outcome.NETWORK  # niepełna odpowiedź: spróbujemy jeszcze raz
	if outcome == Outcome.REJECTED and call == Call.REFRESH:
		# Konta anonimowego nie da się odzyskać bez tokenu odświeżania: zakładamy nowe.
		session = null
		SupabaseSession.clear(session_path)
		_failures += 1
		_retry_left = 0.0
		_set_state(State.OFFLINE)
		return
	_failures += 1
	_retry_left = retry_delay(_failures)
	_set_state(State.OFFLINE)


# --- Sieć ---------------------------------------------------------------------------------------

func _send(call: int, path: String, body: Dictionary) -> void:
	_pending = call
	var err := _http.request(config.url + path, headers_for(config.key, ""), HTTPClient.METHOD_POST,
			JSON.stringify(body))
	if err != OK:
		handle_auth(call, HTTPRequest.RESULT_CANT_CONNECT, 0, "")


func _on_request_completed(result: int, code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	handle_auth(_pending, result, code, body.get_string_from_utf8())


func _on_rest_completed(result: int, code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	handle_castle_rest(_castle_call, result, code, body.get_string_from_utf8())


## Obsługa REST zamku bez sieci (testy). GET → INSERT albo UPDATE z seedem tylko przy INSERT.
func handle_castle_rest(call: int, result: int, code: int, body: String) -> void:
	var pending := call
	_castle_call = CastleCall.NONE
	if pending == CastleCall.NONE or outcome_of(result, code) != Outcome.OK:
		return
	if pending == CastleCall.GET:
		var rows: Variant = SupabaseConfig.parse_json(body)
		var remote := CastleSync.map_seed_from_rows(rows)
		var action := CastleSync.next_action(_castle_map_seed, remote)
		if action == CastleSync.Action.INSERT:
			_castle_send(CastleCall.INSERT, HTTPClient.METHOD_POST, CastleSync.CASTLES_PATH,
					CastleSync.insert_body(user_id(), _castle_map_seed, _castle_save_version, _castle_data))
		elif action == CastleSync.Action.UPDATE:
			_castle_send(CastleCall.UPDATE, HTTPClient.METHOD_PATCH, CastleSync.own_path(user_id()),
					CastleSync.update_body(_castle_save_version, _castle_data))
		return
	# INSERT / UPDATE: sukces kończy cykl; seed w bazie zostaje z INSERT


func _castle_send(call: int, method: int, path: String, body: Dictionary) -> void:
	if _rest == null:
		return
	_castle_call = call
	var headers := rest_headers()
	if method == HTTPClient.METHOD_POST:
		headers.append("Prefer: return=minimal")
	var err := _rest.request(config.url + path, headers, method, JSON.stringify(body))
	if err != OK:
		_castle_call = CastleCall.NONE


func _set_state(s: int) -> void:
	if s == state:
		return
	state = s
	state_changed.emit(s)


static func _now() -> int:
	return int(Time.get_unix_time_from_system())
