extends TestCase
## Rekrutacja (#89): koszt w surowcach i towarach, kolejki w budynkach klas, szkolenie w czasie
## (także offline), limit armii, globalny ekran Wojsko i ekran budynku, zapis.

const T0 := 1_700_000_000_000
const K := BuildingTypes.Kind
const U := UnitTypes.Unit
const G := GoodsConfig.Good
const VIEW := Vector2(320, 180)


func _free_cell(grid: BuildGrid, kind: int) -> Vector2i:
	var c := grid.terrain.center()
	for r in grid.terrain.size:
		for dy in range(-r, r + 1):
			for dx in range(-r, r + 1):
				var p := c + Vector2i(dx, dy)
				if grid.placement_for(p, kind) != Rect2i():
					return p
	return Vector2i(-1, -1)


## Zamek z Dworem 5, dwiema Strzelnicami i Koszarami; bogata gospodarka i pełna zbrojownia.
func _castle() -> Dictionary:
	var grid := BuildGrid.new(TerrainMap.generate(1337))
	grid.place_kind(_free_cell(grid, K.MANOR), K.MANOR, 5)
	var range_a := grid.place_kind(_free_cell(grid, K.ARCHERY_RANGE), K.ARCHERY_RANGE, 1)
	var range_b := grid.place_kind(_free_cell(grid, K.ARCHERY_RANGE), K.ARCHERY_RANGE, 1)
	var barracks := grid.place_kind(_free_cell(grid, K.BARRACKS), K.BARRACKS, 1)
	var e := Economy.new(T0)
	for res in EconomyConfig.count():
		e.amounts[res] = 1000
	var goods := Goods.new(T0)
	for good in GoodsConfig.count():
		goods.amounts[good] = 500
	var r := Research.new()
	for code in TechTree.codes():
		r.done[code] = true
	return {"grid": grid, "e": e, "goods": goods, "r": r, "range_a": range_a, "range_b": range_b,
			"barracks": barracks}


## Kryterium #89: bez towaru nie da się zacząć szkolenia.
func test_no_goods_no_training() -> bool:
	var c := _castle()
	var goods: Goods = c["goods"]
	var e: Economy = c["e"]
	goods.amounts[G.BOW] = 0
	var rec := Recruitment.new()
	var food := e.amounts[EconomyConfig.Res.FOOD]
	assert_eq(rec.start(U.ARCHER, c["range_a"], Recruitment.NEW_SQUAD, c["grid"], e, goods, c["r"], 0, T0), Recruitment.Result.NO_GOODS,
			"Łucznik bez łuku")
	assert_eq(rec.orders.size(), 0, "nic w kolejce")
	assert_eq(e.amounts[EconomyConfig.Res.FOOD], food, "żywność nie zeszła")
	assert_eq(goods.amounts[G.ARROW], 500, "strzały nie zeszły")
	assert_eq(RecruitPanel.missing_text(U.ARCHER, goods), "Brak: 1 Łuk (Łukmistrz)", "brak z budynkiem, który go robi")
	return true


func test_training_spends_cost_and_finishes_in_time() -> bool:
	var c := _castle()
	var goods: Goods = c["goods"]
	var e: Economy = c["e"]
	var rec := Recruitment.new()
	assert_eq(rec.start(U.ARCHER, c["range_a"], Recruitment.NEW_SQUAD, c["grid"], e, goods, c["r"], 0, T0), Recruitment.Result.OK, "start")
	assert_eq(goods.amounts[G.BOW], 499, "łuk zszedł")
	assert_eq(goods.amounts[G.ARROW], 480, "20 strzał zeszło")
	assert_eq(e.amounts[EconomyConfig.Res.FOOD], 990, "10 żywności zeszło")
	assert_eq(rec.start(U.ARCHER, c["range_a"], Recruitment.NEW_SQUAD, c["grid"], e, goods, c["r"], 0, T0), Recruitment.Result.OK, "drugi w kolejce")
	var t := RecruitmentConfig.train_ms(U.ARCHER, 1)
	assert_eq(rec.update(T0 + t - 1), [] as Array[int], "jeszcze trwa")
	assert_eq(rec.update(T0 + t), [U.ARCHER] as Array[int], "pierwszy wyszkolony")
	assert_eq(rec.army_of(U.ARCHER), 1, "w armii")
	# drugi zaczyna się w chwili końca pierwszego, także gdy gra wraca po długiej nieobecności
	assert_eq(rec.update(T0 + 100 * t), [U.ARCHER] as Array[int], "drugi po nieobecności")
	assert_eq(rec.army_of(U.ARCHER), 2, "dwóch łuczników")
	return true


