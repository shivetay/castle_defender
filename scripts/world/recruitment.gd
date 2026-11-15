class_name Recruitment
extends RefCounted
## Rekrutacja (#89): armia (ile jednostek każdego rodzaju) i kolejki szkolenia w budynkach
## rekrutacji. Każdy budynek szkoli po kolei jednostki ze swojej kolejki; kolejka mieści tyle,
## ile RecruitmentConfig.training_slots() dla poziomu budynku, a poziom przyspiesza szkolenie.
## Koszt (surowce i towary) schodzi przy zleceniu; bez towaru szkolenie nie rusza. Szkolenie
## kończy się w czasie zegarowym, także offline. Limit armii liczy też jednostki w szkoleniu.
##
## Szkolić można z ekranu budynku (konkretny budynek) albo z globalnego ekranu Wojsko:
## wtedy start_any() wybiera budynek danego rodzaju z najkrótszą kolejką.

enum Result { OK, NO_BUILDING, NEEDS_TECH, WRONG_AGE, QUEUE_FULL, ARMY_FULL, NO_RESOURCES, NO_GOODS }

const MESSAGES: Array[String] = ["", "Brak budynku do szkolenia", "Najpierw zbadaj technologię",
		"Wymaga późniejszej epoki", "Kolejka szkolenia pełna", "Limit armii osiągnięty", "Brak surowców",
		"Brak towarów"]


class Order:
	extends RefCounted
	var unit := 0
	var building_id := 0
	var duration_ms := 0
	## Początek szkolenia albo -1, gdy czeka w kolejce budynku.
	var start_ms := -1

	func finish_ms() -> int:
		return start_ms + duration_ms


## Wyszkolone jednostki (indeks = UnitTypes.Unit).
var army: Array[int] = []
## Zlecenia w kolejności złożenia; pierwsze zlecenie każdego budynku jest w szkoleniu.
var orders: Array[Order] = []
## Budynek wybrany przez ostatnie udane start_any().
var last_building := 0


func _init() -> void:
	for unit in UnitTypes.count():
		army.append(0)


func army_size() -> int:
	var n := 0
	for c in army:
		n += c
	return n


## Limit armii: Dwór i Koszary (#81, #89).
static func army_limit(grid: BuildGrid) -> int:
	var limit := RecruitmentConfig.ARMY_PER_MANOR_LEVEL * grid.manor_level()
	for id: int in grid.buildings:
		if grid.kinds[id] == BuildingTypes.Kind.BARRACKS:
			limit += RecruitmentConfig.ARMY_PER_BARRACKS_LEVEL * grid.levels[id]
	return limit


## Zlecenia jednego budynku w kolejności szkolenia.
func queue_of(building_id: int) -> Array[Order]:
	var out: Array[Order] = []
	for o in orders:
		if o.building_id == building_id:
			out.append(o)
	return out


## Ile jednostek rodzaju `unit` jest w szkoleniu albo czeka.
func in_training(unit: int) -> int:
	var n := 0
	for o in orders:
		if o.unit == unit:
			n += 1
	return n


## Gotowe budynki, w których szkoli się jednostka `unit` (rosnąco po id).
static func buildings_for(unit: int, grid: BuildGrid) -> Array[int]:
	var out: Array[int] = []
	var kind := UnitTypes.building(unit)
	for id: int in grid.buildings:
		if grid.kinds[id] == kind and grid.levels[id] >= 1:
			out.append(id)
	out.sort()
	return out


## Czy jednostkę można w ogóle szkolić (technologia, epoka, budynek), bez kosztu i limitów.
func availability(unit: int, grid: BuildGrid, research: Research, age: int) -> Result:
	if UnitTypes.age(unit) > age:
		return Result.WRONG_AGE
	var tech := UnitTypes.required_tech(unit)
	if not tech.is_empty() and (research == null or not research.is_done(tech)):
		return Result.NEEDS_TECH
	if buildings_for(unit, grid).is_empty():
		return Result.NO_BUILDING
	return Result.OK


## Brakujące towary dla jednej jednostki: towar → ile brakuje.
static func missing_goods(unit: int, goods: Goods) -> Dictionary:
	var out := {}
	var cost := UnitTypes.goods_cost(unit)
	for good: int in cost:
		var lack := int(cost[good]) - goods.amounts[good]
		if lack > 0:
			out[good] = lack
	return out


