class_name BotCastle
extends RefCounted
## Zamek-cel do ataku (#17) i zamek-bot z listy BotRoster (#26): gród z seeda. Dwór i donżon
## w pierścieniu palisady albo wału (BotRoster.inner_wall_of) z bramą od strony drogi, wieże, budynki gospodarcze i rekrutacji poza
## pierścieniem, od zamku 11 zewnętrzny wał, oraz załoga. `strength` (numer zamku na liście, 0–19)
## wybiera wszystko z BotRoster. Ten sam seed i siła dają zawsze ten sam zamek. Liczby TYMCZASOWE.

const K := BuildingTypes.Kind
const U := UnitTypes.Unit

var seed_value := 0
var strength := 0
## Numer zamku na liście BotRoster (0–19).
var index := 0
var grid: BuildGrid
## Id donżonu: cel ataku.
var objective := 0
## Miejsce wejścia atakującego (droga przy krawędzi mapy), środek strefy rozstawienia.
var spawn := Vector2i.ZERO
## Załoga: oddziały [rodzaj, liczba] jak w Battle.create_squads.
var defenders: Array = []


## Seed zamku numer `index` dla gracza z `world_seed` (inny niż seed jego zamku i fal PvE).
## Tylko testy i starszy kod: Wyprawa w grze używa wspólnej listy BotRoster.seed_of (#26), więc
## nie podpinaj tu z powrotem seeda świata gracza.
static func seed_for(world_seed: int, index: int) -> int:
	return PixelCanvas.hash2(world_seed, index, 0xb07) & 0x7fffffff


static func generate(seed_value: int, strength: int = 0) -> BotCastle:
	var bot := BotCastle.new()
	bot.seed_value = seed_value
	bot.strength = maxi(0, strength)
	var terrain := TerrainMap.generate(WorldSeed.first_playable(seed_value))
	var grid := BuildGrid.new(terrain)
	bot.grid = grid
	var level := BotRoster.level_of(bot.strength)
	var manor := grid.place(grid.manor_spot(WorldSeed.MANOR_MAX_RING), K.MANOR, level)
	bot.objective = grid.place(grid.keep_spot(WorldSeed.KEEP_MAX_RING), K.KEEP, level)
	bot.spawn = edge_road(terrain)
	var inner := grid.buildings[manor] if manor != 0 else Rect2i(terrain.center(), Vector2i.ONE)
	if bot.objective != 0:
		inner = inner.merge(grid.buildings[bot.objective])
	var ring := inner.grow(2)
	var gx := _place_ring(grid, ring, level, bot.spawn, BotRoster.inner_wall_of(bot.strength), true)
	if bot.strength >= BotRoster.OUTER_WALL_FROM:
		# zewnętrzny wał 2 kratki dalej, z przejściem na wprost bramy
		_place_ring(grid, ring.grow(2), level, bot.spawn, K.RAMPART, false, gx)
	for i in BotRoster.towers_of(bot.strength):
		grid.place(grid.spot_around(ring, K.TOWER, 3), K.TOWER, level)
	var kinds: Array[int] = [K.LUMBER_HUT, K.HUNTER, K.LUMBER_HUT]
	kinds.append_array(BotRoster.recruit_buildings(bot.strength))
	for kind in kinds:
		grid.place(grid.spot_around(ring, kind, 6), kind, level)
	bot.defenders = BotRoster.defenders(bot.strength)
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


## Pierścień umocnień `kind` po brzegu `ring` z bramą 3×1 (albo przejściem bez bramy) w boku od strony
## wejścia (górnym albo dolnym). Kratki z wodą i poza mapą zostają luką (tam i tak nikt nie przejdzie),
## a zajęte przez inny budynek zamyka ten budynek. Droga, która przecina pierścień, dostaje odcinek
## umocnienia mimo drogi (BuildGrid.place_on_any_ground), więc pierścień z bramą jest szczelny (w zamku 1
## droga zostawiała lukę, przez którą wchodzili Chłopi). Bez drugiej bramy, żeby gwiazdka „Brama
## zdobyta” nie przychodziła łatwiej z boku (review #200).
## `gate_x` < 0: brama na środku boku. Zwraca lewą kolumnę bramy.
static func _place_ring(grid: BuildGrid, ring: Rect2i, level: int, spawn: Vector2i, kind: int = K.PALISADE,
		gate: bool = true, gate_x: int = -1) -> int:
	var gate_y := ring.position.y if spawn.y < ring.get_center().y else ring.end.y - 1
	@warning_ignore("integer_division")
	var gx := ring.position.x + ring.size.x / 2 - 1 if gate_x < 0 else gate_x
	var holes: Array[Vector2i] = []
	for y in range(ring.position.y, ring.end.y):
		for x in range(ring.position.x, ring.end.x):
			var edge := y == ring.position.y or y == ring.end.y - 1 or x == ring.position.x or x == ring.end.x - 1
			var c := Vector2i(x, y)
			var in_gate := y == gate_y and x >= gx and x < gx + 3
			if not edge or (in_gate and gate):
				continue
			if in_gate or not grid.terrain.in_bounds(c) or grid.terrain.get_tile(c) == TerrainMap.Tile.WATER \
					or grid.building_at(c) != 0:
				continue  # przejście bez bramy (zewnętrzny wał), woda, krawędź mapy albo inny budynek
			if grid.place(Rect2i(c, Vector2i.ONE), kind, level) == 0:
				holes.append(c)
	if gate:
		if grid.place(Rect2i(gx, gate_y, 3, 1), K.GATE, level) == 0:
			for i in 3:
				holes.append(Vector2i(gx + i, gate_y))
	for c in holes:
		grid.place_on_any_ground(Rect2i(c, Vector2i.ONE), kind, level)
	return gx
