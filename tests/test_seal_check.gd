extends TestCase
## Komenda umocnień i sprawdzanie szczelności (#199).

const VIEW := Vector2(320, 180)
const MAIN := preload("res://scripts/main.gd")
const K := BuildingTypes.Kind


func _rich_economy() -> Economy:
	var e := Economy.new(0)
	for res in EconomyConfig.count():
		e.amounts[res] = 1_000_000
	return e


func _free_cell(grid: BuildGrid, kind: int) -> Vector2i:
	for y in range(2, grid.terrain.size - 4):
		for x in range(2, grid.terrain.size - 4):
			var c := Vector2i(x, y)
			if grid.placement_for(c, kind).has_area():
				return c
	return Vector2i(-1, -1)


## Lewy górny róg wolnego prostokąta `size` (stały teren z seedu 1337).
func _open_spot(grid: BuildGrid, size: Vector2i) -> Vector2i:
	for y in range(2, grid.terrain.size - size.y - 2):
		for x in range(2, grid.terrain.size - size.x - 2):
			var c := Vector2i(x, y)
			if grid.can_place(Rect2i(c, size)):
				return c
	return Vector2i(-1, -1)


## Pierścień palisady `side`×`side` od `o`; bez kratek z `skip`.
func _ring(grid: BuildGrid, o: Vector2i, side: int, skip: Array[Vector2i] = []) -> void:
	for i in side:
		for p: Vector2i in [o + Vector2i(i, 0), o + Vector2i(i, side - 1), o + Vector2i(0, i),
				o + Vector2i(side - 1, i)]:
			if grid.building_at(p) == 0 and not skip.has(p):
				grid.place(Rect2i(p, Vector2i.ONE), K.PALISADE, 1)


func test_seal_house_is_buildable_defense() -> bool:
	assert_eq(BuildingTypes.NAMES[K.SEAL_HOUSE], "Komenda umocnień", "nazwa")
	assert_eq(BuildingTypes.SHORT_NAMES[K.SEAL_HOUSE], "Komenda", "krótka")
	assert_eq(BuildingTypes.size_of(K.SEAL_HOUSE), Vector2i(2, 2), "2×2")
	assert_eq(BuildingTypes.category(K.SEAL_HOUSE), BuildingTypes.Category.DEFENSE, "Umocnienia")
	assert_true(BuildingTypes.BUILD_BAR.has(K.SEAL_HOUSE), "na pasku budowy")
	assert_eq(BuildingTypes.Kind.SEAL_HOUSE, 24, "za Strażnicą (stare zapisy bez zmian)")
	assert_eq(BuildConfig.required_tech(K.SEAL_HOUSE), "O2", "z technologii O2 Zaostrzone pale")
	assert_true(TechTree.effect("O2").contains("Komenda umocnień"), "efekt O2 mówi o Komendzie")
	assert_true(not BuildConfig.is_unlocked(K.SEAL_HOUSE, Research.new()), "bez O2 zablokowana")
	assert_true(BuildingArt.make_image(K.SEAL_HOUSE, 1, 0).get_used_rect().has_area(), "rysunek")
	var e := _rich_economy()
	var grid := BuildGrid.new(TerrainMap.generate(1337))
	var cell := _free_cell(grid, K.SEAL_HOUSE)
	assert_true(cell.x >= 0, "jest miejsce")
	var q := BuildQueue.new()
	assert_eq(q.order_build(grid, e, cell, K.SEAL_HOUSE, 0, Research.new()), BuildQueue.Result.NEEDS_TECH,
			"bez O2 nie stoi")
	var r := Research.new()
	r.done["O2"] = true
	assert_eq(q.order_build(grid, e, cell, K.SEAL_HOUSE, 0, r), BuildQueue.Result.OK, "po O2 zlecenie")
	assert_eq(grid.kinds[q.placed_id], K.SEAL_HOUSE, "plac Komendy")
	return true


