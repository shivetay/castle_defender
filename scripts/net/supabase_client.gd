class_name SupabaseClient
extends Node
## Połączenie z Supabase (#22): anonimowe konto gracza, odświeżanie tokenu i tryb offline.
## Gra działa bez sieci tak samo jak dotąd (zapis na telefonie); klient tylko próbuje się połączyć
## i ponawia próby z rosnącą przerwą. Bez `config/supabase.json` (albo z kluczem, którego nie wolno
## mieć w kliencie) stoi w stanie DISABLED i nie wysyła niczego.
## Klient nie jest zaufany (skill `pvp-anti-cheat`): to konto służy tylko do zapisu własnych danych
## przez RLS, a wynik ataku, łup i ranking liczy serwer. Tokenów i odpowiedzi API nie logujemy.
## W ONLINE synchronizuje zamek i obronę z serwerem (#23, logika w `CastleSync`): przy połączeniu czyta
## własny zamek, potem zapisuje zmiany najwyżej co `PUSH_INTERVAL_S` z kontrolą rewizji, a po reinstalacji
## przywraca zamek z serwera (`castle_restored`).

signal state_changed(state: int)
## Serwer ma zamek, który trzeba przywrócić na telefon (#23): zapis w kształcie `SaveGame.to_dict`
## i tożsamość z onboardingu (`Identity.to_dict`, pusty słownik, gdy jej nie ma).
signal castle_restored(save: Dictionary, profile: Dictionary)
## Odczyt zamku z serwera skończył się i nic nie wraca na telefon (zamek zostaje, idzie na serwer
## albo odczyt się nie udał). Po nim zasłona ładowania na starcie może zejść (#316).
signal castle_checked
## Odpowiedź doboru przeciwnika (#24): cele-gracze z serwera (0–3). `ok` false: błąd sieci albo
## serwera; gra zostaje wtedy przy samych zamkach-botach.
## `limited`: serwer odrzucił szukanie z limitu (20 na 10 minut).
signal targets_found(targets: Array[TargetSearch.Target], ok: bool, limited: bool)
## Odpowiedź `start_attack` (#240): `start` z AttackStart.parse_response albo pusty słownik, gdy
## serwer odmówił; `error` to wtedy kod błędu (`edge_error`), przy sukcesie pusty tekst.
signal attack_started(start: Dictionary, error: String)
## Odpowiedź `finish_attack` (#240): łup przyjęty przez serwer (EconomyConfig.Res) albo pusta lista
## i kod błędu. Błąd `NETWORK_ERROR` można ponowić tym samym żądaniem (serwer jest idempotentny).
signal attack_finished(loot: Array[int], error: String)
## Odpowiedź `launch_attack` (#28): pełne kopie zamku i obrony celu (AttackLaunch.parse_response)
## albo pusty słownik z kodem błędu.
signal attack_launched(launch: Dictionary, error: String)
## Odpowiedź `scout` (#28): ScoutNet.parse_send albo pusty słownik z kodem błędu.
signal scout_sent(send: Dictionary, error: String)
## Raporty zwiadu (#28, ScoutNet.parse_reports); `ok` = serwer odpowiedział.
signal scout_reports_loaded(rows: Array[Dictionary], ok: bool)
## Odpowiedź `ranking` (#27): wiersze tabeli rodzaju `kind` (RankingBoard.Kind). `ok` false: błąd sieci
## albo serwera.
signal ranking_loaded(kind: int, rows: Array[RankingBoard.Row], ok: bool)
## Ostatnie obrony gracza (#99, DefenseLog.parse_response): zniszczone budynki i koniec ataku.
## `ok` false: błąd sieci albo serwera.
signal defenses_loaded(rows: Array[Dictionary], ok: bool)
## Historia obron (#29, #328, DefenseLog.parse_history). `ok` false: błąd sieci albo serwera.
signal defense_reports_loaded(reports: Array[DefenseLog.Report], ok: bool)
## Odpowiedź `attack_replay` (#29): AttackReplay.parse_response albo pusty słownik z kodem błędu.
signal replay_loaded(replay: Dictionary, error: String)
## Serwer scalił łup PvP z zapasami przy zapisie zamku (#274, CastleSync.loot_from_rows): zmiana do
## doliczenia na telefonie, dodatnia u atakującego, ujemna u obrońcy. Nie przychodzi dla samych zer.
signal loot_applied(delta: Array[int])
## Odpowiedź na start fali PvE (#288, WaveReport.parse_start; pusty słownik przy błędzie).
signal wave_started(start: Dictionary, error: String)
## Odpowiedź na koniec fali PvE (#288): nagroda, którą serwer dopisał do zamku (zera przy przegranej).
signal wave_finished(reward: Array[int], error: String)
## Serwer odrzucił zapis zamku spoza limitów surowców (#274, HTTP 422). Po tym sygnale zamek wraca
## z serwera (`castle_restored`), a gdy na serwerze go nie ma, synchronizacja stoi do końca sesji.
signal castle_rejected
## Polityka wersji z serwera (#336): `policy` null, gdy nie przyszła (brak sieci, zła odpowiedź).
signal version_policy_loaded(policy: ClientVersion.Policy, ok: bool)
## Serwer odrzucił wersję gry (`update_required`, HTTP 426): gra ma się zablokować do aktualizacji.
signal update_required
## Serwer zapisał token push urządzenia (#30) albo odrzucił go (`ok` false).
signal push_token_saved(ok: bool)
## Katalog sklepu w Targu (#408): grupy ofert albo `ok` = false (brak sieci, błąd).
signal shop_loaded(groups: Array[ShopNet.Group], ok: bool)
## Odbiór oferty (#408): ShopNet.parse_claim albo kod błędu (`error`, pusty przy sukcesie).
signal shop_claimed(claim: Dictionary, error: String)

enum State { DISABLED, CONNECTING, ONLINE, OFFLINE }
## Jak skończyło się żądanie do Auth.
enum Outcome { OK, REJECTED, NETWORK }
enum Call { NONE, SIGNUP, REFRESH }
## Kroki synchronizacji zamku (#23): odczyt, założenie, zapis z rewizją, obrona i nick.
enum CastleCall { NONE, GET, INSERT, PUSH, DEFENSE_PATCH, DEFENSE_INSERT, NICKNAME }
## Żądanie ataku na gracza w toku (#240).
enum AttackCall { NONE, START, FINISH, LAUNCH, REPLAY, WAVE_START, WAVE_FINISH }
## Żądanie zwiadu w toku (#28).
enum ScoutCall { NONE, SEND, REPORTS }
## Żądanie sklepu w toku (#408).
enum ShopCall { NONE, CATALOG, CLAIM }

