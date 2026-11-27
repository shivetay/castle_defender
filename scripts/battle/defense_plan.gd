class_name DefensePlan
extends RefCounted
## Ustawienia obrony (#19, #20, notatki Koncept gry, Interfejs oraz Manewry i zadania): układ, którym
## zamek broni się sam, gdy gracz jest offline. Jak w planie ataku każdy oddział załogi z rekrutacji
## (#89) może dostać zadanie z listy predefiniowanej, z parametrami ustawianymi na mapie:
## - Obrona odcinka: oddział stoi na swoim miejscu (kratka trawy albo kratka przy wskazanym odcinku
##   wału, palisady, bramy czy wieży) i bije wrogów, którzy podejdą na HOLD_RADIUS kratek, ale dalej
##   ich nie ściga;
##   Strzelcy mogą stać na samym wale albo palisadzie (stanowisko na murze, Battle._wall_act);
## - Patrol: oddział krąży między 2–3 punktami, bije wroga w zasięgu wzroku i wraca na trasę;
## - Wypad konnicy (od epoki II): konnica czeka za bramą, a gdy wróg dojdzie pod bramę, wychodzi
##   przez nią, bije i wraca;
## - Przed murami (konnica, od epoki I, prośba właściciela 17.11.2026): konnica stoi na wskazanej
##   kratce, także na zewnątrz murów, bije wrogów do FIELD_RADIUS kratek od niej i wraca; przez własne
##   bramy przejeżdża;
## - Przy donżonie: oddział stoi jak przed #19;
## - Gaszenie pożarów (#35, piechota lekka, gdy zamek ma Studnię): oddział czeka przy wskazanej Studni
##   i gasi płonące budynki w jej pobliżu (Battle._firefight_act);
## - Garnizon Dworu (#81): oddział stacjonuje w Dworze. W bitwie stoi przy donżonie (strzelcy na nim),
##   ma +BattleConfig.GARRISON_HP_PERCENT wytrzymałości i nie idzie do ataku (pilnuje tego też serwer
##   w begin_attack). Dwór mieści RecruitmentConfig.garrison_capacity() jednostek; oddziały ponad
##   pojemność (w kolejności armii) stoją przy donżonie bez premii.
## Oddział bez ustawionego zadania dostaje w bitwie zadanie domyślne według klasy (default_order,
## plan zatwierdzony przez właściciela): strzelcy na mur przy bramie, piechota przy bramie, konnica
## na wypad, specjalni przy donżonie. Bez bramy i murów wszyscy stoją przy donżonie. Priorytet celów
## wież to jedno ustawienie na cały zamek. Pułapki (#100, TrapConfig) stoją na kratkach strefy obrony
## i są częścią tego samego układu. Komendant obrony (#31) to generał gracza (Generals): nie stoi na
## siatce, dowodzi całą obroną; gracz wybiera go na ekranie Obrona.
##
## Zadania są przypisane do id oddziału z rekrutacji (nie do jego miejsca w armii), więc nowy oddział
## nie przejmuje cudzego zadania. Układ to same liczby całkowite, więc ten sam układ i ten sam seed
## dają ten sam przebieg bitwy (powtórka, weryfikacja PvP).

enum Task { HOLD, PATROL, SORTIE, KEEP, FIELD, FIREFIGHT, GARRISON }
## Priorytet celów wież: najbliższy atakujący (jak dotąd), Taran, strzelcy, konnica. Wieża bierze
## najbliższego atakującego z wybranej grupy w swoim zasięgu, a gdy takiego nie ma, najbliższego.
enum TowerPriority { NEAREST, RAM, RANGED, CAVALRY }

const TASK_NAMES: Array[String] = ["Obrona odcinka", "Patrol", "Wypad konnicy", "Przy donżonie", "Przed murami",
		"Gaszenie pożarów", "Garnizon Dworu"]
