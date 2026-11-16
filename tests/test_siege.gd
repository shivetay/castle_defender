extends TestCase
## Samouczek PvE (#16): 5 fal o rosnącej trudności, Oblężenie startuje falę na donżon,
## obrona daje nagrodę i postęp, przegrana zostawia tę samą falę.

const K := BuildingTypes.Kind
const U := UnitTypes.Unit
const W := Battle.Winner
const R := EconomyConfig.Res
const SPAWN := Vector2i(32, 60)


func _castle() -> BuildGrid:
	var grid := BuildGrid.new(TerrainMap.generate(1337))
	grid.place(grid.manor_spot(64), K.MANOR)
	grid.place(grid.keep_spot(64), K.KEEP)
	return grid


func test_there_are_five_waves_getting_harder() -> bool:
	assert_eq(SiegeWaves.WAVE_COUNT, 5, "5 fal")
	assert_eq(SiegeWaves.WAVES.size(), 5, "5 zestawów atakujących")
	assert_eq(SiegeWaves.REWARDS.size(), 5, "5 nagród")
	var prev := 0
	for i in SiegeWaves.WAVE_COUNT:
		var n := SiegeWaves.attacker_count(i)
		assert_true(n > prev, "fala %d ma więcej atakujących niż poprzednia (%d > %d)" % [i + 1, n, prev])
		prev = n
		assert_true(not SiegeWaves.attackers(i).is_empty(), "fala %d ma oddziały" % [i + 1])
	return true


func test_tutorial_advances_only_to_five() -> bool:
	var t := SiegeTutorial.new()
	assert_eq(t.wave_number(), 1, "start od fali 1")
	assert_true(not t.is_complete(), "nieukończony")
	for i in 4:
		assert_true(not t.advance(), "po fali %d jeszcze nie koniec" % [i + 1])
		assert_eq(t.wave_number(), i + 2, "następna fala")
	assert_true(t.advance(), "piąta fala kończy samouczek")
	assert_true(t.is_complete(), "ukończony")
	assert_eq(t.wave_number(), 0, "brak numeru po ukończeniu")
	t.restart()
	assert_eq(t.next_wave, 0, "od nowa")
	return true


func test_reward_adds_gold_from_pve() -> bool:
	var e := Economy.new(0)
	var before_gold := e.amounts[R.GOLD]
	var text := SiegeWaves.grant_reward(e, 0)
	assert_true(e.amounts[R.GOLD] > before_gold, "złoto z PvE")
	assert_true(e.amounts[R.WOOD] > EconomyConfig.START[R.WOOD], "drewno")
	assert_true(text.contains("Zł") or text.contains("Dr"), "opis nagrody")
	return true


## Kryterium #16: fala atakuje donżon; silna załoga broni pierwszej fali.
func test_wave_targets_keep_and_can_be_defended() -> bool:
	var grid := _castle()
	var keep := grid.keep_id()
	assert_true(keep != 0, "jest donżon")
	var defenders: Array = [[U.AXE_WARRIOR, 10], [U.ARCHER, 8], [U.SHIELDBEARER, 6]]
	var b := Battle.create_squads(grid, keep, SiegeWaves.attackers(0), defenders, SPAWN, 42)
	assert_eq(b.objective, keep, "cel to donżon")
	assert_eq(b.run(), W.DEFENDER, "silna załoga broni fali 1")
	return true


## Słaba załoga przegrywa pierwszą falę — gracz musi wrócić do Wojska (#89).
func test_weak_garrison_loses_wave_one() -> bool:
	var grid := _castle()
	var b := Battle.create_squads(grid, grid.keep_id(), SiegeWaves.attackers(0),
			[[U.PEASANT, 1]], SPAWN, 7)
	assert_eq(b.run(), W.ATTACKER, "1 chłop nie broni fali")
	return true


func test_save_keeps_siege_progress() -> bool:
	var path := "user://test_siege_save.json"
	SaveGame.delete(path)
	var grid := _castle()
	var e := Economy.new(0)
	var q := BuildQueue.new()
	var t := SiegeTutorial.new()
	t.next_wave = 3
	assert_eq(SaveGame.write(path, SaveGame.to_dict(1337, grid, e, q, null, null, null, t)), OK, "zapis")
	var s := SaveGame.load_state(path, 0)
	assert_true(s != null, "odczyt")
	assert_eq(s.siege.next_wave, 3, "postęp fal")
	SaveGame.delete(path)
	return true


func test_v4_save_migrates_to_siege_start() -> bool:
	var grid := _castle()
	var d := SaveGame.to_dict(1337, grid, Economy.new(0), BuildQueue.new())
	d["version"] = 4
	d.erase("siege")
	var s := SaveGame.from_dict(d, 0)
	assert_true(s != null, "migracja")
	assert_eq(s.siege.next_wave, 0, "start od fali 1")
	return true


func test_battle_column_is_only_speeds() -> bool:
	assert_eq(Hud.column_targets(false, true),
			[Hud.Target.SPEED1, Hud.Target.SPEED2, Hud.Target.SPEED4] as Array[int], "×1 ×2 ×4")
	assert_eq(Hud.column_label(Hud.Target.SPEED2), "×2", "etykieta")
	assert_eq(Hud.speed_of(Hud.Target.SPEED4), 4, "mnożnik")
	var view := Vector2(320, 180)
	var right := Hud.content_bounds(view, Rect2()).y
	assert_eq(Hud.target_at(Hud.column_rect(right, 0).get_center(), view, right, false, false, false, true),
			Hud.Target.SPEED1, "bitwa: pierwszy przycisk to ×1")
	assert_eq(Hud.target_at(Hud.column_rect(right, 3).get_center(), view, right, false, false, false, false),
			Hud.Target.SIEGE, "poza bitwą Oblężenie nadal w kolumnie")
	return true


func test_speed_labels_fit_buttons() -> bool:
	for label: String in ["×1", "×2", "×4"]:
		assert_true(PixelFont.text_width(label) <= Hud.BUTTON_SIZE.x - 2, "„%s” mieści się" % label)
	return true
