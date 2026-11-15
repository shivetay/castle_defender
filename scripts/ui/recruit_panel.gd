class_name RecruitPanel
extends Node2D
## Ekran Wojsko (#89) na całą mapę, między górnym a dolnym paskiem HUD. Działa w dwóch trybach:
## - globalnym (przycisk Wojsko w HUD): wszystkie jednostki MVP, a Szkol wybiera budynek danego
##   rodzaju z najkrótszą kolejką,
## - budynku (przycisk Szkol na karcie budynku rekrutacji): tylko jednostki tego budynku.
## U góry stan armii, globalny limit (ile zamek może utrzymać) i wolne miejsca, pod spodem kafelki
## jednostek (ikona klasy, nazwa, liczba w armii i w szkoleniu). Jednostki, których nie da się
## szkolić, są przygaszone. Dotknięcie kafelka pokazuje szczegóły: koszt, brakujące towary
## z budynkiem, który je robi, szkolenie, a w ostatnim rzędzie wybór oddziału: Nowy albo istniejący
## oddział tego rodzaju z zajętymi miejscami (pełne są przygaszone).

signal train_requested(unit: int, squad_id: int)
signal closed

enum Target { NONE = -1, CLOSE = 1, TRAIN = 2, TILE = 200, SQUAD = 300 }

const TITLE_Y := Hud.BAR_H + 3
const GRID_Y := TITLE_Y + 11
const TILE_COLS := 3
const TILE_H := 12
const GAP := 2
const MAX_ROWS := 5
const DETAIL_Y := GRID_Y + MAX_ROWS * (TILE_H + GAP) + 1
## Nazwa i stan, koszt, brakujące towary albo szkolenie, wybór oddziału.
const DETAIL_LINES := 4
const SQUAD_Y := DETAIL_Y + 3 * (PixelFont.LINE + 2)
const SQUAD_W := 54
const SQUAD_H := 12
const NEW_SQUAD_LABEL := "Nowy"
const TRAIN_LABEL := "Szkol"
const CLOSE_LABEL := "Zamknij"

var recruitment: Recruitment
var grid: BuildGrid
var economy: Economy
var goods: Goods
var research: Research
var age := 0
var now_ms := 0
## Rodzaj budynku w trybie budynku albo -1 w trybie globalnym.
var building_kind := -1
## Konkretny budynek w trybie budynku (0 w trybie globalnym).
var building_id := 0
var selected := 0
## Oddział, do którego trafi następna jednostka (Recruitment.NEW_SQUAD = nowy).
var target_squad := Recruitment.NEW_SQUAD
var content_left := float(Hud.CORNER_INSET)
var content_right := 320.0 - Hud.CORNER_INSET

var _pressed: int = Target.NONE


## Otwiera ekran: `id` = 0 dla widoku globalnego, inaczej budynek rekrutacji.
func open(id: int = 0) -> void:
	building_id = id
	building_kind = grid.kinds[id] if id != 0 and grid.buildings.has(id) else -1
	visible = true
	_pressed = Target.NONE
	var list := units()
	if not list.has(selected) and not list.is_empty():
		selected = list[0]
	select(selected)


## Wybiera jednostkę i domyślny oddział: pierwszy jej oddział z wolnym miejscem albo nowy.
func select(unit: int) -> void:
	selected = unit
	target_squad = recruitment.default_squad(unit)


func close() -> void:
	visible = false
	closed.emit()


## Jednostki widoczne w bieżącym trybie, w kolejności UnitTypes.Unit.
func units() -> Array[int]:
	return units_for(building_kind)


static func units_for(kind: int) -> Array[int]:
	var out: Array[int] = []
	for unit in UnitTypes.count():
		if kind < 0 or UnitTypes.building(unit) == kind:
			out.append(unit)
	return out


## Czy budynek rodzaju `kind` szkoli jakąkolwiek jednostkę (karta pokazuje wtedy Szkol).
static func recruits(kind: int) -> bool:
	return not units_for(kind).is_empty()


func _process(_delta: float) -> void:
	if not visible:
		return
	var bounds := Hud.content_bounds(get_viewport_rect().size, Hud.safe_area_in_view(get_viewport()))
	content_left = bounds.x
	content_right = bounds.y
	queue_redraw()


# --- Układ -----------------------------------------------------------------------------------

static func tile_rects(left: float, right: float, count: int) -> Array[Rect2]:
	var w := floorf((right - left - (TILE_COLS - 1) * GAP) / TILE_COLS)
	var out: Array[Rect2] = []
	for i in count:
		@warning_ignore("integer_division")
		var row := i / TILE_COLS
		out.append(Rect2(left + (i % TILE_COLS) * (w + GAP), GRID_Y + row * (TILE_H + GAP), w, TILE_H))
	return out


