extends TestCase
## Zwiadowca i Dom zwiadowców (#92): konny zwiad epoki II z notatek Jednostki oraz Klasy jednostek
## i produkcja. Chata tropicieli (#28) stoi od S1 i po S3 staje się Domem zwiadowców, a Zwiadowca
## szkoli się tylko w niej, za konia
## ze Stajni i siodło od Rymarza. Grafikę (5 poziomów, 4 stany, paleta) sprawdza test_buildings
## dla wszystkich rodzajów.

const T0 := 1_700_000_000_000
const K := BuildingTypes.Kind
const U := UnitTypes.Unit
const G := GoodsConfig.Good
const R := EconomyConfig.Res
const RES := Recruitment.Result


func _free_cell(grid: BuildGrid, kind: int) -> Vector2i:
	var c := grid.terrain.center()
	for r in grid.terrain.size:
		for dy in range(-r, r + 1):
			for dx in range(-r, r + 1):
				var p := c + Vector2i(dx, dy)
				if grid.placement_for(p, kind) != Rect2i():
					return p
	return Vector2i(-1, -1)


func _rich() -> Array:
	var e := Economy.new(T0)
	for res in EconomyConfig.count():
		e.amounts[res] = 1000
	var goods := Goods.new(T0)
	for good in GoodsConfig.count():
		goods.amounts[good] = 50
	return [e, goods]


func test_scout_stats_from_the_note() -> bool:
	assert_eq(UnitTypes.unit_name(U.SCOUT), "Zwiadowca", "nazwa")
	assert_eq(UnitTypes.unit_class(U.SCOUT), RecruitmentConfig.UnitClass.SPECIAL, "klasa specjalna")
	assert_eq(UnitTypes.age(U.SCOUT), 1, "epoka II")
	assert_eq(UnitTypes.hp(U.SCOUT), 35, "35 HP")
	assert_eq(UnitTypes.attack(U.SCOUT), 2, "atak 2")
	assert_eq(UnitTypes.speed(U.SCOUT), 5, "szybkość 5")
	assert_eq(UnitTypes.required_tech(U.SCOUT), "S3", "wymaga S3")
	assert_eq(UnitTypes.building(U.SCOUT), K.SCOUT_HOUSE, "szkoli się w Domu zwiadowców")
	assert_eq(UnitTypes.building(U.TRACKER), K.SCOUT_HOUSE, "Tropiciel w Chacie tropicieli (#28)")
	assert_eq(UnitTypes.goods_cost(U.SCOUT), {G.HORSE: 1, G.SADDLE: 1}, "koń i siodło, bez metalu")
	assert_eq(UnitTypes.unit_class(U.TRACKER), RecruitmentConfig.UnitClass.SPECIAL, "Tropiciel zostaje osobną jednostką")
	return true


func test_scout_house_needs_s1_and_becomes_scout_house_with_s3() -> bool:
	assert_eq(BuildConfig.required_tech(K.SCOUT_HOUSE), "S1", "Chata tropicieli wymaga S1 (#28)")
	assert_eq(BuildingTypes.NAMES[K.SCOUT_HOUSE], "Chata tropicieli", "nazwa w epoce I")
	var s3 := Research.new()
	s3.done["S1"] = true
	assert_eq(BuildingTypes.name_of(K.SCOUT_HOUSE, s3), "Chata tropicieli", "bez S3 chata")
	s3.done["S3"] = true
	assert_eq(BuildingTypes.name_of(K.SCOUT_HOUSE, s3), "Dom zwiadowców", "po S3 Dom zwiadowców")
	assert_eq(BuildingTypes.name_of(K.BARRACKS, s3), "Koszary", "inne budynki bez zmian")
	assert_eq(TechTree.age("S3"), 1, "S3 z epoki II")
	assert_eq(TechTree.requires("S3"), ["S1"] as Array[String], "S3 po S1 Tropiciele")
	assert_eq(BuildingTypes.category(K.SCOUT_HOUSE), BuildingTypes.Category.MILITARY, "w zakładce Wojsko")
	assert_true(BuildingTypes.BUILD_BAR.has(K.SCOUT_HOUSE), "na pasku budowy")
	var grid := BuildGrid.new(TerrainMap.generate(1337))
	var q := BuildQueue.new()
	var e := Economy.new(T0)
	for res in EconomyConfig.count():
		e.amounts[res] = 1000
	var cell := _free_cell(grid, K.SCOUT_HOUSE)
	assert_eq(q.order_build(grid, e, cell, K.SCOUT_HOUSE, T0, Research.new()), BuildQueue.Result.NEEDS_TECH, "bez S1 nie stoi")
	var r := Research.new()
	r.done["S1"] = true
	assert_eq(q.order_build(grid, e, cell, K.SCOUT_HOUSE, T0, r), BuildQueue.Result.OK, "po S1 stoi")
	return true