func test_seal_check_countdown_and_gaps() -> bool:
	var check := SealCheck.new()
	var grid := BuildGrid.new(TerrainMap.generate(1337))
	var o := _open_spot(grid, Vector2i(8, 3)) + Vector2i(0, 1)
	assert_true(o.x >= 1, "pas pod linię")
	grid.place(Rect2i(o, Vector2i.ONE), K.PALISADE, 1)
	grid.place(Rect2i(o + Vector2i(3, 0), Vector2i(3, 1)), K.GATE, 1)
	var gap := o + Vector2i(1, 0)
	assert_true(grid.is_wall_gap(gap, K.PALISADE), "jest luka do bramy")
	assert_true(grid.fort_gaps().has(gap), "fort_gaps widzi lukę")
	assert_eq(grid.wall_kind_for_gap(gap), K.PALISADE, "uszczelnienie palisadą")
	assert_true(check.start(1000), "start Sprawdź")
	assert_true(check.is_busy(), "trwa")
	assert_true(not check.start(1500), "drugie Sprawdź zablokowane")
	assert_eq(check.remaining_ms(1000 + SealCheck.DURATION_MS - 1), 1, "prawie koniec")
	assert_true(not check.update(1000 + SealCheck.DURATION_MS - 1, grid), "jeszcze nie")
	assert_true(check.update(1000 + SealCheck.DURATION_MS, grid), "koniec")
	assert_true(check.revealed and not check.is_busy(), "ujawnione")
	assert_true(check.gaps.has(gap), "luka na liście")
	grid.place(Rect2i(gap, Vector2i.ONE), K.PALISADE, 1)
	check.prune(grid)
	assert_true(not check.gaps.has(gap), "po wypełnieniu znika")
	return true


func test_seal_card_buttons() -> bool:
	var b := Hud.content_bounds(VIEW, Rect2())
	var card := Hud.card_rects(VIEW, false, false, true)
	assert_eq(card.size(), 5, "5 przycisków")
	assert_true(card[0].position.x >= b.x and card[-1].end.x <= b.y, "mieści się na 320 px")
	assert_eq(Hud.card_buttons(false, false, true), [
			Hud.CardButton.UPGRADE, Hud.CardButton.DEMOLISH, Hud.CardButton.CHECK, Hud.CardButton.SEAL,
			Hud.CardButton.CLOSE] as Array[int], "kolejność")
	assert_eq(Hud.target_at(card[2].get_center(), VIEW, b.y, false, true, false, false, false, true),
			Hud.Target.CARD + Hud.CardButton.CHECK, "Sprawdź")
	assert_eq(Hud.target_at(card[3].get_center(), VIEW, b.y, false, true, false, false, false, true),
			Hud.Target.CARD + Hud.CardButton.SEAL, "Domknij")
	for button in Hud.card_buttons(false, false, true):
		assert_true(PixelFont.text_width(Hud.card_label(button)) <= Hud.BUTTON_SIZE.x - 2,
				"„%s” mieści się" % Hud.card_label(button))
	var check := SealCheck.new()
	assert_eq(MAIN.seal_card_info(check, 0), MAIN.SEAL_HOUSE_INFO, "przed Sprawdź")
	check.start(0)
	assert_eq(MAIN.seal_card_info(check, 0), "Sprawdzanie: 1:00", "odliczanie")
	assert_eq(SealCheck.DURATION_MS, 60_000, "ok. 1 minuta")
	return true


func test_seal_orders_gap_via_queue() -> bool:
	var grid := BuildGrid.new(TerrainMap.generate(1337))
	var e := _rich_economy()
	var q := BuildQueue.new()
	var o := _open_spot(grid, Vector2i(8, 3)) + Vector2i(0, 1)
	grid.place(Rect2i(o, Vector2i.ONE), K.PALISADE, 1)
	grid.place(Rect2i(o + Vector2i(3, 0), Vector2i(3, 1)), K.GATE, 1)
	assert_true(o.x >= 1, "pas pod linię")
	var gap := o + Vector2i(1, 0)
	var kind := grid.wall_kind_for_gap(gap)
	assert_eq(q.order_build(grid, e, gap, kind, 0), BuildQueue.Result.OK, "Domknij = zlecenie odcinka")
	assert_eq(grid.buildings[q.placed_id].position, gap, "plac w luce")
	assert_eq(grid.levels[q.placed_id], 0, "jeszcze budowa")
	return true


