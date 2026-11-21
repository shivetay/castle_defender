extends TestCase
## Epoka II i przejście I → II (#34): poziomy narastająco przez epoki, warunki przejścia
## (Dwór 5 i technologie kluczowe O1, G1, A7), budynek z poziomu 5 wchodzi w epokę II od poziomu 1,
## premie z epoki I zostają, technologie epoki II czekają na epokę i wymagania, zapis i wygląd.

const HOUR := 3600 * 1000
const DAY := 24 * HOUR
const T0 := 1_700_000_000_000
const K := BuildingTypes.Kind


func _grid() -> BuildGrid:
	return BuildGrid.new(TerrainMap.generate(1337))


func _free_cell(grid: BuildGrid, kind: int) -> Vector2i:
	var c := grid.terrain.center()
	for r in grid.terrain.size:
		for dy in range(-r, r + 1):
			for dx in range(-r, r + 1):
				var p := c + Vector2i(dx, dy)
				if grid.placement_for(p, kind) != Rect2i():
					return p
	return Vector2i(-1, -1)


func _rich_economy() -> Economy:
	var e := Economy.new(T0)
	for res in EconomyConfig.count():
		e.amounts[res] = 1000
	return e


## Zamek z Dworem na poziomie `manor` i Chatą drwala na poziomie `hut`. Zwraca [siatka, id chaty].
func _castle(manor: int, hut: int) -> Array:
	var grid := _grid()
	grid.place_kind(_free_cell(grid, K.MANOR), K.MANOR, manor)
	var hut_id := grid.place_kind(_free_cell(grid, K.LUMBER_HUT), K.LUMBER_HUT, hut)
	return [grid, hut_id]


func _research(codes: Array[String]) -> Research:
	var r := Research.new()
	for code in codes:
		r.done[code] = true
	return r


func test_levels_count_through_ages() -> bool:
	assert_eq(Ages.COUNT, 2, "MVP: epoki I i II")
	assert_eq(Ages.MAX_TOTAL_LEVEL, 10, "5 poziomów na epokę")
	assert_eq(Ages.of_level(0), 0, "plac budowy w epoce I")
	assert_eq(Ages.of_level(5), 0, "poziom 5: epoka I")
	assert_eq(Ages.of_level(6), 1, "poziom 6: epoka II")
	assert_eq(Ages.local_level(6), 1, "poziom 6 to poziom 1 epoki II")
	assert_eq(Ages.local_level(10), 5, "poziom 10 to poziom 5 epoki II")
	assert_eq(Ages.total_level(1, 3), 8, "epoka II poziom 3 = 8")
	assert_true(Ages.is_age_step(6) and not Ages.is_age_step(5) and not Ages.is_age_step(7), "tylko 5 → 6 zmienia epokę")
	assert_eq(Ages.short_level(3), "3", "epoka I bez numeru epoki")
	assert_eq(Ages.short_level(7), "II.2", "epoka II z numerem")
	assert_eq(Ages.level_status(4), "poziom 4/5", "karta epoki I")
	assert_eq(Ages.level_status(6), "poziom 1/5, epoka II", "karta epoki II")
	assert_eq(Ages.label_for_manor(5), "Epoka I · 750 r.", "Dwór 5 na pasku")
	assert_eq(Ages.label_for_manor(6), "Epoka II · 1050 r.", "Dwór po przebudowie na pasku")
	assert_true(PixelFont.text_width(Ages.label_for_manor(10)) <= PixelFont.text_width(Ages.label_for_manor(5)) + 12,
			"napis epoki II mieści się obok zegara")
	return true


