extends TestCase
## Prowadzenie do 5 fal (#185): cele w kolejności, spójność ścieżki z wymaganiami gry, napisy w HUD
## i balans fal z umocnieniami i zadaniami domyślnymi.

const K := BuildingTypes.Kind
const U := UnitTypes.Unit
const G := TutorialGoals.Check
const W := Battle.Winner


func _castle(world_seed: int = 1337) -> BuildGrid:
	var grid := BuildGrid.new(TerrainMap.generate(WorldSeed.first_playable(world_seed)))
	grid.place(grid.manor_spot(64), K.MANOR, 1)
	grid.place(grid.keep_spot(64), K.KEEP, 1)
	return grid


## Brama na drodze w strefie obrony, najbliżej donżonu (co najmniej 4 kratki), i po 2 odcinki
## palisady z każdej strony: umocnienia ze ścieżki samouczka.
func _fortify(grid: BuildGrid) -> bool:
	var keep := DefensePlan.keep_center(grid)
	var zone := DefensePlan.zone(grid)
	var best := Rect2i()
	var best_d := -1
	for y in range(zone.position.y, zone.end.y):
		for x in range(zone.position.x, zone.end.x):
			var c := Vector2i(x, y)
			if grid.terrain.get_tile(c) != TerrainMap.Tile.PATH:
				continue
			var r := grid.placement_for(c, K.GATE)
			var d := (r.get_center() - keep).length_squared()
			if r.has_area() and d >= 16 and (best_d < 0 or d < best_d):
				best = r
				best_d = d
	if not best.has_area():
		return false
	grid.place(best, K.GATE, 1)
	var along := Vector2i.RIGHT if best.size.x > 1 else Vector2i.DOWN
	for k in range(1, 3):
		for p: Vector2i in [best.position - along * k, best.end - Vector2i.ONE + along * k]:
			if grid.can_place(Rect2i(p, Vector2i.ONE)):
				grid.place(Rect2i(p, Vector2i.ONE), K.PALISADE, 1)
	return true


## Spełnia cel w stanie gry (do przejścia całej ścieżki w teście).
func _satisfy(g: Array, grid: BuildGrid, research: Research, r: Recruitment) -> void:
	match int(g[1]):
		G.BUILT:
			var kind := int(g[2])
			if kind == K.GATE:
				_fortify(grid)
			else:
				grid.place(grid.spot_near(grid.buildings[grid.manor_id()].position, kind, 40), kind, 1)
		G.RESEARCHED:
			research.done[g[2] as String] = true
		G.ARMY:
			r.add_squad(U.PEASANT, int(g[3]) - r.army_size())
		G.UNIT:
			while r.army_of(int(g[2])) < int(g[3]):
				r.add_squad(int(g[2]), mini(RecruitmentConfig.SQUAD_SIZE, int(g[3]) - r.army_of(int(g[2]))))
		G.WALLS:
			var c := DefensePlan.keep_center(grid)
			var n := 0
			for y in range(-9, 10):
				for x in range(-9, 10):
					var p := c + Vector2i(x, y)
					if n < int(g[3]) and grid.can_place(Rect2i(p, Vector2i.ONE)):
						grid.place(Rect2i(p, Vector2i.ONE), K.PALISADE, 1)
						n += 1
		G.MANOR:
			while grid.manor_level() < int(g[3]):
				grid.upgrade(grid.manor_id())


func test_goals_lead_through_all_waves() -> bool:
	var grid := _castle()
	var research := Research.new()
	var r := Recruitment.new()
	assert_eq(TutorialGoals.text(0, grid, research, r), "Postaw Koszary (Buduj, Wojsko)", "pierwszy cel")
	var seen: Array[String] = []
	var cleared := 0
	var guard := 0
	while cleared < PveWaves.COUNT and guard < 200:
		guard += 1
		var i := TutorialGoals.current(cleared, grid, research, r)
		var shown := TutorialGoals.text(cleared, grid, research, r)
		seen.append(shown)
		if i < 0:
			assert_eq(shown, "Oblężenie: fala %d z %d" % [cleared + 1, PveWaves.COUNT], "po celach Oblężenie")
			cleared += 1
		else:
			_satisfy(TutorialGoals.GOALS[i], grid, research, r)
			assert_true(TutorialGoals.current(cleared, grid, research, r) != i, "cel „%s” spełniony" % shown)
	assert_eq(cleared, PveWaves.COUNT, "ścieżka prowadzi do końca")
	assert_eq(TutorialGoals.text(PveWaves.COUNT, grid, research, r), "", "po 5. fali bez celów")
	assert_eq(seen.size(), TutorialGoals.GOALS.size() + PveWaves.COUNT, "każdy cel raz, potem Oblężenie przed każdą falą")
	# kryterium #185: ścieżka wymaga co najmniej tych rzeczy
	for kind: int in [K.HUNTER, K.BARRACKS, K.GATE]:
		assert_true(grid.has_built(kind), "%s na ścieżce" % BuildingTypes.NAMES[kind])
	assert_true(research.done.size() >= 5, "kilka badań")
	assert_true(r.army_size() >= 20, "wojsko")
	return true


