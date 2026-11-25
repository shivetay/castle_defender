extends TestCase
## Poziomy doktryn ataku w bitwie: A1 Hartowane topory i A2 Łuk kompozytowy dostają +5 punktów
## procentowych za każdy poziom ponad pierwszy (Battle.doctrine_percent). Poziom atakującego przychodzi
## z serwera w `techs` jako „A1:3” (AttackLaunch.parse_techs / research_of), obrońcy z kopii zamku.

const K := BuildingTypes.Kind
const U := UnitTypes.Unit
const SIDE := Battle.Side


func _research(levels: Dictionary) -> Research:
	var r := Research.new()
	for code: String in levels:
		r.done[code] = true
		if int(levels[code]) > 1:
			r.levels[code] = int(levels[code])
	return r


func _battle(attackers: Array, defenders: Array) -> Battle:
	var bot := BotCastle.generate(BotCastle.seed_for(1337, 0), 0)
	return Battle.create_squads(bot.grid, bot.objective, attackers, defenders, bot.spawn, 7)


func _first(b: Battle, side: int, unit: int) -> Battle.Fighter:
	for f in b.fighters:
		if f.side == side and f.unit == unit:
			return f
	return null


func test_levels_in_battle() -> bool:
	var b := _battle([[U.ARCHER, 1], [U.REFLEX_ARCHER, 1]], [[U.ARCHER, 1]])
	b.apply_research(SIDE.ATTACKER, _research({"A1": 3, "A2": 3}))
	assert_eq(b.tech_level(SIDE.ATTACKER, "A1"), 3, "poziom A1 w bitwie")
	assert_eq(b.doctrine_percent(SIDE.ATTACKER, "A1", BattleConfig.A1_WOOD_PERCENT), 125, "A1 poziom 3: +25% w drewno")
	assert_eq(b.doctrine_percent(SIDE.ATTACKER, "A2", BattleConfig.A2_RANGE_PERCENT), 130, "A2 poziom 3: +30% zasięgu")
	assert_eq(b.doctrine_percent(SIDE.DEFENDER, "A2", BattleConfig.A2_RANGE_PERCENT), BattleConfig.A2_RANGE_PERCENT,
			"bez badań obrońcy: wzór nie odejmuje poniżej bazy")
	# zasięg w całych kratkach w dół: łucznik 6 → 7 (poziomy 1–3), łuk refleksyjny 7 → 9 na poziomie 3
	assert_eq(b.range_of(_first(b, SIDE.ATTACKER, U.ARCHER)), 7, "łucznik z A2 poziom 3")
	assert_eq(b.range_of(_first(b, SIDE.ATTACKER, U.REFLEX_ARCHER)), 9, "łuk refleksyjny z A2 poziom 3")
	b.apply_research(SIDE.ATTACKER, _research({"A2": 1}))
	assert_eq(b.range_of(_first(b, SIDE.ATTACKER, U.REFLEX_ARCHER)), 8, "poziom 1 bez zmian: 8")
	b.apply_research(SIDE.DEFENDER, _research({"A2": 5}))
	assert_eq(b.range_of(_first(b, SIDE.DEFENDER, U.ARCHER)), 8, "obrońca z A2 poziom 5: 6 × 140% = 8")
	return true


func test_a1_level_raises_wood_damage() -> bool:
	var hits: Array[int] = []
	for lv: int in [1, 3]:
		var b := _battle([[U.AXE_WARRIOR, 1]], [])
		var axe := _first(b, SIDE.ATTACKER, U.AXE_WARRIOR)
		var palisade: Battle.Structure = null
		for id: int in b.structures:
			if b.structures[id].kind == K.PALISADE and palisade == null:
				palisade = b.structures[id]
		b.apply_research(SIDE.ATTACKER, _research({"A1": lv}))
		var total := 0
		for i in 200:
			palisade.hp = palisade.max_hp
			axe.cooldown = 0
			axe.charged = true
			b._strike_structure(axe, palisade)
			total += palisade.max_hp - palisade.hp
		hits.append(total)
	# 125 / 115: około +8,7% (rozrzut ±10% z BattleRng, ta sama sekwencja losowań w obu bitwach)
	assert_true(hits[1] * 100 >= hits[0] * 104 and hits[1] * 100 <= hits[0] * 113, "A1 poziom 3 mocniej niż poziom 1")
	return true


func test_server_tokens() -> bool:
	var techs := AttackLaunch.parse_techs(["A1", "A2", "A1:3", "A2:2", "A1:3", "A1:9", "A1:1", "G1:2", "A7:2", "A1:x", 4])
	assert_eq(techs, ["A1", "A2", "A1:3", "A2:2"] as Array[String], "tylko poprawne poziomy A1/A2, bez powtórek")
	var r := AttackLaunch.research_of(techs)
	assert_eq(r.level("A1"), 3, "A1 poziom 3")
	assert_eq(r.level("A2"), 2, "A2 poziom 2")
	assert_eq(AttackLaunch.research_of(["A1:3"] as Array[String]).level("A1"), 0, "poziom bez zbadanej A1 nic nie daje")
	assert_eq(AttackLaunch.parse_techs(["A1", "A7"]), ["A1", "A7"] as Array[String], "stary kształt bez poziomów")
	return true


func test_battle_is_deterministic_with_levels() -> bool:
	var runs: Array = []
	for i in 2:
		var b := _battle([[U.AXE_WARRIOR, 3], [U.ARCHER, 2]], [[U.ARCHER, 2]])
		b.apply_research(SIDE.ATTACKER, _research({"A1": 3, "A2": 2}))
		b.apply_research(SIDE.DEFENDER, _research({"A2": 3}))
		b.run(600)
		runs.append([b.tick, b.winner, b.fighters.size()])
	assert_eq(runs[0], runs[1], "ten sam seed i poziomy: ten sam przebieg")
	return true


func test_panel_shows_battle_bonus() -> bool:
	var r := _research({"A1": 2})
	assert_eq(ResearchPanel.level_text(r, "A1", 0), "Premia +20%, następny poziom +25%", "A1: +15% na poziomie 1, +5 za poziom")
	assert_eq(ResearchPanel.doctrine_base("A2"), 20, "A2: +20% zasięgu")
	return true