func test_transition_needs_manor_5_and_key_technology() -> bool:
	assert_eq(Ages.transition_techs(0), ["O1", "G1", "A7"] as Array[String], "I → II: Obrona, Gospodarka, Atak")
	var branches: Array[int] = []
	for code in Ages.transition_techs(0):
		assert_true(TechTree.is_key(code), "%s jest technologią kluczową" % code)
		assert_eq(TechTree.age(code), 0, "%s z epoki I" % code)
		branches.append(TechTree.branch(code))
	assert_eq(branches, [TechTree.Branch.DEFENSE, TechTree.Branch.ECONOMY, TechTree.Branch.ATTACK] as Array[int],
			"po jednej z Obrony, Gospodarki i Ataku")
	var none := Research.new()
	var o1 := _research(["O1", "G1", "A7"] as Array[String])
	assert_true(not Ages.can_advance(4, o1), "Dwór 4 nie wystarcza")
	assert_true(not Ages.can_advance(5, none), "bez technologii nie wolno")
	assert_true(not Ages.can_advance(5, _research(["O1", "G1"] as Array[String])), "bez A7 nie wolno")
	assert_true(not Ages.can_advance(5, _research(["O1", "A7"] as Array[String])), "bez G1 nie wolno")
	assert_true(not Ages.can_advance(5, _research(["G1", "A7"] as Array[String])), "bez O1 nie wolno")
	assert_true(Ages.can_advance(5, o1), "Dwór 5 i trzy technologie: można przebudować")
	assert_eq(Ages.transition_missing(4, none).size(), 4, "brak Dworu 5 i trzech technologii")
	assert_true(not Ages.can_advance(6, o1), "epoka II to ostatnia epoka MVP")
	var c := _castle(5, 1)
	var grid: BuildGrid = c[0]
	var economy := _rich_economy()
	var q := BuildQueue.new()
	assert_eq(q.order_upgrade(grid, economy, grid.manor_id(), T0), BuildQueue.Result.NEEDS_TECH, "bez badań")
	assert_eq(q.order_upgrade(grid, economy, grid.manor_id(), T0, none), BuildQueue.Result.NEEDS_TECH, "bez O1")
	assert_true(q.upgrade_hint(grid, grid.manor_id(), none).contains("O1, G1, A7"), "podpowiedź mówi o technologiach")
	assert_true(PixelFont.text_width(q.upgrade_hint(grid, grid.manor_id(), none)) <= Hud.MESSAGE_MAX_WIDTH,
			"podpowiedź mieści się w komunikacie")
	assert_eq(q.order_upgrade(grid, economy, grid.manor_id(), T0, _research(["O1", "G1"] as Array[String])),
			BuildQueue.Result.NEEDS_TECH, "bez A7")
	assert_eq(economy.amounts, [1000, 1000, 1000, 1000] as Array[int], "odmowa nic nie kosztuje")
	assert_eq(q.order_upgrade(grid, economy, grid.manor_id(), T0, o1), BuildQueue.Result.OK, "z O1, G1 i A7 przebudowa rusza")
	assert_eq(economy.amounts, [0, 0, 0, 1000] as Array[int], "przebudowa mieści się w magazynie grodu")
	q.update(T0 + DAY, grid, economy, o1)
	assert_eq(grid.manor_level(), 6, "Dwór na poziomie 1 epoki II")
	assert_eq(grid.age(), 1, "zamek w epoce II")
	return true


func test_building_enters_new_age_from_max_level() -> bool:
	var c := _castle(5, 4)
	var grid: BuildGrid = c[0]
	var hut: int = c[1]
	var q := BuildQueue.new()
	var economy := _rich_economy()
	assert_eq(BuildConfig.max_level(K.LUMBER_HUT, 5), 5, "w epoce I najwyżej 5")
	assert_eq(BuildConfig.max_level(K.LUMBER_HUT, 6), 6, "po przebudowie Dworu: poziom 1 epoki II")
	assert_eq(q.order_upgrade(grid, economy, hut, T0), BuildQueue.Result.OK, "4 → 5")
	q.update(T0 + DAY, grid, economy)
	assert_eq(q.order_upgrade(grid, economy, hut, T0 + DAY), BuildQueue.Result.NEEDS_MANOR, "5 → II.1 dopiero w epoce II")
	assert_true(q.upgrade_hint(grid, hut).contains("Dwór"), "podpowiedź: przebuduj Dwór")
	grid.levels[grid.manor_id()] = 6
	assert_eq(q.order_upgrade(grid, economy, hut, T0 + DAY), BuildQueue.Result.OK, "w epoce II chata wchodzi w nową epokę")
	q.update(T0 + 2 * DAY, grid, economy)
	assert_eq(grid.levels[hut], 6, "chata na poziomie 6")
	assert_eq(Ages.of_level(grid.levels[hut]), 1, "chata w epoce II")
	assert_eq(Ages.local_level(grid.levels[hut]), 1, "od poziomu 1")
	# poziom budynku epoki I nie przeskakuje epoki: z 4 najpierw 5
	var low := _castle(6, 4)
	assert_eq(BuildQueue.new().order_upgrade(low[0] as BuildGrid, _rich_economy(), low[1] as int, T0),
			BuildQueue.Result.OK, "z 4 tylko na 5")
	return true


