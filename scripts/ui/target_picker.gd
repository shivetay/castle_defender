class_name TargetPicker
extends Node2D
## Wybór celu ataku (#24), pierwszy ekran Wyprawy ze Strażnicy: zawsze 3 karty celów. Karta ma
## portret władcy, imię gracza, epokę, nazwę zamku, miniaturę zamku (teren i zarys budynków),
## ranking obrony (bot: trudność) i szacowany łup. Graczy dobiera serwer (TargetSearch, `find_targets`);
## puste miejsca, a bez sieci wszystkie trzy, zajmują zamki-boty. Boty otwiera dotychczasową listę
## 20 zamków-botów (BotPicker), Planuj plan ataku na wybranym celu, a Wróć wraca do mapy.
## Planuj na karcie gracza zaczyna atak na serwerze (`start_attack`, #240) i otwiera plan na kopii
## jego zamku. Panel sam obsługuje dotyk, więc nic nie trafia do kamery ani do HUD.
@warning_ignore_start("integer_division")

signal bot_chosen(index: int)
signal player_chosen(target: TargetSearch.Target)
signal bots_pressed
signal closed

enum Target { NONE = -1, PLAN = 1, CLOSE = 2, BOTS = 3, CARD = 100 }
## Stan szukania graczy (napis z prawej od tytułu).
enum Search { OFFLINE, SEARCHING, DONE, FAILED, LIMITED }

const TITLE := "Wyprawa: wybierz cel"
const SEARCH_TEXTS: Array[String] = ["Bez sieci: boty", "Szukam graczy...", "", "Brak odpowiedzi: boty",
		"Za często: boty"]
const NO_PLAYERS_TEXT := "Brak graczy: boty"
const PLAN_LABEL := "Planuj"
const CLOSE_LABEL := "Wróć"
const BOTS_LABEL := "Boty"
## Karta gracza: jego punkty rankingu obrony (#27).
const DEFENSE_RATING_LABEL := "Obrona"
const CARD_Y := Hud.BAR_H + 12
const CARD_GAP := 4
const CARD_H := 90
## Odstęp treści od brzegu karty.
const PAD := 2
const MINI_Y := 36
const LOOT_Y := 70

var targets: Array[TargetSearch.Target] = []
var selected := 0
var search: int = Search.OFFLINE
var beaten := 0
var content_left := float(Hud.CORNER_INSET)
var content_right := 320.0 - Hud.CORNER_INSET

var _pressed: int = Target.NONE


## Otwiera ekran z 3 botami; `online`: trwa szukanie graczy, wynik da `set_players`.
func open(beaten_count: int, online: bool) -> void:
	beaten = beaten_count
	MinimapArt.clear_cache()
	targets = TargetSearch.fill([] as Array[TargetSearch.Target], beaten)
	search = Search.SEARCHING if online else Search.OFFLINE
	selected = 0
	visible = true
	_pressed = Target.NONE
	queue_redraw()


## Wynik szukania z serwera: gracze zajmują pierwsze karty, reszta zostaje dla botów.
## `limited`: serwer odrzucił szukanie z limitu, zostają boty.
func set_players(players: Array[TargetSearch.Target], ok: bool, limited: bool = false) -> void:
	if search != Search.SEARCHING:
		return
	search = Search.DONE if ok else (Search.LIMITED if limited else Search.FAILED)
	if ok:
		targets = TargetSearch.fill(players, beaten)
		selected = 0
	queue_redraw()


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


static func target_at(p: Vector2, view: Vector2, left: float, right: float) -> int:
	if plan_rect(view, right).has_point(p):
		return Target.PLAN
	if close_rect(view, right).has_point(p):
		return Target.CLOSE
	if bots_rect(view, left).has_point(p):
		return Target.BOTS
	var cards := card_rects(left, right)
	for i in cards.size():
		if cards[i].has_point(p):
			return Target.CARD + i
	return Target.NONE


