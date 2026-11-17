extends TestCase
## 20 zamków-botów (#26): lista wspólna dla graczy, rosnąca trudność w epokach I–II, każdy zamek
## kompletny i deterministyczny, odblokowywanie po kolei, ekran wyboru celu i zapis celu.

const K := BuildingTypes.Kind
const U := UnitTypes.Unit
const VIEW := Vector2(320, 180)


func _kinds(bot: BotCastle) -> Dictionary:
	var out := {}
	for id: int in bot.grid.kinds:
		out[bot.grid.kinds[id]] = int(out.get(bot.grid.kinds[id], 0)) + 1
	return out


## Każdy z 20 zamków ma donżon jako cel, Dwór, bramę w pierścieniu, wejście na drodze i załogę.
func test_every_castle_is_complete() -> bool:
	assert_eq(BotRoster.COUNT, 20, "20 zamków")
	assert_eq(BotRoster.NAMES.size(), BotRoster.COUNT, "nazwa dla każdego")
	var seeds := {}
	for i in BotRoster.COUNT:
		var bot := BotRoster.generate(i)
		var kinds := _kinds(bot)
		assert_eq(bot.index, i, "numer zamku")
		assert_true(bot.objective != 0 and bot.grid.kinds[bot.objective] == K.KEEP, "%d: donżon jako cel" % i)
		assert_eq(int(kinds.get(K.MANOR, 0)), 1, "%d: Dwór" % i)
		assert_true(int(kinds.get(K.GATE, 0)) >= 1, "%d: brama" % i)
		assert_true(int(kinds.get(K.PALISADE, 0)) > 8, "%d: pierścień palisady" % i)
		assert_true(bot.grid.terrain.get_tile(bot.spawn) == TerrainMap.Tile.PATH, "%d: wejście na drodze" % i)
		assert_true(BotRoster.defender_count(i) > 0, "%d: załoga" % i)
		seeds[BotRoster.seed_of(i)] = true
	assert_eq(seeds.size(), BotRoster.COUNT, "każdy zamek ma inny seed")
	return true


## Ten sam numer zamku daje zawsze ten sam zamek i załogę (u każdego gracza, bez seeda świata).
func test_castles_are_deterministic_and_shared() -> bool:
	for i: int in [0, 7, 19]:
		var a := BotRoster.generate(i)
		var b := BotRoster.generate(i)
		assert_eq(a.grid.save_data(), b.grid.save_data(), "%d: ten sam zamek" % i)
		assert_eq(a.defenders, b.defenders, "%d: ta sama załoga" % i)
		assert_eq(a.spawn, b.spawn, "%d: to samo wejście" % i)
	return true


## Trudność nie maleje: poziom budynków, wieże, liczba obrońców i ich łączna siła (HP × atak).
func test_difficulty_grows() -> bool:
	var prev_power := 0
	for i in BotRoster.COUNT:
		var power := 0
		for d: Array in BotRoster.defenders(i):
			var row: Array = UnitTypes.UNITS[int(d[0])]
			power += int(d[1]) * int(row[3]) * int(row[4])
		if i > 0:
			assert_true(BotRoster.level_of(i) >= BotRoster.level_of(i - 1), "%d: poziom nie maleje" % i)
			assert_true(BotRoster.towers_of(i) >= BotRoster.towers_of(i - 1), "%d: wieże nie maleją" % i)
			assert_true(BotRoster.defender_count(i) > BotRoster.defender_count(i - 1), "%d: więcej obrońców" % i)
			assert_true(power > prev_power, "%d: silniejsza załoga" % i)
		prev_power = power
	assert_eq(BotRoster.level_of(0), 1, "pierwszy zamek na poziomie 1")
	assert_eq(BotRoster.level_of(BotRoster.COUNT - 1), BuildingTypes.MAX_LEVEL, "ostatni na poziomie 5")
	assert_eq(BotRoster.defenders(0), [[U.PEASANT, 4]], "pierwszy zamek: 4 Chłopów")
	return true


## Epoki: zamki 1–15 bronią tylko jednostki epoki I, 16–20 mają też jednostki epoki II.
## Od zamku 4 budynki rekrutacji, od zamku 11 zewnętrzny wał.
func test_ages_recruit_buildings_and_outer_wall() -> bool:
	for i in BotRoster.COUNT:
		var max_age := 0
		for d: Array in BotRoster.defenders(i):
			max_age = maxi(max_age, int((UnitTypes.UNITS[int(d[0])] as Array)[2]))
		assert_eq(max_age, BotRoster.age_of(i), "%d: epoka jednostek = epoka zamku" % i)
		var bot := BotRoster.generate(i)
		var kinds := _kinds(bot)
		for kind in BotRoster.recruit_buildings(i):
			assert_true(kinds.has(kind), "%d: stoi %s" % [i, BuildingTypes.NAMES[kind]])
		assert_eq(kinds.has(K.RAMPART), i >= BotRoster.OUTER_WALL_FROM, "%d: zewnętrzny wał" % i)
	assert_true(BotRoster.recruit_buildings(2).is_empty() and BotRoster.recruit_buildings(3).has(K.BARRACKS),
			"Koszary od zamku 4")
	return true


