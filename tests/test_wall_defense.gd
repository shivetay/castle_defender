extends TestCase
## Obrona murów (#399, ADR 0017): jawne zadanie DefensePlan.Task.WALL. Strzelcy stają na wale,
## palisadzie, wieży albo Kopcu (jak Obrona odcinka na murze), piechota lekka i ciężka tylko na wale
## i palisadzie: nie strzela, bije wręcz tylko wroga, który wszedł po drabinie, i bez premii zasięgu.

const K := BuildingTypes.Kind
const U := UnitTypes.Unit
const T := DefensePlan.Task
const C := RecruitmentConfig.UnitClass
const NO := DefensePlan.NO_POST
const WALLS := preload("res://tests/test_defense_walls.gd")


func _walled() -> Array:
	return WALLS.new()._walled()


func _wall(post: Vector2i) -> DefensePlan.Order:
	var o := DefensePlan.Order.new()
	o.task = T.WALL
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


## Zamek bota z bramą, wieżą i murami w strefie obrony.
func _bot() -> BuildGrid:
	return BotCastle.generate(BotCastle.seed_for(1337, 0), 0).grid


func _first(g: BuildGrid, kind: int) -> Vector2i:
	var best := 0
	for id: int in g.buildings:
		if g.kinds[id] == kind and g.levels[id] >= 1 and DefensePlan.zone(g).has_point(g.buildings[id].position) \
				and (best == 0 or id < best):
			best = id
	return g.buildings[best].position if best != 0 else NO


func test_task_options_by_class() -> bool:
	assert_eq(DefensePlan.TASK_NAMES[T.WALL], "Obrona murów", "nazwa zadania")
	assert_eq(DefensePlan.TASK_AGE[T.WALL], 0, "od epoki I")
	assert_eq(T.WALL, 7, "na końcu enuma: stare zapisy bez przesunięcia")
	for cls: int in [C.RANGED, C.LIGHT, C.HEAVY]:
		assert_true(DefensePlan.task_allowed(T.WALL, cls, 0), "Obrona murów dla klasy %d" % cls)
		assert_eq(DefensePlan.task_options(cls, 0)[1], T.WALL, "zaraz po Obronie odcinka")
	assert_true(not DefensePlan.task_allowed(T.WALL, C.FAST, 1), "konnica bez Obrony murów")
	assert_true(not DefensePlan.task_allowed(T.WALL, C.SPECIAL, 1), "specjalni bez Obrony murów")
	return true


func test_wall_posts_by_class() -> bool:
	var g := _bot()
	var wall := _first(g, K.PALISADE)
	if wall == NO:
		wall = _first(g, K.RAMPART)
	var tower := _first(g, K.TOWER)
	assert_true(wall != NO, "zamek bota ma mur w strefie")
	assert_true(DefensePlan.wall_task_post(g, wall, C.RANGED), "strzelcy na murze")
	assert_true(DefensePlan.wall_task_post(g, wall, C.LIGHT), "piechota lekka na murze")
	assert_true(DefensePlan.wall_task_post(g, wall, C.HEAVY), "piechota ciężka na murze")
	assert_true(not DefensePlan.wall_task_post(g, wall, C.FAST), "konnica nie")
	if tower != NO:
		assert_true(DefensePlan.wall_task_post(g, tower, C.RANGED), "strzelcy na wieży")
		assert_true(not DefensePlan.wall_task_post(g, tower, C.LIGHT), "piechota nie na wieży")
	var grass := DefensePlan.default_order(g, C.LIGHT, 0).post
	assert_true(not DefensePlan.wall_task_post(g, grass, C.LIGHT), "trawa to nie mur")
	# zapis spoza gry: zła klasa albo zła kratka to brak rozkazu (zadanie domyślne)
	assert_true(DefensePlan.order_allowed(g, _wall(wall), C.LIGHT, 0), "piechota na murze dozwolona")
	assert_true(not DefensePlan.order_allowed(g, _wall(wall), C.FAST, 1), "konnica z Obroną murów odrzucona")
	assert_true(not DefensePlan.order_allowed(g, _wall(grass), C.HEAVY, 0), "Obrona murów na trawie odrzucona")
	if tower != NO:
		assert_true(not DefensePlan.order_allowed(g, _wall(tower), C.LIGHT, 0), "piechota na wieży odrzucona")
		assert_true(DefensePlan.order_allowed(g, _wall(tower), C.RANGED, 0), "strzelcy na wieży dozwoleni")
	return true