## Cele z późniejszych fal nie pojawiają się wcześniej, a wcześniejsze wracają, gdy przestaną być
## spełnione (np. straty w armii).
func test_goals_follow_the_wave() -> bool:
	var grid := _castle()
	var research := Research.new()
	var r := Recruitment.new()
	grid.place(grid.spot_near(grid.buildings[grid.manor_id()].position, K.BARRACKS, 40), K.BARRACKS, 1)
	var id := r.add_squad(U.PEASANT, 6)
	assert_eq(TutorialGoals.text(0, grid, research, r), "Oblężenie: fala 1 z 5", "przed falą 1 nic więcej")
	assert_eq(TutorialGoals.text(1, grid, research, r), "Wyszkol 10 żołnierzy (Wojsko)", "po fali 1 kolejny cel")
	r.apply_losses([id] as Array[int], [2] as Array[int])
	assert_eq(TutorialGoals.text(0, grid, research, r), "Wyszkol 6 żołnierzy (Wojsko)", "po stratach znów szkolenie")
	return true


## Ścieżka jest wykonalna w kolejności: technologia przed swoim budynkiem i jednostką, zależności technologii
## i budynek badań wcześniej, wytwórca towaru przed jednostką, która go zużywa.
func test_path_respects_game_requirements() -> bool:
	var done_tech := {}
	var built := {K.MANOR: true, K.KEEP: true}
	for g: Array in TutorialGoals.GOALS:
		match int(g[1]):
			G.RESEARCHED:
				var code := g[2] as String
				assert_true(TechTree.has(code), "%s w drzewku" % code)
				for req in TechTree.requires(code):
					assert_true(done_tech.has(req), "%s: najpierw %s" % [code, req])
				assert_true(built.has(ResearchConfig.research_building(code)), "%s: budynek badań wcześniej" % code)
				assert_eq(TechTree.age(code), 0, "%s z epoki I" % code)
				done_tech[code] = true
			G.BUILT:
				var kind := int(g[2])
				var tech := BuildConfig.required_tech(kind)
				assert_true(tech.is_empty() or done_tech.has(tech), "%s: najpierw %s" % [BuildingTypes.NAMES[kind], tech])
				built[kind] = true
			G.UNIT:
				var unit := int(g[2])
				var tech := UnitTypes.required_tech(unit)
				assert_true(tech.is_empty() or done_tech.has(tech), "%s: technologia wcześniej" % UnitTypes.unit_name(unit))
				assert_true(built.has(UnitTypes.building(unit)), "%s: budynek rekrutacji wcześniej" % UnitTypes.unit_name(unit))
				var goods: Dictionary = UnitTypes.goods_cost(unit)
				for good: int in goods:
					var made := false
					for kind: int in built:
						var producer: String = GoodsConfig.PRODUCER_KINDS.get(kind, "")
						for row: Array in GoodsConfig.RECIPES:
							if row[0] == producer and (row[5] as Dictionary).has(good):
								made = true
					assert_true(made, "%s: %s robi budynek ze ścieżki" % [UnitTypes.unit_name(unit), GoodsConfig.NAMES[good]])
	return true


func test_goal_texts_fit_the_hud() -> bool:
	var b := Hud.content_bounds(Vector2(320, 180), Rect2())
	var room := int(Hud.goal_rect(b.x, b.y).size.x) - PixelFont.text_width(Hud.GOAL_PREFIX) - 8
	for g: Array in TutorialGoals.GOALS:
		assert_true(PixelFont.text_width(g[4] as String) <= room, "„%s” mieści się" % (g[4] as String))
	assert_true(PixelFont.text_width("Oblężenie: fala 5 z 5") <= room, "Oblężenie mieści się")
	var reward := PveWaves.reward(PveWaves.COUNT - 1)
	assert_eq(TutorialGoals.done_message(reward, 0), "Samouczek ukończony! +%s" % Hud.cost_text(reward), "koniec z nagrodą")
	assert_true(TutorialGoals.done_message(reward, 3).contains("polegli: 3"), "i z poległymi (review #189)")
	for fallen: int in [0, 99]:
		assert_true(PixelFont.text_width(TutorialGoals.done_message(reward, fallen)) <= Hud.MESSAGE_MAX_WIDTH,
				"komunikat końca mieści się (polegli: %d)" % fallen)
	assert_true(not Hud.goal_rect(b.x, b.y).intersects(Hud.column_rect(b.y, 0, true)), "pasek celu obok kolumny przycisków")
	return true


## Kryterium #185: obrona ≈ EXPECTED_DEFENCE z bramą i palisadą oraz zadaniami domyślnymi (#184) wygrywa
## każdą falę, bez ręcznych ustawień.
func test_waves_pass_with_fortifications_and_default_tasks() -> bool:
	for world_seed: int in [1337, 42, 9001]:
		var grid := _castle(world_seed)
		assert_true(_fortify(grid), "seed %d: brama na drodze" % world_seed)
		var spawn := BotCastle.edge_road(grid.terrain)
		for w in PveWaves.COUNT:
			var squads: Array = PveWaves.EXPECTED_DEFENCE[w]
			var ids: Array[int] = []
			for i in squads.size():
				ids.append(i + 1)
			var b := Battle.for_castle_squads(grid, PveWaves.squads(w), squads, spawn, PveWaves.battle_seed(world_seed, w),
					null, DefensePlan.new().battle_orders(ids, squads, grid, 0))
			assert_eq(b.run(), W.DEFENDER, "seed %d, fala %d: obrona z umocnieniami wygrywa" % [world_seed, w + 1])
	return true
