extends TestCase
## Lista Wojsko pokazuje tylko jednostki, które da się szkolić (#376). Jednostki bez technologii,
## bez budynku, z wyższej epoki i „tylko epoka I” po epoce I są ukryte. Jednostka zablokowana,
## którą gracz ma w armii albo w szkoleniu, zostaje na liście. Budynek bez dostępnych jednostek
## nie pokazuje przycisku Szkol.

const K := BuildingTypes.Kind
const U := UnitTypes.Unit


func _free_cell(grid: BuildGrid, kind: int) -> Vector2i:
	var c := grid.terrain.center()
	for r in grid.terrain.size:
		for dy in range(-r, r + 1):
			for dx in range(-r, r + 1):
				var p := c + Vector2i(dx, dy)
				if grid.placement_for(p, kind) != Rect2i():
					return p
	return Vector2i(-1, -1)


func _grid() -> BuildGrid:
	var grid := BuildGrid.new(TerrainMap.generate(1337))
	grid.place_kind(_free_cell(grid, K.MANOR), K.MANOR, 5)
	grid.place_kind(_free_cell(grid, K.BARRACKS), K.BARRACKS, 1)
	return grid


func test_only_available_units_are_listed() -> bool:
	var grid := _grid()
	var rec := Recruitment.new()
	var res := Research.new()
	var list := RecruitPanel.visible_units(-1, rec, grid, res, 0)
	assert_true(not list.is_empty(), "coś da się szkolić w Koszarach")
	for unit: int in list:
		assert_eq(rec.availability(unit, grid, res, 0), Recruitment.Result.OK,
				"%s na liście tylko, gdy da się szkolić" % UnitTypes.unit_name(unit))
	assert_true(list.has(U.AXE_WARRIOR), "Wojownik z toporem: Koszary bez badań")
	assert_true(not list.has(U.ARCHER), "Łucznik ukryty bez Strzelnicy")
	assert_true(not list.has(U.SHIELDBEARER), "Tarczownik ukryty bez A21 i Domu drużyny")
	for unit in UnitTypes.count():
		if UnitTypes.age(unit) > 0:
			assert_true(not list.has(unit), "%s z wyższej epoki ukryty" % UnitTypes.unit_name(unit))
	return true


func test_unit_appears_after_building_and_tech() -> bool:
	var grid := _grid()
	var rec := Recruitment.new()
	var res := Research.new()
	assert_true(not RecruitPanel.visible_units(-1, rec, grid, res, 0).has(U.ARCHER), "bez Strzelnicy ukryty")
	grid.place_kind(_free_cell(grid, K.ARCHERY_RANGE), K.ARCHERY_RANGE, 1)
	assert_true(RecruitPanel.visible_units(-1, rec, grid, res, 0).has(U.ARCHER), "po Strzelnicy widoczny")
	grid.place_kind(_free_cell(grid, K.WARBAND_HOUSE), K.WARBAND_HOUSE, 1)
	assert_true(not RecruitPanel.visible_units(-1, rec, grid, res, 0).has(U.SHIELDBEARER), "bez A21 ukryty")
	res.done["A21"] = true
	assert_true(RecruitPanel.visible_units(-1, rec, grid, res, 0).has(U.SHIELDBEARER), "po A21 widoczny")
	return true


func test_order_follows_units_for() -> bool:
	var grid := _grid()
	var rec := Recruitment.new()
	var res := Research.new()
	var list := RecruitPanel.visible_units(-1, rec, grid, res, 0)
	var expected: Array[int] = []
	for unit: int in RecruitPanel.units_for(-1):
		if list.has(unit):
			expected.append(unit)
	assert_eq(list, expected, "kolejność jak w units_for")
	return true


func test_owned_locked_unit_stays_visible() -> bool:
	var grid := _grid()
	var rec := Recruitment.new()
	var res := Research.new()
	assert_true(RecruitPanel.visible_units(-1, rec, grid, res, 0).has(U.PEASANT) \
			== (rec.availability(U.PEASANT, grid, res, 0) == Recruitment.Result.OK), "Chłop w epoce I wg dostępności")
	assert_true(not RecruitPanel.visible_units(-1, rec, grid, res, 1).has(U.PEASANT), "Chłop po epoce I ukryty")
	rec.add_squad(U.PEASANT, 3)
	assert_true(RecruitPanel.visible_units(-1, rec, grid, res, 1).has(U.PEASANT), "posiadany Chłop zostaje")
	assert_true(not RecruitPanel.visible_units(-1, rec, grid, res, 0).has(U.ARCHER), "Łucznik ukryty")
	rec.add_squad(U.ARCHER, 1)
	assert_true(RecruitPanel.visible_units(-1, rec, grid, res, 0).has(U.ARCHER), "posiadany Łucznik zostaje")
	assert_true(not RecruitPanel.visible_units(K.BARRACKS, rec, grid, res, 0).has(U.ARCHER),
			"w trybie budynku tylko jego jednostki")
	return true


func test_unit_in_training_stays_visible() -> bool:
	var grid := _grid()
	var rec := Recruitment.new()
	var res := Research.new()
	var order := Recruitment.Order.new()
	order.unit = U.ARCHER
	rec.orders.append(order)
	assert_true(RecruitPanel.visible_units(-1, rec, grid, res, 0).has(U.ARCHER), "Łucznik w szkoleniu zostaje")
	return true


func test_building_card_hides_train_without_units() -> bool:
	var grid := _grid()
	var rec := Recruitment.new()
	var res := Research.new()
	assert_true(RecruitPanel.recruits_now(K.BARRACKS, rec, grid, res, 0), "Koszary: jest kogo szkolić")
	grid.place_kind(_free_cell(grid, K.WARBAND_HOUSE), K.WARBAND_HOUSE, 1)
	assert_true(not RecruitPanel.recruits_now(K.WARBAND_HOUSE, rec, grid, res, 0), "Dom drużyny bez A21: bez Szkol")
	res.done["A21"] = true
	assert_true(RecruitPanel.recruits_now(K.WARBAND_HOUSE, rec, grid, res, 0), "po A21 Szkol wraca")
	assert_true(not RecruitPanel.recruits_now(K.MANOR, rec, grid, res, 0), "Dwór nie szkoli")
	return true
