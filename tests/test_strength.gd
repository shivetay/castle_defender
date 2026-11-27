extends TestCase
## Wskaźniki siły armii i obrony (#263): siła jednostki z HP i ataku, armia ze składu, obrona z załogi
## (garnizon z premią), pułapek i umocnień, determinizm i napisy na ekranach Wojsko i Obrona.

const K := BuildingTypes.Kind
const U := UnitTypes.Unit
const T := DefensePlan.Task


func _castle() -> BuildGrid:
	var grid := BuildGrid.new(TerrainMap.generate(WorldSeed.first_playable(1337)))
	grid.place(grid.manor_spot(64), K.MANOR, 1)
	grid.place(grid.keep_spot(64), K.KEEP, 1)
	return grid


func _trap(kind: int) -> DefensePlan.Trap:
	var t := DefensePlan.Trap.new()
	t.kind = kind
	return t


func test_unit_power_from_hp_and_attack() -> bool:
	assert_eq(Strength.unit_power(U.AXE_WARRIOR), 11, "Topornik: (60 + 5×10) / 10")
	assert_eq(Strength.unit_power(U.LANCER), 25, "Kopijnik: (140 + 5×22) / 10")
	assert_eq(Strength.unit_power(U.TRACKER), 0, "Tropiciel nie walczy")
	assert_eq(Strength.unit_power(U.WAGON), 0, "Wóz nie walczy")
	assert_eq(Strength.unit_power(-1), 0, "nieznany rodzaj")
	assert_eq(Strength.unit_power(UnitTypes.count()), 0, "poza tabelą")
	for u in UnitTypes.count():
		assert_true(Strength.unit_power(u) >= 0, "%s: nieujemna" % UnitTypes.unit_name(u))
	return true


func test_army_counts_trained_units_only() -> bool:
	var rec := Recruitment.new()
	assert_eq(Strength.army(rec), 0, "pusta armia")
	assert_eq(Strength.army(null), 0, "bez rekrutacji")
	rec.add_squad(U.AXE_WARRIOR, 4)
	rec.add_squad(U.ARCHER, 3)
	rec.add_squad(U.TRACKER, 2)
	var expected := 4 * Strength.unit_power(U.AXE_WARRIOR) + 3 * Strength.unit_power(U.ARCHER)
	assert_eq(Strength.army(rec), expected, "suma składu")
	rec.add_squad(U.RIDER, 0)
	assert_eq(Strength.army(rec), expected, "pusty oddział nic nie dodaje")
	return true


func test_garrison_gets_hp_bonus_in_crew() -> bool:
	var rec := Recruitment.new()
	var a := rec.add_squad(U.SHIELDBEARER, 4)
	var plan := DefensePlan.new()
	var base := Strength.crew(rec, plan)
	assert_eq(base, Strength.army(rec), "bez garnizonu załoga = armia")
	plan.set_task(a, T.GARRISON)
	var boosted := 4 * Strength.unit_power(U.SHIELDBEARER, BattleConfig.GARRISON_HP_PERCENT)
	assert_eq(Strength.crew(rec, plan), boosted, "garnizon z premią wytrzymałości")
	assert_true(boosted > base, "garnizon silniejszy")
	return true


func test_traps_add_to_defense() -> bool:
	var plan := DefensePlan.new()
	assert_eq(Strength.traps(plan), 0, "bez pułapek")
	assert_eq(Strength.TRAP_POWER.size(), TrapConfig.count(), "waga każdej pułapki")
	plan.traps.append(_trap(TrapConfig.Kind.PIT))
	plan.traps.append(_trap(TrapConfig.Kind.PITCH))
	assert_eq(Strength.traps(plan), Strength.TRAP_POWER[0] + Strength.TRAP_POWER[4], "dół i smoła")
	assert_eq(Strength.trap_power(99), 0, "nieznana pułapka")
	return true


