class_name Recruitment
extends RefCounted
## Rekrutacja (#89): armia w oddziałach i kolejki szkolenia w budynkach rekrutacji.
##
## Oddział ma jeden rodzaj jednostek i najwyżej RecruitmentConfig.SQUAD_SIZE jednostek. Gracz
## szkoli do istniejącego oddziału tego rodzaju (gdy ma wolne miejsce) albo do nowego. Cała armia
## ma globalny limit, czyli tyle, ile zamek może teraz utrzymać (Dwór i Koszary); limit i miejsca
## w oddziale liczą też jednostki w szkoleniu, więc nic nie wyjdzie ponad limit po wyszkoleniu.
##
## Każdy budynek szkoli po kolei jednostki ze swojej kolejki; kolejka mieści tyle, ile
## RecruitmentConfig.training_slots() dla poziomu budynku, a poziom przyspiesza szkolenie.
## Koszt (surowce i towary) schodzi przy zleceniu; bez towaru szkolenie nie rusza. Szkolenie
## kończy się w czasie zegarowym, także offline.
##
## Szkolić można z ekranu budynku (konkretny budynek) albo z globalnego ekranu Wojsko:
## wtedy start_any() wybiera budynek danego rodzaju z najkrótszą kolejką.

enum Result { OK, NO_BUILDING, NEEDS_TECH, WRONG_AGE, QUEUE_FULL, ARMY_FULL, NO_RESOURCES, NO_GOODS,
		SQUAD_FULL, WRONG_SQUAD, ERA_PASSED }

const MESSAGES: Array[String] = ["", "Brak budynku do szkolenia", "Najpierw zbadaj technologię",
		"Wymaga późniejszej epoki", "Kolejka szkolenia pełna", "Limit armii osiągnięty", "Brak surowców",
		"Brak towarów", "Oddział pełny", "W oddziale jest inny rodzaj jednostek", "Tylko w epoce I"]

## Id „nowego oddziału” przy zleceniu szkolenia.
const NEW_SQUAD := 0


class Squad:
	extends RefCounted
	var id := 0
	var unit := 0
	## Wyszkolone jednostki w oddziale (bez tych w szkoleniu).
	var count := 0


class Order:
	extends RefCounted
	var unit := 0
	var building_id := 0
	## Oddział, do którego trafi jednostka po wyszkoleniu.
	var squad_id := 0
	var duration_ms := 0
	## Początek szkolenia albo -1, gdy czeka w kolejce budynku.
	var start_ms := -1

	func finish_ms() -> int:
		return start_ms + duration_ms


## Oddziały w kolejności założenia.
var squads: Array[Squad] = []
## Zlecenia w kolejności złożenia; pierwsze zlecenie każdego budynku jest w szkoleniu.
var orders: Array[Order] = []
## Budynek i oddział z ostatniego udanego zlecenia.
var last_building := 0
var last_squad := 0
var _next_squad := 1


## Zakłada oddział z `count` wyszkolonymi jednostkami i zwraca jego id.
func add_squad(unit: int, count: int = 0) -> int:
	var s := Squad.new()
	s.id = _next_squad
	_next_squad += 1
	s.unit = unit
	s.count = clampi(count, 0, RecruitmentConfig.SQUAD_SIZE)
	squads.append(s)
	return s.id


func squad(id: int) -> Squad:
	for s in squads:
		if s.id == id:
			return s
	return null


## Oddziały jednego rodzaju w kolejności założenia.
func squads_of(unit: int) -> Array[Squad]:
	var out: Array[Squad] = []
	for s in squads:
		if s.unit == unit:
			out.append(s)
	return out


## Ile jednostek czeka albo szkoli się do oddziału `id`.
func pending_for(id: int) -> int:
	var n := 0
	for o in orders:
		if o.squad_id == id:
			n += 1
	return n


## Wolne miejsca w oddziale (z jednostkami w szkoleniu).
func free_in_squad(id: int) -> int:
	var s := squad(id)
	if s == null:
		return 0
	return maxi(0, RecruitmentConfig.SQUAD_SIZE - s.count - pending_for(id))


## Pierwszy oddział rodzaju `unit` z wolnym miejscem albo NEW_SQUAD.
func default_squad(unit: int) -> int:
	for s in squads_of(unit):
		if free_in_squad(s.id) > 0:
			return s.id
	return NEW_SQUAD


## Wyszkolone oddziały jako lista [rodzaj, liczba] dla Battle.create_squads (#15), w kolejności
## tworzenia; puste oddziały pomija.
func battle_squads() -> Array:
	var out: Array = []
	for s in squads:
		if s.count > 0:
			out.append([s.unit, s.count])
	return out