## Szkoli jednostkę `unit` w budynku `building_id`. Koszt schodzi od razu.
func start(unit: int, building_id: int, grid: BuildGrid, economy: Economy, goods: Goods, research: Research,
		age: int, now_ms: int) -> Result:
	var available := availability(unit, grid, research, age)
	if available != Result.OK:
		return available
	if not buildings_for(unit, grid).has(building_id):
		return Result.NO_BUILDING
	var level := grid.levels[building_id]
	if queue_of(building_id).size() >= RecruitmentConfig.training_slots(level):
		return Result.QUEUE_FULL
	if army_size() + orders.size() >= army_limit(grid):
		return Result.ARMY_FULL
	var res_cost := _resource_array(unit)
	if not economy.can_afford(res_cost):
		return Result.NO_RESOURCES
	if not missing_goods(unit, goods).is_empty():
		return Result.NO_GOODS
	economy.spend(res_cost)
	goods.take(UnitTypes.goods_cost(unit))
	var o := Order.new()
	o.unit = unit
	o.building_id = building_id
	o.duration_ms = RecruitmentConfig.train_ms(unit, level)
	o.start_ms = now_ms if queue_of(building_id).is_empty() else -1
	orders.append(o)
	return Result.OK


## Szkolenie z globalnego ekranu: budynek danego rodzaju z najkrótszą kolejką (przy remisie
## najniższe id, więc wybór jest powtarzalny). Id wybranego budynku trafia do `last_building`.
func start_any(unit: int, grid: BuildGrid, economy: Economy, goods: Goods, research: Research, age: int,
		now_ms: int) -> Result:
	last_building = 0
	var available := availability(unit, grid, research, age)
	if available != Result.OK:
		return available
	var best := 0
	var best_len := 1 << 30
	for id in buildings_for(unit, grid):
		var n := queue_of(id).size()
		if n < RecruitmentConfig.training_slots(grid.levels[id]) and n < best_len:
			best = id
			best_len = n
	if best == 0:
		return Result.QUEUE_FULL
	var result := start(unit, best, grid, economy, goods, research, age, now_ms)
	if result == Result.OK:
		last_building = best
	return result


## Kończy szkolenia, których czas minął; w każdym budynku następne zaczyna się w chwili końca
## poprzedniego. Zwraca rodzaje wyszkolonych jednostek w kolejności końca.
func update(now_ms: int) -> Array[int]:
	var done: Array[int] = []
	var progress := true
	while progress:
		progress = false
		var earliest: Order = null
		for o in orders:
			if o.start_ms >= 0 and o.finish_ms() <= now_ms and (earliest == null or o.finish_ms() < earliest.finish_ms()):
				earliest = o
		if earliest == null:
			break
		orders.erase(earliest)
		army[earliest.unit] += 1
		done.append(earliest.unit)
		var rest := queue_of(earliest.building_id)
		if not rest.is_empty():
			rest[0].start_ms = earliest.finish_ms()
		progress = true
	return done


## Usuwa zlecenia budynku, którego już nie ma (rozbiórka). Koszt nie wraca, jak przy rozbiórce budynku.
func drop_building(building_id: int) -> void:
	for o in queue_of(building_id):
		orders.erase(o)


func remaining_ms(building_id: int, now_ms: int) -> int:
	var q := queue_of(building_id)
	if q.is_empty():
		return -1
	var t := maxi(q[0].finish_ms(), now_ms)
	for i in range(1, q.size()):
		t += q[i].duration_ms
	return t - now_ms


func save_data() -> Dictionary:
	var list: Array = []
	for o in orders:
		list.append({"unit": o.unit, "building_id": o.building_id, "duration_ms": o.duration_ms, "start_ms": o.start_ms})
	return {"army": army.duplicate(), "orders": list}


## Wczytuje stan z save_data(). Zlecenia budynków, których nie ma w siatce, są pomijane.
func load_data(d: Dictionary, grid: BuildGrid, now_ms: int) -> int:
	var skipped := 0
	var saved_army: Array = d.get("army", []) as Array
	for unit in army.size():
		army[unit] = maxi(0, int(saved_army[unit])) if unit < saved_army.size() else 0
	orders.clear()
	for entry: Variant in d.get("orders", []) as Array:
		var e := entry as Dictionary
		var unit := int(e.get("unit", -1)) if e != null else -1
		var id := int(e.get("building_id", 0)) if e != null else 0
		if unit < 0 or unit >= UnitTypes.count() or not grid.buildings.has(id):
			skipped += 1
			continue
		var o := Order.new()
		o.unit = unit
		o.building_id = id
		o.duration_ms = maxi(0, int(e.get("duration_ms", 0)))
		var first := queue_of(id).is_empty()
		o.start_ms = int(e.get("start_ms", now_ms)) if first else -1
		if first and o.start_ms < 0:
			o.start_ms = now_ms
		orders.append(o)
	return skipped


func _resource_array(unit: int) -> Array[int]:
	var out: Array[int] = []
	for res in EconomyConfig.count():
		out.append(int(UnitTypes.resource_cost(unit).get(res, 0)))
	return out
