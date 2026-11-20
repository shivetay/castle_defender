extends TestCase
@warning_ignore_start("integer_division")
## Odbudowa po ataku PvP (#99): ruiny z listy zniszczeń, czas odbudowy z epoki, wygląd w trakcie,
## mniejsza produkcja w ruinie (także podczas nieobecności), lista w `finish_attack`, odczyt obron
## z serwera i zgodność liczb gry z migracją `public.record_destroyed`.

const K := BuildingTypes.Kind
const R := EconomyConfig.Res
const HOUR := Economy.MS_PER_HOUR
const MIGRATION := "res://supabase/migrations/20261120200000_attack_ruins.sql"
const UID := "00000000-0000-0000-0000-00000000000a"
const SESSION_PATH := "user://test_ruins_session.json"
const SYNC_PATH := "user://test_ruins_sync.json"


func _grid() -> BuildGrid:
	return BuildGrid.new(TerrainMap.generate(1337))


func _place(grid: BuildGrid, kind: int) -> int:
	var c := grid.terrain.center()
	for r in 20:
		for dy in range(-r, r + 1):
			for dx in range(-r, r + 1):
				var id := grid.place_kind(c + Vector2i(dx, dy), kind)
				if id != 0:
					return id
	return 0


## Epoka I: godzina, każda następna o godzinę dłużej; poza zakresem skrajne wartości.
func test_rebuild_time_by_age() -> bool:
	assert_eq(Ruins.rebuild_ms(0), HOUR, "epoka I")
	assert_eq(Ruins.rebuild_ms(1), 2 * HOUR, "epoka II")
	assert_eq(Ruins.rebuild_ms(5), 6 * HOUR, "epoka VI")
	assert_eq(Ruins.rebuild_ms(-1), HOUR, "poniżej zakresu")
	assert_eq(Ruins.rebuild_ms(99), 6 * HOUR, "powyżej zakresu")
	return true


## Ten sam atak dwa razy niczego nie zmienia, późniejszy atak zaczyna odbudowę od nowa, a starszy
## jej nie skraca. Odbudowany albo rozebrany budynek znika z ruin.
func test_add_and_prune() -> bool:
	var grid := _grid()
	var hut := _place(grid, K.LUMBER_HUT)
	var tower := _place(grid, K.TOWER)
	var ruins := Ruins.new()
	assert_true(ruins.add([hut, tower] as Array[int], 1000, 0), "nowe ruiny")
	assert_true(not ruins.add([hut, tower] as Array[int], 1000, 0), "ten sam atak drugi raz")
	assert_true(not ruins.add([hut] as Array[int], 500, 0), "starszy atak nie skraca odbudowy")
	assert_true(ruins.add([hut] as Array[int], 2000, 0), "nowszy atak zaczyna od nowa")
	assert_eq(ruins.ends[hut], 2000 + HOUR, "koniec od nowszego ataku")
	assert_true(not ruins.add([0, -3] as Array[int], 1000, 0), "złe id pominięte")
	assert_true(ruins.is_ruined(tower, 1000) and not ruins.is_ruined(tower, 999), "od końca ataku")
	assert_eq(ruins.remaining_ms(tower, 1000 + HOUR / 2), HOUR / 2, "pół godziny do końca")
	assert_true(not ruins.prune(1000 + HOUR - 1, grid), "przed końcem nic nie znika")
	assert_true(ruins.prune(1000 + HOUR, grid), "wieża odbudowana")
	assert_true(not ruins.ends.has(tower) and ruins.ends.has(hut), "chata dalej w ruinie")
	grid.remove(hut)
	assert_true(ruins.prune(1000, grid) and ruins.is_empty(), "rozebrana chata znika z ruin")
	return true


## Wygląd w trakcie odbudowy: gruz, wyrwa, pęknięcia, potem cały budynek.
func test_states_follow_rebuild() -> bool:
	var ruins := Ruins.new()
	ruins.add([7] as Array[int], 0, 0)
	var S := BuildingTypes.State
	assert_eq(ruins.state_of(7, 0), S.RUBBLE, "zaraz po ataku gruz")
	assert_eq(ruins.state_of(7, HOUR / 3), S.BREACHED, "po trzeciej części wyrwa")
	assert_eq(ruins.state_of(7, HOUR * 2 / 3), S.CRACKED, "po dwóch trzecich pęknięcia")
	assert_eq(ruins.state_of(7, HOUR), S.INTACT, "po odbudowie cały")
	assert_eq(ruins.states(HOUR / 2), {7: S.BREACHED}, "stany do rysowania")
	assert_eq(ruins.states(HOUR), {}, "po odbudowie nic do rysowania")
	assert_eq(ruins.next_change_after(-1), 0, "pierwsza zmiana: początek")
	assert_eq(ruins.next_change_after(0), HOUR, "następna: koniec odbudowy")
	assert_eq(ruins.next_change_after(HOUR), -1, "potem nic")
	return true