func test_forts_count_walls_and_towers() -> bool:
	var grid := _castle()
	assert_eq(Strength.forts(grid), 0, "Dwór i donżon to nie umocnienia")
	assert_eq(Strength.fort_power(K.PALISADE, 1), 2, "palisada: 100 HP / 50")
	assert_eq(Strength.fort_power(K.TOWER, 1), 23, "wieża: 250 HP / 50 + 3 × atak 6")
	assert_true(Strength.fort_power(K.TOWER, 3) > Strength.fort_power(K.TOWER, 1), "wyższy poziom silniejszy")
	assert_eq(Strength.fort_power(K.TOWER, 0), 0, "plac budowy")
	assert_eq(Strength.fort_power(K.LUMBER_HUT, 3), 0, "budynek gospodarczy")
	var bot := BotCastle.generate(BotCastle.seed_for(1337, 5), 5)
	var expected := 0
	for id: int in bot.grid.kinds:
		expected += Strength.fort_power(bot.grid.kinds[id], bot.grid.levels[id])
	assert_true(expected > 0, "zamek-bot ma umocnienia")
	assert_eq(Strength.forts(bot.grid), expected, "suma po odcinkach")
	assert_eq(Strength.forts(null), 0, "bez siatki")
	return true


func test_defense_is_sum_and_deterministic() -> bool:
	var make := func() -> Array:
		var grid := BotCastle.generate(BotCastle.seed_for(42, 8), 8).grid
		var rec := Recruitment.new()
		var a := rec.add_squad(U.SPEARMAN, 6)
		rec.add_squad(U.ARCHER, 5)
		var plan := DefensePlan.new()
		plan.set_task(a, T.GARRISON)
		plan.traps.append(_trap(TrapConfig.Kind.CALTROPS))
		return [rec, plan, grid]
	var x: Array = make.call()
	var y: Array = make.call()
	var dx := Strength.defense(x[0] as Recruitment, x[1] as DefensePlan, x[2] as BuildGrid)
	var dy := Strength.defense(y[0] as Recruitment, y[1] as DefensePlan, y[2] as BuildGrid)
	assert_eq(dx, dy, "te same dane, ta sama siła")
	assert_eq(dx, Strength.crew(x[0] as Recruitment, x[1] as DefensePlan) + Strength.traps(x[1] as DefensePlan)
			+ Strength.forts(x[2] as BuildGrid), "załoga + pułapki + umocnienia")
	assert_eq(Strength.defense(null, null, null), 0, "pusty zamek")
	return true


func test_labels_fit_on_screens() -> bool:
	var left := float(Hud.CORNER_INSET)
	var right := 320.0 - Hud.CORNER_INSET
	var rec := Recruitment.new()
	rec.add_squad(U.AXE_WARRIOR, 2)
	assert_eq(RecruitPanel.strength_text(rec), "Siła 22", "napis siły armii")
	var at := RecruitPanel.strength_pos(left, right, "Siła 99999", "wszystkie jednostki")
	assert_true(at.x >= RecruitPanel.limit_rect(left, right).end.x, "za licznikiem armii")
	assert_true(at.x + PixelFont.text_width("Siła 99999") < right - PixelFont.text_width("wszystkie jednostki"),
			"nie wchodzi na napis trybu")
	assert_eq(RecruitPanel.strength_pos(left, left + 120, "Siła 99999", "wszystkie jednostki").x, -1.0,
			"na wąskim ekranie się chowa")
	var text := DefensePanel.strength_text(rec, DefensePlan.new(), _castle())
	assert_eq(text, "Siła obrony 22", "napis siły obrony")
	var r := DefensePanel.strength_rect(left, "Siła obrony 99999")
	var cmd := AttackPanel.general_rect(left)
	assert_true(r.position.x > cmd.end.x, "obok przycisku komendanta")
	assert_true(r.position.y >= Hud.BAR_H, "pod górnym paskiem")
	assert_true(r.end.x < right - Hud.BUTTON_SIZE.x, "nie wchodzi na kolumnę przycisków")
	return true


