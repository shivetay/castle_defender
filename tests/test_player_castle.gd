extends TestCase
## Atak na gracza (#240): cel z odpowiedzi `start_attack` (zarys, donżon i zwiad, #28), pełna kopia
## zamku i obrony z `launch_attack`, bitwa z seedem z serwera, łup z surowych zapasów z kopii i treść
## `finish_attack`; klient Supabase bez sieci.

const MAIN := preload("res://scripts/main.gd")
const K := BuildingTypes.Kind
const U := UnitTypes.Unit
const DEFENDER := "00000000-0000-0000-0000-00000000000b"
const ATTACK := "00000000-0000-0000-0000-0000000000aa"
const UID := "00000000-0000-0000-0000-00000000000a"
const SESSION_PATH := "user://test_player_castle_session.json"
const SYNC_PATH := "user://test_player_castle_sync.json"
const STASH: Array[int] = [10000, 4000, 2000, 300]
const ARMY := [[U.AXE_WARRIOR, 10], [U.AXE_WARRIOR, 10], [U.RIDER, 5]]


## Kopia zamku obrońcy w kształcie `castles.data` (CastleSync.castle_data): dwór, donżon, jeden
## oddział załogi i zapasy STASH.
static func _castle(map_seed: int) -> Dictionary:
	var grid := BuildGrid.new(TerrainMap.generate(map_seed))
	grid.place(grid.manor_spot(WorldSeed.MANOR_MAX_RING), K.MANOR, 1)
	grid.place(grid.keep_spot(WorldSeed.KEEP_MAX_RING), K.KEEP, 1)
	var rec := Recruitment.new()
	rec.load_data({"squads": [[1, U.AXE_WARRIOR, 6]]}, grid, 0)
	var save := SaveGame.to_dict(map_seed, grid, Economy.new(0), BuildQueue.new(), null, null, rec)
	var castle := CastleSync.castle_data(save)
	(castle["economy"] as Dictionary)["amounts"] = STASH.duplicate()
	return castle


## Odpowiedź `start_attack` jak z serwera (#28): zarys [x, y, szer., wys.] i donżon z kopii zamku.
static func _raw_start(battle_seed: int = 77) -> Dictionary:
	var map_seed := WorldSeed.first_playable(4242)
	var footprint: Array = []
	var keep: Array = []
	for e: Variant in ((_castle(map_seed)["grid"] as Dictionary)["buildings"] as Array):
		var a := e as Array
		footprint.append([a[3], a[4], a[5], a[6]])
		if int(a[1]) == K.KEEP:
			keep = [a[3], a[4], a[5], a[6]]
	return {"id": ATTACK, "map_seed": map_seed, "battle_seed": battle_seed, "defender_id": DEFENDER,
			"footprint": footprint, "keep": keep, "intel": {}}


static func _start(battle_seed: int = 77) -> Dictionary:
	return AttackStart.parse_response(_raw_start(battle_seed))


## Plan zapisany na serwerze przy zatwierdzeniu (#29): Szturm frontalny dla każdego oddziału ARMY.
static func _server_plan() -> Array:
	var p := AttackPlan.new()
	AttackPlanner.fit_plan(p, ARMY.size(), AttackPlanner.unit_list(ARMY))
	return p.to_server()


static func _launch() -> Dictionary:
	return {"id": ATTACK, "castle": _castle(WorldSeed.first_playable(4242)), "defense": {},
			"plan": _server_plan(), "techs": [] as Array[String]}


## Cel po zatwierdzeniu planu (pełna kopia z `launch_attack`).
static func _launched(battle_seed: int = 77) -> PlayerCastle:
	var pc := PlayerCastle.from_start(_start(battle_seed), ARMY, 0)
	pc.apply_launch(_launch())
	return pc


static func _fight(pc: PlayerCastle) -> Battle:
	var b := pc.create_battle()
	b.run()
	return b


