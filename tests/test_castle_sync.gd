extends TestCase
## Synchronizacja zamku i obrony z serwerem (#23, seed terenu z #166): treści żądań, decyzja po
## odczycie wiersza, stan rewizji i przebieg w kliencie (bez sieci, z `fake_transport`).

const SESSION_PATH := "user://test_castle_sync_session.json"
const SYNC_PATH := "user://test_castle_sync_state.json"
const UID := "00000000-0000-0000-0000-00000000000a"
const OTHER := "00000000-0000-0000-0000-00000000000b"
const SEED := 1337


func _identity() -> PlayerProfile.Identity:
	var id := PlayerProfile.Identity.new()
	id.player_name = "Mieszko"
	id.castle_name = "Gniezno"
	return id


## Wiersz zamku z serwera jak w odpowiedzi GET.
func _row(revision: int, save_version: int = SaveGame.FORMAT_VERSION, with_profile: bool = true) -> Dictionary:
	var save := SaveGame.to_dict(4242, BuildGrid.new(TerrainMap.generate(4242)), Economy.new(0), BuildQueue.new())
	var data := CastleSync.castle_data(save, _identity() if with_profile else null)
	return {"map_seed": 4242, "save_version": save_version, "revision": revision, "data": data}


## Klient w ONLINE z sesją konta UID, bez sieci; `revision` -1 = telefon jeszcze nie synchronizował.
func _client(revision: int = -1, fresh: bool = false) -> SupabaseClient:
	SupabaseSession.clear(SESSION_PATH)
	SaveGame.delete(SYNC_PATH)
	var c := SupabaseClient.new()
	c.setup(SupabaseConfig.parse(JSON.stringify({
		"url": "https://abc.supabase.co", "publishable_key": "sb_publishable_test123",
	})), SESSION_PATH, SYNC_PATH)
	c.fake_transport = true
	c.local_fresh = fresh
	if revision >= 0:
		c.sync_state.player_id = UID
		c.sync_state.revision = revision
	c.handle_auth(SupabaseClient.Call.SIGNUP, HTTPRequest.RESULT_SUCCESS, 200, JSON.stringify({
		"access_token": "t1", "refresh_token": "r1", "expires_in": 3600,
		"user": {"id": UID, "is_anonymous": true},
	}))
	return c


func _done(c: SupabaseClient) -> void:
	SupabaseSession.clear(SESSION_PATH)
	SaveGame.delete(SYNC_PATH)
	c.free()


## Odpowiedź serwera na ostatnie żądanie.
func _reply(c: SupabaseClient, code: int, body: Variant) -> void:
	var last: Dictionary = c.sent_requests[c.sent_requests.size() - 1]
	c.handle_castle_rest(int(last["call"]), HTTPRequest.RESULT_SUCCESS, code,
			JSON.stringify(body) if body != null else "")


func _last(c: SupabaseClient) -> Dictionary:
	return c.sent_requests[c.sent_requests.size() - 1] if not c.sent_requests.is_empty() else {}


func _sync(c: SupabaseClient, n: int = 1, can_push: bool = true) -> void:
	c.sync_castle(SEED, SaveGame.FORMAT_VERSION, {"n": n}, {"traps": [n]}, "Mieszko" if can_push else "",
			can_push)


func test_insert_includes_map_seed_update_does_not() -> bool:
	var data := {"grid": {"a": 1}}
	var insert := CastleSync.insert_body(UID, SEED, 9, data)
	assert_eq(insert["map_seed"], SEED, "INSERT niesie seed terenu")
	assert_eq(insert["player_id"], UID, "właściciel")
	assert_eq(insert["save_version"], 9, "wersja zapisu")
	assert_eq(insert["data"], data, "stan zamku")
	var update := CastleSync.update_body(9, data)
	assert_true(not update.has("map_seed"), "UPDATE nie zmienia seeda")
	assert_true(not update.has("player_id"), "UPDATE nie zmienia właściciela")
	assert_true(not update.has("revision"), "revision ustala serwer")
	assert_eq(update["data"], data, "dane w UPDATE")
	return true


