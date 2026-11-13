class_name TerrainMap
extends RefCounted
## Teren zamku: siatka kratek 8×8 px z typem podłoża i wysokością (odcień trawy).
## Generator jest deterministyczny: ten sam seed zawsze daje ten sam teren. Logika jest
## na liczbach całkowitych, żeby wynik nie zależał od platformy (ważne przy PvP).
@warning_ignore_start("integer_division")

enum Tile { GRASS, PATH, WATER, BRIDGE }

const SIZE := 64
const CELL := 8
## Progi wysokości dla 4 odcieni trawy (wysokość 0..~1100).
const LEVELS: Array[int] = [300, 550, 800]
const HILL_RADIUS := 24
const HILL_BONUS := 600

var size: int
var world_seed: int
var tiles: PackedByteArray
var heights: PackedByteArray


static func generate(map_seed: int, map_size: int = SIZE) -> TerrainMap:
	var map := TerrainMap.new()
	map.size = map_size
	map.world_seed = map_seed
	map.tiles.resize(map_size * map_size)
	map.heights.resize(map_size * map_size)
	map._make_hill()
	var rng := RandomNumberGenerator.new()
	rng.seed = PixelCanvas.hash2(map_seed, 17, 0x5eed)
	var river_west := rng.randi_range(0, 1) == 0
	map._make_river(rng, river_west)
	map._make_paths(rng, river_west)
	return map


func in_bounds(c: Vector2i) -> bool:
	return c.x >= 0 and c.y >= 0 and c.x < size and c.y < size


func get_tile(c: Vector2i) -> int:
	return tiles[c.y * size + c.x]


func get_height(c: Vector2i) -> int:
	return heights[c.y * size + c.x]


## Czy na kratce wolno budować (tylko trawa; ścieżki, woda i mosty są wolne od zabudowy).
func is_buildable(c: Vector2i) -> bool:
	return in_bounds(c) and get_tile(c) == Tile.GRASS


## Środek wzgórza, na którym stoi gród.
func center() -> Vector2i:
	return Vector2i(size / 2, size / 2)


func _set_tile(c: Vector2i, tile: int) -> void:
	if not in_bounds(c):
		return
	var i := c.y * size + c.x
	if tile == Tile.PATH and tiles[i] == Tile.WATER:
		tile = Tile.BRIDGE
	if tiles[i] == Tile.BRIDGE:
		return
	tiles[i] = tile


## Wzgórze: dwie oktawy szumu wartości plus łagodne wzniesienie pośrodku mapy.
func _make_hill() -> void:
	var mid := center()
	var r2 := HILL_RADIUS * HILL_RADIUS
	for y in size:
		for x in size:
			var n := (_value_noise(x, y, 16) * 2 + _value_noise(x, y, 8)) / 3
			var d := Vector2i(x, y) - mid
			var bonus := maxi(0, r2 - (d.x * d.x + d.y * d.y)) * HILL_BONUS / r2
			var h := n / 2 + bonus
			var level := 0
			for t in LEVELS:
				if h >= t:
					level += 1
			heights[y * size + x] = level
			tiles[y * size + x] = Tile.GRASS


## Szum wartości 0..1023 z interpolacją dwuliniową na liczbach całkowitych.
func _value_noise(x: int, y: int, step: int) -> int:
	var lx := x / step
	var ly := y / step
	var fx := x % step
	var fy := y % step
	var a := PixelCanvas.hash2(lx, ly, world_seed) % 1024
	var b := PixelCanvas.hash2(lx + 1, ly, world_seed) % 1024
	var c := PixelCanvas.hash2(lx, ly + 1, world_seed) % 1024
	var d := PixelCanvas.hash2(lx + 1, ly + 1, world_seed) % 1024
	var top := a * (step - fx) + b * fx
	var bottom := c * (step - fx) + d * fx
	return (top * (step - fy) + bottom * fy) / (step * step)


## Rzeka szerokości 2 kratek płynie z północy na południe z boku wzgórza.
func _make_river(rng: RandomNumberGenerator, west: bool) -> void:
	var lo := 3 if west else size - 19
	var hi := 17 if west else size - 5
	var x := rng.randi_range(lo + 3, hi - 3)
	for y in size:
		_set_tile(Vector2i(x, y), Tile.WATER)
		_set_tile(Vector2i(x + 1, y), Tile.WATER)
		x = clampi(x + rng.randi_range(-1, 1), lo, hi)


## Dwie ścieżki od grodu: na południe do krawędzi mapy i w stronę rzeki (przez most).
func _make_paths(rng: RandomNumberGenerator, river_west: bool) -> void:
	var mid := center()
	_walk_path(rng, mid + Vector2i(0, 4), Vector2i(0, 1))
	_walk_path(rng, mid + Vector2i(-4 if river_west else 4, 0), Vector2i(-1 if river_west else 1, 0))


## Ścieżka idzie w kierunku `dir` i co kilka kratek skręca o jedną w bok. Kratki przy skręcie
## łączą się bokami, więc ścieżka nie ma dziur.
func _walk_path(rng: RandomNumberGenerator, start: Vector2i, dir: Vector2i) -> void:
	var side := Vector2i(dir.y, dir.x)
	var c := start
	var mid := center()
	var step := 0
	while in_bounds(c):
		_set_tile(c, Tile.PATH)
		step += 1
		if step % 3 == 0:
			var turn := rng.randi_range(-1, 1)
			var next := c + side * turn
			# ścieżka nie odpływa dalej niż 6 kratek od osi grodu
			var off := next - mid
			if absi(off.x * side.x + off.y * side.y) <= 6:
				c = next
				_set_tile(c, Tile.PATH)
		c += dir