## Wyszkolone jednostki rodzaju `unit` we wszystkich oddziałach.
func army_of(unit: int) -> int:
	var n := 0
	for s in squads_of(unit):
		n += s.count
	return n


func army_size() -> int:
	var n := 0
	for s in squads:
		n += s.count
	return n


## Globalny limit armii, czyli ile zamek może teraz utrzymać: Dwór i Koszary (#81, #89).
static func army_limit(grid: BuildGrid) -> int:
	var limit := RecruitmentConfig.ARMY_PER_MANOR_LEVEL * grid.manor_level()
	for id: int in grid.buildings:
		if grid.kinds[id] == BuildingTypes.Kind.BARRACKS:
			limit += RecruitmentConfig.ARMY_PER_BARRACKS_LEVEL * grid.levels[id]
	return limit


## Wolne miejsca w armii (z jednostkami w szkoleniu).
func free_army(grid: BuildGrid) -> int:
	return maxi(0, army_limit(grid) - army_size() - orders.size())


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
	if UnitTypes.ERA_I_ONLY.has(unit) and age > 0:
		return Result.ERA_PASSED
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


## Szkoli jednostkę `unit` w budynku `building_id` do oddziału `squad_id` (NEW_SQUAD = nowy).
## Koszt schodzi od razu; nowy oddział powstaje przy zleceniu, żeby kolejne jednostki mogły
## do niego trafić jeszcze w trakcie szkolenia.
func start(unit: int, building_id: int, squad_id: int, grid: BuildGrid, economy: Economy, goods: Goods,
		research: Research, age: int, now_ms: int) -> Result:
	var checked := check(unit, building_id, squad_id, grid, economy, goods, research, age)
	if checked != Result.OK:
		return checked
	var res_cost := _resource_array(unit)
	var goods_cost := UnitTypes.goods_cost(unit)
	# koszt pobierany razem albo wcale: najpierw towary, a gdy surowce jednak nie wystarczą, towary wracają
	if not goods.take(goods_cost):
		return Result.NO_GOODS
	if not economy.spend(res_cost):
		for good: int in goods_cost:
			goods.amounts[good] += int(goods_cost[good])
		return Result.NO_RESOURCES
	if squad_id == NEW_SQUAD:
		squad_id = add_squad(unit)
	var level := grid.levels[building_id]
	var o := Order.new()
	o.unit = unit
	o.building_id = building_id
	o.squad_id = squad_id
	o.duration_ms = RecruitmentConfig.train_ms(unit, level)
	o.start_ms = now_ms if queue_of(building_id).is_empty() else -1
	orders.append(o)
	last_building = building_id
	last_squad = squad_id
	return Result.OK


## Czy szkolenie przejdzie, bez zmiany stanu: te same warunki co start() (przycisk Szkol, #147).
func check(unit: int, building_id: int, squad_id: int, grid: BuildGrid, economy: Economy, goods: Goods,
		research: Research, age: int) -> Result:
	var available := availability(unit, grid, research, age)
	if available != Result.OK:
		return available
	if not buildings_for(unit, grid).has(building_id):
		return Result.NO_BUILDING
	if squad_id != NEW_SQUAD:
		var s := squad(squad_id)
		if s == null or s.unit != unit:
			return Result.WRONG_SQUAD
		if free_in_squad(squad_id) <= 0:
			return Result.SQUAD_FULL
	var level := grid.levels[building_id]
	if queue_of(building_id).size() >= RecruitmentConfig.training_slots(level):
		return Result.QUEUE_FULL
	if free_army(grid) <= 0:
		return Result.ARMY_FULL
	var res_cost := _resource_array(unit)
	if not economy.can_afford(res_cost):
		return Result.NO_RESOURCES
	if not missing_goods(unit, goods).is_empty():
		return Result.NO_GOODS
	return Result.OK


## Szkolenie z globalnego ekranu: budynek danego rodzaju z najkrótszą kolejką (przy remisie
## najniższe id, więc wybór jest powtarzalny).
func start_any(unit: int, squad_id: int, grid: BuildGrid, economy: Economy, goods: Goods, research: Research,
		age: int, now_ms: int) -> Result:
	var available := availability(unit, grid, research, age)
	if available != Result.OK:
		return available
	var best := free_building(unit, grid)
	if best == 0:
		return Result.QUEUE_FULL
	return start(unit, best, squad_id, grid, economy, goods, research, age, now_ms)