## Od której epoki zadanie jest dostępne (0 = I), z notatki Manewry i zadania.
const TASK_AGE: Array[int] = [0, 0, 1, 0, 0, 0, 0]
const TOWER_PRIORITY_NAMES: Array[String] = ["najbliższy", "taran", "strzelcy", "konnica"]
const NO_POST := Vector2i(-1, -1)
## Posterunek i pułapka stoją najwyżej radius() kratek (w pionie i poziomie) od środka donżonu: obrona
## skupia się na donżonie (#19), a strefa przy krawędzi mapy zostaje dla atakującego. Promień (#342,
## ADR 0007) to RADIUS przy Dworze 1, RADIUS_PER_MANOR_LEVEL za każdy kolejny poziom Dworu w epoce
## (Ages.bonus_level: w epoce II zostaje jak przy Dworze 5) i RADIUS_PER_TECH_LEVEL za każdy poziom
## technologii REACH_TECH (O25 Wysunięte straże, BuildGrid.reach_level). Liczby TYMCZASOWE.
const RADIUS := 10
const RADIUS_PER_MANOR_LEVEL := 2
const RADIUS_PER_TECH_LEVEL := 1
const REACH_TECH := "O25"
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


class Trap:
	extends RefCounted
	var kind := 0
	var cell := Vector2i.ZERO
	## Czy atakujący ją widzi: dopiero po zwiadzie (#28) albo reklamie Wywiad (#44).
	var revealed := false


## Id oddziału z rekrutacji → zadanie.
var orders: Dictionary[int, Order] = {}
## Pułapki (#100) w kolejności postawienia (ta kolejność to kolejność sprawdzania w bitwie).
var traps: Array[Trap] = []
var tower_priority := 0
## Komendant obrony (#31): rodzaj generała (Generals.Kind) albo -1.
var commander := -1


func order_for(squad_id: int) -> Order:
	return orders.get(squad_id, null) as Order


## Zadanie oddziału `squad_id` (zakłada nowe albo zmienia istniejące) i je zwraca. Zmiana zadania
## zostawia miejsce, a czyści trasę patrolu. Wyjątek: Przy donżonie czyści też miejsce, bo oddział
## nie ma wtedy własnej kratki (review #184).
func set_task(squad_id: int, task: int) -> Order:
	var o := order_for(squad_id)
	if o == null:
		o = Order.new()
		orders[squad_id] = o
	if o.task != task:
		o.route.clear()
	o.task = task
	if task == Task.KEEP or task == Task.GARRISON:
		o.post = NO_POST  # przy donżonie nie ma własnego miejsca (review #184), garnizon też (#81)
	return o


## Czy oddział `squad_id` ma zadanie Garnizon Dworu (#81).
func in_garrison(squad_id: int) -> bool:
	var o := order_for(squad_id)
	return o != null and o.task == Task.GARRISON


## Id oddziałów w garnizonie, rosnąco (do zapisu i testów).
func garrison_ids() -> Array[int]:
	var out: Array[int] = []
	for id: int in orders:
		if orders[id].task == Task.GARRISON:
			out.append(id)
	out.sort()
	return out


## Jednostki w garnizonie: wyszkolone i szkolone do oddziałów garnizonu (#81).
func garrison_units(recruitment: Recruitment) -> int:
	var n := 0
	for id in garrison_ids():
		var s := recruitment.squad(id)
		if s != null:
			n += s.count + recruitment.pending_for(id)
	return n


## Czy oddział `squad_id` zmieści się w garnizonie Dworu zamku `grid` (#81). Oddział już w garnizonie
## się mieści. Liczą się też jednostki w szkoleniu, żeby garnizon nie przerósł Dworu po szkoleniu.
func garrison_fits(squad_id: int, recruitment: Recruitment, grid: BuildGrid) -> bool:
	if in_garrison(squad_id):
		return true
	var s := recruitment.squad(squad_id)
	if s == null or grid == null:
		return false
	var need := s.count + recruitment.pending_for(squad_id)
	return garrison_units(recruitment) + need <= RecruitmentConfig.garrison_capacity(grid)


