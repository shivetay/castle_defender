class_name BuildGrid
extends RefCounted
## Zajętość kratek: który budynek stoi na której kratce. Budynek zajmuje prostokąt kratek,
## ma rodzaj (`BuildingTypes.Kind`) i poziom 1..MAX_LEVEL. Poziom 0 to plac budowy: budynek
## zajmuje już kratki, ale jeszcze nie działa (nie produkuje, rysuje się jako rusztowanie).
## Identyfikatory rosną od 1 (0 oznacza wolną kratkę) i nie są używane ponownie.

var terrain: TerrainMap
var cells: PackedInt32Array
var buildings: Dictionary[int, Rect2i] = {}
var kinds: Dictionary[int, int] = {}
var levels: Dictionary[int, int] = {}
var _next_id := 1


func _init(map: TerrainMap) -> void:
	terrain = map
	cells.resize(map.size * map.size)


## Czy cały prostokąt mieści się na mapie, leży na trawie i jest wolny.
## Brama (`kind` = GATE) może też stać na drodze, ale tylko w poprzek: pozioma brama na drodze
## biegnącej z północy na południe, pionowa na drodze ze wschodu na zachód.
func can_place(rect: Rect2i, kind: int = -1) -> bool:
	if rect.size.x <= 0 or rect.size.y <= 0:
		return false
	var gate_across := Vector2i.ZERO
	if kind == BuildingTypes.Kind.GATE:
		# oś drogi, w poprzek której brama może stać: pozioma brama → droga pionowa
		gate_across = Vector2i.DOWN if rect.size.x > rect.size.y else Vector2i.RIGHT
	for y in range(rect.position.y, rect.end.y):
		for x in range(rect.position.x, rect.end.x):
			var c := Vector2i(x, y)
			if not terrain.in_bounds(c) or cells[y * terrain.size + x] != 0:
				return false
			if terrain.is_buildable(c):
				continue
			if gate_across == Vector2i.ZERO or terrain.get_tile(c) != TerrainMap.Tile.PATH \
					or road_axis(c) != gate_across:
				return false
	return true


## Kierunek drogi na kratce: Vector2i.DOWN (z północy na południe) albo Vector2i.RIGHT (ze wschodu
## na zachód), według liczby sąsiednich kratek drogi (lub mostu). Na zakręcie, gdzie obie osie mają
## po jednym sąsiedzie, wygrywa oś pionowa. Zero, gdy kratka nie jest drogą.
func road_axis(c: Vector2i) -> Vector2i:
	if not terrain.in_bounds(c) or terrain.get_tile(c) != TerrainMap.Tile.PATH:
		return Vector2i.ZERO
	var vertical := int(_is_road(c + Vector2i.UP)) + int(_is_road(c + Vector2i.DOWN))
	var horizontal := int(_is_road(c + Vector2i.LEFT)) + int(_is_road(c + Vector2i.RIGHT))
	return Vector2i.DOWN if vertical >= horizontal else Vector2i.RIGHT


func _is_road(c: Vector2i) -> bool:
	if not terrain.in_bounds(c):
		return false
	var t := terrain.get_tile(c)
	return t == TerrainMap.Tile.PATH or t == TerrainMap.Tile.BRIDGE


## Stawia budynek i zwraca jego id albo 0, gdy miejsce jest niedozwolone.
## Poziom 0 stawia plac budowy (kolejka budowy podnosi go potem do 1).
func place(rect: Rect2i, kind: int = BuildingTypes.Kind.LUMBER_HUT, level: int = 1) -> int:
	if not can_place(rect, kind):
		return 0
	var id := _next_id
	_next_id += 1
	buildings[id] = rect
	kinds[id] = kind
	levels[id] = clampi(level, 0, BuildingTypes.MAX_LEVEL)
	_fill(rect, id)
	return id


