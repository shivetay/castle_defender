extends TestCase
## Ranking PvE (#242): zgłoszenie wyprawy na zamek-bota serwerowi (start, wynik, kolejność odpowiedzi,
## ponowienia), żądania klienta, trzeci widok panelu rankingu na 320 px i zgodność z migracją.

const MIGRATION := "res://supabase/migrations/20261121161439_pve_ranking.sql"
const VIEW := Vector2(320, 180)
const UID := "00000000-0000-0000-0000-0000000000b1"
const ATTACK_ID := "00000000-0000-0000-0000-0000000000c1"
const SESSION_PATH := "user://test_pve_ranking_session.json"
const SYNC_PATH := "user://test_pve_ranking_sync.json"
const U := UnitTypes.Unit


func _result(won: bool) -> BattleResult:
	var r := BattleResult.new()
	r.won = won
	r.percent = 100 if won else 10
	r.compute_loot(3, false)
	return r


func _start(bot: int) -> Dictionary:
	return {"id": ATTACK_ID, "map_seed": 7, "battle_seed": 9, "bot_idx": bot}


## Start przed końcem bitwy: wynik idzie od razu z id ataku, bez listy ruin, z ocalałymi każdego oddziału.
func test_finish_after_start() -> bool:
	var p := PveReport.new()
	p.begin(3, [[U.AXE_WARRIOR, 10], [U.AXE_WARRIOR, 10]])
	assert_eq(p.state, PveReport.State.STARTING, "czeka na start")
	assert_true(p.on_started(_start(3), "").is_empty(), "bez wyniku nic nie idzie")
	assert_eq(p.state, PveReport.State.STARTED, "atak zaczęty")
	var body := p.finish(_result(true), [10, 4] as Array[int])
	assert_eq(body["attack_id"], ATTACK_ID, "id ataku")
	assert_eq(body["survivors"], [10, 4], "ocaleli")
	assert_eq(body["result"], _result(true).to_server(), "wynik")
	assert_eq(body["loot"], _result(true).loot, "łup jak w grze")
	assert_true(not body.has("destroyed"), "bot nie ma ruin")
	assert_eq(p.state, PveReport.State.FINISHING, "wynik w drodze")
	assert_true(p.finish(_result(true), [10, 4] as Array[int]).is_empty(), "drugi koniec nic nie wysyła")
	assert_true(not p.on_finished(""), "przyjęty wynik kończy zgłoszenie")
	assert_true(p.is_idle() and not p.failed(), "bez porażki")
	return true


## Bitwa krótsza niż odpowiedź na start: wynik czeka na id ataku i idzie razem z odpowiedzią.
func test_finish_before_start() -> bool:
	var p := PveReport.new()
	p.begin(5, [[U.AXE_WARRIOR, 10]])
	assert_true(p.finish(_result(false), [0] as Array[int]).is_empty(), "bez id czeka")
	assert_true(p.queued, "wynik w kolejce")
	var body := p.on_started(_start(5), "")
	assert_eq(body["attack_id"], ATTACK_ID, "po starcie wynik z id")
	assert_eq(body["survivors"], [0], "ocaleli")
	assert_eq(p.state, PveReport.State.FINISHING, "wynik w drodze")
	return true


## Odmowa startu albo odpowiedź o innego bota: bez wyniku na serwer i ze znacznikiem porażki.
func test_start_rejected() -> bool:
	var p := PveReport.new()
	p.begin(3, [[U.AXE_WARRIOR, 10]])
	assert_true(p.on_started({}, "army_over_limit").is_empty(), "odmowa")
	assert_true(p.is_idle() and p.failed(), "porażka")
	assert_true(p.finish(_result(true), [10] as Array[int]).is_empty(), "wynik nie idzie")
	p.begin(3, [[U.AXE_WARRIOR, 10]])
	assert_true(not p.failed(), "nowa wyprawa bez porażki poprzedniej")
	p.finish(_result(true), [10] as Array[int])
	assert_true(p.on_started(_start(4), "").is_empty(), "odpowiedź o innego bota")
	assert_true(p.is_idle() and p.failed(), "porażka przy złym bocie")
	var q := PveReport.new()
	assert_true(q.on_started(_start(3), "").is_empty(), "odpowiedź bez zgłoszenia nic nie robi")
	assert_true(q.finish(_result(true), [10] as Array[int]).is_empty(), "koniec bez zgłoszenia nic nie robi")
	assert_true(not q.failed(), "bez zgłoszenia bez porażki")
	return true


