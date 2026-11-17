extends TestCase
## Zadania obrony #20, krok B i C: stanowiska strzelców na murach, zadania domyślne według klasy
## i Wypad konnicy przez własną bramę.

const K := BuildingTypes.Kind
const U := UnitTypes.Unit
const T := DefensePlan.Task
const C := RecruitmentConfig.UnitClass
const NO := DefensePlan.NO_POST


## Zamek z donżonem i pionową linią 5 odcinków palisady w strefie obrony.
func _walled() -> Array:
	var grid := BuildGrid.new(TerrainMap.generate(WorldSeed.first_playable(1337)))
	grid.place(grid.manor_spot(64), K.MANOR, 1)
	grid.place(grid.keep_spot(64), K.KEEP, 1)
	var c := DefensePlan.keep_center(grid)
	# pionowa linia 5 wolnych kratek trawy w strefie, 4–9 kratek od donżonu (najpierw na prawo)
	var cells: Array[Vector2i] = []
	for dx: int in [4, 5, 6, 7, 8, 9, -4, -5, -6, -7, -8, -9]:
		for oy in range(-6, 3):
			cells.clear()
			for dy in range(oy, oy + 5):
				var p := c + Vector2i(dx, dy)
				if grid.can_place(Rect2i(p, Vector2i.ONE)) and grid.terrain.get_tile(p) == TerrainMap.Tile.GRASS:
					cells.append(p)
			if cells.size() == 5:
				break
		if cells.size() == 5:
			break
	for p in cells:
		grid.place(Rect2i(p, Vector2i.ONE), K.PALISADE, 1)
	return [grid, cells]


func _hold(post: Vector2i) -> DefensePlan.Order:
	var o := DefensePlan.Order.new()
	o.post = post
	return o


func _side(b: Battle, side: int, squad: int = 0) -> Array[Battle.Fighter]:
	var out: Array[Battle.Fighter] = []
	for f in b.fighters:
		if f.side == side and (squad == 0 or f.squad == squad):
			out.append(f)
	return out


func _put(f: Battle.Fighter, c: Vector2i) -> void:
	f.x = c.x * BattleConfig.SUB + BattleConfig.SUB / 2
	f.y = c.y * BattleConfig.SUB + BattleConfig.SUB / 2
	f.path.clear()


static func _cheb(a: Vector2i, b: Vector2i) -> int:
	return maxi(absi(a.x - b.x), absi(a.y - b.y))


func test_archers_stand_along_the_wall() -> bool:
	var w := _walled()
	var grid: BuildGrid = w[0]
	var cells: Array[Vector2i] = w[1]
	assert_eq(cells.size(), 5, "5 odcinków palisady")
	var b := Battle.for_castle_squads(grid, [[U.PEASANT, 1]], [[U.ARCHER, 7]], BotCastle.edge_road(grid.terrain), 3,
			null, [_hold(cells[2])] as Array[DefensePlan.Order])
	var on_wall := 0
	var seen := {}
	for f in _side(b, Battle.Side.DEFENDER):
		if f.wall != 0:
			on_wall += 1
			assert_true(cells.has(f.cell()), "na kratce palisady")
			assert_true(not seen.has(f.cell()), "jeden łucznik na odcinek")
			seen[f.cell()] = true
		else:
			assert_true(DefensePlan.post_problem(grid, f.cell()).is_empty(), "reszta na wolnej trawie")
	assert_eq(on_wall, 5, "5 łuczników na 5 odcinkach, 2 pod murem")
	assert_eq(_side(b, Battle.Side.DEFENDER)[0].cell(), cells[2], "pierwszy na wskazanym odcinku")
	# piechota z tym samym miejscem nie wchodzi na mur
	var foot := Battle.for_castle_squads(grid, [[U.PEASANT, 1]], [[U.AXE_WARRIOR, 3]], BotCastle.edge_road(grid.terrain), 3,
			null, [_hold(cells[2])] as Array[DefensePlan.Order])
	for f in _side(foot, Battle.Side.DEFENDER):
		assert_eq(f.wall, 0, "Obrona odcinka na murze to strzelcy; wojownik staje pod murem")
	return true


