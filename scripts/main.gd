extends Node2D
## Etap 1: scena testowa. Sprawdza viewport 320×180, ostre piksele, dotyk i działanie na telefonie.

const VIEW := Vector2i(320, 180)

var _texture: ImageTexture
var _touches: Array[Vector2] = []


func _ready() -> void:
	var img := PixelCanvas.make_terrain(VIEW)
	PixelCanvas.draw_path(img, Rect2i(150, 100, 6, 80))
	PixelCanvas.draw_palisade(img, Vector2i(120, 80), 70)
	PixelCanvas.draw_hut(img, Vector2i(136, 60))
	PixelCanvas.draw_hut(img, Vector2i(160, 62))
	_texture = ImageTexture.create_from_image(img)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch and event.pressed:
		var local := make_input_local(event) as InputEventScreenTouch
		_touches.append(local.position.floor())
		if _touches.size() > 8:
			_touches.pop_front()
		queue_redraw()


func _process(_delta: float) -> void:
	queue_redraw()


func _draw() -> void:
	draw_texture(_texture, Vector2.ZERO)
	for p in _touches:
		draw_rect(Rect2(p - Vector2(1, 1), Vector2(3, 3)), Palette.ACCENT)
	var font := ThemeDB.fallback_font
	draw_rect(Rect2(0, 0, VIEW.x, 12), Color(Palette.SHADOW, 0.8))
	draw_string(font, Vector2(4, 9), "CASTLE DEFENDER  ·  etap 1", HORIZONTAL_ALIGNMENT_LEFT, -1, 8, Palette.INK)
	var info := "%dx%d  %d FPS" % [get_viewport_rect().size.x, get_viewport_rect().size.y, Engine.get_frames_per_second()]
	draw_string(font, Vector2(4, 9), info, HORIZONTAL_ALIGNMENT_RIGHT, VIEW.x - 8, 8, Palette.INK)
