class_name QueuePanel
extends Node2D
## Ekran Kolejka (#163) na całą mapę, w układzie drzewka badań i panelu budowy: u góry zakładki
## Budynki i Jednostki z liczbą zleceń, pod nimi lista, na dole stan kolejki albo armii i przyciski.
## - Budynki: zlecenia BuildQueue w kolejności wykonania (nazwa, „nowy” albo „poz. N→N+1”, czas;
##   pierwsze z paskiem postępu, czekające z napisem „czeka”). Anuluj przy wierszu prosi o drugie
##   dotknięcie (komunikat podaje zwrot kosztu), potem zlecenie znika. Dotknięcie wiersza pokazuje
##   budynek na mapie i zamyka ekran.
## - Jednostki: kolejki szkolenia pogrupowane według budynku rekrutacji (Koszary, Dom drużyny,
##   Strzelnica, Stajnia…): jednostka, oddział docelowy i czas; trwające szkolenie z paskiem.
## Pusta zakładka ma krótki tekst i przycisk do Buduj albo Wojsko. Gdy wiersze się nie mieszczą,
## Dalej przewija listę. Zamknij albo dotknięcie pustego miejsca wraca do mapy. Lista liczy się
## z danych co klatkę (tylko tekst i prostokąty, bez tekstur), więc czasy i paski idą na żywo.

signal closed
## Anulowanie zlecenia budowy (po potwierdzeniu) i pokazanie budynku na mapie.
signal cancel_requested(building_id: int)
signal focus_requested(building_id: int)
## Przycisk z pustej zakładki: Buduj albo Wojsko.
signal build_requested
signal army_requested
## Komunikat dla paska HUD (np. prośba o potwierdzenie anulowania).
signal message(text: String)

enum Tab { BUILDINGS, UNITS }
enum Target { NONE = -1, CLOSE = 1, ACTION = 2, MORE = 3, TAB = 100, ROW = 200, CANCEL = 300 }

const TAB_NAMES: Array[String] = ["Budynki", "Jednostki"]
const TAB_Y := ResearchPanel.TAB_Y
const TAB_H := ResearchPanel.TAB_H
const LIST_Y := ResearchPanel.GRID_Y
## Wiersz 14 px, żeby Anuluj miał 12 px wysokości (minimum celu dotyku z CLAUDE.md, review #183).
const ROW_H := 14
const ROW_GAP := 1
const CANCEL_W := 40
## Kolumna poziomu albo oddziału w wierszu (od lewego brzegu nazwy) i miejsce na nazwę przed nią.
const SECOND_X := 90
const TITLE_W := SECOND_X - 4
const CLOSE_LABEL := "Zamknij"
const MORE_LABEL := "Dalej"
const CANCEL_LABEL := "Anuluj"
const CONFIRM_LABEL := "Na pewno"
const EMPTY_TEXTS: Array[String] = ["Nic się nie buduje", "Nikt się nie szkoli"]
const ACTION_LABELS: Array[String] = ["Buduj", "Wojsko"]
## Kolejność grup na zakładce Jednostki: budynki klas, potem jednostki specjalne.
const RECRUIT_ORDER: Array[int] = [BuildingTypes.Kind.BARRACKS, BuildingTypes.Kind.WARBAND_HOUSE,
		BuildingTypes.Kind.ARCHERY_RANGE, BuildingTypes.Kind.STABLE, BuildingTypes.Kind.TAR_KILN,
		BuildingTypes.Kind.SCOUT_HOUSE]

var queue: BuildQueue
var recruitment: Recruitment
var grid: BuildGrid
var now_ms := 0
var tab := Tab.BUILDINGS
## Pierwszy widoczny wiersz (przewijanie Dalej).
var first := 0
## Budynek, którego anulowanie czeka na drugie dotknięcie (0: żaden).
var confirm_id := 0
var content_left := float(Hud.CORNER_INSET)
var content_right := 320.0 - Hud.CORNER_INSET

var _pressed: int = Target.NONE


## Otwiera ekran: zakładka z czymś w toku (najpierw Budynki), inaczej Budynki.
func open() -> void:
	visible = true
	_pressed = Target.NONE
	confirm_id = 0
	first = 0
	tab = Tab.UNITS if queue.orders.is_empty() and not recruitment.orders.is_empty() else Tab.BUILDINGS


func close() -> void:
	visible = false
	confirm_id = 0
	closed.emit()


