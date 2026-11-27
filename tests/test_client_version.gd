extends TestCase
## Wymuszenie aktualizacji (#336, ADR 0006): kod wersji, polityka z serwera i z pliku, miękki komunikat
## raz na 24 h, blokada po `update_required`, nagłówek wersji w zapytaniach, okno aktualizacji (bez sieci).

const PATH := "user://test_client_version_policy.json"
const SESSION_PATH := "user://test_client_version_session.json"
const SYNC_PATH := "user://test_client_version_sync.json"
const V := preload("res://scripts/net/client_version.gd")
const P := V.Policy


func _policy(min_code: int, recommended: int) -> ClientVersion.Policy:
	return P.parse(JSON.stringify({"min_code": min_code, "recommended_code": recommended,
			"store_url": "market://details?id=com.shivetay.dunhold"}))


func _client() -> SupabaseClient:
	SupabaseSession.clear(SESSION_PATH)
	var c := SupabaseClient.new()
	c.setup(SupabaseConfig.parse(JSON.stringify({
		"url": "https://abc.supabase.co", "publishable_key": "sb_publishable_test123",
	})), SESSION_PATH, SYNC_PATH)
	c.fake_transport = true
	return c


func test_code_of_version_string() -> bool:
	assert_eq(V.code_of("0.6.0"), 600, "0.6.0")
	assert_eq(V.code_of("1.2.3"), 10203, "1.2.3")
	assert_eq(V.code_of("12.99.99"), 129999, "duża wersja")
	assert_eq(V.code_of(""), 0, "pusty tekst")
	assert_eq(V.code_of("0.6"), 0, "za mało części")
	assert_eq(V.code_of("0.6.x"), 0, "nie liczba")
	assert_eq(V.code_of("0.100.0"), 0, "MINOR ponad 99")
	assert_eq(V.code_of("-1.0.0"), 0, "ujemna")
	return true


func test_current_code_from_project() -> bool:
	var version := str(ProjectSettings.get_setting("application/config/version", ""))
	assert_eq(V.current_code(), V.code_of(version), "kod z config/version")
	assert_true(V.current_code() > 0, "projekt ma poprawną wersję")
	return true


func test_parse_policy() -> bool:
	var p := P.parse('{"min_code": 600, "recommended_code": 700, "store_url": "https://play.google.com/x"}')
	assert_true(p != null, "poprawna polityka")
	assert_eq([p.min_code, p.recommended_code, p.store_url], [600, 700, "https://play.google.com/x"], "pola")
	assert_true(P.parse("") == null, "pusta odpowiedź")
	assert_true(P.parse("[1]") == null, "nie obiekt")
	assert_true(P.parse('{"min_code": "600"}') == null, "tekst zamiast liczby")
	assert_true(P.parse('{"min_code": -1, "recommended_code": 0}') == null, "ujemne minimum")
	var bad_url := P.parse('{"min_code": 0, "recommended_code": 0, "store_url": "javascript:alert(1)"}')
	assert_eq(bad_url.store_url, V.STORE_URL, "obcy schemat linku: domyślny sklep")
	var low := P.parse('{"min_code": 700, "recommended_code": 600}')
	assert_eq(low.recommended_code, 700, "rekomendacja nie niższa niż minimum")
	return true


func test_gate() -> bool:
	var p := _policy(600, 700)
	assert_eq(p.gate(599), V.Gate.HARD, "poniżej minimum: blokada")
	assert_eq(p.gate(600), V.Gate.SOFT, "minimum, ale poniżej rekomendacji: komunikat")
	assert_eq(p.gate(699), V.Gate.SOFT, "tuż pod rekomendacją")
	assert_eq(p.gate(700), V.Gate.OK, "aktualna")
	assert_eq(p.gate(10000), V.Gate.OK, "nowsza niż rekomendacja")
	assert_eq(_policy(0, 0).gate(600), V.Gate.OK, "startowe progi nikogo nie zatrzymują")
	return true


func test_soft_once_per_day_per_version() -> bool:
	var p := _policy(0, 700)
	assert_true(p.soft_due(600, 1000), "pierwszy raz")
	p.mark_soft_shown(1000)
	assert_true(not p.soft_due(600, 1000 + V.SOFT_INTERVAL_S - 1), "nie częściej niż raz na 24 h")
	assert_true(p.soft_due(600, 1000 + V.SOFT_INTERVAL_S), "po 24 h znowu")
	var newer := _policy(0, 800)
	newer.keep_soft_state(p)
	assert_true(newer.soft_due(600, 1001), "nowsza rekomendowana wersja: od razu")
	var same := _policy(0, 700)
	same.keep_soft_state(p)
	assert_true(not same.soft_due(600, 1001), "ta sama wersja z serwera pamięta komunikat")
	assert_true(not _policy(0, 700).soft_due(700, 1000), "aktualna wersja bez komunikatu")
	assert_true(not _policy(700, 700).soft_due(600, 1000), "przy blokadzie komunikat nie wychodzi")
	return true


