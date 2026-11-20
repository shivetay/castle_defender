extends TestCase
## Utrzymanie armii z produkcji żywności (#214): każda jednostka ma koszt utrzymania w Ży/h,
## suma utrzymania (wyszkoleni i szkoleni) nie przekracza produkcji żywności, a limit miejsc
## (Dwór i Koszary) działa niezależnie i jednocześnie. Armia je: utrzymanie schodzi z produkcji,
## a po końcu zapasu jednostki odchodzą z głodu.

const T0 := 1_700_000_000_000
const K := BuildingTypes.Kind
const U := UnitTypes.Unit
const R := EconomyConfig.Res
const HOUR := 3600 * 1000


func _free_cell(grid: BuildGrid, kind: int, near_water: bool = false) -> Vector2i:
	for y in grid.terrain.size - 1:
		for x in grid.terrain.size - 1:
			var placed := grid.placement_for(Vector2i(x, y), kind)
			if placed != Rect2i() and (not near_water or grid.touches_water(placed)):
				return Vector2i(x, y)
	return Vector2i(-1, -1)


## Zamek z Dworem `manor` i Koszarami 5 (długa kolejka), bogaty w surowce, bez badań premii.
func _castle(manor: int) -> Dictionary:
	var grid := BuildGrid.new(TerrainMap.generate(1337))
	grid.place_kind(_free_cell(grid, K.MANOR), K.MANOR, manor)
	var barracks := grid.place_kind(_free_cell(grid, K.BARRACKS), K.BARRACKS, 5)
	var e := Economy.new(T0)
	for res in EconomyConfig.count():
		e.amounts[res] = 1000
	var goods := Goods.new(T0)
	for good in GoodsConfig.count():
		goods.amounts[good] = 500
	return {"grid": grid, "e": e, "goods": goods, "r": Research.new(), "barracks": barracks}


func _train(rec: Recruitment, c: Dictionary, unit: int = U.PEASANT, age: int = 0) -> Recruitment.Result:
	return rec.start(unit, c["barracks"], Recruitment.NEW_SQUAD, c["grid"], c["e"], c["goods"], c["r"], age, T0)


## Zapełnia armię wyszkolonymi chłopami do utrzymania `food` (oddziały po SQUAD_SIZE).
func _fill(rec: Recruitment, food: int) -> void:
	var left := food
	while left > 0:
		var n := mini(left, RecruitmentConfig.SQUAD_SIZE)
		rec.add_squad(U.PEASANT, n)
		left -= n


## Kryterium: każda jednostka MVP ma w danych koszt utrzymania (niezerowy albo jawnie zerowy).
func test_every_unit_has_upkeep() -> bool:
	assert_eq(UnitTypes.UPKEEP.size(), UnitTypes.count(), "wpis dla każdej jednostki")
	for unit in UnitTypes.count():
		assert_true(UnitTypes.upkeep(unit) >= 0, "%s: nieujemne" % UnitTypes.unit_name(unit))
	assert_eq(UnitTypes.upkeep(U.RAM), 0, "Taran jawnie bez żywności")
	assert_true(UnitTypes.upkeep(U.RIDER) > UnitTypes.upkeep(U.AXE_WARRIOR), "konny je więcej niż pieszy")
	return true


## Limit utrzymania to produkcja żywności z siatki (sam gród na start).
func test_limit_is_food_production() -> bool:
	var c := _castle(1)
	var grid: BuildGrid = c["grid"]
	assert_eq(Recruitment.upkeep_limit(grid, c["r"]), Economy.rates(grid, c["r"])[R.FOOD], "limit = Ży/h")
	assert_eq(Recruitment.upkeep_limit(grid, c["r"]), EconomyConfig.BASE_PER_HOUR[R.FOOD], "sam gród")
	return true


