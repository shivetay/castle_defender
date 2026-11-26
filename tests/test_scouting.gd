extends TestCase
## Zwiad z mgłą wojny (#28): misja z Chaty tropicieli, koszt złoto + żywność, zmienna długość,
## wynik z seeda (sukces, częściowy, wykryci, porażka), raport w budynku i odsłonięty fragment zamku
## w planie ataku. Determinizm: ta sama misja daje zawsze ten sam wynik i ten sam obszar.

const MAIN := preload("res://scripts/main.gd")
const T0 := 1_700_000_000_000
const K := BuildingTypes.Kind
const U := UnitTypes.Unit
const R := EconomyConfig.Res
const O := ScoutConfig.Outcome
const RES := Scouting.Result
const VIEW := Vector2(320, 180)


func _free_cell(grid: BuildGrid, kind: int) -> Vector2i:
	var c := grid.terrain.center()
	for r in grid.terrain.size:
		for dy in range(-r, r + 1):
			for dx in range(-r, r + 1):
				var p := c + Vector2i(dx, dy)
				if grid.placement_for(p, kind) != Rect2i():
					return p
	return Vector2i(-1, -1)


## Zamek gotowy do zwiadu: Chata tropicieli, S1, 3 Tropicieli w armii i zapasy.
func _castle(trackers: int = 3) -> Dictionary:
	var grid := BuildGrid.new(TerrainMap.generate(1337))
	grid.place_kind(_free_cell(grid, K.MANOR), K.MANOR, 1)
	grid.place_kind(_free_cell(grid, K.SCOUT_HOUSE), K.SCOUT_HOUSE, 1)
	var r := Research.new()
	r.done["S1"] = true
	var rec := Recruitment.new()
	if trackers > 0:
		rec.add_squad(U.TRACKER, trackers)
	rec.add_squad(U.AXE_WARRIOR, 4)
	var e := Economy.new(T0)
	for res in EconomyConfig.count():
		e.amounts[res] = 500
	return {"grid": grid, "r": r, "rec": rec, "e": e}


func _send(s: Scouting, c: Dictionary, key: String = "bot:2", duration: int = 1) -> int:
	return s.send(key, "Gród", duration, 4242, T0, c["grid"], c["r"], c["rec"], c["e"])


func test_config_numbers_are_consistent() -> bool:
	for s3: bool in [false, true]:
		for towers in [0, 1, 3]:
			var sum := 0
			for p in ScoutConfig.chances(s3, towers):
				assert_true(p >= 0, "szansa nieujemna")
				sum += p
			assert_eq(sum, 100, "szanse sumują się do 100")
	var base := ScoutConfig.chances(false, 0)
	assert_true(ScoutConfig.chances(true, 0)[O.SUCCESS] > base[O.SUCCESS], "S3 poprawia szansę sukcesu")
	assert_true(ScoutConfig.chances(false, 1)[O.SUCCESS] < base[O.SUCCESS], "Wieża sygnałowa celu wykrywa zwiad")
	assert_eq(ScoutConfig.reveal_percent(0, 1, false), 20, "S1: krótki zwiad odsłania 20% zamku")
	assert_true(ScoutConfig.reveal_percent(2, 1, false) > ScoutConfig.reveal_percent(0, 1, false), "dłuższy zwiad: więcej")
	assert_eq(ScoutConfig.reveal_percent(0, 1, true), 30, "S3: +10% zasięgu")
	assert_true(ScoutConfig.reveal_percent(2, ScoutConfig.MAX_SCOUTS, true) < 100, "nawet pełny sukces to tylko część")
	assert_eq(ScoutConfig.cost(3), [0, 0, 30, 30] as Array[int], "koszt: złoto + żywność za zwiadowcę")
	assert_eq(ScoutConfig.survivors(O.SUCCESS, 4), 4, "sukces: wracają wszyscy")
	assert_eq(ScoutConfig.survivors(O.PARTIAL, 4), 2, "częściowy: wraca połowa")
	assert_eq(ScoutConfig.survivors(O.PARTIAL, 1), 1, "częściowy z jednym: wraca")
	assert_eq(ScoutConfig.survivors(O.ESCAPED, 4), 4, "wykryci uciekają")
	assert_eq(ScoutConfig.survivors(O.FAILED, 4), 0, "porażka: giną wszyscy")
	assert_eq(ScoutConfig.report_percent(O.PARTIAL, 40), 20, "częściowy: połowa danych")
	assert_eq(ScoutConfig.report_percent(O.ESCAPED, 40), 0, "wykryci: bez danych")
	assert_eq(ScoutConfig.outcome_for_roll(0, base), O.SUCCESS, "rzut 0: sukces")
	assert_eq(ScoutConfig.outcome_for_roll(99, base), O.FAILED, "rzut 99: porażka")
	return true


