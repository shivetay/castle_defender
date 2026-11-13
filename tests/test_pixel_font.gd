extends TestCase
## Font pikselowy: pokrycie znaków UI, szerokości i mieszczenie się tekstów w 320 px.


func test_ui_texts_use_only_known_glyphs() -> bool:
	var texts: Array[String] = ["Castle Defender · etap 3", "seed 1337  4×  60 FPS", "Ulepsz", "Rozbierz",
			"Zamknij", "poziom 5/5", "Tu nie można budować", "Najwyższy poziom", "zażółć gęślą jaźń",
			"ĄĆĘŁŃÓŚŹŻ 0123456789 .,:;-+/%()!?"]
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
	for label in BuildingTypes.SHORT_NAMES + Hud.CARD_LABELS:
		assert_true(PixelFont.text_width(label) <= int(Hud.BUTTON_SIZE.x) - 4, "„%s” mieści się na przycisku" % label)
	for name in BuildingTypes.NAMES:
		var msg := "%s: dotknij trawy, aby postawić" % name
		assert_true(PixelFont.text_width(msg) <= 312, "komunikat „%s” mieści się w 320 px" % msg)
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
