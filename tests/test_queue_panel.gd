extends TestCase
## Ekran Kolejka (#163): wiersze z kolejki budowy i kolejek szkolenia (kolejność, poziomy, czasy,
## postęp, grupowanie według budynku rekrutacji), anulowanie z potwierdzeniem, cele dotyku
## i układ mieszczący się w 320×180.

const K := BuildingTypes.Kind
const U := UnitTypes.Unit
const T0 := 1_700_000_000_000
const VIEW := Vector2(320, 180)


func _rich_economy() -> Economy:
	var e := Economy.new(T0)
	for res in EconomyConfig.count():
		e.amounts[res] = 1_000_000
	return e


func _grid() -> BuildGrid:
	var grid := BuildGrid.new(TerrainMap.generate(WorldSeed.first_playable(1337)))
	grid.place(grid.manor_spot(64), K.MANOR, 3)
	return grid


func _place(grid: BuildGrid, kind: int, level: int = 1) -> int:
	return grid.place(grid.spot_near(grid.buildings[grid.manor_id()].position, kind, 30), kind, level)


func test_building_rows_follow_queue() -> bool:
	var grid := _grid()
	var e := _rich_economy()
	var q := BuildQueue.new()
	var hut := _place(grid, K.LUMBER_HUT, 1)
	var spot := grid.spot_near(grid.buildings[grid.manor_id()].position, K.TOWER, 30)
	assert_eq(q.order_build(grid, e, spot.position, K.TOWER, T0), BuildQueue.Result.OK, "zlecenie wieży")
	var tower := q.placed_id
	assert_eq(q.order_upgrade(grid, e, hut, T0), BuildQueue.Result.OK, "ulepszenie chaty")
	var half := T0 + BuildConfig.time_ms(K.TOWER, 1) / 2
	var rows := QueuePanel.building_rows(q, half)
	assert_eq(rows.size(), 2, "dwa zlecenia")
	assert_eq(rows[0]["title"], "Wieża drewniana", "pierwsze w kolejności wykonania")
	assert_eq(rows[0]["level"], "nowy", "nowy budynek")
	assert_eq(int(rows[0]["progress"]), 500, "postęp pierwszego: połowa")
	assert_true(not bool(rows[0]["waiting"]), "pierwsze w budowie")
	assert_eq(rows[0]["time"], Hud.format_time(q.remaining_ms(tower, half)), "czas jak w kolejce")
	assert_eq(rows[1]["level"], "poz. 1→2", "ulepszenie")
	assert_true(bool(rows[1]["waiting"]), "drugie czeka")
	assert_eq(int(rows[1]["progress"]), -1, "czekające bez paska")
	assert_eq(rows[1]["time"], Hud.format_time(q.remaining_ms(hut, half)), "czas czekającego po pierwszym")
	assert_eq(QueuePanel.footer_text(QueuePanel.Tab.BUILDINGS, q, Recruitment.new(), grid), "Kolejka: 2/4", "zajęte miejsca")
	assert_eq(QueuePanel.confirm_text(q, tower), "Anulować Wieża? Zwrot: %s" % Hud.cost_text(BuildConfig.cost(K.TOWER, 1)),
			"potwierdzenie podaje zwrot")
	# najdroższe zlecenia każdego budynku mieszczą się w pasku komunikatu
	for kind in BuildingTypes.NAMES.size():
		for level in range(1, BuildingTypes.MAX_LEVEL + 1):
			var o := BuildQueue.Order.new()
			o.kind = kind
			o.level = level
			o.cost = BuildConfig.cost(kind, level)
			o.building_id = 999
			var probe := BuildQueue.new()
			probe.orders.append(o)
			assert_true(PixelFont.text_width(QueuePanel.confirm_text(probe, 999)) <= Hud.MESSAGE_MAX_WIDTH,
					"%s poz. %d: pytanie mieści się w pasku" % [BuildingTypes.NAMES[kind], level])
	return true


