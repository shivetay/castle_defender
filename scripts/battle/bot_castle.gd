class_name BotCastle
extends RefCounted
## Zamek-cel do ataku (#17), zanim będzie PvP (etap 9) i 20 zamków-botów (#26): prosty gród
## z seeda. Dwór i donżon w pierścieniu palisady z bramą od strony drogi, wieże i budynki
## gospodarcze poza pierścieniem oraz załoga. `strength` (ile zamków gracz już zdobył) dodaje
## poziomy, wieże i obrońców. Ten sam seed i siła dają zawsze ten sam zamek. Liczby TYMCZASOWE.

const K := BuildingTypes.Kind
const U := UnitTypes.Unit

var seed_value := 0
var strength := 0
var grid: BuildGrid
## Id donżonu: cel ataku.
var objective := 0
## Miejsce wejścia atakującego (droga przy krawędzi mapy), środek strefy rozstawienia.
var spawn := Vector2i.ZERO
## Załoga: oddziały [rodzaj, liczba] jak w Battle.create_squads.
var defenders: Array = []


## Seed zamku numer `index` dla gracza z `world_seed` (inny niż seed jego zamku i fal PvE).
static func seed_for(world_seed: int, index: int) -> int:
	return PixelCanvas.hash2(world_seed, index, 0xb07) & 0x7fffffff


static func generate(seed_value: int, strength: int = 0) -> BotCastle:
	var bot := BotCastle.new()
	bot.seed_value = seed_value
	bot.strength = maxi(0, strength)
	var terrain := TerrainMap.generate(WorldSeed.first_playable(seed_value))
	var grid := BuildGrid.new(terrain)
	bot.grid = grid
	@warning_ignore("integer_division")
	var level := clampi(1 + bot.strength / 2, 1, BuildingTypes.MAX_LEVEL)
	var manor := grid.place(grid.manor_spot(WorldSeed.MANOR_MAX_RING), K.MANOR, level)
	bot.objective = grid.place(grid.keep_spot(WorldSeed.KEEP_MAX_RING), K.KEEP, level)
	bot.spawn = edge_road(terrain)
	var inner := grid.buildings[manor] if manor != 0 else Rect2i(terrain.center(), Vector2i.ONE)
	if bot.objective != 0:
		inner = inner.merge(grid.buildings[bot.objective])
	var ring := inner.grow(2)
	_place_ring(grid, ring, level, bot.spawn)
	for i in mini(2, bot.strength):
		grid.place(grid.spot_around(ring, K.TOWER, 3), K.TOWER, level)
	for kind: int in [K.LUMBER_HUT, K.HUNTER, K.LUMBER_HUT]:
		grid.place(grid.spot_around(ring, kind, 6), kind, level)
	bot.defenders = [[U.PEASANT, 4 + 2 * bot.strength]]
	if bot.strength >= 1:
		bot.defenders.append([U.ARCHER, 2 + bot.strength])
	if bot.strength >= 2:
		bot.defenders.append([U.AXE_WARRIOR, 2 * bot.strength])
	return bot


## Pierwsza kratka drogi na krawędzi mapy (kolejność stała), a bez drogi środek dolnej krawędzi.
static func edge_road(terrain: TerrainMap) -> Vector2i:
	var last := terrain.size - 1
	for i in terrain.size:
		for c: Vector2i in [Vector2i(i, last), Vector2i(i, 0), Vector2i(0, i), Vector2i(last, i)]:
			if terrain.get_tile(c) == TerrainMap.Tile.PATH:
				return c
	@warning_ignore("integer_division")
	return Vector2i(terrain.size / 2, last - 1)


## Pierścień palisady po brzegu `ring` z bramą 3×1 w boku od strony wejścia (górnym albo dolnym).
## Kratki z wodą, poza mapą i zajęte zostają luką w pierścieniu.
static func _place_ring(grid: BuildGrid, ring: Rect2i, level: int, spawn: Vector2i) -> void:
	var gate_y := ring.position.y if spawn.y < ring.get_center().y else ring.end.y - 1
	@warning_ignore("integer_division")
	var gx := ring.position.x + ring.size.x / 2 - 1
	for y in range(ring.position.y, ring.end.y):
		for x in range(ring.position.x, ring.end.x):
			var edge := y == ring.position.y or y == ring.end.y - 1 or x == ring.position.x or x == ring.end.x - 1
			if not edge or (y == gate_y and x >= gx and x < gx + 3):
				continue
			var c := Vector2i(x, y)
			if not grid.terrain.in_bounds(c) or grid.terrain.get_tile(c) == TerrainMap.Tile.WATER or grid.building_at(c) != 0:
				continue
			grid.place(Rect2i(c, Vector2i.ONE), K.PALISADE, level)
	grid.place(Rect2i(gx, gate_y, 3, 1), K.GATE, level)
