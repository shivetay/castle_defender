extends TestCase
## Wóz łupowy (#235): logistyczna jednostka epoki I ze Stajni. Nie walczy, w planie ataku ma tylko
## manewr Tabor (trasa do zaplanowania, start z opóźnieniem WAGON_DELAY_S) i podnosi capacity łupu
## (UnitTypes.CARRY), które sprawdza też serwer (`private.unit_carry`, test pgTAP wagon_test.sql).

const T0 := 1_700_000_000_000
const K := BuildingTypes.Kind
const U := UnitTypes.Unit
const M := AttackPlan.Manoeuvre
const G := GoodsConfig.Good
const R := EconomyConfig.Res
const RES := Recruitment.Result
const SPAWN := Vector2i(32, 60)


func _free_cell(grid: BuildGrid, kind: int) -> Vector2i:
	var c := grid.terrain.center()
	for r in grid.terrain.size:
		for dy in range(-r, r + 1):
			for dx in range(-r, r + 1):
				var p := c + Vector2i(dx, dy)
				if grid.placement_for(p, kind) != Rect2i():
					return p
	return Vector2i(-1, -1)


func _rich() -> Array:
	var e := Economy.new(T0)
	for res in EconomyConfig.count():
		e.amounts[res] = 1000
	var goods := Goods.new(T0)
	for good in GoodsConfig.count():
		goods.amounts[good] = 50
	return [e, goods]


func test_wagon_stats() -> bool:
	assert_eq(UnitTypes.unit_name(U.WAGON), "Wóz", "nazwa")
	assert_eq(UnitTypes.age(U.WAGON), 0, "epoka I")
	assert_eq(UnitTypes.required_tech(U.WAGON), "", "bez badań")
	assert_eq(UnitTypes.building(U.WAGON), K.STABLE, "szkoli się w Stajni")
	assert_eq(UnitTypes.attack(U.WAGON), 0, "nie walczy")
	assert_eq(UnitTypes.hp(U.WAGON), 120, "120 HP")
	assert_eq(UnitTypes.speed(U.WAGON), 2, "wolny")
	assert_eq(UnitTypes.resource_cost(U.WAGON), {R.WOOD: 40}, "40 drewna")
	assert_eq(UnitTypes.goods_cost(U.WAGON), {G.HORSE: 1, G.HARNESS: 1}, "koń i uprząż")
	assert_eq(UnitTypes.carry(U.WAGON), 50, "unosi 50")
	assert_eq(UnitTypes.upkeep(U.WAGON), 2, "je jak koń")
	assert_true(UnitTypes.carry(U.WAGON) > UnitTypes.carry(U.RIDER), "unosi więcej niż konnica")
	return true


## Bez Stajni nie da się zrekrutować Wozu; w Stajni za konia i uprząż tak.
func test_wagon_needs_stable() -> bool:
	var grid := BuildGrid.new(TerrainMap.generate(1337))
	grid.place_kind(_free_cell(grid, K.MANOR), K.MANOR, 3)
	var barracks := grid.place_kind(_free_cell(grid, K.BARRACKS), K.BARRACKS, 1)
	var rich := _rich()
	var e: Economy = rich[0]
	var goods: Goods = rich[1]
	var rec := Recruitment.new()
	var r := Research.new()
	assert_eq(rec.availability(U.WAGON, grid, r, 0), RES.NO_BUILDING, "bez Stajni nie")
	assert_eq(rec.start(U.WAGON, barracks, Recruitment.NEW_SQUAD, grid, e, goods, r, 0, T0), RES.NO_BUILDING,
			"nie w Koszarach")
	var stable := grid.place_kind(_free_cell(grid, K.STABLE), K.STABLE, 1)
	assert_eq(rec.availability(U.WAGON, grid, r, 0), RES.OK, "ze Stajnią w epoce I bez badań")
	goods.amounts[G.HARNESS] = 0
	assert_eq(rec.start(U.WAGON, stable, Recruitment.NEW_SQUAD, grid, e, goods, r, 0, T0), RES.NO_GOODS, "bez uprzęży nie")
	goods.amounts[G.HARNESS] = 1
	var wood := e.amounts[R.WOOD]
	assert_eq(rec.start(U.WAGON, stable, Recruitment.NEW_SQUAD, grid, e, goods, r, 0, T0), RES.OK, "z koniem i uprzężą")
	assert_eq(goods.amounts[G.HORSE], 49, "koń zszedł")
	assert_eq(goods.amounts[G.HARNESS], 0, "uprząż zeszła")
	assert_eq(e.amounts[R.WOOD], wood - 40, "drewno zeszło")
	assert_eq(rec.update(T0 + RecruitmentConfig.train_ms(U.WAGON, 1)), [U.WAGON] as Array[int], "wyszkolony")
	return true