func test_target_from_start_response() -> bool:
	var pc := PlayerCastle.from_start(_start(), ARMY, 1000)
	assert_true(pc != null, "cel z zarysu i donżonu")
	assert_eq(pc.attack_id, ATTACK, "id ataku")
	assert_eq(pc.defender_id, DEFENDER, "obrońca")
	assert_eq(pc.battle_seed, 77, "seed bitwy z serwera")
	assert_eq(pc.target.objective, pc.target.grid.keep_id(), "cel to donżon")
	assert_true(pc.target.objective != 0, "donżon jest")
	assert_eq(pc.target.grid.buildings.size(), 2, "plan zna cały zarys")
	assert_true(not pc.is_launched() and pc.target.defenders.is_empty(), "przed zatwierdzeniem bez załogi (#28)")
	assert_true(pc.intel.is_empty(), "bez zwiadu nic odsłonięte")
	var keep := pc.target.grid.buildings[pc.target.objective]
	assert_true(not pc.apply_launch({"id": "inny", "castle": _castle(4242)}), "kopia innego ataku odrzucona")
	assert_true(pc.apply_launch(_launch()), "pełna kopia po zatwierdzeniu")
	assert_true(pc.is_launched(), "zatwierdzony")
	assert_eq(pc.target.grid.buildings[pc.target.objective], keep, "ten sam donżon: cele planu zostają")
	assert_eq(pc.target.defenders, [[U.AXE_WARRIOR, 6]], "załoga z kopii")
	assert_eq(pc.stash, STASH, "zapasy z kopii bez zmian (jak serwer)")
	assert_eq(pc.army, ARMY, "armia ze startu")
	return true


func test_bad_start_is_rejected() -> bool:
	assert_true(PlayerCastle.from_start({}, ARMY, 0) == null, "pusta odpowiedź")
	var bot := AttackStart.parse_response({"id": ATTACK, "map_seed": 5, "battle_seed": 1, "bot_idx": 2})
	assert_true(PlayerCastle.from_start(bot, ARMY, 0) == null, "atak na bota to nie cel-gracz")
	var start := _start()
	assert_true(PlayerCastle.from_start(start, [], 0) == null, "bez armii")
	var no_keep := _raw_start()
	no_keep.erase("keep")
	assert_true(AttackStart.parse_response(no_keep).is_empty(), "bez donżonu nie ma celu")
	var pc := PlayerCastle.from_start(start, ARMY, 0)
	assert_true(not pc.apply_launch({"id": ATTACK, "castle": "zamek"}), "kopia nie jest obiektem")
	var empty_grid := _launch()
	(empty_grid["castle"] as Dictionary)["grid"] = {}
	assert_true(not pc.apply_launch(empty_grid), "kopia bez donżonu")
	assert_true(not pc.is_launched(), "zła kopia nie zatwierdza")
	assert_true(AttackLaunch.parse_response({"castle": {}}).is_empty(), "pusta kopia to odmowa")
	return true


## Zapasy jak w `end_attack`: liczba całkowita 0..10 000 000, inaczej 0.
func test_stash_reads_like_server() -> bool:
	assert_eq(PlayerCastle.stash_of({"economy": {"amounts": [5, -1, 2.5, 20000000]}}), [5, 0, 0, 0] as Array[int],
			"złe wpisy to 0")
	assert_eq(PlayerCastle.stash_of({"economy": {"amounts": [7.0, "9"]}}), [7, 0, 0, 0] as Array[int],
			"liczba z JSON jako float i brakujące surowce")
	assert_eq(PlayerCastle.stash_of({}), [0, 0, 0, 0] as Array[int], "bez ekonomii")
	return true


## Ten sam start daje zawsze ten sam przebieg (powtórka na serwerze, #29), inny seed bitwy inny.
func test_battle_is_deterministic() -> bool:
	var a := _fight(_launched())
	var b := _fight(_launched())
	assert_true(a.winner != Battle.Winner.NONE, "bitwa się kończy")
	assert_eq(a.checksum(), b.checksum(), "ta sama kopia i seed, ta sama bitwa")
	assert_eq(a.tick, b.tick, "ten sam czas")
	var c := _fight(_launched(78))
	assert_true(c.checksum() != a.checksum(), "inny seed bitwy, inny przebieg")
	return true


