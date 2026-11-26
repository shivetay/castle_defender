extends TestCase
## Zasłona ładowania przy synchronizacji z serwerem (#316): kiedy się pokazuje i znika (SyncCurtain,
## bez renderowania), teksty i sygnał `castle_checked` klienta (bez sieci, z `fake_transport`).

const SESSION_PATH := "user://test_sync_loader_session.json"
const SYNC_PATH := "user://test_sync_loader_state.json"
const UID := "00000000-0000-0000-0000-00000000000c"


func _client(fresh: bool) -> SupabaseClient:
	SupabaseSession.clear(SESSION_PATH)
	SaveGame.delete(SYNC_PATH)
	var c := SupabaseClient.new()
	c.setup(SupabaseConfig.parse(JSON.stringify({
		"url": "https://abc.supabase.co", "publishable_key": "sb_publishable_test123",
	})), SESSION_PATH, SYNC_PATH)
	c.fake_transport = true
	c.local_fresh = fresh
	c.handle_auth(SupabaseClient.Call.SIGNUP, HTTPRequest.RESULT_SUCCESS, 200, JSON.stringify({
		"access_token": "t1", "refresh_token": "r1", "expires_in": 3600,
		"user": {"id": UID, "is_anonymous": true},
	}))
	return c


func _done(c: SupabaseClient) -> void:
	SupabaseSession.clear(SESSION_PATH)
	SaveGame.delete(SYNC_PATH)
	c.free()


func _row(revision: int) -> Dictionary:
	var save := SaveGame.to_dict(4242, BuildGrid.new(TerrainMap.generate(4242)), Economy.new(0), BuildQueue.new())
	return {"map_seed": 4242, "save_version": SaveGame.FORMAT_VERSION, "revision": revision,
			"data": CastleSync.castle_data(save, null)}


func _reply_last(c: SupabaseClient, result: int, code: int, body: String) -> void:
	var last: Dictionary = c.sent_requests[c.sent_requests.size() - 1]
	c.handle_castle_rest(int(last["call"]), result, code, body)


func test_waits_only_when_castle_may_come_back() -> bool:
	assert_true(SyncCurtain.waits_at_start(true, true, false), "start bez zapisu czeka na serwer")
	assert_true(SyncCurtain.waits_at_start(true, false, true), "po nieudanym przywróceniu też")
	assert_true(not SyncCurtain.waits_at_start(true, false, false), "zwykły start rusza od razu")
	assert_true(not SyncCurtain.waits_at_start(false, true, true), "bez serwera nie ma na co czekać")
	return true


func test_startup_hides_after_answer_but_not_before_min_time() -> bool:
	var s := SyncCurtain.new()
	assert_true(not s.is_visible(), "na początku schowana")
	s.start_waiting()
	assert_true(s.is_visible(), "czeka na serwer")
	assert_eq(s.mode, SyncCurtain.Mode.STARTUP, "tryb startu")
	s.on_net_state(SupabaseClient.State.CONNECTING)
	s.on_net_state(SupabaseClient.State.ONLINE)
	s.advance(0.3)
	assert_true(s.is_visible(), "połączenie to jeszcze nie odpowiedź o zamku")
	s.on_castle_checked()
	assert_true(s.is_visible(), "stoi co najmniej MIN_VISIBLE_S, żeby sama nie mignęła")
	s.advance(SyncCurtain.MIN_VISIBLE_S)
	assert_true(not s.is_visible(), "po odpowiedzi i minimalnym czasie znika")
	return true


func test_startup_hides_when_offline_or_disabled() -> bool:
	for st: int in [SupabaseClient.State.OFFLINE, SupabaseClient.State.DISABLED]:
		var s := SyncCurtain.new()
		s.start_waiting()
		s.advance(1.0)
		s.on_net_state(st)
		s.advance(0.0)
		assert_true(not s.is_visible(), "bez sieci gra rusza od razu (stan %d)" % st)
	return true


func test_startup_gives_up_after_max_wait() -> bool:
	var s := SyncCurtain.new()
	s.start_waiting()
	s.advance(SyncCurtain.STARTUP_MAX_S - 0.1)
	assert_true(s.is_visible(), "jeszcze czeka")
	s.advance(0.2)
	assert_true(not s.is_visible(), "po limicie gra rusza z zamkiem z telefonu")
	return true


