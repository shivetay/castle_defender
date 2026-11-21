extends TestCase
## Ranking PvP (#27): odpowiedź `ranking` (dane niezaufane), żądania klienta, układ panelu na 320 px,
## przewijanie o całe wiersze, karta Strażnicy i zgodność liczb gry z migracją serwera.

const MIGRATION := "res://supabase/migrations/20261120072817_pvp_ranking.sql"
const VIEW := Vector2(320, 180)
const UID := "00000000-0000-0000-0000-0000000000a1"
const SESSION_PATH := "user://test_ranking_session.json"
const SYNC_PATH := "user://test_ranking_sync.json"


func _row(place: Variant, name: String = "Ala", castle: String = "Gród", points: Variant = 1000,
		me: bool = false) -> Dictionary:
	return {"place": place, "nickname": name, "castle_name": castle, "ruler": Rulers.DEFAULT,
		"points": points, "is_me": me}


func _rows(n: int, me_at: int = -1) -> Array[RankingBoard.Row]:
	var raw: Array = []
	for i in n:
		raw.append(_row(i + 1, "Gracz", "Gród", 2000 - i, i == me_at))
	return RankingBoard.parse_response({"kind": "attack", "rows": raw}, RankingBoard.Kind.ATTACK)


## Wiersze z serwera: nazwy jak w onboardingu, liczby przycięte, zły wiersz odpada.
func test_parse_sanitizes_rows() -> bool:
	var rows := RankingBoard.parse_response({"kind": "attack", "rows": [
		_row(1, "Ala", "Wawel", 1016, true),
		_row(2, "", "Gród", 99999999),
		{"place": 3, "nickname": "Ola", "castle_name": "Gród", "ruler": "nieznany", "points": "x"},
		_row(0, "Zły", "Gród"),
		_row(4, "Ewa", ""),
		_row("5", "Tekst", "Gród"),
		"zły",
	]}, RankingBoard.Kind.ATTACK)
	assert_eq(rows.size(), 3, "odpadają: miejsce 0, pusty zamek, miejsce tekstem, nie-słownik")
	assert_eq(rows[0].player_name, "Ala", "imię")
	assert_eq(rows[0].castle_name, "Wawel", "zamek")
	assert_eq(rows[0].points, 1016, "punkty")
	assert_true(rows[0].is_me, "własny wiersz")
	assert_eq(rows[1].player_name, "Gracz", "puste imię: Gracz")
	assert_eq(rows[1].points, RankingBoard.MAX_POINTS, "punkty przycięte")
	assert_eq(rows[2].ruler, Rulers.DEFAULT, "nieznany władca: domyślny portret")
	assert_eq(rows[2].points, 0, "punkty tekstem: 0")
	return true


## Odpowiedź na inny rodzaj albo zła odpowiedź daje pustą tabelę; najwyżej MAX_ROWS i jedno „to Ty”.
func test_parse_limits() -> bool:
	assert_true(RankingBoard.parse_response({"kind": "defense", "rows": [_row(1)]},
			RankingBoard.Kind.ATTACK).is_empty(), "odpowiedź na inny widok")
	assert_true(RankingBoard.parse_response([], RankingBoard.Kind.ATTACK).is_empty(), "nie słownik")
	assert_true(RankingBoard.parse_response({"kind": "attack", "rows": {}},
			RankingBoard.Kind.ATTACK).is_empty(), "rows nie lista")
	var many: Array = []
	for i in 40:
		many.append(_row(i + 1, "Gracz", "Gród", 1000, true))
	var rows := RankingBoard.parse_response({"kind": "defense", "rows": many}, RankingBoard.Kind.DEFENSE)
	assert_eq(rows.size(), RankingBoard.MAX_ROWS, "najwyżej 20 i własny wiersz")
	var me := 0
	for r in rows:
		me += 1 if r.is_me else 0
	assert_eq(me, 1, "„to Ty” najwyżej raz")
	var back := RankingBoard.parse_response({"kind": "attack", "rows": [_row(3), _row(1), _row(3)]},
			RankingBoard.Kind.ATTACK)
	assert_eq(back.size(), 2, "miejsce mniejsze niż poprzednie odpada (remis zostaje)")
	assert_eq(RankingBoard.request(RankingBoard.Kind.DEFENSE), {"kind": "defense"}, "żądanie")
	return true


