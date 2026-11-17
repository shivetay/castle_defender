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


## Czy cały prostokąt mieści się na mapie, leży na trawie i jest wolny. Rybak (`kind` = FISHER)
## musi też stykać się bokiem z wodą (rzeka z generatora terenu, #122).
## Brama (`kind` = GATE) może też stać na drodze, ale tylko w poprzek: pozioma brama na drodze
## biegnącej z północy na południe, pionowa na drodze ze wschodu na zachód. Brama może też stanąć
## na odcinkach wału i palisady (po teście na telefonie): place() je wtedy zastępuje.
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
			if not terrain.in_bounds(c):
				return false
			var occupant := cells[y * terrain.size + x]
			if occupant != 0:
				if kind == BuildingTypes.Kind.GATE and BuildingTypes.is_wall(kinds.get(occupant, -1)):
					continue
				return false
			if terrain.is_buildable(c):
				continue
			if gate_across == Vector2i.ZERO or terrain.get_tile(c) != TerrainMap.Tile.PATH \
					or road_axis(c) != gate_across:
				return false
	if kind == BuildingTypes.Kind.FISHER and not touches_water(rect):
		return false
	return true


## Czy któraś kratka stykająca się bokiem z prostokątem jest wodą (most się nie liczy).
func touches_water(rect: Rect2i) -> bool:
	for y in range(rect.position.y - 1, rect.end.y + 1):
		for x in range(rect.position.x - 1, rect.end.x + 1):
			var inside_x := x >= rect.position.x and x < rect.end.x
			var inside_y := y >= rect.position.y and y < rect.end.y
			if inside_x == inside_y:
				continue  # środek prostokąta albo narożnik po skosie
			var c := Vector2i(x, y)
			if terrain.in_bounds(c) and terrain.get_tile(c) == TerrainMap.Tile.WATER:
				return true
	return false


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
	if kind == BuildingTypes.Kind.GATE:
		for wall in walls_under(rect):
			remove(wall)
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
func place_kind(c: Vector2i, kind: int, level: int = 1, stick: bool = false) -> int:
	var rect := placement_for(c, kind, stick)
	return place(rect, kind, level) if rect.has_area() else 0


## Pierwsze miejsce, w które place_kind() postawiłby budynek dla kratki `c`, albo pusty prostokąt.
## Brama najpierw szuka miejsca bez zastępowania umocnień (luka w linii), a dopiero potem stawia
## się na odcinkach wału albo palisady.
func placement_for(c: Vector2i, kind: int, stick: bool = false) -> Rect2i:
	var candidates := placement_candidates(c, kind, stick)
	for rect in candidates:
		if can_place(rect, kind) and (kind != BuildingTypes.Kind.GATE or walls_under(rect).is_empty()):
			return rect
	for rect in candidates:
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
	return spot_near(terrain.center(), BuildingTypes.Kind.MANOR, max_ring)


## Id donżonu (Wieży grodowej, #120) albo 0, gdy go nie ma.
func keep_id() -> int:
	for id: int in kinds:
		if kinds[id] == BuildingTypes.Kind.KEEP:
			return id
	return 0


## Id Strażnicy (budynku PvE, #177) albo 0, gdy jej nie ma.
func watchtower_id() -> int:
	for id: int in kinds:
		if kinds[id] == BuildingTypes.Kind.WATCHTOWER:
			return id
	return 0


## Miejsce na Strażnicę: pierwszy wolny prostokąt wokół Dworu, najdalej `max_ring` kratek, z kratką
## wolnego miejsca dookoła (wysoka czatownia nie zasłania donżonu ani Dworu). Gdy takiego nie ma,
## pierwszy wolny bez odstępu.
func watchtower_spot(max_ring: int) -> Rect2i:
	var id := manor_id()
	var around := Rect2i(terrain.center(), Vector2i.ONE) if id == 0 else buildings[id]
	var kind := BuildingTypes.Kind.WATCHTOWER
	for r in range(2, mini(max_ring, terrain.size) + 1):
		var ring := around.grow(r)
		for y in range(ring.position.y, ring.end.y):
			for x in range(ring.position.x, ring.end.x):
				if y != ring.position.y and y != ring.end.y - 1 and x != ring.position.x and x != ring.end.x - 1:
					continue
				var rect := placement_for(Vector2i(x, y), kind)
				if rect.has_area() and _clear_around(rect):
					return rect
	return spot_around(around, kind, max_ring)


