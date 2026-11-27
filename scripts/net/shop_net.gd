class_name ShopNet
extends RefCounted
## Sklep w Targu (#408, ADR 0014): kontrakt katalogu (`public.shop_catalog`, REST RPC) i odbioru (Edge Function
## `shop_claim`). Oferty układa właścicielka w panelu admina, więc treść z serwera jest niezaufana: nazwy przechodzą
## przez znaki fontu, liczby są przycinane do granic z migracji, a grupa ma najwyżej MAX_OFFERS ofert.
## Czas odnowienia liczy serwer: odliczanie bierze różnicę `next_available_at - server_now` z tej samej odpowiedzi,
## więc zegar telefonu nic nie zmienia. Nagrodę dopisuje serwer do zamku (`castle_loot_pending` → `loot_applied`).

const CATALOG_PATH := "/rest/v1/rpc/shop_catalog"
const CLAIM_PATH := "/functions/v1/shop_claim"
## Granice z migracji `*_shop.sql`: MAX_OFFERS = 3 na grupę, nazwa do 24 znaków, złoto do 100, inne do 2000.
const MAX_OFFERS := 3
const NAME_MAX := 24
const GOLD_MAX := 100
const RES_MAX := 2000
## Najwięcej grup w panelu (zapas na wypadek błędu panelu admina, a nie reguła sklepu).
const MAX_GROUPS := 20
## Odnowienie najdłużej 30 dni (COOLDOWN_MAX = 43200 minut).
const MAX_WAIT_MS := 43200 * 60 * 1000

## Komunikaty błędów odbioru (kod z `shop_claim` → tekst w sklepie).
const NO_CONNECTION := "Brak połączenia"
const STORAGE_FULL := "Magazyn pełny"
const ERROR_TEXT := {
	"storage_full": STORAGE_FULL,
	"cooldown": "Oferta się odnawia",
	"offer_unavailable": "Oferta już niedostępna",
	"no_castle": "Zamek jeszcze nie na serwerze",
	"update_required": "Zaktualizuj grę",
	"network": NO_CONNECTION,
}


class Offer:
	extends RefCounted
	var id := 0
	var slot := 1
	var name := ""
	## EconomyConfig.Res
	var resource := 0
	var amount := 0
	## Chwila (ms na zegarze `now_ms` z parse_catalog), od której oferta znowu jest do odbioru; 0: teraz.
	var ready_at_ms := 0


class Group:
	extends RefCounted
	var id := 0
	var name := ""
	var offers: Array[Offer] = []


static func claim_request(offer_id: int) -> Dictionary:
	return {"offer_id": offer_id}


## Grupy z odpowiedzi `shop_catalog` w kolejności serwera (sort_order, id grupy, slot). `now_ms` to bieżący czas
## telefonu: odliczanie dostaje go jako punkt startu. Zły wiersz jest pomijany.
static func parse_catalog(rows: Variant, now_ms: int) -> Array[Group]:
	var out: Array[Group] = []
	if not rows is Array:
		return out
	var by_id: Dictionary[int, Group] = {}
	for raw: Variant in rows as Array:
		if not raw is Dictionary:
			continue
		var r := raw as Dictionary
		var gid := _int(r.get("group_id"), -1)
		var offer := offer_from(r, now_ms)
		if gid <= 0 or offer == null:
			continue
		if not by_id.has(gid):
			if out.size() >= MAX_GROUPS:
				continue
			var g := Group.new()
			g.id = gid
			g.name = safe_text(str(r.get("group_name", "")))
			if g.name.is_empty():
				g.name = "Oferty"
			by_id[gid] = g
			out.append(g)
		var group := by_id[gid]
		if group.offers.size() < MAX_OFFERS:
			group.offers.append(offer)
	return out


## Oferta z wiersza katalogu albo null (złe id, surowiec albo ilość).
static func offer_from(r: Dictionary, now_ms: int) -> Offer:
	var id := _int(r.get("offer_id"), -1)
	var res := _int(r.get("resource"), -1)
	var amount := _int(r.get("amount"), 0)
	if id <= 0 or res < 0 or res >= EconomyConfig.count() or amount <= 0:
		return null
	var o := Offer.new()
	o.id = id
	o.slot = clampi(_int(r.get("slot"), 1), 1, MAX_OFFERS)
	o.resource = res
	o.amount = mini(amount, GOLD_MAX if res == EconomyConfig.Res.GOLD else RES_MAX)
	o.name = safe_text(str(r.get("name", "")))
	if o.name.is_empty():
		o.name = EconomyConfig.NAMES[res]
	var wait := wait_ms(r.get("next_available_at"), r.get("server_now"))
	o.ready_at_ms = now_ms + wait if wait > 0 else 0
	return o