## Oddziały z `ids` (Recruitment.battle_ids()) i `squads` ([rodzaj, liczba] w tej samej kolejności),
## które w bitwie są garnizonem z premią (#81): z zadaniem Garnizon Dworu, w kolejności armii, dopóki
## suma ich jednostek mieści się w pojemności Dworu. Przycina zapis spoza gry (kopia zamku z serwera),
## więc garnizon nigdy nie jest większy niż Dwór. Bez `grid` (testy, podgląd) nikt nie ma premii.
func battle_garrison(ids: Array[int], squads: Array, grid: BuildGrid) -> Array[bool]:
	var out: Array[bool] = []
	var room := RecruitmentConfig.garrison_capacity(grid) if grid != null else 0
	for i in ids.size():
		var n := int((squads[i] as Array)[1]) if i < squads.size() else 0
		var ok := in_garrison(ids[i]) and n <= room
		if ok:
			room -= n
		out.append(ok)
	return out


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


## Zdejmuje ustawione zadanie: w bitwie oddział dostaje zadanie domyślne swojej klasy (default_order).
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


## Komendant do bitwy: generał z `generals` (kopia) albo null, gdy komendanta nie ma albo gracz go
## nie ma w swoich generałach.
func commander_general(generals: Generals) -> Generals.General:
	if commander < 0 or generals == null:
		return null
	var g := generals.get_general(commander)
	return g.duplicate_general() if g != null else null


## Kolejny komendant przy przełączaniu: brak → generałowie po kolei, bez generała ataku (`attack_kind`).
func next_commander(generals: Generals, attack_kind: int = -1) -> int:
	var options: Array[int] = [-1]
	for g in generals.roster:
		if g.kind != attack_kind:
			options.append(g.kind)
	commander = options[(options.find(commander) + 1) % options.size()]
	return commander


## Usuwa zadania oddziałów, których nie ma już w armii (rozwiązane po stratach, #164).
func prune(recruitment: Recruitment) -> void:
	for id: int in orders.keys():
		if recruitment.squad(id) == null:
			orders.erase(id)


## Zadania oddziałów bitwy w kolejności `ids` (Recruitment.battle_ids()); null to oddział przy
## donżonie, a zadanie Garnizon Dworu (bez miejsca) to garnizon z premią (battle_garrison, #81). Z `squads` (Recruitment.battle_squads(), ta sama kolejność) i `grid` oddział bez
## ustawionego zadania dostaje zadanie domyślne swojej klasy (default_order); bez nich zostaje przy
## donżonie. Patrol bez punktów trasy (sam start) to jeszcze nie pętla, więc idzie do bitwy jako
## Obrona odcinka na swoim miejscu (review #181). Lista idzie do Battle.create_squads (kopie: bitwa
## nie zmienia układu).
func battle_orders(ids: Array[int], squads: Array = [], grid: BuildGrid = null, age: int = 0) -> Array[Order]:
	var out: Array[Order] = []
	var garrison := battle_garrison(ids, squads, grid)
	for i in ids.size():
		if garrison[i]:
			# garnizon Dworu (#81): przy donżonie z premią wytrzymałości (Battle.create_squads)
			var g := Order.new()
			g.task = Task.GARRISON
			out.append(g)
			continue
		var o := order_for(ids[i])
		var cls := UnitTypes.unit_class(int((squads[i] as Array)[0])) if i < squads.size() else -1
		if o != null and grid != null and not order_allowed(grid, o, cls):
			o = null  # rozkaz spoza strefy z zapisu spoza gry (#374): jak brak rozkazu
		if o == null and grid != null and i < squads.size():
			o = default_order(grid, cls, age)
		if o == null or o.post == NO_POST or o.task == Task.KEEP or o.task == Task.GARRISON:
			out.append(null)
			continue
		var c := Order.new()
		c.task = Task.HOLD if o.task == Task.PATROL and o.route.is_empty() else o.task
		c.post = o.post
		c.route = o.route.duplicate()
		out.append(c)
	return out


