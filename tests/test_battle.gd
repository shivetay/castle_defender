extends TestCase
## Symulacja bitwy (#14): determinizm (ten sam seed = ten sam przebieg), działanie bez renderu,
## warunki końca, burzenie umocnień na drodze, wieże i własny RNG.

const K := BuildingTypes.Kind
const U := UnitTypes.Unit
const W := Battle.Winner
const SPAWN := Vector2i(32, 60)


## Zamek: Dwór na wzgórzu (cel do czasu donżonu z #120), opcjonalnie pierścień palisady i wieża.
func _castle(walls: bool = false, tower: bool = false) -> Array:
	var grid := BuildGrid.new(TerrainMap.generate(1337))
	var objective := grid.place(grid.manor_spot(64), K.MANOR, 3)
	if walls:
		var r := grid.buildings[objective].grow(2)
		for x in range(r.position.x, r.end.x):
			for y: int in [r.position.y, r.end.y - 1]:
				grid.place(Rect2i(x, y, 1, 1), K.PALISADE, 2)
		for y in range(r.position.y + 1, r.end.y - 1):
			for x: int in [r.position.x, r.end.x - 1]:
				grid.place(Rect2i(x, y, 1, 1), K.PALISADE, 2)
	if tower:
		# wieża na pierwszym wolnym miejscu na prawo od celu
		var c := grid.buildings[objective].position
		for dx in range(3, 12):
			if grid.place_kind(c + Vector2i(dx, 0), K.TOWER, 3) != 0 or grid.place_kind(c + Vector2i(dx, 2), K.TOWER, 3) != 0:
				break
	return [grid, objective]


func _attackers() -> Dictionary:
	return {U.AXE_WARRIOR: 8, U.ARCHER: 4, U.RIDER: 3}


func _defenders() -> Dictionary:
	return {U.SHIELDBEARER: 3, U.ARCHER: 2}


## Kryterium #14: 100 uruchomień z tym samym seedem daje identyczny wynik. Testy działają pod
## Godot headless, więc symulacja na pewno nie potrzebuje renderu (drugie kryterium).
func test_same_seed_same_battle_100_times() -> bool:
	var c := _castle(true, true)
	var first := Battle.create(c[0], c[1], _attackers(), _defenders(), SPAWN, 42)
	first.run()
	for i in 99:
		var b := Battle.create(c[0], c[1], _attackers(), _defenders(), SPAWN, 42)
		b.run()
		if b.checksum() != first.checksum() or b.winner != first.winner or b.tick != first.tick:
			assert_true(false, "uruchomienie %d różni się od pierwszego" % (i + 2))
			break
	assert_true(first.winner != W.NONE, "bitwa się rozstrzyga")
	return true


func test_different_seed_changes_the_course() -> bool:
	var c := _castle(true, true)
	var a := Battle.create(c[0], c[1], _attackers(), _defenders(), SPAWN, 1)
	var b := Battle.create(c[0], c[1], _attackers(), _defenders(), SPAWN, 2)
	a.run()
	b.run()
	assert_true(a.checksum() != b.checksum(), "inny seed bitwy, inny przebieg")
	return true


func test_army_dict_order_does_not_matter() -> bool:
	var c := _castle()
	var a := Battle.create(c[0], c[1], {U.AXE_WARRIOR: 4, U.ARCHER: 2}, {}, SPAWN, 7)
	var b := Battle.create(c[0], c[1], {U.ARCHER: 2, U.AXE_WARRIOR: 4}, {}, SPAWN, 7)
	a.run()
	b.run()
	assert_eq(a.checksum(), b.checksum(), "kolejność kluczy w słowniku armii bez znaczenia")
	return true


func test_strong_attack_destroys_objective() -> bool:
	var c := _castle()
	var b := Battle.create(c[0], c[1], _attackers(), _defenders(), SPAWN, 42)
	assert_eq(b.run(), W.ATTACKER, "silny atak niszczy cel")
	assert_eq(b.structures[c[1]].hp, 0, "cel zniszczony")
	assert_true(b.tick < BattleConfig.time_limit_ticks(), "przed limitem czasu")
	return true


func test_attackers_break_through_walls() -> bool:
	var c := _castle(true)
	var grid: BuildGrid = c[0]
	var b := Battle.create(grid, c[1], {U.AXE_WARRIOR: 10}, {}, SPAWN, 3)
	assert_eq(b.run(), W.ATTACKER, "pierścień palisady nie zatrzymuje szturmu")
	var broken := 0
	for id: int in b.structures:
		if b.structures[id].kind == K.PALISADE and b.structures[id].hp <= 0:
			broken += 1
	assert_true(broken >= 1, "wyłom w palisadzie (%d odcinków)" % broken)
	assert_true(broken <= 3, "wyłom w jednym miejscu, nie cała linia (%d)" % broken)
	return true


func test_no_attackers_means_defender_wins() -> bool:
	var c := _castle()
	var b := Battle.create(c[0], c[1], {}, _defenders(), SPAWN, 1)
	assert_eq(b.run(), W.DEFENDER, "bez atakujących wygrywa obrońca")
	assert_eq(b.tick, 1, "od razu")
	return true


func test_time_limit_means_defender_wins() -> bool:
	var c := _castle()
	# Tropiciel nie ma ataku: dojdzie do celu, ale go nie zniszczy
	var b := Battle.create(c[0], c[1], {U.TRACKER: 2}, {}, SPAWN, 1)
	assert_eq(b.run(), W.DEFENDER, "po limicie czasu wygrywa obrońca")
	assert_eq(b.tick, BattleConfig.time_limit_ticks(), "180 s × 30 Hz")
	return true


func test_tower_shoots_and_needs_arrows() -> bool:
	var c := _castle(false, true)
	var full := Battle.create(c[0], c[1], {U.DIGGER: 6}, {}, SPAWN, 5)
	var empty := Battle.create(c[0], c[1], {U.DIGGER: 6}, {}, SPAWN, 5)
	empty.tower_fire_percent = GoodsConfig.NO_ARROWS_FIRE_PERCENT
	var towers := 0
	for id: int in full.structures:
		towers += int(full.structures[id].kind == K.TOWER)
	assert_eq(towers, 1, "wieża stoi")
	full.run(2400)
	empty.run(2400)
	var hp_full := 0
	var hp_empty := 0
	for f in full.fighters:
		hp_full += maxi(0, f.hp)
	for f in empty.fighters:
		hp_empty += maxi(0, f.hp)
	assert_true(hp_full < 6 * UnitTypes.hp(U.DIGGER), "wieża rani atakujących")
	assert_true(hp_full < hp_empty, "bez strzał wieża strzela wolniej (#88)")
	return true


func test_rng_is_deterministic_and_in_range() -> bool:
	var a := BattleRng.new(123)
	var b := BattleRng.new(123)
	for i in 1000:
		var v := a.range_int(90, 110)
		assert_eq(v, b.range_int(90, 110), "ten sam ciąg")
		if v < 90 or v > 110:
			assert_true(false, "liczba poza zakresem: %d" % v)
			break
	assert_true(BattleRng.new(0).next_u32() != 0, "seed 0 nie zatrzymuje generatora")
	return true


func test_battle_logic_uses_no_floats() -> bool:
	var src := FileAccess.get_file_as_string("res://scripts/battle/battle.gd")
	for word: String in [": float", "-> float", "randf", "randi()"]:
		assert_true(not src.contains(word), "logika bitwy bez „%s”" % word)
	return true
