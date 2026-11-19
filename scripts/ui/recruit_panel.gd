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
## Przycisk Opis przełącza szczegóły: koszt → opis jednostki → produkcja cywilna (postawieni
## wytwórcy: chata drwala, drzewcarz i inni) → zapas zbrojowni (towary do jednostek) → koszt.
## Dolne przyciski są mniejsze niż w reszcie HUD-u, a między nimi stoi pasek zapasu zbrojowni:
## ikona towaru i liczba sztuk (dotknięcie pokazuje zapas z nazwami w szczegółach).

signal train_requested(unit: int, squad_id: int)
signal closed
## Dotknięto licznika armii w tytule (okienko z limitem, InfoText.army).
signal limit_pressed

enum Target { NONE = -1, CLOSE = 1, TRAIN = 2, INFO = 3, LIMIT = 4, STOCK = 5, TILE = 200, SQUAD = 300 }
## Tryb szczegółów pod kafelkami: koszt, opis, produkcja cywilna albo zapas zbrojowni.
enum DetailMode { COST, INFO, PRODUCTION, STOCK }

const TITLE_Y := Hud.BAR_H + 3
const GRID_Y := TITLE_Y + 11
const TILE_COLS := 3
const TILE_H := 12
const GAP := 2
## Odstęp między rzędami kafelków (1 px, żeby szczegóły miały 4 linie).
const ROW_GAP := 1
const MAX_ROWS := 5
const DETAIL_Y := GRID_Y + MAX_ROWS * (TILE_H + ROW_GAP) + 1
## Linie szczegółów między kafelkami a rzędem oddziałów: nazwa i stan, koszt, braki (do 2 linii).
const DETAIL_LINES := 4
## Braki towarów (albo szkolenie) dostają najwyżej tyle linii.
const EXTRA_LINES := 2
const LINE_STEP := PixelFont.LINE + 2
## Rząd wyboru oddziału na pełnej szerokości treści, tuż nad przyciskami Szkol i Zamknij (review #156:
## w rzędzie przycisków na wąskim ekranie mieściły się tylko dwa miejsca).
const SQUAD_Y := DETAIL_Y + DETAIL_LINES * LINE_STEP
const SQUAD_W := 40
const SQUAD_H := 12
const NEW_SQUAD_LABEL := "Nowy"
## Dolne przyciski (Koszt/Opis, Szkol, Zamknij): mniejsze niż Hud.BUTTON_SIZE, żeby między nimi
## zmieścił się pasek zapasu; wciąż ponad minimum 12×12 px z CLAUDE.md.
const BUTTON_SIZE := Vector2(40, 12)
const BUTTON_GAP := 3
## Pasek zapasu zbrojowni: 2 rzędy po linii fontu, komórka to ikona 5 px, 1 px odstępu,
## liczba do 3 cyfr (11 px) i 3 px przerwy.
const STOCK_ROWS := 2
const STOCK_CELL_W := 20
const TRAIN_LABEL := "Szkol"
const INFO_LABEL := "Opis"
const COST_LABEL := "Koszt"
const PROD_LABEL := "Prod."
const PROD_TITLE := "Produkcja cywilna"
const PROD_STATE := "wytwórcy"
const PROD_EMPTY := "Brak wytwórców. Postaw Chatę drwala lub Drzewcarza (Buduj)."
const STOCK_LABEL := "Zapas"
const STOCK_TITLE := "Zbrojownia"
const STOCK_STATE := "zapas"
const STOCK_EMPTY := "Pusto. Wyprodukuj broń i zbroję u wytwórców (Buduj)."
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
## Co pokazują szczegóły: koszt, opis, produkcję cywilną albo zapas zbrojowni.
var detail_mode := DetailMode.COST
var content_left := float(Hud.CORNER_INSET)
var content_right := 320.0 - Hud.CORNER_INSET

var _pressed: int = Target.NONE


## Otwiera ekran: `id` = 0 dla widoku globalnego, inaczej budynek rekrutacji.
func open(id: int = 0) -> void:
	building_id = id
	building_kind = grid.kinds[id] if id != 0 and grid.buildings.has(id) else -1
	visible = true
	_pressed = Target.NONE
	detail_mode = DetailMode.COST
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


