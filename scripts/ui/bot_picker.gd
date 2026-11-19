class_name BotPicker
extends Node2D
## Wybór celu Wyprawy (#26): najpierw zwarta lista odblokowanych zamków (mniej ekranu), Planuj
## rozwija pełną siatkę 5×4 z opisem, kolejne Planuj otwiera plan ataku. Kafelek / wiersz: zdobyty
## na zielono ze znaczkiem, dostępny jasno, zablokowany przygaszony; zamki epoki II mają czerwony
## znacznik. Pod siatką nazwa, trudność, epoka i załoga. Wróć wraca do mapy. Kolejny zamek
## odblokowuje się po zdobyciu poprzedniego; zdobyte można atakować znowu.
## Panel sam obsługuje dotyk, więc nic nie trafia do kamery ani do HUD.

signal target_chosen(index: int)
signal closed

enum Target { NONE = -1, PLAN = 1, CLOSE = 2, MORE = 3, TILE = 100 }

const TITLE := "Wyprawa: wybierz zamek"
const COLS := 5
const TILE_H := 14
const GAP := 3
const GRID_Y := Hud.BAR_H + 14
const DETAIL_Y := GRID_Y + 4 * (TILE_H + GAP) + 2
const LIST_Y := Hud.BAR_H + 14
const ROW_H := 12
const ROW_GAP := 1
## Najwyżej tyle wierszy na zwięzłej liście (Dalej przewija, gdy odblokowanych jest więcej).
const COMPACT_ROWS := 5
const PLAN_LABEL := "Planuj"
const CLOSE_LABEL := "Wróć"
const MORE_LABEL := "Dalej"
const LOCKED_TEXT := "Zablokowany: najpierw zdobądź poprzedni"

## Ile zamków gracz zdobył po kolei (odblokowuje następny).
var beaten := 0
var selected := 0
## false: zwarta lista; true: pełna siatka (po pierwszym Planuj).
var expanded := false
## Pierwszy widoczny wiersz zwięzłej listy.
var first := 0
var content_left := float(Hud.CORNER_INSET)
var content_right := 320.0 - Hud.CORNER_INSET

var _pressed: int = Target.NONE


func open(beaten_count: int, target: int) -> void:
	beaten = beaten_count
	selected = target if BotRoster.is_unlocked(target, beaten) else BotRoster.last_unlocked(beaten)
	expanded = false
	first = first_for(selected, unlocked_count(beaten), COMPACT_ROWS)
	visible = true
	_pressed = Target.NONE
	queue_redraw()


func close() -> void:
	visible = false
	expanded = false
	closed.emit()


func _process(_delta: float) -> void:
	if not visible:
		return
	var bounds := Hud.content_bounds(get_viewport_rect().size, Hud.safe_area_in_view(get_viewport()))
	content_left = bounds.x
	content_right = bounds.y


## Ile zamków na zwięzłej liście (zdobyte + następny cel).
static func unlocked_count(beaten_count: int) -> int:
	return BotRoster.last_unlocked(beaten_count) + 1


## Ile wierszy rysować: min(odblokowane, COMPACT_ROWS).
static func visible_rows(beaten_count: int) -> int:
	return mini(COMPACT_ROWS, unlocked_count(beaten_count))


## Pierwszy wiersz tak, by `index` był w oknie `fit` spośród `count`.
static func first_for(index: int, count: int, fit: int) -> int:
	if count <= fit:
		return 0
	return clampi(index - fit + 1, 0, count - fit)


## Pierwszy wiersz po Dalej: następna strona, po ostatniej znów pierwsza.
static func next_first(count: int, fit: int, start: int) -> int:
	return 0 if start + fit >= count else start + fit


static func list_row_rect(left: float, right: float, slot: int) -> Rect2:
	return Rect2(left, LIST_Y + slot * (ROW_H + ROW_GAP), right - left, ROW_H)


static func compact_detail_y(beaten_count: int) -> float:
	return LIST_Y + visible_rows(beaten_count) * (ROW_H + ROW_GAP) + 2


static func compact_buttons_y(beaten_count: int) -> float:
	return compact_detail_y(beaten_count) + PixelFont.LINE + 4


## Wysokość zwięzłego panelu od górnego paska HUD (bez dolnego paska).
static func compact_panel_h(beaten_count: int) -> float:
	return compact_buttons_y(beaten_count) + Hud.BUTTON_SIZE.y + 4 - Hud.BAR_H