## Utrzymanie liczy wyszkolonych i szkolonych.
func test_upkeep_counts_army_and_training() -> bool:
	var c := _castle(5)
	var rec := Recruitment.new()
	rec.add_squad(U.RIDER, 3)
	assert_eq(rec.upkeep_used(), 3 * UnitTypes.upkeep(U.RIDER), "wyszkoleni")
	assert_eq(_train(rec, c), Recruitment.Result.OK, "szkolenie")
	assert_eq(rec.upkeep_used(), 3 * UnitTypes.upkeep(U.RIDER) + UnitTypes.upkeep(U.PEASANT), "plus szkoleni")
	return true


## Kryterium: rekrutacja na limicie. Ostatnie miejsce w utrzymaniu przechodzi, kolejne nie, mimo
## wolnych miejsc w armii; stan się nie zmienia, koszt nie schodzi.
func test_recruit_at_upkeep_limit() -> bool:
	var c := _castle(5)
	var grid: BuildGrid = c["grid"]
	var e: Economy = c["e"]
	var rec := Recruitment.new()
	var limit := Recruitment.upkeep_limit(grid, c["r"])
	assert_true(Recruitment.army_limit(grid) > limit, "miejsc w armii więcej niż żywności")
	_fill(rec, limit - UnitTypes.upkeep(U.PEASANT))
	assert_eq(_train(rec, c), Recruitment.Result.OK, "ostatnia porcja żywności")
	assert_eq(rec.free_upkeep(grid, c["r"]), 0, "utrzymanie pełne")
	assert_true(rec.free_army(grid) > 0, "miejsca w armii zostały")
	var food := e.amounts[R.FOOD]
	var orders := rec.orders.size()
	assert_eq(_train(rec, c), Recruitment.Result.NO_UPKEEP, "ponad produkcję nie")
	assert_eq(rec.check(U.PEASANT, c["barracks"], Recruitment.NEW_SQUAD, grid, e, c["goods"], c["r"], 0),
			Recruitment.Result.NO_UPKEEP, "przycisk Szkol gaśnie")
	assert_eq(rec.orders.size(), orders, "nic nie doszło do kolejki")
	assert_eq(e.amounts[R.FOOD], food, "koszt nie zszedł")
	(c["r"] as Research).done["A6"] = true
	assert_eq(_train(rec, c, U.RAM, 1), Recruitment.Result.OK, "Taran (epoka II) nie je, więc przechodzi")
	return true


## Jednostka droższa w utrzymaniu niż wolna reszta nie przechodzi, tańsza tak.
func test_cavalry_needs_more_room() -> bool:
	var c := _castle(5)
	var grid: BuildGrid = c["grid"]
	var r: Research = c["r"]
	r.done["A7"] = true
	var stable := grid.place_kind(_free_cell(grid, K.STABLE), K.STABLE, 5)
	var rec := Recruitment.new()
	_fill(rec, Recruitment.upkeep_limit(grid, r) - 1)
	assert_eq(rec.free_upkeep(grid, r), 1, "zostaje 1 Ży/h")
	assert_eq(rec.start(U.RIDER, stable, Recruitment.NEW_SQUAD, grid, c["e"], c["goods"], r, 0, T0),
			Recruitment.Result.NO_UPKEEP, "Jeździec (2) się nie mieści")
	assert_eq(_train(rec, c), Recruitment.Result.OK, "Chłop (1) tak")
	return true


## Kryterium: limit rośnie po postawieniu i ulepszeniu źródła żywności (Rybak).
func test_limit_grows_with_fisher() -> bool:
	var c := _castle(5)
	var grid: BuildGrid = c["grid"]
	var rec := Recruitment.new()
	var base := Recruitment.upkeep_limit(grid, c["r"])
	_fill(rec, base)
	assert_eq(_train(rec, c), Recruitment.Result.NO_UPKEEP, "przed Rybakiem pełne")
	var spot := _free_cell(grid, K.FISHER, true)
	assert_true(spot.x >= 0, "jest miejsce przy wodzie")
	var fisher := grid.place_kind(spot, K.FISHER, 1)
	var per_level: Array = (EconomyConfig.BUILDING_PRODUCTION[K.FISHER] as Array)[1]
	assert_eq(Recruitment.upkeep_limit(grid, c["r"]), base + int(per_level[0]), "Rybak 1 podnosi limit")
	assert_eq(_train(rec, c), Recruitment.Result.OK, "po Rybaku można szkolić")
	grid.levels[fisher] = 3
	assert_eq(Recruitment.upkeep_limit(grid, c["r"]), base + int(per_level[2]), "ulepszenie podnosi dalej")
	return true