func test_paths_and_parsing() -> bool:
	assert_true(CastleSync.is_valid_map_seed(1), "min")
	assert_true(CastleSync.is_valid_map_seed(WorldSeed.MAX_SEED), "max")
	assert_true(not CastleSync.is_valid_map_seed(0), "0 niedozwolone w castles")
	assert_true(not CastleSync.is_valid_map_seed(WorldSeed.MAX_SEED + 1), "powyżej 31 bitów")
	assert_eq(CastleSync.map_seed_from_rows([{"map_seed": 4242}]), 4242, "odczyt z GET")
	assert_eq(CastleSync.map_seed_from_rows([]), 0, "brak wiersza")
	assert_eq(CastleSync.own_path("abc"), "/rest/v1/castles?player_id=eq.abc", "filtr własnego")
	assert_eq(CastleSync.push_path("abc", 7), "/rest/v1/castles?player_id=eq.abc&revision=eq.7&select=revision",
			"zapis tylko od znanej rewizji")
	assert_eq(CastleSync.revision_from_rows([{"revision": 8}]), 8, "nowa rewizja")
	assert_eq(CastleSync.revision_from_rows([]), -1, "pusta odpowiedź = konflikt")
	assert_eq(CastleSync.revision_from_rows(null), -1, "zła odpowiedź")
	return true


func test_castle_data_round_trip_with_profile() -> bool:
	var save := SaveGame.to_dict(SEED, BuildGrid.new(TerrainMap.generate(SEED)), Economy.new(0), BuildQueue.new(),
			null, null, null, 2)
	var remote := CastleSync.castle_data(save, _identity())
	assert_true(not remote.has("world_seed"), "seed stoi w kolumnie map_seed")
	assert_true(not remote.has("version"), "wersja stoi w kolumnie save_version")
	assert_true(not remote.has("seal"), "Sprawdź zostaje na telefonie")
	assert_true(save.has("scout") and not remote.has("scout"), "zwiad (#28) zostaje na telefonie")
	assert_eq((remote["profile"] as Dictionary)["castle_name"], "Gniezno", "tożsamość z onboardingu")
	assert_true(save.has("world_seed") and save.has("version"), "lokalny zapis bez zmian")
	var row := {"map_seed": SEED, "save_version": SaveGame.FORMAT_VERSION, "revision": 3, "data": remote}
	var back := CastleSync.save_from_row(row)
	assert_eq(int(back["world_seed"]), SEED, "seed wraca do zapisu")
	assert_eq(int(back["version"]), SaveGame.FORMAT_VERSION, "wersja wraca do zapisu")
	assert_true(not back.has("profile"), "tożsamość nie trafia do zapisu zamku")
	var state := SaveGame.from_dict(back, 0)
	assert_true(state != null, "zamek z serwera się wczytuje")
	assert_eq(state.pve_cleared, 2, "postęp wraca")
	assert_eq(CastleSync.identity_from_row(row).player_name, "Mieszko", "imię wraca")
	assert_true(CastleSync.identity_from_row({"data": {}}) == null, "bez tożsamości")
	assert_true(CastleSync.save_from_row({"map_seed": 0, "save_version": 9, "data": {}}).is_empty(), "zły seed")
	assert_true(CastleSync.save_from_row({"map_seed": 5, "save_version": 99, "data": {}}).is_empty(),
			"format z nowszej gry")
	assert_true(CastleSync.save_from_row({"map_seed": 5, "save_version": 9, "data": []}).is_empty(), "dane nie są obiektem")
	assert_eq(CastleSync.defense_data({"defense": {"traps": [1]}}), {"traps": [1]}, "obrona do defense_layouts")
	return true


