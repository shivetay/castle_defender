extends TestCase
## Font pikselowy: pokrycie znaków UI, szerokości i mieszczenie się tekstów w 320 px.


func test_ui_texts_use_only_known_glyphs() -> bool:
	var texts: Array[String] = [Hud.VIEW_MESSAGE, Hud.SIEGE_LATER_MESSAGE, "60 FPS", Ages.label(0, 5),
			"Podczas nieobecności: +200 Dr +20 Ka", "Tu stoi Wieża drewniana", "poziom 5/5", "budowa 1:30:00",
			"Tu nie można budować", "Najwyższy poziom", "zażółć gęślą jaźń", "ĄĆĘŁŃÓŚŹŻ 0123456789 .,:;-+/%()!?"]
	texts.append_array(Hud.CARD_LABELS)
	texts.append_array([Hud.CANCEL_LABEL, Hud.SIEGE_LABEL, Hud.BUILD_LABEL, Hud.DONE_LABEL])
	texts.append_array(BuildingTypes.NAMES)
	texts.append_array(BuildingTypes.SHORT_NAMES)
	for t in texts:
		assert_true(not PixelFont._normalize(t).contains("?") or t.contains("?"), "znaki z „%s” są w foncie" % t)
	return true


func test_widths_and_fit() -> bool:
	assert_eq(PixelFont.text_width(""), 0, "pusty tekst")
	assert_eq(PixelFont.text_width("A"), 4, "A ma 4 px")
	assert_eq(PixelFont.text_width("AA"), 9, "odstęp 1 px")
	assert_eq(PixelFont.text_width("ż"), PixelFont.text_width("Z"), "polska litera ma szerokość bazowej")
	for label in Hud.CARD_LABELS + [Hud.CANCEL_LABEL, Hud.SIEGE_LABEL, Hud.BUILD_LABEL, Hud.DONE_LABEL]:
		assert_true(PixelFont.text_width(label) <= int(Hud.BUTTON_SIZE.x) - 2, "„%s” mieści się na przycisku" % label)
	var messages: Array[String] = [Hud.VIEW_MESSAGE, Hud.SIEGE_LATER_MESSAGE]
	for name in BuildingTypes.NAMES:
		messages.append("Tu stoi %s" % name)
	for msg in messages:
		assert_true(PixelFont.text_width(msg) <= Hud.MESSAGE_MAX_WIDTH, "komunikat „%s” mieści się w 320 px" % msg)
	return true


func test_render_is_deterministic_and_accents_differ() -> bool:
	var a := Image.create(80, 8, false, Image.FORMAT_RGBA8)
	var b := Image.create(80, 8, false, Image.FORMAT_RGBA8)
	PixelFont.render(a, Vector2i.ZERO, "Wieża 5/5", Palette.INK)
	PixelFont.render(b, Vector2i.ZERO, "Wieża 5/5", Palette.INK)
	assert_eq(a.get_data(), b.get_data(), "ten sam tekst, te same piksele")
	var z := Image.create(8, 8, false, Image.FORMAT_RGBA8)
	var zz := Image.create(8, 8, false, Image.FORMAT_RGBA8)
	PixelFont.render(z, Vector2i.ZERO, "Z", Palette.INK)
	PixelFont.render(zz, Vector2i.ZERO, "Ż", Palette.INK)
	assert_true(z.get_data() != zz.get_data(), "Ż różni się od Z")
	return true


