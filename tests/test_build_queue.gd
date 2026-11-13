extends TestCase
## Progresja (#11): tabela kosztów i czasów, wymaganie poziomu Dworu, kolejka budowy
## (1 budowniczy + 3 czekające), anulowanie ze zwrotem, kończenie budowy po nieobecności
## i ekonomia liczona odcinkami przy ukończeniu budynku.

const SEC := 1000
const MIN := 60 * 1000
const HOUR := 3600 * 1000
const T0 := 1_700_000_000_000
const K := BuildingTypes.Kind
const R := EconomyConfig.Res


func _grid() -> BuildGrid:
	return BuildGrid.new(TerrainMap.generate(1337))


## Wolna kratka, na której stanie budynek `kind` (szukana spiralnie od środka, stała dla seeda).
func _free_cell(grid: BuildGrid, kind: int) -> Vector2i:
	var c := grid.terrain.center()
	for r in grid.terrain.size:
		for dy in range(-r, r + 1):
			for dx in range(-r, r + 1):
				var p := c + Vector2i(dx, dy)
				if grid.placement_for(p, kind) != Rect2i():
					return p
	return Vector2i(-1, -1)


## Zamek z Dworem i dużym zapasem surowców (bez limitu w testach kolejki).
func _castle() -> Array:
	var grid := _grid()
	grid.place_kind(_free_cell(grid, K.MANOR), K.MANOR)
	var economy := Economy.new(T0)
	return [grid, economy]


func test_cost_and_time_table() -> bool:
	assert_eq(BuildConfig.cost(K.RAMPART, 1), [10, 0, 10, 0] as Array[int], "wał poziom 1")
	assert_eq(BuildConfig.cost(K.TOWER, 5), [720, 240, 240, 0] as Array[int], "wieża poziom 5 (×6)")
	assert_eq(BuildConfig.cost(K.GATE, 2), [90, 30, 30, 0] as Array[int], "brama poziom 2 (×1,5)")
	assert_eq(BuildConfig.cost(K.LUMBER_HUT, 3), [200, 0, 75, 0] as Array[int], "chata poziom 3 (×2,5)")
	assert_eq(BuildConfig.time_ms(K.RAMPART, 1), 5 * SEC, "wał poziom 1: 5 s")
	assert_eq(BuildConfig.time_ms(K.TOWER, 5), 90 * MIN, "wieża poziom 5: 90 min")
	assert_eq(BuildConfig.time_ms(K.PALISADE, 3), 100 * SEC, "palisada poziom 3: ×10")
	assert_eq(BuildConfig.cost(K.MANOR, 2), [300, 200, 200, 0] as Array[int], "dwór poziom 2")
	assert_eq(BuildConfig.time_ms(K.MANOR, 5), 12 * HOUR, "dwór poziom 5: 12 h")
	# każdy koszt mieści się w magazynie, więc każdy poziom da się kupić
	for kind in BuildingTypes.count():
		for level in range(1, BuildingTypes.MAX_LEVEL + 1):
			var cost := BuildConfig.cost(kind, level)
			for res in cost.size():
				var cap: int = EconomyConfig.CAPACITY[res]
				assert_true(cap == 0 or cost[res] <= cap, "%s poz. %d mieści się w magazynie" % [BuildingTypes.NAMES[kind], level])
			assert_true(BuildConfig.time_ms(kind, level) >= 0, "czas nieujemny")
	return true


