extends TestCase
## Ekonomia: zapasy startowe, stawki z budynków, naliczanie w czasie (także po nieobecności),
## limity magazynów, łup i wydawanie.

const HOUR := Economy.MS_PER_HOUR
const R := EconomyConfig.Res


func _grid() -> BuildGrid:
	var map := TerrainMap.generate(1337)
	return BuildGrid.new(map)


## Pierwsze wolne miejsce na budynek danego rodzaju, szukane od środka mapy.
func _place(grid: BuildGrid, kind: int) -> int:
	var c := grid.terrain.center()
	for r in 20:
		for dy in range(-r, r + 1):
			for dx in range(-r, r + 1):
				var id := grid.place_kind(c + Vector2i(dx, dy), kind)
				if id != 0:
					return id
	return 0


func test_start_amounts() -> bool:
	var e := Economy.new(1000)
	assert_eq(e.amounts, EconomyConfig.START, "zapasy startowe")
	assert_eq(e.last_update_ms, 1000, "czas startu")
	assert_eq(EconomyConfig.count(), 4, "cztery surowce")
	return true


func test_rates_from_buildings() -> bool:
	var grid := _grid()
	assert_eq(Economy.rates(grid), EconomyConfig.BASE_PER_HOUR, "pusty zamek: tylko gród")
	var hut := _place(grid, BuildingTypes.Kind.LUMBER_HUT)
	assert_true(hut != 0, "chata stoi")
	_place(grid, BuildingTypes.Kind.TOWER)
	var huts: Array = EconomyConfig.BUILDING_PRODUCTION[BuildingTypes.Kind.LUMBER_HUT][1]
	assert_eq(Economy.rates(grid)[R.WOOD], EconomyConfig.BASE_PER_HOUR[R.WOOD] + (huts[0] as int), "chata poz. 1")
	grid.upgrade(hut)
	grid.upgrade(hut)
	assert_eq(Economy.rates(grid)[R.WOOD], EconomyConfig.BASE_PER_HOUR[R.WOOD] + (huts[2] as int), "chata poz. 3")
	assert_eq(Economy.rates(grid)[R.STONE], EconomyConfig.BASE_PER_HOUR[R.STONE], "wieża nic nie produkuje")
	assert_eq(Economy.rates(grid)[R.GOLD], 0, "złoto nie rośnie samo")
	return true


func test_one_hour_of_production() -> bool:
	var e := Economy.new()
	var rates: Array[int] = [80, 20, 20, 0]
	var gained := e.advance(HOUR, rates)
	assert_eq(gained, [80, 20, 20, 0] as Array[int], "przyrost za godzinę")
	assert_eq(e.amounts, [580, 320, 320, 50] as Array[int], "zapasy po godzinie")
	return true


## Naliczanie co klatkę, co sekundę i jednym skokiem daje ten sam wynik (bez dryfu ułamków).
func test_same_result_regardless_of_step() -> bool:
	var rates: Array[int] = [97, 13, 7, 0]
	var jump := Economy.new()
	jump.advance(2 * HOUR + 777, rates)
	var seconds := Economy.new()
	for i in 7200:
		seconds.advance(1000, rates)
	seconds.advance(777, rates)
	var frames := Economy.new()
	var left := 2 * HOUR + 777
	while left > 0:
		var step := mini(left, 16 + left % 7)
		frames.advance(step, rates)
		left -= step
	assert_eq(seconds.amounts, jump.amounts, "co sekundę = jednym skokiem")
	assert_eq(frames.amounts, jump.amounts, "nierówne klatki = jednym skokiem")
	return true


## Kryterium #10: po powrocie po kilku godzinach surowce są wyższe.
func test_resources_grow_after_hours_away() -> bool:
	var grid := _grid()
	var hut := _place(grid, BuildingTypes.Kind.LUMBER_HUT)
	grid.upgrade(hut)
	var start := 1_700_000_000_000
	var e := Economy.new(start)
	var gained := e.update(start + 4 * HOUR, Economy.rates(grid))
	var wood: int = EconomyConfig.START[R.WOOD] + 4 * Economy.rates(grid)[R.WOOD]
	assert_eq(e.amounts[R.WOOD], mini(wood, EconomyConfig.CAPACITY[R.WOOD]), "drewno po 4 godzinach")
	assert_true(gained[R.STONE] > 0 and gained[R.FOOD] > 0, "kamień i żywność też rosną")
	assert_eq(gained[R.GOLD], 0, "złoto bez zmian")
	assert_eq(e.last_update_ms, start + 4 * HOUR, "nowy punkt odniesienia")
	return true


