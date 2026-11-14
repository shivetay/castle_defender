class_name WorldSeed
extends RefCounted
## Seed terenu zamku. Każda nowa gra losuje własny seed z kryptograficznego źródła (nie z czasu),
## a potem seed zostaje w zapisie na całą grę. Wylosowany seed przechodzi walidację grywalności:
## Dwór musi zmieścić się blisko środka wzgórza, a od Dworu musi biec droga do krawędzi mapy
## z miejscem na bramę. Gdy mapa nie przechodzi, kolejne seedy wynikają deterministycznie
## z pierwszego (ten sam pierwszy seed zawsze daje ten sam wynik).

## Seedy mieszczą się w 31 bitach: JSON zapisu trzyma liczby jako double, a kolumna w bazie (#21)
## może być zwykłym `integer`.
const MAX_SEED := 0x7fffffff
## Ile seedów sprawdzić, zanim gra weźmie seed zapasowy.
const MAX_ATTEMPTS := 32
## Seed zapasowy, sprawdzony w testach. Na nim stała dotąd każda nowa gra.
const FALLBACK_SEED := 1337
## Dwór może stanąć najdalej tyle kratek od środka mapy.
const MANOR_MAX_RING := 6
## Droga do bramy zaczyna się najdalej tyle kratek od Dworu.
const ROAD_REACH := 4
## Argument wymuszający seed w wersji debug: godot --path . -- --seed=42
## Wymuszony seed omija walidację grywalności, więc da się nim uruchomić też mapę niegrywalną.
const DEBUG_ARG := "--seed="


## Seed dla nowej gry: wymuszony argumentem w wersji debug (bez walidacji), inaczej losowy
## i zwalidowany.
static func for_new_game() -> int:
	var forced := debug_override(OS.get_cmdline_user_args())
	if forced > 0 and OS.is_debug_build():
		return forced
	return first_playable(random_seed())


## Losowy seed 1..MAX_SEED z kryptograficznego źródła.
static func random_seed() -> int:
	var bytes := Crypto.new().generate_random_bytes(4)
	var value := bytes.decode_u32(0) & MAX_SEED
	return value if value != 0 else FALLBACK_SEED


## Seed z argumentu `--seed=N` albo 0, gdy go nie ma lub jest niepoprawny.
static func debug_override(args: PackedStringArray) -> int:
	for arg in args:
		if arg.begins_with(DEBUG_ARG):
			var text := arg.substr(DEBUG_ARG.length())
			if text.is_valid_int():
				var value := text.to_int()
				if value > 0 and value <= MAX_SEED:
					return value
	return 0


## Pierwszy grywalny seed z ciągu wynikającego z `first`; po MAX_ATTEMPTS próbach seed zapasowy.
static func first_playable(first: int) -> int:
	var candidate := first
	for attempt in MAX_ATTEMPTS:
		if is_playable(candidate):
			return candidate
		candidate = next_candidate(first, attempt + 1)
	return FALLBACK_SEED


## Kolejny kandydat po nieudanej próbie: deterministycznie z pierwszego seeda i numeru próby.
static func next_candidate(first: int, attempt: int) -> int:
	var value := PixelCanvas.hash2(first, attempt, 0x5eed5) & MAX_SEED
	return value if value != 0 else FALLBACK_SEED


static func is_playable(map_seed: int) -> bool:
	return is_playable_map(TerrainMap.generate(map_seed))


## Czy na mapie zmieści się Dwór i czy od niego biegnie droga do krawędzi mapy z miejscem na bramę.
static func is_playable_map(map: TerrainMap) -> bool:
	var grid := BuildGrid.new(map)
	var manor := grid.manor_spot(MANOR_MAX_RING)
	if not manor.has_area():
		return false
	grid.place(manor, BuildingTypes.Kind.MANOR)
	var near := manor.grow(ROAD_REACH)
	var seen := {}
	# stos (pop_back): przeszukanie w głąb wystarczy, bo liczy się tylko osiągalność
	var stack: Array[Vector2i] = []
	for y in range(near.position.y, near.end.y):
		for x in range(near.position.x, near.end.x):
			var c := Vector2i(x, y)
			if _is_road(map, c):
				seen[c] = true
				stack.append(c)
	var reaches_edge := false
	var has_gate_spot := false
	while not stack.is_empty():
		var c: Vector2i = stack.pop_back()
		if c.x == 0 or c.y == 0 or c.x == map.size - 1 or c.y == map.size - 1:
			reaches_edge = true
		if not has_gate_spot and grid.placement_for(c, BuildingTypes.Kind.GATE).has_area():
			has_gate_spot = true
		if reaches_edge and has_gate_spot:
			return true
		for d: Vector2i in [Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT]:
			var n := c + d
			if not seen.has(n) and _is_road(map, n):
				seen[n] = true
				stack.append(n)
	return false


static func _is_road(map: TerrainMap, c: Vector2i) -> bool:
	if not map.in_bounds(c):
		return false
	var t := map.get_tile(c)
	return t == TerrainMap.Tile.PATH or t == TerrainMap.Tile.BRIDGE