## Błąd sieci przy wyniku: ta sama treść jeszcze RETRIES - 1 razy, potem porażka; odmowa od razu.
func test_finish_retries() -> bool:
	var p := PveReport.new()
	p.begin(2, [[U.AXE_WARRIOR, 10]])
	p.on_started(_start(2), "")
	var body := p.finish(_result(true), [10] as Array[int])
	var sent := 1
	while p.on_finished(SupabaseClient.NETWORK_ERROR):
		assert_eq(p.retry_body(), body, "ponowienie tej samej treści")
		sent += 1
	assert_eq(sent, AttackFinish.RETRIES, "tyle prób")
	assert_true(p.is_idle() and p.failed(), "po ostatniej próbie porażka")
	p.begin(2, [[U.AXE_WARRIOR, 10]])
	p.on_started(_start(2), "")
	p.finish(_result(true), [10] as Array[int])
	assert_true(not p.on_finished("loot_too_high"), "odmowa bez ponowienia")
	assert_true(p.failed(), "odmowa to porażka")
	assert_true(PixelFont.text_width(PveReport.FAILED_MESSAGE) <= Hud.MESSAGE_MAX_WIDTH, "komunikat w pasku")
	return true


## Zaległy wynik wyprawy z pliku (#425): ta sama treść idzie jeszcze raz, z ponowieniami jak po bitwie,
## a przyjęcie albo odmowa kończy zgłoszenie. Komunikaty mieszczą się w pasku.
func test_resume_from_file() -> bool:
	var p := PveReport.new()
	p.begin(2, [[U.AXE_WARRIOR, 10]])
	p.on_started(_start(2), "")
	var body := p.finish(_result(true), [10] as Array[int])
	var q := PveReport.new()
	var again := q.resume(body)
	assert_eq(again, body, "ta sama treść co po bitwie")
	assert_eq(q.state, PveReport.State.FINISHING, "wynik w drodze")
	assert_eq(q.attack_id, ATTACK_ID, "id ataku z treści")
	assert_true(q.on_finished(SupabaseClient.NETWORK_ERROR), "bez sieci ponowienie")
	assert_eq(q.retry_body(), body, "ponowienie tej samej treści")
	assert_true(not q.on_finished(""), "przyjęty wynik kończy zgłoszenie")
	assert_true(q.is_idle() and not q.failed(), "bez porażki")
	assert_true(PixelFont.text_width(PveReport.QUEUED_MESSAGE) <= Hud.MESSAGE_MAX_WIDTH, "komunikat kolejki w pasku")
	assert_true(PixelFont.text_width(PveReport.RESUMED_MESSAGE) <= Hud.MESSAGE_MAX_WIDTH, "komunikat wysłania w pasku")
	return true


## Klient: start na bota z armią, odpowiedź w `attack_started` z numerem bota; ranking PvE z rodzajem.
func test_client_requests() -> bool:
	SupabaseSession.clear(SESSION_PATH)
	var c := SupabaseClient.new()
	c.setup(SupabaseConfig.parse(JSON.stringify({
		"url": "https://abc.supabase.co", "publishable_key": "sb_publishable_test123",
	})), SESSION_PATH, SYNC_PATH)
	c.fake_transport = true
	assert_true(not c.start_bot_attack(3, [[0, 10]]), "bez sieci nic nie idzie")
	c.handle_auth(SupabaseClient.Call.SIGNUP, HTTPRequest.RESULT_SUCCESS, 200, JSON.stringify({
		"access_token": "t1", "refresh_token": "r1", "expires_in": 3600,
		"user": {"id": UID, "is_anonymous": true},
	}))
	var got: Array = []
	c.attack_started.connect(func(start: Dictionary, error: String) -> void: got.append([start, error]))
	c.sent_requests.clear()
	assert_true(c.start_bot_attack(3, [[0, 10]]), "start idzie")
	assert_true(not c.start_bot_attack(4, [[0, 10]]), "naraz jedno żądanie ataku")
	assert_eq(c.sent_requests[0]["path"], AttackStart.PATH, "ścieżka")
	assert_eq(c.sent_requests[0]["body"], {"bot_idx": 3, "army": [[0, 10]]}, "treść")
	c.handle_attack(SupabaseClient.AttackCall.START, HTTPRequest.RESULT_SUCCESS, 200, JSON.stringify(_start(3)))
	assert_eq((got[0][0] as Dictionary).get("bot_idx"), 3, "odpowiedź z numerem bota")
	assert_eq((got[0][0] as Dictionary).get("id"), ATTACK_ID, "odpowiedź z id ataku")
	c.sent_requests.clear()
	assert_true(c.load_ranking(RankingBoard.Kind.PVE), "ranking PvE idzie")
	assert_eq(c.sent_requests[0]["body"], {"kind": "pve"}, "rodzaj pve")
	SupabaseSession.clear(SESSION_PATH)
	SaveGame.delete(SYNC_PATH)
	c.free()
	return true


