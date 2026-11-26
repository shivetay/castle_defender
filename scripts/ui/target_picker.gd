class_name TargetPicker
extends Node2D
## Wybór celu ataku (#24), pierwszy ekran Wyprawy ze Strażnicy: zawsze 3 karty celów. Karta ma
## tylko portret władcy, imię gracza, nazwę zamku i siłę obrony (#310): bot liczy ją w kliencie
## (Strength.bot_defense), a gracz ma „?”, dopóki serwer jej nie poda (#293). Graczy dobiera serwer (TargetSearch, `find_targets`);
## puste miejsca, a bez sieci wszystkie trzy, zajmują zamki-boty. Boty otwiera dotychczasową listę
## 20 zamków-botów (BotPicker), Planuj plan ataku na wybranym celu, a Wróć wraca do mapy.
## Planuj na karcie gracza zaczyna atak na serwerze (`start_attack`, #240) i otwiera plan na kopii
## jego zamku. Zwiad (#28): pierwsze kliknięcie Zwiad odsłania przycisk czasu (2, 10 albo 30 min,
## #317), kolejne wysyła Tropicieli na wybrany cel; pod kartami są stan i koszt zwiadu, które
## podaje main (scout_lines). Nowe (#313) losuje inne cele za złoto (cena i dostępność od main,
## TargetRefresh); nieudane szukanie zostawia poprzednią listę. Panel sam obsługuje dotyk, więc nic nie trafia do kamery ani do HUD.

signal bot_chosen(index: int)
signal player_chosen(target: TargetSearch.Target)
signal bots_pressed
signal closed
## Zwiad (#28) na cel `target` na `duration` (indeks ScoutConfig.DURATION_S).
signal scout_requested(target: TargetSearch.Target, duration: int)
## Zmienił się wybrany cel albo długość zwiadu: main odświeża scout_lines.
signal scout_changed
## Nowe (#313): gracz chce innych celów za złoto; main sprawdza złoto i woła begin_refresh.
signal refresh_requested

enum Target { NONE = -1, PLAN = 1, CLOSE = 2, BOTS = 3, SCOUT = 4, SCOUT_TIME = 5, REFRESH = 6, CARD = 100 }
## Stan szukania graczy (napis z prawej od tytułu).
enum Search { OFFLINE, SEARCHING, DONE, FAILED, LIMITED }

const TITLE := "Wyprawa: wybierz cel"
const SEARCH_TEXTS: Array[String] = ["Bez sieci: boty", "Szukam graczy...", "", "Brak odpowiedzi: boty",
		"Za często: boty"]
const NO_PLAYERS_TEXT := "Brak graczy: boty"
const PLAN_LABEL := "Planuj"
const CLOSE_LABEL := "Wróć"
const BOTS_LABEL := "Boty"
const SCOUT_LABEL := "Zwiad"
const REFRESH_LABEL := "Nowe"
## Siła obrony celu (#310); siły gracza klient jeszcze nie zna (#293).
const STRENGTH_LABEL := "Siła"
const UNKNOWN_STRENGTH_TEXT := "Siła ?"
const CARD_Y := Hud.BAR_H + 12
const CARD_GAP := 4
## Portret, a pod nim nazwa zamku.
const CARD_H := 38
## Odstęp treści od brzegu karty.
const PAD := 2
## Wiersz nazwy zamku, pod portretem.
const CASTLE_Y := PAD + PortraitArt.SIZE + 3
## Pierwsza linia stanu zwiadu (#28) pod kartami.
const SCOUT_Y := CARD_Y + CARD_H + 3

var targets: Array[TargetSearch.Target] = []
var selected := 0
var search: int = Search.OFFLINE
var beaten := 0
## Zwiad (#28): długość wybrana przyciskiem obok Zwiadu, czy da się go wysłać na wybrany cel
## i dwie linie stanu pod kartami (ustawia main). Przycisk czasu widać dopiero po kliknięciu
## Zwiad (#317).
var scout_duration := 1
var scout_enabled := false
var scout_time_open := false
var scout_lines: Array[String] = []
## Nowe (#313): cena następnego odświeżenia, czy gracz jest w sieci i czy stać go na nie (ustawia main).
var refresh_cost := TargetRefresh.BASE_COST
var refresh_online := false
var refresh_affordable := false
var content_left := float(Hud.CORNER_INSET)
var content_right := 320.0 - Hud.CORNER_INSET

var _pressed: int = Target.NONE
## Trwa płatne odświeżenie: stara lista zostaje, a nieudane szukanie przywraca `_search_before`.
var _refreshing := false
var _search_before: int = Search.OFFLINE


## Otwiera ekran z 3 botami; `online`: trwa szukanie graczy, wynik da `set_players`.
func open(beaten_count: int, online: bool) -> void:
	beaten = beaten_count
	targets = TargetSearch.fill([] as Array[TargetSearch.Target], beaten)
	search = Search.SEARCHING if online else Search.OFFLINE
	selected = 0
	scout_time_open = false
	_refreshing = false
	visible = true
	_pressed = Target.NONE
	queue_redraw()