func test_building_cannot_outgrow_manor() -> bool:
	assert_eq(BuildConfig.max_level(K.TOWER, 1), 1, "dwór 1: wieża najwyżej 1")
	assert_eq(BuildConfig.max_level(K.TOWER, 3), 3, "dwór 3: wieża najwyżej 3")
	assert_eq(BuildConfig.max_level(K.MANOR, 1), BuildingTypes.MAX_LEVEL, "dwór bez limitu")
	var c := _castle()
	var grid: BuildGrid = c[0]
	var economy: Economy = c[1]
	var q := BuildQueue.new()
	economy.add(R.WOOD, 1000)
	assert_eq(q.order_build(grid, economy, _free_cell(grid, K.TOWER), K.TOWER, T0), BuildQueue.Result.OK, "wieża zlecona")
	var tower := q.placed_id
	q.update(T0 + HOUR, grid, economy)
	assert_eq(grid.levels[tower], 1, "wieża gotowa")
	assert_eq(q.order_upgrade(grid, economy, tower, T0 + HOUR), BuildQueue.Result.NEEDS_MANOR, "wieża 2 wymaga dworu 2")
	assert_eq(q.order_upgrade(grid, economy, grid.manor_id(), T0 + HOUR), BuildQueue.Result.OK, "dwór 2 zlecony")
	assert_eq(q.order_upgrade(grid, economy, tower, T0 + HOUR), BuildQueue.Result.NEEDS_MANOR, "dwór w budowie się nie liczy")
	q.update(T0 + 2 * HOUR, grid, economy)
	assert_eq(grid.manor_level(), 2, "dwór na poziomie 2")
	assert_eq(q.order_upgrade(grid, economy, tower, T0 + 2 * HOUR), BuildQueue.Result.OK, "teraz wieża 2 wolno")
	return true


func test_order_takes_cost_and_places_site() -> bool:
	var c := _castle()
	var grid: BuildGrid = c[0]
	var economy: Economy = c[1]
	var q := BuildQueue.new()
	var before: Array[int] = economy.amounts.duplicate()
	var cell := _free_cell(grid, K.LUMBER_HUT)
	assert_eq(q.order_build(grid, economy, cell, K.LUMBER_HUT, T0), BuildQueue.Result.OK, "zlecono")
	var hut := q.placed_id
	assert_eq(grid.levels[hut], 0, "plac budowy")
	assert_eq(grid.building_at(cell), hut, "plac zajmuje kratki")
	assert_eq(economy.amounts[R.WOOD], before[R.WOOD] - 80, "koszt drewna pobrany od razu")
	assert_eq(economy.amounts[R.FOOD], before[R.FOOD] - 30, "koszt żywności pobrany od razu")
	assert_eq(Economy.rates(grid)[R.WOOD], EconomyConfig.BASE_PER_HOUR[R.WOOD], "plac nic nie produkuje")
	assert_eq(q.remaining_ms(hut, T0 + 10 * SEC), 35 * SEC, "zostało 35 s z 45")
	assert_eq(q.progress_permille(hut, T0 + 9 * SEC), 200, "20% po 9 s")
	q.update(T0 + 44 * SEC, grid, economy)
	assert_eq(grid.levels[hut], 0, "jeszcze nie gotowe po 44 s")
	var done := q.update(T0 + 45 * SEC, grid, economy)
	assert_eq(done.size(), 1, "ukończone po 45 s")
	assert_eq(grid.levels[hut], 1, "chata poziom 1")
	assert_true(q.orders.is_empty(), "kolejka pusta")
	return true


func test_failed_orders_change_nothing() -> bool:
	var c := _castle()
	var grid: BuildGrid = c[0]
	var economy: Economy = c[1]
	var q := BuildQueue.new()
	economy.spend([economy.amounts[0] - 50, 0, 0, 0] as Array[int])
	var count := grid.buildings.size()
	assert_eq(q.order_build(grid, economy, _free_cell(grid, K.TOWER), K.TOWER, T0), BuildQueue.Result.NO_RESOURCES, "brak drewna")
	assert_eq(grid.buildings.size(), count, "nic nie postawiono")
	assert_eq(economy.amounts[R.WOOD], 50, "nic nie pobrano")
	var water := Vector2i(-5, -5)
	assert_eq(q.order_build(grid, economy, water, K.RAMPART, T0), BuildQueue.Result.NO_PLACE, "poza mapą")
	assert_eq(q.order_upgrade(grid, economy, 999, T0), BuildQueue.Result.NOT_FOUND, "brak budynku")
	assert_true(q.orders.is_empty(), "kolejka pusta")
	return true