func test_scout_trains_only_in_scout_house_with_horse_and_saddle() -> bool:
	var grid := BuildGrid.new(TerrainMap.generate(1337))
	grid.place_kind(_free_cell(grid, K.MANOR), K.MANOR, 3)
	var stable := grid.place_kind(_free_cell(grid, K.STABLE), K.STABLE, 1)
	var r := Research.new()
	for code in TechTree.codes():
		r.done[code] = true
	var rich := _rich()
	var e: Economy = rich[0]
	var goods: Goods = rich[1]
	var rec := Recruitment.new()
	assert_eq(RecruitPanel.units_for(K.SCOUT_HOUSE), [U.TRACKER, U.SCOUT] as Array[int], "Tropiciel i Zwiadowca")
	assert_true(not RecruitPanel.units_for(K.STABLE).has(U.SCOUT), "Stajnia nie szkoli Zwiadowcy")
	assert_eq(rec.availability(U.SCOUT, grid, r, 1), RES.NO_BUILDING, "bez Domu zwiadowców")
	assert_eq(rec.start(U.SCOUT, stable, Recruitment.NEW_SQUAD, grid, e, goods, r, 1, T0), RES.NO_BUILDING, "nie w Stajni")
	var house := grid.place_kind(_free_cell(grid, K.SCOUT_HOUSE), K.SCOUT_HOUSE, 1)
	assert_eq(rec.availability(U.SCOUT, grid, r, 0), RES.WRONG_AGE, "w epoce I jeszcze nie")
	assert_eq(rec.availability(U.SCOUT, grid, Research.new(), 1), RES.NEEDS_TECH, "bez S3 nie")
	goods.amounts[G.SADDLE] = 0
	assert_eq(rec.start(U.SCOUT, house, Recruitment.NEW_SQUAD, grid, e, goods, r, 1, T0), RES.NO_GOODS, "bez siodła nie")
	goods.amounts[G.SADDLE] = 1
	var food := e.amounts[R.FOOD]
	assert_eq(rec.start(U.SCOUT, house, Recruitment.NEW_SQUAD, grid, e, goods, r, 1, T0), RES.OK, "z koniem i siodłem")
	assert_eq(goods.amounts[G.HORSE], 49, "koń zszedł")
	assert_eq(goods.amounts[G.SADDLE], 0, "siodło zeszło")
	assert_eq(e.amounts[R.FOOD], food - 15, "żywność zeszła")
	assert_eq(rec.update(T0 + RecruitmentConfig.train_ms(U.SCOUT, 1)), [U.SCOUT] as Array[int], "wyszkolony")
	return true


func test_scout_works_in_the_battle() -> bool:
	var grid := BuildGrid.new(TerrainMap.generate(1337))
	var keep := grid.place(grid.manor_spot(64), K.KEEP, 1)
	var a := Battle.create_squads(grid, keep, [[U.SCOUT, 4]], [[U.PEASANT, 2]], Vector2i(32, 60), 5)
	var b := Battle.create_squads(grid, keep, [[U.SCOUT, 4]], [[U.PEASANT, 2]], Vector2i(32, 60), 5)
	a.run()
	b.run()
	assert_true(a.winner != Battle.Winner.NONE, "bitwa ze Zwiadowcami się rozstrzyga")
	assert_eq(a.checksum(), b.checksum(), "deterministycznie")
	return true
