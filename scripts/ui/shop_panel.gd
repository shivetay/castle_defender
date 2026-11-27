class_name ShopPanel
extends Node2D
## Sklep w Targu (#408) na przyciemnionym zamku: grupy ofert jedna pod drugą, w każdej do 3 kart (nazwa, ikona
## surowca, ilość i Odbierz). Po odbiorze karta odlicza odnowienie („2 h 15 min”), a gdy według telefonu surowiec
## nie zmieści się w magazynie, przycisk jest wyszarzony z napisem „Magazyn pełny” (rozstrzyga i tak serwer).
## Sklep działa tylko online: bez sieci albo przy błędzie pokazuje „Brak połączenia”. Grupy przewija się
## przeciągnięciem palca, po całej grupie, więc rysunek zostaje w całych pikselach.

signal closed
signal claim_requested(offer_id: int)

enum Target { NONE = -1, CLOSE = 100, CARD = 1000 }
enum CardState { READY, COOLDOWN, FULL, BUSY }

const TITLE := "Targ"
const CLAIM_LABEL := "Odbierz"
const CLOSE_LABEL := "Zamknij"
const LOADING := "Wczytywanie ofert..."
const EMPTY := "Brak ofert, zajrzyj później"
const LIST_TOP := 18
## Nagłówek grupy (nazwa) i rząd kart pod nim.
const HEADER_H := 10
const CARD_H := 32
const GROUP_GAP := 2
const GROUP_H := HEADER_H + CARD_H + GROUP_GAP
const CARD_W := 94
const CARD_GAP := 4
## Przycisk na karcie: 88×12 px, ponad minimum 12×12 z CLAUDE.md.
const BUTTON_H := 12
const CLOSE_SIZE := Vector2(76, 14)
## Przeciągnięcie o tyle pikseli przewija o jedną grupę.
const DRAG_STEP := 22

var economy: Economy
var groups: Array[ShopNet.Group] = []
var loading := false
var offline := false
## Linia pod listą: wynik ostatniego odbioru albo błąd.
var status := ""
## Oferta, której odbiór czeka na serwer (0: żadna).
var pending_offer := 0
## Pierwsza widoczna grupa.
var first := 0
var _pressed: int = Target.NONE
var _drag := 0.0
var _dragged := false
var _tick_left := 0.0


func open(castle_economy: Economy) -> void:
	economy = castle_economy
	groups = []
	loading = true
	offline = false
	status = ""
	pending_offer = 0
	first = 0
	visible = true
	_pressed = Target.NONE
	queue_redraw()


func close() -> void:
	visible = false
	closed.emit()


## Katalog z serwera (`shop_loaded`); `ok` = false: brak połączenia.
func set_groups(loaded: Array[ShopNet.Group], ok: bool) -> void:
	loading = false
	offline = not ok
	groups = loaded
	first = clampi(first, 0, max_first(groups.size(), _view().y))
	queue_redraw()


## Brak sieci przy otwarciu albo odbiorze.
func show_offline() -> void:
	loading = false
	offline = true
	pending_offer = 0
	queue_redraw()


## Serwer przyjął odbiór: karta odlicza odnowienie od `now_ms`.
func claim_done(claim: Dictionary, now_ms: int) -> void:
	pending_offer = 0
	var o := find_offer(groups, int(claim.get("offer_id", 0)))
	if o != null:
		var wait := int(claim.get("wait_ms", 0))
		o.ready_at_ms = now_ms + wait if wait > 0 else 0
	status = "Odebrano: +%d %s" % [int(claim.get("amount", 0)), EconomyConfig.SHORT_NAMES[clampi(int(claim.get("resource", 0)), 0, 3)]]
	queue_redraw()


## Serwer odrzucił odbiór (kod z `shop_claim`).
func claim_failed(error: String) -> void:
	pending_offer = 0
	if error == SupabaseClient.NETWORK_ERROR:
		offline = true
	status = ShopNet.error_text(error)
	queue_redraw()


static func find_offer(list: Array[ShopNet.Group], offer_id: int) -> ShopNet.Offer:
	for g in list:
		for o in g.offers:
			if o.id == offer_id:
				return o
	return null


## Stan karty: czeka na serwer, odnawia się, nie zmieści się w magazynie (według telefonu) albo do odbioru.
static func card_state(o: ShopNet.Offer, now_ms: int, amounts: Array[int], caps: Array[int], pending: int) -> int:
	if pending != 0 and o.id == pending:
		return CardState.BUSY
	if o.ready_at_ms > now_ms:
		return CardState.COOLDOWN
	if EconomyConfig.is_capped(o.resource) and o.resource < amounts.size() and o.resource < caps.size() \
			and amounts[o.resource] + o.amount > caps[o.resource]:
		return CardState.FULL
	return CardState.READY


