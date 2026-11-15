extends TestCase
## Oddziały w bitwie i cechy jednostek (#15, #92): każda cecha z notatki Jednostki ma test
## na liczbach całkowitych, a cała bitwa z cechami zostaje deterministyczna.

const K := BuildingTypes.Kind
const U := UnitTypes.Unit
const SPAWN := Vector2i(32, 60)


func _castle() -> Array:
	var grid := BuildGrid.new(TerrainMap.generate(1337))
	var objective := grid.place(grid.manor_spot(64), K.MANOR, 3)
	return [grid, objective]


func _fighter(unit: int, side: int, cx: int, cy: int) -> Battle.Fighter:
	var f := Battle.Fighter.new()
	f.unit = unit
	f.side = side
	f.hp = UnitTypes.hp(unit)
	f.x = cx * BattleConfig.SUB + BattleConfig.SUB / 2
	f.y = cy * BattleConfig.SUB + BattleConfig.SUB / 2
	return f


## Pusta bitwa (bez armii) do liczenia obrażeń na ręcznie ustawionych jednostkach.
func _empty() -> Battle:
	var c := _castle()
	return Battle.create(c[0], c[1], {}, {}, SPAWN, 1)


func test_squads_keep_their_order_and_size() -> bool:
	var c := _castle()
	var b := Battle.create_squads(c[0], c[1], [[U.ARCHER, 3], [U.AXE_WARRIOR, 5]], [[U.SHIELDBEARER, 2]], SPAWN, 3)
	var view := b.squads_view(Battle.Side.ATTACKER)
	assert_eq(view.size(), 2, "dwa oddziały atakujących")
	assert_eq(int(view[0]["unit"]), U.ARCHER, "pierwszy oddział to łucznicy, jak w liście")
	assert_eq(int(view[0]["alive"]), 3, "3 łuczników")
	assert_eq(int(view[1]["alive"]), 5, "5 toporników")
	assert_eq(int(view[1]["hp"]), 5 * UnitTypes.hp(U.AXE_WARRIOR), "pełne zdrowie oddziału")
	assert_eq(b.squads_view(Battle.Side.DEFENDER).size(), 1, "jeden oddział obrońców")
	return true


func test_dead_squad_disappears_from_view() -> bool:
	var c := _castle()
	var b := Battle.create_squads(c[0], c[1], [[U.ARCHER, 2], [U.AXE_WARRIOR, 1]], [], SPAWN, 3)
	for f in b.fighters:
		if f.unit == U.ARCHER:
			f.hp = 0
	var view := b.squads_view(Battle.Side.ATTACKER)
	assert_eq(view.size(), 1, "martwy oddział znika z widoku")
	assert_eq(int(view[0]["unit"]), U.AXE_WARRIOR, "zostaje topornik")
	return true


func test_recruitment_squads_go_to_battle() -> bool:
	var r := Recruitment.new()
	r.add_squad(U.AXE_WARRIOR, 7)
	r.add_squad(U.ARCHER, 0)
	r.add_squad(U.ARCHER, 4)
	var sq := r.battle_squads()
	assert_eq(sq.size(), 2, "pusty oddział nie idzie do bitwy")
	assert_eq(int((sq[0] as Array)[1]), 7, "7 toporników")
	assert_eq(int((sq[1] as Array)[0]), U.ARCHER, "potem łucznicy")
	return true


func test_shield_wall_protects_self_and_neighbours_from_arrows() -> bool:
	var b := _empty()
	var archer := _fighter(U.ARCHER, Battle.Side.ATTACKER, 10, 10)
	var shield := _fighter(U.SHIELDBEARER, Battle.Side.DEFENDER, 15, 10)
	var near := _fighter(U.AXE_WARRIOR, Battle.Side.DEFENDER, 16, 10)
	var far := _fighter(U.AXE_WARRIOR, Battle.Side.DEFENDER, 18, 10)
	b.fighters.append_array([archer, shield, near, far])
	var base := UnitTypes.damage(U.ARCHER, U.AXE_WARRIOR)
	assert_eq(b.unit_damage(archer, far), base, "daleko od tarcz: pełne obrażenia")
	assert_eq(b.unit_damage(archer, near), base * 60 / 100, "obok Tarczownika: −40%")
	assert_eq(b.unit_damage(archer, shield), UnitTypes.damage(U.ARCHER, U.SHIELDBEARER) * 60 / 100, "sam Tarczownik: −40%")
	var axe := _fighter(U.AXE_WARRIOR, Battle.Side.ATTACKER, 17, 10)
	assert_eq(b.unit_damage(axe, near), UnitTypes.damage(U.AXE_WARRIOR, U.AXE_WARRIOR), "tarcze nie chronią przed toporem")
	return true


