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
func can_place(rect: Rect2i) -> bool:
	if rect.size.x <= 0 or rect.size.y <= 0:
		return false
	for y in range(rect.position.y, rect.end.y):
		for x in range(rect.position.x, rect.end.x):
			var c := Vector2i(x, y)
			if not terrain.is_buildable(c) or cells[y * terrain.size + x] != 0:
				return false
	return true


## Stawia budynek i zwraca jego id albo 0, gdy miejsce jest niedozwolone.
## Poziom 0 stawia plac budowy (kolejka budowy podnosi go potem do 1).
func place(rect: Rect2i, kind: int = BuildingTypes.Kind.LUMBER_HUT, level: int = 1) -> int:
	if not can_place(rect):
		return 0
	var id := _next_id
	_next_id += 1
	buildings[id] = rect
	kinds[id] = kind
	levels[id] = clampi(level, 0, BuildingTypes.MAX_LEVEL)
	_fill(rect, id)
	return id


## Stawia budynek danego rodzaju na dotkniętej kratce `c`. Zwykle `c` to lewy górny róg.
## Brama staje pionowo (1×2), gdy obok jest pionowa palisada, i dosuwa się o kratkę wstecz,
## jeśli dotknięto dolnej albo prawej kratki luki w linii.
func place_kind(c: Vector2i, kind: int, level: int = 1) -> int:
	for rect in placement_candidates(c, kind):
		if can_place(rect):
			return place(rect, kind, level)
	return 0


## Pierwsze miejsce, w które place_kind() postawiłby budynek dla kratki `c`, albo pusty prostokąt.
func placement_for(c: Vector2i, kind: int) -> Rect2i:
	for rect in placement_candidates(c, kind):
		if can_place(rect):
			return rect
	return Rect2i()


## Id Dworu albo 0, gdy go nie ma.
func manor_id() -> int:
	for id: int in kinds:
		if kinds[id] == BuildingTypes.Kind.MANOR:
			return id
	return 0


## Poziom zamku, czyli poziom Dworu (1, gdy Dworu nie ma albo jest w budowie).
func manor_level() -> int:
	var id := manor_id()
	return maxi(1, levels[id]) if id != 0 else 1


## Prostokąty, które place_kind() próbuje po kolei dla dotkniętej kratki.
func placement_candidates(c: Vector2i, kind: int) -> Array[Rect2i]:
	var size := BuildingTypes.size_of(kind)
	if kind != BuildingTypes.Kind.GATE:
		return [Rect2i(c, size)]
	var beside := _is_palisade(c + Vector2i.LEFT) or _is_palisade(c + Vector2i.RIGHT)
	var above_below := _is_palisade(c + Vector2i.UP) or _is_palisade(c + Vector2i.DOWN)
	if above_below and not beside:
		var v := Vector2i(size.y, size.x)
		return [Rect2i(c, v), Rect2i(c + Vector2i.UP, v)]
	return [Rect2i(c, size), Rect2i(c + Vector2i.LEFT, size)]


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
