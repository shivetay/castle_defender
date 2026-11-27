extends TestCase
## Rozmiary budynków (#340, ADR 0005): Koszary 3×3, budynki wojska, Magazyn i pola 3×2, reszta bez zmian.
## Budynek ze starego zapisu zostaje w zapisanym prostokącie i tak się rysuje. Rysunek 2×2 wygląda
## piksel w piksel jak przed zmianą (suma kontrolna), a boty dalej stawiają wszystkie swoje budynki.

const K := BuildingTypes.Kind
const GROWN_3X2: Array[int] = [K.WARBAND_HOUSE, K.ARCHERY_RANGE, K.STABLE, K.WAREHOUSE, K.FLAX_FIELD, K.FARM,
		K.QUARRY]
## Suma MD5 obrazów 2×2 (poziomy 0–6, 4 stany, 5 stron przybudówki) sprzed #340: wszystkie rodzaje 2×2
## oraz powiększone rodzaje narysowane w starym rozmiarze 2×2.
const GOLDEN_2X2 := "8e9526125fce629f995913b23d1e6266"


func test_size_table() -> bool:
	assert_eq(BuildingTypes.size_of(K.BARRACKS), Vector2i(3, 3), "Koszary 3×3")
	for kind in GROWN_3X2:
		assert_eq(BuildingTypes.size_of(kind), Vector2i(3, 2), "%s 3×2" % BuildingTypes.NAMES[kind])
	for kind: int in [K.RAMPART, K.PALISADE, K.DRY_MOAT]:
		assert_eq(BuildingTypes.size_of(kind), Vector2i(1, 1), "%s 1×1" % BuildingTypes.NAMES[kind])
	assert_eq(BuildingTypes.size_of(K.GATE), Vector2i(3, 1), "brama 3×1")
	for kind: int in [K.MANOR, K.KEEP, K.WATCHTOWER, K.LUMBER_HUT, K.HUNTER, K.TOWER, K.TAR_KILN]:
		assert_eq(BuildingTypes.size_of(kind), Vector2i(2, 2), "%s 2×2" % BuildingTypes.NAMES[kind])
	var barracks := BuildingTypes.size_of(K.BARRACKS)
	var hut := BuildingTypes.size_of(K.LUMBER_HUT)
	assert_true(barracks.x * barracks.y > hut.x * hut.y, "Koszary większe od Chaty drwala")
	return true


func test_two_by_two_art_unchanged() -> bool:
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_MD5)
	for kind in BuildingTypes.count():
		if BuildingTypes.size_of(kind) != Vector2i(2, 2) and not GROWN_3X2.has(kind) and kind != K.BARRACKS:
			continue
		if BuildConfig.start_level(kind) > 1:
			continue  # budynki epoki II z #102 (Młyn, #388) doszły po złotym hashu; ich rysunki ma test_mill
		for level in range(0, 7):
			for state in 4:
				for lean in 5:
					ctx.update(BuildingArt.make_image(kind, level, state, 0, false, lean, Vector2i(2, 2)).get_data())
	assert_eq(ctx.finish().hex_encode(), GOLDEN_2X2, "rysunki 2×2 bez zmian")
	return true


func test_big_art_fills_footprint() -> bool:
	for kind: int in GROWN_3X2 + ([K.BARRACKS] as Array[int]):
		var px := BuildingTypes.size_of(kind) * BuildingArt.CELL
		for level in range(1, 7):
			var img := BuildingArt.make_image(kind, level, BuildingTypes.State.INTACT)
			assert_eq(img.get_size(), px, "%s poz. %d: rozmiar obrazu" % [BuildingTypes.NAMES[kind], level])
			var used := img.get_used_rect()
			if level >= 2:
				# budynek wypełnia nowy obrys, a nie tylko lewy górny róg 16×16
				assert_true(used.end.x > 16 + 4 and used.size.x >= px.x - 6,
						"%s poz. %d: szerokość rysunku %d" % [BuildingTypes.NAMES[kind], level, used.size.x])
				if px.y > 16:
					assert_true(used.end.y > 16 + 2 and used.size.y >= px.y - 6,
							"%s poz. %d: wysokość rysunku %d" % [BuildingTypes.NAMES[kind], level, used.size.y])
	return true


