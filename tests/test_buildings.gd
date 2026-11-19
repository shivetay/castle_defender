extends TestCase
## Budynki epoki I: rysowanie (determinizm, paleta, poziomy, stany), autotiling umocnień,
## cache tekstur oraz ulepszanie i maski sąsiadów w siatce budowy.


func _palette_set() -> Dictionary:
	var allowed := {}
	for col: Color in Palette.AGE_I:
		allowed[col.to_rgba32()] = true
	return allowed


func test_same_input_same_pixels() -> bool:
	for kind in BuildingTypes.count():
		for state in BuildingTypes.State.size():
			var a := BuildingArt.make_image(kind, 3, state, 5)
			var b := BuildingArt.make_image(kind, 3, state, 5)
			assert_eq(a.get_data(), b.get_data(), "rodzaj %d stan %d powtarzalny" % [kind, state])
	return true


func test_every_level_looks_different() -> bool:
	for kind in BuildingTypes.count():
		var seen := {}
		# Strażnica (#177) ma jeden poziom
		var top := BuildingTypes.MAX_LEVEL if BuildingTypes.has_levels(kind) else 1
		for level in range(1, top + 1):
			var img := BuildingArt.make_image(kind, level, BuildingTypes.State.INTACT, 0b1010)
			assert_eq(img.get_size(), BuildingArt.image_size(kind), "rozmiar obrazu rodzaju %d" % kind)
			var data := img.get_data()
			assert_true(not seen.has(data), "%s: poziom %d różni się od niższych" % [BuildingTypes.NAMES[kind], level])
			seen[data] = true
	return true


## Każdy budynek MVP ma 4 różne stany na każdym poziomie, w każdym wariancie autotilingu
## i w obu ułożeniach bramy.
func test_four_distinct_states() -> bool:
	assert_eq(BuildingTypes.State.size(), 4, "cztery stany")
	for kind in BuildingTypes.count():
		var masks := 16 if BuildingTypes.is_wall(kind) else 1
		for level in range(1, BuildingTypes.MAX_LEVEL + 1):
			for mask in masks:
				for vertical: bool in ([false, true] if kind == BuildingTypes.Kind.GATE else [false]):
					var seen := {}
					for state in BuildingTypes.State.size():
						seen[BuildingArt.make_image(kind, level, state, mask, vertical).get_data()] = true
					assert_eq(seen.size(), 4, "%s poz. %d maska %d pion %s: 4 różne stany"
							% [BuildingTypes.NAMES[kind], level, mask, vertical])
	return true


## Gruz leży tylko na kratkach budynku (nic nie wystaje ponad nie), a pęknięcia i wyrwa
## nie dodają pikseli poza sylwetką całego budynku.
func test_damage_stays_inside_building() -> bool:
	for kind in BuildingTypes.count():
		for level in range(1, BuildingTypes.MAX_LEVEL + 1):
			var intact := BuildingArt.make_image(kind, level, BuildingTypes.State.INTACT, 0b1111)
			for state: int in [BuildingTypes.State.CRACKED, BuildingTypes.State.BREACHED]:
				var img := BuildingArt.make_image(kind, level, state, 0b1111)
				var added := 0
				for y in img.get_height():
					for x in img.get_width():
						if img.get_pixel(x, y).a > 0.0 and intact.get_pixel(x, y).a == 0.0:
							added += 1
				assert_eq(added, 0, "rodzaj %d poz. %d stan %d: nowe piksele poza sylwetką" % [kind, level, state])
			var rubble := BuildingArt.make_image(kind, level, BuildingTypes.State.RUBBLE, 0b1111)
			var used := intact.get_used_rect()
			var outside := 0
			for y in rubble.get_height():
				for x in rubble.get_width():
					if rubble.get_pixel(x, y).a > 0.0 and not used.has_point(Vector2i(x, y)):
						outside += 1
			assert_eq(outside, 0, "rodzaj %d poz. %d: gruz leży tam, gdzie stał budynek" % [kind, level])
	return true


