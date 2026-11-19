extends TestCase
## Plan ataku i manewry (#18, notatka Manewry i zadania): każdy manewr robi w symulacji to, co
## opisuje notatka, parametry (cel, trasa, start, odwrót) działają, a plan jest deterministyczny.

const K := BuildingTypes.Kind
const U := UnitTypes.Unit
const M := AttackPlan.Manoeuvre
const ST := AttackPlan.Start
const SPAWN := Vector2i(32, 60)


## Zamek: donżon w pierścieniu palisady z bramą w dolnym boku i Chata drwala poza pierścieniem.
## Zwraca [grid, keep, gate, hut, ring].
func _castle() -> Array:
	var grid := BuildGrid.new(TerrainMap.generate(1337))
	var keep := grid.place(grid.keep_spot(64), K.KEEP, 1)
	var ring := grid.buildings[keep].grow(2)
	@warning_ignore("integer_division")
	var gx := ring.position.x + ring.size.x / 2 - 1
	for x in range(ring.position.x, ring.end.x):
		for y: int in [ring.position.y, ring.end.y - 1]:
			if y == ring.end.y - 1 and x >= gx and x < gx + 3:
				continue
			grid.place(Rect2i(x, y, 1, 1), K.PALISADE, 1)
	for y in range(ring.position.y + 1, ring.end.y - 1):
		for x: int in [ring.position.x, ring.end.x - 1]:
			grid.place(Rect2i(x, y, 1, 1), K.PALISADE, 1)
	var gate := grid.place(Rect2i(gx, ring.end.y - 1, 3, 1), K.GATE, 1)
	var hut := 0
	for dx in range(4, 20):
		hut = grid.place(Rect2i(ring.end.x + dx, ring.end.y + 2, 2, 2), K.LUMBER_HUT, 1)
		if hut != 0:
			break
	return [grid, keep, gate, hut, ring]


func _battle(c: Array, attackers: Array, defenders: Array, plan: AttackPlan, seed_value: int = 3) -> Battle:
	var b := Battle.create_squads(c[0], c[1], attackers, defenders, SPAWN, seed_value)
	if plan != null:
		b.set_plan(plan)
	return b


func _cell_of(grid: BuildGrid, id: int) -> Vector2i:
	return grid.buildings[id].position


func test_plan_rules_and_save() -> bool:
	assert_eq(AttackPlan.max_squads(0), 3, "epoka I: 3 oddziały")
	assert_eq(AttackPlan.max_squads(5), 8, "epoka VI: 8 oddziałów")
	var p := AttackPlan.new()
	p.add(1, M.FRONTAL)
	assert_eq(p.problem(3, 0), "", "poprawny plan")
	assert_true(not p.problem(4, 0).is_empty(), "4 oddziały w epoce I to za dużo")
	p.add(2, M.LADDERS)
	assert_true(not p.problem(3, 0).is_empty(), "drabiny dopiero w epoce II")
	assert_eq(p.problem(3, 1), "", "w epoce II drabiny wolno")
	var o := p.add(3, M.FLANK)
	o.waypoints = [Vector2i(1, 1), Vector2i(2, 2), Vector2i(3, 3), Vector2i(4, 4)] as Array[Vector2i]
	assert_true(not p.problem(3, 1).is_empty(), "najwyżej 3 punkty trasy")
	o.waypoints.resize(2)
	o.start = ST.AFTER_SQUAD
	o.start_value = 3
	assert_true(not p.problem(3, 1).is_empty(), "oddział nie czeka na siebie")
	o.start_value = 2
	var o2 := p.order_for(2)
	o2.start = ST.AFTER_SQUAD
	o2.start_value = 3
	assert_true(not p.problem(3, 1).is_empty(), "oddziały nie czekają na siebie w kółko")
	o2.start = ST.AFTER_SECONDS
	o2.start_value = 5
	o.retreat_percent = 50
	o.flank_left = false
	assert_eq(p.problem(3, 1), "", "poprawny po zmianach")
	var back := AttackPlan.from_dict(JSON.parse_string(JSON.stringify(p.to_dict())) as Dictionary)
	assert_eq(back.to_dict(), p.to_dict(), "zapis i odczyt przez JSON")
	assert_eq(back.order_for(3).waypoints, [Vector2i(1, 1), Vector2i(2, 2)] as Array[Vector2i], "trasa po odczycie")
	return true