## Czy rozkaz `o` oddziału klasy `unit_class` stoi na kratkach, które dopuszcza ekran Obrona (#374):
## każdy punkt (miejsce i punkty trasy patrolu) przechodzi post_problem, a strzelcy z Obroną odcinka
## mogą też stać na stanowisku (station_post). Zapis spoza gry (kopia zamku z serwera) może mieć
## dowolne kratki, a bitwa liczy się tylko z dozwolonych. Rozkaz bez własnej kratki jest dozwolony.
static func order_allowed(grid: BuildGrid, o: Order, unit_class: int) -> bool:
	if o.post == NO_POST or o.task == Task.KEEP or o.task == Task.GARRISON:
		return true
	for p in o.patrol_points():
		if post_problem(grid, p).is_empty():
			continue
		if o.task == Task.HOLD and p == o.post and unit_class == RecruitmentConfig.UnitClass.RANGED \
				and station_post(grid, p):
			continue
		return false
	return true


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


## Promień strefy obrony przy Dworze `manor_level` i technologii REACH_TECH na poziomie `tech_level`.
static func radius_for(manor_level: int, tech_level: int) -> int:
	return RADIUS + RADIUS_PER_MANOR_LEVEL * (maxi(1, Ages.bonus_level(manor_level)) - 1) \
			+ RADIUS_PER_TECH_LEVEL * maxi(0, tech_level)


## Promień strefy obrony zamku `grid` (poziom Dworu i BuildGrid.reach_level).
static func radius(grid: BuildGrid) -> int:
	return radius_for(grid.manor_level(), grid.reach_level)


## Poziom technologii REACH_TECH w badaniach `research` (0 bez badań albo niezbadana); ustawia
## BuildGrid.reach_level.
static func reach_level(research: Research) -> int:
	return research.level(REACH_TECH) if research != null else 0


## Strefa obrony: kratki, na których może stać posterunek i pułapka (przycięta do mapy).
static func zone(grid: BuildGrid) -> Rect2i:
	var c := keep_center(grid)
	if c == NO_POST:
		return Rect2i()
	var rad := radius(grid)
	var r := Rect2i(c - Vector2i.ONE * rad, Vector2i.ONE * (2 * rad + 1))
	return r.intersection(Rect2i(0, 0, grid.terrain.size, grid.terrain.size))


## Pusty napis, gdy na kratce `cell` może stać posterunek; inaczej powód po polsku (pasek komunikatu).
static func post_problem(grid: BuildGrid, cell: Vector2i) -> String:
	if not grid.terrain.in_bounds(cell):
		return "Poza mapą"
	if not zone(grid).has_point(cell):
		return "Za daleko od donżonu: najwyżej %d kratek" % radius(grid)
	if grid.terrain.get_tile(cell) == TerrainMap.Tile.WATER:
		return "Załoga nie stanie w wodzie"
	var id := grid.building_at(cell)
	if id != 0:
		return "Tu stoi %s" % BuildingTypes.NAMES[grid.kinds[id]]
	return ""


