class_name BuildQueue
extends RefCounted
## Kolejka budowy: jeden budowniczy pracuje nad pierwszym zleceniem, a do MAX_WAITING czeka.
## Koszt pobiera się przy zleceniu, a anulowanie oddaje go w całości. Nowy budynek od razu
## zajmuje kratki jako plac budowy (poziom 0). Zlecenia kończą się kolejno w czasie zegarowym,
## więc budowa idzie dalej, gdy gra jest w tle, a po powrocie nadrabia wszystko po kolei.
## Ekonomia liczy się odcinkami: ukończona chata produkuje więcej dopiero od chwili ukończenia.

enum Result { OK, QUEUE_FULL, NO_RESOURCES, MAX_LEVEL, NEEDS_MANOR, ALREADY_QUEUED, NO_PLACE, NOT_FOUND, NEEDS_TECH }

## Komunikaty dla gracza (indeks = Result).
const MESSAGES: Array[String] = ["", "Kolejka budowy pełna", "Brak surowców", "Najwyższy poziom",
		"Najpierw ulepsz Dwór", "Ten budynek już czeka w kolejce", "Tu nie można budować", "Brak budynku",
		"Najpierw zbadaj technologię"]


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
## Budynek z wymaganą technologią (BuildConfig.REQUIRED_TECH) wymaga jej zbadania w `research`.
func order_build(grid: BuildGrid, economy: Economy, c: Vector2i, kind: int, now_ms: int,
		research: Research = null) -> Result:
	placed_id = 0
	if not BuildConfig.is_unlocked(kind, research):
		return Result.NEEDS_TECH
	if is_full():
		return Result.QUEUE_FULL
	# gracz stawia: budynek przykleja się do pobliskiej linii umocnień (#149)
	var rect := grid.placement_for(c, kind, true)
	if rect == Rect2i():
		return Result.NO_PLACE
	# brama w linii umocnień: odcinki w budowie zostają (najpierw trzeba je skończyć albo anulować)
	for wall in grid.walls_under(rect):
		if has_order(wall):
			return Result.NO_PLACE
	var cost := BuildConfig.cost(kind, 1)
	if not economy.spend(cost):
		return Result.NO_RESOURCES
	placed_id = grid.place_kind(c, kind, 0, true)
	if placed_id == 0:
		# bezpiecznik: placement_for i place_kind powinny się zgadzać, ale koszt nie może przepaść
		for res in cost.size():
			economy.add(res, cost[res])
		return Result.NO_PLACE
	_append(placed_id, kind, 1, cost, now_ms)
	return Result.OK


## Zleca ulepszenie budynku o 1 poziom. Budynek nie może przerosnąć Dworu. Przebudowa Dworu
## na nową epokę (#34) wymaga technologii kluczowych zbadanych w `research`.
func order_upgrade(grid: BuildGrid, economy: Economy, building_id: int, now_ms: int,
		research: Research = null) -> Result:
	if not grid.buildings.has(building_id):
		return Result.NOT_FOUND
	if has_order(building_id):
		return Result.ALREADY_QUEUED
	var kind := grid.kinds[building_id]
	var level := grid.levels[building_id] + 1
	if level > BuildConfig.max_level(kind, Ages.MAX_TOTAL_LEVEL):
		return Result.MAX_LEVEL
	if level > BuildConfig.max_level(kind, grid.manor_level()):
		return Result.NEEDS_MANOR
	if not missing_techs(kind, level, research).is_empty():
		return Result.NEEDS_TECH
	if is_full():
		return Result.QUEUE_FULL
	var cost := BuildConfig.cost(kind, level)
	if not economy.spend(cost):
		return Result.NO_RESOURCES
	_append(building_id, kind, level, cost, now_ms)
	return Result.OK