## Kod błędu bez odpowiedzi serwera (brak sieci, przekroczony czas, 408, 5xx): żądanie można ponowić.
const NETWORK_ERROR := "network"
## Serwer odrzucił żądanie, ale nie podał znanego kodu.
const REJECTED_ERROR := "rejected"

## Przerwy między kolejnymi próbami połączenia (s); ostatnia się powtarza.
const RETRY_S: Array[int] = [5, 15, 30, 60, 120, 300]
const TIMEOUT_S := 15.0
const SIGNUP_PATH := "/auth/v1/signup"
const REFRESH_PATH := "/auth/v1/token?grant_type=refresh_token"
## Zamek idzie na serwer najwyżej raz na tyle sekund (zapis lokalny jest dużo częstszy);
## przy wyjściu z gry `flush()` wysyła od razu.
const PUSH_INTERVAL_S := 15.0
## Ile razy z rzędu zapis może trafić na konflikt rewizji, zanim klient poczeka na nowy zapis.
const MAX_CONFLICTS := 3

var state: int = State.DISABLED
var config: SupabaseConfig
var session: SupabaseSession
var session_path := SupabaseSession.PATH
var sync_path := CastleSync.SyncState.PATH
## Rewizja zamku na serwerze, od której zaczyna się stan na telefonie (#23).
var sync_state := CastleSync.SyncState.new()
## Gra wystartowała bez zapisu na telefonie (ustawia main przed dodaniem do drzewa).
var local_fresh := false

var _failures := 0
var _retry_left := 0.0
var _pending: int = Call.NONE
var _http: HTTPRequest
var _rest: HTTPRequest
## Dobór przeciwnika (#24) idzie osobnym połączeniem, żeby nie czekać na synchronizację zamku.
var _rpc: HTTPRequest
var _targets_pending := false
## Start i koniec ataku na gracza (#240) idą osobnym połączeniem, po jednym naraz.
var _attack: HTTPRequest
var _attack_call: int = AttackCall.NONE
## Tabela rankingu (#27) idzie osobnym połączeniem; naraz jedno żądanie, a prośba o inny rodzaj
## w trakcie czeka w `_ranking_next`.
var _ranking: HTTPRequest
var _ranking_kind := -1
var _ranking_next := -1
## Ostatnie obrony (#99) idą osobnym połączeniem, naraz jedno żądanie.
var _defenses: HTTPRequest
var _defenses_pending := false
## Raporty obron (#29) idą osobnym połączeniem, naraz jedno żądanie.
var _reports: HTTPRequest
var _reports_pending := false
## Zwiad (#28) idzie osobnym połączeniem, naraz jedno żądanie.
var _scout: HTTPRequest
var _scout_call: int = ScoutCall.NONE
## Sklep w Targu (#408) idzie osobnym połączeniem, naraz jedno żądanie.
var _shop: HTTPRequest
var _shop_call: int = ShopCall.NONE
## Polityka wersji (#336) idzie osobnym połączeniem, naraz jedno żądanie.
var _version: HTTPRequest
var _version_pending := false
## Token push (#30) idzie osobnym połączeniem, naraz jedno żądanie.
var _push: HTTPRequest
var _push_pending := false
## Serwer odrzucił wersję gry: zamek nie idzie na serwer, dopóki nowe sprawdzenie tego nie zdejmie.
var update_blocked := false
var _castle_call: int = CastleCall.NONE
var _castle_map_seed := 0
var _castle_save_version := 0
var _castle_data: Dictionary = {}
var _defense_data: Dictionary = {}
var _nickname := ""
## Czy gracz ma tożsamość z onboardingu (bez niej zamek nie idzie na serwer, ale może z niego wrócić).
var _can_push := false
## Najnowszy stan nie jest jeszcze na serwerze. Gdy żądanie trwa, nowy zapis tylko podmienia dane.
var _castle_dirty := false
## Zamek jest na serwerze, ale obrona albo nick nie doszły (błąd po udanym zapisie zamku): ponowić je.
var _defense_dirty := false
## Rewizja zamku, który właśnie wraca na telefon; trafia do `sync.json` dopiero po `confirm_restore`.
var _pull_revision := -1
## Konto, dla którego w tej sesji odczytano zamek z serwera (pusty: trzeba odczytać).
var _checked_user := ""
## Rewizja na serwerze, od której idzie następny zapis.
var _base_revision := -1
## Odliczanie do następnego zapisu (s).
var _push_wait := 0.0
var _conflicts := 0
## Na serwerze jest zamek z nowszej wersji gry albo zamek właśnie wraca na telefon: nic nie wysyłamy.
var _castle_hold := false
## Serwer odrzucił zapis zamku (#274): po odczycie zamek wraca z serwera zamiast ponawiać ten sam zapis.
var _force_pull := false
var _failures_castle := 0
## Testy: żądania synchronizacji trafiają tu zamiast do sieci (call, method, path, body).
var fake_transport := false
var sent_requests: Array[Dictionary] = []
var _sent_save_version := 0
var _sent_data: Dictionary = {}
var _sent_defense: Dictionary = {}
var _sent_nickname := ""


## Konfiguracja przed dodaniem do drzewa (w testach inna ścieżka sesji); bez niej `_ready` czyta plik.
func setup(c: SupabaseConfig, path: String = SupabaseSession.PATH,
		sync_file: String = CastleSync.SyncState.PATH) -> void:
	config = c
	session_path = path
	sync_path = sync_file