func test_queue_has_one_builder_and_three_waiting() -> bool:
	var c := _castle()
	var grid: BuildGrid = c[0]
	var economy: Economy = c[1]
	var q := BuildQueue.new()
	var ids: Array[int] = []
	for i in 4:
		assert_eq(q.order_build(grid, economy, _free_cell(grid, K.RAMPART), K.RAMPART, T0), BuildQueue.Result.OK, "wał %d" % i)
		ids.append(q.placed_id)
	assert_true(q.is_full(), "4 zlecenia = pełna kolejka")
	assert_eq(q.order_build(grid, economy, _free_cell(grid, K.RAMPART), K.RAMPART, T0), BuildQueue.Result.QUEUE_FULL, "piąte odrzucone")
	assert_eq(q.orders[0].start_ms, T0, "pierwsze w budowie")
	assert_eq(q.orders[1].start_ms, -1, "drugie czeka")
	assert_eq(q.remaining_ms(ids[3], T0), 20 * SEC, "czwarte gotowe po 4 × 5 s")
	assert_eq(q.order_upgrade(grid, economy, ids[0], T0), BuildQueue.Result.ALREADY_QUEUED, "jeden budynek, jedno zlecenie")
	q.update(T0 + 12 * SEC, grid, economy)
	assert_eq([grid.levels[ids[0]], grid.levels[ids[1]], grid.levels[ids[2]], grid.levels[ids[3]]],
			[1, 1, 0, 0], "po 12 s gotowe dwa pierwsze (budowa po kolei)")
	assert_eq(q.orders[0].start_ms, T0 + 10 * SEC, "trzecie ruszyło, gdy skończyło się drugie")
	return true


## Kryterium #11: budowa kończy się także, gdy gry nie było (tu: kilka godzin w tle).
func test_queue_finishes_while_away() -> bool:
	var c := _castle()
	var grid: BuildGrid = c[0]
	var economy: Economy = c[1]
	var q := BuildQueue.new()
	q.order_build(grid, economy, _free_cell(grid, K.TOWER), K.TOWER, T0)
	var tower := q.placed_id
	q.order_upgrade(grid, economy, grid.manor_id(), T0)
	q.order_build(grid, economy, _free_cell(grid, K.PALISADE), K.PALISADE, T0)
	var done := q.update(T0 + 5 * HOUR, grid, economy)
	assert_eq(done.size(), 3, "wszystkie trzy ukończone")
	assert_eq(grid.levels[tower], 1, "wieża")
	assert_eq(grid.manor_level(), 2, "dwór 2")
	assert_true(q.orders.is_empty(), "kolejka pusta")
	return true


## Chata ukończona w trakcie nieobecności produkuje więcej dopiero od chwili ukończenia,
## a wynik nie zależy od tego, czy gra wracała co sekundę, czy jednym skokiem.
func test_economy_switches_rates_at_completion() -> bool:
	var runs: Array[Array] = []
	for step: int in [0, 7 * SEC]:
		var c := _castle()
		var grid: BuildGrid = c[0]
		var economy: Economy = c[1]
		var q := BuildQueue.new()
		var hut := _free_cell(grid, K.LUMBER_HUT)
		q.order_build(grid, economy, hut, K.LUMBER_HUT, T0)
		var end := T0 + 3 * HOUR
		if step == 0:
			q.update(end, grid, economy)
		else:
			var t := T0
			while t < end:
				t = mini(t + step, end)
				q.update(t, grid, economy)
		runs.append(economy.amounts.duplicate())
	assert_eq(runs[1], runs[0], "co 7 s = jednym skokiem")
	# 45 s po 20/h, potem 3 h − 45 s po 80/h (gród 20 + chata 60)
	var wood: int = EconomyConfig.START[R.WOOD] - 80 + (20 * 45 * SEC + 80 * (3 * HOUR - 45 * SEC)) / HOUR
	assert_eq(runs[0][R.WOOD], wood, "drewno liczone odcinkami")
	return true