## Czy w pasie 1 kratki wokół `r` nie stoi żaden budynek.
func _clear_around(r: Rect2i) -> bool:
	var g := r.grow(1)
	for y in range(g.position.y, g.end.y):
		for x in range(g.position.x, g.end.x):
			if building_at(Vector2i(x, y)) != 0:
				return false
	return true


## Miejsce na donżon: pierwszy wolny prostokąt wokół Dworu (albo środka mapy, gdy Dworu nie ma).
func keep_spot(max_ring: int) -> Rect2i:
	var id := manor_id()
	if id == 0:
		return spot_near(terrain.center(), BuildingTypes.Kind.KEEP, max_ring)
	return spot_around(buildings[id], BuildingTypes.Kind.KEEP, max_ring)


## Pierwszy wolny prostokąt dla `kind` na pierścieniach wokół całego prostokąta `around`
## (pierścień r to brzeg `around.grow(r)`), najdalej `max_ring` kratek. Odległość liczy się od
## każdego boku jednakowo, więc żadna strona nie ma przewagi z samej odległości; w pierścieniu
## kolejność jest stała (wierszami od góry). Pusty prostokąt, gdy brak.
func spot_around(around: Rect2i, kind: int, max_ring: int) -> Rect2i:
	for r in range(1, mini(max_ring, terrain.size) + 1):
		var ring := around.grow(r)
		for y in range(ring.position.y, ring.end.y):
			for x in range(ring.position.x, ring.end.x):
				if y != ring.position.y and y != ring.end.y - 1 and x != ring.position.x and x != ring.end.x - 1:
					continue
				var rect := placement_for(Vector2i(x, y), kind)
				if rect.has_area():
					return rect
	return Rect2i()


## Pierwszy wolny prostokąt dla rodzaju `kind` na kolejnych pierścieniach wokół `c`, najdalej
## `max_ring` kratek (kolejność stała dla seeda). Pusty prostokąt, gdy brak.
func spot_near(c: Vector2i, kind: int, max_ring: int) -> Rect2i:
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
## Czy stoi gotowy (poziom co najmniej 1, nie plac budowy) budynek rodzaju `kind`.
func has_built(kind: int) -> bool:
	for id: int in kinds:
		if kinds[id] == kind and levels[id] >= 1:
			return true
	return false


func manor_level() -> int:
	var id := manor_id()
	return maxi(1, levels[id]) if id != 0 else 1


## Prostokąty, które place_kind() próbuje po kolei dla dotkniętej kratki.
## Ze `stick` (stawianie przez gracza, #149) zwykły budynek przykleja się do pobliskiej linii umocnień;
## bez niego (generator zamków, szukanie miejsc) zostaje dokładnie przy kratce.
func placement_candidates(c: Vector2i, kind: int, stick: bool = false) -> Array[Rect2i]:
	var size := BuildingTypes.size_of(kind)
	if BuildingTypes.is_wall(kind):
		return _wall_candidates(c, kind)
	if kind != BuildingTypes.Kind.GATE:
		# wieża łączy się z linią umocnień, więc staje w niej, a nie obok; Dwór i donżon stoją od startu
		if stick and kind != BuildingTypes.Kind.TOWER and not BuildingTypes.is_unique(kind):
			return _stick_candidates(c, kind, size)
		return [Rect2i(c, size)] as Array[Rect2i]
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


