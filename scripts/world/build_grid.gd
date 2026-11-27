class_name BuildGrid
extends RefCounted
## Zajętość kratek: który budynek stoi na której kratce. Budynek zajmuje prostokąt kratek,
## ma rodzaj (`BuildingTypes.Kind`) i poziom 1..Ages.MAX_TOTAL_LEVEL, liczony narastająco przez epoki
## (6 to poziom 1 epoki II, #34). Poziom 0 to plac budowy: budynek
## zajmuje już kratki, ale jeszcze nie działa (nie produkuje, rysuje się jako rusztowanie).
## Identyfikatory rosną od 1 (0 oznacza wolną kratkę) i nie są używane ponownie.

## Najdłuższa krótka luka (liczba pustych kratek), którą domyka uszczelnienie do bramy/wieży.
const SEAL_MAX := 2

var terrain: TerrainMap
var cells: PackedInt32Array
var buildings: Dictionary[int, Rect2i] = {}
var kinds: Dictionary[int, int] = {}
var levels: Dictionary[int, int] = {}
## Budynki w ruinie po ataku PvP (#99, Ruins.active_at): tylko obniżają produkcję (Economy.rates).
## Ustawia je BuildQueue.update; nie trafiają do zapisu.
var ruined: Dictionary[int, bool] = {}
## Perk władcy zamku (#32, #308, RulerPerks.Perk): działa na cały zamek, więc czytają go produkcja
## (Economy.rates), czas budowy (BuildQueue) i bitwa w obronie (Battle.create_squads). Liczy się
## z badań (RulerPerks.from_research): ustawiają go SaveGame.from_dict i BuildQueue.update po ukończeniu
## badania; nie trafia do zapisu.
var ruler_perk: int = RulerPerks.Perk.NONE
## Poziom technologii O25 Wysunięte straże (#342, DefensePlan.reach_level): poszerza strefę obrony
## (DefensePlan.radius). Jak perk władcy liczy się z badań: ustawiają go SaveGame.from_dict
## i BuildQueue.update po ukończeniu badania; nie trafia do zapisu.
var reach_level: int = 0
## Kratki z pułapkami obrony (#341, DefensePlan.mark_traps): kratka → rodzaj (TrapConfig.Kind).
## Budynek nie staje na pułapce (placement_for, place), ale can_place ich nie zna, więc luka
## w umocnieniach z pułapką zostaje luką (Sprawdź szczelność). Ustawia je main przed każdą zmianą
## budynków (_tick); nie trafiają do zapisu.
var trap_cells: Dictionary[Vector2i, int] = {}
var _next_id := 1


func _init(map: TerrainMap) -> void:
	terrain = map
	cells.resize(map.size * map.size)


## Czy cały prostokąt mieści się na mapie, leży na trawie i jest wolny. Rybak (`kind` = FISHER)
## musi też stykać się bokiem z wodą (rzeka z generatora terenu, #122).
## Brama (`kind` = GATE) może też stać na drodze, ale tylko w poprzek: pozioma brama na drodze
## biegnącej z północy na południe, pionowa na drodze ze wschodu na zachód. Brama może też stanąć
## na odcinkach wału i palisady (po teście na telefonie): place() je wtedy zastępuje. Tak samo wieża
## (replaces_walls).
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
				if replaces_walls(kind) and BuildingTypes.is_wall(kinds.get(occupant, -1)):
					continue
				return false
			if terrain.is_buildable(c):
				continue
			if gate_across == Vector2i.ZERO or terrain.get_tile(c) != TerrainMap.Tile.PATH \
					or road_axis(c) != gate_across:
				return false
	if BuildingTypes.needs_water(kind) and not touches_water(rect):
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
	if not can_place(rect, kind) or trap_under(rect) >= 0:
		return 0
	if replaces_walls(kind):
		for wall in walls_under(rect):
			remove(wall)
	var id := _next_id
	_next_id += 1
	buildings[id] = rect
	kinds[id] = kind
	levels[id] = clampi(level, 0, Ages.MAX_TOTAL_LEVEL)
	_fill(rect, id)
	return id


