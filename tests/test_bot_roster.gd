extends TestCase
## Zamki-boty (#26, #230): 20 na epokę I–II, lista wspólna dla graczy, rosnąca trudność w epoce,
## każdy zamek kompletny i deterministyczny, odblokowywanie po kolei, ekran wyboru celu i zapis celu.

const K := BuildingTypes.Kind
const U := UnitTypes.Unit
const VIEW := Vector2(320, 180)


func _kinds(bot: BotCastle) -> Dictionary:
	var out := {}
	for id: int in bot.grid.kinds:
		out[bot.grid.kinds[id]] = int(out.get(bot.grid.kinds[id], 0)) + 1
	return out


## Każdy zamek ma donżon jako cel, Dwór, bramę w pierścieniu, wejście na drodze i załogę.
func test_every_castle_is_complete() -> bool:
	assert_eq(BotRoster.COUNT_PER_AGE, 20, "20 zamków na epokę")
	assert_eq(BotRoster.COUNT, 40, "epoki I–II: 40 zamków")
	for age in BotRoster.AGES:
		var n := 0
		for i in BotRoster.COUNT:
			if BotRoster.age_of(i) == age:
				n += 1
		assert_eq(n, 20, "epoka %d: 20 zamków" % age)
	assert_eq(BotRoster.NAMES.size(), BotRoster.COUNT, "nazwa dla każdego")
	var seeds := {}
	for i in BotRoster.COUNT:
		var bot := BotRoster.generate(i)
		var kinds := _kinds(bot)
		assert_eq(bot.index, i, "numer zamku")
		assert_true(bot.objective != 0 and bot.grid.kinds[bot.objective] == K.KEEP, "%d: donżon jako cel" % i)
		assert_eq(int(kinds.get(K.MANOR, 0)), 1, "%d: Dwór" % i)
		assert_true(int(kinds.get(K.GATE, 0)) >= 1, "%d: brama" % i)
		var inner := BotRoster.inner_wall_of(BotRoster.structure_of(i))
		assert_true(int(kinds.get(inner, 0)) > 8, "%d: pierścień %s" % [i, BuildingTypes.NAMES[inner]])
		assert_true(bot.grid.terrain.get_tile(bot.spawn) == TerrainMap.Tile.PATH, "%d: wejście na drodze" % i)
		assert_true(BotRoster.defender_count(i) > 0, "%d: załoga" % i)
		seeds[BotRoster.seed_of(i)] = true
	assert_eq(seeds.size(), BotRoster.COUNT, "każdy zamek ma inny seed")
	return true


## Ten sam numer zamku daje zawsze ten sam zamek i załogę (u każdego gracza, bez seeda świata).
func test_castles_are_deterministic_and_shared() -> bool:
	for i: int in [0, 7, 19, 20, 39]:
		var a := BotRoster.generate(i)
		var b := BotRoster.generate(i)
		assert_eq(a.grid.save_data(), b.grid.save_data(), "%d: ten sam zamek" % i)
		assert_eq(a.defenders, b.defenders, "%d: ta sama załoga" % i)
		assert_eq(a.spawn, b.spawn, "%d: to samo wejście" % i)
	return true


func _power(i: int) -> int:
	var power := 0
	for d: Array in BotRoster.defenders(i):
		var row: Array = UnitTypes.UNITS[int(d[0])]
		power += int(d[1]) * int(row[3]) * int(row[4])
	return power


