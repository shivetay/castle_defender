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
	for col: Color in Palette.AGE_I:
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


## Ozdoby (#150) zależą tylko od seeda, stoją wyłącznie na trawie otoczonej trawą i jest ich
## rozsądnie dużo: kilka do kilkunastu procent kratek.
func test_decor_is_seeded_and_only_on_open_grass() -> bool:
	var map := TerrainMap.generate(42)
	var again := TerrainMap.generate(42)
	var count := 0
	for y in map.size:
		for x in map.size:
			var c := Vector2i(x, y)
			var d := TerrainRenderer.decor_at(map, c)
			assert_eq(d, TerrainRenderer.decor_at(again, c), "ten sam seed, ta sama ozdoba")
			if d == TerrainRenderer.Decor.NONE:
				continue
			count += 1
			assert_eq(map.get_tile(c), TerrainMap.Tile.GRASS, "ozdoba na trawie")
			for n: Vector2i in [c + Vector2i.UP, c + Vector2i.DOWN, c + Vector2i.LEFT, c + Vector2i.RIGHT]:
				if map.in_bounds(n):
					assert_eq(map.get_tile(n), TerrainMap.Tile.GRASS, "nie przy ścieżce ani wodzie")
	var cells := map.size * map.size
	assert_true(count > cells / 20 and count < cells / 4, "ozdób: %d z %d kratek" % [count, cells])
	return true


## Obrys i cień budynków (#150): obrys w kolorze cienia z palety, cień to sylwetka przesunięta
## w prawo w dół, półprzezroczysta, a umocnienia i brama nie mają obrysu (łączą się z murem).
func test_outline_and_shadow() -> bool:
	var K := BuildingTypes.Kind
	var img := BuildingArt.make_image(K.BARRACKS, 2, 0)
	var top := BuildingArt._column_top(img, img.get_width() / 2)
	assert_eq(img.get_pixel(img.get_width() / 2, top), Palette.SHADOW, "górny piksel sylwetki to obrys")
	assert_true(not BuildingArt.has_outline(K.PALISADE) and not BuildingArt.has_outline(K.GATE), "mury bez obrysu")
	var off := BuildingArt.shadow_offset(K.BARRACKS)
	var sh := BuildingArt.shadow_image(img, off)
	assert_eq(sh.get_size(), img.get_size() + off, "cień większy o przesunięcie")
	# najniższy pełny piksel sylwetki, licząc od prawego dolnego rogu
	var y := img.get_height() - 1
	var x := -1
	while x < 0:
		x = img.get_width() - 1
		while x >= 0 and img.get_pixel(x, y).a < 1.0:
			x -= 1
		if x < 0:
			y -= 1
	var p := sh.get_pixel(x + off.x, y + off.y)
	assert_true(p.a > 0.0 and p.a < 1.0, "cień półprzezroczysty")
	assert_eq(Color(p, 1.0), Color(Palette.SHADOW, 1.0), "cień w kolorze cienia z palety")
	return true


## Błyski na wodzie (#150, review #191): kratki wody w kubełkach po fazie, każda dokładnie raz,
## więc w tyknięciu rysują się tylko 3 kubełki zamiast całej rzeki.
func test_glint_buckets_cover_water_once() -> bool:
	var grid := BuildGrid.new(TerrainMap.generate(42))
	var view := AmbientView.new()
	view.setup(grid, BuildingTextures.new())
	var water := 0
	for y in grid.terrain.size:
		for x in grid.terrain.size:
			if grid.terrain.get_tile(Vector2i(x, y)) == TerrainMap.Tile.WATER:
				water += 1
	var seen := 0
	for i in AmbientView.GLINT_CYCLE:
		for g: Vector3i in view._glints[i]:
			assert_eq(g.z % AmbientView.GLINT_CYCLE, i, "kratka w swoim kubełku")
			seen += 1
	assert_eq(seen, water, "każda kratka wody raz")
	view.free()
	return true
