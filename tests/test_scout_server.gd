extends TestCase
## Zwiad na gracza przez serwer i pełne ukrycie obrony w planie (#28): odpowiedzi `scout`,
## `scout_reports`, `start_attack` (zarys, donżon, zwiad) i `launch_attack`, misja prowadzona przez
## serwer (klient jej nie rozstrzyga), siatka planu z zarysu i zgodność liczb gry z migracją.

const T0 := 1_700_000_000_000
const K := BuildingTypes.Kind
const U := UnitTypes.Unit
const R := EconomyConfig.Res
const MIGRATION := "res://supabase/migrations/20261121104913_scouting.sql"
const UID := "00000000-0000-0000-0000-00000000000a"
const DEFENDER := "00000000-0000-0000-0000-00000000000b"
const SESSION_PATH := "user://test_scout_server_session.json"
const SYNC_PATH := "user://test_scout_server_sync.json"


func _intel() -> Dictionary:
	return {"region": [10, 10, 6, 6], "buildings": [[10, 10, 2, 2, K.KEEP, 1], [14, 14, 2, 2, K.TOWER, 3],
			[40, 40, 2, 2, K.TOWER, 1]], "squads": [[2, 11, 12], [0, 50, 50]],
			"patrols": [[[12, 12], [30, 30]], [[50, 50], [51, 50]]], "traps": [[0, 13, 13], [99, 12, 12], [1, 40, 40]]}


func test_intel_from_server_keeps_only_region_and_valid_entries() -> bool:
	var i := ScoutIntel.from_server(_intel())
	assert_eq(i.region, Rect2i(10, 10, 6, 6), "obszar")
	assert_eq(i.buildings.size(), 2, "budynek spoza obszaru odpada")
	assert_eq(i.buildings[1], [Rect2i(14, 14, 2, 2), K.TOWER, 3], "rodzaj i poziom")
	assert_eq(i.squads, [[2, Vector2i(11, 12)]], "oddział spoza obszaru odpada")
	assert_eq(i.patrols.size(), 1, "patrol z punktem w obszarze")
	assert_eq(i.traps, [[0, Vector2i(13, 13)]], "zły rodzaj i pułapka spoza obszaru odpadają")
	assert_true(ScoutIntel.from_server({"region": [60, 60, 10, 10]}).is_empty(), "obszar poza mapą")
	assert_true(ScoutIntel.from_server({"region": [1, 1, 1.5, 2]}).is_empty(), "ułamek")
	assert_true(ScoutIntel.from_server("x").is_empty(), "zły typ")
	assert_true(ScoutIntel.from_server({}).is_empty(), "bez zwiadu")
	return true


func test_scout_responses_are_parsed_and_limited() -> bool:
	var s := ScoutNet.parse_send({"id": "m1", "remaining_s": 600, "trackers": 3, "scouts": 2})
	assert_eq(s["units"], {U.TRACKER: 3, U.SCOUT: 2} as Dictionary[int, int], "zwiadowcy z serwera")
	assert_eq(s["remaining_s"], 600, "czas do końca")
	assert_true(ScoutNet.parse_send({"id": "m1", "remaining_s": 60, "trackers": 4, "scouts": 4}).is_empty(), "ponad 5")
	assert_true(ScoutNet.parse_send({"id": "", "remaining_s": 60, "trackers": 1, "scouts": 0}).is_empty(), "bez id")
	assert_true(ScoutNet.parse_send({"id": "m", "remaining_s": 60, "trackers": 0, "scouts": 0}).is_empty(), "nikt")
	var rows := ScoutNet.parse_reports({"reports": [
		{"id": "a", "defender_id": DEFENDER, "castle_name": "Gród", "trackers": 2, "scouts": 0, "finished": false,
			"remaining_s": 30},
		{"id": "b", "defender_id": DEFENDER, "trackers": 2, "scouts": 1, "finished": true, "outcome": 1,
			"percent": 20, "returned": 2, "intel": _intel(), "remaining_s": 0},
		{"id": "c", "defender_id": DEFENDER, "trackers": 2, "scouts": 0, "finished": true, "outcome": 9,
			"percent": 20, "returned": 2},
		{"id": "d", "defender_id": DEFENDER, "trackers": -1, "scouts": 3, "finished": false},
		"x"]})
	assert_eq(rows.size(), 2, "złe wpisy odpadają")
	assert_true(not rows[0].has("outcome"), "w drodze bez wyniku")
	assert_eq(rows[1]["returned"], 2, "ocaleli z serwera")
	assert_eq(rows[1]["sent"], 3, "wysłani")
	assert_eq(ScoutNet.parse_reports(null), [] as Array[Dictionary], "zła odpowiedź")
	assert_eq(ScoutNet.error_message("scout_busy"), "Zwiadowcy są już w drodze", "komunikat")
	return true


