extends TestCase
## Historia obron (#328): odpowiedź Edge Function `defense_history` (nick i siła armii napastnika,
## znacznik powtórki), nowe ataki od ostatniego obejrzenia (znacznik w profilu), tekst powiadomienia,
## wiersze listy z tarczami i strony, kropka nad Obroną w HUD i okienko z Historia / OK.

const U := UnitTypes.Unit
const ATTACK := "00000000-0000-0000-0000-0000000328aa"
const ATTACK2 := "00000000-0000-0000-0000-0000000328ab"
const UID := "00000000-0000-0000-0000-0000000328cc"
const PROFILE_PATH := "user://test_defense_history_profile.json"
const SESSION_PATH := "user://test_defense_history_session.json"
const SYNC_PATH := "user://test_defense_history_sync.json"
const MIGRATION := "res://supabase/migrations/20261126180000_defense_history.sql"
const FUNCTION := "res://supabase/functions/defense_history/index.ts"
const STRENGTH_MIGRATION := "res://supabase/migrations/20261126200000_target_strength.sql"


static func _row(id: String, won: bool, at: String, extra: Dictionary = {}) -> Dictionary:
	var d := {"id": id, "finished_at": at, "has_replay": true, "nickname": "Mieszko",
		"army": [[U.AXE_WARRIOR, 10], [U.RIDER, 5]], "defense": 237,
		"result": {"won": won, "percent": 40, "stars": [true, false, false]}}
	d.merge(extra, true)
	return d


static func _wire(v: Variant) -> Variant:
	return JSON.parse_string(JSON.stringify(v))


static func _report(at_s: int, won: bool) -> DefenseLog.Report:
	var r := DefenseLog.Report.new()
	r.id = ATTACK
	r.at_s = at_s
	r.result = BattleResult.new()
	r.result.won = won
	return r


func test_parse_history() -> bool:
	var rows := DefenseLog.parse_history(_wire({"rows": [
		_row(ATTACK, true, "2026-11-21T10:15:00+01:00"),
		_row(ATTACK2, false, "2026-11-21T08:00:00Z", {"has_replay": false, "nickname": "", "army": "zła", "defense": null}),
		_row("zły", true, "2026-11-21T08:00:00Z"),
		_row(ATTACK, true, "zły czas"),
		_row(ATTACK, true, "2026-11-21T08:00:00Z", {"result": {"won": true}}),
		"śmieć",
	]}))
	assert_eq(rows.size(), 2, "złe wiersze pominięte")
	assert_eq(rows[0].nickname, "Mieszko", "nick napastnika")
	var power := 10 * Strength.unit_power(U.AXE_WARRIOR) + 5 * Strength.unit_power(U.RIDER)
	assert_true(power > 0, "armia ma siłę")
	assert_eq(rows[0].army_power, power, "siła armii jak na ekranie Wojsko (Strength.unit_power)")
	assert_true(rows[0].has_replay, "ma powtórkę")
	assert_eq(rows[0].at_s, Time.get_unix_time_from_datetime_string("2026-11-21T09:15:00"), "czas w UTC")
	assert_eq(rows[1].nickname, DefenseLog.UNKNOWN_NICK, "brak nicku to „?”")
	assert_eq(rows[1].army_power, 0, "zła armia to siła 0")
	assert_eq(rows[0].defense, 200, "siła obrony napastnika: granica przedziału")
	assert_eq(rows[1].defense, -1, "bez zamku napastnika: „?”")
	assert_true(not rows[1].has_replay, "bez powtórki")
	assert_eq(DefenseLog.parse_history(null), [] as Array[DefenseLog.Report], "zła odpowiedź")
	assert_eq(DefenseLog.parse_history({"rows": "x"}), [] as Array[DefenseLog.Report], "złe wiersze")
	# nick od innego gracza jest niezaufany: znaki spoza fontu odpadają, długość przycięta
	var odd := DefenseLog.parse_history(_wire({"rows": [_row(ATTACK, true, "2026-11-21T08:00:00Z",
			{"nickname": "<b>Ala</b>\nxxxxxxxxxxxxxxxxxxxxxx"})]}))
	assert_true(odd[0].nickname.length() <= PlayerProfile.NAME_MAX, "nick przycięty")
	assert_true(not odd[0].nickname.contains("\n"), "bez znaków sterujących")
	var many: Array = []
	for i in 15:
		many.append(_row(ATTACK, true, "2026-11-21T08:00:00Z"))
	assert_eq(DefenseLog.parse_history(_wire({"rows": many})).size(), DefenseLog.REPORTS_LIMIT, "najwyżej 10")
	return true