## Jednostki widoczne w bieżącym trybie, w kolejności units_for (Chłop i inne ERA_I_ONLY na początku).
func units() -> Array[int]:
	return units_for(building_kind)


## Jednostki do szkolenia w budynku `kind` (wszystkie przy -1). Jednostki epoki I bez wymagań
## (Chłop) stoją na początku listy, bo od nich zaczyna się gra.
static func units_for(kind: int) -> Array[int]:
	var out: Array[int] = []
	for unit: int in UnitTypes.ERA_I_ONLY:
		if kind < 0 or UnitTypes.building(unit) == kind:
			out.append(unit)
	for unit in UnitTypes.count():
		if not UnitTypes.ERA_I_ONLY.has(unit) and (kind < 0 or UnitTypes.building(unit) == kind):
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
		out.append(Rect2(left + (i % TILE_COLS) * (w + GAP), GRID_Y + row * (TILE_H + ROW_GAP), w, TILE_H))
	return out


## Miejsca w rzędzie wyboru oddziału na całej szerokości treści: pierwsze to Nowy, dalej istniejące
## oddziały.
static func squad_rects(left: float, right: float, count: int) -> Array[Rect2]:
	var fit := int((right - left + GAP) / (SQUAD_W + GAP))
	var out: Array[Rect2] = []
	for i in mini(count, fit):
		out.append(Rect2(left + i * (SQUAD_W + GAP), SQUAD_Y, SQUAD_W, SQUAD_H))
	return out


## Linie szczegółów jednostki, już zawinięte do `width` px: [tekst, kolor]. Nazwa i stan dzielą
## pierwszą linię, gdy się mieszczą; inaczej stan idzie do drugiej. Koszt i braki zawijają się
## po słowach, a całość mieści się w DETAIL_LINES.
static func detail_lines(name: String, state: String, cost: String, extra: String, extra_col: Color,
		width: int) -> Array:
	var out: Array = []
	if PixelFont.text_width(name) + 6 + PixelFont.text_width(state) <= width:
		out.append([name, Palette.INK, state])
	else:
		for l in PixelFont.wrap(name, width, 1):
			out.append([l, Palette.INK, ""])
		out.append([PixelFont.wrap(state, width, 1)[0] if not state.is_empty() else "", Palette.THATCH[2], ""])
	var room := DETAIL_LINES - out.size()
	var extra_lines := PixelFont.wrap(extra, width) if not extra.is_empty() else PackedStringArray()
	# braki mają pierwszeństwo (do EXTRA_LINES linii), koszt dostaje resztę, ale co najmniej jedną
	var cost_room := maxi(1, room - mini(extra_lines.size(), EXTRA_LINES))
	for l in PixelFont.wrap(cost, width, cost_room):
		out.append([l, Palette.INK, ""])
	room = mini(DETAIL_LINES - out.size(), EXTRA_LINES)
	if room > 0 and not extra.is_empty():
		for l in PixelFont.wrap(extra, width, room):
			out.append([l, extra_col, ""])
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


## Górna krawędź dolnych przycisków: dolny brzeg w tym samym miejscu co przyciski HUD-u.
static func button_y(view: Vector2) -> float:
	return view.y - Hud.BAR_H - BUTTON_SIZE.y - 4


static func train_rect(view: Vector2, right: float) -> Rect2:
	return Rect2(Vector2(right - 2 * BUTTON_SIZE.x - BUTTON_GAP, button_y(view)), BUTTON_SIZE)


static func close_rect(view: Vector2, right: float) -> Rect2:
	return Rect2(Vector2(right - BUTTON_SIZE.x, button_y(view)), BUTTON_SIZE)


## Przycisk Opis/Prod./Zapas/Koszt w dolnym rzędzie przy lewej granicy treści: przełącza
## szczegóły między kosztem, opisem, produkcją cywilną i zapasem zbrojowni.
static func info_rect(view: Vector2, left: float) -> Rect2:
	return Rect2(Vector2(left, button_y(view)), BUTTON_SIZE)


## Pasek zapasu zbrojowni między przyciskiem trybu a Szkol: dwa rzędy po linii fontu, dolny
## kończy się z przyciskami. Pusty (bez pola), gdy na wąskim ekranie nie ma miejsca.
static func stock_rect(view: Vector2, left: float, right: float) -> Rect2:
	var x := info_rect(view, left).end.x + BUTTON_GAP
	var w := train_rect(view, right).position.x - BUTTON_GAP - x
	var h := STOCK_ROWS * PixelFont.LINE
	if w < STOCK_CELL_W:
		return Rect2()
	return Rect2(x, button_y(view) + BUTTON_SIZE.y - h, w, h)