## Kandydaci zwykłego budynku (#149): gdy przy dotkniętej kratce (do 1 kratki od budynku) biegnie wał
## albo palisada, najpierw pozycja przyklejona do tej linii: jeden bok budynku przylega do muru na
## możliwie największej długości (najlepiej całej), po stronie muru, po której jest palec. Z równych
## wygrywa pozycja najbliższa dotkniętej kratce, potem pierwsza w stałej kolejności. Na końcu zwykła
## pozycja od dotkniętej kratki, gdy przyklejenie się nie mieści.
func _stick_candidates(c: Vector2i, kind: int, size: Vector2i) -> Array[Rect2i]:
	var plain := Rect2i(c, size)
	var best := Rect2i()
	var best_score := 0
	for dy in range(-size.y, 2):
		for dx in range(-size.x, 2):
			var r := Rect2i(c + Vector2i(dx, dy), size)
			var contact := wall_contact(r)
			if contact == 0 or not can_place(r, kind):
				continue
			var d := (r.position * 2 + r.size - c * 2 - Vector2i.ONE).length_squared()
			var score := contact * 1000 - d
			if best_score == 0 or score > best_score:
				best = r
				best_score = score
	if not best.has_area() or best == plain:
		return [plain] as Array[Rect2i]
	return [best, plain] as Array[Rect2i]


## Bok, którym zwykły budynek `id` przylega do wału albo palisady (#149): kierunek do muru i kratka
## muru przy tym boku (pierwsza w stałej kolejności), z najdłuższym stykiem; [ZERO, (-1, -1)], gdy nie
## przylega. Umocnienia, brama i wieża się nie przyklejają (łączą się w linii).
func wall_side(id: int) -> Array:
	var none := [Vector2i.ZERO, Vector2i(-1, -1)]
	if not buildings.has(id):
		return none
	var kind := kinds[id]
	if BuildingTypes.is_wall(kind) or kind == BuildingTypes.Kind.GATE or kind == BuildingTypes.Kind.TOWER:
		return none
	var r := buildings[id]
	var best := none
	var best_n := 0
	for side: Vector2i in [Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT]:
		var n := 0
		var first := Vector2i(-1, -1)
		var length := r.size.x if side.y != 0 else r.size.y
		for k in length:
			var edge := Vector2i(r.position.x + k, r.position.y if side.y < 0 else r.end.y - 1) if side.y != 0 \
					else Vector2i(r.position.x if side.x < 0 else r.end.x - 1, r.position.y + k)
			var w := building_at(edge + side) if terrain.in_bounds(edge + side) else 0
			if w != 0 and BuildingTypes.is_wall(kinds[w]):
				n += 1
				if first.x < 0:
					first = edge + side
		if n > best_n:
			best_n = n
			best = [side, first]
	return best


## Ile kratek jednego boku prostokąta przylega do wału albo palisady (najwięcej z czterech boków).
func wall_contact(r: Rect2i) -> int:
	var best := 0
	for side: Vector2i in [Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT]:
		var n := 0
		var length := r.size.x if side.y != 0 else r.size.y
		for k in length:
			var edge := Vector2i(r.position.x + k, r.position.y if side.y < 0 else r.end.y - 1) if side.y != 0 \
					else Vector2i(r.position.x if side.x < 0 else r.end.x - 1, r.position.y + k)
			var w := building_at(edge + side) if terrain.in_bounds(edge + side) else 0
			if w != 0 and BuildingTypes.is_wall(kinds[w]):
				n += 1
		best = maxi(best, n)
	return best


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
	return id != 0 and BuildingTypes.is_wall(kinds[id])


## Odcinki wału i palisady pod prostokątem (brama w linii umocnień je zastępuje).
func walls_under(rect: Rect2i) -> Array[int]:
	var out: Array[int] = []
	for y in range(rect.position.y, rect.end.y):
		for x in range(rect.position.x, rect.end.x):
			var id := building_at(Vector2i(x, y))
			if id != 0 and BuildingTypes.is_wall(kinds[id]) and not out.has(id):
				out.append(id)
	return out


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