## Wynik szukania z serwera: gracze zajmują pierwsze karty, reszta zostaje dla botów.
## `limited`: serwer odrzucił szukanie z limitu, zostają boty.
func set_players(players: Array[TargetSearch.Target], ok: bool, limited: bool = false) -> void:
	if search != Search.SEARCHING:
		return
	if _refreshing:
		_refreshing = false
		if not ok:
			search = _search_before
			queue_redraw()
			return
	search = Search.DONE if ok else (Search.LIMITED if limited else Search.FAILED)
	if ok:
		targets = TargetSearch.fill(players, beaten)
		selected = 0
	queue_redraw()


## Zaczyna płatne odświeżenie (#313): stan „szukam”, a karty zostają do odpowiedzi.
func begin_refresh() -> void:
	_search_before = search
	search = Search.SEARCHING
	_refreshing = true
	queue_redraw()


func is_refreshing() -> bool:
	return _refreshing


## Nowe da się nacisnąć w sieci, ze złotem na cenę i gdy nic się nie szuka.
func refresh_enabled() -> bool:
	return refresh_online and refresh_affordable and search != Search.SEARCHING


static func refresh_label(cost: int) -> String:
	return "%s %d" % [REFRESH_LABEL, cost]


func close() -> void:
	visible = false
	closed.emit()


func status_text() -> String:
	if search == Search.DONE and not targets.is_empty() and targets[0].is_bot:
		return NO_PLAYERS_TEXT
	return SEARCH_TEXTS[search]


func selected_target() -> TargetSearch.Target:
	return targets[selected] if selected >= 0 and selected < targets.size() else null


func _process(_delta: float) -> void:
	if not visible:
		return
	var bounds := Hud.content_bounds(get_viewport_rect().size, Hud.safe_area_in_view(get_viewport()))
	if bounds.x != content_left or bounds.y != content_right:
		content_left = bounds.x
		content_right = bounds.y
		queue_redraw()


# --- Układ (bez stanu, testy) ------------------------------------------------------------------

static func card_width(left: float, right: float) -> float:
	return floorf((right - left - (TargetSearch.COUNT - 1) * CARD_GAP) / TargetSearch.COUNT)


static func card_rects(left: float, right: float) -> Array[Rect2]:
	var w := card_width(left, right)
	var out: Array[Rect2] = []
	for i in TargetSearch.COUNT:
		out.append(Rect2(left + i * (w + CARD_GAP), CARD_Y, w, CARD_H))
	return out


static func plan_rect(view: Vector2, right: float) -> Rect2:
	return Hud.research_rect(view, right)


static func close_rect(view: Vector2, right: float) -> Rect2:
	return Hud.right_corner_rect(view, right)


## Boty: w lewym dolnym rogu treści, z dala od Planuj.
static func bots_rect(view: Vector2, left: float) -> Rect2:
	return Rect2(Vector2(left, Hud.row_y(view)), Hud.BUTTON_SIZE)


## Długość zwiadu (#28): na prawo od Botów (tylko gdy `scout_time_open`, #317).
static func scout_time_rect(view: Vector2, left: float) -> Rect2:
	return Rect2(Vector2(left + Hud.BUTTON_SIZE.x + Hud.BUTTON_GAP, Hud.row_y(view)), Hud.BUTTON_SIZE)


## Zwiad (#28): obok Botów, a po odsłonięciu czasu (#317) na prawo od długości, z dala od Planuj.
static func scout_rect(view: Vector2, left: float, time_open: bool = true) -> Rect2:
	var slot := 2 if time_open else 1
	return Rect2(Vector2(left + slot * (Hud.BUTTON_SIZE.x + Hud.BUTTON_GAP), Hud.row_y(view)), Hud.BUTTON_SIZE)


## Nowe (#313): nad Botami, po lewej, z dala od Planuj (dolny rząd bywa pełny przy czasie zwiadu).
static func refresh_rect(view: Vector2, left: float) -> Rect2:
	return Rect2(Vector2(left, Hud.row_y(view) - Hud.BUTTON_SIZE.y - Hud.BUTTON_GAP), Hud.BUTTON_SIZE)


static func target_at(p: Vector2, view: Vector2, left: float, right: float, time_open: bool = true) -> int:
	if plan_rect(view, right).has_point(p):
		return Target.PLAN
	if close_rect(view, right).has_point(p):
		return Target.CLOSE
	if bots_rect(view, left).has_point(p):
		return Target.BOTS
	if time_open and scout_time_rect(view, left).has_point(p):
		return Target.SCOUT_TIME
	if scout_rect(view, left, time_open).has_point(p):
		return Target.SCOUT
	if refresh_rect(view, left).has_point(p):
		return Target.REFRESH
	var cards := card_rects(left, right)
	for i in cards.size():
		if cards[i].has_point(p):
			return Target.CARD + i
	return Target.NONE


