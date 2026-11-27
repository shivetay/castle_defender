class_name BotPicker
extends Node2D
## Wybór celu Wyprawy (#26, #230): siatka 5×4 z 20 zamkami-botami jednej epoki, epokę zmieniają
## zakładki I / II obok tytułu (otwiera się na epoce wybranego celu). Kafelek: numer w epoce, zdobyty
## na zielono ze znaczkiem, dostępny jasno, zablokowany przygaszony. Pod siatką nazwa, trudność w epoce,
## epoka i załoga. Planuj otwiera plan ataku na wybranym zamku (#312),
## Wróć wraca do ekranu 3 celów. Kolejny zamek odblokowuje się po zdobyciu poprzedniego; zdobyte
## można atakować znowu. Panel sam obsługuje dotyk, więc nic nie trafia do kamery ani do HUD.

signal target_chosen(index: int)
signal closed

enum Target { NONE = -1, PLAN = 1, CLOSE = 2, TAB = 50, TILE = 100 }

const TITLE := "Wyprawa: wybierz zamek"
const COLS := 5
const TAB_W := 18
const TAB_H := 12
const TILE_H := 14
const GAP := 3
const GRID_Y := Hud.BAR_H + 14
const DETAIL_Y := GRID_Y + 4 * (TILE_H + GAP) + 2
const PLAN_LABEL := "Planuj"
const CLOSE_LABEL := "Wróć"
const LOCKED_TEXT := "Zablokowany: najpierw zdobądź poprzedni"

## Ile zamków gracz zdobył po kolei (odblokowuje następny).
var beaten := 0
var selected := 0
## Epoka pokazana w siatce.
var age_tab := 0
var content_left := float(Hud.CORNER_INSET)
var content_right := 320.0 - Hud.CORNER_INSET

var _pressed: int = Target.NONE


func open(beaten_count: int, target: int) -> void:
	beaten = beaten_count
	selected = target if BotRoster.is_unlocked(target, beaten) else BotRoster.last_unlocked(beaten)
	age_tab = BotRoster.age_of(selected)
	visible = true
	_pressed = Target.NONE
	queue_redraw()


func close() -> void:
	visible = false
	closed.emit()


func _process(_delta: float) -> void:
	if not visible:
		return
	var bounds := Hud.content_bounds(get_viewport_rect().size, Hud.safe_area_in_view(get_viewport()))
	content_left = bounds.x
	content_right = bounds.y


## Kafelki jednej epoki (BotRoster.COUNT_PER_AGE); kafelek `k` to zamek first_of_age(epoka) + k.
static func tile_rects(left: float, right: float) -> Array[Rect2]:
	var w := floorf((right - left - (COLS - 1) * GAP) / COLS)
	var out: Array[Rect2] = []
	for i in BotRoster.COUNT_PER_AGE:
		@warning_ignore("integer_division")
		var row := i / COLS
		out.append(Rect2(left + (i % COLS) * (w + GAP), GRID_Y + row * (TILE_H + GAP), w, TILE_H))
	return out


## Zakładki epok na wysokości tytułu, wyrównane do prawej krawędzi treści.
static func tab_rects(right: float) -> Array[Rect2]:
	var out: Array[Rect2] = []
	for age in BotRoster.AGES:
		var x := right - (BotRoster.AGES - age) * (TAB_W + GAP) + GAP
		out.append(Rect2(x, Hud.BAR_H + 1, TAB_W, TAB_H))
	return out


static func plan_rect(view: Vector2, right: float) -> Rect2:
	return Hud.research_rect(view, right)


static func close_rect(view: Vector2, right: float) -> Rect2:
	return Hud.right_corner_rect(view, right)


static func target_at(p: Vector2, view: Vector2, left: float, right: float) -> int:
	if plan_rect(view, right).has_point(p):
		return Target.PLAN
	if close_rect(view, right).has_point(p):
		return Target.CLOSE
	var tabs := tab_rects(right)
	for age in tabs.size():
		if tabs[age].has_point(p):
			return Target.TAB + age
	var tiles := tile_rects(left, right)
	for i in tiles.size():
		if tiles[i].has_point(p):
			return Target.TILE + i
	return Target.NONE


