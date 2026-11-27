extends TestCase
## Powtórka obrony (#29): plan z serwera sprawdzany jak w `private.check_plan`, bitwa atakującego i powtórka
## obrońcy z tych samych danych (po drodze przez JSON jak z serwera) dają ten sam przebieg krok po kroku,
## raporty obron, okno raportu obrońcy, lista powtórek i klient Supabase bez sieci.

const MAIN := preload("res://scripts/main.gd")
const K := BuildingTypes.Kind
const U := UnitTypes.Unit
const ATTACK := "00000000-0000-0000-0000-0000000029aa"
const DEFENDER := "00000000-0000-0000-0000-0000000029bb"
const UID := "00000000-0000-0000-0000-0000000029cc"
const MIGRATION := "res://supabase/migrations/20261121224223_attack_replay.sql"
const ARMY := [[U.AXE_WARRIOR, 10], [U.AXE_WARRIOR, 8], [U.RIDER, 5]]
const SESSION_PATH := "user://test_replay_session.json"
const SYNC_PATH := "user://test_replay_sync.json"


## Zamek obrońcy w kształcie `castles.data`: Dwór, donżon, oddział załogi i O2 (premia obrońcy w bitwie).
static func _castle(map_seed: int) -> Dictionary:
	var grid := BuildGrid.new(TerrainMap.generate(map_seed))
	grid.place(grid.manor_spot(WorldSeed.MANOR_MAX_RING), K.MANOR, 1)
	grid.place(grid.keep_spot(WorldSeed.KEEP_MAX_RING), K.KEEP, 1)
	var rec := Recruitment.new()
	rec.load_data({"squads": [[1, U.AXE_WARRIOR, 8], [2, U.ARCHER, 6]]}, grid, 0)
	var research := Research.new()
	research.done["O2"] = true
	var save := SaveGame.to_dict(map_seed, grid, Economy.new(0), BuildQueue.new(), research, null, rec)
	return CastleSync.castle_data(save)


static func _map_seed() -> int:
	return WorldSeed.first_playable(2929)


## Plan atakującego z różnymi manewrami, trasą, odwrotem i startem po innym oddziale.
static func _plan(keep: Vector2i) -> AttackPlan:
	var p := AttackPlan.new()
	var a := p.add(1, AttackPlan.Manoeuvre.FRONTAL)
	a.retreat_percent = 30
	var b := p.add(2, AttackPlan.Manoeuvre.FLANK, keep)
	b.flank_left = false
	var c := p.add(3, AttackPlan.Manoeuvre.FRONTAL)
	c.start = AttackPlan.Start.AFTER_SQUAD
	c.start_value = 1
	return p


## JSON w obie strony, jak odpowiedź z serwera (liczby wracają jako float).
static func _wire(v: Variant) -> Variant:
	return JSON.parse_string(JSON.stringify(v))


## Atakujący: cel ze startu (epoka II atakującego, obrońca w epoce I) i pełna kopia z `launch_attack`.
static func _attacker(plan: AttackPlan, techs: Array) -> PlayerCastle:
	var castle := _castle(_map_seed())
	var footprint: Array = []
	var keep: Array = []
	for e: Variant in (castle["grid"] as Dictionary)["buildings"] as Array:
		var a := e as Array
		footprint.append([a[3], a[4], a[5], a[6]])
		if int(a[1]) == K.KEEP:
			keep = [a[3], a[4], a[5], a[6]]
	var start := AttackStart.parse_response({"id": ATTACK, "map_seed": _map_seed(), "battle_seed": 4141,
			"defender_id": DEFENDER, "footprint": footprint, "keep": keep, "intel": {}})
	var pc := PlayerCastle.from_start(start, ARMY, 0, 1)
	var launch := AttackLaunch.parse_response(_wire({"id": ATTACK, "castle": castle, "defense": {},
			"plan": plan.to_server(), "techs": techs}))
	if not pc.apply_launch(launch):
		return null
	return pc