## Najtrudniejszy zamek da się zaatakować: bitwa kończy się w limicie czasu i daje ten sam wynik.
func test_hardest_castle_battle_runs() -> bool:
	var bot := BotRoster.generate(BotRoster.COUNT - 1)
	var army := [[U.AXE_WARRIOR, 10], [U.ARCHER, 10], [U.RIDER, 6]]
	var seed_value := PixelCanvas.hash2(bot.seed_value, bot.index, 0xa77) & 0x7fffffff
	var a := Battle.create_squads(bot.grid, bot.objective, army, bot.defenders, bot.spawn, seed_value)
	a.run()
	var b := Battle.create_squads(bot.grid, bot.objective, army, bot.defenders, bot.spawn, seed_value)
	b.run()
	assert_true(a.winner != Battle.Winner.NONE, "bitwa się kończy")
	assert_eq(a.checksum(), b.checksum(), "deterministycznie")
	return true


## Odblokowanie po kolei: dostępne są zdobyte i następny; po 20 zdobytych wszystkie (ostatni dalej).
func test_unlocking() -> bool:
	assert_true(BotRoster.is_unlocked(0, 0) and not BotRoster.is_unlocked(1, 0), "nowy gracz: tylko pierwszy")
	assert_true(BotRoster.is_unlocked(3, 3) and not BotRoster.is_unlocked(4, 3), "po 3 zdobytych: czwarty")
	assert_true(BotRoster.is_beaten(2, 3) and not BotRoster.is_beaten(3, 3), "zdobyte to te przed celem")
	assert_eq(BotRoster.last_unlocked(25), BotRoster.COUNT - 1, "więcej zdobyć niż zamków: ostatni")
	assert_true(BotRoster.is_unlocked(BotRoster.COUNT - 1, BotRoster.COUNT), "po wszystkich dalej można atakować")
	return true


## Ekran wyboru: siatka 5×4 mieści się między paskami, dotknięcia trafiają w kafelki i przyciski,
## a opis każdego zamku mieści się na 320 px.
func test_picker_layout() -> bool:
	var b := Hud.content_bounds(VIEW, Rect2())
	var tiles := BotPicker.tile_rects(b.x, b.y)
	assert_eq(tiles.size(), BotRoster.COUNT, "kafelek na zamek")
	for r in tiles:
		assert_true(r.size.x >= 12 and r.size.y >= 12, "cel ≥ 12×12")
		assert_true(r.position.x >= b.x and r.end.x <= b.y, "w poziomie")
	assert_true(tiles[-1].end.y < BotPicker.DETAIL_Y, "siatka nad opisem")
	assert_eq(BotPicker.target_at(tiles[7].get_center(), VIEW, b.x, b.y), BotPicker.Target.TILE + 7, "kafelek 8")
	assert_eq(BotPicker.target_at(BotPicker.plan_rect(VIEW, b.y).get_center(), VIEW, b.x, b.y), BotPicker.Target.PLAN, "Planuj")
	assert_eq(BotPicker.target_at(BotPicker.close_rect(VIEW, b.y).get_center(), VIEW, b.x, b.y), BotPicker.Target.CLOSE, "Wróć")
	var width := int(b.y - b.x)
	for i in BotRoster.COUNT:
		var lines := BotPicker.detail_lines(i, 3, width)
		assert_true(lines.size() <= 4, "%d: najwyżej 4 linie" % i)
		var bottom := BotPicker.DETAIL_Y + lines.size() * (PixelFont.LINE + 1)
		assert_true(bottom <= BotPicker.plan_rect(VIEW, b.y).position.y, "%d: opis nad przyciskami" % i)
		for line: Array in lines:
			assert_true(PixelFont.text_width(line[0] as String) <= width, "„%s” mieści się" % line[0])
	assert_eq((BotPicker.detail_lines(9, 3, width)[-1] as Array)[0], BotPicker.LOCKED_TEXT, "zablokowany ma podpowiedź")
	return true


## Cel Wyprawy w zapisie; cel spoza odblokowanych (np. ręcznie zmieniony zapis) wraca na ostatni dostępny.
func test_target_survives_save() -> bool:
	var grid := BuildGrid.new(TerrainMap.generate(1337))
	var d := SaveGame.to_dict(1337, grid, Economy.new(0), BuildQueue.new(), null, null, null, 0, null, 5, null, 3)
	var s := SaveGame.from_dict(JSON.parse_string(JSON.stringify(d)) as Dictionary, 0)
	assert_eq(s.bots_beaten, 5, "zdobyte")
	assert_eq(s.attack_target, 3, "cel")
	d["attack"]["target"] = 12
	s = SaveGame.from_dict(JSON.parse_string(JSON.stringify(d)) as Dictionary, 0)
	assert_eq(s.attack_target, 5, "zablokowany cel wraca na ostatni dostępny")
	(d["attack"] as Dictionary).erase("target")
	s = SaveGame.from_dict(JSON.parse_string(JSON.stringify(d)) as Dictionary, 0)
	assert_eq(s.attack_target, 5, "stary zapis: najwyższy dostępny zamek")
	return true
