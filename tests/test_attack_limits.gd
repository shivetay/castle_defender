extends TestCase
## Limit armii i utrzymania przy starcie ataku (#249). Serwer (`public.begin_attack`) liczy z kopii
## zamku to samo co gra (Recruitment.army_limit, Recruitment.upkeep_limit), więc liczby w migracji
## muszą zgadzać się z grą, a klient wysyła tylko armię, która mieści się w obu limitach.

const MIGRATION := "res://supabase/migrations/20261120131426_army_limits.sql"
## Nowsza wersja private.food_production z Polem i spichlerzem (#35).
const FARM_MIGRATION := "res://supabase/migrations/20261120135657_farm_food.sql"
## Stawki i limity do poziomu 10 (#262) mają najnowsze wersje funkcji.
const BALANCE_MIGRATION := "res://supabase/migrations/20261127120000_age_two_balance.sql"
const K := BuildingTypes.Kind
const U := UnitTypes.Unit
const R := EconomyConfig.Res


func _free_cell(grid: BuildGrid, kind: int, near_water: bool = false) -> Vector2i:
	for y in grid.terrain.size - 1:
		for x in grid.terrain.size - 1:
			var placed := grid.placement_for(Vector2i(x, y), kind)
			if placed != Rect2i() and (not near_water or grid.touches_water(placed)):
				return Vector2i(x, y)
	return Vector2i(-1, -1)


## Zamek z Dworem `manor` (20 miejsc przy 2) i bez Rybaka (20 Ży/h z samego grodu).
func _grid(manor: int) -> BuildGrid:
	var grid := BuildGrid.new(TerrainMap.generate(1337))
	grid.place_kind(_free_cell(grid, K.MANOR), K.MANOR, manor)
	return grid


## Liczby gry i serwera są te same (znaczniki w komentarzach migracji).
func test_server_constants_match_game() -> bool:
	var sql := FileAccess.get_file_as_string(MIGRATION)
	assert_true(not sql.is_empty(), "migracja jest")
	assert_true(sql.contains("UPKEEP = %s" % str(UnitTypes.UPKEEP)), "utrzymanie jednostek")
	assert_true(sql.contains("array%s" % str(UnitTypes.UPKEEP)), "tabela w private.unit_upkeep")
	assert_true(sql.contains("ARMY_PER_MANOR_LEVEL = %d" % RecruitmentConfig.ARMY_PER_MANOR_LEVEL), "miejsca za Dwór")
	assert_true(sql.contains("ARMY_PER_BARRACKS_LEVEL = %d" % RecruitmentConfig.ARMY_PER_BARRACKS_LEVEL),
			"miejsca za Koszary")
	assert_true(sql.contains("FOOD_BASE = %d" % EconomyConfig.BASE_PER_HOUR[R.FOOD]), "żywność grodu")
	var balance := FileAccess.get_file_as_string(BALANCE_MIGRATION)
	var fisher: Array = EconomyConfig.BUILDING_PRODUCTION[K.FISHER]
	assert_eq(int(fisher[0]), R.FOOD, "Rybak daje żywność")
	assert_true(balance.contains("FISHER_FOOD = %s" % str(fisher[1])), "stawki Rybaka")
	assert_true(balance.contains("array%s" % str(fisher[1])), "tabela w private.food_production")
	var g2: Array = TechTree.PRODUCTION_BONUS["G2"]
	assert_eq(int(g2[0]), R.FOOD, "G2 dotyczy żywności")
	assert_true(sql.contains("G2 = %d procent" % int(g2[1])), "premia G2")
	assert_true(sql.contains("MANOR = %d, FISHER = %d, BARRACKS = %d" % [K.MANOR, K.FISHER, K.BARRACKS]),
			"rodzaje budynków")
	assert_true(balance.contains("ARMY_PER_MANOR_LEVEL = %d" % RecruitmentConfig.ARMY_PER_MANOR_LEVEL), "Dwór epoki I")
	assert_true(balance.contains("ARMY_PER_MANOR_LEVEL_AGE_II = %d" % RecruitmentConfig.ARMY_PER_MANOR_LEVEL_AGE_II),
			"Dwór epoki II")
	assert_true(balance.contains("ARMY_PER_BARRACKS_LEVEL = %d" % RecruitmentConfig.ARMY_PER_BARRACKS_LEVEL), "Koszary")
	assert_true(balance.contains("select coalesce((select %d * least(greatest(b.level, 1), %d) + %d * greatest(b.level - %d, 0)" % [
			RecruitmentConfig.ARMY_PER_MANOR_LEVEL, Ages.LEVELS_PER_AGE, RecruitmentConfig.ARMY_PER_MANOR_LEVEL_AGE_II,
			Ages.LEVELS_PER_AGE]), "wzór Dworu w private.army_limit")
	assert_true(balance.contains("+ %d * coalesce((select sum(b.level)" % RecruitmentConfig.ARMY_PER_BARRACKS_LEVEL),
			"Koszary w private.army_limit")
	assert_true(balance.contains("przycina poziom do 0..%d" % Ages.MAX_TOTAL_LEVEL), "najwyższy poziom")
	assert_true(balance.contains("least(greatest(b.lvl, 0), %d)::integer" % Ages.MAX_TOTAL_LEVEL), "poziom w castle_buildings")
	return true