## Szturm frontalny na donżon to dotychczasowe zachowanie: ten sam przebieg co bez planu.
func test_frontal_on_objective_matches_no_plan() -> bool:
	var c := _castle()
	var army := [[U.AXE_WARRIOR, 6], [U.ARCHER, 4]]
	var plain := _battle(c, army, [[U.PEASANT, 4]], null)
	plain.run()
	var p := AttackPlan.new()
	p.add(1, M.FRONTAL)
	p.add(2, M.FRONTAL)
	var planned := _battle(c, army, [[U.PEASANT, 4]], p)
	planned.run()
	# suma kontrolna zawiera też flagi rozkazów, których bez planu nie ma, więc porównujemy przebieg
	assert_eq(_course(planned), _course(plain), "ten sam przebieg: jednostki, budynki, wynik i czas")
	return true


## Przebieg bitwy bez stanu rozkazów: pozycje i HP jednostek, HP budynków, zwycięzca i czas.
func _course(b: Battle) -> Array:
	var out: Array = [b.winner, b.end_reason, b.tick]
	for f in b.fighters:
		out.append([f.id, f.x, f.y, f.hp])
	for id: int in b.structures:
		out.append([id, (b.structures[id] as Battle.Structure).hp])
	return out


func test_frontal_on_chosen_building_destroys_it_first() -> bool:
	var c := _castle()
	var grid: BuildGrid = c[0]
	var p := AttackPlan.new()
	p.add(1, M.FRONTAL, _cell_of(grid, c[3]))
	var b := _battle(c, [[U.AXE_WARRIOR, 6]], [], p)
	var hut: Battle.Structure = b.structures[c[3]]
	var keep: Battle.Structure = b.structures[c[1]]
	while hut.hp > 0 and b.winner == Battle.Winner.NONE:
		b.step()
	assert_true(hut.hp <= 0, "chata zburzona")
	assert_eq(keep.hp, keep.max_hp, "donżon jeszcze nietknięty")
	b.step()
	assert_true(b._sq_done.has(Battle._squad_key(Battle.Side.ATTACKER, 1)), "zadanie wykonane")
	return true


func test_ranged_fire_stops_in_range() -> bool:
	var c := _castle()
	var grid: BuildGrid = c[0]
	var ring: Rect2i = c[4]
	var wall_cell := Vector2i(ring.position.x, ring.end.y - 1)
	var p := AttackPlan.new()
	p.add(1, M.RANGED, wall_cell)
	var b := _battle(c, [[U.ARCHER, 4]], [], p)
	var wall := b._structure_at(wall_cell)
	assert_true(wall != null, "odcinek palisady")
	var closest := 1 << 30
	var key := Battle._squad_key(Battle.Side.ATTACKER, 1)
	var hold_after := Vector2i(-1, -1)
	for i in 1800:
		b.step()
		for f in b.fighters:
			var d := maxi(absi(f.cell().x - wall_cell.x), absi(f.cell().y - wall_cell.y))
			closest = mini(closest, d)
		if b._sq_fire.has(key) and hold_after.x < 0:
			hold_after = b._sq_fire[key]
		if wall.hp <= 0:
			break
	assert_true(wall.hp <= 0, "łucznicy zburzyli odcinek z dystansu")
	assert_true(closest >= 2, "żaden łucznik nie podszedł pod mur (najbliżej %d kratki)" % closest)
	assert_true(b._sq_fire.has(key), "oddział ma punkt ostrzału")
	assert_eq(b._sq_fire[key], hold_after, "punkt ostrzału ustalony raz")
	assert_eq(grid.kinds[c[1]], K.KEEP, "donżon na miejscu")
	return true


## Ostrzał: jeden punkt postoju; po wejściu w zasięg nikt nie idzie bliżej muru.
func test_ranged_holds_one_fire_point() -> bool:
	var c := _castle()
	var ring: Rect2i = c[4]
	var wall_cell := Vector2i(ring.position.x, ring.end.y - 1)
	var p := AttackPlan.new()
	p.add(1, M.RANGED, wall_cell)
	var b := _battle(c, [[U.ARCHER, 3]], [], p)
	var wall := b._structure_at(wall_cell)
	var key := Battle._squad_key(Battle.Side.ATTACKER, 1)
	var min_after_shot := 1 << 30
	var engaged := false
	var hold_once := Vector2i(-1, -1)
	for i in 1800:
		b.step()
		if b._sq_fire.has(key):
			if hold_once.x < 0:
				hold_once = b._sq_fire[key]
			assert_eq(b._sq_fire[key], hold_once, "jeden punkt ostrzału na oddział")
		var anyone_in_range := false
		for f in b.fighters:
			if f.alive() and b._rect_in_range(f, wall.rect, b.range_of(f)):
				anyone_in_range = true
				break
		if anyone_in_range:
			engaged = true
			for f in b.fighters:
				if not f.alive():
					continue
				var d := maxi(absi(f.cell().x - wall_cell.x), absi(f.cell().y - wall_cell.y))
				min_after_shot = mini(min_after_shot, d)
		if wall.hp <= 0:
			break
	assert_true(engaged, "oddział wszedł w zasięg ostrzału")
	assert_true(hold_once.x >= 0, "punkt ostrzału wyznaczony")
	assert_true(min_after_shot >= 2, "po ostrzale nikt nie poszedł bliżej muru (min %d)" % min_after_shot)
	assert_true(wall.hp < wall.max_hp, "strzelali w cel z dystansu")
	return true


