extends TestCase
## Balans epok (#262, ADR 0009): każda kolejna epoka płynnie wynika z poprzedniej. Pełna armia epoki II
## zdobywa zamek epoki I na maksimum, a pełna armia epoki I nie zdobywa zamku tuż po przejściu (II.1).
## Pojedynki idą w symulacji bitwy ze stałym seedem, więc wynik jest zawsze ten sam.
## Koszty i czasy: krzywa przez 10 poziomów nie spada na przejściu I.5 → II.1, a każdy koszt mieści
## się w magazynie, który da się mieć przy Dworze danego poziomu.

const K := BuildingTypes.Kind
const U := UnitTypes.Unit
## Zamek z pełnym układem epoki I (zewnętrzny wał, 4 wieże, budynki rekrutacji): ostatni bot epoki I.
const LAYOUT_BOT := BotRoster.COUNT_PER_AGE - 1
const SEED := 262


## Pełna armia w oddziałach po SQUAD_SIZE z rodzajów `units` (po kolei, w kółko) do limitu `limit`.
func _army(units: Array[int], limit: int) -> Array:
	var out: Array = []
	var left := limit
	var i := 0
	while left > 0:
		var n := mini(left, RecruitmentConfig.SQUAD_SIZE)
		out.append([units[i % units.size()], n])
		left -= n
		i += 1
	return out


## Limit armii przy samym Dworze na poziomie `manor` (bez Koszar).
func _limit_at(manor: int) -> int:
	var grid := BuildGrid.new(TerrainMap.generate(WorldSeed.first_playable(SEED)))
	grid.place(grid.manor_spot(WorldSeed.MANOR_MAX_RING), K.MANOR, manor)
	return Recruitment.army_limit(grid)


func _age_i_army(limit: int) -> Array:
	return _army([U.AXE_WARRIOR, U.ARCHER, U.SHIELDBEARER, U.RIDER, U.JAVELINEER], limit)


func _age_ii_army(limit: int) -> Array:
	return _army([U.SPEARMAN, U.GAMBESON_WARRIOR, U.REFLEX_ARCHER, U.LANCER], limit)


## Zamek z układu LAYOUT_BOT ze wszystkimi budynkami z poziomami na poziomie `level`.
func _castle(level: int) -> BotCastle:
	var bot := BotRoster.generate(LAYOUT_BOT)
	for id: int in bot.grid.levels:
		if BuildingTypes.has_levels(bot.grid.kinds[id]):
			bot.grid.levels[id] = level
	return bot


func _duel(bot: BotCastle, attackers: Array, defenders: Array) -> BattleResult:
	var b := Battle.create_squads(bot.grid, bot.objective, attackers, defenders, bot.spawn, SEED)
	b.run()
	return BattleResult.of(b)


func test_full_age_ii_army_takes_max_age_i_castle() -> bool:
	assert_eq(_limit_at(Ages.MAX_TOTAL_LEVEL), 90, "limit przy Dworze II.5")
	var bot := _castle(Ages.LEVELS_PER_AGE)
	var r := _duel(bot, _age_ii_army(_limit_at(Ages.MAX_TOTAL_LEVEL)), _age_i_army(_limit_at(Ages.LEVELS_PER_AGE)))
	print("    epoka II → zamek I.5: wygrana %s, zniszczenia %d%%" % [r.won, r.percent])
	assert_true(r.won, "armia epoki II zdobywa zamek epoki I na maksimum")
	return true


func test_full_age_i_army_loses_to_age_ii_castle() -> bool:
	assert_eq(_limit_at(Ages.LEVELS_PER_AGE), 50, "limit przy Dworze 5")
	var level := Ages.total_level(1, 1)
	var bot := _castle(level)
	var r := _duel(bot, _age_i_army(_limit_at(Ages.LEVELS_PER_AGE)), _age_i_army(_limit_at(level)))
	print("    epoka I → zamek II.1: wygrana %s, zniszczenia %d%%" % [r.won, r.percent])
	assert_true(not r.won, "armia epoki I nie zdobywa zamku epoki II.1")
	return true


func test_duels_are_deterministic() -> bool:
	for level: int in [Ages.LEVELS_PER_AGE, Ages.total_level(1, 1)]:
		var army := _age_ii_army(_limit_at(Ages.MAX_TOTAL_LEVEL))
		var bot := _castle(level)
		var a := Battle.create_squads(bot.grid, bot.objective, army, _age_i_army(50), bot.spawn, SEED)
		var b := Battle.create_squads(_castle(level).grid, bot.objective, army, _age_i_army(50), bot.spawn, SEED)
		a.run()
		b.run()
		assert_eq(a.checksum(), b.checksum(), "poziom %d: ten sam seed, ten sam przebieg" % level)
		assert_eq(BattleResult.of(a).percent, BattleResult.of(b).percent, "poziom %d: ten sam wynik" % level)
	return true


## Koszt i czas poziomu n+1 nie są mniejsze niż poziomu n, dla każdego rodzaju i surowca, bez wyjątków
## (#262): umocnienia w epoce II biorą połowę przyrostu krzywej ponad poziom 5.
func test_cost_and_time_never_drop() -> bool:
	for kind in K.size():
		for level in range(1, Ages.MAX_TOTAL_LEVEL):
			var now := BuildConfig.cost(kind, level)
			var next := BuildConfig.cost(kind, level + 1)
			for res in now.size():
				assert_true(next[res] >= now[res], "rodzaj %d poziom %d → %d surowiec %d" % [kind, level, level + 1, res])
			var t_now := BuildConfig.time_ms(kind, level)
			var t_next := BuildConfig.time_ms(kind, level + 1)
			assert_true(t_next >= t_now, "czas rodzaju %d poziom %d → %d" % [kind, level, level + 1])
	return true


## Każdy koszt poziomu mieści się w magazynie osiągalnym przy Dworze tego poziomu (gród plus Magazyn
## najwyżej na poziomie Dworu). Poziom Dworu L buduje się przy Dworze L - 1.
func test_every_cost_fits_reachable_storage() -> bool:
	for kind in K.size():
		for level in range(1, Ages.MAX_TOTAL_LEVEL + 1):
			var manor := level - 1 if kind == K.MANOR else level
			var cap := EconomyConfig.CAPACITY[EconomyConfig.Res.WOOD]
			if manor >= 1:
				cap += EconomyConfig.WAREHOUSE_CAPACITY[mini(manor, EconomyConfig.WAREHOUSE_CAPACITY.size()) - 1]
			var c := BuildConfig.cost(kind, level)
			for res in c.size():
				if EconomyConfig.is_capped(res):
					assert_true(c[res] <= cap, "rodzaj %d poziom %d surowiec %d: %d > %d" % [kind, level, res, c[res], cap])
	return true
