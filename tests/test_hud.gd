extends TestCase
## HUD z #9: cele dotyku, rozkład przycisków w trybie oglądania i budowy, przewijanie paska
## budynków oraz epoka i rok.

const VIEW := Vector2(320, 180)
const WIDE := Vector2(400, 180)
const T := Hud.Target


func _bounds(view: Vector2) -> Vector2:
	return Hud.content_bounds(view, Rect2())


## Po teście na telefonie przyciski są mniejsze (decyzja właściciela), ale nie mniejsze niż
## minimum 12×12 px z CLAUDE.md, a napisy się mieszczą.
func test_touch_targets_are_big_enough() -> bool:
	assert_true(Hud.BUTTON_SIZE.y >= 12 and Hud.BUTTON_SIZE.x >= 12, "cel ≥ 12×12 px")
	assert_true(Hud.BUTTON_SIZE.y < 22, "mniejszy niż dawne 56×22")
	for label: String in [Hud.BUILD_LABEL, Hud.RESEARCH_LABEL, Hud.ARMY_LABEL, Hud.SIEGE_LABEL, Hud.ATTACK_LABEL, Hud.DEFENCE_LABEL, Hud.DONE_LABEL,
			Hud.CHANGE_LABEL, Hud.CANCEL_LABEL, "Zamknij", "Rozbierz", "Ulepsz", "Postaw", "Szkol", "Badaj"]:
		assert_true(PixelFont.text_width(label) <= Hud.BUTTON_SIZE.x - 2, "„%s” mieści się na przycisku" % label)
	return true


## Przyciski trybów w kolumnie przy prawej krawędzi, od góry, pod górnym paskiem i nad dolnym.
func test_column_buttons_stack_on_the_right() -> bool:
	for view: Vector2 in [VIEW, WIDE]:
		var b := _bounds(view)
		for building: bool in [false, true]:
			var n := Hud.column_targets(building).size()
			for i in n:
				var r := Hud.column_rect(b.y, i, Hud.uses_icons(building))
				assert_eq(r.end.x, b.y, "przy prawej granicy treści")
				assert_true(r.position.y >= Hud.BAR_H, "pod górnym paskiem")
				assert_true(r.end.y <= view.y - Hud.BAR_H, "nad paskiem komunikatu")
				if i > 0:
					assert_true(r.position.y > Hud.column_rect(b.y, i - 1, Hud.uses_icons(building)).end.y, "od góry, bez nakładania")
	assert_eq(Hud.column_targets(false), [T.BUILD, T.RESEARCH, T.ARMY, T.DEFENCE, T.QUEUE, T.SETTINGS] as Array[int],
			"oglądanie: kolejność")
	assert_eq(Hud.column_targets(true), [T.DONE, T.CHANGE, T.CANCEL] as Array[int], "budowa: Gotowe, Zmień i Anuluj")
	return true


func test_targets_follow_mode() -> bool:
	var b := _bounds(VIEW)
	# środki wąskich przycisków z ikonami leżą też na szerokich przyciskach trybu budowy
	var first := Hud.column_rect(b.y, 0, true).get_center()
	var second := Hud.column_rect(b.y, 1, true).get_center()
	var third := Hud.column_rect(b.y, 2, true).get_center()
	var fourth := Hud.column_rect(b.y, 3, true).get_center()
	assert_eq(Hud.target_at(first, VIEW, b.y, false, false), T.BUILD, "oglądanie: Buduj na górze")
	assert_eq(Hud.target_at(second, VIEW, b.y, false, false), T.RESEARCH, "oglądanie: Badania")
	assert_eq(Hud.target_at(third, VIEW, b.y, false, false), T.ARMY, "oglądanie: Wojsko")
	assert_eq(Hud.target_at(fourth, VIEW, b.y, false, false), T.DEFENCE, "oglądanie: Obrona (#19)")
	assert_eq(Hud.target_at(Hud.column_rect(b.y, 4, true).get_center(), VIEW, b.y, false, false), T.QUEUE, "oglądanie: Kolejka")
	assert_eq(Hud.target_at(first, VIEW, b.y, true, false), T.DONE, "budowa: w tym samym miejscu Gotowe")
	assert_eq(Hud.target_at(second, VIEW, b.y, true, false), T.CHANGE, "budowa: Zmień")
	assert_eq(Hud.target_at(third, VIEW, b.y, true, false), T.CANCEL, "budowa: Anuluj")
	assert_eq(Hud.target_at(fourth, VIEW, b.y, true, false), T.NONE, "budowa: tylko trzy przyciski")
	assert_eq(Hud.target_at(Vector2(160, 90), VIEW, b.y, true, false), T.NONE, "mapa to nie przycisk")
	var card := Hud.card_rects(VIEW)
	assert_eq(Hud.target_at(card[1].get_center(), VIEW, b.y, false, true), T.CARD + 1, "karta: środkowy przycisk")
	assert_eq(Hud.target_at(first, VIEW, b.y, false, true), T.NONE, "przy otwartej karcie kolumna nie działa")
	return true