## Pole i spichlerz (#35): nowa wersja private.food_production w osobnej migracji zna Rybaka i Pole.
func test_farm_food_on_server() -> bool:
	var sql := FileAccess.get_file_as_string(BALANCE_MIGRATION)
	assert_true(not sql.is_empty(), "migracja Pola jest")
	var fisher: Array = EconomyConfig.BUILDING_PRODUCTION[K.FISHER]
	var farm: Array = EconomyConfig.BUILDING_PRODUCTION[K.FARM]
	assert_eq(int(farm[0]), R.FOOD, "Pole daje żywność")
	assert_true(sql.contains("FOOD_BASE = %d" % EconomyConfig.BASE_PER_HOUR[R.FOOD]), "żywność grodu")
	assert_true(sql.contains("FISHER_FOOD = %s" % str(fisher[1])), "stawki Rybaka")
	assert_true(sql.contains("FARM_FOOD = %s" % str(farm[1])), "stawki Pola")
	assert_true(sql.contains("when %d then (array%s)" % [K.FISHER, str(fisher[1])]), "tabela Rybaka w funkcji")
	assert_true(sql.contains("when %d then (array%s)" % [K.FARM, str(farm[1])]), "tabela Pola w funkcji")
	var farm_sql := FileAccess.get_file_as_string(FARM_MIGRATION)
	assert_true(farm_sql.contains("FISHER = %d, FARM = %d" % [K.FISHER, K.FARM]), "rodzaje budynków")
	assert_true(farm_sql.contains("G2 = %d procent" % int((TechTree.PRODUCTION_BONUS["G2"] as Array)[1])), "premia G2")
	return true


## Serwer zna tylko Rybaka, Pole i G2 jako źródła żywności. Nowe źródło bez migracji rozjechałoby limity.
func test_food_sources_known_to_server() -> bool:
	for kind: int in EconomyConfig.BUILDING_PRODUCTION:
		var entry: Array = EconomyConfig.BUILDING_PRODUCTION[kind]
		if int(entry[0]) == R.FOOD:
			assert_true(kind == K.FISHER or kind == K.FARM, "żywność dają tylko Rybak i Pole")
	for code: String in TechTree.PRODUCTION_BONUS:
		var bonus: Array = TechTree.PRODUCTION_BONUS[code]
		if int(bonus[0]) == R.FOOD:
			assert_eq(code, "G2", "premię do żywności daje tylko G2")
	return true


