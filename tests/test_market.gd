extends TestCase
## Targ (#408): stoi od startu przy Dworze (nowa gra i stary zapis, to samo miejsce), jeden, bez poziomów,
## bez rozbiórki i bez paska budowy; bez miejsca czeka na zwolnienie 4×4. W bitwie jest przeszkodą: nikt nie
## wchodzi na jego kratki, nie jest budynkiem bitwy (cel, wytrzymałość), a bitwa z Targiem jest deterministyczna.

const K := BuildingTypes.Kind
const U := UnitTypes.Unit
const SPAWN := Vector2i(32, 60)
const MIGRATION := "res://supabase/migrations/20261127170000_market.sql"


## Zamek nowej gry na seedzie 1337: Dwór, donżon i Strażnica jak w main.gd, bez Targu.
func _start_grid() -> BuildGrid:
	var grid := BuildGrid.new(TerrainMap.generate(1337))
	grid.place(grid.manor_spot(64), K.MANOR)
	grid.place(grid.keep_spot(64), K.KEEP)
	grid.place(grid.watchtower_spot(64), K.WATCHTOWER)
	return grid


func test_market_kind_rules() -> bool:
	assert_eq(K.MARKET, 33, "Targ na końcu rodzajów (numery starych zapisów bez zmian)")
	assert_eq(BuildingTypes.NAMES[K.MARKET], "Targ", "nazwa")
	assert_eq(BuildingTypes.SHORT_NAMES[K.MARKET], "Targ", "krótka nazwa")
	assert_eq(BuildingTypes.size_of(K.MARKET), Vector2i(4, 4), "4×4")
	assert_true(BuildingTypes.is_unique(K.MARKET), "jeden na zamek, bez rozbiórki")
	assert_true(not BuildingTypes.has_levels(K.MARKET), "bez poziomów")
	assert_true(BuildingTypes.is_obstacle(K.MARKET), "w bitwie przeszkoda")
	assert_true(not BuildingTypes.BUILD_BAR.has(K.MARKET), "nie ma go na pasku budowy")
	assert_eq(BuildingTypes.category(K.MARKET), -1, "nie ma go w panelu budowy")
	assert_eq(BuildConfig.time_ms(K.MARKET, 1), 0, "bez czasu budowy (serwer: 0)")
	assert_eq(BuildConfig.max_level(K.MARKET, 5), 1, "zawsze poziom 1")
	return true


## Nowa gra: Targ staje obok Dworu, zawsze w tym samym miejscu dla seeda.
func test_new_world_places_market_deterministically() -> bool:
	var a := _start_grid()
	var b := _start_grid()
	assert_true(a.place_market(), "Targ stoi")
	assert_true(b.place_market(), "Targ stoi drugi raz")
	var ra := a.buildings[a.market_id()]
	assert_eq(ra, b.buildings[b.market_id()], "ten sam seed, to samo miejsce")
	assert_eq(ra.size, Vector2i(4, 4), "4×4")
	assert_eq(a.levels[a.market_id()], 1, "poziom 1, od razu gotowy")
	var manor := a.buildings[a.manor_id()]
	assert_true(manor.grow(6).intersects(ra), "przy Dworze")
	assert_true(a.place_market(), "drugie wywołanie nic nie zmienia")
	var count := 0
	for id: int in a.kinds:
		if a.kinds[id] == K.MARKET:
			count += 1
	assert_eq(count, 1, "jeden Targ")
	return true


## Stary zapis bez Targu: po wczytaniu Targ staje tam, gdzie stanąłby w tym samym zamku od razu.
func test_old_save_gets_market_on_load() -> bool:
	var old := _start_grid()
	old.place(Rect2i(old.buildings[old.manor_id()].position + Vector2i(-3, 0), Vector2i(2, 2)), K.LUMBER_HUT)
	var data := old.save_data()
	var loaded := BuildGrid.new(TerrainMap.generate(1337))
	assert_eq(loaded.load_data(data), 0, "stary zapis wczytany w całości")
	assert_eq(loaded.market_id(), 0, "bez Targu w starym zapisie")
	assert_true(loaded.place_market(), "Targ dostawiony przy wczytaniu")
	assert_true(old.place_market(), "ten sam zamek bez zapisu")
	assert_eq(loaded.buildings[loaded.market_id()], old.buildings[old.market_id()], "to samo miejsce (deterministycznie)")
	# zapis z Targiem wraca z Targiem w tym samym miejscu
	var again := BuildGrid.new(TerrainMap.generate(1337))
	again.load_data(loaded.save_data())
	assert_eq(again.buildings[again.market_id()], loaded.buildings[loaded.market_id()], "Targ w zapisie")
	return true