## Kryterium #119: jednostkę da się zrekrutować tylko w budynku swojej klasy.
func test_only_in_building_of_its_class() -> bool:
	var c := _castle()
	var rec := Recruitment.new()
	assert_eq(rec.start(U.ARCHER, c["barracks"], Recruitment.NEW_SQUAD, c["grid"], c["e"], c["goods"], c["r"], 0, T0),
			Recruitment.Result.NO_BUILDING, "Łucznik nie w Koszarach")
	assert_eq(rec.start(U.AXE_WARRIOR, c["barracks"], Recruitment.NEW_SQUAD, c["grid"], c["e"], c["goods"], c["r"], 0, T0),
			Recruitment.Result.OK, "Topornik w Koszarach")
	assert_eq(rec.start(U.RIDER, 0, Recruitment.NEW_SQUAD, c["grid"], c["e"], c["goods"], c["r"], 0, T0), Recruitment.Result.NO_BUILDING,
			"bez Stajni nie ma Jeźdźca")
	return true


func test_availability_reasons() -> bool:
	var c := _castle()
	var rec := Recruitment.new()
	var none := Research.new()
	assert_eq(rec.availability(U.SHIELDBEARER, c["grid"], none, 0), Recruitment.Result.NEEDS_TECH, "Tarczownik bez A21")
	assert_eq(rec.availability(U.SPEARMAN, c["grid"], c["r"], 0), Recruitment.Result.WRONG_AGE, "Włócznik w epoce II")
	assert_eq(rec.availability(U.TRACKER, c["grid"], c["r"], 0), Recruitment.Result.NO_BUILDING, "Tropiciel: brak Wieży sygnałowej")
	assert_eq(rec.availability(U.AXE_WARRIOR, c["grid"], none, 0), Recruitment.Result.OK, "Topornik od razu")
	assert_eq(RecruitPanel.state_text(rec, U.SHIELDBEARER, c["grid"], none, 0), "zbadaj A21", "powód na ekranie")
	return true


## Globalny ekran Wojsko: szkolenie trafia do budynku z najkrótszą kolejką (przy remisie niższe id).
func test_global_training_picks_shortest_queue() -> bool:
	var c := _castle()
	var rec := Recruitment.new()
	var a: int = c["range_a"]
	var b: int = c["range_b"]
	assert_eq(rec.start_any(U.ARCHER, Recruitment.NEW_SQUAD, c["grid"], c["e"], c["goods"], c["r"], 0, T0), Recruitment.Result.OK, "1")
	assert_eq(rec.last_building, mini(a, b), "remis: niższe id")
	rec.start_any(U.ARCHER, Recruitment.NEW_SQUAD, c["grid"], c["e"], c["goods"], c["r"], 0, T0)
	assert_eq(rec.last_building, maxi(a, b), "drugi do pustej kolejki")
	assert_eq(rec.queue_of(a).size(), 1, "kolejki wyrównane")
	assert_eq(rec.queue_of(b).size(), 1, "kolejki wyrównane")
	# Strzelnice poziom 1 mieszczą po 2 w kolejce: łącznie 4, piąty się nie zmieści
	for i in 2:
		rec.start_any(U.ARCHER, Recruitment.NEW_SQUAD, c["grid"], c["e"], c["goods"], c["r"], 0, T0)
	assert_eq(rec.start_any(U.ARCHER, Recruitment.NEW_SQUAD, c["grid"], c["e"], c["goods"], c["r"], 0, T0), Recruitment.Result.QUEUE_FULL,
			"obie kolejki pełne")
	return true


