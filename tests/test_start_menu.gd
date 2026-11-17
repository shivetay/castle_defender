extends TestCase
## Ekran startowy (#177): przyciski zależne od zapisu, potwierdzenie nowej gry, ustawienia z zapowiedzią
## języka angielskiego, układ na 320×180 i powrót do menu z HUD-u.

const VIEW := Vector2(320, 180)
const T := StartMenu.Target
const S := StartMenu.Screen


func test_buttons_depend_on_save() -> bool:
	assert_eq(StartMenu.targets(S.MAIN, true), [T.CONTINUE, T.NEW_GAME, T.SETTINGS] as Array[int], "z zapisem: Kontynuuj")
	assert_eq(StartMenu.targets(S.MAIN, false), [T.NEW_GAME, T.SETTINGS] as Array[int], "bez zapisu: bez Kontynuuj")
	var first := StartMenu.button_rects(VIEW, S.MAIN, true)[0].get_center()
	assert_eq(StartMenu.target_at(first, VIEW, S.MAIN, true), T.CONTINUE, "dotknięcie pierwszego przycisku")
	assert_eq(StartMenu.target_at(first, VIEW, S.MAIN, false), T.NEW_GAME, "bez zapisu na górze Nowa gra")
	assert_eq(StartMenu.target_at(Vector2(4, 4), VIEW, S.MAIN, true), T.NONE, "tło to nie przycisk")
	return true


## Nowa gra przy zapisie najpierw pyta; Nie wraca do menu, Tak wysyła sygnał. Bez zapisu od razu.
func test_new_game_needs_confirmation_with_save() -> bool:
	var m := StartMenu.new()
	var asked: Array[int] = [0]
	m.new_game_requested.connect(func() -> void: asked[0] += 1)
	m.has_save = true
	m.activate(T.NEW_GAME)
	assert_eq(m.screen, S.CONFIRM, "pytanie o potwierdzenie")
	assert_eq(asked[0], 0, "jeszcze bez nowej gry")
	m.activate(T.CONFIRM_NO)
	assert_eq(m.screen, S.MAIN, "Nie wraca do menu")
	m.activate(T.NEW_GAME)
	m.activate(T.CONFIRM_YES)
	assert_eq(asked[0], 1, "Tak zaczyna nową grę")
	m.has_save = false
	m.screen = S.MAIN
	m.activate(T.NEW_GAME)
	assert_eq(asked[0], 2, "bez zapisu bez pytania")
	var went: Array[int] = [0]
	m.continue_pressed.connect(func() -> void: went[0] += 1)
	m.activate(T.CONTINUE)
	assert_eq(went[0], 1, "Kontynuuj wraca do gry")
	m.free()
	return true


## Ustawienia: język przełącza się na English z zapowiedzią (#64), dźwięk to zapowiedź, Wróć.
func test_settings_show_language_path() -> bool:
	var m := StartMenu.new()
	m.activate(T.SETTINGS)
	assert_eq(m.screen, S.SETTINGS, "ekran ustawień")
	assert_eq(m.label(T.LANGUAGE), "Język: polski", "domyślnie polski")
	m.activate(T.LANGUAGE)
	assert_eq(m.label(T.LANGUAGE), "Język: English", "wybór angielskiego")
	assert_eq(m.hint, StartMenu.ENGLISH_LATER, "angielski wkrótce")
	m.activate(T.LANGUAGE)
	assert_eq(m.label(T.LANGUAGE), "Język: polski", "z powrotem polski")
	m.activate(T.BACK)
	assert_eq(m.screen, S.MAIN, "Wróć do menu")
	m.free()
	return true


## Układ: cele ≥ 12×12, napisy mieszczą się na przyciskach i na 320 px, przyciski nad stopką.
func test_layout_fits_the_screen() -> bool:
	var m := StartMenu.new()
	for s: int in [S.MAIN, S.CONFIRM, S.SETTINGS]:
		var rects := StartMenu.button_rects(VIEW, s, true)
		var ts := StartMenu.targets(s, true)
		for i in rects.size():
			var r := rects[i]
			assert_true(r.size.x >= 12 and r.size.y >= 12, "cel ≥ 12×12")
			assert_true(r.position.x >= Hud.CORNER_INSET and r.end.x <= VIEW.x - Hud.CORNER_INSET, "w poziomie na ekranie")
			assert_true(r.end.y + 16 < VIEW.y - StartMenu.FOOTER_Y, "nad podpowiedzią i stopką z wersją")
			assert_true(PixelFont.text_width(m.label(ts[i])) <= r.size.x - 2, "„%s” mieści się" % m.label(ts[i]))
			if i > 0:
				assert_true(r.position.y > rects[i - 1].end.y, "bez nakładania")
	for t: String in [StartMenu.TITLE.to_upper(), StartMenu.SUBTITLE, StartMenu.CONFIRM_TEXT, StartMenu.ENGLISH_LATER,
			StartMenu.OFFLINE_NOTE, StartMenu.version_text()]:
		assert_true(PixelFont.text_width(t) <= VIEW.x - 2 * Hud.CORNER_INSET, "„%s” mieści się na 320 px" % t)
	assert_true(StartMenu.version_text().begins_with("Wersja "), "wersja z project.godot")
	m.free()
	return true


## Z gry do menu prowadzi ósmy przycisk kolumny (Menu), który mieści się nad dolnym paskiem.
func test_menu_button_in_hud_column() -> bool:
	var b := Hud.content_bounds(VIEW, Rect2())
	var targets := Hud.column_targets(false)
	assert_eq(targets[-1], Hud.Target.MENU, "Menu na dole kolumny")
	var r := Hud.column_rect(b.y, targets.size() - 1, true)
	assert_true(r.end.y <= VIEW.y - Hud.BAR_H, "nad paskiem komunikatu")
	assert_eq(Hud.target_at(r.get_center(), VIEW, b.y, false, false), Hud.Target.MENU, "dotknięcie Menu")
	assert_eq(Hud.column_label(Hud.Target.MENU), "Menu", "dymek z nazwą")
	return true
