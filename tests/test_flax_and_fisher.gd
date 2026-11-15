extends TestCase
## Budynki gospodarcze epoki I (#122): Pole lnu daje len do zbrojowni, a Cięciwiarz go zużywa;
## Rybak daje żywność i staje tylko przy wodzie. Grafikę (5 poziomów, 4 stany, paleta) sprawdza
## test_buildings dla wszystkich rodzajów.

const T0 := 1_700_000_000_000
const HOUR := 3600 * 1000
const K := BuildingTypes.Kind
const G := GoodsConfig.Good


## Pierwszy lewy górny róg 2×2 na trawie, który styka się bokiem z wodą (albo nie, gdy `near` = false).
func _spot(grid: BuildGrid, near: bool) -> Vector2i:
	var size := BuildingTypes.size_of(K.FISHER)
	for y in grid.terrain.size - 1:
		for x in grid.terrain.size - 1:
			var r := Rect2i(Vector2i(x, y), size)
			if grid.can_place(r) and grid.touches_water(r) == near:
				return r.position
	return Vector2i(-1, -1)


## Kryterium #122: Rybaka nie da się postawić z dala od wody.
func test_fisher_only_next_to_water() -> bool:
	for map_seed: int in [1, 42, 1337, 9001]:
		var grid := BuildGrid.new(TerrainMap.generate(map_seed))
		var dry := _spot(grid, false)
		assert_eq(grid.place_kind(dry, K.FISHER), 0, "seed %d: z dala od wody nie" % map_seed)
		var wet := _spot(grid, true)
		assert_true(wet.x >= 0, "seed %d: jest miejsce przy rzece" % map_seed)
		assert_true(grid.place_kind(wet, K.FISHER) > 0, "seed %d: przy rzece tak" % map_seed)
		assert_true(grid.place_kind(dry, K.HUNTER) > 0, "seed %d: inne budynki nie muszą stać przy wodzie" % map_seed)
	return true


func test_water_must_touch_a_side() -> bool:
	var map := TerrainMap.generate(1337)
	for i in map.tiles.size():
		map.tiles[i] = TerrainMap.Tile.GRASS
	map.tiles[10 * map.size + 10] = TerrainMap.Tile.WATER
	var grid := BuildGrid.new(map)
	assert_true(grid.touches_water(Rect2i(11, 9, 2, 2)), "woda przy lewym boku")
	assert_true(grid.touches_water(Rect2i(9, 11, 2, 2)), "woda nad górnym bokiem")
	assert_true(not grid.touches_water(Rect2i(11, 11, 2, 2)), "woda tylko po skosie się nie liczy")
	map.tiles[10 * map.size + 10] = TerrainMap.Tile.BRIDGE
	assert_true(not grid.touches_water(Rect2i(11, 9, 2, 2)), "most to nie woda")
	return true


func test_fisher_gives_food() -> bool:
	var grid := BuildGrid.new(TerrainMap.generate(1337))
	var before := Economy.rates(grid)
	var id := grid.place_kind(_spot(grid, true), K.FISHER)
	assert_true(id > 0, "Rybak stoi")
	var after := Economy.rates(grid)
	assert_true(after[EconomyConfig.Res.FOOD] > before[EconomyConfig.Res.FOOD], "Rybak daje żywność")
	grid.levels[id] = 0
	assert_eq(Economy.rates(grid), before, "plac budowy jeszcze nie łowi")
	return true


## Kryterium #122: len trafia do magazynu i zużywa go Cięciwiarz.
func test_flax_goes_to_armory_and_bowstring_maker_uses_it() -> bool:
	var grid := BuildGrid.new(TerrainMap.generate(1337))
	var field := grid.place_kind(Vector2i(20, 20), K.FLAX_FIELD)
	if field == 0:
		field = grid.place_kind(_spot(grid, false), K.FLAX_FIELD)
	assert_true(field > 0, "Pole lnu stoi")
	var goods := Goods.new(T0)
	var e := Economy.new(T0)
	goods.update(T0 + HOUR, Goods.producers(grid), e)
	assert_true(goods.amounts[G.FLAX] > 0, "len w zbrojowni")
	# Cięciwiarz bez ścięgien robi cięciwy z lnu
	var flax := goods.amounts[G.FLAX]
	goods.update(T0 + 2 * HOUR, {"bowstring": [1]}, e)
	assert_true(goods.amounts[G.BOWSTRING] > 0, "Cięciwiarz zrobił cięciwy")
	assert_true(goods.amounts[G.FLAX] < flax, "len zużyty")
	assert_eq(goods.amounts[G.SINEW], 0, "bez ścięgien")
	return true


func test_need_their_technologies() -> bool:
	assert_eq(BuildConfig.required_tech(K.FLAX_FIELD), "G20", "Pole lnu: G20 Uprawa lnu")
	assert_eq(BuildConfig.required_tech(K.FISHER), "G21", "Rybak: G21 Rybołówstwo")
	for kind: int in [K.FLAX_FIELD, K.FISHER]:
		assert_true(TechTree.effect(BuildConfig.required_tech(kind)).begins_with("budynek " + BuildingTypes.NAMES[kind]),
				"%s: technologia z drzewka" % BuildingTypes.NAMES[kind])
	var grid := BuildGrid.new(TerrainMap.generate(1337))
	var e := Economy.new(T0)
	var r := Research.new()
	var q := BuildQueue.new()
	var wet := _spot(grid, true)
	assert_eq(q.order_build(grid, e, wet, K.FISHER, T0, r), BuildQueue.Result.NEEDS_TECH, "bez G21 nie")
	r.done["G21"] = true
	assert_eq(q.order_build(grid, e, wet, K.FISHER, T0, r), BuildQueue.Result.OK, "po G21 tak")
	return true
