extends TestCase
## Surowce bez zaufanej edycji lokalnej (#274, etapy 1 i 2). Serwer (`*_resource_sanity.sql`) liczy
## pojemność i pokrycie złota tymi samymi liczbami co gra, przenosi łup PvP między zamkami, a telefon
## dolicza zmianę z odpowiedzi na zapis zamku (`loot_applied`). Łup z wyprawy na bota przychodzi tą samą
## drogą (#282).

const MIGRATION := "res://supabase/migrations/20261124090000_resource_sanity.sql"
## Magazyn do poziomu 10 (#262) ma najnowsza wersja `private.castle_capacity`.
const BALANCE_MIGRATION := "res://supabase/migrations/20261127120000_age_two_balance.sql"
const MAIN := preload("res://scripts/main.gd")
const K := BuildingTypes.Kind
const R := EconomyConfig.Res


## Liczby gry i serwera są te same (znaczniki w komentarzach migracji i tabele w funkcjach).
func test_server_constants_match_game() -> bool:
	var sql := FileAccess.get_file_as_string(MIGRATION)
	assert_true(not sql.is_empty(), "migracja jest")
	assert_true(sql.contains("CAPACITY = %s" % str(EconomyConfig.CAPACITY)), "pojemność grodu")
	var balance := FileAccess.get_file_as_string(BALANCE_MIGRATION)
	assert_true(balance.contains("WAREHOUSE_CAPACITY = %s" % str(EconomyConfig.WAREHOUSE_CAPACITY)), "Magazyny")
	assert_true(balance.contains("(array%s)[b.level]" % str(EconomyConfig.WAREHOUSE_CAPACITY)), "tabela w castle_capacity")
	assert_true(sql.contains("WAREHOUSE = %d" % K.WAREHOUSE), "rodzaj Magazynu")
	assert_true(sql.contains("b.kind = %d" % K.WAREHOUSE), "Magazyn w castle_capacity")
	assert_true(sql.contains("select (%d + coalesce" % EconomyConfig.CAPACITY[R.WOOD]), "zapas Dworu w castle_capacity")
	assert_true(sql.contains("PUSH_INTERVAL_S = %d" % int(SupabaseClient.PUSH_INTERVAL_S)), "przerwa między zapisami")
	# PUSH_LIMIT ma zapas ponad zwykłą synchronizację (zapis co PUSH_INTERVAL_S w 10 minut)
	@warning_ignore("integer_division")
	var normal := 600 / int(SupabaseClient.PUSH_INTERVAL_S)
	assert_true(sql.contains("PUSH_LIMIT = 90") and 90 >= normal * 2, "limit zapisów z zapasem")
	assert_true(sql.contains("errcode = 'PT422'"), "odrzut kodem HTTP 422")
	assert_eq(CastleSync.REJECTED_HTTP, 422, "klient rozpoznaje odrzut")
	# pojemność z jednego miejsca: Dwór daje tyle samo każdemu surowcowi z limitem, złoto bez limitu
	for res in EconomyConfig.count():
		if res == R.GOLD:
			assert_true(not EconomyConfig.is_capped(res), "złoto bez magazynu")
		else:
			assert_eq(EconomyConfig.CAPACITY[res], EconomyConfig.CAPACITY[R.WOOD], "ta sama pojemność")
	return true


## Pojemność liczona przez serwer to Economy.capacities_for z tej samej siatki.
func test_capacity_matches_server_formula() -> bool:
	var grid := BuildGrid.new(TerrainMap.generate(1337))
	assert_eq(Economy.capacities_for(grid)[R.WOOD], 1000, "sam gród")
	var c := grid.terrain.center()
	var id := 0
	for r in 20:
		for dy in range(-r, r + 1):
			for dx in range(-r, r + 1):
				if id == 0:
					id = grid.place_kind(c + Vector2i(dx, dy), K.WAREHOUSE, 3)
	assert_true(id != 0, "Magazyn stoi")
	assert_eq(Economy.capacities_for(grid)[R.STONE], 1000 + EconomyConfig.WAREHOUSE_CAPACITY[2], "Magazyn 3")
	assert_eq(Economy.capacities_for(grid)[R.GOLD], 0, "złoto bez limitu")
	return true


