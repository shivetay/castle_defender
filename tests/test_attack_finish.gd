extends TestCase
## Koniec ataku (#25): capacity łupu z ocalałych jednostek, łup z zapasów gracza, przycięcie do capacity,
## treść żądania `finish_attack` i zgodność liczb gry z migracją serwera (`public.end_attack`).

const U := UnitTypes.Unit
const MIGRATION := "res://supabase/migrations/20261119183238_finish_attack.sql"
## Najnowsza wersja `private.unit_carry` i `private.unit_count` (Wóz, #235).
const CARRY_MIGRATION := "res://supabase/migrations/20261120122724_wagon_carry.sql"


## Piechota 5, konnica 10, taran 0; więcej ocalałych daje więcej capacity.
func test_capacity_scales_with_survivors() -> bool:
	assert_eq(UnitTypes.CARRY.size(), UnitTypes.count(), "wpis capacity dla każdej jednostki")
	assert_eq(UnitTypes.carry(U.AXE_WARRIOR), 5, "piechota")
	assert_eq(UnitTypes.carry(U.RIDER), 10, "konnica")
	assert_eq(UnitTypes.carry(U.RAM), 0, "taran nic nie wiezie")
	assert_eq(UnitTypes.carry(99), 0, "nieznany rodzaj")
	var army := [[U.AXE_WARRIOR, 10], [U.AXE_WARRIOR, 10], [U.RIDER, 10]]
	assert_eq(BattleResult.carry_capacity(army, [10, 10, 10] as Array[int]), 200, "cała armia")
	assert_eq(BattleResult.carry_capacity(army, [5, 0, 0] as Array[int]), 25, "5 ocalałych toporników")
	assert_eq(BattleResult.carry_capacity(army, [10, 10] as Array[int]), 100, "brak wpisu = 0 ocalałych")
	assert_eq(BattleResult.carry_capacity(army, [99, -3, 1] as Array[int]), 60, "ocaleli w granicach oddziału")
	assert_true(BattleResult.carry_capacity(army, [10, 10, 10] as Array[int])
			> BattleResult.carry_capacity(army, [10, 5, 10] as Array[int]), "więcej jednostek, wyższy limit")
	return true


## Łup z zamku gracza jak z bota: niechroniona połowa × 20 procent × procent łupu (przykład z testu pgTAP).
func test_player_loot_from_amounts() -> bool:
	var r := BattleResult.new()
	r.won = true
	r.percent = 60
	r.compute_player_loot([10000, 4000, 2000, 300])
	assert_eq(r.loot, [600, 240, 120, 18] as Array[int], "60 procent zniszczeń")
	r.percent = 10
	r.compute_player_loot([10000, -5, "x", 300])
	assert_eq(r.loot, [500, 0, 0, 15] as Array[int], "wygrana liczy co najmniej 50 procent; złe pola to 0")
	r.won = false
	r.compute_player_loot([10000, 4000, 2000, 300])
	assert_eq(r.loot, [0, 0, 0, 0] as Array[int], "przegrana bez łupu")
	r.won = true
	r.compute_player_loot([1000])
	assert_eq(r.loot.size(), EconomyConfig.count(), "brakujące surowce to 0")
	return true


## Przycięcie do capacity: suma nie większa niż capacity, proporcje zachowane, ten sam wynik za każdym razem.
func test_limit_to_capacity() -> bool:
	var r := BattleResult.new()
	r.loot = [600, 240, 120, 18] as Array[int]
	r.limit_to_capacity(2000)
	assert_eq(r.loot, [600, 240, 120, 18] as Array[int], "w capacity bez zmian")
	r.limit_to_capacity(25)
	var sum := 0
	for v in r.loot:
		sum += v
	assert_true(sum <= 25, "suma w capacity")
	assert_eq(r.loot, [15, 6, 3, 0] as Array[int], "proporcjonalnie, w dół")
	var again := BattleResult.new()
	again.loot = [600, 240, 120, 18] as Array[int]
	again.limit_to_capacity(25)
	assert_eq(again.loot, r.loot, "deterministycznie")
	again.limit_to_capacity(0)
	assert_eq(again.loot, [0, 0, 0, 0] as Array[int], "bez ocalałych bez łupu")
	return true


## Prawdziwa bitwa: łup po przycięciu mieści się w capacity ocalałych, a wynik dla serwera ma 3 pola.
func test_battle_loot_within_capacity() -> bool:
	var army := [[U.AXE_WARRIOR, 10], [U.ARCHER, 8]]
	var bot := BotRoster.generate(0)
	var b := Battle.create_squads(bot.grid, bot.objective, army, bot.defenders, bot.spawn,
			PixelCanvas.hash2(bot.seed_value, 0, 0xa77) & 0x7fffffff)
	b.run()
	var r := BattleResult.of(b)
	r.compute_loot(0, false)
	var alive := b.survivors(Battle.Side.ATTACKER)
	var cap := BattleResult.carry_capacity(army, alive)
	r.limit_to_capacity(cap)
	var sum := 0
	for v in r.loot:
		sum += v
	assert_true(sum <= cap, "łup w capacity")
	var srv := r.to_server()
	assert_eq(srv.keys().size(), 3, "won, percent, stars")
	assert_eq(srv["stars"][1], r.percent >= BattleResult.STAR_PERCENT, "gwiazdka połowy zgodna z procentem")
	assert_eq(srv["stars"][2], r.won, "gwiazdka donżonu zgodna z wygraną")
	return true