## Zadanie domyślne oddziału klasy `unit_class` (RecruitmentConfig.UnitClass) na zamku `grid` w epoce
## `age`, albo null (przy donżonie): strzelcy na odcinek wału albo palisady najbliżej bramy (bez bramy
## najbliżej donżonu), piechota lekka i ciężka przy bramie od środka, konnica na wypad (przed epoką II
## jak piechota), specjalni przy donżonie. Brama i mury muszą stać w strefie obrony.
static func default_order(grid: BuildGrid, unit_class: int, age: int = 0) -> Order:
	var gate := main_gate(grid)
	var o := Order.new()
	match unit_class:
		RecruitmentConfig.UnitClass.RANGED:
			o.post = default_wall_post(grid, gate)
		RecruitmentConfig.UnitClass.LIGHT, RecruitmentConfig.UnitClass.HEAVY:
			o.post = section_post(grid, gate) if gate != 0 else NO_POST
		RecruitmentConfig.UnitClass.FAST:
			o.post = section_post(grid, gate) if gate != 0 else NO_POST
			if age >= TASK_AGE[Task.SORTIE]:
				o.task = Task.SORTIE
		_:
			return null
	return o if o.post != NO_POST else null


## Brama zamku w strefie obrony (najniższe id) albo 0.
static func main_gate(grid: BuildGrid) -> int:
	var z := zone(grid)
	var best := 0
	for id: int in grid.buildings:
		if grid.kinds[id] == BuildingTypes.Kind.GATE and grid.levels[id] >= 1 and z.intersects(grid.buildings[id]) \
				and (best == 0 or id < best):
			best = id
	return best


## Kratka wału albo palisady w strefie najbliżej bramy `gate` (bez bramy: najbliżej donżonu), przy
## remisie najniższe id; NO_POST bez murów.
static func default_wall_post(grid: BuildGrid, gate: int) -> Vector2i:
	var target := grid.buildings[gate].get_center() if gate != 0 else keep_center(grid)
	var z := zone(grid)
	var best := NO_POST
	var best_d := -1
	var best_id := 0
	for id: int in grid.buildings:
		var c := grid.buildings[id].position
		if not BuildingTypes.is_wall(grid.kinds[id]) or grid.levels[id] < 1 or not z.has_point(c):
			continue
		var d := (c - target).length_squared()
		if best_d < 0 or d < best_d or (d == best_d and id < best_id):
			best = c
			best_d = d
			best_id = id
	return best


## Czy kratka `cell` to stanowisko na murze: gotowy wał albo palisada w strefie obrony (#20).
static func wall_post(grid: BuildGrid, cell: Vector2i) -> bool:
	if not grid.terrain.in_bounds(cell) or not zone(grid).has_point(cell):
		return false
	var id := grid.building_at(cell)
	return id != 0 and BuildingTypes.is_wall(grid.kinds[id]) and grid.levels[id] >= 1


## Czy kratka `cell` to stanowisko strzelców: mur (wall_post), gotowa wieża drewniana (#232) albo Kopiec
## (#35) w strefie obrony. Na donżonie strzelcy stają sami, gdy oddział stoi przy donżonie.
static func station_post(grid: BuildGrid, cell: Vector2i) -> bool:
	if wall_post(grid, cell):
		return true
	if not grid.terrain.in_bounds(cell) or not zone(grid).has_point(cell):
		return false
	var id := grid.building_at(cell)
	return id != 0 and (grid.kinds[id] == BuildingTypes.Kind.TOWER or grid.kinds[id] == BuildingTypes.Kind.MOUND) \
			and grid.levels[id] >= 1


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


# --- Pułapki (#100) -----------------------------------------------------------------------------------

func trap_at(cell: Vector2i) -> Trap:
	for t in traps:
		if t.cell == cell:
			return t
	return null


func add_trap(kind: int, cell: Vector2i) -> Trap:
	var t := Trap.new()
	t.kind = kind
	t.cell = cell
	traps.append(t)
	return t


func remove_trap(cell: Vector2i) -> bool:
	var t := trap_at(cell)
	if t == null:
		return false
	traps.erase(t)
	return true


