extends TestCase
## Zadania obrony (#20, notatka Manewry i zadania): Obrona odcinka, Patrol i Priorytet celów wież
## w symulacji bitwy oraz ich edycja na ekranie Obrona.

const K := BuildingTypes.Kind
const U := UnitTypes.Unit
const T := DefensePlan.Task
const NO := DefensePlan.NO_POST


func _castle(world_seed: int = 1337) -> BuildGrid:
	var grid := BuildGrid.new(TerrainMap.generate(WorldSeed.first_playable(world_seed)))
	grid.place(grid.manor_spot(64), K.MANOR, 1)
	grid.place(grid.keep_spot(64), K.KEEP, 1)
	return grid


static func _cheb(a: Vector2i, b: Vector2i) -> int:
	return maxi(absi(a.x - b.x), absi(a.y - b.y))


## Wolna kratka strefy obrony w odległości `dist` od donżonu, w kierunku `dir` (albo najbliższa takiej).
func _free_at(grid: BuildGrid, dir: Vector2i, dist: int) -> Vector2i:
	var c := DefensePlan.keep_center(grid)
	for k in range(dist, 0, -1):
		for side: int in [0, 1, -1, 2, -2]:
			var p := c + dir * k + Vector2i(dir.y, dir.x) * side
			if DefensePlan.post_problem(grid, p).is_empty():
				return p
	return NO


func _order(task: int, post: Vector2i, route: Array[Vector2i] = []) -> DefensePlan.Order:
	var o := DefensePlan.Order.new()
	o.task = task
	o.post = post
	o.route = route
	return o


func _put(b: Battle, f: Battle.Fighter, c: Vector2i) -> void:
	f.x = c.x * BattleConfig.SUB + BattleConfig.SUB / 2
	f.y = c.y * BattleConfig.SUB + BattleConfig.SUB / 2
	f.path.clear()


func _side(b: Battle, side: int) -> Array[Battle.Fighter]:
	var out: Array[Battle.Fighter] = []
	for f in b.fighters:
		if f.side == side:
			out.append(f)
	return out


## Obrona odcinka: wróg daleko od miejsca (ale w zasięgu wzroku) nie wyciąga obrońcy, wróg blisko
## miejsca jest ścigany, a po walce obrońca wraca na miejsce.
func test_hold_section_does_not_chase_far() -> bool:
	var grid := _castle()
	var post := _free_at(grid, Vector2i.RIGHT, 8)
	var spawn := BotCastle.edge_road(grid.terrain)
	var b := Battle.for_castle_squads(grid, [[U.TRACKER, 1]], [[U.AXE_WARRIOR, 1]], spawn, 4, null,
			[_order(T.HOLD, post)] as Array[DefensePlan.Order])
	var def := _side(b, Battle.Side.DEFENDER)[0]
	var foe := _side(b, Battle.Side.ATTACKER)[0]
	# wróg 7 kratek od miejsca: w zasięgu wzroku obrońcy, ale poza HOLD_RADIUS
	var far := post + Vector2i(0, BattleConfig.HOLD_RADIUS + 3)
	if not DefensePlan.post_problem(grid, far).is_empty():
		far = post - Vector2i(0, BattleConfig.HOLD_RADIUS + 3)
	_put(b, foe, far)
	for i in 300:
		b._act(def)
	assert_true(_cheb(def.cell(), post) <= 1, "obrońca odcinka zostaje na miejscu")
	# bez zadania ten sam obrońca rusza w pościg (DEFENDER_AGGRO_EXTRA)
	var free := Battle.for_castle_squads(grid, [[U.TRACKER, 1]], [[U.AXE_WARRIOR, 1]], spawn, 4, null,
			DefensePlan.hold_orders([post] as Array[Vector2i]))
	free.defence.clear()
	var d2 := _side(free, Battle.Side.DEFENDER)[0]
	_put(free, _side(free, Battle.Side.ATTACKER)[0], far)
	for i in 300:
		free._act(d2)
	assert_true(_cheb(d2.cell(), post) >= 2, "bez zadania obrońca ściga")
	return true