## Wyrwa obniża sylwetkę: w każdym budynku jest kolumna, której wierzch leży niżej niż w całym.
func test_breach_lowers_silhouette() -> bool:
	for kind in BuildingTypes.count():
		for level in range(1, BuildingTypes.MAX_LEVEL + 1):
			var intact := BuildingArt.make_image(kind, level, BuildingTypes.State.INTACT, 0b0101)
			var breached := BuildingArt.make_image(kind, level, BuildingTypes.State.BREACHED, 0b0101)
			var lowered := false
			for x in intact.get_width():
				for y in intact.get_height():
					if intact.get_pixel(x, y).a > 0.0 and breached.get_pixel(x, y).a == 0.0:
						lowered = true
			assert_true(lowered, "%s poz. %d: wyrwa zabiera część budynku" % [BuildingTypes.NAMES[kind], level])
	return true


func test_state_follows_hp_percent() -> bool:
	var s := BuildingTypes.State
	assert_eq(BuildingTypes.state_for_hp(100, 100), s.INTACT, "100%")
	assert_eq(BuildingTypes.state_for_hp(76, 100), s.INTACT, "76%")
	assert_eq(BuildingTypes.state_for_hp(75, 100), s.CRACKED, "75%")
	assert_eq(BuildingTypes.state_for_hp(41, 100), s.CRACKED, "41%")
	assert_eq(BuildingTypes.state_for_hp(40, 100), s.BREACHED, "40%")
	assert_eq(BuildingTypes.state_for_hp(1, 1000), s.BREACHED, "0,1% to jeszcze nie gruz")
	assert_eq(BuildingTypes.state_for_hp(0, 100), s.RUBBLE, "0%")
	assert_eq(BuildingTypes.state_for_hp(-5, 100), s.RUBBLE, "ujemne HP")
	assert_eq(BuildingTypes.state_for_hp(150, 100), s.INTACT, "HP ponad maksimum")
	assert_eq(BuildingTypes.state_for_hp(10, 0), s.RUBBLE, "brak maksimum")
	# stan nigdy nie poprawia się, gdy HP spada
	var last := s.INTACT
	for hp in range(300, -1, -1):
		var st := BuildingTypes.state_for_hp(hp, 300)
		assert_true(st >= last, "HP %d/300: stan nie cofa się" % hp)
		last = st
	return true


func test_age_palette_has_12_to_16_colors() -> bool:
	var unique := _palette_set()
	assert_eq(unique.size(), Palette.AGE_I.size(), "kolory epoki się nie powtarzają")
	assert_true(Palette.AGE_I.size() >= 12 and Palette.AGE_I.size() <= 16, "12–16 kolorów epoki I")
	for group: Array in [Palette.GRASS, Palette.WOOD, Palette.EARTH, Palette.THATCH, Palette.WATER]:
		for col: Color in group:
			assert_true(unique.has(col.to_rgba32()), "rampa należy do palety epoki")
	for col: Color in [Palette.SHADOW, Palette.ACCENT]:
		assert_true(unique.has(col.to_rgba32()), "cień i akcent należą do palety epoki")
	return true


