class_name SyncLoaderPanel
extends Node2D
## Zasłona ładowania przy synchronizacji z serwerem (#316): pełny ekran w kolorze cienia, kowal
## walący w kowadło (SmithIcon) i zmieniające się teksty klimatyczne. Kiedy się pokazuje i znika, decyduje SyncCurtain.
## Dopóki stoi, łapie każdy dotyk (stoi nad wszystkim, także nad onboardingiem).

## Pozycje tekstów względem środka ekranu (całe piksele).
## Kowal w skali 2× (całkowitej, piksele zostają ostre), żeby był czytelny na telefonie.
const ICON_SCALE := 2
const ICON_DY := -40
const LINE_DY := 4
const RULE_W := 60

var curtain := SyncCurtain.new()

var _frame := -1
var _line := ""


func _ready() -> void:
	visible = curtain.is_visible()


func start_waiting() -> void:
	curtain.start_waiting()
	_refresh()


## Przy przywracaniu scena się przeładowuje, a Godot może pokazać jedną klatkę bez sceny: wtedy
## widać kolor czyszczenia ekranu, więc na ten czas jest nim kolor zasłony (wraca, gdy zasłona zejdzie).
func start_restore() -> void:
	curtain.start_restore()
	RenderingServer.set_default_clear_color(Palette.SHADOW)
	_refresh()


func finish() -> void:
	curtain.finish()


func on_net_state(st: int) -> void:
	curtain.on_net_state(st)


func on_castle_checked() -> void:
	curtain.on_castle_checked()


func _process(delta: float) -> void:
	if not curtain.is_visible():
		return
	if curtain.advance(delta):
		RenderingServer.set_default_clear_color(
				ProjectSettings.get_setting("rendering/environment/defaults/default_clear_color") as Color)
	_refresh()


## Pokazuje albo chowa zasłonę i przerysowuje ją tylko wtedy, gdy zmienił się tekst.
func _refresh() -> void:
	visible = curtain.is_visible()
	if not visible:
		return
	var f := curtain.smith_frame()
	var l := curtain.line()
	if f != _frame or l != _line:
		_frame = f
		_line = l
		queue_redraw()


func _input(event: InputEvent) -> void:
	if not visible:
		return
	if event is InputEventScreenTouch or event is InputEventScreenDrag or event is InputEventMouse:
		get_viewport().set_input_as_handled()


func _draw() -> void:
	var view := get_viewport_rect().size
	draw_rect(Rect2(Vector2.ZERO, view), Palette.SHADOW)
	var mid := floorf(view.y / 2.0)
	SmithIcon.draw(self, Vector2(floorf((view.x - SmithIcon.W * ICON_SCALE) / 2.0), mid + ICON_DY), _frame,
			ICON_SCALE)
	draw_rect(Rect2(floorf(view.x / 2.0) - RULE_W / 2.0, mid - 2, RULE_W, 1), Palette.WOOD[2])
	PixelFont.draw_centered(self, Rect2(0, mid + LINE_DY, view.x, 10), _line, Palette.WOOD[3])