func test_army_limit_counts_training_units() -> bool:
	var c := _castle()
	var grid: BuildGrid = c["grid"]
	var rec := Recruitment.new()
	var limit := Recruitment.army_limit(grid)
	assert_eq(limit, RecruitmentConfig.ARMY_PER_MANOR_LEVEL * 5 + RecruitmentConfig.ARMY_PER_BARRACKS_LEVEL,
			"Dwór 5 i Koszary 1")
	var left := limit - 1
	while left > 0:
		rec.add_squad(U.AXE_WARRIOR, mini(left, RecruitmentConfig.SQUAD_SIZE))
		left -= RecruitmentConfig.SQUAD_SIZE
	assert_eq(rec.start(U.ARCHER, c["range_a"], Recruitment.NEW_SQUAD, grid, c["e"], c["goods"], c["r"], 0, T0), Recruitment.Result.OK, "ostatnie miejsce")
	assert_eq(rec.start(U.ARCHER, c["range_a"], Recruitment.NEW_SQUAD, grid, c["e"], c["goods"], c["r"], 0, T0), Recruitment.Result.ARMY_FULL,
			"limit liczy też szkolonych")
	return true


func test_higher_level_trains_faster_and_more() -> bool:
	assert_true(RecruitmentConfig.train_ms(U.ARCHER, 5) < RecruitmentConfig.train_ms(U.ARCHER, 1), "szybciej")
	assert_true(RecruitmentConfig.training_slots(5) > RecruitmentConfig.training_slots(1), "dłuższa kolejka")
	return true


func test_demolished_building_drops_its_queue() -> bool:
	var c := _castle()
	var rec := Recruitment.new()
	rec.start(U.ARCHER, c["range_a"], Recruitment.NEW_SQUAD, c["grid"], c["e"], c["goods"], c["r"], 0, T0)
	rec.drop_building(c["range_a"])
	assert_eq(rec.orders.size(), 0, "kolejka rozebranego budynku znika")
	return true


func test_save_round_trip_and_migration() -> bool:
	var c := _castle()
	var grid: BuildGrid = c["grid"]
	var rec := Recruitment.new()
	rec.add_squad(U.AXE_WARRIOR, 3)
	rec.start(U.ARCHER, c["range_a"], Recruitment.NEW_SQUAD, grid, c["e"], c["goods"], c["r"], 0, T0)
	rec.start(U.ARCHER, c["range_a"], Recruitment.NEW_SQUAD, grid, c["e"], c["goods"], c["r"], 0, T0)
	var d := SaveGame.to_dict(1337, grid, c["e"], BuildQueue.new(), c["r"], c["goods"], rec)
	var s := SaveGame.from_dict(JSON.parse_string(JSON.stringify(d)) as Dictionary, T0)
	assert_true(s != null, "zapis czytelny")
	if s != null:
		assert_eq(s.recruitment.save_data(), rec.save_data(), "armia i kolejki po odczycie")
	var v3 := d.duplicate(true)
	v3["version"] = 3
	v3.erase("recruitment")
	var old := SaveGame.from_dict(v3, T0)
	assert_true(old != null and old.recruitment.army_size() == 0 and old.recruitment.orders.is_empty(), "wersja 3 → pusta armia")
	return true


func test_panel_modes_and_layout() -> bool:
	assert_eq(RecruitPanel.units_for(-1).size(), UnitTypes.count(), "globalnie wszystkie jednostki")
	assert_eq(RecruitPanel.units_for(K.BARRACKS), [U.PEASANT, U.AXE_WARRIOR, U.JAVELINEER, U.SPEARMAN, U.RAM, U.DIGGER] as Array[int],
			"Koszary: lekka piechota i inżynieria")
	assert_eq(RecruitPanel.units_for(K.STABLE), [U.RIDER, U.LANCER] as Array[int], "Stajnia: konnica")
	assert_true(not RecruitPanel.recruits(K.MANOR), "Dwór nie szkoli")
	assert_true(RecruitPanel.recruits(K.TAR_KILN), "Smolarnia szkoli Podpalacza")
	var b := Hud.content_bounds(VIEW, Rect2())
	var tiles := RecruitPanel.tile_rects(b.x, b.y, UnitTypes.count())
	for i in tiles.size():
		assert_true(tiles[i].size.y >= 12 and tiles[i].size.x >= 12, "kafelek ≥ 12×12")
		assert_true(tiles[i].end.y <= RecruitPanel.DETAIL_Y, "kafelki nad szczegółami")
		assert_true(9 + PixelFont.text_width(UnitTypes.SHORT_NAMES[i] + " 99+9") <= tiles[i].size.x,
				"„%s” mieści się na kafelku" % UnitTypes.SHORT_NAMES[i])
	assert_true(RecruitPanel.DETAIL_Y + RecruitPanel.DETAIL_LINES * (PixelFont.LINE + 2) <= Hud.row_y(VIEW),
			"szczegóły nad przyciskami")
	var T := RecruitPanel.Target
	var n := UnitTypes.count()
	assert_eq(RecruitPanel.target_at(tiles[n - 1].get_center(), VIEW, b.x, b.y, n), T.TILE + n - 1, "ostatni kafelek")
	assert_eq(RecruitPanel.target_at(RecruitPanel.train_rect(VIEW, b.y).get_center(), VIEW, b.x, b.y, n), T.TRAIN, "Szkol")
	return true