func test_hold_section_engages_close_enemy() -> bool:
	var grid := _castle()
	var post := _free_at(grid, Vector2i.RIGHT, 8)
	var b := Battle.for_castle_squads(grid, [[U.AXE_WARRIOR, 1]], [[U.AXE_WARRIOR, 1]],
			BotCastle.edge_road(grid.terrain), 4, null, [_order(T.HOLD, post)] as Array[DefensePlan.Order])
	var def := _side(b, Battle.Side.DEFENDER)[0]
	var foe := _side(b, Battle.Side.ATTACKER)[0]
	var near := post + Vector2i(0, 3)
	if not DefensePlan.post_problem(grid, near).is_empty():
		near = post - Vector2i(0, 3)
	_put(b, foe, near)
	var hp := foe.hp
	for i in 90:
		b._act(def)
	assert_true(foe.hp < hp, "wróg 3 kratki od miejsca dostaje")
	foe.hp = 0
	for i in 120:
		b._act(def)
	assert_true(_cheb(def.cell(), post) <= 1, "po walce obrońca wraca na miejsce")
	return true


## Patrol: bez wrogów oddział obchodzi wszystkie punkty trasy w kółko.
func test_patrol_visits_all_points() -> bool:
	var grid := _castle()
	var a := _free_at(grid, Vector2i.RIGHT, 6)
	var c := _free_at(grid, Vector2i.DOWN, 6)
	var d := _free_at(grid, Vector2i.LEFT, 6)
	var o := _order(T.PATROL, a, [c, d] as Array[Vector2i])
	var b := Battle.for_castle_squads(grid, [[U.TRACKER, 1]], [[U.ARCHER, 2]], BotCastle.edge_road(grid.terrain), 6,
			null, [o] as Array[DefensePlan.Order])
	var f := _side(b, Battle.Side.DEFENDER)[0]
	var seen := {}
	var laps := 0
	var last := -1
	for t in 120 * BattleConfig.TICK_HZ:
		b._act(f)
		for k in 3:
			if _cheb(f.cell(), o.patrol_points()[k]) <= 1:
				seen[k] = true
		if f.wp == 0 and last == 2:
			laps += 1
		last = f.wp
	assert_eq(seen.size(), 3, "obszedł 3 punkty")
	assert_true(laps >= 1, "i wrócił na początek trasy")
	return true


## Priorytet wież: z Taranem w zasięgu wieża bije Taran, choć piechota stoi bliżej; bez priorytetu
## (najbliższy) bije piechotę.
func test_tower_priority_picks_ram() -> bool:
	var grid := _castle()
	var c := DefensePlan.keep_center(grid)
	var spot := NO
	for k in range(5, 10):
		for dy in range(-4, 5):
			var q := c + Vector2i(k, dy)
			if spot == NO and grid.can_place(Rect2i(q, Vector2i(2, 2))) \
					and grid.can_place(Rect2i(q - Vector2i(4, 0), Vector2i(4, 2))):
				spot = q
	grid.place(Rect2i(spot, Vector2i(2, 2)), K.TOWER, 1)
	var tower := grid.building_at(spot)
	assert_true(tower != 0, "wieża stoi")
	var shots := {}
	for priority: int in [DefensePlan.TowerPriority.NEAREST, DefensePlan.TowerPriority.RAM]:
		var b := Battle.for_castle_squads(grid, [[U.AXE_WARRIOR, 1], [U.RAM, 1]], [], BotCastle.edge_road(grid.terrain),
				5, null, [] as Array[DefensePlan.Order], priority)
		var axe := _side(b, Battle.Side.ATTACKER)[0]
		var ram := _side(b, Battle.Side.ATTACKER)[1]
		var r := grid.buildings[tower]
		_put(b, axe, r.position + Vector2i(-1, 0))
		_put(b, ram, r.position + Vector2i(-4, 0))
		var s := b.structures[tower]
		s.cooldown = 0
		b._tower_act(s)
		shots[priority] = "taran" if ram.hp < UnitTypes.hp(U.RAM) else ("topór" if axe.hp < UnitTypes.hp(U.AXE_WARRIOR) else "nic")
	assert_eq(shots[DefensePlan.TowerPriority.NEAREST], "topór", "najbliższy: piechota")
	assert_eq(shots[DefensePlan.TowerPriority.RAM], "taran", "priorytet taran")
	assert_true(c != NO, "donżon")
	return true


