class_name Economy
extends RefCounted
## Surowce zamku i ich produkcja w czasie. Cały rachunek jest w liczbach całkowitych:
## ułamki jednostek czekają w `_remainder` (jednostka × milisekunda), więc wynik nie zależy
## od tego, czy czas płynie co klatkę, co sekundę czy jednym skokiem po powrocie do gry.
## Liczby balansu są w EconomyConfig. Żywność może mieć ujemny bilans, gdy armia je więcej,
## niż zamek produkuje (#214, net_rates()); zapas wtedy maleje, a po zerze rośnie głód. Pojemność to zapas z Dworu plus Magazyny (`capacities`),
## liczona z siatki przez refresh_capacity(); sama nie trafia do zapisu.

const MS_PER_HOUR := 3600 * 1000

var amounts: Array[int] = []
## Czas ostatniego naliczenia (unix, ms). Na jego podstawie liczy się nieobecność.
var last_update_ms := 0
## Pojemność każdego surowca (0 = bez limitu). Na start tyle, ile daje sam Dwór.
var capacities: Array[int] = []
## Głód (#214): ile ms żywność była na zerze przy ujemnym bilansie (armia je więcej, niż zamek
## produkuje), a jeszcze nie zamieniła się w dezercję (Recruitment.starve). Trafia do zapisu.
var starved_ms := 0
var _remainder: Array[int] = []


func _init(now_ms: int = 0) -> void:
	amounts.assign(EconomyConfig.START)
	capacities.assign(EconomyConfig.CAPACITY)
	for res in EconomyConfig.count():
		_remainder.append(0)
	last_update_ms = now_ms


## Produkcja na godzinę dla zamku z siatki `grid`: gród plus budynki produkcyjne, razy premie
## ze zbadanych technologii (`research`, np. G1 +20% drewna) i z perka władcy Gospodarny (+10 punktów
## procentowych do premii, #32). Budynek w ruinie po ataku PvP
## (`grid.ruined`, #99) daje Ruins.PRODUCTION_PERCENT swojej produkcji.
static func rates(grid: BuildGrid, research: Research = null) -> Array[int]:
	var out: Array[int] = []
	out.assign(EconomyConfig.BASE_PER_HOUR)
	var perk_bonus := 0
	if grid != null:
		_add_buildings(grid, out)
		perk_bonus = RulerPerks.production_bonus(grid.ruler_perk)
	if research != null or perk_bonus > 0:
		for res in out.size():
			var percent := research.production_percent(res) if research != null else 100
			@warning_ignore("integer_division")
			out[res] = out[res] * (percent + perk_bonus) / 100
	return out


## Bilans na godzinę: produkcja z rates() minus utrzymanie armii w żywności (#214). Żywność
## może wyjść ujemna; wtedy advance() zjada zapas, a po jego końcu liczy głód (starved_ms).
static func net_rates(grid: BuildGrid, research: Research = null, upkeep: int = 0) -> Array[int]:
	var out := rates(grid, research)
	out[EconomyConfig.Res.FOOD] -= maxi(0, upkeep)
	return out


static func _add_buildings(grid: BuildGrid, out: Array[int]) -> void:
	for id: int in grid.buildings:
		var entry: Array = EconomyConfig.BUILDING_PRODUCTION.get(grid.kinds[id], [])
		if entry.is_empty() or grid.levels[id] < 1:
			continue  # plac budowy jeszcze nic nie produkuje
		var res: int = entry[0]
		var per_level: Array = entry[1]
		var amount := per_level[clampi(grid.levels[id], 1, per_level.size()) - 1] as int
		if grid.ruined.has(id):
			@warning_ignore("integer_division")
			amount = amount * Ruins.PRODUCTION_PERCENT / 100  # ruina po ataku PvP (#99)
		out[res] += amount


## Pojemność dla zamku z siatki `grid`: zapas Dworu plus każdy ukończony Magazyn według poziomu.
## Plac budowy (poziom 0) jeszcze nic nie mieści. Surowce bez limitu (złoto) zostają bez limitu.
static func capacities_for(grid: BuildGrid) -> Array[int]:
	var out: Array[int] = []
	out.assign(EconomyConfig.CAPACITY)
	if grid == null:
		return out
	var extra := 0
	for id: int in grid.buildings:
		if grid.kinds[id] == BuildingTypes.Kind.WAREHOUSE and grid.levels[id] >= 1:
			extra += EconomyConfig.WAREHOUSE_CAPACITY[clampi(grid.levels[id], 1,
					EconomyConfig.WAREHOUSE_CAPACITY.size()) - 1]
	for res in out.size():
		if EconomyConfig.is_capped(res):
			out[res] += extra
	return out


