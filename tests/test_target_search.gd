extends TestCase
## Dobór przeciwnika (#24): odpowiedź `find_targets`, czyszczenie danych od innych graczy,
## uzupełnianie botami do 3 celów, szacowany łup zgodny z serwerem i zapytanie w kliencie.

const UID := "00000000-0000-0000-0000-0000000000a1"
const B := "00000000-0000-0000-0000-0000000000b1"
const C := "00000000-0000-0000-0000-0000000000c1"
const D := "00000000-0000-0000-0000-0000000000d1"
const SESSION_PATH := "user://test_targets_session.json"
const SYNC_PATH := "user://test_targets_sync.json"
const MIGRATION := "res://supabase/migrations/20261119140714_match_targets.sql"


func _row(id: String, nickname: String = "Bolko", castle: String = "Gród Bolka") -> Dictionary:
	return {
		"player_id": id, "nickname": nickname, "castle_name": castle, "ruler": Rulers.DEFAULT,
		"age": 0, "rating": 1040, "map_seed": 777, "footprint": [[30, 30, 2, 2], [33, 30, 1, 1]],
		"loot": [50, 20, 0, 0],
	}


func test_parse_player_row() -> bool:
	var list := TargetSearch.parse_response({"targets": [_row(B)]})
	assert_eq(list.size(), 1, "jeden gracz")
	var t := list[0]
	assert_true(not t.is_bot, "gracz, nie bot")
	assert_eq(t.player_id, B, "id")
	assert_eq(t.player_name, "Bolko", "imię")
	assert_eq(t.castle_name, "Gród Bolka", "nazwa zamku")
	assert_eq(t.ruler, Rulers.DEFAULT, "władca")
	assert_eq(t.rating, 1040, "ranking")
	assert_eq(t.map_seed, 777, "seed terenu")
	assert_eq(t.footprint, [Rect2i(30, 30, 2, 2), Rect2i(33, 30, 1, 1)] as Array[Rect2i], "zarys")
	assert_eq(t.loot, [50, 20, 0, 0] as Array[int], "łup")
	assert_eq(t.key(), "gracz:" + B, "klucz cache")
	return true


## Dane pochodzą od innych graczy: złe wiersze odpadają, reszta jest przycinana.
func test_parse_rejects_and_cleans_untrusted_rows() -> bool:
	var bad_id := _row("nie-uuid")
	var no_seed := _row(C)
	no_seed["map_seed"] = 0
	var no_castle := _row(D, "Ala", "<b>")
	var weird := _row(B, "Ala<script>", "  Bardzo   długa nazwa zamku  ")
	weird["ruler"] = "smok"
	weird["rating"] = 1e12
	weird["age"] = -3
	weird["footprint"] = [[1, 1, 2, 2], [60, 60, 10, 10], ["x", 1, 1, 1], [1, 1, 0, 1], 5, [2, 2, 1]]
	weird["loot"] = [-5, "7", 1e9]
	var list := TargetSearch.parse_response({"targets": [bad_id, no_seed, no_castle, weird, _row(B)]})
	assert_eq(list.size(), 1, "zostaje jeden poprawny wiersz, bez duplikatu id")
	var t := list[0]
	assert_eq(t.player_name, "Gracz", "imię ze znakami spoza fontu zastępuje „Gracz”")
	assert_eq(t.castle_name, "Bardzo długa naz", "nazwa zamku oczyszczona i przycięta do 16 znaków")
	assert_eq(t.ruler, Rulers.DEFAULT, "nieznany władca to domyślny")
	assert_eq(t.rating, TargetSearch.MAX_RATING, "ranking przycięty")
	assert_eq(t.age, 0, "epoka przycięta")
	assert_eq(t.footprint, [Rect2i(1, 1, 2, 2)] as Array[Rect2i], "zarys tylko w mapie i z liczb")
	assert_eq(t.loot, [0, 0, TargetSearch.MAX_LOOT, 0] as Array[int], "łup: liczby, 0..MAX, 4 surowce")
	assert_true(TargetSearch.parse_response(null).is_empty(), "null")
	assert_true(TargetSearch.parse_response({"targets": "x"}).is_empty(), "targets nie tablicą")
	var many: Array = [_row(B), _row(C), _row(D), _row("00000000-0000-0000-0000-0000000000e1")]
	assert_eq(TargetSearch.parse_response({"targets": many}).size(), TargetSearch.COUNT, "najwyżej 3")
	return true


## Kryterium #24: zawsze 3 cele, braki uzupełniają boty.
func test_always_three_targets() -> bool:
	var none: Array[TargetSearch.Target] = []
	for beaten in [0, 1, 2, 5, BotRoster.COUNT - 1, BotRoster.COUNT, 99]:
		var list := TargetSearch.fill(none, beaten)
		assert_eq(list.size(), 3, "3 boty przy %d zdobytych" % beaten)
		var seen := {}
		for t in list:
			assert_true(t.is_bot, "sam bot")
			assert_true(t.bot_idx >= 0 and t.bot_idx < BotRoster.COUNT, "numer bota w zakresie")
			seen[t.bot_idx] = true
		assert_eq(seen.size(), 3, "3 różne boty")
	var players := TargetSearch.parse_response({"targets": [_row(B), _row(C)]})
	var mixed := TargetSearch.fill(players, 4)
	assert_eq(mixed.size(), 3, "2 graczy + 1 bot")
	assert_true(not mixed[0].is_bot and not mixed[1].is_bot and mixed[2].is_bot, "najpierw gracze")
	assert_eq(mixed[2].bot_idx, 4, "bot: bieżący cel kampanii")
	var full := TargetSearch.fill(TargetSearch.parse_response({"targets": [_row(B), _row(C), _row(D)]}), 0)
	for t in full:
		assert_true(not t.is_bot, "3 graczy: bez botów")
	return true


