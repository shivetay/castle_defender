class_name Hud
extends Node2D
## Interfejs nad mapą (nie przesuwa się z kamerą), obsługiwany jednym kciukiem w poziomie.
## U góry: surowce z ikonami, a z prawej czas budowy (gdy kolejka pracuje) oraz epoka i rok.
## U dołu pasek komunikatu z FPS. Przyciski trybów stoją w kolumnie przy prawej krawędzi, od góry
## (po teście na telefonie: mniejsze i nie zasłaniają środka mapy):
## - oglądanie: Buduj, Badania, Wojsko, Oblężenie, Atak, Obrona, Kolejka (z liczbą zleceń, #163);
##   dotknięcie budynku otwiera kartę, a dotknięcie czasu budowy na górnym pasku otwiera Kolejkę,
## - budowa: Gotowe i Zmień (wraca do panelu budowy); dotknięcia mapy tylko stawiają wybrany
##   budynek, niczego nie zaznaczają,
## - karta budynku: stan, koszt ulepszenia oraz Ulepsz, Rozbierz (Anuluj dla zlecenia), przy budynku
##   rekrutacji Szkol, i Zamknij, wyśrodkowane nad paskiem komunikatu.
## Dotknięcia przycisków nie trafiają do kamery. Gdy otwarty jest ekran
## na całą mapę (np. drzewko badań, `overlay`), HUD rysuje tylko górny i dolny pasek.

signal build_pressed
signal change_pressed
signal build_mode_changed(building: bool)
signal siege_pressed
signal speed_pressed
signal upgrade_pressed
signal demolish_pressed
signal card_closed
signal research_pressed
signal army_pressed
signal recruit_pressed
signal attack_pressed
signal defence_pressed
signal queue_pressed
signal menu_pressed

enum CardButton { UPGRADE, DEMOLISH, RECRUIT, CLOSE }
## Cele dotyku: przyciski kolumny i przyciski karty.
enum Target { NONE = -1, SIEGE = 1, BUILD = 2, DONE = 3, RESEARCH = 4, ARMY = 5, CHANGE = 6, SPEED = 7, ATTACK = 8, DEFENCE = 9, QUEUE = 10, MENU = 11, CARD = 100 }

const BAR_H := 12
## Margines treści od lewej i prawej krawędzi ekranu. Zaokrąglone narożniki telefonów ucinają
## ok. 10 px logicznych przy samej górze i dole, a Android nie zgłasza ich jako strefy
## niebezpiecznej, więc margines jest stały; wycięcia (np. na kamerę) dokładają do niego.
const CORNER_INSET := 12
## Przycisk 48×16 px logicznych (po teście na telefonie mniejszy niż wcześniejsze 56×22; decyzja
## właściciela). Przy skali 6 to ok. 37 dp wysokości, mniej niż zalecane 48 dp, ale ponad
## minimum 12×12 px z CLAUDE.md.
const BUTTON_SIZE := Vector2(48, 16)
const BUTTON_GAP := 3
## Główna kolumna (tryb oglądania, #150): przyciski z ikoną zamiast napisu, żeby nie zasłaniały mapy.
## Nazwa pojawia się w dymku obok, póki palec trzyma przycisk.
const ICON_BUTTON_SIZE := Vector2(18, 16)
## Miejsce na FPS z prawej strony paska komunikatu (do testów wydajności na telefonie).
const FPS_WIDTH := 40
## Najszerszy komunikat, który mieści się w dolnym pasku obok FPS na ekranie 320 px.
const MESSAGE_MAX_WIDTH := 320 - 2 * CORNER_INSET - FPS_WIDTH
const CARD_LABELS: Array[String] = ["Ulepsz", "Rozbierz", "Zamknij"]
## Karta budynku rekrutacji ma czwarty przycisk Szkol przed Zamknij.
const RECRUIT_CARD_LABELS: Array[String] = ["Ulepsz", "Rozbierz", "Szkol", "Zamknij"]
const ARMY_LABEL := "Wojsko"
const CANCEL_LABEL := "Anuluj"
const SIEGE_LABEL := "Oblężenie"
const ATTACK_LABEL := "Atak"
const DEFENCE_LABEL := "Obrona"
const QUEUE_LABEL := "Kolejka"
const MENU_LABEL := "Menu"
const GOAL_PREFIX := "Cel:"
const BUILD_LABEL := "Buduj"
const DONE_LABEL := "Gotowe"
const CHANGE_LABEL := "Zmień"
const RESEARCH_LABEL := "Badania"
## Komunikat w trybie oglądania i po dotknięciu wyszarzonego Oblężenia (bitwa dojdzie w #14).
const VIEW_MESSAGE := "Dotknij budynku albo wybierz Buduj"
const SIEGE_LATER_MESSAGE := "Wszystkie fale samouczka obronione"
const ICON_GAP := 2
const RESOURCE_GAP := 7

