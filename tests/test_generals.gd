extends TestCase
## Generałowie (#31): rekrutacja za złoto w Dworze, poziomy 1–3 z doświadczenia i złota, perk
## dodatkowy na poziomie 3, zapis oraz generał w bitwie (aura, perki, śmierć) z determinizmem.

const K := BuildingTypes.Kind
const U := UnitTypes.Unit
const G := Generals.Kind
const P := Generals.Perk
const RES := Generals.Result
const SIDE := Battle.Side
const SPAWN := Vector2i(32, 60)


func _rich() -> Economy:
	var e := Economy.new(0)
	e.amounts[EconomyConfig.Res.GOLD] = 100000
	return e


func _general(kind: int, level: int = 1, perk: int = P.NONE) -> Generals.General:
	var g := Generals.General.new()
	g.kind = kind
	g.level = level
	g.perk = perk
	return g


func _grid() -> BuildGrid:
	return BuildGrid.new(TerrainMap.generate(1337))


## Pole bitwy bez umocnień: cel to Dwór, armie w polu.
func _battle(attackers: Array, defenders: Array = [], seed_value: int = 1) -> Battle:
	var grid := _grid()
	var objective := grid.place(grid.manor_spot(64), K.MANOR, 3)
	return Battle.create_squads(grid, objective, attackers, defenders, SPAWN, seed_value)


func _first(b: Battle, side: int, squad: int = 1) -> Battle.Fighter:
	for f in b.fighters:
		if f.side == side and f.squad == squad and f.general < 0:
			return f
	return null


func test_recruit_costs_gold_and_kinds_are_unique() -> bool:
	var gs := Generals.new()
	var e := Economy.new(0)
	e.amounts[EconomyConfig.Res.GOLD] = Generals.RECRUIT_GOLD - 1
	assert_eq(gs.recruit(G.CHIEF, 0, e), RES.NO_GOLD, "bez złota")
	assert_eq(gs.recruit(G.CHIEF, 0, e, false), RES.NO_MANOR, "bez Dworu")
	e.amounts[EconomyConfig.Res.GOLD] = Generals.RECRUIT_GOLD * 4
	assert_eq(gs.recruit(G.CHIEF, 0, e), RES.OK, "rekrutacja")
	assert_eq(e.amounts[EconomyConfig.Res.GOLD], Generals.RECRUIT_GOLD * 3, "złoto zeszło")
	assert_eq(gs.recruit(G.CHIEF, 0, e), RES.TAKEN, "ten sam generał drugi raz")
	assert_eq(gs.get_general(G.CHIEF).level, 1, "zaczyna od poziomu 1")
	assert_eq(gs.recruitable(0), [G.HUNTSMAN, G.MOUND_BUILDER] as Array[int], "do wzięcia w epoce I")
	assert_eq(gs.recruit(G.HUNTSMAN, 0, e), RES.OK, "drugi")
	assert_eq(gs.recruit(G.MOUND_BUILDER, 0, e), RES.OK, "Budowniczy kopców od epoki I (decyzja właścicielki)")
	assert_eq(gs.roster.size(), Generals.MAX, "najwyżej 3")
	assert_eq(gs.recruit(-1, 0, e), RES.UNKNOWN, "nieznany")
	return true


