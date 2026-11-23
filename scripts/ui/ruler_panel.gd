class_name RulerPanel
extends Node2D
## Władca i jego perk (#32) po dotknięciu portretu w HUD-zie, na przyciemnionym zamku: gracz, zamek,
## miejsce na perk z tym, co teraz działa, koszt zmiany i lista 6 perków MVP. Perk z późniejszej epoki
## jest wyszarzony z dopiskiem epoki. Logikę i komunikaty liczy main.gd (RulerPerks), panel tylko rysuje
## i oddaje dotyk.

signal closed
signal perk_requested(perk: int)

## Wiersz perka (+ numer perka) i Zamknij.
enum Target { NONE = -1, PERK = 0, CLOSE = 100 }

const ROW_Y := 48
const ROW_H := 13
const GAP := 2
const ROW_W := 248.0
const BUTTON_SIZE := Vector2(76, 14)
const CLOSE_LABEL := "Zamknij"
const SLOT_LINE := "Perk (%d miejsce): %s"
const FREE_LINE := "Zmiana: darmowa (raz na 24 h)"
const PAID_LINE := "Zmiana: %d Zł, darmowa za %s"

var ruler_name := ""
var player_line := ""
var perks: RulerPerks
var age := 0
## Chwila otwarcia (unix, ms): od niej liczy się koszt zmiany i czas do darmowej.
var now_ms := 0
var _pressed: int = Target.NONE


func open(name: String, line: String, ruler: RulerPerks, castle_age: int, at_ms: int) -> void:
	ruler_name = name
	player_line = line
	perks = ruler
	age = castle_age
	now_ms = at_ms
	visible = true
	_pressed = Target.NONE
	queue_redraw()


func close() -> void:
	visible = false
	closed.emit()


static func perk_rect(view: Vector2, i: int) -> Rect2:
	return Rect2(Vector2(floorf((view.x - ROW_W) / 2.0), ROW_Y + i * (ROW_H + GAP)), Vector2(ROW_W, ROW_H))


static func close_rect(view: Vector2) -> Rect2:
	return Rect2(Vector2(floorf((view.x - BUTTON_SIZE.x) / 2.0), ROW_Y + RulerPerks.count() * (ROW_H + GAP) + 4),
			BUTTON_SIZE)


## Napis wiersza perka `p`: nazwa i efekt, „działa” przy wybranym, epoka przy zablokowanym.
static func row_label(r: RulerPerks, p: int, castle_age: int) -> String:
	if RulerPerks.PERK_AGE[p] > castle_age:
		return "%s: od epoki %s" % [RulerPerks.NAMES[p], TechTree.AGE_NUMERALS[RulerPerks.PERK_AGE[p]]]
	var text := "%s: %s" % [RulerPerks.NAMES[p], RulerPerks.DESC[p]]
	return text + " (działa)" if r != null and r.perk == p else text


## Linia z kosztem zmiany w chwili `at_ms`.
static func cost_line(r: RulerPerks, at_ms: int) -> String:
	if r.is_free_change(at_ms):
		return FREE_LINE
	return PAID_LINE % [RulerPerks.CHANGE_GOLD, Hud.format_time(r.next_free_ms(at_ms) - at_ms)]


func target_at(p: Vector2, view: Vector2) -> int:
	for i in RulerPerks.count():
		if perk_rect(view, i).has_point(p):
			return Target.PERK + i
	return Target.CLOSE if close_rect(view).has_point(p) else Target.NONE


func activate(t: int) -> void:
	if t == Target.CLOSE:
		close()
	elif t >= Target.PERK and t < Target.PERK + RulerPerks.count():
		perk_requested.emit(t - Target.PERK)


# --- Dotyk -------------------------------------------------------------------------------------

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


# --- Rysowanie ---------------------------------------------------------------------------------

func _draw() -> void:
	if perks == null:
		return
	var view := get_viewport_rect().size
	var w := int(ROW_W)
	var left := floorf((view.x - ROW_W) / 2.0)
	draw_rect(Rect2(Vector2.ZERO, view), Color(Palette.SHADOW, 0.85))
	PixelFont.draw_centered(self, Rect2(0, 8, view.x, 10), ruler_name.to_upper(), Palette.THATCH[2])
	draw_rect(Rect2(floorf(view.x / 2.0) - 30, 19, 60, 1), Palette.WOOD[2])
	PixelFont.draw_text(self, Vector2(left, 22), PixelFont._fit(player_line, w), Palette.THATCH[2])
	var slot := SLOT_LINE % [RulerPerks.SLOTS, RulerPerks.perk_name(perks.active(age))]
	PixelFont.draw_text(self, Vector2(left, 30), PixelFont._fit(slot, w), Palette.INK)
	PixelFont.draw_text(self, Vector2(left, 38), PixelFont._fit(cost_line(perks, now_ms), w), Palette.WOOD[3])
	for i in RulerPerks.count():
		var r := perk_rect(view, i)
		var locked := RulerPerks.PERK_AGE[i] > age
		var label := PixelFont._fit(row_label(perks, i, age), w - 4)
		Hud.paint_button(self, r, label, _pressed == Target.PERK + i or perks.perk == i, locked)
	Hud.paint_button(self, close_rect(view), CLOSE_LABEL, _pressed == Target.CLOSE, false)