## Miejsca w rzędzie wyboru oddziału: pierwsze to Nowy, dalej istniejące oddziały.
static func squad_rects(left: float, right: float, count: int) -> Array[Rect2]:
	var fit := int((right - left + GAP) / (SQUAD_W + GAP))
	var out: Array[Rect2] = []
	for i in mini(count, fit):
		out.append(Rect2(left + i * (SQUAD_W + GAP), SQUAD_Y, SQUAD_W, SQUAD_H))
	return out


## Oddziały do wyboru dla jednostki: NEW_SQUAD, a za nim jej oddziały w kolejności założenia.
static func squad_options(r: Recruitment, unit: int) -> Array[int]:
	var out: Array[int] = [Recruitment.NEW_SQUAD]
	for sq in r.squads_of(unit):
		out.append(sq.id)
	return out


## Napis na miejscu oddziału, np. „Nowy” albo „2: 7/10” (numer oddziału tego rodzaju,
## jednostki wyszkolone i w szkoleniu, rozmiar oddziału).
static func squad_label(r: Recruitment, unit: int, squad_id: int) -> String:
	if squad_id == Recruitment.NEW_SQUAD:
		return NEW_SQUAD_LABEL
	var list := r.squads_of(unit)
	for i in list.size():
		if list[i].id == squad_id:
			return "%d: %d/%d" % [i + 1, list[i].count + r.pending_for(squad_id), RecruitmentConfig.SQUAD_SIZE]
	return "?"


static func train_rect(view: Vector2, right: float) -> Rect2:
	return Hud.research_rect(view, right)


static func close_rect(view: Vector2, right: float) -> Rect2:
	return Hud.right_corner_rect(view, right)


static func target_at(p: Vector2, view: Vector2, left: float, right: float, count: int, squad_count: int = 0) -> int:
	if close_rect(view, right).has_point(p):
		return Target.CLOSE
	if train_rect(view, right).has_point(p):
		return Target.TRAIN
	var sq := Hud.hit(squad_rects(left, right, squad_count), p)
	if sq >= 0:
		return Target.SQUAD + sq
	var tile := Hud.hit(tile_rects(left, right, count), p)
	return Target.TILE + tile if tile >= 0 else Target.NONE


# --- Teksty ------------------------------------------------------------------------------------

## Dlaczego jednostki nie da się szkolić albo ile jest jej w armii.
static func state_text(r: Recruitment, unit: int, g: BuildGrid, res: Research, current_age: int) -> String:
	match r.availability(unit, g, res, current_age):
		Recruitment.Result.WRONG_AGE:
			return TechTree.age_label(UnitTypes.age(unit))
		Recruitment.Result.NEEDS_TECH:
			return "zbadaj %s" % UnitTypes.required_tech(unit)
		Recruitment.Result.NO_BUILDING:
			var kind := UnitTypes.building(unit)
			return "brak: %s" % (BuildingTypes.NAMES[kind] if kind >= 0 else "budynku")
	return "w armii %d" % r.army_of(unit)


## Koszt jako tekst, np. „10 Ży, 1 Łuk, 20 Strzały”.
static func cost_text(unit: int) -> String:
	var parts: PackedStringArray = []
	var res_cost := UnitTypes.resource_cost(unit)
	for res: int in res_cost:
		parts.append("%d %s" % [int(res_cost[res]), EconomyConfig.SHORT_NAMES[res]])
	var goods_cost := UnitTypes.goods_cost(unit)
	for good: int in goods_cost:
		parts.append("%d %s" % [int(goods_cost[good]), GoodsConfig.NAMES[good]])
	return ", ".join(parts)


## Brakujące towary z budynkiem, który je robi, np. „Brak: 1 Łuk (Łukmistrz)”. Pusty, gdy niczego
## nie brakuje.
static func missing_text(unit: int, g: Goods) -> String:
	var missing := Recruitment.missing_goods(unit, g)
	if missing.is_empty():
		return ""
	var parts: PackedStringArray = []
	for good: int in missing:
		var maker := GoodsConfig.producer_name(good)
		parts.append("%d %s (%s)" % [int(missing[good]), GoodsConfig.NAMES[good], maker] if not maker.is_empty()
				else "%d %s" % [int(missing[good]), GoodsConfig.NAMES[good]])
	return "Brak: " + ", ".join(parts)


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
	var t := target_at(touch.position, get_viewport_rect().size, content_left, content_right, units().size(),
			squad_options(recruitment, selected).size())
	if touch.pressed:
		_pressed = t
		return
	var was := _pressed
	_pressed = Target.NONE
	if was != Target.NONE and t == was:
		_activate(was)


func _activate(t: int) -> void:
	if t >= Target.SQUAD:
		var sq: int = squad_options(recruitment, selected)[t - Target.SQUAD]
		if sq == Recruitment.NEW_SQUAD or recruitment.free_in_squad(sq) > 0:
			target_squad = sq
	elif t >= Target.TILE:
		select(units()[t - Target.TILE])
	elif t == Target.TRAIN:
		train_requested.emit(selected, target_squad)
	elif t == Target.CLOSE:
		close()


