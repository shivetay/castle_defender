class_name AmbientView
extends Node2D
## Życie zamku (#150, #36): dym z kominów, błyski na wodzie, mieszkańcy przy budynkach, straż
## na murach, łopoczące proporce i pora dnia. Rysuje kilkadziesiąt prostokątów kilka razy na sekundę
## (TICK_HZ), a nie co klatkę, i nie dotyka tekstur terenu ani budynków. To czysta oprawa: czas
## nie wpływa na symulację, a trasy i wzory biorą się z siatki i hash2.
@warning_ignore_start("integer_division")

const TICK_HZ := 8
## Długość cyklu błysku na wodzie i życia kłębu dymu (w tyknięciach).
const GLINT_CYCLE := 32
const SMOKE_LIFE := 24
const PUFFS := 4
## Najwięcej mieszkańców i strażników naraz (koszt rysowania na słabym telefonie).
const MAX_VILLAGERS := 10
const MAX_PATROLS := 4
## Mieszkaniec chodzi pod budynkiem najdalej o tyle kratek w każdą stronę.
const VILLAGER_REACH := 4
## Najdłuższa trasa strażnika w odcinkach muru i najkrótsza, na której w ogóle stoi straż.
const MAX_PATROL_CELLS := 16
const MIN_PATROL_CELLS := 3
## Pora dnia (#36): co ile sekund odświeżyć tint z zegara telefonu.
const TINT_EVERY_S := 10.0
## Klatki kluczowe pory dnia: (minuta doby, indeks w Palette.DAYLIGHT). Noc do 5:00, świt do 8:00,
## dzień do 18:30, zmierzch do 21:30.
const DAY_KEYS: Array[Vector2i] = [Vector2i(0, 0), Vector2i(300, 0), Vector2i(390, 1), Vector2i(480, 2),
		Vector2i(1110, 2), Vector2i(1200, 3), Vector2i(1290, 0), Vector2i(1440, 0)]
## Mieszkańcy siedzą w domach od tej minuty doby do NIGHT_END.
const NIGHT_START := 1290
const NIGHT_END := 300
## Kolory ubrań mieszkańców (z palety epoki I).
const TUNICS: Array[Color] = [Palette.WOOD[2], Palette.THATCH[0], Palette.WATER[1], Palette.EARTH[3]]

var grid: BuildGrid
var textures: BuildingTextures
## Mieszkańcy i straż chodzą tylko poza bitwą (main wyłącza je na czas bitwy na własnym zamku).
var life := true
## Stan zniszczeń budynków (id → BuildingTypes.State), żeby zburzony budynek nie łopotał flagą.
var states: Dictionary = {}

## Kratki wody w kubełkach po fazie błysku (hash2 % GLINT_CYCLE): w danym tyknięciu błyszczą tylko
## 3 kubełki, więc rysowanie nie przechodzi po całej rzece (review #191).
var _glints: Array[Array] = []
var _tick := 0
var _time := 0.0
## Trasy liczone przy zmianie zabudowy (_layout_key), a nie w każdym tyknięciu.
var _layout := -1
var _villagers: Array[Vector4i] = []
var _patrols: Array[Array] = []
## Proporce w pikselach mapy: Vector4i(x, y, kierunek, kolor) jak w BuildingTextures.flags.
var _flags: Array[Vector4i] = []
var _tint: CanvasModulate
var _tint_wait := 0.0
## Minuta doby wymuszona w wersji debug: `godot --path . -- --hour=22` (test nocy bez czekania).
var _forced_minute := -1


## Kratki wody liczy się raz: teren się nie zmienia.
func setup(g: BuildGrid, t: BuildingTextures) -> void:
	grid = g
	textures = t
	_layout = -1
	_glints.clear()
	for i in GLINT_CYCLE:
		_glints.append([])
	var map := g.terrain
	for y in map.size:
		for x in map.size:
			if map.get_tile(Vector2i(x, y)) == TerrainMap.Tile.WATER:
				var h := PixelCanvas.hash2(x, y, 7)
				_glints[h % GLINT_CYCLE].append(Vector3i(x, y, h))
	if OS.is_debug_build():
		for arg in OS.get_cmdline_user_args():
			if arg.begins_with("--hour="):
				_forced_minute = clampi(arg.trim_prefix("--hour=").to_int(), 0, 23) * 60


## CanvasModulate barwi cały świat (warstwa 0), a HUD na CanvasLayer zostaje w swoich kolorach.
func _ready() -> void:
	_tint = CanvasModulate.new()
	add_child(_tint)
	_update_tint()


