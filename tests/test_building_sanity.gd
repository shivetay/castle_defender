extends TestCase
## Zabudowa bez zaufanej edycji lokalnej (#274, etap 4). Serwer (`*_building_sanity.sql`) odrzuca zapis
## zamku z budynkiem wyżej niż Dwór, z epoką II bez technologii przejścia i z zabudową, której jeden
## budowniczy nie zdążyłby zbudować. Liczby czasu i reguły poziomów muszą być te same co w grze.

const MIGRATION := "res://supabase/migrations/20261124120000_building_sanity.sql"
## Czasy budowy poziomów 1–10 (ciągła krzywa, #262) ma najnowsza wersja `private.build_time_ms`.
const BALANCE_MIGRATION := "res://supabase/migrations/20261127120000_age_two_balance.sql"
## Najnowsze tabele czasu poziomu 1 i wymaganych technologii (#388: Młyn).
const MILL_MIGRATION := "res://supabase/migrations/20261127160000_mill.sql"
## Targ (#408): bez poziomów, jeden na zamek, nie przenosi się.
const MARKET_MIGRATION := "res://supabase/migrations/20261127170000_market.sql"
const K := BuildingTypes.Kind


func _sql() -> String:
	return FileAccess.get_file_as_string(MIGRATION)


func _balance_sql() -> String:
	return FileAccess.get_file_as_string(BALANCE_MIGRATION)


## Czasy poziomu 1 rodzajów do Młyna. Targ (#408) nie ma czasu budowy: serwer daje 0 dla rodzaju spoza tablicy
## (`coalesce`), więc tablica w migracji kończy się na Młynie.
func _base_times() -> Array[int]:
	var out: Array[int] = []
	for kind in K.MARKET:
		out.append(int(BuildConfig.BASE_TIME_S.get(kind, 0)))
	return out


## Znaczniki w komentarzu i tabele w `private.build_time_ms` to liczby z BuildConfig.
func test_server_time_constants_match_game() -> bool:
	var sql := _sql()
	assert_true(not sql.is_empty(), "migracja jest")
	var base := str(_base_times())
	var mill := FileAccess.get_file_as_string(MILL_MIGRATION)
	assert_true(mill.contains("BASE_TIME_S = %s" % base), "czasy poziomu 1 w komentarzu")
	assert_true(mill.contains("coalesce((array%s)[p_kind + 1], 0)" % base), "czasy poziomu 1 w funkcji")
	var balance := _balance_sql()
	assert_true(balance.contains("TIME_MULT = %s" % str(BuildConfig.TIME_MULT)), "krzywa czasu")
	assert_true(balance.contains("(array%s)[p_level]" % str(BuildConfig.TIME_MULT)), "krzywa w funkcji")
	assert_eq(BuildConfig.TIME_MULT.size(), Ages.MAX_TOTAL_LEVEL, "krzywa przez wszystkie poziomy")
	var forts := str(BuildConfig.FORT_KINDS).replace("[", "(").replace("]", ")")
	assert_true(balance.contains("FORT_KINDS = %s" % str(BuildConfig.FORT_KINDS)), "umocnienia w komentarzu")
	assert_true(balance.contains("FORT_AGE_II_TIME_PERCENT = %d" % BuildConfig.FORT_AGE_II_TIME_PERCENT),
			"połowa czasu w komentarzu")
	assert_true(balance.contains("case when p_kind in %s and p_level > %d" % [forts, Ages.LEVELS_PER_AGE]),
			"umocnienia epoki II w funkcji")
	var top := BuildConfig.TIME_MULT[Ages.LEVELS_PER_AGE - 1]
	assert_true(balance.contains("then %d + ((array%s)[p_level] - %d) * %d / 100" % [top,
			str(BuildConfig.TIME_MULT), top, BuildConfig.FORT_AGE_II_TIME_PERCENT]),
			"umocnienia: połowa przyrostu ponad poziom 5 w funkcji")
	assert_true(balance.contains("MANOR_TIME_S = %s" % str(BuildConfig.MANOR_TIME_S)), "czasy Dworu")
	assert_true(balance.contains("when p_kind = %d then (array%s)" % [K.MANOR, str(BuildConfig.MANOR_TIME_S)]),
			"czasy Dworu w funkcji")
	assert_eq(Ages.LEVELS_PER_AGE, 5, "5 poziomów na epokę jak w funkcji")
	assert_true(sql.contains("MAX_TOTAL_LEVEL = %d" % Ages.MAX_TOTAL_LEVEL), "najwyższy poziom")
	assert_true(sql.contains("BUILDERS = %d" % BuildConfig.BUILDERS), "jeden budowniczy")
	assert_true(sql.contains("BUILDER_TIME_PERCENT = %d" % RulerPerks.BUILDER_TIME_PERCENT), "perk Budowniczy")
	return true


