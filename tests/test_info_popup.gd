extends TestCase
## Okienka z informacją (po teście na telefonie): dotknięcie surowca na górnym pasku pokazuje
## produkcję, a dotknięcie licznika armii na ekranie Wojsko mówi, skąd jest limit i jak go podnieść.

const K := BuildingTypes.Kind
const R := EconomyConfig.Res
const VIEW := Vector2(320, 180)


func _spot(grid: BuildGrid, kind: int) -> Vector2i:
	return grid.spot_around(Rect2i(grid.terrain.center(), Vector2i.ONE), kind, 20).position


func test_resource_info_shows_production() -> bool:
	var grid := BuildGrid.new(TerrainMap.generate(1337))
	grid.place_kind(_spot(grid, K.MANOR), K.MANOR, 1)
	grid.place_kind(_spot(grid, K.LUMBER_HUT), K.LUMBER_HUT, 1)
	grid.place_kind(_spot(grid, K.LUMBER_HUT), K.LUMBER_HUT, 2)
	var amounts: Array[int] = [400, 1000, 100, 50]
	var wood := InfoText.resource(R.WOOD, grid, null, amounts)
	assert_eq(wood[0], "Zapas: 400 z 1000 (magazyn)", "zapas")
	assert_eq(wood[1], "Produkcja: +%d na godzinę" % Economy.rates(grid)[R.WOOD], "produkcja")
	assert_true(wood.has("- gród: +20"), "gród")
	assert_true(wood.has("- Chata drwala ×2: +150"), "chaty z poziomami 1 i 2")
	assert_true(wood.has("Więcej daje: Chata drwala (postaw albo ulepsz)"), "jak zdobyć więcej")
	assert_true(" ".join(InfoText.resource(R.STONE, grid, null, amounts)).contains("Magazyn pełny:"), "pełny magazyn")
	var r := Research.new()
	r.done["G1"] = true
	assert_true(" ".join(InfoText.resource(R.WOOD, grid, r, amounts)).contains("- badania: +"), "premia z badań")
	var gold := InfoText.resource(R.GOLD, grid, null, amounts)
	assert_eq(gold[0], "Zapas: 50, bez limitu magazynu", "złoto bez magazynu")
	assert_true(gold.has(InfoText.LOOT_LINE), "złoto z łupu")
	return true


func test_army_info_explains_limit() -> bool:
	var grid := BuildGrid.new(TerrainMap.generate(1337))
	grid.place_kind(_spot(grid, K.MANOR), K.MANOR, 1)
	var rec := Recruitment.new()
	var text := " | ".join(InfoText.army(grid, rec))
	assert_true(text.contains("- Dwór poz. 1: +10") and text.contains("- Koszary: brak"), "bez Koszar: %s" % text)
	grid.place_kind(_spot(grid, K.BARRACKS), K.BARRACKS, 1)
	text = " | ".join(InfoText.army(grid, rec))
	assert_true(text.contains("limit 12") and text.contains("- Koszary poz. 1: +2"), "Dwór i Koszary: %s" % text)
	assert_true(text.contains("ulepsz Dwór") and text.contains("Koszary"), "jak podnieść")
	return true


## Okienko mieści się na ekranie z najdłuższą treścią; surowce na pasku i licznik armii to cele
## dotyku co najmniej 12×12 px (cel dotyku licznika obok napisu trybu w tytule).
func test_popup_and_touch_targets_fit() -> bool:
	var grid := BuildGrid.new(TerrainMap.generate(1337))
	grid.place_kind(_spot(grid, K.MANOR), K.MANOR, 1)
	for i in 3:
		grid.place_kind(_spot(grid, K.BARRACKS), K.BARRACKS, 5)
	var amounts: Array[int] = [999, 1000, 50, 99999]
	var longest: PackedStringArray = InfoText.army(grid, Recruitment.new())
	for res in EconomyConfig.count():
		var lines := InfoText.resource(res, grid, null, amounts)
		if lines.size() > longest.size():
			longest = lines
	var lines := InfoPopup.wrapped(longest)
	for line in lines:
		assert_true(PixelFont.text_width(line) <= InfoPopup.WIDTH - 2 * InfoPopup.PAD, "„%s” mieści się" % line)
	var box := InfoPopup.box_rect(VIEW, lines.size())
	assert_true(box.position.y >= Hud.BAR_H and box.end.y <= VIEW.y - Hud.BAR_H, "okienko między paskami")
	assert_true(box.position.x >= Hud.CORNER_INSET and box.end.x <= VIEW.x - Hud.CORNER_INSET, "okienko poza rogami")
	var rects := Hud.resource_rects(amounts, Hud.CORNER_INSET)
	assert_eq(rects.size(), EconomyConfig.count(), "cel dla każdego surowca")
	for res in rects.size():
		assert_true(rects[res].size.x >= 12 and rects[res].size.y >= 12, "%d: cel 12×12" % res)
		assert_eq(Hud.hit(rects, rects[res].get_center()), res, "%d: trafienie" % res)
	var left := float(Hud.CORNER_INSET)
	var right := VIEW.x - Hud.CORNER_INSET
	var limit := RecruitPanel.limit_rect(left, right)
	assert_true(limit.size.y >= 12 and limit.size.x >= 12, "licznik armii 12×12")
	var rec := Recruitment.new()
	var title := RecruitPanel.title_text(rec, grid)
	assert_true(PixelFont.text_width(title) <= limit.size.x, "tytuł w celu dotyku: %s" % title)
	assert_true(left + PixelFont.text_width(title) + 4 < right - PixelFont.text_width("wszystkie jednostki"),
			"tytuł nie wchodzi na napis trybu")
	assert_eq(RecruitPanel.target_at(limit.get_center(), VIEW, left, right, 3), RecruitPanel.Target.LIMIT, "trafienie licznika")
	return true


## Otwarte okienko łapie dotyk i zamyka się po puszczeniu palca.
func test_popup_opens_and_closes() -> bool:
	var popup := InfoPopup.new()
	var got := [false]
	popup.closed.connect(func() -> void: got[0] = true)
	popup.open("Drewno", PackedStringArray(["Zapas: 1"]))
	assert_true(popup.visible and popup.lines.size() == 1, "otwarte")
	popup.close()
	assert_true(not popup.visible and got[0], "zamknięte")
	popup.free()
	return true
