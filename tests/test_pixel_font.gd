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
	for label in BuildingTypes.SHORT_NAMES + Hud.CARD_LABELS + [Hud.CANCEL_LABEL, Hud.SIEGE_LABEL, Hud.BUILD_LABEL, Hud.DONE_LABEL]:
		assert_true(PixelFont.text_width(label) <= int(Hud.BUTTON_SIZE.x) - 4, "„%s” mieści się na przycisku" % label)
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