func test_age_ii_costs_and_times() -> bool:
	assert_eq(BuildConfig.cost(K.TOWER, 6), [240, 80, 80, 0] as Array[int], "wieża II.1: koszt poz. 1 ×2")
	assert_eq(BuildConfig.time_ms(K.TOWER, 6), BuildConfig.time_ms(K.TOWER, 1) * 2, "wieża II.1: czas poz. 1 ×2")
	assert_eq(BuildConfig.cost(K.MANOR, 6), [1000, 1000, 1000, 0] as Array[int], "przebudowa Dworu")
	assert_eq(BuildConfig.level_techs(K.MANOR, 6), ["O1", "G1", "A7"] as Array[String], "przebudowa wymaga trzech technologii")
	assert_true(BuildConfig.level_techs(K.MANOR, 7).is_empty(), "dalsze poziomy już nie")
	assert_true(BuildConfig.level_techs(K.TOWER, 6).is_empty(), "inne budynki bez technologii przejścia")
	for kind in BuildingTypes.count():
		if not BuildingTypes.has_levels(kind):
			continue
		# w epoce II czas znowu rośnie od poziomu 1 (jak w notatce Progresja budowy), ale jest dłuższy
		# niż ten sam poziom epoki I
		for local in range(2, Ages.LEVELS_PER_AGE + 1):
			var level := Ages.total_level(1, local)
			# przebudowa Dworu (II.1) to długa budowa przejścia, dalsze poziomy jak zwykle
			if kind == K.MANOR and local == 2:
				continue
			assert_true(BuildConfig.time_ms(kind, level) > BuildConfig.time_ms(kind, level - 1),
					"%s II.%d: czas rośnie" % [BuildingTypes.NAMES[kind], local])
		for local in range(1, Ages.LEVELS_PER_AGE + 1):
			if kind != K.MANOR:
				assert_true(BuildConfig.time_ms(kind, Ages.total_level(1, local)) > BuildConfig.time_ms(kind, local),
						"%s II.%d dłużej niż %d" % [BuildingTypes.NAMES[kind], local, local])
	return true


func test_bonuses_from_age_i_are_kept() -> bool:
	var five := _castle(5, 5)
	var six := _castle(6, 6)
	var g5: BuildGrid = five[0]
	var g6: BuildGrid = six[0]
	assert_eq(Economy.rates(g6), Economy.rates(g5), "chata II.1 produkuje co najmniej jak poziom 5")
	assert_eq(Recruitment.army_limit(g6), Recruitment.army_limit(g5), "limit armii z Dworu zostaje")
	assert_eq(TrapConfig.limit(6), TrapConfig.limit(5), "limit pułapek zostaje")
	for kind in [K.PALISADE, K.TOWER, K.GATE, K.MANOR]:
		assert_eq(BattleConfig.building_hp(kind, 6), BattleConfig.building_hp(kind, 5), "wytrzymałość %d zostaje" % kind)
	assert_eq(Ages.bonus_level(10), 5, "premie z poziomu 5 epoki I")
	assert_eq(BuildQueue.capacity_gain_text(K.WAREHOUSE, 6), "", "Magazyn II.1 bez „+0 miejsca” (review #261)")
	assert_true(BuildQueue.capacity_gain_text(K.WAREHOUSE, 2).begins_with(", +"), "epoka I z dopiskiem")
	return true