func test_decide() -> bool:
	var A := CastleSync.Action
	var row := _row(5)
	assert_eq(CastleSync.decide(SEED, -1, false, false, true, {}), A.INSERT, "brak zamku: założenie")
	assert_eq(CastleSync.decide(SEED, -1, false, false, false, {}), A.NOP, "bez tożsamości nie zakładamy")
	assert_eq(CastleSync.decide(0, -1, false, false, true, {}), A.NOP, "bez seeda nic")
	assert_eq(CastleSync.decide(SEED, -1, true, false, false, row), A.PULL, "reinstalacja: zamek wraca")
	assert_eq(CastleSync.decide(SEED, 5, true, false, true, row), A.PULL, "utracony zapis: zamek wraca")
	assert_eq(CastleSync.decide(SEED, -1, false, false, true, row), A.PUSH, "gra sprzed #23 zostaje")
	assert_eq(CastleSync.decide(SEED, 5, false, false, true, row), A.PUSH, "zgodna rewizja: zapis")
	assert_eq(CastleSync.decide(SEED, 3, false, false, true, row), A.PULL, "serwer nowszy: wygrywa")
	assert_eq(CastleSync.decide(SEED, 3, true, true, true, row), A.PUSH, "Zacznij od nowa nadpisuje")
	assert_eq(CastleSync.decide(SEED, 3, true, true, false, row), A.NOP, "nowa gra bez tożsamości czeka")
	assert_eq(CastleSync.decide(SEED, 5, false, false, true, _row(5, SaveGame.FORMAT_VERSION + 1)), A.NOP,
			"zamek z nowszej gry nietknięty")
	assert_eq(CastleSync.decide(SEED, 3, false, false, true, {"map_seed": 4242, "save_version": 9, "revision": 5,
			"data": "zepsute"}), A.PUSH, "nieczytelny zamek na serwerze nadpisuje telefon")
	# ten sam wiersz i stan zawsze dają tę samą decyzję
	assert_eq(CastleSync.decide(SEED, 3, false, false, true, row), CastleSync.decide(SEED, 3, false, false, true, row),
			"deterministycznie")
	return true


func test_sync_state_round_trip() -> bool:
	SaveGame.delete(SYNC_PATH)
	var s := CastleSync.SyncState.load_from(SYNC_PATH)
	assert_eq(s.revision_for(UID), -1, "bez pliku: brak rewizji")
	s.player_id = UID
	s.revision = 12
	s.force_push = true
	s.nickname = "Mieszko"
	assert_eq(s.save(SYNC_PATH), OK, "zapis")
	var back := CastleSync.SyncState.load_from(SYNC_PATH)
	assert_eq(back.revision_for(UID), 12, "rewizja wraca")
	assert_eq(back.revision_for(OTHER), -1, "rewizja innego konta się nie liczy")
	assert_true(back.force_push, "nowa gra czeka na zapis")
	assert_eq(back.nickname, "Mieszko", "ostatni nick")
	SaveGame.delete(SYNC_PATH)
	return true


## Reinstalacja na tym samym koncie: telefon bez zapisu dostaje zamek z serwera i nic nie wysyła.
func test_fresh_install_restores_castle() -> bool:
	var c := _client(-1, true)
	var got: Array = []
	c.castle_restored.connect(func(save: Dictionary, profile: Dictionary) -> void: got.append([save, profile]))
	_sync(c, 1, false)
	assert_eq(int(_last(c)["call"]), SupabaseClient.CastleCall.GET, "najpierw odczyt zamku, także bez tożsamości")
	_reply(c, 200, [_row(5)])
	assert_eq(got.size(), 1, "zamek wraca")
	assert_eq(int((got[0][0] as Dictionary)["world_seed"]), 4242, "z seedem terenu z serwera")
	assert_eq((got[0][1] as Dictionary)["player_name"], "Mieszko", "z tożsamością")
	var pending := CastleSync.SyncState.load_from(SYNC_PATH)
	assert_eq(pending.revision_for(UID), -1, "rewizja dopiero po zapisie zamku na telefonie")
	assert_true(pending.restore_pending_for(UID), "przywracanie w toku")
	c.confirm_restore()
	var done := CastleSync.SyncState.load_from(SYNC_PATH)
	assert_eq(done.revision_for(UID), 5, "telefon zna rewizję")
	assert_true(not done.restore_pending_for(UID), "przywracanie skończone")
	var sent := c.sent_requests.size()
	_sync(c, 2)
	c.flush()
	assert_eq(c.sent_requests.size(), sent, "do przeładowania sceny nic nie idzie na serwer")
	_done(c)
	return true