## Ten sam wzór co `private.build_time_ms` daje BuildConfig.time_ms dla każdego rodzaju i poziomu.
func test_server_formula_matches_build_config() -> bool:
	var base := _base_times()
	for kind in K.size():
		for level in range(1, Ages.MAX_TOTAL_LEVEL + 1):
			var server := 0
			if kind >= base.size():
				server = 0  # coalesce: rodzaj spoza tablicy (Targ) buduje się od razu
			elif kind == K.MANOR:
				server = BuildConfig.MANOR_TIME_S[level - 1] * 1000
			else:
				var mult := BuildConfig.TIME_MULT[level - 1]
				if BuildConfig.FORT_KINDS.has(kind) and level > Ages.LEVELS_PER_AGE:
					@warning_ignore("integer_division")
					var top5 := BuildConfig.TIME_MULT[Ages.LEVELS_PER_AGE - 1]
					mult = top5 + (mult - top5) * BuildConfig.FORT_AGE_II_TIME_PERCENT / 100
				server = base[kind] * mult * 1000
			assert_eq(server, BuildConfig.time_ms(kind, level), "czas %d poziom %d" % [kind, level])
	return true


## Reguły poziomów serwera to reguły gry: budynek do poziomu Dworu, bez poziomów tylko 1, epoka II
## z technologiami przejścia.
func test_level_rules_match_game() -> bool:
	var sql := _sql()
	assert_true(sql.contains("MANOR = %d" % K.MANOR), "rodzaj Dworu")
	assert_true(sql.contains("KEEP = %d, WATCHTOWER = %d" % [K.KEEP, K.WATCHTOWER]), "rodzaje bez poziomów")
	assert_true(sql.contains("b.kind in (%d, %d)" % [K.KEEP, K.WATCHTOWER]), "bez poziomów w funkcji")
	var market := FileAccess.get_file_as_string(MARKET_MIGRATION)
	assert_true(market.contains("KEEP = %d, WATCHTOWER = %d, MARKET = %d" % [K.KEEP, K.WATCHTOWER, K.MARKET]),
			"rodzaje bez poziomów z Targiem (#408)")
	assert_true(market.contains("b.kind in (%d, %d, %d)" % [K.KEEP, K.WATCHTOWER, K.MARKET]),
			"bez poziomów w funkcji z Targiem")
	for kind in K.size():
		var flat := kind == K.KEEP or kind == K.WATCHTOWER or kind == K.MARKET
		assert_eq(BuildingTypes.has_levels(kind), not flat, "tylko donżon, strażnica i Targ bez poziomów")
		if kind != K.MANOR:
			assert_eq(BuildConfig.max_level(kind, 3), 1 if flat else 3, "do poziomu Dworu")
	var techs := str(Ages.TRANSITION_TECHS[0]).replace("\"", "")
	assert_eq(techs, "[O1, G1, A7]", "technologie przejścia I → II")
	assert_true(sql.contains("'[\"O1\", \"G1\", \"A7\"]'"), "te same technologie w funkcji")
	return true


## Nowy budynek wymaga tej samej technologii co w grze (BuildConfig.REQUIRED_TECH, review #279).
func test_required_tech_matches_game() -> bool:
	var keys: Array = BuildConfig.REQUIRED_TECH.keys()
	keys.sort()
	var parts: Array[String] = []
	for kind: int in keys:
		parts.append("\"%d\": \"%s\"" % [kind, BuildConfig.REQUIRED_TECH[kind]])
	var table := "{" + ", ".join(parts) + "}"
	var sql := _sql()
	var mill := FileAccess.get_file_as_string(MILL_MIGRATION)
	assert_true(mill.contains("REQUIRED_TECH = " + table), "tabela w komentarzu")
	assert_true(mill.contains("select ('" + table + "'::jsonb ->> n.kind::text)"), "tabela w funkcji")
	assert_true(sql.contains("TOLERANCE = 5 minut łącznie"), "tolerancja łączna, nie na zapis")
	return true


## Kolejka w zapisie ma pola, z których serwer liczy zlecenie w toku (`queue.orders[0]`).
func test_queue_save_has_server_fields() -> bool:
	var grid := BuildGrid.new(TerrainMap.generate(1337))
	var manor := grid.place(grid.manor_spot(grid.terrain.size), K.MANOR, 1)
	var q := BuildQueue.new()
	var e := Economy.new(0)
	e.amounts.assign([5000, 5000, 5000, 0])
	e.capacities.assign([10000, 10000, 10000, 0])
	assert_eq(q.order_upgrade(grid, e, manor, 0), BuildQueue.Result.OK, "Dwór 2 w kolejce")
	var saved: Dictionary = q.save_data()
	var first: Dictionary = (saved["orders"] as Array)[0]
	assert_eq(int(first["building_id"]), manor, "id budynku")
	assert_eq(int(first["level"]), 2, "poziom zlecenia")
	assert_true(_sql().contains("p_castle -> 'queue' -> 'orders' -> 0"), "serwer czyta pierwsze zlecenie")
	return true
