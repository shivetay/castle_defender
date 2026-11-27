extends TestCase
## Poziomy doktryn na serwerze. Migracja `*_doctrine_levels.sql` liczy poziomy tymi samymi liczbami co gra
## (TechTree.LEVELED_DOCTRINES, DOCTRINE_MAX_LEVEL, DOCTRINE_LEVEL_PERCENT): test szuka ich w komentarzu
## i w funkcjach migracji.

const MIGRATION := "res://supabase/migrations/20261126065715_doctrine_levels.sql"
## Lista doktryn z poziomami z doktrynami ataku (najnowsza wersja `private.research_leveled`).
const ATTACK_MIGRATION := "res://supabase/migrations/20261126065756_attack_doctrine_levels.sql"
## Najnowsza lista doktryn z poziomami (`private.research_leveled`, od #342 z O25).
const LEVELED_MIGRATION := "res://supabase/migrations/20261127071313_defense_reach.sql"


func _sql() -> String:
	return FileAccess.get_file_as_string(MIGRATION)


func test_constants_match_game() -> bool:
	var sql := _sql()
	assert_true(not sql.is_empty(), "migracja istnieje")
	var json: Array[String] = []
	var arr: Array[String] = []
	for c in TechTree.LEVELED_DOCTRINES:
		json.append("\"%s\"" % c)
		arr.append("'%s'" % c)
	var attack := FileAccess.get_file_as_string(ATTACK_MIGRATION)
	var leveled := FileAccess.get_file_as_string(LEVELED_MIGRATION)
	assert_true(leveled.contains("LEVELED = [%s]" % ", ".join(json)), "doktryny z poziomami w komentarzu")
	assert_true(leveled.contains("create or replace function private.research_leveled()"), "najnowsza research_leveled")
	assert_true(leveled.contains("select array[%s]::text[]" % ", ".join(arr)), "doktryny z poziomami w funkcji")
	# poziomy doktryn ataku w `attacker_techs`: każdy poziom 2..najwyższy jako „A1:N”
	for code in ["A1", "A2"]:
		assert_true(TechTree.is_leveled(code), "%s z poziomami" % code)
		for n in range(2, TechTree.max_level_any(code) + 1):
			assert_true(attack.contains("'%s:%d'" % [code, n]), "%s:%d w ograniczeniu kolumny" % [code, n])
	assert_true(attack.contains("cardinality(attacker_techs) <= %d" % (3 + 2)), "najwyżej 3 kody i 2 poziomy")
	assert_true(sql.contains("DOCTRINE_MAX_LEVEL = %s" % str(TechTree.DOCTRINE_MAX_LEVEL)), "limity epok w komentarzu")
	assert_eq(TechTree.DOCTRINE_MAX_LEVEL.size(), 2, "dwie epoki, jak least(..., 1) w funkcji")
	assert_true(sql.contains("select (array[%d, %d])[least(" % [TechTree.DOCTRINE_MAX_LEVEL[0], TechTree.DOCTRINE_MAX_LEVEL[1]]),
			"limity epok w funkcji")
	assert_true(sql.contains("least(greatest((p_castle -> 'research' -> 'levels' ->> p_code)::numeric::integer, 1), %d)"
			% TechTree.DOCTRINE_MAX_LEVEL.max()), "najwyższy poziom w tech_level")
	var step := TechTree.DOCTRINE_LEVEL_PERCENT
	assert_true(sql.contains("DOCTRINE_LEVEL_PERCENT = %d" % step), "premia poziomu w komentarzu")
	assert_true(sql.contains("+ %d * (greatest(private.tech_level(p_old, t.k)" % step), "premia poziomu w produkcji")
	assert_true(sql.contains("then 15 + %d * (private.tech_level(p_castle, 'G2') - 1)" % step), "premia G2 w limicie utrzymania")
	assert_eq(int((TechTree.PRODUCTION_BONUS["G2"] as Array)[1]), 15, "G2 +15% jak w limicie utrzymania")
	var ms: Array[String] = []
	for s in ResearchConfig.BASE_TIME_S:
		ms.append(str(s * 1000))
	assert_true(sql.contains("sum((array[%s])[(private.tech_tree() -> c ->> 0)::integer + 1]" % ", ".join(ms)),
			"czas poziomu w funkcji")
	return true


## Koszt poziomów jak na serwerze: każdy poziom to kolejny krok doktryny epoki (liczby z testu pgTAP).
func test_level_costs_match_pgtap() -> bool:
	var r := Research.new()
	var total: Array[int] = [0, 0, 0, 0]
	for i in 3:
		var e := Economy.new(0)
		for res in EconomyConfig.count():
			e.amounts[res] = 1 << 40
		var price := r.cost_of("G1")
		for res in 4:
			total[res] += price[res]
		assert_eq(r.start("G1", 0, e, 0), Research.Result.OK, "poziom %d" % (i + 1))
		r.update(r.duration_ms)
	assert_eq(total, [516, 258, 258, 0] as Array[int], "G1 do poziomu 3: kroki 0, 1 i 2")
	assert_eq(r.cost_of("G2"), [409, 204, 204, 0] as Array[int], "G2 po trzech poziomach G1: krok 3")
	return true