func test_cannot_send_without_building_tech_scouts_or_resources() -> bool:
	var s := Scouting.new()
	var c := _castle(0)
	assert_eq(_send(s, c), RES.NO_SCOUTS, "bez zwiadowców w budynku nie da się wysłać zwiadu")
	var no_house := _castle()
	no_house["grid"] = BuildGrid.new(TerrainMap.generate(1337))
	assert_eq(_send(s, no_house), RES.NO_BUILDING, "bez Chaty tropicieli")
	var no_tech := _castle()
	no_tech["r"] = Research.new()
	assert_eq(_send(s, no_tech), RES.NO_TECH, "zwiad wymaga S1")
	var poor := _castle()
	(poor["e"] as Economy).amounts[R.GOLD] = 0
	assert_eq(_send(s, poor), RES.NO_RESOURCES, "bez złota")
	var ok := _castle()
	assert_eq(s.send("", "x", 0, 1, T0, ok["grid"], ok["r"], ok["rec"], ok["e"]), RES.BAD_TARGET, "bez celu")
	assert_eq(_send(s, ok), RES.OK, "z budynkiem, S1, zwiadowcami i zapasami")
	assert_eq(_send(s, _castle()), RES.BUSY, "naraz jedna misja")
	return true


func test_send_takes_scouts_and_cost_and_report_brings_survivors_back() -> bool:
	var s := Scouting.new()
	var c := _castle(3)
	var rec: Recruitment = c["rec"]
	var e: Economy = c["e"]
	assert_eq(_send(s, c, "bot:2", 1), RES.OK, "wysłany")
	assert_eq(rec.army_of(U.TRACKER), 0, "Tropiciele wyszli z armii")
	assert_eq(rec.army_of(U.AXE_WARRIOR), 4, "reszta armii zostaje")
	assert_eq(e.amounts[R.GOLD], 470, "złoto zeszło")
	assert_eq(e.amounts[R.FOOD], 470, "żywność zeszła")
	assert_eq(s.mission.sent(), 3, "3 zwiadowców")
	var end := T0 + ScoutConfig.duration_ms(1)
	assert_true(s.update(end - 1, rec) == null, "przed czasem nie ma raportu")
	assert_eq(s.remaining_ms(end - 1000), 1000, "odliczanie")
	var rep := s.update(end, rec)
	assert_true(rep != null and not s.is_busy(), "po czasie raport")
	assert_eq(rec.army_of(U.TRACKER), rep.returned, "ocaleli wrócili do armii")
	assert_eq(rep.returned, ScoutConfig.survivors(rep.outcome, 3), "ocaleli według wyniku")
	assert_true(s.report_for("bot:2") == rep, "raport przy celu")
	assert_true(not Scouting.report_text(rep).is_empty(), "tekst raportu")
	return true


func test_same_mission_gives_same_result_and_outcomes_vary() -> bool:
	var a := Scouting.new()
	var b := Scouting.new()
	var ca := _castle()
	var cb := _castle()
	_send(a, ca)
	_send(b, cb)
	assert_eq(a.mission.seed_value, b.mission.seed_value, "ten sam seed misji")
	var ra := Scouting.resolve(a.mission)
	var rb := Scouting.resolve(b.mission)
	assert_eq([ra.outcome, ra.percent, ra.returned, ra.region_seed], [rb.outcome, rb.percent, rb.returned, rb.region_seed],
			"ta sama misja: ten sam wynik")
	var seen := {}
	for i in 200:
		var m := Scouting.Mission.new()
		m.target_key = "bot:1"
		m.units = {U.TRACKER: 2}
		m.seed_value = Scouting.mission_seed(77, i, m.target_key)
		seen[Scouting.resolve(m).outcome] = true
	assert_eq(seen.size(), ScoutConfig.OUTCOME_NAMES.size(), "zdarzają się wszystkie wyniki")
	assert_true(Scouting.mission_seed(77, 1, "bot:1") != Scouting.mission_seed(77, 2, "bot:1"), "kolejna misja: inny seed")
	return true