func test_only_palette_colors() -> bool:
	var allowed := _palette_set()
	for kind in BuildingTypes.count():
		for level in range(1, BuildingTypes.MAX_LEVEL + 1):
			for state in BuildingTypes.State.size():
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
	# poziomy 0–5 (0 = plac budowy): wał i palisada w 16 maskach, brama w dwóch ułożeniach,
	# a pozostałe rodzaje (wieża, chata, dwór, wytwórcy) po jednym wariancie; chata i warsztaty
	# na poziomach 1–5 dodatkowo jako przybudówki z 4 stron (#149)
	var others := BuildingTypes.count() - 3
	var leaning := 0
	for kind in BuildingTypes.count():
		if BuildingArt.can_lean(kind):
			leaning += 1
	assert_eq(tx.cached_count(), 6 * (2 * 16 + 2 + others) + 5 * 4 * leaning,
			"warm_up rysuje wszystkie całe warianty, place budowy i przybudówki")
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
	# wał obok palisady łączy się z nią (mieszana linia bez szpar)
	var rampart := grid.place_kind(origin + Vector2i(1, 1), BuildingTypes.Kind.RAMPART)
	assert_eq(grid.wall_mask(rampart), BuildingTypes.N | BuildingTypes.W, "wał łączy się z palisadą")
	assert_eq(grid.wall_mask(east), BuildingTypes.W | BuildingTypes.S, "palisada łączy się z wałem")
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
		for x in range(2, map.size - 7):
			if grid.can_place(Rect2i(x, y, 5, 3)):
				origin = Vector2i(x, y)
				break
		if origin.x >= 0:
			break
	var wall := grid.place_kind(origin, BuildingTypes.Kind.PALISADE)
	var gate := grid.place_kind(origin + Vector2i(1, 0), BuildingTypes.Kind.GATE)
	var after := grid.place_kind(origin + Vector2i(4, 0), BuildingTypes.Kind.PALISADE)
	assert_true(gate > 0, "brama 3×1 postawiona w linii")
	assert_eq(grid.buildings[gate], Rect2i(origin + Vector2i(1, 0), Vector2i(3, 1)), "brama dosunięta do palisady")
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
	var o := _free_area(grid, Vector2i(3, 7))
	assert_true(o.x >= 0, "wolne miejsce 3×7")
	var c := o + Vector2i(1, 0)
	for dy: int in [0, 1, 5, 6]:
		grid.place_kind(c + Vector2i(0, dy), BuildingTypes.Kind.PALISADE)
	# dotknięta dolna kratka luki: brama dosuwa się w górę i staje pionowo
	var gate := grid.place_kind(c + Vector2i(0, 4), BuildingTypes.Kind.GATE)
	assert_true(gate > 0, "brama postawiona")
	assert_eq(grid.buildings[gate], Rect2i(c + Vector2i(0, 2), Vector2i(1, 3)), "brama pionowa w luce")
	assert_true(grid.is_vertical(gate), "is_vertical")
	var above := grid.building_at(c + Vector2i(0, 1))
	var below := grid.building_at(c + Vector2i(0, 5))
	assert_eq(grid.wall_mask(above), BuildingTypes.N | BuildingTypes.S, "palisada nad bramą łączy się w dół")
	assert_eq(grid.wall_mask(below), BuildingTypes.N | BuildingTypes.S, "palisada pod bramą łączy się w górę")
	# palisada z boku bramy pionowej się z nią nie łączy
	var side := grid.place_kind(c + Vector2i(-1, 2), BuildingTypes.Kind.PALISADE)
	assert_eq(grid.wall_mask(side), 0, "palisada obok skrzydła bramy bez połączenia")
	return true


func test_gate_snaps_into_horizontal_gap() -> bool:
	var grid := BuildGrid.new(TerrainMap.generate(1337))
	var o := _free_area(grid, Vector2i(7, 3))
	var c := o + Vector2i(0, 1)
	for dx: int in [0, 1, 5, 6]:
		grid.place_kind(c + Vector2i(dx, 0), BuildingTypes.Kind.PALISADE)
	var gate := grid.place_kind(c + Vector2i(4, 0), BuildingTypes.Kind.GATE)
	assert_eq(grid.buildings[gate], Rect2i(c + Vector2i(2, 0), Vector2i(3, 1)), "dotknięta prawa kratka luki")
	assert_true(not grid.is_vertical(gate), "brama pozioma")
	grid.remove(gate)
	var middle := grid.place_kind(c + Vector2i(3, 0), BuildingTypes.Kind.GATE)
	assert_eq(grid.buildings[middle], Rect2i(c + Vector2i(2, 0), Vector2i(3, 1)), "dotknięty środek luki")
	return true


