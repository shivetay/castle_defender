extends TestCase
## Dwór z epokami i garnizon (#81): pojemność garnizonu z poziomu Dworu, przypisanie oddziału na ekranie
## Obrona, przycinanie zapisu spoza gry, premia wytrzymałości i miejsce przy donżonie w deterministycznej
## bitwie, garnizon poza armią ataku oraz własny wygląd Dworu na każdym poziomie epoki I i II.

const K := BuildingTypes.Kind
const U := UnitTypes.Unit
const T := DefensePlan.Task


func _castle(manor: int = 1) -> BuildGrid:
	var grid := BuildGrid.new(TerrainMap.generate(WorldSeed.first_playable(1337)))
	grid.place(grid.manor_spot(64), K.MANOR, manor)
	grid.place(grid.keep_spot(64), K.KEEP, 1)
	return grid


func _side(b: Battle, side: int) -> Array[Battle.Fighter]:
	var out: Array[Battle.Fighter] = []
	for f in b.fighters:
		if f.side == side:
			out.append(f)
	return out


func test_capacity_grows_with_manor_level() -> bool:
	assert_eq(RecruitmentConfig.GARRISON_PER_MANOR_LEVEL, 4, "decyzja właścicielki: 4 za poziom")
	for level in range(1, Ages.MAX_TOTAL_LEVEL + 1):
		var expected := 4 * level  # epoka II dokłada miejsca dalej (#262): do 40
		assert_eq(RecruitmentConfig.garrison_capacity(_castle(level)), expected, "Dwór %d: %d miejsc" % [level, expected])
	return true


func test_garrison_respects_limit() -> bool:
	var grid := _castle(1)  # 4 miejsca
	var rec := Recruitment.new()
	var a := rec.add_squad(U.AXE_WARRIOR, 3)
	var b := rec.add_squad(U.ARCHER, 2)
	var c := rec.add_squad(U.SHIELDBEARER, 1)
	var plan := DefensePlan.new()
	assert_true(plan.garrison_fits(a, rec, grid), "3 z 4 się mieści")
	plan.set_task(a, T.GARRISON)
	assert_eq(plan.garrison_units(rec), 3, "w garnizonie 3")
	assert_true(not plan.garrison_fits(b, rec, grid), "3 + 2 ponad 4")
	assert_true(plan.garrison_fits(c, rec, grid), "3 + 1 = 4 się mieści")
	assert_true(plan.garrison_fits(a, rec, grid), "oddział w garnizonie zawsze się mieści")
	# jednostki w szkoleniu do oddziału też zajmują miejsce
	var o := Recruitment.Order.new()
	o.unit = U.SHIELDBEARER
	o.squad_id = c
	rec.orders.append(o)
	assert_true(not plan.garrison_fits(c, rec, grid), "1 wyszkolony + 1 w szkoleniu ponad 4")
	assert_true(plan.garrison_fits(b, rec, _castle(2)), "Dwór 2: 8 miejsc")
	assert_eq(plan.order_for(a).post, DefensePlan.NO_POST, "garnizon nie ma własnego miejsca")
	return true


func test_panel_cycles_to_garrison_only_when_it_fits() -> bool:
	var grid := _castle(1)
	var rec := Recruitment.new()
	var a := rec.add_squad(U.AXE_WARRIOR, 4)
	var b := rec.add_squad(U.AXE_WARRIOR, 1)
	var plan := DefensePlan.new()
	var panel := DefensePanel.new()
	panel.recruitment = rec
	panel.open(plan, rec.battle_squads(), rec.battle_ids(), grid, 0)
	var options := DefensePanel.task_options(RecruitmentConfig.UnitClass.LIGHT, 0)
	assert_true(options.has(T.GARRISON) and options.back() == T.KEEP, "Garnizon przed Przy donżonie")
	plan.set_task(a, T.PATROL)
	panel.select(0)
	panel.activate(DefensePanel.Target.TASK)
	assert_eq(plan.order_for(a).task, T.GARRISON, "Patrol → Garnizon Dworu")
	assert_true(panel.describe(0)[1].ends_with("4/4"), "opis z zajętymi miejscami")
	plan.set_task(b, T.PATROL)
	panel.select(1)
	panel.activate(DefensePanel.Target.TASK)
	assert_eq(plan.order_for(b).task, T.KEEP, "pełny Dwór: przeskok na Przy donżonie")
	assert_true(not plan.in_garrison(b), "drugi oddział poza garnizonem")
	assert_true(panel.tap(grid, grid.buildings[grid.keep_id()].position + Vector2i(0, 3)).begins_with("Przy donżonie"),
			"przy donżonie mapa nie zmienia zadania")
	panel.select(0)
	assert_true(panel.tap(grid, grid.buildings[grid.keep_id()].position + Vector2i(0, 3)).begins_with("Garnizon Dworu"),
			"garnizon też nie bierze miejsca z mapy")
	assert_eq(plan.order_for(a).task, T.GARRISON, "zadanie zostaje")
	for text: String in ["Garnizon pełny 20/20, Oddział 10: Przy donżonie", "Oddział 10: Garnizon Dworu 20/20",
			"Całe wojsko w garnizonie Dworu: zmień w Obronie"]:
		assert_true(PixelFont.text_width(text) <= Hud.MESSAGE_MAX_WIDTH, "„%s” mieści się" % text)
	panel.free()
	return true