## Przelicza pojemność z siatki (po ukończeniu, rozbiórce albo odczycie zamku). Gdy pojemność
## spadła (rozebrany Magazyn), nadmiar przepada, żeby zapas nigdy nie przekraczał magazynów.
func refresh_capacity(grid: BuildGrid) -> void:
	capacities = capacities_for(grid)
	for res in EconomyConfig.count():
		if EconomyConfig.is_capped(res) and amounts[res] > capacities[res]:
			amounts[res] = capacities[res]
			_remainder[res] = 0


func capacity(res: int) -> int:
	return capacities[res]


func is_full(res: int) -> bool:
	return EconomyConfig.is_capped(res) and amounts[res] >= capacity(res)


## Nalicza produkcję za `ms` milisekund przy stawkach `per_hour`. Zwraca przyrost każdego
## surowca. Pełny magazyn nie gromadzi ułamków, więc po wydaniu surowca nic nie „wyskakuje”.
func advance(ms: int, per_hour: Array[int]) -> Array[int]:
	var gained: Array[int] = []
	ms = clampi(ms, 0, EconomyConfig.MAX_CATCH_UP_MS)
	for res in EconomyConfig.count():
		var before := amounts[res]
		if per_hour[res] < 0:
			_consume(res, ms, -per_hour[res])
			gained.append(amounts[res] - before)
			continue
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


## Zużycie `per_hour` jednostek na godzinę przez `ms` ms (ujemny bilans żywności, #214). Zapas
## i ułamek schodzą w tej samej skali co przy produkcji (jednostka × ms). Gdy zapas się skończy,
## reszta czasu idzie do starved_ms: ceil, więc ostatnia porcja zawsze zdąży zejść przed głodem.
func _consume(res: int, ms: int, per_hour: int) -> void:
	var stock := amounts[res] * MS_PER_HOUR + _remainder[res]
	var need := per_hour * ms
	if need <= stock:
		stock -= need
		@warning_ignore("integer_division")
		amounts[res] = stock / MS_PER_HOUR
		_remainder[res] = stock % MS_PER_HOUR
		return
	@warning_ignore("integer_division")
	var empty_after := (stock + per_hour - 1) / per_hour
	amounts[res] = 0
	_remainder[res] = 0
	starved_ms += maxi(0, ms - empty_after)


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


## Dolicza zmianę zapasów z serwera (#274, łup PvP scalony przy zapisie zamku): dodatnią do pojemności
## magazynu, ujemną najwyżej do zera. Zwraca, o ile faktycznie zmienił się każdy surowiec.
func apply_delta(delta: Array[int]) -> Array[int]:
	var out: Array[int] = []
	for res in EconomyConfig.count():
		var d := delta[res] if res < delta.size() else 0
		if d >= 0:
			out.append(add(res, d))
			continue
		var before := amounts[res]
		amounts[res] = maxi(0, before + d)
		if amounts[res] == 0:
			_remainder[res] = 0
		out.append(amounts[res] - before)
	return out


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


## Stan do zapisu: zapasy, ułamki jednostek i czas ostatniego naliczenia (liczby całkowite).
func save_data() -> Dictionary:
	return {"amounts": amounts.duplicate(), "remainder": _remainder.duplicate(), "last_update_ms": last_update_ms,
			"starved_ms": starved_ms}


## Wczytuje stan z save_data(). Brakujące albo złe pola zostawiają wartości startowe.
## Zapasy są przycięte do pojemności magazynów, więc zapis nie przemyci przepełnienia.
func load_data(d: Dictionary) -> void:
	var saved_amounts: Array = d.get("amounts", []) as Array
	var saved_rem: Array = d.get("remainder", []) as Array
	for res in EconomyConfig.count():
		if res < saved_amounts.size():
			amounts[res] = maxi(0, int(saved_amounts[res]))
			if EconomyConfig.is_capped(res):
				amounts[res] = mini(amounts[res], capacity(res))
		if res < saved_rem.size():
			_remainder[res] = clampi(int(saved_rem[res]), 0, MS_PER_HOUR - 1)
	last_update_ms = int(d.get("last_update_ms", last_update_ms))
	starved_ms = clampi(int(d.get("starved_ms", 0)), 0, EconomyConfig.MAX_CATCH_UP_MS)