## Ocalałe wozy podnoszą capacity; brak wozów nie blokuje łupu, tylko daje mniejszy limit.
func test_wagon_raises_loot_capacity() -> bool:
	var army := [[U.AXE_WARRIOR, 10], [U.WAGON, 2]]
	assert_eq(BattleResult.carry_capacity(army, [10, 2] as Array[int]), 150, "10 × 5 + 2 × 50")
	assert_eq(BattleResult.carry_capacity(army, [10, 0] as Array[int]), 50, "bez ocalałych wozów")
	assert_eq(BattleResult.army_capacity(army), 150, "szacunek w planie: wszyscy wracają")
	assert_eq(BattleResult.wagon_capacity(army), 100, "udział wozów")
	assert_eq(BattleResult.wagon_capacity([[U.AXE_WARRIOR, 10]]), 0, "bez wozów")
	assert_eq(AttackPanel.capacity_text(army), "Unosi łupu: 150 (wozy +100)", "tekst planu")
	assert_eq(AttackPanel.capacity_text([[U.AXE_WARRIOR, 10]]), "Unosi łupu: 50", "bez wozów bez dopisku")
	var r := BattleResult.new()
	r.loot = [100, 100, 100, 0] as Array[int]
	r.limit_to_capacity(BattleResult.carry_capacity(army, [10, 2] as Array[int]))
	assert_eq(r.loot, [50, 50, 50, 0] as Array[int], "łup przycięty do capacity z wozami")
	assert_true(PixelFont.text_width(AttackPanel.capacity_text([[U.AXE_WARRIOR, 10], [U.WAGON, 10], [U.WAGON, 10]]))
			< 200, "tekst mieści się obok kolumny")
	return true


## Plan: Wóz ma tylko Tabor, trasę trzeba wyznaczyć, a start ma zawsze opóźnienie.
func test_wagon_plan_rules() -> bool:
	var units: Array[int] = [U.AXE_WARRIOR, U.WAGON]
	var p := AttackPlan.new()
	AttackPlanner.fit_plan(p, 2, units)
	assert_eq(p.order_for(1).manoeuvre, M.FRONTAL, "piechota: szturm")
	assert_eq(p.order_for(2).manoeuvre, M.CONVOY, "Wóz: Tabor")
	assert_eq(p.problem(2, 0, null, units), "Oddział 2: wyznacz trasę Wozu", "trasę trzeba zaplanować")
	var none := AttackPlan.new()
	assert_eq(none.problem(2, 0, null, units), "Oddział 2: wyznacz trasę Wozu", "Wóz bez rozkazu też")
	var o := p.order_for(2)
	o.waypoints.append(Vector2i(30, 50))
	assert_eq(p.problem(2, 0, null, units), "", "z trasą plan poprawny")
	o.manoeuvre = M.FRONTAL
	assert_true(not p.problem(2, 0, null, units).is_empty(), "Wóz nie szturmuje")
	AttackPlanner.fit_plan(p, 2, units)
	assert_eq(o.manoeuvre, M.CONVOY, "zły manewr Wozu wraca do Taboru")
	assert_eq(AttackPlanner.start_text(o), "po %d s" % AttackPlan.WAGON_DELAY_S, "start z opóźnieniem")
	AttackPlanner.next_start(o, 2)
	assert_eq(o.start_value, 30, "krótsze czasy niż opóźnienie pominięte")
	assert_eq(AttackPlanner.start_text(o), "po 30 s", "dłuższy czas z planu")
	# trasa: budynek nie jest celem, ostatni punkt to postój
	var bot := BotCastle.generate(BotCastle.seed_for(1337, 0), 0)
	var keep_cell := bot.grid.buildings[bot.objective].position
	o.waypoints.clear()
	assert_eq(AttackPlanner.tap(o, bot.grid, keep_cell), AttackPlanner.WAGON_HINT, "budynek: podpowiedź")
	assert_eq(o.target, AttackPlan.NO_TARGET, "bez celu-budynku")
	assert_eq(AttackPlanner.end_cell(o, bot), AttackPlan.NO_TARGET, "bez trasy bez końca strzałki")
	var grass := _grass_near(bot, bot.spawn + Vector2i(0, -4))
	AttackPlanner.tap(o, bot.grid, grass)
	assert_eq(AttackPlanner.end_cell(o, bot), grass, "koniec strzałki to postój")
	assert_eq(AttackPlanner.arrow_cells(o, bot), [bot.spawn, grass] as Array[Vector2i], "strzałka: wejście i trasa")
	var other := _grass_near(bot, bot.spawn + Vector2i(3, -4))
	AttackPlanner.set_end(o, bot.grid, other)
	assert_eq(o.waypoints, [other] as Array[Vector2i], "przeciągnięcie przenosi postój")
	assert_eq(AttackPlanner.set_end(o, bot.grid, keep_cell), AttackPlanner.WAGON_HINT, "nie na budynek")
	assert_true(PixelFont.text_width(AttackPlanner.WAGON_HINT) <= 296, "podpowiedź mieści się")
	assert_true(PixelFont.text_width(UnitTypes.ROLES[U.WAGON]) <= 296 * 2, "opis roli w 2 liniach")
	return true