## Nieudany zapis zamku z serwera na telefonie: przy następnym starcie (już z zapisem lokalnym i starą
## rewizją) zamek znowu wraca, a stary zamek z telefonu nie nadpisuje serwera.
func test_failed_restore_does_not_push_over_server() -> bool:
	var c := _client(3, true)
	_sync(c, 1)
	_reply(c, 200, [_row(5)])
	c.restore_failed()
	var sent := c.sent_requests.size()
	_sync(c, 2)
	c.flush()
	assert_eq(c.sent_requests.size(), sent, "do końca sesji nic nie idzie")
	assert_eq(CastleSync.SyncState.load_from(SYNC_PATH).revision_for(UID), 3, "rewizja serwera nieutrwalona")
	SupabaseSession.clear(SESSION_PATH)
	c.free()
	# następny start: zapis lokalny jest (local_fresh false), sync.json zostaje
	var next := SupabaseClient.new()
	next.setup(SupabaseConfig.parse(JSON.stringify({
		"url": "https://abc.supabase.co", "publishable_key": "sb_publishable_test123",
	})), SESSION_PATH, SYNC_PATH)
	next.sync_state = CastleSync.SyncState.load_from(SYNC_PATH)
	next.fake_transport = true
	next.handle_auth(SupabaseClient.Call.SIGNUP, HTTPRequest.RESULT_SUCCESS, 200, JSON.stringify({
		"access_token": "t1", "refresh_token": "r1", "expires_in": 3600,
		"user": {"id": UID, "is_anonymous": true},
	}))
	var got: Array = []
	next.castle_restored.connect(func(save: Dictionary, _p: Dictionary) -> void: got.append(save))
	_sync(next, 3)
	_reply(next, 200, [_row(3)])
	assert_eq(got.size(), 1, "zamek znowu wraca, mimo zgodnej rewizji")
	assert_eq(int(_last(next)["call"]), SupabaseClient.CastleCall.GET, "bez zapisu na serwer")
	_done(next)
	return true


## Błąd obrony po udanym zapisie zamku: po przerwie idzie sama obrona (bez nowej rewizji zamku).
func test_defense_failure_retries_defense() -> bool:
	var c := _client(5)
	c.sync_state.nickname = "Mieszko"
	_sync(c, 1)
	_reply(c, 200, [_row(5)])
	_reply(c, 200, [{"revision": 6}])
	var defense := _last(c)
	assert_eq(int(defense["call"]), SupabaseClient.CastleCall.DEFENSE_PATCH, "obrona po zamku")
	c.handle_castle_rest(int(defense["call"]), HTTPRequest.RESULT_CANT_CONNECT, 0, "")
	assert_true(c._defense_dirty, "obrona czeka na ponowienie")
	assert_true(not c._castle_dirty, "zamek już na serwerze")
	c._process(float(SupabaseClient.retry_delay(1)) + 0.1)
	assert_eq(int(_last(c)["call"]), SupabaseClient.CastleCall.DEFENSE_PATCH, "ponowiona sama obrona")
	_reply(c, 200, [{"player_id": UID}])
	assert_true(not c._defense_dirty, "obrona doszła")
	assert_eq(c._castle_call, SupabaseClient.CastleCall.NONE, "koniec")
	_done(c)
	return true