func test_force_hard_after_server_rejection() -> bool:
	var p := _policy(0, 0)
	p.force_hard(600)
	assert_eq(p.gate(600), V.Gate.HARD, "serwer odrzucił wersję: blokada")
	assert_eq(p.gate(601), V.Gate.OK, "nowsza wersja przejdzie")
	var higher := _policy(900, 900)
	higher.force_hard(600)
	assert_eq(higher.min_code, 900, "wyższe minimum zostaje")
	return true


func test_needs_check_hourly() -> bool:
	var p := _policy(0, 0)
	p.fetched_s = 5000
	assert_true(not p.needs_check(5000 + V.CHECK_INTERVAL_S - 1), "przed upływem godziny")
	assert_true(p.needs_check(5000 + V.CHECK_INTERVAL_S), "po godzinie")
	assert_true(P.new().needs_check(0), "polityka nigdy nie pobrana")
	return true


func test_save_and_load() -> bool:
	SaveGame.delete(PATH)
	assert_true(P.load_from(PATH) == null, "bez pliku nic")
	var p := _policy(600, 700)
	p.fetched_s = 123
	p.mark_soft_shown(456)
	assert_eq(p.save(PATH), OK, "zapis")
	var back := P.load_from(PATH)
	assert_true(back != null, "odczyt")
	assert_eq([back.min_code, back.recommended_code, back.store_url, back.fetched_s, back.soft_code, back.soft_shown_s],
			[600, 700, "market://details?id=com.shivetay.dunhold", 123, 700, 456], "pola po odczycie")
	var f := FileAccess.open(PATH, FileAccess.WRITE)
	f.store_string("{zepsute")
	f.close()
	assert_true(P.load_from(PATH) == null, "zepsuty plik: brak polityki (gra działa)")
	SaveGame.delete(PATH)
	return true


func test_store_urls() -> bool:
	assert_eq(V.store_urls(_policy(0, 0)), [V.STORE_URL, V.STORE_WEB_URL] as Array[String], "sklep, potem strona")
	var web := P.parse('{"min_code": 0, "recommended_code": 0, "store_url": "https://example.org/dunhold"}')
	assert_eq(V.store_urls(web), ["https://example.org/dunhold", V.STORE_WEB_URL] as Array[String], "link z serwera")
	assert_eq(V.store_urls(null), [V.STORE_URL, V.STORE_WEB_URL] as Array[String], "bez polityki")
	return true


func test_headers_carry_client_version() -> bool:
	var h := SupabaseClient.headers_for("k", "")
	assert_true(h.has("%s: %d" % [V.HEADER, V.current_code()]), "nagłówek wersji")
	assert_true(h.has("apikey: k"), "klucz zostaje")
	return true


func test_check_version_request() -> bool:
	var c := _client()
	var got: Array = []
	c.version_policy_loaded.connect(func(p: ClientVersion.Policy, ok: bool) -> void: got.append([p, ok]))
	assert_true(c.check_version(), "sprawdzenie bez konta (klucz publishable)")
	assert_eq(c.sent_requests[-1]["path"], V.POLICY_PATH, "funkcja polityki")
	var sent := c.sent_requests.size()
	assert_true(c.check_version(), "sprawdzenie w toku: wynik przyjdzie z niego")
	assert_eq(c.sent_requests.size(), sent, "jedno żądanie naraz")
	c.handle_version(HTTPRequest.RESULT_SUCCESS, 200, '{"min_code": 600, "recommended_code": 700}')
	assert_eq(got.size(), 1, "sygnał")
	assert_true(got[0][1] as bool, "ok")
	assert_eq((got[0][0] as ClientVersion.Policy).min_code, 600, "polityka z serwera")
	assert_true(c.check_version(), "kolejne sprawdzenie po odpowiedzi")
	c.handle_version(HTTPRequest.RESULT_TIMEOUT, 0, "")
	assert_true(got[1][0] == null and not (got[1][1] as bool), "brak sieci: bez polityki")
	c.check_version()
	c.handle_version(HTTPRequest.RESULT_SUCCESS, 200, "[]")
	assert_true(not (got[2][1] as bool), "zła odpowiedź: bez polityki")
	SupabaseSession.clear(SESSION_PATH)
	c.free()
	return true


func test_update_required_status_blocks_once() -> bool:
	var c := _client()
	var count := [0]
	c.update_required.connect(func() -> void: count[0] += 1)
	c.note_status(200)
	c.note_status(409)
	assert_eq(count[0], 0, "inne kody nic nie robią")
	c.note_status(V.HTTP_UPDATE_REQUIRED)
	c.note_status(V.HTTP_UPDATE_REQUIRED)
	assert_eq(count[0], 1, "sygnał raz")
	assert_true(c.update_blocked, "klient wstrzymany")
	c.clear_update_block()
	assert_true(not c.update_blocked, "po nowym sprawdzeniu wraca")
	c.note_status(V.HTTP_UPDATE_REQUIRED)
	assert_eq(count[0], 2, "kolejna odmowa znowu blokuje")
	SupabaseSession.clear(SESSION_PATH)
	c.free()
	return true