func _ready() -> void:
	if config == null:
		config = SupabaseConfig.load_from()
	sync_state = CastleSync.SyncState.load_from(sync_path)
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
	_rpc = HTTPRequest.new()
	_rpc.timeout = TIMEOUT_S
	add_child(_rpc)
	_rpc.request_completed.connect(_on_rpc_completed)
	_attack = HTTPRequest.new()
	_attack.timeout = TIMEOUT_S
	add_child(_attack)
	_attack.request_completed.connect(_on_attack_completed)
	_ranking = HTTPRequest.new()
	_ranking.timeout = TIMEOUT_S
	add_child(_ranking)
	_ranking.request_completed.connect(_on_ranking_completed)
	_defenses = HTTPRequest.new()
	_defenses.timeout = TIMEOUT_S
	add_child(_defenses)
	_defenses.request_completed.connect(_on_defenses_completed)
	_reports = HTTPRequest.new()
	_reports.timeout = TIMEOUT_S
	add_child(_reports)
	_reports.request_completed.connect(_on_reports_completed)
	_scout = HTTPRequest.new()
	_scout.timeout = TIMEOUT_S
	add_child(_scout)
	_scout.request_completed.connect(_on_scout_completed)
	_shop = HTTPRequest.new()
	_shop.timeout = TIMEOUT_S
	add_child(_shop)
	_shop.request_completed.connect(_on_shop_completed)
	_version = HTTPRequest.new()
	_version.timeout = TIMEOUT_S
	add_child(_version)
	_version.request_completed.connect(_on_version_completed)
	_push = HTTPRequest.new()
	_push.timeout = TIMEOUT_S
	add_child(_push)
	_push.request_completed.connect(_on_push_completed)
	session = SupabaseSession.load_from(session_path)
	connect_now()


func _process(delta: float) -> void:
	if _push_wait > 0.0:
		_push_wait -= delta
		if _push_wait <= 0.0:
			_castle_pump()
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


## Pobiera politykę wersji (#336); wynik w `version_policy_loaded`. Działa też bez konta i przy
## kłopotach z logowaniem (tylko klucz publishable), bo stary klient ma się dowiedzieć o blokadzie.
## False, gdy serwer nie jest skonfigurowany; gdy sprawdzenie już trwa, sygnał przyjdzie z tamtego.
func check_version() -> bool:
	if config == null or not config.is_ready():
		return false
	if _version_pending:
		return true
	_version_pending = true
	if fake_transport:
		sent_requests.append({"path": ClientVersion.POLICY_PATH, "body": {}})
		return true
	if _version == null:
		_version_pending = false
		return false
	var err := _version.request(config.url + ClientVersion.POLICY_PATH, headers_for(config.key, ""),
			HTTPClient.METHOD_POST, "{}")
	if err != OK:
		handle_version(HTTPRequest.RESULT_CANT_CONNECT, 0, "")
	return true


func handle_version(result: int, code: int, body: String) -> void:
	_version_pending = false
	var policy: ClientVersion.Policy = null
	if outcome_of(result, code) == Outcome.OK:
		policy = ClientVersion.Policy.parse(body)
	version_policy_loaded.emit(policy, policy != null)


## Każda odpowiedź serwera przechodzi tędy: 426 to `update_required` (#336). Sygnał idzie raz,
## do `clear_update_block` po nowym sprawdzeniu wersji.
func note_status(code: int) -> void:
	if code != ClientVersion.HTTP_UPDATE_REQUIRED or update_blocked:
		return
	update_blocked = true
	update_required.emit()


func clear_update_block() -> void:
	update_blocked = false


## Nowy stan zamku do wysłania (#23). Bez sieci zostaje w pamięci i pójdzie po połączeniu (main
## woła to też po wejściu w ONLINE). Zapis idzie najwyżej co `PUSH_INTERVAL_S`; w trakcie żądania
## nowy stan tylko podmienia poprzedni, więc częsty zapis lokalny niczego nie gubi.
## `nickname` pusty i `can_push` false: gracz bez tożsamości, zamek może tylko wrócić z serwera.
func sync_castle(map_seed: int, save_version: int, data: Dictionary, defense: Dictionary = {},
		nickname: String = "", can_push: bool = true) -> void:
	if not CastleSync.is_valid_map_seed(map_seed):
		return
	_castle_map_seed = map_seed
	_castle_save_version = save_version
	_castle_data = data
	_defense_data = defense
	_nickname = nickname
	_can_push = can_push
	_castle_dirty = true
	_conflicts = 0
	_castle_pump()


## Szuka 3 przeciwników (#24, Edge Function `find_targets`); wynik przychodzi w `targets_found`.
## False, gdy nie ma sieci; gdy poprzednie szukanie jeszcze trwa, sygnał przyjdzie z tamtego.
func find_targets() -> bool:
	if _targets_pending:
		return true
	if not is_online() or user_id().is_empty():
		return false
	if fake_transport:
		# testy: odpowiedź podaje handle_targets
		_targets_pending = true
		return true
	if _rpc == null:
		return false
	_targets_pending = true
	var err := _rpc.request(config.url + TargetSearch.PATH, rest_headers(), HTTPClient.METHOD_POST, "{}")
	if err != OK:
		handle_targets(HTTPRequest.RESULT_CANT_CONNECT, 0, "")
	return true


## Obsługa odpowiedzi `find_targets` (bez sieci, wołana też z testów).
func handle_targets(result: int, code: int, body: String) -> void:
	_targets_pending = false
	if outcome_of(result, code) != Outcome.OK:
		targets_found.emit([] as Array[TargetSearch.Target], false,
				result == HTTPRequest.RESULT_SUCCESS and code == 429)
		return
	targets_found.emit(TargetSearch.parse_response(SupabaseConfig.parse_json(body)), true, false)


## Tabela rankingu `kind` (RankingBoard.Kind, #27); wynik przychodzi w `ranking_loaded`. False, gdy
## nie ma sieci. Gdy trwa żądanie innego rodzaju, ten idzie zaraz po nim.
func load_ranking(kind: int) -> bool:
	if not is_online() or user_id().is_empty():
		return false
	if _ranking_kind >= 0:
		# ten sam rodzaj już idzie; inny czeka (prośba o bieżący nie kasuje czekającego)
		if kind != _ranking_kind:
			_ranking_next = kind
		return true
	_ranking_kind = kind
	if fake_transport:
		sent_requests.append({"path": RankingBoard.PATH, "body": RankingBoard.request(kind)})
		return true
	if _ranking == null:
		_ranking_kind = -1
		return false
	var err := _ranking.request(config.url + RankingBoard.PATH, rest_headers(), HTTPClient.METHOD_POST,
			JSON.stringify(RankingBoard.request(kind)))
	if err != OK:
		handle_ranking(HTTPRequest.RESULT_CANT_CONNECT, 0, "")
	return true


