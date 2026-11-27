extends TestCase
## Odcinki wału i palisady 1/2/3 kratki (#371): N kratek 1×1 jednym zleceniem, materiały i czas ×N,
## dopłata w złocie za 2 i 3, cały odcinek odrzucony przy zajętej kratce, anulowanie zdejmuje
## wszystkie place budowy, a zapis kolejki trzyma dodatkowe kratki.

const SEC := 1000
const T0 := 1_700_000_000_000
const K := BuildingTypes.Kind
const R := EconomyConfig.Res
const MAIN := preload("res://scripts/main.gd")


func _grid() -> BuildGrid:
	return BuildGrid.new(TerrainMap.generate(1337))


## Kratka startowa, od której mieści się odcinek `length` w danej orientacji (szukana spiralnie od środka).
func _free_start(grid: BuildGrid, kind: int, length: int, vertical: bool) -> Vector2i:
	var c := grid.terrain.center() + Vector2i(6, 6)
	for r in grid.terrain.size:
		for dy in range(-r, r + 1):
			for dx in range(-r, r + 1):
				var p := c + Vector2i(dx, dy)
				if not grid.segment_cells(p, kind, length, vertical).is_empty():
					return p
	return Vector2i(-1, -1)


func _castle() -> Array:
	var grid := _grid()
	var economy := Economy.new(T0)
	return [grid, economy]


func test_segment_cost_adds_gold() -> bool:
	assert_eq(BuildConfig.segment_cost(K.RAMPART, 1, 1), BuildConfig.cost(K.RAMPART, 1), "1 kratka: koszt jak dziś")
	assert_eq(BuildConfig.segment_cost(K.RAMPART, 1, 2), [20, 0, 20, 2] as Array[int], "2 kratki: ×2 + 2 zł")
	assert_eq(BuildConfig.segment_cost(K.PALISADE, 1, 3), [60, 0, 15, 5] as Array[int], "3 kratki: ×3 + 5 zł")
	assert_true(BuildConfig.SEGMENT_GOLD[2] > BuildConfig.SEGMENT_GOLD[1], "3 kratki droższe niż 2")
	return true


func test_segment_cells_follow_orientation() -> bool:
	var grid := _grid()
	var c := _free_start(grid, K.PALISADE, 3, false)
	assert_eq(grid.segment_cells(c, K.PALISADE, 3, false),
			[Rect2i(c, Vector2i.ONE), Rect2i(c + Vector2i(1, 0), Vector2i.ONE), Rect2i(c + Vector2i(2, 0), Vector2i.ONE)] as Array[Rect2i],
			"poziomo w prawo od dotkniętej kratki")
	var v := _free_start(grid, K.PALISADE, 3, true)
	assert_eq(grid.segment_cells(v, K.PALISADE, 2, true),
			[Rect2i(v, Vector2i.ONE), Rect2i(v + Vector2i(0, 1), Vector2i.ONE)] as Array[Rect2i], "pionowo w dół")
	return true


func test_order_segment_places_n_tiles_in_one_order() -> bool:
	var castle := _castle()
	var grid: BuildGrid = castle[0]
	var economy: Economy = castle[1]
	var q := BuildQueue.new()
	var c := _free_start(grid, K.PALISADE, 3, false)
	var before := economy.amounts.duplicate()
	assert_eq(q.order_build(grid, economy, c, K.PALISADE, T0, null, 3, false), BuildQueue.Result.OK, "zlecone")
	assert_eq(q.orders.size(), 1, "jedno zlecenie")
	var o := q.orders[0]
	assert_eq(o.extra_ids.size(), 2, "dwie dodatkowe kratki")
	assert_eq(o.duration_ms, 3 * BuildConfig.time_ms(K.PALISADE, 1), "czas ×3")
	for i in 3:
		var id := grid.building_at(c + Vector2i(i, 0))
		assert_true(id != 0 and grid.kinds[id] == K.PALISADE and grid.levels[id] == 0, "plac budowy %d" % i)
		assert_true(q.has_order(id), "kratka %d należy do zlecenia" % i)
	assert_eq(economy.amounts[R.GOLD], int(before[R.GOLD]) - 5, "pobrane 5 zł")
	assert_eq(economy.amounts[R.WOOD], int(before[R.WOOD]) - 60, "pobrane drewno ×3")
	q.update(T0 + o.duration_ms, grid, economy)
	for i in 3:
		assert_eq(grid.levels[grid.building_at(c + Vector2i(i, 0))], 1, "ukończona kratka %d" % i)
	assert_true(q.orders.is_empty(), "kolejka pusta")
	return true