func _process(_delta: float) -> void:
	if not visible:
		return
	var bounds := Hud.content_bounds(get_viewport_rect().size, Hud.safe_area_in_view(get_viewport()))
	content_left = bounds.x
	content_right = bounds.y
	queue_redraw()


# --- Dane wierszy (statyczne, testowane bez ekranu) ------------------------------------------------

## Wiersze zakładki Budynki: {id, title, level, time, progress (‰ albo -1), waiting}.
static func building_rows(q: BuildQueue, now: int) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for i in q.orders.size():
		var o := q.orders[i]
		out.append({
			"id": o.building_id,
			"title": row_title(o.kind),
			"level": level_text(o.level),
			"time": Hud.format_time(q.remaining_ms(o.building_id, now)),
			"progress": q.progress_permille(o.building_id, now) if i == 0 else -1,
			"waiting": i > 0,
		})
	return out


## Nazwa budynku w wierszu: pełna, a gdy nie mieści się przed kolumną poziomu, skrócona.
static func row_title(kind: int) -> String:
	var name := BuildingTypes.NAMES[kind]
	return name if PixelFont.text_width(name) <= TITLE_W else BuildingTypes.SHORT_NAMES[kind]


## „nowy” dla postawienia, „poz. 1→2” dla ulepszenia, „poz. 5→II.1” dla wejścia w epokę II (#34).
static func level_text(level: int) -> String:
	return "nowy" if level <= 1 else "poz. %s→%s" % [Ages.short_level(level - 1), Ages.short_level(level)]


## Wiersze zakładki Jednostki: nagłówek grupy {header: true, title} i zlecenia {title, squad, time,
## progress (‰ albo -1), waiting}. Grupy w kolejności RECRUIT_ORDER, w grupie budynki po id; drugi
## budynek tego samego rodzaju ma numer w nagłówku.
static func unit_rows(r: Recruitment, g: BuildGrid, now: int) -> Array[Dictionary]:
	var ids: Array[int] = []
	for o in r.orders:
		if not ids.has(o.building_id):
			ids.append(o.building_id)
	ids.sort_custom(func(a: int, b: int) -> bool:
		var ka := _kind_rank(g, a)
		var kb := _kind_rank(g, b)
		return ka < kb if ka != kb else a < b)
	var out: Array[Dictionary] = []
	var seen: Dictionary[int, int] = {}
	for id in ids:
		var kind: int = g.kinds.get(id, -1)
		var name := BuildingTypes.NAMES[kind] if kind >= 0 else "?"
		seen[kind] = int(seen.get(kind, 0)) + 1
		if seen[kind] > 1:
			name += " %d" % seen[kind]
		out.append({"header": true, "title": name})
		var q := r.queue_of(id)
		var t := now
		for i in q.size():
			var o := q[i]
			t = maxi(o.finish_ms(), now) if i == 0 else t + o.duration_ms
			var progress := -1
			if i == 0 and o.start_ms >= 0 and o.duration_ms > 0:
				@warning_ignore("integer_division")
				progress = clampi((now - o.start_ms) * 1000 / o.duration_ms, 0, 1000)
			out.append({
				"header": false,
				"title": UnitTypes.SHORT_NAMES[o.unit],
				"squad": "oddz. " + RecruitPanel.squad_label(r, o.unit, o.squad_id),
				"time": Hud.format_time(t - now),
				"progress": progress,
				"waiting": i > 0,
			})
	return out


static func _kind_rank(g: BuildGrid, id: int) -> int:
	var i := RECRUIT_ORDER.find(int(g.kinds.get(id, -1)))
	return i if i >= 0 else RECRUIT_ORDER.size()


## Tekst pod listą: zajęte miejsca w kolejce budowy albo armia względem limitu.
static func footer_text(t: int, q: BuildQueue, r: Recruitment, g: BuildGrid) -> String:
	if t == Tab.BUILDINGS:
		return "Kolejka: %d/%d" % [q.orders.size(), BuildConfig.BUILDERS + BuildConfig.MAX_WAITING]
	var text := "Armia: %d/%d" % [r.army_size(), Recruitment.army_limit(g)]
	if not r.orders.is_empty():
		text += " (+%d)" % r.orders.size()
	return text


