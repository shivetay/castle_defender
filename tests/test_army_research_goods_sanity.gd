extends TestCase
## Badania, wojsko i towary bez zaufanej edycji lokalnej (#281). Serwer (`*_army_research_goods_sanity.sql`)
## odrzuca zapis zamku z technologią bez wymagań, jednostką bez technologii, towarem ponad zbrojownię
## i przyrostem szybszym niż badanie, szkolenie albo produkcja w grze. Tabele w migracji muszą być te same
## co w grze; test składa je z klas gry i szuka w komentarzu i w funkcji migracji.

const MIGRATION := "res://supabase/migrations/20261124150000_army_research_goods_sanity.sql"
## Najnowsza wersja `private.tech_tree` (#388: G5 Młyn wodny w epoce II).
const TREE_MIGRATION := "res://supabase/migrations/20261127160000_mill.sql"
## Tempo wytwórców do poziomu 10 (#262) ma najnowsza wersja `private.goods_plan`.
const BALANCE_MIGRATION := "res://supabase/migrations/20261127120000_age_two_balance.sql"


func _sql() -> String:
	return FileAccess.get_file_as_string(MIGRATION)


## Drzewko jak `private.tech_tree`: {"kod": [epoka, ["wymagany", ...]], ...} w kolejności TechTree.TECHS.
func _tech_tree() -> String:
	var parts: Array[String] = []
	for row: Array in TechTree.TECHS:
		var req: Array[String] = []
		for code: String in row[5]:
			req.append("\"%s\"" % code)
		parts.append("\"%s\": [%d, [%s]]" % [row[0], int(row[3]), ", ".join(req)])
	return "{" + ", ".join(parts) + "}"


## Jednostki jak `private.unit_rules`: [[epoka, "technologia", budynek], ...] w kolejności UnitTypes.Unit.
func _unit_rules() -> String:
	var parts: Array[String] = []
	for unit in UnitTypes.count():
		parts.append("[%d, \"%s\", %d]" % [UnitTypes.age(unit), UnitTypes.required_tech(unit), UnitTypes.building(unit)])
	return "[" + ", ".join(parts) + "]"


## Przepisy jak `private.goods_recipes`: [[budynek wytwórcy, od poziomu, cykle/h, {"towar": ilość}], ...].
func _recipes() -> String:
	var parts: Array[String] = []
	for row: Array in GoodsConfig.RECIPES:
		var outs: Array[String] = []
		var goods: Array = (row[5] as Dictionary).keys()
		goods.sort()
		for good: int in goods:
			outs.append("\"%d\": %d" % [good, int(row[5][good])])
		parts.append("[%d, %d, %d, {%s}]" % [_producer_kind(row[0] as String), int(row[1]), int(row[2]), ", ".join(outs)])
	return "[" + ", ".join(parts) + "]"


static func _producer_kind(producer: String) -> int:
	for kind: int in GoodsConfig.PRODUCER_KINDS:
		if GoodsConfig.PRODUCER_KINDS[kind] == producer:
			return kind
	return -1


func test_tech_tree_matches_game() -> bool:
	var sql := FileAccess.get_file_as_string(TREE_MIGRATION)
	assert_true(not sql.is_empty(), "migracja jest")
	var tree := _tech_tree()
	assert_true(sql.contains("TECH_TREE = " + tree), "drzewko w komentarzu")
	assert_true(sql.contains("select '" + tree + "'::jsonb"), "drzewko w funkcji")
	return true


## Czas badań na serwerze jest od migracji `*_research_fixed_cost.sql` stały w epoce
## (tests/test_research_fixed_cost.gd); tu zostaje sprawdzenie liczby badaczy.
func test_research_time_matches_game() -> bool:
	var sql := _sql()
	assert_true(sql.contains("BASE_TIME_S = %s" % str(ResearchConfig.BASE_TIME_S)), "czasy epok w komentarzu")
	assert_true(sql.contains("RESEARCHERS = %d" % ResearchConfig.RESEARCHERS), "jeden badacz")
	return true


func test_unit_rules_match_game() -> bool:
	var sql := _sql()
	var rules := _unit_rules()
	assert_true(sql.contains("UNIT_RULES = " + rules), "jednostki w komentarzu")
	assert_true(sql.contains("select '" + rules + "'::jsonb"), "jednostki w funkcji")
	assert_true(sql.contains("SQUAD_SIZE = %d" % RecruitmentConfig.SQUAD_SIZE), "rozmiar oddziału")
	var era := str(UnitTypes.ERA_I_ONLY)
	assert_true(sql.contains("ERA_I_ONLY = " + era), "jednostki tylko na epokę I w komentarzu")
	assert_eq(sql.count("= any (array%s)" % era), 2, "jednostki tylko na epokę I w funkcji")
	return true