func test_partial_return_puts_scouts_back_by_unit() -> bool:
	var rec := Recruitment.new()
	var units: Dictionary[int, int] = {U.TRACKER: 2, U.SCOUT: 2}
	Scouting._return_units(rec, units, 3)
	assert_eq(rec.army_of(U.TRACKER), 2, "najpierw Tropiciele")
	assert_eq(rec.army_of(U.SCOUT), 1, "potem Zwiadowcy")
	var c := _castle(3)
	var avail := Scouting.available(c["rec"] as Recruitment)
	assert_eq(avail, {U.TRACKER: 3} as Dictionary[int, int], "dostępni zwiadowcy")
	return true


func test_save_and_load_keep_mission_and_reports() -> bool:
	var s := Scouting.new()
	var c := _castle()
	_send(s, c, "bot:4", 2)
	var done := Scouting.new()
	var c2 := _castle()
	_send(done, c2, "bot:1", 0)
	done.update(T0 + ScoutConfig.duration_ms(0), c2["rec"] as Recruitment)
	s.reports = done.reports
	var copy := Scouting.new()
	assert_eq(copy.load_data(JSON.parse_string(JSON.stringify(s.save_data())) as Dictionary, T0 + 5), 0, "nic nie pominięto")
	assert_eq(copy.save_data(), s.save_data(), "ten sam stan po wczytaniu")
	assert_eq(copy.mission.seed_value, s.mission.seed_value, "seed misji z zapisu")
	var rep_a := Scouting.resolve(copy.mission)
	var rep_b := Scouting.resolve(s.mission)
	assert_eq(rep_a.outcome, rep_b.outcome, "po wczytaniu ten sam wynik")
	var future := s.save_data()
	(future["mission"] as Dictionary)["start_ms"] = T0 + 999_999
	copy.load_data(future, T0)
	assert_eq(copy.mission.start_ms, T0, "start z przyszłości przesunięty")
	var bad := {"reports": [{"key": "", "outcome": 0}, "x", {"key": "bot:1", "outcome": 9}],
			"mission": {"key": "bot:1", "units": [[U.AXE_WARRIOR, 3]]}}
	assert_eq(copy.load_data(bad, T0), 4, "złe wpisy pominięte")
	assert_true(not copy.is_busy() and copy.reports.is_empty(), "bez złych danych")
	return true


func test_save_game_v10_keeps_scouting_and_migrates_v9() -> bool:
	var c := _castle()
	var s := Scouting.new()
	_send(s, c)
	var grid: BuildGrid = c["grid"]
	var save := SaveGame.to_dict(1337, grid, c["e"], BuildQueue.new(), c["r"], null, c["rec"], 0, null, 0, null, 0,
			null, s)
	assert_eq(save["version"], SaveGame.FORMAT_VERSION, "bieżąca wersja")
	var st := SaveGame.from_dict(save, T0)
	assert_true(st.scouting.is_busy() and st.scouting.mission.target_key == "bot:2", "misja z zapisu")
	var old := save.duplicate(true)
	old["version"] = 9
	old.erase("scout")
	var migrated := SaveGame.from_dict(old, T0)
	assert_true(migrated != null and not migrated.scouting.is_busy(), "zapis v9: bez zwiadu")
	return true


func test_region_is_part_of_castle_and_deterministic() -> bool:
	var box := Rect2i(10, 12, 20, 16)
	var a := ScoutIntel.region_of(box, 35, 99)
	assert_eq(a, ScoutIntel.region_of(box, 35, 99), "ten sam raport: ten sam obszar")
	assert_true(box.encloses(a), "obszar w zabudowie")
	var area := a.size.x * a.size.y
	assert_true(area >= box.size.x * box.size.y * 35 / 100 and area < box.size.x * box.size.y, "ok. 35% i nie całość")
	assert_eq(ScoutIntel.region_of(box, 0, 99), ScoutIntel.NONE, "bez danych nic")
	assert_eq(ScoutIntel.region_of(Rect2i(), 50, 1), ScoutIntel.NONE, "bez zabudowy nic")
	var seen := {}
	for sd in 30:
		seen[ScoutIntel.region_of(box, 20, sd).position] = true
	assert_true(seen.size() > 1, "inny raport: inny fragment")
	assert_eq(ScoutIntel.isqrt(9999), 99, "pierwiastek całkowity")
	return true