## Kryterium: spadek produkcji poniżej utrzymania (rozbiórka Rybaka). Armia zostaje (bez
## dezercji w MVP), szkolenie jest zablokowane, a ekran i okienko limitu to pokazują.
func test_production_drop_blocks_recruitment() -> bool:
	var c := _castle(5)
	var grid: BuildGrid = c["grid"]
	var r: Research = c["r"]
	var fisher := grid.place_kind(_free_cell(grid, K.FISHER, true), K.FISHER, 2)
	var rec := Recruitment.new()
	# konni (2 Ży/h), żeby utrzymanie doszło do granicy przed limitem miejsc
	@warning_ignore("integer_division")
	var riders := Recruitment.upkeep_limit(grid, r) / UnitTypes.upkeep(U.RIDER)
	while riders > 0:
		var n := mini(riders, RecruitmentConfig.SQUAD_SIZE)
		rec.add_squad(U.RIDER, n)
		riders -= n
	assert_eq(rec.upkeep_used(), Recruitment.upkeep_limit(grid, r), "utrzymanie równe produkcji")
	assert_true(rec.free_army(grid) > 0, "miejsca w armii zostały")
	var army := rec.army_size()
	assert_true(not rec.over_upkeep(grid, r), "na granicy, jeszcze nie ponad")
	grid.remove(fisher)
	assert_true(rec.over_upkeep(grid, r), "po rozbiórce utrzymanie ponad produkcją")
	assert_eq(rec.free_upkeep(grid, r), 0, "nic wolnego")
	assert_eq(rec.army_size(), army, "armia zostaje")
	assert_eq(_train(rec, c), Recruitment.Result.NO_UPKEEP, "szkolenie zablokowane")
	assert_true(RecruitPanel.limit_warning(rec, grid, r), "licznik w tytule ostrzega")
	var text := " | ".join(InfoText.army(grid, rec, r))
	assert_true(text.contains("Za mało żywności"), "okienko mówi, co się stało: %s" % text)
	assert_true(text.contains(BuildingTypes.NAMES[K.FISHER]), "i jak to naprawić")
	return true


## Kryterium: limit miejsc (Dwór i Koszary) i limit utrzymania działają niezależnie i jednocześnie.
## Przy małym Dworze blokuje limit miejsc mimo wolnej żywności, przy dużym blokuje żywność.
func test_army_and_upkeep_limits_are_independent() -> bool:
	var small := _castle(1)
	var grid: BuildGrid = small["grid"]
	var rec := Recruitment.new()
	var places := Recruitment.army_limit(grid)
	assert_true(places * UnitTypes.upkeep(U.RAM) < Recruitment.upkeep_limit(grid, small["r"]), "Taran nie zjada żywności")
	var left := places
	while left > 0:
		var n := mini(left, RecruitmentConfig.SQUAD_SIZE)
		rec.add_squad(U.RAM, n)
		left -= n
	assert_eq(rec.upkeep_used(), 0, "Tarany bez utrzymania")
	assert_eq(_train(rec, small), Recruitment.Result.ARMY_FULL, "miejsca pełne mimo żywności")
	var big := _castle(5)
	var rec2 := Recruitment.new()
	_fill(rec2, Recruitment.upkeep_limit(big["grid"], big["r"]))
	assert_true(rec2.free_army(big["grid"]) > 0, "miejsca wolne")
	assert_eq(_train(rec2, big), Recruitment.Result.NO_UPKEEP, "żywność pełna mimo miejsc")
	return true


