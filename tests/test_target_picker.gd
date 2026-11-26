extends TestCase
## Ekran 3 celów (#24): układ na 320×180, cele dotyku, teksty mieszczące się w kartach,
## treść karty (#310: portret, imię, zamek, siła) i przebieg: boty od razu, gracze z serwera
## na pierwszych kartach.

const VIEW := Vector2(320, 180)
const LEFT := float(Hud.CORNER_INSET)
const RIGHT := 320.0 - Hud.CORNER_INSET
const T := TargetPicker.Target
const B := "00000000-0000-0000-0000-0000000000b1"


func _player(rating: int = 1040) -> TargetSearch.Target:
	var list := TargetSearch.parse_response({"targets": [{
		"player_id": B, "nickname": "Władysław123", "castle_name": "Żółwia Ściana Wsch",
		"ruler": Rulers.DEFAULT, "age": 1, "rating": rating, "map_seed": 4242,
		"footprint": [[30, 30, 2, 2]], "loot": [999999, 999999, 999999, 999999],
	}]})
	return list[0]


func test_layout_fits_screen() -> bool:
	var cards := TargetPicker.card_rects(LEFT, RIGHT)
	assert_eq(cards.size(), 3, "3 karty")
	for i in cards.size():
		var r := cards[i]
		assert_true(r.position.x >= LEFT and r.end.x <= RIGHT, "karta %d w poziomie" % i)
		assert_true(r.end.y <= Hud.row_y(VIEW), "karta %d nad przyciskami" % i)
		assert_true(r.position.y >= Hud.BAR_H, "karta %d pod górnym paskiem" % i)
		if i > 0:
			assert_true(r.position.x >= cards[i - 1].end.x, "karty się nie nachodzą")
	var buttons := [TargetPicker.bots_rect(VIEW, LEFT), TargetPicker.plan_rect(VIEW, RIGHT),
			TargetPicker.close_rect(VIEW, RIGHT)]
	for b: Rect2 in buttons:
		assert_true(b.size.x >= 12 and b.size.y >= 12, "przycisk co najmniej 12×12")
		assert_true(b.position.x >= LEFT and b.end.x <= RIGHT, "przycisk z dala od krawędzi")
	assert_true(not buttons[0].intersects(buttons[1]) and not buttons[1].intersects(buttons[2]), "przyciski osobno")
	assert_eq(TargetPicker.target_at(cards[1].get_center(), VIEW, LEFT, RIGHT), T.CARD + 1, "dotyk karty")
	assert_eq(TargetPicker.target_at((buttons[0] as Rect2).get_center(), VIEW, LEFT, RIGHT), T.BOTS, "Boty")
	assert_eq(TargetPicker.target_at((buttons[1] as Rect2).get_center(), VIEW, LEFT, RIGHT), T.PLAN, "Planuj")
	assert_eq(TargetPicker.target_at((buttons[2] as Rect2).get_center(), VIEW, LEFT, RIGHT), T.CLOSE, "Wróć")
	var title_w := PixelFont.text_width(TargetPicker.TITLE)
	for s in TargetPicker.SEARCH_TEXTS + [TargetPicker.NO_PLAYERS_TEXT]:
		assert_true(title_w + 6 + PixelFont.text_width(s) <= RIGHT - LEFT, "tytuł i stan mieszczą się: " + s)
	return true


## Najdłuższe nazwy i liczby mieszczą się w karcie (8 px font, karta ok. 96 px), a karta pod portretem.
func test_card_text_fits() -> bool:
	var w := int(TargetPicker.card_width(LEFT, RIGHT))
	var player := _player(TargetSearch.MAX_RATING)
	assert_true(TargetPicker.CARD_H >= 2 * TargetPicker.PAD + PortraitArt.SIZE, "portret w karcie")
	for t: TargetSearch.Target in [player, TargetSearch.bot_target(19), TargetSearch.bot_target(0)]:
		var lines := TargetPicker.card_lines(t, w)
		assert_eq(lines.size(), 3, "imię, siła i nazwa zamku")
		for line: Array in lines:
			var at := line[0] as Vector2
			var text := line[1] as String
			assert_true(not text.is_empty(), "tekst na karcie")
			assert_true(at.x + PixelFont.text_width(text) <= w, "„%s” mieści się w szerokości" % text)
			assert_true(at.y + PixelFont.LINE <= TargetPicker.CARD_H, "„%s” mieści się w wysokości" % text)
		var castle := lines[2][1] as String
		assert_true(castle == t.castle_name or castle.ends_with("..."), "nazwa zamku na karcie")
	assert_true(TargetPicker.card_lines(player, w)[0][1] == "Władysław123", "pełne imię gracza")
	return true


