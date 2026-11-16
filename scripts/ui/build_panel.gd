class_name BuildPanel
extends Node2D
## Panel budowy na całą mapę (po teście na telefonie), w tym samym układzie co drzewko badań
## i Wojsko: u góry zakładki kategorii (Umocnienia, Gospodarka, Wytwórcy, Wojsko), pod nimi
## kafelki budynków, niżej szczegóły zaznaczonego: rozmiar, stan, koszt i czas budowy, wymagana
## technologia i co budynek daje. Postaw zamyka panel i włącza stawianie wybranego budynku na
## mapie, Zamknij wraca do mapy. Panel sam obsługuje dotyk.

signal place_requested(kind: int)
signal closed

enum Target { NONE = -1, CLOSE = 1, PLACE = 2, TAB = 100, TILE = 200 }

const TAB_Y := ResearchPanel.TAB_Y
const TAB_H := ResearchPanel.TAB_H
const GRID_Y := ResearchPanel.GRID_Y
const TILE_COLS := 4
const TILE_H := ResearchPanel.TILE_H
const GAP := ResearchPanel.GAP
const DETAIL_Y := ResearchPanel.DETAIL_Y
const DETAIL_LINES := ResearchPanel.DETAIL_LINES
const LINE_STEP := PixelFont.LINE + 2
const PLACE_LABEL := "Postaw"
const CLOSE_LABEL := "Zamknij"
## Opisy budynków, których działania nie da się wyczytać z danych produkcji i rekrutacji.
const DESCRIPTIONS := {
	BuildingTypes.Kind.RAMPART: "Umocnienie z ziemi, łączy się z palisadą",
	BuildingTypes.Kind.PALISADE: "Umocnienie z bali, łączy się z wałem",
	BuildingTypes.Kind.GATE: "Przejście w linii umocnień",
	BuildingTypes.Kind.TOWER: "Strzela do atakujących (strzały ze zbrojowni)",
	BuildingTypes.Kind.FISHER: "Stawiany tylko tuż przy rzece",
}

var research: Research
var economy: Economy
var category := 0
var selected := BuildingTypes.Kind.RAMPART
var content_left := float(Hud.CORNER_INSET)
var content_right := 320.0 - Hud.CORNER_INSET

var _pressed: int = Target.NONE


func open() -> void:
	visible = true
	_pressed = Target.NONE
	category = maxi(0, BuildingTypes.category(selected))


func close() -> void:
	visible = false
	closed.emit()


func select(kind: int) -> void:
	selected = kind
	category = maxi(0, BuildingTypes.category(kind))


func _process(_delta: float) -> void:
	if not visible:
		return
	var bounds := Hud.content_bounds(get_viewport_rect().size, Hud.safe_area_in_view(get_viewport()))
	content_left = bounds.x
	content_right = bounds.y
	queue_redraw()


# --- Układ -----------------------------------------------------------------------------------

static func tab_rects(left: float, right: float) -> Array[Rect2]:
	var n := BuildingTypes.CATEGORY_NAMES.size()
	var w := floorf((right - left - (n - 1) * GAP) / n)
	var out: Array[Rect2] = []
	for i in n:
		out.append(Rect2(left + i * (w + GAP), TAB_Y, w, TAB_H))
	return out


static func tile_rects(left: float, right: float, count: int) -> Array[Rect2]:
	var w := floorf((right - left - (TILE_COLS - 1) * GAP) / TILE_COLS)
	var out: Array[Rect2] = []
	for i in count:
		@warning_ignore("integer_division")
		var row := i / TILE_COLS
		out.append(Rect2(left + (i % TILE_COLS) * (w + GAP), GRID_Y + row * (TILE_H + GAP), w, TILE_H))
	return out


static func place_rect(view: Vector2, right: float) -> Rect2:
	return Hud.research_rect(view, right)


static func close_rect(view: Vector2, right: float) -> Rect2:
	return Hud.right_corner_rect(view, right)


static func target_at(p: Vector2, view: Vector2, left: float, right: float, shown: int) -> int:
	if close_rect(view, right).has_point(p):
		return Target.CLOSE
	if place_rect(view, right).has_point(p):
		return Target.PLACE
	var tab := Hud.hit(tab_rects(left, right), p)
	if tab >= 0:
		return Target.TAB + tab
	var tile := Hud.hit(tile_rects(left, right, BuildingTypes.in_category(shown).size()), p)
	if tile >= 0:
		return Target.TILE + tile
	return Target.NONE


# --- Teksty ------------------------------------------------------------------------------------