func test_closed_ring_has_no_gaps() -> bool:
	var grid := BuildGrid.new(TerrainMap.generate(1337))
	var o := _open_spot(grid, Vector2i(8, 8)) + Vector2i.ONE
	assert_true(o.x >= 1, "miejsce na pierścień")
	_ring(grid, o, 6)
	assert_eq(grid.fort_gaps(), [] as Array[Vector2i], "szczelny pierścień: wewnętrzne narożniki to nie luki")
	var check := SealCheck.new()
	check.start(0)
	assert_true(check.update(SealCheck.DURATION_MS, grid), "koniec Sprawdź")
	assert_true(check.revealed and check.gaps.is_empty(), "obrona szczelna")
	assert_eq(MAIN.seal_card_info(check, SealCheck.DURATION_MS), "Obrona szczelna", "komunikat na karcie")
	return true


func test_ring_gaps_found_on_side_and_corner() -> bool:
	var grid := BuildGrid.new(TerrainMap.generate(1337))
	var o := _open_spot(grid, Vector2i(8, 8)) + Vector2i.ONE
	assert_true(o.x >= 1, "miejsce na pierścień")
	var side_gap := o + Vector2i(3, 0)
	var corner_gap := o + Vector2i(5, 5)
	_ring(grid, o, 6, [side_gap, corner_gap] as Array[Vector2i])
	assert_eq(grid.fort_gaps(), [side_gap, corner_gap] as Array[Vector2i], "luka w boku i brakujący narożnik")
	assert_eq(grid.wall_kind_for_gap(corner_gap), K.PALISADE, "narożnik domyka palisada")
	grid.place(Rect2i(corner_gap, Vector2i.ONE), K.PALISADE, 1)
	assert_eq(grid.fort_gaps(), [side_gap] as Array[Vector2i], "po domknięciu narożnika zostaje bok")
	return true


func test_fort_gaps_deterministic() -> bool:
	var a := BuildGrid.new(TerrainMap.generate(1337))
	var b := BuildGrid.new(TerrainMap.generate(1337))
	for grid: BuildGrid in [a, b]:
		var o := _open_spot(grid, Vector2i(8, 8)) + Vector2i.ONE
		_ring(grid, o, 6, [o + Vector2i(2, 5)] as Array[Vector2i])
	assert_eq(a.fort_gaps(), b.fort_gaps(), "ten sam seed i układ: te same luki")
	return true


func test_player_selects_gap_to_seal() -> bool:
	var grid := BuildGrid.new(TerrainMap.generate(1337))
	var o := _open_spot(grid, Vector2i(8, 8)) + Vector2i.ONE
	var a := o + Vector2i(2, 0)
	var b := o + Vector2i(2, 5)
	_ring(grid, o, 6, [a, b] as Array[Vector2i])
	var check := SealCheck.new()
	assert_eq(check.gap_near(Vector2(b * TerrainMap.CELL), 3.0), SealCheck.NO_GAP, "przed Sprawdź nic")
	check.start(0)
	check.update(SealCheck.DURATION_MS, grid)
	assert_eq(check.gaps, [a, b] as Array[Vector2i], "dwie luki")
	assert_true(not check.has_selection(), "na start żadna wskazana")
	var center := Vector2(b * TerrainMap.CELL) + Vector2.ONE * TerrainMap.CELL / 2.0
	assert_eq(check.gap_near(center, 3.0), b, "dotknięcie w lukę")
	assert_eq(check.gap_near(center + Vector2(0, 6), 3.0), b, "palec tuż pod luką też ją trafia")
	assert_eq(check.gap_near(center + Vector2(0, 12), 3.0), SealCheck.NO_GAP, "za daleko")
	assert_true(not check.select(o), "kratka bez luki nie do wskazania")
	assert_true(check.select(b), "wskazanie drugiej luki")
	assert_eq(MAIN.seal_card_info(check, 0), MAIN.SEAL_SELECTED_INFO, "karta mówi o wybranej luce")
	var q := BuildQueue.new()
	var kind := grid.wall_kind_for_gap(check.selected)
	assert_eq(q.order_build(grid, _rich_economy(), check.selected, kind, 0), BuildQueue.Result.OK, "Domknij wybranej")
	check.prune(grid)
	assert_eq(check.gaps, [a] as Array[Vector2i], "domknięta luka znika, pierwsza zostaje")
	assert_true(not check.has_selection(), "wybór znika razem z luką")
	return true


