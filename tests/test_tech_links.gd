extends TestCase
## Powiązania technologii na ekranie drzewka (po teście na telefonie): co technologia odblokowuje
## i z czym łączy się przez towary, a szczegóły mieszczą się w szerokości ekranu.


func test_unlocks_are_direct_dependents() -> bool:
	assert_true(TechLinks.unlocks("A40").has("A41"), "A40 Cięciwiarstwo odblokowuje A41 Łukmistrzostwo")
	assert_true(TechLinks.unlocks("A41").has("A44"), "A41 odblokowuje A44 Ćwiczenia strzeleckie")
	for code in TechTree.codes():
		for next in TechLinks.unlocks(code):
			assert_true(TechTree.requires(next).has(code), "%s naprawdę wymaga %s" % [next, code])
	return true


## Przykład z testu właściciela: A39 Drzewcarstwo (Drzewcarz robi kopię) i A22 Kopia rycerska
## (Kopijnik potrzebuje kopii).
func test_goods_link_polearm_maker_and_lancer() -> bool:
	assert_true(TechLinks.outputs("A39").has(GoodsConfig.Good.LANCE), "Drzewcarz robi kopię")
	assert_true(TechLinks.inputs("A22").has(GoodsConfig.Good.LANCE), "Kopijnik potrzebuje kopii")
	assert_true(TechLinks.related("A39").has("A22"), "A39 powiązana z A22")
	assert_true(TechLinks.related("A22").has("A39"), "i w drugą stronę")
	return true


func test_related_is_symmetric_and_skips_direct_links() -> bool:
	for code in TechTree.codes():
		var linked := TechLinks.related(code)
		assert_true(not linked.has(code), "%s nie jest powiązana sama ze sobą" % code)
		for other in linked:
			assert_true(TechLinks.related(other).has(code) or TechTree.requires(other).has(code)
					or TechTree.requires(code).has(other), "%s ↔ %s w obie strony" % [code, other])
			assert_true(not TechTree.requires(code).has(other), "%s: wymagania osobno" % code)
	return true


## Szczegóły każdej technologii mieszczą się w szerokości treści (także zwężonej strefą bezpieczną)
## i w DETAIL_LINES liniach nad przyciskami.
func test_details_fit_on_narrow_screens() -> bool:
	var r := Research.new()
	for width: int in [200, 240, 296]:
		for code in TechTree.codes():
			var lines := ResearchPanel.detail_lines(r, code, 0, 0, width)
			assert_true(lines.size() <= ResearchPanel.DETAIL_LINES, "%s: najwyżej %d linii" % [code, ResearchPanel.DETAIL_LINES])
			for l: Array in lines:
				var w := PixelFont.text_width(l[0] as String)
				if not (l[2] as String).is_empty():
					w += 6 + PixelFont.text_width(l[2] as String)
				assert_true(w <= width, "%s: „%s” mieści się w %d px" % [code, l[0], width])
	# A22 jest z epoki II: widać ją dopiero po A7
	var with_a7 := Research.new()
	with_a7.done["A7"] = true
	var a39 := ResearchPanel.detail_lines(with_a7, "A39", 0, 0, 296)
	var shows_link := false
	for l: Array in a39:
		if (l[0] as String).begins_with("Powiązane:") and (l[0] as String).contains("A22"):
			shows_link = true
	assert_true(shows_link, "A39 pokazuje powiązanie z A22")
	assert_true(ResearchPanel.DETAIL_Y + ResearchPanel.DETAIL_LINES * ResearchPanel.LINE_STEP
			<= Hud.row_y(Vector2(320, 180)), "szczegóły nad przyciskami")
	return true


## Zbadane technologie wyróżniają się kafelkiem, nie tylko kolorem napisu.
func test_researched_tiles_look_different() -> bool:
	assert_true(ResearchPanel.tile_color(true, false) != ResearchPanel.tile_color(false, false), "zbadana inna niż niezbadana")
	assert_true(ResearchPanel.tile_color(true, true) != ResearchPanel.tile_color(true, false), "zaznaczona zbadana jaśniejsza")
	return true


## Gdy brakuje linii, odblokowuje i powiązane łączą się w jedną (A41: A44 i A47).
func test_links_merge_when_short_of_lines() -> bool:
	# A47 jest z epoki II: widać ją dopiero po A2
	var r := Research.new()
	r.done["A2"] = true
	var lines := ResearchPanel.detail_lines(r, "A41", 0, 0, 296)
	var merged := false
	for l: Array in lines:
		var t := l[0] as String
		if t.begins_with("Odblokowuje:") and t.contains("A44") and t.contains("powiązane") and t.contains("A47"):
			merged = true
	assert_true(merged, "A44 i A47 w jednej linii (review #157)")
	return true


## Powiązania widać też na zakładkach innych gałęzi (review #157): ramki są tylko w bieżącej zakładce.
func test_tab_marks_related_branch() -> bool:
	var reqs := TechTree.requires("A39")
	var next := TechLinks.unlocks("A39")
	var linked := TechLinks.related("A39")
	var atak := TechTree.branch("A22")
	assert_true(ResearchPanel.tab_marker(atak, reqs, next, linked).a > 0.0, "gałąź z A22 ma znacznik")
	var none := 0
	for i in TechTree.BRANCH_NAMES.size():
		if ResearchPanel.tab_marker(i, [] as Array[String], [] as Array[String], [] as Array[String]).a == 0.0:
			none += 1
	assert_eq(none, TechTree.BRANCH_NAMES.size(), "bez powiązań bez znaczników")
	# spełnione wymaganie ma inny kolor niż zielony znaczek zbadanej technologii
	var done_req := ResearchPanel.link_color("A40", ["A40"] as Array[String], [] as Array[String], [] as Array[String], true)
	assert_true(done_req != Palette.VALID, "ramka spełnionego wymagania widoczna na zielonym kafelku")
	return true
