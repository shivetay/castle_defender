class_name ResearchPanel
extends Node2D
## Ekran drzewka badań (#12) na całą mapę, między górnym a dolnym paskiem HUD.
## U góry zakładki gałęzi (Atak, Obrona, Gospodarka, Użyteczne, Specjalne), pod nimi kafelki technologii
## z kodem. Kafelek pokazuje stan kolorem napisu: zbadana, w toku, dostępna, zablokowana
## (brak wymaganej technologii, budynku badań gałęzi z #165 albo późniejsza epoka); zbadana ma zielony kafelek ze znaczkiem
## w lewym rogu, a technologia kluczowa ★ czerwony znacznik w prawym. Technologie z późniejszej epoki
## są ukryte, dopóki nie zbadano ich wymagań (Research.is_visible); ukryte nie pojawiają się też
## w ramkach, w „Odblokowuje” ani w „Powiązane”.
## Dotknięcie kafelka pokazuje szczegóły: nazwę, stan, efekt, koszt i czas, wymagania, co technologia
## odblokowuje i z czym łączy się przez towary (TechLinks). Ramki na kafelkach: wymagane czerwone
## (zielone, gdy zbadane), odblokowywane złote, powiązane niebieskie. Badaj rozpoczyna badanie,
## Zamknij wraca do mapy.
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
## Nazwa i stan, efekt, epoka z kosztem i czasem, wymagania, odblokowuje, powiązane, trwające badanie.
const DETAIL_LINES := 5
const LINE_STEP := PixelFont.LINE + 2
const START_LABEL := "Badaj"
## Przycisk startu dla kolejnego poziomu zbadanej doktryny.
const LEVEL_UP_LABEL := "Ulepsz"
const CLOSE_LABEL := "Zamknij"

var research: Research
var economy: Economy
## Epoka gry (0 = I); technologii z późniejszej epoki nie da się badać.
var age := 0
## Siatka zamku: bez budynku badań gałęzi (#165) technologii nie da się badać.
var grid: BuildGrid
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
	if selected.is_empty() or not _is_shown(selected):
		select(shown_codes(branch)[0])


func close() -> void:
	visible = false
	closed.emit()


func select(code: String) -> void:
	selected = code
	branch = TechTree.branch(code)


## Kafelki gałęzi `b` widoczne w tej chwili (bez badań: całe drzewko, jak w testach układu).
func shown_codes(b: int) -> Array[String]:
	var codes := TechTree.in_branch(b)
	return research.visible_of(codes, age) if research != null else codes


func _is_shown(code: String) -> bool:
	return research == null or research.is_visible(code, age)


## Lista kodów bez ukrytych technologii.
func _shown_of(codes: Array[String]) -> Array[String]:
	return research.visible_of(codes, age) if research != null else codes


func _process(_delta: float) -> void:
	if not visible:
		return
	var bounds := Hud.content_bounds(get_viewport_rect().size, Hud.safe_area_in_view(get_viewport()))
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


static func target_at(p: Vector2, view: Vector2, left: float, right: float, tile_count: int) -> int:
	if close_rect(view, right).has_point(p):
		return Target.CLOSE
	if start_rect(view, right).has_point(p):
		return Target.START
	var tab := Hud.hit(tab_rects(left, right), p)
	if tab >= 0:
		return Target.TAB + tab
	var tile := Hud.hit(tile_rects(left, right, tile_count), p)
	if tile >= 0:
		return Target.TILE + tile
	return Target.NONE


# --- Teksty ------------------------------------------------------------------------------------

## Stan technologii po polsku, np. „zbadana”, „w toku 0:42”, „Epoka II”.
static func state_text(r: Research, code: String, current_age: int, now: int, grid: BuildGrid = null) -> String:
	if r.active == code:
		return "w toku %s" % Hud.format_time(r.remaining_ms(now))
	if r.is_done(code):
		if TechTree.is_leveled(code):
			return "poziom %d/%d" % [r.level(code), TechTree.max_level(code, current_age)]
		return "zbadana"
	if TechTree.age(code) > current_age:
		return TechTree.age_label(TechTree.age(code))
	if not r.missing(code).is_empty():
		return "zablokowana"
	if grid != null and not Research.has_building(code, grid):
		return "brak budynku"
	return "dostępna"


