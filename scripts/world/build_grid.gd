class_name BuildGrid
extends RefCounted
## Zajętość kratek: który budynek stoi na której kratce. Budynek zajmuje prostokąt kratek.
## Identyfikatory rosną od 1 (0 oznacza wolną kratkę) i nie są używane ponownie.

var terrain: TerrainMap
var cells: PackedInt32Array
var buildings: Dictionary[int, Rect2i] = {}
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
func place(rect: Rect2i) -> int:
	if not can_place(rect):
		return 0
	var id := _next_id
	_next_id += 1
	buildings[id] = rect
	_fill(rect, id)
	return id


## Usuwa budynek. Zwraca false, gdy takiego nie ma.
func remove(id: int) -> bool:
	if not buildings.has(id):
		return false
	_fill(buildings[id], 0)
	buildings.erase(id)
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