## Treść karty (#310, #293): bez epoki, łupu i rankingu; siła jako przedział (mgła wojny): gracza
## z serwera, bota z Strength.bot_defense; gracz bez siły z serwera ma „?”.
func test_card_content() -> bool:
	var w := int(TargetPicker.card_width(LEFT, RIGHT))
	var player := _player(1234)
	var texts: Array[String] = []
	for line: Array in TargetPicker.card_lines(player, w):
		texts.append(line[1] as String)
	assert_eq(texts[1], TargetPicker.UNKNOWN_STRENGTH_TEXT, "siła gracza bez serwera: znak zapytania")
	player.strength = 250
	assert_eq(TargetPicker.card_lines(player, w)[1][1], "Siła 250-300", "siła gracza: przedział")
	player.strength = Strength.MAX_RANGE_LOW
	var widest: Array = TargetPicker.card_lines(player, w)[1]
	assert_true((widest[0] as Vector2).x + PixelFont.text_width(widest[1] as String) <= w, "najszerszy przedział mieści się")
	assert_true(not "1234" in texts and not TargetSearch.age_label(player.age) in texts, "bez rankingu i epoki")
	var bot := TargetSearch.bot_target(5)
	var expected := "%s %s" % [TargetPicker.STRENGTH_LABEL, Strength.range_text(Strength.bot_defense(BotRoster.generate(5)))]
	assert_true(expected.contains("-"), "bot też w przedziale")
	assert_eq(TargetPicker.card_lines(bot, w)[1][1], expected, "siła bota")
	assert_eq(TargetPicker.strength_text(TargetSearch.bot_target(5)), expected, "ta sama siła z cache")
	return true


func test_flow_bots_then_players() -> bool:
	var p := TargetPicker.new()
	var chosen: Array = []
	p.bot_chosen.connect(func(i: int) -> void: chosen.append(["bot", i]))
	p.player_chosen.connect(func(t: TargetSearch.Target) -> void: chosen.append(["gracz", t.player_id]))
	p.open(2, true)
	assert_eq(p.targets.size(), 3, "od razu 3 cele")
	assert_eq(p.status_text(), TargetPicker.SEARCH_TEXTS[TargetPicker.Search.SEARCHING], "szukam")
	assert_true(p.targets[0].is_bot, "przed odpowiedzią same boty")
	p._activate(T.PLAN)
	assert_eq(chosen, [["bot", 2]], "Planuj na bocie: bieżący cel kampanii")
	p.set_players([_player()] as Array[TargetSearch.Target], true)
	assert_eq(p.targets.size(), 3, "nadal 3 cele")
	assert_true(not p.targets[0].is_bot and p.targets[1].is_bot and p.targets[2].is_bot, "gracz na pierwszej karcie")
	assert_eq(p.status_text(), "", "znaleziono graczy")
	p._activate(T.PLAN)
	assert_eq(chosen[1], ["gracz", B], "Planuj na graczu")
	p._activate(T.CARD + 2)
	assert_eq(p.selected, 2, "wybór karty")
	p.set_players([] as Array[TargetSearch.Target], true)
	assert_eq(p.selected, 2, "spóźniona odpowiedź niczego nie zmienia")
	p.open(0, true)
	p.set_players([] as Array[TargetSearch.Target], true)
	assert_eq(p.status_text(), TargetPicker.NO_PLAYERS_TEXT, "brak graczy")
	p.open(0, true)
	p.set_players([] as Array[TargetSearch.Target], false)
	assert_eq(p.status_text(), TargetPicker.SEARCH_TEXTS[TargetPicker.Search.FAILED], "serwer nie odpowiada")
	assert_eq(p.targets.size(), 3, "przy błędzie zostają 3 boty")
	p.open(0, true)
	p.set_players([] as Array[TargetSearch.Target], false, true)
	assert_eq(p.status_text(), TargetPicker.SEARCH_TEXTS[TargetPicker.Search.LIMITED], "limit szukań")
	p.open(0, false)
	assert_eq(p.status_text(), TargetPicker.SEARCH_TEXTS[TargetPicker.Search.OFFLINE], "bez sieci")
	p.set_players([_player()] as Array[TargetSearch.Target], true)
	assert_true(p.targets[0].is_bot, "bez szukania odpowiedź jest pomijana")
	p.free()
	return true