## Obrońca: odpowiedź `attack_replay` z tymi samymi danymi, które serwer zapisał przy starcie i zatwierdzeniu.
static func _replay_response(plan: AttackPlan, techs: Array, result: BattleResult) -> Dictionary:
	return AttackReplay.parse_response(_wire({"id": ATTACK, "map_seed": _map_seed(), "battle_seed": 4141,
			"castle": _castle(_map_seed()), "defense": {}, "army": ARMY, "plan": plan.to_server(), "techs": techs,
			"result": result.to_server(), "loot": [10, 20, 0, 0], "finished_at": "2026-11-21T10:15:00.123+00:00"}))


static func _keep_cell() -> Vector2i:
	var grid := BuildGrid.new(TerrainMap.generate(_map_seed()))
	return grid.keep_spot(WorldSeed.KEEP_MAX_RING).position


## Sumy kontrolne co kilka kroków aż do końca bitwy.
static func _trace(b: Battle) -> Array[int]:
	var out: Array[int] = []
	while b.winner == Battle.Winner.NONE and b.tick < BattleConfig.time_limit_ticks() + 10:
		b.step()
		if b.tick % 5 == 0:
			out.append(b.checksum())
	out.append(b.checksum())
	return out


## Kryterium #29: powtórka u obrońcy wygląda tak samo jak bitwa u atakującego.
func test_replay_matches_attacker_battle() -> bool:
	var plan := _plan(_keep_cell())
	var techs := ["A7", "A1", "G2"]
	var pc := _attacker(plan, techs)
	assert_true(pc != null, "atakujący dostaje kopię i plan")
	var live := pc.create_battle()
	var live_trace := _trace(live)
	assert_true(live.winner != Battle.Winner.NONE, "bitwa atakującego się kończy")
	assert_true(live_trace.size() > 20, "bitwa trwa dłużej niż chwilę")
	var result := pc.result_of(live)
	var replay := BattleReplay.from_response(_replay_response(plan, techs, result))
	assert_true(replay != null, "powtórka z odpowiedzi serwera")
	var again := replay.create_battle()
	assert_eq(_trace(again), live_trace, "ten sam przebieg krok po kroku")
	assert_eq(again.tick, live.tick, "ten sam czas bitwy")
	assert_eq(again.winner, live.winner, "ten sam zwycięzca")
	assert_eq(again.survivors(Battle.Side.ATTACKER), live.survivors(Battle.Side.ATTACKER), "ci sami ocaleli")
	assert_true(MAIN.replay_matches(BattleResult.of(again), replay.result), "wynik powtórki zgodny z serwerem")
	assert_true(again.has_tech(Battle.Side.ATTACKER, "A7") and not again.has_tech(Battle.Side.ATTACKER, "A2"),
			"badania atakującego z serwera")
	assert_true(again.has_tech(Battle.Side.DEFENDER, "O2"), "badania obrońcy z kopii")
	assert_eq(replay.loot, [10, 20, 0, 0] as Array[int], "łup z serwera")
	assert_eq(replay.at_s, Time.get_unix_time_from_datetime_string("2026-11-21T10:15:00"), "koniec ataku")
	var twice := replay.create_battle()
	assert_eq(_trace(twice), live_trace, "drugie obejrzenie od początku, tak samo")
	return true


## Plan i badania naprawdę zmieniają bitwę, więc zgodność powyżej nie jest przypadkiem.
func test_plan_and_techs_change_battle() -> bool:
	var plan := _plan(_keep_cell())
	var base := _trace(_attacker(plan, ["A7"]).create_battle())
	var other := AttackPlan.new()
	other.add(1, AttackPlan.Manoeuvre.FRONTAL).start_value = 0
	other.add(2, AttackPlan.Manoeuvre.FRONTAL)
	other.add(3, AttackPlan.Manoeuvre.FRONTAL).retreat_percent = 70
	assert_true(_trace(_attacker(other, ["A7"]).create_battle()) != base, "inny plan, inny przebieg")
	assert_true(_trace(_attacker(plan, []).create_battle()) != base, "bez Strzemienia inny przebieg")
	return true