func test_age_and_year_follow_manor() -> bool:
	assert_eq(Ages.year(0, 1), 550, "epoka I zaczyna się w 550")
	assert_eq(Ages.year(0, 5), 750, "dwór 5: 750")
	assert_eq(Ages.label(0, 2), "Epoka I · 600 r.", "napis")
	assert_eq(Hud.top_right_text("", "Epoka I · 550 r."), "Epoka I · 550 r.", "bez budowy tylko epoka")
	assert_eq(Hud.top_right_text("0:05", "Epoka I · 550 r."), "0:05  Epoka I · 550 r.", "z budową")
	return true


## Główna kolumna (#150): wąskie przyciski z ikoną, każdy cel ≥ 12×12 px, ikona na każdy przycisk
## i pasek celu sięga do samej kolumny.
func test_icon_column_is_narrow() -> bool:
	var b := _bounds(VIEW)
	assert_true(Hud.ICON_BUTTON_SIZE.x >= 12 and Hud.ICON_BUTTON_SIZE.y >= 12, "cel ≥ 12×12 px")
	assert_true(Hud.ICON_BUTTON_SIZE.x < Hud.BUTTON_SIZE.x / 2, "kolumna węższa niż połowa dawnej")
	assert_eq(PixelIcons.MENU.size(), Hud.column_targets(false).size(), "ikona dla każdego przycisku")
	for icon: Array in PixelIcons.MENU:
		assert_eq(icon.size(), PixelIcons.MENU_SIZE, "7 wierszy")
		for row: String in icon:
			assert_eq(row.length(), PixelIcons.MENU_SIZE, "7 znaków w wierszu")
	assert_true(Hud.uses_icons(false) and not Hud.uses_icons(true) and not Hud.uses_icons(false, true),
			"ikony tylko przy oglądaniu zamku")
	assert_eq(Hud.goal_rect(b.x, b.y).end.x, b.y - Hud.ICON_BUTTON_SIZE.x - Hud.BUTTON_GAP, "pasek celu do kolumny")
	assert_eq(Hud.target_at(Vector2(b.y - Hud.ICON_BUTTON_SIZE.x - 2, Hud.column_rect(b.y, 0).get_center().y), VIEW, b.y, false, false),
			T.NONE, "obok wąskiego przycisku jest już mapa")
	return true


## #318: ekrany Generałowie, Władca i Ustawienia przyciemniają widok tylko do dolnego paska, więc
## komunikat (np. po „Wyszkol” generała) jest widoczny, a ich przyciski mieszczą się nad paskiem.
func test_backdrop_leaves_message_bar_visible() -> bool:
	for view: Vector2 in [VIEW, WIDE]:
		var r := Hud.backdrop_rect(view)
		assert_eq(r.position, Vector2.ZERO, "tło od lewego górnego rogu")
		assert_eq(r.size.x, view.x, "tło na całą szerokość")
		assert_eq(r.end.y, view.y - Hud.BAR_H, "tło kończy się nad dolnym paskiem")
		var bottom: Array[Rect2] = [GeneralsPanel.close_rect(view), GeneralsPanel.back_rect(view, Generals.perks_for(2).size()),
				RulerPanel.close_rect(view)]
		for s: int in [SettingsPanel.Screen.SETTINGS, SettingsPanel.Screen.CONFIRM]:
			bottom.append_array(SettingsPanel.button_rects(view, s))
		bottom.append(Rect2(0, view.y - SettingsPanel.FOOTER_Y, view.x, 20))  # stopka: sieć i wersja
		for b: Rect2 in bottom:
			assert_true(r.encloses(b), "przycisk %s nad dolnym paskiem" % b)
	return true