## Czas do końca odnowienia (ms) z dwóch czasów serwera; 0, gdy oferta jest do odbioru albo czasy są złe.
static func wait_ms(next_at: Variant, server_now: Variant) -> int:
	if not next_at is String or not server_now is String:
		return 0
	var a := iso_ms(next_at as String)
	var b := iso_ms(server_now as String)
	if a < 0 or b < 0:
		return 0
	return clampi(a - b, 0, MAX_WAIT_MS)


## Czas ISO 8601 z PostgREST (np. „2026-11-27T13:53:34.123456+00:00” albo z „Z”) w ms od epoki; -1, gdy zły.
static func iso_ms(text: String) -> int:
	if text.length() < 19 or text[10] != "T":
		return -1
	var base := text.substr(0, 19)
	for i in base.length():
		if i in [4, 7]:
			if base[i] != "-":
				return -1
		elif i == 10 or i in [13, 16]:
			continue
		elif not base[i].is_valid_int():
			return -1
	var s := Time.get_unix_time_from_datetime_string(base)
	var ms := s * 1000
	var rest := text.substr(19)
	if rest.begins_with("."):
		var digits := ""
		var i := 1
		while i < rest.length() and rest[i].is_valid_int():
			digits += rest[i]
			i += 1
		ms += int((digits + "000").substr(0, 3))
		rest = rest.substr(i)
	if rest.length() >= 6 and (rest[0] == "+" or rest[0] == "-"):
		var off := (rest.substr(1, 2).to_int() * 60 + rest.substr(4, 2).to_int()) * 60 * 1000
		ms -= off if rest[0] == "+" else -off
	return ms


## Odpowiedź `shop_claim`: {offer_id, resource, amount, wait_ms} albo pusty słownik, gdy zła.
static func parse_claim(data: Variant) -> Dictionary:
	if not data is Dictionary:
		return {}
	var d := data as Dictionary
	var id := _int(d.get("offer_id"), -1)
	var res := _int(d.get("resource"), -1)
	var amount := _int(d.get("amount"), 0)
	if id <= 0 or res < 0 or res >= EconomyConfig.count() or amount <= 0:
		return {}
	return {"offer_id": id, "resource": res, "amount": mini(amount, GOLD_MAX if res == EconomyConfig.Res.GOLD else RES_MAX),
			"wait_ms": wait_ms(d.get("next_available_at"), d.get("claimed_at"))}


## Tekst błędu odbioru dla gracza.
static func error_text(code: String) -> String:
	return str(ERROR_TEXT.get(code, "Odbiór nieudany"))


## Odliczanie odnowienia: „2 h 15 min”, „2 h”, „15 min”, „3 d 4 h”; pełne minuty w górę (59 s to „1 min”).
static func countdown(ms: int) -> String:
	if ms <= 0:
		return ""
	@warning_ignore("integer_division")
	var minutes := (ms + 59999) / 60000
	@warning_ignore("integer_division")
	var hours := minutes / 60
	minutes %= 60
	if hours >= 24:
		@warning_ignore("integer_division")
		var days := hours / 24
		hours %= 24
		return "%d d" % days if hours == 0 else "%d d %d h" % [days, hours]
	if hours == 0:
		return "%d min" % minutes
	return "%d h" % hours if minutes == 0 else "%d h %d min" % [hours, minutes]


## Nazwa z panelu admina tylko ze znaków fontu (bez znaku ikony), najwyżej NAME_MAX znaków.
static func safe_text(text: String) -> String:
	var out := ""
	for ch in PlayerProfile.clean_name(text):
		var up := ch.to_upper()
		if ch == PixelFont.ICON_MARK or not (ch == " " or PixelFont.GLYPHS.has(up) or PixelFont.ACCENTED.has(up)):
			continue
		out += ch
	return out.substr(0, NAME_MAX).strip_edges()


static func _int(v: Variant, fallback: int) -> int:
	if v is int:
		return v as int
	if v is float and is_finite(v as float):
		return int(v as float)
	return fallback
