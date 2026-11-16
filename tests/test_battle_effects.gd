extends TestCase
## Efekty bitwy (#101): strzały, pociski z cieniem, pył i ogień. Efekty to tylko rysowanie,
## więc najważniejszy test: zapis zdarzeń dla efektów nie zmienia przebiegu ani wyniku bitwy.

const K := BuildingTypes.Kind
const U := UnitTypes.Unit
const SPAWN := Vector2i(32, 60)


## Zamek z pierścieniem palisady wokół Dworu i wieżą obok (jak w test_battle).
func _castle() -> Array:
	var grid := BuildGrid.new(TerrainMap.generate(1337))
	var objective := grid.place(grid.manor_spot(64), K.MANOR, 3)
	var r := grid.buildings[objective].grow(2)
	for x in range(r.position.x, r.end.x):
		for y: int in [r.position.y, r.end.y - 1]:
			grid.place(Rect2i(x, y, 1, 1), K.PALISADE, 2)
	for y in range(r.position.y + 1, r.end.y - 1):
		for x: int in [r.position.x, r.end.x - 1]:
			grid.place(Rect2i(x, y, 1, 1), K.PALISADE, 2)
	var c := grid.buildings[objective].position
	for dx in range(3, 12):
		if grid.place_kind(c + Vector2i(dx, 0), K.TOWER, 3) != 0 or grid.place_kind(c + Vector2i(dx, 2), K.TOWER, 3) != 0:
			break
	return [grid, objective]


func _battle(fx: bool) -> Battle:
	var c := _castle()
	var b := Battle.create_squads(c[0], c[1], [[U.AXE_WARRIOR, 8], [U.ARCHER, 4], [U.JAVELINEER, 3], [U.FIRE_RAISER, 3]],
			[[U.SHIELDBEARER, 3], [U.ARCHER, 3]], SPAWN, 42)
	b.record_fx = fx
	return b


## Zbiera wszystkie zdarzenia całej bitwy, odczytując je co krok jak widok.
func _run_collecting(b: Battle) -> Array[PackedInt32Array]:
	var all: Array[PackedInt32Array] = []
	while b.winner == Battle.Winner.NONE and b.tick < BattleConfig.time_limit_ticks():
		b.step()
		all.append_array(b.take_fx())
	return all


func test_effects_do_not_change_the_battle() -> bool:
	var plain := _battle(false)
	plain.run()
	var shown := _battle(true)
	_run_collecting(shown)
	assert_eq(shown.checksum(), plain.checksum(), "ta sama suma kontrolna z efektami i bez")
	assert_eq(shown.winner, plain.winner, "ten sam zwycięzca")
	assert_eq(shown.tick, plain.tick, "ten sam czas bitwy")
	return true


func test_battle_records_shots_hits_and_collapse() -> bool:
	var events := _run_collecting(_battle(true))
	var kinds := {}
	var shooters := {}
	for e in events:
		kinds[e[1]] = true
		if e[1] == Battle.Fx.SHOT:
			shooters[e[2]] = true
	assert_true(kinds.has(Battle.Fx.SHOT), "strzały")
	assert_true(kinds.has(Battle.Fx.HIT), "uderzenia w umocnienia")
	assert_true(kinds.has(Battle.Fx.COLLAPSE), "zawalenie palisady")
	assert_true(shooters.has(U.ARCHER), "strzela łucznik")
	assert_true(shooters.has(Battle.FX_TOWER), "strzela wieża")
	assert_true(not shooters.has(U.AXE_WARRIOR), "topornik nie strzela")
	return true


func test_without_view_nothing_is_recorded() -> bool:
	var b := _battle(false)
	b.run()
	assert_eq(b.take_fx().size(), 0, "bez widoku lista zdarzeń nie rośnie")
	return true


func test_missile_flies_from_shooter_to_target() -> bool:
	var fx := BattleEffects.new()
	var sub := BattleConfig.SUB
	fx.add_events([PackedInt32Array([10, Battle.Fx.SHOT, U.JAVELINEER, 2 * sub, 2 * sub, 6 * sub, 2 * sub])] as Array[PackedInt32Array])
	assert_eq(fx.items.size(), 1, "jeden pocisk")
	var it := fx.items[0]
	assert_eq(it[7], BattleEffects.Missile.JAVELIN, "oszczepnik rzuca oszczepem")
	var c := TerrainMap.CELL
	assert_eq(BattleEffects.missile_ground(it, 10), Vector2i(2 * c, 2 * c), "start przy strzelcu")
	assert_eq(BattleEffects.missile_ground(it, 10 + it[2]), Vector2i(6 * c, 2 * c), "koniec przy celu")
	assert_eq(BattleEffects.missile_height(it, 10), 0, "start na ziemi")
	@warning_ignore("integer_division")
	assert_true(BattleEffects.missile_height(it, 10 + it[2] / 2) > 0, "w połowie lotu nad cieniem")
	assert_eq(BattleEffects.missile_for(U.ARCHER), BattleEffects.Missile.ARROW, "łucznik: strzała")
	assert_eq(BattleEffects.missile_for(Battle.FX_TOWER), BattleEffects.Missile.ARROW, "wieża: strzała")
	assert_eq(BattleEffects.missile_for(U.FIRE_RAISER), BattleEffects.Missile.POT, "podpalacz: garnek smoły")
	var arrow := PackedInt32Array([BattleEffects.Kind.MISSILE, 0, 8, 0, 0, 30, 0, BattleEffects.Missile.ARROW])
	assert_eq(BattleEffects.missile_height(arrow, 4), 0, "strzała leci płasko")
	var line := BattleEffects.streak(Vector2i(10, 5), Vector2i(0, 5), Vector2i(30, 5), BattleEffects.ARROW_LEN)
	assert_eq(line, [Vector2i(10, 5), Vector2i(9, 5), Vector2i(8, 5)] as Array[Vector2i], "strzała to kreska 1 px wzdłuż lotu")
	return true


