class_name RankingPanel
extends Node2D
## Rankingi z karty Strażnicy, na przyciemnionym zamku. Trzy widoki o tym samym układzie: PvP (#27)
## Atak (punkty za ataki na graczy) i Obrona (punkty za obronę przed nimi) oraz osobny ranking PvE
## (#242, punkty za zdobyte zamki-boty), zawsze tylko gracze z epoki gracza. Wiersz: miejsce, portret władcy, imię gracza, nazwa zamku i punkty; własny wiersz jest
## podświetlony, a gdy gracz jest poza 20 najlepszymi, stoi pod nimi. Punkty liczy serwer
## (RankingBoard), panel tylko je pokazuje. Lista przewija się przeciąganiem o całe wiersze.
## Panel sam obsługuje dotyk, więc nic nie trafia do kamery ani do HUD.
@warning_ignore_start("integer_division")

## Gracz przełączył widok: main prosi serwer o tabelę tego rodzaju (RankingBoard.Kind).
signal kind_changed(kind: int)
## Nowy komunikat do dolnego paska HUD-u (miejsce gracza, wczytywanie, błąd).
signal message_changed(text: String)
signal closed

enum Target { NONE = -1, ATTACK, DEFENSE, PVE, CLOSE }
enum Load { OFFLINE, LOADING, DONE, FAILED }

## Tytuł według RankingBoard.Kind.
const TITLES: Array[String] = ["Ranking PvP", "Ranking PvP", "Ranking PvE"]
const LOAD_TEXTS: Array[String] = ["Bez sieci", "Wczytuję...", "", "Brak odpowiedzi"]
const OFFLINE_MESSAGE := "Ranking wymaga połączenia z serwerem"
const LOADING_MESSAGE := "Wczytuję ranking"
const FAILED_MESSAGE := "Serwer nie odpowiada, spróbuj później"
const EMPTY_TEXTS: Array[String] = ["Nikt w tej epoce nie atakował graczy",
	"Nikt w tej epoce nie bronił się przed graczem", "Nikt w tej epoce nie zdobył zamku-bota"]
## Przyciski widoków w kolejności RankingBoard.Kind (i Target).
const TAB_LABELS: Array[String] = ["Atak", "Obrona", "PvE"]
const CLOSE_LABEL := "Wróć"
const LIST_Y := Hud.BAR_H + 11
## Wysokość wiersza: portret i odstęp.
const ROW_H := PortraitArt.SIZE + 2
## Szerokość kolumny z miejscem (najwyżej „99999.” mieści się w kolumnie i nie zachodzi na portret).
const PLACE_W := 26
const SCROLLBAR_W := 2

var kind: int = RankingBoard.Kind.ATTACK
var rows: Array[RankingBoard.Row] = []
var load: int = Load.OFFLINE
var age := 0
## Pierwszy widoczny wiersz.
var scroll := 0
var content_left := float(Hud.CORNER_INSET)
var content_right := 320.0 - Hud.CORNER_INSET

var _pressed: int = Target.NONE
var _drag := 0.0
## Tabele obu rodzajów z tego otwarcia: przełączenie widoku nie czeka drugi raz na serwer.
var _cache: Dictionary[int, Array] = {}


## Otwiera ranking `kind` dla epoki `player_age`; `online`: main poprosi serwer (kind_changed).
func open(player_age: int, online: bool, start_kind: int = RankingBoard.Kind.ATTACK) -> void:
	age = player_age
	_cache.clear()
	visible = true
	_pressed = Target.NONE
	_show(start_kind, online)


## Odpowiedź serwera; odpowiedź na inny widok niż bieżący trafia tylko do pamięci.
func set_rows(for_kind: int, new_rows: Array[RankingBoard.Row], ok: bool) -> void:
	if ok:
		_cache[for_kind] = new_rows
	if for_kind != kind or load != Load.LOADING:
		return
	load = Load.DONE if ok else Load.FAILED
	rows = new_rows if ok else [] as Array[RankingBoard.Row]
	scroll = start_scroll(rows, visible_rows(_view()))
	message_changed.emit(message())
	queue_redraw()


func close() -> void:
	visible = false
	closed.emit()