## Atakujący liczy bitwę z planu oddanego przez serwer, a nie z planu na telefonie.
func test_attacker_uses_server_plan() -> bool:
	var plan := _plan(_keep_cell())
	var pc := _attacker(plan, [])
	assert_eq(pc.plan.to_dict(), plan.to_dict(), "plan z serwera")
	var bad := PlayerCastle.from_start(AttackStart.parse_response({"id": ATTACK, "map_seed": _map_seed(),
			"battle_seed": 1, "defender_id": DEFENDER, "footprint": [], "keep": [30, 30, 2, 2], "intel": {}}), ARMY, 0)
	assert_true(not bad.apply_launch({"id": ATTACK, "castle": _castle(_map_seed()), "defense": {}}),
			"bez planu kopia nie zatwierdza ataku")
	assert_true(not bad.apply_launch({"id": ATTACK, "castle": _castle(_map_seed()), "defense": {}, "plan": "x"}),
			"zły plan nie zatwierdza ataku")
	assert_eq(AttackLaunch.request(ATTACK, plan), {"attack_id": ATTACK, "plan": plan.to_server(),
			"sim_version": VerifyJob.project_sim_version()}, "plan i wersja symulacji w żądaniu launch_attack")
	return true


func test_server_plan_is_checked() -> bool:
	var good := {"squad": 1, "manoeuvre": 3, "target": [-1, -1], "waypoints": [[4, 5], [6, 7]], "start": 2,
			"start_value": 2, "retreat": 30, "flank_left": false}
	var p := AttackPlan.from_server(_wire([good, {"squad": 2, "manoeuvre": 0, "target": [10, 11], "waypoints": [],
			"start": 0, "start_value": 0, "retreat": 0, "flank_left": true}]), 3)
	assert_true(p != null, "poprawny plan z JSON (liczby jako float)")
	assert_eq(p.order_for(1).waypoints, [Vector2i(4, 5), Vector2i(6, 7)] as Array[Vector2i], "trasa")
	assert_eq(p.order_for(1).manoeuvre, AttackPlan.Manoeuvre.FLANK, "manewr")
	assert_true(not p.order_for(1).flank_left, "strona oskrzydlenia")
	assert_eq(p.order_for(2).target, Vector2i(10, 11), "cel")
	var bad: Array = [
		{"squad": 4}, {"squad": 0}, {"squad": 1.5}, {"squad": "1"}, {"manoeuvre": 7}, {"start": 3},
		{"start_value": 601}, {"retreat": 101}, {"retreat": -1}, {"flank_left": 1}, {"target": [-1, 4]},
		{"target": [64, 1]}, {"target": [1]}, {"waypoints": [[1, 1], [2, 2], [3, 3], [4, 4]]},
		{"waypoints": [[-1, -1]]}, {"waypoints": "x"}, {"loot": 1},
	]
	for change: Dictionary in bad:
		var o := good.duplicate(true)
		o.merge(change, true)
		assert_true(AttackPlan.from_server([o], 3) == null, "odrzucony: %s" % str(change))
	assert_true(AttackPlan.from_server([good, good], 3) == null, "dwa rozkazy dla jednego oddziału")
	assert_true(AttackPlan.from_server([], 3) == null, "pusty plan")
	assert_true(AttackPlan.from_server([good, good, good, good], 3) == null, "więcej rozkazów niż oddziałów")
	assert_true(AttackPlan.from_server({"orders": []}, 3) == null, "nie tablica")
	var no_key := good.duplicate()
	no_key.erase("waypoints")
	assert_true(AttackPlan.from_server([no_key], 3) == null, "brak klucza")
	return true


