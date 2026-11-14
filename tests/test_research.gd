extends TestCase
## Badania (#12): dane drzewka, zależności, blokada epoki, koszt i czas, zapis i ekran drzewka.

const T0 := 1_700_000_000_000
const VIEW := Vector2(320, 180)


func _rich_economy() -> Economy:
	var e := Economy.new(T0)
	for res in EconomyConfig.count():
		e.amounts[res] = 1_000_000
	return e


## Bada technologię od razu do końca; zapasy uzupełnia, bo koszt rośnie z każdą technologią.
func _finish(r: Research, code: String, economy: Economy) -> bool:
	for res in EconomyConfig.count():
		economy.amounts[res] = 1 << 50
	if r.start(code, 1, economy, T0) != Research.Result.OK:
		return false
	return r.update(T0 + r.duration_ms) == code


func test_tree_has_34_unique_technologies() -> bool:
	assert_eq(TechTree.count(), 34, "34 technologie MVP")
	var seen := {}
	for code in TechTree.codes():
		assert_true(not seen.has(code), "kod %s jest unikalny" % code)
		seen[code] = true
		assert_true(not TechTree.tech_name(code).is_empty(), "%s ma nazwę" % code)
	var sizes: Array[int] = []
	for b in TechTree.BRANCH_NAMES.size():
		sizes.append(TechTree.in_branch(b).size())
	assert_eq(sizes, [19, 3, 9, 3] as Array[int], "Atak 19, Obrona 3, Gospodarka 9, Użyteczne 3")
	return true


func test_dependencies_from_issue() -> bool:
	assert_eq(TechTree.requires("A21"), ["A38"] as Array[String], "A21 wymaga A38")
	assert_eq(TechTree.requires("A7"), ["A2", "A43"] as Array[String], "A7 wymaga A2 i A43")
	assert_eq(TechTree.requires("A3"), ["G24"] as Array[String], "A3 wymaga G24")
	assert_eq(TechTree.requires("A44"), ["A41"] as Array[String], "A44 wymaga A41")
	assert_true(TechTree.is_key("O1") and TechTree.age("O1") == 0, "O1 ★ kluczowa w epoce I (przejście I → II)")
	assert_true(TechTree.is_key("G6") and TechTree.age("G6") == 1, "G6 ★ kluczowa w epoce II")
	assert_eq(TechTree.age("A7"), 0, "Strzemię w epoce I (#91)")
	for code: String in ["A22", "A46", "A47"]:
		assert_eq(TechTree.age(code), 1, "%s w epoce II (#92)" % code)
	return true


func test_requirements_exist_are_not_later_and_have_no_cycles() -> bool:
	for code in TechTree.codes():
		for req in TechTree.requires(code):
			assert_true(TechTree.has(req), "%s: wymagana %s istnieje" % [code, req])
			assert_true(TechTree.age(req) <= TechTree.age(code), "%s: wymagana %s nie jest z późniejszej epoki" % [code, req])
	# każdą technologię da się zbadać, idąc po kolei przez drzewko (brak cykli)
	var r := Research.new()
	var e := _rich_economy()
	var progress := true
	while progress:
		progress = false
		for code in TechTree.codes():
			if r.check(code, 1) == Research.Result.OK and _finish(r, code, e):
				progress = true
	assert_eq(r.done.size(), TechTree.count(), "wszystkie technologie osiągalne")
	return true


func test_requirements_and_age_block_research() -> bool:
	var r := Research.new()
	var e := _rich_economy()
	assert_eq(r.start("A7", 0, e, T0), Research.Result.MISSING_REQUIREMENTS, "A7 bez A2 i A43")
	assert_eq(r.missing("A7"), ["A2", "A43"] as Array[String], "brakuje obu")
	assert_eq(r.start("A46", 0, e, T0), Research.Result.WRONG_AGE, "technologia epoki II w epoce I")
	assert_eq(r.start("G6", 0, e, T0), Research.Result.WRONG_AGE, "G6 w epoce I")
	assert_eq(r.start("XX", 0, e, T0), Research.Result.UNKNOWN, "nieznany kod")
	assert_eq(r.start("A2", 0, e, T0), Research.Result.OK, "A2 bez wymagań")
	assert_eq(r.start("A43", 0, e, T0), Research.Result.BUSY, "jedno badanie naraz")
	r.update(T0 + r.duration_ms)
	assert_eq(r.start("A2", 0, e, T0), Research.Result.ALREADY_DONE, "drugi raz nie")
	_finish(r, "A43", e)
	assert_eq(r.check("A7", 0), Research.Result.OK, "po A2 i A43 Strzemię dostępne")
	assert_eq(r.check("A46", 1), Research.Result.OK, "w epoce II A46 dostępne")
	return true