## Liczba sztuk na pasku: do 3 cyfr, od tysiąca w tysiącach („1k”; zbrojownia mieści 1000).
static func stock_count_text(amount: int) -> String:
	if amount >= 1000:
		@warning_ignore("integer_division")
		return "%dk" % (amount / 1000)
	return "%d" % amount


## Towary na pasku zapasu, który mieści `cells` komórek: wszystkie towary jednostek w stałej
## kolejności, a gdy się nie mieszczą, tylko te, których coś leży w zbrojowni.
static func stock_strip(g: Goods, cells: int) -> Array[int]:
	var all := unit_goods()
	if all.size() <= cells:
		return all
	var out: Array[int] = []
	for good in all:
		if out.size() < cells and g != null and good < g.amounts.size() and g.amounts[good] > 0:
			out.append(good)
	return out


## Pozycje komórek paska zapasu (lewy górny róg linii), wierszami od lewej; zajęte kolumny stoją
## na środku paska (w całych pikselach).
static func stock_cells(r: Rect2, count: int) -> Array[Vector2]:
	var cols := int((r.size.x + 3) / STOCK_CELL_W) if r.has_area() else 0
	var out: Array[Vector2] = []
	var n := mini(count, cols * STOCK_ROWS)
	if n == 0:
		return out
	@warning_ignore("integer_division")
	var used := mini(cols, (n + STOCK_ROWS - 1) / STOCK_ROWS)
	var x0 := r.position.x + floorf((r.size.x - (used * STOCK_CELL_W - 3)) / 2.0)
	for i in n:
		@warning_ignore("integer_division")
		out.append(Vector2(x0 + (i % used) * STOCK_CELL_W, r.position.y + (i / used) * PixelFont.LINE))
	return out


## Napis na przycisku trybu szczegółów: następny tryb (Koszt → Opis → Prod. → Zapas → Koszt).
static func mode_button_label(mode: int) -> String:
	match mode:
		DetailMode.COST:
			return INFO_LABEL
		DetailMode.INFO:
			return PROD_LABEL
		DetailMode.PRODUCTION:
			return STOCK_LABEL
		_:
			return COST_LABEL


## Linie opisu jednostki [tekst, kolor, tekst z prawej] pod linią nazwy: rola (zawinięta) i przewagi.
static func info_lines(unit: int, width: int, room: int) -> Array:
	var out: Array = []
	var counters := PixelFont.wrap(UnitTypes.counters_text(unit), width, 2)
	for l in PixelFont.wrap(UnitTypes.ROLES[unit], width, maxi(1, room - counters.size())):
		out.append([l, Palette.THATCH[2], ""])
	for l in counters:
		if out.size() < room:
			out.append([l, Palette.INK, ""])
	return out


## Licznik armii w tytule jako cel dotyku: lewa połowa wiersza tytułu, 12 px wysokości.
static func limit_rect(left: float, right: float) -> Rect2:
	return Rect2(left, TITLE_Y - 2, floorf((right - left) / 2.0), 12)


## Tytuł ekranu z licznikiem armii, np. „Wojsko: 12/12, wolne 0 (?)”; znak zapytania mówi, że
## licznik da się dotknąć.
static func title_text(r: Recruitment, g: BuildGrid) -> String:
	return "Wojsko: %d/%d, wolne %d (?)" % [r.army_size() + r.orders.size(), Recruitment.army_limit(g), r.free_army(g)]

