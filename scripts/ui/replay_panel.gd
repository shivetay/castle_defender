class_name ReplayPanel
extends Node2D
## Ostatnie obrony (#29) na środku ekranu: do DefenseLog.REPORTS_LIMIT ataków na zamek gracza, od
## najnowszego. Wiersz to data i godzina końca ataku, wynik (odparty albo zdobyty, procent zniszczeń)
## i gwiazdki atakującego; dotknięcie wiersza pyta serwer o powtórkę tej obrony. Wróć zamyka okno.
## Okno samo obsługuje dotyk, więc nic nie trafia do kamery ani do HUD.
@warning_ignore_start("integer_division")

signal replay_requested(attack_id: String)
signal closed

enum State { LOADING, READY, FAILED }

const SIZE := Vector2(240, 150)
const BUTTON := Vector2(64, 16)
## Wiersz obrony: wysokość ponad minimum 12 px celu dotyku.
const ROW_H := 16
const ROW_GAP := 2
const TITLE := "Ostatnie obrony"
const CLOSE_LABEL := "Wróć"
const LOADING_TEXT := "Wczytuję obrony..."
const EMPTY_TEXT := "Nikt jeszcze nie atakował"
const FAILED_TEXT := "Brak połączenia z serwerem"
const HELD := "Odparty"
const LOST := "Zdobyty"
## Mała gwiazdka 5×5 w wierszu.
const STAR: Array[String] = ["..#..", "#####", ".###.", ".#.#.", "#...#"]
const STAR_W := 5
const STAR_GAP := 2

var state: int = State.LOADING
var reports: Array[DefenseLog.Report] = []
## Wiersz trzymany palcem (indeks), -2 = Wróć, -1 = nic.
var _pressed := -1


func open() -> void:
	state = State.LOADING
	reports = []
	_pressed = -1
	visible = true
	queue_redraw()


## Raporty z serwera (`ok` false: błąd sieci albo serwera).
func show_reports(list: Array[DefenseLog.Report], ok: bool) -> void:
	reports = list
	state = State.READY if ok else State.FAILED
	queue_redraw()


func close() -> void:
	visible = false
	closed.emit()


static func panel_rect(view: Vector2) -> Rect2:
	return Rect2(((view - SIZE) / 2.0).floor(), SIZE)


static func close_rect(view: Vector2) -> Rect2:
	var p := panel_rect(view)
	return Rect2(Vector2(floorf(p.get_center().x - BUTTON.x / 2.0), p.end.y - BUTTON.y - 6), BUTTON)


static func row_rect(view: Vector2, i: int) -> Rect2:
	var p := panel_rect(view)
	return Rect2(p.position.x + 6, p.position.y + 18 + i * (ROW_H + ROW_GAP), p.size.x - 12, ROW_H)


## Cel pod punktem: indeks wiersza, -2 (Wróć) albo -1.
static func target_at(p: Vector2, view: Vector2, count: int) -> int:
	if close_rect(view).has_point(p):
		return -2
	for i in mini(count, DefenseLog.REPORTS_LIMIT):
		if row_rect(view, i).has_point(p):
			return i
	return -1


## Tekst wiersza, np. „21.11 14:05 Odparty 30%”. `bias_min`: strefa czasowa telefonu w minutach.
static func row_text(r: DefenseLog.Report, bias_min: int) -> String:
	var t := Time.get_datetime_dict_from_unix_time(r.at_s + bias_min * 60)
	return "%02d.%02d %02d:%02d %s %d%%" % [int(t["day"]), int(t["month"]), int(t["hour"]), int(t["minute"]),
			LOST if r.result.won else HELD, r.result.percent]


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
	var on := target_at(touch.position, view, count)
	if touch.pressed:
		_pressed = on
		queue_redraw()
		return
	var was := _pressed
	_pressed = -1
	queue_redraw()
	if was != on or was == -1:
		return
	if was == -2:
		close()
	else:
		replay_requested.emit(reports[was].id)


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
	if state == State.READY:
		var bias := int(Time.get_time_zone_from_system().get("bias", 0))
		for i in mini(reports.size(), DefenseLog.REPORTS_LIMIT):
			_draw_row(row_rect(view, i), reports[i], bias, _pressed == i)
	Hud.paint_button(self, close_rect(view), CLOSE_LABEL, _pressed == -2, false)


func _draw_row(r: Rect2, rep: DefenseLog.Report, bias: int, pressed: bool) -> void:
	draw_rect(r, Palette.WOOD[2] if pressed else Palette.WOOD[1])
	PixelFont.draw_text(self, Vector2(r.position.x + 3, r.position.y + 4), row_text(rep, bias),
			Palette.ACCENT if rep.result.won else Palette.INK)
	var x0 := int(r.end.x) - 3 - 3 * STAR_W - 2 * STAR_GAP
	for i in 3:
		_draw_star(Vector2i(x0 + i * (STAR_W + STAR_GAP), int(r.position.y) + 6), rep.result.stars[i])


func _draw_star(at: Vector2i, on: bool) -> void:
	var col: Color = Palette.THATCH[2] if on else Palette.WOOD[0]
	for y in STAR.size():
		for x in STAR_W:
			if STAR[y][x] == "#":
				draw_rect(Rect2(at.x + x, at.y + y, 1, 1), col)
