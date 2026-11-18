class_name InfoPopup
extends Control
## Okienko z informacją nad całym ekranem (po teście na telefonie): tytuł, linie tekstu łamane na
## szerokość okienka i podpowiedź „Dotknij, aby zamknąć”. Otwarte łapie wszystkie dotknięcia,
## a puszczenie palca je zamyka. Treść liczy InfoText.

signal closed

## Szerokość okienka w pikselach logicznych (mieści się między zaokrąglonymi rogami ekranu 320 px).
const WIDTH := 260
const PAD := 4
const HINT := "Dotknij, aby zamknąć"

var title := ""
var lines: PackedStringArray = []


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false


func open(new_title: String, new_lines: PackedStringArray) -> void:
	title = new_title
	lines = wrapped(new_lines)
	# bezpiecznik: nadmiar linii nie wypycha okienka poza paski (treść z InfoText mieści się dużo niżej)
	var room := max_lines(get_viewport_rect().size if is_inside_tree() else Vector2(320, 180))
	if lines.size() > room:
		lines = lines.slice(0, room)
	visible = true
	queue_redraw()


func close() -> void:
	if not visible:
		return
	visible = false
	closed.emit()


## Linie złamane na szerokość treści okienka (bez ucinania).
static func wrapped(src: PackedStringArray) -> PackedStringArray:
	var out: PackedStringArray = []
	for line in src:
		for part in PixelFont.wrap(line, WIDTH - 2 * PAD):
			out.append(part)
	return out


## Najwięcej linii treści, przy których okienko mieści się między górnym a dolnym paskiem HUD.
static func max_lines(view: Vector2) -> int:
	@warning_ignore("integer_division")
	return maxi(1, (int(view.y) - 2 * Hud.BAR_H - _frame_h()) / PixelFont.LINE)


static func _frame_h() -> int:
	return PAD + 10 + 3 + PixelFont.LINE + PAD


## Prostokąt okienka z `count` liniami (najwyżej max_lines), wyśrodkowany na ekranie `view`.
static func box_rect(view: Vector2, count: int) -> Rect2:
	var h := _frame_h() + mini(count, max_lines(view)) * PixelFont.LINE
	return Rect2(floorf((view.x - WIDTH) / 2.0), floorf((view.y - h) / 2.0), WIDTH, h)


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
	if not touch.pressed:
		close()


func _draw() -> void:
	var view := get_viewport_rect().size
	draw_rect(Rect2(Vector2.ZERO, view), Color(Palette.SHADOW, 0.5))
	var r := box_rect(view, lines.size())
	draw_rect(r, Color(Palette.SHADOW, 0.95))
	CastleView.draw_frame(self, Rect2i(r), Palette.WOOD[2])
	PixelFont.draw_text(self, r.position + Vector2(PAD, PAD), title, Palette.INK)
	for i in lines.size():
		PixelFont.draw_text(self, r.position + Vector2(PAD, PAD + 10 + i * PixelFont.LINE), lines[i], Palette.WOOD[3])
	PixelFont.draw_centered(self, Rect2(r.position.x, r.end.y - PAD - PixelFont.LINE, r.size.x, PixelFont.LINE),
			HINT, Palette.WOOD[2])
