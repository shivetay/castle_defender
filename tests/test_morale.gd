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


## Premia działa też przy słabych atakach: z obcinaniem 5 * 110 / 100 dawało znowu 5 (review #155).
func test_high_morale_bonus_works_for_weak_attacks() -> bool:
	var b := _battle([[U.SHIELDBEARER, 1]], [[U.TRACKER, 1]])
	var a := _first(b, SIDE.ATTACKER)
	b.morale[Battle._squad_key(SIDE.ATTACKER, 1)] = 90
	for dmg: int in [1, 4, 5, 7, 9]:
		assert_true(b.morale_damage(a, dmg) > dmg, "premia przy obrażeniach %d" % dmg)
	assert_eq(b.morale_damage(a, 20), 22, "+10% przy 20")
	assert_eq(b.morale_damage(a, 0), 0, "bez ataku bez premii")
	return true


## Wycofany oddział omija żywe mury (review #155): jednostka w pierścieniu palisady z jedną luką,
## z kratką startową po drugiej stronie, wychodzi przez lukę, a nie staje pod murem.
func test_retreat_goes_around_live_walls() -> bool:
	var grid := BuildGrid.new(TerrainMap.generate(1337))
	var objective := grid.place(grid.manor_spot(64), K.MANOR, 3)
	var r := grid.buildings[objective].grow(3)
	var gap := Vector2i(r.end.x - 1, r.position.y + r.size.y / 2)  # luka w prawym boku
	for x in range(r.position.x, r.end.x):
		for y in range(r.position.y, r.end.y):
			var c := Vector2i(x, y)
			var edge := x == r.position.x or x == r.end.x - 1 or y == r.position.y or y == r.end.y - 1
			if edge and c != gap:
				grid.place(Rect2i(c, Vector2i.ONE), K.PALISADE, 2)
	var b := Battle.create_squads(grid, objective, [[U.AXE_WARRIOR, 1]], [], SPAWN, 9)
	var f := _first(b, SIDE.ATTACKER)
	# w środku pierścienia przy lewym boku, start tuż za lewym murem
	var inside := Vector2i(r.position.x + 1, r.position.y + r.size.y / 2)
	f.x = inside.x * BattleConfig.SUB + BattleConfig.SUB / 2
	f.y = inside.y * BattleConfig.SUB + BattleConfig.SUB / 2
	f.post = Vector2i(r.position.x - 2, inside.y)
	b.add_side_morale(SIDE.ATTACKER, -50)
	for t in BattleConfig.TICK_HZ * 60:
		b._act(f)
		if f.cell() == f.post:
			break
	assert_eq(f.cell(), f.post, "wycofany obszedł mur przez lukę i wrócił na start")
	for id: int in b.structures:
		assert_eq(b.structures[id].hp, b.structures[id].max_hp, "nic nie zburzył")
	return true


## Wycofany atakujący nie zdobywa celu, a wycofany obrońca go nie broni (review #155).
func test_routed_units_neither_capture_nor_defend() -> bool:
	var grid := BuildGrid.new(TerrainMap.generate(1337))
	grid.place(grid.manor_spot(64), K.MANOR, 3)
	grid.place(grid.keep_spot(64), K.KEEP, 1)
	var b := Battle.for_castle(grid, {U.AXE_WARRIOR: 1}, {U.SHIELDBEARER: 1}, SPAWN, 1)
	var keep := b.structures[grid.keep_id()]
	var at := Vector2i(keep.rect.position.x, keep.rect.position.y - 1)
	for f in b.fighters:
		f.x = at.x * BattleConfig.SUB + BattleConfig.SUB / 2
		f.y = at.y * BattleConfig.SUB + BattleConfig.SUB / 2
	# obrońca złamany z dala od swojej kratki: nie blokuje zdobywania
	b.add_side_morale(SIDE.DEFENDER, -50)
	for f in b.fighters:
		if f.side == SIDE.DEFENDER:
			f.post = at + Vector2i(10, 10)
	b._update_capture()
	assert_eq(b.capture_ticks, 1, "wycofany obrońca w drodze nie broni celu")
	# ten sam obrońca osaczony na swojej kratce przy donżonie broni go dalej (#16)
	for f in b.fighters:
		if f.side == SIDE.DEFENDER:
			f.post = at
	b._update_capture()
	assert_eq(b.capture_ticks, 0, "osaczony obrońca blokuje zdobywanie")
	b.add_side_morale(SIDE.ATTACKER, 50)
	# atakujący też złamany: nie zdobywa
	b.add_side_morale(SIDE.ATTACKER, -50)
	b._update_capture()
	assert_eq(b.capture_ticks, 0, "wycofany atakujący nie zdobywa")
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
	# fabryka bitwy o zamek sama dolicza premię (review #155)
	var grid := BuildGrid.new(TerrainMap.generate(1337))
	grid.place(grid.manor_spot(64), K.MANOR, 3)
	grid.place(grid.keep_spot(64), K.KEEP, 1)
	var b := Battle.for_castle(grid, {U.AXE_WARRIOR: 1}, {U.SHIELDBEARER: 1}, SPAWN, 1, r)
	assert_eq(b.squad_morale(SIDE.DEFENDER, 1), BattleConfig.MORALE_START + 5, "załoga z U1")
	assert_eq(b.squad_morale(SIDE.ATTACKER, 1), BattleConfig.MORALE_START, "atakujący bez premii")
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



## Samouczek #16: wycofany obrońca, który stoi już na swojej kratce, oddaje wrogom w zasięgu,
## zamiast stać bezbronnie. Nie ściga ich.
func test_cornered_defender_fights_back() -> bool:
	var b := _battle([[U.AXE_WARRIOR, 1]], [[U.AXE_WARRIOR, 1]])
	var a := _first(b, SIDE.ATTACKER)
	var d := _first(b, SIDE.DEFENDER)
	a.x = d.x + BattleConfig.SUB
	a.y = d.y
	b.add_side_morale(SIDE.DEFENDER, -50)
	assert_true(b.routed(d) and b.cornered(d), "obrońca złamany na swojej kratce")
	var hp := a.hp
	d.cooldown = 0
	b._act(d)
	assert_true(a.hp < hp, "osaczony oddaje")
	var x := d.x
	a.x = d.x + 3 * BattleConfig.SUB
	for i in 30:
		b._act(d)
	assert_eq(d.x, x, "nie ściga")
	return true
