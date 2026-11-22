extends TestCase
## Ustawienia obrony (#19): miejsca załogi w strefie wokół donżonu, zapis układu (wersja 8),
## rozstawienie obrońców w bitwie według układu i ekran edycji (pasek oddziałów, dotknięcia mapy).
## Zadania obrony (#20) mają osobne testy w test_defense_tasks.gd.

const K := BuildingTypes.Kind
const U := UnitTypes.Unit
const NO := DefensePlan.NO_POST
const VIEW := Vector2(320, 180)


func _castle(world_seed: int = 1337) -> BuildGrid:
	var grid := BuildGrid.new(TerrainMap.generate(WorldSeed.first_playable(world_seed)))
	grid.place(grid.manor_spot(64), K.MANOR, 1)
	grid.place(grid.keep_spot(64), K.KEEP, 1)
	return grid


static func _cheb(a: Vector2i, b: Vector2i) -> int:
	return maxi(absi(a.x - b.x), absi(a.y - b.y))


## Wolne kratki strefy obrony co najmniej `min_dist` od środka donżonu, w stałej kolejności.
func _free_cells(grid: BuildGrid, min_dist: int) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	var zone := DefensePlan.zone(grid)
	var c := DefensePlan.keep_center(grid)
	for y in range(zone.position.y, zone.end.y):
		for x in range(zone.position.x, zone.end.x):
			var p := Vector2i(x, y)
			if _cheb(p, c) >= min_dist and DefensePlan.post_problem(grid, p).is_empty():
				out.append(p)
	return out


func _fighters(b: Battle, side: int, squad: int) -> Array[Battle.Fighter]:
	var out: Array[Battle.Fighter] = []
	for f in b.fighters:
		if f.side == side and f.squad == squad:
			out.append(f)
	return out


func test_posts_stand_on_free_ground_near_the_keep() -> bool:
	var grid := _castle()
	var c := DefensePlan.keep_center(grid)
	var zone := DefensePlan.zone(grid)
	assert_eq(zone.size, Vector2i.ONE * (2 * DefensePlan.RADIUS + 1), "strefa: %d kratek wokół donżonu" % DefensePlan.RADIUS)
	assert_true(zone.has_point(c), "donżon w środku strefy")
	assert_eq(DefensePlan.post_problem(grid, Vector2i(64, 3)), "Poza mapą", "poza mapą")
	assert_eq(DefensePlan.post_problem(grid, c + Vector2i(DefensePlan.RADIUS + 1, 0)),
			"Za daleko od donżonu: najwyżej %d kratek" % DefensePlan.RADIUS, "za strefą")
	assert_eq(DefensePlan.post_problem(grid, grid.buildings[grid.manor_id()].position), "Tu stoi %s" % BuildingTypes.NAMES[K.MANOR],
			"nie na budynku")
	var water := false
	for y in range(zone.position.y, zone.end.y):
		for x in range(zone.position.x, zone.end.x):
			if grid.terrain.get_tile(Vector2i(x, y)) == TerrainMap.Tile.WATER and not water:
				water = true
				assert_eq(DefensePlan.post_problem(grid, Vector2i(x, y)), "Załoga nie stanie w wodzie", "nie w wodzie")
	assert_true(_free_cells(grid, 3).size() > 20, "w strefie jest wolna trawa")
	assert_true(DefensePlan.zone(BuildGrid.new(grid.terrain)) == Rect2i(), "bez donżonu nie ma strefy")
	return true