var economy: Economy
var message := ""
## Tryb budowy: w kolumnie Gotowe i Zmień zamiast przycisków trybów.
var building := false
## Wybrany rodzaj budynku (BuildingTypes.Kind), ustawia go panel budowy.
var selected_kind := 0
## Karta budynku: widoczna, gdy card_title nie jest pusty.
var card_title := ""
## Tekst z prawej strony karty, np. „poziom 2/5” albo „budowa 0:42”.
var card_status := ""
var card_can_upgrade := true
## Linia pod tytułem karty: koszt i czas ulepszenia albo informacja o maksymalnym poziomie.
var card_info := ""
## Fragmenty card_info na czerwono (brakujące surowce na ulepszenie).
var card_info_missing: PackedStringArray = []
## Środkowy przycisk: Rozbierz, a dla budynku w kolejce Anuluj.
var card_cancel := false
var card_middle_enabled := true
## Karta budynku rekrutacji (z przyciskiem Szkol).
var card_recruit := false
## Czas budowy w prawym górnym rogu; pusty, gdy kolejka stoi.
var queue_text := ""
## Czas do końca badania w prawym górnym rogu, np. „Bad. 0:42”; pusty, gdy nic się nie bada.
var research_text := ""
## Epoka i rok w prawym górnym rogu, np. „Epoka I · 550 r.”.
var age_text := ""
## Lewa i prawa granica treści w pikselach widoku (z marginesem narożników i wycięć).
var content_left := float(CORNER_INSET)
var content_right := 320.0 - CORNER_INSET
## Ekran na całą mapę (drzewko badań) przykrywa przyciski HUD i sam obsługuje dotyk.
var overlay := false
## Trwa bitwa (samouczek PvE #16): w kolumnie jest tylko Tempo, a dotknięcia mapy nic nie robią.
var battle := false
## Bieżący cel samouczka (#185), np. „Postaw Koszary”; pusty po 5. fali. Pokazuje się pod górnym
## paskiem, poza bitwą i ekranami na całą mapę.
var goal_text := ""
## Zlecenia budowy i szkolenia razem (licznik na przycisku Kolejka).
var queue_count := 0
## Napis przycisku tempa, np. „Tempo ×2”.
var speed_label := "Tempo ×1"

var _pressed: int = Target.NONE


func _process(_delta: float) -> void:
	var bounds := content_bounds(get_viewport_rect().size, safe_area_in_view(get_viewport()))
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


## Strefa bezpieczna ekranu przeliczona na piksele widoku `viewport` (pusta, gdy system jej nie
## podaje). Używają jej HUD i ekrany na całą mapę, żeby przyciski stały w tych samych miejscach.
static func safe_area_in_view(viewport: Viewport) -> Rect2:
	var safe := Rect2(DisplayServer.get_display_safe_area())
	if not safe.has_area():
		return Rect2()
	return viewport.get_final_transform().affine_inverse() * safe


## Górna krawędź rzędu przycisków nad paskiem komunikatu.
static func row_y(view: Vector2) -> float:
	return view.y - BAR_H - BUTTON_SIZE.y - 4


## Prawy dolny róg (Zamknij na ekranach na całą mapę).
static func right_corner_rect(view: Vector2, right: float) -> Rect2:
	return Rect2(Vector2(right - BUTTON_SIZE.x, row_y(view)), BUTTON_SIZE)


## Przycisk na lewo od prawego dolnego rogu (Badaj, Szkol, Postaw na ekranach na całą mapę).
static func research_rect(view: Vector2, right: float) -> Rect2:
	return Rect2(Vector2(right - 2 * BUTTON_SIZE.x - BUTTON_GAP, row_y(view)), BUTTON_SIZE)


## Przycisk `i` kolumny przy prawej krawędzi, licząc od góry (pod górnym paskiem).
## `icons`: wąski przycisk z ikoną (główna kolumna, uses_icons).
static func column_rect(right: float, i: int, icons: bool = false) -> Rect2:
	var sz := ICON_BUTTON_SIZE if icons else BUTTON_SIZE
	return Rect2(Vector2(right - sz.x, BAR_H + 4 + i * (sz.y + BUTTON_GAP)), sz)


