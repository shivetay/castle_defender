class_name AmbientView
extends Node2D
## Życie zamku (#150): dym z kominów i błyski na wodzie. Rysuje kilkadziesiąt prostokątów
## kilka razy na sekundę (TICK_HZ), a nie co klatkę, i nie dotyka tekstur terenu ani budynków.
## To czysta oprawa: czas nie wpływa na symulację, a wzór i tak bierze się z hash2.
@warning_ignore_start("integer_division")

const TICK_HZ := 8
## Długość cyklu błysku na wodzie i życia kłębu dymu (w tyknięciach).
const GLINT_CYCLE := 32
const SMOKE_LIFE := 24
const PUFFS := 4

var grid: BuildGrid
var textures: BuildingTextures

## Kratki wody w kubełkach po fazie błysku (hash2 % GLINT_CYCLE): w danym tyknięciu błyszczą tylko
## 3 kubełki, więc rysowanie nie przechodzi po całej rzece (review #191).
var _glints: Array[Array] = []
var _tick := 0
var _time := 0.0


## Kratki wody liczy się raz: teren się nie zmienia.
func setup(g: BuildGrid, t: BuildingTextures) -> void:
	grid = g
	textures = t
	_glints.clear()
	for i in GLINT_CYCLE:
		_glints.append([])
	var map := g.terrain
	for y in map.size:
		for x in map.size:
			if map.get_tile(Vector2i(x, y)) == TerrainMap.Tile.WATER:
				var h := PixelCanvas.hash2(x, y, 7)
				_glints[h % GLINT_CYCLE].append(Vector3i(x, y, h))


func _process(delta: float) -> void:
	_time += delta
	var t := int(_time * TICK_HZ)
	if t != _tick:
		_tick = t
		queue_redraw()


func _draw() -> void:
	if grid == null:
		return
	_draw_glints()
	_draw_smoke()


## Błysk: krótka jasna kreska, która przez 3 tyknięcia przesuwa się po kratce wody.
func _draw_glints() -> void:
	var cell := TerrainMap.CELL
	for phase in 3:
		# faza (tick + h) % CYCLE == phase  ⇔  h % CYCLE == (phase - tick) mod CYCLE
		var bucket: Array = _glints[posmod(phase - _tick, GLINT_CYCLE)]
		for g: Vector3i in bucket:
			var h := g.z
			var at := Vector2i(g.x, g.y) * cell + Vector2i(1 + h % 3 + phase, 2 + (h / 3) % 4)
			draw_rect(Rect2(at.x, at.y, 3 - absi(phase - 1), 1), Palette.WATER[2])
			if phase == 1:
				draw_rect(Rect2(at.x + 1, at.y, 1, 1), Palette.THATCH[2])


## Dym: kłęby z komina (prawa trzecia część dachu) unoszą się, dryfują na boki i bledną.
func _draw_smoke() -> void:
	for id in grid.draw_order():
		var kind := grid.kinds[id]
		if grid.levels[id] < 1 or not smokes(kind, grid.buildings[id].position):
			continue
		var top := chimney(id)
		var h := PixelCanvas.hash2(id, kind, 13)
		for k in PUFFS:
			var age := (_tick + h + k * SMOKE_LIFE / PUFFS) % SMOKE_LIFE
			var drift := (age / 6 + h) % 3 - 1 + age / 8
			var size := 3 - age * 3 / SMOKE_LIFE
			var alpha := 0.95 - 0.03 * float(age)
			var at := Vector2i(top.x + drift - size / 2, top.y - age / 2 - size)
			# szary dym z dwóch kolorów palety: jasna ziemia przykryta do połowy szaroniebieską wodą
			draw_rect(Rect2(at.x, at.y, size, size), Color(Palette.EARTH[3], alpha))
			draw_rect(Rect2(at.x, at.y, size, size), Color(Palette.WATER[2], alpha * 0.5))


## Czy budynek dymi: Dwór i smolarnia zawsze, chaty i warsztaty co drugi (z hasha pozycji).
static func smokes(kind: int, cell: Vector2i) -> bool:
	if kind == BuildingTypes.Kind.MANOR or kind == BuildingTypes.Kind.TAR_KILN:
		return true
	return BuildingArt.can_lean(kind) and PixelCanvas.hash2(cell.x, cell.y, 31) % 2 == 0


## Wylot komina w pikselach mapy: nad dachem, w prawej trzeciej części sylwetki.
func chimney(id: int) -> Vector2i:
	var kind := grid.kinds[id]
	var lean := CastleView.lean_of(grid, id)
	var used := textures.used_rect(kind, grid.levels[id], BuildingTypes.State.INTACT, 0, false, lean)
	var origin := CastleView.texture_origin(grid.buildings[id].position, kind) + CastleView.attach_offset(grid, textures, id)
	return origin + Vector2i(used.position.x + used.size.x * 2 / 3, used.position.y)
