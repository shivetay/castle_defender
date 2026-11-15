extends TestCase
## Stajnia w epoce I (#91): stoi bez technologii, z żywności hoduje konie do zbrojowni,
## a razem z siodłem od Rymarza daje wyposażenie dla klasy szybkiej. Grafikę (5 poziomów,
## 4 stany, paleta) sprawdza test_buildings dla wszystkich rodzajów.

const T0 := 1_700_000_000_000
const HOUR := 3600 * 1000
const K := BuildingTypes.Kind
const G := GoodsConfig.Good
const R := EconomyConfig.Res


func _free_cell(grid: BuildGrid, kind: int) -> Vector2i:
	var c := grid.terrain.center()
	for r in grid.terrain.size:
		for dy in range(-r, r + 1):
			for dx in range(-r, r + 1):
				var p := c + Vector2i(dx, dy)
				if grid.placement_for(p, kind) != Rect2i():
					return p
	return Vector2i(-1, -1)


func test_stable_is_available_in_age_one_without_research() -> bool:
	assert_eq(BuildConfig.required_tech(K.STABLE), "", "Stajnia bez technologii")
	var grid := BuildGrid.new(TerrainMap.generate(1337))
	var q := BuildQueue.new()
	var e := Economy.new(T0)
	assert_eq(q.order_build(grid, e, _free_cell(grid, K.STABLE), K.STABLE, T0, Research.new()), BuildQueue.Result.OK,
			"Stajnia staje od początku gry")
	var slot := BuildingTypes.BUILD_BAR.find(K.STABLE)
	assert_eq(BuildingTypes.BUILD_BAR[slot - 1], K.SADDLER, "na pasku obok Rymarza (łańcuch konnicy)")
	return true


func test_stable_breeds_horses_from_food() -> bool:
	var grid := BuildGrid.new(TerrainMap.generate(1337))
	var id := grid.place_kind(_free_cell(grid, K.STABLE), K.STABLE)
	assert_true(id > 0, "Stajnia stoi")
	var goods := Goods.new(T0)
	var e := Economy.new(T0)
	var food := e.amounts[R.FOOD]
	goods.update(T0 + 3 * HOUR, Goods.producers(grid), e)
	assert_true(goods.amounts[G.HORSE] > 0, "konie w zbrojowni")
	assert_true(e.amounts[R.FOOD] < food, "konie jedzą żywność")
	e.amounts[R.FOOD] = 0
	var horses := goods.amounts[G.HORSE]
	goods.update(T0 + 6 * HOUR, Goods.producers(grid), e)
	assert_eq(goods.amounts[G.HORSE], horses, "bez żywności nie przybywa koni")
	return true


## Jeździec potrzebuje konia ze Stajni i siodła od Rymarza (#91); rekrutacja dojdzie w #89.
func test_horse_and_saddle_equip_the_fast_class() -> bool:
	var goods := Goods.new(T0)
	var e := Economy.new(T0)
	goods.add(G.LEATHER, 50)
	goods.update(T0 + 5 * HOUR, {"stable": [2], "saddler": [2]}, e)
	assert_true(goods.amounts[G.HORSE] > 0 and goods.amounts[G.SADDLE] > 0, "są konie i siodła")
	assert_true(goods.take({G.HORSE: 1, G.SADDLE: 1}), "koń i siodło dla jeźdźca")
	return true