## Komunikat pod tabelą: miejsce gracza albo zachęta; mieści się w dolnym pasku.
func test_summary() -> bool:
	var rows := _rows(3, 1)
	assert_eq(RankingBoard.summary(rows, RankingBoard.Kind.ATTACK), "Twoje miejsce: 2., punkty: 1999", "miejsce")
	var long := RankingBoard.parse_response({"kind": "attack", "rows": [_row(99999, "A", "B", 99999, true)]},
			RankingBoard.Kind.ATTACK)
	for text: String in [RankingBoard.summary(long, 0), RankingBoard.summary([] as Array[RankingBoard.Row], 0),
			RankingBoard.summary([] as Array[RankingBoard.Row], 1), RankingPanel.OFFLINE_MESSAGE,
			RankingPanel.LOADING_MESSAGE, RankingPanel.FAILED_MESSAGE]:
		assert_true(PixelFont.text_width(text) <= Hud.MESSAGE_MAX_WIDTH, "„%s” mieści się w pasku" % text)
	return true


## Klient: żądanie z rodzajem, odpowiedź do sygnału, prośba o inny widok w trakcie idzie po niej.
func test_client_requests() -> bool:
	SupabaseSession.clear(SESSION_PATH)
	var c := SupabaseClient.new()
	c.setup(SupabaseConfig.parse(JSON.stringify({
		"url": "https://abc.supabase.co", "publishable_key": "sb_publishable_test123",
	})), SESSION_PATH, SYNC_PATH)
	c.fake_transport = true
	assert_true(not c.load_ranking(RankingBoard.Kind.ATTACK), "bez sieci nic nie idzie")
	c.handle_auth(SupabaseClient.Call.SIGNUP, HTTPRequest.RESULT_SUCCESS, 200, JSON.stringify({
		"access_token": "t1", "refresh_token": "r1", "expires_in": 3600,
		"user": {"id": UID, "is_anonymous": true},
	}))
	var got: Array = []
	c.ranking_loaded.connect(func(kind: int, rows: Array[RankingBoard.Row], ok: bool) -> void:
		got.append([kind, rows.size(), ok]))
	c.sent_requests.clear()
	assert_true(c.load_ranking(RankingBoard.Kind.ATTACK), "żądanie idzie")
	assert_true(c.load_ranking(RankingBoard.Kind.DEFENSE), "drugie czeka")
	assert_true(c.load_ranking(RankingBoard.Kind.ATTACK), "znowu atak w trakcie")
	assert_eq(c.sent_requests.size(), 1, "naraz jedno żądanie")
	assert_eq(c.sent_requests[0]["path"], RankingBoard.PATH, "ścieżka Edge Function")
	assert_eq(c.sent_requests[0]["body"], {"kind": "attack"}, "treść")
	c.handle_ranking(HTTPRequest.RESULT_SUCCESS, 200, JSON.stringify({"kind": "attack", "rows": [_row(1)]}))
	assert_eq(got, [[RankingBoard.Kind.ATTACK, 1, true]], "tabela ataku")
	assert_eq(c.sent_requests.size(), 2, "po niej obrona")
	assert_eq(c.sent_requests[1]["body"], {"kind": "defense"}, "treść obrony")
	c.handle_ranking(HTTPRequest.RESULT_SUCCESS, 500, "")
	assert_eq(got[1], [RankingBoard.Kind.DEFENSE, 0, false], "błąd serwera")
	SupabaseSession.clear(SESSION_PATH)
	SaveGame.delete(SYNC_PATH)
	c.free()
	return true


