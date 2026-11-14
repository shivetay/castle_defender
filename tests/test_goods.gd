extends TestCase
## Towary i łańcuchy produkcji (#88): wzrost w czasie, limit zbrojowni, brak wejścia,
## łańcuch wytwórców, poziomy odblokowujące lepszy towar, brak metalu i zapis. Wejścia przepisów
## według kolumny „Z czego” notatki Klasy jednostek i produkcja.

const T0 := 1_700_000_000_000
const HOUR := 3600 * 1000
const G := GoodsConfig.Good
const R := EconomyConfig.Res


func _economy() -> Economy:
	return Economy.new(T0)


func test_config_is_consistent() -> bool:
	assert_eq(GoodsConfig.ARMORY_CAPACITY, EconomyConfig.CAPACITY[R.WOOD], "zbrojownia: limit jak przy surowcach")
	assert_eq(GoodsConfig.NAMES.size(), GoodsConfig.Good.size(), "nazwa dla każdego towaru")
	for row: Array in GoodsConfig.RECIPES:
		var producer: String = row[0]
		assert_true(GoodsConfig.PRODUCERS.has(producer), "%s na liście wytwórców" % producer)
		assert_true(GoodsConfig.PRODUCER_NAMES.has(producer), "%s ma nazwę" % producer)
		assert_true(int(row[1]) >= 1 and int(row[1]) <= BuildingTypes.MAX_LEVEL, "%s: poziom 1–5" % producer)
		assert_true(not (row[5] as Dictionary).is_empty() or not (row[6] as Dictionary).is_empty(), "%s coś daje" % producer)
		for good: int in (row[4] as Dictionary).keys() + (row[5] as Dictionary).keys():
			assert_true(good >= 0 and good < GoodsConfig.count(), "%s: znany towar" % producer)
	for producer in GoodsConfig.PRODUCERS:
		var has_recipe := false
		for row: Array in GoodsConfig.RECIPES:
			has_recipe = has_recipe or row[0] == producer
		assert_true(has_recipe, "%s ma przepis" % producer)
	return true


## Kryterium #88: żaden przepis epok I–II nie zużywa metalu. Surowce wejściowe to tylko drewno,
## kamień i żywność; złoto i (od epoki III) żelazo nie wchodzą do przepisów.
func test_no_recipe_uses_metal() -> bool:
	for row: Array in GoodsConfig.RECIPES:
		for res: int in (row[3] as Dictionary):
			assert_true(res in [R.WOOD, R.STONE, R.FOOD], "%s: surowiec %s nie jest metalem" % [row[0], EconomyConfig.NAMES[res]])
	return true


## Kryterium #88: towar rośnie w czasie i zatrzymuje się na limicie.
func test_goods_grow_and_stop_at_capacity() -> bool:
	var goods := Goods.new(T0)
	var e := _economy()
	var flax := {"flax_field": [1]}
	goods.update(T0 + HOUR, flax, e)
	var per_hour := GoodsConfig.cycles_per_hour(1, 1) * 3
	assert_eq(goods.amounts[G.FLAX], per_hour, "po godzinie")
	goods.update(T0 + 100 * HOUR, flax, e)
	assert_eq(goods.amounts[G.FLAX], GoodsConfig.capacity(G.FLAX), "zatrzymuje się na limicie zbrojowni")
	assert_true(goods.is_full(G.FLAX), "pełne")
	return true


func test_same_result_per_frame_and_in_one_jump() -> bool:
	var a := Goods.new(T0)
	var b := Goods.new(T0)
	var e := _economy()
	var flax := {"flax_field": [2]}
	for i in range(1, 3601):
		a.update(T0 + i * 1000, flax, e)
	b.update(T0 + 3600 * 1000, flax, e)
	assert_eq(a.amounts, b.amounts, "co sekundę i jednym skokiem")
	return true


## Kryterium #88: brak surowca wejściowego zatrzymuje produkcję.
func test_missing_input_stops_production() -> bool:
	var goods := Goods.new(T0)
	var e := _economy()
	goods.update(T0 + 5 * HOUR, {"tannery": [3]}, e)
	assert_eq(goods.amounts[G.LEATHER], 0, "Garbarnia bez surowych skór stoi")
	e.amounts[R.WOOD] = 0
	goods.update(T0 + 10 * HOUR, {"tar_kiln": [1]}, e)
	assert_eq(goods.amounts[G.PITCH], 0, "Smolarnia bez drewna stoi")
	e.amounts[R.WOOD] = 8
	goods.update(T0 + 20 * HOUR, {"tar_kiln": [1]}, e)
	assert_eq(goods.amounts[G.PITCH], 2, "8 drewna wystarcza na 2 smoły")
	assert_eq(e.amounts[R.WOOD], 0, "drewno zużyte")
	return true


func test_chain_hunter_tannery_saddler() -> bool:
	var goods := Goods.new(T0)
	var e := _economy()
	var food := e.amounts[R.FOOD]
	var castle := {"hunter": [1], "tannery": [1], "saddler": [1]}
	goods.update(T0 + 10 * HOUR, castle, e)
	assert_true(goods.amounts[G.LEATHER] + goods.amounts[G.SADDLE] + goods.amounts[G.HARNESS] > 0, "skóra przeszła łańcuch")
	assert_true(goods.amounts[G.SADDLE] > 0, "Rymarz zrobił siodła")
	assert_true(e.amounts[R.FOOD] > food, "Chata myśliwego daje też trochę żywności")
	return true


