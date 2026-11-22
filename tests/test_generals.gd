extends TestCase
## Generałowie (#31): rekrutacja za złoto w Dworze, poziomy 1–3 z doświadczenia i złota, perk
## dodatkowy na poziomie 3, zapis oraz generał w bitwie (perki na całą stronę) z determinizmem.

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
		if f.side == side and f.squad == squad:
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
	assert_eq(gs.get_general(G.CHIEF).xp, 0, "Wyszkol zużywa PD")
	assert_eq(Generals.total_xp(gs.get_general(G.CHIEF)), Generals.LEVEL_XP[2], "zebrane PD liczą też zużyte")
	assert_eq(Generals.total_gold(gs.get_general(G.CHIEF)), Generals.RECRUIT_GOLD + Generals.LEVEL_GOLD[2],
			"złoto na generała: rekrutacja i awans")
	assert_eq(gs.choose_perk(G.CHIEF, P.FAST_MARCH, 0), RES.NO_PERK_YET, "perk dopiero na poziomie 3")
	assert_eq(gs.promote(G.CHIEF, e), RES.NO_XP, "na 3 trzeba więcej doświadczenia")
	gs.get_general(G.CHIEF).xp = Generals.LEVEL_XP[3]
	var poor := Economy.new(0)
	assert_eq(gs.promote(G.CHIEF, poor), RES.NO_GOLD, "bez złota nie awansuje")
	assert_eq(gs.promote(G.CHIEF, e), RES.OK, "awans na 3")
	assert_eq(gs.promote(G.CHIEF, e), RES.MAX_LEVEL, "MVP kończy się na 3")
	assert_eq(gs.choose_perk(G.CHIEF, P.CAREFUL, 0), RES.PERK_LOCKED, "Ostrożny od epoki II")
	assert_eq(gs.choose_perk(G.CHIEF, P.FAST_MARCH, 0), RES.OK, "Szybki marsz")
	assert_eq(gs.choose_perk(G.CHIEF, P.FAST_MARCH, 1), RES.PERK_SET, "perk dodatkowy tylko jeden")
	assert_eq(Generals.perks_for(0).size(), 1, "w epoce I jeden perk")
	assert_eq(Generals.perks_for(1).size(), 2, "w epoce II dwa")
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
	gs.choose_perk(G.HUNTSMAN, P.FAST_MARCH, 0)
	gs.set_attack(G.HUNTSMAN)
	var back := Generals.new()
	assert_eq(back.load_data(JSON.parse_string(JSON.stringify(gs.save_data())) as Dictionary), 0, "nic nie pominięto")
	assert_eq(back.save_data(), gs.save_data(), "ten sam stan po JSON")
	assert_eq(back.attack_kind, G.HUNTSMAN, "generał ataku")
	var raw := {"roster": [{"kind": 0, "level": 9, "xp": 99999, "perk": 1}, {"kind": 0}, {"kind": 7}, "x",
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
	var d := SaveGame.to_dict(1337, grid, e, BuildQueue.new(), null, null, null, 0, null, 0, defense, 0, null, null, gs)
	var s := SaveGame.from_dict(JSON.parse_string(JSON.stringify(d)) as Dictionary, 0)
	assert_eq(s.generals.save_data(), gs.save_data(), "generałowie z zapisu")
	assert_eq(s.defense.commander, G.CHIEF, "komendant obrony")
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
	var n := led.fighters.size()
	plain.run()
	led.run()
	assert_true(plain.checksum() != led.checksum(), "inny przebieg z generałem")
	assert_eq(n, plain.fighters.size(), "generał nie staje na siatce")
	var again := _battle(army, crew, 5)
	again.set_general(SIDE.ATTACKER, _general(G.CHIEF))
	again.run()
	assert_eq(again.checksum(), led.checksum(), "ten sam seed i generał: ten sam przebieg")
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
	return true


func test_chief_boosts_whole_side() -> bool:
	var b := _battle([[U.AXE_WARRIOR, 2], [U.ARCHER, 2]], [[U.AXE_WARRIOR, 1]])
	var axe := _first(b, SIDE.ATTACKER, 1)
	var archer := _first(b, SIDE.ATTACKER, 2)
	var enemy := _first(b, SIDE.DEFENDER)
	var before := b.unit_damage(axe, enemy)
	var archer_before := b.unit_damage(archer, enemy)
	b.set_general(SIDE.ATTACKER, _general(G.CHIEF))
	assert_eq(b.unit_damage(axe, enemy), before * Generals.CHIEF_DAMAGE_PERCENT / 100, "piechota +10%")
	assert_eq(b.unit_damage(archer, enemy), archer_before, "strzelcy bez premii Wodza")
	assert_eq(b.squad_morale(SIDE.ATTACKER, 1), BattleConfig.MORALE_START + Generals.CHIEF_MORALE, "oddział 1: +10 morale")
	assert_eq(b.squad_morale(SIDE.ATTACKER, 2), BattleConfig.MORALE_START + Generals.CHIEF_MORALE, "oddział 2: +10 morale")
	assert_eq(b.squad_morale(SIDE.DEFENDER, 1), BattleConfig.MORALE_START, "wróg bez premii")
	b.set_general(SIDE.ATTACKER, _general(G.CHIEF))
	assert_eq(b.squad_morale(SIDE.ATTACKER, 1), BattleConfig.MORALE_START + Generals.CHIEF_MORALE, "jeden generał na stronę")
	return true


func test_extra_perks() -> bool:
	assert_true(not _general(G.CHIEF, 2, P.FAST_MARCH).has_perk(P.FAST_MARCH), "perk działa od poziomu 3")
	# Szybki marsz: +1 szybkości całej armii
	var b := _battle([[U.AXE_WARRIOR, 1]], [[U.ARCHER, 1]])
	var axe := _first(b, SIDE.ATTACKER)
	var slow := b.step_of(axe)
	b.set_general(SIDE.ATTACKER, _general(G.CHIEF, 3, P.FAST_MARCH))
	assert_eq(b.step_of(axe), slow + Generals.FAST_MARCH_SPEED * BattleConfig.SPEED_SUB_PER_TICK, "Szybki marsz")
	assert_eq(b.step_of(_first(b, SIDE.DEFENDER)), UnitTypes.speed(U.ARCHER) * BattleConfig.SPEED_SUB_PER_TICK,
			"wróg bez premii")
	# Ostrożny: −15% od strzał dla całej armii
	var c := _battle([[U.AXE_WARRIOR, 1]], [[U.ARCHER, 1]])
	var target := _first(c, SIDE.ATTACKER)
	var archer := _first(c, SIDE.DEFENDER)
	var arrow := c.unit_damage(archer, target)
	var melee := c.unit_damage(target, archer)
	c.set_general(SIDE.ATTACKER, _general(G.HUNTSMAN, 3, P.CAREFUL))
	assert_eq(c.unit_damage(archer, target), arrow * Generals.CAREFUL_ARROW_PERCENT / 100, "Ostrożny")
	assert_eq(c.unit_damage(target, archer), melee, "w zwarciu bez zmian")
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


func test_commander_choice_skips_attack_general() -> bool:
	var gs := Generals.new()
	var e := _rich()
	var plan := DefensePlan.new()
	assert_eq(DefensePanel.next_commander(plan, gs), "Najpierw zwerbuj generała w Dworze", "bez generałów")
	gs.recruit(G.CHIEF, 0, e)
	gs.recruit(G.HUNTSMAN, 0, e)
	gs.set_attack(G.HUNTSMAN)
	assert_eq(DefensePanel.next_commander(plan, gs), "Komendant: Wódz drużyny, poz. 1", "Wódz")
	assert_eq(DefensePanel.next_commander(plan, gs), "Komendant: brak", "Łowczy dowodzi atakiem, więc znów brak")
	assert_eq(DefensePanel.commander_label(plan, gs), DefensePanel.COMMANDER_LABEL, "przycisk bez komendanta")
	var view := Vector2(320, 180)
	var b := Hud.content_bounds(view, Rect2())
	assert_eq(DefensePanel.target_at(AttackPanel.general_rect(b.x).get_center(), view, b.x, b.y, 3, 0),
			DefensePanel.Target.COMMANDER, "przycisk komendanta w lewym górnym rogu")
	assert_eq(AttackPanel.target_at(AttackPanel.general_rect(b.x).get_center(), view, b.x, b.y, 3),
			AttackPanel.Target.GENERAL, "przycisk generała ataku")
	for label: String in [DefensePanel.COMMANDER_LABEL, AttackPanel.GENERAL_LABEL] + Generals.SHORT_NAMES:
		assert_true(PixelFont.text_width(label) <= Hud.BUTTON_SIZE.x - 2, "„%s” mieści się na przycisku" % label)
	return true


const REPLAY := preload("res://tests/test_replay.gd")


## Kopia zamku obrońcy z generałami (Wódz drużyny, poziom 2) i obrona z Wodzem jako komendantem.
static func _defender_castle() -> Dictionary:
	var castle := REPLAY._castle(REPLAY._map_seed())
	castle["generals"] = {"roster": [{"kind": G.CHIEF, "level": 2, "xp": 120, "perk": -1}], "attack": -1}
	return castle


## Bitwa atakującego na graczu i powtórka obrońcy z tych samych danych z serwera, z generałami obu stron.
func _pvp(general: Variant, defense: Dictionary) -> Array:
	var plan := REPLAY._plan(REPLAY._keep_cell())
	var castle := _defender_castle()
	var footprint: Array = []
	var keep: Array = []
	for e: Variant in (castle["grid"] as Dictionary)["buildings"] as Array:
		var a := e as Array
		footprint.append([a[3], a[4], a[5], a[6]])
		if int(a[1]) == K.KEEP:
			keep = [a[3], a[4], a[5], a[6]]
	var start := AttackStart.parse_response({"id": REPLAY.ATTACK, "map_seed": REPLAY._map_seed(), "battle_seed": 4141,
			"defender_id": REPLAY.DEFENDER, "footprint": footprint, "keep": keep, "intel": {}})
	var pc := PlayerCastle.from_start(start, REPLAY.ARMY, 0, 1)
	var launch := AttackLaunch.parse_response(REPLAY._wire({"id": REPLAY.ATTACK, "castle": castle, "defense": defense,
			"plan": plan.to_server(), "techs": ["A1"], "general": general}))
	assert_true(pc.apply_launch(launch), "kopia z launch_attack")
	var live := pc.create_battle()
	var trace := REPLAY._trace(live)
	var result := pc.result_of(live)
	var replay := BattleReplay.from_response(AttackReplay.parse_response(REPLAY._wire({"id": REPLAY.ATTACK,
			"map_seed": REPLAY._map_seed(), "battle_seed": 4141, "castle": castle, "defense": defense, "army": REPLAY.ARMY,
			"plan": plan.to_server(), "techs": ["A1"], "general": general, "result": result.to_server(),
			"loot": [0, 0, 0, 0], "finished_at": "2026-11-21T10:15:00+00:00"})))
	assert_true(replay != null, "powtórka z odpowiedzi")
	return [live, trace, replay.create_battle()]


## Kryterium #31 w PvP: generał ataku z serwera i komendant z kopii obrony wchodzą do bitwy u atakującego
## i w powtórce u obrońcy, a powtórka idzie krok po kroku tak samo.
func test_pvp_generals_match_in_replay() -> bool:
	var defense := {"orders": [], "tower_priority": 0, "traps": [], "commander": G.CHIEF}
	var general := {"kind": G.HUNTSMAN, "level": 3, "perk": P.FAST_MARCH}
	var led := _pvp(general, defense)
	var live: Battle = led[0]
	assert_eq(live.generals[SIDE.ATTACKER].kind, G.HUNTSMAN, "generał ataku z serwera")
	assert_true(live.general_perk(SIDE.ATTACKER, P.FAST_MARCH), "z perkiem z serwera")
	assert_eq(live.generals[SIDE.DEFENDER].level, 2, "komendant z kopii zamku obrońcy")
	assert_eq(REPLAY._trace(led[2]), led[1], "powtórka z generałami: ten sam przebieg")
	var plain := _pvp(null, {})
	assert_true(plain[1] != led[1], "bez generałów inny przebieg")
	assert_true((plain[0] as Battle).generals.is_empty(), "bez generałów nikogo nie ma")
	return true


func test_launch_request_has_general_only_when_chosen() -> bool:
	var plan := AttackPlan.new()
	plan.add(1, AttackPlan.Manoeuvre.FRONTAL)
	assert_true(not AttackLaunch.request("x", plan).has("general"), "bez generała bez klucza (stary serwer)")
	assert_eq(AttackLaunch.request("x", plan, G.HUNTSMAN)["general"], G.HUNTSMAN, "rodzaj generała")
	assert_true(not AttackLaunch.request("x", plan, 9).has("general"), "nieznany rodzaj nie idzie")
	assert_true(Generals.general_from({"kind": 1.0, "level": 2.5}) != null, "liczby z JSON")
	assert_eq(Generals.general_from({"kind": 1.0, "level": 2.5}).level, 1, "ułamek poziomu: poziom 1 jak na serwerze")
	assert_eq(Generals.general_from(null), null, "null: bez generała")
	return true


## Serwer (`private.checked_generals`, migracja *_general_budget.sql) liczy pokrycie generałów z tymi samymi
## liczbami co gra: koszty, PD za bitwę, złoto startowe i nagrody fal PvE.
func test_server_budget_constants_match_game() -> bool:
	var sql := FileAccess.get_file_as_string("res://supabase/migrations/20261122100000_general_budget.sql")
	assert_true(not sql.is_empty(), "migracja jest")
	var pve_gold := 0
	for w in PveWaves.COUNT:
		pve_gold += PveWaves.reward(w)[EconomyConfig.Res.GOLD]
	assert_true(sql.contains("v_gold + %d + %d" % [EconomyConfig.START[EconomyConfig.Res.GOLD], pve_gold]),
			"złoto startowe i nagrody fal")
	assert_true(sql.contains("(v_battles + %d) * %d" % [PveWaves.COUNT, Generals.XP_BATTLE + Generals.XP_WIN]),
			"PD za bitwę i fale")
	assert_true(sql.contains("v_spent + %d > v_gold" % Generals.RECRUIT_GOLD), "rekrutacja")
	assert_true(sql.contains("v_cost + %d > v_gold" % Generals.LEVEL_GOLD[2]), "awans na 2")
	assert_true(sql.contains("v_cost + %d > v_gold" % Generals.LEVEL_GOLD[3]), "awans na 3")
	assert_true(sql.contains("then %d else 0 end + case when v_level >= 3 then %d" % [Generals.LEVEL_XP[2],
			Generals.LEVEL_XP[3]]), "PD na awanse")
	assert_true(sql.contains("private.json_int(e -> 'xp', 0, %d)" % Generals.XP_MAX), "górna granica PD")
	assert_true(sql.contains("private.json_int(e -> 'perk', 0, %d)" % (Generals.PERK_NAMES.size() - 1)), "perki")
	return true