## Teksty produkcji postawionych wytwórców cywilnych z danych gry (EconomyConfig / GoodsConfig):
## np. „Chata drwala ×2: +150 Dr/h”, „Drzewcarz ×1: Topór kamienny 2/h, Oszczep 6/h”.
static func civilian_texts(g: BuildGrid) -> PackedStringArray:
	var out: PackedStringArray = []
	if g == null:
		return out
	for kind: int in EconomyConfig.BUILDING_PRODUCTION:
		var n := 0
		var sum := 0
		var entry: Array = EconomyConfig.BUILDING_PRODUCTION[kind]
		var res: int = entry[0]
		var per_level: Array = entry[1]
		for id: int in g.buildings:
			if g.kinds[id] == kind and g.levels[id] >= 1:
				n += 1
				sum += int(per_level[clampi(g.levels[id], 1, per_level.size()) - 1])
		if n > 0:
			out.append("%s ×%d: +%d %s/h" % [BuildingTypes.NAMES[kind], n, sum, EconomyConfig.SHORT_NAMES[res]])
	var by_producer := Goods.producers(g)
	for producer: String in GoodsConfig.PRODUCERS:
		var levels: Array = by_producer.get(producer, [])
		if levels.is_empty():
			continue
		var goods_rate := {}
		var res_rate := {}
		for level: int in levels:
			for recipe in GoodsConfig.RECIPES.size():
				var row: Array = GoodsConfig.RECIPES[recipe]
				if row[0] != producer:
					continue
				var cph := GoodsConfig.cycles_per_hour(recipe, level)
				if cph <= 0:
					continue
				for good: int in row[5] as Dictionary:
					goods_rate[good] = int(goods_rate.get(good, 0)) + cph * int((row[5] as Dictionary)[good])
				for res: int in row[6] as Dictionary:
					res_rate[res] = int(res_rate.get(res, 0)) + cph * int((row[6] as Dictionary)[res])
		var parts: PackedStringArray = []
		for recipe in GoodsConfig.RECIPES.size():
			var row: Array = GoodsConfig.RECIPES[recipe]
			if row[0] != producer:
				continue
			for good: int in row[5] as Dictionary:
				if goods_rate.has(good):
					parts.append("%s %d/h" % [GoodsConfig.NAMES[good], int(goods_rate[good])])
					goods_rate.erase(good)
		for res: int in EconomyConfig.count():
			if res_rate.has(res):
				parts.append("+%d %s/h" % [int(res_rate[res]), EconomyConfig.SHORT_NAMES[res]])
		if not parts.is_empty():
			out.append("%s ×%d: %s" % [GoodsConfig.PRODUCER_NAMES[producer], levels.size(), ", ".join(parts)])
	return out


## Linie produkcji cywilnej [tekst, kolor, ""] pod tytułem trybu; puste, gdy brak postawionych wytwórców.
static func civilian_lines(g: BuildGrid, width: int, room: int) -> Array:
	var out: Array = []
	var texts := civilian_texts(g)
	if texts.is_empty():
		for l in PixelFont.wrap(PROD_EMPTY, width, room):
			out.append([l, Palette.THATCH[2], ""])
		return out
	for text in texts:
		if out.size() >= room:
			break
		for l in PixelFont.wrap(text, width, room - out.size()):
			out.append([l, Palette.INK, ""])
			if out.size() >= room:
				break
	return out


## Towary używane przy szkoleniu jednostek (broń, zbroja, koń…), w kolejności GoodsConfig.
static func unit_goods() -> Array[int]:
	var needed := {}
	for unit in UnitTypes.count():
		for good: int in UnitTypes.goods_cost(unit):
			needed[good] = true
	var out: Array[int] = []
	for good in GoodsConfig.count():
		if needed.has(good):
			out.append(good)
	return out


## Zapisy zapasu towarów jednostkowych ze zbrojowni (`goods.amounts`), np. „1 Łuk”, „40 Strzały”.
## Puste, gdy nic nie leży w magazynie.
static func stock_texts(g: Goods) -> PackedStringArray:
	var out: PackedStringArray = []
	if g == null:
		return out
	for good in unit_goods():
		if good < g.amounts.size() and g.amounts[good] > 0:
			out.append("%d %s" % [g.amounts[good], GoodsConfig.NAMES[good]])
	return out


## Linie zapasu zbrojowni [tekst, kolor, ""] pod tytułem trybu; podpowiedź, gdy pusto.
static func stock_lines(g: Goods, width: int, room: int) -> Array:
	var out: Array = []
	var texts := stock_texts(g)
	if texts.is_empty():
		for l in PixelFont.wrap(STOCK_EMPTY, width, room):
			out.append([l, Palette.THATCH[2], ""])
		return out
	for l in PixelFont.wrap(", ".join(texts), width, room):
		out.append([l, Palette.INK, ""])
	return out


