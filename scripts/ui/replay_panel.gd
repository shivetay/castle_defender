class_name ReplayPanel
extends Node2D
## Historia obron (#29, #328) na środku ekranu: do DefenseLog.REPORTS_LIMIT ataków na zamek gracza, od
## najnowszego, po PER_PAGE na stronę ze strzałkami. Wiersz ma dwie linie: data i godzina końca ataku,
## wynik (odparty albo zdobyty, procent zniszczeń) i 3 tarcze obrońcy, a pod spodem nick napastnika,
## siła jego armii i przedział siły obrony jego zamku z serwera (#293, np. „Obr. 200-250”, „Obr. ?” bez zamku). Dotknięcie
## wiersza pyta serwer o powtórkę tej obrony; obrona bez powtórki (sprzed #29) jest wyszarzona i nic nie
## robi. Wróć zamyka okno. Okno samo obsługuje dotyk, więc nic nie trafia do kamery ani do HUD.
@warning_ignore_start("integer_division")

signal replay_requested(attack_id: String)
signal closed

enum State { LOADING, READY, FAILED }

const SIZE := Vector2(296, 150)
const BUTTON := Vector2(64, 16)
const ARROW := Vector2(20, 16)
## Wiersz obrony: dwie linie fontu 8 px, ponad minimum 12 px celu dotyku.
const ROW_H := 20
const ROW_GAP := 2
const PER_PAGE := 4
## Cele dotyku poza wierszami.
const CLOSE := -2
const PREV := -3
const NEXT := -4
const TITLE := "Historia obron"
const CLOSE_LABEL := "Wróć"
const LOADING_TEXT := "Wczytuję obrony..."
const EMPTY_TEXT := "Nikt jeszcze nie atakował"
const FAILED_TEXT := "Brak połączenia z serwerem"
const HELD := "Odparty"
const LOST := "Zdobyty"
## Siła obrony zamku napastnika: przedział z serwera (#293), „?”, gdy zamku już nie ma.
const DEFENSE_LABEL := "Obr."
const DEFENSE_UNKNOWN := "Obr. ?"
## Tarcza obrońcy 5×5 za każdy z 3 celów: pełna, gdy atakujący nie zdobył gwiazdki, pęknięta, gdy zdobył.
const SHIELD: Array[String] = ["#####", "#####", "#####", ".###.", "..#.."]
const CRACKED: Array[String] = ["##.##", "#.###", "##.##", ".#.#.", "..#.."]
const SHIELD_W := 5
const SHIELD_GAP := 2

var state: int = State.LOADING
var reports: Array[DefenseLog.Report] = []
var page := 0
## Cel trzymany palcem (indeks wiersza na liście albo CLOSE, PREV, NEXT), -1 = nic.
var _pressed := -1


func open() -> void:
	state = State.LOADING
	reports = []
	page = 0
	_pressed = -1
	visible = true
	queue_redraw()


## Raporty z serwera (`ok` false: błąd sieci albo serwera).
func show_reports(list: Array[DefenseLog.Report], ok: bool) -> void:
	reports = list
	state = State.READY if ok else State.FAILED
	page = clampi(page, 0, page_count(list.size()) - 1)
	queue_redraw()


func close() -> void:
	visible = false
	closed.emit()


## Wybór celu `t` (z target_at): wiersz z powtórką prosi o nią, strzałki zmieniają stronę.
func choose(t: int) -> void:
	match t:
		CLOSE:
			close()
		PREV:
			page = maxi(0, page - 1)
		NEXT:
			page = mini(page_count(reports.size()) - 1, page + 1)
		_:
			if t >= 0 and t < reports.size() and reports[t].has_replay:
				replay_requested.emit(reports[t].id)
	queue_redraw()


static func page_count(count: int) -> int:
	return maxi(1, (count + PER_PAGE - 1) / PER_PAGE)


static func panel_rect(view: Vector2) -> Rect2:
	return Rect2(((view - SIZE) / 2.0).floor(), SIZE)


static func close_rect(view: Vector2) -> Rect2:
	var p := panel_rect(view)
	return Rect2(Vector2(floorf(p.get_center().x - BUTTON.x / 2.0), p.end.y - BUTTON.y - 6), BUTTON)


static func prev_rect(view: Vector2) -> Rect2:
	var c := close_rect(view)
	return Rect2(c.position - Vector2(ARROW.x + 8, 0), ARROW)


static func next_rect(view: Vector2) -> Rect2:
	var c := close_rect(view)
	return Rect2(Vector2(c.end.x + 8, c.position.y), ARROW)


## Wiersz `i` bieżącej strony (0..PER_PAGE-1).
static func row_rect(view: Vector2, i: int) -> Rect2:
	var p := panel_rect(view)
	return Rect2(p.position.x + 6, p.position.y + 18 + i * (ROW_H + ROW_GAP), p.size.x - 12, ROW_H)


