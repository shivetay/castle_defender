extends TestCase
## Komenda umocnień i sprawdzanie szczelności (#199).

const VIEW := Vector2(320, 180)
const MAIN := preload("res://scripts/main.gd")
const K := BuildingTypes.Kind


func _rich_economy() -> Economy:
	var e := Economy.new(0)
	for res in EconomyConfig.count():
		e.amounts[res] = 1_000_000
	return e


func _free_cell(grid: BuildGrid, kind: int) -> Vector2i:
	for y in range(2, grid.terrain.size - 4):
		for x in range(2, grid.terrain.size - 4):
			var c := Vector2i(x, y)
			if grid.placement_for(c, kind).has_area():
				return c
	return Vector2i(-1, -1)


func test_seal_house_is_buildable_defense() -> bool:
	assert_eq(BuildingTypes.NAMES[K.SEAL_HOUSE], "Komenda umocnień", "nazwa")
	assert_eq(BuildingTypes.SHORT_NAMES[K.SEAL_HOUSE], "Komenda", "krótka")
	assert_eq(BuildingTypes.size_of(K.SEAL_HOUSE), Vector2i(2, 2), "2×2")
	assert_eq(BuildingTypes.category(K.SEAL_HOUSE), BuildingTypes.Category.DEFENSE, "Umocnienia")
	assert_true(BuildingTypes.BUILD_BAR.has(K.SEAL_HOUSE), "na pasku budowy")
	assert_eq(BuildingTypes.Kind.SEAL_HOUSE, 24, "za Strażnicą (stare zapisy bez zmian)")
	assert_eq(BuildConfig.required_tech(K.SEAL_HOUSE), "", "bez technologii")
	assert_true(BuildConfig.is_unlocked(K.SEAL_HOUSE, Research.new()), "od razu dostępna")
	assert_true(BuildingArt.make_image(K.SEAL_HOUSE, 1, 0).get_used_rect().has_area(), "rysunek")
	var e := _rich_economy()
	var grid := BuildGrid.new(TerrainMap.generate(1337))
	var cell := _free_cell(grid, K.SEAL_HOUSE)
	assert_true(cell.x >= 0, "jest miejsce")
	var q := BuildQueue.new()
	assert_eq(q.order_build(grid, e, cell, K.SEAL_HOUSE, 0), BuildQueue.Result.OK, "zlecenie")
	assert_eq(grid.kinds[q.placed_id], K.SEAL_HOUSE, "plac Komendy")
	return true


func test_seal_check_countdown_and_gaps() -> bool:
	var check := SealCheck.new()
	var grid := BuildGrid.new(TerrainMap.generate(1337))
	var o := Vector2i(-1, -1)
	for y in range(2, grid.terrain.size - 6):
		for x in range(2, grid.terrain.size - 8):
			var c := Vector2i(x, y)
			if grid.can_place(Rect2i(c, Vector2i(8, 3))):
				o = c + Vector2i(0, 1)
				break
		if o.x >= 0:
			break
	assert_true(o.x >= 0, "pas pod linię")
	grid.place(Rect2i(o, Vector2i.ONE), K.PALISADE, 1)
	grid.place(Rect2i(o + Vector2i(3, 0), Vector2i(3, 1)), K.GATE, 1)
	var gap := o + Vector2i(1, 0)
	assert_true(grid.is_wall_gap(gap, K.PALISADE), "jest luka do bramy")
	assert_true(grid.fort_gaps().has(gap), "fort_gaps widzi lukę")
	assert_eq(grid.wall_kind_for_gap(gap), K.PALISADE, "uszczelnienie palisadą")
	assert_true(check.start(1000), "start Sprawdź")
	assert_true(check.is_busy(), "trwa")
	assert_true(not check.start(1500), "drugie Sprawdź zablokowane")
	assert_eq(check.remaining_ms(1000 + SealCheck.DURATION_MS - 1), 1, "prawie koniec")
	assert_true(not check.update(1000 + SealCheck.DURATION_MS - 1, grid), "jeszcze nie")
	assert_true(check.update(1000 + SealCheck.DURATION_MS, grid), "koniec")
	assert_true(check.revealed and not check.is_busy(), "ujawnione")
	assert_true(check.gaps.has(gap), "luka na liście")
	grid.place(Rect2i(gap, Vector2i.ONE), K.PALISADE, 1)
	check.prune(grid)
	assert_true(not check.gaps.has(gap), "po wypełnieniu znika")
	return true


func test_seal_card_buttons() -> bool:
	var b := Hud.content_bounds(VIEW, Rect2())
	var card := Hud.card_rects(VIEW, false, false, true)
	assert_eq(card.size(), 5, "5 przycisków")
	assert_true(card[0].position.x >= b.x and card[-1].end.x <= b.y, "mieści się na 320 px")
	assert_eq(Hud.card_buttons(false, false, true), [
			Hud.CardButton.UPGRADE, Hud.CardButton.DEMOLISH, Hud.CardButton.CHECK, Hud.CardButton.SEAL,
			Hud.CardButton.CLOSE] as Array[int], "kolejność")
	assert_eq(Hud.target_at(card[2].get_center(), VIEW, b.y, false, true, false, false, false, true),
			Hud.Target.CARD + Hud.CardButton.CHECK, "Sprawdź")
	assert_eq(Hud.target_at(card[3].get_center(), VIEW, b.y, false, true, false, false, false, true),
			Hud.Target.CARD + Hud.CardButton.SEAL, "Domknij")
	for button in Hud.card_buttons(false, false, true):
		assert_true(PixelFont.text_width(Hud.card_label(button)) <= Hud.BUTTON_SIZE.x - 2,
				"„%s” mieści się" % Hud.card_label(button))
	var check := SealCheck.new()
	assert_eq(MAIN.seal_card_info(check, 0), MAIN.SEAL_HOUSE_INFO, "przed Sprawdź")
	check.start(0)
	assert_eq(MAIN.seal_card_info(check, 0), "Sprawdzanie: 1:00", "odliczanie")
	assert_eq(SealCheck.DURATION_MS, 60_000, "ok. 1 minuta")
	return true


func test_seal_orders_gap_via_queue() -> bool:
	var grid := BuildGrid.new(TerrainMap.generate(1337))
	var e := _rich_economy()
	var q := BuildQueue.new()
	var o := Vector2i(-1, -1)
	for y in range(2, grid.terrain.size - 6):
		for x in range(2, grid.terrain.size - 8):
			var c := Vector2i(x, y)
			if grid.can_place(Rect2i(c, Vector2i(8, 3))):
				o = c + Vector2i(0, 1)
				break
		if o.x >= 0:
			break
	grid.place(Rect2i(o, Vector2i.ONE), K.PALISADE, 1)
	grid.place(Rect2i(o + Vector2i(3, 0), Vector2i(3, 1)), K.GATE, 1)
	var gap := o + Vector2i(1, 0)
	var kind := grid.wall_kind_for_gap(gap)
	assert_eq(q.order_build(grid, e, gap, kind, 0), BuildQueue.Result.OK, "Domknij = zlecenie odcinka")
	assert_eq(grid.buildings[q.placed_id].position, gap, "plac w luce")
	assert_eq(grid.levels[q.placed_id], 0, "jeszcze budowa")
	return true