## Trudność w epoce nie maleje z rangą: poziom budynków, wieże, liczba obrońców i ich łączna siła
## (HP × atak). Epoka II zaczyna od połowy krzywej konstrukcji epoki I (#230).
func test_difficulty_grows() -> bool:
	for i in BotRoster.COUNT:
		if BotRoster.rank_of(i) == 0:
			continue
		var s := BotRoster.structure_of(i)
		var p := BotRoster.structure_of(i - 1)
		assert_true(s >= p, "%d: konstrukcja nie słabnie" % i)
		assert_true(BotRoster.level_of(s) >= BotRoster.level_of(p), "%d: poziom nie maleje" % i)
		assert_true(BotRoster.towers_of(s) >= BotRoster.towers_of(p), "%d: wieże nie maleją" % i)
		assert_true(BotRoster.defender_count(i) > BotRoster.defender_count(i - 1), "%d: więcej obrońców" % i)
		assert_true(_power(i) > _power(i - 1), "%d: silniejsza załoga" % i)
	assert_eq(BotRoster.level_of(BotRoster.structure_of(0)), 1, "pierwszy zamek na poziomie 1")
	assert_eq(BotRoster.level_of(BotRoster.structure_of(19)), BuildingTypes.MAX_LEVEL, "ostatni epoki I na poziomie 5")
	assert_eq(BotRoster.level_of(BotRoster.structure_of(BotRoster.COUNT - 1)), BuildingTypes.MAX_LEVEL,
			"ostatni epoki II na poziomie 5")
	assert_eq(BotRoster.defenders(0), [[U.PEASANT, 4]], "pierwszy zamek: 4 Chłopów")
	var first_ii := BotRoster.first_of_age(1)
	assert_eq(BotRoster.structure_of(first_ii), BotRoster.AGE_II_STRUCTURE_FROM, "epoka II od połowy krzywej")
	assert_eq(BotRoster.level_of(BotRoster.structure_of(first_ii)), 3, "pierwszy zamek epoki II na poziomie 3")
	assert_true(_power(first_ii) > _power(BotRoster.AGE_II_BASE_RANK), "epoka II mocniejsza od samego tła")
	return true


## Zamki 1–15 epoki I mają tę samą załogę co przed #230 (stare wiersze bez jednostek epoki II).
func test_age_one_garrisons_unchanged() -> bool:
	assert_eq(BotRoster.defenders(14), [[U.PEASANT, 12], [U.AXE_WARRIOR, 12], [U.ARCHER, 12],
			[U.JAVELINEER, 10], [U.SHIELDBEARER, 9], [U.RIDER, 6], [U.FIRE_RAISER, 3]], "zamek 15")
	assert_eq(BotRoster.defenders(7), [[U.PEASANT, 11], [U.AXE_WARRIOR, 9], [U.ARCHER, 8],
			[U.JAVELINEER, 5], [U.SHIELDBEARER, 2]], "zamek 8")
	for i in 15:
		assert_eq(BotRoster.structure_of(i), i, "%d: konstrukcja = numer" % i)
	return true


## Epoki: zamki epoki I bronią tylko jednostki epoki I, epoki II mają też jednostki epoki II.
## Od siły 3 budynki rekrutacji, siły 1, 3, …, 9 na wale zamiast palisady, od siły 10 zewnętrzny wał.
func test_ages_recruit_buildings_and_outer_wall() -> bool:
	for i in BotRoster.COUNT:
		var max_age := 0
		for d: Array in BotRoster.defenders(i):
			max_age = maxi(max_age, int((UnitTypes.UNITS[int(d[0])] as Array)[2]))
		assert_eq(max_age, BotRoster.age_of(i), "%d: epoka jednostek = epoka zamku" % i)
		var bot := BotRoster.generate(i)
		var kinds := _kinds(bot)
		var s := BotRoster.structure_of(i)
		for kind in BotRoster.recruit_buildings(s):
			assert_true(kinds.has(kind), "%d: stoi %s" % [i, BuildingTypes.NAMES[kind]])
		assert_eq(kinds.has(K.RAMPART), s >= BotRoster.OUTER_WALL_FROM or BotRoster.inner_wall_of(s) == K.RAMPART,
				"%d: wał (pierścień albo zewnętrzny)" % i)
		assert_eq(kinds.has(K.PALISADE), BotRoster.inner_wall_of(s) == K.PALISADE, "%d: palisada" % i)
	assert_eq(BotRoster.inner_wall_of(0), K.PALISADE, "zamek 1: palisada")
	assert_eq(BotRoster.inner_wall_of(1), K.RAMPART, "zamek 2: wał")
	assert_eq(BotRoster.inner_wall_of(BotRoster.OUTER_WALL_FROM + 1), K.PALISADE, "z zewnętrznym wałem: palisada")
	assert_true(BotRoster.recruit_buildings(2).is_empty() and BotRoster.recruit_buildings(3).has(K.BARRACKS),
			"Koszary od zamku 4")
	return true