## Ostrzał: wróg w zasięgu strzału — stój i bij, bez marszu naprzód.
func test_ranged_stays_when_enemy_in_range() -> bool:
	var c := _castle()
	var ring: Rect2i = c[4]
	var wall_cell := Vector2i(ring.position.x, ring.end.y - 1)
	var p := AttackPlan.new()
	p.add(1, M.RANGED, wall_cell)
	var def_cell := Vector2i(SPAWN.x, SPAWN.y - 8)
	var b := _battle(c, [[U.ARCHER, 2]], [[U.PEASANT, 1]], p)
	for f in b.fighters:
		if f.side == Battle.Side.DEFENDER:
			f.x = def_cell.x * BattleConfig.SUB + BattleConfig.SUB / 2
			f.y = def_cell.y * BattleConfig.SUB + BattleConfig.SUB / 2
			f.post = def_cell
	var prev: Dictionary = {}
	var held_ticks := 0
	for i in 900:
		b.step()
		var defenders: Array[Battle.Fighter] = []
		for g in b.fighters:
			if g.side == Battle.Side.DEFENDER and g.alive():
				defenders.append(g)
		if defenders.is_empty():
			break
		for f in b.fighters:
			if f.side != Battle.Side.ATTACKER or not f.alive():
				continue
			var in_shot := false
			for enemy in defenders:
				if b._in_range(f, enemy.x, enemy.y, b.range_of(f)):
					in_shot = true
					break
			if not in_shot:
				prev.erase(f.id)
				continue
			if prev.has(f.id):
				assert_eq(f.cell(), prev[f.id] as Vector2i, "przy wrogu w zasięgu bez marszu")
				held_ticks += 1
			prev[f.id] = f.cell()
		if held_ticks >= 20:
			break
	assert_true(held_ticks >= 10, "stali i strzelali przy wrogu w zasięgu (%d ticków)" % held_ticks)
	assert_true(b._structure_at(wall_cell) != null, "cel budynku wciąż na mapie")
	return true


func test_fire_hold_point_is_in_range() -> bool:
	var rect := Rect2i(10, 10, 2, 2)
	var spawn := Vector2i(10, 30)
	var p := Battle.fire_hold_point(spawn, rect, 6, 64)
	assert_eq(p.x, 10, "na osi podejścia")
	assert_eq(p.y, 17, "6 kratek od krawędzi w stronę wejścia")
	var edge := Vector2i(10, 11)
	assert_eq(maxi(absi(p.x - edge.x), absi(p.y - edge.y)), 6, "dystans Chebysheva od krawędzi")
	return true


func test_fire_targets_wooden_buildings() -> bool:
	var c := _castle()
	var p := AttackPlan.new()
	p.add(1, M.FIRE)
	var b := _battle(c, [[U.FIRE_RAISER, 3]], [], p)
	var key := Battle._squad_key(Battle.Side.ATTACKER, 1)
	var burned := 0
	for i in 1800:
		b.step()
		if b._sq_done.has(key):
			break
	for id: int in b.structures:
		var s: Battle.Structure = b.structures[id]
		if s.burning > 0 or s.hp < s.max_hp:
			burned += 1
	assert_true(b._sq_done.has(key), "pierwszy cel płonie")
	assert_true(burned > 0, "drewniany budynek trafiony")
	assert_eq((b.structures[c[1]] as Battle.Structure).hp, (b.structures[c[1]] as Battle.Structure).max_hp,
			"podpalacze nie idą na donżon, tylko na najbliższe drewno")
	return true


