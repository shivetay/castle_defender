extends TestCase
## Budynek przyklejany do murów (#149): stawiany przez gracza przy wale albo palisadzie dosuwa się do
## linii umocnień bokiem, rysuje się jako przybudówka z dachem jednospadowym (wyżej przy murze) i bez
## szpary na styku.

const K := BuildingTypes.Kind
const L := BuildingArt.Lean


## Lewy górny róg wolnego pola trawy 14×14 na mapie z seeda (w stałej kolejności) i siatka z linią
## 10 odcinków palisady przez środek pola: poziomą (wiersz o.y + 7) albo pionową (kolumna o.x + 7).
var o := Vector2i.ZERO


func _grid(horizontal: bool) -> BuildGrid:
	var grid := BuildGrid.new(TerrainMap.generate(WorldSeed.first_playable(1337)))
	o = _free_field(grid)
	for k in range(2, 12):
		var c := o + (Vector2i(k, 7) if horizontal else Vector2i(7, k))
		grid.place(Rect2i(c, Vector2i.ONE), K.PALISADE, 1)
	return grid


func _free_field(grid: BuildGrid) -> Vector2i:
	for y in range(2, grid.terrain.size - 16):
		for x in range(2, grid.terrain.size - 16):
			if grid.can_place(Rect2i(x, y, 14, 14)):
				return Vector2i(x, y)
	return Vector2i(-1, -1)


func test_sticks_to_horizontal_wall_on_both_sides() -> bool:
	var grid := _grid(true)
	# palec kratkę pod linią, ale z odstępem: budynek dosuwa się w górę, do muru
	assert_true(o.x >= 0, "wolne pole na mapie")
	var below := grid.placement_for(o + Vector2i(4, 9), K.TANNERY, true)
	assert_eq(below.position.y, o.y + 8, "pod murem: górny bok przy linii")
	assert_eq(grid.wall_contact(below), 2, "cały bok przylega")
	var above := grid.placement_for(o + Vector2i(4, 4), K.TANNERY, true)
	assert_eq(above.end.y, o.y + 7, "nad murem: dolny bok przy linii")
	assert_eq(grid.wall_contact(above), 2, "cały bok przylega")
	assert_eq(grid.placement_for(o + Vector2i(4, 9), K.TANNERY), Rect2i(o + Vector2i(4, 9), Vector2i(2, 2)),
			"bez stick (generator) jak dotąd")
	assert_eq(grid.placement_for(o + Vector2i(4, 9), K.TANNERY, true), below, "deterministycznie")
	var far := grid.placement_for(o + Vector2i(4, 11), K.TANNERY, true)
	assert_eq(far, Rect2i(o + Vector2i(4, 11), Vector2i(2, 2)), "daleko od muru: bez przyklejania")
	return true


func test_sticks_to_vertical_wall_and_not_onto_it() -> bool:
	var grid := _grid(false)
	assert_true(o.x >= 0, "wolne pole na mapie")
	var right := grid.placement_for(o + Vector2i(9, 4), K.TANNERY, true)
	assert_eq(right.position.x, o.x + 8, "z prawej: lewy bok przy linii")
	var left := grid.placement_for(o + Vector2i(4, 4), K.TANNERY, true)
	assert_eq(left.end.x, o.x + 7, "z lewej: prawy bok przy linii")
	for r: Rect2i in [right, left]:
		for y in range(r.position.y, r.end.y):
			for x in range(r.position.x, r.end.x):
				assert_true(grid.building_at(Vector2i(x, y)) == 0, "nie wchodzi na mur")
	# wieża łączy się z linią umocnień, więc się nie przykleja
	var tower := grid.placement_for(o + Vector2i(9, 2), K.TOWER, true)
	assert_eq(tower, Rect2i(o + Vector2i(9, 2), Vector2i(2, 2)), "wieża stoi tam, gdzie dotknięto")
	return true


func test_wall_side_and_lean() -> bool:
	var grid := _grid(true)
	var below := grid.place(grid.placement_for(o + Vector2i(4, 9), K.BARRACKS, true), K.BARRACKS, 1)
	var above := grid.place(grid.placement_for(o + Vector2i(7, 4), K.LUMBER_HUT, true), K.LUMBER_HUT, 1)
	assert_eq(grid.wall_side(below)[0], Vector2i.UP, "mur nad budynkiem")
	assert_eq(grid.wall_side(above)[0], Vector2i.DOWN, "mur pod budynkiem")
	assert_eq(CastleView.lean_of(grid, below), L.NORTH, "przybudówka od północy")
	assert_eq(CastleView.lean_of(grid, above), L.SOUTH, "przybudówka od południa")
	var lone := grid.place(Rect2i(o + Vector2i(11, 11), Vector2i(2, 2)), K.BARRACKS, 1)
	assert_eq(CastleView.lean_of(grid, lone), L.NONE, "bez muru zwykły budynek")
	for kind: int in [K.MANOR, K.KEEP, K.TOWER, K.GATE, K.PALISADE, K.RAMPART, K.FLAX_FIELD]:
		assert_true(not BuildingArt.can_lean(kind), "%s ma własny kształt" % BuildingTypes.NAMES[kind])
	assert_true(BuildingArt.can_lean(K.LUMBER_HUT) and BuildingArt.can_lean(K.BARRACKS), "chata i warsztaty")
	return true


