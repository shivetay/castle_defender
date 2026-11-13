class_name BuildQueue
extends RefCounted
## Kolejka budowy: jeden budowniczy pracuje nad pierwszym zleceniem, a do MAX_WAITING czeka.
## Koszt pobiera się przy zleceniu, a anulowanie oddaje go w całości. Nowy budynek od razu
## zajmuje kratki jako plac budowy (poziom 0). Zlecenia kończą się kolejno w czasie zegarowym,
## więc budowa idzie dalej, gdy gra jest w tle, a po powrocie nadrabia wszystko po kolei.
## Ekonomia liczy się odcinkami: ukończona chata produkuje więcej dopiero od chwili ukończenia.

enum Result { OK, QUEUE_FULL, NO_RESOURCES, MAX_LEVEL, NEEDS_MANOR, ALREADY_QUEUED, NO_PLACE, NOT_FOUND }

## Komunikaty dla gracza (indeks = Result).
const MESSAGES: Array[String] = ["", "Kolejka budowy pełna", "Brak surowców", "Najwyższy poziom",
		"Najpierw ulepsz Dwór", "Ten budynek już czeka w kolejce", "Tu nie można budować", "Brak budynku"]


class Order:
	extends RefCounted
	var building_id := 0
	var kind := 0
	## Poziom po ukończeniu (1 = postawienie nowego budynku).
	var level := 1
	var cost: Array[int] = []
	var duration_ms := 0
	## Początek pracy (unix, ms) albo -1, gdy zlecenie czeka.
	var start_ms := -1

	func finish_ms() -> int:
		return start_ms + duration_ms


## Zlecenia w kolejności wykonania. Pierwsze jest w budowie.
var orders: Array[Order] = []
## Id budynku postawionego przez ostatnie udane order_build().
var placed_id := 0


func is_full() -> bool:
	return orders.size() >= BuildConfig.BUILDERS + BuildConfig.MAX_WAITING


func order_for(building_id: int) -> Order:
	for o in orders:
		if o.building_id == building_id:
			return o
	return null


func has_order(building_id: int) -> bool:
	return order_for(building_id) != null


## Zleca postawienie budynku `kind` na kratce `c`: pobiera koszt i stawia plac budowy.
func order_build(grid: BuildGrid, economy: Economy, c: Vector2i, kind: int, now_ms: int) -> Result:
	placed_id = 0
	if is_full():
		return Result.QUEUE_FULL
	if grid.placement_for(c, kind) == Rect2i():
		return Result.NO_PLACE
	var cost := BuildConfig.cost(kind, 1)
	if not economy.spend(cost):
		return Result.NO_RESOURCES
	placed_id = grid.place_kind(c, kind, 0)
	if placed_id == 0:
		# bezpiecznik: placement_for i place_kind powinny się zgadzać, ale koszt nie może przepaść
		for res in cost.size():
			economy.add(res, cost[res])
		return Result.NO_PLACE
	_append(placed_id, kind, 1, cost, now_ms)
	return Result.OK


## Zleca ulepszenie budynku o 1 poziom. Budynek nie może przerosnąć Dworu.
func order_upgrade(grid: BuildGrid, economy: Economy, building_id: int, now_ms: int) -> Result:
	if not grid.buildings.has(building_id):
		return Result.NOT_FOUND
	if has_order(building_id):
		return Result.ALREADY_QUEUED
	var kind := grid.kinds[building_id]
	var level := grid.levels[building_id] + 1
	if level > BuildingTypes.MAX_LEVEL:
		return Result.MAX_LEVEL
	if level > BuildConfig.max_level(kind, grid.manor_level()):
		return Result.NEEDS_MANOR
	if is_full():
		return Result.QUEUE_FULL
	var cost := BuildConfig.cost(kind, level)
	if not economy.spend(cost):
		return Result.NO_RESOURCES
	_append(building_id, kind, level, cost, now_ms)
	return Result.OK


