class_name PushPrompt
extends Node2D
## Okienko zgody na powiadomienia (#30, ADR 0012) przy pierwszym wejściu na Wyprawę. Dopiero „Tak”
## otwiera systemowe pytanie Androida. „Nie teraz” odkłada pytanie o 7 dni. Okno samo obsługuje dotyk.

signal answered(yes: bool)

const SIZE := Vector2(220, 68)
const BUTTON := Vector2(64, 16)
const TITLE := "Powiadomienia"
const QUESTION := "Chcesz wiedzieć, gdy ktoś zaatakuje Twój zamek?"
const YES_LABEL := "Tak"
const LATER_LABEL := "Nie teraz"
const YES := 0
const LATER := 1

var lines: PackedStringArray = []
var _pressed := -1


func _init() -> void:
	visible = false


func open() -> void:
	lines = PixelFont.wrap(QUESTION, int(SIZE.x) - 8)
	_pressed = -1
	visible = true
	queue_redraw()


func choose(t: int) -> void:
	if t != YES and t != LATER:
		return
	visible = false
	answered.emit(t == YES)


static func panel_rect(view: Vector2) -> Rect2:
	return Rect2(((view - SIZE) / 2.0).floor(), SIZE)


static func yes_rect(view: Vector2) -> Rect2:
	var p := panel_rect(view)
	return Rect2(Vector2(floorf(p.get_center().x) - BUTTON.x - 4, p.end.y - BUTTON.y - 6), BUTTON)


static func later_rect(view: Vector2) -> Rect2:
	var p := panel_rect(view)
	return Rect2(Vector2(floorf(p.get_center().x) + 4, p.end.y - BUTTON.y - 6), BUTTON)


## Cel pod punktem: YES, LATER albo -1.
static func target_at(p: Vector2, view: Vector2) -> int:
	if yes_rect(view).has_point(p):
		return YES
	if later_rect(view).has_point(p):
		return LATER
	return -1


func _input(event: InputEvent) -> void:
	if not visible:
		return
	if event is InputEventScreenDrag:
		get_viewport().set_input_as_handled()
		return
	var touch := event as InputEventScreenTouch
	if touch == null:
		return
	get_viewport().set_input_as_handled()
	var on := target_at(touch.position, get_viewport_rect().size)
	if touch.pressed:
		_pressed = on
		queue_redraw()
		return
	var was := _pressed
	_pressed = -1
	queue_redraw()
	if was == on and was != -1:
		choose(was)


func _draw() -> void:
	var view := get_viewport_rect().size
	draw_rect(Rect2(Vector2.ZERO, view), Color(Palette.SHADOW, 0.6))
	var p := panel_rect(view)
	draw_rect(p, Color(Palette.SHADOW, 0.95))
	CastleView.draw_frame(self, Rect2i(p), Palette.WOOD[2])
	PixelFont.draw_centered(self, Rect2(p.position.x, p.position.y + 5, p.size.x, 10), TITLE, Palette.THATCH[2])
	for i in mini(lines.size(), 3):
		PixelFont.draw_text(self, Vector2(p.position.x + 4, p.position.y + 17 + i * PixelFont.LINE), lines[i], Palette.INK)
	Hud.paint_button(self, yes_rect(view), YES_LABEL, _pressed == YES, false)
	Hud.paint_button(self, later_rect(view), LATER_LABEL, _pressed == LATER, false)