## Na murze: wręcz dosięgnie tylko atakujący po drabinie, strzały ranią o 40% mniej, zasięg +1.
func test_wall_protects_and_extends_range() -> bool:
	var w := _walled()
	var grid: BuildGrid = w[0]
	var cells: Array[Vector2i] = w[1]
	var b := Battle.for_castle_squads(grid, [[U.AXE_WARRIOR, 1], [U.ARCHER, 1]], [[U.ARCHER, 1]],
			BotCastle.edge_road(grid.terrain), 3, null, [_hold(cells[2])] as Array[DefensePlan.Order])
	var def := _side(b, Battle.Side.DEFENDER)[0]
	var axe := _side(b, Battle.Side.ATTACKER, 1)[0]
	var bow := _side(b, Battle.Side.ATTACKER, 2)[0]
	assert_true(def.wall != 0, "łucznik na murze")
	_put(axe, cells[2] + Vector2i.RIGHT)
	_put(bow, cells[2] + Vector2i.RIGHT * (UnitTypes.attack_range(U.ARCHER) + 1))
	assert_true(b._enemy_for(axe) != def, "topornik pod murem nie bierze go na cel")
	axe.climbed = true
	assert_true(b._enemy_for(axe) == def, "po drabinie już tak")
	axe.climbed = false
	assert_true(b._enemy_for(bow) == def or b._enemy_for(bow) != null, "strzelec widzi cel na murze")
	var on_wall := b.unit_damage(bow, def)
	def.wall = 0
	var on_ground := b.unit_damage(bow, def)
	def.wall = b._cells[cells[2].y * grid.terrain.size + cells[2].x]
	assert_eq(on_wall, on_ground * BattleConfig.WALL_ARROW_PERCENT / 100, "strzały: 60% obrażeń")
	# zasięg +1: łucznik atakujący stoi o 1 kratkę dalej niż zasięg łuku
	axe.hp = 0
	def.cooldown = 0
	var hp := bow.hp
	b._act(def)
	assert_true(bow.hp < hp, "łucznik na murze sięga o kratkę dalej")
	return true


## Odcinek padł: łucznik zostaje na gruzie i walczy z ziemi. Złamany oddział schodzi z muru.
func test_fall_and_step_down() -> bool:
	var w := _walled()
	var grid: BuildGrid = w[0]
	var cells: Array[Vector2i] = w[1]
	var b := Battle.for_castle_squads(grid, [[U.PEASANT, 1]], [[U.ARCHER, 2]], BotCastle.edge_road(grid.terrain), 3,
			null, [_hold(cells[2])] as Array[DefensePlan.Order])
	var a := _side(b, Battle.Side.DEFENDER)[0]
	var c := _side(b, Battle.Side.DEFENDER)[1]
	b._destroy(b.structures[a.wall])
	b._act(a)
	assert_eq(a.wall, 0, "po upadku odcinka już nie na murze")
	assert_eq(a.post, a.cell(), "broni się z gruzu")
	var wall_cell := c.cell()
	b.add_squad_morale(Battle.Side.DEFENDER, 1, -100)
	b._act(c)
	assert_eq(c.wall, 0, "złamany schodzi z muru")
	assert_true(c.cell() != wall_cell and DefensePlan.post_problem(grid, c.cell()).is_empty(), "na wolną kratkę obok")
	return true


func test_default_orders_by_class() -> bool:
	var bare := BuildGrid.new(TerrainMap.generate(WorldSeed.first_playable(1337)))
	bare.place(bare.manor_spot(64), K.MANOR, 1)
	bare.place(bare.keep_spot(64), K.KEEP, 1)
	for cls in RecruitmentConfig.CLASS_NAMES.size():
		assert_true(DefensePlan.default_order(bare, cls, 1) == null, "bez bramy i murów: przy donżonie (%d)" % cls)
	var bot := BotCastle.generate(BotCastle.seed_for(1337, 0), 0)
	var g := bot.grid
	var gate := DefensePlan.main_gate(g)
	assert_true(gate != 0, "brama zamku-celu w strefie")
	var ranged := DefensePlan.default_order(g, C.RANGED, 0)
	assert_true(ranged != null and ranged.task == T.HOLD and DefensePlan.wall_post(g, ranged.post), "strzelcy: na murze")
	var gc := g.buildings[gate].get_center()
	for id: int in g.buildings:
		if BuildingTypes.is_wall(g.kinds[id]) and DefensePlan.zone(g).has_point(g.buildings[id].position):
			assert_true((ranged.post - gc).length_squared() <= (g.buildings[id].position - gc).length_squared(),
					"odcinek najbliżej bramy")
	var light := DefensePlan.default_order(g, C.LIGHT, 0)
	assert_eq(light.post, DefensePlan.section_post(g, gate), "piechota: przy bramie od środka")
	assert_eq(DefensePlan.default_order(g, C.HEAVY, 0).post, light.post, "ciężka też")
	assert_eq(DefensePlan.default_order(g, C.FAST, 0).task, T.HOLD, "konnica w epoce I trzyma bramę")
	assert_eq(DefensePlan.default_order(g, C.FAST, 1).task, T.SORTIE, "od epoki II wypad")
	assert_true(DefensePlan.default_order(g, C.SPECIAL, 1) == null, "specjalni przy donżonie")
	# ustawione zadanie ma pierwszeństwo, Przy donżonie wyłącza domyślne
	var p := DefensePlan.new()
	p.set_task(2, T.KEEP)
	var orders := p.battle_orders([1, 2] as Array[int], [[U.ARCHER, 3], [U.ARCHER, 3]], g, 0)
	assert_true(orders[0] != null and DefensePlan.wall_post(g, orders[0].post), "bez ustawień: domyślne")
	assert_true(orders[1] == null, "Przy donżonie: bez domyślnego")
	assert_true(p.battle_orders([1] as Array[int])[0] == null, "bez danych o oddziałach: jak dawniej")
	# review #184: Przy donżonie zdejmuje stare miejsce, a Zdejmij mówi o zadaniu domyślnym
	p.set_post(3, ranged.post)
	p.set_task(3, T.KEEP)
	assert_eq(p.post_for(3), NO, "Przy donżonie: bez znacznika na mapie")
	var panel := DefensePanel.new()
	var said: Array[String] = []
	panel.changed.connect(func(t: String) -> void: said.append(t))
	panel.open(p, [[U.ARCHER, 3]], [3] as Array[int], g, 0)
	panel.activate(DefensePanel.Target.CLEAR)
	assert_eq(said[-1], "Oddział 1: domyślnie: na murze", "Zdejmij: komunikat jak opis oddziału")
	assert_eq(panel.describe(0)[1], "domyślnie: na murze", "opis")
	panel.free()
	return true


