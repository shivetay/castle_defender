extends TestCase
## Ekran planowania ataku (#17): zamek-cel z seeda, edycja planu przyciskami i dotykiem mapy,
## układ na ekranie 320×180 i zapis planu w grze (wersja 6).

const K := BuildingTypes.Kind
const U := UnitTypes.Unit
const M := AttackPlan.Manoeuvre
const ST := AttackPlan.Start
const VIEW := Vector2(320, 180)


func test_bot_castle_is_deterministic_and_complete() -> bool:
	var a := BotCastle.generate(BotCastle.seed_for(1337, 0), 0)
	var b := BotCastle.generate(BotCastle.seed_for(1337, 0), 0)
	assert_eq(a.grid.save_data(), b.grid.save_data(), "ten sam seed: ten sam zamek")
	assert_eq(a.defenders, b.defenders, "ta sama załoga")
	assert_true(a.objective != 0 and a.grid.kinds[a.objective] == K.KEEP, "donżon jako cel")
	var kinds := {}
	for id: int in a.grid.kinds:
		kinds[a.grid.kinds[id]] = int(kinds.get(a.grid.kinds[id], 0)) + 1
	assert_true(int(kinds.get(K.PALISADE, 0)) > 8, "pierścień palisady")
	assert_eq(int(kinds.get(K.GATE, 0)), 1, "brama")
	assert_true(kinds.has(K.LUMBER_HUT), "drewno do podpalenia poza pierścieniem")
	assert_true(BotCastle.seed_for(1337, 0) != BotCastle.seed_for(1337, 1), "kolejny zamek jest inny")
	var strong := BotCastle.generate(BotCastle.seed_for(1337, 3), 3)
	var towers := 0
	var defenders := 0
	for id: int in strong.grid.kinds:
		if strong.grid.kinds[id] == K.TOWER:
			towers += 1
	for sq: Array in strong.defenders:
		defenders += int(sq[1])
	assert_true(towers >= 1, "mocniejszy zamek ma wieże")
	assert_true(defenders > 4, "i większą załogę")
	return true


func test_buttons_cycle_order_parameters() -> bool:
	assert_eq(AttackPlanner.next_manoeuvre(M.FRONTAL, 0), M.RANGED, "Manewr: kolejny")
	assert_eq(AttackPlanner.next_manoeuvre(M.FLANK, 0), M.FRONTAL, "w epoce I bez drabin i taranu")
	assert_eq(AttackPlanner.next_manoeuvre(M.FLANK, 1), M.LADDERS, "w epoce II drabiny")
	var p := AttackPlan.new()
	var o := p.add(2, M.FRONTAL)
	var seen: Array[String] = []
	for i in 6:
		seen.append(AttackPlanner.start_text(o))
		AttackPlanner.next_start(o, 3)
	assert_eq(seen, ["od razu", "po 10 s", "po 20 s", "po 30 s", "po oddz. 1", "po oddz. 3"] as Array[String],
			"Start: czas, potem inne oddziały (bez siebie)")
	assert_eq(AttackPlanner.start_text(o), "od razu", "i znów od razu")
	assert_eq(AttackPlanner.next_retreat(0), 30, "Odwrót 30%")
	assert_eq(AttackPlanner.next_retreat(70), 0, "po 70% znów nigdy")
	return true


func test_map_taps_set_target_and_route() -> bool:
	var bot := BotCastle.generate(BotCastle.seed_for(1337, 0), 0)
	var p := AttackPlan.new()
	AttackPlanner.fit_plan(p, 3)
	assert_eq(p.orders.size(), 3, "każdy oddział ma rozkaz")
	var o := p.order_for(1)
	var gate_cell := Vector2i(-1, -1)
	for id: int in bot.grid.kinds:
		if bot.grid.kinds[id] == K.GATE:
			gate_cell = bot.grid.buildings[id].position
	assert_eq(AttackPlanner.tap(o, bot.grid, gate_cell), "Cel: Brama drewniana", "budynek to cel")
	assert_eq(o.target, gate_cell, "cel zapisany")
	var grass: Array[Vector2i] = []
	for y in range(bot.spawn.y - 8, bot.spawn.y):
		var c := Vector2i(bot.spawn.x, y)
		if bot.grid.terrain.in_bounds(c) and bot.grid.building_at(c) == 0 \
				and bot.grid.terrain.get_tile(c) != TerrainMap.Tile.WATER:
			grass.append(c)
	assert_true(grass.size() >= 4, "trawa przy wejściu")
	for i in 3:
		AttackPlanner.tap(o, bot.grid, grass[i])
	assert_eq(o.waypoints.size(), 3, "trzy punkty trasy")
	AttackPlanner.tap(o, bot.grid, grass[3])
	assert_eq(o.waypoints, [grass[3]] as Array[Vector2i], "czwarty zaczyna trasę od nowa")
	var arrow := AttackPlanner.arrow_cells(o, bot)
	assert_eq(arrow[0], bot.spawn, "strzałka od wejścia")
	assert_eq(arrow[-1], gate_cell, "do celu")
	AttackPlanner.clear(o)
	assert_eq(AttackPlanner.arrow_cells(o, bot)[-1], bot.grid.buildings[bot.objective].get_center(), "bez celu: donżon")
	# Oskrzydlenie bez trasy: strzałka idzie przez ten sam punkt obejścia, który wyznaczy bitwa
	o.manoeuvre = M.FLANK
	var flank := AttackPlanner.arrow_cells(o, bot)
	assert_eq(flank.size(), 3, "wejście, obejście, cel")
	var battle := Battle.create_squads(bot.grid, bot.objective, [[U.PEASANT, 2]], [], bot.spawn, 1)
	assert_eq(flank[1], battle.flank_point(o), "ten sam punkt co w bitwie")
	o.flank_left = false
	assert_eq(AttackPlanner.arrow_cells(o, bot)[1], battle.flank_point(o), "także z prawej")
	p.orders.append(AttackPlan.Order.new())
	p.orders[-1].squad = 5
	AttackPlanner.fit_plan(p, 2)
	assert_eq(p.orders.size(), 2, "rozkazy spoza armii wypadają")
	assert_eq(AttackPlanner.line_pixels(Vector2i(0, 0), Vector2i(3, 1)).size(), 4, "kreska w całych pikselach")
	return true


