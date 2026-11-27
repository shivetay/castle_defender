extends TestCase
## Kampania zamków-botów na serwerze (#386, ADR 0015): odmowa `bot_locked` z postępem z serwera,
## wyrównanie licznika w grze, karty Wyprawy tylko z odblokowanymi botami i zgodność z migracją.

const MIGRATION := "res://supabase/migrations/20261127180000_bot_campaign.sql"
const EDGE := "res://supabase/functions/start_attack/index.ts"
const UID := "00000000-0000-0000-0000-0000000386b1"
const SESSION_PATH := "user://test_bot_campaign_session.json"
const SYNC_PATH := "user://test_bot_campaign_sync.json"
const U := UnitTypes.Unit


## Postęp z odmowy: tylko liczba 0..BotRoster.COUNT przy kodzie `bot_locked`.
func test_locked_progress_from_response() -> bool:
	assert_eq(AttackStart.locked_progress({"error": "bot_locked", "bots_beaten": 2}), 2, "postęp z serwera")
	assert_eq(AttackStart.locked_progress({"error": "bot_locked", "bots_beaten": 0}), 0, "nowy gracz")
	assert_eq(AttackStart.locked_progress({"error": "bot_locked", "bots_beaten": float(BotRoster.COUNT)}),
			BotRoster.COUNT, "liczba z JSON jako float")
	assert_eq(AttackStart.locked_progress({"error": "bot_locked"}), -1, "bez postępu")
	assert_eq(AttackStart.locked_progress({"error": "bot_locked", "bots_beaten": "3"}), -1, "tekst to nie liczba")
	assert_eq(AttackStart.locked_progress({"error": "bot_locked", "bots_beaten": -1}), -1, "poniżej zakresu")
	assert_eq(AttackStart.locked_progress({"error": "bot_locked", "bots_beaten": BotRoster.COUNT + 1}), -1,
			"powyżej zakresu")
	assert_eq(AttackStart.locked_progress({"error": "bot_locked", "bots_beaten": 2.5}), -1, "ułamek")
	assert_eq(AttackStart.locked_progress({"error": "target_busy", "bots_beaten": 2}), -1, "inny kod")
	assert_eq(AttackStart.locked_progress(null), -1, "brak treści")
	return true


## Odmowa ma własny komunikat, który mieści się w pasku (font 8 px, 320 px).
func test_locked_message() -> bool:
	var text := AttackStart.error_message(AttackStart.BOT_LOCKED)
	assert_true(text != AttackStart.error_message("cokolwiek"), "własny komunikat")
	assert_true(text.length() <= 50, "mieści się w pasku")
	assert_eq(SupabaseClient.edge_error(HTTPRequest.RESULT_SUCCESS, 409, '{"error":"bot_locked","bots_beaten":1}'),
			AttackStart.BOT_LOCKED, "kod 409 dochodzi do gry")
	return true


## Klient: odmowa `bot_locked` daje w `attack_started` kod i postęp z serwera, inne odmowy pusty słownik.
func test_client_passes_server_progress() -> bool:
	SupabaseSession.clear(SESSION_PATH)
	var c := SupabaseClient.new()
	c.setup(SupabaseConfig.parse(JSON.stringify({
		"url": "https://abc.supabase.co", "publishable_key": "sb_publishable_test123",
	})), SESSION_PATH, SYNC_PATH)
	c.fake_transport = true
	c.handle_auth(SupabaseClient.Call.SIGNUP, HTTPRequest.RESULT_SUCCESS, 200, JSON.stringify({
		"access_token": "t1", "refresh_token": "r1", "expires_in": 3600,
		"user": {"id": UID, "is_anonymous": true},
	}))
	var got: Array = []
	c.attack_started.connect(func(start: Dictionary, error: String) -> void: got.append([start, error]))
	assert_true(c.start_bot_attack(5, [[U.AXE_WARRIOR, 10]]), "start idzie")
	c.handle_attack(SupabaseClient.AttackCall.START, HTTPRequest.RESULT_SUCCESS, 409,
			'{"error":"bot_locked","bots_beaten":2}')
	assert_eq(got[0][1], AttackStart.BOT_LOCKED, "kod odmowy")
	assert_eq(got[0][0], {"bots_beaten": 2}, "postęp z serwera")
	assert_true(c.start_bot_attack(5, [[U.AXE_WARRIOR, 10]]), "drugi start idzie")
	c.handle_attack(SupabaseClient.AttackCall.START, HTTPRequest.RESULT_SUCCESS, 409, '{"error":"bot_locked"}')
	assert_true((got[1][0] as Dictionary).is_empty(), "bez postępu: pusta odpowiedź")
	assert_true(c.start_bot_attack(5, [[U.AXE_WARRIOR, 10]]), "trzeci start idzie")
	c.handle_attack(SupabaseClient.AttackCall.START, HTTPRequest.RESULT_SUCCESS, 409,
			'{"error":"target_busy","bots_beaten":2}')
	assert_true((got[2][0] as Dictionary).is_empty(), "inna odmowa nie niesie postępu")
	SupabaseSession.clear(SESSION_PATH)
	SaveGame.delete(SYNC_PATH)
	c.free()
	return true


