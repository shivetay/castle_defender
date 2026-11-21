class_name GeneralsPanel
extends Node2D
## Generałowie (#31) z karty Dworu, na przyciemnionym zamku: po wierszu na każdego z 3 generałów MVP
## z poziomem, doświadczeniem i perkami. Przycisk wiersza werbuje generała za złoto, kupuje kolejny
## poziom (gdy doświadczenia wystarczy) albo otwiera wybór perka dodatkowego na poziomie 3. Logikę
## i komunikaty liczy main.gd (Generals), panel tylko rysuje i oddaje dotyk.

signal closed
signal recruit_requested(kind: int)
signal promote_requested(kind: int)
signal perk_requested(kind: int, perk: int)

enum Screen { LIST, PERKS }
## Przycisk wiersza (do listy), wybór perka i Zamknij/Wróć.
enum Target { NONE = -1, ROW = 0, PERK = 100, CLOSE = 200 }

const TITLE := "Generałowie"
const PERK_TITLE := "Perk dodatkowy: %s"
const ROW_Y := 38
const ROW_H := 32
const LEFT := 16
const BUTTON_SIZE := Vector2(76, 14)
const PERK_SIZE := Vector2(200, 14)
const GAP := 4
const CLOSE_LABEL := "Zamknij"
const BACK_LABEL := "Wróć"
const DONE_LABEL := "Najwyższy poz."

var generals: Generals
var age := 0
var screen := Screen.LIST
## Generał, któremu gracz wybiera perk (ekran PERKS).
var perk_kind := -1
var _pressed: int = Target.NONE


func open(g: Generals, castle_age: int) -> void:
	generals = g
	age = castle_age
	screen = Screen.LIST
	perk_kind = -1
	visible = true
	_pressed = Target.NONE
	queue_redraw()


func close() -> void:
	visible = false
	closed.emit()


## Prostokąt przycisku wiersza `i` (z prawej, z marginesem od krawędzi).
static func row_button(view: Vector2, i: int) -> Rect2:
	return Rect2(Vector2(view.x - LEFT - BUTTON_SIZE.x, ROW_Y + i * ROW_H + 4), BUTTON_SIZE)


static func close_rect(view: Vector2) -> Rect2:
	return Rect2(Vector2(floorf((view.x - BUTTON_SIZE.x) / 2.0), ROW_Y + Generals.count() * ROW_H + 2), BUTTON_SIZE)


static func perk_rect(view: Vector2, i: int) -> Rect2:
	return Rect2(Vector2(floorf((view.x - PERK_SIZE.x) / 2.0), ROW_Y + i * (PERK_SIZE.y + GAP)), PERK_SIZE)


static func back_rect(view: Vector2, perk_count: int) -> Rect2:
	return Rect2(Vector2(floorf((view.x - BUTTON_SIZE.x) / 2.0), ROW_Y + perk_count * (PERK_SIZE.y + GAP) + GAP),
			BUTTON_SIZE)


## Napis przycisku wiersza generała `kind`: Werbuj, Awans, Perk albo pusty (brak akcji).
static func row_label(g: Generals, kind: int) -> String:
	var gen := g.get_general(kind)
	if gen == null:
		return "Werbuj %d Zł" % Generals.RECRUIT_GOLD
	if gen.level >= Generals.PERK_LEVEL and gen.perk == Generals.Perk.NONE:
		return "Wybierz perk"
	if gen.level >= Generals.MAX_LEVEL:
		return DONE_LABEL
	return "Awans %d Zł" % Generals.LEVEL_GOLD[gen.level + 1]


## Druga linia wiersza: poziom i doświadczenie albo „najlepszy w: …”.
static func row_status(g: Generals, kind: int) -> String:
	var gen := g.get_general(kind)
	if gen == null:
		return "Najlepszy w: %s" % Generals.BEST_IN[kind]
	var next := "max" if gen.level >= Generals.MAX_LEVEL else str(Generals.LEVEL_XP[gen.level + 1])
	return "Poz. %d · PD %d/%s" % [gen.level, gen.xp, next]