## Zakresy klienta są te same co w `private.check_plan`.
func test_server_constants_match_game() -> bool:
	var sql := FileAccess.get_file_as_string(MIGRATION)
	assert_true(not sql.is_empty(), "migracja jest")
	assert_true(sql.contains("START_VALUE_MAX = %d" % AttackPlan.START_VALUE_MAX), "start")
	assert_true(sql.contains("RETREAT_MAX = %d" % AttackPlan.RETREAT_MAX), "odwrót")
	assert_true(sql.contains("CELL_MAX = %d" % AttackPlan.CELL_MAX), "mapa")
	assert_eq(AttackPlan.CELL_MAX, TerrainMap.SIZE - 1, "kratki mapy")
	assert_true(sql.contains("'start_value', 0, %d" % AttackPlan.START_VALUE_MAX), "start w check_plan")
	assert_true(sql.contains("'retreat', 0, %d" % AttackPlan.RETREAT_MAX), "odwrót w check_plan")
	assert_true(sql.contains("'manoeuvre', 0, %d" % (AttackPlan.MANOEUVRE_NAMES.size() - 1)), "manewry")
	assert_true(sql.contains("'start', 0, %d" % (AttackPlan.Start.size() - 1)), "rodzaje startu")
	assert_true(sql.contains("jsonb_array_length(e -> 'waypoints') <= %d" % AttackPlan.MAX_WAYPOINTS), "trasa")
	assert_true(sql.contains("lo, %d)" % AttackPlan.CELL_MAX), "kratki w plan_cell")
	for key in AttackPlan.ORDER_KEYS:
		assert_true(sql.contains("'%s'" % key), "klucz %s" % key)
	assert_eq(AttackReplay.MAX_SQUADS, AttackPlan.MAX_SQUADS_BY_AGE[-1], "najwięcej oddziałów")
	var fn := FileAccess.get_file_as_string("res://supabase/functions/launch_attack/index.ts")
	assert_true(fn.contains("MAX_ORDERS = %d" % AttackReplay.MAX_SQUADS), "limit rozkazów w Edge Function")
	return true


func test_replay_response_is_checked() -> bool:
	var plan := _plan(_keep_cell())
	var r := BattleResult.new()
	var ok := _replay_response(plan, ["A1"], r)
	assert_true(not ok.is_empty(), "poprawna odpowiedź")
	assert_eq(ok["techs"], ["A1"] as Array[String], "badania")
	assert_eq(AttackLaunch.parse_techs(["A1", "A1", "O2", 7, "A7"]), ["A1", "A7"] as Array[String],
			"tylko badania atakującego z bitwy, bez powtórek")
	var raw := {"id": ATTACK, "map_seed": 5, "battle_seed": 6, "castle": {"grid": {}}, "defense": {},
			"army": ARMY, "plan": [], "techs": [], "result": r.to_server(), "loot": [0, 0, 0, 0],
			"finished_at": "2026-11-21T10:15:00Z"}
	assert_true(not AttackReplay.parse_response(raw).is_empty(), "kształt odpowiedzi")
	for change: Dictionary in [{"army": []}, {"army": [[99, 1]]}, {"army": [[0, 0]]}, {"army": [[0, 1.5]]},
			{"army": [[0, 1], [0, 1], [0, 1], [0, 1], [0, 1], [0, 1], [0, 1], [0, 1], [0, 1]]},
			{"battle_seed": -1}, {"map_seed": "5"}, {"castle": {}}, {"result": {"won": 1}},
			{"result": {"won": true, "percent": 101, "stars": [true, true, true]}}, {"id": ""}]:
		var d := raw.duplicate(true)
		d.merge(change, true)
		assert_true(AttackReplay.parse_response(d).is_empty(), "odrzucona: %s" % str(change))
	assert_true(BattleReplay.from_response(AttackReplay.parse_response(raw)) == null, "kopia bez donżonu")
	assert_true(BattleReplay.from_response({}) == null, "pusta odpowiedź")
	var no_plan := _replay_response(AttackPlan.new(), [], r)
	assert_true(BattleReplay.from_response(no_plan) == null, "bez planu nie ma powtórki")
	assert_eq(AttackReplay.error_message("replay_missing"), "Ta obrona nie ma powtórki", "stary atak")
	return true