func test_plan_round_trip_and_prune() -> bool:
	var r := Recruitment.new()
	var a := r.add_squad(U.PEASANT, 5)
	var b := r.add_squad(U.ARCHER, 3)
	var p := DefensePlan.new()
	p.set_post(b, Vector2i(30, 31))
	p.set_post(a, Vector2i(28, 29))
	p.set_post(99, Vector2i(1, 1))
	var d := p.to_dict()
	assert_eq(d, {"orders": [[a, 0, 28, 29, []], [b, 0, 30, 31, []], [99, 0, 1, 1, []]], "tower_priority": 0, "traps": [],
			"commander": -1},
			"zapis w kolejności id")
	var q := DefensePlan.from_dict(JSON.parse_string(JSON.stringify(d)) as Dictionary)
	assert_eq(q.to_dict(), d, "odczyt z JSON (liczby jako float)")
	assert_eq(q.squad_at(Vector2i(30, 31)), b, "oddział na posterunku")
	assert_eq(q.squad_at(Vector2i(5, 5)), 0, "pusta kratka")
	q.prune(r)
	assert_eq(q.post_for(99), NO, "posterunek rozwiązanego oddziału znika")
	assert_eq(q.battle_posts(r.battle_ids()), [Vector2i(28, 29), Vector2i(30, 31)] as Array[Vector2i],
			"posterunki w kolejności oddziałów bitwy")
	q.clear_post(a)
	assert_eq(q.battle_posts(r.battle_ids()), [NO, Vector2i(30, 31)] as Array[Vector2i], "bez posterunku: przy donżonie")
	assert_eq(DefensePlan.from_dict({"orders": [[0, 0, 1, 1, []], [3], "x", [4, 9, 1, 1, []]]}).orders.size(), 0,
			"złe wpisy pominięte")
	return true


func test_save_keeps_defense_and_migrates() -> bool:
	var grid := _castle()
	var economy := Economy.new(0)
	var r := Recruitment.new()
	var id := r.add_squad(U.PEASANT, 4)
	var p := DefensePlan.new()
	p.set_post(id, Vector2i(20, 21))
	p.set_post(id + 7, Vector2i(2, 2))
	var d := SaveGame.to_dict(1337, grid, economy, BuildQueue.new(), null, null, r, 0, null, 0, p)
	assert_eq(int(d["version"]), SaveGame.FORMAT_VERSION, "bieżąca wersja formatu")
	var s := SaveGame.from_dict(JSON.parse_string(JSON.stringify(d)) as Dictionary, 0)
	assert_eq(s.defense.post_for(id), Vector2i(20, 21), "posterunek po odczycie")
	assert_eq(s.defense.post_for(id + 7), NO, "posterunek oddziału spoza armii odrzucony")
	var old := d.duplicate(true)
	old.erase("defense")
	old["version"] = 6
	var m := SaveGame.from_dict(old, 0)
	assert_true(m != null and m.defense.orders.is_empty(), "zapis z wersji 6: cała załoga przy donżonie")
	var v7 := d.duplicate(true)
	v7["version"] = 7
	v7["defense"] = {"posts": [[id, 20, 21]]}
	var n := SaveGame.from_dict(JSON.parse_string(JSON.stringify(v7)) as Dictionary, 0)
	assert_eq(n.defense.order_for(id).task, DefensePlan.Task.HOLD, "zapis z wersji 7: posterunek to Obrona odcinka")
	assert_eq(n.defense.post_for(id), Vector2i(20, 21), "na tej samej kratce")
	assert_eq(n.defense.tower_priority, DefensePlan.TowerPriority.NEAREST, "wieże biją najbliższego")
	return true


## Kryterium #19: układ obrony jest używany w bitwie. Oddział z posterunkiem staje przy nim,
## oddział bez posterunku przy donżonie.
func test_battle_places_defenders_on_posts() -> bool:
	var grid := _castle()
	var spawn := BotCastle.edge_road(grid.terrain)
	var keep := DefensePlan.keep_center(grid)
	var post := _free_cells(grid, 7)[0]
	var defenders := [[U.PEASANT, 4], [U.ARCHER, 3]]
	var b := Battle.for_castle_squads(grid, [[U.PEASANT, 2]], defenders, spawn, 5, null, DefensePlan.hold_orders([NO, post] as Array[Vector2i]))
	for f in _fighters(b, Battle.Side.DEFENDER, 2):
		assert_true(_cheb(f.post, post) <= 1, "łucznicy wokół posterunku")
		assert_true(_cheb(f.cell(), post) <= 1, "i tam zaczynają bitwę")
	for f in _fighters(b, Battle.Side.DEFENDER, 1):
		assert_true(_cheb(f.post, keep) <= 3, "Chłopi bez posterunku przy donżonie")
	var plain := Battle.for_castle_squads(grid, [[U.PEASANT, 2]], defenders, spawn, 5)
	for f in _fighters(plain, Battle.Side.DEFENDER, 2):
		assert_true(_cheb(f.post, keep) <= 3, "bez układu wszyscy przy donżonie")
	return true


