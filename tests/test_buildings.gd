extends TestCase
## Budynki epoki I: rysowanie (determinizm, paleta, poziomy, stany), autotiling umocnień,
## cache tekstur oraz ulepszanie i maski sąsiadów w siatce budowy.


func _palette_set() -> Dictionary:
	var allowed := {}
	for group: Array in [Palette.GRASS, Palette.EARTH, Palette.WOOD, Palette.THATCH, Palette.WATER]:
		for col: Color in group:
			allowed[col.to_rgba32()] = true
	for col: Color in [Palette.SHADOW, Palette.INK, Palette.ACCENT]:
		allowed[col.to_rgba32()] = true
	return allowed


func test_same_input_same_pixels() -> bool:
	for kind in BuildingTypes.count():
		for state in 3:
			var a := BuildingArt.make_image(kind, 3, state, 5)
			var b := BuildingArt.make_image(kind, 3, state, 5)
			assert_eq(a.get_data(), b.get_data(), "rodzaj %d stan %d powtarzalny" % [kind, state])
	return true


func test_every_level_looks_different() -> bool:
	for kind in BuildingTypes.count():
		var seen := {}
		for level in range(1, BuildingTypes.MAX_LEVEL + 1):
			var img := BuildingArt.make_image(kind, level, BuildingTypes.State.INTACT, 0b1010)
			assert_eq(img.get_size(), BuildingArt.image_size(kind), "rozmiar obrazu rodzaju %d" % kind)
			var data := img.get_data()
			assert_true(not seen.has(data), "%s: poziom %d różni się od niższych" % [BuildingTypes.NAMES[kind], level])
			seen[data] = true
	return true


func test_states_differ_from_intact() -> bool:
	for kind in BuildingTypes.count():
		var intact := BuildingArt.make_image(kind, 2, BuildingTypes.State.INTACT, 0b0101).get_data()
		var damaged := BuildingArt.make_image(kind, 2, BuildingTypes.State.DAMAGED, 0b0101).get_data()
		var ruined := BuildingArt.make_image(kind, 2, BuildingTypes.State.RUINED, 0b0101).get_data()
		assert_true(damaged != intact, "rodzaj %d: uszkodzony inny niż cały" % kind)
		assert_true(ruined != intact and ruined != damaged, "rodzaj %d: zniszczony inny" % kind)
	return true


func test_only_palette_colors() -> bool:
	var allowed := _palette_set()
	for kind in BuildingTypes.count():
		for level in range(1, BuildingTypes.MAX_LEVEL + 1):
			for state in 3:
				var img := BuildingArt.make_image(kind, level, state, 0b1111)
				var outside := 0
				for y in img.get_height():
					for x in img.get_width():
						var col := img.get_pixel(x, y)
						# przezroczystość koloru z palety (cień) jest dozwolona
						if col.a > 0.0 and not allowed.has(Color(col, 1.0).to_rgba32()):
							outside += 1
				assert_eq(outside, 0, "rodzaj %d poziom %d stan %d: piksele spoza palety" % [kind, level, state])
	return true


func test_wall_shape_has_16_distinct_variants() -> bool:
	for t: int in [2, 4]:
		var seen := {}
		for mask in 16:
			seen[BuildingArt.wall_shape(mask, t)] = true
		assert_eq(seen.size(), 16, "16 różnych kształtów dla grubości %d" % t)
	return true


## Ramię w stronę sąsiada dochodzi do krawędzi kratki dokładnie tam, gdzie ramię sąsiada
## zaczyna się z drugiej strony, więc linia umocnień nie ma dziur ani przesunięć.
func test_wall_arms_meet_at_cell_edges() -> bool:
	var last := BuildingArt.CELL - 1
	for t: int in [2, 4]:
		for mask in 16:
			var f := BuildingArt.wall_shape(mask, t)
			var e := BuildingArt.wall_shape(BuildingTypes.W, t)
			var s := BuildingArt.wall_shape(BuildingTypes.N, t)
			for i in BuildingArt.CELL:
				var right := f[i * BuildingArt.CELL + last]
				var bottom := f[last * BuildingArt.CELL + i]
				if mask & BuildingTypes.E != 0:
					assert_eq(right, e[i * BuildingArt.CELL], "t%d maska %d: styk wschodni w wierszu %d" % [t, mask, i])
				else:
					assert_eq(right, 0, "t%d maska %d: bez sąsiada nic przy krawędzi E" % [t, mask])
				if mask & BuildingTypes.S != 0:
					assert_eq(bottom, s[i], "t%d maska %d: styk południowy w kolumnie %d" % [t, mask, i])
	return true