func test_age_ii_technologies_wait_for_age_and_requirements() -> bool:
	var r := _research(["O1"] as Array[String])
	assert_eq(r.check("A4", 1), Research.Result.MISSING_REQUIREMENTS, "A4 wymaga A1")
	assert_eq(r.check("A5", 0), Research.Result.WRONG_AGE, "epoka II niedostępna w epoce I")
	assert_eq(r.check("A5", 1), Research.Result.MISSING_REQUIREMENTS, "A5 w epoce II wymaga A4")
	r.done["A1"] = true
	r.done["A4"] = true
	assert_eq(r.check("A5", 0), Research.Result.WRONG_AGE, "nawet z A4 epoka I blokuje")
	assert_eq(r.check("A5", 1), Research.Result.OK, "epoka II i A4: można badać")
	var c := _castle(6, 1)
	assert_eq((c[0] as BuildGrid).age(), 1, "epoka zamku z Dworu")
	return true


func test_transition_keeps_castle_and_survives_save() -> bool:
	var c := _castle(5, 5)
	var grid: BuildGrid = c[0]
	var hut: int = c[1]
	var o1 := _research(["O1", "G1", "A7"] as Array[String])
	var before := grid.buildings.duplicate()
	var economy := _rich_economy()
	var q := BuildQueue.new()
	assert_eq(q.order_upgrade(grid, economy, grid.manor_id(), T0, o1), BuildQueue.Result.OK, "przebudowa")
	var saved_queue := q.save_data()
	var q2 := BuildQueue.new()
	q2.load_data(saved_queue, grid, T0)
	assert_eq(q2.orders[0].level, 6, "zlecenie przebudowy przetrwa zapis")
	q.update(T0 + DAY, grid, economy, o1)
	assert_eq(grid.buildings, before, "żaden budynek nie zniknął ani się nie przesunął")
	assert_eq(grid.levels[hut], 5, "chata zostaje na poziomie 5")
	var copy := _grid()
	copy.load_data(grid.save_data())
	assert_eq(copy.manor_level(), 6, "Dwór epoki II po odczycie")
	assert_eq(copy.age(), 1, "epoka po odczycie")
	assert_eq(copy.levels[hut], 5, "chata po odczycie")
	var bad := grid.save_data()
	((bad["buildings"] as Array)[0] as Array)[2] = 99
	var broken := _grid()
	broken.load_data(bad)
	assert_true(broken.levels.values().max() <= Ages.MAX_TOTAL_LEVEL, "poziom z zapisu najwyżej 10")
	return true


func test_age_ii_art_uses_palettes_and_is_deterministic() -> bool:
	var allowed := {}
	for col: Color in Palette.AGE_I + Palette.AGE_II:
		allowed[col.to_rgba32()] = true
	assert_eq(Palette.AGE_II.size(), 16, "16 kolorów epoki II")
	var unique := {}
	for col: Color in Palette.AGE_II:
		unique[col.to_rgba32()] = true
	assert_eq(unique.size(), 16, "kolory epoki II się nie powtarzają")
	for kind in BuildingTypes.count():
		var a := BuildingArt.make_image(kind, 6, BuildingTypes.State.INTACT, 0b1010)
		var b := BuildingArt.make_image(kind, 6, BuildingTypes.State.INTACT, 0b1010)
		assert_eq(a.get_data(), b.get_data(), "rodzaj %d epoki II powtarzalny" % kind)
		assert_eq(a.get_size(), BuildingArt.image_size(kind), "rozmiar rodzaju %d" % kind)
		for y in a.get_height():
			for x in a.get_width():
				var p := a.get_pixel(x, y)
				if p.a > 0.0:
					assert_true(allowed.has(Color(p, 1.0).to_rgba32()), "rodzaj %d: kolor z palety" % kind)
	var manor_i := BuildingArt.make_image(K.MANOR, 5, BuildingTypes.State.INTACT)
	var manor_ii := BuildingArt.make_image(K.MANOR, 6, BuildingTypes.State.INTACT)
	assert_true(manor_i.get_data() != manor_ii.get_data(), "Dwór po przebudowie wygląda inaczej")
	var textures := BuildingTextures.new()
	assert_eq(textures.draw_building(K.MANOR, 9), textures.draw_building(K.MANOR, 6), "epoka II: jeden rysunek w cache")
	assert_true(textures.draw_building(K.MANOR, 6) != textures.draw_building(K.MANOR, 5), "inny niż poziom 5")
	return true