## Czy kolumna w tym trybie ma przyciski z ikonami (oglądanie zamku) zamiast napisów.
static func uses_icons(is_building: bool, in_battle: bool = false) -> bool:
	return not is_building and not in_battle


## Przyciski kolumny w danym trybie, od góry.
static func column_targets(is_building: bool, in_battle: bool = false) -> Array[int]:
	if in_battle:
		return [Target.SPEED] as Array[int]
	if is_building:
		return [Target.DONE, Target.CHANGE] as Array[int]
	return [Target.BUILD, Target.RESEARCH, Target.ARMY, Target.SIEGE, Target.ATTACK, Target.DEFENCE,
			Target.QUEUE, Target.MENU] as Array[int]


## Przyciski karty budynku (Ulepsz, Rozbierz, [Szkol,] Zamknij), wyśrodkowane nad paskiem komunikatu.
static func card_rects(view: Vector2, recruit: bool = false) -> Array[Rect2]:
	var n := RECRUIT_CARD_LABELS.size() if recruit else CARD_LABELS.size()
	var total := n * BUTTON_SIZE.x + (n - 1) * BUTTON_GAP
	var x := floorf((view.x - total) / 2.0)
	var out: Array[Rect2] = []
	for i in n:
		out.append(Rect2(Vector2(x + i * (BUTTON_SIZE.x + BUTTON_GAP), row_y(view)), BUTTON_SIZE))
	return out


## Przycisk karty (CardButton) na miejscu `i`: bez Szkol trzecie miejsce to Zamknij.
static func card_button(i: int, recruit: bool) -> int:
	if not recruit and i == 2:
		return CardButton.CLOSE
	return i


## Cel pod punktem `p` w danym stanie interfejsu. Przyciski karty to CARD + CardButton.
static func target_at(p: Vector2, view: Vector2, right: float, is_building: bool, card_open: bool,
		recruit_card: bool = false, in_battle: bool = false) -> int:
	if card_open and not in_battle:
		var i := hit(card_rects(view, recruit_card), p)
		return Target.CARD + card_button(i, recruit_card) if i >= 0 else Target.NONE
	var targets := column_targets(is_building, in_battle)
	var icons := uses_icons(is_building, in_battle)
	for i in targets.size():
		if column_rect(right, i, icons).has_point(p):
			return targets[i]
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


## Fragmenty tekstu kosztu, na które nie stać gracza, np. ["120 Dr"] (po teście na telefonie
## brakujące surowce są na czerwono). Format jak w cost_text.
static func missing_tokens(cost: Array[int], amounts: Array[int]) -> PackedStringArray:
	var out: PackedStringArray = []
	for res in cost.size():
		if cost[res] > 0 and res < amounts.size() and amounts[res] < cost[res]:
			out.append("%d %s" % [cost[res], EconomyConfig.SHORT_NAMES[res]])
	return out


## Rysuje tekst kolorem `col`, a fragmenty z `tokens` kolorem `hl` (każdy fragment raz, od lewej).
static func draw_highlighted(ci: CanvasItem, pos: Vector2, text: String, col: Color, tokens: PackedStringArray,
		hl: Color) -> void:
	var x := pos.x
	var rest := text
	while not rest.is_empty():
		var best := -1
		var token := ""
		for t in tokens:
			var i := rest.find(t)
			if i >= 0 and (best < 0 or i < best):
				best = i
				token = t
		if best < 0:
			PixelFont.draw_text(ci, Vector2(x, pos.y), rest, col)
			return
		var before := rest.substr(0, best)
		PixelFont.draw_text(ci, Vector2(x, pos.y), before, col)
		x += PixelFont.text_width(before) + (1 if not before.is_empty() else 0)
		PixelFont.draw_text(ci, Vector2(x, pos.y), token, hl)
		x += PixelFont.text_width(token) + 1
		rest = rest.substr(best + token.length())


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


## Tekst w prawym górnym rogu: czas budowy i badania (jeśli trwają) oraz epoka i rok.
static func top_right_text(queue: String, age: String, research: String = "") -> String:
	var parts: PackedStringArray = []
	for part: String in [queue, research, age]:
		if not part.is_empty():
			parts.append(part)
	return "  ".join(parts)


# --- Dotyk -------------------------------------------------------------------------------------

func _target_at(p: Vector2) -> int:
	if overlay:
		return Target.NONE
	if not battle and queue_text_rect(content_right, queue_text, research_text, age_text).has_point(p):
		return Target.QUEUE
	return target_at(p, get_viewport_rect().size, content_right, building, is_card_open(), card_recruit, battle)