func _append(building_id: int, kind: int, level: int, cost: Array[int], now_ms: int) -> void:
	var o := Order.new()
	o.building_id = building_id
	o.kind = kind
	o.level = level
	o.cost = cost
	o.duration_ms = BuildConfig.time_ms(kind, level)
	if orders.is_empty():
		o.start_ms = now_ms
	orders.append(o)


## Anuluje zlecenie budynku i oddaje cały koszt (do pojemności magazynu, której nic nie
## przekracza). Plac budowy nowego budynku znika.
## Gdy anulowano zlecenie w budowie, budowniczy od razu bierze następne.
func cancel(grid: BuildGrid, economy: Economy, building_id: int, now_ms: int) -> bool:
	var o := order_for(building_id)
	if o == null:
		return false
	var was_active := orders[0] == o
	orders.erase(o)
	for res in o.cost.size():
		economy.add(res, o.cost[res])
	if o.level == 1 and grid.levels.get(building_id, -1) == 0:
		grid.remove(building_id)
	if was_active and not orders.is_empty():
		orders[0].start_ms = now_ms
	return true


## Kończy wszystkie zlecenia, których czas minął do `now_ms`, po kolei: następne zaczyna się
## w chwili ukończenia poprzedniego. Przed każdym ukończeniem ekonomia nalicza produkcję
## po starych stawkach. Zwraca ukończone zlecenia.
func update(now_ms: int, grid: BuildGrid, economy: Economy) -> Array[Order]:
	var done: Array[Order] = []
	while not orders.is_empty() and orders[0].finish_ms() <= now_ms:
		var o: Order = orders.pop_front()
		var finish := o.finish_ms()
		if finish > economy.last_update_ms:
			economy.update(finish, Economy.rates(grid))
		if grid.buildings.has(o.building_id):
			grid.levels[o.building_id] = o.level
		if not orders.is_empty():
			orders[0].start_ms = finish
		done.append(o)
	economy.update(now_ms, Economy.rates(grid))
	return done


## Ile zostało do końca zlecenia budynku (ms). Dla czekającego zlecenia: cały jego czas
## plus czas zleceń przed nim. -1, gdy budynek nie ma zlecenia.
func remaining_ms(building_id: int, now_ms: int) -> int:
	var t := now_ms
	for i in orders.size():
		var o := orders[i]
		t = maxi(o.finish_ms(), now_ms) if i == 0 else t + o.duration_ms
		if o.building_id == building_id:
			return t - now_ms
	return -1


## Co pokazać o ulepszeniu budynku: stan zlecenia, najwyższy poziom, brak poziomu Dworu
## albo koszt i czas następnego poziomu.
func upgrade_hint(grid: BuildGrid, building_id: int) -> String:
	var kind := grid.kinds[building_id]
	var next := grid.levels[building_id] + 1
	if has_order(building_id):
		return "W kolejce: poziom %d" % order_for(building_id).level
	if next > BuildingTypes.MAX_LEVEL:
		return MESSAGES[Result.MAX_LEVEL]
	if next > BuildConfig.max_level(kind, grid.manor_level()):
		return "Poziom %d wymaga Dworu na poziomie %d" % [next, next]
	return "Ulepszenie: %s, %s" % [Hud.cost_text(BuildConfig.cost(kind, next)),
			Hud.format_time(BuildConfig.time_ms(kind, next))]


## Postęp zlecenia w budowie, 0..1000 (‰). 0 dla czekających i budynków bez zlecenia.
func progress_permille(building_id: int, now_ms: int) -> int:
	if orders.is_empty() or orders[0].building_id != building_id:
		return 0
	var o := orders[0]
	if o.duration_ms <= 0:
		return 1000
	@warning_ignore("integer_division")
	return clampi((now_ms - o.start_ms) * 1000 / o.duration_ms, 0, 1000)