## Łup w limitach serwera: na surowiec niechroniona część × 20 procent × procent łupu, razem
## najwyżej capacity ocalałych; treść żądania z ocalałymi na każdy oddział startu.
func test_result_within_server_limits() -> bool:
	var pc := _launched()
	var b := _fight(pc)
	var r := pc.result_of(b)
	var alive := b.survivors(Battle.Side.ATTACKER)
	var pct := maxi(r.percent, 50) if r.won else 0
	var sum := 0
	for res in EconomyConfig.count():
		assert_true(r.loot[res] <= STASH[res] * 50 / 100 * 20 / 100 * pct / 100, "surowiec w limicie")
		sum += r.loot[res]
	assert_true(sum <= BattleResult.carry_capacity(ARMY, alive), "łup w capacity")
	var body := pc.finish_request(b, r)
	assert_eq(body["attack_id"], ATTACK, "id ataku")
	assert_eq((body["survivors"] as Array).size(), ARMY.size(), "ocaleli na każdy oddział")
	assert_eq(body["loot"], r.loot, "łup z wyniku")
	assert_eq(body["result"], r.to_server(), "wynik dla serwera")
	return true


func test_launch_rules() -> bool:
	var pc := PlayerCastle.from_start(_start(), ARMY, 1000)
	assert_true(pc.can_launch(1000 + PlayerCastle.PLAN_LIMIT_S), "w limicie planu")
	assert_true(not pc.can_launch(1001 + PlayerCastle.PLAN_LIMIT_S), "za długo")
	assert_eq(MAIN.player_attack_problem(pc, ARMY.duplicate(true), 1000), "", "ta sama armia")
	assert_true(not MAIN.player_attack_problem(pc, [[U.AXE_WARRIOR, 10]], 1000).is_empty(), "inna armia")
	assert_true(not MAIN.player_attack_problem(pc, ARMY, 5000).is_empty(), "plan za długi")
	return true


func _client() -> SupabaseClient:
	SupabaseSession.clear(SESSION_PATH)
	SaveGame.delete(SYNC_PATH)
	var c := SupabaseClient.new()
	c.setup(SupabaseConfig.parse(JSON.stringify({
		"url": "https://abc.supabase.co", "publishable_key": "sb_publishable_test123",
	})), SESSION_PATH, SYNC_PATH)
	c.fake_transport = true
	return c


func _online(c: SupabaseClient) -> void:
	c.handle_auth(SupabaseClient.Call.SIGNUP, HTTPRequest.RESULT_SUCCESS, 200, JSON.stringify({
		"access_token": "t1", "refresh_token": "r1", "expires_in": 3600,
		"user": {"id": UID, "is_anonymous": true},
	}))


func test_client_start_attack() -> bool:
	var c := _client()
	var got: Array = []
	c.attack_started.connect(func(start: Dictionary, error: String) -> void: got.append([start, error]))
	assert_true(not c.start_attack(DEFENDER, ARMY), "bez sieci nic nie idzie")
	_online(c)
	assert_true(c.start_attack(DEFENDER, ARMY), "online idzie")
	assert_true(not c.start_attack(DEFENDER, ARMY), "drugi start czeka na pierwszy")
	var sent := c.sent_requests[c.sent_requests.size() - 1]
	assert_eq(sent["path"], AttackStart.PATH, "ścieżka start_attack")
	assert_eq(sent["body"], {"defender_id": DEFENDER, "army": ARMY}, "treść bez id atakującego")
	var map_seed := WorldSeed.first_playable(4242)
	var raw := _raw_start(5)
	raw["map_seed"] = map_seed
	c.handle_attack(SupabaseClient.AttackCall.START, HTTPRequest.RESULT_SUCCESS, 200, JSON.stringify(raw))
	assert_eq(got[0][1], "", "bez błędu")
	assert_eq((got[0][0] as Dictionary)["id"], ATTACK, "odpowiedź z zarysem i donżonem")
	assert_true(not (got[0][0] as Dictionary).has("castle"), "bez kopii zamku przed zatwierdzeniem (#28)")
	assert_true(not c.is_attack_pending(), "po odpowiedzi wolne")
	c.start_attack(DEFENDER, ARMY)
	c.handle_attack(SupabaseClient.AttackCall.START, HTTPRequest.RESULT_SUCCESS, 409, '{"error":"target_busy"}')
	assert_eq(got[1][1], "target_busy", "zajęty cel")
	assert_true((got[1][0] as Dictionary).is_empty(), "bez kopii")
	c.start_attack(DEFENDER, ARMY)
	c.handle_attack(SupabaseClient.AttackCall.START, HTTPRequest.RESULT_TIMEOUT, 0, "")
	assert_eq(got[2][1], SupabaseClient.NETWORK_ERROR, "brak sieci")
	c.start_attack(DEFENDER, ARMY)
	c.handle_attack(SupabaseClient.AttackCall.START, HTTPRequest.RESULT_SUCCESS, 200, '{"id":"x"}')
	assert_eq(got[3][1], SupabaseClient.REJECTED_ERROR, "niepełna odpowiedź to odmowa")
	c.free()
	return true