## Stawia budynek danego rodzaju na dotkniętej kratce `c`. Zwykle `c` to lewy górny róg.
## Brama (3×1) staje środkiem na dotkniętej kratce, a gdy tam się nie mieści, dosuwa się tak,
## żeby dotknięta kratka była jej końcem. Staje pionowo (1×3), gdy obok jest pionowa palisada.
## Dotknięta droga ustawia bramę w poprzek drogi, z drogą pośrodku.
func place_kind(c: Vector2i, kind: int, level: int = 1) -> int:
	for rect in placement_candidates(c, kind):
		if can_place(rect, kind):
			return place(rect, kind, level)
	return 0


## Pierwsze miejsce, w które place_kind() postawiłby budynek dla kratki `c`, albo pusty prostokąt.
func placement_for(c: Vector2i, kind: int) -> Rect2i:
	for rect in placement_candidates(c, kind):
		if can_place(rect, kind):
			return rect
	return Rect2i()


## Id Dworu albo 0, gdy go nie ma.
func manor_id() -> int:
	for id: int in kinds:
		if kinds[id] == BuildingTypes.Kind.MANOR:
			return id
	return 0


## Miejsce na Dwór: pierwszy wolny prostokąt na kolejnych pierścieniach wokół środka mapy
## (kolejność stała dla seeda), najdalej `max_ring` kratek od środka. Pusty prostokąt, gdy brak.
func manor_spot(max_ring: int) -> Rect2i:
	var c := terrain.center()
	var kind := BuildingTypes.Kind.MANOR
	for r in mini(max_ring, terrain.size) + 1:
		for dy in range(-r, r + 1):
			for dx in range(-r, r + 1):
				if maxi(absi(dx), absi(dy)) != r:
					continue
				var rect := placement_for(c + Vector2i(dx, dy), kind)
				if rect.has_area():
					return rect
	return Rect2i()


## Poziom zamku, czyli poziom Dworu (1, gdy Dworu nie ma albo jest w budowie).
func manor_level() -> int:
	var id := manor_id()
	return maxi(1, levels[id]) if id != 0 else 1


## Prostokąty, które place_kind() próbuje po kolei dla dotkniętej kratki.
func placement_candidates(c: Vector2i, kind: int) -> Array[Rect2i]:
	var size := BuildingTypes.size_of(kind)
	if BuildingTypes.is_wall(kind):
		return _wall_candidates(c, kind)
	if kind != BuildingTypes.Kind.GATE:
		return [Rect2i(c, size)]
	var axis := road_axis(c)
	var vertical := axis == Vector2i.RIGHT
	if axis == Vector2i.ZERO:
		var beside := _is_palisade(c + Vector2i.LEFT) or _is_palisade(c + Vector2i.RIGHT)
		var above_below := _is_palisade(c + Vector2i.UP) or _is_palisade(c + Vector2i.DOWN)
		vertical = above_below and not beside
	var along := Vector2i.DOWN if vertical else Vector2i.RIGHT
	var rect_size := Vector2i(size.y, size.x) if vertical else size
	var out: Array[Rect2i] = []
	# środek na dotkniętej kratce, potem dotknięta kratka jako pierwsza i jako ostatnia
	for back: int in [1, 0, 2]:
		out.append(Rect2i(c - along * back, rect_size))
	return out


## Kratki dla odcinka umocnienia. Wierzch umocnienia rysuje się o pół kratki wyżej niż jego kratka,
## a palec na telefonie zakrywa kilka kratek, więc dotknięcie widocznej luki w linii często trafia
## w kratkę obok. Gdy dotknięta kratka sama nie jest luką, a sąsiednia wolna kratka jest (łączy się
## z co najmniej dwoma odcinkami), odcinek wskakuje w tę lukę. Najpierw sprawdzana jest kratka
## pod dotkniętą, bo tam najczęściej leży luka, w którą celował gracz.
func _wall_candidates(c: Vector2i, kind: int) -> Array[Rect2i]:
	var tapped := Rect2i(c, Vector2i.ONE)
	if wall_links(c, kind) >= 2:
		return [tapped]
	for d: Vector2i in [Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP]:
		var n := c + d
		if wall_links(n, kind) >= 2 and can_place(Rect2i(n, Vector2i.ONE), kind):
			return [Rect2i(n, Vector2i.ONE), tapped]
	return [tapped]