func _process(delta: float) -> void:
	_time += delta
	_tint_wait -= delta
	if _tint_wait <= 0.0:
		_update_tint()
	var t := int(_time * TICK_HZ)
	if t != _tick:
		_tick = t
		queue_redraw()


func _draw() -> void:
	if grid == null:
		return
	_refresh_layout()
	_draw_glints()
	if life:
		if villagers_out(_minute()):
			_draw_villagers()
		_draw_patrols()
	_draw_flags()
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


## Wylot komina w pikselach mapy: w prawej trzeciej części dachu, tuż za kalenicą (BuildingArt.chimney_at).
func chimney(id: int) -> Vector2i:
	var kind := grid.kinds[id]
	var lean := CastleView.lean_of(grid, id)
	var used := textures.used_rect(kind, grid.levels[id], BuildingTypes.State.INTACT, 0, false, lean, grid.cells_of(id))
	var origin := CastleView.texture_origin(grid.buildings[id].position, kind) + CastleView.attach_offset(grid, textures, id)
	return origin + BuildingArt.chimney_at(used)


# --- Pora dnia (#36) ---------------------------------------------------------------------------

## Minuta doby z zegara telefonu (czas lokalny) albo wymuszona w wersji debug.
func _minute() -> int:
	if _forced_minute >= 0:
		return _forced_minute
	var now := Time.get_datetime_dict_from_system()
	return int(now["hour"]) * 60 + int(now["minute"])


func _update_tint() -> void:
	_tint_wait = TINT_EVERY_S
	if _tint != null:
		_tint.color = tint_at(_minute())


## Tint świata o danej minucie doby: płynne przejście między klatkami DAY_KEYS.
static func tint_at(minute: int) -> Color:
	var m := posmod(minute, 1440)
	for i in range(1, DAY_KEYS.size()):
		var b := DAY_KEYS[i]
		if m <= b.x:
			var a := DAY_KEYS[i - 1]
			var t := float(m - a.x) / float(b.x - a.x)
			return Palette.DAYLIGHT[a.y].lerp(Palette.DAYLIGHT[b.y], t)
	return Palette.NIGHT_TINT


## Czy mieszkańcy są na dworze (nocą siedzą w domach, straż chodzi dalej).
static func villagers_out(minute: int) -> bool:
	var m := posmod(minute, 1440)
	return m >= NIGHT_END and m < NIGHT_START


# --- Trasy mieszkańców i straży (#36) ----------------------------------------------------------

## Klucz zabudowy: zmienia się, gdy budynek przybywa, znika, zmienia rodzaj albo poziom (proporzec
## pojawia się na poziomie 5 i zmienia z epoką, review #286). Do tego stan zniszczeń (flagi znikają
## ze zburzonych budynków).
func _layout_key() -> int:
	var k := grid.levels.size()
	for id in grid.levels:
		k = (k * 31 + id * 7 + grid.levels[id] * 3 + grid.kinds[id] * 101) & 0x7fffffff
	return (k * 131 + states.hash()) & 0x7fffffff


func _refresh_layout() -> void:
	var k := _layout_key()
	if k == _layout:
		return
	_layout = k
	_villagers = villager_routes(grid)
	_patrols = patrol_paths(grid)
	_flags = _flag_spots()


## Trasy mieszkańców: Vector4i(pierwsza kratka x, ostatnia kratka x, wiersz y, hash). Dwa na trzy gotowe
## domy i warsztaty (z hasha pozycji) mają mieszkańca, który chodzi tam i z powrotem po wolnych kratkach
## pod budynkiem (albo nad nim, gdy pod spodem nie ma miejsca), nigdy przez budynek ani wodę.
static func villager_routes(g: BuildGrid) -> Array[Vector4i]:
	var routes: Array[Vector4i] = []
	for id in g.draw_order():
		if routes.size() >= MAX_VILLAGERS:
			break
		var kind := g.kinds[id]
		if g.levels[id] < 1 or not _has_folk(kind):
			continue
		var r := g.buildings[id]
		var h := PixelCanvas.hash2(r.position.x, r.position.y, 41)
		if h % 3 == 0:
			continue
		var cx := r.position.x + r.size.x / 2
		for y: int in [r.end.y, r.position.y - 1]:
			var span := _free_span(g, Vector2i(cx, y))
			if span.y - span.x >= 1:
				routes.append(Vector4i(span.x, span.y, y, h))
				break
	return routes