## Obsługa odpowiedzi `ranking` (bez sieci, wołana też z testów).
func handle_ranking(result: int, code: int, body: String) -> void:
	var kind := _ranking_kind
	_ranking_kind = -1
	if kind < 0:
		return
	if outcome_of(result, code) != Outcome.OK:
		ranking_loaded.emit(kind, [] as Array[RankingBoard.Row], false)
	else:
		ranking_loaded.emit(kind, RankingBoard.parse_response(SupabaseConfig.parse_json(body), kind), true)
	var next := _ranking_next
	_ranking_next = -1
	if next >= 0:
		load_ranking(next)


## Obrony gracza zakończone po `since_s` (unix s); wynik przychodzi w `defenses_loaded`. False, gdy
## nie ma sieci albo poprzednie żądanie jeszcze trwa.
func load_defenses(since_s: int) -> bool:
	if _defenses_pending or not is_online():
		return false
	var p := DefenseLog.path(user_id(), since_s)
	if p.is_empty():
		return false
	_defenses_pending = true
	if fake_transport:
		sent_requests.append({"path": p})
		return true
	if _defenses == null:
		_defenses_pending = false
		return false
	var err := _defenses.request(config.url + p, rest_headers(), HTTPClient.METHOD_GET)
	if err != OK:
		handle_defenses(HTTPRequest.RESULT_CANT_CONNECT, 0, "")
	return true


## Obsługa odpowiedzi z obronami (bez sieci, wołana też z testów).
func handle_defenses(result: int, code: int, body: String) -> void:
	_defenses_pending = false
	if outcome_of(result, code) != Outcome.OK:
		defenses_loaded.emit([] as Array[Dictionary], false)
		return
	defenses_loaded.emit(DefenseLog.parse_response(SupabaseConfig.parse_json(body)), true)


## Historia obron gracza (#328, Edge Function `defense_history`); odpowiedź w `defense_reports_loaded`.
## Id gracza serwer bierze z tokenu, więc treść jest pusta. False: brak sieci albo poprzednie żądanie
## jeszcze trwa (wtedy jego odpowiedź też przyjdzie w `defense_reports_loaded`).
func load_defense_reports() -> bool:
	if _reports_pending or not is_online() or user_id().is_empty():
		return false
	_reports_pending = true
	if fake_transport:
		sent_requests.append({"path": DefenseLog.HISTORY_PATH, "body": {}})
		return true
	if _reports == null:
		_reports_pending = false
		return false
	var err := _reports.request(config.url + DefenseLog.HISTORY_PATH, rest_headers(), HTTPClient.METHOD_POST, "{}")
	if err != OK:
		handle_reports(HTTPRequest.RESULT_CANT_CONNECT, 0, "")
	return true


## Czy historia obron jest w drodze.
func is_reports_pending() -> bool:
	return _reports_pending


## Obsługa odpowiedzi z raportami obron (bez sieci, wołana też z testów).
func handle_reports(result: int, code: int, body: String) -> void:
	_reports_pending = false
	if outcome_of(result, code) != Outcome.OK:
		defense_reports_loaded.emit([] as Array[DefenseLog.Report], false)
		return
	defense_reports_loaded.emit(DefenseLog.parse_history(SupabaseConfig.parse_json(body)), true)


## Zapis tokenu push urządzenia z przełącznikiem „Ataki” (#30, Edge Function `push_token`); odpowiedź
## w `push_token_saved`. Id gracza serwer bierze z tokenu konta. False: brak sieci, zły token albo
## poprzedni zapis jeszcze trwa.
func save_push_token(token: String, attacks: bool) -> bool:
	if _push_pending or not is_online() or user_id().is_empty() or not PushNotifications.is_valid_token(token):
		return false
	_push_pending = true
	var body := PushNotifications.save_request(token, attacks)
	if fake_transport:
		sent_requests.append({"path": PushNotifications.PATH, "body": body})
		return true
	if _push == null:
		_push_pending = false
		return false
	var err := _push.request(config.url + PushNotifications.PATH, rest_headers(), HTTPClient.METHOD_POST,
			JSON.stringify(body))
	if err != OK:
		handle_push(HTTPRequest.RESULT_CANT_CONNECT, 0, "")
	return true


## Obsługa odpowiedzi zapisu tokenu (bez sieci, wołana też z testów). Treści nie logujemy.
func handle_push(result: int, code: int, _body: String) -> void:
	_push_pending = false
	push_token_saved.emit(outcome_of(result, code) == Outcome.OK)


## Dane powtórki obrony `attack_id` (#29); odpowiedź w `replay_loaded`. False: brak sieci albo inne
## żądanie ataku jeszcze trwa.
func load_replay(attack_id: String) -> bool:
	return _attack_send(AttackCall.REPLAY, AttackReplay.PATH, AttackReplay.request(attack_id))


## Start ataku na gracza `defender_id` armią `army` (oddziały [rodzaj, liczba]); odpowiedź przychodzi
## w `attack_started`. False: brak sieci albo inne żądanie ataku jeszcze trwa (wtedy nic nie idzie).
func start_attack(defender_id: String, army: Array) -> bool:
	return _attack_send(AttackCall.START, AttackStart.PATH, AttackStart.request_player(defender_id, army))


## Start ataku na zamek-bota `bot_idx` (#242, ranking PvE) armią `army`; odpowiedź w `attack_started`
## (z `bot_idx`). False: brak sieci albo inne żądanie ataku jeszcze trwa.
func start_bot_attack(bot_idx: int, army: Array) -> bool:
	return _attack_send(AttackCall.START, AttackStart.PATH, AttackStart.request_bot(bot_idx, army))


## Wynik ataku (`AttackFinish.request` / `PlayerCastle.finish_request`); odpowiedź w `attack_finished`.
## Ponowienie tej samej treści po błędzie sieci jest bezpieczne: serwer zwraca zapisany wynik.
func finish_attack(body: Dictionary) -> bool:
	return _attack_send(AttackCall.FINISH, AttackFinish.PATH, body)