## Napis w prawym górnym rogu jako cel dotyku, który otwiera Kolejkę (#163): od lewego brzegu tekstu
## do końca epoki, na całą wysokość paska. Działa tylko wtedy, gdy coś się buduje (jest czas budowy);
## samo szkolenie albo badanie nie robi z paska celu, a Kolejkę otwiera wtedy przycisk w kolumnie.
static func queue_text_rect(right: float, queue: String, research: String, age: String) -> Rect2:
	if queue.is_empty():
		return Rect2()
	var w := PixelFont.text_width(top_right_text(queue, age, research))
	return Rect2(right - w - 2, 0, w + 2, BAR_H)


## Pasek celu samouczka (#185): pod górnym paskiem, od lewej granicy treści do kolumny przycisków.
static func goal_rect(left: float, right: float, icons: bool = true) -> Rect2:
	var w := ICON_BUTTON_SIZE.x if icons else BUTTON_SIZE.x
	return Rect2(left, BAR_H + 2, right - w - BUTTON_GAP - left, 10)


## Napis przycisku Kolejka: z liczbą zleceń budowy i szkolenia, gdy coś trwa.
static func queue_label(count: int) -> String:
	return QUEUE_LABEL if count <= 0 else "%s %d" % [QUEUE_LABEL, count]


func _input(event: InputEvent) -> void:
	var touch := event as InputEventScreenTouch
	if touch == null:
		return
	var t := _target_at(touch.position)
	if touch.pressed:
		_pressed = t
		if t != Target.NONE:
			get_viewport().set_input_as_handled()
		return
	# przycisk działa, gdy palec puszczono na tym samym przycisku, na którym go położono
	var was := _pressed
	_pressed = Target.NONE
	if was == Target.NONE:
		return
	get_viewport().set_input_as_handled()
	if t != was:
		return
	_activate(was)


func _activate(t: int) -> void:
	if t >= Target.CARD:
		match t - Target.CARD:
			CardButton.UPGRADE:
				upgrade_pressed.emit()
			CardButton.DEMOLISH:
				demolish_pressed.emit()
			CardButton.RECRUIT:
				recruit_pressed.emit()
			CardButton.CLOSE:
				card_closed.emit()
	elif t == Target.BUILD:
		build_pressed.emit()
	elif t == Target.SPEED:
		speed_pressed.emit()
	elif t == Target.CHANGE:
		change_pressed.emit()
	elif t == Target.DONE:
		set_building(false)
	elif t == Target.SIEGE:
		siege_pressed.emit()
	elif t == Target.RESEARCH:
		research_pressed.emit()
	elif t == Target.ARMY:
		army_pressed.emit()
	elif t == Target.ATTACK:
		attack_pressed.emit()
	elif t == Target.DEFENCE:
		defence_pressed.emit()
	elif t == Target.QUEUE:
		queue_pressed.emit()
	elif t == Target.MENU:
		menu_pressed.emit()


# --- Rysowanie ---------------------------------------------------------------------------------

func _draw() -> void:
	var view := get_viewport_rect().size
	draw_rect(Rect2(0, 0, view.x, BAR_H), Color(Palette.SHADOW, 0.8))
	if economy != null:
		_draw_resources()
	PixelFont.draw_right(self, content_right, 1, top_right_text(queue_text, age_text, research_text), Palette.INK)

	if not goal_text.is_empty() and not overlay and not battle:
		var r := goal_rect(content_left, content_right, uses_icons(building, battle))
		draw_rect(r, Color(Palette.SHADOW, 0.7))
		PixelFont.draw_text(self, r.position + Vector2(2, 1), GOAL_PREFIX, Palette.THATCH[2])
		PixelFont.draw_text(self, r.position + Vector2(3 + PixelFont.text_width(GOAL_PREFIX) + 2, 1),
				ResearchPanel.fit_text(goal_text, int(r.size.x) - PixelFont.text_width(GOAL_PREFIX) - 8), Palette.INK)
	if overlay:
		pass
	elif is_card_open() and not battle:
		_draw_card(view)
	else:
		var targets := column_targets(building, battle)
		var icons := uses_icons(building, battle)
		for i in targets.size():
			var label := speed_label if targets[i] == Target.SPEED else column_label(targets[i])
			if targets[i] == Target.QUEUE:
				label = queue_label(queue_count)
			if icons:
				_draw_icon_button(column_rect(content_right, i, true), i, label, _pressed == targets[i],
						queue_count if targets[i] == Target.QUEUE else 0)
			else:
				_draw_button(column_rect(content_right, i), label, _pressed == targets[i], false)

	draw_rect(Rect2(0, view.y - BAR_H, view.x, BAR_H), Color(Palette.SHADOW, 0.6))
	PixelFont.draw_text(self, Vector2(content_left, view.y - BAR_H + 1), message, Palette.INK)
	PixelFont.draw_right(self, content_right, view.y - BAR_H + 1, "%d FPS" % Engine.get_frames_per_second(),
			Palette.WOOD[3])