## Stawia odcinek wału albo palisady bez sprawdzania rodzaju terenu, np. na drodze. Tylko dla generatora
## zamków-botów (BotCastle), który tak zamyka pierścień tam, gdzie przecina go droga. Inne rodzaje
## budynków dają 0 (review #200). Kratki muszą być na mapie, wolne i bez wody. Zwraca id albo 0.
## Takiego odcinka nie odtworzy load_data (wymaga can_place), ale zamków-botów się nie zapisuje.
func place_on_any_ground(rect: Rect2i, kind: int, level: int = 1) -> int:
	if not rect.has_area() or not BuildingTypes.is_wall(kind):
		return 0
	for y in range(rect.position.y, rect.end.y):
		for x in range(rect.position.x, rect.end.x):
			var c := Vector2i(x, y)
			if not terrain.in_bounds(c) or cells[y * terrain.size + x] != 0 \
					or terrain.get_tile(c) == TerrainMap.Tile.WATER:
				return 0
	var id := _next_id
	_next_id += 1
	buildings[id] = rect
	kinds[id] = kind
	levels[id] = clampi(level, 0, Ages.MAX_TOTAL_LEVEL)
	_fill(rect, id)
	return id


## Stawia zarys budynku z serwera (#28, plan ataku na gracza przed zatwierdzeniem): dowolny rodzaj
## i prostokąt bez reguł budowy, byle na mapie i na wolnych kratkach. Siatka planu ma tylko zarys
## i odsłonięte przez zwiad budynki; bitwa idzie z pełną kopią zamku (PlayerCastle.apply_launch).
## Zwraca id albo 0.
func place_outline(rect: Rect2i, kind: int, level: int = 1) -> int:
	if not rect.has_area() or kind < 0 or kind >= BuildingTypes.count():
		return 0
	for y in range(rect.position.y, rect.end.y):
		for x in range(rect.position.x, rect.end.x):
			if not terrain.in_bounds(Vector2i(x, y)) or cells[y * terrain.size + x] != 0:
				return 0
	var id := _next_id
	_next_id += 1
	buildings[id] = rect
	kinds[id] = kind
	levels[id] = clampi(level, 0, Ages.MAX_TOTAL_LEVEL)
	_fill(rect, id)
	return id


## Stawia budynek danego rodzaju na dotkniętej kratce `c`. Zwykle `c` to lewy górny róg.
## Brama (3×1) staje środkiem na dotkniętej kratce, a gdy tam się nie mieści, dosuwa się tak,
## żeby dotknięta kratka była jej końcem. Staje pionowo (1×3), gdy obok jest pionowa palisada.
## Dotknięta droga ustawia bramę w poprzek drogi, z drogą pośrodku.
## Gotowy odcinek umocnienia (poziom ≥ 1) domyka krótkie luki do bramy i wieży; gotowa brama
## albo wieża domyka luki od strony istniejących wałów i palisad.
func place_kind(c: Vector2i, kind: int, level: int = 1, stick: bool = false) -> int:
	var rect := placement_for(c, kind, stick)
	if not rect.has_area():
		return 0
	var id := place(rect, kind, level)
	if id != 0 and level >= 1:
		seal_after_place(id)
	return id


## Czy budynek `kind` może stanąć na odcinkach wału i palisady i je zastąpić: brama i wieża
## (po teście na telefonie), bo obie stoją w linii umocnień.
static func replaces_walls(kind: int) -> bool:
	return kind == BuildingTypes.Kind.GATE or kind == BuildingTypes.Kind.TOWER


## Czy budynek jest kotwicą linii umocnień, do której odcinki mają dochodzić bez szpary.
static func is_fort_anchor(kind: int) -> bool:
	return kind == BuildingTypes.Kind.GATE or kind == BuildingTypes.Kind.TOWER


## Pierwsze miejsce, w które place_kind() postawiłby budynek dla kratki `c`, albo pusty prostokąt.
## Brama i wieża (replaces_walls) najpierw szukają miejsca bez zastępowania umocnień (luka w linii),
## a dopiero potem stawiają się na odcinkach wału albo palisady.
func placement_for(c: Vector2i, kind: int, stick: bool = false) -> Rect2i:
	var candidates := placement_candidates(c, kind, stick)
	for rect in candidates:
		if can_place(rect, kind) and trap_under(rect) < 0 and (not replaces_walls(kind) or walls_under(rect).is_empty()):
			return rect
	for rect in candidates:
		if can_place(rect, kind) and trap_under(rect) < 0:
			return rect
	return Rect2i()


## Rodzaj pułapki (TrapConfig.Kind) na którejś kratce prostokąta albo -1 (#341).
func trap_under(rect: Rect2i) -> int:
	for c: Vector2i in trap_cells:
		if rect.has_point(c):
			return trap_cells[c]
	return -1


