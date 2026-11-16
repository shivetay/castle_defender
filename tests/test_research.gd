extends TestCase
## Badania (#12): dane drzewka zgodne z notatką Drzewko technologiczne, zależności, blokada epoki,
## koszt i czas, premie do produkcji, zapis i ekran drzewka.

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
	assert_eq(sizes, [19, 3, 9, 1, 2] as Array[int], "Atak 19, Obrona 3, Gospodarka 9, Użyteczne 1, Specjalne 2")
	var mvp: Array[String] = ["A1", "A2", "A3", "A4", "A5", "A6", "A7", "A21", "A22", "A38", "A39", "A40", "A41",
			"A42", "A43", "A44", "A45", "A46", "A47", "O1", "O2", "O3", "G1", "G2", "G4", "G6", "G18", "G19", "G20",
			"G21", "G24", "U1", "S1", "S2"]
	for code in mvp:
		assert_true(TechTree.has(code), "%s z listy MVP (Plan MVP)" % code)
		assert_true(not TechTree.effect(code).is_empty(), "%s ma efekt" % code)
	return true


## Zależności i epoki z notatki, z jej sekcją „Zmienione zależności”.
func test_dependencies_and_ages_from_note() -> bool:
	var expected := {
		"A3": ["G24"], "A4": ["A1"], "A5": ["A4"], "A6": ["A1"], "A7": ["A2", "A43"], "A21": ["A38"],
		"A22": ["A7"], "A38": ["G19"], "A40": ["G18"], "A41": ["A40"], "A42": ["G18"], "A43": ["G19"],
		"A44": ["A41"], "A45": ["A38"], "A46": ["A45"], "A47": ["A2"], "O3": ["O2"], "G4": ["G1"],
		"G6": ["G4"], "G19": ["G18"], "G20": ["G2"], "G24": ["G1"],
	}
	for code in TechTree.codes():
		var want: Array[String] = []
		want.assign(expected.get(code, []) as Array)
		assert_eq(TechTree.requires(code), want, "%s wymaga" % code)
	var age_two: Array[String] = ["A5", "A6", "A22", "A46", "A47", "G4", "G6"]
	for code in TechTree.codes():
		assert_eq(TechTree.age(code), 1 if age_two.has(code) else 0, "%s: epoka" % code)
	assert_true(TechTree.is_key("O1") and TechTree.is_key("G6"), "O1 i G6 kluczowe (★)")
	var keys := 0
	for code in TechTree.codes():
		keys += int(TechTree.is_key(code))
	assert_eq(keys, 2, "tylko dwie kluczowe w MVP")
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
	assert_eq(r.start("G18", 0, e, T0), Research.Result.BUSY, "jedno badanie naraz")
	r.update(T0 + r.duration_ms)
	assert_eq(r.start("A2", 0, e, T0), Research.Result.ALREADY_DONE, "drugi raz nie")
	assert_eq(r.check("A43", 0), Research.Result.MISSING_REQUIREMENTS, "Rymarstwo wymaga Garbarstwa")
	for code: String in ["G18", "G19", "A43"]:
		_finish(r, code, e)
	assert_eq(r.check("A7", 0), Research.Result.OK, "po A2 i A43 Strzemię dostępne")
	assert_eq(r.check("A47", 1), Research.Result.OK, "w epoce II A47 (po A2) dostępne")
	assert_eq(r.check("A47", 0), Research.Result.WRONG_AGE, "ale nie w epoce I")
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
	_finish(r, "G1", e)
	_finish(r, "G24", e)
	r.start("A3", 0, e, T0 + 5000)
	var grid := BuildGrid.new(TerrainMap.generate(1337))
	var d := SaveGame.to_dict(1337, grid, e, BuildQueue.new(), r)
	var s := SaveGame.from_dict(JSON.parse_string(JSON.stringify(d)) as Dictionary, T0)
	assert_true(s != null, "zapis czytelny")
	if s != null:
		assert_eq(s.research.done.keys(), ["A2", "G1", "G24"], "zbadane po odczycie")
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
	assert_eq(tabs.size(), 5, "5 zakładek")
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
	assert_true(ResearchPanel.DETAIL_Y + ResearchPanel.DETAIL_LINES * (PixelFont.LINE + 2) <= row,
			"linie szczegółów nad przyciskami")
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
	assert_eq(ResearchPanel.requires_text("A7", 100), "Wymaga: A2, A43", "za wąsko: same kody")
	assert_true(PixelFont.text_width(ResearchPanel.requires_text("A7", 60)) <= 60, "jeszcze węziej: przycięte (review #157)")
	var long := ResearchPanel.fit_text(TechTree.effect("A42"), 100)
	assert_true(PixelFont.text_width(long) <= 100 and long.ends_with("..."), "długi efekt przycięty")
	assert_eq(ResearchPanel.fit_text("+20% drewna", 300), "+20% drewna", "krótki bez zmian")
	return true


