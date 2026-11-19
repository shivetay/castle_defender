extends TestCase
## Magazyn: Dwór daje pojemność na start, a każdy ukończony Magazyn podnosi limit drewna, kamienia
## i żywności według poziomu. Pojemność liczy się z siatki, rośnie od chwili ukończenia budowy,
## spada po rozbiórce i jest ta sama po zapisie i odczycie.

const HOUR := Economy.MS_PER_HOUR
const K := BuildingTypes.Kind
const R := EconomyConfig.Res
const T0 := 1_000_000_000


func _grid() -> BuildGrid:
	var grid := BuildGrid.new(TerrainMap.generate(1337))
	grid.place(grid.manor_spot(64), K.MANOR, 1)
	return grid


func _spot(grid: BuildGrid) -> Vector2i:
	return grid.spot_around(Rect2i(grid.terrain.center(), Vector2i.ONE), K.WAREHOUSE, 30).position


func test_warehouse_is_buildable_economy() -> bool:
	assert_true(BuildingTypes.BUILD_BAR.has(K.WAREHOUSE), "na pasku budowy")
	assert_eq(BuildingTypes.category(K.WAREHOUSE), BuildingTypes.Category.ECONOMY, "w Gospodarce")
	assert_true(BuildConfig.is_unlocked(K.WAREHOUSE, null), "bez technologii")
	assert_true(not BuildingTypes.is_unique(K.WAREHOUSE), "można postawić kilka i rozebrać")
	assert_eq(BuildingTypes.NAMES.size(), BuildingTypes.SIZES.size(), "rozmiar dla każdego rodzaju")
	assert_eq(BuildingTypes.SHORT_NAMES.size(), BuildingTypes.NAMES.size(), "skrót dla każdego rodzaju")
	assert_true(BuildPanel.describe(K.WAREHOUSE).contains("pojemności"), "opis w panelu budowy")
	return true


func test_capacity_from_manor_and_warehouses() -> bool:
	var grid := _grid()
	assert_eq(Economy.capacities_for(grid), EconomyConfig.CAPACITY, "bez Magazynu: tylko Dwór")
	var site := grid.place_kind(_spot(grid), K.WAREHOUSE, 0)
	assert_true(site != 0, "plac budowy Magazynu")
	assert_eq(Economy.capacities_for(grid), EconomyConfig.CAPACITY, "plac budowy jeszcze nic nie mieści")
	grid.levels[site] = 1
	var one := EconomyConfig.WAREHOUSE_CAPACITY[0]
	var caps := Economy.capacities_for(grid)
	for res: int in [R.WOOD, R.STONE, R.FOOD]:
		assert_eq(caps[res], EconomyConfig.CAPACITY[res] + one, "%s: Dwór + Magazyn 1" % EconomyConfig.NAMES[res])
	assert_eq(caps[R.GOLD], 0, "złoto dalej bez limitu")
	grid.levels[site] = 3
	grid.place_kind(_spot(grid), K.WAREHOUSE, 1)
	assert_eq(Economy.capacities_for(grid)[R.WOOD],
			EconomyConfig.CAPACITY[R.WOOD] + EconomyConfig.WAREHOUSE_CAPACITY[2] + one, "Magazyny się sumują")
	return true


## Ukończony Magazyn podnosi limit od chwili ukończenia: wcześniej produkcja staje na pojemności Dworu.
func test_finished_warehouse_raises_limit() -> bool:
	var grid := _grid()
	var e := Economy.new(T0)
	var q := BuildQueue.new()
	assert_eq(q.order_build(grid, e, _spot(grid), K.WAREHOUSE, T0), BuildQueue.Result.OK, "zlecono Magazyn")
	var rates: Array[int] = [600, 600, 600, 0]
	e.advance(10 * HOUR, rates)
	assert_eq(e.amounts[R.WOOD], EconomyConfig.CAPACITY[R.WOOD], "w budowie: limit Dworu")
	q.update(T0 + BuildConfig.time_ms(K.WAREHOUSE, 1), grid, e)
	assert_eq(e.capacity(R.WOOD), EconomyConfig.CAPACITY[R.WOOD] + EconomyConfig.WAREHOUSE_CAPACITY[0], "nowy limit")
	assert_true(not e.is_full(R.WOOD), "magazyn znów ma miejsce")
	e.advance(10 * HOUR, rates)
	assert_eq(e.amounts[R.WOOD], e.capacity(R.WOOD), "produkcja dochodzi do nowego limitu")
	assert_true(e.spend([0, 600, 0, 0] as Array[int]), "wydano kamień")
	assert_eq(e.add(R.STONE, 100_000), 600, "łup do nowego limitu")
	assert_eq(e.amounts[R.STONE], e.capacity(R.STONE), "kamień pełny po łupie")
	return true