static func target_at(p: Vector2, view: Vector2, left: float, right: float, count: int, squad_count: int = 0) -> int:
	if close_rect(view, right).has_point(p):
		return Target.CLOSE
	if limit_rect(left, right).has_point(p):
		return Target.LIMIT
	if info_rect(view, left).has_point(p):
		return Target.INFO
	if train_rect(view, right).has_point(p):
		return Target.TRAIN
	if stock_rect(view, left, right).has_point(p):
		return Target.STOCK
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
		Recruitment.Result.ERA_PASSED:
			return "tylko epoka I"
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


## Brakujące towary pogrupowane według budynku, który je robi, np. „Brak: 1 Przeszywanica,
## 1 Tarcza (Wytwórca zbroi skórzanych), 20 Strzały (Strzałmistrz)”. Nazwa budynku pada raz na
## grupę, żeby tekst mieścił się w dwóch liniach. Pusty, gdy niczego nie brakuje.
static func missing_text(unit: int, g: Goods) -> String:
	var missing := Recruitment.missing_goods(unit, g)
	if missing.is_empty():
		return ""
	var makers: PackedStringArray = []
	var groups := {}
	for good: int in missing:
		var maker := GoodsConfig.producer_name(good)
		if not groups.has(maker):
			groups[maker] = []  # Array, bo PackedStringArray w słowniku to kopia
			makers.append(maker)
		(groups[maker] as Array).append("%d %s" % [int(missing[good]), GoodsConfig.NAMES[good]])
	var parts: PackedStringArray = []
	for maker in makers:
		var goods_list := ", ".join(PackedStringArray(groups[maker] as Array))
		parts.append(goods_list if maker.is_empty() else "%s (%s)" % [goods_list, maker])
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
	elif t == Target.INFO:
		detail_mode = (detail_mode + 1) % DetailMode.size()
	elif t == Target.STOCK:
		detail_mode = DetailMode.STOCK
	elif t == Target.LIMIT:
		limit_pressed.emit()
	elif t == Target.CLOSE:
		close()


# --- Rysowanie ---------------------------------------------------------------------------------

## Wynik próby szkolenia wybranej jednostki do `target_squad`, bez zmiany stanu. Przycisk Szkol
## gaśnie przy każdej przeszkodzie: pełna armia, kolejka albo oddział, brak surowców lub towarów.
func train_check() -> Recruitment.Result:
	if building_id != 0:
		return recruitment.check(selected, building_id, target_squad, grid, economy, goods, research, age)
	return recruitment.check_any(selected, target_squad, grid, economy, goods, research, age)


func _draw() -> void:
	if recruitment == null:
		return
	var view := get_viewport_rect().size
	draw_rect(Rect2(0, Hud.BAR_H, view.x, view.y - 2 * Hud.BAR_H), Color(Palette.SHADOW, 0.92))
	var full := recruitment.free_army(grid) <= 0
	PixelFont.draw_text(self, Vector2(content_left, TITLE_Y), title_text(recruitment, grid),
			Palette.ACCENT if full else Palette.INK)
	var mode := BuildingTypes.NAMES[building_kind] if building_kind >= 0 else "wszystkie jednostki"
	PixelFont.draw_right(self, content_right, TITLE_Y, mode, Palette.THATCH[2])
	var list := units()
	var tiles := tile_rects(content_left, content_right, list.size())
	for i in list.size():
		_draw_tile(tiles[i], list[i], list[i] == selected or _pressed == Target.TILE + i)
	_draw_details()
	var can_train := train_check() == Recruitment.Result.OK
	Hud.paint_button(self, train_rect(view, content_right), TRAIN_LABEL, _pressed == Target.TRAIN, not can_train)
	Hud.paint_button(self, info_rect(view, content_left), mode_button_label(detail_mode),
			_pressed == Target.INFO or detail_mode != DetailMode.COST, false)
	Hud.paint_button(self, close_rect(view, content_right), CLOSE_LABEL, _pressed == Target.CLOSE, false)
	_draw_stock(view)