func test_battle_orders_and_default() -> bool:
	var g := _bot()
	var ranged := DefensePlan.default_order(g, C.RANGED, 0)
	assert_true(ranged != null and ranged.task == T.WALL and DefensePlan.wall_post(g, ranged.post),
			"strzelcy domyślnie: Obrona murów przy bramie")
	assert_eq(DefensePlan.default_order(g, C.LIGHT, 0).task, T.HOLD, "piechota domyślnie bez zmian")
	var p := DefensePlan.new()
	p.set_task(1, T.WALL)  # bez kratki
	p.set_task(2, T.WALL)
	p.set_post(2, ranged.post)
	p.set_task(3, T.WALL)
	p.set_post(3, ranged.post)
	var squads := [[U.AXE_WARRIOR, 3], [U.AXE_WARRIOR, 3], [U.RIDER, 2]]
	var orders := p.battle_orders([1, 2, 3] as Array[int], squads, g, 1)
	var light := DefensePlan.default_order(g, C.LIGHT, 1)
	assert_eq(orders[0].task, light.task, "bez kratki: zadanie domyślne")
	assert_eq(orders[0].post, light.post, "bez kratki: miejsce domyślne")
	assert_eq(orders[1].task, T.WALL, "piechota na murze")
	assert_eq(orders[1].post, ranged.post, "na wskazanej kratce")
	assert_eq(orders[2].task, DefensePlan.default_order(g, C.FAST, 1).task, "konnica z zapisu: domyślne")
	return true


func test_infantry_stands_on_wall_and_fights_climbers_only() -> bool:
	var w := _walled()
	var grid: BuildGrid = w[0]
	var cells: Array[Vector2i] = w[1]
	var b := Battle.for_castle_squads(grid, [[U.AXE_WARRIOR, 1]], [[U.AXE_WARRIOR, 7]],
			BotCastle.edge_road(grid.terrain), 3, null, [_wall(cells[2])] as Array[DefensePlan.Order])
	var on_wall := 0
	for f in _side(b, Battle.Side.DEFENDER):
		if f.wall != 0:
			on_wall += 1
			assert_true(cells.has(f.cell()), "na kratce palisady")
	assert_eq(on_wall, 5, "5 toporników na 5 odcinkach, 2 pod murem")
	var def := _side(b, Battle.Side.DEFENDER)[0]
	var axe := _side(b, Battle.Side.ATTACKER)[0]
	assert_eq(def.cell(), cells[2], "pierwszy na wskazanym odcinku")
	# wróg tuż pod murem, bez drabiny: topornik na murze go nie bije i nie schodzi
	_put(axe, cells[2] + Vector2i.RIGHT)
	def.cooldown = 0
	var hp := axe.hp
	b._act(def)
	assert_eq(axe.hp, hp, "bez drabiny: nie bije spod muru")
	assert_eq(def.cell(), cells[2], "nie schodzi z muru")
	assert_true(b._enemy_for(axe) != def, "atakujący spod muru go nie dosięga")
	# wróg po drabinie: bije go wręcz
	axe.climbed = true
	def.cooldown = 0
	b._act(def)
	assert_true(axe.hp < hp, "po drabinie: bije wręcz")
	assert_true(b._enemy_for(axe) == def, "wspięty dosięga obrońcy na murze")
	# bez premii zasięgu: wspięty o 2 kratki dalej jest poza zasięgiem wręcz
	axe.hp = hp
	_put(axe, cells[2] + Vector2i.RIGHT * 2)
	def.cooldown = 0
	b._act(def)
	assert_eq(axe.hp, hp, "piechota na murze bez +1 zasięgu")
	assert_eq(def.cell(), cells[2], "i nie schodzi za nim")
	return true


func test_infantry_on_wall_takes_reduced_arrows() -> bool:
	var w := _walled()
	var grid: BuildGrid = w[0]
	var cells: Array[Vector2i] = w[1]
	var b := Battle.for_castle_squads(grid, [[U.ARCHER, 1]], [[U.AXE_WARRIOR, 1]],
			BotCastle.edge_road(grid.terrain), 3, null, [_wall(cells[2])] as Array[DefensePlan.Order])
	var def := _side(b, Battle.Side.DEFENDER)[0]
	var bow := _side(b, Battle.Side.ATTACKER)[0]
	assert_true(def.wall != 0, "topornik na murze")
	var on_wall := b.unit_damage(bow, def)
	var wall_id := def.wall
	def.wall = 0
	var on_ground := b.unit_damage(bow, def)
	def.wall = wall_id
	assert_eq(on_wall, on_ground * BattleConfig.WALL_ARROW_PERCENT / 100, "strzały: 60% obrażeń")
	return true


