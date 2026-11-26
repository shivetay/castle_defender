extends TestCase
## Bilans surowców na serwerze (#282). Migracja `*_economy_growth.sql` liczy produkcję, koszty i zużycie
## tymi samymi liczbami co gra: test składa tabele z klas gry i szuka ich w komentarzu i w funkcjach
## migracji, a wzory kosztów porównuje z BuildConfig.cost i ResearchConfig.cost.

const MIGRATION := "res://supabase/migrations/20261124180000_economy_growth.sql"
const R := EconomyConfig.Res


func _sql() -> String:
	return FileAccess.get_file_as_string(MIGRATION)


## Lista w zapisie SQL/JSON: „[1, 2, 3]”.
static func _list(a: Array) -> String:
	var parts: Array[String] = []
	for x: Variant in a:
		parts.append(_list(x as Array) if x is Array else str(x))
	return "[" + ", ".join(parts) + "]"


## Rodzaje z BuildConfig.BASE_COST rosnąco: {"rodzaj": [koszt], ...}.
static func _build_cost() -> String:
	var kinds: Array = BuildConfig.BASE_COST.keys()
	kinds.sort()
	var parts: Array[String] = []
	for k: int in kinds:
		parts.append("\"%d\": %s" % [k, _list(BuildConfig.BASE_COST[k] as Array)])
	return "{" + ", ".join(parts) + "}"


## Produkcja budynków jak w migracji: {"rodzaj": [surowiec, [stawki]], ...}.
static func _production() -> String:
	var kinds: Array = EconomyConfig.BUILDING_PRODUCTION.keys()
	kinds.sort()
	var parts: Array[String] = []
	for k: int in kinds:
		var e: Array = EconomyConfig.BUILDING_PRODUCTION[k]
		parts.append("\"%d\": [%d, %s]" % [k, int(e[0]), _list(e[1] as Array)])
	return "{" + ", ".join(parts) + "}"


static func _production_bonus() -> String:
	var codes: Array = TechTree.PRODUCTION_BONUS.keys()
	codes.sort()
	var parts: Array[String] = []
	for code: String in codes:
		parts.append("\"%s\": %s" % [code, _list(TechTree.PRODUCTION_BONUS[code] as Array)])
	return "{" + ", ".join(parts) + "}"


## Koszty jednostek w surowcach (indeks = UnitTypes.Unit).
static func _unit_cost() -> String:
	var rows: Array = []
	for u in UnitTypes.count():
		var row: Array = []
		for res in EconomyConfig.count():
			row.append(int(UnitTypes.resource_cost(u).get(res, 0)))
		rows.append(row)
	return _list(rows)


static func _producer_kind(producer: String) -> int:
	for kind: int in GoodsConfig.PRODUCER_KINDS:
		if GoodsConfig.PRODUCER_KINDS[kind] == producer:
			return kind
	return -1


## Przepisy z wejściami surowców: [[budynek, od poziomu, cykle/h, {"surowiec": ilość}], ...].
static func _goods_inputs() -> String:
	var parts: Array[String] = []
	for row: Array in GoodsConfig.RECIPES:
		var ins: Dictionary = row[3]
		if ins.is_empty():
			continue
		var keys: Array = ins.keys()
		keys.sort()
		var q: Array[String] = []
		for res: int in keys:
			q.append("\"%d\": %d" % [res, int(ins[res])])
		parts.append("[%d, %d, %d, {%s}]" % [_producer_kind(row[0] as String), int(row[1]), int(row[2]), ", ".join(q)])
	return "[" + ", ".join(parts) + "]"


func test_production_matches_game() -> bool:
	var sql := _sql()
	assert_true(not sql.is_empty(), "migracja jest")
	assert_true(sql.contains("BASE_PER_HOUR = %s" % _list(EconomyConfig.BASE_PER_HOUR)), "gród w komentarzu")
	assert_true(sql.contains("(array%s)[r + 1]" % _list(EconomyConfig.BASE_PER_HOUR)), "gród w funkcji")
	var prod := _production()
	assert_true(sql.contains("PRODUCTION = " + prod), "budynki w komentarzu")
	assert_true(sql.contains("'" + prod + "'::jsonb"), "budynki w funkcji")
	var bonus := _production_bonus()
	assert_true(sql.contains("PRODUCTION_BONUS = " + bonus), "premie technologii w komentarzu")
	assert_true(sql.contains("'" + bonus + "'::jsonb"), "premie technologii w funkcji")
	assert_true(sql.contains("THRIFTY = %d" % RulerPerks.Perk.THRIFTY), "perk Gospodarny w komentarzu")
	assert_true(sql.contains("castle_ruler_perk(p_new) = %d then %d" % [RulerPerks.Perk.THRIFTY,
			RulerPerks.THRIFTY_PRODUCTION_BONUS]), "perk Gospodarny w funkcji")
	# żywność Chaty myśliwego z pierwszego przepisu
	var hunter: Array = GoodsConfig.RECIPES[0]
	assert_eq(hunter[0], "hunter", "pierwszy przepis to Chata myśliwego")
	assert_eq(_producer_kind("hunter"), BuildingTypes.Kind.HUNTER, "wytwórca to Chata myśliwego")
	var food := int((hunter[6] as Dictionary).get(R.FOOD, 0))
	assert_true(sql.contains("HUNTER_FOOD = %d" % food), "żywność na cykl w komentarzu")
	assert_true(sql.contains("sum(%d * (%d * (array%s)[b.level] / 100))" % [food, int(hunter[2]),
			_list(GoodsConfig.LEVEL_PERCENT)]), "przepis w funkcji")
	assert_true(sql.contains("where b.kind = %d), 0)" % BuildingTypes.Kind.HUNTER), "rodzaj Chaty myśliwego w funkcji")
	assert_true(sql.contains("START = %s" % _list(EconomyConfig.START)), "zapasy nowej gry w komentarzu")
	assert_true(sql.contains("v_old_amounts := array%s;" % _list(EconomyConfig.START)), "zapasy nowej gry w wyzwalaczu")
	return true