## Start fali PvE `wave` na serwerze (#288); odpowiedź w `wave_started`. False: brak sieci albo inne
## żądanie ataku jeszcze trwa (wtedy fala idzie bez serwera i bez nagrody).
func start_wave(wave: int) -> bool:
	return _attack_send(AttackCall.WAVE_START, WaveReport.PATH, WaveReport.start_request(wave))


## Wynik fali PvE (WaveReport.finish); odpowiedź w `wave_finished`. Ponowienie tej samej treści po błędzie
## sieci jest bezpieczne: serwer zwraca zapisany wynik bez drugiej nagrody.
func finish_wave(body: Dictionary) -> bool:
	return _attack_send(AttackCall.WAVE_FINISH, WaveReport.PATH, body)


## Zatwierdzenie planu ataku na gracza (#28) z planem `plan` (#29); pełne kopie, zapisany plan i badania
## przychodzą w `attack_launched`. Ponowienie po błędzie sieci jest bezpieczne: serwer zwraca te same
## kopie i plan z pierwszego zatwierdzenia.
func launch_attack(attack_id: String, plan: AttackPlan, general: int = -1) -> bool:
	return _attack_send(AttackCall.LAUNCH, AttackLaunch.PATH, AttackLaunch.request(attack_id, plan, general))


## Zwiad na gracza `defender_id` (#28); odpowiedź w `scout_sent`. False: brak sieci albo inne
## żądanie zwiadu w toku.
func send_scout(defender_id: String, duration: int) -> bool:
	return _scout_send(ScoutCall.SEND, ScoutNet.SEND_PATH, ScoutNet.request(defender_id, duration))


## Raporty zwiadu (#28); odpowiedź w `scout_reports_loaded`.
func load_scout_reports() -> bool:
	return _scout_send(ScoutCall.REPORTS, ScoutNet.REPORTS_PATH, {})


func is_scout_pending() -> bool:
	return _scout_call != ScoutCall.NONE


## Obsługa odpowiedzi `scout` / `scout_reports` (bez sieci, wołana też z testów).
func handle_scout(call: int, result: int, code: int, body: String) -> void:
	_scout_call = ScoutCall.NONE
	var error := edge_error(result, code, body)
	match call:
		ScoutCall.SEND:
			var send := ScoutNet.parse_send(SupabaseConfig.parse_json(body)) if error.is_empty() else {}
			if error.is_empty() and send.is_empty():
				error = REJECTED_ERROR
			scout_sent.emit(send, error)
		ScoutCall.REPORTS:
			if not error.is_empty():
				scout_reports_loaded.emit([] as Array[Dictionary], false)
			else:
				scout_reports_loaded.emit(ScoutNet.parse_reports(SupabaseConfig.parse_json(body)), true)


func _scout_send(call: int, path: String, body: Dictionary) -> bool:
	if _scout_call != ScoutCall.NONE or not is_online() or user_id().is_empty():
		return false
	_scout_call = call
	if fake_transport:
		sent_requests.append({"call": call, "path": path, "body": body})
		return true
	if _scout == null:
		_scout_call = ScoutCall.NONE
		return false
	var err := _scout.request(config.url + path, rest_headers(), HTTPClient.METHOD_POST, JSON.stringify(body))
	if err != OK:
		handle_scout(call, HTTPRequest.RESULT_CANT_CONNECT, 0, "")
	return true