func test_layout_fits_and_targets() -> bool:
	var left := float(Hud.CORNER_INSET)
	var right := VIEW.x - Hud.CORNER_INSET
	for i in AttackPanel.COLUMN.size():
		var r := Hud.column_rect(right, i)
		assert_true(r.end.y < AttackPanel.info_rect(VIEW, left, right).position.y, "kolumna nad opisem rozkazu")
		assert_true(PixelFont.text_width(AttackPanel.LABELS[i]) <= Hud.BUTTON_SIZE.x - 2, "„%s” na przycisku" % AttackPanel.LABELS[i])
		assert_eq(AttackPanel.target_at(r.get_center(), VIEW, left, right, 3), AttackPanel.COLUMN[i], "przycisk %d" % i)
	var max_tiles := AttackPlan.max_squads(0)
	var last := AttackPanel.squad_rect(VIEW, left, max_tiles - 1)
	assert_true(last.end.x <= right, "pasek oddziałów mieści się w epoce I")
	assert_true(last.end.y <= VIEW.y - Hud.BAR_H, "nad paskiem komunikatu")
	assert_eq(AttackPanel.target_at(AttackPanel.squad_rect(VIEW, left, 1).get_center(), VIEW, left, right, 3),
			AttackPanel.Target.SQUAD + 1, "drugi oddział")
	assert_eq(AttackPanel.target_at(Vector2(100, 60), VIEW, left, right, 3), AttackPanel.Target.NONE, "mapa wolna")
	var info := AttackPanel.info_rect(VIEW, left, right)
	for m in AttackPlan.MANOEUVRE_NAMES.size():
		for st: Array in [[ST.NOW, 0], [ST.AFTER_SECONDS, 30], [ST.AFTER_SQUAD, 3]]:
			var o := AttackPlan.Order.new()
			o.manoeuvre = m
			o.start = int(st[0])
			o.start_value = int(st[1])
			o.retreat_percent = 70
			var text := AttackPlanner.describe(o)
			var w := PixelFont.text_width("8. " + text[0]) + PixelFont.text_width(text[1]) + 8
			assert_true(w <= info.size.x, "opis rozkazu mieści się: %s / %s" % text)
	for won: bool in [true, false]:
		assert_true(PixelFont.text_width(MAIN.attack_end_message(won, 30)) <= Hud.MESSAGE_MAX_WIDTH, "komunikat po ataku")
	return true


const MAIN := preload("res://scripts/main.gd")


func test_plan_saves_with_the_game() -> bool:
	var grid := BuildGrid.new(TerrainMap.generate(1337))
	var p := AttackPlan.new()
	var o := p.add(1, M.FLANK, Vector2i(10, 12))
	o.waypoints.append(Vector2i(5, 6))
	o.retreat_percent = 50
	var data := SaveGame.to_dict(1337, grid, Economy.new(0), BuildQueue.new(), Research.new(), Goods.new(0),
			Recruitment.new(), 2, p, 3)
	var s := SaveGame.from_dict(JSON.parse_string(JSON.stringify(data)) as Dictionary, 0)
	assert_eq(s.attack_plan.to_dict(), p.to_dict(), "plan po odczycie")
	assert_eq(s.bots_beaten, 3, "zdobyte zamki po odczycie")
	var old := (JSON.parse_string(JSON.stringify(data)) as Dictionary)
	old["version"] = 5
	old.erase("attack")
	var migrated := SaveGame.from_dict(old, 0)
	assert_eq(migrated.attack_plan.orders.size(), 0, "zapis v5: pusty plan")
	assert_eq(migrated.bots_beaten, 0, "zapis v5: zero zdobytych")
	return true


## Pełny atak według planu na zamku-celu: przebieg powtarzalny, plan z ekranu działa w bitwie.
func test_attack_on_bot_follows_the_plan() -> bool:
	var bot := BotCastle.generate(BotCastle.seed_for(1337, 0), 0)
	var army := [[U.AXE_WARRIOR, 8], [U.ARCHER, 4], [U.PEASANT, 6]]
	var p := AttackPlan.new()
	AttackPlanner.fit_plan(p, army.size())
	p.order_for(2).manoeuvre = M.RANGED
	p.order_for(3).manoeuvre = M.FLANK
	var a := Battle.create_squads(bot.grid, bot.objective, army, bot.defenders, bot.spawn, 5)
	a.set_plan(p)
	var b := Battle.create_squads(bot.grid, bot.objective, army, bot.defenders, bot.spawn, 5)
	b.set_plan(AttackPlan.from_dict(p.to_dict()))
	a.run()
	b.run()
	assert_true(a.winner != Battle.Winner.NONE, "atak się rozstrzyga")
	assert_eq(a.checksum(), b.checksum(), "deterministycznie")
	return true