## Treść pasków trzyma się z dala od zaokrąglonych narożników, a wycięcie ekranu ją odsuwa dalej.
func test_hud_content_avoids_rounded_corners() -> bool:
	var view := Vector2(400, 180)
	assert_eq(Hud.content_bounds(view, Rect2()), Vector2(Hud.CORNER_INSET, 400 - Hud.CORNER_INSET), "bez strefy: stały margines")
	assert_eq(Hud.content_bounds(view, Rect2(30, 0, 340, 180)), Vector2(30, 370), "wycięcie po bokach odsuwa treść")
	assert_eq(Hud.content_bounds(view, Rect2(2, 0, 396, 180)), Vector2(Hud.CORNER_INSET, 400 - Hud.CORNER_INSET),
			"mała strefa nie zmniejsza marginesu narożników")
	var odd := Hud.content_bounds(view, Rect2(300, 0, 50, 180))
	assert_true(odd.y >= odd.x, "nietypowa strefa: prawa granica nie przed lewą")
	var rects := Hud.card_rects(Vector2(320, 180))
	assert_true(rects[0].position.x >= Hud.CORNER_INSET and rects[-1].end.x <= 320 - Hud.CORNER_INSET,
			"karta budynku mieści się między narożnikami")
	return true


## Liczba zapalonych pikseli glifu (bez akcentów).
func _ink(ch: String) -> int:
	var n := 0
	for row: String in PixelFont.GLYPHS[ch]:
		n += row.count("#")
	return n


## #327: lżejsze glify przy tych samych szerokościach, więc układ paneli się nie zmienia.
func test_glyphs_are_light_and_keep_widths() -> bool:
	var widths := {"0": 3, "1": 3, "2": 3, "3": 3, "5": 3, "6": 3, "8": 3, "9": 3,
			"B": 4, "E": 4, "G": 4, "S": 4, "W": 5, "M": 5, "I": 3, "O": 4}
	for ch: String in widths:
		assert_eq(PixelFont.glyph_width(ch), int(widths[ch]), "„%s” ma tę samą szerokość" % ch)
	for ch: String in PixelFont.GLYPHS:
		var rows: Array = PixelFont.GLYPHS[ch]
		assert_true(rows.size() == 5 or rows.size() == 6, "„%s” ma 5 wierszy (+ogonek)" % ch)
		for row: String in rows:
			assert_eq(row.length(), (rows[0] as String).length(), "„%s”: równe wiersze" % ch)
	for d in ["0", "3", "6", "8", "9"]:
		assert_true(_ink(d) <= 10, "cyfra „%s” nie jest pełnym prostokątem" % d)
		var top: String = PixelFont.GLYPHS[d][0]
		assert_true(top[0] == "." or top[2] == ".", "cyfra „%s” ma zaokrąglony górny róg" % d)
	assert_true(PixelFont.GLYPHS["1"] != PixelFont.GLYPHS["I"], "1 różni się od I")
	assert_eq(PixelFont.GLYPHS["1"][4], ".#.", "1 bez dolnej belki")
	assert_true(PixelFont.GLYPHS["5"] != PixelFont.GLYPHS["S"], "5 różni się od S")
	for ch in ["B", "E"]:
		assert_eq(PixelFont.GLYPHS[ch][2], "##..", "„%s” ma krótszą środkową belkę" % ch)
	return true


## Skróty surowców jako osobne słowo rysują się ikoną z paska surowców, a nie literami.
func test_resource_short_names_become_icons() -> bool:
	var toks := PixelFont.tokens("120 Dr 40 Ka, 5 Ży/h +2 Zł")
	for res in EconomyConfig.count():
		assert_true(toks.has(PixelFont.ICON_MARK + str(res)), "ikona surowca %d" % res)
	assert_eq(PixelFont.text_width("5 Dr"), PixelFont.text_width("5 ") + 1 + PixelIcons.SIZE, "ikona ma szerokość 5 px")
	for t in ["Drewno", "Kamień", "Złoto", "Kara"]:
		assert_true(not "".join(PixelFont.tokens(t)).contains(PixelFont.ICON_MARK), "„%s” bez ikony" % t)
	var a := Image.create(40, 8, false, Image.FORMAT_RGBA8)
	var b := Image.create(40, 8, false, Image.FORMAT_RGBA8)
	PixelFont.render(a, Vector2i.ZERO, "9 Ka", Palette.INK)
	PixelFont.render(b, Vector2i.ZERO, "9 KA", Palette.INK)
	assert_true(a.get_data() != b.get_data(), "„Ka” to ikona, „KA” litery")
	return true