## Czas szkolenia na serwerze (`private.train_ms`) to RecruitmentConfig.train_ms dla każdej jednostki i poziomu.
func test_train_time_matches_game() -> bool:
	var sql := _sql()
	var times := str(RecruitmentConfig.TRAIN_TIME_S)
	var speed := str(RecruitmentConfig.TRAINING_SPEED_PERCENT)
	assert_true(sql.contains("TRAIN_TIME_S = " + times), "czasy w komentarzu")
	assert_true(sql.contains("coalesce((array%s)[p_unit + 1], 0)" % times), "czasy w funkcji")
	assert_true(sql.contains("TRAINING_SPEED_PERCENT = " + speed), "tempo w komentarzu")
	assert_true(sql.contains("(array%s)[least(greatest(p_level, 1), 5)]" % speed), "tempo w funkcji")
	for unit in UnitTypes.count():
		for level in range(1, Ages.MAX_TOTAL_LEVEL + 1):
			var pct: int = RecruitmentConfig.TRAINING_SPEED_PERCENT[clampi(level, 1, 5) - 1]
			@warning_ignore("integer_division")
			var server: int = RecruitmentConfig.TRAIN_TIME_S[unit] * 1000 * 100 / pct
			assert_eq(server, RecruitmentConfig.train_ms(unit, level), "jednostka %d poziom %d" % [unit, level])
	return true


func test_goods_match_game() -> bool:
	var sql := _sql()
	var recipes := _recipes()
	assert_true(sql.contains("GOODS_RECIPES = " + recipes), "przepisy w komentarzu")
	assert_true(sql.contains("select '" + recipes + "'::jsonb"), "przepisy w funkcji")
	assert_true(sql.contains("GOODS_COUNT = %d" % GoodsConfig.count()), "liczba towarów")
	assert_true(sql.contains("jsonb_array_length(v_amounts) <> %d" % GoodsConfig.count()), "liczba towarów w funkcji")
	assert_true(sql.contains("generate_series(0, %d)" % (GoodsConfig.count() - 1)), "towary w planie produkcji")
	assert_true(sql.contains("ARMORY_CAPACITY = %d" % GoodsConfig.ARMORY_CAPACITY), "pojemność zbrojowni")
	assert_true(sql.contains("if x > %d then" % GoodsConfig.ARMORY_CAPACITY), "pojemność w funkcji")
	for good in GoodsConfig.count():
		assert_eq(GoodsConfig.capacity(good), GoodsConfig.ARMORY_CAPACITY, "jedna pojemność dla towaru %d" % good)
	var pct := str(GoodsConfig.LEVEL_PERCENT)
	var balance := FileAccess.get_file_as_string(BALANCE_MIGRATION)
	assert_true(balance.contains("LEVEL_PERCENT = " + pct), "tempo poziomów w komentarzu")
	assert_true(balance.contains("(array%s)[least(b.lvl, %d)]" % [pct, Ages.MAX_TOTAL_LEVEL]), "tempo poziomów w funkcji")
	for recipe in GoodsConfig.RECIPES.size():
		assert_true(_producer_kind(GoodsConfig.RECIPES[recipe][0] as String) >= 0, "wytwórca %d ma budynek" % recipe)
	return true


## Zapisy gry mają pola, z których serwer liczy przyrost: oddziały [id, rodzaj, liczba], zlecenia
## z `unit` i `building_id`, misję zwiadu z `units` i trwające badanie z `code`.
func test_saves_have_server_fields() -> bool:
	var r := Recruitment.new()
	var id := r.add_squad(UnitTypes.Unit.AXE_WARRIOR, 3)
	var o := Recruitment.Order.new()
	o.unit = UnitTypes.Unit.AXE_WARRIOR
	o.building_id = 7
	o.squad_id = id
	r.orders.append(o)
	var saved: Dictionary = r.save_data()
	assert_eq(str((saved["squads"] as Array)[0]), str([id, UnitTypes.Unit.AXE_WARRIOR, 3]), "oddział [id, rodzaj, liczba]")
	var order: Dictionary = (saved["orders"] as Array)[0]
	assert_eq(int(order["unit"]), UnitTypes.Unit.AXE_WARRIOR, "rodzaj w zleceniu")
	assert_eq(int(order["building_id"]), 7, "budynek w zleceniu")
	var research := Research.new()
	research.active = "A1"
	var rd: Dictionary = research.save_data()
	assert_eq(str((rd["active"] as Dictionary)["code"]), "A1", "kod trwającego badania")
	var goods := Goods.new(0)
	assert_eq(((goods.save_data()["amounts"]) as Array).size(), GoodsConfig.count(), "zapasy wszystkich towarów")
	var sql := _sql()
	assert_true(sql.contains("p_castle -> 'research' -> 'active' -> 'code'"), "serwer czyta trwające badanie")
	assert_true(sql.contains("p_castle -> 'scout' -> 'mission' -> 'units'"), "serwer czyta zwiadowców na misji")
	assert_true(sql.contains("x.e -> 'building_id'"), "serwer czyta budynek zlecenia")
	return true
