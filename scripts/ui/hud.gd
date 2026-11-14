class_name Hud
extends Node2D
## Interfejs nad mapą (nie przesuwa się z kamerą), obsługiwany jednym kciukiem w poziomie.
## U góry: surowce z ikonami, a z prawej czas budowy (gdy kolejka pracuje) oraz epoka i rok.
## U dołu pasek komunikatu z FPS. Nad nim, zależnie od trybu:
## - oglądanie: w lewym rogu Oblężenie, w prawym Buduj, obok niego Badania; dotknięcie budynku
##   otwiera kartę,
## - budowa: przewijany w poziomie pasek budynków i Gotowe w prawym rogu; dotknięcia mapy
##   tylko stawiają budynki, niczego nie zaznaczają,
## - karta budynku: stan oraz Ulepsz, Rozbierz (Anuluj dla zlecenia) i Zamknij, wyśrodkowane.
## Dotknięcia przycisków i przewijanie paska nie trafiają do kamery. Gdy otwarty jest ekran
## na całą mapę (np. drzewko badań, `overlay`), HUD rysuje tylko górny i dolny pasek.

signal kind_selected(kind: int)
signal build_mode_changed(building: bool)
signal siege_pressed
signal upgrade_pressed
signal demolish_pressed
signal card_closed
signal research_pressed

enum CardButton { UPGRADE, DEMOLISH, CLOSE }
## Cele dotyku: przyciski w rogach, przyciski karty i rodzaje budynków na pasku (KIND + rodzaj).
enum Target { NONE = -1, SIEGE = 1, BUILD = 2, DONE = 3, RESEARCH = 4, CARD = 100, KIND = 200 }

const BAR_H := 12
## Margines treści od lewej i prawej krawędzi ekranu. Zaokrąglone narożniki telefonów ucinają
## ok. 10 px logicznych przy samej górze i dole, a Android nie zgłasza ich jako strefy
## niebezpiecznej, więc margines jest stały; wycięcia (np. na kamerę) dokładają do niego.
const CORNER_INSET := 12
## Przycisk 56×22 px logicznych: przy typowym telefonie (skala 6, ok. 420 dpi) to ok. 50 dp
## wysokości, czyli powyżej zalecanych 48 dp na cel dotyku.
const BUTTON_SIZE := Vector2(56, 22)
const BUTTON_GAP := 4
## Miejsce na FPS z prawej strony paska komunikatu (do testów wydajności na telefonie).
const FPS_WIDTH := 40
## Najszerszy komunikat, który mieści się w dolnym pasku obok FPS na ekranie 320 px.
const MESSAGE_MAX_WIDTH := 320 - 2 * CORNER_INSET - FPS_WIDTH
## Przesunięcie palca, od którego dotknięcie paska budynków staje się przewijaniem.
const DRAG_THRESHOLD := 6
const CARD_LABELS: Array[String] = ["Ulepsz", "Rozbierz", "Zamknij"]
const CANCEL_LABEL := "Anuluj"
const SIEGE_LABEL := "Oblężenie"
const BUILD_LABEL := "Buduj"
const DONE_LABEL := "Gotowe"
const RESEARCH_LABEL := "Badania"
## Komunikat w trybie oglądania i po dotknięciu wyszarzonego Oblężenia (bitwa dojdzie w #14).
const VIEW_MESSAGE := "Dotknij budynku albo wybierz Buduj"
const SIEGE_LATER_MESSAGE := "Oblężenia dojdą razem z bitwą"
const ICON_GAP := 2
const RESOURCE_GAP := 7