func test_intel_shows_only_what_is_in_the_region() -> bool:
	var grid := BuildGrid.new(TerrainMap.generate(1337))
	var defense := DefensePlan.new()
	defense.add_trap(TrapConfig.Kind.LOGS, Vector2i(5, 5))
	defense.add_trap(TrapConfig.Kind.LOGS, Vector2i(30, 30))
	var o := DefensePlan.Order.new()
	o.task = DefensePlan.Task.PATROL
	o.post = Vector2i(6, 6)
	o.route = [Vector2i(20, 6)] as Array[Vector2i]
	defense.orders[1] = o
	var hold := DefensePlan.Order.new()
	hold.task = DefensePlan.Task.PATROL
	hold.post = Vector2i(40, 40)
	hold.route = [Vector2i(41, 40)] as Array[Vector2i]
	defense.orders[2] = hold
	var posts: Array = [[0, Vector2i(7, 7)], [2, Vector2i(35, 35)]]
	var area := Rect2i(4, 4, 6, 6)
	var intel := ScoutIntel.build(area, posts, defense)
	assert_eq(intel.squads, [[0, Vector2i(7, 7)]], "oddział w obszarze")
	assert_eq(intel.traps, [[TrapConfig.Kind.LOGS, Vector2i(5, 5)]], "pułapka w obszarze")
	assert_eq(intel.patrols.size(), 1, "patrol z punktem w obszarze")
	assert_eq(ScoutIntel.mark_traps(defense, area), 1, "pole odsłonięta (#100)")
	assert_true(defense.traps[0].revealed and not defense.traps[1].revealed, "tylko w obszarze")
	var none := ScoutIntel.build(ScoutIntel.NONE, posts, defense)
	assert_true(none.is_empty() and none.squads.is_empty() and none.traps.is_empty(), "bez zwiadu nic")
	assert_eq(ScoutIntel.mark_traps(defense, ScoutIntel.NONE), 0, "bez zwiadu pułapki ukryte")
	assert_true(grid != null, "siatka")
	return true


func test_plan_hides_buildings_outside_the_region() -> bool:
	var bot := BotRoster.generate(3)
	var all := AttackPlanner.hidden_ids(bot.grid, ScoutIntel.new())
	assert_eq(all.size(), bot.grid.buildings.size(), "bez zwiadu: wszystkie budynki to zarys")
	var keep := bot.grid.buildings[bot.objective]
	var o := AttackPlan.Order.new()
	assert_eq(AttackPlanner.tap(o, bot.grid, keep.position, ScoutIntel.new()), AttackPlanner.HIDDEN_TARGET,
			"cel bez rodzaju poza zwiadem")
	assert_eq(o.target, keep.position, "ale cel się ustawia")
	var intel := ScoutIntel.new()
	intel.region = keep
	assert_true(not AttackPlanner.hidden_ids(bot.grid, intel).has(bot.objective), "odsłonięty donżon widać")
	assert_eq(AttackPlanner.tap(o, bot.grid, keep.position, intel), "Cel: Wieża grodowa", "odsłonięty: z rodzajem")
	assert_eq(AttackPlanner.tap(o, bot.grid, keep.position), "Cel: Wieża grodowa", "bez mgły (stary kod): z rodzajem")
	# miejsca załogi bota z początku bitwy
	var b := Battle.create_squads(bot.grid, bot.objective, [[U.AXE_WARRIOR, 2]], bot.defenders, bot.spawn, 5)
	var posts := ScoutIntel.defender_posts(b)
	assert_eq(posts.size(), bot.defenders.size(), "miejsce każdego oddziału załogi")
	var full := ScoutIntel.build(ScoutIntel.castle_rect(bot.grid).grow(64), posts, null)
	assert_eq(full.squads.size(), posts.size(), "cały zamek: cała załoga")
	return true