## Rodzaj pułapki, przez którą placement_for() nie znalazł miejsca dla `kind` przy kratce `c`:
## pod pierwszym wariantem, który bez pułapki byłby wolny. -1, gdy przeszkodą jest coś innego (#341).
func trap_blocking(c: Vector2i, kind: int, stick: bool = false) -> int:
	for rect in placement_candidates(c, kind, stick):
		if can_place(rect, kind):
			var trap := trap_under(rect)
			if trap >= 0:
				return trap
	return -1


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


## Id Targu (#408) albo 0, gdy go nie ma.
func market_id() -> int:
	for id: int in kinds:
		if kinds[id] == BuildingTypes.Kind.MARKET:
			return id
	return 0


## Miejsce na Targ (#408): najbliższy wolny prostokąt 4×4 wokół Dworu (albo środka mapy, gdy Dworu nie ma),
## w stałej kolejności pierścieni (spot_around), najdalej `max_ring` kratek. Pusty prostokąt, gdy brak.
## Tak samo w nowej grze i w starym zapisie bez Targu, więc ten sam zamek dostaje zawsze to samo miejsce.
## Kratki z pułapkami (trap_cells, #341) omija jak każdy budynek (placement_for).
func market_spot(max_ring: int) -> Rect2i:
	var id := manor_id()
	if id == 0:
		return spot_near(terrain.center(), BuildingTypes.Kind.MARKET, max_ring)
	return spot_around(buildings[id], BuildingTypes.Kind.MARKET, max_ring)


## Stawia brakujący Targ (#408) na market_spot: w nowej grze po Strażnicy, w starym zapisie przy wczytaniu
## i po zwolnieniu miejsca. `true`, gdy Targ stoi (także gdy stał już wcześniej).
func place_market() -> bool:
	if market_id() != 0:
		return true
	var spot := market_spot(terrain.size)
	return spot.has_area() and place(spot, BuildingTypes.Kind.MARKET) != 0


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


## Epoka zamku (0 = epoka I): epoka Dworu, bo przejście to przebudowa Dworu (#34).
func age() -> int:
	return Ages.of_level(manor_level())


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
		if kind == BuildingTypes.Kind.TOWER and _is_palisade(c):
			return _tower_on_wall_candidates(c, size)
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


## Wieża dotknięta na odcinku umocnienia: każde położenie, które obejmuje dotkniętą kratkę, najpierw
## te, które przykrywają najwięcej odcinków (wieża w linii, nie obok niej), przy remisie w stałej
## kolejności od dotkniętej kratki jako lewego górnego rogu.
func _tower_on_wall_candidates(c: Vector2i, size: Vector2i) -> Array[Rect2i]:
	var out: Array[Rect2i] = []
	for dy in size.y:
		for dx in size.x:
			out.append(Rect2i(c - Vector2i(dx, dy), size))
	var under: Dictionary[Rect2i, int] = {}
	for r in out:
		var n := 0
		for y in range(r.position.y, r.end.y):
			for x in range(r.position.x, r.end.x):
				n += int(_is_palisade(Vector2i(x, y)))
		under[r] = n
	var sorted: Array[Rect2i] = []
	for want in range(size.x * size.y, 0, -1):
		for r in out:
			if under[r] == want:
				sorted.append(r)
	return sorted


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
			if contact == 0 or not can_place(r, kind) or trap_under(r) >= 0:
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
## z co najmniej dwoma odcinkami albo domyka krótką lukę do bramy/wieży), odcinek wskakuje w tę lukę.
## Najpierw sprawdzana jest kratka pod dotkniętą, bo tam najczęściej leży luka, w którą celował gracz.
func _wall_candidates(c: Vector2i, kind: int) -> Array[Rect2i]:
	var tapped := Rect2i(c, Vector2i.ONE)
	if is_wall_gap(c, kind):
		return [tapped]
	for d: Vector2i in [Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP]:
		var n := c + d
		if is_wall_gap(n, kind):
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
		if is_wall_gap(n, kind):
			best = n
			best_dist = dist[i]
	return best


## Czy wolna kratka `c` to luka do wypełnienia odcinkiem `kind`: łączy co najmniej dwa budynki
## albo leży na krótkiej prostej między wałem/palisadą a bramą/wieżą (do SEAL_MAX pustych).
## Przy wieży 2×2 nie uznaje „równoległej” kratki obok już podłączonego odcinka (pętla 1×1).
func is_wall_gap(c: Vector2i, kind: int) -> bool:
	if not can_place(Rect2i(c, Vector2i.ONE), kind):
		return false
	if wall_links(c, kind) >= 2 and not _tower_parallel_spur(c):
		return true
	return _anchor_line_gap(c, kind)


