extends TestCase
## Siatka budowy: walidacja miejsca, stawianie i usuwanie budynków.


func _grass_rect(map: TerrainMap, size: Vector2i) -> Rect2i:
	for y in map.size - size.y:
		for x in map.size - size.x:
			var r := Rect2i(x, y, size.x, size.y)
			if BuildGrid.new(map).can_place(r):
				return r
	return Rect2i()


func _first_cell(map: TerrainMap, tile: int) -> Vector2i:
	for y in map.size:
		for x in map.size:
			if map.get_tile(Vector2i(x, y)) == tile:
				return Vector2i(x, y)
	return Vector2i(-1, -1)


func test_place_and_remove_on_free_grass() -> bool:
	var map := TerrainMap.generate(1337)
	var grid := BuildGrid.new(map)
	var r := _grass_rect(map, Vector2i(2, 2))
	assert_true(r.has_area(), "znaleziono wolną trawę 2×2")
	var id := grid.place(r)
	assert_true(id > 0, "budynek postawiony")
	assert_eq(grid.building_at(r.position), id, "kratka zajęta przez budynek")
	assert_eq(grid.building_at(r.end - Vector2i.ONE), id, "ostatnia kratka zajęta")
	assert_eq(grid.place(r), 0, "nie można postawić drugi raz w tym samym miejscu")
	assert_eq(grid.place(Rect2i(r.position + Vector2i.ONE, r.size)), 0, "nachodzące budynki")
	assert_true(grid.remove(id), "usunięcie")
	assert_eq(grid.building_at(r.position), 0, "kratka wolna po usunięciu")
	assert_true(not grid.remove(id), "drugie usunięcie się nie udaje")
	assert_true(grid.place(r) > id, "po usunięciu miejsce znów wolne, nowe id")
	return true


func test_cannot_build_on_water_path_or_outside() -> bool:
	var map := TerrainMap.generate(1337)
	var grid := BuildGrid.new(map)
	var water := _first_cell(map, TerrainMap.Tile.WATER)
	var path := _first_cell(map, TerrainMap.Tile.PATH)
	assert_eq(grid.place(Rect2i(water, Vector2i.ONE)), 0, "woda")
	assert_eq(grid.place(Rect2i(path, Vector2i.ONE)), 0, "ścieżka")
	assert_eq(grid.place(Rect2i(-1, 5, 2, 2)), 0, "poza mapą z lewej")
	assert_eq(grid.place(Rect2i(63, 63, 2, 2)), 0, "poza mapą w rogu")
	assert_eq(grid.place(Rect2i(10, 10, 0, 2)), 0, "pusty prostokąt")
	assert_eq(grid.building_at(Vector2i(-3, 0)), 0, "building_at poza mapą")
	assert_true(grid.buildings.is_empty(), "nic nie postawiono")
	return true


## Pierwsza kratka drogi o danej osi, której oba sąsiedzi wzdłuż osi to droga, a w poprzek trawa.
func _straight_road(grid: BuildGrid, axis: Vector2i) -> Vector2i:
	var across := Vector2i(axis.y, axis.x)
	for y in grid.terrain.size:
		for x in grid.terrain.size:
			var c := Vector2i(x, y)
			if grid.road_axis(c) == axis and grid.road_axis(c + axis) == axis and grid.road_axis(c - axis) == axis \
					and grid.terrain.is_buildable(c + across) and grid.terrain.is_buildable(c - across):
				return c
	return Vector2i(-1, -1)


## Brama staje nad drogą w poprzek niej: pozioma na drodze północ–południe, pionowa na wschód–zachód.
func test_gate_spans_road_across() -> bool:
	for axis: Vector2i in [Vector2i.DOWN, Vector2i.RIGHT]:
		var grid := BuildGrid.new(TerrainMap.generate(1337))
		var c := _straight_road(grid, axis)
		assert_true(c.x >= 0, "jest prosta droga o osi %s" % axis)
		var id := grid.place_kind(c, BuildingTypes.Kind.GATE)
		assert_true(id != 0, "brama na drodze o osi %s" % axis)
		var r := grid.buildings[id]
		var across := Vector2i(axis.y, axis.x)
		assert_eq(r, Rect2i(c - across, across * 2 + Vector2i.ONE), "brama 3 kratki, droga pośrodku (oś %s)" % axis)
		assert_eq(grid.is_vertical(id), axis == Vector2i.RIGHT, "brama w poprzek drogi o osi %s" % axis)
	return true


## Brama nie leży wzdłuż drogi, a inne budynki w ogóle nie stają na drodze.
func test_road_only_for_gate_across() -> bool:
	var grid := BuildGrid.new(TerrainMap.generate(1337))
	var c := _straight_road(grid, Vector2i.DOWN)
	assert_true(not grid.can_place(Rect2i(c - Vector2i(0, 1), Vector2i(1, 3)), BuildingTypes.Kind.GATE), "pionowa brama wzdłuż drogi pionowej")
	assert_true(grid.can_place(Rect2i(c - Vector2i(1, 0), Vector2i(3, 1)), BuildingTypes.Kind.GATE), "pozioma brama w poprzek")
	for kind: int in [BuildingTypes.Kind.RAMPART, BuildingTypes.Kind.PALISADE, BuildingTypes.Kind.TOWER,
			BuildingTypes.Kind.LUMBER_HUT]:
		assert_eq(grid.place_kind(c, kind), 0, "%s nie staje na drodze" % BuildingTypes.NAMES[kind])
	assert_true(not grid.can_place(Rect2i(c - Vector2i(1, 0), Vector2i(3, 1))), "bez rodzaju droga jest zajęta jak dawniej")
	return true