## Chata drwala w ruinie daje 75 procent; wieża (bez produkcji) nic nie zmienia.
func test_ruined_producer_makes_less() -> bool:
	var grid := _grid()
	var hut := _place(grid, K.LUMBER_HUT)
	var tower := _place(grid, K.TOWER)
	var full := Economy.rates(grid)[R.WOOD]
	var hut_rate := int((EconomyConfig.BUILDING_PRODUCTION[K.LUMBER_HUT][1] as Array)[0])
	grid.ruined = {tower: true}
	assert_eq(Economy.rates(grid)[R.WOOD], full, "ruina wieży nie zmienia produkcji")
	grid.ruined = {hut: true}
	assert_eq(Economy.rates(grid)[R.WOOD], full - hut_rate + hut_rate * Ruins.PRODUCTION_PERCENT / 100,
			"chata w ruinie: 75 procent")
	var lines := InfoText.resource(R.WOOD, grid, null, [0, 0, 0, 0] as Array[int])
	assert_true(lines.has("- ruiny po ataku: -%d" % (hut_rate - hut_rate * Ruins.PRODUCTION_PERCENT / 100)),
			"okienko drewna mówi o ruinie")
	return true


## Nieobecność dłuższa niż odbudowa: do końca odbudowy mniejsza stawka, potem pełna; wynik nie
## zależy od tego, czy czas płynie jednym skokiem, czy co minutę.
func test_production_split_at_rebuild_end() -> bool:
	var grid := _grid()
	var hut := _place(grid, K.LUMBER_HUT)
	var full := Economy.rates(grid)[R.WOOD]
	grid.ruined = {hut: true}
	var low := Economy.rates(grid)[R.WOOD]
	grid.ruined = {}
	var ruins := Ruins.new()
	ruins.add([hut] as Array[int], 0, 0)
	var jump := Economy.new(0)
	jump.capacities = [0, 0, 0, 0] as Array[int]
	BuildQueue.new().update(3 * HOUR, grid, jump, null, null, 0, ruins)
	assert_eq(jump.amounts[R.WOOD], EconomyConfig.START[R.WOOD] + low + 2 * full, "godzina w ruinie, dwie pełne")
	assert_true(grid.ruined.is_empty(), "po odbudowie bez kary")
	var steps := Economy.new(0)
	steps.capacities = [0, 0, 0, 0] as Array[int]
	var q := BuildQueue.new()
	for minute in range(1, 181):
		q.update(minute * 60 * 1000, grid, steps, null, null, 0, ruins)
	assert_eq(steps.amounts, jump.amounts, "ten sam wynik co minutę")
	return true


## `finish_attack` dostaje id zniszczonych budynków z wyniku (bez muru), rosnąco i najwyżej 200.
func test_finish_request_has_destroyed() -> bool:
	var bot := BotRoster.generate(0)
	var b := Battle.create_squads(bot.grid, bot.objective, [[UnitTypes.Unit.AXE_WARRIOR, 1]], bot.defenders,
			bot.spawn, 5)
	var ids: Array[int] = []
	for id: int in b.structures:
		var s: Battle.Structure = b.structures[id]
		if ids.size() < 3 or BuildingTypes.is_wall(s.kind):
			s.hp = 0
			if not BuildingTypes.is_wall(s.kind):
				ids.append(id)
	ids.sort()
	var r := BattleResult.of(b)
	assert_eq(r.destroyed_ids, ids, "zniszczone bez odcinków muru, rosnąco")
	assert_eq(r.destroyed, ids.size(), "liczba zgodna z procentem")
	var body := AttackFinish.request("a", r, 1, [1] as Array[int])
	assert_eq(body["destroyed"], ids, "lista w żądaniu")
	var many := BattleResult.new()
	for i in 250:
		many.destroyed_ids.append(i)
	assert_eq((AttackFinish.request("a", many, 0, [] as Array[int])["destroyed"] as Array).size(),
			AttackFinish.MAX_DESTROYED, "najwyżej 200 id, bez zera")
	return true