## Technologie z BuildConfig.level_techs, których brakuje do poziomu `level`.
static func missing_techs(kind: int, level: int, research: Research) -> Array[String]:
	var out: Array[String] = []
	for code in BuildConfig.level_techs(kind, level):
		if research == null or not research.is_done(code):
			out.append(code)
	return out


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
## w chwili ukończenia poprzedniego. Badanie (`research`) kończy się w tym samym porządku czasu.
## Przed każdym ukończeniem ekonomia nalicza produkcję po starych stawkach, więc nowy budynek
## albo premia z technologii liczą się dokładnie od chwili ukończenia. Zwraca ukończone zlecenia.
## Towary (`goods`) liczą się w tych samych punktach czasu co surowce: wytwórca ukończony w trakcie
## nieobecności produkuje dopiero od chwili ukończenia (review PR 140). `upkeep` to utrzymanie armii
## w Ży/h (#214, Recruitment.army_upkeep), odejmowane od produkcji żywności. `ruins`: budynki
## w odbudowie po ataku PvP (#99); produkcja liczy się osobno przed i po każdym początku i końcu
## odbudowy, więc ruina odbudowana podczas nieobecności produkuje pełną stawką od tej chwili.
func update(now_ms: int, grid: BuildGrid, economy: Economy, research: Research = null,
		goods: Goods = null, upkeep: int = 0, ruins: Ruins = null) -> Array[Order]:
	var done: Array[Order] = []
	# pojemność z Magazynów (także po rozbiórce albo odczycie), zanim cokolwiek się naliczy
	economy.refresh_capacity(grid)
	while true:
		var build_at := orders[0].finish_ms() if not orders.is_empty() else -1
		var research_at := research.finish_ms() if research != null else -1
		var build_due := build_at >= 0 and build_at <= now_ms
		var research_due := research_at >= 0 and research_at <= now_ms
		if not build_due and not research_due:
			break
		# przy równym czasie najpierw budowa, w następnym obrocie badanie
		var take_research := research_due and (not build_due or research_at < build_at)
		var at := research_at if take_research else build_at
		if at > economy.last_update_ms:
			_economy_to(at, grid, economy, research, upkeep, ruins)
		if goods != null and at > goods.last_update_ms:
			goods.update(at, Goods.producers(grid), economy)
		if take_research:
			research.update(at)
			continue
		var o: Order = orders.pop_front()
		if grid.buildings.has(o.building_id):
			grid.levels[o.building_id] = o.level
			# ukończony wał/palisada/brama/wieża domyka krótkie luki do bramy i wieży
			if o.level >= 1:
				grid.seal_after_place(o.building_id)
			# ukończony Magazyn mieści więcej od chwili ukończenia
			economy.refresh_capacity(grid)
		if not orders.is_empty():
			orders[0].start_ms = at
		done.append(o)
	_economy_to(now_ms, grid, economy, research, upkeep, ruins)
	if goods != null:
		goods.update(now_ms, Goods.producers(grid), economy)
	return done


## Nalicza produkcję do `at_ms`, dzieląc czas w chwilach, w których zmienia się zbiór ruin (#99).
static func _economy_to(at_ms: int, grid: BuildGrid, economy: Economy, research: Research, upkeep: int,
		ruins: Ruins) -> void:
	if ruins == null:
		grid.ruined = {}
		economy.update(at_ms, Economy.net_rates(grid, research, upkeep))
		return
	while true:
		var change := ruins.next_change_after(economy.last_update_ms)
		grid.ruined = ruins.active_at(economy.last_update_ms)
		if change < 0 or change >= at_ms:
			break
		economy.update(change, Economy.net_rates(grid, research, upkeep))
	economy.update(at_ms, Economy.net_rates(grid, research, upkeep))
	grid.ruined = ruins.active_at(at_ms)


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


## Komunikat po dotknięciu budynku bez poziomów (Strażnica, #177).
const NO_LEVELS_HINT := "Wybierz Oblężenie albo Wyprawę"
## Komunikat po dotknięciu donżonu (#232): bez ulepszeń i rozbiórki.
const KEEP_HINT := "Donżonu nie ulepszysz ani nie rozbierzesz"


