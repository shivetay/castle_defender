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
	var wood := "%d Dr" % BuildConfig.cost(K.TOWER, 1)[EconomyConfig.Res.WOOD]
	assert_true((poor[1][3] as PackedStringArray).has(wood), "brakujące drewno na czerwono")
	assert_eq((poor[1][3] as PackedStringArray).size(), 1, "tylko drewno, reszty starcza")
	return true


## Karta budynku pokazuje koszt i czas następnego poziomu (po teście na telefonie).
func test_card_shows_upgrade_cost() -> bool:
	var info: String = load("res://scripts/main.gd").upgrade_info(K.TOWER, 1, 3, false)
	assert_true(info.begins_with("Ulepsz: "), "koszt ulepszenia")
	assert_true(info.contains(Hud.cost_text(BuildConfig.cost(K.TOWER, 2))), "koszt poziomu 2")
	assert_true((load("res://scripts/main.gd").upgrade_info(K.TOWER, 5, 5, false) as String).begins_with("Epoka II: "),
			"poziom 5: wejście w epokę II (#34)")
	assert_eq(load("res://scripts/main.gd").upgrade_info(K.TOWER, 10, 10, false), "Najwyższy poziom", "poziom 5 epoki II")
	assert_eq(load("res://scripts/main.gd").upgrade_info(K.TOWER, 1, 3, true), "Trwa budowa", "w kolejce")
	return true


## Karta pokazuje wymagania następnego poziomu (po teście na telefonie), a cały opis mieści się
## w liniach karty bez ucinania „...”.
func test_card_shows_requirements_in_full() -> bool:
	var main: GDScript = load("res://scripts/main.gd")
	assert_eq(main.upgrade_needs(K.TOWER, 3, 3, false), "Wymaga: Dwór poz. 4 (masz 3)", "ponad poziom Dworu")
	assert_eq(main.upgrade_needs(K.TOWER, 1, 3, false), "Wymaga: Dwór poz. 2 (masz 3)", "spełnione")
	assert_eq(main.upgrade_needs(K.MANOR, 1, 1, false), "Wymaga: tylko surowców", "Dwór")
	assert_eq(main.upgrade_needs(K.TOWER, 5, 5, false), "Wymaga: Dwór poz. II.1 (masz 5)", "epoka II po przebudowie Dworu")
	assert_eq(main.upgrade_needs(K.MANOR, 5, 5, false), "Wymaga: O1 Sypanie kopców", "przebudowa Dworu (#34)")
	assert_true(not main.upgrade_needs_ok(K.MANOR, 5, 5, false), "bez O1 na czerwono")
	assert_eq(main.upgrade_needs(K.TOWER, 10, 10, false), "", "najwyższy poziom: bez linii")
	assert_eq(main.upgrade_needs(K.TOWER, 1, 3, true), "", "w budowie: bez linii")
	assert_true(main.upgrade_needs_ok(K.TOWER, 1, 3, false), "wieża 1 przy Dworze 3: zielona")
	assert_true(not main.upgrade_needs_ok(K.TOWER, 3, 3, false), "wieża 3 przy Dworze 3: czerwona")
	assert_true(main.upgrade_needs_ok(K.MANOR, 3, 3, false), "Dwór: zielona")
	assert_eq(Hud.card_lines("Ulepsz: 180 Dr 60 Ka, 3:00", "", 70),
			PackedStringArray(["Ulepsz: 180 Dr", "60 Ka, 3:00"]), "koszt łamie się całymi parami")
	var view := Vector2(320, 180)
	for kind in BuildingTypes.count():
		for level in range(1, BuildingTypes.MAX_LEVEL):
			var info: String = main.upgrade_info(kind, level, 1, false)
			var needs: String = main.upgrade_needs(kind, level, 1, false)
			var lines := Hud.card_lines(info, needs, Hud.CARD_MIN_W - 8)
			var joined := " ".join(lines)
			assert_eq(joined, (info + " " + needs).strip_edges(), "%d/%d: cały tekst" % [kind, level])
			for line in lines:
				assert_true(PixelFont.text_width(line) <= Hud.CARD_MIN_W - 8, "%d/%d: „%s” mieści się" % [kind, level, line])
			for res in EconomyConfig.count():
				for line in lines:
					assert_true(not line.ends_with(" " + "%d" % BuildConfig.cost(kind, level + 1)[res]) \
							or BuildConfig.cost(kind, level + 1)[res] == 0, "%d/%d: koszt w jednej linii" % [kind, level])
			for variant: Vector2i in [Vector2i(0, 0), Vector2i(1, 0), Vector2i(0, 1)]:
				var panel := Hud.card_panel(view, lines.size(), variant.x == 1, variant.y == 1)
				assert_true(panel.position.y > Hud.BAR_H + 10, "%d/%d: karta pod paskiem celu" % [kind, level])
				assert_true(panel.position.x >= 0 and panel.end.x <= view.x, "%d/%d: karta na ekranie" % [kind, level])
	return true



## Review #160: Zamknij w panelu otwartym przez Zmień zostaje w trybie budowy z kosztem wybranego
## budynku w komunikacie, a otwartym przez Buduj wraca do oglądania.
func test_closing_panel_keeps_the_mode() -> bool:
	var main_script: GDScript = load("res://scripts/main.gd")
	var in_build: String = main_script.closed_message(true, K.TOWER)
	assert_true(in_build.begins_with(BuildingTypes.NAMES[K.TOWER]), "tryb budowy: komunikat o wieży")
	assert_true(in_build.contains(Hud.cost_text(BuildConfig.cost(K.TOWER, 1))), "z kosztem")
	assert_eq(main_script.closed_message(false, K.TOWER), main_script.DEFAULT_MESSAGE, "oglądanie: zwykły komunikat")
	return true



## Po teście na telefonie: brakujące surowce do budowy i ulepszenia są na czerwono.
func test_missing_resource_tokens() -> bool:
	var cost: Array[int] = [120, 40, 40, 0]
	assert_eq(Hud.missing_tokens(cost, [500, 300, 300, 50] as Array[int]).size(), 0, "na wszystko stać")
	assert_eq(Hud.missing_tokens(cost, [100, 300, 10, 50] as Array[int]), PackedStringArray(["120 Dr", "40 Ży"]), "brak drewna i żywności")
	assert_true(Hud.cost_text(cost).contains("120 Dr") and Hud.cost_text(cost).contains("40 Ży"), "fragmenty pochodzą z tekstu kosztu")
	return true