func test_gambeson_reduces_melee_only() -> bool:
	var b := _empty()
	var g := _fighter(U.GAMBESON_WARRIOR, Battle.Side.DEFENDER, 10, 10)
	var axe := _fighter(U.AXE_WARRIOR, Battle.Side.ATTACKER, 11, 10)
	var archer := _fighter(U.REFLEX_ARCHER, Battle.Side.ATTACKER, 14, 10)
	assert_eq(b.unit_damage(axe, g), UnitTypes.damage(U.AXE_WARRIOR, U.GAMBESON_WARRIOR) * 75 / 100, "wręcz −25%")
	assert_eq(b.unit_damage(archer, g), UnitTypes.damage(U.REFLEX_ARCHER, U.GAMBESON_WARRIOR), "strzały bez zmian")
	return true


func test_lancer_charges_only_once() -> bool:
	var b := _empty()
	var lancer := _fighter(U.LANCER, Battle.Side.ATTACKER, 10, 10)
	var target := _fighter(U.TRACKER, Battle.Side.DEFENDER, 11, 10)
	target.hp = 10000
	b.fighters.append_array([lancer, target])
	var base := UnitTypes.damage(U.LANCER, U.TRACKER)
	assert_eq(b.unit_damage(lancer, target), base * 2, "szarża: ×2")
	b._strike_unit(lancer, target)
	assert_eq(b.unit_damage(lancer, target), base, "po pierwszym uderzeniu bez szarży")
	return true


func test_axe_is_stronger_against_wood() -> bool:
	var axe := UnitTypes.attack(U.AXE_WARRIOR)
	assert_eq(Battle.structure_damage(U.AXE_WARRIOR, K.PALISADE), axe * 3 / 2, "palisada: ×1,5")
	assert_eq(Battle.structure_damage(U.AXE_WARRIOR, K.RAMPART), axe, "wał ziemny: bez premii")
	assert_eq(Battle.structure_damage(U.JAVELINEER, K.PALISADE), UnitTypes.attack(U.JAVELINEER), "oszczep bez premii")
	return true


func test_ram_only_damages_gates() -> bool:
	assert_eq(Battle.structure_damage(U.RAM, K.PALISADE), 0, "taran nie bije palisady")
	assert_eq(Battle.structure_damage(U.RAM, K.MANOR), 0, "taran nie bije Dworu")
	assert_eq(Battle.structure_damage(U.RAM, K.GATE), UnitTypes.attack(U.RAM), "taran bije bramę")
	return true


func test_ram_drives_to_the_gate_and_breaks_it() -> bool:
	var grid := BuildGrid.new(TerrainMap.generate(1337))
	var objective := grid.place(grid.manor_spot(64), K.MANOR, 3)
	var spot := grid.spot_near(grid.buildings[objective].position + Vector2i(0, 6), K.GATE, 12)
	assert_true(spot.has_area(), "jest miejsce na bramę")
	var gate := grid.place(spot, K.GATE, 1)
	var b := Battle.create(grid, objective, {U.RAM: 1}, {}, SPAWN, 5)
	b.run(BattleConfig.TICK_HZ * 120)
	assert_true(b.structures[gate].hp < b.structures[gate].max_hp, "taran dojechał do bramy i ją bije")
	assert_eq(b.structures[objective].hp, b.structures[objective].max_hp, "Dworu nie rusza")
	return true