static func tile_rects(left: float, right: float) -> Array[Rect2]:
	var w := floorf((right - left - (COLS - 1) * GAP) / COLS)
	var out: Array[Rect2] = []
	for i in BotRoster.COUNT:
		@warning_ignore("integer_division")
		var row := i / COLS
		out.append(Rect2(left + (i % COLS) * (w + GAP), GRID_Y + row * (TILE_H + GAP), w, TILE_H))
	return out


static func plan_rect(view: Vector2, right: float, is_expanded: bool = true, beaten_count: int = 0) -> Rect2:
	if is_expanded:
		return Hud.research_rect(view, right)
	return Rect2(Vector2(right - 2 * Hud.BUTTON_SIZE.x - Hud.BUTTON_GAP, compact_buttons_y(beaten_count)),
			Hud.BUTTON_SIZE)


static func close_rect(view: Vector2, right: float, is_expanded: bool = true, beaten_count: int = 0) -> Rect2:
	if is_expanded:
		return Hud.right_corner_rect(view, right)
	return Rect2(Vector2(right - Hud.BUTTON_SIZE.x, compact_buttons_y(beaten_count)), Hud.BUTTON_SIZE)


## Dalej: na lewo od Planuj, tylko na zwięzłej liście przy przepełnieniu.
static func more_rect(view: Vector2, right: float, beaten_count: int) -> Rect2:
	var a := plan_rect(view, right, false, beaten_count)
	return Rect2(a.position - Vector2(Hud.BUTTON_SIZE.x + Hud.BUTTON_GAP, 0), Hud.BUTTON_SIZE)


static func target_at(p: Vector2, view: Vector2, left: float, right: float, is_expanded: bool = true,
		beaten_count: int = 0, start: int = 0) -> int:
	if plan_rect(view, right, is_expanded, beaten_count).has_point(p):
		return Target.PLAN
	if close_rect(view, right, is_expanded, beaten_count).has_point(p):
		return Target.CLOSE
	if is_expanded:
		var tiles := tile_rects(left, right)
		for i in tiles.size():
			if tiles[i].has_point(p):
				return Target.TILE + i
		return Target.NONE
	var count := unlocked_count(beaten_count)
	var fit := visible_rows(beaten_count)
	if count > fit and more_rect(view, right, beaten_count).has_point(p):
		return Target.MORE
	for slot in fit:
		var i := start + slot
		if i >= count:
			break
		if list_row_rect(left, right, slot).has_point(p):
			return Target.TILE + i
	return Target.NONE


## Linie opisu zamku `i`: [tekst, kolor]. Nazwa z numerem, trudność z epoką i stanem, załoga
## (zawinięta do `width` px, najwyżej 2 wiersze).
static func detail_lines(i: int, beaten_count: int, width: int) -> Array:
	var state := "zdobyty" if BotRoster.is_beaten(i, beaten_count) else "cel"
	if not BotRoster.is_unlocked(i, beaten_count):
		state = "zablokowany"
	var out: Array = [
		["%d. %s" % [i + 1, BotRoster.NAMES[i]], Palette.INK],
		["Trudność %d/%d, epoka %s, %s" % [i + 1, BotRoster.COUNT, "II" if BotRoster.age_of(i) == 1 else "I", state],
				Palette.THATCH[2]],
	]
	for line in PixelFont.wrap("Załoga: " + BotRoster.defenders_text(i), width, 2):
		out.append([line, Palette.WOOD[3]])
	if not BotRoster.is_unlocked(i, beaten_count):
		out[-1] = [LOCKED_TEXT, Palette.ACCENT]
	return out


## Jedna linia pod zwięzłą listą: trudność, epoka i stan wybranego zamku.
static func compact_detail_line(i: int, beaten_count: int) -> Array:
	var state := "zdobyty" if BotRoster.is_beaten(i, beaten_count) else "cel"
	return ["Trudność %d/%d, epoka %s, %s" % [i + 1, BotRoster.COUNT,
			"II" if BotRoster.age_of(i) == 1 else "I", state], Palette.THATCH[2]]


