extends TestCase
## Kamera: zoom tylko 1×/2×/4× i granice mapy w całych pikselach.

const WORLD := Vector2i(512, 512)
const VIEW := Vector2(320, 180)


func test_zoom_steps() -> bool:
	assert_eq(PanZoomCamera.step_zoom(1, 1), 2, "1× → 2×")
	assert_eq(PanZoomCamera.step_zoom(2, 1), 4, "2× → 4×")
	assert_eq(PanZoomCamera.step_zoom(4, 1), 4, "4× to maksimum")
	assert_eq(PanZoomCamera.step_zoom(4, -1), 2, "4× → 2×")
	assert_eq(PanZoomCamera.step_zoom(1, -1), 1, "1× to minimum")
	return true


func test_clamp_keeps_view_inside_map() -> bool:
	assert_eq(PanZoomCamera.clamp_center(Vector2(-50, -50), VIEW, 1, WORLD), Vector2i(160, 90), "lewy górny róg, 1×")
	assert_eq(PanZoomCamera.clamp_center(Vector2(9999, 9999), VIEW, 1, WORLD), Vector2i(352, 422), "prawy dolny róg, 1×")
	assert_eq(PanZoomCamera.clamp_center(Vector2(0, 0), VIEW, 4, WORLD), Vector2i(40, 23), "lewy górny róg, 4×")
	assert_eq(PanZoomCamera.clamp_center(Vector2(256.4, 300.6), VIEW, 2, WORLD), Vector2i(256, 301), "środek zaokrąglony do piksela")
	# 180 / 4 / 2 = 22,5 px: dół widoku musi zostać na mapie
	assert_eq(PanZoomCamera.clamp_center(Vector2(9999, 9999), VIEW, 4, WORLD), Vector2i(472, 489), "prawy dolny róg, 4×")
	return true


func test_small_world_is_centered() -> bool:
	var small := Vector2i(200, 100)
	assert_eq(PanZoomCamera.clamp_center(Vector2(0, 0), VIEW, 1, small), Vector2i(100, 50), "mapa mniejsza od widoku")
	return true


## Regresja z review #72: po szczypaniu pozostały palec przesuwa kamerę i nie wywołuje tapu.
func test_pan_continues_after_pinch_without_tap() -> bool:
	var cam := PanZoomCamera.new()
	cam.view_size_override = VIEW
	cam.look_at_world(Vector2(256, 256))
	var taps: Array[Vector2] = []
	cam.tapped.connect(func(p: Vector2) -> void: taps.append(p))
	_touch(cam, 0, Vector2(150, 90), true)
	_touch(cam, 1, Vector2(170, 90), true)
	_drag(cam, 1, Vector2(200, 90), Vector2(30, 0))
	assert_eq(cam.zoom_level, 2, "rozsunięcie palców daje zoom 2×")
	_touch(cam, 1, Vector2(200, 90), false)
	var before := cam.position
	_drag(cam, 0, Vector2(130, 90), Vector2(-20, 0))
	assert_eq(cam.position.x - before.x, 10.0, "pozostały palec przesuwa kamerę (20 px / zoom 2)")
	_touch(cam, 0, Vector2(130, 90), false)
	assert_true(taps.is_empty(), "koniec gestu po szczypaniu nie jest tapem")
	_touch(cam, 0, Vector2(160, 90), true)
	_touch(cam, 0, Vector2(160, 90), false)
	assert_eq(taps.size(), 1, "zwykły tap działa dalej")
	cam.free()
	return true


func _touch(cam: PanZoomCamera, index: int, pos: Vector2, pressed: bool) -> void:
	var e := InputEventScreenTouch.new()
	e.index = index
	e.position = pos
	e.pressed = pressed
	cam._unhandled_input(e)


func _drag(cam: PanZoomCamera, index: int, pos: Vector2, rel: Vector2) -> void:
	var e := InputEventScreenDrag.new()
	e.index = index
	e.position = pos
	e.relative = rel
	cam._unhandled_input(e)