## Anuluj prosi o drugie dotknięcie; po nim zlecenie znika, koszt wraca, a kolejne rusza.
func test_cancel_needs_confirmation() -> bool:
	var grid := _grid()
	var e := _rich_economy()
	var q := BuildQueue.new()
	var spot := grid.spot_near(grid.buildings[grid.manor_id()].position, K.TOWER, 30)
	q.order_build(grid, e, spot.position, K.TOWER, T0)
	var tower := q.placed_id
	var hut := _place(grid, K.LUMBER_HUT, 1)
	q.order_upgrade(grid, e, hut, T0)
	var panel := QueuePanel.new()
	panel.queue = q
	panel.recruitment = Recruitment.new()
	panel.grid = grid
	panel.now_ms = T0 + 1000
	panel.open()
	var asked: Array[String] = []
	var cancelled: Array[int] = []
	panel.message.connect(func(t: String) -> void: asked.append(t))
	panel.cancel_requested.connect(func(id: int) -> void:
		cancelled.append(id)
		q.cancel(grid, e, id, T0 + 1000))
	panel.activate(QueuePanel.Target.CANCEL + 0)
	assert_eq(cancelled.size(), 0, "pierwsze dotknięcie tylko pyta")
	assert_true(asked.size() == 1 and asked[0].begins_with("Anulować Wieża?"), "komunikat z pytaniem")
	assert_eq(panel.confirm_id, tower, "czeka na potwierdzenie")
	panel.activate(QueuePanel.Target.TAB + 1)
	assert_eq(panel.confirm_id, 0, "inny przycisk kasuje pytanie")
	panel.tab = QueuePanel.Tab.BUILDINGS
	e.amounts[0] = 0
	var wood := e.amounts[0]
	panel.activate(QueuePanel.Target.CANCEL + 0)
	panel.activate(QueuePanel.Target.CANCEL + 0)
	assert_eq(cancelled, [tower] as Array[int], "drugie dotknięcie anuluje")
	assert_true(not grid.buildings.has(tower), "plac budowy znika")
	assert_true(e.amounts[0] > wood, "koszt wraca")
	assert_eq(q.orders[0].building_id, hut, "kolejne zlecenie przechodzi do pracy")
	assert_eq(q.orders[0].start_ms, T0 + 1000, "i rusza od razu")
	panel.free()
	return true


func test_unit_rows_grouped_by_building() -> bool:
	var grid := _grid()
	var e := _rich_economy()
	var goods := Goods.new(T0)
	var research := Research.new()
	var r := Recruitment.new()
	var barracks := _place(grid, K.BARRACKS, 1)
	var barracks2 := _place(grid, K.BARRACKS, 1)
	var range_id := _place(grid, K.ARCHERY_RANGE, 1)
	for code: String in ["A39", "A40", "A41", "A44", "G18"]:
		research.done[code] = true
	for res in GoodsConfig.NAMES.size():
		goods.add(res, 100)
	assert_eq(r.start(U.ARCHER, range_id, Recruitment.NEW_SQUAD, grid, e, goods, research, 0, T0), Recruitment.Result.OK,
			"łucznik w Strzelnicy")
	assert_eq(r.start(U.PEASANT, barracks2, Recruitment.NEW_SQUAD, grid, e, goods, research, 0, T0), Recruitment.Result.OK,
			"chłop w drugich Koszarach")
	assert_eq(r.start(U.PEASANT, barracks, Recruitment.NEW_SQUAD, grid, e, goods, research, 0, T0), Recruitment.Result.OK,
			"chłop w Koszarach")
	assert_eq(r.start(U.PEASANT, barracks, r.last_squad, grid, e, goods, research, 0, T0), Recruitment.Result.OK,
			"drugi chłop czeka")
	var rows := QueuePanel.unit_rows(r, grid, T0 + 5000)
	var titles: Array[String] = []
	for row in rows:
		titles.append(("# " if bool(row["header"]) else "") + (row["title"] as String))
	var peasant := UnitTypes.SHORT_NAMES[U.PEASANT]
	assert_eq(titles, ["# Koszary", peasant, peasant, "# Koszary 2", peasant, "# Strzelnica", UnitTypes.SHORT_NAMES[U.ARCHER]]
			as Array[String], "grupy w kolejności budynków klas, w grupie po id")
	assert_true(int(rows[1]["progress"]) > 0, "trwające szkolenie z paskiem")
	assert_eq(int(rows[2]["progress"]), -1, "czekające bez paska")
	assert_true(bool(rows[2]["waiting"]), "czeka")
	assert_eq(rows[2]["time"], Hud.format_time(r.remaining_ms(barracks, T0 + 5000)), "czas ostatniego = koniec kolejki budynku")
	assert_true((rows[1]["squad"] as String).begins_with("oddz. "), "oddział docelowy")
	assert_eq(QueuePanel.footer_text(QueuePanel.Tab.UNITS, BuildQueue.new(), r, grid),
			"Armia: 0/%d (+4)" % Recruitment.army_limit(grid), "armia względem limitu i w szkoleniu")
	return true