func test_no_gold_blocks_segment() -> bool:
	var castle := _castle()
	var grid: BuildGrid = castle[0]
	var economy: Economy = castle[1]
	economy.amounts[R.GOLD] = 4
	var q := BuildQueue.new()
	var c := _free_start(grid, K.RAMPART, 3, false)
	var before := economy.amounts.duplicate()
	assert_eq(q.order_build(grid, economy, c, K.RAMPART, T0, null, 3, false), BuildQueue.Result.NO_GOLD, "brak złota")
	assert_eq(economy.amounts, before, "nic nie pobrane")
	assert_eq(grid.building_at(c), 0, "nic nie stoi")
	assert_true(not q.message(BuildQueue.Result.NO_GOLD).is_empty(), "czytelny komunikat")
	assert_eq(q.order_build(grid, economy, c, K.RAMPART, T0, null, 1, false), BuildQueue.Result.OK, "1 kratka bez złota")
	return true


func test_blocked_cell_rejects_whole_segment() -> bool:
	var castle := _castle()
	var grid: BuildGrid = castle[0]
	var economy: Economy = castle[1]
	var q := BuildQueue.new()
	var c := _free_start(grid, K.PALISADE, 3, false)
	grid.place(Rect2i(c + Vector2i(2, 0), Vector2i.ONE), K.RAMPART, 1)
	var before := economy.amounts.duplicate()
	assert_eq(q.order_build(grid, economy, c, K.PALISADE, T0, null, 3, false), BuildQueue.Result.NO_PLACE, "zajęta 3. kratka")
	assert_eq(economy.amounts, before, "nic nie pobrane")
	assert_eq(grid.building_at(c), 0, "pierwsza kratka wolna")
	return true


func test_cancel_removes_all_tiles_and_refunds() -> bool:
	var castle := _castle()
	var grid: BuildGrid = castle[0]
	var economy: Economy = castle[1]
	var q := BuildQueue.new()
	var c := _free_start(grid, K.RAMPART, 2, true)
	var before := economy.amounts.duplicate()
	assert_eq(q.order_build(grid, economy, c, K.RAMPART, T0, null, 2, true), BuildQueue.Result.OK, "zlecone")
	var second := grid.building_at(c + Vector2i(0, 1))
	assert_true(q.cancel(grid, economy, second, T0), "anulowanie przez dodatkową kratkę")
	assert_eq(grid.building_at(c), 0, "pierwsza zdjęta")
	assert_eq(grid.building_at(c + Vector2i(0, 1)), 0, "druga zdjęta")
	assert_eq(economy.amounts, before, "pełny zwrot ze złotem")
	return true


func test_save_load_keeps_extra_tiles() -> bool:
	var castle := _castle()
	var grid: BuildGrid = castle[0]
	var economy: Economy = castle[1]
	var q := BuildQueue.new()
	var c := _free_start(grid, K.PALISADE, 3, false)
	q.order_build(grid, economy, c, K.PALISADE, T0, null, 3, false)
	var grid2 := BuildGrid.new(grid.terrain)
	grid2.load_data(grid.save_data())
	var q2 := BuildQueue.new()
	assert_eq(q2.load_data(q.save_data(), grid2, T0), 0, "nic nie pominięte")
	assert_eq(q2.orders[0].extra_ids, q.orders[0].extra_ids, "dodatkowe kratki z zapisu")
	q2.update(T0 + q2.orders[0].duration_ms, grid2, economy)
	for i in 3:
		assert_eq(grid2.levels[grid2.building_at(c + Vector2i(i, 0))], 1, "ukończona po wczytaniu %d" % i)
	# stary zapis bez extra_ids
	var old := q.save_data()
	((old["orders"] as Array)[0] as Dictionary).erase("extra_ids")
	var q3 := BuildQueue.new()
	q3.load_data(old, grid2, T0)
	assert_true(q3.orders[0].extra_ids.is_empty(), "stary zapis: bez dodatkowych kratek")
	return true


func test_segment_seals_toward_tower() -> bool:
	var castle := _castle()
	var grid: BuildGrid = castle[0]
	var economy: Economy = castle[1]
	var q := BuildQueue.new()
	var c := _free_start(grid, K.PALISADE, 3, false)
	# wieża 2×2 dwie kratki za końcem odcinka (luka 1 kratki), więc ukończony odcinek ją domyka
	var tower := Rect2i(c + Vector2i(4, 0), BuildingTypes.size_of(K.TOWER))
	assert_true(grid.can_place(tower, K.TOWER) and grid.can_place(Rect2i(c + Vector2i(3, 0), Vector2i.ONE), K.PALISADE),
			"miejsce na wieżę i lukę (seed 1337)")
	grid.place(tower, K.TOWER, 1)
	assert_eq(q.order_build(grid, economy, c, K.PALISADE, T0, null, 3, false), BuildQueue.Result.OK, "zlecone")
	q.update(T0 + q.orders[0].duration_ms, grid, economy)
	assert_true(grid.building_at(c + Vector2i(3, 0)) != 0, "luka do wieży domknięta")
	return true