## Linie tekstu karty [pozycja względem karty, tekst, kolor], przycięte do szerokości karty:
## imię i siła obok portretu, nazwa zamku pod nim.
static func card_lines(t: TargetSearch.Target, w: int) -> Array:
	var side_x := PAD + PortraitArt.SIZE + 2
	var side := w - side_x - PAD
	return [
		[Vector2(side_x, 3), fit(t.player_name, side), Palette.INK],
		[Vector2(side_x, 13), fit(strength_text(t), side), Palette.THATCH[2]],
		[Vector2(PAD, CASTLE_Y), fit(t.castle_name, w - 2 * PAD), Palette.THATCH[2]],
	]


## Napis siły na karcie, np. „Siła 245”, albo „Siła ?”, gdy jej nie znamy.
static func strength_text(t: TargetSearch.Target) -> String:
	return UNKNOWN_STRENGTH_TEXT if t.strength < 0 else "%s %d" % [STRENGTH_LABEL, t.strength]


## Jedna linia najwyżej `width` px (z „...”, gdy się nie mieści); pusty tekst zostaje pusty.
static func fit(text: String, width: int) -> String:
	var lines := PixelFont.wrap(text, width, 1)
	return lines[0] if not lines.is_empty() else ""


func _activate(t: int) -> void:
	if t >= Target.CARD:
		selected = t - Target.CARD
		scout_changed.emit()
	elif t == Target.SCOUT_TIME:
		if scout_time_open:
			scout_duration = (scout_duration + 1) % ScoutConfig.duration_count()
			scout_changed.emit()
	elif t == Target.SCOUT:
		# pierwsze kliknięcie tylko odsłania czas (#317); wysyłka od drugiego
		if not scout_time_open:
			scout_time_open = true
			scout_changed.emit()
		else:
			var target := selected_target()
			if target != null and scout_enabled:
				scout_requested.emit(target, scout_duration)
	elif t == Target.PLAN:
		var target := selected_target()
		if target == null:
			return
		if target.is_bot:
			bot_chosen.emit(target.bot_idx)
		else:
			player_chosen.emit(target)
	elif t == Target.REFRESH:
		if refresh_enabled():
			refresh_requested.emit()
	elif t == Target.BOTS:
		bots_pressed.emit()
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
	var t := target_at(touch.position, view, content_left, content_right, scout_time_open)
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
	var status := status_text()
	if not status.is_empty():
		PixelFont.draw_right(self, content_right, Hud.BAR_H + 2, status, Palette.WOOD[3])
	var cards := card_rects(content_left, content_right)
	for i in mini(cards.size(), targets.size()):
		_draw_card(cards[i], targets[i], i)
	var target := selected_target()
	Hud.paint_button(self, plan_rect(view, content_right), PLAN_LABEL, _pressed == Target.PLAN,
			target == null or not target.is_bot)
	Hud.paint_button(self, close_rect(view, content_right), CLOSE_LABEL, _pressed == Target.CLOSE, false)
	Hud.paint_button(self, bots_rect(view, content_left), BOTS_LABEL, _pressed == Target.BOTS, false)
	if scout_time_open:
		Hud.paint_button(self, scout_time_rect(view, content_left), ScoutConfig.DURATION_LABELS[scout_duration],
				_pressed == Target.SCOUT_TIME, false)
	Hud.paint_button(self, scout_rect(view, content_left, scout_time_open), SCOUT_LABEL,
			_pressed == Target.SCOUT, not scout_enabled)
	Hud.paint_button(self, refresh_rect(view, content_left), refresh_label(refresh_cost),
			_pressed == Target.REFRESH, not refresh_enabled())
	var w := int(content_right - content_left)
	for i in mini(scout_lines.size(), 2):
		PixelFont.draw_text(self, Vector2(content_left, SCOUT_Y + i * (PixelFont.LINE + 1)), fit(scout_lines[i], w),
				Palette.THATCH[2] if i == 0 else Palette.THATCH[1])


func _draw_card(r: Rect2, t: TargetSearch.Target, i: int) -> void:
	var active := i == selected or _pressed == Target.CARD + i
	draw_rect(r, ResearchPanel.tile_color(false, active))
	var o := r.position
	draw_texture(PortraitArt.ruler_texture(t.ruler), o + Vector2(PAD, PAD))
	for line: Array in card_lines(t, int(r.size.x)):
		PixelFont.draw_text(self, o + (line[0] as Vector2), line[1] as String, line[2] as Color)
	if t.is_bot:
		# znacznik zamku-bota w prawym górnym rogu (epoka II jak na liście botów: czerwony)
		draw_rect(Rect2(r.end.x - 4, r.position.y + 2, 2, 2),
				Palette.ACCENT if t.age >= 1 else Palette.WOOD[3])
	if i == selected:
		CastleView.draw_frame(self, Rect2i(r), Palette.INK)