func _grass_near(bot: BotCastle, c: Vector2i) -> Vector2i:
	for r in 10:
		for dy in range(-r, r + 1):
			for dx in range(-r, r + 1):
				var p := c + Vector2i(dx, dy)
				if bot.grid.terrain.in_bounds(p) and bot.grid.building_at(p) == 0 \
						and bot.grid.terrain.get_tile(p) != TerrainMap.Tile.WATER:
					return p
	return c


func _wagons(b: Battle) -> Array[Battle.Fighter]:
	var out: Array[Battle.Fighter] = []
	for f in b.fighters:
		if f.side == Battle.Side.ATTACKER and f.unit == U.WAGON:
			out.append(f)
	return out


func _battle(plan: AttackPlan, attackers: Array) -> Battle:
	var grid := BuildGrid.new(TerrainMap.generate(1337))
	var keep := grid.place(grid.manor_spot(64), K.KEEP, 1)
	var b := Battle.create_squads(grid, keep, attackers, [[U.PEASANT, 2]], SPAWN, 5)
	if plan != null:
		b.set_plan(plan)
	return b


## Bitwa: Wóz czeka WAGON_DELAY_S sekund, potem jedzie trasą i staje na jej końcu; nie walczy.
func test_wagon_in_battle() -> bool:
	var p := AttackPlan.new()
	p.add(1, M.FRONTAL)
	var o := p.add(2, M.CONVOY)
	var stop := SPAWN + Vector2i(-6, -2)
	o.waypoints.append(stop)
	var b := _battle(p, [[U.TRACKER, 1], [U.WAGON, 2]])
	var start: Array[Vector2i] = []
	for f in _wagons(b):
		start.append(f.cell())
	b.run(AttackPlan.WAGON_DELAY_S * BattleConfig.TICK_HZ - 1)
	var moved := false
	for i in _wagons(b).size():
		moved = moved or _wagons(b)[i].cell() != start[i]
	assert_true(not moved, "przed opóźnieniem Wóz stoi")
	b.run(AttackPlan.WAGON_DELAY_S * BattleConfig.TICK_HZ + 40 * BattleConfig.TICK_HZ)
	var route: Array = b._sq_route[Battle._squad_key(Battle.Side.ATTACKER, 2)]
	var goal: Vector2i = route[-1]
	for f in _wagons(b):
		assert_true(f.alive(), "Wóz cały")
		assert_true(absi(f.cell().x - goal.x) <= 2 and absi(f.cell().y - goal.y) <= 2, "Wóz na postoju")
		assert_eq(f.target, 0, "Wóz nie walczy")
	var again := _battle(p, [[U.TRACKER, 1], [U.WAGON, 2]])
	again.run(b.tick)
	assert_eq(again.checksum(), b.checksum(), "deterministycznie")
	return true


## Same wozy nie przedłużają bitwy: bez walczących atakujących atak się kończy od razu.
func test_only_wagons_end_the_battle() -> bool:
	var b := _battle(null, [[U.WAGON, 2]])
	b.run()
	assert_eq(b.winner, Battle.Winner.DEFENDER, "przegrana")
	assert_eq(b.end_reason, Battle.EndReason.ATTACKERS_ROUTED, "bez walczących")
	assert_true(b.tick < 5, "od razu, nie po limicie czasu")
	return true