## Bez posterunków bitwa przebiega dokładnie tak jak przed #19 (te same sumy kontrolne), a ten sam
## układ i ten sam seed dają ten sam przebieg.
func test_posts_are_deterministic() -> bool:
	var grid := _castle()
	var spawn := BotCastle.edge_road(grid.terrain)
	var attackers := PveWaves.squads(2)
	var defenders := [[U.PEASANT, 6], [U.AXE_WARRIOR, 4]]
	var none := Battle.for_castle_squads(grid, attackers, defenders, spawn, 77)
	var empty := Battle.for_castle_squads(grid, attackers, defenders, spawn, 77, null, DefensePlan.hold_orders([NO, NO] as Array[Vector2i]))
	none.run()
	empty.run()
	assert_eq(empty.checksum(), none.checksum(), "puste posterunki: przebieg jak dawniej")
	var cells := _free_cells(grid, 5)
	var posts: Array[Vector2i] = [cells[0], cells[cells.size() - 1]]
	var a := Battle.for_castle_squads(grid, attackers, defenders, spawn, 77, null, DefensePlan.hold_orders(posts))
	var c := Battle.for_castle_squads(grid, attackers, defenders, spawn, 77, null, DefensePlan.hold_orders(posts.duplicate()))
	a.run()
	c.run()
	assert_eq(a.checksum(), c.checksum(), "ten sam układ i seed: ten sam przebieg")
	assert_eq(a.winner, c.winner, "i ten sam wynik")
	assert_true(a.checksum() != none.checksum(), "posterunki zmieniają przebieg")
	return true


## Sąsiednie posterunki nie stawiają dwóch jednostek na jednej kratce.
func test_neighbour_posts_do_not_stack() -> bool:
	var grid := _castle()
	var cells := _free_cells(grid, 4)
	var p := cells[0]
	var q := p + Vector2i.RIGHT if DefensePlan.post_problem(grid, p + Vector2i.RIGHT).is_empty() else p + Vector2i.DOWN
	var b := Battle.for_castle_squads(grid, [[U.PEASANT, 1]], [[U.PEASANT, 8], [U.ARCHER, 8]],
			BotCastle.edge_road(grid.terrain), 3, null, DefensePlan.hold_orders([p, q] as Array[Vector2i]))
	var seen := {}
	for f in b.fighters:
		if f.side == Battle.Side.DEFENDER:
			assert_true(not seen.has(f.post), "kratka %s zajęta raz" % str(f.post))
			seen[f.post] = true
	assert_eq(seen.size(), 16, "16 obrońców na 16 kratkach")
	return true