func test_seal_state_survives_save() -> bool:
	var grid := BuildGrid.new(TerrainMap.generate(1337))
	var o := _open_spot(grid, Vector2i(8, 8)) + Vector2i.ONE
	var a := o + Vector2i(2, 0)
	_ring(grid, o, 6, [a] as Array[Vector2i])
	var e := Economy.new(0)
	var running := SealCheck.new()
	running.start(1000)
	var d := SaveGame.to_dict(1337, grid, e, BuildQueue.new(), null, null, null, 0, null, 0, null, 0, running)
	var s := SaveGame.from_dict(JSON.parse_string(JSON.stringify(d)) as Dictionary, 20_000)
	assert_true(s.seal.is_busy(), "odliczanie trwa po wczytaniu")
	assert_eq(s.seal.remaining_ms(20_000), SealCheck.DURATION_MS - 19_000, "liczy się czas nieobecności")
	assert_true(s.seal.update(1000 + SealCheck.DURATION_MS, s.grid), "kończy się po wczytaniu")
	assert_eq(s.seal.gaps, [a] as Array[Vector2i], "luka z wczytanej siatki")
	s.seal.select(a)
	var d2 := SaveGame.to_dict(1337, s.grid, e, BuildQueue.new(), null, null, null, 0, null, 0, null, 0, s.seal)
	var s2 := SaveGame.from_dict(JSON.parse_string(JSON.stringify(d2)) as Dictionary, 100_000)
	assert_true(s2.seal.revealed and not s2.seal.is_busy(), "wynik po wczytaniu")
	assert_eq(s2.seal.gaps, [a] as Array[Vector2i], "te same luki")
	assert_eq(s2.seal.selected, a, "ta sama wskazana luka")
	assert_true(not CastleSync.castle_data(d2).has("seal"), "stan Sprawdź nie idzie na serwer")
	var future := SealCheck.new()
	future.start(500_000)
	var s3 := SaveGame.from_dict(SaveGame.to_dict(1337, grid, e, BuildQueue.new(), null, null, null, 0, null, 0,
			null, 0, future), 1000)
	assert_eq(s3.seal.start_ms, 1000, "start z przyszłości przycięty do teraz")
	var bad := {"busy": false, "revealed": true, "gaps": [[-5, 2], "x", [a.x, a.y], [a.x, a.y]], "selected": [9999, 0]}
	var c := SealCheck.new()
	assert_eq(c.load_data(bad, grid, 0), 3, "złe wpisy pominięte")
	assert_eq(c.gaps, [a] as Array[Vector2i], "dobra luka zostaje")
	assert_eq(c.selected, SealCheck.NO_GAP, "wybór spoza luk odrzucony")
	return true


func test_old_save_without_seal_loads() -> bool:
	var grid := BuildGrid.new(TerrainMap.generate(1337))
	var d := SaveGame.to_dict(1337, grid, Economy.new(0), BuildQueue.new())
	d.erase("seal")
	d["version"] = 8
	var s := SaveGame.from_dict(d, 0)
	assert_true(s != null, "zapis v8 wczytany")
	assert_true(not s.seal.is_busy() and not s.seal.revealed, "bez Sprawdź")
	return true