## Układ na 320×180: wiersze między tytułem a przyciskami, przyciski z dala od siebie, teksty w wierszu.
func test_layout_fits() -> bool:
	var b := Hud.content_bounds(VIEW, Rect2())
	var shown := RankingPanel.visible_rows(VIEW)
	assert_true(shown >= 4, "co najmniej 4 wiersze na ekranie")
	var last := RankingPanel.row_rect(shown - 1, b.x, b.y)
	assert_true(RankingPanel.row_rect(0, b.x, b.y).position.y >= Hud.BAR_H + PixelFont.LINE, "pod tytułem")
	assert_true(last.end.y <= Hud.row_y(VIEW), "nad przyciskami")
	var tabs := [RankingPanel.tab_rect(0, VIEW, b.x), RankingPanel.tab_rect(1, VIEW, b.x)]
	var close := RankingPanel.close_rect(VIEW, b.y)
	assert_true(not (tabs[1] as Rect2).intersects(close), "Obrona z dala od Wróć")
	for r: Rect2 in tabs + [close]:
		assert_true(r.size.x >= 12 and r.size.y >= 12, "cel dotyku 12×12")
		assert_true(r.position.x >= b.x and r.end.x <= b.y, "przycisk w treści")
	assert_eq(RankingPanel.target_at((tabs[0] as Rect2).get_center(), VIEW, b.x, b.y), RankingPanel.Target.ATTACK, "Atak")
	assert_eq(RankingPanel.target_at((tabs[1] as Rect2).get_center(), VIEW, b.x, b.y), RankingPanel.Target.DEFENSE, "Obrona")
	assert_eq(RankingPanel.target_at(close.get_center(), VIEW, b.x, b.y), RankingPanel.Target.CLOSE, "Wróć")
	for label: String in RankingPanel.TAB_LABELS:
		assert_true(PixelFont.text_width(label) <= Hud.BUTTON_SIZE.x - 2, "„%s” mieści się" % label)
	for text: String in RankingPanel.EMPTY_TEXTS:
		assert_true(PixelFont.text_width(text) <= int(b.y - b.x), "„%s” mieści się" % text)
	var title := RankingPanel.title_text(9)
	assert_true(PixelFont.text_width(title) + 4 + PixelFont.text_width(RankingPanel.LOAD_TEXTS[3])
			<= int(b.y - b.x), "tytuł i stan w jednej linii")
	# najdłuższy wiersz: miejsce 99999, długie nazwy, punkty 99999 — nic nie wychodzi poza wiersz
	var r := RankingBoard.Row.new()
	r.place = RankingBoard.MAX_PLACE
	r.player_name = "W".repeat(PlayerProfile.NAME_MAX)
	r.castle_name = "W".repeat(PlayerProfile.CASTLE_MAX)
	r.points = RankingBoard.MAX_POINTS
	var w := int(last.size.x)
	var lines := RankingPanel.row_lines(r, w)
	for line: Array in lines:
		var at := line[0] as Vector2
		assert_true(at.x >= 0 and at.x + PixelFont.text_width(line[1] as String) <= w, "„%s” w wierszu" % line[1])
	assert_true((lines[0][0] as Vector2).x + PixelFont.text_width(lines[0][1] as String) <= RankingPanel.PLACE_W,
			"miejsce nie zachodzi na portret")
	assert_true((lines[1][0] as Vector2).x + PixelFont.text_width(lines[1][1] as String)
			< (lines[3][0] as Vector2).x, "imię nie zachodzi na punkty")
	return true


## Przewijanie o całe wiersze, w granicach listy; własny wiersz poza ekranem jest widoczny na start.
func test_scroll() -> bool:
	var h := RankingPanel.ROW_H
	assert_eq(RankingPanel.drag_scroll(0, 0.0, -h * 2.5, 21, 5), [2, -h * 0.5], "w górę: dwa wiersze, reszta zostaje")
	assert_eq(RankingPanel.drag_scroll(2, -h * 0.5, -h * 0.5, 21, 5), [3, 0.0], "reszta się sumuje")
	assert_eq(RankingPanel.drag_scroll(3, 0.0, h * 10.0, 21, 5), [0, 0.0], "nie wyżej niż początek")
	assert_eq(RankingPanel.drag_scroll(0, 0.0, -h * 100.0, 21, 5), [16, 0.0], "nie niżej niż koniec")
	assert_eq(RankingPanel.drag_scroll(0, 0.0, -h * 3.0, 3, 5), [0, 0.0], "krótka lista się nie przewija")
	assert_eq(RankingPanel.start_scroll(_rows(21, 20), 5), 16, "własny wiersz na dole ekranu")
	assert_eq(RankingPanel.start_scroll(_rows(21, 2), 5), 0, "własny wiersz widoczny od góry")
	assert_eq(RankingPanel.start_scroll(_rows(21), 5), 0, "bez własnego wiersza od góry")
	return true