## Czy wolna kratka `c` to prawdziwa luka w pierścieniu umocnień (Sprawdź z Komendy, #199).
## Jak is_wall_gap, ale dwa odcinki pod kątem prostym liczą się tylko wtedy, gdy nie łączy ich już
## kratka narożna: wewnętrzny narożnik szczelnego pierścienia nie jest luką.
func is_fort_gap(c: Vector2i, kind: int) -> bool:
	if not can_place(Rect2i(c, Vector2i.ONE), kind):
		return false
	var links: Array[Vector2i] = []
	for d: Vector2i in [Vector2i.UP, Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT]:
		var other := building_at(c + d)
		if other != 0 and _connects_dir(kind, other, d):
			links.append(d)
	for i in links.size():
		for j in range(i + 1, links.size()):
			var a := links[i]
			var b := links[j]
			if a == -b:
				return true
			var corner := c + a + b
			if _joins_fort(building_at(corner)):
				continue
			# brakujący narożnik da się domknąć z obu stron przekątnej: luką jest kratka,
			# do której dochodzi prosta linia odcinków (zewnętrzny narożnik pierścienia)
			if not can_place(Rect2i(corner, Vector2i.ONE), kind) \
					or _joins_fort(building_at(c + a * 2)) or _joins_fort(building_at(c + b * 2)):
				return true
	return _anchor_line_gap(c, kind)


## Czy budynek `id` spina umocnienia (odcinek, brama albo wieża).
func _joins_fort(id: int) -> bool:
	return id != 0 and (BuildingTypes.is_wall(kinds[id]) or is_fort_anchor(kinds[id]))


## Krótka prosta (do SEAL_MAX pustych) między wałem/palisadą a bramą/wieżą przez kratkę `c`.
func _anchor_line_gap(c: Vector2i, kind: int) -> bool:
	for axis: Vector2i in [Vector2i.RIGHT, Vector2i.DOWN]:
		var forward := _gap_end(c, axis, kind)
		var back := _gap_end(c, -axis, kind)
		if forward.is_empty() or back.is_empty():
			continue
		var a: int = forward["id"]
		var b: int = back["id"]
		var empty_count: int = int(forward["empties"]) + 1 + int(back["empties"])
		if empty_count > SEAL_MAX:
			continue
		if BuildingTypes.is_wall(kinds[a]) and is_fort_anchor(kinds[b]) and _anchor_dir_ok(b, axis) \
				and not _parallel_tower_seal(c, axis, b):
			return true
		if BuildingTypes.is_wall(kinds[b]) and is_fort_anchor(kinds[a]) and _anchor_dir_ok(a, -axis) \
				and not _parallel_tower_seal(c, -axis, a):
			return true
	return false


## Z iloma sąsiednimi budynkami połączyłby się odcinek umocnienia `kind` postawiony na kratce `c`.
func wall_links(c: Vector2i, kind: int) -> int:
	var n := 0
	for d: Vector2i in [Vector2i.UP, Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT]:
		var other := building_at(c + d)
		if other == 0 or not _connects_dir(kind, other, d):
			continue
		n += 1
	return n


## Po postawieniu gotowego budynku: wał/palisada domyka lukę do bramy/wieży, a brama/wieża
## domyka luki od strony istniejących odcinków. Plac budowy (poziom 0) nie uszczelnia — dopiero
## ukończenie w kolejce (BuildQueue) albo place_kind z poziomem ≥ 1.
func seal_after_place(id: int) -> Array[int]:
	if not buildings.has(id) or levels[id] < 1:
		return []
	var kind := kinds[id]
	if BuildingTypes.is_wall(kind):
		return seal_toward_anchors(buildings[id].position, kind, levels[id])
	if is_fort_anchor(kind):
		return seal_walls_to_anchor(id)
	return []