func test_infantry_not_on_tower_and_archers_keep_range() -> bool:
	var w := _walled()
	var grid: BuildGrid = w[0]
	var cells: Array[Vector2i] = w[1]
	# strzelec z Obroną murów: jak Obrona odcinka na murze, +1 zasięgu
	var b := Battle.for_castle_squads(grid, [[U.ARCHER, 1]], [[U.ARCHER, 1]],
			BotCastle.edge_road(grid.terrain), 3, null, [_wall(cells[2])] as Array[DefensePlan.Order])
	var def := _side(b, Battle.Side.DEFENDER)[0]
	var bow := _side(b, Battle.Side.ATTACKER)[0]
	assert_true(def.wall != 0, "łucznik na murze")
	_put(bow, cells[2] + Vector2i.RIGHT * (UnitTypes.attack_range(U.ARCHER) + 1))
	def.cooldown = 0
	var hp := bow.hp
	b._act(def)
	assert_true(bow.hp < hp, "łucznik z Obroną murów sięga o kratkę dalej")
	# konnica z Obroną murów (zapis spoza gry, bitwa bez sprawdzania) nie wchodzi na mur
	var horse := Battle.for_castle_squads(grid, [[U.PEASANT, 1]], [[U.RIDER, 2]],
			BotCastle.edge_road(grid.terrain), 3, null, [_wall(cells[2])] as Array[DefensePlan.Order])
	for f in _side(horse, Battle.Side.DEFENDER):
		assert_eq(f.wall, 0, "konnica pod murem")
	return true


func test_wall_defense_is_deterministic() -> bool:
	var bot := BotCastle.generate(BotCastle.seed_for(1337, 1), 1)
	var g := bot.grid
	var post := DefensePlan.default_order(g, C.RANGED, 1).post
	var p := DefensePlan.new()
	p.set_task(1, T.WALL)
	p.set_post(1, post)
	p.set_task(2, T.WALL)
	p.set_post(2, post)
	var squads := [[U.ARCHER, 4], [U.AXE_WARRIOR, 6]]
	var ids: Array[int] = [1, 2]
	var sums: Array[int] = []
	for i in 2:
		var b := Battle.create_squads(g, bot.objective, PveWaves.squads(3), squads, bot.spawn, 21,
				p.battle_orders(ids, squads, g, 1))
		b.run()
		sums.append(b.checksum())
	assert_eq(sums[0], sums[1], "ten sam seed i układ: ten sam przebieg")
	return true


func test_panel_wall_task() -> bool:
	var w := _walled()
	var grid: BuildGrid = w[0]
	var cells: Array[Vector2i] = w[1]
	var p := DefensePlan.new()
	var panel := DefensePanel.new()
	var said: Array[String] = []
	panel.changed.connect(func(t: String) -> void: said.append(t))
	panel.open(p, [[U.AXE_WARRIOR, 3]], [5] as Array[int], grid, 0)
	panel.activate(DefensePanel.Target.TASK)  # Obrona odcinka
	panel.activate(DefensePanel.Target.TASK)  # Obrona murów
	assert_eq(p.order_for(5).task, T.WALL, "drugie zadanie piechoty to Obrona murów")
	var grass := cells[2] + Vector2i.LEFT * 2
	if not DefensePlan.post_problem(grid, grass).is_empty():
		grass = cells[2] + Vector2i.RIGHT * 2
	assert_eq(panel.tap(grid, grass), "Obrona murów: dotknij wału lub palisady", "trawa: podpowiedź")
	assert_eq(p.post_for(5), NO, "trawa nie ustawia miejsca")
	assert_eq(panel.tap(grid, cells[1]), "Oddział 1: na murze, %s" % BuildingTypes.NAMES[K.PALISADE], "mur")
	assert_eq(p.post_for(5), cells[1], "miejsce na murze")
	assert_eq(panel.describe(0)[1], "Na murze", "opis")
	# zmiana na Patrol: kratka muru nie jest miejscem patrolu, więc znika
	panel.activate(DefensePanel.Target.TASK)
	assert_eq(p.order_for(5).task, T.PATROL, "dalej Patrol")
	assert_eq(p.post_for(5), NO, "mur nie zostaje punktem patrolu")
	panel.free()
	# strzelcy: podpowiedź z wieżą i Kopcem, domyślny opis
	var archers := DefensePanel.new()
	archers.open(DefensePlan.new(), [[U.ARCHER, 3]], [6] as Array[int], grid, 0)
	assert_eq(archers.describe(0)[1], "domyślnie: Obrona murów", "strzelcy domyślnie")
	archers.activate(DefensePanel.Target.TASK)
	archers.activate(DefensePanel.Target.TASK)
	assert_eq(archers.tap(grid, grass), "Obrona murów: dotknij muru, wieży lub kopca", "podpowiedź strzelców")
	for text: String in ["Obrona murów: dotknij muru, wieży lub kopca", "Obrona murów: dotknij wału lub palisady",
			"Oddział 1: domyślnie: Obrona murów"]:
		assert_true(PixelFont.text_width(text) <= Hud.MESSAGE_MAX_WIDTH, "mieści się w 320 px: %s" % text)
	archers.free()
	return true