## Domy i warsztaty: tam, gdzie ktoś mieszka albo pracuje (bez umocnień, wież i pól).
static func _has_folk(kind: int) -> bool:
	return kind == BuildingTypes.Kind.MANOR or BuildingArt.can_lean(kind) or kind in [
			BuildingTypes.Kind.FARM, BuildingTypes.Kind.WELL, BuildingTypes.Kind.QUARRY]


## Wolne kratki w wierszu wokół `c` (najdalej VILLAGER_REACH): Vector2i(pierwsza x, ostatnia x),
## albo (1, 0), gdy samo `c` nie jest wolne.
static func _free_span(g: BuildGrid, c: Vector2i) -> Vector2i:
	if not _walkable(g, c):
		return Vector2i(1, 0)
	var x0 := c.x
	var x1 := c.x
	while c.x - x0 < VILLAGER_REACH and _walkable(g, Vector2i(x0 - 1, c.y)):
		x0 -= 1
	while x1 - c.x < VILLAGER_REACH and _walkable(g, Vector2i(x1 + 1, c.y)):
		x1 += 1
	return Vector2i(x0, x1)


static func _walkable(g: BuildGrid, c: Vector2i) -> bool:
	var n := g.terrain.size
	if c.x < 0 or c.y < 0 or c.x >= n or c.y >= n:
		return false
	return g.building_at(c) == 0 and g.terrain.get_tile(c) != TerrainMap.Tile.WATER


## Trasy straży: po jednej na każdy ciąg gotowych odcinków wału i palisady z co najmniej
## MIN_PATROL_CELLS odcinkami. Strażnik zaczyna na końcu linii (na pierścieniu w kratce o najmniejszym
## hashu) i idzie po sąsiednich odcinkach, najdalej MAX_PATROL_CELLS. Kratki w kolejności marszu.
static func patrol_paths(g: BuildGrid) -> Array[Array]:
	var walls: Dictionary[Vector2i, bool] = {}
	var order: Array[Vector2i] = []
	for id in g.draw_order():
		if BuildingTypes.is_wall(g.kinds[id]) and g.levels[id] >= 1:
			walls[g.buildings[id].position] = true
			order.append(g.buildings[id].position)
	var seen: Dictionary[Vector2i, bool] = {}
	var paths: Array[Array] = []
	for first in order:
		if paths.size() >= MAX_PATROLS:
			break
		if seen.has(first):
			continue
		var part := _component(first, walls, seen)
		if part.size() < MIN_PATROL_CELLS:
			continue
		var path := _walk(_patrol_start(part, walls), walls)
		if path.size() >= MIN_PATROL_CELLS:
			paths.append(path)
	return paths


const _DIRS: Array[Vector2i] = [Vector2i.UP, Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT]


static func _component(first: Vector2i, walls: Dictionary[Vector2i, bool], seen: Dictionary[Vector2i, bool]) -> Array[Vector2i]:
	var part: Array[Vector2i] = [first]
	seen[first] = true
	var i := 0
	while i < part.size():
		for d in _DIRS:
			var n := part[i] + d
			if walls.has(n) and not seen.has(n):
				seen[n] = true
				part.append(n)
		i += 1
	return part


static func _degree(c: Vector2i, walls: Dictionary[Vector2i, bool]) -> int:
	var n := 0
	for d in _DIRS:
		if walls.has(c + d):
			n += 1
	return n


## Początek trasy: koniec linii (odcinek z jednym sąsiadem) o najmniejszym hashu, a bez końców
## (pierścień) dowolna kratka o najmniejszym hashu.
static func _patrol_start(part: Array[Vector2i], walls: Dictionary[Vector2i, bool]) -> Vector2i:
	var best := part[0]
	var best_score := -1
	for c in part:
		var score := PixelCanvas.hash2(c.x, c.y, 43) + (0 if _degree(c, walls) == 1 else 0x40000000)
		if best_score < 0 or score < best_score:
			best = c
			best_score = score
	return best


## Marsz po linii: zawsze do pierwszego nieodwiedzonego sąsiada (N, E, S, W), aż do końca albo limitu.
static func _walk(start: Vector2i, walls: Dictionary[Vector2i, bool]) -> Array[Vector2i]:
	var path: Array[Vector2i] = [start]
	var visited: Dictionary[Vector2i, bool] = {start: true}
	while path.size() < MAX_PATROL_CELLS:
		var next := Vector2i(-1, -1)
		for d in _DIRS:
			var n := path[-1] + d
			if walls.has(n) and not visited.has(n):
				next = n
				break
		if next.x < 0:
			break
		visited[next] = true
		path.append(next)
	return path