## Komunikat przy pierwszym dotknięciu Anuluj, np. „Anulować Wieża? Zwrot: 120 Dr 40 Ka 40 Ży”.
static func confirm_text(q: BuildQueue, id: int) -> String:
	var o := q.order_for(id)
	if o == null:
		return ""
	return "Anulować %s? Zwrot: %s" % [BuildingTypes.SHORT_NAMES[o.kind], Hud.cost_text(o.cost)]


# --- Układ ----------------------------------------------------------------------------------------

static func tab_rects(left: float, right: float) -> Array[Rect2]:
	var w := floorf((right - left - ResearchPanel.GAP) / 2.0)
	return [Rect2(left, TAB_Y, w, TAB_H), Rect2(left + w + ResearchPanel.GAP, TAB_Y, w, TAB_H)] as Array[Rect2]


## Ile wierszy mieści lista nad rzędem przycisków.
static func rows_fit(view: Vector2) -> int:
	return maxi(1, int((Hud.row_y(view) - 2 - LIST_Y + ROW_GAP) / (ROW_H + ROW_GAP)))


static func row_rect(left: float, right: float, slot: int) -> Rect2:
	return Rect2(left, LIST_Y + slot * (ROW_H + ROW_GAP), right - left, ROW_H)


static func cancel_rect(row: Rect2) -> Rect2:
	return Rect2(row.end.x - CANCEL_W - 1, row.position.y + 1, CANCEL_W, ROW_H - 2)


static func close_rect(view: Vector2, right: float) -> Rect2:
	return Hud.right_corner_rect(view, right)


static func action_rect(view: Vector2, right: float) -> Rect2:
	return Hud.research_rect(view, right)


## Dalej: na lewo od przycisku akcji, w rzędzie przycisków.
static func more_rect(view: Vector2, right: float) -> Rect2:
	var a := action_rect(view, right)
	return Rect2(a.position - Vector2(Hud.BUTTON_SIZE.x + Hud.BUTTON_GAP, 0), Hud.BUTTON_SIZE)


## Cel pod punktem przy `count` wierszach listy od `start`. Wiersz to ROW + indeks, Anuluj to
## CANCEL + indeks (tylko zakładka Budynki), Dalej tylko przy przepełnionej liście, przycisk akcji
## tylko przy pustej zakładce.
static func target_at(p: Vector2, view: Vector2, left: float, right: float, t: int, count: int, start: int) -> int:
	if close_rect(view, right).has_point(p):
		return Target.CLOSE
	if count == 0 and action_rect(view, right).has_point(p):
		return Target.ACTION
	if count > rows_fit(view) and more_rect(view, right).has_point(p):
		return Target.MORE
	var tab_i := Hud.hit(tab_rects(left, right), p)
	if tab_i >= 0:
		return Target.TAB + tab_i
	for slot in mini(rows_fit(view), count - start):
		var r := row_rect(left, right, slot)
		if not r.has_point(p):
			continue
		if t == Tab.BUILDINGS and cancel_rect(r).has_point(p):
			return Target.CANCEL + start + slot
		return Target.ROW + start + slot
	return Target.NONE


## Pierwszy wiersz po Dalej: następna strona, po ostatniej znów pierwsza.
static func next_first(count: int, fit: int, start: int) -> int:
	return 0 if start + fit >= count else start + fit


# --- Dotyk ----------------------------------------------------------------------------------------

func rows() -> Array[Dictionary]:
	if tab == Tab.BUILDINGS:
		return building_rows(queue, now_ms)
	return unit_rows(recruitment, grid, now_ms)


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
	# górny i dolny pasek HUD zostają aktywne tylko do oglądania: dotyk w nich nic nie robi
	if touch.position.y < Hud.BAR_H or touch.position.y >= view.y - Hud.BAR_H:
		return
	get_viewport().set_input_as_handled()
	var t := target_at(touch.position, view, content_left, content_right, tab, rows().size(), first)
	if touch.pressed:
		_pressed = t
		return
	var was := _pressed
	_pressed = Target.NONE
	if t == was:
		activate(t)


