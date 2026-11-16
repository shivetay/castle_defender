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
	for label: String in [Hud.BUILD_LABEL, Hud.RESEARCH_LABEL, Hud.ARMY_LABEL, Hud.SIEGE_LABEL, Hud.DONE_LABEL,
			Hud.CHANGE_LABEL, "Zamknij", "Rozbierz", "Ulepsz", "Postaw", "Szkol", "Badaj"]:
		assert_true(PixelFont.text_width(label) <= Hud.BUTTON_SIZE.x - 2, "„%s” mieści się na przycisku" % label)
	return true


## Przyciski trybów w kolumnie przy prawej krawędzi, od góry, pod górnym paskiem i nad dolnym.
func test_column_buttons_stack_on_the_right() -> bool:
	for view: Vector2 in [VIEW, WIDE]:
		var b := _bounds(view)
		for building: bool in [false, true]:
			var n := Hud.column_targets(building).size()
			for i in n:
				var r := Hud.column_rect(b.y, i)
				assert_eq(r.end.x, b.y, "przy prawej granicy treści")
				assert_true(r.position.y >= Hud.BAR_H, "pod górnym paskiem")
				assert_true(r.end.y <= view.y - Hud.BAR_H, "nad paskiem komunikatu")
				if i > 0:
					assert_true(r.position.y > Hud.column_rect(b.y, i - 1).end.y, "od góry, bez nakładania")
	assert_eq(Hud.column_targets(false), [T.BUILD, T.RESEARCH, T.ARMY, T.SIEGE] as Array[int], "oglądanie: kolejność")
	assert_eq(Hud.column_targets(true), [T.DONE, T.CHANGE] as Array[int], "budowa: Gotowe i Zmień")
	assert_eq(Hud.column_targets(false, true), [T.SPEED1, T.SPEED2, T.SPEED4] as Array[int], "bitwa: tylko tempo")
	return true


func test_targets_follow_mode() -> bool:
	var b := _bounds(VIEW)
	var first := Hud.column_rect(b.y, 0).get_center()
	var second := Hud.column_rect(b.y, 1).get_center()
	var fourth := Hud.column_rect(b.y, 3).get_center()
	assert_eq(Hud.target_at(first, VIEW, b.y, false, false), T.BUILD, "oglądanie: Buduj na górze")
	assert_eq(Hud.target_at(second, VIEW, b.y, false, false), T.RESEARCH, "oglądanie: Badania")
	assert_eq(Hud.target_at(Hud.column_rect(b.y, 2).get_center(), VIEW, b.y, false, false), T.ARMY, "oglądanie: Wojsko")
	assert_eq(Hud.target_at(fourth, VIEW, b.y, false, false), T.SIEGE, "oglądanie: Oblężenie")
	assert_eq(Hud.target_at(first, VIEW, b.y, true, false), T.DONE, "budowa: w tym samym miejscu Gotowe")
	assert_eq(Hud.target_at(second, VIEW, b.y, true, false), T.CHANGE, "budowa: Zmień")
	assert_eq(Hud.target_at(fourth, VIEW, b.y, true, false), T.NONE, "budowa: tylko dwa przyciski")
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