func test_flank_goes_around_the_side() -> bool:
	var c := _castle()
	var p := AttackPlan.new()
	var o := p.add(1, M.FLANK)
	var b := _battle(c, [[U.AXE_WARRIOR, 4]], [], p)
	var left := b.flank_point(o)
	o.flank_left = false
	var right := b.flank_point(o)
	assert_true(left.x < SPAWN.x and right.x > SPAWN.x, "obejście z lewej i z prawej (cel na północy)")
	o.flank_left = true
	b.set_plan(p)
	var route: Array = b._sq_route[Battle._squad_key(Battle.Side.ATTACKER, 1)]
	assert_eq(route.size(), 1, "punkt obejścia")
	var point: Vector2i = route[0]
	var reached := false
	for i in 1800:
		b.step()
		for f in b.fighters:
			if f.wp >= 1:
				reached = true
		if reached:
			break
	assert_true(reached, "oddział doszedł do punktu obejścia")
	var keep_x := (b.structures[c[1]] as Battle.Structure).rect.get_center().x
	assert_true(absi(point.x - keep_x) >= BattleConfig.FLANK_MIN_CELLS - 1, "punkt z boku zamku, nie na wprost")
	return true


func test_ladders_cross_the_wall_without_a_breach() -> bool:
	var c := _castle()
	var ring: Rect2i = c[4]
	var wall_cell := Vector2i(ring.position.x + 1, ring.end.y - 1)
	var p := AttackPlan.new()
	p.add(1, M.LADDERS, wall_cell)
	var b := _battle(c, [[U.AXE_WARRIOR, 4]], [], p)
	var inside := Rect2i(ring.position + Vector2i.ONE, ring.size - Vector2i(2, 2))
	var crossed: Battle.Fighter = null
	for i in 2400:
		b.step()
		for f in b.fighters:
			if f.climbed and crossed == null:
				crossed = f
		if crossed != null:
			break
	assert_true(crossed != null, "jednostka przeszła po drabinie")
	assert_true(inside.has_point(crossed.cell()), "jest wewnątrz pierścienia")
	var wall := b._structure_at(wall_cell)
	assert_true(wall != null and wall.hp == wall.max_hp, "mur cały: bez wyłomu")
	var gate: Battle.Structure = b.structures[c[2]]
	assert_eq(gate.hp, gate.max_hp, "brama ominięta")
	return true


func test_ram_with_escort_breaks_the_gate() -> bool:
	var c := _castle()
	var p := AttackPlan.new()
	p.add(1, M.RAM_GATE)
	p.add(2, M.RAM_GATE)
	var b := _battle(c, [[U.RAM, 1], [U.AXE_WARRIOR, 4]], [], p)
	var gate: Battle.Structure = b.structures[c[2]]
	var max_gap := 0
	for i in 3600:
		b.step()
		var ram: Battle.Fighter = null
		for f in b.fighters:
			if f.unit == U.RAM:
				ram = f
		if ram != null and i > 150:
			for f in b.fighters:
				if f.unit != U.RAM:
					@warning_ignore("integer_division")
					max_gap = maxi(max_gap, maxi(absi(f.x - ram.x), absi(f.y - ram.y)) / BattleConfig.SUB)
		if gate.hp <= 0:
			break
	assert_true(gate.hp <= 0, "brama padła")
	assert_true(max_gap <= BattleConfig.ESCORT_RADIUS + 2, "osłona idzie przy taranie (najdalej %d kratek)" % max_gap)
	b.step()
	assert_true(b._sq_done.has(Battle._squad_key(Battle.Side.ATTACKER, 2)), "zadanie osłony wykonane")
	return true


func test_start_after_seconds_and_after_squad() -> bool:
	var c := _castle()
	var grid: BuildGrid = c[0]
	var p := AttackPlan.new()
	p.add(1, M.FRONTAL, _cell_of(grid, c[3]))
	var o2 := p.add(2, M.FRONTAL)
	o2.start = ST.AFTER_SQUAD
	o2.start_value = 1
	var o3 := p.add(3, M.FRONTAL)
	o3.start = ST.AFTER_SECONDS
	o3.start_value = 5
	var b := _battle(c, [[U.AXE_WARRIOR, 6], [U.ARCHER, 2], [U.PEASANT, 2]], [], p)
	var start := {}
	for f in b.fighters:
		start[f.id] = Vector2i(f.x, f.y)
	for i in 5 * BattleConfig.TICK_HZ - 1:
		b.step()
	for f in b.fighters:
		if f.squad == 3:
			assert_eq(Vector2i(f.x, f.y), start[f.id], "oddział 3 czeka 5 s")
	b.step()
	b.step()
	var moved := false
	for f in b.fighters:
		if f.squad == 3 and Vector2i(f.x, f.y) != start[f.id]:
			moved = true
	assert_true(moved, "po 5 s oddział 3 rusza")
	var hut: Battle.Structure = b.structures[c[3]]
	var key2 := Battle._squad_key(Battle.Side.ATTACKER, 2)
	while hut.hp > 0 and b.winner == Battle.Winner.NONE:
		assert_true(not b._sq_started.has(key2), "oddział 2 czeka, aż chata padnie")
		b.step()
	b.step()
	b.step()
	assert_true(b._sq_started.has(key2), "po zburzeniu chaty oddział 2 rusza")
	return true


