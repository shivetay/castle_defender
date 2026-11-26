extends TestCase
## Płatne odświeżenie celów Wyprawy (#313): cena 5, 5, 7, 9, 11..., licznik dzienny zerowany
## o północy (czas lokalny), złoto pobierane tylko przy udanym szukaniu i stan w zapisie.

const GOLD := EconomyConfig.Res.GOLD
const DAY := TargetRefresh.SECONDS_PER_DAY


func _economy(gold: int) -> Economy:
	var e := Economy.new(0)
	e.amounts[GOLD] = gold
	return e


func test_cost_curve() -> bool:
	var costs: Array[int] = []
	for n in 6:
		costs.append(TargetRefresh.cost_for(n))
	assert_eq(costs, [5, 5, 7, 9, 11, 13] as Array[int], "pierwsze dwa po 5, potem +2")
	return true


func test_pay_raises_cost_and_spends_gold() -> bool:
	var r := TargetRefresh.new()
	var e := _economy(100)
	assert_eq(r.cost(10), 5, "pierwsze odświeżenie")
	assert_true(r.pay(e, 10), "zapłacone")
	assert_eq(e.amounts[GOLD], 95, "pobrane 5")
	assert_true(r.pay(e, 10), "drugie")
	assert_eq(r.cost(10), 7, "trzecie droższe")
	assert_true(r.pay(e, 10), "trzecie")
	assert_eq(e.amounts[GOLD], 83, "5 + 5 + 7")
	assert_eq(r.cost(10), 9, "czwarte")
	return true


func test_not_enough_gold_changes_nothing() -> bool:
	var r := TargetRefresh.new()
	var e := _economy(4)
	assert_true(not r.can_afford(e, 3), "za mało złota")
	assert_true(not r.pay(e, 3), "nie płaci")
	assert_eq(e.amounts[GOLD], 4, "złoto zostaje")
	assert_eq(r.cost(3), 5, "cena bez zmian")
	return true


func test_counter_resets_next_day() -> bool:
	var r := TargetRefresh.new()
	var e := _economy(100)
	for i in 3:
		r.pay(e, 20)
	assert_eq(r.cost(20), 9, "po trzech odświeżeniach")
	assert_eq(r.cost(21), 5, "nowy dzień: znowu 5")
	assert_true(r.pay(e, 21), "płaci w nowym dniu")
	assert_eq(r.cost(21), 5, "drugie w nowym dniu nadal 5")
	return true


## Północ liczy się w czasie lokalnym telefonu: przesunięcie strefy zmienia dzień.
func test_local_day_uses_time_zone() -> bool:
	var midnight_utc := 20000 * DAY
	assert_eq(TargetRefresh.local_day(midnight_utc, 0), 20000, "północ UTC")
	assert_eq(TargetRefresh.local_day(midnight_utc - 1, 0), 19999, "sekundę przed północą")
	# UTC+1: 23:30 UTC to już 0:30 następnego dnia
	assert_eq(TargetRefresh.local_day(midnight_utc - 1800, 60), 20000, "strefa +1 h")
	# UTC-5: 2:00 UTC to jeszcze poprzedni dzień
	assert_eq(TargetRefresh.local_day(midnight_utc + 7200, -300), 19999, "strefa -5 h")
	return true


func test_save_round_trip() -> bool:
	var r := TargetRefresh.new()
	var e := _economy(100)
	r.pay(e, 7)
	r.pay(e, 7)
	r.pay(e, 7)
	var back := TargetRefresh.new()
	back.load_data(r.save_data())
	assert_eq(back.cost(7), 9, "licznik z zapisu")
	var empty := TargetRefresh.new()
	empty.load_data({})
	assert_eq(empty.cost(7), 5, "brak wpisu: start od 5")
	var bad := TargetRefresh.new()
	bad.load_data({"day": "x", "count": 99})
	assert_eq(bad.cost(7), 5, "zły dzień: start od 5")
	var huge := TargetRefresh.new()
	huge.load_data({"day": 7, "count": 1e12})
	assert_eq(huge.paid_today(7), TargetRefresh.MAX_COUNT, "licznik przycięty")
	return true


## Pełny zapis gry niesie licznik odświeżeń, a zapis bez niego (starszy) zaczyna od zera.
func test_save_game_keeps_counter() -> bool:
	var grid := BuildGrid.new(TerrainMap.generate(1337))
	var e := Economy.new(0)
	e.amounts[GOLD] = 100
	var r := TargetRefresh.new()
	r.pay(e, 5)
	r.pay(e, 5)
	var d := SaveGame.to_dict(1337, grid, e, BuildQueue.new(), null, null, null, 0, null, 0, null, 0, null, null,
			null, r)
	var s := SaveGame.from_dict(JSON.parse_string(JSON.stringify(d)) as Dictionary, 0)
	assert_true(s != null, "zapis czytelny")
	assert_eq(s.target_refresh.cost(5), 7, "licznik wraca z zapisu")
	d.erase("refresh")
	var old := SaveGame.from_dict(d, 0)
	assert_eq(old.target_refresh.cost(5), 5, "zapis bez licznika: od 5")
	return true