func test_defense_reports() -> bool:
	# historia z Edge Function defense_history (#328): wynik, czas i gwiazdki; nick i siła w test_defense_history.gd
	var rows := DefenseLog.parse_history(_wire({"rows": [
		{"id": ATTACK, "result": {"won": true, "percent": 66, "stars": [false, true, true]}, "has_replay": true,
			"finished_at": "2026-11-21T10:15:00+01:00", "nickname": "Ala", "army": []},
		{"id": "zły", "result": {"won": true, "percent": 1, "stars": [false, false, false]},
			"finished_at": "2026-11-21T10:15:00Z"},
		{"id": ATTACK, "result": {"won": true}, "finished_at": "2026-11-21T10:15:00Z"},
		"śmieć",
	]}))
	assert_eq(rows.size(), 1, "złe wiersze pominięte")
	assert_eq(rows[0].result.percent, 66, "procent")
	assert_eq(rows[0].result.stars, [false, true, true] as Array[bool], "gwiazdki")
	assert_eq(rows[0].at_s, Time.get_unix_time_from_datetime_string("2026-11-21T09:15:00"), "czas w UTC")
	assert_eq(ReplayPanel.row_text(rows[0], 60), "21.11 10:15 Zdobyty 66%", "wiersz listy w czasie telefonu")
	rows[0].result.won = false
	assert_eq(ReplayPanel.row_text(rows[0], 0), "21.11 09:15 Odparty 66%", "odparty atak")
	return true


func test_replay_panel_touch() -> bool:
	var view := Vector2(320, 180)
	assert_eq(ReplayPanel.target_at(ReplayPanel.row_rect(view, 0).get_center(), view, 2, 0), 0, "pierwszy wiersz")
	assert_eq(ReplayPanel.target_at(ReplayPanel.row_rect(view, 1).get_center(), view, 2, 0), 1, "drugi wiersz")
	assert_eq(ReplayPanel.target_at(ReplayPanel.row_rect(view, 2).get_center(), view, 2, 0), -1, "pusty wiersz")
	assert_eq(ReplayPanel.target_at(ReplayPanel.close_rect(view).get_center(), view, 2, 0), ReplayPanel.CLOSE, "Wróć")
	assert_eq(ReplayPanel.status_text(ReplayPanel.State.READY, 0), ReplayPanel.EMPTY_TEXT, "bez obron")
	assert_eq(ReplayPanel.status_text(ReplayPanel.State.FAILED, 0), ReplayPanel.FAILED_TEXT, "bez sieci")
	assert_eq(ReplayPanel.status_text(ReplayPanel.State.READY, 2), "", "lista")
	return true


func test_defense_report_panel() -> bool:
	var r := BattleResult.new()
	r.won = true
	r.percent = 66
	r.stars = [false, true, true]
	assert_eq(ResultPanel.title(r, true), ResultPanel.DEFENSE_WIN_TITLE, "atakujący wygrał")
	assert_eq(ResultPanel.title(r, false), ResultPanel.WIN_TITLE, "u atakującego bez zmian")
	r.won = false
	assert_eq(ResultPanel.title(r, true), ResultPanel.DEFENSE_LOSS_TITLE, "obrona udana")
	var lines := ResultPanel.lines(r, [10, 0, 0, 0] as Array[int], 0, "", true)
	assert_eq(lines[2][1], Palette.ACCENT, "gwiazdka atakującego to strata obrońcy")
	assert_eq((lines[4][0] as String), "Stracony łup: " + Hud.cost_text([10, 0, 0, 0] as Array[int]), "stracony łup")
	assert_true(PixelFont.text_width(ResultPanel.DEFENSE_LABEL) <= int(ResultPanel.BUTTON.x) - 4, "przycisk mieści napis")
	var panel := ResultPanel.new()
	panel.show_defense(r, [0, 0, 0, 0] as Array[int])
	assert_true(panel.defender, "raport obrońcy")
	panel.show_result(r, [0, 0, 0, 0] as Array[int], 0, "")
	assert_true(not panel.defender, "zwykły wynik ataku")
	panel.free()
	var a := BattleResult.new()
	var b := BattleResult.new()
	assert_true(MAIN.replay_matches(a, b), "ten sam wynik")
	b.percent = 1
	assert_true(not MAIN.replay_matches(a, b), "inny procent")
	return true