## Pasek zapasu: ikona towaru i liczba sztuk. Pusty towar jest przygaszony, a towar, którego
## brakuje wybranej jednostce, świeci kolorem braku.
func _draw_stock(view: Vector2) -> void:
	var r := stock_rect(view, content_left, content_right)
	if not r.has_area() or goods == null:
		return
	if _pressed == Target.STOCK:
		draw_rect(r, Palette.WOOD[1])
	var cols := int((r.size.x + 3) / STOCK_CELL_W)
	var strip := stock_strip(goods, cols * STOCK_ROWS)
	var cells := stock_cells(r, strip.size())
	var missing := Recruitment.missing_goods(selected, goods)
	for i in cells.size():
		var good := strip[i]
		var amount: int = goods.amounts[good] if good < goods.amounts.size() else 0
		var col: Color = Palette.INK
		if missing.has(good):
			col = Palette.ACCENT
		elif amount <= 0:
			col = Palette.WOOD[2]
		PixelIcons.draw_good(self, cells[i] + Vector2(0, PixelFont.CAP_TOP), good)
		PixelFont.draw_text(self, cells[i] + Vector2(PixelIcons.SIZE + 1, 0), stock_count_text(amount), col)


func _draw_tile(r: Rect2, unit: int, active: bool) -> void:
	draw_rect(r, Palette.WOOD[2] if active else Palette.WOOD[1])
	var available := recruitment.availability(unit, grid, research, age) == Recruitment.Result.OK
	var col: Color = Palette.INK if available else Palette.WOOD[0]
	var icon_y := r.position.y + floorf((r.size.y - PixelIcons.SIZE) / 2.0)
	var unit_class := UnitTypes.unit_class(unit)
	if unit_class >= 0:
		PixelIcons.draw_class_badge(self, Vector2(r.position.x + 2, icon_y), unit_class)
	var text_y := r.position.y + floorf((r.size.y - PixelFont.LINE) / 2.0)
	PixelFont.draw_text(self, Vector2(r.position.x + 9, text_y), UnitTypes.SHORT_NAMES[unit], col)
	var count := "%d" % recruitment.army_of(unit)
	var training := recruitment.in_training(unit)
	if training > 0:
		count += "+%d" % training
	PixelFont.draw_right(self, r.end.x - 2, text_y, count, Palette.VALID if available else col)


func _draw_details() -> void:
	var width := int(content_right - content_left)
	var cost := "Koszt: %s, %s" % [cost_text(selected),
			Hud.format_time(RecruitmentConfig.train_ms(selected, 1))]
	var extra := missing_text(selected, goods)
	var extra_col: Color = Palette.ACCENT
	var queued := recruitment.orders.size()
	if building_id != 0:
		queued = recruitment.queue_of(building_id).size()
	if extra.is_empty() and queued > 0:
		extra = "W szkoleniu: %d" % queued
		if building_id != 0:
			extra += ", koniec za %s" % Hud.format_time(recruitment.remaining_ms(building_id, now_ms))
		extra_col = Palette.WOOD[3]
	var lines := detail_lines(UnitTypes.unit_name(selected), state_text(recruitment, selected, grid, research, age),
			cost, extra, extra_col, width)
	if detail_mode == DetailMode.INFO:
		lines = lines.slice(0, 1) + info_lines(selected, width, DETAIL_LINES - 1)
	elif detail_mode == DetailMode.PRODUCTION:
		lines = detail_lines(PROD_TITLE, PROD_STATE, "", "", Palette.INK, width).slice(0, 1)
		lines.append_array(civilian_lines(grid, width, DETAIL_LINES - 1))
	elif detail_mode == DetailMode.STOCK:
		lines = detail_lines(STOCK_TITLE, STOCK_STATE, "", "", Palette.INK, width).slice(0, 1)
		lines.append_array(stock_lines(goods, width, DETAIL_LINES - 1))
	var y := float(DETAIL_Y)
	var res_cost: Array[int] = []
	res_cost.resize(EconomyConfig.count())
	var unit_cost := UnitTypes.resource_cost(selected)
	for res: int in unit_cost:
		res_cost[res] = int(unit_cost[res])
	var missing_res := Hud.missing_tokens(res_cost, economy.amounts) if economy != null else PackedStringArray()
	if detail_mode != DetailMode.COST:
		missing_res = PackedStringArray()
	for l: Array in lines:
		Hud.draw_highlighted(self, Vector2(content_left, y), l[0] as String, l[1] as Color, missing_res, Palette.ACCENT)
		if not (l[2] as String).is_empty():
			PixelFont.draw_right(self, content_right, y, l[2] as String, Palette.THATCH[2])
		y += LINE_STEP
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