## Co budynek daje, z danych gry: produkcja surowca, towary wytwórcy, szkolone jednostki
## i opis z DESCRIPTIONS.
static func describe(kind: int) -> String:
	var parts: PackedStringArray = []
	if EconomyConfig.BUILDING_PRODUCTION.has(kind):
		var prod: Array = EconomyConfig.BUILDING_PRODUCTION[kind]
		parts.append("+%d %s/h" % [int((prod[1] as Array)[0]), EconomyConfig.SHORT_NAMES[int(prod[0])]])
	var producer: String = GoodsConfig.PRODUCER_KINDS.get(kind, "")
	if not producer.is_empty():
		var goods: PackedStringArray = []
		for row: Array in GoodsConfig.RECIPES:
			if row[0] == producer:
				for good: int in row[5] as Dictionary:
					var name := GoodsConfig.NAMES[good]
					if int(row[1]) > 1:
						name += " (poz. %d)" % int(row[1])
					if not goods.has(name):
						goods.append(name)
		parts.append("Robi: " + ", ".join(goods))
	var units := RecruitPanel.units_for(kind)
	if not units.is_empty():
		var names: PackedStringArray = []
		for u in units:
			names.append(UnitTypes.SHORT_NAMES[u])
		parts.append("Szkoli: " + ", ".join(names))
	if DESCRIPTIONS.has(kind):
		parts.append(DESCRIPTIONS[kind] as String)
	return ". ".join(parts)


## Stan budynku w panelu: „dostępny” albo co go blokuje.
static func state_text(kind: int, r: Research) -> String:
	if BuildConfig.is_unlocked(kind, r):
		return "dostępny"
	return "zbadaj %s" % BuildConfig.required_tech(kind)


## Linie szczegółów [tekst, kolor, tekst z prawej], zawinięte do `width` px, najwyżej DETAIL_LINES:
## nazwa z rozmiarem i stanem, koszt z czasem, wymagana technologia, opis.
static func detail_lines(kind: int, r: Research, e: Economy, width: int) -> Array:
	var out: Array = []
	var size := BuildingTypes.size_of(kind)
	var title := "%s (%d×%d)" % [BuildingTypes.NAMES[kind], size.x, size.y]
	var state := state_text(kind, r)
	out.append([ResearchPanel.fit_text(title, width - PixelFont.text_width(state) - 6), Palette.INK, state])
	var cost := BuildConfig.cost(kind, 1)
	var affordable := e == null or e.can_afford(cost)
	var cost_line := "Koszt: %s, %s" % [Hud.cost_text(cost), Hud.format_time(BuildConfig.time_ms(kind, 1))]
	if not affordable:
		cost_line += ", brak surowców"
	for l in PixelFont.wrap(cost_line, width, 2):
		out.append([l, Palette.INK if affordable else Palette.ACCENT, ""])
	var tech := BuildConfig.required_tech(kind)
	if not tech.is_empty():
		var done := r != null and r.is_done(tech)
		out.append([ResearchPanel.fit_text("Wymaga: %s %s" % [tech, TechTree.tech_name(tech)], width),
				Palette.VALID if done else Palette.ACCENT, ""])
	var room := DETAIL_LINES - out.size()
	if room > 0:
		for l in PixelFont.wrap(describe(kind), width, room):
			out.append([l, Palette.THATCH[2], ""])
	return out


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
	var t := target_at(touch.position, get_viewport_rect().size, content_left, content_right, category)
	if touch.pressed:
		_pressed = t
		return
	var was := _pressed
	_pressed = Target.NONE
	if was != Target.NONE and t == was:
		_activate(was)


func _activate(t: int) -> void:
	if t >= Target.TILE:
		selected = BuildingTypes.in_category(category)[t - Target.TILE]
	elif t >= Target.TAB:
		category = t - Target.TAB
		selected = BuildingTypes.in_category(category)[0]
	elif t == Target.PLACE:
		if BuildConfig.is_unlocked(selected, research):
			visible = false
			place_requested.emit(selected)
	elif t == Target.CLOSE:
		close()


# --- Rysowanie ---------------------------------------------------------------------------------

func _draw() -> void:
	var view := get_viewport_rect().size
	draw_rect(Rect2(0, Hud.BAR_H, view.x, view.y - 2 * Hud.BAR_H), Color(Palette.SHADOW, 0.92))
	var tabs := tab_rects(content_left, content_right)
	for i in tabs.size():
		Hud.paint_button(self, tabs[i], BuildingTypes.CATEGORY_NAMES[i], i == category or _pressed == Target.TAB + i, false)
	var kinds := BuildingTypes.in_category(category)
	var tiles := tile_rects(content_left, content_right, kinds.size())
	for i in kinds.size():
		var locked := not BuildConfig.is_unlocked(kinds[i], research)
		Hud.paint_button(self, tiles[i], BuildingTypes.SHORT_NAMES[kinds[i]],
				kinds[i] == selected or _pressed == Target.TILE + i, locked)
	var y := float(DETAIL_Y)
	for l: Array in detail_lines(selected, research, economy, int(content_right - content_left)):
		PixelFont.draw_text(self, Vector2(content_left, y), l[0] as String, l[1] as Color)
		if not (l[2] as String).is_empty():
			PixelFont.draw_right(self, content_right, y, l[2] as String, Palette.THATCH[2])
		y += LINE_STEP
	var can_place := BuildConfig.is_unlocked(selected, research)
	Hud.paint_button(self, place_rect(view, content_right), PLACE_LABEL, _pressed == Target.PLACE, not can_place)
	Hud.paint_button(self, close_rect(view, content_right), CLOSE_LABEL, _pressed == Target.CLOSE, false)
