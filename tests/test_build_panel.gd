extends TestCase
## Panel budowy (po teście na telefonie): kategorie, szczegóły z kosztem i wymaganiami, opis tego,
## co budynek daje, oraz koszt ulepszenia na karcie budynku.

const K := BuildingTypes.Kind
const VIEW := Vector2(320, 180)


func test_every_buildable_kind_is_in_exactly_one_category() -> bool:
	for kind in BuildingTypes.BUILD_BAR:
		var found := 0
		for cat in BuildingTypes.CATEGORY_NAMES.size():
			if BuildingTypes.in_category(cat).has(kind):
				found += 1
		assert_eq(found, 1, "%s w jednej kategorii" % BuildingTypes.NAMES[kind])
	assert_eq(BuildingTypes.category(K.TOWER), BuildingTypes.Category.DEFENSE, "wieża: umocnienia")
	assert_eq(BuildingTypes.category(K.BOWYER), BuildingTypes.Category.PRODUCERS, "Łukmistrz: wytwórcy")
	assert_eq(BuildingTypes.category(K.BARRACKS), BuildingTypes.Category.MILITARY, "Koszary: wojsko")
	return true


func test_layout_fits_and_targets() -> bool:
	var b := Hud.content_bounds(VIEW, Rect2())
	var most := 0
	for cat in BuildingTypes.CATEGORY_NAMES.size():
		most = maxi(most, BuildingTypes.in_category(cat).size())
	var tiles := BuildPanel.tile_rects(b.x, b.y, most)
	for t in tiles:
		assert_true(t.size.x >= 12 and t.size.y >= 12, "kafelek ≥ 12×12")
		assert_true(t.end.y <= BuildPanel.DETAIL_Y, "kafelki nad szczegółami")
		assert_true(t.end.x <= b.y, "w granicach treści")
	for tab_label: String in BuildingTypes.CATEGORY_NAMES:
		assert_true(PixelFont.text_width(tab_label) <= BuildPanel.tab_rects(b.x, b.y)[0].size.x - 2, "zakładka „%s”" % tab_label)
	assert_true(BuildPanel.DETAIL_Y + BuildPanel.DETAIL_LINES * BuildPanel.LINE_STEP <= Hud.row_y(VIEW), "szczegóły nad przyciskami")
	var T := BuildPanel.Target
	assert_eq(BuildPanel.target_at(BuildPanel.place_rect(VIEW, b.y).get_center(), VIEW, b.x, b.y, 0), T.PLACE, "Postaw")
	assert_eq(BuildPanel.target_at(BuildPanel.close_rect(VIEW, b.y).get_center(), VIEW, b.x, b.y, 0), T.CLOSE, "Zamknij")
	assert_eq(BuildPanel.target_at(BuildPanel.tab_rects(b.x, b.y)[2].get_center(), VIEW, b.x, b.y, 0), T.TAB + 2, "zakładka")
	assert_eq(BuildPanel.target_at(tiles[0].get_center(), VIEW, b.x, b.y, 0), T.TILE, "kafelek")
	return true


## Szczegóły każdego budynku mieszczą się w szerokości (także zwężonej) i w DETAIL_LINES.
func test_details_fit_for_every_building() -> bool:
	var r := Research.new()
	var e := Economy.new(0)
	for width: int in [200, 240, 296]:
		for kind in BuildingTypes.BUILD_BAR:
			var lines := BuildPanel.detail_lines(kind, r, e, width)
			assert_true(lines.size() <= BuildPanel.DETAIL_LINES, "%s: najwyżej %d linii" % [BuildingTypes.NAMES[kind], BuildPanel.DETAIL_LINES])
			for l: Array in lines:
				var w := PixelFont.text_width(l[0] as String)
				if not (l[2] as String).is_empty():
					w += 6 + PixelFont.text_width(l[2] as String)
				assert_true(w <= width, "„%s” mieści się w %d px" % [l[0], width])
	return true


func test_details_show_cost_requirement_and_effect() -> bool:
	var r := Research.new()
	var e := Economy.new(0)
	var text := ""
	for l: Array in BuildPanel.detail_lines(K.HUNTER, r, e, 296):
		text += (l[0] as String) + "|" + (l[2] as String) + "|"
	assert_true(text.contains("Koszt:"), "koszt budowy")
	assert_true(text.contains("Wymaga: G18"), "wymagana technologia")
	assert_true(text.contains("zbadaj G18"), "stan: zablokowany")
	assert_true(BuildPanel.describe(K.HUNTER).contains("Surowe skóry"), "co robi myśliwy")
	assert_true(BuildPanel.describe(K.LUMBER_HUT).contains("Dr/h"), "chata drwala daje drewno")
	assert_true(BuildPanel.describe(K.BARRACKS).contains("Szkoli:"), "Koszary szkolą")
	assert_true(BuildPanel.describe(K.BOWYER).contains("poz. 3"), "łuk refleksyjny od poziomu 3")
	e.amounts[EconomyConfig.Res.WOOD] = 0
	var poor := BuildPanel.detail_lines(K.TOWER, r, e, 296)
	assert_true((poor[1][0] as String).contains("brak surowców"), "brak surowców widać")
	return true


## Karta budynku pokazuje koszt i czas następnego poziomu (po teście na telefonie).
func test_card_shows_upgrade_cost() -> bool:
	var info: String = load("res://scripts/main.gd").upgrade_info(K.TOWER, 1, 3, false)
	assert_true(info.begins_with("Ulepsz: "), "koszt ulepszenia")
	assert_true(info.contains(Hud.cost_text(BuildConfig.cost(K.TOWER, 2))), "koszt poziomu 2")
	assert_eq(load("res://scripts/main.gd").upgrade_info(K.TOWER, 5, 5, false), "Najwyższy poziom", "poziom 5")
	assert_true((load("res://scripts/main.gd").upgrade_info(K.TOWER, 3, 3, false) as String).contains("najpierw Dwór"),
			"ponad poziom Dworu")
	assert_eq(load("res://scripts/main.gd").upgrade_info(K.TOWER, 1, 3, true), "Trwa budowa", "w kolejce")
	return true