## Kod i nazwa technologii, przy doktrynie z poziomami z poziomem: obecnym albo (`next`) tym,
## który da badanie, np. „G1 Karczowanie lasu, poziom 2”.
static func title_of(r: Research, code: String, next: bool = false) -> String:
	var title := "%s %s" % [code, TechTree.tech_name(code)]
	if TechTree.is_leveled(code):
		var lv := r.level(code)
		if next:
			lv += 1
		if lv > 1:
			title += ", poziom %d" % lv
	return title


## Premia doktryny z poziomami jako tekst, np. „Premia +25%, następny poziom +30%”; pusty dla innych.
static func level_text(r: Research, code: String, current_age: int) -> String:
	if not TechTree.is_leveled(code) or not TechTree.PRODUCTION_BONUS.has(code):
		return ""
	var base := int((TechTree.PRODUCTION_BONUS[code] as Array)[1])
	var lv := r.level(code)
	var now_text := "Premia +%d%%" % r.doctrine_percent(code, base) if lv > 0 else "Premia +%d%%" % base
	if lv == 0 or lv >= TechTree.max_level(code, current_age):
		return now_text if lv > 0 else ""
	return "%s, następny poziom +%d%%" % [now_text, base + TechTree.DOCTRINE_LEVEL_PERCENT * lv]


## Czy technologię da się jeszcze badać (niezbadana albo doktryna poniżej najwyższego poziomu w epoce).
static func can_research_more(r: Research, code: String, current_age: int) -> bool:
	if r.active == code:
		return false
	return not r.is_done(code) or (TechTree.is_leveled(code) and r.level(code) < TechTree.max_level(code, current_age))


## Wymagania jako tekst: budynek badań gałęzi (#165, gdy to nie Dwór, który stoi zawsze) i kody
## z nazwami, a gdy to za szerokie, same kody.
static func requires_text(code: String, max_width: int) -> String:
	var reqs := TechTree.requires(code)
	var building := ResearchConfig.research_building(code)
	var head: PackedStringArray = []
	if building != BuildingTypes.Kind.MANOR:
		head.append(BuildingTypes.NAMES[building])
	if reqs.is_empty() and head.is_empty():
		return "Bez wymagań"
	var named := head.duplicate()
	for req in reqs:
		named.append("%s %s" % [req, TechTree.tech_name(req)])
	var text := "Wymaga: " + ", ".join(named)
	if PixelFont.text_width(text) <= max_width:
		return text
	var short := head.duplicate()
	short.append_array(PackedStringArray(reqs))
	return fit_text("Wymaga: " + ", ".join(short), max_width)


## Tekst przycięty do szerokości `max_width` (z wielokropkiem „...”).
static func fit_text(text: String, max_width: int) -> String:
	if PixelFont.text_width(text) <= max_width:
		return text
	var out := text
	while out.length() > 0 and PixelFont.text_width(out + "...") > max_width:
		out = out.substr(0, out.length() - 1)
	return out.strip_edges() + "..."


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
	var t := target_at(touch.position, get_viewport_rect().size, content_left, content_right,
			shown_codes(branch).size())
	if touch.pressed:
		_pressed = t
		return
	var was := _pressed
	_pressed = Target.NONE
	if was != Target.NONE and t == was:
		_activate(was)


func _activate(t: int) -> void:
	if t >= Target.TILE:
		select(shown_codes(branch)[t - Target.TILE])
	elif t >= Target.TAB:
		branch = t - Target.TAB
		select(shown_codes(branch)[0])
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
	var reqs := TechTree.requires(selected)
	var next := _shown_of(TechLinks.unlocks(selected))
	var linked := _shown_of(TechLinks.related(selected))
	var tabs := tab_rects(content_left, content_right)
	for i in tabs.size():
		Hud.paint_button(self, tabs[i], TechTree.BRANCH_NAMES[i], i == branch or _pressed == Target.TAB + i, false)
		var mark := tab_marker(i, reqs, next, linked)
		if i != branch and mark.a > 0.0:
			# powiązanie w innej gałęzi: pasek w kolorze ramki na dole zakładki (review #157)
			draw_rect(Rect2(tabs[i].position.x + 2, tabs[i].end.y - 3, tabs[i].size.x - 4, 2), mark)
	var codes := shown_codes(branch)
	var tiles := tile_rects(content_left, content_right, codes.size())
	for i in codes.size():
		var frame := link_color(codes[i], reqs, next, linked, research.is_done(codes[i]))
		_draw_tile(tiles[i], codes[i], codes[i] == selected or _pressed == Target.TILE + i, frame)
	_draw_details()
	var can_start := research.check(selected, age, grid) == Research.Result.OK \
			and economy != null and economy.can_afford(research.cost_of(selected))
	var label := LEVEL_UP_LABEL if research.is_level_up(selected) else START_LABEL
	Hud.paint_button(self, start_rect(view, content_right), label, _pressed == Target.START, not can_start)
	Hud.paint_button(self, close_rect(view, content_right), CLOSE_LABEL, _pressed == Target.CLOSE, false)


