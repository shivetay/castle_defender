extends TestCase
## Morale (#98): 0–100 na oddział, liczone w liczbach całkowitych. Poniżej 30 oddział sam się
## wycofuje, powyżej 80 dostaje +10% obrażeń, poległy zabiera morale swojemu oddziałowi.

const K := BuildingTypes.Kind
const U := UnitTypes.Unit
const W := Battle.Winner
const E := Battle.EndReason
const SIDE := Battle.Side
const SPAWN := Vector2i(32, 60)


func _battle(attackers: Array, defenders: Array = [], seed_value: int = 1) -> Battle:
	var grid := BuildGrid.new(TerrainMap.generate(1337))
	var objective := grid.place(grid.manor_spot(64), K.MANOR, 3)
	return Battle.create_squads(grid, objective, attackers, defenders, SPAWN, seed_value)


func _first(b: Battle, side: int) -> Battle.Fighter:
	for f in b.fighters:
		if f.side == side:
			return f
	return null


func test_squads_start_with_the_same_morale() -> bool:
	var b := _battle([[U.AXE_WARRIOR, 3], [U.ARCHER, 2]], [[U.SHIELDBEARER, 2]])
	assert_eq(b.squad_morale(SIDE.ATTACKER, 1), BattleConfig.MORALE_START, "oddział 1")
	assert_eq(b.squad_morale(SIDE.ATTACKER, 2), BattleConfig.MORALE_START, "oddział 2")
	assert_eq(b.squad_morale(SIDE.DEFENDER, 1), BattleConfig.MORALE_START, "załoga")
	return true


## Kryterium #98: oddział przy morale 29 wycofuje się, przy 30 jeszcze walczy.
func test_squad_at_29_retreats() -> bool:
	var b := _battle([[U.AXE_WARRIOR, 2]])
	var f := _first(b, SIDE.ATTACKER)
	b.morale[Battle._squad_key(SIDE.ATTACKER, 1)] = 30
	assert_true(not b.routed(f), "przy 30 walczy")
	b.morale[Battle._squad_key(SIDE.ATTACKER, 1)] = 29
	assert_true(b.routed(f), "przy 29 się wycofuje")
	# wycofany wraca na swoją kratkę startową i nie idzie na cel
	f.x += 4 * BattleConfig.SUB
	var start_x := f.x
	for i in BattleConfig.TICK_HZ * 3:
		b._act(f)
	assert_true(f.x < start_x, "idzie z powrotem do kratki startowej")
	assert_eq(f.target, 0, "nie wybiera wroga")
	return true


func test_routed_army_loses_the_battle() -> bool:
	var b := _battle([[U.AXE_WARRIOR, 4]])
	b.add_side_morale(SIDE.ATTACKER, -50)
	assert_eq(b.run(), W.DEFENDER, "wycofana armia przegrywa")
	assert_eq(b.end_reason, E.ATTACKERS_ROUTED, "przez wycofanie")
	assert_eq(b.alive_count(SIDE.ATTACKER), 4, "nikt nie zginął")
	return true


func test_losses_lower_squad_morale() -> bool:
	var b := _battle([[U.AXE_WARRIOR, 3], [U.ARCHER, 2]])
	var f := _first(b, SIDE.ATTACKER)
	var loss := BattleConfig.MORALE_SQUAD_LOSS / 3
	assert_eq(b.loss_morale(SIDE.ATTACKER, 1), loss, "strata rozłożona na 3 ludzi")
	b._hurt(f, 10000)
	assert_eq(b.squad_morale(SIDE.ATTACKER, 1), BattleConfig.MORALE_START - loss, "strata za poległego")
	assert_eq(b.squad_morale(SIDE.ATTACKER, 2), BattleConfig.MORALE_START, "inny oddział bez zmian")
	b._hurt(f, 10000)
	assert_eq(b.squad_morale(SIDE.ATTACKER, 1), BattleConfig.MORALE_START - loss,
			"martwy nie traci morale drugi raz")
	return true