func test_hud_army_button_and_recruit_card() -> bool:
	var b := Hud.content_bounds(VIEW, Rect2())
	var army := Hud.column_rect(b.y, Hud.column_targets(false).find(Hud.Target.ARMY))
	assert_eq(Hud.target_at(army.get_center(), VIEW, b.y, false, false), Hud.Target.ARMY, "Wojsko w kolumnie")
	var card := Hud.card_rects(VIEW, true)
	assert_eq(card.size(), 4, "karta budynku rekrutacji: 4 przyciski")
	assert_true(card[0].position.x >= b.x and card[-1].end.x <= b.y, "karta mieści się na 320 px")
	assert_eq(Hud.target_at(card[2].get_center(), VIEW, b.y, false, true, true), Hud.Target.CARD + Hud.CardButton.RECRUIT,
			"trzeci przycisk: Szkol")
	assert_eq(Hud.target_at(card[3].get_center(), VIEW, b.y, false, true, true), Hud.Target.CARD + Hud.CardButton.CLOSE,
			"czwarty: Zamknij")
	var plain := Hud.card_rects(VIEW)
	assert_eq(Hud.target_at(plain[2].get_center(), VIEW, b.y, false, true), Hud.Target.CARD + Hud.CardButton.CLOSE,
			"zwykła karta: trzeci to Zamknij")
	return true


## Oddział ma jeden rodzaj jednostek; nowa jednostka trafia do wskazanego oddziału albo do nowego.
func test_training_into_existing_or_new_squad() -> bool:
	var c := _castle()
	var rec := Recruitment.new()
	var args: Array = [c["grid"], c["e"], c["goods"], c["r"], 0, T0]
	assert_eq(rec.callv("start", [U.ARCHER, c["range_a"], Recruitment.NEW_SQUAD] + args), Recruitment.Result.OK, "nowy oddział")
	var first := rec.last_squad
	assert_eq(rec.squads.size(), 1, "jeden oddział")
	assert_eq(rec.callv("start", [U.ARCHER, c["range_b"], first] + args), Recruitment.Result.OK, "do istniejącego")
	assert_eq(rec.squads.size(), 1, "dalej jeden oddział")
	assert_eq(rec.pending_for(first), 2, "dwóch w drodze do oddziału")
	assert_eq(rec.callv("start", [U.AXE_WARRIOR, c["barracks"], first] + args), Recruitment.Result.WRONG_SQUAD,
			"Topornik nie wejdzie do oddziału łuczników")
	rec.update(T0 + 10 * RecruitmentConfig.train_ms(U.ARCHER, 1))
	assert_eq(rec.squad(first).count, 2, "obaj łucznicy w tym samym oddziale")
	assert_eq(rec.default_squad(U.ARCHER), first, "domyślnie oddział z wolnym miejscem")
	assert_eq(rec.default_squad(U.RIDER), Recruitment.NEW_SQUAD, "bez oddziału: nowy")
	return true