func test_textures_follow_rect() -> bool:
	var tex := BuildingTextures.new()
	var big := tex.draw_building(K.BARRACKS, 3)
	var old := tex.draw_building(K.BARRACKS, 3, BuildingTypes.State.INTACT, 0, false, 0, Vector2i(2, 2))
	assert_eq(Vector2i(big.get_size()), Vector2i(24, 24), "nowe Koszary 24×24 px")
	assert_eq(Vector2i(old.get_size()), Vector2i(16, 16), "Koszary ze starego zapisu 16×16 px")
	assert_true(big != old, "osobne tekstury w cache")
	assert_eq(tex.used_rect(K.BARRACKS, 3, 0, 0, false, 0, Vector2i(2, 2)), old.get_image().get_used_rect(),
			"zamalowany prostokąt starego rozmiaru")
	assert_eq(Vector2i(tex.shadow(K.WAREHOUSE, 2).get_size()), Vector2i(24, 16) + BuildingArt.shadow_offset(K.WAREHOUSE),
			"cień Magazynu 3×2")
	return true


func _grid() -> BuildGrid:
	var grid := BuildGrid.new(TerrainMap.generate(WorldSeed.first_playable(1337)))
	grid.place(grid.manor_spot(64), K.MANOR, 1)
	grid.place(grid.keep_spot(64), K.KEEP, 1)
	return grid


func test_placement_uses_footprint() -> bool:
	var grid := _grid()
	var spot := grid.spot_near(DefensePlan.keep_center(grid), K.BARRACKS, 20)
	assert_eq(spot.size, Vector2i(3, 3), "miejsce na Koszary 3×3")
	var cands := grid.placement_candidates(spot.position, K.BARRACKS, true)
	assert_true(not cands.is_empty(), "są kandydaci")
	for r in cands:
		assert_eq(r.size, Vector2i(3, 3), "kandydat Koszar 3×3")
	var id := grid.place(spot, K.BARRACKS, 1)
	assert_true(id != 0, "Koszary stoją")
	for dy in 3:
		for dx in 3:
			assert_eq(grid.building_at(spot.position + Vector2i(dx, dy)), id, "kratka Koszar %d,%d" % [dx, dy])
	return true


func test_old_save_keeps_rect() -> bool:
	var grid := _grid()
	var spot := grid.spot_near(DefensePlan.keep_center(grid), K.BARRACKS, 20)
	var old := Rect2i(spot.position, Vector2i(2, 2))
	var id := grid.place(old, K.BARRACKS, 2)
	assert_true(id != 0, "stare Koszary 2×2 (jak w zapisie sprzed #340)")
	var loaded := BuildGrid.new(grid.terrain)
	assert_eq(loaded.load_data(grid.save_data()), 0, "nic nie pominięte")
	assert_eq(loaded.buildings[id], old, "prostokąt z zapisu")
	assert_eq(loaded.cells_of(id), Vector2i(2, 2), "rysunek w starym rozmiarze")
	var gate := loaded.place(loaded.spot_near(spot.position + Vector2i(0, 6), K.GATE, 20), K.GATE, 1)
	assert_eq(loaded.cells_of(gate), Vector2i(3, 1), "brama: obrys bez obrotu")
	return true


func test_bots_place_all_buildings() -> bool:
	for i in BotRoster.COUNT:
		var bot := BotRoster.generate(i)
		var want: Dictionary[int, int] = {K.LUMBER_HUT: 2, K.HUNTER: 1}
		for kind in BotRoster.recruit_buildings(BotRoster.structure_of(i)):
			want[kind] = int(want.get(kind, 0)) + 1
		for kind: int in want:
			var have := 0
			for id: int in bot.grid.kinds:
				if bot.grid.kinds[id] == kind:
					have += 1
					assert_eq(bot.grid.buildings[id].size, BuildingTypes.size_of(kind),
							"bot %d: %s w nowym rozmiarze" % [i, BuildingTypes.NAMES[kind]])
			assert_eq(have, want[kind], "bot %d: %s" % [i, BuildingTypes.NAMES[kind]])
		var again := BotRoster.generate(i)
		assert_eq(again.grid.save_data(), bot.grid.save_data(), "bot %d: ten sam układ dla tego samego seeda" % i)
	return true