func test_panel_taps_set_and_select_posts() -> bool:
	var grid := _castle()
	var cells := _free_cells(grid, 3)
	var p := DefensePlan.new()
	var panel := DefensePanel.new()
	var ids: Array[int] = [4, 9]
	panel.open(p, [[U.PEASANT, 5], [U.ARCHER, 3]], ids)
	assert_eq(panel.selected_id(), 4, "na start pierwszy oddział")
	assert_eq(panel.describe(0), ["1. Chłop ×5", DefensePanel.AT_KEEP] as Array[String], "opis: przy donżonie")
	assert_eq(panel.tap(grid, cells[0]), "Oddział 1: obrona odcinka", "dotknięcie trawy")
	assert_eq(p.post_for(4), cells[0], "posterunek oddziału 1")
	assert_eq(panel.describe(0)[1], "Obrona odcinka", "opis: zadanie")
	assert_eq(panel.tap(grid, grid.buildings[grid.manor_id()].position), "Tu stoi %s" % BuildingTypes.NAMES[K.MANOR], "nie na budynku")
	panel.activate(DefensePanel.Target.SQUAD + 1)
	assert_eq(panel.selected_id(), 9, "kafelek wybiera oddział 2")
	panel.tap(grid, cells[1])
	assert_eq(panel.tap(grid, cells[0]), "Oddział 1: Obrona odcinka", "dotknięcie cudzego posterunku")
	assert_eq(panel.selected_id(), 4, "wybiera jego oddział")
	assert_eq(p.post_for(9), cells[1], "a posterunek oddziału 2 zostaje")
	panel.activate(DefensePanel.Target.CLEAR)
	assert_eq(p.post_for(4), NO, "Zdejmij: oddział wraca pod donżon")
	assert_eq(p.post_for(9), cells[1], "inne posterunki zostają")
	var empty := DefensePanel.new()
	empty.open(DefensePlan.new(), [], [] as Array[int])
	assert_eq(empty.tap(grid, cells[0]), "Najpierw wyszkol wojsko: Koszary i Wojsko", "bez wojska")
	panel.free()
	empty.free()
	return true


## Pasek oddziałów na ekranie 320 px: przyciski i kafelki się nie nakładają, a więcej oddziałów,
## niż mieści pasek, przewija przycisk Dalej.
func test_squad_bar_fits_and_pages() -> bool:
	var b := Hud.content_bounds(VIEW, Rect2())
	var fit := DefensePanel.tiles_fit(b.x, b.y)
	assert_eq(fit, 6, "6 kafelków na 320 px")
	assert_true(DefensePanel.tile_rect(VIEW, b.x, fit - 1).end.x <= b.y, "ostatni kafelek w granicy treści")
	assert_true(DefensePanel.tile_rect(VIEW, b.x, 0).position.y > Hud.column_rect(b.y, DefensePanel.COLUMN.size() - 1).end.y,
			"pasek pod kolumną przycisków")
	for label: String in DefensePanel.LABELS + [DefensePanel.MORE_LABEL]:
		assert_true(PixelFont.text_width(label) <= Hud.BUTTON_SIZE.x - 2, "„%s” mieści się na przycisku" % label)
	assert_true(PixelFont.text_width("8. Strzelec z łukiem refleksyjnym ×10  Obrona odcinka") <= b.y - b.x - 4,
			"najdłuższy opis mieści się w pasku")
	assert_eq(DefensePanel.visible_squads(4, fit, 0), [0, 1, 2, 3] as Array[int], "mało oddziałów: wszystkie")
	assert_eq(DefensePanel.visible_squads(8, fit, 0), [0, 1, 2, 3, 4] as Array[int], "dużo: miejsce na Dalej")
	assert_eq(DefensePanel.next_first(8, fit, 0), 5, "Dalej: następna strona")
	assert_eq(DefensePanel.visible_squads(8, fit, 5), [5, 6, 7] as Array[int], "druga strona")
	assert_eq(DefensePanel.next_first(8, fit, 5), 0, "po ostatniej znów pierwsza")
	var more := DefensePanel.tile_rect(VIEW, b.x, 5).get_center()
	assert_eq(DefensePanel.target_at(more, VIEW, b.x, b.y, 8, 0), DefensePanel.Target.MORE, "kafelek Dalej")
	assert_eq(DefensePanel.target_at(more, VIEW, b.x, b.y, 8, 5), DefensePanel.Target.NONE, "za ostatnim oddziałem pusto")
	assert_eq(DefensePanel.target_at(DefensePanel.tile_rect(VIEW, b.x, 1).get_center(), VIEW, b.x, b.y, 8, 5),
			DefensePanel.Target.SQUAD + 6, "kafelek na drugiej stronie")
	assert_eq(DefensePanel.target_at(Hud.column_rect(b.y, DefensePanel.COLUMN.size() - 1).get_center(), VIEW, b.x, b.y, 8, 0),
			DefensePanel.Target.BACK, "Gotowe na dole kolumny")
	assert_true(Hud.column_rect(b.y, DefensePanel.COLUMN.size() - 1).end.y < DefensePanel.tile_rect(VIEW, b.x, 0).position.y,
			"kolumna nie wchodzi na pasek oddziałów")
	assert_eq(DefensePanel.target_at(Hud.column_rect(b.y, 0).get_center(), VIEW, b.x, b.y, 8, 0),
			DefensePanel.Target.TASK, "Zadanie na górze")
	assert_eq(DefensePanel.target_at(Vector2(150, 80), VIEW, b.x, b.y, 8, 0), DefensePanel.Target.NONE, "mapa")
	var panel := DefensePanel.new()
	var army := []
	var ids: Array[int] = []
	for i in 8:
		army.append([U.PEASANT, 1])
		ids.append(i + 1)
	panel.open(DefensePlan.new(), army, ids)
	panel.select(6)
	assert_eq(panel.first, 5, "wybór oddziału z drugiej strony przewija pasek")
	panel.free()
	return true


