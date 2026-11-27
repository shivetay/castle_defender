extends TestCase
## Ekran tytułowy Dunholm (#360): grafika z kodu i z palety, deterministyczna, logo i przyciski
## mieszczą się na 320×180, „Graj” zamyka ekran. Link do Discorda wspólny z Ustawieniami.

const VIEW := Vector2(320, 180)
const WIDE := Vector2(400, 180)
const T := TitleScreen.Target


## Wszystkie piksele z palet: epoki I i II, ekranu tytułowego i UI (zasada 2 z CLAUDE.md).
func test_art_uses_only_palette_colors() -> bool:
	var allowed := {}
	for c: Color in Palette.AGE_I + Palette.AGE_II + Palette.TITLE + Palette.UI:
		allowed[c.to_rgba32()] = true
	var img := TitleArt.make_image(Vector2i(VIEW))
	var bad := 0
	for y in img.get_height():
		for x in img.get_width():
			if not allowed.has(img.get_pixel(x, y).to_rgba32()):
				bad += 1
	assert_eq(bad, 0, "piksele spoza palety")
	return true


func test_art_is_deterministic() -> bool:
	for v: Vector2 in [VIEW, WIDE]:
		var a := TitleArt.make_image(Vector2i(v))
		var b := TitleArt.make_image(Vector2i(v))
		assert_eq(a.get_size(), Vector2i(v), "rozmiar ekranu")
		assert_true(a.get_data() == b.get_data(), "ten sam rozmiar, te same piksele")
	return true


func test_layout_fits_the_screen() -> bool:
	for v: Vector2 in [VIEW, WIDE]:
		var logo := TitleArt.logo_rect(int(v.x))
		assert_true(logo.position.x >= Hud.CORNER_INSET and logo.end.x <= int(v.x) - Hud.CORNER_INSET, "logo mieści się")
		var rects := TitleScreen.button_rects(v)
		assert_eq(rects.size(), TitleScreen.targets().size(), "przycisk na cel")
		for i in rects.size():
			var r := rects[i]
			assert_true(r.size.x >= 12 and r.size.y >= 12, "cel ≥ 12×12")
			assert_true(r.position.x >= Hud.CORNER_INSET and r.end.x <= v.x - Hud.CORNER_INSET, "z dala od bocznych krawędzi")
			assert_true(r.end.y <= v.y - 12, "z dala od dolnej krawędzi")
			assert_true(r.position.y > logo.end.y, "pod logo")
			assert_eq(r.position, r.position.floor(), "całe piksele")
			var l := TitleScreen.label(TitleScreen.targets()[i])
			assert_true(PixelFont.text_width(l) <= r.size.x - 2, "„%s” mieści się" % l)
			assert_eq(TitleScreen.target_at(r.get_center(), v), TitleScreen.targets()[i], "dotknięcie przycisku")
		assert_true(not rects[0].intersects(rects[1]), "bez nakładania")
		assert_eq(TitleScreen.target_at(Vector2(2, 2), v), T.NONE, "tło to nie przycisk")
	for t: String in [TitleArt.SUBTITLE, CommunityLink.OPENING, CommunityLink.FAILED]:
		assert_true(PixelFont.text_width(t) <= int(VIEW.x) - 2 * Hud.CORNER_INSET, "„%s” mieści się na 320 px" % t)
	return true


func test_play_closes_and_marks_shown() -> bool:
	var was := TitleScreen.shown_this_run
	var s := TitleScreen.new()
	var played: Array[int] = [0]
	s.play_pressed.connect(func() -> void: played[0] += 1)
	s.open()
	assert_true(s.visible and TitleScreen.shown_this_run, "pokazany i zapamiętany na to uruchomienie")
	s.activate(T.PLAY)
	assert_true(not s.visible and played[0] == 1, "Graj zamyka ekran")
	s.free()
	TitleScreen.shown_this_run = was
	return true


func test_discord_link_in_settings() -> bool:
	assert_true(CommunityLink.DISCORD_URL.begins_with("https://discord.gg/"), "link zaproszenia Discord")
	assert_true(SettingsPanel.targets(SettingsPanel.Screen.SETTINGS).has(SettingsPanel.Target.DISCORD), "Discord w Ustawieniach")
	var m := SettingsPanel.new()
	assert_eq(m.label(SettingsPanel.Target.DISCORD), CommunityLink.LABEL, "napis")
	m.free()
	return true
