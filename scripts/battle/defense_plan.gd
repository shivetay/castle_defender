class_name DefensePlan
extends RefCounted
## Ustawienia obrony (#19, #20, notatki Koncept gry, Interfejs oraz Manewry i zadania): układ, którym
## zamek broni się sam, gdy gracz jest offline. Jak w planie ataku każdy oddział załogi z rekrutacji
## (#89) może dostać zadanie z listy predefiniowanej, z parametrami ustawianymi na mapie:
## - Obrona odcinka: oddział stoi na swoim miejscu (kratka trawy albo kratka przy wskazanym odcinku
##   wału, palisady, bramy czy wieży) i bije wrogów, którzy podejdą na HOLD_RADIUS kratek, ale dalej
##   ich nie ściga;
## - Patrol: oddział krąży między 2–3 punktami, bije wroga w zasięgu wzroku i wraca na trasę.
## Oddział bez zadania stoi jak dotąd przy donżonie (#120). Priorytet celów wież to jedno ustawienie
## na cały zamek. Stanowiska na murach, Wypad konnicy i Gaszenie pożarów dojdą w kolejnych krokach #20
## (plan zatwierdzony przez właściciela), pułapki w #100, a komendant z generałami w #31.
##
## Zadania są przypisane do id oddziału z rekrutacji (nie do jego miejsca w armii), więc nowy oddział
## nie przejmuje cudzego zadania. Układ to same liczby całkowite, więc ten sam układ i ten sam seed
## dają ten sam przebieg bitwy (powtórka, weryfikacja PvP).

enum Task { HOLD, PATROL }
## Priorytet celów wież: najbliższy atakujący (jak dotąd), Taran, strzelcy, konnica. Wieża bierze
## najbliższego atakującego z wybranej grupy w swoim zasięgu, a gdy takiego nie ma, najbliższego.
enum TowerPriority { NEAREST, RAM, RANGED, CAVALRY }

const TASK_NAMES: Array[String] = ["Obrona odcinka", "Patrol"]
const TOWER_PRIORITY_NAMES: Array[String] = ["najbliższy", "taran", "strzelcy", "konnica"]
const NO_POST := Vector2i(-1, -1)
## Posterunek stoi najwyżej tyle kratek (w pionie i poziomie) od środka donżonu: obrona skupia się
## na donżonie (#19), a strefa przy krawędzi mapy zostaje dla atakującego. TYMCZASOWE.
const RADIUS := 10
## Patrol: najwięcej punktów trasy poza miejscem startu (razem 2–3 punkty).
const MAX_ROUTE := 2


class Order:
	extends RefCounted
	var task := 0
	## Miejsce oddziału: kratka obrony odcinka albo pierwszy punkt patrolu (tam oddział staje na start).
	var post := Vector2i(-1, -1)
	## Kolejne punkty patrolu (0–MAX_ROUTE); przy Obronie odcinka puste.
	var route: Array[Vector2i] = []

	## Punkty trasy patrolu w kolejności obchodu, od miejsca startu.
	func patrol_points() -> Array[Vector2i]:
		var out: Array[Vector2i] = [post]
		out.append_array(route)
		return out


## Id oddziału z rekrutacji → zadanie.
var orders: Dictionary[int, Order] = {}
var tower_priority := 0


func order_for(squad_id: int) -> Order:
	return orders.get(squad_id, null) as Order


## Zadanie oddziału `squad_id` (zakłada nowe albo zmienia istniejące) i je zwraca. Zmiana zadania
## zostawia miejsce, a czyści trasę patrolu.
func set_task(squad_id: int, task: int) -> Order:
	var o := order_for(squad_id)
	if o == null:
		o = Order.new()
		orders[squad_id] = o
	if o.task != task:
		o.route.clear()
	o.task = task
	return o


func post_for(squad_id: int) -> Vector2i:
	var o := order_for(squad_id)
	return o.post if o != null else NO_POST


## Obrona odcinka na kratce `cell` (zostawia zadanie Patrol, jeśli już było, i zaczyna jego trasę od nowa).
func set_post(squad_id: int, cell: Vector2i) -> void:
	var o := order_for(squad_id)
	if o == null:
		o = set_task(squad_id, Task.HOLD)
	o.post = cell
	o.route.clear()


## Zdejmuje zadanie: oddział wraca pod donżon.
func clear_post(squad_id: int) -> void:
	orders.erase(squad_id)


## Oddział, którego miejsce albo punkt patrolu stoi na kratce `cell`, albo 0 (przy remisie najniższe id).
func squad_at(cell: Vector2i) -> int:
	var best := 0
	for id: int in orders:
		var o := orders[id]
		if (o.post == cell or o.route.has(cell)) and (best == 0 or id < best):
			best = id
	return best


## Usuwa zadania oddziałów, których nie ma już w armii (rozwiązane po stratach, #164).
func prune(recruitment: Recruitment) -> void:
	for id: int in orders.keys():
		if recruitment.squad(id) == null:
			orders.erase(id)


## Zadania oddziałów bitwy w kolejności `ids` (Recruitment.battle_ids()); null dla oddziału bez
## zadania albo bez miejsca. Patrol bez punktów trasy (sam start) to jeszcze nie pętla, więc idzie
## do bitwy jako Obrona odcinka na swoim miejscu (review #181). Lista idzie do Battle.create_squads
## (kopie: bitwa nie zmienia układu).
func battle_orders(ids: Array[int]) -> Array[Order]:
	var out: Array[Order] = []
	for id in ids:
		var o := order_for(id)
		if o == null or o.post == NO_POST:
			out.append(null)
			continue
		var c := Order.new()
		c.task = Task.HOLD if o.task == Task.PATROL and o.route.is_empty() else o.task
		c.post = o.post
		c.route = o.route.duplicate()
		out.append(c)
	return out