func test_tower_gets_stubs_toward_palisade() -> bool:
	var grid := BuildGrid.new(TerrainMap.generate(1337))
	var o := _free_area(grid, Vector2i(4, 4))
	var tower := grid.place_kind(o + Vector2i(1, 1), BuildingTypes.Kind.TOWER)
	grid.place_kind(o + Vector2i(0, 1), BuildingTypes.Kind.PALISADE)
	grid.place_kind(o + Vector2i(1, 3), BuildingTypes.Kind.PALISADE)
	grid.place_kind(o + Vector2i(3, 2), BuildingTypes.Kind.RAMPART)
	var stubs := grid.wall_stubs(tower)
	assert_eq(stubs.size(), 3, "trzy wpusty: dwie palisady i wał")
	assert_true(stubs.has(Vector3i(o.x + 1, o.y + 1, BuildingTypes.W)), "wpust od zachodu")
	assert_true(stubs.has(Vector3i(o.x + 1, o.y + 2, BuildingTypes.S)), "wpust od południa")
	assert_true(stubs.has(Vector3i(o.x + 2, o.y + 2, BuildingTypes.E)), "wpust od wału na wschodzie")
	return true


func test_vertical_gate_image() -> bool:
	for level in range(1, BuildingTypes.MAX_LEVEL + 1):
		var v := BuildingArt.make_image(BuildingTypes.Kind.GATE, level, BuildingTypes.State.INTACT, 0, true)
		assert_eq(v.get_size(), Vector2i(8, 24), "rozmiar bramy pionowej 1×3")
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


## Rzut z góry: obraz ma dokładnie rozmiar kratek (nic nie wystaje na sąsiadów), a wieże i donżon
## mają dach namiotowy ze szczytem w środku. Brama poziom 3 jest symetryczna (daszki na obu słupach).
func test_top_down_fits_cells() -> bool:
	for kind in BuildingTypes.count():
		assert_eq(BuildingArt.image_size(kind), BuildingTypes.size_of(kind) * BuildingArt.CELL,
				"%s: obraz równy kratkom" % BuildingTypes.NAMES[kind])
	for kind: int in [BuildingTypes.Kind.TOWER, BuildingTypes.Kind.KEEP]:
		var img := BuildingArt.make_image(kind, 4, BuildingTypes.State.INTACT)
		var peak := img.get_pixel(8, 8)
		assert_true(Palette.WOOD.has(peak), "%s: szczyt dachu w środku" % BuildingTypes.NAMES[kind])
		assert_true(Palette.THATCH.has(img.get_pixel(5, 3)), "%s: strzecha z góry" % BuildingTypes.NAMES[kind])
	var gate := BuildingTypes.Kind.GATE
	var g3 := BuildingArt.make_image(gate, 3, BuildingTypes.State.INTACT)
	var w := g3.get_width()
	for y in g3.get_height():
		for x in w:
			assert_eq(g3.get_pixel(x, y).a > 0.0, g3.get_pixel(w - 1 - x, y).a > 0.0,
					"brama poziom 3 symetryczna w (%d, %d)" % [x, y])
	# brama pionowa to ta sama sylwetka z zamienionymi osiami
	var h := BuildingArt.make_image(gate, 4, BuildingTypes.State.INTACT)
	var v := BuildingArt.make_image(gate, 4, BuildingTypes.State.INTACT, 0, true)
	for y in h.get_height():
		for x in h.get_width():
			assert_eq(h.get_pixel(x, y).a > 0.0, v.get_pixel(y, x).a > 0.0, "brama pionowa w (%d, %d)" % [x, y])
	return true


func test_failed_gate_cursor_uses_vertical_shape() -> bool:
	var grid := BuildGrid.new(TerrainMap.generate(1337))
	var o := _free_area(grid, Vector2i(3, 6))
	var c := o + Vector2i(1, 0)
	grid.place_kind(c, BuildingTypes.Kind.PALISADE)
	assert_eq(grid.placement_candidates(c + Vector2i(0, 1), BuildingTypes.Kind.GATE)[0].size, Vector2i(1, 3),
			"pod pionową palisadą pierwszy wariant bramy jest pionowy")
	return true


