class_name Goods
extends RefCounted
## Zbrojownia: zapasy towarów i ich produkcja w czasie (#88). Wytwórcy wykonują cykle przepisów
## z GoodsConfig: każdy cykl zużywa wejścia (surowce z Economy i towary) i daje wyjścia.
## Brak wejścia albo pełna zbrojownia zatrzymuje przepis; niewykonane cykle przepadają, a ułamek
## cyklu czeka (cykl × milisekunda), jak w Economy. Rachunek jest w liczbach całkowitych, więc
## jest deterministyczny. Pojedynczy przepis daje to samo co klatkę i jednym skokiem; w łańcuchu
## jeden skok liczy najpierw cały półprodukt, a potem jego zużycie, więc po długiej nieobecności
## dalszy wytwórca nie traci cykli, które co klatkę przepadłyby przez chwilowy brak wejścia.

const MS_PER_HOUR := 3600 * 1000

var amounts: Array[int] = []
var last_update_ms := 0
## Ułamki cykli każdego przepisu (cykl × milisekunda).
var _progress: Array[int] = []


func _init(now_ms: int = 0) -> void:
	for good in GoodsConfig.count():
		amounts.append(0)
	for recipe in GoodsConfig.RECIPES.size():
		_progress.append(0)
	last_update_ms = now_ms


## Wytwórcy w zamku: wytwórca → poziomy jego gotowych budynków (plac budowy nie produkuje).
static func producers(grid: BuildGrid) -> Dictionary:
	var out := {}
	if grid == null:
		return out
	for id: int in grid.buildings:
		var producer: String = GoodsConfig.PRODUCER_KINDS.get(grid.kinds[id], "")
		if producer.is_empty() or grid.levels[id] < 1:
			continue
		if not out.has(producer):
			out[producer] = [] as Array[int]
		(out[producer] as Array[int]).append(grid.levels[id])
	return out


func is_full(good: int) -> bool:
	return amounts[good] >= GoodsConfig.CAPACITY[good]


## Dodaje towar do pojemności zbrojowni. Zwraca, ile faktycznie weszło.
func add(good: int, amount: int) -> int:
	var before := amounts[good]
	amounts[good] = mini(before + maxi(0, amount), GoodsConfig.CAPACITY[good])
	return amounts[good] - before


## Pobiera towary w całości albo nic (np. przy rekrutacji, #89). `cost`: {Good: ilość}.
func take(cost: Dictionary) -> bool:
	for good: int in cost:
		if amounts[good] < int(cost[good]):
			return false
	for good: int in cost:
		amounts[good] -= int(cost[good])
	return true


## Tempo strzelania wież i strzelców w procentach: pusta zbrojownia strzał to −50% (#88).
func fire_rate_percent() -> int:
	return 100 if amounts[GoodsConfig.Good.ARROW] > 0 else GoodsConfig.NO_ARROWS_FIRE_PERCENT


## Nalicza produkcję za `ms` milisekund dla wytwórców `producers` (jak z producers()).
## Wytwórcy liczą się w kolejności GoodsConfig.PRODUCERS. Zwraca przyrost każdego towaru.
func advance(ms: int, producers_by_kind: Dictionary, economy: Economy) -> Array[int]:
	var before: Array[int] = []
	before.assign(amounts)
	ms = clampi(ms, 0, EconomyConfig.MAX_CATCH_UP_MS)
	for producer in GoodsConfig.PRODUCERS:
		var levels: Array = producers_by_kind.get(producer, [])
		if levels.is_empty():
			continue
		for recipe in GoodsConfig.RECIPES.size():
			if GoodsConfig.RECIPES[recipe][0] != producer:
				continue
			var per_hour := 0
			for level: int in levels:
				per_hour += GoodsConfig.cycles_per_hour(recipe, level)
			_run(recipe, ms, per_hour, economy)
	var gained: Array[int] = []
	for good in amounts.size():
		gained.append(amounts[good] - before[good])
	return gained


## Nalicza produkcję od ostatniego naliczenia do `now_ms`. Zegar cofnięty nic nie odbiera.
func update(now_ms: int, producers_by_kind: Dictionary, economy: Economy) -> Array[int]:
	var elapsed := maxi(0, now_ms - last_update_ms)
	last_update_ms = now_ms
	return advance(elapsed, producers_by_kind, economy)


## Wykonuje tyle cykli przepisu, ile przypada na `ms` przy `per_hour`, ale nie więcej, niż
## pozwalają wejścia i miejsce w zbrojowni.
func _run(recipe: int, ms: int, per_hour: int, economy: Economy) -> void:
	if per_hour <= 0:
		_progress[recipe] = 0
		return
	var row: Array = GoodsConfig.RECIPES[recipe]
	var res_in: Dictionary = row[3]
	var goods_in: Dictionary = row[4]
	var goods_out: Dictionary = row[5]
	var res_out: Dictionary = row[6]
	var total := _progress[recipe] + per_hour * ms
	@warning_ignore("integer_division")
	var cycles := total / MS_PER_HOUR
	_progress[recipe] = total % MS_PER_HOUR
	if cycles <= 0:
		return
	var n := cycles
	for res: int in res_in:
		@warning_ignore("integer_division")
		n = mini(n, economy.amounts[res] / int(res_in[res]))
	for good: int in goods_in:
		@warning_ignore("integer_division")
		n = mini(n, amounts[good] / int(goods_in[good]))
	if not goods_out.is_empty():
		# cykl rusza, dopóki choć jeden z jego towarów mieści się w zbrojowni
		var room := 0
		for good: int in goods_out:
			@warning_ignore("integer_division")
			room = maxi(room, (GoodsConfig.CAPACITY[good] - amounts[good] + int(goods_out[good]) - 1) / int(goods_out[good]))
		n = mini(n, room)
	if n < cycles:
		_progress[recipe] = 0  # zatrzymana produkcja nie gromadzi ułamków
	if n <= 0:
		return
	for res: int in res_in:
		economy.amounts[res] -= int(res_in[res]) * n
	for good: int in goods_in:
		amounts[good] -= int(goods_in[good]) * n
	for good: int in goods_out:
		add(good, int(goods_out[good]) * n)
	for res: int in res_out:
		economy.add(res, int(res_out[res]) * n)


## Stan do zapisu: zapasy, ułamki cykli i czas ostatniego naliczenia (liczby całkowite).
func save_data() -> Dictionary:
	return {"amounts": amounts.duplicate(), "progress": _progress.duplicate(), "last_update_ms": last_update_ms}


## Wczytuje stan z save_data(). Zapasy są przycięte do pojemności zbrojowni.
func load_data(d: Dictionary) -> void:
	var saved_amounts: Array = d.get("amounts", []) as Array
	var saved_progress: Array = d.get("progress", []) as Array
	for good in amounts.size():
		if good < saved_amounts.size():
			amounts[good] = clampi(int(saved_amounts[good]), 0, GoodsConfig.CAPACITY[good])
	for recipe in _progress.size():
		if recipe < saved_progress.size():
			_progress[recipe] = clampi(int(saved_progress[recipe]), 0, MS_PER_HOUR - 1)
	last_update_ms = int(d.get("last_update_ms", last_update_ms))