static func column_label(t: int) -> String:
	match t:
		Target.BUILD:
			return BUILD_LABEL
		Target.RESEARCH:
			return RESEARCH_LABEL
		Target.ARMY:
			return ARMY_LABEL
		Target.SIEGE:
			return SIEGE_LABEL
		Target.ATTACK:
			return ATTACK_LABEL
		Target.DEFENCE:
			return DEFENCE_LABEL
		Target.QUEUE:
			return QUEUE_LABEL
		Target.MENU:
			return MENU_LABEL
		Target.DONE:
			return DONE_LABEL
		Target.CHANGE:
			return CHANGE_LABEL
	return ""


func _draw_card(view: Vector2) -> void:
	var rects := card_rects(view, card_recruit)
	var labels := RECRUIT_CARD_LABELS if card_recruit else CARD_LABELS
	var r0 := rects[0]
	var panel := Rect2(r0.position - Vector2(4, 26), Vector2(rects[-1].end.x - r0.position.x + 8, r0.size.y + 30))
	draw_rect(panel, Color(Palette.SHADOW, 0.85))
	PixelFont.draw_text(self, panel.position + Vector2(4, 3), card_title, Palette.INK)
	PixelFont.draw_right(self, panel.end.x - 4, panel.position.y + 3, card_status, Palette.THATCH[2])
	var info_width := int(panel.size.x - 8)
	draw_highlighted(self, panel.position + Vector2(4, 13), ResearchPanel.fit_text(card_info, info_width),
			Palette.WOOD[3], card_info_missing, Palette.ACCENT)
	for i in rects.size():
		var button := card_button(i, card_recruit)
		var label := CANCEL_LABEL if button == CardButton.DEMOLISH and card_cancel else labels[i]
		var disabled := (button == CardButton.UPGRADE and not card_can_upgrade) \
				or (button == CardButton.DEMOLISH and not card_middle_enabled)
		_draw_button(rects[i], label, _pressed == Target.CARD + button, disabled)


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


## Przycisk z ikoną: deska jak w paint_button, ikona pośrodku, liczba zleceń w czerwonej plakietce
## przy lewym dolnym rogu. Wciśnięty pokazuje swoją nazwę w dymku po lewej.
func _draw_icon_button(r: Rect2, icon: int, label: String, active: bool, count: int) -> void:
	paint_button(self, r, "", active, false)
	var at := r.position + ((r.size - Vector2(PixelIcons.MENU_SIZE, PixelIcons.MENU_SIZE)) / 2.0).floor()
	# ciemne okienko pod ikoną, żeby drewniane ikony odcinały się od deski
	draw_rect(Rect2(at - Vector2(2, 2), Vector2(PixelIcons.MENU_SIZE + 4, PixelIcons.MENU_SIZE + 4)),
			Color(Palette.SHADOW, 0.7))
	PixelIcons.draw_menu(self, at, icon)
	if count > 0:
		var n := str(count)
		var w := PixelFont.text_width(n) + 2
		var badge := Rect2(r.position.x - w + 3, r.end.y - 8, w, 9)
		draw_rect(badge, Palette.ACCENT)
		PixelFont.draw_text(self, badge.position + Vector2(1, 0), n, Palette.INK)
	if active:
		var w := PixelFont.text_width(label) + 6
		var tip := Rect2(r.position.x - w - BUTTON_GAP, r.position.y, w, r.size.y)
		draw_rect(tip, Color(Palette.SHADOW, 0.85))
		PixelFont.draw_centered(self, tip, label, Palette.INK)


## Przycisk z desek: jaśniejszy, gdy wciśnięty; wyszarzony napis, gdy nieaktywny.
static func paint_button(ci: CanvasItem, r: Rect2, label: String, active: bool, disabled: bool) -> void:
	ci.draw_rect(r, Palette.WOOD[2] if active else Palette.WOOD[1])
	ci.draw_rect(Rect2(r.position, Vector2(r.size.x, 1)), Palette.WOOD[3])
	ci.draw_rect(Rect2(r.position + Vector2(0, r.size.y - 1), Vector2(r.size.x, 1)), Palette.WOOD[0])
	var col: Color = Palette.WOOD[0] if disabled else Palette.INK
	PixelFont.draw_centered(ci, r, label, col)