func test_new_since_and_notice() -> bool:
	var list: Array[DefenseLog.Report] = [_report(300, true), _report(200, false), _report(100, false)]
	assert_eq(DefenseLog.new_since(list, 0).size(), 3, "bez znacznika wszystkie są nowe")
	assert_eq(DefenseLog.new_since(list, 200).size(), 1, "tylko po ostatnio obejrzanej")
	assert_eq(DefenseLog.new_since(list, 300).size(), 0, "wszystko obejrzane")
	assert_eq(DefenseLog.newest_s(list), 300, "najnowsza obrona")
	assert_eq(DefenseLog.newest_s([] as Array[DefenseLog.Report]), 0, "pusta lista")
	assert_eq(DefenseNotice.text(DefenseLog.new_since(list, 0)),
			"Zaatakowano Cię 3× od ostatniej wizyty (2 odparte, 1 zdobyty)", "tekst powiadomienia")
	assert_eq(DefenseNotice.text(DefenseLog.new_since(list, 200)),
			"Zaatakowano Cię 1× od ostatniej wizyty (0 odpartych, 1 zdobyty)", "jeden atak")
	return true


func test_profile_marker() -> bool:
	PlayerProfile.delete(PROFILE_PATH)
	assert_eq(PlayerProfile.read_seen_defense(PROFILE_PATH), 0, "bez profilu: nic nie obejrzane")
	assert_eq(PlayerProfile.write_seen_defense(PROFILE_PATH, 1700000000), OK, "zapis")
	assert_eq(PlayerProfile.read_seen_defense(PROFILE_PATH), 1700000000, "odczyt")
	PlayerProfile.write_seed(PROFILE_PATH, 77)
	assert_eq(PlayerProfile.read_seen_defense(PROFILE_PATH), 1700000000, "inne pola go nie kasują")
	assert_eq(PlayerProfile.read_seed(PROFILE_PATH), 77, "znacznik nie kasuje seeda")
	PlayerProfile.write_seen_defense(PROFILE_PATH, -5)
	assert_eq(PlayerProfile.read_seen_defense(PROFILE_PATH), 0, "zły znacznik to 0")
	PlayerProfile.delete(PROFILE_PATH)
	return true


func test_history_rows() -> bool:
	var r := DefenseLog.parse_history(_wire({"rows": [_row(ATTACK, true, "2026-11-21T10:15:00+01:00",
			{"nickname": "Mieszkomiesz"})]}))[0]
	assert_eq(ReplayPanel.row_text(r, 60), "21.11 10:15 Zdobyty 40%", "pierwsza linia")
	assert_eq(ReplayPanel.detail_text(r), "Mieszkomiesz  Siła %d  Obr. 200-250" % r.army_power, "druga linia")
	r.defense = -1
	assert_eq(ReplayPanel.detail_text(r), "Mieszkomiesz  Siła %d  Obr. ?" % r.army_power, "bez zamku napastnika")
	r.defense = Strength.MAX_RANGE_LOW
	var room := int(ReplayPanel.SIZE.x) - 12 - 6
	assert_true(PixelFont.text_width("30.12 23:59 Zdobyty 100%") + ReplayPanel.shields_width() + 4 <= room,
			"pierwsza linia z tarczami mieści się")
	r.army_power = 99999
	assert_true(PixelFont.text_width(ReplayPanel.detail_text(r)) <= room, "druga linia mieści się")
	assert_true(ReplayPanel.SIZE.x <= 320 - 2 * Hud.CORNER_INSET, "okno mieści się na ekranie 320 px")
	# tarcza obrońcy: pełna, gdy atakujący nie zdobył gwiazdki, pęknięta, gdy zdobył
	assert_eq(ReplayPanel.shield_color(false), Palette.SIDE_DEFENDER, "pełna tarcza")
	assert_true(ReplayPanel.shield_color(true) != Palette.SIDE_DEFENDER, "pęknięta tarcza")
	assert_true(ReplayPanel.SHIELD != ReplayPanel.CRACKED, "inny kształt pękniętej tarczy")
	return true