## Wypad: konnica czeka za bramą, a gdy wróg podejdzie pod bramę, wychodzi przez nią, bije go
## i po walce wraca na swoje miejsce.
func test_sortie_through_own_gate() -> bool:
	var bot := BotCastle.generate(BotCastle.seed_for(1337, 0), 0)
	var g := bot.grid
	var gate := DefensePlan.main_gate(g)
	var o := DefensePlan.Order.new()
	o.task = T.SORTIE
	o.post = DefensePlan.section_post(g, gate)
	var b := Battle.create_squads(g, bot.objective, [[U.AXE_WARRIOR, 1]], [[U.RIDER, 2]], bot.spawn, 8,
			[o] as Array[DefensePlan.Order])
	var riders := _side(b, Battle.Side.DEFENDER)
	var foe := _side(b, Battle.Side.ATTACKER)[0]
	var r := g.buildings[gate]
	var keep := DefensePlan.keep_center(g)
	# wróg daleko: konnica stoi
	_put(foe, bot.spawn)
	for t in 90:
		for f in riders:
			b._act(f)
	for f in riders:
		assert_true(_cheb(f.cell(), o.post) <= 2, "bez wroga pod bramą konnica czeka")
	# wróg pod bramą, od zewnątrz
	var outside := Vector2i(-1, -1)
	for c in Battle._ring(r):
		if b._free_ground(c) and (c - keep).length_squared() > (r.get_center() - keep).length_squared() \
				and (outside.x < 0 or (c - keep).length_squared() > (outside - keep).length_squared()):
			outside = c
	assert_true(outside.x >= 0, "jest miejsce przed bramą")
	_put(foe, outside)
	var hp := foe.hp
	var went_out := false
	for t in 20 * BattleConfig.TICK_HZ:
		for f in riders:
			b._act(f)
			if (f.cell() - keep).length_squared() > (r.get_center() - keep).length_squared() + 2:
				went_out = true
		if foe.hp < hp:
			break
	assert_true(went_out, "konnica wyszła przez własną bramę")
	assert_true(foe.hp < hp, "i bije wroga pod bramą")
	assert_eq(b.structures[gate].hp, b.structures[gate].max_hp, "bramy przy tym nie burzy")
	foe.hp = 0
	for t in 20 * BattleConfig.TICK_HZ:
		for f in riders:
			b._act(f)
	for f in riders:
		assert_true(_cheb(f.cell(), o.post) <= 2, "po walce wraca za bramę")
	return true


func test_walls_and_sortie_are_deterministic() -> bool:
	var bot := BotCastle.generate(BotCastle.seed_for(1337, 1), 1)
	var g := bot.grid
	var p := DefensePlan.new()
	var squads := [[U.ARCHER, 6], [U.AXE_WARRIOR, 6], [U.RIDER, 3]]
	var ids: Array[int] = [1, 2, 3]
	var sums: Array[int] = []
	for i in 2:
		var b := Battle.create_squads(g, bot.objective, PveWaves.squads(3), squads, bot.spawn, 21,
				p.battle_orders(ids, squads, g, 1))
		b.run()
		sums.append(b.checksum())
	assert_eq(sums[0], sums[1], "ten sam przebieg z murami, bramą i wypadem")
	return true
