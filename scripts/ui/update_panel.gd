class_name UpdatePanel
extends Node2D
## Okno aktualizacji gry (#336, ADR 0005), nad wszystkim innym, także nad zasłoną ładowania.
## SOFT: komunikat o nowej wersji na przyciemnionym zamku; Aktualizuj otwiera sklep, Później zamyka.
## HARD: pełny ekran blokady; Aktualizuj otwiera sklep, Sprawdź ponownie pyta serwer jeszcze raz.
## Blokady nie da się zamknąć. Okno samo obsługuje dotyk, więc nic nie trafia do kamery ani do HUD.

signal update_pressed
signal later_pressed
signal retry_pressed

enum Mode { HIDDEN, SOFT, HARD }
enum Target { NONE = -1, UPDATE, LATER, RETRY }

const BUTTON_SIZE := Vector2(104, 16)
const GAP := 4
const TITLE_Y := 30
const TEXT_Y := 46
const TITLES := {
	Mode.SOFT: "NOWA WERSJA",
	Mode.HARD: "WYMAGANA AKTUALIZACJA",
}
const SOFT_LINES: Array[String] = [
	"Jest nowa wersja gry.",
	"Zaktualizuj ją w sklepie, żeby grać",
	"z innymi na tych samych zasadach.",
]
const HARD_LINES: Array[String] = [
	"Ta wersja gry jest już za stara.",
	"Zaktualizuj grę w sklepie,",
	"żeby grać dalej.",
]
const LABELS := {
	Target.UPDATE: "Aktualizuj",
	Target.LATER: "Później",
	Target.RETRY: "Sprawdź ponownie",
}

var mode: int = Mode.HIDDEN
## Tekst pod przyciskami, np. „Sklep się nie otworzył” albo „Brak połączenia”.
var note := ""

var _pressed: int = Target.NONE


func _ready() -> void:
	visible = mode != Mode.HIDDEN


func open(new_mode: int) -> void:
	mode = new_mode
	visible = mode != Mode.HIDDEN
	_pressed = Target.NONE
	note = ""
	queue_redraw()


func set_note(text: String) -> void:
	note = text
	queue_redraw()


static func lines_for(m: int) -> Array[String]:
	return HARD_LINES if m == Mode.HARD else SOFT_LINES


static func targets(m: int) -> Array[int]:
	if m == Mode.HARD:
		return [Target.UPDATE, Target.RETRY] as Array[int]
	return [Target.UPDATE, Target.LATER] as Array[int]


## Przyciski wyśrodkowane w poziomie, jeden pod drugim, pod tekstem (całe piksele).
static func button_rects(view: Vector2, m: int) -> Array[Rect2]:
	var out: Array[Rect2] = []
	var x := floorf((view.x - BUTTON_SIZE.x) / 2.0)
	var y := float(TEXT_Y + (lines_for(m).size() + 1) * PixelFont.LINE + 4)
	for i in targets(m).size():
		out.append(Rect2(Vector2(x, y + i * (BUTTON_SIZE.y + GAP)), BUTTON_SIZE))
	return out


static func target_at(p: Vector2, view: Vector2, m: int) -> int:
	var i := Hud.hit(button_rects(view, m), p)
	return targets(m)[i] if i >= 0 else Target.NONE


func activate(t: int) -> void:
	if t == Target.NONE or not targets(mode).has(t):
		return
	match t:
		Target.UPDATE:
			update_pressed.emit()
		Target.LATER:
			open(Mode.HIDDEN)
			later_pressed.emit()
		Target.RETRY:
			retry_pressed.emit()


func _input(event: InputEvent) -> void:
	if not visible:
		return
	if event is InputEventScreenDrag or (event is InputEventMouse and not event is InputEventScreenTouch):
		get_viewport().set_input_as_handled()
		return
	var touch := event as InputEventScreenTouch
	if touch == null:
		return
	get_viewport().set_input_as_handled()
	var t := target_at(touch.position, get_viewport_rect().size, mode)
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
	if mode == Mode.HIDDEN:
		return
	var view := get_viewport_rect().size
	draw_rect(Rect2(Vector2.ZERO, view), Palette.SHADOW if mode == Mode.HARD else Color(Palette.SHADOW, 0.85))
	PixelFont.draw_centered(self, Rect2(0, TITLE_Y, view.x, 10), TITLES[mode] as String, Palette.THATCH[2])
	draw_rect(Rect2(floorf(view.x / 2.0) - 30, TITLE_Y + 12, 60, 1), Palette.WOOD[2])
	var lines := lines_for(mode)
	for i in lines.size():
		PixelFont.draw_centered(self, Rect2(0, TEXT_Y + i * PixelFont.LINE, view.x, 10), lines[i], Palette.INK)
	var rects := button_rects(view, mode)
	var ts := targets(mode)
	for i in rects.size():
		Hud.paint_button(self, rects[i], LABELS[ts[i]] as String, _pressed == ts[i], false)
	var bottom := rects[-1].end.y + 4
	if not note.is_empty():
		PixelFont.draw_centered(self, Rect2(0, bottom, view.x, 10), note, Palette.THATCH[2])
		bottom += PixelFont.LINE
	PixelFont.draw_centered(self, Rect2(0, bottom, view.x, 10), SettingsPanel.version_text(), Palette.WOOD[3])
