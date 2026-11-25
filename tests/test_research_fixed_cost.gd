extends TestCase
## Stały koszt technologii na serwerze. Migracja `*_research_fixed_cost.sql` liczy wydatki na badania
## jak Research.cost_of: zwykła technologia po koszcie epoki, doktryny (TechTree.DOCTRINES) ×1,6
## za każdą wcześniejszą doktrynę epoki. Test szuka listy doktryn w komentarzu i w funkcji migracji.

const MIGRATION := "res://supabase/migrations/20261125110000_research_fixed_cost.sql"


func _sql() -> String:
	return FileAccess.get_file_as_string(MIGRATION)


## Lista kodów jak w komentarzu migracji: ["A1", "A2"].
static func _json_list(codes: Array[String]) -> String:
	var parts: Array[String] = []
	for c in codes:
		parts.append("\"%s\"" % c)
	return "[" + ", ".join(parts) + "]"


## Lista kodów jak w funkcji migracji: array['A1', 'A2'].
static func _sql_array(codes: Array[String]) -> String:
	var parts: Array[String] = []
	for c in codes:
		parts.append("'%s'" % c)
	return "array[" + ", ".join(parts) + "]"


func test_doctrines_match_game() -> bool:
	var sql := _sql()
	assert_true(not sql.is_empty(), "migracja istnieje")
	assert_true(sql.contains("DOCTRINES = " + _json_list(TechTree.DOCTRINES)), "doktryny w komentarzu")
	assert_true(sql.contains(_sql_array(TechTree.DOCTRINES) + "::text[]"), "doktryny w funkcji")
	return true


func test_server_formula_matches_game() -> bool:
	# wzór serwera: k nowych doktryn po m starych w epoce to kroki m..m+k-1, zwykła technologia krok 0
	var r := Research.new()
	var e := Economy.new(0)
	var order: Array[String] = ["A39", "A1", "G18", "A2", "G1", "G19", "G2"]
	var server: Array[int] = [0, 0, 0, 0]
	var game: Array[int] = [0, 0, 0, 0]
	var doctrines := 0
	for code in order:
		for res in EconomyConfig.count():
			e.amounts[res] = 1 << 40
		var price := r.cost_of(code)
		var expected := ResearchConfig.cost(0, doctrines if TechTree.is_doctrine(code) else 0)
		if TechTree.is_doctrine(code):
			doctrines += 1
		for i in 4:
			game[i] += price[i]
			server[i] += expected[i]
		assert_eq(r.start(code, 0, e, 0), Research.Result.OK, "start %s" % code)
		assert_eq(r.update(r.duration_ms), code, "koniec %s" % code)
	assert_eq(game, server, "suma kosztów jak na serwerze")
	assert_eq(server, [100 * 3 + 100 + 160 + 256 + 409, 50 * 3 + 50 + 80 + 128 + 204, 50 * 3 + 50 + 80 + 128 + 204, 0] as Array[int],
			"liczby z testu pgTAP")
	return true