func test_promote_needs_xp_and_gold_up_to_level_3() -> bool:
	var gs := Generals.new()
	var e := _rich()
	gs.recruit(G.CHIEF, 0, e)
	assert_eq(gs.promote(G.CHIEF, e), RES.NO_XP, "bez doświadczenia")
	assert_eq(gs.add_battle_xp(G.CHIEF, true), Generals.XP_BATTLE + Generals.XP_WIN, "wygrana")
	assert_eq(gs.add_battle_xp(G.CHIEF, false), Generals.XP_BATTLE, "przegrana")
	assert_eq(gs.add_battle_xp(G.HUNTSMAN, true), 0, "generała, którego nie ma, nic nie dostaje")
	gs.get_general(G.CHIEF).xp = Generals.LEVEL_XP[2]
	var gold := e.amounts[EconomyConfig.Res.GOLD]
	assert_eq(gs.promote(G.CHIEF, e), RES.OK, "awans na 2")
	assert_eq(e.amounts[EconomyConfig.Res.GOLD], gold - Generals.LEVEL_GOLD[2], "za złoto")
	assert_eq(gs.choose_perk(G.CHIEF, P.VETERAN, 0), RES.NO_PERK_YET, "perk dopiero na poziomie 3")
	assert_eq(gs.promote(G.CHIEF, e), RES.NO_XP, "na 3 trzeba więcej doświadczenia")
	gs.get_general(G.CHIEF).xp = Generals.LEVEL_XP[3]
	var poor := Economy.new(0)
	assert_eq(gs.promote(G.CHIEF, poor), RES.NO_GOLD, "bez złota nie awansuje")
	assert_eq(gs.promote(G.CHIEF, e), RES.OK, "awans na 3")
	assert_eq(gs.promote(G.CHIEF, e), RES.MAX_LEVEL, "MVP kończy się na 3")
	assert_eq(gs.choose_perk(G.CHIEF, P.CRUEL, 0), RES.PERK_LOCKED, "Okrutny od epoki II")
	assert_eq(gs.choose_perk(G.CHIEF, P.VETERAN, 0), RES.OK, "Weteran")
	assert_eq(gs.choose_perk(G.CHIEF, P.TOUGH, 0), RES.PERK_SET, "perk dodatkowy tylko jeden")
	assert_eq(Generals.perks_for(0).size(), 3, "w epoce I trzy perki")
	assert_eq(Generals.perks_for(1).size(), 5, "w epoce II pięć")
	for i in 30:
		gs.add_battle_xp(G.CHIEF, true)
	assert_eq(gs.get_general(G.CHIEF).xp, Generals.XP_MAX, "doświadczenie ma górną granicę")
	return true


func test_attack_general_is_not_the_commander() -> bool:
	var gs := Generals.new()
	var e := _rich()
	gs.recruit(G.CHIEF, 0, e)
	gs.recruit(G.MOUND_BUILDER, 0, e)
	assert_eq(gs.set_attack(G.CHIEF, G.CHIEF), -1, "komendant obrony nie dowodzi atakiem")
	assert_eq(gs.set_attack(G.HUNTSMAN), -1, "generała, którego nie ma, nie da się wybrać")
	assert_eq(gs.next_attack(G.MOUND_BUILDER), G.CHIEF, "brak → Wódz")
	assert_eq(gs.next_attack(G.MOUND_BUILDER), -1, "Wódz → brak (Budowniczy jest komendantem)")
	assert_eq(gs.next_attack(), G.CHIEF, "bez komendanta: Wódz")
	assert_eq(gs.next_attack(), G.MOUND_BUILDER, "potem Budowniczy")
	assert_true(gs.attack_general() != gs.get_general(G.MOUND_BUILDER), "do bitwy idzie kopia")
	return true


func test_save_round_trip_and_bad_entries() -> bool:
	var gs := Generals.new()
	var e := _rich()
	gs.recruit(G.HUNTSMAN, 0, e)
	gs.get_general(G.HUNTSMAN).level = 3
	gs.get_general(G.HUNTSMAN).xp = 250
	gs.choose_perk(G.HUNTSMAN, P.TOUGH, 0)
	gs.set_attack(G.HUNTSMAN)
	var back := Generals.new()
	assert_eq(back.load_data(JSON.parse_string(JSON.stringify(gs.save_data())) as Dictionary), 0, "nic nie pominięto")
	assert_eq(back.save_data(), gs.save_data(), "ten sam stan po JSON")
	assert_eq(back.attack_kind, G.HUNTSMAN, "generał ataku")
	var raw := {"roster": [{"kind": 0, "level": 9, "xp": 99999, "perk": 3}, {"kind": 0}, {"kind": 7}, "x",
			{"kind": 2, "level": 2, "perk": 1}], "attack": 1}
	assert_eq(back.load_data(raw), 3, "powtórzony, nieznany i zły wpis pominięte")
	assert_eq(back.get_general(G.CHIEF).level, Generals.MAX_LEVEL, "poziom przycięty do MVP")
	assert_eq(back.get_general(G.CHIEF).xp, Generals.XP_MAX, "doświadczenie przycięte")
	assert_eq(back.get_general(G.MOUND_BUILDER).perk, P.NONE, "perk poniżej poziomu 3 nie wchodzi")
	assert_eq(back.attack_kind, -1, "generał ataku, którego nie ma, przepada")
	return true