func _castle() -> Dictionary:
	var grid := BuildGrid.new(TerrainMap.generate(1337))
	var c := grid.terrain.center()
	grid.place_kind(c, K.SCOUT_HOUSE, 1)
	var r := Research.new()
	r.done["S1"] = true
	var rec := Recruitment.new()
	rec.add_squad(U.TRACKER, 3)
	var e := Economy.new(T0)
	for res in EconomyConfig.count():
		e.amounts[res] = 500
	return {"grid": grid, "r": r, "rec": rec, "e": e}


func test_remote_mission_waits_for_server_report() -> bool:
	var c := _castle()
	var rec: Recruitment = c["rec"]
	var e: Economy = c["e"]
	var s := Scouting.new()
	s.start_remote("m1", "gracz:" + DEFENDER, "Gród", 1, {U.TRACKER: 2} as Dictionary[int, int], 60_000, T0, rec, e)
	assert_true(s.is_busy() and s.mission.is_remote(), "misja na serwerze")
	assert_eq(rec.army_of(U.TRACKER), 1, "zwiadowcy z odpowiedzi serwera wyszli z armii")
	assert_eq(e.amounts[R.GOLD], 480, "koszt zszedł")
	assert_eq(s.mission.finish_ms(), T0 + 60_000, "koniec z czasu serwera")
	assert_true(not s.remote_due(T0 + 59_999), "jeszcze w drodze")
	assert_true(s.update(T0 + 999_999, rec) == null and s.is_busy(), "klient nie rozstrzyga misji na gracza")
	assert_true(s.remote_due(T0 + 60_000), "czeka na raport")
	var pending: Array[Dictionary] = [{"id": "m1", "finished": false}]
	assert_true(s.apply_reports(pending, rec, T0 + 60_000) == null and s.is_busy(), "raport jeszcze niegotowy")
	var copy := Scouting.new()
	copy.load_data(JSON.parse_string(JSON.stringify(s.save_data())) as Dictionary, T0 + 1)
	assert_eq(copy.mission.remote_id, "m1", "id misji w zapisie")
	var done: Array[Dictionary] = [{"id": "inna", "finished": true, "outcome": 0, "percent": 30, "returned": 2,
			"intel": {}},
			{"id": "m1", "finished": true, "outcome": 1, "percent": 17, "returned": 1, "intel": _intel()}]
	var rep := s.apply_reports(done, rec, T0 + 70_000)
	assert_true(rep != null and not s.is_busy(), "raport z serwera kończy misję")
	assert_eq([rep.outcome, rep.percent, rep.returned, rep.sent], [1, 17, 1, 2], "wynik z serwera, nie z klienta")
	assert_eq(rec.army_of(U.TRACKER), 2, "ocaleli według serwera wrócili")
	assert_true(not ScoutIntel.from_server(rep.intel).is_empty(), "odsłonięte dane w raporcie")
	var saved := Scouting.new()
	saved.load_data(JSON.parse_string(JSON.stringify(s.save_data())) as Dictionary, T0)
	var back := ScoutIntel.from_server(saved.report_for("gracz:" + DEFENDER).intel)
	var orig := ScoutIntel.from_server(rep.intel)
	assert_eq([back.region, back.buildings, back.squads, back.traps], [orig.region, orig.buildings, orig.squads, orig.traps],
			"intel w zapisie (liczby z JSON jako float)")
	# misja, której serwer już nie zna: po dobie zwiadowcy wracają bez raportu
	var lost := Scouting.new()
	lost.start_remote("m2", "gracz:" + DEFENDER, "Gród", 0, {U.TRACKER: 2} as Dictionary[int, int], 1000, T0, rec, null)
	var none: Array[Dictionary] = []
	assert_true(lost.apply_reports(none, rec, T0 + 5000) == null and lost.is_busy(), "chwilę po końcu czeka dalej")
	lost.apply_reports(none, rec, T0 + 2000 + Scouting.LOST_MISSION_MS)
	assert_true(not lost.is_busy() and rec.army_of(U.TRACKER) == 2, "po dobie zwiadowcy wracają")
	return true


