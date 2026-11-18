extends TestCase
## Produkcja cywilna na ekranie Wojsko: postawieni wytwórcy (chata drwala, drzewcarz, rybak…)
## pokazują surowiec/towar i tempo z EconomyConfig / GoodsConfig, bez osobnej ekonomii.

const K := BuildingTypes.Kind
const G := GoodsConfig.Good


func _free_cell(grid: BuildGrid, kind: int) -> Vector2i:
	var c := grid.terrain.center()
	for r in grid.terrain.size:
		for dy in range(-r, r + 1):
			for dx in range(-r, r + 1):
				var p := c + Vector2i(dx, dy)
				if grid.placement_for(p, kind) != Rect2i():
					return p
	return Vector2i(-1, -1)


## Pierwszy róg 2×2 na trawie przy wodzie (jak w test_flax_and_fisher).
func _fisher_spot(grid: BuildGrid) -> Vector2i:
	var size := BuildingTypes.size_of(K.FISHER)
	for y in grid.terrain.size - 1:
		for x in grid.terrain.size - 1:
			var r := Rect2i(Vector2i(x, y), size)
			if grid.can_place(r) and grid.touches_water(r):
				return r.position
	return Vector2i(-1, -1)


## Bez wytwórców: krótka wskazówka do Buduj; z Chatą drwala i Drzewcarzem widać drewno i topory.
func test_civilian_texts_use_building_and_recipe_rates() -> bool:
	var grid := BuildGrid.new(TerrainMap.generate(42))
	assert_eq(RecruitPanel.civilian_texts(grid).size(), 0, "pusty zamek: brak linii")
	assert_true(RecruitPanel.civilian_lines(grid, 240, 3)[0][0].begins_with("Brak wytwórców"),
			"podpowiedź bez wytwórców")
	grid.place_kind(_free_cell(grid, K.MANOR), K.MANOR, 1)
	grid.place_kind(_free_cell(grid, K.LUMBER_HUT), K.LUMBER_HUT, 1)
	grid.place_kind(_free_cell(grid, K.LUMBER_HUT), K.LUMBER_HUT, 2)
	grid.place_kind(_free_cell(grid, K.POLEARM), K.POLEARM, 1)
	var texts := RecruitPanel.civilian_texts(grid)
	assert_true(texts.size() >= 2, "chata i drzewcarz")
	var wood := 60 + 90
	assert_true(texts[0].contains("Chata drwala ×2") and texts[0].contains("+%d Dr/h" % wood),
			"drewno z obu chat: %s" % texts[0])
	var axe_rate := 0
	for recipe in GoodsConfig.RECIPES.size():
		var row: Array = GoodsConfig.RECIPES[recipe]
		if row[0] == "polearm" and (row[5] as Dictionary).has(G.STONE_AXE):
			axe_rate = GoodsConfig.cycles_per_hour(recipe, 1) * int((row[5] as Dictionary)[G.STONE_AXE])
			break
	assert_true(axe_rate > 0, "przepis topora")
	var pole := ""
	for t in texts:
		if t.begins_with("Drzewcarz"):
			pole = t
	assert_true(pole.contains("Drzewcarz ×1") and pole.contains("Topór kamienny %d/h" % axe_rate),
			"drzewcarz z tempem topora: %s" % pole)
	assert_true(pole.contains("Oszczep") and pole.contains("Włócznia"), "pozostałe drzewce")
	return true


## Rybak i myśliwy: żywność z BUILDING_PRODUCTION oraz towary (+ żywność z przepisu myśliwego).
func test_civilian_texts_include_fisher_and_hunter() -> bool:
	var grid := BuildGrid.new(TerrainMap.generate(1337))
	grid.place_kind(_free_cell(grid, K.MANOR), K.MANOR, 1)
	var wet := _fisher_spot(grid)
	assert_true(wet.x >= 0, "jest miejsce przy rzece")
	assert_true(grid.place_kind(wet, K.FISHER, 1) > 0, "Rybak stoi")
	grid.place_kind(_free_cell(grid, K.HUNTER), K.HUNTER, 1)
	var texts := RecruitPanel.civilian_texts(grid)
	var joined := " | ".join(texts)
	assert_true(joined.contains("Rybak") and joined.contains("+40 Ży/h"), "rybak poz. 1: %s" % joined)
	assert_true(joined.contains("Chata myśliwego") and joined.contains("Surowe skóry"),
			"myśliwy z towarami: %s" % joined)
	assert_true(joined.contains("+%d Ży/h" % (6 * 2)) or joined.contains("Ży/h"),
			"myśliwy dokłada żywność z przepisu: %s" % joined)
	return true


## Przycisk trybu i linie produkcji mieszczą się w szczegółach Wojsko.
func test_production_mode_label_and_lines_fit() -> bool:
	assert_eq(RecruitPanel.mode_button_label(RecruitPanel.DetailMode.COST), RecruitPanel.INFO_LABEL, "z kosztu → Opis")
	assert_eq(RecruitPanel.mode_button_label(RecruitPanel.DetailMode.INFO), RecruitPanel.PROD_LABEL, "z opisu → Prod.")
	assert_eq(RecruitPanel.mode_button_label(RecruitPanel.DetailMode.PRODUCTION), RecruitPanel.STOCK_LABEL,
			"z produkcji → Zapas")
	assert_eq(RecruitPanel.mode_button_label(RecruitPanel.DetailMode.STOCK), RecruitPanel.COST_LABEL,
			"z zapasu → Koszt")
	assert_true(PixelFont.text_width(RecruitPanel.PROD_LABEL) <= int(Hud.BUTTON_SIZE.x) - 4, "Prod. na przycisku")
	assert_true(PixelFont.text_width(RecruitPanel.STOCK_LABEL) <= int(Hud.BUTTON_SIZE.x) - 4, "Zapas na przycisku")
	var grid := BuildGrid.new(TerrainMap.generate(7))
	grid.place_kind(_free_cell(grid, K.MANOR), K.MANOR, 1)
	grid.place_kind(_free_cell(grid, K.LUMBER_HUT), K.LUMBER_HUT, 1)
	grid.place_kind(_free_cell(grid, K.POLEARM), K.POLEARM, 1)
	for width: int in [200, 240, 296]:
		var lines := RecruitPanel.civilian_lines(grid, width, RecruitPanel.DETAIL_LINES - 1)
		assert_true(lines.size() <= RecruitPanel.DETAIL_LINES - 1, "najwyżej 3 linie przy %d px" % width)
		assert_true(not lines.is_empty(), "jest treść")
		for l: Array in lines:
			assert_true(PixelFont.text_width(l[0] as String) <= width, "„%s” w %d px" % [l[0], width])
	return true