## #355: mgła to jeden ciągły prostokąt zabudowy + 1 kratka, bez dziur między budynkami;
## odsłonięty fragment jest z niej wycięty, a kawałki mgły się nie nakładają.
func test_fog_covers_whole_castle_area_without_holes() -> bool:
	var bot := BotRoster.generate(3)
	var map := Rect2i(0, 0, bot.grid.terrain.size, bot.grid.terrain.size)
	var area := AttackPlanner.fog_area(bot.grid)
	assert_eq(area, ScoutIntel.castle_rect(bot.grid).grow(1).intersection(map), "zabudowa + 1 kratka")
	assert_eq(AttackPlanner.fog_rects(area, ScoutIntel.NONE), [area] as Array[Rect2i], "bez zwiadu: cała mgła")
	assert_eq(AttackPlanner.fog_rects(area, area.grow(3)).size(), 0, "pełny zwiad: bez mgły")
	assert_eq(AttackPlanner.fog_rects(area, Rect2i(-5, -5, 2, 2)), [area] as Array[Rect2i], "zwiad obok: cała mgła")
	var inner := Rect2i(area.position + Vector2i(2, 3), Vector2i(3, 2))
	for region: Rect2i in [inner, Rect2i(area.position, Vector2i(4, 4)), Rect2i(area.end - Vector2i(2, 2), Vector2i(5, 5))]:
		var parts := AttackPlanner.fog_rects(area, region)
		assert_true(parts.size() <= 4, "najwyżej 4 kawałki")
		assert_eq(parts, AttackPlanner.fog_rects(area, region), "deterministycznie")
		for y in range(area.position.y, area.end.y):
			for x in range(area.position.x, area.end.x):
				var c := Vector2i(x, y)
				var n := 0
				for r in parts:
					if r.has_point(c):
						n += 1
				assert_eq(n, 0 if region.has_point(c) else 1, "kratka %s: mgła raz albo wycięta" % c)
	# przy krawędzi mapy margines się przycina
	var edge := BuildGrid.new(bot.grid.terrain)
	edge.buildings[1] = Rect2i(0, 0, 2, 2)
	assert_eq(AttackPlanner.fog_area(edge), Rect2i(0, 0, 3, 3), "przycięte do mapy")
	assert_eq(AttackPlanner.fog_area(BuildGrid.new(bot.grid.terrain)), ScoutIntel.NONE, "bez budynków: bez mgły")
	return true


## #355: ramka ukrytego celu obejmuje tylko dotkniętą kratkę, żeby nie zdradzać kształtu budynku.
func test_hidden_target_frame_is_one_cell() -> bool:
	var bot := BotRoster.generate(3)
	var keep := bot.grid.buildings[bot.objective]
	var cell := keep.position + Vector2i.ONE
	assert_eq(AttackPlanner.target_frame(bot.grid, ScoutIntel.new(), cell), Rect2i(cell, Vector2i.ONE), "we mgle: kratka")
	var intel := ScoutIntel.new()
	intel.region = keep
	assert_eq(AttackPlanner.target_frame(bot.grid, intel, cell), keep, "odsłonięty: cały budynek")
	var empty := Vector2i(-1, -1)
	for y in bot.grid.terrain.size:
		if bot.grid.building_at(Vector2i(0, y)) == 0:
			empty = Vector2i(0, y)
			break
	assert_eq(AttackPlanner.target_frame(bot.grid, intel, empty), ScoutIntel.NONE, "pusta kratka: bez ramki")
	return true