func test_effects_expire_and_are_capped() -> bool:
	var fx := BattleEffects.new()
	var events: Array[PackedInt32Array] = []
	for i in BattleEffects.MAX_ITEMS + 20:
		events.append(PackedInt32Array([0, Battle.Fx.HIT, U.AXE_WARRIOR, 0, 0, 100, 100]))
	fx.add_events(events)
	assert_eq(fx.items.size(), BattleEffects.MAX_ITEMS, "limit efektów naraz")
	fx.prune(BattleEffects.DUST_TICKS - 1)
	assert_eq(fx.items.size(), BattleEffects.MAX_ITEMS, "pył jeszcze trwa")
	fx.prune(BattleEffects.DUST_TICKS)
	assert_eq(fx.items.size(), 0, "pył opadł")
	return true


func test_particles_are_deterministic_and_whole_pixels() -> bool:
	var collapse := PackedInt32Array([BattleEffects.Kind.COLLAPSE, 5, BattleEffects.COLLAPSE_TICKS, 40, 48, 16, 8, 0])
	var a := BattleEffects.dust_pixels(collapse, 15)
	assert_eq(a, BattleEffects.dust_pixels(collapse, 15), "ten sam pył")
	assert_eq(a.size(), BattleEffects.COLLAPSE_PER_CELL * 2, "cząstki na każdą kratkę budynku")
	var rect := Rect2i(40, 48, 16, 8)
	var flames := BattleEffects.flame_pixels(rect, 9)
	assert_eq(flames, BattleEffects.flame_pixels(rect, 9), "ten sam ogień w tym samym ticku")
	assert_true(flames != BattleEffects.flame_pixels(rect, 12), "ogień migocze")
	for p in flames:
		assert_true(rect.has_point(Vector2i(p.x, p.y)), "płomień nad budynkiem")
	for p in BattleEffects.smoke_pixels(rect, 9):
		assert_true(p.y <= rect.position.y + 2, "dym nad dachem")
	return true


## Ogień przechodzi na sąsiednie drewno (#101): po FIRE_SPREAD_S sekundach płonie sąsiednia palisada,
## a dalej kolejny odcinek. Wał ziemny i dalekie budynki nie zajmują się ogniem.
func test_fire_spreads_to_neighbouring_wood() -> bool:
	var grid := BuildGrid.new(TerrainMap.generate(1337))
	var manor := grid.place(grid.manor_spot(64), K.MANOR, 3)
	var r := grid.buildings[manor]
	var p1 := grid.place(Rect2i(r.end.x, r.position.y, 1, 1), K.PALISADE, 1)
	var p2 := grid.place(Rect2i(r.end.x + 1, r.position.y, 1, 1), K.PALISADE, 1)
	var earth := grid.place(Rect2i(r.position.x, r.end.y, 1, 1), K.RAMPART, 1)
	var far := grid.place(Rect2i(r.end.x + 6, r.position.y, 1, 1), K.PALISADE, 1)
	assert_true(p1 > 0 and p2 > 0 and earth > 0 and far > 0, "budynki stoją")
	var b := Battle.create(grid, manor, {}, {}, SPAWN, 1)
	var s := b.structures
	s[manor].burning = BattleConfig.FIRE_S * BattleConfig.TICK_HZ
	var spread_ticks := BattleConfig.FIRE_SPREAD_S * BattleConfig.TICK_HZ
	for i in spread_ticks - 1:
		b._burn(s[manor])
	assert_eq(s[p1].burning, 0, "przed czasem sąsiad nie płonie")
	b._burn(s[manor])
	assert_eq(s[p1].burning, BattleConfig.FIRE_S * BattleConfig.TICK_HZ, "sąsiednia palisada się zajmuje")
	assert_eq(s[p2].burning, 0, "dalszy odcinek jeszcze nie")
	assert_eq(s[earth].burning, 0, "wał ziemny nie płonie")
	for i in spread_ticks:
		b._burn(s[p1])
	assert_true(s[p2].burning > 0, "ogień idzie dalej po palisadzie")
	assert_eq(s[far].burning, 0, "daleki budynek nie płonie")
	return true