## Proporce wszystkich budynków w pikselach mapy, z tekstur w obecnym stanie zniszczeń.
func _flag_spots() -> Array[Vector4i]:
	var spots: Array[Vector4i] = []
	for id in grid.draw_order():
		var kind := grid.kinds[id]
		if grid.levels[id] < 1:
			continue
		var lean := CastleView.lean_of(grid, id)
		var fl := textures.flags(kind, grid.levels[id], int(states.get(id, BuildingTypes.State.INTACT)),
				grid.wall_mask(id), grid.is_vertical(id), lean, grid.cells_of(id))
		if fl.is_empty():
			continue
		var origin := CastleView.texture_origin(grid.buildings[id].position, kind) + CastleView.attach_offset(grid, textures, id)
		for f: Vector4i in fl:
			spots.append(Vector4i(origin.x + f.x, origin.y + f.y, f.z, f.w))
	return spots


# --- Rysowanie życia (#36) ---------------------------------------------------------------------

## Mieszkaniec: głowa 1 px, tunika 2×2 i krok co drugie tyknięcie. Chodzi 8 px/s tam i z powrotem.
func _draw_villagers() -> void:
	var cell := TerrainMap.CELL
	for v in _villagers:
		var x0 := v.x * cell + 1
		var span := (v.y - v.x + 1) * cell - 4
		var p := (_tick + v.w) % (2 * span)
		var right := p < span
		var x := x0 + (p if right else 2 * span - p)
		var y := v.z * cell + 2 + v.w % 3
		_draw_person(Vector2i(x, y), right, TUNICS[v.w % TUNICS.size()])


## Strażnik: jak mieszkaniec, w ciemnej tunice i z włócznią. Maszeruje 4 px/s po koronie muru.
func _draw_patrols() -> void:
	var cell := TerrainMap.CELL
	for i in _patrols.size():
		var path: Array = _patrols[i]
		var length := (path.size() - 1) * cell
		var h := PixelCanvas.hash2(i, path.size(), 47)
		var p := (_tick / 2 + h) % (2 * length)
		var dist := p if p < length else 2 * length - p
		var seg := mini(dist / cell, path.size() - 2)
		var a: Vector2i = path[seg]
		var b: Vector2i = path[seg + 1]
		var at := a * cell + Vector2i(3, 2) + (b - a) * (dist - seg * cell)
		var forward := p < length
		_draw_person(at, (b.x > a.x) == forward if b.x != a.x else forward, Palette.WATER[0])
		draw_rect(Rect2(at.x + 2, at.y - 1, 1, 3), Palette.WOOD[1])  # drzewce włóczni
		draw_rect(Rect2(at.x + 2, at.y - 2, 1, 1), Palette.THATCH[2])  # grot


func _draw_person(at: Vector2i, right: bool, tunic: Color) -> void:
	draw_rect(Rect2(at.x + 1, at.y + 3, 2, 1), Color(Palette.SHADOW, 0.35))
	draw_rect(Rect2(at.x, at.y + 1, 2, 2), tunic)
	draw_rect(Rect2(at.x + (1 if right else 0), at.y, 1, 1), Palette.SKIN)
	draw_rect(Rect2(at.x + _tick % 2, at.y + 3, 1, 1), Palette.WOOD[0])


## Łopotanie proporca w 4 klatkach: spokojny (jak tekstura), fala w środku płachty, płachta
## wyprostowana (wcięcie wypełnione, koniec dłuższy o piksel) i opadający koniec.
func _draw_flags() -> void:
	for f in _flags:
		var col := Palette.ACCENT if f.w == 0 else Palette.AGE_II_ACCENT
		var d := f.z
		match (_tick / 2 + PixelCanvas.hash2(f.x, f.y, 17)) % 4:
			1:
				draw_rect(Rect2(f.x + d, f.y, 1, 1), Color(Palette.SHADOW, 0.35))
			2:
				draw_rect(Rect2(f.x + 2 * d, f.y + 1, 1, 1), col)
				draw_rect(Rect2(f.x + 3 * d, f.y, 1, 1), col)
			3:
				draw_rect(Rect2(f.x + 2 * d, f.y, 1, 1), Color(Palette.SHADOW, 0.35))
				draw_rect(Rect2(f.x + 2 * d, f.y + 1, 1, 1), col)