## Rozebrany Magazyn zmniejsza pojemność, a nadmiar przepada (zapas nigdy nie przekracza magazynów).
func test_demolished_warehouse_lowers_limit() -> bool:
	var grid := _grid()
	var id := grid.place_kind(_spot(grid), K.WAREHOUSE, 2)
	var e := Economy.new(T0)
	e.refresh_capacity(grid)
	e.add(R.WOOD, 100_000)
	assert_eq(e.amounts[R.WOOD], EconomyConfig.CAPACITY[R.WOOD] + EconomyConfig.WAREHOUSE_CAPACITY[1], "pełny z Magazynem")
	grid.remove(id)
	e.refresh_capacity(grid)
	assert_eq(e.amounts[R.WOOD], EconomyConfig.CAPACITY[R.WOOD], "po rozbiórce przycięte do Dworu")
	assert_eq(e.amounts[R.GOLD], EconomyConfig.START[R.GOLD], "złota nie przycina")
	return true


## Zapis i odczyt: zapas ponad pojemność Dworu wraca w całości, bo pojemność liczy się z Magazynów
## przed odczytem zapasów. Ten sam zamek daje zawsze tę samą pojemność.
func test_save_keeps_stock_above_manor_capacity() -> bool:
	var grid := _grid()
	grid.place_kind(_spot(grid), K.WAREHOUSE, 4)
	var e := Economy.new(T0)
	e.refresh_capacity(grid)
	e.add(R.FOOD, 2000)
	var stock := e.amounts[R.FOOD]
	assert_true(stock > EconomyConfig.CAPACITY[R.FOOD], "zapas ponad limit Dworu")
	var d := SaveGame.to_dict(1337, grid, e, BuildQueue.new())
	var s := SaveGame.from_dict(JSON.parse_string(JSON.stringify(d)) as Dictionary, T0)
	assert_eq(s.economy.amounts[R.FOOD], stock, "zapas po odczycie")
	assert_eq(s.economy.capacities, e.capacities, "ta sama pojemność po odczycie")
	assert_eq(Economy.capacities_for(s.grid), Economy.capacities_for(grid), "deterministycznie z siatki")
	return true


func test_info_text_explains_storage() -> bool:
	var grid := _grid()
	var amounts: Array[int] = [100, 100, 100, 0]
	var text := " | ".join(InfoText.resource(R.WOOD, grid, null, amounts))
	assert_true(text.contains("więcej mieści Magazyn"), "bez Magazynu: wskazówka (%s)" % text)
	grid.place_kind(_spot(grid), K.WAREHOUSE, 1)
	var wood := InfoText.resource(R.WOOD, grid, null, amounts)
	assert_eq(wood[0], "Zapas: 100 z %d (magazyn)" % (EconomyConfig.CAPACITY[R.WOOD] + EconomyConfig.WAREHOUSE_CAPACITY[0]),
			"zapas z Magazynem")
	assert_true(wood.has("Pojemność: Dwór 1000, Magazyn ×1: +%d" % EconomyConfig.WAREHOUSE_CAPACITY[0]), "rozbicie")
	for line in InfoPopup.wrapped(wood):
		assert_true(PixelFont.text_width(line) <= InfoPopup.WIDTH - 2 * InfoPopup.PAD, "„%s” mieści się" % line)
	return true


func test_warehouse_art_all_levels() -> bool:
	for level in range(0, BuildingTypes.MAX_LEVEL + 1):
		var img := BuildingArt.make_image(K.WAREHOUSE, level, BuildingTypes.State.INTACT)
		assert_eq(img.get_size(), BuildingTypes.size_of(K.WAREHOUSE) * BuildingArt.CELL, "rozmiar poz. %d" % level)
	return true