func status_text() -> String:
	return LOAD_TEXTS[load]


## Komunikat do dolnego paska: miejsce gracza albo zachęta, a bez tabeli stan wczytywania.
func message() -> String:
	match load:
		Load.DONE:
			return RankingBoard.summary(rows, kind)
		Load.LOADING:
			return LOADING_MESSAGE
		Load.FAILED:
			return FAILED_MESSAGE
	return OFFLINE_MESSAGE


func _show(new_kind: int, online: bool) -> void:
	kind = new_kind
	scroll = 0
	_drag = 0.0
	if _cache.has(kind):
		# nowa lista: `rows` bywa tą samą tablicą co tabela drugiego widoku w pamięci
		var cached: Array[RankingBoard.Row] = []
		cached.assign(_cache[kind])
		rows = cached
		load = Load.DONE
		scroll = start_scroll(rows, visible_rows(_view()))
	else:
		rows = [] as Array[RankingBoard.Row]
		load = Load.LOADING if online else Load.OFFLINE
		if online:
			kind_changed.emit(kind)
	message_changed.emit(message())
	queue_redraw()


## Rozmiar widoku (poza drzewem, w testach, ekran 320×180).
func _view() -> Vector2:
	return get_viewport_rect().size if is_inside_tree() else Vector2(320, 180)


func _process(_delta: float) -> void:
	if not visible:
		return
	var bounds := Hud.content_bounds(get_viewport_rect().size, Hud.safe_area_in_view(get_viewport()))
	if bounds.x != content_left or bounds.y != content_right:
		content_left = bounds.x
		content_right = bounds.y
		queue_redraw()


# --- Układ (bez stanu, testy) ------------------------------------------------------------------

static func title_text(player_age: int, for_kind: int = RankingBoard.Kind.ATTACK) -> String:
	return "%s: %s" % [TITLES[clampi(for_kind, 0, TITLES.size() - 1)], TargetSearch.age_label(player_age)]


## Ile całych wierszy mieści się między tytułem a rzędem przycisków.
static func visible_rows(view: Vector2) -> int:
	return maxi(1, int((Hud.row_y(view) - 2 - LIST_Y) / ROW_H))


static func max_scroll(count: int, shown: int) -> int:
	return maxi(0, count - shown)


## Przewinięcie na start: od góry, chyba że własny wiersz jest niżej niż ekran; wtedy tak, żeby
## był ostatnim widocznym.
static func start_scroll(list: Array[RankingBoard.Row], shown: int) -> int:
	for i in list.size():
		if list[i].is_me:
			return clampi(i - shown + 1, 0, max_scroll(list.size(), shown))
	return 0


static func row_rect(i: int, left: float, right: float) -> Rect2:
	return Rect2(left, LIST_Y + i * ROW_H, right - left - SCROLLBAR_W - 2, ROW_H - 2)


static func tab_rect(k: int, view: Vector2, left: float) -> Rect2:
	return Rect2(Vector2(left + k * (Hud.BUTTON_SIZE.x + Hud.BUTTON_GAP), Hud.row_y(view)), Hud.BUTTON_SIZE)


static func close_rect(view: Vector2, right: float) -> Rect2:
	return Hud.right_corner_rect(view, right)


static func target_at(p: Vector2, view: Vector2, left: float, right: float) -> int:
	for k in TAB_LABELS.size():
		if tab_rect(k, view, left).has_point(p):
			return k  # Target.ATTACK, DEFENSE i PVE mają numery RankingBoard.Kind
	if close_rect(view, right).has_point(p):
		return Target.CLOSE
	return Target.NONE


## Linie tekstu wiersza [pozycja względem wiersza, tekst, kolor], przycięte do szerokości `w`.
static func row_lines(r: RankingBoard.Row, w: int) -> Array:
	var points := str(r.points)
	var text_x := PLACE_W + PortraitArt.SIZE + 3
	var text_w := w - text_x - PixelFont.text_width(points) - 6
	return [
		[Vector2(PLACE_W - 2 - PixelFont.text_width("%d." % r.place), 7), "%d." % r.place, Palette.INK],
		[Vector2(text_x, 3), TargetPicker.fit(r.player_name, text_w), Palette.INK],
		[Vector2(text_x, 12), TargetPicker.fit(r.castle_name, text_w), Palette.THATCH[2]],
		[Vector2(w - 2 - PixelFont.text_width(points), 7), points, Palette.INK],
	]


