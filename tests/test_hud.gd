extends TestCase
## HUD z #9: cele dotyku, rozkład przycisków w trybie oglądania i budowy, przewijanie paska
## budynków oraz epoka i rok.

const VIEW := Vector2(320, 180)
const WIDE := Vector2(400, 180)
const T := Hud.Target


func _bounds(view: Vector2) -> Vector2:
	return Hud.content_bounds(view, Rect2())


## Kryterium #9: interfejs jednym kciukiem, cele dotyku co najmniej 48 dp. Przycisk ma 22 px
## logicznych; przy skali 6 i 420 dpi (typowy telefon) to 22 · 6 / 2,625 ≈ 50 dp.
func test_touch_targets_are_big_enough() -> bool:
	var dp := Hud.BUTTON_SIZE.y * 6.0 / (420.0 / 160.0)
	assert_true(dp >= 48.0, "wysokość przycisku ≥ 48 dp (jest %.1f)" % dp)
	assert_true(Hud.BUTTON_SIZE.x >= Hud.BUTTON_SIZE.y, "przycisk nie węższy niż wysoki")
	return true


func test_corner_buttons_stay_inside_and_apart() -> bool:
	for view: Vector2 in [VIEW, WIDE]:
		var b := _bounds(view)
		var siege := Hud.left_corner_rect(view, b.x)
		var build := Hud.right_corner_rect(view, b.y)
		assert_true(siege.position.x >= Hud.CORNER_INSET and build.end.x <= view.x - Hud.CORNER_INSET, "z dala od narożników")
		assert_true(not siege.intersects(build), "Oblężenie i Buduj się nie nakładają")
		assert_true(build.end.y <= view.y - Hud.BAR_H, "nad paskiem komunikatu")
		assert_true(build.position.y >= view.y / 2.0, "w dolnej połowie, pod kciukiem")
	return true


func test_targets_follow_mode() -> bool:
	var b := _bounds(VIEW)
	var build := Hud.right_corner_rect(VIEW, b.y).get_center()
	var siege := Hud.left_corner_rect(VIEW, b.x).get_center()
	assert_eq(Hud.target_at(build, VIEW, b.x, b.y, false, false, 0), T.BUILD, "oglądanie: Buduj")
	assert_eq(Hud.target_at(siege, VIEW, b.x, b.y, false, false, 0), T.SIEGE, "oglądanie: Oblężenie")
	assert_eq(Hud.target_at(build, VIEW, b.x, b.y, true, false, 0), T.DONE, "budowa: w tym samym miejscu Gotowe")
	var kinds := Hud.kind_rects(VIEW, b.x, b.y, 1)
	assert_eq(Hud.target_at(kinds[0].get_center(), VIEW, b.x, b.y, true, false, 1), T.KIND + 1, "przewinięty pasek: pierwszy widoczny to rodzaj 1")
	assert_eq(Hud.target_at(Vector2(160, 90), VIEW, b.x, b.y, true, false, 0), T.NONE, "mapa to nie przycisk")
	var card := Hud.card_rects(VIEW)
	assert_eq(Hud.target_at(card[1].get_center(), VIEW, b.x, b.y, false, true, 0), T.CARD + 1, "karta: środkowy przycisk")
	assert_eq(Hud.target_at(siege, VIEW, b.x, b.y, false, true, 0), T.NONE, "przy otwartej karcie rogi nie działają")
	return true


func test_build_bar_scrolls_to_every_kind() -> bool:
	for view: Vector2 in [VIEW, WIDE]:
		var b := _bounds(view)
		var done := Hud.right_corner_rect(view, b.y)
		var seen := {}
		for first in range(0, Hud.max_first_kind(b.x, b.y) + 1):
			var rects := Hud.kind_rects(view, b.x, b.y, first)
			for i in rects.size():
				assert_true(not rects[i].intersects(done), "rodzaj nie nachodzi na Gotowe")
				assert_true(rects[i].position.x >= b.x, "rodzaj w granicach treści")
				seen[first + i] = true
		assert_eq(seen.size(), BuildingTypes.buildable_count(), "każdy rodzaj da się wybrać (%d px)" % int(view.x))
	assert_true(Hud.max_first_kind(_bounds(VIEW).x, _bounds(VIEW).y) > 0, "na 320 px pasek się przewija")
	return true


func test_age_and_year_follow_manor() -> bool:
	assert_eq(Ages.year(0, 1), 550, "epoka I zaczyna się w 550")
	assert_eq(Ages.year(0, 5), 750, "dwór 5: 750")
	assert_eq(Ages.label(0, 2), "Epoka I · 600 r.", "napis")
	assert_eq(Hud.top_right_text("", "Epoka I · 550 r."), "Epoka I · 550 r.", "bez budowy tylko epoka")
	assert_eq(Hud.top_right_text("0:05", "Epoka I · 550 r."), "0:05  Epoka I · 550 r.", "z budową")
	return true