## Odpowiedź rankingu PvE: tylko na widok PvE; zachęta bez własnego wiersza mieści się w pasku.
func test_parse_and_summary() -> bool:
	var raw := {"kind": "pve", "rows": [{"place": 1, "nickname": "Ala", "castle_name": "Wawel",
		"ruler": Rulers.DEFAULT, "points": 95, "is_me": true}]}
	var rows := RankingBoard.parse_response(raw, RankingBoard.Kind.PVE)
	assert_eq(rows.size(), 1, "wiersz PvE")
	assert_eq(rows[0].points, 95, "punkty")
	assert_true(RankingBoard.parse_response(raw, RankingBoard.Kind.ATTACK).is_empty(), "odpowiedź PvE nie trafia do PvP")
	assert_eq(RankingBoard.summary(rows, RankingBoard.Kind.PVE), "Twoje miejsce: 1., punkty: 95", "miejsce")
	var hint := RankingBoard.summary([] as Array[RankingBoard.Row], RankingBoard.Kind.PVE)
	assert_eq(hint, "Zdobądź zamek-bota, żeby wejść do rankingu", "zachęta")
	assert_true(PixelFont.text_width(hint) <= Hud.MESSAGE_MAX_WIDTH, "zachęta w pasku")
	assert_eq(RankingBoard.request(RankingBoard.Kind.PVE), {"kind": "pve"}, "żądanie")
	return true


## Panel: trzy przyciski widoków w treści, z dala od Wróć; PvE z własnym tytułem i pustym tekstem.
func test_panel_has_pve_view() -> bool:
	var b := Hud.content_bounds(VIEW, Rect2())
	var close := RankingPanel.close_rect(VIEW, b.y)
	assert_eq(RankingPanel.TAB_LABELS.size(), RankingBoard.KIND_KEYS.size(), "przycisk na każdy ranking")
	for k in RankingPanel.TAB_LABELS.size():
		var r := RankingPanel.tab_rect(k, VIEW, b.x)
		assert_true(not r.intersects(close), "„%s” z dala od Wróć" % RankingPanel.TAB_LABELS[k])
		assert_true(r.position.x >= b.x and r.end.x <= b.y, "„%s” w treści" % RankingPanel.TAB_LABELS[k])
		assert_eq(RankingPanel.target_at(r.get_center(), VIEW, b.x, b.y), k, "dotyk „%s”" % RankingPanel.TAB_LABELS[k])
		assert_true(PixelFont.text_width(RankingPanel.TAB_LABELS[k]) <= Hud.BUTTON_SIZE.x - 2, "napis mieści się")
	assert_eq(RankingPanel.title_text(0, RankingBoard.Kind.PVE), "Ranking PvE: " + TargetSearch.age_label(0), "tytuł PvE")
	assert_eq(RankingPanel.title_text(0, RankingBoard.Kind.DEFENSE), "Ranking PvP: " + TargetSearch.age_label(0), "tytuł PvP")
	var title := RankingPanel.title_text(9, RankingBoard.Kind.PVE)
	assert_true(PixelFont.text_width(title) + 4 + PixelFont.text_width(RankingPanel.LOAD_TEXTS[3])
			<= int(b.y - b.x), "tytuł i stan w jednej linii")
	assert_true(PixelFont.text_width(RankingPanel.EMPTY_TEXTS[RankingBoard.Kind.PVE]) <= int(b.y - b.x), "pusty tekst")

	var p := RankingPanel.new()
	var asked: Array[int] = []
	p.kind_changed.connect(func(k: int) -> void: asked.append(k))
	p.open(0, true)
	p._activate(RankingPanel.Target.PVE)
	assert_eq(p.kind, RankingBoard.Kind.PVE, "widok PvE")
	assert_eq(asked, [RankingBoard.Kind.ATTACK, RankingBoard.Kind.PVE] as Array[int], "prośba o PvE")
	p.free()
	return true


## Liczby i warunki migracji: punkty tylko za wygraną z botem, raz na dobę za bota, 20 najlepszych.
func test_matches_migration() -> bool:
	var sql := FileAccess.get_file_as_string(MIGRATION)
	assert_true(not sql.is_empty(), "migracja jest")
	assert_true(sql.contains("PVE_BASE = 10, PVE_STEP = 5") and sql.contains("10 + 5 * greatest(bot_idx, 0)"),
			"punkty za bota w opisie i w funkcji")
	assert_true(sql.contains("PVE_COOLDOWN_HOURS = 24") and sql.contains("interval '24 hours'"), "raz na dobę")
	assert_true(sql.contains("RANKING_TOP = %d" % RankingBoard.TOP) and sql.contains("r.ord <= %d" % RankingBoard.TOP),
			"20 najlepszych")
	assert_true(sql.contains("new.bot_idx is not null") and sql.contains("new.result -> 'won' = 'true'::jsonb"),
			"tylko wygrana z botem")
	assert_true(sql.contains("p.age = v_age"), "pula tej samej epoki")
	var fn := FileAccess.get_file_as_string("res://supabase/functions/ranking/index.ts")
	for key: String in RankingBoard.KIND_KEYS:
		assert_true(fn.contains("\"%s\"" % key), "Edge Function zna rodzaj „%s”" % key)
	assert_true(fn.contains("pve_ranking"), "Edge Function woła pve_ranking")
	return true