## Brak wolnego 4×4: Targ nie staje, a po zwolnieniu miejsca staje sam.
func test_no_room_then_room_frees() -> bool:
	var grid := _start_grid()
	# zapełnij każdą wolną kratkę odcinkiem wału
	var t := grid.terrain
	for y in t.size:
		for x in t.size:
			grid.place(Rect2i(x, y, 1, 1), K.RAMPART)
	assert_true(not grid.place_market(), "bez miejsca Targu nie ma")
	assert_eq(grid.market_id(), 0, "Targ nie stoi")
	# rozbierz 4×4 wałów przy Dworze
	var free := Rect2i()
	var around := grid.buildings[grid.manor_id()].grow(6)
	for y in range(around.position.y, around.end.y - 3):
		for x in range(around.position.x, around.end.x - 3):
			var r := Rect2i(x, y, 4, 4)
			var walls := true
			for cy in range(r.position.y, r.end.y):
				for cx in range(r.position.x, r.end.x):
					walls = walls and grid.kinds.get(grid.building_at(Vector2i(cx, cy)), -1) == K.RAMPART
			if walls:
				free = r
				break
		if free.has_area():
			break
	assert_true(free.has_area(), "jest blok wałów 4×4 przy Dworze")
	for cy in range(free.position.y, free.end.y):
		for cx in range(free.position.x, free.end.x):
			grid.remove(grid.building_at(Vector2i(cx, cy)))
	assert_true(grid.place_market(), "po zwolnieniu miejsca Targ stoi")
	assert_eq(grid.buildings[grid.market_id()], free, "na zwolnionym miejscu")
	return true


## Zamek z Dworem i Targiem obok (BuildGrid.place_market).
func _battle_grid() -> Array:
	var grid := BuildGrid.new(TerrainMap.generate(1337))
	var objective := grid.place(grid.manor_spot(64), K.MANOR, 3)
	grid.place_market()
	return [grid, objective, grid.market_id()]


func test_battle_market_is_obstacle_not_target() -> bool:
	var c := _battle_grid()
	var grid: BuildGrid = c[0]
	assert_true(int(c[2]) != 0, "Targ stoi przy Dworze")
	var cells := grid.buildings[int(c[2])]
	var b := Battle.create(grid, c[1], {U.AXE_WARRIOR: 8, U.RIDER: 3}, {U.SHIELDBEARER: 2}, SPAWN, 42)
	assert_true(not b.structures.has(int(c[2])), "Targ nie jest budynkiem bitwy (bez wytrzymałości, nie cel)")
	assert_eq(b.obstacles.size(), 16, "16 kratek przeszkody")
	var stepped := false
	while b.winner == Battle.Winner.NONE and b.tick < BattleConfig.TICK_HZ * BattleConfig.TIME_LIMIT_S:
		b.step()
		for f in b.fighters:
			if f.alive() and cells.has_point(f.cell()):
				stepped = true
	assert_true(not stepped, "nikt nie stanął na Targu")
	assert_true(b.winner != Battle.Winner.NONE, "bitwa się rozstrzyga")
	return true


func test_battle_with_market_is_deterministic() -> bool:
	var c := _battle_grid()
	var first := Battle.create(c[0], c[1], {U.AXE_WARRIOR: 8, U.ARCHER: 4}, {U.ARCHER: 2}, SPAWN, 7)
	first.run()
	for i in 5:
		var b := Battle.create(c[0], c[1], {U.AXE_WARRIOR: 8, U.ARCHER: 4}, {U.ARCHER: 2}, SPAWN, 7)
		b.run()
		assert_eq(b.checksum(), first.checksum(), "przebieg %d jak pierwszy" % (i + 2))
		assert_eq(b.tick, first.tick, "ten sam koniec")
	return true


## Reguły serwera (`*_market.sql`) to reguły gry: rodzaj Targu i budynki startu nowej gry.
func test_server_market_rules_match_game() -> bool:
	var sql := FileAccess.get_file_as_string(MIGRATION)
	assert_true(sql.contains("MARKET = %d" % K.MARKET), "rodzaj Targu")
	assert_true(sql.contains("b.kind = %d and b.level <> 1" % K.MARKET), "tylko poziom 1")
	var start := "START_KINDS = (%d, %d, %d, %d)" % [K.MANOR, K.KEEP, K.WATCHTOWER, K.MARKET]
	assert_true(sql.contains(start), "budynki startu w komentarzu")
	assert_true(sql.contains("b.kind not in (%d, %d, %d, %d)" % [K.MANOR, K.KEEP, K.WATCHTOWER, K.MARKET]),
			"budynki startu w funkcji")
	return true