func _draw_tile(r: Rect2, code: String, active: bool, frame: Color) -> void:
	draw_rect(r, tile_color(research.is_done(code), active))
	var col: Color = Palette.INK
	if research.is_done(code):
		# zbadana: zielony kafelek z jasnym kodem i znaczkiem w lewym górnym rogu
		draw_rect(Rect2(r.position.x + 1, r.position.y + 1, 2, 2), Palette.VALID)
		# kolejne poziomy doktryny: znaczek za każdy poziom ponad pierwszy w lewym dolnym rogu
		for i in research.level(code) - 1:
			draw_rect(Rect2(r.position.x + 1 + 3 * i, r.end.y - 3, 2, 2), Palette.VALID)
		if research.active == code:
			col = Palette.THATCH[2]
	elif research.active == code:
		col = Palette.THATCH[2]
	elif TechTree.age(code) > age or not research.missing(code).is_empty() \
			or (grid != null and not Research.has_building(code, grid)):
		# przygaszone tylko zablokowane: trwające inne badanie nie gasi reszty drzewka
		col = Palette.WOOD[0]
	PixelFont.draw_centered(self, r, code, col)
	if TechTree.is_key(code):
		draw_rect(Rect2(r.end.x - 3, r.position.y + 1, 2, 2), Palette.ACCENT)
	if frame.a > 0.0:
		draw_rect(Rect2(r.position.x, r.position.y, r.size.x, 1), frame)
		draw_rect(Rect2(r.position.x, r.end.y - 1, r.size.x, 1), frame)
		draw_rect(Rect2(r.position.x, r.position.y, 1, r.size.y), frame)
		draw_rect(Rect2(r.end.x - 1, r.position.y, 1, r.size.y), frame)


## Kolor ramki kafelka `code` względem zaznaczonej technologii: wymagana czerwona (spełniona jasna,
## żeby była widoczna na zielonym kafelku zbadanej, review #157), odblokowywana złota, powiązana
## niebieska; przezroczysty, gdy brak powiązania.
static func link_color(code: String, reqs: Array[String], next: Array[String], linked: Array[String],
		done: bool) -> Color:
	if reqs.has(code):
		return Palette.INK if done else Palette.ACCENT
	if next.has(code):
		return Palette.THATCH[2]
	if linked.has(code):
		return Palette.WATER[2]
	return Color(0, 0, 0, 0)


## Znacznik zakładki gałęzi `i`, w której leży coś powiązanego z zaznaczoną technologią (ramki
## widać tylko w bieżącej zakładce): kolor najważniejszego powiązania albo przezroczysty.
static func tab_marker(i: int, reqs: Array[String], next: Array[String], linked: Array[String]) -> Color:
	var best := Color(0, 0, 0, 0)
	for code in TechTree.in_branch(i):
		if reqs.has(code):
			return Palette.ACCENT
		if next.has(code):
			best = Palette.THATCH[2]
		elif linked.has(code) and best.a == 0.0:
			best = Palette.WATER[2]
	return best


## Tło kafelka: zbadane mają zielone (trawa), reszta drewniane; zaznaczony jest jaśniejszy.
static func tile_color(done: bool, active: bool) -> Color:
	if done:
		return Palette.GRASS[2] if active else Palette.GRASS[0]
	return Palette.WOOD[2] if active else Palette.WOOD[1]