## Determinizm: ten sam zamek i ta sama armia dają ten sam limit i ten sam wynik.
func test_upkeep_is_deterministic() -> bool:
	var a := _castle(3)
	var b := _castle(3)
	var ra := Recruitment.new()
	var rb := Recruitment.new()
	_fill(ra, 15)
	_fill(rb, 15)
	assert_eq(Recruitment.upkeep_limit(a["grid"], a["r"]), Recruitment.upkeep_limit(b["grid"], b["r"]), "limit")
	assert_eq(ra.free_upkeep(a["grid"], a["r"]), rb.free_upkeep(b["grid"], b["r"]), "wolne")
	assert_eq(_train(ra, a), _train(rb, b), "wynik szkolenia")
	return true


## Tytuł ekranu Wojsko pokazuje utrzymanie względem produkcji i mieści się w celu dotyku.
func test_title_shows_upkeep() -> bool:
	var c := _castle(5)
	var grid: BuildGrid = c["grid"]
	var rec := Recruitment.new()
	rec.add_squad(U.RIDER, 10)
	rec.add_squad(U.RIDER, 10)
	var title := RecruitPanel.title_text(rec, grid, c["r"])
	assert_eq(title, "Wojsko %d/%d Ży %d/%d (?)" % [20, Recruitment.army_limit(grid), rec.upkeep_used(),
			Recruitment.upkeep_limit(grid, c["r"])], "miejsca i utrzymanie")
	var limit := RecruitPanel.limit_rect(Hud.CORNER_INSET, 320 - Hud.CORNER_INSET)
	assert_true(PixelFont.text_width("Wojsko 100/100 Ży 999/999 (?)") <= limit.size.x, "długi tytuł się mieści")
	return true


## Wyszkolona armia je: bilans żywności to produkcja minus utrzymanie (szkoleni jeszcze nie jedzą).
func test_army_eats_food() -> bool:
	var c := _castle(5)
	var grid: BuildGrid = c["grid"]
	var rec := Recruitment.new()
	_fill(rec, 8)
	assert_eq(_train(rec, c), Recruitment.Result.OK, "jeden w szkoleniu")
	assert_eq(rec.army_upkeep(), 8, "je tylko wyszkolona armia")
	var gross := Economy.rates(grid, c["r"])[R.FOOD]
	assert_eq(Economy.net_rates(grid, c["r"], rec.army_upkeep())[R.FOOD], gross - 8, "bilans netto")
	var e := Economy.new(T0)
	e.amounts[R.FOOD] = 100
	e.update(T0 + HOUR, Economy.net_rates(grid, c["r"], rec.army_upkeep()))
	assert_eq(e.amounts[R.FOOD], 100 + gross - 8, "po godzinie")
	return true


## Ujemny bilans zjada zapas, a dopiero po jego końcu liczy się głód.
func test_negative_balance_eats_stock_then_starves() -> bool:
	var e := Economy.new(T0)
	var rates: Array[int] = [0, 0, -10, 0]
	e.amounts[R.FOOD] = 5
	e.update(T0 + HOUR / 4, rates)
	assert_eq(e.amounts[R.FOOD], 2, "kwadrans: zeszło 2,5, zostaje 2 i ułamek")
	assert_eq(e.starved_ms, 0, "jeszcze bez głodu")
	e.update(T0 + HOUR, rates)
	assert_eq(e.amounts[R.FOOD], 0, "zapas pusty")
	assert_eq(e.starved_ms, HOUR / 2, "głód od chwili, gdy zabrakło (po 30 min)")
	return true