var economy: Economy
var message := ""
## Tryb budowy: pasek budynków zamiast przycisków Buduj i Oblężenie.
var building := false
var selected_kind := 0
## Pierwszy rodzaj widoczny na przewijanym pasku budynków.
var first_kind := 0
## Karta budynku: widoczna, gdy card_title nie jest pusty.
var card_title := ""
## Tekst z prawej strony karty, np. „poziom 2/5” albo „budowa 0:42”.
var card_status := ""
var card_can_upgrade := true
## Środkowy przycisk: Rozbierz, a dla budynku w kolejce Anuluj.
var card_cancel := false
var card_middle_enabled := true
## Czas budowy w prawym górnym rogu; pusty, gdy kolejka stoi.
var queue_text := ""
## Epoka i rok w prawym górnym rogu, np. „Epoka I · 550 r.”.
var age_text := ""
## Lewa i prawa granica treści w pikselach widoku (z marginesem narożników i wycięć).
var content_left := float(CORNER_INSET)
var content_right := 320.0 - CORNER_INSET
## Ekran na całą mapę (drzewko badań) przykrywa przyciski HUD i sam obsługuje dotyk.
var overlay := false

var _pressed: int = Target.NONE
var _drag_start := Vector2.ZERO
var _drag_first := 0
var _dragging := false


func _process(_delta: float) -> void:
	var bounds := content_bounds(get_viewport_rect().size, _safe_area_in_view())
	content_left = bounds.x
	content_right = bounds.y
	queue_redraw()


# --- Układ -----------------------------------------------------------------------------------

## Granice treści dla widoku `view` i strefy bezpiecznej `safe` (w pikselach widoku; pusta, gdy
## system jej nie podaje): nigdy bliżej krawędzi niż CORNER_INSET.
static func content_bounds(view: Vector2, safe: Rect2) -> Vector2:
	var left := float(CORNER_INSET)
	var right := view.x - CORNER_INSET
	if safe.has_area():
		left = maxf(left, ceilf(safe.position.x))
		right = minf(right, floorf(safe.end.x))
	# zabezpieczenie przed nietypową strefą bezpieczną: prawa granica nigdy nie przed lewą
	right = maxf(right, left)
	return Vector2(left, right)


## Strefa bezpieczna ekranu przeliczona na piksele widoku (pusta, gdy system jej nie podaje).
func _safe_area_in_view() -> Rect2:
	var safe := Rect2(DisplayServer.get_display_safe_area())
	if not safe.has_area():
		return Rect2()
	return get_viewport().get_final_transform().affine_inverse() * safe


## Górna krawędź rzędu przycisków nad paskiem komunikatu.
static func row_y(view: Vector2) -> float:
	return view.y - BAR_H - BUTTON_SIZE.y - 4


## Przycisk w lewym rogu (Oblężenie) i w prawym (Buduj albo Gotowe).
static func left_corner_rect(view: Vector2, left: float) -> Rect2:
	return Rect2(Vector2(left, row_y(view)), BUTTON_SIZE)


static func right_corner_rect(view: Vector2, right: float) -> Rect2:
	return Rect2(Vector2(right - BUTTON_SIZE.x, row_y(view)), BUTTON_SIZE)


## Przycisk Badania na lewo od Buduj (w trybie oglądania).
static func research_rect(view: Vector2, right: float) -> Rect2:
	return Rect2(Vector2(right - 2 * BUTTON_SIZE.x - BUTTON_GAP, row_y(view)), BUTTON_SIZE)


## Ile rodzajów budynków mieści się na pasku między lewą granicą a przyciskiem Gotowe.
static func visible_kinds(left: float, right: float) -> int:
	var area := right - BUTTON_SIZE.x - BUTTON_GAP - left
	return clampi(int((area + BUTTON_GAP) / (BUTTON_SIZE.x + BUTTON_GAP)), 1, BuildingTypes.buildable_count())


## Najdalsze przewinięcie paska (pierwszy widoczny rodzaj).
static func max_first_kind(left: float, right: float) -> int:
	return BuildingTypes.buildable_count() - visible_kinds(left, right)


## Prostokąty widocznych miejsc na pasku budowy (od lewej). Miejsce `i` pokazuje rodzaj first_kind + i.
static func kind_rects(view: Vector2, left: float, right: float) -> Array[Rect2]:
	var out: Array[Rect2] = []
	for i in visible_kinds(left, right):
		out.append(Rect2(Vector2(left + i * (BUTTON_SIZE.x + BUTTON_GAP), row_y(view)), BUTTON_SIZE))
	return out


