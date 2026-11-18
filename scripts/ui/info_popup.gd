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


## Prostokąt okienka z `count` liniami, wyśrodkowany na ekranie `view`.
static func box_rect(view: Vector2, count: int) -> Rect2:
	var h := PAD + 10 + count * PixelFont.LINE + 3 + PixelFont.LINE + PAD
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