func test_clock_going_back_takes_nothing() -> bool:
	var e := Economy.new(10 * HOUR)
	var rates: Array[int] = [100, 100, 100, 0]
	assert_eq(e.update(9 * HOUR, rates), [0, 0, 0, 0] as Array[int], "cofnięty zegar nic nie daje")
	assert_eq(e.amounts, EconomyConfig.START, "nic nie zabrano")
	e.update(10 * HOUR, rates)
	assert_eq(e.amounts[R.WOOD], EconomyConfig.START[R.WOOD] + 100, "liczy się od nowego punktu")
	return true


## Kryterium #10: nie da się przekroczyć pojemności magazynu.
func test_storage_capacity_is_never_exceeded() -> bool:
	var e := Economy.new()
	var rates: Array[int] = [500, 500, 500, 0]
	e.advance(1000 * HOUR, rates)
	for res: int in [R.WOOD, R.STONE, R.FOOD]:
		assert_eq(e.amounts[res], EconomyConfig.CAPACITY[res], "%s do pełna" % EconomyConfig.NAMES[res])
		assert_true(e.is_full(res), "%s pełny" % EconomyConfig.NAMES[res])
	assert_eq(e.add(R.WOOD, 300), 0, "łup nie wchodzi do pełnego magazynu")
	assert_eq(e.amounts[R.WOOD], EconomyConfig.CAPACITY[R.WOOD], "nadal pojemność")
	# po wydaniu magazyn napełnia się od zera ułamków: bez „zaległej” produkcji
	assert_true(e.spend([100, 0, 0, 0] as Array[int]), "wydano 100 drewna")
	e.advance(HOUR / 10 - 1, rates)
	assert_eq(e.amounts[R.WOOD], EconomyConfig.CAPACITY[R.WOOD] - 100 + 49, "6 minut minus 1 ms po wydaniu")
	return true


func test_gold_has_no_limit_and_comes_from_loot() -> bool:
	var e := Economy.new()
	assert_true(not EconomyConfig.is_capped(R.GOLD), "złoto bez limitu")
	assert_eq(e.add(R.GOLD, 1_000_000), 1_000_000, "cały łup złota wchodzi")
	assert_eq(e.add(R.STONE, 900), EconomyConfig.CAPACITY[R.STONE] - EconomyConfig.START[R.STONE], "kamień do pojemności")
	assert_eq(e.add(R.FOOD, -50), 0, "ujemny łup nic nie zabiera")
	return true


func test_spend_is_all_or_nothing() -> bool:
	var e := Economy.new()
	assert_true(e.can_afford([500, 300, 0, 0] as Array[int]), "stać na dokładnie tyle, ile jest")
	assert_true(not e.spend([100, 400, 0, 0] as Array[int]), "brak kamienia")
	assert_eq(e.amounts, EconomyConfig.START, "nic nie pobrano")
	assert_true(e.spend([100, 50, 0, 10] as Array[int]), "pobrano")
	assert_eq(e.amounts, [400, 250, 300, 40] as Array[int], "po zakupie")
	return true


## Górny pasek przy pełnych magazynach, dużym zapasie złota, długiej budowie i ostatnim roku epoki
## mieści się na ekranie 320 px z marginesami narożników.
func test_resources_bar_fits() -> bool:
	var full: Array[int] = []
	for res in EconomyConfig.count():
		full.append(EconomyConfig.CAPACITY[res] if EconomyConfig.is_capped(res) else 99999)
	var right := PixelFont.text_width(Hud.top_right_text("11:59:59 +3", Ages.label(0, 5)))
	var xs := Hud.resource_layout(full, Hud.CORNER_INSET)
	assert_eq(xs.size(), EconomyConfig.count() + 1, "pozycja każdej ikony i koniec paska")
	assert_true(xs[-1] + 6 + right <= 320 - Hud.CORNER_INSET, "pasek surowców, budowa i epoka mieszczą się w 320 px")
	return true