## Wyprawa odrzucona przez serwer kończy zgłoszenie jako porażka z kodem odmowy.
func test_pve_report_keeps_locked_error() -> bool:
	var p := PveReport.new()
	p.begin(5, [[U.AXE_WARRIOR, 10]])
	assert_true(p.on_started({"bots_beaten": 2}, AttackStart.BOT_LOCKED).is_empty(), "odmowa")
	assert_true(p.is_idle() and p.failed() and p.locked(), "zablokowany bot")
	assert_eq(p.failed_message(), AttackStart.error_message(AttackStart.BOT_LOCKED), "komunikat odmowy")
	p.begin(5, [[U.AXE_WARRIOR, 10]])
	assert_true(not p.locked(), "nowa wyprawa bez odmowy poprzedniej")
	assert_true(p.on_started({}, "army_over_limit").is_empty(), "inna odmowa")
	assert_true(p.failed() and not p.locked(), "inna odmowa to nie blokada")
	assert_eq(p.failed_message(), PveReport.FAILED_MESSAGE, "zwykły komunikat porażki")
	return true


## Cel Wyprawy po wyrównaniu licznika: zablokowany cel wraca na najwyższy odblokowany zamek.
func test_target_follows_server_progress() -> bool:
	assert_eq(BotRoster.unlocked_target(5, 2), 2, "cel powyżej postępu wraca na bieżący zamek")
	assert_eq(BotRoster.unlocked_target(1, 2), 1, "zdobyty zamek zostaje celem")
	assert_eq(BotRoster.unlocked_target(2, 2), 2, "bieżący zamek zostaje")
	assert_eq(BotRoster.unlocked_target(39, 0), 0, "nowy gracz: pierwszy zamek")
	assert_eq(BotRoster.unlocked_target(-3, 4), 4, "zły numer: bieżący zamek")
	assert_eq(BotRoster.unlocked_target(39, BotRoster.COUNT), 39, "wszystkie zdobyte")
	return true


## Karty Wyprawy pokazują tylko boty, które serwer przyjmie (bot_idx <= bots_beaten).
func test_target_cards_only_unlocked() -> bool:
	var none: Array[TargetSearch.Target] = []
	for beaten in [0, 1, 2, 5, BotRoster.COUNT, 99]:
		for t in TargetSearch.fill(none, beaten):
			assert_true(BotRoster.is_unlocked(t.bot_idx, beaten), "bot %d odblokowany przy %d" % [t.bot_idx, beaten])
	assert_eq(TargetSearch.fill(none, 0).size(), 1, "nowy gracz: jeden bot")
	assert_eq(TargetSearch.fill(none, 1).size(), 2, "jeden zdobyty: dwa boty")
	return true


## Migracja i Edge Function używają tych samych liczb i kodu co gra.
func test_matches_migration() -> bool:
	var sql := FileAccess.get_file_as_string(MIGRATION)
	assert_true(not sql.is_empty(), "migracja jest")
	assert_true(sql.contains("BotRoster.COUNT = %d" % BotRoster.COUNT), "liczba botów w opisie")
	assert_true(sql.contains("check (bots_beaten between 0 and %d)" % BotRoster.COUNT), "zakres licznika")
	assert_true(sql.contains("p.bots_beaten < %d" % BotRoster.COUNT), "licznik kończy się na liczbie botów")
	assert_true(sql.contains("least(w.last_won + 1, %d)" % BotRoster.COUNT), "import w zakresie")
	assert_true(sql.contains("if p_bot > v_beaten then") and sql.contains("'%s'" % AttackStart.BOT_LOCKED),
			"warunek BotRoster.is_unlocked i kod odmowy")
	var fn := FileAccess.get_file_as_string(EDGE)
	assert_true(fn.contains("%s: 409" % AttackStart.BOT_LOCKED), "Edge Function: 409 przy odmowie")
	assert_true(fn.contains("bots_beaten: me.bots_beaten"), "Edge Function: postęp w odpowiedzi")
	return true