func _activate(t: int) -> void:
	if t >= Target.TILE:
		selected = t - Target.TILE
	elif t == Target.MORE:
		first = next_first(unlocked_count(beaten), COMPACT_ROWS, first)
	elif t == Target.PLAN:
		if BotRoster.is_unlocked(selected, beaten):
			if not expanded:
				expanded = true
			else:
				target_chosen.emit(selected)
	elif t == Target.CLOSE:
		close()
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
	var view := get_viewport_rect().size
	if touch.position.y < Hud.BAR_H or touch.position.y >= view.y - Hud.BAR_H:
		return
	get_viewport().set_input_as_handled()
	# poza zwięzłym panelem: jak puste miejsce — zamknięcie
	if not expanded:
		var panel := Rect2(0, Hud.BAR_H, view.x, compact_panel_h(beaten))
		if not panel.has_point(touch.position):
			if touch.pressed:
				_pressed = Target.CLOSE
			else:
				var was_out := _pressed
				_pressed = Target.NONE
				if was_out == Target.CLOSE:
					close()
				queue_redraw()
			return
	var t := target_at(touch.position, view, content_left, content_right, expanded, beaten, first)
	if touch.pressed:
		_pressed = t
		queue_redraw()
		return
	var was := _pressed
	_pressed = Target.NONE
	if was != Target.NONE and t == was:
		_activate(was)
	queue_redraw()


# --- Rysowanie ---------------------------------------------------------------------------------

func _draw() -> void:
	var view := get_viewport_rect().size
	if expanded:
		draw_rect(Rect2(0, Hud.BAR_H, view.x, view.y - 2 * Hud.BAR_H), Color(Palette.SHADOW, 0.92))
	else:
		draw_rect(Rect2(0, Hud.BAR_H, view.x, compact_panel_h(beaten)), Color(Palette.SHADOW, 0.92))
	PixelFont.draw_text(self, Vector2(content_left, Hud.BAR_H + 2), TITLE, Palette.THATCH[2])
	if expanded:
		var tiles := tile_rects(content_left, content_right)
		for i in tiles.size():
			_draw_tile(tiles[i], i)
		var y := DETAIL_Y
		for line: Array in detail_lines(selected, beaten, int(content_right - content_left)):
			PixelFont.draw_text(self, Vector2(content_left, y), line[0] as String, line[1] as Color)
			y += PixelFont.LINE + 1
	else:
		var count := unlocked_count(beaten)
		var fit := visible_rows(beaten)
		for slot in fit:
			var i := first + slot
			if i >= count:
				break
			_draw_row(list_row_rect(content_left, content_right, slot), i)
		var detail: Array = compact_detail_line(selected, beaten)
		PixelFont.draw_text(self, Vector2(content_left, compact_detail_y(beaten)),
				detail[0] as String, detail[1] as Color)
		if count > fit:
			Hud.paint_button(self, more_rect(view, content_right, beaten), MORE_LABEL,
					_pressed == Target.MORE, false)
	Hud.paint_button(self, plan_rect(view, content_right, expanded, beaten), PLAN_LABEL,
			_pressed == Target.PLAN, not BotRoster.is_unlocked(selected, beaten))
	Hud.paint_button(self, close_rect(view, content_right, expanded, beaten), CLOSE_LABEL,
			_pressed == Target.CLOSE, false)


func _draw_row(r: Rect2, i: int) -> void:
	var done := BotRoster.is_beaten(i, beaten)
	var active := i == selected or _pressed == Target.TILE + i
	draw_rect(r, ResearchPanel.tile_color(done, active))
	var col: Color = Palette.INK if BotRoster.is_unlocked(i, beaten) else Palette.WOOD[0]
	if done:
		draw_rect(Rect2(r.position.x + 1, r.position.y + 1, 2, 2), Palette.VALID)
	PixelFont.draw_text(self, Vector2(r.position.x + 4, r.position.y + 2),
			"%d. %s" % [i + 1, BotRoster.NAMES[i]], col)
	if BotRoster.age_of(i) == 1:
		draw_rect(Rect2(r.end.x - 3, r.position.y + 1, 2, 2), Palette.ACCENT)
	if i == selected:
		CastleView.draw_frame(self, Rect2i(r), Palette.INK)


func _draw_tile(r: Rect2, i: int) -> void:
	var done := BotRoster.is_beaten(i, beaten)
	var active := i == selected or _pressed == Target.TILE + i
	draw_rect(r, ResearchPanel.tile_color(done, active))
	var col: Color = Palette.INK if BotRoster.is_unlocked(i, beaten) else Palette.WOOD[0]
	if done:
		draw_rect(Rect2(r.position.x + 1, r.position.y + 1, 2, 2), Palette.VALID)
	PixelFont.draw_centered(self, r, str(i + 1), col)
	if BotRoster.age_of(i) == 1:
		draw_rect(Rect2(r.end.x - 3, r.position.y + 1, 2, 2), Palette.ACCENT)
	if i == selected:
		CastleView.draw_frame(self, Rect2i(r), Palette.INK)