## Przyciski karty budynku (Ulepsz, Rozbierz, Zamknij), wyśrodkowane nad paskiem komunikatu.
static func card_rects(view: Vector2) -> Array[Rect2]:
	var n := CARD_LABELS.size()
	var total := n * BUTTON_SIZE.x + (n - 1) * BUTTON_GAP
	var x := floorf((view.x - total) / 2.0)
	var out: Array[Rect2] = []
	for i in n:
		out.append(Rect2(Vector2(x + i * (BUTTON_SIZE.x + BUTTON_GAP), row_y(view)), BUTTON_SIZE))
	return out


## Cel pod punktem `p` w danym stanie interfejsu.
static func target_at(p: Vector2, view: Vector2, left: float, right: float, is_building: bool, card_open: bool,
		first: int) -> int:
	if card_open:
		var i := hit(card_rects(view), p)
		return Target.CARD + i if i >= 0 else Target.NONE
	if right_corner_rect(view, right).has_point(p):
		return Target.DONE if is_building else Target.BUILD
	if is_building:
		var k := hit(kind_rects(view, left, right), p)
		return Target.KIND + first + k if k >= 0 else Target.NONE
	if left_corner_rect(view, left).has_point(p):
		return Target.SIEGE
	if research_rect(view, right).has_point(p):
		return Target.RESEARCH
	return Target.NONE


## Indeks prostokąta pod punktem albo -1.
static func hit(rects: Array[Rect2], p: Vector2) -> int:
	for i in rects.size():
		if rects[i].has_point(p):
			return i
	return -1


# --- Stan --------------------------------------------------------------------------------------

func show_card(title: String, status: String, can_upgrade: bool, cancel: bool, middle_enabled: bool) -> void:
	card_title = title
	card_status = status
	card_can_upgrade = can_upgrade
	card_cancel = cancel
	card_middle_enabled = middle_enabled


func hide_card() -> void:
	card_title = ""


func is_card_open() -> bool:
	return not card_title.is_empty()


## Włącza albo wyłącza tryb budowy i powiadamia grę.
func set_building(on: bool) -> void:
	if building == on:
		return
	building = on
	build_mode_changed.emit(on)


# --- Teksty ------------------------------------------------------------------------------------

## Czas w formacie m:ss albo h:mm:ss, zaokrąglony w górę do pełnej sekundy.
static func format_time(ms: int) -> String:
	@warning_ignore("integer_division")
	var s := (maxi(0, ms) + 999) / 1000
	@warning_ignore("integer_division")
	var h := s / 3600
	@warning_ignore("integer_division")
	var m := (s % 3600) / 60
	if h > 0:
		return "%d:%02d:%02d" % [h, m, s % 60]
	return "%d:%02d" % [m, s % 60]


## Koszt jako tekst, np. „120 Dr 40 Ka 40 Ży” (pomija zera).
static func cost_text(cost: Array[int]) -> String:
	var parts: PackedStringArray = []
	for res in cost.size():
		if cost[res] > 0:
			parts.append("%d %s" % [cost[res], EconomyConfig.SHORT_NAMES[res]])
	return " ".join(parts)


## Liczby na pasku surowców (bez ikon). Pełny magazyn wyróżnia kolor liczby (bez dopisku,
## żeby pasek z czasem budowy oraz epoką i rokiem zmieścił się na ekranie 320 px).
static func resource_labels(amounts: Array[int]) -> Array[String]:
	var out: Array[String] = []
	for res in EconomyConfig.count():
		out.append("%d" % amounts[res])
	return out


## Lewe krawędzie ikon na pasku surowców, licząc od x = `left`, i na końcu prawa krawędź paska.
static func resource_layout(amounts: Array[int], left: int) -> Array[int]:
	var xs: Array[int] = []
	var x := left
	for label in resource_labels(amounts):
		xs.append(x)
		x += PixelIcons.SIZE + ICON_GAP + PixelFont.text_width(label) + RESOURCE_GAP
	xs.append(x - RESOURCE_GAP)
	return xs