## Panel: przełącznik widoków o tym samym układzie, tabela z pamięci, odpowiedź na inny widok w pamięci.
func test_panel_switches_views() -> bool:
	var p := RankingPanel.new()
	var asked: Array[int] = []
	p.kind_changed.connect(func(k: int) -> void: asked.append(k))
	p.open(0, true)
	assert_eq(asked, [RankingBoard.Kind.ATTACK] as Array[int], "otwarcie prosi o atak")
	assert_eq(p.status_text(), "Wczytuję...", "wczytywanie")
	p.set_rows(RankingBoard.Kind.DEFENSE, _rows(2), true)
	assert_eq(p.load, RankingPanel.Load.LOADING, "odpowiedź na inny widok nie zmienia bieżącego")
	p.set_rows(RankingBoard.Kind.ATTACK, _rows(3, 0), true)
	assert_eq(p.rows.size(), 3, "tabela ataku")
	assert_eq(p.message(), "Twoje miejsce: 1., punkty: 2000", "komunikat z miejscem")
	p._activate(RankingPanel.Target.DEFENSE)
	assert_eq(p.kind, RankingBoard.Kind.DEFENSE, "widok obrony")
	assert_eq(p.rows.size(), 2, "obrona z pamięci")
	assert_eq(asked.size(), 1, "bez drugiego żądania")
	p._activate(RankingPanel.Target.ATTACK)
	assert_eq(p.rows.size(), 3, "atak z pamięci")
	p.open(0, false)
	assert_eq(p.load, RankingPanel.Load.OFFLINE, "bez sieci")
	assert_eq(p.message(), RankingPanel.OFFLINE_MESSAGE, "komunikat bez sieci")
	p._activate(RankingPanel.Target.DEFENSE)
	assert_eq(asked.size(), 1, "bez sieci nic nie idzie")
	p.free()
	return true


## Karta Strażnicy prowadzi do rankingu.
func test_watchtower_card_has_ranking() -> bool:
	var buttons := Hud.card_buttons(false, true)
	assert_true(buttons.has(Hud.CardButton.RANKING), "Ranking na karcie Strażnicy")
	assert_eq(Hud.card_label(Hud.CardButton.RANKING), Hud.RANKING_LABEL, "napis")
	return true


## Liczby gry zgodne z migracją: 20 najlepszych, K = 32, rodzaje rankingu.
func test_matches_migration() -> bool:
	var sql := FileAccess.get_file_as_string(MIGRATION)
	assert_true(not sql.is_empty(), "migracja jest")
	assert_true(sql.contains("RANKING_TOP = %d" % RankingBoard.TOP), "20 najlepszych")
	assert_true(sql.contains("r.ord <= %d" % RankingBoard.TOP), "limit w zapytaniu")
	assert_true(sql.contains("ELO_K = 32") and sql.contains("round(32 *"), "K w opisie i w funkcji")
	for kind: int in [RankingBoard.Kind.ATTACK, RankingBoard.Kind.DEFENSE]:
		var key := RankingBoard.KIND_KEYS[kind]
		assert_true(sql.contains("'%s'" % key), "rodzaj „%s”" % key)
	var fn := FileAccess.get_file_as_string("res://supabase/functions/ranking/index.ts")
	assert_true(fn.contains("MAX_ROWS = %d" % RankingBoard.MAX_ROWS), "Edge Function: 20 i własny wiersz")
	return true
