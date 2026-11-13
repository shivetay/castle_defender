class_name BuildGrid
extends RefCounted
## Zajętość kratek: który budynek stoi na której kratce. Budynek zajmuje prostokąt kratek,
## ma rodzaj (`BuildingTypes.Kind`) i poziom 1..MAX_LEVEL.
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
func place(rect: Rect2i, kind: int = BuildingTypes.Kind.LUMBER_HUT) -> int:
	if not can_place(rect):
		return 0
	var id := _next_id
	_next_id += 1
	buildings[id] = rect
	kinds[id] = kind
	levels[id] = 1
	_fill(rect, id)
	return id


## Stawia budynek danego rodzaju z lewym górnym rogiem na kratce `c`.
func place_kind(c: Vector2i, kind: int) -> int:
	return place(Rect2i(c, BuildingTypes.size_of(kind)), kind)


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
		if other != 0 and BuildingTypes.connects(kinds[id], kinds[other]):
			mask |= bits[i]
	return mask


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