## Napis przycisku karty w danym stanie.
static func button_label(state: int, o: ShopNet.Offer, now_ms: int) -> String:
	match state:
		CardState.COOLDOWN:
			return ShopNet.countdown(o.ready_at_ms - now_ms)
		CardState.FULL:
			return ShopNet.STORAGE_FULL
		CardState.BUSY:
			return "..."
	return CLAIM_LABEL


# --- Układ --------------------------------------------------------------------------------------

static func list_bottom(view: Vector2) -> float:
	return close_rect(view).position.y - 2


static func close_rect(view: Vector2) -> Rect2:
	var bottom := Hud.backdrop_rect(view).end.y
	return Rect2(Vector2(floorf((view.x - CLOSE_SIZE.x) / 2.0), bottom - CLOSE_SIZE.y - 2), CLOSE_SIZE)


## Ile grup mieści się w liście naraz (co najmniej 1).
static func visible_groups(view_h: float) -> int:
	var v := Vector2(320, view_h)
	return maxi(1, int((list_bottom(v) - LIST_TOP) / GROUP_H))


## Najdalsza pierwsza grupa przy `count` grupach.
static func max_first(count: int, view_h: float) -> int:
	return maxi(0, count - visible_groups(view_h))


static func cards_left(view: Vector2) -> float:
	return floorf((view.x - (ShopNet.MAX_OFFERS * CARD_W + (ShopNet.MAX_OFFERS - 1) * CARD_GAP)) / 2.0)


## Karta `slot_index` (0..2) w `row`-tej widocznej grupie.
static func card_rect(view: Vector2, row: int, slot_index: int) -> Rect2:
	return Rect2(Vector2(cards_left(view) + slot_index * (CARD_W + CARD_GAP), LIST_TOP + row * GROUP_H + HEADER_H),
			Vector2(CARD_W, CARD_H))


static func button_rect(card: Rect2) -> Rect2:
	return Rect2(card.position + Vector2(3, CARD_H - BUTTON_H - 1), Vector2(card.size.x - 6, BUTTON_H))


## Cel dotyku: przycisk karty (CARD + id oferty) albo Zamknij.
func target_at(p: Vector2, view: Vector2) -> int:
	if close_rect(view).has_point(p):
		return Target.CLOSE
	if loading or offline:
		return Target.NONE
	var shown := visible_groups(view.y)
	for row in shown:
		var gi := first + row
		if gi >= groups.size():
			break
		var g := groups[gi]
		for i in g.offers.size():
			if button_rect(card_rect(view, row, i)).has_point(p):
				return Target.CARD + g.offers[i].id
	return Target.NONE


func activate(t: int) -> void:
	if t == Target.CLOSE:
		close()
		return
	if t < Target.CARD or pending_offer != 0:
		return
	var o := find_offer(groups, t - Target.CARD)
	if o == null:
		return
	var now := _now_ms()
	var st := card_state(o, now, _amounts(), _caps(), pending_offer)
	if st == CardState.FULL:
		status = ShopNet.STORAGE_FULL
		queue_redraw()
		return
	if st != CardState.READY:
		return
	pending_offer = o.id
	status = ""
	queue_redraw()
	claim_requested.emit(o.id)


## Przewinięcie o `steps` grup (dodatnie: w dół listy).
func scroll(steps: int) -> void:
	first = clampi(first + steps, 0, max_first(groups.size(), _view().y))
	queue_redraw()


# --- Dotyk -------------------------------------------------------------------------------------

func _input(event: InputEvent) -> void:
	if not visible:
		return
	var drag := event as InputEventScreenDrag
	if drag != null:
		get_viewport().set_input_as_handled()
		_drag += drag.relative.y
		while absf(_drag) >= DRAG_STEP:
			# palec w górę (ujemny ruch) pokazuje dalsze grupy
			scroll(1 if _drag < 0.0 else -1)
			_drag += DRAG_STEP if _drag < 0.0 else -DRAG_STEP
			_dragged = true
			_pressed = Target.NONE
		return
	var touch := event as InputEventScreenTouch
	if touch == null:
		return
	get_viewport().set_input_as_handled()
	var t := target_at(touch.position, _view())
	if touch.pressed:
		_pressed = t
		_drag = 0.0
		_dragged = false
		queue_redraw()
		return
	var was := _pressed
	_pressed = Target.NONE
	queue_redraw()
	if not _dragged and was != Target.NONE and t == was:
		activate(was)


