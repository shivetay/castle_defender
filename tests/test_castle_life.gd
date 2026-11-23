extends TestCase
## Życie w zamku (#36): pora dnia, trasy mieszkańców i straży oraz proporce wykrywane na teksturach.
## Trasy liczą się z siatki, więc ten sam zamek zawsze daje te same trasy.

const K := BuildingTypes.Kind


func _free_field(grid: BuildGrid) -> Vector2i:
	for y in range(2, grid.terrain.size - 16):
		for x in range(2, grid.terrain.size - 16):
			if grid.can_place(Rect2i(x, y, 14, 14)):
				return Vector2i(x, y)
	return Vector2i(-1, -1)


func _grid() -> BuildGrid:
	return BuildGrid.new(TerrainMap.generate(WorldSeed.first_playable(1337)))


func test_tint_follows_time_of_day() -> bool:
	assert_eq(AmbientView.tint_at(12 * 60), Palette.DAY_TINT, "w południe bez tintu")
	assert_eq(AmbientView.tint_at(2 * 60), Palette.NIGHT_TINT, "o 2:00 noc")
	assert_eq(AmbientView.tint_at(23 * 60 + 59), Palette.NIGHT_TINT, "przed północą noc")
	assert_eq(AmbientView.tint_at(390), Palette.DAWN_TINT, "o 6:30 świt")
	assert_eq(AmbientView.tint_at(1200), Palette.DUSK_TINT, "o 20:00 zmierzch")
	assert_eq(AmbientView.tint_at(1440 + 12 * 60), Palette.DAY_TINT, "minuta poza dobą zawija się")
	var mid := AmbientView.tint_at(345)
	assert_true(mid.b < Palette.NIGHT_TINT.b + 0.001 and mid.r > Palette.NIGHT_TINT.r, "przed świtem płynne przejście")
	for m in range(0, 1440, 15):
		var c := AmbientView.tint_at(m)
		assert_true(c.r >= Palette.NIGHT_TINT.r - 0.001 and c.r <= 1.0, "tint nie ciemniejszy niż noc (%d)" % m)
	return true


func test_villagers_stay_home_at_night() -> bool:
	assert_true(AmbientView.villagers_out(12 * 60), "w dzień na dworze")
	assert_true(not AmbientView.villagers_out(23 * 60), "w nocy w domach")
	assert_true(not AmbientView.villagers_out(3 * 60), "przed świtem w domach")
	assert_true(AmbientView.villagers_out(5 * 60), "od 5:00 wychodzą")
	return true


func test_villager_routes_avoid_buildings_and_water() -> bool:
	var grid := _grid()
	var o := _free_field(grid)
	assert_true(o.x >= 0, "wolne pole na mapie")
	for i in 3:
		grid.place(Rect2i(o + Vector2i(i * 4, 0), Vector2i(2, 2)), K.LUMBER_HUT, 2)
		grid.place(Rect2i(o + Vector2i(i * 4, 6), Vector2i(2, 2)), K.TANNERY, 3)
	grid.place(Rect2i(o + Vector2i(0, 11), Vector2i(2, 2)), K.WAREHOUSE, 0)  # plac budowy: nikt tu nie mieszka
	var routes := AmbientView.villager_routes(grid)
	assert_true(not routes.is_empty(), "przy domach ktoś chodzi")
	assert_true(routes.size() <= AmbientView.MAX_VILLAGERS, "limit mieszkańców")
	for r in routes:
		assert_true(r.y > r.x, "trasa ma co najmniej 2 kratki")
		assert_true(r.y - r.x <= 2 * AmbientView.VILLAGER_REACH, "trasa krótka")
		for x in range(r.x, r.y + 1):
			var c := Vector2i(x, r.z)
			assert_eq(grid.building_at(c), 0, "kratka %s wolna" % c)
			assert_true(grid.terrain.get_tile(c) != TerrainMap.Tile.WATER, "kratka %s nie jest wodą" % c)
	assert_eq(AmbientView.villager_routes(grid), routes, "te same trasy z tej samej siatki")
	return true


func test_patrol_walks_along_wall_line() -> bool:
	var grid := _grid()
	var o := _free_field(grid)
	for k in range(2, 12):
		grid.place(Rect2i(o + Vector2i(k, 7), Vector2i.ONE), K.PALISADE, 1)
	for k in range(2, 4):
		grid.place(Rect2i(o + Vector2i(k, 2), Vector2i.ONE), K.RAMPART, 1)  # za krótki odcinek na straż
	var paths := AmbientView.patrol_paths(grid)
	assert_eq(paths.size(), 1, "jedna trasa na jedną linię")
	var path: Array = paths[0]
	assert_eq(path.size(), 10, "strażnik przechodzi całą linię")
	var ends: Array = [o + Vector2i(2, 7), o + Vector2i(11, 7)]
	assert_true(ends.has(path[0]), "zaczyna na końcu linii")
	for i in range(1, path.size()):
		var a: Vector2i = path[i - 1]
		var b: Vector2i = path[i]
		assert_eq(absi(a.x - b.x) + absi(a.y - b.y), 1, "kolejne kratki sąsiadują")
	assert_eq(AmbientView.patrol_paths(grid), paths, "ta sama trasa z tej samej siatki")
	return true


func test_patrol_on_ring_and_under_construction() -> bool:
	var grid := _grid()
	var o := _free_field(grid)
	var ring := Rect2i(o + Vector2i(2, 2), Vector2i(5, 5))
	for y in range(ring.position.y, ring.end.y):
		for x in range(ring.position.x, ring.end.x):
			if x == ring.position.x or y == ring.position.y or x == ring.end.x - 1 or y == ring.end.y - 1:
				grid.place(Rect2i(Vector2i(x, y), Vector2i.ONE), K.RAMPART, 1)
	var paths := AmbientView.patrol_paths(grid)
	assert_eq(paths.size(), 1, "pierścień ma straż")
	assert_eq((paths[0] as Array).size(), 16, "obchodzi cały pierścień 5×5")
	var fresh := _grid()
	for k in range(2, 12):
		fresh.place(Rect2i(o + Vector2i(k, 7), Vector2i.ONE), K.PALISADE, 0)
	assert_true(AmbientView.patrol_paths(fresh).is_empty(), "na placu budowy nie ma straży")
	return true


func test_flags_found_on_textures() -> bool:
	var t := BuildingTextures.new()
	assert_eq(t.flags(K.MANOR, 5), [Vector4i(3, 6, 1, 0)], "Dwór 5: jeden czerwony proporzec, tarcze to nie flagi")
	assert_eq(t.flags(K.MANOR, 9).size(), 2, "Dwór II.4: dwa błękitne proporce")
	assert_eq((t.flags(K.MANOR, 9)[0] as Vector4i).w, 1, "w epoce II błękit")
	assert_true(t.flags(K.MANOR, 4).is_empty(), "Dwór 4 bez flagi")
	assert_true(t.flags(K.MANOR, 5, BuildingTypes.State.RUBBLE).is_empty(), "gruz nie łopocze")
	var east := t.flags(K.TANNERY, 5, BuildingTypes.State.INTACT, 0, false, BuildingArt.Lean.EAST)
	assert_eq(east.size(), 1, "przybudówka przy murze z prawej ma proporzec")
	assert_eq((east[0] as Vector4i).z, -1, "odbity proporzec łopocze na zachód")
	assert_eq(t.flags(K.TOWER, 5), t.flags(K.TOWER, 5), "wykrycie powtarzalne")
	return true