## Plac budowy (poziom 0) wygląda inaczej niż poziom 1, mieści się w obrazie budynku, używa palety
## i nie wystaje ponad kratki wyżej niż rusztowanie.
func test_construction_site() -> bool:
	var allowed := _palette_set()
	for kind in BuildingTypes.count():
		for vertical: bool in ([false, true] if kind == BuildingTypes.Kind.GATE else [false]):
			var site := BuildingArt.make_image(kind, 0, BuildingTypes.State.INTACT, 0b0110, vertical)
			var built := BuildingArt.make_image(kind, 1, BuildingTypes.State.INTACT, 0b0110, vertical)
			assert_eq(site.get_size(), built.get_size(), "rodzaj %d: plac ma rozmiar budynku" % kind)
			assert_true(site.get_data() != built.get_data(), "rodzaj %d: plac różni się od poziomu 1" % kind)
			assert_true(not site.is_invisible(), "rodzaj %d: plac jest widoczny" % kind)
			for y in site.get_height():
				for x in site.get_width():
					var col := site.get_pixel(x, y)
					if col.a > 0.0:
						assert_true(allowed.has(Color(col, 1.0).to_rgba32()), "rodzaj %d: plac w palecie" % kind)
	return true


## Warsztaty od poziomu 2: dach wg kategorii (strzecha / pomost / namiot). Rekwizyty bez zmian;
## chata drwala i umocnienia nie idą tą ścieżką.
func test_workshop_roofs_by_category() -> bool:
	var level := 2
	var producer := BuildingArt.make_image(BuildingTypes.Kind.TANNERY, level, BuildingTypes.State.INTACT)
	var military := BuildingArt.make_image(BuildingTypes.Kind.BARRACKS, level, BuildingTypes.State.INTACT)
	var economy := BuildingArt.make_image(BuildingTypes.Kind.FISHER, level, BuildingTypes.State.INTACT)
	# połać korpusu (nie kalenica y=6), z dala od propsu (x=11)
	assert_true(Palette.THATCH.has(producer.get_pixel(5, 4)), "wytwórca: strzecha")
	assert_true(Palette.WOOD.has(military.get_pixel(5, 4)), "wojsko: pomost z desek")
	assert_true(not Palette.THATCH.has(military.get_pixel(5, 4)), "wojsko bez strzechy w korpusie")
	assert_true(Palette.THATCH.has(economy.get_pixel(3, 4)), "gospodarka: dach namiotowy (strzecha)")
	# stóg (korpus 10×9 od (1, 2)): kalenica tylko w środku, narożniki pod 45° najciemniejsze
	assert_true(Palette.WOOD.has(economy.get_pixel(5, 6)), "stóg: kalenica z belki w środku")
	assert_true(Palette.WOOD.has(economy.get_pixel(6, 6)), "stóg: kalenica ma 2 px")
	assert_true(Palette.THATCH.has(economy.get_pixel(2, 6)), "stóg: kalenica krótsza niż korpus")
	assert_eq(economy.get_pixel(3, 4), Palette.THATCH[0], "stóg: narożnik z lewej")
	assert_eq(economy.get_pixel(8, 4), Palette.THATCH[0], "stóg: narożnik z prawej")
	# pomost wojska w ramie z belek (wiata z poziomu 1 ma tylko dolną krawędź)
	assert_eq(military.get_pixel(10, 6), Palette.WOOD[0], "pomost: rama z belek")
	assert_true(producer.get_data() != military.get_data(), "wojsko ≠ wytwórca nawet bez patrzenia na props")
	assert_true(producer.get_data() != economy.get_data(), "gospodarka ≠ wytwórca")
	assert_true(military.get_data() != economy.get_data(), "gospodarka ≠ wojsko")
	# props bez zmian: kadź garbarni (obwódka WOOD, środek EARTH)
	assert_true(Palette.WOOD.has(producer.get_pixel(11, 5)), "garbarnia: obwódka kadzi")
	assert_true(Palette.EARTH.has(producer.get_pixel(13, 5)), "garbarnia: środek kadzi")
	# chata drwala to gospodarka, ale nie warsztat — zostaje przy strzesze dwuspadowej
	var hut := BuildingArt.make_image(BuildingTypes.Kind.LUMBER_HUT, level, BuildingTypes.State.INTACT)
	assert_true(Palette.THATCH.has(hut.get_pixel(5, 4)), "chata: strzecha jak wcześniej")
	assert_true(hut.get_data() != economy.get_data(), "chata ≠ rybak (hip)")
	return true


