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