func test_picker_lines_and_buttons() -> bool:
	var bot := TargetSearch.Target.new()
	bot.is_bot = true
	bot.bot_idx = 2
	bot.castle_name = "Gród"
	var s := Scouting.new()
	var units: Dictionary[int, int] = {U.TRACKER: 2}
	var lines: Array[String] = MAIN.scout_lines(bot, s, RES.OK, units, 1, false, T0)
	assert_eq(lines[0], "Bez zwiadu: plan pokaże tylko zarys budynków", "bez zwiadu")
	assert_eq(lines[1], "2 zwiad., 40% zamku, koszt 20 Ży 20 Zł", "co da zwiad")
	var player := TargetSearch.Target.new()
	player.player_id = "00000000-0000-0000-0000-000000000001"
	assert_eq(MAIN.scout_lines(player, s, RES.OK, units, 1, false, T0)[1], "Zwiad na gracza: wymaga sieci",
			"gracz bez sieci")
	assert_eq(MAIN.scout_lines(player, s, RES.OK, units, 1, false, T0, true)[1], "2 zwiad., 40% zamku, koszt 20 Ży 20 Zł",
			"gracz online: zwiad przez serwer")
	var c := _castle()
	_send(s, c, bot.key(), 0)
	assert_true((MAIN.scout_lines(bot, s, RES.BUSY, units, 0, false, T0 + 1000)[0] as String).begins_with("Zwiad w drodze"),
			"misja w drodze")
	assert_eq(MAIN.scout_card_info(s, T0), "Zwiad: Gród, %s" % Hud.format_time(ScoutConfig.duration_ms(0)), "karta budynku")
	var left := float(Hud.CORNER_INSET)
	var right := 320.0 - Hud.CORNER_INSET
	# przed kliknięciem Zwiad: tylko Boty i Zwiad obok siebie, bez czasu (#317)
	var closed: Array[Rect2] = [TargetPicker.bots_rect(VIEW, left), TargetPicker.scout_rect(VIEW, left, false),
			TargetPicker.plan_rect(VIEW, right), TargetPicker.close_rect(VIEW, right)]
	for i in closed.size():
		assert_true(closed[i].size.x >= 12 and closed[i].size.y >= 12, "cel dotyku co najmniej 12×12")
		assert_true(closed[i].position.x >= left and closed[i].end.x <= right, "w treści")
		for j in range(i + 1, closed.size()):
			assert_true(not closed[i].intersects(closed[j]), "przyciski się nie nakładają")
	assert_eq(TargetPicker.target_at(closed[1].get_center(), VIEW, left, right, false), TargetPicker.Target.SCOUT,
			"Zwiad bez czasu (na miejscu czasu)")
	assert_eq(TargetPicker.target_at(TargetPicker.scout_rect(VIEW, left, true).get_center(), VIEW, left, right, false),
			TargetPicker.Target.NONE, "pusty slot czasu przed odsłonięciem")
	# po odsłonięciu: Boty, czas, Zwiad
	var open: Array[Rect2] = [TargetPicker.bots_rect(VIEW, left), TargetPicker.scout_time_rect(VIEW, left),
			TargetPicker.scout_rect(VIEW, left, true), TargetPicker.plan_rect(VIEW, right),
			TargetPicker.close_rect(VIEW, right)]
	for i in open.size():
		for j in range(i + 1, open.size()):
			assert_true(not open[i].intersects(open[j]), "przyciski z czasem się nie nakładają")
	assert_eq(TargetPicker.target_at(open[2].get_center(), VIEW, left, right, true), TargetPicker.Target.SCOUT, "Zwiad")
	assert_eq(TargetPicker.target_at(open[1].get_center(), VIEW, left, right, true), TargetPicker.Target.SCOUT_TIME,
			"czas po Zwiadzie")
	var picker := TargetPicker.new()
	var sent: Array = []
	picker.scout_requested.connect(func(t: TargetSearch.Target, d: int) -> void: sent.append([t, d]))
	picker.open(0, false)
	picker.scout_enabled = true
	assert_true(not picker.scout_time_open, "open() chowa czas")
	picker._activate(TargetPicker.Target.SCOUT)
	assert_true(picker.scout_time_open and sent.is_empty(), "pierwsze Zwiad odsłania czas, bez wysyłki")
	picker._activate(TargetPicker.Target.SCOUT)
	assert_eq(sent.size(), 1, "drugie Zwiad wysyła misję")
	picker.open(0, false)
	assert_true(not picker.scout_time_open, "ponowne open() chowa czas")
	picker.free()
	var y := TargetPicker.SCOUT_Y + 2 * PixelFont.LINE
	assert_true(y < Hud.row_y(VIEW), "linie zwiadu nad przyciskami")
	return true


## Zwiad idzie na serwer (`castles.data`): po reinstalacji misja w drodze i jej zwiadowcy wracają.
func test_mission_survives_restore_from_server() -> bool:
	var c := _castle()
	var s := Scouting.new()
	_send(s, c)
	var save := SaveGame.to_dict(1337, c["grid"], c["e"], BuildQueue.new(), c["r"], null, c["rec"], 0, null, 0, null, 0,
			null, s)
	var remote := CastleSync.castle_data(save)
	var row := {"map_seed": 1337, "save_version": SaveGame.FORMAT_VERSION, "revision": 1,
			"data": JSON.parse_string(JSON.stringify(remote))}
	var st := SaveGame.from_dict(CastleSync.save_from_row(row), T0)
	assert_true(st.scouting.is_busy(), "misja z serwera")
	assert_eq(st.scouting.mission.seed_value, s.mission.seed_value, "ten sam seed")
	var rep := st.scouting.update(T0 + ScoutConfig.duration_ms(1), st.recruitment)
	assert_eq(st.recruitment.army_of(U.TRACKER), rep.returned, "ocaleli wracają do odtworzonej armii")
	return true