func test_history_pages_and_touch() -> bool:
	var view := Vector2(320, 180)
	assert_eq(ReplayPanel.PER_PAGE, 4, "4 obrony na stronę")
	assert_eq(ReplayPanel.page_count(0), 1, "pusta lista ma stronę")
	assert_eq(ReplayPanel.page_count(4), 1, "4 obrony")
	assert_eq(ReplayPanel.page_count(10), 3, "10 obron")
	var last := ReplayPanel.row_rect(view, ReplayPanel.PER_PAGE - 1)
	assert_true(last.end.y < ReplayPanel.close_rect(view).position.y, "wiersze nad przyciskami")
	assert_true(last.size.y >= 12 and last.size.x >= 12, "cel dotyku co najmniej 12×12")
	assert_true(ReplayPanel.prev_rect(view).size.x >= 12 and ReplayPanel.next_rect(view).size.y >= 12, "strzałki 12×12")
	assert_true(ReplayPanel.panel_rect(view).end.y <= view.y - Hud.BAR_H, "okno nad dolnym paskiem")
	assert_eq(ReplayPanel.target_at(ReplayPanel.row_rect(view, 1).get_center(), view, 6, 0), 1, "drugi wiersz")
	assert_eq(ReplayPanel.target_at(ReplayPanel.row_rect(view, 1).get_center(), view, 6, 1), 5, "drugi wiersz 2. strony")
	assert_eq(ReplayPanel.target_at(ReplayPanel.row_rect(view, 2).get_center(), view, 6, 1), -1, "pusty wiersz")
	assert_eq(ReplayPanel.target_at(ReplayPanel.close_rect(view).get_center(), view, 6, 0), ReplayPanel.CLOSE, "Wróć")
	assert_eq(ReplayPanel.target_at(ReplayPanel.next_rect(view).get_center(), view, 6, 0), ReplayPanel.NEXT, "dalej")
	assert_eq(ReplayPanel.target_at(ReplayPanel.next_rect(view).get_center(), view, 6, 1), -1, "ostatnia strona")
	assert_eq(ReplayPanel.target_at(ReplayPanel.prev_rect(view).get_center(), view, 6, 0), -1, "pierwsza strona")
	assert_eq(ReplayPanel.target_at(ReplayPanel.prev_rect(view).get_center(), view, 6, 1), ReplayPanel.PREV, "wstecz")
	assert_eq(ReplayPanel.TITLE, "Historia obron", "tytuł")
	# obrona bez powtórki: wiersz jest, ale dotknięcie nie prosi o powtórkę
	var panel := ReplayPanel.new()
	var asked: Array = []
	panel.replay_requested.connect(func(id: String) -> void: asked.append(id))
	var a := _report(200, true)
	a.has_replay = false
	var b := _report(100, false)
	b.id = ATTACK2
	b.has_replay = true
	panel.show_reports([a, b] as Array[DefenseLog.Report], true)
	panel.choose(0)
	panel.choose(1)
	assert_eq(asked, [ATTACK2], "tylko obrona z powtórką")
	panel.free()
	return true


func test_defense_button_label() -> bool:
	var i := DefensePanel.COLUMN.find(DefensePanel.Target.REPLAYS)
	assert_eq(DefensePanel.LABELS[i], "Historia", "przycisk Historia")
	assert_true(PixelFont.text_width(DefensePanel.LABELS[i]) <= int(Hud.BUTTON_SIZE.x) - 4, "napis mieści się")
	return true


func test_hud_alert_dot() -> bool:
	var r := Hud.column_rect(300, 3, true)
	var dot := Hud.alert_rect(r)
	assert_true(dot.position.y < r.position.y + 4 and dot.end.x >= r.end.x - 1, "kropka w prawym górnym rogu")
	assert_true(dot.end.x <= 320 - 1 and dot.position.y >= Hud.BAR_H, "kropka na ekranie, pod górnym paskiem")
	var hud := Hud.new()
	assert_true(not hud.defence_alert, "domyślnie bez kropki")
	hud.free()
	return true


