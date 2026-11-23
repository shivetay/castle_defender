extends TestCase
## Fale PvE na serwerze (#288): zgłoszenie fali (start, wynik, kolejność odpowiedzi, ponowienia), żądania
## klienta i odpowiedzi `pve_wave`, komunikaty fali bez nagrody na 320 px i zgodność z migracją.

const MIGRATION := "res://supabase/migrations/20261125090000_pve_wave_results.sql"
const FUNCTION := "res://supabase/functions/pve_wave/index.ts"
const MAIN := preload("res://scripts/main.gd")
const UID := "00000000-0000-0000-0000-0000000288c1"
const WAVE_ID := "00000000-0000-0000-0000-0000000288d1"
const SESSION_PATH := "user://test_pve_wave_session.json"
const SYNC_PATH := "user://test_pve_wave_sync.json"


static func _list(a: Array) -> String:
	var parts: Array[String] = []
	for x: Variant in a:
		parts.append(_list(x as Array) if x is Array else str(x))
	return "[" + ", ".join(parts) + "]"


func _start(wave: int) -> Dictionary:
	return {"id": WAVE_ID, "wave": wave}


## Start przed końcem bitwy: wynik idzie od razu z id fali.
func test_finish_after_start() -> bool:
	var w := WaveReport.new()
	assert_true(not w.online(), "bez zgłoszenia fala jest poza serwerem")
	w.begin(2)
	assert_eq(w.state, WaveReport.State.STARTING, "czeka na start")
	assert_true(w.online(), "start w drodze: nagroda może przyjść")
	assert_true(w.on_started(_start(2), "").is_empty(), "bez wyniku nic nie idzie")
	assert_eq(w.state, WaveReport.State.STARTED, "fala zaczęta")
	assert_eq(w.finish(true), {"wave_id": WAVE_ID, "won": true}, "wynik z id fali")
	assert_eq(w.state, WaveReport.State.FINISHING, "wynik w drodze")
	assert_true(w.finish(true).is_empty(), "drugi koniec nic nie wysyła")
	assert_true(not w.on_finished(""), "przyjęty wynik kończy zgłoszenie")
	assert_true(w.is_idle() and not w.failed(), "bez porażki")
	return true


## Bitwa krótsza niż odpowiedź na start: wynik czeka na id fali i idzie razem z odpowiedzią.
func test_finish_before_start() -> bool:
	var w := WaveReport.new()
	w.begin(0)
	assert_true(w.finish(false).is_empty(), "bez id czeka")
	assert_true(w.queued, "wynik w kolejce")
	assert_eq(w.on_started(_start(0), ""), {"wave_id": WAVE_ID, "won": false}, "po starcie wynik z id")
	assert_eq(w.state, WaveReport.State.FINISHING, "wynik w drodze")
	return true


## Odmowa startu albo odpowiedź o inną falę: bez wyniku na serwer i ze znacznikiem porażki.
func test_start_rejected() -> bool:
	var w := WaveReport.new()
	w.begin(1)
	assert_true(w.on_started({}, "wave_done").is_empty(), "odmowa")
	assert_true(w.is_idle() and w.failed() and not w.online(), "porażka, fala poza serwerem")
	assert_true(w.finish(true).is_empty(), "wynik nie idzie")
	w.begin(1)
	assert_true(not w.failed(), "nowa fala bez porażki poprzedniej")
	w.finish(true)
	assert_true(w.on_started(_start(3), "").is_empty(), "odpowiedź o inną falę")
	assert_true(w.is_idle() and w.failed(), "porażka przy złej fali")
	var q := WaveReport.new()
	assert_true(q.on_started(_start(1), "").is_empty(), "odpowiedź bez zgłoszenia nic nie robi")
	assert_true(q.finish(true).is_empty(), "koniec bez zgłoszenia nic nie robi")
	assert_true(not q.failed(), "bez zgłoszenia bez porażki")
	return true


