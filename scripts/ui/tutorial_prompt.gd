class_name TutorialPrompt
extends Node2D
## Okno z pytaniem o samouczek (#251) na przyciemnionym zamku: pojawia się raz, po onboardingu (albo
## przy pierwszym uruchomieniu nowej wersji), dopóki gracz nie odpowie. „Prowadź” zostawia cele
## i podświetlenia, „Wyłącz” chowa je. Wybór trafia do profilu, a zmienić go można w Ustawieniach.
## Okno samo obsługuje dotyk, więc nic nie trafia do kamery ani do HUD.

## `keep`: gracz zostawił samouczek włączony.
signal answered(keep: bool)

enum Target { NONE = -1, KEEP, TURN_OFF }

const BUTTON_SIZE := Vector2(96, 16)
const GAP := 4
const TEXT_Y := 40
const LINES: Array[String] = [
	"Samouczek podświetli, co dotknąć,",
	"żeby postawić Koszary i wyszkolić",
	"pierwszych żołnierzy.",
]
const QUESTION := "Wyłączyć samouczek?"
const LABELS := {
	Target.KEEP: "Nie, prowadź",
	Target.TURN_OFF: "Tak, wyłącz",
}
const LATER_NOTE := "Zmienisz to w Ustawieniach"

var _pressed: int = Target.NONE


func open() -> void:
	visible = true
	_pressed = Target.NONE
	queue_redraw()


static func targets() -> Array[int]:
	return [Target.KEEP, Target.TURN_OFF] as Array[int]


static func question_y() -> int:
	return TEXT_Y + LINES.size() * PixelFont.LINE + 4


## Przyciski wyśrodkowane w poziomie, jeden pod drugim, pod pytaniem (całe piksele).
static func button_rects(view: Vector2) -> Array[Rect2]:
	var out: Array[Rect2] = []
	var x := floorf((view.x - BUTTON_SIZE.x) / 2.0)
	var y := question_y() + PixelFont.LINE + 6
	for i in targets().size():
		out.append(Rect2(Vector2(x, y + i * (BUTTON_SIZE.y + GAP)), BUTTON_SIZE))
	return out


static func target_at(p: Vector2, view: Vector2) -> int:
	var i := Hud.hit(button_rects(view), p)
	return targets()[i] if i >= 0 else Target.NONE


func activate(t: int) -> void:
	if t == Target.NONE:
		return
	visible = false
	answered.emit(t == Target.KEEP)


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
	var t := target_at(touch.position, get_viewport_rect().size)
	if touch.pressed:
		_pressed = t
		queue_redraw()
		return
	var was := _pressed
	_pressed = Target.NONE
	queue_redraw()
	if was != Target.NONE and t == was:
		activate(was)


func _draw() -> void:
	var view := get_viewport_rect().size
	draw_rect(Rect2(Vector2.ZERO, view), Color(Palette.SHADOW, 0.85))
	PixelFont.draw_centered(self, Rect2(0, 24, view.x, 10), "SAMOUCZEK", Palette.THATCH[2])
	draw_rect(Rect2(floorf(view.x / 2.0) - 30, 36, 60, 1), Palette.WOOD[2])
	for i in LINES.size():
		PixelFont.draw_centered(self, Rect2(0, TEXT_Y + i * PixelFont.LINE, view.x, 10), LINES[i], Palette.INK)
	PixelFont.draw_centered(self, Rect2(0, question_y(), view.x, 10), QUESTION, Palette.THATCH[2])
	var rects := button_rects(view)
	var ts := targets()
	for i in rects.size():
		Hud.paint_button(self, rects[i], LABELS[ts[i]] as String, _pressed == ts[i], false)
	PixelFont.draw_centered(self, Rect2(0, rects[-1].end.y + 4, view.x, 10), LATER_NOTE, Palette.WOOD[3])