## Oddział łamie się po stracie ponad połowy ludzi, niezależnie od liczebności.
func test_squad_breaks_after_losing_more_than_half() -> bool:
	for size: int in [2, 4, 6, 10]:
		var b := _battle([[U.AXE_WARRIOR, size]])
		var lost := 0
		for f in b.fighters:
			if b.routed(f):
				break
			b._hurt(f, 10000)
			lost += 1
		var any_alive := b.alive_count(SIDE.ATTACKER) > 0
		assert_true(lost * 2 > size, "oddział %d: walczy do połowy strat (padło %d)" % [size, lost])
		assert_true(not any_alive or b.routed(b.fighters[size - 1]), "oddział %d w końcu się łamie" % size)
	return true


func test_morale_stays_in_range() -> bool:
	var b := _battle([[U.AXE_WARRIOR, 1]])
	b.add_side_morale(SIDE.ATTACKER, 500)
	assert_eq(b.squad_morale(SIDE.ATTACKER, 1), BattleConfig.MORALE_MAX, "najwyżej 100")
	b.add_squad_morale(SIDE.ATTACKER, 1, -500)
	assert_eq(b.squad_morale(SIDE.ATTACKER, 1), 0, "najmniej 0")
	return true


func test_high_morale_adds_ten_percent_damage() -> bool:
	var b := _battle([[U.AXE_WARRIOR, 1]], [[U.AXE_WARRIOR, 1]])
	var a := _first(b, SIDE.ATTACKER)
	var d := _first(b, SIDE.DEFENDER)
	var base := UnitTypes.damage(U.AXE_WARRIOR, U.AXE_WARRIOR)
	b.morale[Battle._squad_key(SIDE.ATTACKER, 1)] = 80
	assert_eq(b.unit_damage(a, d), base, "przy 80 bez premii")
	b.morale[Battle._squad_key(SIDE.ATTACKER, 1)] = 81
	assert_eq(b.unit_damage(a, d), base * 110 / 100, "powyżej 80: +10%")
	return true


func test_general_death_constant_matches_note() -> bool:
	var b := _battle([[U.AXE_WARRIOR, 1]])
	b.add_squad_morale(SIDE.ATTACKER, 1, BattleConfig.MORALE_GENERAL_DEATH)
	assert_eq(b.squad_morale(SIDE.ATTACKER, 1), BattleConfig.MORALE_START - 20, "śmierć generała: −20")
	return true


func test_u1_gives_defenders_five_morale() -> bool:
	var r := Research.new()
	assert_eq(BattleConfig.defender_morale_bonus(r), 0, "bez U1")
	r.done["U1"] = true
	assert_eq(BattleConfig.defender_morale_bonus(r), 5, "Wiec grodowy: +5")
	return true


## Kryterium #98: morale działa deterministycznie.
func test_morale_battle_is_deterministic() -> bool:
	var att := [[U.AXE_WARRIOR, 8], [U.ARCHER, 4]]
	var dfn := [[U.SHIELDBEARER, 4], [U.ARCHER, 3]]
	var first := _battle(att, dfn, 42)
	first.run()
	var routed_any := false
	for key: int in first.morale:
		if int(first.morale[key]) < BattleConfig.MORALE_ROUT:
			routed_any = true
	for i in 10:
		var b := _battle(att, dfn, 42)
		b.run()
		if b.checksum() != first.checksum() or b.morale != first.morale:
			assert_true(false, "przebieg %d różni się" % (i + 2))
			break
	assert_true(routed_any, "w tej bitwie któryś oddział się łamie (morale naprawdę działa)")
	return true


func test_view_shows_morale_bar() -> bool:
	assert_eq(BattleView.morale_fill({"morale": 100}), BattleView.BADGE, "pełne morale: pełny pasek")
	assert_eq(BattleView.morale_fill({"morale": 0}), 0, "zero")
	assert_true(BattleView.morale_color({"morale": 29}) == Palette.ACCENT, "poniżej progu w kolorze akcentu")
	return true