## Siła zamku-bota (#310) na karcie celu: załoga z BotRoster.defenders i umocnienia z jego siatki
## (bot nie ma pułapek ani garnizonu); ten sam numer daje zawsze tę samą liczbę.
func test_bot_defense() -> bool:
	for i in [0, 9, 19]:
		var bot := BotRoster.generate(i)
		var crew := 0
		for d: Array in bot.defenders:
			crew += int(d[1]) * Strength.unit_power(int(d[0]))
		assert_eq(Strength.bot_defense(bot), crew + Strength.forts(bot.grid), "zamek %d: załoga i umocnienia" % i)
		assert_eq(Strength.bot_defense(BotRoster.generate(i)), Strength.bot_defense(bot), "zamek %d: determinizm" % i)
	assert_true(Strength.bot_defense(BotRoster.generate(19)) > Strength.bot_defense(BotRoster.generate(0)),
			"ostatni zamek silniejszy od pierwszego")
	assert_eq(Strength.bot_defense(null), 0, "brak zamku")
	return true


# --- Mgła wojny i serwer (#293, ADR 0004) --------------------------------------------------------

const SERVER_MIGRATION := "res://supabase/migrations/20261126200000_target_strength.sql"
## Umocnienia do poziomu 10 (#262) liczy najnowsza wersja `private.defense_strength`.
const BALANCE_MIGRATION := "res://supabase/migrations/20261127120000_age_two_balance.sql"
const SERVER_TEST := "res://supabase/tests/database/target_strength_test.sql"
## Przykładowy zamek i układ obrony, które ten sam test pgTAP liczy w `private.defense_strength`:
## budynki na terenie z seeda 1337, oddziały ze złymi wpisami (powtórzone id, zły rodzaj, liczba ponad
## SQUAD_SIZE), garnizon z późniejszym rozkazem, który go zdejmuje, i pułapka na zajętej kratce.
const SAMPLE_BUILDINGS := "[[1,5,1,32,32,2,2],[2,21,1,34,31,2,2],[4,3,3,31,28,2,2],[5,2,1,31,34,3,1],[6,0,0,33,28,1,1],[7,0,5,34,28,1,1],[8,4,2,34,34,2,2]]"
const SAMPLE_SQUADS := "[[1,0,10],[2,3,7],[3,1,4],[4,5,3],[1,2,10],[5,99,3],[6,10,15]]"
const SAMPLE_ORDERS := "[[3,6,40,40,[]],[1,0,30,30,[]],[2,6,0,0,[]],[2,0,1,1,[]]]"
const SAMPLE_TRAPS := "[[0,10,10,0],[4,11,10,0],[3,10,10,0],[9,12,12,0]]"


func test_range_has_fixed_bounds() -> bool:
	assert_eq(Strength.range_low(0), 0, "0")
	assert_eq(Strength.range_low(-7), 0, "ujemna to 0")
	assert_eq(Strength.range_low(249), 200, "krok 50")
	assert_eq(Strength.range_low(250), 250, "granica przedziału")
	assert_eq(Strength.range_low(499), 450, "ostatni przedział z krokiem 50")
	assert_eq(Strength.range_low(500), 500, "od 500 krok 100")
	assert_eq(Strength.range_low(1999), 1900, "do 2000 krok 100")
	assert_eq(Strength.range_low(2499), 2000, "od 2000 krok 500")
	assert_eq(Strength.range_low(10000000), Strength.MAX_RANGE_LOW, "przycięta")
	assert_eq(Strength.range_text(237), "200-250", "przedział jako tekst")
	assert_eq(Strength.range_text(200), "200-250", "dolna granica daje ten sam przedział")
	assert_eq(Strength.range_text(480), "450-500", "przedział kończy się na 500")
	assert_eq(Strength.range_text(1950), "1900-2000", "przedział kończy się na 2000")
	assert_eq(Strength.range_text(2000), "2000-2500", "krok 500")
	for v in [0, 37, 450, 999, 2001, 77777]:
		var low := Strength.range_low(v)
		assert_eq(Strength.range_low(low), low, "%d: granica jest stała" % v)
		assert_true(low <= v and v < low + Strength.range_step(low), "%d w swoim przedziale" % v)
	return true


