extends TestCase
## Samouczek PvE (#16): 5 fal o rosnącej trudności na donżon gracza, przycisk Oblężenie, tempo,
## nagrody i postęp w zapisie.

const K := BuildingTypes.Kind
const U := UnitTypes.Unit
const W := Battle.Winner
const MAIN := preload("res://scripts/main.gd")


## Zamek startowy gracza: Dwór 1 i Koszary (donżon) 1 na pierwszej grywalnej mapie seeda.
func _castle(world_seed: int = 1337) -> BuildGrid:
	var grid := BuildGrid.new(TerrainMap.generate(WorldSeed.first_playable(world_seed)))
	grid.place(grid.manor_spot(64), K.MANOR, 1)
	grid.place(grid.keep_spot(64), K.KEEP, 1)
	return grid


## Wejście fali: pierwsze pole drogi na krawędzi mapy.
func _spawn(grid: BuildGrid) -> Vector2i:
	var last := grid.terrain.size - 1
	for i in grid.terrain.size:
		for c: Vector2i in [Vector2i(i, last), Vector2i(i, 0), Vector2i(0, i), Vector2i(last, i)]:
			if grid.terrain.get_tile(c) == TerrainMap.Tile.PATH:
				return c
	return Vector2i(32, last - 1)


## Siła fali: suma HP × atak jej jednostek (prosta miara do porównania fal).
func _strength(wave: int) -> int:
	var total := 0
	for sq: Array in PveWaves.squads(wave):
		total += int(sq[1]) * UnitTypes.hp(int(sq[0])) * UnitTypes.attack(int(sq[0]))
	return total


func test_five_waves_grow() -> bool:
	assert_eq(PveWaves.COUNT, 5, "5 fal")
	for i in range(1, PveWaves.COUNT):
		assert_true(PveWaves.size(i) >= PveWaves.size(i - 1), "fala %d nie mniejsza niż %d" % [i + 1, i])
		assert_true(_strength(i) > _strength(i - 1), "fala %d silniejsza niż %d" % [i + 1, i])
		var a := 0
		var b := 0
		for r in PveWaves.reward(i):
			a += r
		for r in PveWaves.reward(i - 1):
			b += r
		assert_true(a > b, "nagroda rośnie")
	for i in PveWaves.COUNT:
		for sq: Array in PveWaves.squads(i):
			assert_eq(UnitTypes.age(int(sq[0])), 0, "fala %d: tylko jednostki epoki I" % (i + 1))
	return true


## Balans na prawdziwym starcie, na kilku mapach: obrona, jaką gracz może mieć na danym etapie
## samouczka (PveWaves.EXPECTED_DEFENCE, fala 1 to 6 Chłopów), wygrywa, a sami Chłopi w mniejszej
## liczbie (2, 4, 6, 8, 10) przegrywają, więc trudność rośnie i trzeba rozwijać armię.
func test_expected_defence_holds_and_weak_falls() -> bool:
	for world_seed: int in [1337, 42, 9001]:
		var grid := _castle(world_seed)
		var spawn := _spawn(grid)
		for w in PveWaves.COUNT:
			var bs := PveWaves.battle_seed(world_seed, w)
			var good := Battle.for_castle_squads(grid, PveWaves.squads(w), PveWaves.EXPECTED_DEFENCE[w], spawn, bs)
			assert_eq(good.run(), W.DEFENDER, "seed %d, fala %d: oczekiwana obrona wygrywa" % [world_seed, w + 1])
			var weak := Battle.for_castle_squads(grid, PveWaves.squads(w), [[U.PEASANT, 2 * (w + 1)]], spawn, bs)
			assert_eq(weak.run(), W.ATTACKER, "seed %d, fala %d: %d Chłopów to za mało" % [world_seed, w + 1, 2 * (w + 1)])
	return true


func test_first_wave_fits_starting_army() -> bool:
	var defence: Array = PveWaves.EXPECTED_DEFENCE[0]
	assert_eq(defence.size(), 1, "jeden oddział")
	assert_eq(int((defence[0] as Array)[0]), U.PEASANT, "same Chłopy, bez badań")
	assert_true(int((defence[0] as Array)[1]) <= Recruitment.army_limit(_castle()), "mieści się w limicie wojska na starcie")
	return true


func test_wave_battle_is_deterministic() -> bool:
	var grid := _castle()
	assert_eq(PveWaves.battle_seed(1337, 2), PveWaves.battle_seed(1337, 2), "ten sam seed fali")
	assert_true(PveWaves.battle_seed(1337, 2) != PveWaves.battle_seed(1337, 3), "inna fala, inny seed")
	var a := Battle.for_castle_squads(grid, PveWaves.squads(2), [[U.AXE_WARRIOR, 6]], _spawn(grid), PveWaves.battle_seed(1337, 2))
	var b := Battle.for_castle_squads(grid, PveWaves.squads(2), [[U.AXE_WARRIOR, 6]], _spawn(grid), PveWaves.battle_seed(1337, 2))
	a.run()
	b.run()
	assert_eq(a.checksum(), b.checksum(), "ta sama fala, ten sam przebieg")
	return true


func test_siege_button_rules_and_speed() -> bool:
	assert_eq(MAIN.siege_problem(0, 0, 5), "Najpierw wyszkol wojsko: Koszary i Wojsko", "bez wojska fala nie rusza")
	assert_eq(MAIN.siege_problem(0, 1, 5), "", "z oddziałem rusza")
	assert_eq(MAIN.siege_problem(5, 1, 5), Hud.SIEGE_LATER_MESSAGE, "po 5 falach koniec samouczka")
	assert_eq(MAIN.next_speed(1), 2, "1 → 2")
	assert_eq(MAIN.next_speed(2), 4, "2 → 4")
	assert_eq(MAIN.next_speed(4), 1, "4 → 1")
	for s: int in [1, 2, 4]:
		assert_true(PixelFont.text_width(MAIN.speed_label(s)) <= Hud.BUTTON_SIZE.x - 2, "napis tempa na przycisku")
	assert_eq(Hud.column_targets(false, true), [Hud.Target.SPEED] as Array[int], "w bitwie tylko tempo")
	return true


func test_progress_survives_save_and_migration() -> bool:
	var grid := _castle()
	var data := SaveGame.to_dict(1337, grid, Economy.new(0), BuildQueue.new(), Research.new(), Goods.new(0),
			Recruitment.new(), 3)
	var parsed: Variant = JSON.parse_string(JSON.stringify(data))
	var s := SaveGame.from_dict(parsed as Dictionary, 0)
	assert_eq(s.pve_cleared, 3, "postęp po odczycie")
	var old := (parsed as Dictionary).duplicate(true)
	old["version"] = 4
	old.erase("pve")
	assert_eq(SaveGame.from_dict(old, 0).pve_cleared, 0, "zapis v4 zaczyna od fali 1")
	return true