func test_retreat_after_losses() -> bool:
	var c := _castle()
	var p := AttackPlan.new()
	var o := p.add(1, M.FRONTAL)
	o.retreat_percent = 50
	var b := _battle(c, [[U.PEASANT, 6]], [[U.SHIELDBEARER, 6], [U.ARCHER, 6]], p)
	var key := Battle._squad_key(Battle.Side.ATTACKER, 1)
	while b.winner == Battle.Winner.NONE and not b._sq_retreat.has(key):
		b.step()
	assert_true(b._sq_retreat.has(key), "oddział się wycofuje")
	var dead := 0
	for f in b.fighters:
		if f.side == Battle.Side.ATTACKER and not f.alive():
			dead += 1
	assert_eq(dead, 3, "przy 50% strat, nie wcześniej")
	b.run()
	assert_eq(b.winner, Battle.Winner.DEFENDER, "wycofany atak przegrywa")
	return true


func test_planned_battle_is_deterministic() -> bool:
	var c := _castle()
	var grid: BuildGrid = c[0]
	var army := [[U.AXE_WARRIOR, 6], [U.ARCHER, 4], [U.FIRE_RAISER, 3]]
	var p := AttackPlan.new()
	p.add(1, M.FLANK).retreat_percent = 70
	p.add(2, M.RANGED, _cell_of(grid, c[2]))
	var o3 := p.add(3, M.FIRE)
	o3.start = ST.AFTER_SECONDS
	o3.start_value = 3
	var a := _battle(c, army, [[U.PEASANT, 6]], p, 9)
	var b := _battle(c, army, [[U.PEASANT, 6]], AttackPlan.from_dict(p.to_dict()), 9)
	a.run()
	b.run()
	assert_true(a.winner != Battle.Winner.NONE, "bitwa się rozstrzyga")
	assert_eq(a.checksum(), b.checksum(), "ten sam plan i seed: ten sam przebieg")
	return true


## Review PR 175: zejście z drabiny nie ląduje na zajętej kratce, set_plan(null) zdejmuje plan,
## a stan rozkazów wchodzi do sumy kontrolnej.
func test_review_fixes() -> bool:
	var c := _castle()
	var ring: Rect2i = c[4]
	var wall_cell := Vector2i(ring.position.x + 1, ring.end.y - 1)
	var p := AttackPlan.new()
	p.add(1, M.LADDERS, wall_cell)
	var b := _battle(c, [[U.AXE_WARRIOR, 6]], [], p)
	var landed := {}
	var stacked := 0
	for i in 2400:
		b.step()
		for f in b.fighters:
			if f.climbed and not landed.has(f.id):
				landed[f.id] = f.cell()
				for other: int in landed:
					if other != f.id and landed[other] == f.cell():
						var g: Battle.Fighter = null
						for h in b.fighters:
							if h.id == other:
								g = h
						if g != null and g.cell() == f.cell():
							stacked += 1
		if landed.size() >= 2:
			break
	assert_true(landed.size() >= 2, "co najmniej dwóch zeszło po drabinie")
	assert_eq(stacked, 0, "nikt nie wylądował na kratce, na której ktoś stoi")
	var plain := _battle(c, [[U.AXE_WARRIOR, 4]], [[U.PEASANT, 2]], null)
	var cleared := _battle(c, [[U.AXE_WARRIOR, 4]], [[U.PEASANT, 2]], p)
	cleared.set_plan(null)
	assert_true(cleared.plan == null, "plan zdjęty")
	plain.run()
	cleared.run()
	assert_eq(cleared.checksum(), plain.checksum(), "zdjęty plan: dokładnie jak bez planu")
	var waiting := AttackPlan.new()
	var o := waiting.add(1, M.FRONTAL)
	o.start = ST.AFTER_SECONDS
	o.start_value = 2
	var x := _battle(c, [[U.AXE_WARRIOR, 4]], [], waiting)
	var y := _battle(c, [[U.AXE_WARRIOR, 4]], [], waiting)
	x.step()
	y.step()
	y._sq_started[Battle._squad_key(Battle.Side.ATTACKER, 1)] = true
	assert_true(x.checksum() != y.checksum(), "stan rozkazów jest w sumie kontrolnej")
	return true
