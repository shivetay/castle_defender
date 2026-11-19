extends TestCase
## Ekran 3 celów (#24): układ na 320×180, cele dotyku, teksty mieszczące się w kartach,
## miniatura zamku i przebieg: boty od razu, gracze z serwera na pierwszych kartach.

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


## Najdłuższe nazwy i liczby mieszczą się w karcie (8 px font, karta ok. 96 px).
func test_card_text_fits() -> bool:
	var w := int(TargetPicker.card_width(LEFT, RIGHT))
	var player := _player(TargetSearch.MAX_RATING)
	for t: TargetSearch.Target in [player, TargetSearch.bot_target(19), TargetSearch.bot_target(0)]:
		var lines := TargetPicker.card_lines(t, w)
		for line: Array in lines:
			var at := line[0] as Vector2
			var text := line[1] as String
			assert_true(not text.is_empty(), "tekst na karcie")
			assert_true(at.x + PixelFont.text_width(text) <= w, "„%s” mieści się w szerokości" % text)
			assert_true(at.y + PixelFont.LINE <= TargetPicker.CARD_H, "„%s” mieści się w wysokości" % text)
		var texts: Array[String] = []
		for line: Array in lines:
			texts.append(line[1] as String)
		assert_true(t.castle_name in texts or texts[2].ends_with("..."), "nazwa zamku na karcie")
		assert_true(TargetPicker.CARD_H >= TargetPicker.MINI_Y + MinimapArt.SIZE, "miniatura w karcie")
	assert_true(TargetPicker.card_lines(player, w)[0][1] == "Władysław123", "pełne imię gracza")
	return true


func test_minimap_image() -> bool:
	var footprint: Array[Rect2i] = [Rect2i(30, 30, 2, 2), Rect2i(34, 30, 1, 1)]
	var a := MinimapArt.castle_image(4242, footprint)
	var b := MinimapArt.castle_image(4242, footprint)
	assert_eq(a.get_size(), Vector2i(MinimapArt.SIZE, MinimapArt.SIZE), "32×32")
	assert_eq(a.get_data(), b.get_data(), "ten sam seed i zarys: ta sama miniatura")
	var o := MinimapArt.window_origin(footprint)
	assert_eq(a.get_pixelv(Vector2i(30, 30) - o), MinimapArt.BUILDING, "wnętrze budynku")
	assert_eq(a.get_pixelv(Vector2i(31, 31) - o), MinimapArt.BUILDING_EDGE, "obwódka od południowego wschodu")
	assert_eq(a.get_pixelv(Vector2i(34, 30) - o), MinimapArt.BUILDING, "odcinek 1×1 bez obwódki")
	assert_eq(MinimapArt.window_origin([Rect2i(0, 0, 1, 1)] as Array[Rect2i]), Vector2i.ZERO, "przycięte do mapy")
	assert_eq(MinimapArt.window_origin([Rect2i(63, 63, 1, 1)] as Array[Rect2i]), Vector2i(32, 32), "przycięte z drugiej strony")
	assert_eq(MinimapArt.window_origin([] as Array[Rect2i]), Vector2i(16, 16), "bez zarysu: środek mapy")
	var other := MinimapArt.castle_image(1337, footprint)
	assert_true(other.get_data() != a.get_data(), "inny seed: inny teren")
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