## Tekst w prawym górnym rogu: czas budowy (jeśli trwa) oraz epoka i rok.
static func top_right_text(queue: String, age: String) -> String:
	return age if queue.is_empty() else "%s  %s" % [queue, age]


# --- Dotyk -------------------------------------------------------------------------------------

func _target_at(p: Vector2) -> int:
	if overlay:
		return Target.NONE
	return target_at(p, get_viewport_rect().size, content_left, content_right, building, is_card_open(), first_kind)


func _input(event: InputEvent) -> void:
	var drag := event as InputEventScreenDrag
	if drag != null:
		_on_drag(drag)
		return
	var touch := event as InputEventScreenTouch
	if touch == null:
		return
	var t := _target_at(touch.position)
	if touch.pressed:
		_pressed = t
		_dragging = false
		_drag_start = touch.position
		_drag_first = first_kind
		if t != Target.NONE:
			get_viewport().set_input_as_handled()
		return
	# przycisk działa, gdy palec puszczono na tym samym przycisku, na którym go położono,
	# i nie był to ruch przewijania paska
	var was := _pressed
	var dragged := _dragging
	_pressed = Target.NONE
	_dragging = false
	if was == Target.NONE:
		return
	get_viewport().set_input_as_handled()
	if dragged or t != was:
		return
	_activate(was)


## Przewijanie paska budynków: przesunięcie palca o szerokość przycisku przesuwa pasek o jeden rodzaj.
func _on_drag(drag: InputEventScreenDrag) -> void:
	if not building or _pressed < Target.KIND:
		return
	get_viewport().set_input_as_handled()
	var dx := drag.position.x - _drag_start.x
	if not _dragging and absf(dx) < DRAG_THRESHOLD:
		return
	_dragging = true
	var step := int(roundf(-dx / (BUTTON_SIZE.x + BUTTON_GAP)))
	first_kind = clampi(_drag_first + step, 0, max_first_kind(content_left, content_right))


func _activate(t: int) -> void:
	if t >= Target.KIND:
		selected_kind = t - Target.KIND
		kind_selected.emit(selected_kind)
	elif t >= Target.CARD:
		match t - Target.CARD:
			CardButton.UPGRADE:
				upgrade_pressed.emit()
			CardButton.DEMOLISH:
				demolish_pressed.emit()
			CardButton.CLOSE:
				card_closed.emit()
	elif t == Target.BUILD:
		set_building(true)
		kind_selected.emit(selected_kind)
	elif t == Target.DONE:
		set_building(false)
	elif t == Target.SIEGE:
		siege_pressed.emit()
	elif t == Target.RESEARCH:
		research_pressed.emit()


# --- Rysowanie ---------------------------------------------------------------------------------

func _draw() -> void:
	var view := get_viewport_rect().size
	draw_rect(Rect2(0, 0, view.x, BAR_H), Color(Palette.SHADOW, 0.8))
	if economy != null:
		_draw_resources()
	PixelFont.draw_right(self, content_right, 1, top_right_text(queue_text, age_text), Palette.INK)

	if overlay:
		pass
	elif is_card_open():
		_draw_card(view)
	elif building:
		_draw_build_bar(view)
	else:
		# Oblężenie jest wyszarzone tylko wizualnie: dotknięcie emituje siege_pressed, a gra pokazuje
		# SIEGE_LATER_MESSAGE. Przy włączaniu bitwy (#14, #16) zdejmij wyszarzenie razem z komunikatem.
		_draw_button(left_corner_rect(view, content_left), SIEGE_LABEL, _pressed == Target.SIEGE, true)
		_draw_button(right_corner_rect(view, content_right), BUILD_LABEL, _pressed == Target.BUILD, false)
		_draw_button(research_rect(view, content_right), RESEARCH_LABEL, _pressed == Target.RESEARCH, false)

	draw_rect(Rect2(0, view.y - BAR_H, view.x, BAR_H), Color(Palette.SHADOW, 0.6))
	PixelFont.draw_text(self, Vector2(content_left, view.y - BAR_H + 1), message, Palette.INK)
	PixelFont.draw_right(self, content_right, view.y - BAR_H + 1, "%d FPS" % Engine.get_frames_per_second(),
			Palette.WOOD[3])