## Pusty napis, gdy na kratce `cell` może stanąć pułapka `kind` (strefa, wolna kratka, miejsce według
## TrapConfig.PLACE, bez innej pułapki); inaczej powód po polsku.
func trap_place_problem(grid: BuildGrid, kind: int, cell: Vector2i) -> String:
	var problem := post_problem(grid, cell)
	if not problem.is_empty():
		return problem
	if trap_at(cell) != null:
		return "Tu już jest pułapka"
	var keep := keep_center(grid)
	var here := (cell - keep).length_squared()
	match TrapConfig.PLACE[kind]:
		TrapConfig.Place.BEFORE_WALL:
			for d: Vector2i in [Vector2i.UP, Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT]:
				if wall_post(grid, cell + d) and here > (cell + d - keep).length_squared():
					return ""
			return "%s: tuż przed wałem albo palisadą, od zewnątrz" % TrapConfig.NAMES[kind]
		TrapConfig.Place.NEAR_WALL:
			for dy in range(-1, 2):
				for dx in range(-1, 2):
					var n := cell + Vector2i(dx, dy)
					var id := grid.building_at(n) if grid.terrain.in_bounds(n) else 0
					if id != 0 and grid.levels[id] >= 1 and (BuildingTypes.is_wall(grid.kinds[id]) \
							or grid.kinds[id] == BuildingTypes.Kind.TOWER):
						return ""
			return "%s: przy murze albo wieży" % TrapConfig.NAMES[kind]
		TrapConfig.Place.BEFORE_GATE:
			for d: Vector2i in [Vector2i.UP, Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT]:
				var n := cell + d
				var id := grid.building_at(n) if grid.terrain.in_bounds(n) else 0
				if id != 0 and grid.kinds[id] == BuildingTypes.Kind.GATE and grid.levels[id] >= 1 \
						and here > (grid.buildings[id].get_center() - keep).length_squared():
					return ""
			return "%s: tuż przed bramą, od zewnątrz" % TrapConfig.NAMES[kind]
	return ""


## Pułapki do bitwy na zamku `grid` (#374): tylko te, które ekran Obrona by postawił, czyli spełnione
## wymagania (TrapConfig.requirement_problem z badaniami `research` i epoką `age`) i miejsce
## (trap_place_problem), w kolejności postawienia i najwyżej TrapConfig.limit. Kopie: bitwa nie
## zmienia układu, a zapis zostaje bez zmian (np. pułapka przed zburzonym wałem wraca z wałem).
func battle_traps(grid: BuildGrid, research: Research, age: int) -> Array[Trap]:
	var ok := DefensePlan.new()
	var limit := TrapConfig.limit(grid.manor_level())
	for t in traps:
		if ok.traps.size() >= limit:
			break
		if not TrapConfig.requirement_problem(t.kind, grid, research, age).is_empty() \
				or not ok.trap_place_problem(grid, t.kind, t.cell).is_empty():
			continue
		ok.add_trap(t.kind, t.cell).revealed = t.revealed
	return ok.traps


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
	var trap_list: Array = []
	for t in traps:
		trap_list.append([t.kind, t.cell.x, t.cell.y, 1 if t.revealed else 0])
	return {"orders": list, "tower_priority": tower_priority, "traps": trap_list, "commander": commander}


## Układ z danych zapisu (JSON daje liczby jako float, więc wszystko idzie przez int()). Złe wpisy
## są pomijane.
static func from_dict(d: Dictionary) -> DefensePlan:
	var p := DefensePlan.new()
	for e: Variant in d.get("traps", []) as Array:
		if not e is Array or (e as Array).size() < 3:
			continue
		var a := e as Array
		var kind := int(a[0])
		var cell := Vector2i(int(a[1]), int(a[2]))
		if kind < 0 or kind >= TrapConfig.count() or p.trap_at(cell) != null:
			continue
		p.add_trap(kind, cell).revealed = a.size() > 3 and int(a[3]) != 0
	p.tower_priority = clampi(int(d.get("tower_priority", 0)), 0, TOWER_PRIORITY_NAMES.size() - 1)
	var cmd := Generals._int_of(d.get("commander"), -1)
	p.commander = cmd if cmd >= 0 and cmd < Generals.count() else -1
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
