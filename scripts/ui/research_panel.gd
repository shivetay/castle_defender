class_name ResearchPanel
extends Node2D
## Ekran drzewka badań (#12) na całą mapę, między górnym a dolnym paskiem HUD.
## U góry zakładki gałęzi (Atak, Obrona, Gospodarka, Użyteczne), pod nimi kafelki technologii
## z kodem. Kafelek pokazuje stan kolorem napisu: zbadana, w toku, dostępna, zablokowana
## (brak wymaganej technologii albo późniejsza epoka); technologia kluczowa ★ ma znacznik w rogu.
## Dotknięcie kafelka pokazuje szczegóły: nazwę, stan, koszt i czas, wymagania (z ramką na
## wymaganych kafelkach). Badaj rozpoczyna badanie, Zamknij wraca do mapy.
## Panel sam obsługuje dotyk, więc nic nie trafia do kamery ani do HUD.

signal research_requested(code: String)
signal closed

enum Target { NONE = -1, CLOSE = 1, START = 2, TAB = 100, TILE = 200 }

const TAB_Y := Hud.BAR_H + 3
const TAB_H := 14
const GRID_Y := TAB_Y + TAB_H + 4
const TILE_COLS := 8
const TILE_H := 14
const GAP := 3
const DETAIL_Y := GRID_Y + 3 * (TILE_H + GAP) + 2
const START_LABEL := "Badaj"
const CLOSE_LABEL := "Zamknij"

var research: Research
var economy: Economy
## Epoka gry (0 = I); technologii z późniejszej epoki nie da się badać.
var age := 0
## Czas do liczenia pozostałego czasu badania (ustawia gra co klatkę).
var now_ms := 0
var branch := 0
var selected := ""
var content_left := float(Hud.CORNER_INSET)
var content_right := 320.0 - Hud.CORNER_INSET

var _pressed: int = Target.NONE


func open() -> void:
	visible = true
	_pressed = Target.NONE
	if selected.is_empty():
		select(TechTree.in_branch(branch)[0])


func close() -> void:
	visible = false
	closed.emit()


func select(code: String) -> void:
	selected = code
	branch = TechTree.branch(code)


func _process(_delta: float) -> void:
	if not visible:
		return
	var bounds := Hud.content_bounds(get_viewport_rect().size, Rect2())
	content_left = bounds.x
	content_right = bounds.y
	queue_redraw()


# --- Układ -----------------------------------------------------------------------------------

static func tab_rects(left: float, right: float) -> Array[Rect2]:
	var n := TechTree.BRANCH_NAMES.size()
	var w := floorf((right - left - (n - 1) * GAP) / n)
	var out: Array[Rect2] = []
	for i in n:
		out.append(Rect2(left + i * (w + GAP), TAB_Y, w, TAB_H))
	return out


## Kafelki `count` technologii gałęzi, po TILE_COLS w rzędzie.
static func tile_rects(left: float, right: float, count: int) -> Array[Rect2]:
	var w := floorf((right - left - (TILE_COLS - 1) * GAP) / TILE_COLS)
	var out: Array[Rect2] = []
	for i in count:
		@warning_ignore("integer_division")
		var row := i / TILE_COLS
		out.append(Rect2(left + (i % TILE_COLS) * (w + GAP), GRID_Y + row * (TILE_H + GAP), w, TILE_H))
	return out


## Badaj w miejscu przycisku Badania, Zamknij w miejscu Buduj (ten sam kciuk otwiera i zamyka).
static func start_rect(view: Vector2, right: float) -> Rect2:
	return Hud.research_rect(view, right)


static func close_rect(view: Vector2, right: float) -> Rect2:
	return Hud.right_corner_rect(view, right)


static func target_at(p: Vector2, view: Vector2, left: float, right: float, shown_branch: int) -> int:
	if close_rect(view, right).has_point(p):
		return Target.CLOSE
	if start_rect(view, right).has_point(p):
		return Target.START
	var tab := Hud.hit(tab_rects(left, right), p)
	if tab >= 0:
		return Target.TAB + tab
	var tile := Hud.hit(tile_rects(left, right, TechTree.in_branch(shown_branch).size()), p)
	if tile >= 0:
		return Target.TILE + tile
	return Target.NONE


# --- Teksty ------------------------------------------------------------------------------------

## Stan technologii po polsku, np. „zbadana”, „w toku 0:42”, „Epoka II”.
static func state_text(r: Research, code: String, current_age: int, now: int) -> String:
	if r.is_done(code):
		return "zbadana"
	if r.active == code:
		return "w toku %s" % Hud.format_time(r.remaining_ms(now))
	if TechTree.age(code) > current_age:
		return TechTree.age_label(TechTree.age(code))
	if not r.missing(code).is_empty():
		return "zablokowana"
	return "dostępna"