## Nowe przewinięcie po przeciągnięciu o `dy` px (w górę przewija w dół listy), o całe wiersze;
## zwraca [przewinięcie, reszta przeciągnięcia].
static func drag_scroll(current: int, acc: float, dy: float, count: int, shown: int) -> Array:
	var total := acc + dy
	var steps := int(total / ROW_H)  # w stronę zera, więc reszta ma ten sam znak co przeciągnięcie
	var next := clampi(current - steps, 0, max_scroll(count, shown))
	return [next, total - steps * ROW_H]


func _activate(t: int) -> void:
	match t:
		Target.ATTACK, Target.DEFENSE, Target.PVE:
			if t != kind:
				_show(t, load != Load.OFFLINE)
		Target.CLOSE:
			close()
	queue_redraw()


# --- Dotyk -------------------------------------------------------------------------------------

func _input(event: InputEvent) -> void:
	if not visible:
		return
	var view := get_viewport_rect().size
	var drag := event as InputEventScreenDrag
	if drag != null:
		get_viewport().set_input_as_handled()
		var res := drag_scroll(scroll, _drag, drag.relative.y, rows.size(), visible_rows(view))
		_drag = res[1] as float
		if res[0] as int != scroll:
			scroll = res[0] as int
			queue_redraw()
		return
	var touch := event as InputEventScreenTouch
	if touch == null:
		return
	if touch.position.y < Hud.BAR_H or touch.position.y >= view.y - Hud.BAR_H:
		return
	get_viewport().set_input_as_handled()
	var t := target_at(touch.position, view, content_left, content_right)
	if touch.pressed:
		_pressed = t
		_drag = 0.0
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
	PixelFont.draw_text(self, Vector2(content_left, Hud.BAR_H + 2), title_text(age, kind), Palette.THATCH[2])
	var status := status_text()
	if not status.is_empty():
		PixelFont.draw_right(self, content_right, Hud.BAR_H + 2, status, Palette.WOOD[3])
	var shown := visible_rows(view)
	if load == Load.DONE and rows.is_empty():
		PixelFont.draw_text(self, Vector2(content_left, LIST_Y + 4), EMPTY_TEXTS[kind], Palette.WOOD[3])
	for i in mini(shown, rows.size() - scroll):
		_draw_row(row_rect(i, content_left, content_right), rows[scroll + i])
	_draw_scrollbar(shown)
	for k in TAB_LABELS.size():
		Hud.paint_button(self, tab_rect(k, view, content_left), TAB_LABELS[k],
				k == kind or _pressed == k, false)
	Hud.paint_button(self, close_rect(view, content_right), CLOSE_LABEL, _pressed == Target.CLOSE, false)


func _draw_row(r: Rect2, row: RankingBoard.Row) -> void:
	draw_rect(r, ResearchPanel.tile_color(false, row.is_me))
	draw_texture(PortraitArt.ruler_texture(row.ruler), r.position + Vector2(PLACE_W, 0))
	for line: Array in row_lines(row, int(r.size.x)):
		PixelFont.draw_text(self, r.position + (line[0] as Vector2), line[1] as String, line[2] as Color)
	if row.is_me:
		CastleView.draw_frame(self, Rect2i(r), Palette.INK)


## Pasek przewijania przy prawej krawędzi listy, gdy wiersze się nie mieszczą.
func _draw_scrollbar(shown: int) -> void:
	if rows.size() <= shown:
		return
	var x := content_right - SCROLLBAR_W
	var h := shown * ROW_H - 2
	draw_rect(Rect2(x, LIST_Y, SCROLLBAR_W, h), Palette.WOOD[1])
	var thumb := maxi(4, h * shown / rows.size())
	var y := LIST_Y + (h - thumb) * scroll / max_scroll(rows.size(), shown)
	draw_rect(Rect2(x, y, SCROLLBAR_W, thumb), Palette.THATCH[2])