func test_empty_tabs_and_layout() -> bool:
	var b := Hud.content_bounds(VIEW, Rect2())
	var fit := QueuePanel.rows_fit(VIEW)
	assert_true(fit >= 7, "lista mieści co najmniej 7 wierszy (jest %d)" % fit)
	var last := QueuePanel.row_rect(b.x, b.y, fit - 1)
	assert_true(last.end.y < Hud.row_y(VIEW), "ostatni wiersz nad rzędem przycisków")
	assert_true(QueuePanel.cancel_rect(last).size.y >= 12 and QueuePanel.cancel_rect(last).size.x >= 12,
			"Anuluj co najmniej 12×12 px (review #183)")
	for label: String in [QueuePanel.CANCEL_LABEL, QueuePanel.CONFIRM_LABEL]:
		assert_true(PixelFont.text_width(label) <= QueuePanel.CANCEL_W - 2, "„%s” mieści się" % label)
	for label: String in QueuePanel.ACTION_LABELS + [QueuePanel.CLOSE_LABEL, QueuePanel.MORE_LABEL, Hud.queue_label(12)]:
		assert_true(PixelFont.text_width(label) <= Hud.BUTTON_SIZE.x - 2, "„%s” mieści się na przycisku" % label)
	var tabs := QueuePanel.tab_rects(b.x, b.y)
	assert_true(tabs[1].end.x <= b.y, "zakładki w granicy treści")
	assert_true(PixelFont.text_width("Jednostki (24)") <= tabs[1].size.x - 4, "zakładka z licznikiem mieści się")
	for kind in BuildingTypes.NAMES.size():
		assert_true(PixelFont.text_width(QueuePanel.row_title(kind)) <= QueuePanel.TITLE_W,
				"%s mieści się przed kolumną poziomu" % BuildingTypes.NAMES[kind])
	for unit in UnitTypes.count():
		assert_true(PixelFont.text_width(UnitTypes.SHORT_NAMES[unit]) <= QueuePanel.TITLE_W, "jednostka mieści się")
	assert_eq(QueuePanel.row_title(K.LEATHERWORKER), "Zbrojarz", "za długa nazwa: skrót")
	assert_true(QueuePanel.SECOND_X + PixelFont.text_width("poz. 4→5") + PixelFont.text_width("czeka 1:30:00") + QueuePanel.CANCEL_W + 12 <= b.y - b.x,
			"poziom, czas i Anuluj w jednym wierszu")
	# cele dotyku
	var q := BuildQueue.new()
	assert_eq(QueuePanel.target_at(QueuePanel.action_rect(VIEW, b.y).get_center(), VIEW, b.x, b.y, 0, 0, 0),
			QueuePanel.Target.ACTION, "pusta zakładka: Buduj")
	assert_eq(QueuePanel.target_at(QueuePanel.action_rect(VIEW, b.y).get_center(), VIEW, b.x, b.y, 0, 3, 0),
			QueuePanel.Target.NONE, "z wierszami przycisku akcji nie ma")
	var r1 := QueuePanel.row_rect(b.x, b.y, 1)
	assert_eq(QueuePanel.target_at(r1.position + Vector2(5, 5), VIEW, b.x, b.y, 0, 3, 0), QueuePanel.Target.ROW + 1, "wiersz")
	assert_eq(QueuePanel.target_at(QueuePanel.cancel_rect(r1).get_center(), VIEW, b.x, b.y, 0, 3, 0),
			QueuePanel.Target.CANCEL + 1, "Anuluj w wierszu")
	assert_eq(QueuePanel.target_at(QueuePanel.cancel_rect(r1).get_center(), VIEW, b.x, b.y, 1, 3, 0),
			QueuePanel.Target.ROW + 1, "na zakładce Jednostki bez Anuluj")
	assert_eq(QueuePanel.target_at(QueuePanel.row_rect(b.x, b.y, 5).get_center(), VIEW, b.x, b.y, 0, 3, 0),
			QueuePanel.Target.NONE, "pod listą pusto (zamyka ekran)")
	assert_eq(QueuePanel.target_at(QueuePanel.more_rect(VIEW, b.y).get_center(), VIEW, b.x, b.y, 1, fit + 2, 0),
			QueuePanel.Target.MORE, "Dalej przy przepełnionej liście")
	assert_eq(QueuePanel.next_first(fit + 2, fit, 0), fit, "Dalej: następna strona")
	assert_eq(QueuePanel.next_first(fit + 2, fit, fit), 0, "i znów pierwsza")
	assert_eq(QueuePanel.target_at(r1.get_center(), VIEW, b.x, b.y, 1, fit + 2, fit), QueuePanel.Target.ROW + fit + 1,
			"wiersz na drugiej stronie")
	assert_true(not QueuePanel.more_rect(VIEW, b.y).intersects(QueuePanel.action_rect(VIEW, b.y)), "Dalej obok akcji")
	assert_true(PixelFont.text_width(QueuePanel.footer_text(1, q, Recruitment.new(), _grid()) + " (+24)")
			< QueuePanel.more_rect(VIEW, b.y).position.x - b.x, "stopka nie wchodzi pod Dalej")
	# pusta zakładka i przyciski HUD
	assert_eq(Hud.queue_label(0), "Kolejka", "bez zleceń sama nazwa")
	assert_eq(Hud.queue_label(3), "Kolejka 3", "z licznikiem")
	assert_eq(Hud.queue_text_rect(b.y, "", "", "Epoka I · 550 r."), Rect2(), "bez budowy górny pasek nie otwiera Kolejki")
	var top := Hud.queue_text_rect(b.y, "0:42", "", "Epoka I · 550 r.")
	assert_true(top.has_point(Vector2(b.y - 5, 5)) and top.size.y >= 12, "czas budowy na górnym pasku to cel dotyku")
	assert_true(Hud.column_rect(b.y, Hud.column_targets(false).size() - 1, true).end.y < VIEW.y - Hud.BAR_H,
			"7 przycisków kolumny nad paskiem komunikatu")
	return true


