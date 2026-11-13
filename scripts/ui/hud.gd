class_name Hud
extends Node2D
## Interfejs nad mapą (nie przesuwa się z kamerą). U góry: etap, seed, zoom i FPS.
## Nad dolnym paskiem komunikatu: pasek wyboru budynku albo karta zaznaczonego budynku
## (poziom, Ulepsz, Rozbierz, Zamknij). Dotknięcia przycisków nie trafiają do kamery.

signal kind_selected(kind: int)
signal upgrade_pressed
signal demolish_pressed
signal card_closed

enum CardButton { UPGRADE, DEMOLISH, CLOSE }

const BAR_H := 12
const BUTTON_SIZE := Vector2(56, 14)
const BUTTON_GAP := 4
const CARD_LABELS: Array[String] = ["Ulepsz", "Rozbierz", "Zamknij"]

var camera: PanZoomCamera
var world_seed := 0
var message := "Wybierz budynek i dotknij trawy"
var selected_kind := 0
## Karta budynku: widoczna, gdy card_title nie jest pusty.
var card_title := ""
var card_level := 0
var _pressed := -1


func _process(_delta: float) -> void:
	queue_redraw()


func show_card(title: String, level: int) -> void:
	card_title = title
	card_level = level


func hide_card() -> void:
	card_title = ""


func is_card_open() -> bool:
	return not card_title.is_empty()


## Przyciski paska budynków: rząd wyśrodkowany nad paskiem komunikatu, z dala od krawędzi.
static func toolbar_rects(view: Vector2) -> Array[Rect2]:
	return _row(view, BuildingTypes.count())


## Przyciski karty budynku (Ulepsz, Rozbierz, Zamknij) w tym samym miejscu co pasek.
static func card_rects(view: Vector2) -> Array[Rect2]:
	return _row(view, CARD_LABELS.size())


static func _row(view: Vector2, n: int) -> Array[Rect2]:
	var total := n * BUTTON_SIZE.x + (n - 1) * BUTTON_GAP
	var x := floorf((view.x - total) / 2.0)
	var y := view.y - BAR_H - BUTTON_SIZE.y - 4
	var out: Array[Rect2] = []
	for i in n:
		out.append(Rect2(Vector2(x + i * (BUTTON_SIZE.x + BUTTON_GAP), y), BUTTON_SIZE))
	return out


## Indeks przycisku pod punktem ekranu albo -1.
static func hit(rects: Array[Rect2], p: Vector2) -> int:
	for i in rects.size():
		if rects[i].has_point(p):
			return i
	return -1


func _current_rects() -> Array[Rect2]:
	var view := get_viewport_rect().size
	return card_rects(view) if is_card_open() else toolbar_rects(view)


func _input(event: InputEvent) -> void:
	var touch := event as InputEventScreenTouch
	if touch == null:
		return
	var i := hit(_current_rects(), touch.position)
	if touch.pressed:
		_pressed = i
		if i >= 0:
			get_viewport().set_input_as_handled()
		return
	# przycisk działa, gdy palec puszczono na tym samym przycisku, na którym go położono
	var was := _pressed
	_pressed = -1
	if was < 0:
		return
	get_viewport().set_input_as_handled()
	if i != was:
		return
	if is_card_open():
		match i:
			CardButton.UPGRADE:
				upgrade_pressed.emit()
			CardButton.DEMOLISH:
				demolish_pressed.emit()
			CardButton.CLOSE:
				card_closed.emit()
	else:
		selected_kind = i
		kind_selected.emit(i)


func _draw() -> void:
	var font := ThemeDB.fallback_font
	var view := get_viewport_rect().size
	draw_rect(Rect2(0, 0, view.x, BAR_H), Color(Palette.SHADOW, 0.8))
	draw_string(font, Vector2(4, 9), "CASTLE DEFENDER · etap 3", HORIZONTAL_ALIGNMENT_LEFT, -1, 8, Palette.INK)
	var zoom := camera.zoom_level if camera != null else 1
	var info := "seed %d  %d×  %d FPS" % [world_seed, zoom, Engine.get_frames_per_second()]
	draw_string(font, Vector2(4, 9), info, HORIZONTAL_ALIGNMENT_RIGHT, view.x - 8, 8, Palette.INK)

	var rects := _current_rects()
	if is_card_open():
		var r0 := rects[0]
		var panel := Rect2(r0.position - Vector2(4, 16), Vector2(rects[-1].end.x - r0.position.x + 8, r0.size.y + 20))
		draw_rect(panel, Color(Palette.SHADOW, 0.85))
		var lv := "poziom %d/%d" % [card_level, BuildingTypes.MAX_LEVEL]
		draw_string(font, panel.position + Vector2(4, 10), card_title, HORIZONTAL_ALIGNMENT_LEFT, -1, 8, Palette.INK)
		draw_string(font, panel.position + Vector2(4, 10), lv, HORIZONTAL_ALIGNMENT_RIGHT, panel.size.x - 8, 8, Palette.THATCH[2])
		for i in rects.size():
			var disabled := i == CardButton.UPGRADE and card_level >= BuildingTypes.MAX_LEVEL
			_draw_button(rects[i], CARD_LABELS[i], i == _pressed, disabled)
	else:
		for i in rects.size():
			_draw_button(rects[i], BuildingTypes.SHORT_NAMES[i], i == selected_kind or i == _pressed, false)

	draw_rect(Rect2(0, view.y - BAR_H, view.x, BAR_H), Color(Palette.SHADOW, 0.6))
	draw_string(font, Vector2(4, view.y - 3), message, HORIZONTAL_ALIGNMENT_LEFT, view.x - 8, 8, Palette.INK)


func _draw_button(r: Rect2, label: String, active: bool, disabled: bool) -> void:
	var font := ThemeDB.fallback_font
	draw_rect(r, Palette.WOOD[2] if active else Palette.WOOD[1])
	draw_rect(Rect2(r.position, Vector2(r.size.x, 1)), Palette.WOOD[3])
	draw_rect(Rect2(r.position + Vector2(0, r.size.y - 1), Vector2(r.size.x, 1)), Palette.WOOD[0])
	var col: Color = Palette.WOOD[0] if disabled else Palette.INK
	draw_string(font, r.position + Vector2(0, 10), label, HORIZONTAL_ALIGNMENT_CENTER, r.size.x, 8, col)