## Zwykły zapis: PATCH od znanej rewizji, potem obrona (PATCH, a bez wiersza INSERT) i nick.
func test_push_chain_with_revision() -> bool:
	var c := _client(5)
	_sync(c, 1)
	_reply(c, 200, [_row(5)])
	var push := _last(c)
	assert_eq(int(push["call"]), SupabaseClient.CastleCall.PUSH, "zgodna rewizja: zapis")
	assert_true((push["path"] as String).contains("revision=eq.5"), "z kontrolą rewizji")
	assert_eq(int(push["method"]), HTTPClient.METHOD_PATCH, "PATCH")
	assert_true(not (push["body"] as Dictionary).has("map_seed"), "seed się nie zmienia")
	_reply(c, 200, [{"revision": 6}])
	assert_eq(c.sync_state.revision, 6, "nowa rewizja")
	assert_eq(CastleSync.SyncState.load_from(SYNC_PATH).revision_for(UID), 6, "rewizja na telefonie")
	assert_eq(int(_last(c)["call"]), SupabaseClient.CastleCall.DEFENSE_PATCH, "potem obrona")
	assert_eq(((_last(c)["body"] as Dictionary)["data"] as Dictionary)["traps"], [1], "układ obrony")
	_reply(c, 200, [])
	assert_eq(int(_last(c)["call"]), SupabaseClient.CastleCall.DEFENSE_INSERT, "brak wiersza obrony: założenie")
	assert_eq((_last(c)["body"] as Dictionary)["player_id"], UID, "własna obrona")
	_reply(c, 201, null)
	assert_eq(int(_last(c)["call"]), SupabaseClient.CastleCall.NICKNAME, "nick do players")
	assert_eq((_last(c)["body"] as Dictionary), {"nickname": "Mieszko"}, "tylko nick")
	_reply(c, 204, null)
	assert_eq(c.sync_state.nickname, "Mieszko", "nick zapamiętany")
	assert_eq(c._castle_call, SupabaseClient.CastleCall.NONE, "koniec")
	_done(c)
	return true


## Zapis najwyżej co PUSH_INTERVAL_S; flush (wyjście z gry) wysyła od razu i bez ponownego odczytu.
func test_push_is_throttled() -> bool:
	var c := _client(5)
	c.sync_state.nickname = "Mieszko"
	_sync(c, 1)
	_reply(c, 200, [_row(5)])
	_reply(c, 200, [{"revision": 6}])
	_reply(c, 200, [{"player_id": UID}])
	var sent := c.sent_requests.size()
	_sync(c, 2)
	_sync(c, 3)
	assert_eq(c.sent_requests.size(), sent, "w przerwie nic nie idzie")
	c._process(SupabaseClient.PUSH_INTERVAL_S + 0.1)
	assert_eq(c.sent_requests.size(), sent + 1, "po przerwie jeden zapis")
	assert_eq(int(_last(c)["call"]), SupabaseClient.CastleCall.PUSH, "bez ponownego odczytu")
	assert_true((_last(c)["path"] as String).contains("revision=eq.6"), "od nowej rewizji")
	assert_eq(((_last(c)["body"] as Dictionary)["data"] as Dictionary)["n"], 3, "najnowszy stan")
	_reply(c, 200, [{"revision": 7}])
	_reply(c, 200, [{"player_id": UID}])
	_sync(c, 4)
	c.flush()
	assert_eq(((_last(c)["body"] as Dictionary)["data"] as Dictionary)["n"], 4, "flush wysyła od razu")
	_done(c)
	return true


## Konflikt: ktoś zapisał zamek w międzyczasie, więc klient czyta go od nowa, a nowszy serwer wygrywa.
func test_conflict_rereads_and_server_wins() -> bool:
	var c := _client(5)
	var got: Array = []
	c.castle_restored.connect(func(save: Dictionary, _p: Dictionary) -> void: got.append(save))
	_sync(c, 1)
	_reply(c, 200, [_row(5)])
	_reply(c, 200, [])
	assert_eq(int(_last(c)["call"]), SupabaseClient.CastleCall.GET, "konflikt: ponowny odczyt")
	_reply(c, 200, [_row(8)])
	assert_eq(got.size(), 1, "nowszy zamek z serwera wraca na telefon")
	assert_eq(c.sync_state.revision, 5, "rewizja czeka na zapis zamku na telefonie")
	c.confirm_restore()
	assert_eq(c.sync_state.revision, 8, "od jego rewizji")
	_done(c)
	return true