func test_defense_panel_has_replays() -> bool:
	var view := Vector2(320, 180)
	var i := DefensePanel.COLUMN.find(DefensePanel.Target.REPLAYS)
	assert_true(i >= 0, "Historia w kolumnie obrony")
	assert_eq(DefensePanel.LABELS[i], "Historia", "napis")
	assert_true(PixelFont.text_width(DefensePanel.LABELS[i]) <= int(Hud.BUTTON_SIZE.x) - 4, "napis mieści się")
	assert_eq(DefensePanel.target_at(Hud.column_rect(300, i).get_center(), view, 12, 300, 1, 0),
			DefensePanel.Target.REPLAYS, "dotknięcie")
	var panel := DefensePanel.new()
	var got: Array = []
	panel.replays_requested.connect(func() -> void: got.append(true))
	panel.activate(DefensePanel.Target.REPLAYS)
	assert_eq(got.size(), 1, "sygnał listy powtórek")
	panel.free()
	return true


func test_client_requests() -> bool:
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
	var reports: Array = []
	var replays: Array = []
	c.defense_reports_loaded.connect(func(list: Array[DefenseLog.Report], ok: bool) -> void: reports.append([list, ok]))
	c.replay_loaded.connect(func(d: Dictionary, e: String) -> void: replays.append([d, e]))
	assert_true(c.load_defense_reports(), "raporty idą")
	assert_true(not c.load_defense_reports(), "drugie żądanie czeka")
	assert_eq(c.sent_requests[-1]["path"], DefenseLog.HISTORY_PATH, "ścieżka historii obron")
	c.handle_reports(HTTPRequest.RESULT_SUCCESS, 200, '{"rows": []}')
	assert_true(reports[0][1] and (reports[0][0] as Array).is_empty(), "pusta lista")
	c.load_defense_reports()
	c.handle_reports(HTTPRequest.RESULT_CANT_CONNECT, 0, "")
	assert_true(not reports[1][1], "bez sieci")
	assert_true(c.load_replay(ATTACK), "powtórka idzie")
	assert_eq(c.sent_requests[-1]["path"], AttackReplay.PATH, "ścieżka attack_replay")
	assert_eq(c.sent_requests[-1]["body"], {"attack_id": ATTACK}, "tylko id ataku, bez id gracza")
	c.handle_attack(SupabaseClient.AttackCall.REPLAY, HTTPRequest.RESULT_SUCCESS, 410, '{"error":"replay_missing"}')
	assert_eq(replays[0][1], "replay_missing", "stary atak")
	c.load_replay(ATTACK)
	c.handle_attack(SupabaseClient.AttackCall.REPLAY, HTTPRequest.RESULT_SUCCESS, 200, '{"id":"x"}')
	assert_eq(replays[1][1], SupabaseClient.REJECTED_ERROR, "nieczytelna powtórka")
	assert_true(c.launch_attack(ATTACK, _plan(Vector2i(3, 4))), "zatwierdzenie z planem")
	assert_eq(c.sent_requests[-1]["body"]["plan"], _plan(Vector2i(3, 4)).to_server(), "plan w treści")
	c.free()
	SupabaseSession.clear(SESSION_PATH)
	SaveGame.delete(SYNC_PATH)
	return true