## Trzecia linia: perk główny i dodatkowy.
static func row_perks(g: Generals, kind: int) -> String:
	var gen := g.get_general(kind)
	var text := Generals.MAIN_PERKS[kind]
	if gen != null and gen.perk != Generals.Perk.NONE:
		text = "%s; %s" % [text, Generals.PERK_NAMES[gen.perk]]
	return text


func target_at(p: Vector2, view: Vector2) -> int:
	if screen == Screen.PERKS:
		var perks := Generals.perks_for(age)
		for i in perks.size():
			if perk_rect(view, i).has_point(p):
				return Target.PERK + perks[i]
		return Target.CLOSE if back_rect(view, perks.size()).has_point(p) else Target.NONE
	for k in Generals.count():
		if row_button(view, k).has_point(p):
			return Target.ROW + k
	return Target.CLOSE if close_rect(view).has_point(p) else Target.NONE


## Dotknięcie przycisku `t`.
func activate(t: int) -> void:
	if t == Target.CLOSE:
		if screen == Screen.PERKS:
			screen = Screen.LIST
			queue_redraw()
		else:
			close()
		return
	if t >= Target.PERK:
		perk_requested.emit(perk_kind, t - Target.PERK)
		screen = Screen.LIST
		queue_redraw()
		return
	var kind := t - Target.ROW
	var gen := generals.get_general(kind)
	if gen == null:
		recruit_requested.emit(kind)
	elif gen.level >= Generals.PERK_LEVEL and gen.perk == Generals.Perk.NONE:
		perk_kind = kind
		screen = Screen.PERKS
	elif gen.level < Generals.MAX_LEVEL:
		promote_requested.emit(kind)
	queue_redraw()


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
	if generals == null:
		return
	var view := get_viewport_rect().size
	draw_rect(Rect2(Vector2.ZERO, view), Color(Palette.SHADOW, 0.85))
	if screen == Screen.PERKS:
		_draw_perks(view)
		return
	PixelFont.draw_centered(self, Rect2(0, 22, view.x, 10), TITLE.to_upper(), Palette.THATCH[2])
	draw_rect(Rect2(floorf(view.x / 2.0) - 30, 33, 60, 1), Palette.WOOD[2])
	var text_w := int(view.x - LEFT * 2 - BUTTON_SIZE.x - GAP)
	for k in Generals.count():
		var y := ROW_Y + k * ROW_H
		var owned := generals.has_general(k)
		var name_col := Palette.INK if owned else Palette.THATCH[1]
		var tag := " (atak)" if generals.attack_kind == k else ""
		PixelFont.draw_text(self, Vector2(LEFT, y), PixelFont._fit(Generals.NAMES[k] + tag, text_w), name_col)
		PixelFont.draw_text(self, Vector2(LEFT, y + 9), PixelFont._fit(row_status(generals, k), text_w), Palette.THATCH[2])
		PixelFont.draw_text(self, Vector2(LEFT, y + 18), PixelFont._fit(row_perks(generals, k), text_w), Palette.WOOD[3])
		var label := row_label(generals, k)
		Hud.paint_button(self, row_button(view, k), label, _pressed == Target.ROW + k, label == DONE_LABEL)
	Hud.paint_button(self, close_rect(view), CLOSE_LABEL, _pressed == Target.CLOSE, false)


func _draw_perks(view: Vector2) -> void:
	var name := Generals.NAMES[perk_kind] if perk_kind >= 0 else ""
	PixelFont.draw_centered(self, Rect2(0, 22, view.x, 10), PERK_TITLE % name, Palette.THATCH[2])
	var perks := Generals.perks_for(age)
	for i in perks.size():
		var p := perks[i]
		Hud.paint_button(self, perk_rect(view, i), "%s: %s" % [Generals.PERK_NAMES[p], Generals.PERK_DESC[p]],
				_pressed == Target.PERK + p, false)
	Hud.paint_button(self, back_rect(view, perks.size()), BACK_LABEL, _pressed == Target.CLOSE, false)