## Komunikat po zdobyciu: odblokowany zamek `i`, np. „Odblokowany: 2. Bobrowa Wola”, a pierwszy
## zamek nowej epoki z jej numerem.
static func unlock_text(i: int) -> String:
	var text := "Odblokowany: " + BotRoster.title(i)
	if BotRoster.rank_of(i) == 0 and BotRoster.age_of(i) > 0:
		text += " (epoka %s)" % BotRoster.age_name(BotRoster.age_of(i))
	return text


## Linie opisu zamku `i`: [tekst, kolor]. Nazwa z numerem, trudność z epoką i stanem, załoga
## (zawinięta do `width` px, najwyżej 2 wiersze).
static func detail_lines(i: int, beaten_count: int, width: int) -> Array:
	var state := "zdobyty" if BotRoster.is_beaten(i, beaten_count) else "cel"
	if not BotRoster.is_unlocked(i, beaten_count):
		state = "zablokowany"
	var out: Array = [
		[BotRoster.title(i), Palette.INK],
		["Trudność %d/%d, epoka %s, %s" % [BotRoster.rank_of(i) + 1, BotRoster.COUNT_PER_AGE,
				BotRoster.age_name(BotRoster.age_of(i)), state], Palette.THATCH[2]],
	]
	for line in PixelFont.wrap("Załoga: " + BotRoster.defenders_text(i), width, 2):
		out.append([line, Palette.WOOD[3]])
	if not BotRoster.is_unlocked(i, beaten_count):
		out[-1] = [LOCKED_TEXT, Palette.ACCENT]
	return out


## Zamek zaznaczany po przejściu na zakładkę `age`: dotychczasowy, gdy jest w tej epoce, inaczej
## najwyższy odblokowany w niej, a w całkiem zablokowanej epoce jej pierwszy zamek.
static func select_in_age(age: int, current: int, beaten_count: int) -> int:
	if BotRoster.age_of(current) == age:
		return current
	var first := BotRoster.first_of_age(age)
	return clampi(BotRoster.last_unlocked(beaten_count), first, first + BotRoster.COUNT_PER_AGE - 1)


func _activate(t: int) -> void:
	if t >= Target.TILE:
		selected = BotRoster.first_of_age(age_tab) + t - Target.TILE
	elif t >= Target.TAB:
		age_tab = t - Target.TAB
		selected = select_in_age(age_tab, selected, beaten)
	elif t == Target.PLAN:
		if BotRoster.is_unlocked(selected, beaten):
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
	var t := target_at(touch.position, view, content_left, content_right)
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
	draw_rect(Rect2(0, Hud.BAR_H, view.x, view.y - 2 * Hud.BAR_H), Color(Palette.SHADOW, 0.92))
	PixelFont.draw_text(self, Vector2(content_left, Hud.BAR_H + 2), TITLE, Palette.THATCH[2])
	var tabs := tab_rects(content_right)
	for age in tabs.size():
		Hud.paint_button(self, tabs[age], BotRoster.age_name(age), age == age_tab or _pressed == Target.TAB + age, false)
		if age == age_tab:
			CastleView.draw_frame(self, Rect2i(tabs[age]), Palette.INK)
	var tiles := tile_rects(content_left, content_right)
	var first := BotRoster.first_of_age(age_tab)
	for k in tiles.size():
		_draw_tile(tiles[k], first + k, Target.TILE + k)
	var y := DETAIL_Y
	for line: Array in detail_lines(selected, beaten, int(content_right - content_left)):
		PixelFont.draw_text(self, Vector2(content_left, y), line[0] as String, line[1] as Color)
		y += PixelFont.LINE + 1
	Hud.paint_button(self, plan_rect(view, content_right), PLAN_LABEL,
			_pressed == Target.PLAN, not BotRoster.is_unlocked(selected, beaten))
	Hud.paint_button(self, close_rect(view, content_right), CLOSE_LABEL,
			_pressed == Target.CLOSE, false)


func _draw_tile(r: Rect2, i: int, target: int) -> void:
	var done := BotRoster.is_beaten(i, beaten)
	var active := i == selected or _pressed == target
	draw_rect(r, ResearchPanel.tile_color(done, active))
	var col: Color = Palette.INK if BotRoster.is_unlocked(i, beaten) else Palette.WOOD[0]
	if done:
		draw_rect(Rect2(r.position.x + 1, r.position.y + 1, 2, 2), Palette.VALID)
	PixelFont.draw_centered(self, r, str(BotRoster.rank_of(i) + 1), col)
	if i == selected:
		CastleView.draw_frame(self, Rect2i(r), Palette.INK)
