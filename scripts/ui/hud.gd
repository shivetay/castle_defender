class_name Hud
extends Node2D
## Pasek u góry ekranu (nie przesuwa się z kamerą): nazwa etapu, seed, zoom i FPS,
## a nad dolną krawędzią komunikat ostatniej akcji.

var camera: PanZoomCamera
var world_seed := 0
var message := "Dotknij trawy, aby postawić chatę"


func _process(_delta: float) -> void:
	queue_redraw()


func _draw() -> void:
	var font := ThemeDB.fallback_font
	var view := get_viewport_rect().size
	draw_rect(Rect2(0, 0, view.x, 12), Color(Palette.SHADOW, 0.8))
	draw_string(font, Vector2(4, 9), "CASTLE DEFENDER · etap 2", HORIZONTAL_ALIGNMENT_LEFT, -1, 8, Palette.INK)
	var zoom := camera.zoom_level if camera != null else 1
	var info := "seed %d  %d×  %d FPS" % [world_seed, zoom, Engine.get_frames_per_second()]
	draw_string(font, Vector2(4, 9), info, HORIZONTAL_ALIGNMENT_RIGHT, view.x - 8, 8, Palette.INK)
	draw_rect(Rect2(0, view.y - 12, view.x, 12), Color(Palette.SHADOW, 0.6))
	draw_string(font, Vector2(4, view.y - 3), message, HORIZONTAL_ALIGNMENT_LEFT, view.x - 8, 8, Palette.INK)