## Domknij krótkie luki od kratki odcinka `from` w stronę bramy i wieży: stawia ten sam rodzaj
## umocnienia na pustych kratkach (1..SEAL_MAX). Nie wypełnia luk między samymi odcinkami.
## Do wieży tylko wzdłuż zamierzonego odcinka — bez domykania równoległej kratki przy jej boku.
func seal_toward_anchors(from: Vector2i, kind: int, level: int) -> Array[int]:
	var placed: Array[int] = []
	if not BuildingTypes.is_wall(kind):
		return placed
	for d: Vector2i in [Vector2i.UP, Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT]:
		var empties: Array[Vector2i] = []
		var p := from + d
		while empties.size() < SEAL_MAX and terrain.in_bounds(p) and building_at(p) == 0:
			if not can_place(Rect2i(p, Vector2i.ONE), kind):
				break
			empties.append(p)
			p += d
		if empties.is_empty():
			continue
		var end := building_at(p)
		if end == 0 or not is_fort_anchor(kinds[end]) or not _connects_dir(kind, end, d):
			continue
		if _seal_hits_parallel_tower(empties, d, end):
			continue
		for cell in empties:
			var id := place(Rect2i(cell, Vector2i.ONE), kind, level)
			if id != 0:
				placed.append(id)
	return placed


## Puste kratki będące lukami w umocnieniach (#199): `is_fort_gap` dla wału albo palisady,
## w stałej kolejności (wiersz po wierszu).
func fort_gaps() -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for y in terrain.size:
		for x in terrain.size:
			var c := Vector2i(x, y)
			if building_at(c) == 0 and is_fort_gap_any(c):
				out.append(c)
	return out


## Czy kratka `c` to luka dla wału albo palisady.
func is_fort_gap_any(c: Vector2i) -> bool:
	return is_fort_gap(c, BuildingTypes.Kind.RAMPART) or is_fort_gap(c, BuildingTypes.Kind.PALISADE)


## Rodzaj odcinka do uszczelnienia luki `c`: ten, który da się tam postawić; gdy oba, rodzaj
## sąsiednich odcinków (albo odcinka po drugiej stronie pustek do bramy/wieży), inaczej palisada.
func wall_kind_for_gap(c: Vector2i) -> int:
	var rampart_ok := is_fort_gap(c, BuildingTypes.Kind.RAMPART)
	var palisade_ok := is_fort_gap(c, BuildingTypes.Kind.PALISADE)
	if rampart_ok != palisade_ok:
		return BuildingTypes.Kind.RAMPART if rampart_ok else BuildingTypes.Kind.PALISADE
	var rampart := false
	var palisade := false
	for d: Vector2i in [Vector2i.UP, Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT]:
		var id := building_at(c + d)
		if id == 0:
			continue
		match kinds[id]:
			BuildingTypes.Kind.RAMPART:
				rampart = true
			BuildingTypes.Kind.PALISADE:
				palisade = true
	if rampart != palisade:
		return BuildingTypes.Kind.RAMPART if rampart else BuildingTypes.Kind.PALISADE
	# luka do kotwicy: ten sam rodzaj co odcinek po drugiej stronie pustek
	for axis: Vector2i in [Vector2i.RIGHT, Vector2i.DOWN]:
		for dir: Vector2i in [axis, -axis]:
			var end := _gap_end(c, dir, BuildingTypes.Kind.PALISADE)
			if not end.is_empty() and BuildingTypes.is_wall(kinds[int(end["id"])]):
				return kinds[int(end["id"])]
	return BuildingTypes.Kind.PALISADE
	# luka do kotwicy: ten sam rodzaj co odcinek po drugiej stronie pustek
	for axis: Vector2i in [Vector2i.RIGHT, Vector2i.DOWN]:
		for dir: Vector2i in [axis, -axis]:
			var end := _gap_end(c, dir, BuildingTypes.Kind.PALISADE)
			if end.is_empty():
				end = _gap_end(c, dir, BuildingTypes.Kind.RAMPART)
			if end.is_empty():
				continue
			var id: int = int(end["id"])
			if BuildingTypes.is_wall(kinds[id]):
				return kinds[id]
	if is_wall_gap(c, BuildingTypes.Kind.RAMPART) and not is_wall_gap(c, BuildingTypes.Kind.PALISADE):
		return BuildingTypes.Kind.RAMPART
	return BuildingTypes.Kind.PALISADE


## Domknij krótkie luki wału/palisady dochodzące do bramy albo wieży `anchor_id`.
func seal_walls_to_anchor(anchor_id: int) -> Array[int]:
	var placed: Array[int] = []
	if not buildings.has(anchor_id) or not is_fort_anchor(kinds[anchor_id]):
		return placed
	var wall_ids: Array[int] = []
	wall_ids.assign(buildings.keys())
	for wid in wall_ids:
		if not buildings.has(wid) or not BuildingTypes.is_wall(kinds[wid]) or levels[wid] < 1:
			continue
		placed.append_array(seal_toward_anchors(buildings[wid].position, kinds[wid], levels[wid]))
	return placed