## Przybudówka przy murze z prawej to odbicie wariantu z lewej, ale stóg gospodarki zachowuje
## światło z lewej góry (nie robi się płaski), a pomost wojska nie ma belki ramy od strony muru.
func test_workshop_roofs_keep_light_at_wall() -> bool:
	var L := BuildingArt.Lean
	for lean: int in [L.NONE, L.WEST, L.EAST]:
		var img := BuildingArt.make_image(BuildingTypes.Kind.FISHER, 3, BuildingTypes.State.INTACT, 0, false, lean)
		var lit_west := 0
		var lit_east := 0
		var hips := 0
		for y in img.get_height():
			for x in img.get_width():
				var c := img.get_pixel(x, y)
				if c == Palette.THATCH[2]:
					if x < img.get_width() / 2:
						lit_west += 1
					else:
						lit_east += 1
				elif c == Palette.THATCH[0]:
					hips += 1
		assert_true(lit_west > lit_east, "stóg (przy murze %d): jasna połać od zachodu" % lean)
		assert_true(hips > 0, "stóg (przy murze %d): ciemne narożniki" % lean)
	# poziom 4: korpus już dochodzi do krawędzi, różnicę daje brak belki ramy od strony muru
	var plain := BuildingArt.make_image(BuildingTypes.Kind.BARRACKS, 4, BuildingTypes.State.INTACT)
	var west := BuildingArt.make_image(BuildingTypes.Kind.BARRACKS, 4, BuildingTypes.State.INTACT, 0, false, L.WEST)
	var east := BuildingArt.make_image(BuildingTypes.Kind.BARRACKS, 4, BuildingTypes.State.INTACT, 0, false, L.EAST)
	assert_true(plain.get_data() != west.get_data(), "pomost przy murze bez belki od muru")
	# korpus 11×11 od (0, 1): kolumna x=0 to belka (rozjaśniona światłem z lewej) albo deski
	assert_true(plain.get_pixel(0, 6) != west.get_pixel(0, 6), "przybudówka z lewej: deski aż do muru")
	assert_eq(west.get_pixel(0, 6), east.get_pixel(15, 6), "przybudówka z prawej: lustro z lewej")
	return true


func test_manor_is_not_on_toolbar() -> bool:
	assert_eq(BuildingTypes.buildable_count(), BuildingTypes.count() - 3, "pasek bez Dworu, donżonu i Strażnicy")
	assert_true(not BuildingTypes.BUILD_BAR.has(BuildingTypes.Kind.KEEP), "donżonu nie ma na pasku")
	assert_true(not BuildingTypes.BUILD_BAR.has(BuildingTypes.Kind.WATCHTOWER), "Strażnicy nie ma na pasku")
	assert_eq(BuildingTypes.Kind.WATCHTOWER, 23, "Strażnica za Domem zwiadowców (stare zapisy bez zmian)")
	assert_true(not BuildingTypes.BUILD_BAR.has(BuildingTypes.Kind.MANOR), "Dworu nie ma na pasku")
	assert_eq(BuildingTypes.Kind.MANOR, 5, "Dwór ma stały numer (zapisy)")
	var in_panel := 0
	for cat in BuildingTypes.CATEGORY_NAMES.size():
		in_panel += BuildingTypes.in_category(cat).size()
	assert_eq(in_panel, BuildingTypes.buildable_count(), "panel budowy pokazuje wszystkie rodzaje z paska, bez Dworu")
	assert_eq(BuildingTypes.category(BuildingTypes.Kind.MANOR), -1, "Dworu nie ma w panelu")
	return true