func test_restore_stays_until_scene_reload_and_ignores_startup_events() -> bool:
	var s := SyncCurtain.new()
	s.start_waiting()
	s.start_restore()
	assert_eq(s.mode, SyncCurtain.Mode.RESTORE, "przywracanie")
	s.on_castle_checked()
	s.on_net_state(SupabaseClient.State.OFFLINE)
	s.advance(SyncCurtain.STARTUP_MAX_S * 2.0)
	assert_true(s.is_visible(), "zasłona stoi aż do przeładowania sceny")
	# nowa scena po przeładowaniu: zasłona od razu, znika po minimalnym czasie
	var next := SyncCurtain.new()
	next.start_restore()
	next.finish()
	assert_true(next.is_visible(), "pierwsza klatka nowej sceny pod zasłoną")
	next.advance(SyncCurtain.MIN_VISIBLE_S)
	assert_true(not next.is_visible(), "potem znika")
	return true


func test_texts_rotate_deterministically_and_fit() -> bool:
	var s := SyncCurtain.new()
	s.start_waiting()
	assert_eq(s.title(), SyncCurtain.STARTUP_TITLE, "bez kropek na starcie")
	assert_eq(s.line(), SyncCurtain.LINES[0], "pierwszy tekst")
	s.advance(SyncCurtain.DOT_S * 2.0)
	assert_eq(s.title(), SyncCurtain.STARTUP_TITLE + "..", "kropki rosną")
	s.advance(SyncCurtain.LINE_S)
	assert_eq(s.line(), SyncCurtain.LINES[1], "kolejny tekst")
	s.advance(SyncCurtain.LINE_S * float(SyncCurtain.LINES.size() - 1))
	assert_eq(s.line(), SyncCurtain.LINES[0], "teksty idą w kółko")
	s.start_restore()
	assert_true(s.title().begins_with(SyncCurtain.RESTORE_TITLE), "inny tytuł przy przywracaniu")
	assert_true(SyncCurtain.LINES.size() >= 5, "kilka tekstów")
	for text: String in SyncCurtain.LINES + [SyncCurtain.STARTUP_TITLE + "...", SyncCurtain.RESTORE_TITLE + "..."]:
		assert_true(PixelFont.text_width(text) <= 300, "mieści się w 320 px: %s" % text)
		assert_true(not PixelFont._normalize(text).contains("?"), "font zna wszystkie znaki: %s" % text)
	return true


func test_client_reports_checked_castle() -> bool:
	# serwer nie ma zamku (pierwszy start bez tożsamości): odczyt skończony, bez przywracania
	var c := _client(true)
	var checked: Array[int] = [0]
	c.castle_checked.connect(func() -> void: checked[0] += 1)
	c.sync_castle(1337, SaveGame.FORMAT_VERSION, {"n": 1}, {}, "", false)
	assert_eq(checked[0], 0, "przed odpowiedzią nic")
	_reply_last(c, HTTPRequest.RESULT_SUCCESS, 200, "[]")
	assert_eq(checked[0], 1, "odpowiedź o zamku")
	_done(c)
	# serwer ma zamek: przychodzi przywracanie, a nie `castle_checked`
	var p := _client(true)
	var checked_p: Array[int] = [0]
	var restored: Array[int] = [0]
	p.castle_checked.connect(func() -> void: checked_p[0] += 1)
	p.castle_restored.connect(func(_s: Dictionary, _pr: Dictionary) -> void: restored[0] += 1)
	p.sync_castle(1337, SaveGame.FORMAT_VERSION, {"n": 1}, {}, "", false)
	_reply_last(p, HTTPRequest.RESULT_SUCCESS, 200, JSON.stringify([_row(5)]))
	assert_eq(restored[0], 1, "zamek wraca")
	assert_eq(checked_p[0], 0, "zasłona czeka na przeładowanie")
	_done(p)
	# błąd sieci przy odczycie: gra nie czeka na ponowienie
	var e := _client(true)
	var checked_e: Array[int] = [0]
	e.castle_checked.connect(func() -> void: checked_e[0] += 1)
	e.sync_castle(1337, SaveGame.FORMAT_VERSION, {"n": 1}, {}, "", false)
	_reply_last(e, HTTPRequest.RESULT_CANT_CONNECT, 0, "")
	assert_eq(checked_e[0], 1, "błąd odczytu też kończy czekanie")
	_done(e)
	return true


## Nieudane przywrócenie (main._restore_failed): gra zostaje przy zamku z telefonu, zasłona nie czeka
## do STARTUP_MAX_S.
func test_failed_restore_ends_startup_wait() -> bool:
	var s := SyncCurtain.new()
	s.start_waiting()
	s.advance(0.5)
	s.finish()
	s.advance(SyncCurtain.MIN_VISIBLE_S)
	assert_true(not s.is_visible(), "zasłona schodzi po minimalnym czasie")
	return true