## Przycisk „Nowe” (#313): nad Botami, z dala od Planuj i od innych przycisków, z ceną w napisie,
## także przy odsłoniętym czasie zwiadu.
func test_refresh_button_layout() -> bool:
	var r := TargetPicker.refresh_rect(VIEW, LEFT)
	assert_true(r.size.x >= 12 and r.size.y >= 12, "co najmniej 12×12")
	assert_true(r.position.x >= LEFT and r.end.x <= RIGHT, "z dala od krawędzi")
	assert_true(r.end.y <= Hud.row_y(VIEW), "nad dolnym rzędem")
	assert_true(r.position.y >= TargetPicker.SCOUT_Y + 2 * (PixelFont.LINE + 1), "pod liniami zwiadu")
	for b: Rect2 in [TargetPicker.bots_rect(VIEW, LEFT), TargetPicker.plan_rect(VIEW, RIGHT),
			TargetPicker.close_rect(VIEW, RIGHT), TargetPicker.scout_rect(VIEW, LEFT, true),
			TargetPicker.scout_time_rect(VIEW, LEFT)]:
		assert_true(not r.intersects(b), "osobno od innych przycisków")
	for open: bool in [false, true]:
		assert_eq(TargetPicker.target_at(r.get_center(), VIEW, LEFT, RIGHT, open), T.REFRESH, "dotyk Nowe")
	for n in [0, 5, 50]:
		var label := TargetPicker.refresh_label(TargetRefresh.cost_for(n))
		assert_true(PixelFont.text_width(label) + 4 <= Hud.BUTTON_SIZE.x, "„%s” mieści się" % label)
	return true


## Odświeżenie: tylko w sieci, ze złotem i gdy nic się nie szuka. Udane podmienia cele, nieudane
## zostawia poprzednią listę i jej stan.
func test_refresh_flow() -> bool:
	var p := TargetPicker.new()
	var asked: Array[int] = [0]
	p.refresh_requested.connect(func() -> void: asked[0] += 1)
	p.open(0, true)
	p.refresh_online = true
	p.refresh_affordable = true
	assert_true(not p.refresh_enabled(), "w trakcie szukania wyszarzony")
	p._activate(T.REFRESH)
	assert_eq(asked[0], 0, "w trakcie szukania nic nie robi")
	p.set_players([_player()] as Array[TargetSearch.Target], true)
	assert_true(p.refresh_enabled(), "po szukaniu aktywny")
	p._activate(T.REFRESH)
	assert_eq(asked[0], 1, "prośba o odświeżenie")
	p.begin_refresh()
	assert_true(p.is_refreshing(), "odświeża")
	assert_true(not p.targets[0].is_bot, "w trakcie zostaje stara lista")
	p.set_players([] as Array[TargetSearch.Target], false)
	assert_true(not p.is_refreshing(), "koniec odświeżania")
	assert_true(not p.targets[0].is_bot, "nieudane: gracz zostaje")
	assert_eq(p.status_text(), "", "nieudane: poprzedni stan")
	p.begin_refresh()
	p.set_players([] as Array[TargetSearch.Target], true)
	assert_true(p.targets[0].is_bot, "udane: nowa lista")
	p.refresh_affordable = false
	assert_true(not p.refresh_enabled(), "bez złota wyszarzony")
	p._activate(T.REFRESH)
	assert_eq(asked[0], 1, "bez złota nic")
	p.refresh_affordable = true
	p.refresh_online = false
	assert_true(not p.refresh_enabled(), "bez sieci wyszarzony")
	p.refresh_online = true
	p.begin_refresh()
	p.close()
	assert_true(not p.is_refreshing(), "Wróć przerywa odświeżanie")
	assert_eq(p.status_text(), TargetPicker.NO_PLAYERS_TEXT, "po Wróć stan sprzed odświeżenia")
	p.set_players([_player()] as Array[TargetSearch.Target], true)
	assert_true(p.targets[0].is_bot, "spóźniona odpowiedź po Wróć pominięta")
	p.begin_refresh()
	p.open(0, true)
	assert_true(not p.is_refreshing(), "ponowne otwarcie kasuje odświeżanie")
	p.free()
	return true
