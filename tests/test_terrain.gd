extends TestCase
## Generator terenu: determinizm, rzeka, ścieżki z mostem i renderowanie tylko z palety.

const SEEDS: Array[int] = [1, 2, 3, 7, 42, 1337, 9001, 123456]


func test_same_seed_same_terrain() -> bool:
	var a := TerrainMap.generate(1337)
	var b := TerrainMap.generate(1337)
	assert_eq(a.tiles, b.tiles, "kratki z seedem 1337")
	assert_eq(a.heights, b.heights, "wysokości z seedem 1337")
	var c := TerrainMap.generate(1338)
	assert_true(a.tiles != c.tiles or a.heights != c.heights, "inny seed daje inny teren")
	return true


func test_map_is_64x64() -> bool:
	var map := TerrainMap.generate(5)
	assert_eq(map.size, 64, "rozmiar mapy")
	assert_eq(map.tiles.size(), 64 * 64, "liczba kratek")
	return true


func test_every_seed_has_river_paths_and_bridge() -> bool:
	for s in SEEDS:
		var map := TerrainMap.generate(s)
		var counts := {}
		for t in map.tiles:
			counts[t] = int(counts.get(t, 0)) + 1
		assert_true(int(counts.get(TerrainMap.Tile.WATER, 0)) >= 64, "seed %d: rzeka" % s)
		assert_true(int(counts.get(TerrainMap.Tile.PATH, 0)) >= 40, "seed %d: ścieżki" % s)
		assert_true(int(counts.get(TerrainMap.Tile.BRIDGE, 0)) >= 1, "seed %d: most" % s)
	return true


func test_hill_top_is_buildable_and_high() -> bool:
	for s in SEEDS:
		var map := TerrainMap.generate(s)
		assert_true(map.is_buildable(map.center()), "seed %d: środek wzgórza to trawa" % s)
		assert_true(map.get_height(map.center()) >= 2, "seed %d: środek jest wysoko" % s)
		var levels := {}
		for h in map.heights:
			levels[h] = true
		assert_true(levels.size() >= 3, "seed %d: co najmniej 3 odcienie trawy" % s)
	return true


func test_paths_connect_hill_with_map_edges() -> bool:
	for s in SEEDS:
		var map := TerrainMap.generate(s)
		var start := map.center() + Vector2i(0, 4)
		var seen := {start: true}
		var queue: Array[Vector2i] = [start]
		var edges := {}
		while not queue.is_empty():
			var c: Vector2i = queue.pop_back()
			if c.y == map.size - 1:
				edges["S"] = true
			if c.x == 0 or c.x == map.size - 1:
				edges["WE"] = true
			for d: Vector2i in [Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT]:
				var n := c + d
				if map.in_bounds(n) and not seen.has(n) and _is_road(map, n):
					seen[n] = true
					queue.append(n)
				# odnoga do rzeki zaczyna się 4 kratki od środka; łączy je środek wzgórza
				elif map.in_bounds(n) and not seen.has(n) and n.distance_squared_to(map.center()) <= 16:
					seen[n] = true
					queue.append(n)
		assert_true(edges.has("S"), "seed %d: ścieżka do południowej krawędzi" % s)
		assert_true(edges.has("WE"), "seed %d: ścieżka przez most do bocznej krawędzi" % s)
	return true


func test_render_is_deterministic_and_uses_palette() -> bool:
	var map := TerrainMap.generate(42)
	var a := TerrainRenderer.render(map)
	var b := TerrainRenderer.render(TerrainMap.generate(42))
	assert_eq(a.get_size(), Vector2i(512, 512), "rozmiar obrazu")
	assert_eq(a.get_data(), b.get_data(), "ten sam seed, te same piksele")
	var allowed := {}
	for group: Array in [Palette.GRASS, Palette.EARTH, Palette.WOOD, Palette.WATER]:
		for col: Color in group:
			allowed[col.to_rgba32()] = true
	var outside := 0
	for y in range(0, a.get_height(), 3):
		for x in range(0, a.get_width(), 3):
			if not allowed.has(a.get_pixel(x, y).to_rgba32()):
				outside += 1
	assert_eq(outside, 0, "piksele spoza palety")
	return true


func _is_road(map: TerrainMap, c: Vector2i) -> bool:
	var t := map.get_tile(c)
	return t == TerrainMap.Tile.PATH or t == TerrainMap.Tile.BRIDGE