func test_cost_is_spent_and_research_ends_on_time() -> bool:
	var r := Research.new()
	var e := Economy.new(T0)
	var before: Array[int] = []
	before.assign(e.amounts)
	var price := r.cost_of("A1")
	assert_eq(r.start("A1", 0, e, T0), Research.Result.OK, "start")
	for res in price.size():
		assert_eq(e.amounts[res], before[res] - price[res], "pobrano koszt (%s)" % EconomyConfig.NAMES[res])
	assert_eq(r.update(T0 + r.duration_ms - 1), "", "milisekundę przed końcem jeszcze trwa")
	assert_eq(r.remaining_ms(T0 + r.duration_ms - 1), 1, "zostaje 1 ms")
	assert_eq(r.update(T0 + r.duration_ms + 10 * 3600 * 1000), "A1", "kończy się także po długiej nieobecności")
	assert_true(r.is_done("A1") and not r.is_busy(), "zbadane i wolne")
	var poor := Economy.new(T0)
	poor.amounts = [0, 0, 0, 0] as Array[int]
	assert_eq(Research.new().start("A1", 0, poor, T0), Research.Result.NO_RESOURCES, "bez surowców nie rusza")
	return true


func test_each_next_technology_in_age_costs_more() -> bool:
	var r := Research.new()
	var e := _rich_economy()
	var c0 := r.cost_of("A1")
	var t0 := r.time_of("A1")
	assert_eq(c0, ResearchConfig.cost(0, 0), "pierwsza technologia epoki I po koszcie bazowym")
	_finish(r, "A1", e)
	var c1 := r.cost_of("A4")
	assert_eq(c1[0], c0[0] * ResearchConfig.COST_STEP_PERCENT / 100, "druga ×1,6")
	assert_eq(r.time_of("A4"), t0 * ResearchConfig.TIME_STEP, "druga ×2 dłużej")
	assert_eq(r.cost_of("A46"), ResearchConfig.cost(1, 0), "epoka II liczy się osobno")
	assert_eq(ResearchConfig.cost(0, 5), ResearchConfig.cost(0, 5), "deterministycznie")
	return true


func test_save_round_trip_and_v1_migration() -> bool:
	var r := Research.new()
	var e := _rich_economy()
	_finish(r, "A2", e)
	_finish(r, "G24", e)
	r.start("A3", 0, e, T0 + 5000)
	var grid := BuildGrid.new(TerrainMap.generate(1337))
	var d := SaveGame.to_dict(1337, grid, e, BuildQueue.new(), r)
	var s := SaveGame.from_dict(JSON.parse_string(JSON.stringify(d)) as Dictionary, T0)
	assert_true(s != null, "zapis czytelny")
	if s != null:
		assert_eq(s.research.done.keys(), ["A2", "G24"], "zbadane po odczycie")
		assert_eq(s.research.active, "A3", "trwające badanie")
		assert_eq(s.research.start_ms, r.start_ms, "początek badania")
		assert_eq(s.research.duration_ms, r.duration_ms, "czas badania")
		assert_eq(s.research.cost, r.cost, "zapłacony koszt")
	# zapis sprzed badań (wersja 1)
	var v1 := d.duplicate(true)
	v1["version"] = 1
	v1.erase("research")
	var old := SaveGame.from_dict(v1, T0)
	assert_true(old != null and old.research.done.is_empty() and not old.research.is_busy(), "wersja 1 → puste badania")
	# nieznane kody są pomijane
	var bad := Research.new()
	var skipped := bad.load_data({"done": ["A1", "Z9"], "active": {"code": "Q1"}}, T0)
	assert_eq(skipped, 2, "pominięto nieznane wpisy")
	assert_true(bad.is_done("A1") and not bad.is_busy(), "dobre wpisy zostały")
	return true