## Linie tekstu karty [pozycja względem karty, tekst, kolor], przycięte do szerokości karty.
static func card_lines(t: TargetSearch.Target, w: int) -> Array:
	var side := w - PortraitArt.SIZE - 2 * PAD - 2
	var stats_x := PAD + MinimapArt.SIZE + 3
	var stats_w := w - stats_x - PAD
	var out: Array = [
		[Vector2(PAD + PortraitArt.SIZE + 2, 3), fit(t.player_name, side), Palette.INK],
		[Vector2(PAD + PortraitArt.SIZE + 2, 13), TargetSearch.age_label(t.age), Palette.THATCH[2]],
		[Vector2(PAD, 26), fit(t.castle_name, w - 2 * PAD), Palette.THATCH[2]],
	]
	if t.is_bot:
		out.append([Vector2(stats_x, MINI_Y), fit("Trudność", stats_w), Palette.THATCH[1]])
		out.append([Vector2(stats_x, MINI_Y + 9), "%d/%d" % [t.bot_idx + 1, BotRoster.COUNT], Palette.INK])
	else:
		# ranking obrony celu (#27): z nim mierzy się ranking ataku gracza
		out.append([Vector2(stats_x, MINI_Y), fit(DEFENSE_RATING_LABEL, stats_w), Palette.THATCH[1]])
		out.append([Vector2(stats_x, MINI_Y + 9), str(t.rating), Palette.INK])
	out.append([Vector2(stats_x, MINI_Y + 20), fit("Łup ok.", stats_w), Palette.THATCH[1]])
	for res in t.loot.size():
		var at := loot_pos(res, w) + Vector2(PixelIcons.SIZE + 2, -1)
		out.append([at, str(t.loot[res]), Palette.INK])
	return out


## Jedna linia najwyżej `width` px (z „...”, gdy się nie mieści); pusty tekst zostaje pusty.
static func fit(text: String, width: int) -> String:
	var lines := PixelFont.wrap(text, width, 1)
	return lines[0] if not lines.is_empty() else ""


## Lewy górny róg ikony surowca `res` na karcie: dwa wiersze po dwa surowce.
static func loot_pos(res: int, w: int) -> Vector2:
	var col_w := (w - 2 * PAD) / 2
	return Vector2(PAD + (res % 2) * col_w, LOOT_Y + 1 + (res / 2) * (PixelFont.LINE + 1))


func _activate(t: int) -> void:
	if t >= Target.CARD:
		selected = t - Target.CARD
	elif t == Target.PLAN:
		var target := selected_target()
		if target == null:
			return
		if target.is_bot:
			bot_chosen.emit(target.bot_idx)
		else:
			player_chosen.emit(target)
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
	var t := target_at(touch.position, view, content_left, content_right)
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


func _draw_card(r: Rect2, t: TargetSearch.Target, i: int) -> void:
	var active := i == selected or _pressed == Target.CARD + i
	draw_rect(r, ResearchPanel.tile_color(false, active))
	var o := r.position
	draw_texture(PortraitArt.ruler_texture(t.ruler), o + Vector2(PAD, PAD))
	draw_texture(MinimapArt.castle_texture(t.key(), t.map_seed, t.footprint), o + Vector2(PAD, MINI_Y))
	for line: Array in card_lines(t, int(r.size.x)):
		PixelFont.draw_text(self, o + (line[0] as Vector2), line[1] as String, line[2] as Color)
	for res in t.loot.size():
		PixelIcons.draw_resource(self, o + loot_pos(res, int(r.size.x)), res)
	if t.is_bot:
		# znacznik zamku-bota w prawym górnym rogu (epoka II jak na liście botów: czerwony)
		draw_rect(Rect2(r.end.x - 4, r.position.y + 2, 2, 2),
				Palette.ACCENT if t.age >= 1 else Palette.WOOD[3])
	if i == selected:
		CastleView.draw_frame(self, Rect2i(r), Palette.INK)