func test_blocked_client_stops_castle_push() -> bool:
	var c := _client()
	c.handle_auth(SupabaseClient.Call.SIGNUP, HTTPRequest.RESULT_SUCCESS, 200, JSON.stringify({
		"access_token": "t1", "refresh_token": "r1", "expires_in": 3600,
		"user": {"id": "00000000-0000-0000-0000-0000000336a1", "is_anonymous": true},
	}))
	c.note_status(V.HTTP_UPDATE_REQUIRED)
	var before := c.sent_requests.size()
	var save := SaveGame.to_dict(4242, BuildGrid.new(TerrainMap.generate(4242)), Economy.new(0), BuildQueue.new())
	c.sync_castle(4242, SaveGame.FORMAT_VERSION, save, {}, "Bolko", true)
	assert_eq(c.sent_requests.size(), before, "zablokowany klient nie wysyła zamku")
	SupabaseSession.clear(SESSION_PATH)
	SaveGame.delete(SYNC_PATH)
	c.free()
	return true


func test_update_panel_buttons() -> bool:
	var view := Vector2(320, 180)
	for mode in [UpdatePanel.Mode.SOFT, UpdatePanel.Mode.HARD]:
		var rects := UpdatePanel.button_rects(view, mode)
		assert_eq(rects.size(), 2, "dwa przyciski")
		for r in rects:
			assert_true(r.size.x >= 12 and r.size.y >= 12, "cel dotyku co najmniej 12×12")
			assert_true(r.position.x >= 16 and r.end.x <= view.x - 16, "z dala od krawędzi")
			assert_true(r.position == r.position.floor(), "całe piksele")
		assert_eq(UpdatePanel.target_at(rects[0].get_center(), view, mode), UpdatePanel.Target.UPDATE, "Aktualizuj")
	var soft := UpdatePanel.button_rects(view, UpdatePanel.Mode.SOFT)
	assert_eq(UpdatePanel.target_at(soft[1].get_center(), view, UpdatePanel.Mode.SOFT), UpdatePanel.Target.LATER,
			"Później")
	var hard := UpdatePanel.button_rects(view, UpdatePanel.Mode.HARD)
	assert_eq(UpdatePanel.target_at(hard[1].get_center(), view, UpdatePanel.Mode.HARD), UpdatePanel.Target.RETRY,
			"Sprawdź ponownie")
	assert_eq(UpdatePanel.target_at(Vector2(2, 2), view, UpdatePanel.Mode.HARD), UpdatePanel.Target.NONE, "obok")
	for mode in [UpdatePanel.Mode.SOFT, UpdatePanel.Mode.HARD]:
		for line in UpdatePanel.lines_for(mode):
			assert_true(PixelFont.text_width(line) <= 300, "tekst mieści się w 320 px: " + line)
	return true


func test_update_panel_signals() -> bool:
	var panel := UpdatePanel.new()
	var got: Array[String] = []
	panel.update_pressed.connect(func() -> void: got.append("update"))
	panel.later_pressed.connect(func() -> void: got.append("later"))
	panel.retry_pressed.connect(func() -> void: got.append("retry"))
	panel.open(UpdatePanel.Mode.SOFT)
	assert_true(panel.visible, "komunikat widoczny")
	panel.activate(UpdatePanel.Target.LATER)
	assert_true(not panel.visible, "Później zamyka komunikat")
	panel.open(UpdatePanel.Mode.HARD)
	panel.activate(UpdatePanel.Target.UPDATE)
	assert_true(panel.visible, "blokada zostaje po Aktualizuj")
	panel.activate(UpdatePanel.Target.LATER)
	assert_true(panel.visible, "blokady nie da się odłożyć")
	panel.activate(UpdatePanel.Target.RETRY)
	assert_eq(got, ["later", "update", "retry"] as Array[String], "sygnały")
	panel.open(UpdatePanel.Mode.SOFT)
	panel.activate(UpdatePanel.Target.UPDATE)
	assert_true(not panel.visible, "Aktualizuj zamyka komunikat")
	panel.activate(UpdatePanel.Target.RETRY)
	assert_eq(got.size(), 4, "schowane okno nie reaguje")
	panel.free()
	return true


func test_update_required_finish_note_keeps_result() -> bool:
	var note := AttackFinish.error_note(V.UPDATE_REQUIRED_ERROR)
	assert_eq(note, "Zaktualizuj grę: wynik wyślę później", "wynik czeka na aktualizację, nie przepada")
	assert_true(PixelFont.text_width(note) <= 300, "komunikat mieści się w 320 px")
	return true