func test_texture_cache_reuses_textures() -> bool:
	var tx := BuildingTextures.new()
	var a := tx.draw_building(BuildingTypes.Kind.PALISADE, 2, BuildingTypes.State.INTACT, 3)
	var b := tx.draw_building(BuildingTypes.Kind.PALISADE, 2, BuildingTypes.State.INTACT, 3)
	assert_true(a == b, "ta sama tekstura z cache")
	var c := tx.draw_building(BuildingTypes.Kind.TOWER, 2, BuildingTypes.State.INTACT, 3)
	var d := tx.draw_building(BuildingTypes.Kind.TOWER, 2, BuildingTypes.State.INTACT, 0)
	assert_true(c == d, "maska nie ma znaczenia dla wieży")
	tx.warm_up()
	assert_eq(tx.cached_count(), 2 * 5 * 16 + 3 * 5, "warm_up rysuje wszystkie całe warianty")
	return true


func test_grid_upgrade_and_wall_masks() -> bool:
	var map := TerrainMap.generate(1337)
	var grid := BuildGrid.new(map)
	var origin := Vector2i(-1, -1)
	for y in range(2, map.size - 4):
		for x in range(2, map.size - 4):
			if grid.can_place(Rect2i(x, y, 3, 3)):
				origin = Vector2i(x, y)
				break
		if origin.x >= 0:
			break
	assert_true(origin.x >= 0, "znaleziono wolną trawę 3×3")
	# narożnik palisady: (0,0) (1,0) i (0,1)
	var corner := grid.place_kind(origin, BuildingTypes.Kind.PALISADE)
	var east := grid.place_kind(origin + Vector2i(1, 0), BuildingTypes.Kind.PALISADE)
	var south := grid.place_kind(origin + Vector2i(0, 1), BuildingTypes.Kind.PALISADE)
	assert_eq(grid.wall_mask(corner), BuildingTypes.E | BuildingTypes.S, "narożnik łączy się na E i S")
	assert_eq(grid.wall_mask(east), BuildingTypes.W, "odcinek wschodni łączy się na W")
	assert_eq(grid.wall_mask(south), BuildingTypes.N, "odcinek południowy łączy się na N")
	# wał obok palisady się z nią nie łączy
	var rampart := grid.place_kind(origin + Vector2i(1, 1), BuildingTypes.Kind.RAMPART)
	assert_eq(grid.wall_mask(rampart), 0, "wał nie łączy się z palisadą")
	assert_eq(grid.wall_mask(east), BuildingTypes.W, "palisada nie łączy się z wałem")
	grid.remove(east)
	assert_eq(grid.wall_mask(corner), BuildingTypes.S, "po rozbiórce sąsiada maska się zmienia")
	# ulepszanie do poziomu 5 i nie dalej
	assert_eq(grid.levels[corner], 1, "nowy budynek ma poziom 1")
	for i in 4:
		assert_true(grid.upgrade(corner), "ulepszenie %d" % (i + 2))
	assert_eq(grid.levels[corner], BuildingTypes.MAX_LEVEL, "poziom 5")
	assert_true(not grid.upgrade(corner), "powyżej poziomu 5 nie można")
	assert_true(not grid.upgrade(9999), "nieistniejący budynek")
	return true


func test_gate_connects_palisade_and_draw_order() -> bool:
	var map := TerrainMap.generate(1337)
	var grid := BuildGrid.new(map)
	var origin := Vector2i(-1, -1)
	for y in range(2, map.size - 4):
		for x in range(2, map.size - 6):
			if grid.can_place(Rect2i(x, y, 4, 3)):
				origin = Vector2i(x, y)
				break
		if origin.x >= 0:
			break
	var wall := grid.place_kind(origin, BuildingTypes.Kind.PALISADE)
	var gate := grid.place_kind(origin + Vector2i(1, 0), BuildingTypes.Kind.GATE)
	var after := grid.place_kind(origin + Vector2i(3, 0), BuildingTypes.Kind.PALISADE)
	assert_true(gate > 0, "brama 2×1 postawiona w linii")
	assert_eq(grid.wall_mask(wall), BuildingTypes.E, "palisada łączy się z bramą od wschodu")
	assert_eq(grid.wall_mask(after), BuildingTypes.W, "palisada łączy się z bramą od zachodu")
	var front := grid.place_kind(origin + Vector2i(0, 1), BuildingTypes.Kind.TOWER)
	var order := grid.draw_order()
	assert_eq(order[-1], front, "wieża niżej na mapie rysuje się na końcu")
	assert_eq(order.size(), 4, "wszystkie budynki w kolejności rysowania")
	return true