## Zmiana z serwera: łup do pojemności, strata najwyżej do zera.
func test_apply_delta() -> bool:
	var e := Economy.new(0)
	e.amounts.assign([990, 100, 5, 20])
	var got := e.apply_delta([50, -30, -10, 7] as Array[int])
	assert_eq(got, [10, -30, -5, 7] as Array[int], "faktyczna zmiana")
	assert_eq(e.amounts, [1000, 70, 0, 27] as Array[int], "zapasy po zmianie")
	assert_eq(e.apply_delta([] as Array[int]), [0, 0, 0, 0] as Array[int], "pusta zmiana nic nie robi")
	return true


## Wyprawa na bota (#282): okno wyniku pokazuje łup czekający na serwer, a bez serwera nic; sam łup
## do magazynu przychodzi dopiero z `loot_applied`.
func test_bot_loot_from_server() -> bool:
	var loot: Array[int] = [10, 20, 30, 40]
	assert_eq(PveReport.shown_loot(loot, true), [10, 20, 30, 40] as Array[int], "łup przyjmie serwer")
	assert_eq(PveReport.shown_loot(loot, false), [0, 0, 0, 0] as Array[int], "bez sieci bez łupu")
	assert_eq(PveReport.shown_loot([] as Array[int], true), [0, 0, 0, 0] as Array[int], "pusty łup")
	assert_eq(loot, [10, 20, 30, 40] as Array[int], "łup bitwy bez zmian")
	var e := Economy.new(0)
	var r := BattleResult.new()
	r.loot.assign([10, 20, 30, 40])
	assert_eq(r.apply_loot(e), [10, 20, 30, 40] as Array[int], "apply_loot dodaje wszystko")
	return true


## Komunikat o łupie z serwera mieści się w pasku.
func test_loot_message() -> bool:
	assert_eq(MAIN.loot_message([50, 20, 0, 5] as Array[int]), "Łup z ataku: +50 Dr +20 Ka +5 Zł", "łup")
	assert_eq(MAIN.loot_message([-50, 0, 0, 0] as Array[int]), "Straty z najazdu: -50 Dr", "strata")
	assert_eq(MAIN.loot_message([50, -40, 0, 5] as Array[int]), "Zmiana zapasów: +50 Dr -40 Ka +5 Zł",
			"łup i strata w jednym zapisie")
	assert_eq(MAIN.loot_message([0, 0, 0, 0] as Array[int]), "", "bez zmiany bez komunikatu")
	var worst := MAIN.loot_message([-9999, -9999, -9999, -9999] as Array[int])
	assert_true(PixelFont.text_width(worst) <= Hud.MESSAGE_MAX_WIDTH, "najdłuższa strata w pasku")
	assert_true(PixelFont.text_width(PveReport.FAILED_MESSAGE) <= Hud.MESSAGE_MAX_WIDTH, "wyprawa bez łupu w pasku")
	assert_true(PixelFont.text_width(PveReport.OFFLINE_MESSAGE) <= Hud.MESSAGE_MAX_WIDTH, "wyprawa bez sieci w pasku")
	assert_true(AttackStart.error_message("castle_invalid") != AttackStart.error_message("cokolwiek"),
			"własny komunikat odrzuconego zamku")
	return true


## Odpowiedź na zapis zamku: łup scalony przez serwer albo zera.
func test_loot_from_rows() -> bool:
	assert_eq(CastleSync.loot_from_rows([{"revision": 3, "loot_applied": [5, 0, -2, 1]}]), [5, 0, -2, 1] as Array[int],
			"zmiana z odpowiedzi")
	assert_eq(CastleSync.loot_from_rows([{"revision": 3}]), [0, 0, 0, 0] as Array[int], "stary serwer bez kolumny")
	assert_eq(CastleSync.loot_from_rows([{"loot_applied": [1, 2]}]), [0, 0, 0, 0] as Array[int], "zła długość")
	assert_eq(CastleSync.loot_from_rows([{"loot_applied": [1, "x", 0, 0]}]), [0, 0, 0, 0] as Array[int], "zły typ")
	assert_eq(CastleSync.loot_from_rows(null), [0, 0, 0, 0] as Array[int], "brak odpowiedzi")
	assert_true(CastleSync.push_path("abc", 1).ends_with("select=revision,loot_applied"), "zapis prosi o łup")
	assert_eq(CastleSync.insert_path(), "/rest/v1/castles?select=revision,loot_applied", "założenie też")
	return true