func test_request_and_response() -> bool:
	var r := BattleResult.new()
	r.won = true
	r.percent = 60
	r.stars = [true, true, true]
	r.loot = [20, 5, 0, 0] as Array[int]
	var body := AttackFinish.request("a1", r, 3, [5, -1] as Array[int])
	assert_eq(body["attack_id"], "a1", "id ataku")
	assert_eq(body["survivors"], [5, 0, 0] as Array[int], "ocaleli dopełnieni do liczby oddziałów")
	assert_eq(body["loot"], [20, 5, 0, 0] as Array[int], "łup")
	assert_eq((body["result"] as Dictionary)["percent"], 60, "wynik")
	var ok := AttackFinish.parse_response(JSON.parse_string('{"status":"finished","loot":[20,5,0,0]}'))
	assert_eq(ok["loot"], [20, 5, 0, 0] as Array[int], "łup przyjęty przez serwer")
	assert_true(AttackFinish.parse_response({"status": "abandoned"}).is_empty(), "porzucony atak")
	assert_true(AttackFinish.parse_response({"status": "finished", "loot": [1, 2]}).is_empty(), "zły łup")
	assert_true(AttackFinish.parse_response({"error": "loot_too_high"}).is_empty(), "odrzucony łup")
	return true


## Kopie zamku i obrony z `start_attack` trafiają do klienta tylko przy ataku na gracza.
func test_start_response_snapshots() -> bool:
	var p := AttackStart.parse_response({"id": "p", "map_seed": 42, "battle_seed": 7, "defender_id": "u",
			"castle": {"economy": {"amounts": [1, 2, 3, 4]}}, "defense": {"traps": []}})
	assert_eq((p["castle"] as Dictionary)["economy"], {"amounts": [1, 2, 3, 4]}, "kopia zamku")
	assert_eq(p["defense"], {"traps": []}, "kopia obrony")
	var bad := AttackStart.parse_response({"map_seed": 42, "battle_seed": 7, "defender_id": "u", "castle": 5})
	assert_eq(bad["castle"], {}, "zły typ kopii to pusty słownik")
	var bot := AttackStart.parse_response({"map_seed": 42, "battle_seed": 7, "bot_idx": 1})
	assert_true(not bot.has("castle"), "bot bez kopii")
	return true


## Liczby gry i serwera są te same (znaczniki w komentarzach migracji).
func test_server_constants_match_game() -> bool:
	var sql := FileAccess.get_file_as_string(MIGRATION)
	assert_true(not sql.is_empty(), "migracja jest")
	var carry_sql := FileAccess.get_file_as_string(CARRY_MIGRATION)
	assert_true(carry_sql.contains("CARRY = %s" % str(UnitTypes.CARRY)), "capacity jednostek")
	assert_true(carry_sql.contains("array%s" % str(UnitTypes.CARRY)), "tabela w private.unit_carry")
	assert_true(carry_sql.contains("UNIT_COUNT = %d" % UnitTypes.count()), "liczba rodzajów jednostek")
	assert_true(carry_sql.contains("select %d $$" % UnitTypes.count()), "liczba w private.unit_count")
	assert_true(sql.contains("MAX_SQUADS_BY_AGE = %s" % str(AttackPlan.MAX_SQUADS_BY_AGE)), "oddziały na epokę")
	assert_true(sql.contains("SQUAD_SIZE = %d" % RecruitmentConfig.SQUAD_SIZE), "wielkość oddziału")
	assert_true(sql.contains("STAR_PERCENT = %d" % BattleResult.STAR_PERCENT), "gwiazdka połowy")
	assert_true(sql.contains("WIN_LOOT_PERCENT = %d" % BattleResult.WIN_LOOT_PERCENT), "łup po wygranej")
	assert_true(sql.contains("PROTECTED_PERCENT = %d, LOOT_PERCENT = %d"
			% [BattleResult.PROTECTED_PERCENT, BattleResult.LOOT_PERCENT]), "ochrona i procent łupu")
	assert_true(sql.contains("STASH_BASE = %d, STASH_STEP = %d" % [BattleResult.STASH_BASE, BattleResult.STASH_STEP]),
			"skarbiec bota")
	assert_true(sql.contains("GOLD_BASE = %d, GOLD_STEP = %d" % [BattleResult.GOLD_BASE, BattleResult.GOLD_STEP]),
			"złoto bota")
	assert_true(sql.contains("SHIELD_PERCENT = %d, SHIELD_HOURS = %d"
			% [BattleResult.SHIELD_PERCENT, BattleResult.SHIELD_HOURS]), "tarcza")
	assert_true(sql.contains("interval '%d hours'" % BattleResult.SHIELD_HOURS), "czas tarczy w kodzie SQL")
	return true