func test_save_game_keeps_generals() -> bool:
	var grid := _grid()
	grid.place(grid.manor_spot(64), K.MANOR, 1)
	var e := _rich()
	var gs := Generals.new()
	gs.recruit(G.CHIEF, 0, e)
	gs.recruit(G.HUNTSMAN, 0, e)
	gs.set_attack(G.HUNTSMAN)
	var defense := DefensePlan.new()
	defense.commander = G.CHIEF
	defense.commander_squad = 5
	var d := SaveGame.to_dict(1337, grid, e, BuildQueue.new(), null, null, null, 0, null, 0, defense, 0, null, null, gs)
	var s := SaveGame.from_dict(JSON.parse_string(JSON.stringify(d)) as Dictionary, 0)
	assert_eq(s.generals.save_data(), gs.save_data(), "generałowie z zapisu")
	assert_eq(s.defense.commander, G.CHIEF, "komendant obrony")
	assert_eq(s.defense.commander_squad, 0, "oddziału, którego nie ma w armii, komendant wraca pod donżon")
	var old := d.duplicate(true)
	old["version"] = 10
	old.erase("generals")
	var s10 := SaveGame.from_dict(old, 0)
	assert_true(s10 != null and s10.generals.roster.is_empty(), "zapis sprzed generałów")
	return true


## Kryterium akceptacji #31: generał przypisany do ataku zmienia wynik symulacji.
func test_attack_general_changes_the_battle() -> bool:
	var army := [[U.AXE_WARRIOR, 6], [U.SPEARMAN, 4]]
	var crew := [[U.AXE_WARRIOR, 6], [U.SHIELDBEARER, 4]]
	var plain := _battle(army, crew, 5)
	var led := _battle(army, crew, 5)
	led.set_general(SIDE.ATTACKER, _general(G.CHIEF))
	plain.run()
	led.run()
	assert_true(plain.checksum() != led.checksum(), "inny przebieg z generałem")
	var again := _battle(army, crew, 5)
	again.set_general(SIDE.ATTACKER, _general(G.CHIEF))
	again.run()
	assert_eq(again.checksum(), led.checksum(), "ten sam seed i generał: ten sam przebieg")
	assert_eq(led.survivors(SIDE.ATTACKER).size(), 2, "generał nie jest oddziałem w ocalałych")
	return true


## Kryterium akceptacji #31: komendant obrony zmienia wynik symulacji.
func test_defense_commander_changes_the_battle() -> bool:
	var army := [[U.AXE_WARRIOR, 8]]
	var crew := [[U.AXE_WARRIOR, 6]]
	var plain := _battle(army, crew, 9)
	var led := _battle(army, crew, 9)
	led.set_general(SIDE.DEFENDER, _general(G.CHIEF))
	plain.run()
	led.run()
	assert_true(plain.checksum() != led.checksum(), "inny przebieg z komendantem")
	assert_true(led.general_fighter(SIDE.DEFENDER) != null, "komendant stoi na siatce")
	return true