func test_tabs_open_and_switch() -> bool:
	var grid := _grid()
	var panel := QueuePanel.new()
	panel.queue = BuildQueue.new()
	panel.recruitment = Recruitment.new()
	panel.grid = grid
	panel.recruitment.orders.append(Recruitment.Order.new())
	panel.open()
	assert_eq(panel.tab, QueuePanel.Tab.UNITS, "tylko szkolenie: otwiera Jednostki")
	var spot := grid.spot_near(grid.buildings[grid.manor_id()].position, K.TOWER, 30)
	panel.queue.order_build(grid, _rich_economy(), spot.position, K.TOWER, T0)
	panel.open()
	assert_eq(panel.tab, QueuePanel.Tab.BUILDINGS, "z budową: Budynki")
	var events: Array[String] = []
	panel.closed.connect(func() -> void: events.append("zamknij"))
	panel.focus_requested.connect(func(id: int) -> void: events.append("budynek %d" % id))
	panel.army_requested.connect(func() -> void: events.append("wojsko"))
	panel.activate(QueuePanel.Target.ROW + 0)
	assert_eq(events, ["zamknij", "budynek %d" % panel.queue.placed_id] as Array[String], "wiersz: mapa i budynek")
	panel.open()
	panel.activate(QueuePanel.Target.NONE)
	assert_true(not panel.visible, "dotknięcie pustego miejsca zamyka")
	panel.open()
	panel.tab = QueuePanel.Tab.UNITS
	panel.recruitment.orders.clear()
	panel.activate(QueuePanel.Target.ACTION)
	assert_eq(events[-1], "wojsko", "pusta zakładka Jednostki: Wojsko")
	panel.free()
	return true
