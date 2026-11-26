class_name DefenseNotice
extends Node2D
## Okienko po połączeniu z serwerem (#328): ktoś zaatakował zamek od ostatniego obejrzenia Historii.
## Tekst mówi, ile ataków było i ile z nich odparto. Historia otwiera listę obron, OK tylko zamyka
## (kropka nad Obroną gaśnie dopiero po otwarciu Historii). Okno samo obsługuje dotyk.
@warning_ignore_start("integer_division")

signal history_requested
signal closed

const SIZE := Vector2(220, 68)
const BUTTON := Vector2(64, 16)
const TITLE := "Atak na zamek"
const HISTORY_LABEL := "Historia"
const OK_LABEL := "OK"
const HISTORY := 0
const OK := 1

var lines: PackedStringArray = []
var _pressed := -1


func _init() -> void:
	visible = false


func open(text: String) -> void:
	lines = PixelFont.wrap(text, int(SIZE.x) - 8)
	_pressed = -1
	visible = true
	queue_redraw()


func choose(t: int) -> void:
	if t == HISTORY:
		visible = false
		history_requested.emit()
	elif t == OK:
		visible = false
		closed.emit()


## Tekst o nowych obronach, np. „Zaatakowano Cię 3× od ostatniej wizyty (2 odparte, 1 zdobyty)”.
static func text(fresh: Array[DefenseLog.Report]) -> String:
	var lost := 0
	for r in fresh:
		if r.result.won:
			lost += 1
	var held := fresh.size() - lost
	return "Zaatakowano Cię %d× od ostatniej wizyty (%d %s, %d %s)" % [fresh.size(),
			held, _plural(held, "odparty", "odparte", "odpartych"), lost, _plural(lost, "zdobyty", "zdobyte", "zdobytych")]


## Odmiana po liczebniku: 1 → `one`, 2–4 (bez 12–14) → `few`, reszta → `many`.
static func _plural(n: int, one: String, few: String, many: String) -> String:
	if n == 1:
		return one
	if n % 10 >= 2 and n % 10 <= 4 and (n % 100 < 12 or n % 100 > 14):
		return few
	return many


static func panel_rect(view: Vector2) -> Rect2:
	return Rect2(((view - SIZE) / 2.0).floor(), SIZE)


static func history_rect(view: Vector2) -> Rect2:
	var p := panel_rect(view)
	return Rect2(Vector2(floorf(p.get_center().x) - BUTTON.x - 4, p.end.y - BUTTON.y - 6), BUTTON)


static func ok_rect(view: Vector2) -> Rect2:
	var p := panel_rect(view)
	return Rect2(Vector2(floorf(p.get_center().x) + 4, p.end.y - BUTTON.y - 6), BUTTON)


## Cel pod punktem: HISTORY, OK albo -1.
static func target_at(p: Vector2, view: Vector2) -> int:
	if history_rect(view).has_point(p):
		return HISTORY
	if ok_rect(view).has_point(p):
		return OK
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
	Hud.paint_button(self, history_rect(view), HISTORY_LABEL, _pressed == HISTORY, false)
	Hud.paint_button(self, ok_rect(view), OK_LABEL, _pressed == OK, false)