func test_chief_aura_damage_and_morale() -> bool:
	var b := _battle([[U.AXE_WARRIOR, 2], [U.ARCHER, 2]], [[U.AXE_WARRIOR, 1]])
	var axe := _first(b, SIDE.ATTACKER, 1)
	var archer := _first(b, SIDE.ATTACKER, 2)
	var enemy := _first(b, SIDE.DEFENDER)
	var before := b.unit_damage(axe, enemy)
	var archer_before := b.unit_damage(archer, enemy)
	b.set_general(SIDE.ATTACKER, _general(G.CHIEF))
	var gf := b.general_fighter(SIDE.ATTACKER)
	assert_eq(gf.hp, Generals.GENERAL_HP, "HP 150")
	gf.x = axe.x
	gf.y = axe.y
	assert_true(b.in_aura(axe, G.CHIEF), "topornik w aurze")
	assert_eq(b.unit_damage(axe, enemy), before * Generals.CHIEF_DAMAGE_PERCENT / 100, "piechota +10%")
	assert_eq(b.unit_damage(archer, enemy), archer_before, "strzelcy bez premii Wodza")
	gf.x += (Generals.AURA_CELLS + 1) * BattleConfig.SUB
	assert_true(not b.in_aura(axe, G.CHIEF), "poza aurą")
	assert_eq(b.unit_damage(axe, enemy), before, "poza aurą bez premii")
	gf.x = axe.x
	b._chief_morale()
	b._chief_morale()
	assert_eq(b.squad_morale(SIDE.ATTACKER, 1), BattleConfig.MORALE_START + Generals.CHIEF_MORALE, "+10 morale raz")
	return true


func test_general_death_costs_morale_and_he_alone_does_not_fight_on() -> bool:
	var b := _battle([[U.AXE_WARRIOR, 2], [U.ARCHER, 2]])
	b.set_general(SIDE.ATTACKER, _general(G.HUNTSMAN))
	var gf := b.general_fighter(SIDE.ATTACKER)
	b._hurt(gf, gf.hp)
	assert_eq(b.squad_morale(SIDE.ATTACKER, 1), BattleConfig.MORALE_START + BattleConfig.MORALE_GENERAL_DEATH,
			"oddział 1: −20")
	assert_eq(b.squad_morale(SIDE.ATTACKER, 2), BattleConfig.MORALE_START + BattleConfig.MORALE_GENERAL_DEATH,
			"oddział 2: −20")
	assert_true(b.general_view(SIDE.ATTACKER).is_empty(), "poległy generał nie jest rysowany")
	var lone := _battle([[U.AXE_WARRIOR, 1]])
	lone.set_general(SIDE.ATTACKER, _general(G.CHIEF))
	lone._hurt(_first(lone, SIDE.ATTACKER), 9999)
	lone.step()
	assert_eq(lone.winner, Battle.Winner.DEFENDER, "sam generał nie przedłuża bitwy")
	return true


func test_extra_perks() -> bool:
	var tough := _general(G.CHIEF, 3, P.TOUGH)
	assert_eq(tough.max_hp(), Generals.GENERAL_HP * 2, "Twardy: +100% HP")
	assert_eq(_general(G.CHIEF, 3, P.VETERAN).aura_cells(), Generals.AURA_CELLS + 2, "Weteran: aura +2")
	assert_eq(_general(G.CHIEF, 2, P.VETERAN).aura_cells(), Generals.AURA_CELLS, "perk działa od poziomu 3")
	# Szybki marsz: +1 szybkości w aurze
	var b := _battle([[U.AXE_WARRIOR, 1]], [[U.ARCHER, 1]])
	var axe := _first(b, SIDE.ATTACKER)
	var slow := b.step_of(axe)
	b.set_general(SIDE.ATTACKER, _general(G.CHIEF, 3, P.FAST_MARCH))
	b.general_fighter(SIDE.ATTACKER).x = axe.x
	b.general_fighter(SIDE.ATTACKER).y = axe.y
	assert_eq(b.step_of(axe), slow + Generals.FAST_MARCH_SPEED * BattleConfig.SPEED_SUB_PER_TICK, "Szybki marsz")
	# Ostrożny: −15% od strzał w aurze
	var c := _battle([[U.AXE_WARRIOR, 1]], [[U.ARCHER, 1]])
	var target := _first(c, SIDE.ATTACKER)
	var archer := _first(c, SIDE.DEFENDER)
	var arrow := c.unit_damage(archer, target)
	c.set_general(SIDE.ATTACKER, _general(G.HUNTSMAN, 3, P.CAREFUL))
	c.general_fighter(SIDE.ATTACKER).x = target.x
	c.general_fighter(SIDE.ATTACKER).y = target.y
	assert_eq(c.unit_damage(archer, target), arrow * Generals.CAREFUL_ARROW_PERCENT / 100, "Ostrożny")
	# Okrutny: −5 morale własnych oddziałów od startu
	var d := _battle([[U.AXE_WARRIOR, 1], [U.ARCHER, 1]])
	d.set_general(SIDE.ATTACKER, _general(G.CHIEF, 3, P.CRUEL))
	assert_eq(d.squad_morale(SIDE.ATTACKER, 2), BattleConfig.MORALE_START + Generals.CRUEL_MORALE, "Okrutny")
	return true