## Zacznij od nowa: pusty start nie przywraca starego zamku, tylko go nadpisuje.
func test_new_game_overwrites_server() -> bool:
	var c := _client(3, true)
	c.mark_new_game()
	assert_true(CastleSync.SyncState.load_from(SYNC_PATH).force_push, "znacznik nowej gry na telefonie")
	var got: Array = []
	c.castle_restored.connect(func(save: Dictionary, _p: Dictionary) -> void: got.append(save))
	_sync(c, 1)
	_reply(c, 200, [_row(9)])
	assert_eq(got.size(), 0, "bez przywracania")
	assert_true((_last(c)["path"] as String).contains("revision=eq.9"), "zapis od rewizji serwera")
	_reply(c, 200, [{"revision": 10}])
	assert_true(not CastleSync.SyncState.load_from(SYNC_PATH).force_push, "po zapisie znacznik znika")
	_done(c)
	return true


## Pierwszy zamek na koncie: INSERT z seedem; bez tożsamości nic nie idzie na serwer.
func test_insert_only_with_identity() -> bool:
	var c := _client()
	_sync(c, 1, false)
	_reply(c, 200, [])
	var sent := c.sent_requests.size()
	assert_eq(int(_last(c)["call"]), SupabaseClient.CastleCall.GET, "bez tożsamości tylko odczyt")
	_sync(c, 2, true)
	assert_eq(c.sent_requests.size(), sent + 1, "po onboardingu odczyt od nowa")
	_reply(c, 200, [])
	var insert := _last(c)
	assert_eq(int(insert["call"]), SupabaseClient.CastleCall.INSERT, "założenie zamku")
	assert_eq((insert["body"] as Dictionary)["map_seed"], SEED, "z seedem terenu")
	_reply(c, 201, [{"revision": 0}])
	assert_eq(c.sync_state.revision_for(UID), 0, "rewizja startowa")
	assert_eq(int(_last(c)["call"]), SupabaseClient.CastleCall.DEFENSE_PATCH, "potem obrona")
	_done(c)
	return true


## Zamek z nowszej wersji gry na serwerze: ta wersja go nie wczytuje i nie nadpisuje.
func test_newer_format_on_server_is_left_alone() -> bool:
	var c := _client(5)
	var got: Array = []
	c.castle_restored.connect(func(save: Dictionary, _p: Dictionary) -> void: got.append(save))
	_sync(c, 1)
	_reply(c, 200, [_row(9, SaveGame.FORMAT_VERSION + 1)])
	var sent := c.sent_requests.size()
	_sync(c, 2)
	c.flush()
	assert_eq(c.sent_requests.size(), sent, "bez zapisu")
	assert_eq(got.size(), 0, "bez przywracania")
	_done(c)
	return true


## Błąd sieci: stan zostaje do wysłania i idzie po przerwie (jak próby połączenia), od odczytu.
func test_network_error_retries_later() -> bool:
	var c := _client(5)
	_sync(c, 1)
	_reply(c, 200, [_row(5)])
	var push := _last(c)
	c.handle_castle_rest(int(push["call"]), HTTPRequest.RESULT_CANT_CONNECT, 0, "")
	assert_true(c._castle_dirty, "stan czeka na wysłanie")
	var sent := c.sent_requests.size()
	c._process(1.0)
	assert_eq(c.sent_requests.size(), sent, "jeszcze nie")
	c._process(float(SupabaseClient.retry_delay(1)))
	assert_eq(c.sent_requests.size(), sent + 1, "ponowienie po przerwie")
	assert_eq(int(_last(c)["call"]), SupabaseClient.CastleCall.PUSH, "zapis od znanej rewizji")
	_done(c)
	return true


## Inne konto (np. nowe konto anonimowe po utracie tokenu): rewizja starego konta się nie liczy.
func test_other_account_does_not_reuse_revision() -> bool:
	var c := _client()
	c.sync_state.player_id = OTHER
	c.sync_state.revision = 40
	_sync(c, 1)
	_reply(c, 200, [_row(2)])
	assert_true((_last(c)["path"] as String).contains("revision=eq.2"), "zapis od rewizji nowego konta")
	_done(c)
	return true