## Co pokazać o ulepszeniu budynku: stan zlecenia, najwyższy poziom, brak poziomu Dworu,
## brak technologii przejścia epoki albo koszt i czas następnego poziomu.
func upgrade_hint(grid: BuildGrid, building_id: int, research: Research = null) -> String:
	var kind := grid.kinds[building_id]
	var next := grid.levels[building_id] + 1
	if has_order(building_id):
		return "W kolejce: poziom %s" % Ages.short_level(order_for(building_id).level)
	if kind == BuildingTypes.Kind.KEEP:
		return KEEP_HINT
	if not BuildingTypes.has_levels(kind):
		return NO_LEVELS_HINT
	if next > BuildConfig.max_level(kind, Ages.MAX_TOTAL_LEVEL):
		return MESSAGES[Result.MAX_LEVEL]
	if next > BuildConfig.max_level(kind, grid.manor_level()):
		if Ages.is_age_step(next):
			return "Epoka II: najpierw przebuduj Dwór" if Ages.of_level(next) == 1 else MESSAGES[Result.NEEDS_MANOR]
		return "Poziom %s wymaga Dworu na poziomie %s" % [Ages.short_level(next), Ages.short_level(next)]
	var techs := missing_techs(kind, next, research)
	if not techs.is_empty():
		return "%s wymaga technologii %s" % [Ages.age_name(Ages.of_level(next)), ", ".join(techs)]
	var title := Ages.age_name(Ages.of_level(next)) if Ages.is_age_step(next) else "Ulepszenie"
	return "%s: %s, %s%s" % [title, Hud.cost_text(BuildConfig.cost(kind, next)),
			Hud.format_time(BuildConfig.time_ms(kind, next)), capacity_gain_text(kind, next)]


## Dopisek do ulepszenia Magazynu: ile więcej zmieści poziom `level` (np. „, +250 miejsca”).
## Dla innych budynków pusty, żeby gracz widział, po co ulepszać Magazyn (review PR 238).
static func capacity_gain_text(kind: int, level: int) -> String:
	var gain := EconomyConfig.warehouse_gain(level)
	# poziomy epoki II (#34) nie dokładają jeszcze miejsca (balans w #262), więc bez „+0 miejsca”
	if kind != BuildingTypes.Kind.WAREHOUSE or gain <= 0:
		return ""
	return ", +%d miejsca" % gain


## Postęp zlecenia w budowie, 0..1000 (‰). 0 dla czekających i budynków bez zlecenia.
func progress_permille(building_id: int, now_ms: int) -> int:
	if orders.is_empty() or orders[0].building_id != building_id:
		return 0
	var o := orders[0]
	if o.duration_ms <= 0:
		return 1000
	@warning_ignore("integer_division")
	return clampi((now_ms - o.start_ms) * 1000 / o.duration_ms, 0, 1000)


## Stan do zapisu: zlecenia w kolejności, każde z kosztem, czasem i początkiem pracy, tak jak
## zostały zlecone (późniejsza zmiana BuildConfig nie zmienia obiecanych zleceń).
func save_data() -> Dictionary:
	var list: Array = []
	for o in orders:
		list.append({"building_id": o.building_id, "kind": o.kind, "level": o.level, "cost": o.cost.duplicate(),
				"duration_ms": o.duration_ms, "start_ms": o.start_ms})
	return {"orders": list}


## Wczytuje zlecenia z save_data(). Zlecenie budynku, którego nie ma w siatce, jest pomijane.
## Pierwsze zlecenie zawsze ma początek pracy, a kolejne czekają. Zwraca liczbę pominiętych.
func load_data(d: Dictionary, grid: BuildGrid, now_ms: int) -> int:
	orders.clear()
	var skipped := 0
	for entry: Variant in d.get("orders", []) as Array:
		var e := entry as Dictionary
		if e == null or not grid.buildings.has(int(e.get("building_id", 0))) or is_full():
			skipped += 1
			continue
		var o := Order.new()
		o.building_id = int(e["building_id"])
		o.kind = grid.kinds[o.building_id]
		o.level = clampi(int(e.get("level", 1)), 1, Ages.MAX_TOTAL_LEVEL)
		for amount: Variant in e.get("cost", []) as Array:
			o.cost.append(maxi(0, int(amount)))
		o.duration_ms = maxi(0, int(e.get("duration_ms", 0)))
		o.start_ms = int(e.get("start_ms", -1)) if orders.is_empty() else -1
		if orders.is_empty() and o.start_ms < 0:
			o.start_ms = now_ms
		orders.append(o)
	return skipped