func test_save_keeps_garrison() -> bool:
	var plan := DefensePlan.new()
	plan.set_task(3, T.GARRISON)
	plan.set_task(5, T.HOLD)
	var back := DefensePlan.from_dict(JSON.parse_string(JSON.stringify(plan.to_dict())) as Dictionary)
	assert_eq(back.garrison_ids(), [3] as Array[int], "garnizon przetrwał zapis")
	assert_true(not back.in_garrison(5), "inne zadania bez zmian")
	return true


## Zapis spoza gry (kopia zamku z serwera) może mieć garnizon ponad pojemność: premię dostają oddziały
## w kolejności armii, dopóki mieszczą się w Dworze, a reszta stoi przy donżonie bez premii.
func test_battle_garrison_is_clamped_to_capacity() -> bool:
	var grid := _castle(1)
	var plan := DefensePlan.new()
	var ids: Array[int] = [1, 2, 3, 4]
	var squads := [[U.AXE_WARRIOR, 3], [U.ARCHER, 3], [U.SHIELDBEARER, 1], [U.AXE_WARRIOR, 2]]
	for id: int in [1, 2, 3]:
		plan.set_task(id, T.GARRISON)
	assert_eq(plan.battle_garrison(ids, squads, grid), [true, false, true, false] as Array[bool], "3 + 1 w 4 miejscach")
	assert_eq(plan.battle_garrison(ids, squads, null), [false, false, false, false] as Array[bool], "bez zamku bez premii")
	var orders := plan.battle_orders(ids, squads, grid, 0)
	assert_eq(orders[0].task, T.GARRISON, "garnizon idzie do bitwy")
	assert_true(orders[1] == null, "ponad pojemność: przy donżonie")
	assert_eq(orders[2].task, T.GARRISON, "mieści się dalej w kolejności")
	return true


func test_garrison_defends_keep_with_more_hp() -> bool:
	var grid := _castle(2)
	var spawn := BotCastle.edge_road(grid.terrain)
	var plan := DefensePlan.new()
	var ids: Array[int] = [1, 2, 3]
	var squads := [[U.AXE_WARRIOR, 4], [U.ARCHER, 2], [U.AXE_WARRIOR, 4]]
	plan.set_task(1, T.GARRISON)
	plan.set_task(2, T.GARRISON)
	var b := Battle.for_castle_squads(grid, [[U.AXE_WARRIOR, 6]], squads, spawn, 7, null,
			plan.battle_orders(ids, squads, grid, 0))
	assert_eq(b.garrison, {1: true, 2: true} as Dictionary[int, bool], "dwa oddziały w garnizonie")
	var keep := b.structures[b.objective]
	var on_keep := 0
	for f in _side(b, Battle.Side.DEFENDER):
		var base := UnitTypes.hp(f.unit)
		if f.squad <= 2:
			assert_eq(f.hp, base * BattleConfig.GARRISON_HP_PERCENT / 100, "garnizon: +20% wytrzymałości")
		else:
			assert_eq(f.hp, base, "poza garnizonem bez premii")
		if f.squad == 2 and f.wall == keep.id:
			on_keep += 1
		if f.squad == 1:
			assert_true(maxi(absi(f.cell().x - keep.rect.get_center().x), absi(f.cell().y - keep.rect.get_center().y)) <= 4,
					"garnizon startuje przy donżonie")
	assert_eq(on_keep, 2, "strzelcy garnizonu na donżonie")
	for v in b.squads_view(Battle.Side.DEFENDER):
		if int(v["squad"]) == 1:
			assert_eq(int(v["max_hp"]), 4 * UnitTypes.hp(U.AXE_WARRIOR) * BattleConfig.GARRISON_HP_PERCENT / 100,
					"pasek oddziału z premią")
	return true