func test_cancel_refunds_and_removes_site() -> bool:
	var c := _castle()
	var grid: BuildGrid = c[0]
	var economy: Economy = c[1]
	var q := BuildQueue.new()
	var before: Array[int] = economy.amounts.duplicate()
	q.order_build(grid, economy, _free_cell(grid, K.GATE), K.GATE, T0)
	var gate := q.placed_id
	q.order_build(grid, economy, _free_cell(grid, K.RAMPART), K.RAMPART, T0)
	var wall := q.placed_id
	assert_true(q.cancel(grid, economy, gate, T0 + 10 * SEC), "anulowano bramę w budowie")
	assert_true(not grid.buildings.has(gate), "plac bramy zniknął")
	assert_eq(q.orders[0].building_id, wall, "wał wszedł na budowę")
	assert_eq(q.orders[0].start_ms, T0 + 10 * SEC, "od chwili anulowania")
	assert_true(q.cancel(grid, economy, wall, T0 + 10 * SEC), "anulowano wał")
	assert_eq(economy.amounts, before, "cały koszt wrócił")
	assert_true(not q.cancel(grid, economy, wall, T0), "drugi raz nie ma czego anulować")
	return true


func test_cancel_upgrade_keeps_building() -> bool:
	var c := _castle()
	var grid: BuildGrid = c[0]
	var economy: Economy = c[1]
	var q := BuildQueue.new()
	var manor := grid.manor_id()
	var before: Array[int] = economy.amounts.duplicate()
	q.order_upgrade(grid, economy, manor, T0)
	assert_true(q.cancel(grid, economy, manor, T0 + MIN), "anulowano ulepszenie dworu")
	assert_true(grid.buildings.has(manor), "dwór stoi")
	assert_eq(grid.manor_level(), 1, "poziom bez zmian")
	assert_eq(economy.amounts, before, "zwrot")
	return true


func test_same_orders_same_result() -> bool:
	var results: Array = []
	for run in 2:
		var c := _castle()
		var grid: BuildGrid = c[0]
		var economy: Economy = c[1]
		var q := BuildQueue.new()
		q.order_build(grid, economy, _free_cell(grid, K.LUMBER_HUT), K.LUMBER_HUT, T0)
		q.order_build(grid, economy, _free_cell(grid, K.TOWER), K.TOWER, T0 + SEC)
		q.update(T0 + 30 * MIN, grid, economy)
		results.append([economy.amounts.duplicate(), grid.levels.duplicate(), grid.buildings.duplicate()])
	assert_eq(results[0], results[1], "te same zlecenia, ten sam zamek")
	return true


func test_texts_fit_on_screen() -> bool:
	assert_eq(Hud.format_time(5 * SEC), "0:05", "5 s")
	assert_eq(Hud.format_time(90 * MIN), "1:30:00", "90 min")
	assert_eq(Hud.format_time(1), "0:01", "zaokrąglenie w górę")
	assert_eq(Hud.cost_text([120, 40, 40, 0] as Array[int]), "120 Dr 40 Ka 40 Ży", "koszt bez zer")
	var c := _castle()
	var grid: BuildGrid = c[0]
	var q := BuildQueue.new()
	for kind in BuildingTypes.count():
		for level in range(1, BuildingTypes.MAX_LEVEL + 1):
			var msg := "%s: %s, %s" % [BuildingTypes.NAMES[kind], Hud.cost_text(BuildConfig.cost(kind, level)),
					Hud.format_time(BuildConfig.time_ms(kind, level))]
			assert_true(PixelFont.text_width(msg) <= 312, "„%s” mieści się" % msg)
			var up := "Ulepszenie: %s, %s" % [Hud.cost_text(BuildConfig.cost(kind, level)),
					Hud.format_time(BuildConfig.time_ms(kind, level))]
			assert_true(PixelFont.text_width(up) <= 312, "„%s” mieści się" % up)
	for m in BuildQueue.MESSAGES:
		assert_true(PixelFont.text_width(m) <= 312, "„%s” mieści się" % m)
	assert_true(PixelFont.text_width(q.upgrade_hint(grid, grid.manor_id())) <= 312, "podpowiedź dworu")
	var card := Hud.card_rects(Vector2(320, 180))
	var status_w := PixelFont.text_width("budowa 11:59:59")
	assert_true(PixelFont.text_width("Brama drewniana") + status_w + 12 <= card[-1].end.x - card[0].position.x + 8,
			"tytuł i czas budowy mieszczą się na karcie")
	return true
