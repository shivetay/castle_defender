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