## Wymagania jako tekst: kody z nazwami, a gdy to za szerokie, same kody.
static func requires_text(code: String, max_width: int) -> String:
	var reqs := TechTree.requires(code)
	if reqs.is_empty():
		return "Bez wymagań"
	var named: PackedStringArray = []
	for req in reqs:
		named.append("%s %s" % [req, TechTree.tech_name(req)])
	var text := "Wymaga: " + ", ".join(named)
	if PixelFont.text_width(text) <= max_width:
		return text
	return "Wymaga: " + ", ".join(PackedStringArray(reqs))


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
	var t := target_at(touch.position, get_viewport_rect().size, content_left, content_right, branch)
	if touch.pressed:
		_pressed = t
		return
	var was := _pressed
	_pressed = Target.NONE
	if was != Target.NONE and t == was:
		_activate(was)


func _activate(t: int) -> void:
	if t >= Target.TILE:
		select(TechTree.in_branch(branch)[t - Target.TILE])
	elif t >= Target.TAB:
		branch = t - Target.TAB
		select(TechTree.in_branch(branch)[0])
	elif t == Target.START:
		if not selected.is_empty():
			research_requested.emit(selected)
	elif t == Target.CLOSE:
		close()


# --- Rysowanie ---------------------------------------------------------------------------------

func _draw() -> void:
	if research == null:
		return
	var view := get_viewport_rect().size
	draw_rect(Rect2(0, Hud.BAR_H, view.x, view.y - 2 * Hud.BAR_H), Color(Palette.SHADOW, 0.92))
	var tabs := tab_rects(content_left, content_right)
	for i in tabs.size():
		Hud.paint_button(self, tabs[i], TechTree.BRANCH_NAMES[i], i == branch or _pressed == Target.TAB + i, false)
	var codes := TechTree.in_branch(branch)
	var tiles := tile_rects(content_left, content_right, codes.size())
	var reqs := TechTree.requires(selected)
	for i in codes.size():
		_draw_tile(tiles[i], codes[i], codes[i] == selected or _pressed == Target.TILE + i, reqs.has(codes[i]))
	_draw_details()
	var can_start := research.check(selected, age) == Research.Result.OK \
			and economy != null and economy.can_afford(research.cost_of(selected))
	Hud.paint_button(self, start_rect(view, content_right), START_LABEL, _pressed == Target.START, not can_start)
	Hud.paint_button(self, close_rect(view, content_right), CLOSE_LABEL, _pressed == Target.CLOSE, false)


func _draw_tile(r: Rect2, code: String, active: bool, required: bool) -> void:
	draw_rect(r, Palette.WOOD[2] if active else Palette.WOOD[1])
	var col: Color = Palette.INK
	if research.is_done(code):
		col = Palette.VALID
	elif research.active == code:
		col = Palette.THATCH[2]
	elif TechTree.age(code) > age or not research.missing(code).is_empty():
		# przygaszone tylko zablokowane: trwające inne badanie nie gasi reszty drzewka
		col = Palette.WOOD[0]
	PixelFont.draw_centered(self, r, code, col)
	if TechTree.is_key(code):
		draw_rect(Rect2(r.end.x - 3, r.position.y + 1, 2, 2), Palette.ACCENT)
	if required:
		var frame: Color = Palette.VALID if research.is_done(code) else Palette.ACCENT
		draw_rect(Rect2(r.position.x, r.position.y, r.size.x, 1), frame)
		draw_rect(Rect2(r.position.x, r.end.y - 1, r.size.x, 1), frame)
		draw_rect(Rect2(r.position.x, r.position.y, 1, r.size.y), frame)
		draw_rect(Rect2(r.end.x - 1, r.position.y, 1, r.size.y), frame)


## Szczegóły zaznaczonej technologii: do 4 linii między kafelkami a rzędem przycisków.
func _draw_details() -> void:
	if selected.is_empty():
		return
	var x := content_left
	var width := int(content_right - content_left)
	var y := float(DETAIL_Y)
	var title := "%s %s" % [selected, TechTree.tech_name(selected)]
	if TechTree.is_key(selected):
		title += " (kluczowa)"
	PixelFont.draw_text(self, Vector2(x, y), title, Palette.INK)
	PixelFont.draw_right(self, content_right, y, state_text(research, selected, age, now_ms), Palette.THATCH[2])
	y += PixelFont.LINE + 2
	if not research.is_done(selected) and research.active != selected:
		var line := "%s, %s, %s" % [TechTree.age_label(TechTree.age(selected)),
				Hud.cost_text(research.cost_of(selected)), Hud.format_time(research.time_of(selected))]
		PixelFont.draw_text(self, Vector2(x, y), line, Palette.INK)
		y += PixelFont.LINE + 2
	PixelFont.draw_text(self, Vector2(x, y), requires_text(selected, width), Palette.INK)
	y += PixelFont.LINE + 2
	if research.is_busy() and research.active != selected:
		var busy := "Trwa: %s %s, %s" % [research.active, TechTree.tech_name(research.active),
				Hud.format_time(research.remaining_ms(now_ms))]
		PixelFont.draw_text(self, Vector2(x, y), busy, Palette.WOOD[3])