## Wolna luka w linii umocnień tuż przy punkcie `pos` (piksele świata), w którą da się postawić
## odcinek `kind`, albo (-1, -1). Liczy się luka sąsiadująca z dotkniętą kratką, gdy punkt leży
## najwyżej `tolerance` px od wspólnej krawędzi; wygrywa najbliższa. Dzięki temu palec, który
## w wąskiej luce trafił w sąsiedni odcinek, stawia odcinek w luce zamiast zaznaczać sąsiada.
func gap_near(pos: Vector2, kind: int, tolerance: int) -> Vector2i:
	var cell := TerrainMap.CELL
	var c := Vector2i((pos / cell).floor())
	var local := pos - Vector2(c * cell)
	var dist: Array[float] = [local.y, cell - local.x, cell - local.y, local.x]  # N, E, S, W
	var dirs: Array[Vector2i] = [Vector2i.UP, Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT]
	var best := Vector2i(-1, -1)
	var best_dist := float(tolerance)
	for i in dirs.size():
		var n := c + dirs[i]
		if dist[i] > best_dist or building_at(n) != 0:
			continue
		if wall_links(n, kind) >= 2 and can_place(Rect2i(n, Vector2i.ONE), kind):
			best = n
			best_dist = dist[i]
	return best


## Z iloma sąsiednimi budynkami połączyłby się odcinek umocnienia `kind` postawiony na kratce `c`.
func wall_links(c: Vector2i, kind: int) -> int:
	var n := 0
	for d: Vector2i in [Vector2i.UP, Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT]:
		var other := building_at(c + d)
		if other == 0 or not BuildingTypes.connects(kind, kinds[other]):
			continue
		# z bramą łączy się tylko odcinek leżący na jej osi
		if kinds[other] == BuildingTypes.Kind.GATE and (d.x == 0) != is_vertical(other):
			continue
		n += 1
	return n


## Czy budynek stoi pionowo (dłuższy w osi y), np. brama w pionowej linii palisady.
func is_vertical(id: int) -> bool:
	return buildings.has(id) and buildings[id].size.y > buildings[id].size.x


func _is_palisade(c: Vector2i) -> bool:
	var id := building_at(c)
	return id != 0 and kinds[id] == BuildingTypes.Kind.PALISADE


## Podnosi poziom o 1. Zwraca false, gdy budynku nie ma albo ma już najwyższy poziom.
func upgrade(id: int) -> bool:
	if not buildings.has(id) or levels[id] >= BuildingTypes.MAX_LEVEL:
		return false
	levels[id] += 1
	return true


## Maska sąsiadów N/E/S/W dla odcinka umocnienia (0 dla innych budynków).
func wall_mask(id: int) -> int:
	if not buildings.has(id) or not BuildingTypes.is_wall(kinds[id]):
		return 0
	var c := buildings[id].position
	var mask := 0
	var bits: Array[int] = [BuildingTypes.N, BuildingTypes.E, BuildingTypes.S, BuildingTypes.W]
	var dirs: Array[Vector2i] = [Vector2i.UP, Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT]
	for i in dirs.size():
		var other := building_at(c + dirs[i])
		if other == 0 or not BuildingTypes.connects(kinds[id], kinds[other]):
			continue
		# z bramą łączy się tylko odcinek leżący na jej osi (nie z boku skrzydeł)
		if kinds[other] == BuildingTypes.Kind.GATE and (dirs[i].x == 0) != is_vertical(other):
			continue
		mask |= bits[i]
	return mask