func _process(delta: float) -> void:
	if not visible:
		return
	# odliczanie zmienia się co minutę; odświeżenie co sekundę wystarcza
	_tick_left -= delta
	if _tick_left <= 0.0:
		_tick_left = 1.0
		queue_redraw()


# --- Rysowanie ---------------------------------------------------------------------------------

func _draw() -> void:
	var view := _view()
	draw_rect(Hud.backdrop_rect(view), Color(Palette.SHADOW, 0.85))
	PixelFont.draw_centered(self, Rect2(0, 5, view.x, 10), TITLE.to_upper(), Palette.THATCH[2])
	draw_rect(Rect2(floorf(view.x / 2.0) - 20, 15, 40, 1), Palette.WOOD[2])
	var list := Rect2(0, LIST_TOP, view.x, list_bottom(view) - LIST_TOP)
	if offline:
		PixelFont.draw_centered(self, list, ShopNet.NO_CONNECTION, Palette.ACCENT)
	elif loading:
		PixelFont.draw_centered(self, list, LOADING, Palette.INK)
	elif groups.is_empty():
		PixelFont.draw_centered(self, list, EMPTY, Palette.INK)
	else:
		_draw_groups(view)
	if not status.is_empty() and not offline:
		var col := Palette.VALID if status.begins_with("Odebrano") else Palette.ACCENT
		PixelFont.draw_right(self, close_rect(view).position.x - 4, close_rect(view).position.y + 3,
				PixelFont._fit(status, int(close_rect(view).position.x) - 8), col)
	Hud.paint_button(self, close_rect(view), CLOSE_LABEL, _pressed == Target.CLOSE, false)


func _draw_groups(view: Vector2) -> void:
	var now := _now_ms()
	var amounts := _amounts()
	var caps := _caps()
	var left := cards_left(view)
	var shown := visible_groups(view.y)
	for row in shown:
		var gi := first + row
		if gi >= groups.size():
			break
		var g := groups[gi]
		var top := LIST_TOP + row * GROUP_H
		PixelFont.draw_text(self, Vector2(left, top + 1), PixelFont._fit(g.name, CARD_W * 2), Palette.THATCH[2])
		for i in g.offers.size():
			_draw_card(card_rect(view, row, i), g.offers[i], card_state(g.offers[i], now, amounts, caps, pending_offer), now)
	# strzałki przewijania, gdy są grupy poza widokiem
	if first > 0:
		_arrow(Vector2(view.x - left - 5, 8), true)
	if first < max_first(groups.size(), view.y):
		_arrow(Vector2(view.x - left - 5, close_rect(view).position.y + 4), false)


## Trójkąt 5×3 px w górę albo w dół (więcej grup nad albo pod listą).
func _arrow(at: Vector2, up: bool) -> void:
	for i in 3:
		var y := at.y + (2 - i if up else i)
		draw_rect(Rect2(at.x + i, y, 5 - 2 * i, 1), Palette.INK)


func _draw_card(r: Rect2, o: ShopNet.Offer, state: int, now_ms: int) -> void:
	draw_rect(r, Color(Palette.WOOD[0], 0.9))
	draw_rect(Rect2(r.position, Vector2(r.size.x, 1)), Palette.WOOD[2])
	PixelFont.draw_text(self, r.position + Vector2(3, 1), PixelFont._fit(o.name, int(r.size.x) - 6), Palette.INK)
	PixelIcons.draw_resource(self, r.position + Vector2(3, 10 + PixelFont.CAP_TOP), o.resource)
	PixelFont.draw_text(self, r.position + Vector2(3 + PixelIcons.SIZE + 2, 10), "+%d" % o.amount, Palette.THATCH[2])
	var button := button_rect(r)
	Hud.paint_button(self, button, button_label(state, o, now_ms), _pressed == Target.CARD + o.id,
			state != CardState.READY)


func _view() -> Vector2:
	return get_viewport_rect().size if is_inside_tree() else Vector2(320, 180)


func _amounts() -> Array[int]:
	return economy.amounts if economy != null else [] as Array[int]


func _caps() -> Array[int]:
	return economy.capacities if economy != null else [] as Array[int]


static func _now_ms() -> int:
	return int(Time.get_unix_time_from_system() * 1000.0)