## Serwer liczy produkcję jak Economy.rates dla tego samego zamku (bez ruin, perk i premie z zapisu).
func test_production_formula_matches_rates() -> bool:
	var g := BuildGrid.new(TerrainMap.generate(1337))
	for kind: int in EconomyConfig.BUILDING_PRODUCTION:
		for level in range(1, 6):
			g.buildings.clear()
			g.kinds.clear()
			g.levels.clear()
			g.buildings[1] = Rect2i()
			g.kinds[1] = kind
			g.levels[1] = level
			var r := Research.new()
			r.done = {"G1": true, "G2": true}
			g.ruler_perk = RulerPerks.Perk.THRIFTY
			var game := Economy.rates(g, r)
			var e: Array = EconomyConfig.BUILDING_PRODUCTION[kind]
			for res in EconomyConfig.count():
				var raw := EconomyConfig.BASE_PER_HOUR[res] + (int((e[1] as Array)[level - 1]) if int(e[0]) == res else 0)
				var percent := 100 + RulerPerks.THRIFTY_PRODUCTION_BONUS
				for code: String in TechTree.PRODUCTION_BONUS:
					if int(TechTree.PRODUCTION_BONUS[code][0]) == res:
						percent += int(TechTree.PRODUCTION_BONUS[code][1])
				@warning_ignore("integer_division")
				assert_eq(raw * percent / 100, game[res], "rodzaj %d poziom %d surowiec %d" % [kind, level, res])
	return true


func test_build_cost_matches_game() -> bool:
	var sql := _sql()
	var costs := _build_cost()
	assert_true(sql.contains("BUILD_COST = " + costs), "koszty w komentarzu")
	assert_true(sql.contains("v_base := '" + costs + "'::jsonb"), "koszty w funkcji")
	assert_true(sql.contains("COST_PERCENT = %s" % _list(BuildConfig.COST_PERCENT)), "mnożnik poziomów w komentarzu")
	assert_true(sql.contains("AGE_COST_PERCENT = %s" % _list(BuildConfig.AGE_COST_PERCENT)), "mnożnik epok w komentarzu")
	assert_true(sql.contains("(array%s)[(v_lv - 1) %% 5 + 1] * (array%s)[(v_lv - 1) / 5 + 1]" % [
			_list(BuildConfig.COST_PERCENT), _list(BuildConfig.AGE_COST_PERCENT)]), "mnożniki w funkcji")
	var manor := _list(BuildConfig.MANOR_COST)
	assert_true(sql.contains("MANOR_COST = " + manor), "Dwór w komentarzu")
	assert_true(sql.contains("('" + manor + "'::jsonb"), "Dwór w funkcji")
	assert_eq(BuildConfig.COST_PERCENT.size(), 5, "5 poziomów w epoce, jak `% 5` w funkcji")
	# wzór serwera: koszt bazowy × procent poziomu × procent epoki / 10000, Dwór z tabeli
	for kind in BuildingTypes.Kind.size():
		for level in range(1, Ages.MAX_TOTAL_LEVEL + 1):
			var server: Array[int] = []
			if kind == BuildingTypes.Kind.MANOR:
				server.assign(BuildConfig.MANOR_COST[level - 1])
			else:
				var base: Array = BuildConfig.BASE_COST.get(kind, [0, 0, 0, 0])
				var percent := BuildConfig.COST_PERCENT[(level - 1) % 5] * BuildConfig.AGE_COST_PERCENT[(level - 1) / 5]
				for amount: int in base:
					@warning_ignore("integer_division")
					server.append(amount * percent / 10000)
			assert_eq(server, BuildConfig.cost(kind, level), "rodzaj %d poziom %d" % [kind, level])
	return true