func _draw_card(view: Vector2) -> void:
	var rects := card_rects(view)
	var r0 := rects[0]
	var panel := Rect2(r0.position - Vector2(4, 16), Vector2(rects[-1].end.x - r0.position.x + 8, r0.size.y + 20))
	draw_rect(panel, Color(Palette.SHADOW, 0.85))
	PixelFont.draw_text(self, panel.position + Vector2(4, 3), card_title, Palette.INK)
	PixelFont.draw_right(self, panel.end.x - 4, panel.position.y + 3, card_status, Palette.THATCH[2])
	for i in rects.size():
		var label := CANCEL_LABEL if i == CardButton.DEMOLISH and card_cancel else CARD_LABELS[i]
		var disabled := (i == CardButton.UPGRADE and not card_can_upgrade) \
				or (i == CardButton.DEMOLISH and not card_middle_enabled)
		_draw_button(rects[i], label, _pressed == Target.CARD + i, disabled)


## Pasek budowy: widoczne rodzaje, strzałki, gdy część rodzajów jest poza paskiem, i Gotowe.
func _draw_build_bar(view: Vector2) -> void:
	var rects := kind_rects(view, content_left, content_right)
	for i in rects.size():
		var kind := first_kind + i
		var active := kind == selected_kind or _pressed == Target.KIND + kind
		_draw_button(rects[i], BuildingTypes.SHORT_NAMES[kind], active, false)
	var y := row_y(view) + BUTTON_SIZE.y / 2.0 - 2.0
	if first_kind > 0:
		_draw_arrow(Vector2(rects[0].position.x - 3, y), -1)
	if first_kind < max_first_kind(content_left, content_right):
		_draw_arrow(Vector2(rects[-1].end.x + 1, y), 1)
	_draw_button(right_corner_rect(view, content_right), DONE_LABEL, _pressed == Target.DONE, false)


## Mała strzałka 2×5 px wskazująca, że pasek można przewinąć w stronę `dir`.
func _draw_arrow(at: Vector2, dir: int) -> void:
	for i in 3:
		var h := 5 - 2 * i
		var x := at.x + (i if dir > 0 else 2 - i)
		draw_rect(Rect2(x, at.y + i, 1, h), Palette.INK)


## Ikona 5×5 na wysokości wielkich liter, obok liczba. Pełny magazyn świeci kolorem strzechy.
func _draw_resources() -> void:
	var labels := resource_labels(economy.amounts)
	var xs := resource_layout(economy.amounts, int(content_left))
	for res in labels.size():
		PixelIcons.draw_resource(self, Vector2(xs[res], 1 + PixelFont.CAP_TOP), res)
		var col: Color = Palette.THATCH[2] if economy.is_full(res) else Palette.INK
		PixelFont.draw_text(self, Vector2(xs[res] + PixelIcons.SIZE + ICON_GAP, 1), labels[res], col)


func _draw_button(r: Rect2, label: String, active: bool, disabled: bool) -> void:
	paint_button(self, r, label, active, disabled)


## Przycisk z desek: jaśniejszy, gdy wciśnięty; wyszarzony napis, gdy nieaktywny.
static func paint_button(ci: CanvasItem, r: Rect2, label: String, active: bool, disabled: bool) -> void:
	ci.draw_rect(r, Palette.WOOD[2] if active else Palette.WOOD[1])
	ci.draw_rect(Rect2(r.position, Vector2(r.size.x, 1)), Palette.WOOD[3])
	ci.draw_rect(Rect2(r.position + Vector2(0, r.size.y - 1), Vector2(r.size.x, 1)), Palette.WOOD[0])
	var col: Color = Palette.WOOD[0] if disabled else Palette.INK
	PixelFont.draw_centered(ci, r, label, col)
