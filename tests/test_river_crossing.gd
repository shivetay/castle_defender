extends TestCase
## Rzeka i most (#248): woda jest nieprzechodnia, brzegi łączy most, a jednostki obu stron nigdy
## nie stają na kratce wody. Wszystko z seedem, więc ten sam przebieg powtarza się co do ticku.

const U := UnitTypes.Unit
const M := AttackPlan.Manoeuvre
const TICKS := 1500


func _count(map: TerrainMap, tile: int) -> int:
	var n := 0
	for t in map.tiles:
		if t == tile:
			n += 1
	return n


## Pierwsza kolumna wody w wierszu `y` (-1 bez wody).
func _river_x(map: TerrainMap, y: int) -> int:
	for x in map.size:
		if map.get_tile(Vector2i(x, y)) == TerrainMap.Tile.WATER:
			return x
	return -1


## Przebieg bitwy tick po ticku: pierwsza jednostka w wodzie (opis) albo pusty napis; w `seen`
## zbiera kratki mostu, na których stanął atakujący.
func _water_walker(b: Battle, map: TerrainMap, seen: Dictionary) -> String:
	while b.winner == Battle.Winner.NONE and b.tick < TICKS:
		b.step()
		for f in b.fighters:
			if not f.alive():
				continue
			var c := f.cell()
			var t := map.get_tile(c)
			if t == TerrainMap.Tile.WATER:
				return "tick %d: jednostka %d (strona %d) w wodzie na %s" % [b.tick, f.unit, f.side, c]
			if t == TerrainMap.Tile.BRIDGE and f.side == Battle.Side.ATTACKER:
				seen[c] = true
	return ""


func test_every_seed_has_land_joined_by_bridge() -> bool:
	for s in range(1, 301):
		var map := TerrainMap.generate(s)
		assert_true(_count(map, TerrainMap.Tile.WATER) >= 64, "seed %d: rzeka" % s)
		assert_true(_count(map, TerrainMap.Tile.BRIDGE) >= 1, "seed %d: most" % s)
		assert_true(map.land_connected(), "seed %d: ląd po obu stronach rzeki łączy most" % s)
	return true


@warning_ignore("integer_division")
func test_water_is_not_walkable_bridge_is() -> bool:
	var map := TerrainMap.generate(1337)
	var water := Vector2i(_river_x(map, 10), 10)
	assert_true(not map.is_walkable(water), "woda nieprzechodnia")
	for i in map.tiles.size():
		if map.tiles[i] == TerrainMap.Tile.BRIDGE:
			assert_true(map.is_walkable(Vector2i(i % map.size, i / map.size)), "most przechodni")
	assert_true(not map.is_walkable(Vector2i(-1, 0)), "poza mapą nieprzechodnie")
	return true


## Bez mostu rzeka odcina brzeg; ensure_crossing kładzie most i znów łączy ląd. Zwykły teren
## zostaje bez zmian (ten sam seed, ten sam teren).
func test_missing_bridge_is_restored() -> bool:
	var map := TerrainMap.generate(1337)
	assert_true(not map.ensure_crossing(), "teren z mostem zostaje bez zmian")
	assert_eq(map.tiles, TerrainMap.generate(1337).tiles, "ten sam seed, te same kratki")
	for i in map.tiles.size():
		if map.tiles[i] == TerrainMap.Tile.BRIDGE:
			map.tiles[i] = TerrainMap.Tile.WATER
	assert_true(not map.land_connected(), "bez mostu rzeka odcina brzeg")
	assert_true(map.ensure_crossing(), "most dołożony")
	assert_true(map.land_connected(), "po dołożeniu ląd jest spójny")
	assert_true(_count(map, TerrainMap.Tile.BRIDGE) >= 2, "most przez całą szerokość rzeki")
	return true


