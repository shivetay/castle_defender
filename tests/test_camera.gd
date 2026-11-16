extends TestCase
## Kamera: zoom 0,5×/1×/2×/4× (w procentach) i granice mapy w całych pikselach.

const WORLD := Vector2i(512, 512)
const VIEW := Vector2(320, 180)


func test_zoom_steps() -> bool:
	assert_eq(PanZoomCamera.step_zoom(100, 1), 200, "1× → 2×")
	assert_eq(PanZoomCamera.step_zoom(200, 1), 400, "2× → 4×")
	assert_eq(PanZoomCamera.step_zoom(400, 1), 400, "4× to maksimum")
	assert_eq(PanZoomCamera.step_zoom(400, -1), 200, "4× → 2×")
	assert_eq(PanZoomCamera.step_zoom(100, -1), 50, "1× → 0,5× (dodatkowe oddalenie)")
	assert_eq(PanZoomCamera.step_zoom(50, -1), 50, "0,5× to minimum")
	return true


func test_clamp_keeps_view_inside_map() -> bool:
	assert_eq(PanZoomCamera.clamp_center(Vector2(-50, -50), VIEW, 100, WORLD), Vector2i(160, 90), "lewy górny róg, 1×")
	assert_eq(PanZoomCamera.clamp_center(Vector2(9999, 9999), VIEW, 100, WORLD), Vector2i(352, 422), "prawy dolny róg, 1×")
	assert_eq(PanZoomCamera.clamp_center(Vector2(0, 0), VIEW, 400, WORLD), Vector2i(40, 23), "lewy górny róg, 4×")
	assert_eq(PanZoomCamera.clamp_center(Vector2(256.4, 300.6), VIEW, 200, WORLD), Vector2i(256, 301), "środek zaokrąglony do piksela")
	# 180 / 4 / 2 = 22,5 px: dół widoku musi zostać na mapie
	assert_eq(PanZoomCamera.clamp_center(Vector2(9999, 9999), VIEW, 400, WORLD), Vector2i(472, 489), "prawy dolny róg, 4×")
	return true


## 0,5×: widok obejmuje 640×360 px świata, środek w parzystych pikselach, mapa w całości w poziomie.
func test_half_zoom_shows_more_and_snaps_to_even_pixels() -> bool:
	var c := PanZoomCamera.clamp_center(Vector2(101, 101), VIEW, 50, WORLD)
	assert_eq(c.x, 256, "mapa 512 px węższa niż widok 640 px: środek mapy")
	assert_eq(c.y, 180, "góra widoku przy krawędzi mapy (360 / 2)")
	var mid := PanZoomCamera.clamp_center(Vector2(255, 301), VIEW, 50, Vector2i(2048, 2048))
	assert_eq(mid.x % 2, 0, "x parzyste")
	assert_eq(mid.y % 2, 0, "y parzyste")
	assert_eq(PanZoomCamera.scale_of(50), 0.5, "skala 0,5")
	return true


func test_small_world_is_centered() -> bool:
	var small := Vector2i(200, 100)
	assert_eq(PanZoomCamera.clamp_center(Vector2(0, 0), VIEW, 100, small), Vector2i(100, 50), "mapa mniejsza od widoku")
	return true


## Review #159: przy 0,5× wolne przesuwanie (drobne ruchy palca albo myszy) też rusza kamerę.
func test_slow_pan_moves_camera_at_half_zoom() -> bool:
	var cam := PanZoomCamera.new()
	cam.view_size_override = VIEW
	cam.world_size = Vector2i(2048, 2048)
	cam.look_at_world(Vector2(1024, 1024))
	cam.set_zoom_level(50, VIEW * 0.5)
	var start := cam.position
	_touch(cam, 0, Vector2(160, 90), true)
	var x := 160.0
	for i in 40:
		x -= 0.2
		_drag(cam, 0, Vector2(x, 90), Vector2(-0.2, 0))
	_touch(cam, 0, Vector2(x, 90), false)
	assert_true(cam.position.x > start.x, "kamera ruszyła się przy ruchach po 0,2 px (było %d, jest %d)" % [start.x, cam.position.x])
	assert_eq(int(cam.position.x) % 2, 0, "dalej w parzystych pikselach")
	cam.free()
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
	assert_eq(cam.zoom_level, 200, "rozsunięcie palców daje zoom 2×")
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