func test_level_unlocks_better_goods() -> bool:
	var e := _economy()
	var low := Goods.new(T0)
	low.amounts[G.BOWSTRING] = 50
	low.amounts[G.LEATHER] = 50
	low.update(T0 + 5 * HOUR, {"bowyer": [2]}, e)
	assert_true(low.amounts[G.BOW] > 0 and low.amounts[G.REFLEX_BOW] == 0, "Łukmistrz 2 robi zwykłe łuki")
	var high := Goods.new(T0)
	high.amounts[G.BOWSTRING] = 50
	high.amounts[G.LEATHER] = 50
	high.update(T0 + 5 * HOUR, {"bowyer": [3]}, e)
	assert_true(high.amounts[G.REFLEX_BOW] > 0, "Łukmistrz 3 robi łuki refleksyjne (#88)")
	var faster := Goods.new(T0)
	faster.update(T0 + HOUR, {"flax_field": [5]}, e)
	var slower := Goods.new(T0)
	slower.update(T0 + HOUR, {"flax_field": [1]}, e)
	assert_true(faster.amounts[G.FLAX] > slower.amounts[G.FLAX], "wyższy poziom produkuje szybciej")
	assert_eq(Goods.producers(BuildGrid.new(TerrainMap.generate(1))), {}, "bez budynków wytwórców nic nie produkuje")
	return true


func test_take_and_fire_rate() -> bool:
	var goods := Goods.new(T0)
	assert_eq(goods.fire_rate_percent(), GoodsConfig.NO_ARROWS_FIRE_PERCENT, "bez strzał −50%")
	goods.add(G.ARROW, 10)
	goods.add(G.BOW, 1)
	assert_eq(goods.fire_rate_percent(), 100, "ze strzałami pełne tempo")
	assert_true(not goods.take({G.BOW: 1, G.ARROW: 20}), "za mało strzał: nic nie schodzi")
	assert_eq(goods.amounts[G.BOW], 1, "łuk został")
	assert_true(goods.take({G.BOW: 1, G.ARROW: 10}), "łuk i strzały dla łucznika")
	assert_eq(goods.amounts[G.ARROW], 0, "strzały zużyte")
	assert_eq(goods.add(G.HORSE, 1000), GoodsConfig.capacity(G.HORSE), "add do pojemności")
	return true


## Kryterium #88: zapis i odczyt towarów; starsze zapisy dostają pustą zbrojownię.
func test_save_round_trip_and_migration() -> bool:
	var goods := Goods.new(T0)
	var e := _economy()
	goods.update(T0 + HOUR + 1234, {"hunter": [2], "flax_field": [1]}, e)
	var grid := BuildGrid.new(TerrainMap.generate(1337))
	var d := SaveGame.to_dict(1337, grid, e, BuildQueue.new(), Research.new(), goods)
	var s := SaveGame.from_dict(JSON.parse_string(JSON.stringify(d)) as Dictionary, T0)
	assert_true(s != null, "zapis czytelny")
	if s != null:
		assert_eq(s.goods.amounts, goods.amounts, "zapasy po odczycie")
		assert_eq(s.goods.save_data(), goods.save_data(), "ułamki cykli i czas po odczycie")
	var v2 := d.duplicate(true)
	v2["version"] = 2
	v2.erase("goods")
	var old := SaveGame.from_dict(v2, T0)
	assert_true(old != null and old.goods.amounts.max() == 0, "wersja 2 → pusta zbrojownia")
	var v1 := v2.duplicate(true)
	v1["version"] = 1
	v1.erase("research")
	assert_true(SaveGame.from_dict(v1, T0) != null, "wersja 1 przechodzi obie migracje")
	var tampered := d.duplicate(true)
	((tampered["goods"] as Dictionary)["amounts"] as Array)[G.HORSE] = 99999
	var t := SaveGame.from_dict(tampered, T0)
	assert_eq(t.goods.amounts[G.HORSE], GoodsConfig.capacity(G.HORSE), "zapas przycięty do pojemności")
	return true


## Wejścia z notatki: Drzewcarz z drewna i kamienia, Łukmistrz 3 dokłada skórę do łuku
## refleksyjnego, Stajnia z żywności, Wytwórca zbroi skórzanych robi też mokre skóry na Taran.
func test_recipes_follow_note() -> bool:
	for row: Array in GoodsConfig.RECIPES:
		var res_in: Dictionary = row[3]
		var goods_in: Dictionary = row[4]
		var out: Dictionary = row[5]
		match row[0] as String:
			"polearm":
				assert_true(res_in.has(R.WOOD) and res_in.has(R.STONE), "Drzewcarz: drewno + kamień")
			"stable":
				assert_eq(res_in.keys(), [R.FOOD], "Stajnia: z żywności")
			"tar_kiln":
				assert_eq(res_in.keys(), [R.WOOD], "Smolarnia: z drewna")
			"hunter":
				assert_true(res_in.is_empty() and goods_in.is_empty(), "Chata myśliwego: z lasu")
		if out.has(G.REFLEX_BOW):
			assert_eq(int(row[1]), 3, "łuk refleksyjny od poziomu 3")
			assert_true(goods_in.has(G.LEATHER) and goods_in.has(G.BOWSTRING), "łuk refleksyjny: cięciwa + skóra")
	var wet := false
	for row: Array in GoodsConfig.RECIPES:
		wet = wet or (row[0] == "leatherworker" and (row[5] as Dictionary).has(G.WET_HIDE))
	assert_true(wet, "mokre skóry na Taran od Wytwórcy zbroi skórzanych")
	return true