## Krok ruchu nigdy nie kończy się w wodzie, nawet gdy cel ruchu leży za rzeką na wprost.
func test_step_never_ends_in_water() -> bool:
	var grid := BuildGrid.new(TerrainMap.generate(1337))
	var map := grid.terrain
	var b := Battle.create(grid, grid.place(grid.manor_spot(64), BuildingTypes.Kind.MANOR, 3),
			{U.RIDER: 1}, {}, Vector2i(32, 60), 5)
	var f: Battle.Fighter = b.fighters[0]
	var y := 10
	var rx := _river_x(map, y)
	var bank := Vector2i(rx - 1, y)
	var across := Vector2i(rx + 3, y)
	assert_true(map.is_walkable(bank), "start na brzegu")
	f.x = bank.x * BattleConfig.SUB + BattleConfig.SUB / 2
	f.y = bank.y * BattleConfig.SUB + BattleConfig.SUB / 2
	for i in 60:
		b._move_toward(f, across.x * BattleConfig.SUB + BattleConfig.SUB / 2, across.y * BattleConfig.SUB + BattleConfig.SUB / 2)
		assert_true(map.is_walkable(f.cell()), "krok %d: jednostka nie wchodzi do wody" % i)
	assert_eq(f.cell(), bank, "bez mostu na wprost zostaje na brzegu")
	return true


## Zamek-bot 1 ma wejście za rzeką: atakujący idą do donżonu przez most, a nikt z obu stron
## (z pościgiem obrońców i odwrotem) nie staje w wodzie. Ten sam seed daje ten sam przebieg.
func test_attack_from_across_river_uses_bridge() -> bool:
	var bot := BotRoster.generate(1)
	var map := bot.grid.terrain
	var rx := _river_x(map, bot.spawn.y)
	assert_true(rx >= 0 and bot.spawn.x < rx, "wejście na zachód od rzeki (zamek 1)")
	var army: Array = [[U.AXE_WARRIOR, 6], [U.ARCHER, 4], [U.RIDER, 3]]
	var plan := AttackPlan.new()
	plan.add(2, M.RANGED).retreat_percent = 30
	plan.add(3, M.FLANK).flank_left = false
	var runs: Array[int] = []
	for run in 2:
		var b := Battle.create_squads(bot.grid, bot.objective, army, bot.defenders, bot.spawn, 1007)
		b.set_plan(AttackPlan.from_dict(plan.to_dict()))
		var seen := {}
		var problem := _water_walker(b, map, seen)
		assert_eq(problem, "", "nikt nie wchodzi do wody")
		assert_true(not seen.is_empty(), "atakujący przechodzą mostem")
		runs.append(b.checksum())
	assert_eq(runs[0], runs[1], "ten sam seed, ten sam przebieg")
	return true


## Punkt trasy za rzeką: oddział obchodzi wodę mostem i dochodzi na drugi brzeg.
func test_waypoint_across_river_goes_over_bridge() -> bool:
	var grid := BuildGrid.new(TerrainMap.generate(1337))
	var map := grid.terrain
	var objective := grid.place(grid.manor_spot(64), BuildingTypes.Kind.MANOR, 3)
	var rx := _river_x(map, 50)
	var far := Vector2i(rx - 3 if rx < 32 else rx + 4, 50)
	assert_true(map.is_walkable(far), "punkt trasy na lądzie")
	var b := Battle.create_squads(grid, objective, [[U.RIDER, 3]], [], Vector2i(32, 60), 9)
	var plan := AttackPlan.new()
	plan.add(1, M.FRONTAL).waypoints = [far] as Array[Vector2i]
	b.set_plan(plan)
	var seen := {}
	var reached := false
	while b.winner == Battle.Winner.NONE and b.tick < TICKS and not reached:
		b.step()
		for f in b.fighters:
			var c := f.cell()
			assert_true(map.get_tile(c) != TerrainMap.Tile.WATER, "tick %d: jeździec w wodzie na %s" % [b.tick, c])
			if map.get_tile(c) == TerrainMap.Tile.BRIDGE:
				seen[c] = true
			if (c - far).length_squared() <= 2:
				reached = true
	assert_true(reached, "oddział doszedł na drugi brzeg")
	assert_true(not seen.is_empty(), "przez rzekę tylko mostem")
	return true