## Miejsca oddziałów bitwy (NO_POST bez zadania), w kolejności `ids`.
func battle_posts(ids: Array[int]) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for id in ids:
		out.append(post_for(id))
	return out


## Zadania z samych miejsc: Obrona odcinka na każdej kratce, NO_POST to brak zadania (testy, podgląd).
static func hold_orders(posts: Array[Vector2i]) -> Array[Order]:
	var out: Array[Order] = []
	for p in posts:
		if p == NO_POST:
			out.append(null)
			continue
		var o := Order.new()
		o.post = p
		out.append(o)
	return out


## Środek donżonu (kratka), wokół którego liczy się strefa obrony; NO_POST bez donżonu.
static func keep_center(grid: BuildGrid) -> Vector2i:
	var keep := grid.keep_id()
	if keep == 0:
		return NO_POST
	return grid.buildings[keep].get_center()


## Strefa obrony: kratki, na których może stać posterunek (przycięta do mapy).
static func zone(grid: BuildGrid) -> Rect2i:
	var c := keep_center(grid)
	if c == NO_POST:
		return Rect2i()
	var r := Rect2i(c - Vector2i.ONE * RADIUS, Vector2i.ONE * (2 * RADIUS + 1))
	return r.intersection(Rect2i(0, 0, grid.terrain.size, grid.terrain.size))


## Pusty napis, gdy na kratce `cell` może stać posterunek; inaczej powód po polsku (pasek komunikatu).
static func post_problem(grid: BuildGrid, cell: Vector2i) -> String:
	if not grid.terrain.in_bounds(cell):
		return "Poza mapą"
	if not zone(grid).has_point(cell):
		return "Za daleko od donżonu: najwyżej %d kratek" % RADIUS
	if grid.terrain.get_tile(cell) == TerrainMap.Tile.WATER:
		return "Załoga nie stanie w wodzie"
	var id := grid.building_at(cell)
	if id != 0:
		return "Tu stoi %s" % BuildingTypes.NAMES[grid.kinds[id]]
	return ""


## Czy budynek rodzaju `kind` to odcinek obrony (wał, palisada, brama, wieża).
static func is_section(kind: int) -> bool:
	return BuildingTypes.is_wall(kind) or kind == BuildingTypes.Kind.GATE or kind == BuildingTypes.Kind.TOWER


## Kratka obrony odcinka `id`: wolna kratka strefy stykająca się z budynkiem bokiem (nie po skosie),
## najbliżej donżonu (od środka zamku), przy remisie pierwsza w kolejności wierszy. NO_POST, gdy
## takiej nie ma.
static func section_post(grid: BuildGrid, id: int) -> Vector2i:
	var r := grid.buildings[id]
	var c := keep_center(grid)
	var best := NO_POST
	var best_d := -1
	var g := r.grow(1)
	for y in range(g.position.y, g.end.y):
		for x in range(g.position.x, g.end.x):
			var p := Vector2i(x, y)
			var beside := (x >= r.position.x and x < r.end.x) or (y >= r.position.y and y < r.end.y)
			if r.has_point(p) or not beside or not post_problem(grid, p).is_empty():
				continue
			var d := (p - c).length_squared()
			if best_d < 0 or d < best_d:
				best = p
				best_d = d
	return best


func to_dict() -> Dictionary:
	var ids: Array[int] = []
	for id: int in orders:
		ids.append(id)
	ids.sort()
	var list: Array = []
	for id in ids:
		var o := orders[id]
		var route: Array = []
		for p in o.route:
			route.append([p.x, p.y])
		list.append([id, o.task, o.post.x, o.post.y, route])
	return {"orders": list, "tower_priority": tower_priority}


## Układ z danych zapisu (JSON daje liczby jako float, więc wszystko idzie przez int()). Złe wpisy
## są pomijane.
static func from_dict(d: Dictionary) -> DefensePlan:
	var p := DefensePlan.new()
	p.tower_priority = clampi(int(d.get("tower_priority", 0)), 0, TOWER_PRIORITY_NAMES.size() - 1)
	for e: Variant in d.get("orders", []) as Array:
		if not e is Array:
			continue
		var a := e as Array
		if a.size() < 4 or int(a[0]) <= 0 or int(a[1]) < 0 or int(a[1]) >= TASK_NAMES.size():
			continue
		var o := p.set_task(int(a[0]), int(a[1]))
		o.post = Vector2i(int(a[2]), int(a[3]))
		if o.task == Task.PATROL and a.size() > 4 and a[4] is Array:
			for w: Variant in a[4] as Array:
				if w is Array and (w as Array).size() >= 2 and o.route.size() < MAX_ROUTE:
					o.route.append(Vector2i(int((w as Array)[0]), int((w as Array)[1])))
	return p


## Wersja 7 zapisu (#19): same posterunki [id, x, y] → Obrona odcinka.
static func from_v7(d: Dictionary) -> Dictionary:
	var list: Array = []
	for e: Variant in d.get("posts", []) as Array:
		if e is Array and (e as Array).size() >= 3:
			var a := e as Array
			list.append([a[0], Task.HOLD, a[1], a[2], []])
	return {"orders": list, "tower_priority": TowerPriority.NEAREST}