func test_segment_is_deterministic() -> bool:
	var a := _castle()
	var b := _castle()
	var qa := BuildQueue.new()
	var qb := BuildQueue.new()
	var ca := _free_start(a[0], K.PALISADE, 3, true)
	var cb := _free_start(b[0], K.PALISADE, 3, true)
	assert_eq(ca, cb, "ta sama kratka")
	qa.order_build(a[0], a[1], ca, K.PALISADE, T0, null, 3, true)
	qb.order_build(b[0], b[1], cb, K.PALISADE, T0, null, 3, true)
	assert_eq((a[0] as BuildGrid).save_data(), (b[0] as BuildGrid).save_data(), "ta sama siatka")
	assert_eq(qa.save_data(), qb.save_data(), "ta sama kolejka")
	return true


func test_hud_segment_buttons() -> bool:
	const T := Hud.Target
	assert_eq(Hud.column_targets(true, false, true), [T.DONE, T.CHANGE, T.CANCEL, T.LENGTH, T.ORIENT] as Array[int],
			"wał/palisada: długość i orientacja pod Anuluj")
	assert_eq(Hud.column_targets(true), [T.DONE, T.CHANGE, T.CANCEL] as Array[int], "inne budynki bez zmian")
	var view := Vector2(320, 180)
	for i in 5:
		var r := Hud.column_rect(view.x - Hud.CORNER_INSET, i)
		assert_true(r.end.y <= view.y - Hud.BAR_H, "przycisk %d nad paskiem komunikatu" % i)
		assert_true(r.size.x >= 12 and r.size.y >= 12, "cel dotyku co najmniej 12×12")
	for label: String in Hud.LENGTH_LABELS + [Hud.HORIZONTAL_LABEL, Hud.VERTICAL_LABEL]:
		assert_true(PixelFont.text_width(label) <= Hud.BUTTON_SIZE.x - 2, "„%s” mieści się na przycisku" % label)
	var hud := Hud.new()
	hud.selected_kind = K.PALISADE
	hud.set_building(true)
	assert_eq(hud.build_length(), 1, "domyślnie 1")
	hud.segment_length = 3
	hud.segment_vertical = true
	assert_eq(hud.build_length(), 3, "wybrane 3")
	hud.selected_kind = K.TOWER
	assert_eq(hud.build_length(), 1, "wieża zawsze 1")
	hud.set_building(false)
	assert_eq(hud.segment_length, 1, "wyjście z budowy zeruje długość")
	assert_true(not hud.segment_vertical, "i orientację")
	hud.free()
	return true


func test_build_message_shows_segment_cost() -> bool:
	var msg := MAIN.build_message(K.PALISADE, RulerPerks.Perk.NONE, 3)
	assert_true(msg.contains(Hud.cost_text(BuildConfig.segment_cost(K.PALISADE, 1, 3))), "koszt odcinka w komunikacie")
	assert_true(PixelFont.text_width(msg) <= Hud.MESSAGE_MAX_WIDTH, "komunikat mieści się w pasku")
	return true


## Serwer zna te same dopłaty i zasady odcinka (review PR 414, migracja `*_wall_segments.sql`).
func test_server_knows_segment_gold() -> bool:
	var sql := FileAccess.get_file_as_string("res://supabase/migrations/20261127180000_wall_segments.sql")
	assert_true(not sql.is_empty(), "migracja jest")
	assert_true(sql.contains("SEGMENT_GOLD = %s" % str(BuildConfig.SEGMENT_GOLD)), "dopłaty w komentarzu")
	var arr := "(array[%s])" % ", ".join(BuildConfig.SEGMENT_GOLD.map(func(g: int) -> String: return str(g)))
	assert_true(sql.contains(arr + "[cardinality(s.extra_ids) + 1]"), "dopłaty w funkcji")
	assert_true(sql.contains("limit %d" % (BuildConfig.SEGMENT_MAX - 1)), "najwyżej SEGMENT_MAX − 1 dodatkowych kratek")
	assert_true(sql.contains("b.kind in (%d, %d)" % [K.RAMPART, K.PALISADE]), "tylko wał i palisada")
	return true


## Zapis z extra_ids przy budynku, który nie jest odcinkiem (wieża, ulepszenie), ich nie bierze, jak serwer.
func test_load_ignores_extra_ids_outside_segments() -> bool:
	var castle := _castle()
	var grid: BuildGrid = castle[0]
	var c := _free_start(grid, K.PALISADE, 3, false)
	var a := grid.place(Rect2i(c, Vector2i.ONE), K.PALISADE, 1)
	var b := grid.place(Rect2i(c + Vector2i(1, 0), Vector2i.ONE), K.PALISADE, 1)
	var data := {"orders": [{"building_id": a, "extra_ids": [b], "kind": K.PALISADE, "level": 2,
			"cost": [30, 0, 7, 0], "duration_ms": 30 * SEC, "start_ms": T0}]}
	var q := BuildQueue.new()
	q.load_data(data, grid, T0)
	assert_true(q.orders[0].extra_ids.is_empty(), "ulepszenie nie jest odcinkiem")
	return true