## Zapytanie o obrony tylko dla własnego UUID; odpowiedź to dane niezaufane.
func test_defense_log() -> bool:
	var p := DefenseLog.path(UID, 1700000000)
	assert_true(p.begins_with(DefenseLog.PATH + "?select=destroyed,finished_at&defender_id=eq." + UID), "własne obrony")
	assert_true(p.contains("finished_at=gte.2023-11-14T22:13:20Z"), "od podanej chwili, UTC")
	assert_eq(DefenseLog.path("x&select=*", 0), "", "zły id nie idzie do sieci")
	assert_eq(DefenseLog.parse_timestamp("2023-11-14T22:13:20+00:00"), 1700000000, "strefa +00:00")
	assert_eq(DefenseLog.parse_timestamp("2023-11-14T22:13:20.123456+00:00"), 1700000000, "ułamek sekundy")
	assert_eq(DefenseLog.parse_timestamp("2023-11-14T23:13:20+01:00"), 1700000000, "strefa +01:00")
	assert_eq(DefenseLog.parse_timestamp("2023-11-14T21:13:20-01:00"), 1700000000, "strefa -01:00")
	assert_eq(DefenseLog.parse_timestamp("2023-11-14T22:13:20Z"), 1700000000, "Z")
	assert_eq(DefenseLog.parse_timestamp("wczoraj"), -1, "zły czas")
	var rows := DefenseLog.parse_response([
		{"destroyed": [3, 5.0, -1, "x", 2.5], "finished_at": "2023-11-14T22:13:20+00:00"},
		{"destroyed": [], "finished_at": "2023-11-14T22:13:20+00:00"},
		{"destroyed": [4], "finished_at": "zły"},
		{"destroyed": "4", "finished_at": "2023-11-14T22:13:20+00:00"},
		"śmieć",
	])
	assert_eq(rows.size(), 1, "tylko poprawny wiersz z budynkami")
	assert_eq(rows[0]["ids"], [3, 5] as Array[int], "tylko dodatnie liczby całkowite")
	assert_eq(rows[0]["at_ms"], 1700000000000, "koniec ataku w ms")
	assert_true(DefenseLog.parse_response({"a": 1}).is_empty(), "nie lista")
	return true


## Klient: żądanie tylko online, naraz jedno, odpowiedź do sygnału; komunikat mieści się w pasku.
func test_client_loads_defenses() -> bool:
	SupabaseSession.clear(SESSION_PATH)
	var c := SupabaseClient.new()
	c.setup(SupabaseConfig.parse(JSON.stringify({
		"url": "https://abc.supabase.co", "publishable_key": "sb_publishable_test123",
	})), SESSION_PATH, SYNC_PATH)
	c.fake_transport = true
	assert_true(not c.load_defenses(0), "bez sieci nic nie idzie")
	c.handle_auth(SupabaseClient.Call.SIGNUP, HTTPRequest.RESULT_SUCCESS, 200, JSON.stringify({
		"access_token": "t1", "refresh_token": "r1", "expires_in": 3600,
		"user": {"id": UID, "is_anonymous": true},
	}))
	var got: Array = []
	c.defenses_loaded.connect(func(rows: Array[Dictionary], ok: bool) -> void: got.append([rows.size(), ok]))
	c.sent_requests.clear()
	assert_true(c.load_defenses(0), "żądanie idzie")
	assert_true(not c.load_defenses(0), "drugie czeka na odpowiedź")
	assert_eq(c.sent_requests.size(), 1, "jedno żądanie")
	c.handle_defenses(HTTPRequest.RESULT_SUCCESS, 200,
			JSON.stringify([{"destroyed": [3], "finished_at": "2023-11-14T22:13:20+00:00"}]))
	c.handle_defenses(HTTPRequest.RESULT_CANT_CONNECT, 0, "")
	assert_eq(got, [[1, true], [0, false]], "odpowiedź i błąd sieci")
	SupabaseSession.clear(SESSION_PATH)
	c.free()
	var text := "Zamek zaatakowany: w odbudowie %d bud." % 99
	assert_true(PixelFont.text_width(text) <= Hud.MESSAGE_MAX_WIDTH, "komunikat mieści się w pasku")
	return true


## Liczby gry w migracji: limit listy i rodzaje umocnień pomijane jak w BattleResult.
func test_migration_matches_game() -> bool:
	var sql := FileAccess.get_file_as_string(MIGRATION)
	assert_true(not sql.is_empty(), "migracja jest")
	assert_true(sql.contains("MAX_DESTROYED = %d" % AttackFinish.MAX_DESTROYED), "limit listy")
	assert_true(sql.contains("cardinality(destroyed) <= %d" % AttackFinish.MAX_DESTROYED), "limit w kolumnie")
	assert_true(sql.contains("WALL_KINDS = [%d, %d]" % [K.RAMPART, K.PALISADE]), "wał i palisada")
	assert_true(sql.contains("b.kind not in (%d, %d)" % [K.RAMPART, K.PALISADE]), "rodzaje w zapytaniu")
	for kind in BuildingTypes.count():
		assert_eq(BuildingTypes.is_wall(kind), kind == K.RAMPART or kind == K.PALISADE, "tylko dwa rodzaje muru")
	var edge := FileAccess.get_file_as_string("res://supabase/functions/finish_attack/index.ts")
	assert_true(edge.contains("const MAX_DESTROYED = %d;" % AttackFinish.MAX_DESTROYED), "limit w Edge Function")
	return true
