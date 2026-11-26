class_name RulerPanel
extends Node2D
## Władca i jego perki (#32, #308) po dotknięciu portretu w HUD-zie, na przyciemnionym zamku: gracz, zamek,
## perk wrodzony władcy, perk z technologii, który teraz działa, i 4 linie perków z technologiami
## kolejnych poziomów. Perka nie wybiera się tu z listy: odblokowuje go badanie (RulerPerks), więc wiersze
## linii tylko pokazują stan (wybrana, zablokowana, do zbadania). Dotyk obsługuje tylko Zamknij.

signal closed

enum Target { NONE = -1, CLOSE = 100 }

const ROW_Y := 64
const ROW_H := 13
const GAP := 2
const ROW_W := 248.0
const BUTTON_SIZE := Vector2(76, 14)
const CLOSE_LABEL := "Zamknij"
const INNATE_LINE := "Perk władcy: %s"
const TECH_LINE := "Perk z badań: %s"
const NO_TECH_PERK := "brak"
const HINT_LINE := "Zbadaj 1 linię w Badaniach, na stałe"
const CHOSEN := "wybrana"
const LOCKED := "zablokowana"

var ruler_name := ""
var player_line := ""
## Perk wrodzony władcy jednym tekstem (Rulers.perk_text).
var innate_text := ""
var research: Research
var age := 0
var _pressed: int = Target.NONE


func open(name: String, line: String, innate: String, castle_research: Research, castle_age: int) -> void:
	ruler_name = name
	player_line = line
	innate_text = innate
	research = castle_research
	age = castle_age
	visible = true
	_pressed = Target.NONE
	queue_redraw()


func close() -> void:
	visible = false
	closed.emit()


static func line_rect(view: Vector2, i: int) -> Rect2:
	return Rect2(Vector2(floorf((view.x - ROW_W) / 2.0), ROW_Y + i * (ROW_H + GAP)), Vector2(ROW_W, ROW_H))


static func close_rect(view: Vector2) -> Rect2:
	return Rect2(Vector2(floorf((view.x - BUTTON_SIZE.x) / 2.0),
			ROW_Y + RulerPerks.LINES.size() * (ROW_H + GAP) + 4), BUTTON_SIZE)


## Linia z perkiem z technologii, który działa w zamku z epoki `castle_age`.
static func tech_line(r: Research, castle_age: int) -> String:
	var p := RulerPerks.from_research(r, castle_age)
	return TECH_LINE % (RulerPerks.NAMES[p] if RulerPerks.is_known(p) else NO_TECH_PERK)


## Efekt perka z technologii albo podpowiedź, gdy jeszcze go nie ma.
static func effect_line(r: Research, castle_age: int) -> String:
	var p := RulerPerks.from_research(r, castle_age)
	return RulerPerks.DESC[p] if RulerPerks.is_known(p) else HINT_LINE


## Napis wiersza linii `line`: nazwa, kody technologii poziomów i stan, np. „Zdobywca A60 > A61: wybrana”.
static func row_label(r: Research, line: int) -> String:
	var text := "%s %s" % [RulerPerks.LINE_NAMES[line], " > ".join(RulerPerks.LINES[line] as Array)]
	var chosen := RulerPerks.chosen_line(r.done, r.active) if r != null else -1
	if chosen == line:
		return "%s: %s" % [text, CHOSEN]
	if chosen != -1:
		return "%s: %s" % [text, LOCKED]
	return text


func target_at(p: Vector2, view: Vector2) -> int:
	return Target.CLOSE if close_rect(view).has_point(p) else Target.NONE


func activate(t: int) -> void:
	if t == Target.CLOSE:
		close()


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
	if research == null:
		return
	var view := get_viewport_rect().size
	var w := int(ROW_W)
	var left := floorf((view.x - ROW_W) / 2.0)
	draw_rect(Hud.backdrop_rect(view), Color(Palette.SHADOW, 0.85))
	PixelFont.draw_centered(self, Rect2(0, 8, view.x, 10), ruler_name.to_upper(), Palette.THATCH[2])
	draw_rect(Rect2(floorf(view.x / 2.0) - 30, 19, 60, 1), Palette.WOOD[2])
	PixelFont.draw_text(self, Vector2(left, 22), PixelFont._fit(player_line, w), Palette.THATCH[2])
	PixelFont.draw_text(self, Vector2(left, 30), PixelFont._fit(INNATE_LINE % innate_text, w), Palette.INK)
	PixelFont.draw_text(self, Vector2(left, 38), PixelFont._fit(tech_line(research, age), w), Palette.INK)
	PixelFont.draw_text(self, Vector2(left, 46), PixelFont._fit(effect_line(research, age), w), Palette.WOOD[3])
	var chosen := RulerPerks.chosen_line(research.done, research.active)
	for i in RulerPerks.LINES.size():
		var label := PixelFont._fit(row_label(research, i), w - 4)
		Hud.paint_button(self, line_rect(view, i), label, chosen == i, chosen != -1 and chosen != i)
	Hud.paint_button(self, close_rect(view), CLOSE_LABEL, _pressed == Target.CLOSE, false)