func test_panel_layout_fits_screen() -> bool:
	var b := Hud.content_bounds(VIEW, Rect2())
	var tabs := ResearchPanel.tab_rects(b.x, b.y)
	assert_eq(tabs.size(), 4, "4 zakładki")
	for i in tabs.size():
		assert_true(tabs[i].size.y >= 12 and tabs[i].size.x >= 12, "zakładka ≥ 12×12")
		assert_true(PixelFont.text_width(TechTree.BRANCH_NAMES[i]) <= tabs[i].size.x - 2, "nazwa gałęzi mieści się")
	assert_true(tabs[-1].end.x <= b.y, "zakładki w granicach treści")
	var row := Hud.row_y(VIEW)
	for branch in TechTree.BRANCH_NAMES.size():
		var codes := TechTree.in_branch(branch)
		var tiles := ResearchPanel.tile_rects(b.x, b.y, codes.size())
		for i in tiles.size():
			assert_true(tiles[i].size.y >= 12 and tiles[i].size.x >= 12, "kafelek ≥ 12×12")
			assert_true(tiles[i].end.x <= b.y, "kafelek w granicach treści")
			assert_true(tiles[i].end.y <= ResearchPanel.DETAIL_Y, "kafelki nad szczegółami")
			assert_true(PixelFont.text_width(codes[i]) <= tiles[i].size.x - 2, "kod %s mieści się" % codes[i])
	assert_true(ResearchPanel.DETAIL_Y + 4 * (PixelFont.LINE + 2) <= row, "4 linie szczegółów nad przyciskami")
	assert_true(not ResearchPanel.start_rect(VIEW, b.y).intersects(ResearchPanel.close_rect(VIEW, b.y)), "Badaj i Zamknij osobno")
	return true


func test_panel_targets() -> bool:
	var b := Hud.content_bounds(VIEW, Rect2())
	var T := ResearchPanel.Target
	assert_eq(ResearchPanel.target_at(ResearchPanel.close_rect(VIEW, b.y).get_center(), VIEW, b.x, b.y, 0), T.CLOSE, "Zamknij")
	assert_eq(ResearchPanel.target_at(ResearchPanel.start_rect(VIEW, b.y).get_center(), VIEW, b.x, b.y, 0), T.START, "Badaj")
	var tabs := ResearchPanel.tab_rects(b.x, b.y)
	assert_eq(ResearchPanel.target_at(tabs[2].get_center(), VIEW, b.x, b.y, 0), T.TAB + 2, "zakładka Gospodarka")
	var tiles := ResearchPanel.tile_rects(b.x, b.y, 19)
	assert_eq(ResearchPanel.target_at(tiles[18].get_center(), VIEW, b.x, b.y, 0), T.TILE + 18, "ostatni kafelek Ataku")
	assert_eq(ResearchPanel.target_at(tiles[18].get_center(), VIEW, b.x, b.y, 1), T.NONE, "w Obronie tam pusto")
	return true


func test_panel_texts() -> bool:
	var r := Research.new()
	assert_eq(ResearchPanel.state_text(r, "A1", 0, T0), "dostępna", "dostępna")
	assert_eq(ResearchPanel.state_text(r, "A7", 0, T0), "zablokowana", "brak wymagań")
	assert_eq(ResearchPanel.state_text(r, "A46", 0, T0), "Epoka II", "późniejsza epoka")
	r.start("A1", 0, _rich_economy(), T0)
	assert_eq(ResearchPanel.state_text(r, "A1", 0, T0 + r.duration_ms - 1000), "w toku 0:01", "w toku")
	assert_eq(ResearchPanel.requires_text("A1", 300), "Bez wymagań", "bez wymagań")
	assert_eq(ResearchPanel.requires_text("A7", 300), "Wymaga: A2 Łuk kompozytowy, A43 Rymarstwo", "z nazwami")
	assert_eq(ResearchPanel.requires_text("A7", 60), "Wymaga: A2, A43", "za wąsko: same kody")
	return true


func test_hud_research_button() -> bool:
	var b := Hud.content_bounds(VIEW, Rect2())
	var research := Hud.research_rect(VIEW, b.y)
	assert_true(not research.intersects(Hud.right_corner_rect(VIEW, b.y)), "Badania obok Buduj")
	assert_true(not research.intersects(Hud.left_corner_rect(VIEW, b.x)), "Badania nie na Oblężeniu")
	assert_eq(Hud.target_at(research.get_center(), VIEW, b.x, b.y, false, false, 0), Hud.Target.RESEARCH, "oglądanie: Badania")
	assert_true(Hud.target_at(research.get_center(), VIEW, b.x, b.y, true, false, 0) != Hud.Target.RESEARCH, "w trybie budowy nie")
	return true