## Działanie celu (też z testów). Dotknięcie pustego miejsca zamyka ekran.
func activate(t: int) -> void:
	if t == Target.NONE or t == Target.CLOSE:
		close()
		return
	if t >= Target.CANCEL:
		var row: Dictionary = rows()[t - Target.CANCEL]
		var id := int(row["id"])
		if confirm_id == id:
			confirm_id = 0
			cancel_requested.emit(id)
		else:
			confirm_id = id
			message.emit(confirm_text(queue, id))
		return
	confirm_id = 0
	if t >= Target.ROW:
		var row: Dictionary = rows()[t - Target.ROW]
		if tab == Tab.BUILDINGS:
			# najpierw powrót do mapy, potem budynek (jego karta i komunikat zostają na wierzchu)
			close()
			focus_requested.emit(int(row["id"]))
		return
	if t >= Target.TAB:
		tab = t - Target.TAB
		first = 0
		return
	match t:
		Target.MORE:
			first = next_first(rows().size(), rows_fit(get_viewport_rect().size if is_inside_tree() else Vector2(320, 180)), first)
		Target.ACTION:
			close()
			if tab == Tab.BUILDINGS:
				build_requested.emit()
			else:
				army_requested.emit()


# --- Rysowanie ------------------------------------------------------------------------------------

func _draw() -> void:
	if queue == null or recruitment == null:
		return
	var view := get_viewport_rect().size
	draw_rect(Rect2(0, Hud.BAR_H, view.x, view.y - 2 * Hud.BAR_H), Color(Palette.SHADOW, 0.92))
	var tabs := tab_rects(content_left, content_right)
	var counts: Array[int] = [queue.orders.size(), recruitment.orders.size()]
	for i in tabs.size():
		var label := TAB_NAMES[i] if counts[i] == 0 else "%s (%d)" % [TAB_NAMES[i], counts[i]]
		Hud.paint_button(self, tabs[i], label, i == tab or _pressed == Target.TAB + i, false)
	var list := rows()
	if list.is_empty():
		PixelFont.draw_text(self, Vector2(content_left, LIST_Y + 2), EMPTY_TEXTS[tab], Palette.WOOD[3])
		Hud.paint_button(self, action_rect(view, content_right), ACTION_LABELS[tab], _pressed == Target.ACTION, false)
	var fit := rows_fit(view)
	for slot in mini(fit, list.size() - first):
		_draw_row(row_rect(content_left, content_right, slot), list[first + slot], first + slot)
	if list.size() > fit:
		Hud.paint_button(self, more_rect(view, content_right), MORE_LABEL, _pressed == Target.MORE, false)
	var foot_y := Hud.row_y(view) + 4
	PixelFont.draw_text(self, Vector2(content_left, foot_y), footer_text(tab, queue, recruitment, grid), Palette.INK)
	Hud.paint_button(self, close_rect(view, content_right), CLOSE_LABEL, _pressed == Target.CLOSE, false)


func _draw_row(r: Rect2, row: Dictionary, i: int) -> void:
	if bool(row.get("header", false)):
		PixelFont.draw_text(self, r.position + Vector2(1, 3), row["title"] as String, Palette.THATCH[2])
		return
	draw_rect(r, Palette.WOOD[2] if _pressed == Target.ROW + i else Palette.WOOD[1])
	var x := r.position.x + 3
	PixelFont.draw_text(self, Vector2(x, r.position.y + 3), row["title"] as String, Palette.INK)
	var second: String = row.get("level", row.get("squad", "")) as String
	PixelFont.draw_text(self, Vector2(x + SECOND_X, r.position.y + 3), second, Palette.THATCH[2])
	var right := r.end.x - 3
	if tab == Tab.BUILDINGS:
		var c := cancel_rect(r)
		var confirming := confirm_id == int(row["id"])
		Hud.paint_button(self, c, CONFIRM_LABEL if confirming else CANCEL_LABEL, _pressed == Target.CANCEL + i, false)
		if confirming:
			CastleView.draw_frame(self, Rect2i(c), Palette.ACCENT)
		right = c.position.x - 4
	var time: String = "czeka %s" % row["time"] if bool(row["waiting"]) else row["time"] as String
	PixelFont.draw_right(self, right, r.position.y + 3, time, Palette.WOOD[3] if bool(row["waiting"]) else Palette.INK)
	var progress := int(row["progress"])
	if progress >= 0:
		# pasek postępu 1 px na dole wiersza, w całych pikselach
		var w := int(r.size.x) - 2
		@warning_ignore("integer_division")
		var fill := w * progress / 1000
		draw_rect(Rect2(r.position.x + 1, r.end.y - 2, w, 1), Palette.SHADOW)
		draw_rect(Rect2(r.position.x + 1, r.end.y - 2, fill, 1), Palette.VALID)