## Rozmiar oddziału liczy też jednostki w szkoleniu.
func test_squad_size_limit() -> bool:
	var c := _castle()
	var rec := Recruitment.new()
	var full := rec.add_squad(U.ARCHER, RecruitmentConfig.SQUAD_SIZE - 1)
	var args: Array = [c["grid"], c["e"], c["goods"], c["r"], 0, T0]
	assert_eq(rec.free_in_squad(full), 1, "jedno wolne miejsce")
	assert_eq(rec.callv("start", [U.ARCHER, c["range_a"], full] + args), Recruitment.Result.OK, "ostatnie miejsce")
	assert_eq(rec.free_in_squad(full), 0, "zajęte przez szkolonego")
	assert_eq(rec.callv("start", [U.ARCHER, c["range_b"], full] + args), Recruitment.Result.SQUAD_FULL, "oddział pełny")
	assert_eq(rec.default_squad(U.ARCHER), Recruitment.NEW_SQUAD, "pełny oddział: domyślnie nowy")
	assert_eq(RecruitPanel.squad_label(rec, U.ARCHER, full), "1: 10/10", "napis z jednostkami w szkoleniu")
	return true


## Globalny limit: ile zamek może utrzymać, z wolnymi miejscami po odjęciu szkolonych.
func test_free_army_counts_training() -> bool:
	var c := _castle()
	var grid: BuildGrid = c["grid"]
	var rec := Recruitment.new()
	var limit := Recruitment.army_limit(grid)
	assert_eq(rec.free_army(grid), limit, "pusta armia: cały limit wolny")
	rec.add_squad(U.AXE_WARRIOR, 5)
	rec.callv("start", [U.ARCHER, c["range_a"], Recruitment.NEW_SQUAD, grid, c["e"], c["goods"], c["r"], 0, T0])
	assert_eq(rec.free_army(grid), limit - 6, "5 w armii i 1 w szkoleniu")
	return true


func test_empty_squad_disappears_with_its_building() -> bool:
	var c := _castle()
	var rec := Recruitment.new()
	rec.callv("start", [U.ARCHER, c["range_a"], Recruitment.NEW_SQUAD, c["grid"], c["e"], c["goods"], c["r"], 0, T0])
	assert_eq(rec.squads.size(), 1, "oddział powstał przy zleceniu")
	rec.drop_building(c["range_a"])
	assert_eq(rec.squads.size(), 0, "pusty oddział bez szkolonych znika")
	return true


func test_squad_picker_layout() -> bool:
	var b := Hud.content_bounds(VIEW, Rect2())
	var rects := RecruitPanel.squad_rects(b.x, b.y, 10)
	assert_true(rects.size() >= 4, "mieści się Nowy i co najmniej 3 oddziały")
	for r in rects:
		assert_true(r.size.x >= 12 and r.size.y >= 12, "cel ≥ 12×12")
		assert_true(r.position.x >= b.x and r.end.x <= b.y, "w granicach treści")
		assert_true(r.end.y <= Hud.row_y(VIEW), "nad przyciskami Szkol i Zamknij")
		assert_true(r.position.y >= RecruitPanel.DETAIL_Y + RecruitPanel.DETAIL_LINES * RecruitPanel.LINE_STEP,
				"pod szczegółami")
		assert_true(PixelFont.text_width("9: 10/10") <= r.size.x - 4, "napis oddziału mieści się")
	# review #156: telefon ze strefą bezpieczną zwęża treść; Nowy i 3 oddziały mieszczą się dalej
	for width: int in [200, 240]:
		var narrow := RecruitPanel.squad_rects(40, 40 + width, 10)
		assert_true(narrow.size() >= 4, "%d px treści: Nowy i co najmniej 3 oddziały" % width)
	var rec := Recruitment.new()
	var sq := rec.add_squad(U.ARCHER, 4)
	assert_eq(RecruitPanel.squad_options(rec, U.ARCHER), [Recruitment.NEW_SQUAD, sq] as Array[int], "Nowy i oddział łuczników")
	assert_eq(RecruitPanel.squad_options(rec, U.RIDER), [Recruitment.NEW_SQUAD] as Array[int], "konnica: tylko Nowy")
	assert_eq(RecruitPanel.target_at(rects[1].get_center(), VIEW, b.x, b.y, 13, 2), RecruitPanel.Target.SQUAD + 1,
			"dotknięcie oddziału")
	return true