## Ten sam seed i ten sam garnizon dają ten sam przebieg, a garnizon zmienia przebieg (bierze udział w bitwie).
func test_garrison_battle_is_deterministic() -> bool:
	var grid := _castle(3)
	var spawn := BotCastle.edge_road(grid.terrain)
	var ids: Array[int] = [1, 2]
	var squads := [[U.AXE_WARRIOR, 6], [U.ARCHER, 4]]
	var attackers := [[U.AXE_WARRIOR, 10], [U.JAVELINEER, 6]]
	var plan := DefensePlan.new()
	plan.set_task(1, T.GARRISON)
	var sums: Array[int] = []
	for i in 2:
		var b := Battle.for_castle_squads(grid, attackers, squads, spawn, 99, null, plan.battle_orders(ids, squads, grid, 0))
		b.run(1200)
		sums.append(b.checksum())
	assert_eq(sums[0], sums[1], "powtórka identyczna")
	var plain := Battle.for_castle_squads(grid, attackers, squads, spawn, 99, null,
			DefensePlan.new().battle_orders(ids, squads, grid, 0))
	plain.run(1200)
	assert_true(plain.checksum() != sums[0], "garnizon zmienia przebieg")
	return true


func test_garrison_stays_home_from_attack() -> bool:
	var rec := Recruitment.new()
	var a := rec.add_squad(U.AXE_WARRIOR, 3)
	var b := rec.add_squad(U.ARCHER, 2)
	var plan := DefensePlan.new()
	plan.set_task(a, T.GARRISON)
	assert_eq(rec.battle_squads(plan.garrison_ids()), [[U.ARCHER, 2]], "do ataku bez garnizonu")
	assert_eq(rec.battle_ids(plan.garrison_ids()), [b] as Array[int], "id bez garnizonu")
	assert_eq(rec.battle_squads().size(), 2, "w obronie cała armia")
	return true


func test_manor_looks_different_on_every_level() -> bool:
	var seen := {}
	for level in range(1, Ages.MAX_TOTAL_LEVEL + 1):
		var img := BuildingArt.make_image(K.MANOR, level, BuildingTypes.State.INTACT)
		var again := BuildingArt.make_image(K.MANOR, level, BuildingTypes.State.INTACT)
		assert_eq(img.get_data(), again.get_data(), "poziom %d powtarzalny" % level)
		assert_true(not seen.has(img.get_data()), "poziom %d wygląda inaczej niż niższe" % level)
		seen[img.get_data()] = true
		for state in range(1, BuildingTypes.State.size()):
			var hurt := BuildingArt.make_image(K.MANOR, level, state)
			assert_true(hurt.get_data() != img.get_data(), "poziom %d: stan %d inny niż cały" % [level, state])
	var textures := BuildingTextures.new()
	assert_true(textures.draw_building(K.MANOR, 10) != textures.draw_building(K.MANOR, 6), "epoka II: osobne tekstury")
	assert_eq(textures.draw_building(K.TOWER, 10), textures.draw_building(K.TOWER, 6), "inne budynki: jeden rysunek")
	return true


## Serwer (migracja `garrison`) zna numer zadania garnizonu z gry.
func test_server_knows_garrison_task() -> bool:
	var sql := FileAccess.get_file_as_string("res://supabase/migrations/20261123180000_garrison.sql")
	assert_true(not sql.is_empty(), "migracja jest")
	assert_true(sql.contains("GARRISON = %d" % T.GARRISON), "numer zadania w komentarzu")
	assert_true(sql.contains("private.json_int(o.value -> 1, 0, 100) = %d" % T.GARRISON), "numer zadania w zapytaniu")
	return true