## Serwer czyta budynki z zapisu jako [id, rodzaj, poziom, ...], a badania z `research.done`.
func test_save_layout_read_by_server() -> bool:
	var grid := _grid(3)
	var entry := ((grid.save_data()["buildings"] as Array)[0]) as Array
	assert_eq(entry.size(), 7, "7 pól na budynek")
	assert_eq(int(entry[1]), K.MANOR, "rodzaj na drugim miejscu")
	assert_eq(int(entry[2]), 3, "poziom na trzecim")
	var research := Research.new()
	research.done["G2"] = true
	assert_true((research.save_data()["done"] as Array).has("G2"), "zbadane kody w research.done")
	return true


## Kryterium: armia ponad limit miejsc nie idzie do ataku, obcięta o całe oddziały od końca.
func test_fit_attack_slot_limit() -> bool:
	var grid := _grid(2)
	assert_eq(Recruitment.army_limit(grid), 20, "Dwór 2: 20 miejsc")
	var army: Array = [[U.RAM, 10], [U.RAM, 10], [U.RAM, 5]]
	assert_eq(Recruitment.fit_attack(army, grid, Research.new()), [[U.RAM, 10], [U.RAM, 10]],
			"taran nie je, ale zajmuje miejsce: trzeci oddział zostaje")
	assert_eq(Recruitment.fit_attack([[U.RAM, 10], [U.RAM, 10]], grid, Research.new()).size(), 2,
			"równo w limicie przechodzi")
	return true


## Kryterium: armia, której utrzymanie przekracza produkcję żywności, nie idzie do ataku.
func test_fit_attack_upkeep_limit() -> bool:
	var grid := _grid(5)
	var research := Research.new()
	assert_eq(Recruitment.upkeep_limit(grid, research), 20, "sam gród: 20 Ży/h")
	var army: Array = [[U.RIDER, 10], [U.AXE_WARRIOR, 1]]
	assert_eq(Recruitment.fit_attack(army, grid, research), [[U.RIDER, 10]], "jeźdźcy jedzą 20, topornik już nie")
	grid.place_kind(_free_cell(grid, K.FISHER, true), K.FISHER, 1)
	assert_eq(Recruitment.fit_attack(army, grid, research), army, "z Rybakiem całość się mieści")
	return true


## Kolejność oddziałów zostaje, a wynik jest ten sam przy każdym wywołaniu.
func test_fit_attack_keeps_prefix_and_is_deterministic() -> bool:
	var grid := _grid(1)
	var army: Array = [[U.AXE_WARRIOR, 4], [U.RIDER, 3], [U.AXE_WARRIOR, 4]]
	var a := Recruitment.fit_attack(army, grid, Research.new())
	assert_eq(a, Recruitment.fit_attack(army, grid, Research.new()), "ten sam zamek → ta sama armia")
	assert_eq(a, army.slice(0, a.size()), "początek listy w tej samej kolejności")
	assert_eq(a.size(), 2, "trzeci oddział przekroczyłby 10 miejsc")
	return true


## Odmowy serwera mają czytelne komunikaty mieszczące się w pasku (font 8 px, 320 px).
func test_error_messages() -> bool:
	for code: String in ["army_over_limit", "army_over_upkeep", "unsupported_version"]:
		var text := AttackStart.error_message(code)
		assert_true(text != AttackStart.error_message("cokolwiek"), "%s: własny komunikat" % code)
		assert_true(text.length() <= 50, "%s: mieści się w pasku" % code)
	return true


## #354, ADR 0008: wersja gry bez packa na serwerze nie atakuje, a gracz wie, że ma zaktualizować grę.
func test_unsupported_version_asks_for_update() -> bool:
	assert_true(AttackStart.error_message("unsupported_version").contains("Zaktualizuj"), "komunikat o aktualizacji")
	assert_eq(SupabaseClient.edge_error(HTTPRequest.RESULT_SUCCESS, 409, '{"error":"unsupported_version"}'),
			"unsupported_version", "kod 409 dochodzi do komunikatu")
	assert_true(AttackLaunch.request("x", AttackPlan.new())["sim_version"] as int > 0, "wersja symulacji w żądaniu")
	return true