## Review PR 146: Taran i Kopacz (inżynieria) szkolą się w Koszarach, choć Koszary to budynek
## klasy lekkiej; budynek bierze się z danych jednostki (UnitTypes.building), nie z klasy.
func test_engineering_trains_in_barracks() -> bool:
	var c := _castle()
	var rec := Recruitment.new()
	var args: Array = [c["grid"], c["e"], c["goods"], c["r"], 1, T0]
	assert_eq(rec.callv("start", [U.DIGGER, c["barracks"], Recruitment.NEW_SQUAD] + args), Recruitment.Result.OK,
			"Kopacz w Koszarach")
	assert_eq(rec.callv("start", [U.RAM, c["barracks"], Recruitment.NEW_SQUAD] + args), Recruitment.Result.OK,
			"Taran w Koszarach (epoka II)")
	assert_eq(rec.callv("start", [U.DIGGER, c["range_a"], Recruitment.NEW_SQUAD] + args), Recruitment.Result.NO_BUILDING,
			"Kopacz nie w Strzelnicy")
	return true


## check() mówi to samo co start(), ale niczego nie zmienia (przycisk Szkol gaśnie przy każdej
## przeszkodzie, review #147).
func test_check_matches_start_without_side_effects() -> bool:
	var c := _castle()
	var e: Economy = c["e"]
	var goods: Goods = c["goods"]
	var rec := Recruitment.new()
	assert_eq(rec.check_any(U.ARCHER, Recruitment.NEW_SQUAD, c["grid"], e, goods, c["r"], 0), Recruitment.Result.OK, "można")
	assert_eq(rec.orders.size(), 0, "check niczego nie kolejkuje")
	assert_eq(e.amounts[EconomyConfig.Res.FOOD], 1000, "check nie wydaje surowców")
	e.amounts[EconomyConfig.Res.FOOD] = 0
	assert_eq(rec.check_any(U.ARCHER, Recruitment.NEW_SQUAD, c["grid"], e, goods, c["r"], 0), Recruitment.Result.NO_RESOURCES,
			"bez żywności")
	assert_eq(rec.start_any(U.ARCHER, Recruitment.NEW_SQUAD, c["grid"], e, goods, c["r"], 0, T0), Recruitment.Result.NO_RESOURCES,
			"start mówi to samo")
	e.amounts[EconomyConfig.Res.FOOD] = 1000
	var squad := rec.add_squad(U.ARCHER, RecruitmentConfig.SQUAD_SIZE)
	assert_eq(rec.check(U.ARCHER, c["range_a"], squad, c["grid"], e, goods, c["r"], 0), Recruitment.Result.SQUAD_FULL,
			"pełny oddział")
	return true



## Jednostka poziomu 0 (po teście na telefonie): Chłop szkoli się w Koszarach od startu, bez
## technologii i bez towarów, za samą żywność; tylko w epoce I.
func test_peasant_needs_no_tech_and_no_goods() -> bool:
	var grid := BuildGrid.new(TerrainMap.generate(1337))
	grid.place_kind(_free_cell(grid, K.MANOR), K.MANOR, 1)
	var barracks := grid.place_kind(_free_cell(grid, K.BARRACKS), K.BARRACKS, 1)
	var e := Economy.new(T0)
	var goods := Goods.new(T0)
	var rec := Recruitment.new()
	assert_eq(UnitTypes.required_tech(U.PEASANT), "", "bez technologii")
	assert_true(UnitTypes.goods_cost(U.PEASANT).is_empty(), "bez towarów")
	var food := e.amounts[EconomyConfig.Res.FOOD]
	assert_eq(rec.start(U.PEASANT, barracks, Recruitment.NEW_SQUAD, grid, e, goods, Research.new(), 0, T0),
			Recruitment.Result.OK, "od startu, bez badań i pustą zbrojownią")
	assert_eq(e.amounts[EconomyConfig.Res.FOOD], food - 5, "zeszło 5 żywności (review #158)")
	assert_eq(rec.availability(U.PEASANT, grid, Research.new(), 1), Recruitment.Result.ERA_PASSED, "w epoce II już nie")
	assert_eq(rec.check(U.PEASANT, barracks, Recruitment.NEW_SQUAD, grid, e, goods, Research.new(), 1),
			Recruitment.Result.ERA_PASSED, "check w epoce II")
	assert_eq(rec.start(U.PEASANT, barracks, Recruitment.NEW_SQUAD, grid, e, goods, Research.new(), 1, T0),
			Recruitment.Result.ERA_PASSED, "start w epoce II")
	assert_eq(RecruitPanel.units_for(-1)[0], U.PEASANT, "pierwszy na liście Wojsko")
	assert_eq(RecruitPanel.units_for(K.BARRACKS)[0], U.PEASANT, "pierwszy w Koszarach")
	assert_eq(Recruitment.MESSAGES.size(), Recruitment.Result.size(), "komunikat dla każdego wyniku")
	return true