func test_huntsman_speeds_up_flanking() -> bool:
	var b := _battle([[U.AXE_WARRIOR, 2], [U.AXE_WARRIOR, 2]])
	var p := AttackPlan.new()
	p.add(1, AttackPlan.Manoeuvre.FLANK)
	b.set_plan(p)
	var flank := _first(b, SIDE.ATTACKER, 1)
	var front := _first(b, SIDE.ATTACKER, 2)
	var base := b.step_of(flank)
	b.set_general(SIDE.ATTACKER, _general(G.HUNTSMAN))
	assert_eq(b.step_of(flank), base * Generals.HUNTSMAN_FLANK_SPEED_PERCENT / 100, "Oskrzydlenie 20% szybciej")
	assert_eq(b.step_of(front), base, "inne manewry bez zmian")
	b._hurt(b.general_fighter(SIDE.ATTACKER), 9999)
	assert_eq(b.step_of(flank), base, "po śmierci Łowczego premia znika")
	return true


func test_mound_builder_strengthens_fortifications() -> bool:
	var grid := _grid()
	var keep := grid.place(grid.keep_spot(64), K.KEEP, 1)
	var ring := grid.buildings[keep].grow(2)
	var pal := grid.place(Rect2i(ring.position.x, ring.position.y, 1, 1), K.PALISADE, 1)
	var b := Battle.create_squads(grid, keep, [[U.AXE_WARRIOR, 1]], [], SPAWN, 1)
	var base := b.structures[pal].max_hp
	var research := Research.new()
	research.done["O2"] = true
	b.apply_research(SIDE.DEFENDER, research)
	var o2 := b.structures[pal].max_hp
	b.set_general(SIDE.DEFENDER, _general(G.MOUND_BUILDER))
	assert_eq(b.structures[pal].max_hp, o2 * Generals.MOUND_BUILDER_HP_PERCENT / 100, "O2, potem +15%")
	b.apply_research(SIDE.DEFENDER, research)
	assert_eq(b.structures[pal].max_hp, o2 * Generals.MOUND_BUILDER_HP_PERCENT / 100, "bez podwójnej premii")
	var a := Battle.create_squads(grid, keep, [[U.AXE_WARRIOR, 1]], [], SPAWN, 1)
	a.set_general(SIDE.ATTACKER, _general(G.MOUND_BUILDER))
	assert_eq(a.structures[pal].max_hp, base, "w ataku Budowniczy nie wzmacnia cudzych murów")
	return true


func test_defender_general_follows_chosen_squad() -> bool:
	var b := _battle([[U.AXE_WARRIOR, 1]], [[U.AXE_WARRIOR, 2], [U.ARCHER, 2]])
	b.set_general(SIDE.DEFENDER, _general(G.CHIEF), 2)
	var gf := b.general_fighter(SIDE.DEFENDER)
	assert_true(b._general_leader(gf) == _first(b, SIDE.DEFENDER, 2), "idzie przy oddziale 2")
	var keep_side := _battle([[U.AXE_WARRIOR, 1]], [[U.AXE_WARRIOR, 2]])
	keep_side.set_general(SIDE.DEFENDER, _general(G.CHIEF))
	assert_true(keep_side._general_leader(keep_side.general_fighter(SIDE.DEFENDER)) == null, "bez oddziału: przy donżonie")
	return true