func test_fog_target_shows_outline_and_scouted_buildings() -> bool:
	var seed_value := WorldSeed.first_playable(4242)
	var intel := ScoutIntel.from_server(_intel())
	var footprint: Array[Rect2i] = [Rect2i(10, 10, 2, 2), Rect2i(14, 14, 2, 2), Rect2i(40, 40, 2, 2)]
	var t := PlayerCastle.fog_target(seed_value, footprint, Rect2i(10, 10, 2, 2), intel)
	assert_true(t != null and t.grid.kinds[t.objective] == K.KEEP, "donżon jako cel")
	assert_eq(t.grid.buildings.size(), 3, "cały zarys w siatce")
	var tower := t.grid.building_at(Vector2i(14, 14))
	assert_eq([t.grid.kinds[tower], t.grid.levels[tower]], [K.TOWER, 3], "odsłonięty budynek z rodzajem")
	var hidden := AttackPlanner.hidden_ids(t.grid, intel)
	assert_true(hidden.has(t.grid.building_at(Vector2i(40, 40))) and not hidden.has(tower), "reszta to zarys")
	var o := AttackPlan.Order.new()
	assert_eq(AttackPlanner.tap(o, t.grid, Vector2i(40, 40), intel), AttackPlanner.HIDDEN_TARGET, "bez rodzaju")
	assert_true(PlayerCastle.fog_target(seed_value, footprint, Rect2i(70, 70, 2, 2), intel) == null, "zły donżon")
	return true


func _client() -> SupabaseClient:
	SupabaseSession.clear(SESSION_PATH)
	SaveGame.delete(SYNC_PATH)
	var c := SupabaseClient.new()
	c.setup(SupabaseConfig.parse(JSON.stringify({
		"url": "https://abc.supabase.co", "publishable_key": "sb_publishable_test123",
	})), SESSION_PATH, SYNC_PATH)
	c.fake_transport = true
	c.handle_auth(SupabaseClient.Call.SIGNUP, HTTPRequest.RESULT_SUCCESS, 200, JSON.stringify({
		"access_token": "t1", "refresh_token": "r1", "expires_in": 3600,
		"user": {"id": UID, "is_anonymous": true},
	}))
	return c


func test_client_scout_and_launch_requests() -> bool:
	var c := _client()
	var sent: Array = []
	var reports: Array = []
	var launched: Array = []
	c.scout_sent.connect(func(d: Dictionary, err: String) -> void: sent.append([d, err]))
	c.scout_reports_loaded.connect(func(rows: Array[Dictionary], ok: bool) -> void: reports.append([rows, ok]))
	c.attack_launched.connect(func(d: Dictionary, err: String) -> void: launched.append([d, err]))
	assert_true(c.send_scout(DEFENDER, 2), "zwiad idzie")
	assert_true(not c.send_scout(DEFENDER, 2), "drugi czeka na pierwszy")
	var req := c.sent_requests[c.sent_requests.size() - 1]
	assert_eq(req["path"], ScoutNet.SEND_PATH, "ścieżka scout")
	assert_eq(req["body"], {"defender_id": DEFENDER, "duration": 2}, "treść bez id gracza i bez wyniku")
	c.handle_scout(SupabaseClient.ScoutCall.SEND, HTTPRequest.RESULT_SUCCESS, 200,
			'{"id":"m1","remaining_s":1800,"trackers":2,"scouts":0}')
	assert_eq(sent[0][1], "", "przyjęty")
	c.send_scout(DEFENDER, 0)
	c.handle_scout(SupabaseClient.ScoutCall.SEND, HTTPRequest.RESULT_SUCCESS, 409, '{"error":"scout_busy"}')
	assert_eq(sent[1][1], "scout_busy", "zajęci zwiadowcy")
	assert_true(c.load_scout_reports(), "raporty idą")
	assert_eq(c.sent_requests[c.sent_requests.size() - 1]["path"], ScoutNet.REPORTS_PATH, "ścieżka raportów")
	c.handle_scout(SupabaseClient.ScoutCall.REPORTS, HTTPRequest.RESULT_SUCCESS, 200,
			'{"reports":[{"id":"m1","defender_id":"%s","trackers":2,"scouts":0,"finished":false,"remaining_s":5}]}' % DEFENDER)
	assert_eq((reports[0][0] as Array).size(), 1, "raport z serwera")
	assert_true(reports[0][1], "serwer odpowiedział")
	assert_true(c.launch_attack("a1"), "zatwierdzenie planu idzie")
	assert_eq(c.sent_requests[c.sent_requests.size() - 1]["path"], AttackLaunch.PATH, "ścieżka launch_attack")
	c.handle_attack(SupabaseClient.AttackCall.LAUNCH, HTTPRequest.RESULT_SUCCESS, 200,
			'{"id":"a1","castle":{"grid":{}},"defense":{}}')
	assert_eq(launched[0][1], "", "pełna kopia")
	c.launch_attack("a1")
	c.handle_attack(SupabaseClient.AttackCall.LAUNCH, HTTPRequest.RESULT_SUCCESS, 409, '{"error":"attack_expired"}')
	assert_eq(launched[1][1], "attack_expired", "wygasły atak")
	c.free()
	return true