func _on_scout_completed(result: int, code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	note_status(code)
	handle_scout(_scout_call, result, code, body.get_string_from_utf8())


## Katalog sklepu (#408, `public.shop_catalog`); odpowiedź w `shop_loaded`. False: brak sieci albo inne żądanie
## sklepu jeszcze trwa.
func load_shop() -> bool:
	return _shop_send(ShopCall.CATALOG, ShopNet.CATALOG_PATH, {})


## Odbiór oferty `offer_id` (#408, Edge Function `shop_claim`); odpowiedź w `shop_claimed`. False: brak sieci albo
## inne żądanie sklepu jeszcze trwa.
func claim_offer(offer_id: int) -> bool:
	return _shop_send(ShopCall.CLAIM, ShopNet.CLAIM_PATH, ShopNet.claim_request(offer_id))


## Czy żądanie sklepu jest w drodze.
func is_shop_pending() -> bool:
	return _shop_call != ShopCall.NONE


## Obsługa odpowiedzi sklepu (bez sieci, wołana też z testów).
func handle_shop(call: int, result: int, code: int, body: String) -> void:
	_shop_call = ShopCall.NONE
	if call == ShopCall.CATALOG:
		if outcome_of(result, code) != Outcome.OK:
			shop_loaded.emit([] as Array[ShopNet.Group], false)
			return
		shop_loaded.emit(ShopNet.parse_catalog(SupabaseConfig.parse_json(body), _now_ms()), true)
	elif call == ShopCall.CLAIM:
		var error := edge_error(result, code, body)
		var claim := ShopNet.parse_claim(SupabaseConfig.parse_json(body)) if error.is_empty() else {}
		if error.is_empty() and claim.is_empty():
			error = REJECTED_ERROR
		shop_claimed.emit(claim, error)


func _shop_send(call: int, path: String, body: Dictionary) -> bool:
	if _shop_call != ShopCall.NONE or not is_online() or user_id().is_empty():
		return false
	_shop_call = call
	if fake_transport:
		sent_requests.append({"call": call, "path": path, "body": body})
		return true
	if _shop == null:
		_shop_call = ShopCall.NONE
		return false
	var err := _shop.request(config.url + path, rest_headers(), HTTPClient.METHOD_POST, JSON.stringify(body))
	if err != OK:
		handle_shop(call, HTTPRequest.RESULT_CANT_CONNECT, 0, "")
	return true


func _on_shop_completed(result: int, code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	note_status(code)
	handle_shop(_shop_call, result, code, body.get_string_from_utf8())


func is_attack_pending() -> bool:
	return _attack_call != AttackCall.NONE


## Obsługa odpowiedzi `start_attack` / `finish_attack` / `pve_wave` (bez sieci, wołana też z testów).
func handle_attack(call: int, result: int, code: int, body: String) -> void:
	_attack_call = AttackCall.NONE
	var error := edge_error(result, code, body)
	match call:
		AttackCall.START:
			var start := AttackStart.parse_response(SupabaseConfig.parse_json(body)) if error.is_empty() else {}
			if error.is_empty() and start.is_empty():
				error = REJECTED_ERROR  # niepełna odpowiedź: nie ma czego atakować
			if error == AttackStart.BOT_LOCKED:
				# #386: zablokowany zamek-bot; serwer podaje swój postęp kampanii, żeby gra go wyrównała
				var beaten := AttackStart.locked_progress(SupabaseConfig.parse_json(body))
				if beaten >= 0:
					start = {"bots_beaten": beaten}
			attack_started.emit(start, error)
		AttackCall.FINISH:
			var finish := AttackFinish.parse_response(SupabaseConfig.parse_json(body)) if error.is_empty() else {}
			if error.is_empty() and finish.is_empty():
				error = NETWORK_ERROR  # niepełna odpowiedź: ponowienie zwróci zapisany wynik
			var loot: Array[int] = []
			if error.is_empty():
				loot = finish["loot"] as Array[int]
			attack_finished.emit(loot, error)
		AttackCall.LAUNCH:
			var launch := AttackLaunch.parse_response(SupabaseConfig.parse_json(body)) if error.is_empty() else {}
			if error.is_empty() and launch.is_empty():
				error = NETWORK_ERROR  # niepełna odpowiedź: ponowienie zwróci te same kopie
			attack_launched.emit(launch, error)
		AttackCall.REPLAY:
			var replay := AttackReplay.parse_response(SupabaseConfig.parse_json(body)) if error.is_empty() else {}
			if error.is_empty() and replay.is_empty():
				error = REJECTED_ERROR  # nieczytelna powtórka: ponowienie da to samo
			replay_loaded.emit(replay, error)
		AttackCall.WAVE_START:
			var wave := WaveReport.parse_start(SupabaseConfig.parse_json(body)) if error.is_empty() else {}
			if error.is_empty() and wave.is_empty():
				error = REJECTED_ERROR  # niepełna odpowiedź: fala idzie bez serwera
			wave_started.emit(wave, error)
		AttackCall.WAVE_FINISH:
			var done := WaveReport.parse_finish(SupabaseConfig.parse_json(body)) if error.is_empty() else {}
			if error.is_empty() and done.is_empty():
				error = NETWORK_ERROR  # niepełna odpowiedź: ponowienie zwróci zapisany wynik
			var reward: Array[int] = []
			if error.is_empty():
				reward = done["reward"] as Array[int]
			wave_finished.emit(reward, error)


## Wysyła zaległy zapis od razu (przy wyjściu z gry), bez czekania na `PUSH_INTERVAL_S`.
func flush() -> void:
	_push_wait = 0.0
	_castle_pump()


## Zamek z `castle_restored` leży już w zapisie na telefonie: od teraz telefon zna rewizję serwera.
func confirm_restore() -> void:
	if _pull_revision < 0:
		return
	sync_state.restore_pending = false
	_castle_saved(_pull_revision)
	_pull_revision = -1


## Zapis zamku z serwera na telefonie się nie udał. Do końca sesji nic nie wysyłamy, a `restore_pending`
## zostaje, więc przy następnym starcie zamek znowu spróbuje wrócić zamiast nadpisać serwer.
func restore_failed() -> void:
	_pull_revision = -1
	_castle_hold = true


## „Zacznij od nowa” (#23): następny zapis nadpisuje zamek na serwerze, a nie przywraca starego.
func mark_new_game() -> void:
	if sync_state == null:
		sync_state = CastleSync.SyncState.load_from(sync_path)
	sync_state.force_push = true
	sync_state.save(sync_path)


# --- Logika bez sieci (testy) ------------------------------------------------------------------

static func headers_for(key: String, access_token: String) -> PackedStringArray:
	var h := PackedStringArray(["apikey: " + key, "Content-Type: application/json",
			"%s: %d" % [ClientVersion.HEADER, ClientVersion.current_code()]])
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


## Kod błędu odpowiedzi Edge Function: pusty tekst dla 2xx, NETWORK_ERROR, gdy odpowiedzi nie ma albo
## można ją ponowić (outcome_of), a przy odrzuceniu kod z `{"error": "<kod>"}` (tylko litery i `_`)
## albo REJECTED_ERROR. Treści odpowiedzi nie logujemy.
static func edge_error(result: int, code: int, body: String) -> String:
	var outcome := outcome_of(result, code)
	if outcome == Outcome.OK:
		return ""
	var data: Variant = SupabaseConfig.parse_json(body)
	var raw: Variant = (data as Dictionary).get("error") if data is Dictionary else null
	var text := raw as String if raw is String else ""
	var safe := not text.is_empty() and text.length() <= 32
	for ch in text:
		if not (ch == "_" or (ch >= "a" and ch <= "z")):
			safe = false
	if outcome == Outcome.NETWORK:
		# 429 (limit startów) też jest „spróbuj później”, ale gracz ma dostać o nim komunikat
		return text if safe and code == 429 else NETWORK_ERROR
	return text if safe else REJECTED_ERROR


## Kody Auth, po których token odświeżania na pewno nie wróci: unieważniony, zużyty, sesja albo
## konto usunięte (także przez czyszczenie nieaktywnych kont gości, migracja `purge_inactive_guests`).
const DEAD_REFRESH_CODES: Array[String] = [
	"refresh_token_not_found", "refresh_token_already_used", "session_not_found", "session_expired",
	"user_not_found", "user_banned", "bad_jwt",
]


## Serwer Auth odrzucił token odświeżania na stałe (400/401/403 z kodem GoTrue `error_code` albo
## starszym `"error": "invalid_grant"`). Inne odmowy nie kasują sesji. Treści odpowiedzi nie logujemy.
static func refresh_token_dead(code: int, body: String) -> bool:
	if code != 400 and code != 401 and code != 403:
		return false
	var data: Variant = SupabaseConfig.parse_json(body)
	if not data is Dictionary:
		return false
	var d := data as Dictionary
	var error_code: Variant = d.get("error_code")
	if error_code is String and DEAD_REFRESH_CODES.has(error_code as String):
		return true
	var error: Variant = d.get("error")
	return error is String and (error as String) == "invalid_grant"


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
			if session.save(session_path) != OK:
				# bez treści i tokenów (skill `user-data-privacy`): sesja zostaje w pamięci, a następny
				# zapis (odświeżenie) spróbuje znowu
				push_warning("Nie udało się zapisać sesji konta na telefonie")
			_failures = 0
			_set_state(State.ONLINE)
			return
		outcome = Outcome.NETWORK  # niepełna odpowiedź: spróbujemy jeszcze raz
	if outcome == Outcome.REJECTED and call == Call.REFRESH and not refresh_token_dead(code, body):
		# Odmowa bez znanego kodu Auth (np. pośrednik w sieci): sesji nie wyrzucamy, bo nowe konto
		# oznacza utratę zamku na serwerze. Ponawiamy jak przy braku sieci.
		outcome = Outcome.NETWORK
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


func _on_version_completed(result: int, code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	handle_version(result, code, body.get_string_from_utf8())


func _on_rpc_completed(result: int, code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	note_status(code)
	handle_targets(result, code, body.get_string_from_utf8())


func _on_attack_completed(result: int, code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	note_status(code)
	handle_attack(_attack_call, result, code, body.get_string_from_utf8())


func _on_ranking_completed(result: int, code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	note_status(code)
	handle_ranking(result, code, body.get_string_from_utf8())


func _on_defenses_completed(result: int, code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	note_status(code)
	handle_defenses(result, code, body.get_string_from_utf8())


func _on_reports_completed(result: int, code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	note_status(code)
	handle_reports(result, code, body.get_string_from_utf8())


func _on_push_completed(result: int, code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	note_status(code)
	handle_push(result, code, body.get_string_from_utf8())


func _attack_send(call: int, path: String, body: Dictionary) -> bool:
	if _attack_call != AttackCall.NONE or not is_online() or user_id().is_empty():
		return false
	_attack_call = call
	if fake_transport:
		sent_requests.append({"call": call, "path": path, "body": body})
		return true
	if _attack == null:
		_attack_call = AttackCall.NONE
		return false
	var err := _attack.request(config.url + path, rest_headers(), HTTPClient.METHOD_POST, JSON.stringify(body))
	if err != OK:
		handle_attack(call, HTTPRequest.RESULT_CANT_CONNECT, 0, "")
	return true


func _on_rest_completed(result: int, code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	note_status(code)
	handle_castle_rest(_castle_call, result, code, body.get_string_from_utf8())


## Obsługa odpowiedzi REST synchronizacji zamku (bez sieci, wołana też z testów).
func handle_castle_rest(call: int, result: int, code: int, body: String) -> void:
	_castle_call = CastleCall.NONE
	if call == CastleCall.NONE:
		return
	var outcome := outcome_of(result, code)
	if outcome != Outcome.OK:
		if code == CastleSync.REJECTED_HTTP and (call == CastleCall.PUSH or call == CastleCall.INSERT):
			_castle_rejected(call)
			return
		_castle_failed(call, code)
		if call == CastleCall.GET:
			castle_checked.emit()
		return
	var rows: Variant = SupabaseConfig.parse_json(body)
	match call:
		CastleCall.GET:
			if not _castle_on_get(CastleSync.first_row(rows)):
				castle_checked.emit()
		CastleCall.INSERT, CastleCall.PUSH:
			var revision := CastleSync.revision_from_rows(rows)
			if revision < 0:
				# zapis nie trafił w wiersz: ktoś zapisał zamek w międzyczasie, czytamy od nowa
				_castle_conflict()
				return
			_failures_castle = 0
			_conflicts = 0
			_castle_saved(revision)
			var delta := CastleSync.loot_from_rows(rows)
			if delta.any(func(v: int) -> bool: return v != 0):
				loot_applied.emit(delta)
			_castle_send(CastleCall.DEFENSE_PATCH, HTTPClient.METHOD_PATCH, CastleSync.defense_path(user_id()),
					CastleSync.update_body(_sent_save_version, _sent_defense), true)
		CastleCall.DEFENSE_PATCH:
			if CastleSync.first_row(rows).is_empty():
				_castle_send(CastleCall.DEFENSE_INSERT, HTTPClient.METHOD_POST, CastleSync.DEFENSE_PATH,
						CastleSync.defense_insert_body(user_id(), _sent_save_version, _sent_defense), false)
			else:
				_castle_send_nickname()
		CastleCall.DEFENSE_INSERT:
			_castle_send_nickname()
		CastleCall.NICKNAME:
			sync_state.nickname = _sent_nickname
			sync_state.save(sync_path)
			_castle_pump()


## Kolejny krok synchronizacji, gdy nic nie trwa: odczyt zamku (raz na sesję konta i po konflikcie)
## albo zapis, gdy minęła przerwa.
func _castle_pump() -> void:
	if update_blocked:
		return
	if _castle_call != CastleCall.NONE or _castle_hold or not (_castle_dirty or _defense_dirty):
		return
	if not is_online() or (_rest == null and not fake_transport) or user_id().is_empty():
		return
	if _checked_user != user_id():
		_castle_send(CastleCall.GET, HTTPClient.METHOD_GET, CastleSync.read_path(user_id()), {}, false)
		return
	if _push_wait > 0.0 or not _can_push:
		return
	if _castle_dirty:
		_castle_push()
	else:
		_defense_push()


## Decyzja po odczycie zamku; true, gdy zamek wraca z serwera (`castle_restored`).
func _castle_on_get(row: Dictionary) -> bool:
	var uid := user_id()
	_checked_user = uid
	if not row.is_empty() and int(row.get("save_version", 0)) > SaveGame.FORMAT_VERSION:
		# zamek zapisała nowsza wersja gry: nie nadpisujemy go do końca sesji
		_castle_hold = true
		return false
	# nieudane przywrócenie z poprzedniej sesji liczy się jak start bez zapisu
	var fresh := local_fresh or sync_state.restore_pending_for(uid)
	var action := CastleSync.decide(_castle_map_seed, sync_state.revision_for(uid), fresh,
			sync_state.force_push, _can_push, row)
	if _force_pull:
		# serwer odrzucił stan z telefonu (#274): wygrywa zamek z serwera, a bez niego nic nie wysyłamy
		_force_pull = false
		if CastleSync.save_from_row(row).is_empty():
			_castle_hold = true
			_castle_dirty = false
			return false
		action = CastleSync.Action.PULL
	match action:
		CastleSync.Action.INSERT:
			_castle_dirty = false
			_capture_sent()
			_castle_send(CastleCall.INSERT, HTTPClient.METHOD_POST, CastleSync.insert_path(),
					CastleSync.insert_body(uid, _castle_map_seed, _sent_save_version, _sent_data), true)
		CastleSync.Action.PUSH:
			_base_revision = int(row.get("revision", 0))
			_push_wait = 0.0
			_castle_push()
		CastleSync.Action.PULL:
			# rewizja serwera trafi na telefon dopiero razem z zamkiem (confirm_restore); do tego czasu
			# znacznik restore_pending nie pozwala nadpisać serwera starym zamkiem z telefonu
			_castle_hold = true
			_castle_dirty = false
			_defense_dirty = false
			_pull_revision = int(row.get("revision", 0))
			if sync_state.player_id != uid:
				sync_state.player_id = uid
				sync_state.revision = -1
			sync_state.restore_pending = true
			sync_state.save(sync_path)
			var id := CastleSync.identity_from_row(row)
			castle_restored.emit(CastleSync.save_from_row(row), id.to_dict() if id != null else {})
			return true
		_:
			# bez tożsamości: zamek zostaje na telefonie; odczytamy go znowu przy następnym zapisie
			_checked_user = ""
			_castle_dirty = false
	return false


func _castle_push() -> void:
	if _base_revision < 0:
		_base_revision = sync_state.revision_for(user_id())
	_castle_dirty = false
	_defense_dirty = false
	_capture_sent()
	_push_wait = PUSH_INTERVAL_S
	_castle_send(CastleCall.PUSH, HTTPClient.METHOD_PATCH, CastleSync.push_path(user_id(), _base_revision),
			CastleSync.update_body(_sent_save_version, _sent_data), true)


## Ponawia samą obronę i nick (zamek już jest na serwerze), z najnowszego stanu z gry.
func _defense_push() -> void:
	_defense_dirty = false
	_capture_sent()
	_push_wait = PUSH_INTERVAL_S
	_castle_send(CastleCall.DEFENSE_PATCH, HTTPClient.METHOD_PATCH, CastleSync.defense_path(user_id()),
			CastleSync.update_body(_sent_save_version, _sent_defense), true)


## Zamek na serwerze ma rewizję `revision` i jest zgodny z telefonem.
func _castle_saved(revision: int) -> void:
	_base_revision = revision
	sync_state.player_id = user_id()
	sync_state.revision = revision
	sync_state.force_push = false
	sync_state.save(sync_path)


func _castle_conflict() -> void:
	_castle_dirty = true
	_checked_user = ""
	_base_revision = -1
	_conflicts += 1
	if _conflicts > MAX_CONFLICTS:
		# ktoś stale zapisuje ten zamek: czekamy na kolejny zapis z gry
		_castle_dirty = false
		return
	_push_wait = 0.0
	_castle_pump()


## Serwer odrzucił zamek spoza limitów surowców (#274). Ten sam zapis nie przejdzie, więc czytamy zamek
## z serwera i przywracamy go na telefon (`_force_pull`). Odrzucone założenie zamku (na serwerze nic
## nie ma) zatrzymuje synchronizację do końca sesji.
func _castle_rejected(call: int) -> void:
	_failures_castle = 0
	_conflicts = 0
	_base_revision = -1
	castle_rejected.emit()
	if call == CastleCall.INSERT:
		_castle_hold = true
		_castle_dirty = false
		return
	_force_pull = true
	_castle_dirty = true
	_checked_user = ""
	_push_wait = 0.0
	_castle_pump()


## Błąd sieci albo odrzucone żądanie: zaległy zamek pójdzie po przerwie (jak próby połączenia).
func _castle_failed(call: int, code: int) -> void:
	if call == CastleCall.INSERT and code == 409:
		# zamek już jest (np. założony z innego telefonu): czytamy go i decydujemy od nowa
		_castle_conflict()
		return
	if call == CastleCall.GET or call == CastleCall.INSERT or call == CastleCall.PUSH:
		_castle_dirty = true
	if call == CastleCall.GET or call == CastleCall.INSERT:
		_checked_user = ""
	if call == CastleCall.DEFENSE_PATCH or call == CastleCall.DEFENSE_INSERT or call == CastleCall.NICKNAME:
		# zamek już jest na serwerze, a start_attack kopiuje obronę z defense_layouts: ponowić obronę
		_defense_dirty = true
	_failures_castle += 1
	_push_wait = float(retry_delay(_failures_castle))


func _castle_send_nickname() -> void:
	if _sent_nickname.is_empty() or _sent_nickname == sync_state.nickname:
		_castle_pump()
		return
	_castle_send(CastleCall.NICKNAME, HTTPClient.METHOD_PATCH, CastleSync.nickname_path(user_id()),
			{"nickname": _sent_nickname}, false)


## Zapamiętuje, co dokładnie idzie na serwer (gra może w tym czasie podmienić najnowszy stan).
func _capture_sent() -> void:
	_sent_save_version = _castle_save_version
	_sent_data = _castle_data
	_sent_defense = _defense_data
	_sent_nickname = _nickname


func _castle_send(call: int, method: int, path: String, body: Dictionary, representation: bool) -> void:
	if fake_transport:
		_castle_call = call
		sent_requests.append({"call": call, "method": method, "path": path, "body": body})
		return
	if _rest == null:
		return
	_castle_call = call
	var headers := rest_headers()
	if method != HTTPClient.METHOD_GET:
		headers.append("Prefer: return=representation" if representation else "Prefer: return=minimal")
	var payload := "" if method == HTTPClient.METHOD_GET else JSON.stringify(body)
	var err := _rest.request(config.url + path, headers, method, payload)
	if err != OK:
		handle_castle_rest(call, HTTPRequest.RESULT_CANT_CONNECT, 0, "")


func _set_state(s: int) -> void:
	if s == state:
		return
	state = s
	state_changed.emit(s)


static func _now() -> int:
	return int(Time.get_unix_time_from_system())


static func _now_ms() -> int:
	return int(Time.get_unix_time_from_system() * 1000.0)