## Review #179: złamany oddział z wysuniętego posterunku wycofuje się pod donżon (#98), a nie zostaje
## na posterunku. Posterunek to miejsce walki, nie schronienie.
func test_routed_outpost_falls_back_to_keep() -> bool:
	var grid := _castle()
	var keep := DefensePlan.keep_center(grid)
	var post := _free_cells(grid, 8)[0]
	var b := Battle.for_castle_squads(grid, [[U.PEASANT, 1]], [[U.PEASANT, 3], [U.ARCHER, 3]],
			BotCastle.edge_road(grid.terrain), 9, null, DefensePlan.hold_orders([NO, post] as Array[Vector2i]))
	for f in _fighters(b, Battle.Side.DEFENDER, 2):
		assert_true(_cheb(f.post, post) <= 1, "łucznicy zaczynają na posterunku")
		assert_true(_cheb(f.rally, keep) <= 3, "a wycofują się pod donżon")
	var other := Battle.for_castle_squads(grid, [[U.PEASANT, 1]], [[U.PEASANT, 3], [U.ARCHER, 3]],
			BotCastle.edge_road(grid.terrain), 9, null, DefensePlan.hold_orders([NO, post] as Array[Vector2i]))
	for f in _fighters(other, Battle.Side.DEFENDER, 2):
		f.rally = f.post
	assert_true(other.checksum() != b.checksum(), "kratka wycofania wchodzi do sumy kontrolnej (review #180)")
	for f in _fighters(b, Battle.Side.DEFENDER, 1):
		assert_eq(f.rally, f.post, "oddział przy donżonie wycofuje się tam, gdzie stoi")
	for f in _fighters(b, Battle.Side.ATTACKER, 1):
		assert_eq(f.rally, f.post, "atakujący wycofuje się na swoje miejsce startu")
	b.add_squad_morale(Battle.Side.DEFENDER, 2, -100)
	var archers := _fighters(b, Battle.Side.DEFENDER, 2)
	var start := _cheb(archers[0].cell(), keep)
	var t := 0
	while t < 60 * BattleConfig.TICK_HZ and not archers.all(func(f: Battle.Fighter) -> bool: return b.cornered(f)):
		b.step()
		t += 1
	assert_true(t < 60 * BattleConfig.TICK_HZ, "złamani łucznicy doszli pod donżon w 60 s")
	for f in archers:
		assert_true(_cheb(f.cell(), keep) <= 3 and _cheb(f.cell(), keep) < start,
				"złamany łucznik pod donżonem (jest %s, donżon %s)" % [f.cell(), keep])
	return true