## Błąd sieci przy wyniku: ta sama treść jeszcze RETRIES - 1 razy, potem porażka; odmowa od razu.
func test_finish_retries() -> bool:
	var w := WaveReport.new()
	w.begin(4)
	w.on_started(_start(4), "")
	var body := w.finish(true)
	var sent := 1
	while w.on_finished(SupabaseClient.NETWORK_ERROR):
		assert_true(not w.is_idle(), "między próbami zgłoszenie trwa (nowa fala go nie kasuje, review #290)")
		assert_eq(w.retry_body(), body, "ponowienie tej samej treści")
		sent += 1
	assert_eq(sent, AttackFinish.RETRIES, "tyle prób")
	assert_true(w.is_idle() and w.failed(), "po ostatniej próbie porażka")
	w.begin(4)
	w.on_started(_start(4), "")
	w.finish(true)
	assert_true(not w.on_finished("wave_too_fast"), "odmowa bez ponowienia")
	assert_true(w.failed(), "odmowa to porażka")
	return true


## Odpowiedzi `pve_wave`: start z id i numerem fali, koniec z wynikiem i nagrodą; reszta odrzucona.
func test_parse_responses() -> bool:
	assert_eq(WaveReport.parse_start({"id": WAVE_ID, "wave": 3.0}), _start(3), "start")
	assert_true(WaveReport.parse_start({"wave": 3}).is_empty(), "start bez id")
	assert_true(WaveReport.parse_start({"id": WAVE_ID}).is_empty(), "start bez fali")
	assert_true(WaveReport.parse_start([]).is_empty(), "start nie jest obiektem")
	var won := WaveReport.parse_finish({"status": "won", "wave": 0, "reward": [100, 50, 100, 10]})
	assert_eq(won["status"], "won", "wygrana")
	assert_eq(won["reward"], [100, 50, 100, 10] as Array[int], "nagroda")
	assert_eq(WaveReport.parse_finish({"status": "lost", "reward": [0, 0, 0, 0]})["reward"], [0, 0, 0, 0] as Array[int],
			"przegrana bez nagrody")
	assert_true(WaveReport.parse_finish({"status": "abandoned", "reward": null}).is_empty(), "porzucona")
	assert_true(WaveReport.parse_finish({"status": "won", "reward": [1, 2, 3]}).is_empty(), "zła nagroda")
	assert_true(WaveReport.parse_finish({"status": "won", "reward": [1, 2, "x", 4]}).is_empty(), "nagroda nie z liczb")
	return true


## Klient: start i koniec fali idą do `pve_wave` kanałem ataków; odpowiedzi w `wave_started` i `wave_finished`.
func test_client_requests() -> bool:
	SupabaseSession.clear(SESSION_PATH)
	var c := SupabaseClient.new()
	c.setup(SupabaseConfig.parse(JSON.stringify({
		"url": "https://abc.supabase.co", "publishable_key": "sb_publishable_test123",
	})), SESSION_PATH, SYNC_PATH)
	c.fake_transport = true
	assert_true(not c.start_wave(0), "bez sieci nic nie idzie")
	c.handle_auth(SupabaseClient.Call.SIGNUP, HTTPRequest.RESULT_SUCCESS, 200, JSON.stringify({
		"access_token": "t1", "refresh_token": "r1", "expires_in": 3600,
		"user": {"id": UID, "is_anonymous": true},
	}))
	var started: Array = []
	var finished: Array = []
	c.wave_started.connect(func(start: Dictionary, error: String) -> void: started.append([start, error]))
	c.wave_finished.connect(func(reward: Array[int], error: String) -> void: finished.append([reward, error]))
	c.sent_requests.clear()
	assert_true(c.start_wave(1), "start idzie")
	assert_true(not c.start_bot_attack(3, [[0, 10]]), "naraz jedno żądanie kanałem ataków")
	assert_eq(c.sent_requests[0]["path"], WaveReport.PATH, "ścieżka")
	assert_eq(c.sent_requests[0]["body"], {"wave": 1}, "treść startu")
	c.handle_attack(SupabaseClient.AttackCall.WAVE_START, HTTPRequest.RESULT_SUCCESS, 200, JSON.stringify(_start(1)))
	assert_eq(started[0][0], _start(1), "odpowiedź na start")
	assert_eq(started[0][1], "", "bez błędu")
	c.handle_attack(SupabaseClient.AttackCall.WAVE_START, HTTPRequest.RESULT_SUCCESS, 200, "{}")
	assert_eq(started[1][1], SupabaseClient.REJECTED_ERROR, "niepełny start to odmowa")
	c.sent_requests.clear()
	assert_true(c.finish_wave(WaveReport.finish_request(WAVE_ID, true)), "wynik idzie")
	assert_eq(c.sent_requests[0]["body"], {"wave_id": WAVE_ID, "won": true}, "treść wyniku")
	c.handle_attack(SupabaseClient.AttackCall.WAVE_FINISH, HTTPRequest.RESULT_SUCCESS, 200,
			JSON.stringify({"status": "won", "wave": 1, "reward": [150, 100, 150, 15]}))
	assert_eq(finished[0][0], [150, 100, 150, 15] as Array[int], "nagroda z serwera")
	c.handle_attack(SupabaseClient.AttackCall.WAVE_FINISH, HTTPRequest.RESULT_SUCCESS, 410,
			JSON.stringify({"error": "wave_expired"}))
	assert_eq(finished[1][1], "wave_expired", "fala po terminie")
	c.handle_attack(SupabaseClient.AttackCall.WAVE_FINISH, HTTPRequest.RESULT_SUCCESS, 200, "{}")
	assert_eq(finished[2][1], SupabaseClient.NETWORK_ERROR, "niepełny wynik ponawia")
	SupabaseSession.clear(SESSION_PATH)
	SaveGame.delete(SYNC_PATH)
	c.free()
	return true