func test_hud_research_button() -> bool:
	var b := Hud.content_bounds(VIEW, Rect2())
	var research := Hud.research_rect(VIEW, b.y)
	assert_true(not research.intersects(Hud.right_corner_rect(VIEW, b.y)), "Badania obok Buduj")
	assert_true(not research.intersects(Hud.left_corner_rect(VIEW, b.x)), "Badania nie na Oblężeniu")
	assert_eq(Hud.target_at(research.get_center(), VIEW, b.x, b.y, false, false, 0), Hud.Target.RESEARCH, "oglądanie: Badania")
	assert_true(Hud.target_at(research.get_center(), VIEW, b.x, b.y, true, false, 0) != Hud.Target.RESEARCH, "w trybie budowy nie")
	return true


## Efekty G1 i G2 (+20% drewna, +15% żywności) zmieniają produkcję od chwili zbadania.
func test_production_bonus_from_research() -> bool:
	var r := Research.new()
	var e := _rich_economy()
	var base := Economy.rates(null)
	assert_eq(Economy.rates(null, r), base, "bez badań bez premii")
	_finish(r, "G1", e)
	_finish(r, "G2", e)
	var bonus := Economy.rates(null, r)
	assert_eq(bonus[EconomyConfig.Res.WOOD], base[EconomyConfig.Res.WOOD] * 120 / 100, "+20% drewna")
	assert_eq(bonus[EconomyConfig.Res.FOOD], base[EconomyConfig.Res.FOOD] * 115 / 100, "+15% żywności")
	assert_eq(bonus[EconomyConfig.Res.STONE], base[EconomyConfig.Res.STONE], "kamień bez zmian")
	return true


## Badanie kończy się w kolejce w porządku czasu: premia liczy się od chwili zbadania także
## wtedy, gdy gra nadrabia nieobecność jednym skokiem.
func test_bonus_starts_when_research_ends_during_absence() -> bool:
	var grid := BuildGrid.new(TerrainMap.generate(1337))
	var hour := 3600 * 1000
	var jump := _economy_at(T0)
	var r := Research.new()
	r.start("G1", 0, jump, T0)
	var finish := r.finish_ms()
	BuildQueue.new().update(finish + 10 * hour, grid, jump, r)
	assert_true(r.is_done("G1"), "zbadane po powrocie")
	# ten sam przebieg ręcznie: do końca badania bez premii, potem z premią
	var ref := _economy_at(T0)
	var spent := ResearchConfig.cost(0, 0)
	ref.spend(spent)
	ref.update(finish, Economy.rates(grid))
	var done := Research.new()
	done.done["G1"] = true
	ref.update(finish + 10 * hour, Economy.rates(grid, done))
	assert_eq(jump.amounts, ref.amounts, "jeden skok = odcinek bez premii + odcinek z premią")
	return true


func _economy_at(t: int) -> Economy:
	var e := Economy.new(t)
	e.amounts = [500, 300, 300, 50] as Array[int]
	return e


## Review #139: odliczanie badania na górnym pasku mieści się obok surowców w najgorszym przypadku.
func test_research_countdown_fits_top_bar() -> bool:
	assert_eq(Hud.top_right_text("", "Epoka I · 550 r.", "Bad. 0:42"), "Bad. 0:42  Epoka I · 550 r.", "badanie i epoka")
	assert_eq(Hud.top_right_text("0:05", "Epoka I · 550 r.", "Bad. 0:42"), "0:05  Bad. 0:42  Epoka I · 550 r.", "budowa, badanie, epoka")
	var worst := Hud.top_right_text("12:00:00 +3", "Epoka I · 750 r.", "Bad. 12:00:00")
	var amounts: Array[int] = [1000, 1000, 1000, 9999]
	var xs := Hud.resource_layout(amounts, Hud.CORNER_INSET)
	var right := 320 - Hud.CORNER_INSET
	assert_true(xs[-1] + 4 <= right - PixelFont.text_width(worst), "„%s” nie wchodzi na surowce" % worst)
	return true


## Review #139: wczytane trwające badanie musi spełniać wymagania, jak przy check().
func test_loaded_active_research_needs_requirements() -> bool:
	var r := Research.new()
	var skipped := r.load_data({"done": [], "active": {"code": "A7", "start_ms": T0, "duration_ms": 1000}}, T0)
	assert_eq(skipped, 1, "A7 bez A2 i A43 pominięte")
	assert_true(not r.is_busy(), "nic się nie bada")
	skipped = r.load_data({"done": ["A2", "G18", "G19", "A43"], "active": {"code": "A7", "duration_ms": 1000}}, T0)
	assert_eq(skipped, 0, "z wymaganiami wraca")
	assert_eq(r.active, "A7", "A7 w toku")
	return true