## Id budynku na końcu prostej od `from` w kierunku `dir` (przez co najwyżej SEAL_MAX pustych
## kratek, na których da się postawić `kind`) albo pusty słownik.
func _gap_end(from: Vector2i, dir: Vector2i, kind: int) -> Dictionary:
	var p := from + dir
	var empties := 0
	while terrain.in_bounds(p) and building_at(p) == 0:
		if empties >= SEAL_MAX or not can_place(Rect2i(p, Vector2i.ONE), kind):
			return {}
		empties += 1
		p += dir
	if not terrain.in_bounds(p) or building_at(p) == 0:
		return {}
	return {"id": building_at(p), "empties": empties}


func _connects_dir(wall_kind: int, other_id: int, d: Vector2i) -> bool:
	if not BuildingTypes.connects(wall_kind, kinds[other_id]):
		return false
	return _anchor_dir_ok(other_id, d)


## Z bramą łączy się tylko odcinek leżący na jej osi (nie z boku skrzydeł).
func _anchor_dir_ok(other_id: int, d: Vector2i) -> bool:
	if kinds[other_id] != BuildingTypes.Kind.GATE:
		return true
	return (d.x == 0) == is_vertical(other_id)


## Czy uszczelnianie pustych kratek w kierunku `toward` do kotwicy domknęłoby równoległą
## kratkę przy boku wieży (pętla 1×1 obok już podłączonego odcinka).
func _seal_hits_parallel_tower(empties: Array[Vector2i], toward: Vector2i, anchor_id: int) -> bool:
	if kinds[anchor_id] != BuildingTypes.Kind.TOWER:
		return false
	for cell in empties:
		if _parallel_tower_seal(cell, toward, anchor_id):
			return true
	return false


## Kratka `c` na prostej do wieży `tower_id` (kierunek `toward_tower`) leży równolegle do
## odcinka, który już styka się z tą wieżą — auto-fill zrobiłby małą pętlę przy wieży.
func _parallel_tower_seal(c: Vector2i, toward_tower: Vector2i, tower_id: int) -> bool:
	if not buildings.has(tower_id) or kinds[tower_id] != BuildingTypes.Kind.TOWER:
		return false
	var side := Vector2i(toward_tower.y, -toward_tower.x)
	for s: Vector2i in [side, -side]:
		var n := c + s
		var wid := building_at(n)
		if wid == 0 or not BuildingTypes.is_wall(kinds[wid]):
			continue
		for td: Vector2i in [Vector2i.UP, Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT]:
			if building_at(n + td) == tower_id:
				return true
	return false


## Wolna kratka przy wieży i przy odcinku, który już łączy się z tą wieżą (kształt L) —
## to nie luka w linii, tylko równoległa kratka domykająca pętlę.
func _tower_parallel_spur(c: Vector2i) -> bool:
	for d: Vector2i in [Vector2i.UP, Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT]:
		var other := building_at(c + d)
		if other == 0 or kinds[other] != BuildingTypes.Kind.TOWER:
			continue
		if _parallel_tower_seal(c, d, other):
			return true
	return false


## Czy budynek stoi pionowo (dłuższy w osi y), np. brama w pionowej linii palisady.
func is_vertical(id: int) -> bool:
	return buildings.has(id) and buildings[id].size.y > buildings[id].size.x


## Obrys budynku `id` do rysunku (BuildingArt.make_image, `cells`): zapisany prostokąt, a dla bramy
## w pionowej linii jej obrys bez obrotu. Budynek ze starszego zapisu ma tu stary rozmiar (#340).
func cells_of(id: int) -> Vector2i:
	if not buildings.has(id):
		return Vector2i.ZERO
	var s := buildings[id].size
	return Vector2i(s.y, s.x) if kinds[id] == BuildingTypes.Kind.GATE and s.y > s.x else s


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
	if not buildings.has(id) or levels[id] >= Ages.MAX_TOTAL_LEVEL:
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
		if other == 0 or not _connects_dir(kinds[id], other, dirs[i]):
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
		levels[id] = clampi(int(e[2]), 0, Ages.MAX_TOTAL_LEVEL)
		_fill(rect, id)
		max_id = maxi(max_id, id)
	_next_id = maxi(int(d.get("next_id", 1)), max_id + 1)
	return skipped