## Ten sam układ zadań i ten sam seed: ten sam przebieg; bez zadań przebieg jak dawniej.
func test_tasks_are_deterministic() -> bool:
	var grid := _castle()
	var spawn := BotCastle.edge_road(grid.terrain)
	var attackers := PveWaves.squads(3)
	var defenders := [[U.AXE_WARRIOR, 6], [U.ARCHER, 4]]
	var orders: Array[DefensePlan.Order] = [_order(T.HOLD, _free_at(grid, Vector2i.DOWN, 5)),
			_order(T.PATROL, _free_at(grid, Vector2i.RIGHT, 4), [_free_at(grid, Vector2i.UP, 4)] as Array[Vector2i])]
	var sums: Array[int] = []
	for i in 2:
		var b := Battle.for_castle_squads(grid, attackers, defenders, spawn, 31, null, orders,
				DefensePlan.TowerPriority.RANGED)
		b.run()
		sums.append(b.checksum())
	assert_eq(sums[0], sums[1], "ten sam przebieg")
	var plain := Battle.for_castle_squads(grid, attackers, defenders, spawn, 31)
	var empty := Battle.for_castle_squads(grid, attackers, defenders, spawn, 31, null, [null, null] as Array[DefensePlan.Order])
	plain.run()
	empty.run()
	assert_eq(empty.checksum(), plain.checksum(), "puste zadania: jak bez ustawień")
	return true


