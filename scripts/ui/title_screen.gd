class_name TitleScreen
extends Node2D
## Ekran tytułowy Dunholm (#360): pokazuje się raz przy uruchomieniu gry, nad zamkiem, który
## w tym czasie wczytuje się i łączy z serwerem pod spodem. „Graj” go zamyka, „Discord” otwiera
## link do społeczności. Przeładowanie sceny (nowa gra, zamek z serwera) go nie pokazuje ponownie.
## Dopóki stoi, łapie każdy dotyk. Grafikę rysuje TitleArt raz dla rozmiaru ekranu.

signal play_pressed

enum Target { NONE = -1, PLAY, DISCORD }

const PLAY_LABEL := "Graj"
const BUTTON_SIZE := Vector2(80, 14)
const GAP := 8
## Przyciski tyle pikseli nad dolną krawędzią (z dala od gestów systemowych).
const BUTTONS_FROM_BOTTOM := 30

## Czy ekran tytułowy był już w tym uruchomieniu gry (statyczne, przeżywa przeładowanie sceny).
static var shown_this_run := false

var hint := ""

var _pressed: int = Target.NONE
var _texture: ImageTexture
var _texture_size := Vector2i.ZERO


static func targets() -> Array[int]:
	return [Target.PLAY, Target.DISCORD] as Array[int]


## Dwa przyciski obok siebie, wyśrodkowane, nad dolną krawędzią (całe piksele).
static func button_rects(view: Vector2) -> Array[Rect2]:
	var total := 2.0 * BUTTON_SIZE.x + GAP
	var x := floorf((view.x - total) / 2.0)
	var y := view.y - BUTTONS_FROM_BOTTOM
	return [Rect2(Vector2(x, y), BUTTON_SIZE), Rect2(Vector2(x + BUTTON_SIZE.x + GAP, y), BUTTON_SIZE)] as Array[Rect2]


static func target_at(p: Vector2, view: Vector2) -> int:
	var rects := button_rects(view)
	for i in rects.size():
		if rects[i].has_point(p):
			return targets()[i]
	return Target.NONE


static func label(t: int) -> String:
	return PLAY_LABEL if t == Target.PLAY else CommunityLink.LABEL


func _ready() -> void:
	get_viewport().size_changed.connect(queue_redraw)


func open() -> void:
	shown_this_run = true
	visible = true
	hint = ""
	queue_redraw()


func activate(t: int) -> void:
	match t:
		Target.PLAY:
			visible = false
			play_pressed.emit()
		Target.DISCORD:
			hint = CommunityLink.open_discord()
	queue_redraw()


func _input(event: InputEvent) -> void:
	if not visible:
		return
	get_viewport().set_input_as_handled()
	var touch := event as InputEventScreenTouch
	if touch == null:
		return
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
	var size := Vector2i(int(view.x), int(view.y))
	if _texture == null or size != _texture_size:
		_texture_size = size
		_texture = ImageTexture.create_from_image(TitleArt.make_image(size))
	draw_texture(_texture, Vector2.ZERO)
	var rects := button_rects(view)
	var ts := targets()
	for i in rects.size():
		Hud.paint_button(self, rects[i], label(ts[i]), _pressed == ts[i], false)
	if not hint.is_empty():
		PixelFont.draw_centered(self, Rect2(0, rects[0].position.y - 11, view.x, 10), hint, Palette.INK)
	PixelFont.draw_right(self, view.x - Hud.CORNER_INSET, view.y - 10, SettingsPanel.version_text(), Palette.WOOD[3])