## Najtrudniejszy zamek da się zaatakować: bitwa kończy się w limicie czasu i daje ten sam wynik.
func test_hardest_castle_battle_runs() -> bool:
	var bot := BotRoster.generate(BotRoster.COUNT - 1)
	assert_eq(BotRoster.age_of(bot.index), 1, "ostatni zamek z epoki II")
	var army := [[U.AXE_WARRIOR, 10], [U.ARCHER, 10], [U.RIDER, 6]]
	var seed_value := PixelCanvas.hash2(bot.seed_value, bot.index, 0xa77) & 0x7fffffff
	var a := Battle.create_squads(bot.grid, bot.objective, army, bot.defenders, bot.spawn, seed_value)
	a.run()
	var b := Battle.create_squads(bot.grid, bot.objective, army, bot.defenders, bot.spawn, seed_value)
	b.run()
	assert_true(a.winner != Battle.Winner.NONE, "bitwa się kończy")
	assert_eq(a.checksum(), b.checksum(), "deterministycznie")
	return true


## Odblokowanie po kolei: dostępne są zdobyte i następny; epoka II po 20 zamkach epoki I; po
## wszystkich ostatni dalej.
func test_unlocking() -> bool:
	assert_true(BotRoster.is_unlocked(0, 0) and not BotRoster.is_unlocked(1, 0), "nowy gracz: tylko pierwszy")
	assert_true(BotRoster.is_unlocked(3, 3) and not BotRoster.is_unlocked(4, 3), "po 3 zdobytych: czwarty")
	assert_true(BotRoster.is_beaten(2, 3) and not BotRoster.is_beaten(3, 3), "zdobyte to te przed celem")
	assert_true(not BotRoster.is_unlocked(20, 19) and BotRoster.is_unlocked(20, 20), "epoka II po 20 zamkach")
	assert_eq(BotRoster.last_unlocked(55), BotRoster.COUNT - 1, "więcej zdobyć niż zamków: ostatni")
	assert_true(BotRoster.is_unlocked(BotRoster.COUNT - 1, BotRoster.COUNT), "po wszystkich dalej można atakować")
	return true


## Ekran wyboru: siatka 5×4 mieści się między paskami, dotknięcia trafiają w kafelki i przyciski,
## a opis każdego zamku mieści się na 320 px (#312: od razu pełna lista, bez zwartego panelu).
func test_picker_layout() -> bool:
	var b := Hud.content_bounds(VIEW, Rect2())
	var tiles := BotPicker.tile_rects(b.x, b.y)
	assert_eq(tiles.size(), BotRoster.COUNT_PER_AGE, "kafelek na zamek epoki")
	var tabs := BotPicker.tab_rects(b.y)
	assert_eq(tabs.size(), BotRoster.AGES, "zakładka na epokę")
	for age in tabs.size():
		var t := tabs[age]
		assert_true(t.size.x >= 12 and t.size.y >= 12, "zakładka ≥ 12×12")
		assert_true(t.end.x <= b.y and t.end.y <= BotPicker.GRID_Y, "zakładka nad siatką")
		assert_true(t.position.x > b.x + PixelFont.text_width(BotPicker.TITLE), "zakładka obok tytułu")
		assert_eq(BotPicker.target_at(t.get_center(), VIEW, b.x, b.y), BotPicker.Target.TAB + age, "zakładka %d" % age)
	assert_true(tabs[0].end.x < tabs[1].position.x, "zakładki osobno")
	for r in tiles:
		assert_true(r.size.x >= 12 and r.size.y >= 12, "cel ≥ 12×12")
		assert_true(r.position.x >= b.x and r.end.x <= b.y, "w poziomie")
	assert_true(tiles[-1].end.y < BotPicker.DETAIL_Y, "siatka nad opisem")
	assert_eq(BotPicker.target_at(tiles[7].get_center(), VIEW, b.x, b.y),
			BotPicker.Target.TILE + 7, "kafelek 8")
	assert_eq(BotPicker.target_at(BotPicker.plan_rect(VIEW, b.y).get_center(), VIEW, b.x, b.y),
			BotPicker.Target.PLAN, "Planuj")
	assert_eq(BotPicker.target_at(BotPicker.close_rect(VIEW, b.y).get_center(), VIEW, b.x, b.y),
			BotPicker.Target.CLOSE, "Wróć")
	var width := int(b.y - b.x)
	for i in BotRoster.COUNT:
		var lines := BotPicker.detail_lines(i, 3, width)
		assert_true(lines.size() <= 4, "%d: najwyżej 4 linie" % i)
		var bottom := BotPicker.DETAIL_Y + lines.size() * (PixelFont.LINE + 1)
		assert_true(bottom <= BotPicker.plan_rect(VIEW, b.y).position.y, "%d: opis nad przyciskami" % i)
		for line: Array in lines:
			assert_true(PixelFont.text_width(line[0] as String) <= width, "„%s” mieści się" % line[0])
	assert_eq((BotPicker.detail_lines(9, 3, width)[-1] as Array)[0], BotPicker.LOCKED_TEXT, "zablokowany ma podpowiedź")
	assert_eq((BotPicker.detail_lines(24, 24, width)[0] as Array)[0], "5. " + BotRoster.NAMES[24], "numer w epoce")
	assert_eq((BotPicker.detail_lines(24, 24, width)[1] as Array)[0], "Trudność 5/20, epoka II, cel", "trudność w epoce")
	return true