## Przybudówka ma inny dach niż zwykły budynek, sylwetka przy murze z prawej to lustro wariantu z lewej
## (światło pada zawsze z lewej góry, więc kolory się różnią),
## a u wytwórcy z góry korpus dochodzi do muru z kalenicą tuż przy nim (dach jednospadowy).
## Wojsko sprawdza samą zmianę obrysu (dach to pomost, nie strzecha).
func test_lean_to_art() -> bool:
	for level in range(1, BuildingTypes.MAX_LEVEL + 1):
		var plain := BuildingArt.make_image(K.BARRACKS, level, 0)
		var west := BuildingArt.make_image(K.BARRACKS, level, 0, 0, false, L.WEST)
		var east := BuildingArt.make_image(K.BARRACKS, level, 0, 0, false, L.EAST)
		assert_true(plain.get_data() != west.get_data(), "poziom %d: przybudówka inna niż zwykły" % level)
		west.flip_x()
		assert_eq(_alpha(west), _alpha(east), "poziom %d: z prawej sylwetka to lustro z lewej" % level)
		var north := BuildingArt.make_image(K.BARRACKS, level, 0, 0, false, L.NORTH)
		assert_true(plain.get_data() != north.get_data(), "poziom %d: połać od muru z tyłu" % level)
	# wytwórca przy murze: strzecha jednospadowa (kalenica WOOD, połać THATCH)
	var img := BuildingArt.make_image(K.TANNERY, 3, 0, 0, false, L.WEST)
	var plain3 := BuildingArt.make_image(K.TANNERY, 3, 0)
	assert_true(not Palette.WOOD.has(plain3.get_pixel(0, 6)), "zwykły budynek z odstępem od krawędzi")
	assert_true(Palette.WOOD.has(img.get_pixel(0, 6)), "kalenica przy murze z lewej")
	assert_true(Palette.THATCH.has(img.get_pixel(5, 6)), "połać opada od muru")
	var t := BuildingTextures.new()
	assert_true(BuildingTextures.key(K.BARRACKS, 3, 0, 0, false, L.WEST) != BuildingTextures.key(K.BARRACKS, 3, 0, 0, false, L.EAST),
			"osobne klucze cache")
	assert_true(t.draw_building(K.MANOR, 2, 0, 0, false, L.WEST) == t.draw_building(K.MANOR, 2), "Dwór bez przybudówki")
	return true


## Na styku nie ma szpary: po przesunięciu zamalowana część budynku dotyka zamalowanej części muru,
## z każdej strony (najwyżej o MAX_ATTACH_SHIFT px).
func test_no_gap_at_the_seam() -> bool:
	var t := BuildingTextures.new()
	for horizontal: bool in [true, false]:
		var grid := _grid(horizontal)
		var taps: Array[Vector2i] = []
		if horizontal:
			taps.assign([o + Vector2i(4, 9), o + Vector2i(4, 4)])
		else:
			taps.assign([o + Vector2i(9, 4), o + Vector2i(4, 4)])
		for tap in taps:
			var id := grid.place(grid.placement_for(tap, K.BARRACKS, true), K.BARRACKS, 1)
			var side: Array = grid.wall_side(id)
			var dir: Vector2i = side[0]
			assert_true(dir != Vector2i.ZERO, "przyklejony")
			var off := CastleView.attach_offset(grid, t, id)
			assert_true(absi(off.x) + absi(off.y) <= CastleView.MAX_ATTACH_SHIFT, "przesunięcie w granicy")
			var lean := CastleView.lean_of(grid, id)
			var bu := t.used_rect(K.BARRACKS, 1, 0, 0, false, lean)
			var b := Rect2i(CastleView.texture_origin(grid.buildings[id].position, K.BARRACKS) + bu.position + off, bu.size)
			var wc: Vector2i = side[1]
			var wid := grid.building_at(wc)
			var wu := t.used_rect(K.PALISADE, 1, 0, grid.wall_mask(wid))
			var w := Rect2i(CastleView.texture_origin(wc, K.PALISADE) + wu.position, wu.size)
			var gap := 0
			match dir:
				Vector2i.UP:
					gap = b.position.y - w.end.y
				Vector2i.DOWN:
					gap = w.position.y - b.end.y
				Vector2i.LEFT:
					gap = b.position.x - w.end.x
				Vector2i.RIGHT:
					gap = w.position.x - b.end.x
			assert_true(gap <= 0, "%s: bez szpary (%d px)" % [str(dir), gap])
			grid.remove(id)
	return true


static func _alpha(img: Image) -> PackedByteArray:
	var out := PackedByteArray()
	for y in img.get_height():
		for x in img.get_width():
			out.append(int(img.get_pixel(x, y).a * 255.0))
	return out


## Dwór i donżon nie przyklejają się do muru (review #190): stoją tam, gdzie dotknięto.
func test_unique_buildings_do_not_stick() -> bool:
	var grid := _grid(true)
	for kind: int in [K.MANOR, K.KEEP]:
		var tap := o + Vector2i(4, 9)
		assert_eq(grid.placement_candidates(tap, kind, true), [Rect2i(tap, BuildingTypes.size_of(kind))] as Array[Rect2i],
				"%s bez przyklejania" % BuildingTypes.NAMES[kind])
	return true
