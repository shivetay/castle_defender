class_name PanZoomCamera
extends Camera2D
## Kamera widoku zamku: przeciągnięcie jednym palcem przesuwa, szczypanie zmienia zoom
## (0,5×, 1×, 2×, 4×), kółko myszy działa jak szczypanie. Pozycja jest zawsze w całych pikselach
## świata (przy 0,5× w parzystych, żeby piksel ekranu trafiał zawsze w ten sam piksel świata), a kamera
## nie wychodzi poza mapę. Krótkie dotknięcie bez ruchu emituje `tapped`.
## 0,5× to wyjątek od zasady ostrych pikseli (decyzja właściciela po teście na telefonie): widać
## 4× więcej zamku, ale co drugi piksel grafiki znika.
@warning_ignore_start("integer_division")

signal tapped(world_pos: Vector2)

## Poziomy zoomu w procentach (50 = 0,5×).
const ZOOMS: Array[int] = [50, 100, 200, 400]
## Ruch palca (w pikselach logicznych), po którym dotknięcie staje się przeciąganiem.
const TAP_SLOP := 4.0
## Zmiana odległości palców, po której zoom przeskakuje o jeden poziom.
const PINCH_STEP := 1.4

var world_size := Vector2i(512, 512)
var zoom_level := 100
## Rozmiar widoku podany z zewnątrz (testy bez drzewa sceny). Zero oznacza rozmiar viewportu.
var view_size_override := Vector2.ZERO

var _center := Vector2.ZERO
var _touches: Dictionary[int, Vector2] = {}
var _press_pos := Vector2.ZERO
var _dragging := false
var _multi_touch := false
var _pinch_dist := 0.0


func _ready() -> void:
	position_smoothing_enabled = false
	_apply()


## Ustawia środek widoku (w pikselach świata) z uwzględnieniem granic mapy.
func look_at_world(p: Vector2) -> void:
	_center = p
	_apply()


func set_zoom_level(level: int, anchor_screen: Vector2) -> void:
	if level == zoom_level:
		return
	var anchor_world := screen_to_world(anchor_screen)
	zoom_level = level
	# punkt pod palcami zostaje na miejscu
	_center = anchor_world - (anchor_screen - _view_size() * 0.5) / scale_of(zoom_level)
	_apply()


func screen_to_world(p: Vector2) -> Vector2:
	return position + (p - _view_size() * 0.5) / scale_of(zoom_level)


## Skala ekranu dla poziomu w procentach (100 = 1×).
static func scale_of(level: int) -> float:
	return level / 100.0


## Następny dozwolony poziom zoomu w kierunku `dir` (+1 bliżej, -1 dalej).
static func step_zoom(level: int, dir: int) -> int:
	var i := clampi(ZOOMS.find(level) + dir, 0, ZOOMS.size() - 1)
	return ZOOMS[i]


## Środek widoku przycięty tak, żeby kamera nie pokazywała nic poza mapą. Gdy mapa jest
## mniejsza niż widok w danej osi, kamera staje na jej środku.
static func clamp_center(center: Vector2, view: Vector2, level: int, world: Vector2i) -> Vector2i:
	var half := view / scale_of(level) * 0.5
	# przy pomniejszeniu krok środka to tyle pikseli świata, ile mieści się w pikselu ekranu
	var step := maxi(1, 100 / level)
	var out := Vector2i.ZERO
	for axis in 2:
		if half[axis] * 2.0 >= world[axis]:
			out[axis] = world[axis] / 2 / step * step
		else:
			# ceil/floor zamiast round: krawędź widoku nigdy nie wystaje poza mapę o pół piksela
			var lo := ceili(half[axis] / step) * step
			var hi := floori((world[axis] - half[axis]) / step) * step
			out[axis] = clampi(roundi(center[axis] / step) * step, lo, hi)
	return out


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		_on_touch(event as InputEventScreenTouch)
	elif event is InputEventScreenDrag:
		_on_drag(event as InputEventScreenDrag)
	elif event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.pressed and mb.button_index == MOUSE_BUTTON_WHEEL_UP:
			set_zoom_level(step_zoom(zoom_level, 1), mb.position)
		elif mb.pressed and mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			set_zoom_level(step_zoom(zoom_level, -1), mb.position)


func _on_touch(e: InputEventScreenTouch) -> void:
	if e.pressed:
		_touches[e.index] = e.position
		if _touches.size() == 1:
			_press_pos = e.position
			_dragging = false
			_multi_touch = false
		else:
			_multi_touch = true
			_pinch_dist = _finger_distance()
		return
	_touches.erase(e.index)
	if _touches.is_empty():
		if not _dragging and not _multi_touch:
			tapped.emit(screen_to_world(e.position))
	elif _touches.size() == 1:
		# po szczypaniu pozostały palec od razu przesuwa kamerę; _dragging = true, żeby
		# podniesienie go bez ruchu nie zostało uznane za tap (nie stawia budynku)
		_multi_touch = false
		_dragging = true
		_press_pos = _touches.values()[0] as Vector2
		_pinch_dist = 0.0


func _on_drag(e: InputEventScreenDrag) -> void:
	if not _touches.has(e.index):
		return
	_touches[e.index] = e.position
	if _touches.size() >= 2:
		_on_pinch()
		return
	if not _dragging and e.position.distance_to(_press_pos) > TAP_SLOP:
		_dragging = true
	if _dragging and not _multi_touch:
		_center -= e.relative / scale_of(zoom_level)
		_apply()


func _on_pinch() -> void:
	var d := _finger_distance()
	if _pinch_dist <= 0.0:
		_pinch_dist = d
		return
	var dir := 0
	if d > _pinch_dist * PINCH_STEP:
		dir = 1
	elif d < _pinch_dist / PINCH_STEP:
		dir = -1
	if dir != 0:
		_pinch_dist = d
		set_zoom_level(step_zoom(zoom_level, dir), _finger_midpoint())


func _finger_distance() -> float:
	var pts := _touches.values()
	return (pts[0] as Vector2).distance_to(pts[1] as Vector2)


func _finger_midpoint() -> Vector2:
	var pts := _touches.values()
	return ((pts[0] as Vector2) + (pts[1] as Vector2)) * 0.5


func _view_size() -> Vector2:
	if view_size_override != Vector2.ZERO:
		return view_size_override
	return get_viewport_rect().size


func _apply() -> void:
	var c := clamp_center(_center, _view_size(), zoom_level, world_size)
	# akumulator też się przycina, żeby po dojechaniu do krawędzi kamera od razu ruszała z powrotem
	_center = _center.clamp(Vector2(c) - Vector2(0.5, 0.5), Vector2(c) + Vector2(0.5, 0.5))
	position = Vector2(c)
	zoom = Vector2(scale_of(zoom_level), scale_of(zoom_level))