## Cel pod punktem na stronie `pg` listy `count` obron: indeks obrony na liście, CLOSE, PREV, NEXT albo -1.
static func target_at(p: Vector2, view: Vector2, count: int, pg: int) -> int:
	if close_rect(view).has_point(p):
		return CLOSE
	if pg > 0 and prev_rect(view).has_point(p):
		return PREV
	if pg < page_count(count) - 1 and next_rect(view).has_point(p):
		return NEXT
	for i in PER_PAGE:
		var idx := pg * PER_PAGE + i
		if idx < mini(count, DefenseLog.REPORTS_LIMIT) and row_rect(view, i).has_point(p):
			return idx
	return -1


## Pierwsza linia wiersza, np. „21.11 14:05 Zdobyty 30%”. `bias_min`: strefa czasowa telefonu w minutach.
static func row_text(r: DefenseLog.Report, bias_min: int) -> String:
	var t := Time.get_datetime_dict_from_unix_time(r.at_s + bias_min * 60)
	return "%02d.%02d %02d:%02d %s %d%%" % [int(t["day"]), int(t["month"]), int(t["hour"]), int(t["minute"]),
			LOST if r.result.won else HELD, r.result.percent]


## Druga linia wiersza: nick napastnika, siła jego armii i siła obrony jego zamku.
static func detail_text(r: DefenseLog.Report) -> String:
	var defense := DEFENSE_UNKNOWN if r.defense < 0 else "%s %s" % [DEFENSE_LABEL, Strength.range_text(r.defense)]
	return "%s  Siła %d  %s" % [r.nickname, r.army_power, defense]


static func shields_width() -> int:
	return 3 * SHIELD_W + 2 * SHIELD_GAP


## Kolor tarczy: pęknięta (cel zdobyty przez atakującego) jest szara.
static func shield_color(taken: bool) -> Color:
	return Palette.LOCKED[0] if taken else Palette.SIDE_DEFENDER


static func status_text(st: int, count: int) -> String:
	match st:
		State.LOADING:
			return LOADING_TEXT
		State.FAILED:
			return FAILED_TEXT
	return EMPTY_TEXT if count == 0 else ""


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
	var view := get_viewport_rect().size
	var count := reports.size() if state == State.READY else 0
	var on := target_at(touch.position, view, count, page)
	if touch.pressed:
		_pressed = on
		queue_redraw()
		return
	var was := _pressed
	_pressed = -1
	queue_redraw()
	if was == on and was != -1:
		choose(was)


# --- Rysowanie ---------------------------------------------------------------------------------

func _draw() -> void:
	var view := get_viewport_rect().size
	draw_rect(Rect2(Vector2.ZERO, view), Color(Palette.SHADOW, 0.6))
	var p := panel_rect(view)
	draw_rect(p, Color(Palette.SHADOW, 0.95))
	CastleView.draw_frame(self, Rect2i(p), Palette.WOOD[2])
	PixelFont.draw_centered(self, Rect2(p.position.x, p.position.y + 5, p.size.x, 10), TITLE, Palette.THATCH[2])
	var status := status_text(state, reports.size())
	if not status.is_empty():
		PixelFont.draw_centered(self, Rect2(p.position.x, p.position.y + 50, p.size.x, 10), status, Palette.INK)
	var pages := 1
	if state == State.READY:
		pages = page_count(reports.size())
		var bias := int(Time.get_time_zone_from_system().get("bias", 0))
		for i in PER_PAGE:
			var idx := page * PER_PAGE + i
			if idx < mini(reports.size(), DefenseLog.REPORTS_LIMIT):
				_draw_row(row_rect(view, i), reports[idx], bias, _pressed == idx)
	Hud.paint_button(self, close_rect(view), CLOSE_LABEL, _pressed == CLOSE, false)
	if pages > 1:
		Hud.paint_button(self, prev_rect(view), "<", _pressed == PREV, page == 0)
		Hud.paint_button(self, next_rect(view), ">", _pressed == NEXT, page >= pages - 1)


func _draw_row(r: Rect2, rep: DefenseLog.Report, bias: int, pressed: bool) -> void:
	draw_rect(r, Palette.WOOD[2] if pressed and rep.has_replay else Palette.WOOD[1])
	var ink: Color = Palette.INK if rep.has_replay else Palette.LOCKED[0]
	PixelFont.draw_text(self, Vector2(r.position.x + 3, r.position.y + 1), row_text(rep, bias),
			Palette.ACCENT if rep.result.won and rep.has_replay else ink)
	PixelFont.draw_text(self, Vector2(r.position.x + 3, r.position.y + 1 + PixelFont.LINE), detail_text(rep),
			Palette.WOOD[3] if rep.has_replay else ink)
	var x0 := int(r.end.x) - 3 - shields_width()
	for i in 3:
		_draw_shield(Vector2i(x0 + i * (SHIELD_W + SHIELD_GAP), int(r.position.y) + 3), rep.result.stars[i])


func _draw_shield(at: Vector2i, taken: bool) -> void:
	var shape := CRACKED if taken else SHIELD
	var col := shield_color(taken)
	for y in shape.size():
		for x in SHIELD_W:
			if shape[y][x] == "#":
				draw_rect(Rect2(at.x + x, at.y + y, 1, 1), col)