## Tablice wag w migracji to te same liczby co w grze (jak CARRY ↔ private.unit_carry).
func test_server_weights_match_game() -> bool:
	var sql := FileAccess.get_file_as_string(SERVER_MIGRATION)
	assert_true(not sql.is_empty(), "migracja siły celu jest w projekcie")
	var unit := str(Strength.unit_powers())
	var garrison := str(Strength.unit_powers(BattleConfig.GARRISON_HP_PERCENT))
	var forts := str(Strength.fort_powers())
	var traps := str(Strength.TRAP_POWER)
	assert_true(sql.contains("UNIT_POWER = " + unit) and sql.contains("array" + unit), "siła jednostek")
	assert_true(sql.contains("GARRISON_UNIT_POWER = " + garrison) and sql.contains("array" + garrison),
			"siła jednostek w garnizonie")
	assert_true(sql.contains("TRAP_POWER = " + traps) and sql.contains("array" + traps), "siła pułapek")
	var balance := FileAccess.get_file_as_string(BALANCE_MIGRATION)
	assert_true(balance.contains("FORT_POWER = " + forts) and balance.contains("array" + forts), "siła umocnień")
	assert_eq(Strength.FORTS, [K.RAMPART, K.PALISADE, K.GATE, K.TOWER] as Array[int], "umocnienia 0..3 jak w SQL")
	assert_true(K.RAMPART == 0 and K.TOWER == 3 and sql.contains("between 0 and 3"), "rodzaje umocnień w SQL")
	assert_true(balance.contains("fort_power[b.kind * %d + least(b.lv, %d)]" % [BattleConfig.LEVEL_HP_PERCENT.size(),
			BattleConfig.LEVEL_HP_PERCENT.size()]), "poziomy w tablicy umocnień")
	assert_true(balance.contains("array" + unit) and balance.contains("array" + garrison) and balance.contains("array" + traps),
			"nowa wersja funkcji ma te same wagi jednostek i pułapek")
	assert_true(sql.contains("between 0 and %d" % (UnitTypes.count() - 1)), "rodzaje jednostek")
	assert_true(sql.contains("between 0 and %d" % (TrapConfig.count() - 1)), "rodzaje pułapek")
	assert_true(sql.contains("SQUAD_SIZE = %d" % RecruitmentConfig.SQUAD_SIZE), "rozmiar oddziału")
	assert_true(sql.contains("GARRISON_TASK = %d" % T.GARRISON) and sql.contains("o.task = %d" % T.GARRISON),
			"zadanie garnizonu")
	assert_true(sql.contains("RANGE_STEPS = " + str(Strength.RANGE_STEPS))
			and sql.contains("RANGE_LIMITS = " + str(Strength.RANGE_LIMITS))
			and sql.contains("MAX_RANGE_LOW = %d" % Strength.MAX_RANGE_LOW), "przedziały jak w grze")
	assert_true(sql.contains("to service_role") and sql.contains("from public, anon, authenticated"),
			"tylko service_role")
	return true


## Ten sam przykładowy zamek daje w grze tę samą siłę, jakiej test pgTAP oczekuje od serwera.
func test_sample_castle_matches_server_test() -> bool:
	var grid := BuildGrid.new(TerrainMap.generate(WorldSeed.first_playable(1337)))
	assert_eq(grid.load_data({"buildings": JSON.parse_string(SAMPLE_BUILDINGS)}), 0, "budynki pasują do terenu")
	var rec := Recruitment.new()
	assert_eq(rec.load_data({"squads": JSON.parse_string(SAMPLE_SQUADS)}, grid, 0), 2,
			"powtórzone id i zły rodzaj odpadają")
	var plan := DefensePlan.from_dict({"orders": JSON.parse_string(SAMPLE_ORDERS), "traps": JSON.parse_string(SAMPLE_TRAPS)})
	assert_eq(plan.garrison_ids(), [3] as Array[int], "późniejszy rozkaz zdejmuje oddział z garnizonu")
	var expected := Strength.defense(rec, plan, grid)
	assert_eq(expected, 532, "siła przykładowego zamku")
	var test_sql := FileAccess.get_file_as_string(SERVER_TEST)
	for part: String in [SAMPLE_BUILDINGS, SAMPLE_SQUADS, SAMPLE_ORDERS, SAMPLE_TRAPS]:
		assert_true(test_sql.contains(part), "ten sam zamek w teście pgTAP")
	assert_true(test_sql.contains("%d, 'siła przykładowego zamku jak w grze'" % expected), "ta sama liczba w pgTAP")
	assert_true(test_sql.contains("%d, 'przedział przykładowego zamku'" % Strength.range_low(expected)), "ten sam przedział")
	return true