## Fala poza serwerem: komunikat bez nagrody, także na koniec samouczka; wszystkie mieszczą się w pasku.
func test_messages_without_reward_fit() -> bool:
	var none: Array[int] = []
	assert_eq(MAIN.wave_end_message(0, true, none, 0), "Fala 1 obroniona poza serwerem: bez nagrody", "bez strat")
	assert_true(MAIN.wave_end_message(4, true, none, 30).contains("Bez nagrody"), "z poległymi")
	assert_true(not TutorialGoals.done_message(none, 0).contains("+"), "koniec samouczka bez nagrody")
	for t: String in [MAIN.wave_end_message(4, true, none, 30), MAIN.wave_end_message(4, true, none, 0),
			TutorialGoals.done_message(none, 30), TutorialGoals.done_message(none, 0), MAIN.WAVE_FAILED_MESSAGE,
			MAIN.WAVE_REWARD_PREFIX + "+500 Dr +300 Ka +500 Żyw +50 Zł"]:
		assert_true(PixelFont.text_width(t) <= Hud.MESSAGE_MAX_WIDTH, "„%s” mieści się w pasku" % t)
	assert_true(MAIN.loot_message([100, 50, 0, 10] as Array[int]).begins_with(MAIN.LOOT_PREFIX), "łup ma swój prefiks")
	return true


## Liczby migracji i Edge Function jak w grze: liczba fal, nagrody, limity w komentarzu i w kodzie.
func test_matches_migration() -> bool:
	var sql := FileAccess.get_file_as_string(MIGRATION)
	assert_true(not sql.is_empty(), "migracja jest")
	var rewards := _list(PveWaves.REWARDS)
	assert_true(sql.contains("PveWaves.REWARDS = " + rewards), "nagrody w komentarzu")
	assert_true(sql.contains("'" + rewards + "'::jsonb"), "nagrody w funkcji")
	assert_true(sql.contains("PveWaves.COUNT = %d" % PveWaves.COUNT), "liczba fal w komentarzu")
	assert_true(sql.contains("check (wave between 0 and %d)" % (PveWaves.COUNT - 1))
			and sql.contains("p_wave > %d" % (PveWaves.COUNT - 1)), "zakres fal w tabeli i w starcie")
	assert_true(sql.contains("WAVE_START_LIMIT = 10") and sql.contains(">= 10 then"), "limit startów")
	assert_true(sql.contains("WAVE_DEADLINE_S = 600") and sql.contains("interval '600 seconds'"), "termin wyniku")
	assert_true(sql.contains("WAVE_MIN_S = 5") and sql.contains("interval '5 seconds'"), "najkrótsza wygrana")
	assert_true(sql.contains("enable row level security"), "RLS na przebiegach fal")
	assert_true(not sql.contains("private.pve_reward(v_rewarded"), "bilans nie liczy nagród z licznika fal")
	var fn := FileAccess.get_file_as_string(FUNCTION)
	assert_true(fn.contains("const WAVES = %d;" % PveWaves.COUNT), "Edge Function zna liczbę fal")
	assert_true(fn.contains("begin_wave") and fn.contains("end_wave"), "Edge Function woła funkcje fal")
	return true