## Edycja na ekranie: Zadanie przełącza Obrona odcinka ↔ Patrol, dotknięcia przy Patrolu dodają
## punkty trasy (czwarty zaczyna od nowa), dotknięcie odcinka palisady daje miejsce od środka,
## Wieże zmieniają priorytet. Zapis zachowuje wszystko.
func test_panel_edits_tasks() -> bool:
	var grid := _castle()
	var c := DefensePlan.keep_center(grid)
	var p := DefensePlan.new()
	var panel := DefensePanel.new()
	panel.open(p, [[U.ARCHER, 4]], [7] as Array[int], grid)
	panel.activate(DefensePanel.Target.TASK)
	assert_eq(p.order_for(7).task, T.HOLD, "pierwsze Zadanie: Obrona odcinka")
	assert_eq(panel.describe(0)[1], "Obrona odcinka: dotknij mapy", "bez miejsca prosi o dotknięcie")
	assert_true(p.battle_orders([7] as Array[int])[0] == null, "bez miejsca oddział stoi przy donżonie")
	panel.activate(DefensePanel.Target.TASK)
	assert_eq(p.order_for(7).task, T.PATROL, "drugie: Patrol")
	var pts: Array[Vector2i] = [_free_at(grid, Vector2i.RIGHT, 5), _free_at(grid, Vector2i.DOWN, 5),
			_free_at(grid, Vector2i.LEFT, 5), _free_at(grid, Vector2i.UP, 5)]
	assert_eq(panel.tap(grid, pts[0]), "Oddział 1: patrol, punkt 1 z 3", "pierwszy punkt")
	assert_eq(panel.describe(0)[1], "Patrol 1/3: dodaj punkt", "sam start to jeszcze nie pętla (review #181)")
	assert_eq(p.battle_orders([7] as Array[int])[0].task, T.HOLD, "i w bitwie trzyma miejsce jak Obrona odcinka")
	panel.tap(grid, pts[1])
	assert_eq(p.battle_orders([7] as Array[int])[0].task, T.PATROL, "z drugim punktem to patrol")
	assert_eq(panel.tap(grid, pts[2]), "Oddział 1: patrol, punkt 3 z 3", "trzeci punkt")
	assert_eq(p.order_for(7).patrol_points(), [pts[0], pts[1], pts[2]] as Array[Vector2i], "trasa")
	assert_eq(panel.describe(0)[1], "Patrol 3/3 pkt", "opis trasy")
	assert_eq(panel.tap(grid, pts[3]), "Oddział 1: patrol, punkt 1 z 3", "czwarty zaczyna od nowa")
	assert_eq(p.order_for(7).patrol_points(), [pts[3]] as Array[Vector2i], "nowa trasa")
	var d := p.to_dict()
	assert_eq(DefensePlan.from_dict(JSON.parse_string(JSON.stringify(d)) as Dictionary).to_dict(), d, "zapis patrolu")
	panel.activate(DefensePanel.Target.TASK)
	assert_eq(p.order_for(7).task, T.KEEP, "trzecie: Przy donżonie (łucznik nie ma Wypadu)")
	assert_eq(panel.describe(0)[1], "Przy donżonie", "opis")
	assert_true(p.battle_orders([7] as Array[int])[0] == null, "w bitwie przy donżonie")
	assert_eq(panel.tap(grid, pts[0]), "Przy donżonie: zmień Zadanie, żeby wskazać miejsce", "mapa nic nie zmienia")
	panel.activate(DefensePanel.Target.TASK)
	assert_eq(p.order_for(7).task, T.HOLD, "czwarte: znów Obrona odcinka")
	assert_eq(p.order_for(7).route.size(), 0, "zmiana zadania czyści trasę")
	# odcinek palisady w strefie: miejsce tuż przy nim, od strony donżonu
	var wall_at := c + Vector2i(6, 0)
	var placed := false
	for dy in range(-3, 4):
		var q := wall_at + Vector2i(0, dy)
		if not placed and DefensePlan.post_problem(grid, q).is_empty() \
				and DefensePlan.post_problem(grid, q + Vector2i.LEFT).is_empty():
			grid.place(Rect2i(q, Vector2i.ONE), K.PALISADE, 1)
			wall_at = q
			placed = true
	assert_true(placed, "palisada w strefie")
	panel.activate(DefensePanel.Target.TASK)
	assert_eq(panel.tap(grid, wall_at), "Tu stoi %s" % BuildingTypes.NAMES[K.PALISADE],
			"przy Patrolu palisada nie przyciąga punktu (review #181)")
	panel.activate(DefensePanel.Target.TASK)
	panel.activate(DefensePanel.Target.TASK)
	assert_eq(p.order_for(7).task, T.HOLD, "znów Obrona odcinka")
	assert_eq(panel.tap(grid, wall_at), "Oddział 1: na murze, %s" % BuildingTypes.NAMES[K.PALISADE],
			"łucznik staje na samej palisadzie (#20)")
	assert_eq(p.post_for(7), wall_at, "miejsce to kratka muru")
	assert_eq(panel.describe(0)[1], "Na murze", "opis")
	# piechota przy tym samym odcinku staje od środka zamku
	var foot := DefensePanel.new()
	foot.open(p, [[U.AXE_WARRIOR, 4]], [8] as Array[int], grid)
	assert_eq(foot.tap(grid, wall_at), "Oddział 1: obrona odcinka, %s" % BuildingTypes.NAMES[K.PALISADE], "dotknięcie palisady")
	assert_eq(p.post_for(8), wall_at + Vector2i.LEFT, "miejsce od środka zamku")
	foot.free()
	assert_eq(p.tower_priority, DefensePlan.TowerPriority.NEAREST, "wieże: domyślnie najbliższy")
	panel.activate(DefensePanel.Target.TOWERS)
	assert_eq(p.tower_priority, DefensePlan.TowerPriority.RAM, "Wieże: najpierw taran")
	for i in 3:
		panel.activate(DefensePanel.Target.TOWERS)
	assert_eq(p.tower_priority, DefensePlan.TowerPriority.NEAREST, "w kółko")
	for label: String in DefensePanel.LABELS:
		assert_true(PixelFont.text_width(label) <= Hud.BUTTON_SIZE.x - 2, "„%s” mieści się na przycisku" % label)
	for i in DefensePlan.TOWER_PRIORITY_NAMES.size():
		assert_true(PixelFont.text_width(DefensePanel.tower_text(i)) <= Hud.MESSAGE_MAX_WIDTH, "komunikat wież mieści się")
	panel.free()
	return true
