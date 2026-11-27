extends TestCase
## Premie poziomów 6–10 (epoka II) dla szkolenia, kolców w fosie i zasięgu z Kopca (#387, ADR 0013).
## Tablice mają 10 wartości zatwierdzonych przez właścicielkę, żadna premia nie spada na przejściu
## I.5 → II.1, a zwiad pokazuje budynek epoki II z jego poziomem (do 10), a nie przycięty do 5.
## Zgodność czasu szkolenia z serwerem (`private.train_ms`) sprawdza `tests/test_army_research_goods_sanity.gd`.

const K := BuildingTypes.Kind


func test_tables_have_ten_agreed_values() -> bool:
	assert_eq(RecruitmentConfig.TRAINING_SLOTS, [2, 3, 4, 5, 6, 7, 8, 9, 10, 11] as Array[int], "miejsca w kolejce")
	assert_eq(RecruitmentConfig.TRAINING_SPEED_PERCENT, [100, 120, 140, 170, 200, 230, 260, 300, 340, 400] as Array[int],
			"tempo szkolenia")
	assert_eq(BattleConfig.MOAT_SPIKE_DAMAGE, [2, 3, 4, 5, 6, 7, 8, 9, 10, 11] as Array[int], "kolce w fosie")
	assert_eq(BattleConfig.MOUND_RANGE_BONUS, [1, 1, 2, 2, 2, 2, 2, 2, 3, 3] as Array[int], "zasięg z Kopca")
	for table: Array[int] in [RecruitmentConfig.TRAINING_SLOTS, RecruitmentConfig.TRAINING_SPEED_PERCENT,
			BattleConfig.MOAT_SPIKE_DAMAGE, BattleConfig.MOUND_RANGE_BONUS]:
		assert_eq(table.size(), Ages.MAX_TOTAL_LEVEL, "10 poziomów")
	return true


## Żadna premia nie spada z poziomu na poziom, także na przejściu I.5 → II.1, a ponad 10 zostaje jak 10.
func test_bonuses_never_drop() -> bool:
	for level in range(2, Ages.MAX_TOTAL_LEVEL + 1):
		assert_true(RecruitmentConfig.training_slots(level) > RecruitmentConfig.training_slots(level - 1),
				"miejsca rosną na poziomie %d" % level)
		assert_true(RecruitmentConfig.training_speed_percent(level) > RecruitmentConfig.training_speed_percent(level - 1),
				"tempo rośnie na poziomie %d" % level)
		assert_true(BattleConfig.moat_spike_damage(level) > BattleConfig.moat_spike_damage(level - 1),
				"kolce rosną na poziomie %d" % level)
		assert_true(BattleConfig.mound_range_bonus(level) >= BattleConfig.mound_range_bonus(level - 1),
				"zasięg nie spada na poziomie %d" % level)
	assert_eq(RecruitmentConfig.training_slots(99), 11, "ponad 10 jak 10")
	assert_eq(BattleConfig.moat_spike_damage(99), 11, "ponad 10 jak 10")
	assert_eq(BattleConfig.mound_range_bonus(99), 3, "ponad 10 jak 10")
	return true


func test_age_two_trains_faster() -> bool:
	assert_eq(RecruitmentConfig.train_ms(0, 5), 10000, "topornik w Koszarach 5: 10 s")
	assert_eq(RecruitmentConfig.train_ms(0, 6), 8695, "Koszary II.1: 230 procent")
	assert_eq(RecruitmentConfig.train_ms(0, 10), 5000, "Koszary II.5: 400 procent")
	return true


## Zwiad (#387): budynek epoki II zostaje ze swoim poziomem narastającym, poziom ponad 10 jak 10.
func test_scout_keeps_age_two_level() -> bool:
	var intel := ScoutIntel.from_server({"region": [10, 10, 6, 6], "buildings": [
			[10, 10, 2, 2, K.TOWER, 8], [14, 14, 2, 2, K.TOWER, 99], [12, 12, 1, 1, K.TOWER, 5]]})
	assert_eq(intel.buildings[0][2], 8, "Wieża II.3 jako poziom 8")
	assert_eq(intel.buildings[1][2], Ages.MAX_TOTAL_LEVEL, "ponad 10 jak 10")
	assert_eq(intel.buildings[2][2], 5, "epoka I bez zmian")
	return true
