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
