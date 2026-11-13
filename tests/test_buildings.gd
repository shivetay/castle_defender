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
	assert_eq(tx.cached_count(), 2 * 5 * 16 + 3 * 5 + 5, "warm_up rysuje wszystkie całe warianty (z bramą pionową)")
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


func _free_area(grid: BuildGrid, size: Vector2i) -> Vector2i:
	var map := grid.terrain
	for y in range(2, map.size - size.y - 2):
		for x in range(2, map.size - size.x - 2):
			if grid.can_place(Rect2i(x, y, size.x, size.y)):
				return Vector2i(x, y)
	return Vector2i(-1, -1)


func test_gate_turns_vertical_in_vertical_palisade() -> bool:
	var grid := BuildGrid.new(TerrainMap.generate(1337))
	var o := _free_area(grid, Vector2i(3, 6))
	assert_true(o.x >= 0, "wolne miejsce 3×6")
	var c := o + Vector2i(1, 0)
	for dy: int in [0, 1, 4, 5]:
		grid.place_kind(c + Vector2i(0, dy), BuildingTypes.Kind.PALISADE)
	# dotknięta dolna kratka luki: brama dosuwa się w górę i staje pionowo
	var gate := grid.place_kind(c + Vector2i(0, 3), BuildingTypes.Kind.GATE)
	assert_true(gate > 0, "brama postawiona")
	assert_eq(grid.buildings[gate], Rect2i(c + Vector2i(0, 2), Vector2i(1, 2)), "brama pionowa w luce")
	assert_true(grid.is_vertical(gate), "is_vertical")
	var above := grid.building_at(c + Vector2i(0, 1))
	var below := grid.building_at(c + Vector2i(0, 4))
	assert_eq(grid.wall_mask(above), BuildingTypes.N | BuildingTypes.S, "palisada nad bramą łączy się w dół")
	assert_eq(grid.wall_mask(below), BuildingTypes.N | BuildingTypes.S, "palisada pod bramą łączy się w górę")
	# palisada z boku bramy pionowej się z nią nie łączy
	var side := grid.place_kind(c + Vector2i(-1, 2), BuildingTypes.Kind.PALISADE)
	assert_eq(grid.wall_mask(side), 0, "palisada obok skrzydła bramy bez połączenia")
	return true


func test_gate_snaps_into_horizontal_gap() -> bool:
	var grid := BuildGrid.new(TerrainMap.generate(1337))
	var o := _free_area(grid, Vector2i(6, 3))
	var c := o + Vector2i(0, 1)
	for dx: int in [0, 1, 4, 5]:
		grid.place_kind(c + Vector2i(dx, 0), BuildingTypes.Kind.PALISADE)
	var gate := grid.place_kind(c + Vector2i(3, 0), BuildingTypes.Kind.GATE)
	assert_eq(grid.buildings[gate], Rect2i(c + Vector2i(2, 0), Vector2i(2, 1)), "dotknięta prawa kratka luki")
	assert_true(not grid.is_vertical(gate), "brama pozioma")
	return true


func test_tower_gets_stubs_toward_palisade() -> bool:
	var grid := BuildGrid.new(TerrainMap.generate(1337))
	var o := _free_area(grid, Vector2i(4, 4))
	var tower := grid.place_kind(o + Vector2i(1, 1), BuildingTypes.Kind.TOWER)
	grid.place_kind(o + Vector2i(0, 1), BuildingTypes.Kind.PALISADE)
	grid.place_kind(o + Vector2i(1, 3), BuildingTypes.Kind.PALISADE)
	grid.place_kind(o + Vector2i(3, 2), BuildingTypes.Kind.RAMPART)
	var stubs := grid.wall_stubs(tower)
	assert_eq(stubs.size(), 2, "dwa wpusty (wał się nie liczy)")
	assert_true(stubs.has(Vector3i(o.x + 1, o.y + 1, BuildingTypes.W)), "wpust od zachodu")
	assert_true(stubs.has(Vector3i(o.x + 1, o.y + 2, BuildingTypes.S)), "wpust od południa")
	return true


func test_vertical_gate_image() -> bool:
	for level in range(1, BuildingTypes.MAX_LEVEL + 1):
		var v := BuildingArt.make_image(BuildingTypes.Kind.GATE, level, BuildingTypes.State.INTACT, 0, true)
		assert_eq(v.get_size(), Vector2i(8, 16 + BuildingArt.EXTRA[BuildingTypes.Kind.GATE]), "rozmiar bramy pionowej")
		assert_true(not v.is_invisible(), "brama pionowa poziom %d coś rysuje" % level)
	var a := BuildingArt.make_image(BuildingTypes.Kind.GATE, 1, 0, 0, true).get_data()
	var b := BuildingArt.make_image(BuildingTypes.Kind.GATE, 5, 0, 0, true).get_data()
	assert_true(a != b, "poziomy bramy pionowej się różnią")
	return true


func _row_has_pixel(img: Image, y: int) -> bool:
	for x in img.get_width():
		if img.get_pixel(x, y).a > 0.0:
			return true
	return false


## Szczyty dachów i flag muszą mieścić się w obrazie (px() po cichu ucina piksele poza nim).
## Najwyższe elementy dochodzą do wiersza 0, a wiersz 0 ma kolor ze strzechy albo flagi.
func test_tallest_parts_fit_in_image() -> bool:
	var gate := BuildingTypes.Kind.GATE
	for level: int in [4, 5]:
		var v := BuildingArt.make_image(gate, level, BuildingTypes.State.INTACT, 0, true)
		assert_true(_row_has_pixel(v, 0), "brama pionowa poziom %d: szczyt strzechy w wierszu 0" % level)
		# lewa krawędź strzechy: 16 wierszy dachu + okap; ucięty dach miałby ich mniej
		var eave := 0
		for y in v.get_height():
			if v.get_pixel(1, y) == Palette.THATCH[0]:
				eave += 1
		assert_eq(eave, 17, "brama pionowa poziom %d: cała krawędź strzechy w obrazie" % level)
	var tower := BuildingArt.make_image(BuildingTypes.Kind.TOWER, 5, BuildingTypes.State.INTACT)
	assert_true(_row_has_pixel(tower, 0), "wieża poziom 5: flaga sięga wiersza 0")
	assert_eq(tower.get_pixel(8, 0), Palette.ACCENT, "wieża poziom 5: górny wiersz proporca")
	assert_eq(tower.get_pixel(8, 1), Palette.ACCENT, "wieża poziom 5: dolny wiersz proporca (cały w obrazie)")
	# daszki słupów bramy poziom 3: symetryczne, oba w całości w obrazie
	var g3 := BuildingArt.make_image(gate, 3, BuildingTypes.State.INTACT)
	var w := g3.get_width()
	for y in g3.get_height():
		for x in w:
			assert_eq(g3.get_pixel(x, y).a > 0.0, g3.get_pixel(w - 1 - x, y).a > 0.0,
					"brama poziom 3 symetryczna w (%d, %d)" % [x, y])
	return true


func test_failed_gate_cursor_uses_vertical_shape() -> bool:
	var grid := BuildGrid.new(TerrainMap.generate(1337))
	var o := _free_area(grid, Vector2i(3, 6))
	var c := o + Vector2i(1, 0)
	grid.place_kind(c, BuildingTypes.Kind.PALISADE)
	assert_eq(grid.placement_candidates(c + Vector2i(0, 1), BuildingTypes.Kind.GATE)[0].size, Vector2i(1, 2),
			"pod pionową palisadą pierwszy wariant bramy jest pionowy")
	return true