## check() dla globalnego ekranu: budynek wybiera się jak w start_any().
func check_any(unit: int, squad_id: int, grid: BuildGrid, economy: Economy, goods: Goods, research: Research,
		age: int) -> Result:
	var available := availability(unit, grid, research, age)
	if available != Result.OK:
		return available
	var best := free_building(unit, grid)
	if best == 0:
		return Result.QUEUE_FULL
	return check(unit, best, squad_id, grid, economy, goods, research, age)


## Budynek dla `unit` z wolnym miejscem i najkrótszą kolejką (przy remisie najniższe id) albo 0.
func free_building(unit: int, grid: BuildGrid) -> int:
	var best := 0
	var best_len := 1 << 30
	for id in buildings_for(unit, grid):
		var n := queue_of(id).size()
		if n < RecruitmentConfig.training_slots(grid.levels[id]) and n < best_len:
			best = id
			best_len = n
	return best


## Kończy szkolenia, których czas minął; w każdym budynku następne zaczyna się w chwili końca
## poprzedniego. Jednostka trafia do swojego oddziału. Zwraca rodzaje wyszkolonych jednostek.
func update(now_ms: int) -> Array[int]:
	var done: Array[int] = []
	while true:
		var earliest: Order = null
		for o in orders:
			if o.start_ms >= 0 and o.finish_ms() <= now_ms and (earliest == null or o.finish_ms() < earliest.finish_ms()):
				earliest = o
		if earliest == null:
			break
		orders.erase(earliest)
		var s := squad(earliest.squad_id)
		if s == null:
			s = squad(add_squad(earliest.unit))
		s.count += 1
		done.append(earliest.unit)
		var rest := queue_of(earliest.building_id)
		if not rest.is_empty():
			rest[0].start_ms = earliest.finish_ms()
	return done


## Usuwa zlecenia budynku, którego już nie ma (rozbiórka). Koszt nie wraca, jak przy rozbiórce
## budynku; puste oddziały bez szkolonych jednostek znikają.
func drop_building(building_id: int) -> void:
	for o in queue_of(building_id):
		orders.erase(o)
	_drop_empty_squads()


func _drop_empty_squads() -> void:
	for s in squads.duplicate():
		if s.count == 0 and pending_for(s.id) == 0:
			squads.erase(s)


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
		list.append({"unit": o.unit, "building_id": o.building_id, "squad_id": o.squad_id,
				"duration_ms": o.duration_ms, "start_ms": o.start_ms})
	var squad_list: Array = []
	for s in squads:
		squad_list.append([s.id, s.unit, s.count])
	return {"squads": squad_list, "next_squad": _next_squad, "orders": list}


## Wczytuje stan z save_data(). Złe oddziały i zlecenia budynków, których nie ma w siatce,
## są pomijane; zwraca liczbę pominiętych wpisów.
func load_data(d: Dictionary, grid: BuildGrid, now_ms: int) -> int:
	var skipped := 0
	squads.clear()
	orders.clear()
	_next_squad = 1
	for entry: Variant in d.get("squads", []) as Array:
		var e := entry as Array
		if e == null or e.size() < 3 or int(e[1]) < 0 or int(e[1]) >= UnitTypes.count() or squad(int(e[0])) != null \
				or int(e[0]) <= 0:
			skipped += 1
			continue
		var s := Squad.new()
		s.id = int(e[0])
		s.unit = int(e[1])
		s.count = clampi(int(e[2]), 0, RecruitmentConfig.SQUAD_SIZE)
		squads.append(s)
		_next_squad = maxi(_next_squad, s.id + 1)
	_next_squad = maxi(_next_squad, int(d.get("next_squad", 1)))
	for entry: Variant in d.get("orders", []) as Array:
		var e := entry as Dictionary
		var unit := int(e.get("unit", -1)) if e != null else -1
		var id := int(e.get("building_id", 0)) if e != null else 0
		var target := squad(int(e.get("squad_id", 0))) if e != null else null
		if unit < 0 or unit >= UnitTypes.count() or not grid.buildings.has(id) or target == null or target.unit != unit:
			skipped += 1
			continue
		var o := Order.new()
		o.unit = unit
		o.building_id = id
		o.squad_id = target.id
		o.duration_ms = maxi(0, int(e.get("duration_ms", 0)))
		var first := queue_of(id).is_empty()
		o.start_ms = int(e.get("start_ms", now_ms)) if first else -1
		if first and o.start_ms < 0:
			o.start_ms = now_ms
		orders.append(o)
	_drop_empty_squads()
	return skipped


func _resource_array(unit: int) -> Array[int]:
	var out: Array[int] = []
	for res in EconomyConfig.count():
		out.append(int(UnitTypes.resource_cost(unit).get(res, 0)))
	return out