func test_research_cost_matches_game() -> bool:
	var sql := _sql()
	assert_true(sql.contains("RESEARCH_BASE_COST = %s" % _list(ResearchConfig.BASE_COST)), "koszty epok w komentarzu")
	assert_true(sql.contains("COST_STEP_PERCENT = %d" % ResearchConfig.COST_STEP_PERCENT), "wzrost w komentarzu")
	assert_eq(ResearchConfig.BASE_COST.size(), 2, "dwie epoki, jak w funkcji")
	assert_true(sql.contains("case when p_age >= 1 then array%s else array%s end" % [
			_list(ResearchConfig.BASE_COST[1] as Array), _list(ResearchConfig.BASE_COST[0] as Array)]), "koszty epok w funkcji")
	assert_true(sql.contains("v_out[i] * %d / 100" % ResearchConfig.COST_STEP_PERCENT), "wzrost w funkcji")
	return true


func test_spend_tables_match_game() -> bool:
	var sql := _sql()
	var units := _unit_cost()
	assert_true(sql.contains("UNIT_COST = " + units), "koszty jednostek w komentarzu")
	assert_true(sql.contains("'" + units + "'::jsonb"), "koszty jednostek w funkcji")
	var traps := _list(TrapConfig.COST)
	assert_true(sql.contains("TRAP_COST = " + traps), "pułapki w komentarzu")
	assert_true(sql.contains("'" + traps + "'::jsonb"), "pułapki w funkcji")
	assert_eq(TrapConfig.count(), 5, "5 rodzajów pułapek, jak generate_series(0, 4)")
	assert_true(sql.contains("SCOUT_COST = %s" % _list(ScoutConfig.COST_PER_SCOUT)), "zwiad w komentarzu")
	assert_eq(ScoutConfig.COST_PER_SCOUT, [0, 0, 10, 10] as Array[int], "zwiad w funkcji: 10 żywności i 10 złota")
	assert_true(sql.contains("v_out[3] := v_out[3] + %d * v_scouts" % ScoutConfig.COST_PER_SCOUT[R.FOOD]), "żywność zwiadu")
	assert_true(sql.contains("v_out[4] := v_out[4] + %d * v_scouts" % ScoutConfig.COST_PER_SCOUT[R.GOLD]), "złoto zwiadu")
	assert_true(sql.contains("sum(%d" % Generals.RECRUIT_GOLD), "werbunek generała")
	assert_true(sql.contains(">= 2 then %d" % Generals.LEVEL_GOLD[2]), "awans generała na 2")
	assert_true(sql.contains(">= 3 then %d" % Generals.LEVEL_GOLD[3]), "awans generała na 3")
	# płatna zmiana perka z listy (#32, 50 zł) już nie rośnie od #308, ale zostaje w budżecie złota
	assert_true(sql.contains("50 * greatest(new.ruler_perk_paid - old.ruler_perk_paid, 0)"), "płatna zmiana perka")
	var inputs := _goods_inputs()
	assert_true(sql.contains("GOODS_INPUTS = " + inputs), "wejścia wytwórców w komentarzu")
	assert_true(sql.contains("'" + inputs + "'::jsonb"), "wejścia wytwórców w funkcji")
	assert_true(sql.contains("(array%s)[b.level] / 100 * (rec.ins" % _list(GoodsConfig.LEVEL_PERCENT)), "tempo poziomów")
	return true


func test_pve_rewards_match_game() -> bool:
	var sql := _sql()
	var rewards := _list(PveWaves.REWARDS)
	assert_true(sql.contains("PveWaves.REWARDS = " + rewards), "nagrody w komentarzu")
	assert_true(sql.contains("'" + rewards + "'::jsonb"), "nagrody w funkcji")
	assert_true(sql.contains("between 0 and %d" % PveWaves.COUNT), "liczba fal w kolumnie")
	assert_true(sql.contains("least(p_to, %d)" % PveWaves.COUNT), "liczba fal w funkcji")
	return true


## Tolerancja: 5 minut produkcji (jak budowa i badania, #279, #281) i stały zapas na niewidoczne wydatki.
func test_tolerance() -> bool:
	var sql := _sql()
	assert_true(sql.contains("v_prod[i] * 5 * 60 * 1000 / 3600000.0 + 2"), "5 minut produkcji i ROUND_SLACK = 2")
	assert_true(sql.contains("ROUND_SLACK = 2"), "w komentarzu")
	assert_true(sql.contains("HIDE_SLACK = [100, 100, 100, 20]"), "zapas na niewidoczne wydatki w komentarzu")
	assert_true(sql.contains("(array[100, 100, 100, 20])[i]"), "zapas na niewidoczne wydatki w wyzwalaczu")
	return true
