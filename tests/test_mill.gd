extends TestCase
## Młyn (#388, ADR 0010): pierwszy budynek epoki II spoza MVP. G5 Młyn wodny (epoka II, wymaga G2),
## 2×2 przy rzece, stawiany od razu na poziomie 6 (1/5 epoki II), premia +4/8/12/16/20% całej
## produkcji żywności; liczy się jeden Młyn o najwyższym poziomie. Serwer zna te same liczby.

const K := BuildingTypes.Kind
const R := EconomyConfig.Res
const MIGRATION := "res://supabase/migrations/20261127160000_mill.sql"
const T0 := 1_000_000


func _free_cell(grid: BuildGrid, kind: int, near_water: bool) -> Vector2i:
	for y in grid.terrain.size - 1:
		for x in grid.terrain.size - 1:
			var placed := grid.placement_for(Vector2i(x, y), kind)
			if placed != Rect2i() and grid.touches_water(placed) == near_water:
				return Vector2i(x, y)
	return Vector2i(-1, -1)


func _grid(manor: int) -> BuildGrid:
	var grid := BuildGrid.new(TerrainMap.generate(1337))
	grid.place_kind(_free_cell(grid, K.MANOR, false), K.MANOR, manor)
	return grid


func _research(codes: Array[String]) -> Research:
	var r := Research.new()
	for c in codes:
		r.done[c] = true
	return r


func _rich() -> Economy:
	var e := Economy.new()
	for res in EconomyConfig.count():
		e.amounts[res] = 100000
	return e


func test_definition() -> bool:
	assert_eq(BuildingTypes.NAMES[K.MILL], "Młyn", "nazwa")
	assert_eq(BuildingTypes.size_of(K.MILL), Vector2i(2, 2), "2×2")
	assert_eq(BuildingTypes.category(K.MILL), BuildingTypes.Category.ECONOMY, "w Gospodarce")
	assert_true(BuildingTypes.BUILD_BAR.has(K.MILL), "na pasku budowy")
	assert_true(BuildingTypes.is_wooden(K.MILL), "z drewna")
	assert_eq(BuildConfig.required_tech(K.MILL), "G5", "po G5")
	assert_eq(BuildConfig.BASE_COST[K.MILL], [120, 60, 20, 0], "koszt poziomu 1")
	assert_true(TechTree.has("G5"), "G5 w drzewku")
	assert_eq(TechTree.age("G5"), 1, "G5 w epoce II")
	assert_eq(TechTree.branch("G5"), TechTree.Branch.ECONOMY, "G5 w Gospodarce")
	assert_eq(TechTree.requires("G5"), ["G2"] as Array[String], "G5 wymaga G2")
	return true


func test_start_level() -> bool:
	assert_eq(BuildConfig.start_level(K.MILL), 6, "Młyn od poziomu 6 (1/5 epoki II)")
	for kind in K.size():
		if kind != K.MILL:
			assert_eq(BuildConfig.start_level(kind), 1, "reszta od poziomu 1: %d" % kind)
	return true


func test_only_by_river() -> bool:
	var grid := _grid(6)
	assert_eq(grid.place_kind(_free_cell(grid, K.MILL, false), K.MILL), 0, "z dala od wody nie")
	assert_true(grid.place_kind(_free_cell(grid, K.MILL, true), K.MILL) > 0, "przy rzece tak")
	return true


func test_order_needs_g5_and_age_two() -> bool:
	var q := BuildQueue.new()
	var e := _rich()
	var grid := _grid(5)
	var wet := _free_cell(grid, K.MILL, true)
	assert_eq(q.order_build(grid, e, wet, K.MILL, T0, Research.new()), BuildQueue.Result.NEEDS_TECH, "bez G5 nie")
	var before: Array[int] = e.amounts.duplicate()
	assert_eq(q.order_build(grid, e, wet, K.MILL, T0, _research(["G2", "G5"])), BuildQueue.Result.NEEDS_MANOR,
			"Dwór w epoce I: nie")
	assert_eq(e.amounts, before, "odmowa nic nie kosztuje")
	assert_eq(grid.buildings.size(), 1, "i nic nie stawia")
	grid = _grid(6)
	wet = _free_cell(grid, K.MILL, true)
	assert_eq(q.order_build(grid, e, wet, K.MILL, T0, _research(["G2", "G5"])), BuildQueue.Result.OK, "epoka II: tak")
	assert_eq(q.order_for(q.placed_id).level, 6, "zlecenie od razu na poziom 6")
	assert_eq(e.amounts[R.WOOD], 100000 - BuildConfig.cost(K.MILL, 6)[R.WOOD], "koszt poziomu 6")
	q.update(T0 + BuildConfig.time_ms(K.MILL, 6), grid, e)
	assert_eq(grid.levels[q.placed_id], 6, "po budowie poziom 6")
	return true