# --- Rysowanie ---------------------------------------------------------------------------------

func _draw() -> void:
	if recruitment == null:
		return
	var view := get_viewport_rect().size
	draw_rect(Rect2(0, Hud.BAR_H, view.x, view.y - 2 * Hud.BAR_H), Color(Palette.SHADOW, 0.92))
	var title := "Wojsko: %d/%d, wolne %d" % [recruitment.army_size() + recruitment.orders.size(),
			Recruitment.army_limit(grid), recruitment.free_army(grid)]
	PixelFont.draw_text(self, Vector2(content_left, TITLE_Y), title, Palette.INK)
	var mode := BuildingTypes.NAMES[building_kind] if building_kind >= 0 else "wszystkie jednostki"
	PixelFont.draw_right(self, content_right, TITLE_Y, mode, Palette.THATCH[2])
	var list := units()
	var tiles := tile_rects(content_left, content_right, list.size())
	for i in list.size():
		_draw_tile(tiles[i], list[i], list[i] == selected or _pressed == Target.TILE + i)
	_draw_details()
	var can_train := recruitment.availability(selected, grid, research, age) == Recruitment.Result.OK
	Hud.paint_button(self, train_rect(view, content_right), TRAIN_LABEL, _pressed == Target.TRAIN, not can_train)
	Hud.paint_button(self, close_rect(view, content_right), CLOSE_LABEL, _pressed == Target.CLOSE, false)


func _draw_tile(r: Rect2, unit: int, active: bool) -> void:
	draw_rect(r, Palette.WOOD[2] if active else Palette.WOOD[1])
	var available := recruitment.availability(unit, grid, research, age) == Recruitment.Result.OK
	var col: Color = Palette.INK if available else Palette.WOOD[0]
	var icon_y := r.position.y + floorf((r.size.y - PixelIcons.SIZE) / 2.0)
	var unit_class := UnitTypes.unit_class(unit)
	if unit_class >= 0:
		# ciemne tło pod ikoną, żeby brązowa tarcza nie znikała na drewnianym kafelku
		draw_rect(Rect2(r.position.x + 1, icon_y - 1, PixelIcons.SIZE + 2, PixelIcons.SIZE + 2), Palette.SHADOW)
		PixelIcons.draw_class(self, Vector2(r.position.x + 2, icon_y), unit_class)
	var text_y := r.position.y + floorf((r.size.y - PixelFont.LINE) / 2.0)
	PixelFont.draw_text(self, Vector2(r.position.x + 9, text_y), UnitTypes.SHORT_NAMES[unit], col)
	var count := "%d" % recruitment.army_of(unit)
	var training := recruitment.in_training(unit)
	if training > 0:
		count += "+%d" % training
	PixelFont.draw_right(self, r.end.x - 2, text_y, count, Palette.VALID if available else col)


func _draw_details() -> void:
	var x := content_left
	var y := float(DETAIL_Y)
	PixelFont.draw_text(self, Vector2(x, y), UnitTypes.unit_name(selected), Palette.INK)
	PixelFont.draw_right(self, content_right, y, state_text(recruitment, selected, grid, research, age), Palette.THATCH[2])
	y += PixelFont.LINE + 2
	var width := int(content_right - content_left)
	var cost := "Koszt: %s, %s" % [cost_text(selected),
			Hud.format_time(RecruitmentConfig.train_ms(selected, 1))]
	PixelFont.draw_text(self, Vector2(x, y), ResearchPanel.fit_text(cost, width), Palette.INK)
	y += PixelFont.LINE + 2
	var missing := missing_text(selected, goods)
	var queued := recruitment.orders.size()
	if building_id != 0:
		queued = recruitment.queue_of(building_id).size()
	if not missing.is_empty():
		PixelFont.draw_text(self, Vector2(x, y), ResearchPanel.fit_text(missing, width), Palette.ACCENT)
	elif queued > 0:
		var line := "W szkoleniu: %d" % queued
		if building_id != 0:
			line += ", koniec za %s" % Hud.format_time(recruitment.remaining_ms(building_id, now_ms))
		PixelFont.draw_text(self, Vector2(x, y), line, Palette.WOOD[3])
	_draw_squads()


## Rząd wyboru oddziału: Nowy i oddziały wybranej jednostki; pełne są przygaszone.
func _draw_squads() -> void:
	var options := squad_options(recruitment, selected)
	var rects := squad_rects(content_left, content_right, options.size())
	for i in rects.size():
		var sq := options[i]
		var full := sq != Recruitment.NEW_SQUAD and recruitment.free_in_squad(sq) <= 0
		Hud.paint_button(self, rects[i], squad_label(recruitment, selected, sq),
				sq == target_squad or _pressed == Target.SQUAD + i, full)