## Boty: bieżący cel, potem zdobyte od najmłodszego, a nowy gracz dostaje kolejne zamki z listy.
func test_bot_order_is_deterministic() -> bool:
	assert_eq(TargetSearch.bot_indices(5, 3), [5, 4, 3] as Array[int], "bieżący i zdobyte")
	assert_eq(TargetSearch.bot_indices(0, 3), [0, 1, 2] as Array[int], "nowy gracz")
	assert_eq(TargetSearch.bot_indices(1, 3), [1, 0, 2] as Array[int], "jeden zdobyty")
	assert_eq(TargetSearch.bot_indices(30, 3), [19, 18, 17] as Array[int], "wszystkie zdobyte")
	assert_eq(TargetSearch.bot_indices(3, 0), [] as Array[int], "brak wolnych miejsc")
	var a := TargetSearch.bot_target(7)
	assert_eq(a.castle_name, BotRoster.NAMES[7], "nazwa z listy botów")
	assert_eq(a.map_seed, BotRoster.seed_of(7), "seed z listy botów")
	assert_eq(a.key(), "bot:7", "klucz cache")
	assert_true(not a.footprint.is_empty(), "bot ma zarys budynków")
	var fresh := BotRoster.generate(7)
	assert_eq(a.footprint.size(), fresh.grid.buildings.size(), "zarys z wygenerowanego zamku")
	assert_eq(TargetSearch.bot_target(7), a, "bot z cache")
	return true


## Szacowany łup: bot ze skarbca jak po wygranej z minimalnym procentem; gracz 5 procent zapasów,
## liczone na serwerze (ten sam procent w migracji).
func test_loot_estimate_matches_server() -> bool:
	assert_eq(BattleResult.loot_estimate_percent(), 5, "5 procent zapasów")
	var r := BattleResult.new()
	r.won = true
	r.percent = 0
	r.compute_loot(3, false)
	assert_eq(BattleResult.estimate_bot_loot(3), r.loot, "bot: łup wygranej z WIN_LOOT_PERCENT")
	var sql := FileAccess.get_file_as_string(MIGRATION)
	assert_true(not sql.is_empty(), "migracja match_targets jest w projekcie")
	var p := BattleResult.loot_estimate_percent()
	assert_true(sql.contains("LOOT_ESTIMATE_PERCENT = %d" % p), "znacznik procentu w migracji")
	assert_true(sql.contains("* %d / 100" % p), "ten sam procent w obliczeniu SQL")
	return true


func test_age_label() -> bool:
	assert_eq(TargetSearch.age_label(0), "Epoka I", "epoka I")
	assert_eq(TargetSearch.age_label(1), "Epoka II", "epoka II")
	assert_eq(TargetSearch.age_label(-1), "Epoka I", "przycięta")
	return true


func _client() -> SupabaseClient:
	SupabaseSession.clear(SESSION_PATH)
	SaveGame.delete(SYNC_PATH)
	var c := SupabaseClient.new()
	c.setup(SupabaseConfig.parse(JSON.stringify({
		"url": "https://abc.supabase.co", "publishable_key": "sb_publishable_test123",
	})), SESSION_PATH, SYNC_PATH)
	c.fake_transport = true
	return c


func _online(c: SupabaseClient) -> void:
	c.handle_auth(SupabaseClient.Call.SIGNUP, HTTPRequest.RESULT_SUCCESS, 200, JSON.stringify({
		"access_token": "t1", "refresh_token": "r1", "expires_in": 3600,
		"user": {"id": UID, "is_anonymous": true},
	}))


func test_client_find_targets() -> bool:
	var c := _client()
	var got: Array = []
	c.targets_found.connect(func(list: Array[TargetSearch.Target], ok: bool, limited: bool) -> void:
		got.append([list, ok, limited]))
	assert_true(not c.find_targets(), "bez sesji nie szuka")
	_online(c)
	assert_true(c.find_targets(), "online szuka")
	assert_true(c.find_targets(), "drugie szukanie czeka na pierwsze")
	c.handle_targets(HTTPRequest.RESULT_SUCCESS, 200, JSON.stringify({"targets": [_row(B)]}))
	assert_eq(got.size(), 1, "jedna odpowiedź")
	assert_true(got[0][1] as bool, "ok")
	assert_eq((got[0][0] as Array).size(), 1, "jeden gracz")
	c.find_targets()
	c.handle_targets(HTTPRequest.RESULT_SUCCESS, 500, "{}")
	assert_true(not (got[1][1] as bool), "błąd serwera: ok false")
	assert_true((got[1][0] as Array).is_empty(), "bez graczy")
	assert_true(not (got[1][2] as bool), "500 to nie limit")
	c.find_targets()
	c.handle_targets(HTTPRequest.RESULT_SUCCESS, 429, "{}")
	assert_true(not (got[2][1] as bool) and got[2][2] as bool, "429: limit szukań")
	got.remove_at(2)
	c.find_targets()
	c.handle_targets(HTTPRequest.RESULT_SUCCESS, 200, "to nie json")
	assert_true(got[2][1] as bool, "zła treść: ok, ale bez graczy")
	assert_true((got[2][0] as Array).is_empty(), "bez graczy")
	SupabaseSession.clear(SESSION_PATH)
	SaveGame.delete(SYNC_PATH)
	c.free()
	return true