## Po teście na telefonie: brama może stanąć na ciągłej linii wału albo palisady i zastępuje
## odcinki pod sobą; linia łączy się z bramą po obu stronach.
func test_gate_replaces_wall_segments() -> bool:
	for wall: int in [BuildingTypes.Kind.PALISADE, BuildingTypes.Kind.RAMPART]:
		var grid := BuildGrid.new(TerrainMap.generate(1337))
		var o := _free_area(grid, Vector2i(7, 3))
		var c := o + Vector2i(0, 1)
		for dx in 7:
			grid.place_kind(c + Vector2i(dx, 0), wall)
		var before := grid.buildings.size()
		var gate := grid.place_kind(c + Vector2i(3, 0), BuildingTypes.Kind.GATE)
		assert_true(gate > 0, "brama na linii (%s)" % BuildingTypes.NAMES[wall])
		assert_eq(grid.buildings[gate], Rect2i(c + Vector2i(2, 0), Vector2i(3, 1)), "pozioma, środek na dotkniętej kratce")
		assert_eq(grid.buildings.size(), before - 3 + 1, "trzy odcinki zastąpione bramą")
		assert_eq(grid.wall_mask(grid.building_at(c + Vector2i(1, 0))) & BuildingTypes.E, BuildingTypes.E, "linia łączy się z bramą od zachodu")
		assert_eq(grid.wall_mask(grid.building_at(c + Vector2i(5, 0))) & BuildingTypes.W, BuildingTypes.W, "i od wschodu")
	return true


## Brama nie zastępuje innych budynków ani odcinków w budowie.
func test_gate_does_not_replace_other_buildings_or_pending_walls() -> bool:
	var grid := BuildGrid.new(TerrainMap.generate(1337))
	var o := _free_area(grid, Vector2i(7, 3))
	var c := o + Vector2i(0, 1)
	grid.place_kind(c + Vector2i(2, 0), BuildingTypes.Kind.LUMBER_HUT)
	assert_eq(grid.placement_for(c + Vector2i(3, 0), BuildingTypes.Kind.GATE).intersects(grid.buildings[grid.building_at(c + Vector2i(2, 0))]),
			false, "chaty nie zastępuje")
	var grid2 := BuildGrid.new(TerrainMap.generate(1337))
	var e := Economy.new(0)
	var q := BuildQueue.new()
	var c2 := _free_area(grid2, Vector2i(7, 3)) + Vector2i(0, 1)
	for dx in 2:
		assert_eq(q.order_build(grid2, e, c2 + Vector2i(dx, 0), BuildingTypes.Kind.PALISADE, 0), BuildQueue.Result.OK, "palisada w kolejce")
	assert_eq(q.order_build(grid2, e, c2 + Vector2i(1, 0), BuildingTypes.Kind.GATE, 0), BuildQueue.Result.NO_PLACE,
			"odcinki w budowie zostają")
	return true