## Telefon: długie teksty w szczegółach zawijają się po słowach i nie wychodzą poza ekran.
func test_long_details_wrap_inside_the_panel() -> bool:
	var g := Goods.new(T0)
	for width: int in [200, 240, 296]:
		var missing := RecruitPanel.missing_text(U.REFLEX_ARCHER, g)
		var lines := RecruitPanel.detail_lines(UnitTypes.unit_name(U.REFLEX_ARCHER), "Epoka II",
				"Koszt: " + RecruitPanel.cost_text(U.REFLEX_ARCHER) + ", 0:35", missing, Palette.ACCENT, width)
		assert_true(lines.size() <= RecruitPanel.DETAIL_LINES, "najwyżej %d linii przy %d px" % [RecruitPanel.DETAIL_LINES, width])
		for l: Array in lines:
			var w := PixelFont.text_width(l[0] as String)
			if not (l[2] as String).is_empty():
				w += 6 + PixelFont.text_width(l[2] as String)
			assert_true(w <= width, "linia „%s” mieści się w %d px" % [l[0], width])
		var has_missing := false
		for l: Array in lines:
			if (l[1] as Color) == Palette.ACCENT:
				has_missing = true
		assert_true(has_missing, "braki widać przy %d px" % width)
	assert_true(RecruitPanel.DETAIL_Y + RecruitPanel.DETAIL_LINES * RecruitPanel.LINE_STEP <= Hud.row_y(VIEW),
			"szczegóły nad rzędem przycisków")
	return true


func test_wrap_splits_on_words() -> bool:
	var lines := PixelFont.wrap("jeden dwa trzy cztery piec szesc", PixelFont.text_width("jeden dwa"))
	assert_eq(lines[0], "jeden dwa", "pierwsza linia")
	assert_true(lines.size() >= 3, "kilka linii")
	var cut := PixelFont.wrap("jeden dwa trzy cztery piec szesc", PixelFont.text_width("jeden dwa"), 2)
	assert_eq(cut.size(), 2, "limit linii")
	assert_true(cut[1].ends_with("..."), "ucięty tekst kończy się kropkami")
	assert_eq(PixelFont.wrap("", 50).size(), 0, "pusty tekst")
	assert_eq(PixelFont.wrap("bardzo dlugi tekst", 2, 1)[0], "", "szerokość mniejsza niż wielokropek: pusto, nic nie wystaje")
	return true


## Telefon: braki Drużynnika (trzy towary jednego wytwórcy) mieszczą się w dwóch liniach, bez ucinania.
## Nazwa budynku pada raz na grupę towarów.
func test_missing_goods_fit_in_two_lines() -> bool:
	var g := Goods.new(T0)
	var miss := RecruitPanel.missing_text(U.GAMBESON_WARRIOR, g)
	assert_eq(miss.count("Wytwórca zbroi skórzanych"), 1, "budynek raz na grupę")
	assert_true(miss.contains("Przeszywanica") and miss.contains("Tarcza") and miss.contains("Zbroja skórzana"), "wszystkie towary")
	for width: int in [240, 296]:
		for unit in UnitTypes.count():
			var m := RecruitPanel.missing_text(unit, g)
			if m.is_empty():
				continue
			var cost := "Koszt: " + RecruitPanel.cost_text(unit) + ", 0:50"
			var lines := RecruitPanel.detail_lines(UnitTypes.unit_name(unit), "zbadaj A46", cost, m, Palette.ACCENT, width)
			var shown := PackedStringArray()
			for l: Array in lines:
				if (l[1] as Color) == Palette.ACCENT:
					shown.append(l[0] as String)
			assert_true(shown.size() <= RecruitPanel.EXTRA_LINES, "%s: braki w najwyżej 2 liniach" % UnitTypes.unit_name(unit))
			assert_eq(" ".join(shown), m, "%s przy %d px: braki w całości, bez ucinania" % [UnitTypes.unit_name(unit), width])
	return true