## Kryterium: spadek produkcji poniżej utrzymania. Zapas schodzi, potem co DESERT_MS odchodzi jedna
## jednostka z najmłodszego oddziału, aż armia mieści się w produkcji; potem głód się zeruje.
func test_starvation_makes_units_desert() -> bool:
	var c := _castle(5)
	var grid: BuildGrid = c["grid"]
	var r: Research = c["r"]
	var gross := Recruitment.upkeep_limit(grid, r)
	var rec := Recruitment.new()
	rec.add_squad(U.AXE_WARRIOR, 10)
	rec.add_squad(U.PEASANT, 10)
	var young := rec.add_squad(U.PEASANT, 10)
	rec.add_squad(U.RAM, 3)
	var over := rec.army_upkeep() - gross
	assert_true(over > 0, "armia je więcej, niż zamek produkuje")
	var e := Economy.new(T0)
	e.amounts[R.FOOD] = 0
	e.update(T0 + 3 * RecruitmentConfig.DESERT_MS, Economy.net_rates(grid, r, rec.army_upkeep()))
	var gone := rec.starve(e, grid, r)
	assert_eq(gone.size(), mini(3, over), "jedna jednostka na każdą godzinę głodu")
	assert_eq(rec.squad(young).count, 10 - gone.size(), "odchodzą najmłodsi")
	assert_eq(rec.army_of(U.RAM), 3, "Taran nie je, więc nie odchodzi")
	e.update(T0 + 100 * RecruitmentConfig.DESERT_MS, Economy.net_rates(grid, r, rec.army_upkeep()))
	rec.starve(e, grid, r)
	assert_eq(rec.army_upkeep(), gross, "odchodzą tylko do granicy produkcji")
	assert_eq(e.starved_ms, 0, "po wyrównaniu głód się zeruje")
	assert_eq(Economy.net_rates(grid, r, rec.army_upkeep())[R.FOOD], 0, "bilans zero")
	return true


## Bez ujemnego bilansu nie ma głodu ani dezercji, nawet przy pustym magazynie.
func test_no_desertion_without_deficit() -> bool:
	var c := _castle(5)
	var rec := Recruitment.new()
	_fill(rec, 10)
	var e := Economy.new(T0)
	e.amounts[R.FOOD] = 0
	e.update(T0 + 10 * HOUR, Economy.net_rates(c["grid"], c["r"], rec.army_upkeep()))
	assert_eq(rec.starve(e, c["grid"], c["r"]).size(), 0, "nikt nie odchodzi")
	assert_eq(rec.army_size(), 10, "armia cała")
	return true


## Determinizm: głód i dezercja wychodzą tak samo przy naliczaniu co minutę i jednym skokiem.
func test_starvation_same_in_steps_and_jump() -> bool:
	var results: Array = []
	for step: int in [60 * 1000, 10 * HOUR]:
		var c := _castle(5)
		var grid: BuildGrid = c["grid"]
		var rec := Recruitment.new()
		rec.add_squad(U.RIDER, 10)
		rec.add_squad(U.RIDER, 10)
		var e := Economy.new(T0)
		e.amounts[R.FOOD] = 7
		var t := T0
		while t < T0 + 10 * HOUR:
			t += step
			e.update(t, Economy.net_rates(grid, c["r"], rec.army_upkeep()))
			rec.starve(e, grid, c["r"])
		results.append([rec.army_size(), e.amounts[R.FOOD], e.starved_ms])
	assert_eq(results[0], results[1], "co minutę i jednym skokiem")
	return true


## Głód przetrwa zapis i odczyt.
func test_starvation_saved() -> bool:
	var e := Economy.new(T0)
	e.starved_ms = 1234
	var loaded := Economy.new(T0)
	loaded.load_data(e.save_data())
	assert_eq(loaded.starved_ms, 1234, "głód w zapisie")
	return true


## Okienko żywności pokazuje utrzymanie armii, bilans i ostrzeżenie o głodzie.
func test_food_popup_shows_upkeep() -> bool:
	var c := _castle(5)
	var grid: BuildGrid = c["grid"]
	var amounts: Array[int] = [0, 0, 50, 0]
	var gross := Economy.rates(grid, c["r"])[R.FOOD]
	var text := " | ".join(InfoText.resource(R.FOOD, grid, c["r"], amounts, gross + 10))
	assert_true(text.contains("Produkcja: -10 na godzinę"), "bilans ujemny: %s" % text)
	assert_true(text.contains("- utrzymanie armii: -%d" % (gross + 10)), "utrzymanie w rozbiciu")
	assert_true(text.contains("Zapas skończy się za") and text.contains("odchodzą"), "ostrzeżenie")
	amounts[R.FOOD] = 0
	text = " | ".join(InfoText.resource(R.FOOD, grid, c["r"], amounts, gross + 10))
	assert_true(text.contains("Brak żywności"), "pusty zapas: %s" % text)
	return true