func test_client_finish_attack() -> bool:
	var c := _client()
	var got: Array = []
	c.attack_finished.connect(func(loot: Array[int], error: String) -> void: got.append([loot, error]))
	_online(c)
	var body := {"attack_id": ATTACK, "result": {"won": true, "percent": 60, "stars": [true, true, true]},
			"loot": [600, 240, 120, 18], "survivors": [10, 10, 5]}
	assert_true(c.finish_attack(body), "wynik idzie")
	assert_eq(c.sent_requests[c.sent_requests.size() - 1]["path"], AttackFinish.PATH, "ścieżka finish_attack")
	c.handle_attack(SupabaseClient.AttackCall.FINISH, HTTPRequest.RESULT_SUCCESS, 200,
			'{"status":"finished","result":{},"loot":[500,240,120,18]}')
	assert_eq(got[0][1], "", "przyjęty")
	assert_eq(got[0][0], [500, 240, 120, 18] as Array[int], "łup z odpowiedzi serwera")
	c.finish_attack(body)
	c.handle_attack(SupabaseClient.AttackCall.FINISH, HTTPRequest.RESULT_SUCCESS, 422, '{"error":"loot_too_high"}')
	assert_eq(got[1][1], "loot_too_high", "zawyżony łup odrzucony")
	assert_true((got[1][0] as Array).is_empty(), "bez łupu")
	c.finish_attack(body)
	c.handle_attack(SupabaseClient.AttackCall.FINISH, HTTPRequest.RESULT_SUCCESS, 503, "")
	assert_eq(got[2][1], SupabaseClient.NETWORK_ERROR, "błąd serwera można ponowić")
	c.finish_attack(body)
	c.handle_attack(SupabaseClient.AttackCall.FINISH, HTTPRequest.RESULT_SUCCESS, 410, '{"error":"attack_expired"}')
	assert_eq(got[3][1], "attack_expired", "wygasły atak")
	c.free()
	return true


## Kod błędu tylko z małych liter i `_`; reszta to ogólna odmowa (nic z odpowiedzi nie trafia do UI).
func test_edge_error() -> bool:
	assert_eq(SupabaseClient.edge_error(HTTPRequest.RESULT_SUCCESS, 200, "{}"), "", "2xx")
	assert_eq(SupabaseClient.edge_error(HTTPRequest.RESULT_SUCCESS, 429, '{"error":"rate_limited"}'),
			"rate_limited", "limit startów")
	assert_eq(SupabaseClient.edge_error(HTTPRequest.RESULT_SUCCESS, 500, '{"error":"start_failed"}'),
			SupabaseClient.NETWORK_ERROR, "5xx")
	assert_eq(SupabaseClient.edge_error(HTTPRequest.RESULT_SUCCESS, 400, '{"error":"<b>zły</b>"}'),
			SupabaseClient.REJECTED_ERROR, "obcy tekst nie przechodzi")
	assert_eq(SupabaseClient.edge_error(HTTPRequest.RESULT_SUCCESS, 404, "nie json"),
			SupabaseClient.REJECTED_ERROR, "bez kodu")
	assert_true(AttackStart.error_message("bad_army") != AttackStart.error_message("cokolwiek"),
			"zła armia ma własny komunikat")
	for code: String in ["target_busy", "target_shielded", "rate_limited", "bad_army", "network", "cokolwiek"]:
		assert_true(AttackStart.error_message(code).length() <= 50, "komunikat mieści się w pasku")
	return true