## Odcinki umocnień przylegające do budynku wielokratkowego (poza bramą, która leży w linii).
## Każdy wpis to (kratka budynku, bit kierunku do odcinka). Na tych kratkach rysuje się
## „wpust” palisady, żeby linia dochodziła do korpusu budynku bez szpary.
func wall_stubs(id: int) -> Array[Vector3i]:
	var out: Array[Vector3i] = []
	if not buildings.has(id) or BuildingTypes.is_wall(kinds[id]) or kinds[id] == BuildingTypes.Kind.GATE:
		return out
	var r := buildings[id]
	var bits: Array[int] = [BuildingTypes.N, BuildingTypes.E, BuildingTypes.S, BuildingTypes.W]
	var dirs: Array[Vector2i] = [Vector2i.UP, Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT]
	for y in range(r.position.y, r.end.y):
		for x in range(r.position.x, r.end.x):
			var c := Vector2i(x, y)
			for i in dirs.size():
				var other := building_at(c + dirs[i])
				if other != 0 and other != id and BuildingTypes.is_wall(kinds[other]) \
						and BuildingTypes.connects(kinds[other], kinds[id]):
					out.append(Vector3i(x, y, bits[i]))
	return out


## Usuwa budynek. Zwraca false, gdy takiego nie ma.
func remove(id: int) -> bool:
	if not buildings.has(id):
		return false
	_fill(buildings[id], 0)
	buildings.erase(id)
	kinds.erase(id)
	levels.erase(id)
	return true


## Id budynku na kratce albo 0.
func building_at(c: Vector2i) -> int:
	if not terrain.in_bounds(c):
		return 0
	return cells[c.y * terrain.size + c.x]


func _fill(rect: Rect2i, id: int) -> void:
	for y in range(rect.position.y, rect.end.y):
		for x in range(rect.position.x, rect.end.x):
			cells[y * terrain.size + x] = id


## Id budynków w kolejności rysowania: od tylnych (wyżej na mapie) do przednich, żeby
## budynek bliżej dołu ekranu zasłaniał ten za nim. Kolejność jest zawsze ta sama.
func draw_order() -> Array[int]:
	var ids: Array[int] = []
	ids.assign(buildings.keys())
	ids.sort_custom(func(a: int, b: int) -> bool:
		var ra := buildings[a]
		var rb := buildings[b]
		if ra.end.y != rb.end.y:
			return ra.end.y < rb.end.y
		if ra.position.x != rb.position.x:
			return ra.position.x < rb.position.x
		return a < b)
	return ids


## Stan do zapisu: budynki w kolejności id, każdy jako [id, rodzaj, poziom, x, y, szer., wys.].
## Teren nie jest zapisywany, bo odtwarza się z seeda.
func save_data() -> Dictionary:
	var list: Array = []
	var ids: Array[int] = []
	ids.assign(buildings.keys())
	ids.sort()
	for id in ids:
		var r := buildings[id]
		list.append([id, kinds[id], levels[id], r.position.x, r.position.y, r.size.x, r.size.y])
	return {"next_id": _next_id, "buildings": list}


## Wczytuje budynki z save_data() do pustej siatki. Wpis, który nie mieści się na tym terenie
## (zły rodzaj, poza mapą, na zajętej kratce), jest pomijany, żeby uszkodzony zapis nie wywrócił gry.
## Zwraca liczbę pominiętych wpisów.
func load_data(d: Dictionary) -> int:
	var skipped := 0
	var max_id := 0
	for entry: Variant in d.get("buildings", []) as Array:
		var e := entry as Array
		if e == null or e.size() < 7:
			skipped += 1
			continue
		var id := int(e[0])
		var kind := int(e[1])
		var rect := Rect2i(int(e[3]), int(e[4]), int(e[5]), int(e[6]))
		if id <= 0 or buildings.has(id) or kind < 0 or kind >= BuildingTypes.count() or not can_place(rect, kind):
			skipped += 1
			continue
		buildings[id] = rect
		kinds[id] = kind
		levels[id] = clampi(int(e[2]), 0, BuildingTypes.MAX_LEVEL)
		_fill(rect, id)
		max_id = maxi(max_id, id)
	_next_id = maxi(int(d.get("next_id", 1)), max_id + 1)
	return skipped
