extends TestCase
## Samouczek PvE (#16): 5 fal o rosnącej trudności na donżon gracza, przycisk Oblężenie, tempo,
## nagrody i postęp w zapisie.

const K := BuildingTypes.Kind
const U := UnitTypes.Unit
const W := Battle.Winner
const MAIN := preload("res://scripts/main.gd")


func _castle() -> BuildGrid:
	var grid := BuildGrid.new(TerrainMap.generate(1337))
	grid.place(grid.manor_spot(64), K.MANOR, 3)
	grid.place(grid.keep_spot(64), K.KEEP, 2)
	return grid


func test_five_waves_grow() -> bool:
	assert_eq(PveWaves.COUNT, 5, "5 fal")
	for i in range(1, PveWaves.COUNT):
		assert_true(PveWaves.size(i) > PveWaves.size(i - 1), "fala %d większa niż %d" % [i + 1, i])
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


## Trudność naprawdę rośnie: ten sam oddział obrońców broni pierwszej fali, a ostatniej już nie.
func test_difficulty_rises_against_same_defence() -> bool:
	var grid := _castle()
	var defence := [[U.AXE_WARRIOR, 8]]
	var first := Battle.for_castle_squads(grid, PveWaves.squads(0), defence, Vector2i(32, 60), PveWaves.battle_seed(1337, 0))
	assert_eq(first.run(), W.DEFENDER, "fala 1 obroniona")
	var last := Battle.for_castle_squads(grid, PveWaves.squads(4), defence, Vector2i(32, 60), PveWaves.battle_seed(1337, 4))
	assert_eq(last.run(), W.ATTACKER, "fala 5 za silna na 8 toporników")
	return true


func test_wave_battle_is_deterministic() -> bool:
	var grid := _castle()
	assert_eq(PveWaves.battle_seed(1337, 2), PveWaves.battle_seed(1337, 2), "ten sam seed fali")
	assert_true(PveWaves.battle_seed(1337, 2) != PveWaves.battle_seed(1337, 3), "inna fala, inny seed")
	var a := Battle.for_castle_squads(grid, PveWaves.squads(2), [[U.AXE_WARRIOR, 6]], Vector2i(32, 60), PveWaves.battle_seed(1337, 2))
	var b := Battle.for_castle_squads(grid, PveWaves.squads(2), [[U.AXE_WARRIOR, 6]], Vector2i(32, 60), PveWaves.battle_seed(1337, 2))
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