func test_rider_skips_slow_targets() -> bool:
	var b := _empty()
	var rider := _fighter(U.RIDER, Battle.Side.ATTACKER, 10, 10)
	var shield := _fighter(U.SHIELDBEARER, Battle.Side.DEFENDER, 12, 10)
	var archer := _fighter(U.ARCHER, Battle.Side.DEFENDER, 14, 10)
	b.fighters.append_array([rider, shield, archer])
	assert_true(b._enemy_for(rider) == archer, "jeździec mija wolnego Tarczownika i jedzie na łucznika")
	shield.x = rider.x + BattleConfig.SUB
	assert_true(b._enemy_for(rider) == shield, "wolny wróg tuż obok jest celem")
	return true


func test_javelineer_throws_from_distance() -> bool:
	var b := _empty()
	var jav := _fighter(U.JAVELINEER, Battle.Side.ATTACKER, 10, 10)
	var enemy := _fighter(U.AXE_WARRIOR, Battle.Side.DEFENDER, 13, 10)
	b.fighters.append_array([jav, enemy])
	b._act(jav)
	assert_true(enemy.hp < UnitTypes.hp(U.AXE_WARRIOR), "oszczep trafia z 3 kratek, zanim wróg podejdzie")
	assert_eq(jav.x, 10 * BattleConfig.SUB + BattleConfig.SUB / 2, "oszczepnik rzuca w miejscu")
	return true


func test_fire_burns_wooden_buildings() -> bool:
	var b := _empty()
	var manor: Battle.Structure = null
	for id: int in b.structures:
		manor = b.structures[id]
	var raiser := _fighter(U.FIRE_RAISER, Battle.Side.ATTACKER, 10, 10)
	b._strike_structure(raiser, manor)
	assert_eq(manor.burning, BattleConfig.FIRE_S * BattleConfig.TICK_HZ, "Dwór płonie")
	var hp := manor.hp
	# pusta bitwa kończy się od razu, więc ogień liczymy wprost, tak jak robi to step()
	while manor.burning > 0:
		b._burn(manor)
	assert_eq(manor.burning, 0, "ogień gaśnie")
	assert_eq(manor.hp, hp - BattleConfig.FIRE_S * BattleConfig.FIRE_DAMAGE_PER_S, "ogień zabiera stałą liczbę punktów")
	return true


func test_traits_battle_is_deterministic() -> bool:
	var c := _castle()
	var att := [[U.LANCER, 3], [U.FIRE_RAISER, 4], [U.JAVELINEER, 5], [U.RAM, 1]]
	var dfn := [[U.SHIELDBEARER, 4], [U.GAMBESON_WARRIOR, 2], [U.ARCHER, 3]]
	var first := Battle.create_squads(c[0], c[1], att, dfn, SPAWN, 77)
	first.run()
	for i in 20:
		var b := Battle.create_squads(c[0], c[1], att, dfn, SPAWN, 77)
		b.run()
		if b.checksum() != first.checksum() or b.tick != first.tick:
			assert_true(false, "uruchomienie %d różni się" % (i + 2))
			break
	return true


func test_badges_do_not_overlap() -> bool:
	var squads: Array[Dictionary] = []
	for i in 4:
		squads.append({"unit": U.AXE_WARRIOR, "alive": 10, "hp": 600, "max_hp": 600, "x": 2000, "y": 2000})
	var origins := BattleView.layout(squads)
	for i in origins.size():
		for j in range(i + 1, origins.size()):
			var a := Rect2i(origins[i], BattleView.badge_size(squads[i]))
			var b := Rect2i(origins[j], BattleView.badge_size(squads[j]))
			assert_true(not a.intersects(b), "odznaki %d i %d nie nachodzą na siebie" % [i, j])
	assert_eq(origins, BattleView.layout(squads), "układ odznak stały")
	return true


func test_hp_bar_shows_squad_health() -> bool:
	assert_eq(BattleView.hp_fill({"hp": 600, "max_hp": 600}), BattleView.BADGE, "pełne zdrowie: pełny pasek")
	assert_eq(BattleView.hp_fill({"hp": 1, "max_hp": 600}), 1, "żywy oddział ma co najmniej 1 px")
	return true