func test_notice_panel() -> bool:
	var view := Vector2(320, 180)
	var n := DefenseNotice.new()
	var got: Array = []
	n.history_requested.connect(func() -> void: got.append("historia"))
	n.closed.connect(func() -> void: got.append("ok"))
	n.open("Zaatakowano Cię 1× od ostatniej wizyty (1 odparty, 0 zdobytych)")
	assert_true(n.visible, "otwarte")
	assert_true(n.lines.size() >= 2, "tekst złamany na szerokość")
	for line in n.lines:
		assert_true(PixelFont.text_width(line) <= int(DefenseNotice.SIZE.x) - 8, "linia mieści się")
	assert_eq(DefenseNotice.target_at(DefenseNotice.history_rect(view).get_center(), view), DefenseNotice.HISTORY, "Historia")
	assert_eq(DefenseNotice.target_at(DefenseNotice.ok_rect(view).get_center(), view), DefenseNotice.OK, "OK")
	assert_eq(DefenseNotice.target_at(Vector2(1, 1), view), -1, "poza przyciskami")
	assert_true(DefenseNotice.history_rect(view).size.y >= 12, "cel dotyku")
	n.choose(DefenseNotice.HISTORY)
	assert_true(not n.visible, "Historia zamyka okienko")
	n.open("x")
	n.choose(DefenseNotice.OK)
	assert_eq(got, ["historia", "ok"], "sygnały")
	n.free()
	return true


func test_client_request() -> bool:
	SupabaseSession.clear(SESSION_PATH)
	SaveGame.delete(SYNC_PATH)
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
	c.defense_reports_loaded.connect(func(list: Array[DefenseLog.Report], ok: bool) -> void: got.append([list, ok]))
	assert_true(c.load_defense_reports(), "historia idzie")
	assert_true(c.is_reports_pending(), "czeka na odpowiedź")
	assert_eq(c.sent_requests[-1]["path"], DefenseLog.HISTORY_PATH, "Edge Function defense_history")
	assert_eq(c.sent_requests[-1]["body"], {}, "bez id gracza w treści (serwer bierze je z tokenu)")
	c.handle_reports(HTTPRequest.RESULT_SUCCESS, 200, JSON.stringify({"rows": [_row(ATTACK, true, "2026-11-21T08:00:00Z")]}))
	assert_true(got[0][1] and (got[0][0] as Array).size() == 1, "lista")
	assert_true(not c.is_reports_pending(), "po odpowiedzi")
	c.free()
	SupabaseSession.clear(SESSION_PATH)
	SaveGame.delete(SYNC_PATH)
	return true


## Serwer oddaje tyle wierszy, ile pokazuje lista, i nie oddaje id napastnika.
func test_server_contract() -> bool:
	var sql := FileAccess.get_file_as_string(MIGRATION)
	var ts := FileAccess.get_file_as_string(FUNCTION)
	assert_true(sql.contains("HISTORY_LIMIT = %d" % DefenseLog.REPORTS_LIMIT) and sql.contains("limit %d" % DefenseLog.REPORTS_LIMIT),
			"limit w SQL jak w kliencie")
	assert_true(ts.contains("HISTORY_LIMIT = %d" % DefenseLog.REPORTS_LIMIT), "limit w Edge Function")
	assert_true(not ts.contains("attacker_id"), "Edge Function nie oddaje id napastnika")
	var strength_sql := FileAccess.get_file_as_string(STRENGTH_MIGRATION)
	assert_true(strength_sql.contains("HISTORY_LIMIT = %d" % DefenseLog.REPORTS_LIMIT)
			and strength_sql.contains("limit %d" % DefenseLog.REPORTS_LIMIT), "nowa wersja funkcji: ten sam limit")
	assert_true(strength_sql.contains("grant execute on function public.defense_history(uuid) to service_role"),
			"nowa wersja funkcji: tylko service_role")
	assert_true(ts.contains("defense: Number.isInteger(row.defense)"), "Edge Function oddaje przedział siły obrony")
	assert_true(sql.contains("to service_role") and sql.contains("from public, anon, authenticated"),
			"tylko service_role")
	return true