func test_food_bonus() -> bool:
	var grid := _grid(10)
	var base := Economy.rates(grid)
	var id := grid.place_kind(_free_cell(grid, K.MILL, true), K.MILL, 0)
	assert_eq(Economy.rates(grid), base, "plac budowy nic nie daje")
	for local in range(1, 6):
		grid.levels[id] = Ages.total_level(1, local)
		var rates := Economy.rates(grid)
		@warning_ignore("integer_division")
		var want := base[R.FOOD] * (100 + EconomyConfig.MILL_FOOD_PERCENT[local - 1]) / 100
		assert_eq(rates[R.FOOD], want, "żywność przy Młynie %d/5" % local)
		assert_eq(rates[R.WOOD], base[R.WOOD], "drewno bez zmian")
	assert_eq(EconomyConfig.MILL_FOOD_PERCENT, [4, 8, 12, 16, 20] as Array[int], "stawki z ustaleń")
	grid.place_kind(_free_cell(grid, K.MILL, true), K.MILL, 6)
	@warning_ignore("integer_division")
	assert_eq(Economy.rates(grid)[R.FOOD], base[R.FOOD] * 120 / 100, "drugi Młyn się nie sumuje")
	return true


func test_bonus_adds_to_g2() -> bool:
	var grid := _grid(10)
	var research := _research(["G2"])
	var base := Economy.rates(grid)[R.FOOD]
	grid.place_kind(_free_cell(grid, K.MILL, true), K.MILL, 10)
	@warning_ignore("integer_division")
	assert_eq(Economy.rates(grid, research)[R.FOOD], base * (100 + 15 + 20) / 100, "procenty się dodają")
	assert_eq(Economy.rates(grid, research), Economy.rates(grid, research), "ten sam zamek → ta sama produkcja")
	return true


func test_art_levels() -> bool:
	var seen: Array[PackedByteArray] = []
	for local in range(1, 6):
		var img := BuildingArt.make_image(K.MILL, Ages.total_level(1, local), BuildingTypes.State.INTACT)
		assert_eq(img.get_size(), BuildingArt.image_size(K.MILL), "rozmiar rysunku")
		assert_true(not seen.has(img.get_data()), "poziom %d wygląda inaczej" % local)
		seen.append(img.get_data())
	var intact := BuildingArt.make_image(K.MILL, 8, BuildingTypes.State.INTACT).get_data()
	for state in [BuildingTypes.State.CRACKED, BuildingTypes.State.BREACHED, BuildingTypes.State.RUBBLE]:
		assert_true(BuildingArt.make_image(K.MILL, 8, state).get_data() != intact, "stan %d inny" % state)
	return true


## Liczby serwera (migracja `*_mill.sql`) to liczby gry.
func test_server_matches_game() -> bool:
	var sql := FileAccess.get_file_as_string(MIGRATION)
	assert_true(not sql.is_empty(), "migracja jest")
	assert_true(sql.contains("MILL = %d" % K.MILL), "rodzaj Młyna")
	assert_true(sql.contains("MILL_FOOD_PERCENT = %s" % str(EconomyConfig.MILL_FOOD_PERCENT)), "stawki w komentarzu")
	assert_true(sql.contains("(array%s)[least(m.level - 5, 5)]" % str(EconomyConfig.MILL_FOOD_PERCENT)),
			"stawki w funkcji")
	assert_true(sql.contains("START_LEVEL = %d" % BuildConfig.start_level(K.MILL)), "poziom startowy")
	assert_true(sql.contains("case when b.kind = %d then %d else 1 end" % [K.MILL, BuildConfig.start_level(K.MILL)]),
			"poziom startowy w funkcji")
	assert_true(sql.contains("\"%d\": %s" % [K.MILL, str(BuildConfig.BASE_COST[K.MILL])]), "koszt Młyna")
	assert_true(sql.contains("b.kind = %d and b.level between 1 and %d" % [K.MILL, BuildConfig.start_level(K.MILL) - 1]),
			"poziomów 1–5 Młyna nie ma: zapis odrzucony")
	return true
