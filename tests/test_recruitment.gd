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
	assert_eq(RecruitPanel.units_for(K.BARRACKS), [U.AXE_WARRIOR, U.JAVELINEER, U.SPEARMAN, U.RAM, U.DIGGER] as Array[int],
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
	assert_eq(RecruitPanel.target_at(tiles[12].get_center(), VIEW, b.x, b.y, 13), T.TILE + 12, "ostatni kafelek")
	assert_eq(RecruitPanel.target_at(RecruitPanel.train_rect(VIEW, b.y).get_center(), VIEW, b.x, b.y, 13), T.TRAIN, "Szkol")
	return true


func test_hud_army_button_and_recruit_card() -> bool:
	var b := Hud.content_bounds(VIEW, Rect2())
	var army := Hud.army_rect(VIEW, b.x)
	assert_true(not army.intersects(Hud.left_corner_rect(VIEW, b.x)), "Wojsko obok Oblężenia")
	assert_true(not army.intersects(Hud.research_rect(VIEW, b.y)), "Wojsko nie na Badaniach")
	assert_eq(Hud.target_at(army.get_center(), VIEW, b.x, b.y, false, false, 0), Hud.Target.ARMY, "Wojsko")
	var card := Hud.card_rects(VIEW, true)
	assert_eq(card.size(), 4, "karta budynku rekrutacji: 4 przyciski")
	assert_true(card[0].position.x >= b.x and card[-1].end.x <= b.y, "karta mieści się na 320 px")
	assert_eq(Hud.target_at(card[2].get_center(), VIEW, b.x, b.y, false, true, 0, true), Hud.Target.CARD + Hud.CardButton.RECRUIT,
			"trzeci przycisk: Szkol")
	assert_eq(Hud.target_at(card[3].get_center(), VIEW, b.x, b.y, false, true, 0, true), Hud.Target.CARD + Hud.CardButton.CLOSE,
			"czwarty: Zamknij")
	var plain := Hud.card_rects(VIEW)
	assert_eq(Hud.target_at(plain[2].get_center(), VIEW, b.x, b.y, false, true, 0), Hud.Target.CARD + Hud.CardButton.CLOSE,
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
		assert_true(r.end.x <= b.y, "w granicach treści")
		assert_true(r.end.y <= Hud.row_y(VIEW), "nad przyciskami Szkol i Zamknij")
		assert_true(PixelFont.text_width("9: 10/10") <= r.size.x - 4, "napis oddziału mieści się")
	var rec := Recruitment.new()
	var sq := rec.add_squad(U.ARCHER, 4)
	assert_eq(RecruitPanel.squad_options(rec, U.ARCHER), [Recruitment.NEW_SQUAD, sq] as Array[int], "Nowy i oddział łuczników")
	assert_eq(RecruitPanel.squad_options(rec, U.RIDER), [Recruitment.NEW_SQUAD] as Array[int], "konnica: tylko Nowy")
	assert_eq(RecruitPanel.target_at(rects[1].get_center(), VIEW, b.x, b.y, 13, 2), RecruitPanel.Target.SQUAD + 1,
			"dotknięcie oddziału")
	return true