## Linie szczegółów technologii [tekst, kolor, tekst z prawej], zawinięte do `width` px i najwyżej
## DETAIL_LINES. Kolejność ważności: tytuł ze stanem, efekt, koszt, wymaga, odblokowuje, powiązane,
## trwające badanie; czego nie da się zmieścić, wypada od końca.
static func detail_lines(r: Research, code: String, current_age: int, now: int, width: int,
		amounts: Array[int] = [], grid: BuildGrid = null) -> Array:
	var head: Array = []
	var title := title_of(r, code)
	if TechTree.is_key(code):
		title += " (kluczowa)"
	var state := state_text(r, code, current_age, now, grid)
	head.append([fit_text(title, width - PixelFont.text_width(state) - 6), Palette.INK, state])
	var effect := PixelFont.wrap(TechTree.effect(code), width, 2)
	var bonus := level_text(r, code, current_age)
	if not bonus.is_empty():
		head.append([fit_text(bonus, width), Palette.VALID, ""])
	if can_research_more(r, code, current_age):
		head.append([fit_text("%s, %s, %s" % [TechTree.age_label(TechTree.age(code)), Hud.cost_text(r.cost_of(code)),
				Hud.format_time(r.time_of(code))], width), Palette.INK, "", Hud.missing_tokens(r.cost_of(code), amounts)])
	var links: Array = []
	# brakujący budynek badań na czerwono, jak brakujące surowce
	var missing_building := PackedStringArray()
	if grid != null and not Research.has_building(code, grid) and not r.is_done(code):
		missing_building.append(BuildingTypes.NAMES[ResearchConfig.research_building(code)])
	links.append([requires_text(code, width), Palette.INK, "", missing_building])
	var next := r.visible_of(TechLinks.unlocks(code), current_age)
	if not next.is_empty():
		links.append([codes_text("Odblokowuje: ", next, width), Palette.THATCH[2], ""])
	var linked := r.visible_of(TechLinks.related(code), current_age)
	if not linked.is_empty():
		links.append([codes_text("Powiązane: ", linked, width), Palette.WATER[2], ""])
	# brak miejsca: odblokowuje i powiązane w jednej linii, same kody
	if head.size() + 1 + links.size() > DETAIL_LINES and not next.is_empty() and not linked.is_empty():
		links.resize(1)
		links.append([fit_text("Odblokowuje: %s; powiązane: %s" % [", ".join(PackedStringArray(next)),
				", ".join(PackedStringArray(linked))], width), Palette.THATCH[2], ""])
	var tail: Array = []
	if r.is_busy() and r.active != code:
		tail.append([fit_text("Trwa: %s %s, %s" % [r.active, TechTree.tech_name(r.active),
				Hud.format_time(r.remaining_ms(now))], width), Palette.WOOD[3], ""])
	# efekt dostaje drugą linię tylko wtedy, gdy zostaje miejsce po powiązaniach
	var fixed := head.size() + links.size() + tail.size() + 1
	var out: Array = [head[0]]
	for i in mini(effect.size(), maxi(1, DETAIL_LINES - fixed + 1)):
		out.append([effect[i], Palette.VALID, ""])
	out.append_array(head.slice(1))
	out.append_array(links)
	out.append_array(tail)
	return out.slice(0, DETAIL_LINES)


## Lista kodów z nazwami („Odblokowuje: A22 Kopia rycerska”), a gdy to za szerokie, same kody.
static func codes_text(prefix: String, list: Array[String], max_width: int) -> String:
	var named: PackedStringArray = []
	for c in list:
		named.append("%s %s" % [c, TechTree.tech_name(c)])
	var text := prefix + ", ".join(named)
	if PixelFont.text_width(text) <= max_width:
		return text
	return fit_text(prefix + ", ".join(PackedStringArray(list)), max_width)


## Szczegóły zaznaczonej technologii: do DETAIL_LINES linii między kafelkami a rzędem przycisków.
func _draw_details() -> void:
	if selected.is_empty():
		return
	var y := float(DETAIL_Y)
	var amounts: Array[int] = economy.amounts if economy != null else [] as Array[int]
	for l: Array in detail_lines(research, selected, age, now_ms, int(content_right - content_left), amounts, grid):
		var tokens: PackedStringArray = l[3] if l.size() > 3 else PackedStringArray()
		Hud.draw_highlighted(self, Vector2(content_left, y), l[0] as String, l[1] as Color, tokens, Palette.ACCENT)
		if not (l[2] as String).is_empty():
			PixelFont.draw_right(self, content_right, y, l[2] as String, Palette.THATCH[2])
		y += LINE_STEP