## Po teście na telefonie: wieża, jak brama, staje na linii wału albo palisady, zastępuje odcinki pod
## sobą i łączy się z linią po obu stronach. Odcinków w budowie ani innych budynków nie zastępuje.
func test_tower_replaces_wall_segments() -> bool:
	for wall: int in [BuildingTypes.Kind.PALISADE, BuildingTypes.Kind.RAMPART]:
		var grid := BuildGrid.new(TerrainMap.generate(1337))
		var o := _free_area(grid, Vector2i(7, 3))
		var c := o + Vector2i(0, 1)
		for dx in 7:
			grid.place_kind(c + Vector2i(dx, 0), wall)
		var before := grid.buildings.size()
		var tower := grid.place_kind(c + Vector2i(3, 0), BuildingTypes.Kind.TOWER)
		assert_true(tower > 0, "wieża na linii (%s)" % BuildingTypes.NAMES[wall])
		var r := grid.buildings[tower]
		assert_eq(r, Rect2i(c + Vector2i(3, 0), Vector2i(2, 2)), "dotknięta kratka to lewy górny róg (remis 2 odcinków)")
		assert_eq(grid.walls_under(r).size(), 0, "odcinki pod wieżą zniknęły")
		assert_eq(grid.buildings.size(), before - 2 + 1, "dwa odcinki zastąpione wieżą")
		var west := grid.building_at(Vector2i(r.position.x - 1, c.y))
		var east := grid.building_at(Vector2i(r.end.x, c.y))
		assert_eq(grid.wall_mask(west) & BuildingTypes.E, BuildingTypes.E, "linia łączy się z wieżą od zachodu")
		assert_eq(grid.wall_mask(east) & BuildingTypes.W, BuildingTypes.W, "i od wschodu")
	var grid2 := BuildGrid.new(TerrainMap.generate(1337))
	var e := Economy.new(0)
	var q := BuildQueue.new()
	var c2 := _free_area(grid2, Vector2i(7, 3)) + Vector2i(0, 1)
	for dx in 2:
		assert_eq(q.order_build(grid2, e, c2 + Vector2i(dx, 0), BuildingTypes.Kind.PALISADE, 0), BuildQueue.Result.OK, "palisada w kolejce")
	assert_eq(q.order_build(grid2, e, c2, BuildingTypes.Kind.TOWER, 0), BuildQueue.Result.NO_PLACE, "odcinki w budowie zostają")
	var grid3 := BuildGrid.new(TerrainMap.generate(1337))
	var c3 := _free_area(grid3, Vector2i(7, 3)) + Vector2i(0, 1)
	var hut := grid3.place_kind(c3 + Vector2i(2, 0), BuildingTypes.Kind.LUMBER_HUT)
	assert_true(hut > 0, "chata stoi")
	assert_true(not grid3.placement_for(c3 + Vector2i(3, 0), BuildingTypes.Kind.TOWER).intersects(grid3.buildings[hut]),
			"chaty nie zastępuje")
	return true


## Wieża na pionowej linii: zastępuje 2 odcinki, a linia łączy się z nią od północy i południa.
func test_tower_on_vertical_wall_line() -> bool:
	for wall: int in [BuildingTypes.Kind.PALISADE, BuildingTypes.Kind.RAMPART]:
		var grid := BuildGrid.new(TerrainMap.generate(1337))
		var c := _free_area(grid, Vector2i(3, 7)) + Vector2i(1, 0)
		for dy in 7:
			grid.place_kind(c + Vector2i(0, dy), wall)
		var before := grid.buildings.size()
		var tower := grid.place_kind(c + Vector2i(0, 3), BuildingTypes.Kind.TOWER)
		assert_true(tower > 0, "wieża na pionowej linii (%s)" % BuildingTypes.NAMES[wall])
		var r := grid.buildings[tower]
		assert_eq(r, Rect2i(c + Vector2i(0, 3), Vector2i(2, 2)), "dotknięta kratka to lewy górny róg")
		assert_eq(grid.buildings.size(), before - 2 + 1, "dwa odcinki zastąpione wieżą")
		var north := grid.building_at(Vector2i(c.x, r.position.y - 1))
		var south := grid.building_at(Vector2i(c.x, r.end.y))
		assert_eq(grid.wall_mask(north) & BuildingTypes.S, BuildingTypes.S, "linia łączy się z wieżą od północy")
		assert_eq(grid.wall_mask(south) & BuildingTypes.N, BuildingTypes.N, "i od południa")
	return true