func test_gate_never_on_water_or_bridge() -> bool:
	var grid := BuildGrid.new(TerrainMap.generate(1337))
	for y in grid.terrain.size:
		for x in grid.terrain.size:
			var c := Vector2i(x, y)
			var t := grid.terrain.get_tile(c)
			if t == TerrainMap.Tile.WATER or t == TerrainMap.Tile.BRIDGE:
				assert_true(not grid.can_place(Rect2i(c - Vector2i(1, 0), Vector2i(3, 1)), BuildingTypes.Kind.GATE), "brama pozioma na %s" % c)
				assert_true(not grid.can_place(Rect2i(c - Vector2i(0, 1), Vector2i(1, 3)), BuildingTypes.Kind.GATE), "brama pionowa na %s" % c)
	return true


func _free_area(grid: BuildGrid, size: Vector2i) -> Vector2i:
	for y in range(2, grid.terrain.size - size.y - 2):
		for x in range(2, grid.terrain.size - size.x - 2):
			if grid.can_place(Rect2i(x, y, size.x, size.y)):
				return Vector2i(x, y)
	return Vector2i(-1, -1)


## Wał i palisada łączą się ze sobą, więc mieszana linia nie ma szpar (zgłoszenie z telefonu).
func test_rampart_and_palisade_connect() -> bool:
	var grid := BuildGrid.new(TerrainMap.generate(1337))
	var o := _free_area(grid, Vector2i(6, 3)) + Vector2i(0, 1)
	var r1 := grid.place_kind(o, BuildingTypes.Kind.RAMPART)
	var p1 := grid.place_kind(o + Vector2i(1, 0), BuildingTypes.Kind.PALISADE)
	var r2 := grid.place_kind(o + Vector2i(2, 0), BuildingTypes.Kind.RAMPART)
	var tower := grid.place_kind(o + Vector2i(3, 0), BuildingTypes.Kind.TOWER)
	assert_eq(grid.wall_mask(r1), BuildingTypes.E, "wał łączy się z palisadą")
	assert_eq(grid.wall_mask(p1), BuildingTypes.E | BuildingTypes.W, "palisada łączy się z wałami po obu stronach")
	assert_eq(grid.wall_mask(r2), BuildingTypes.E | BuildingTypes.W, "wał łączy się z palisadą i wieżą")
	assert_true(grid.wall_stubs(tower).has(Vector3i(o.x + 3, o.y, BuildingTypes.W)), "wieża dostaje wpust od wału")
	return true


## Luka w linii palisady: dotknięcie kratki nad luką (tam, gdzie widać wierzch palisady) albo obok
## stawia odcinek w luce. Bez luki odcinek staje tam, gdzie dotknięto.
func test_wall_snaps_into_gap() -> bool:
	for kind: int in [BuildingTypes.Kind.PALISADE, BuildingTypes.Kind.RAMPART]:
		var grid := BuildGrid.new(TerrainMap.generate(1337))
		var o := _free_area(grid, Vector2i(5, 4)) + Vector2i(0, 1)
		grid.place_kind(o, BuildingTypes.Kind.PALISADE)
		grid.place_kind(o + Vector2i(2, 0), BuildingTypes.Kind.PALISADE)
		var gap := o + Vector2i(1, 0)
		assert_eq(grid.wall_links(gap, kind), 2, "luka łączy dwa odcinki")
		var id := grid.place_kind(gap + Vector2i.UP, kind)
		assert_eq(grid.buildings[id].position, gap, "%s: dotknięcie nad luką wypełnia lukę" % BuildingTypes.NAMES[kind])
		assert_eq(grid.wall_mask(id), BuildingTypes.E | BuildingTypes.W, "linia ciągła")
		# luka zapełniona: kolejne dotknięcie nad linią stawia odcinek tam, gdzie dotknięto
		var above := grid.place_kind(gap + Vector2i.UP, kind)
		assert_eq(grid.buildings[above].position, gap + Vector2i.UP, "bez luki brak przeskoku")
	# luka pionowa: dotknięcie z boku
	var g := BuildGrid.new(TerrainMap.generate(1337))
	var v := _free_area(g, Vector2i(4, 5)) + Vector2i(1, 0)
	g.place_kind(v, BuildingTypes.Kind.PALISADE)
	g.place_kind(v + Vector2i(0, 2), BuildingTypes.Kind.PALISADE)
	var side := g.place_kind(v + Vector2i(1, 1), BuildingTypes.Kind.PALISADE)
	assert_eq(g.buildings[side].position, v + Vector2i(0, 1), "dotknięcie z boku wypełnia lukę pionową")
	return true


## Pojedynczy odcinek obok innego (jedno połączenie) to nie luka: nie ma przeskoku.
func test_wall_extends_line_where_tapped() -> bool:
	var grid := BuildGrid.new(TerrainMap.generate(1337))
	var o := _free_area(grid, Vector2i(4, 4)) + Vector2i(1, 1)
	grid.place_kind(o, BuildingTypes.Kind.PALISADE)
	var next := grid.place_kind(o + Vector2i(0, -1) + Vector2i(1, 0), BuildingTypes.Kind.PALISADE)
	assert_eq(grid.buildings[next].position, o + Vector2i(1, -1), "jedno połączenie obok: stawiamy w dotkniętej kratce")
	return true