## Zakładki epok: siatka otwiera się na epoce celu, zakładka przełącza epokę i zaznaczenie, kafelek
## wybiera zamek tej epoki, a komunikat po zdobyciu podaje numer w epoce.
func test_picker_age_tabs() -> bool:
	var picker := BotPicker.new()
	picker.open(22, 21)
	assert_eq(picker.age_tab, 1, "cel z epoki II: zakładka II")
	picker._activate(BotPicker.Target.TAB)
	assert_eq(picker.age_tab, 0, "zakładka I")
	assert_eq(picker.selected, 19, "w epoce I najwyższy odblokowany")
	picker._activate(BotPicker.Target.TILE + 3)
	assert_eq(picker.selected, 3, "kafelek 4 epoki I")
	picker._activate(BotPicker.Target.TAB + 1)
	assert_eq(picker.selected, 22, "w epoce II najwyższy odblokowany")
	picker._activate(BotPicker.Target.TILE + 3)
	assert_eq(picker.selected, 23, "kafelek 4 epoki II")
	picker.open(4, 4)
	picker._activate(BotPicker.Target.TAB + 1)
	assert_eq(picker.selected, 20, "zablokowana epoka: jej pierwszy zamek")
	picker._activate(BotPicker.Target.PLAN)
	assert_eq(BotPicker.unlock_text(1), "Odblokowany: 2. Bobrowa Wola", "komunikat")
	assert_eq(BotPicker.unlock_text(20), "Odblokowany: 1. %s (epoka II)" % BotRoster.NAMES[20], "nowa epoka")
	picker.free()
	return true


## Planuj od razu emituje cel (bez rozwijania panelu, #312).
func test_picker_plan_emits() -> bool:
	var picker := BotPicker.new()
	var chosen := [-1]
	picker.target_chosen.connect(func(i: int) -> void: chosen[0] = i)
	picker.open(2, 1)
	assert_eq(picker.selected, 1, "wybrany cel z zapisu")
	picker._activate(BotPicker.Target.PLAN)
	assert_eq(chosen[0], 1, "Planuj: start wyprawy")
	picker.open(0, 5)
	assert_eq(picker.selected, 0, "zablokowany cel wraca na ostatni dostępny")
	chosen[0] = -1
	picker._activate(BotPicker.Target.PLAN)
	assert_eq(chosen[0], 0, "Planuj na odblokowanym")
	picker.selected = 5
	chosen[0] = -1
	picker._activate(BotPicker.Target.PLAN)
	assert_eq(chosen[0], -1, "Planuj na zablokowanym nic nie robi")
	picker.free()
	return true