## Liczby i rodzaje gry są te same co w migracji (znaczniki w komentarzach i tabele w SQL).
func test_server_constants_match_game() -> bool:
	var sql := FileAccess.get_file_as_string(MIGRATION)
	assert_true(not sql.is_empty(), "migracja jest")
	var classes: Array[int] = []
	for u in UnitTypes.count():
		classes.append(UnitTypes.unit_class(u))
	assert_true(sql.contains("UNIT_CLASS = %s" % str(classes)), "klasy jednostek")
	assert_true(sql.contains("array%s" % str(classes)), "tabela w private.unit_class")
	assert_true(sql.contains("DURATION_S = %s" % str(ScoutConfig.DURATION_S)), "długości zwiadu")
	assert_true(sql.contains("array%s" % str(ScoutConfig.DURATION_S)), "długości w begin_scout")
	assert_true(sql.contains("REVEAL_PERCENT = %s" % str(ScoutConfig.REVEAL_PERCENT)), "odsłonięcie")
	assert_true(sql.contains("array%s" % str(ScoutConfig.REVEAL_PERCENT)), "odsłonięcie w begin_scout")
	assert_true(sql.contains("CHANCES = %s" % str(ScoutConfig.CHANCES)), "szanse")
	assert_true(sql.contains("array%s" % str(ScoutConfig.CHANCES)), "szanse w begin_scout")
	assert_true(sql.contains("EXTRA_SCOUT_PERCENT = %d" % ScoutConfig.EXTRA_SCOUT_PERCENT), "za zwiadowcę")
	assert_true(sql.contains("S3_PERCENT = %d" % ScoutConfig.S3_PERCENT), "S3 zasięg")
	assert_true(sql.contains("MAX_PERCENT = %d" % ScoutConfig.MAX_PERCENT), "najwyżej")
	assert_true(sql.contains("S3_SUCCESS_BONUS = %d" % ScoutConfig.S3_SUCCESS_BONUS), "S3 szansa")
	assert_true(sql.contains("SIGNAL_TOWER_PENALTY = %d" % ScoutConfig.SIGNAL_TOWER_PENALTY), "Wieża sygnałowa")
	assert_true(sql.contains("MAX_SCOUTS = %d" % ScoutConfig.MAX_SCOUTS), "zwiadowców na misję")
	assert_true(sql.contains("SCOUT_HOUSE = %d" % K.SCOUT_HOUSE), "rodzaj Chaty tropicieli")
	assert_true(sql.contains("SIGNAL_TOWER = %d" % K.SIGNAL_TOWER), "rodzaj Wieży sygnałowej")
	assert_true(sql.contains("KEEP = %d" % K.KEEP), "rodzaj donżonu")
	assert_true(sql.contains("TRACKER = %d, SCOUT = %d" % [U.TRACKER, U.SCOUT]), "rodzaje zwiadowców")
	assert_true(sql.contains("DefensePlan.MAX_ROUTE = %d" % DefensePlan.MAX_ROUTE), "długość trasy patrolu")
	assert_true(sql.contains("w.ord <= %d" % DefensePlan.MAX_ROUTE), "trasa w scout_intel")
	assert_eq(DefensePlan.Task.PATROL, 1, "patrol to zadanie 1 (scout_intel)")
	return true
