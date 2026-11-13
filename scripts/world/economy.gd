class_name Economy
extends RefCounted
## Surowce zamku i ich produkcja w czasie. Cały rachunek jest w liczbach całkowitych:
## ułamki jednostek czekają w `_remainder` (jednostka × milisekunda), więc wynik nie zależy
## od tego, czy czas płynie co klatkę, co sekundę czy jednym skokiem po powrocie do gry.
## Liczby balansu są w EconomyConfig.

const MS_PER_HOUR := 3600 * 1000

var amounts: Array[int] = []
## Czas ostatniego naliczenia (unix, ms). Na jego podstawie liczy się nieobecność.
var last_update_ms := 0
var _remainder: Array[int] = []


func _init(now_ms: int = 0) -> void:
	amounts.assign(EconomyConfig.START)
	for res in EconomyConfig.count():
		_remainder.append(0)
	last_update_ms = now_ms


## Produkcja na godzinę dla zamku z siatki `grid`: gród plus budynki produkcyjne.
static func rates(grid: BuildGrid) -> Array[int]:
	var out: Array[int] = []
	out.assign(EconomyConfig.BASE_PER_HOUR)
	if grid == null:
		return out
	for id: int in grid.buildings:
		var entry: Array = EconomyConfig.BUILDING_PRODUCTION.get(grid.kinds[id], [])
		if entry.is_empty():
			continue
		var res: int = entry[0]
		var per_level: Array = entry[1]
		out[res] += per_level[clampi(grid.levels[id], 1, per_level.size()) - 1] as int
	return out


static func capacity(res: int) -> int:
	return EconomyConfig.CAPACITY[res]


func is_full(res: int) -> bool:
	return EconomyConfig.is_capped(res) and amounts[res] >= capacity(res)


## Nalicza produkcję za `ms` milisekund przy stawkach `per_hour`. Zwraca przyrost każdego
## surowca. Pełny magazyn nie gromadzi ułamków, więc po wydaniu surowca nic nie „wyskakuje”.
func advance(ms: int, per_hour: Array[int]) -> Array[int]:
	var gained: Array[int] = []
	ms = clampi(ms, 0, EconomyConfig.MAX_CATCH_UP_MS)
	for res in EconomyConfig.count():
		var before := amounts[res]
		if is_full(res) or per_hour[res] <= 0:
			_remainder[res] = 0
			gained.append(0)
			continue
		var total := _remainder[res] + per_hour[res] * ms
		@warning_ignore("integer_division")
		var whole := total / MS_PER_HOUR
		_remainder[res] = total % MS_PER_HOUR
		amounts[res] = before + whole
		if EconomyConfig.is_capped(res) and amounts[res] >= capacity(res):
			amounts[res] = capacity(res)
			_remainder[res] = 0
		gained.append(amounts[res] - before)
	return gained


## Nalicza produkcję od ostatniego naliczenia do `now_ms` (także za czas, gdy gra była w tle).
## Zegar cofnięty wstecz nic nie odbiera, tylko przestawia punkt odniesienia.
func update(now_ms: int, per_hour: Array[int]) -> Array[int]:
	var elapsed := maxi(0, now_ms - last_update_ms)
	last_update_ms = now_ms
	return advance(elapsed, per_hour)


## Dodaje surowiec (np. łup) do pojemności magazynu. Zwraca, ile faktycznie weszło.
func add(res: int, amount: int) -> int:
	var before := amounts[res]
	amounts[res] = before + maxi(0, amount)
	if EconomyConfig.is_capped(res):
		amounts[res] = mini(amounts[res], capacity(res))
	return amounts[res] - before


## Koszt to tablica ilości w kolejności EconomyConfig.Res.
func can_afford(cost: Array[int]) -> bool:
	for res in cost.size():
		if amounts[res] < cost[res]:
			return false
	return true


## Pobiera koszt w całości albo nic. Zwraca false, gdy brakuje któregoś surowca.
func spend(cost: Array[int]) -> bool:
	if not can_afford(cost):
		return false
	for res in cost.size():
		amounts[res] -= cost[res]
	return true