## Cel Wyprawy w zapisie; cel spoza odblokowanych (np. ręcznie zmieniony zapis) wraca na ostatni dostępny.
func test_target_survives_save() -> bool:
	var grid := BuildGrid.new(TerrainMap.generate(1337))
	var d := SaveGame.to_dict(1337, grid, Economy.new(0), BuildQueue.new(), null, null, null, 0, null, 5, null, 3)
	var s := SaveGame.from_dict(JSON.parse_string(JSON.stringify(d)) as Dictionary, 0)
	assert_eq(s.bots_beaten, 5, "zdobyte")
	assert_eq(s.attack_target, 3, "cel")
	d["attack"]["target"] = 12
	s = SaveGame.from_dict(JSON.parse_string(JSON.stringify(d)) as Dictionary, 0)
	assert_eq(s.attack_target, 5, "zablokowany cel wraca na ostatni dostępny")
	(d["attack"] as Dictionary).erase("target")
	s = SaveGame.from_dict(JSON.parse_string(JSON.stringify(d)) as Dictionary, 0)
	assert_eq(s.attack_target, 5, "stary zapis: najwyższy dostępny zamek")
	return true


## Pierścień wokół donżonu jest szczelny: od wejścia nie da się dojść do donżonu bez burzenia
## budynku (w zamku 1 droga przecinała palisadę i zostawała luka, przez którą wchodzili Chłopi).
func test_inner_ring_is_sealed() -> bool:
	for i in BotRoster.COUNT:
		var bot := BotRoster.generate(i)
		assert_true(not _reaches_keep(bot), "%d: do donżonu bez wyłomu" % i)
	return true


## Czy pieszy dojdzie od wejścia do kratki przy donżonie po trawie i drodze (bez budynków i wody).
func _reaches_keep(bot: BotCastle) -> bool:
	var g := bot.grid
	var near := g.buildings[bot.objective].grow(1)
	var seen := {bot.spawn: true}
	var todo: Array[Vector2i] = [bot.spawn]
	while not todo.is_empty():
		var c: Vector2i = todo.pop_back()
		if near.has_point(c) and g.building_at(c) == 0:
			return true
		for d: Vector2i in [Vector2i.UP, Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT]:
			var n := c + d
			if seen.has(n) or not g.terrain.in_bounds(n) or g.building_at(n) != 0 \
					or g.terrain.get_tile(n) == TerrainMap.Tile.WATER:
				continue
			seen[n] = true
			todo.append(n)
	return false


## Odcinek mimo drogi stawia tylko generator i tylko umocnienie: na drodze tak, na wodzie i dla innych
## rodzajów nie. Zewnętrzny wał zostawia przejście na wprost bramy.
func test_wall_on_road_and_outer_gap() -> bool:
	var grid := BuildGrid.new(TerrainMap.generate(1337))
	var road := Vector2i(-1, -1)
	var water := Vector2i(-1, -1)
	for y in grid.terrain.size:
		for x in grid.terrain.size:
			var c := Vector2i(x, y)
			if road.x < 0 and grid.terrain.get_tile(c) == TerrainMap.Tile.PATH:
				road = c
			if water.x < 0 and grid.terrain.get_tile(c) == TerrainMap.Tile.WATER:
				water = c
	assert_true(road.x >= 0 and water.x >= 0, "mapa ma drogę i wodę")
	assert_eq(grid.place_on_any_ground(Rect2i(road, Vector2i.ONE), K.LUMBER_HUT), 0, "chata na drodze: nie")
	assert_eq(grid.place_on_any_ground(Rect2i(water, Vector2i.ONE), K.PALISADE), 0, "na wodzie: nie")
	assert_true(grid.place_on_any_ground(Rect2i(road, Vector2i.ONE), K.PALISADE) != 0, "palisada na drodze: tak")
	assert_eq(grid.place_on_any_ground(Rect2i(road, Vector2i.ONE), K.PALISADE), 0, "na zajętej kratce: nie")
	var bot := BotRoster.generate(BotRoster.OUTER_WALL_FROM)
	var gates := 0
	var gate := Rect2i()
	for id: int in bot.grid.kinds:
		if bot.grid.kinds[id] == K.GATE:
			gates += 1
			gate = bot.grid.buildings[id]
	assert_eq(gates, 1, "jedna brama")
	# kratki zewnętrznego wału na wprost bramy (2 kratki dalej od pierścienia) są wolne
	var dy := -2 if bot.spawn.y < gate.position.y else 2
	for i in 3:
		var c := gate.position + Vector2i(i, dy)
		assert_true(bot.grid.building_at(c) == 0 or bot.grid.kinds[bot.grid.building_at(c)] != K.RAMPART,
				"przejście w zewnętrznym wale %d" % i)
	return true
