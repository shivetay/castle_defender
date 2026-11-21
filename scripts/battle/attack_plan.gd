class_name AttackPlan
extends RefCounted
## Plan ataku (#18, notatka Manewry i zadania): bitwą nikt nie steruje, więc każdy oddział
## atakującego dostaje przed bitwą rozkaz, czyli manewr z parametrami, i wykonuje go sam:
## - cel: kratka budynku (budynek, odcinek muru albo brama); (-1, -1) to cel bitwy (donżon) albo
##   cel dobierany przez manewr (Podpalenie, Drabiny, Taran);
## - trasa: 0–3 punkty pośrednie, przez które oddział idzie, zanim zacznie manewr;
## - start: od razu, po X sekundach albo gdy inny oddział wykona swoje zadanie (np. po wyłomie);
## - odwrót: oddział wycofuje się, gdy straci co najmniej tyle procent ludzi (0: nigdy).
##
## Plan to same liczby całkowite, więc ten sam plan daje ten sam przebieg (powtórka, weryfikacja PvP
## na serwerze). Oddział bez rozkazu walczy jak dotąd, czyli jak Szturm frontalny na donżon.
##
## Tabor (#235): jedyny manewr Wozu. Wóz nie walczy, jedzie trasą z planu i staje na jej ostatnim
## punkcie. Trasę trzeba zaplanować (bez punktu trasy plan jest niepoprawny), a start ma zawsze
## co najmniej WAGON_DELAY_S sekund opóźnienia, żeby wozy nie wjeżdżały przed wojskiem.

enum Manoeuvre { FRONTAL, RANGED, FIRE, FLANK, LADDERS, RAM_GATE, CONVOY }
enum Start { NOW, AFTER_SECONDS, AFTER_SQUAD }

const MANOEUVRE_NAMES: Array[String] = ["Szturm frontalny", "Ostrzał z dystansu", "Podpalenie", "Oskrzydlenie",
		"Szturm z drabinami", "Taranowanie bramy", "Tabor"]
## Od której epoki manewr jest dostępny (0 = I), z notatki.
const MANOEUVRE_AGE: Array[int] = [0, 0, 0, 0, 1, 1, 0]
## Technologia, która odblokowuje manewr (#12, notatka Drzewko technologiczne); pusty napis: bez badań.
const MANOEUVRE_TECH: Array[String] = ["", "", "A3", "A4", "A5", "A6", ""]
## Krótki opis manewru na liście wyboru (ekran planu).
const MANOEUVRE_DESC: Array[String] = ["Idzie na cel i burzy, co stoi na drodze",
		"Punkt ostrzału; marsz tylko bez wroga w zasięgu",
		"Podpala drewniane budynki", "Obchodzi obronę bokiem", "Wchodzi na mur po drabinach",
		"Taran bije bramę, piechota go osłania", "Wóz jedzie trasą i czeka na łup"]
## Komunikat, gdy jednostka oddziału nie umie wykonać manewru (po teście na telefonie Chłopi mieli
## Ostrzał z dystansu).
const UNIT_HINTS: Array[String] = ["nie Wóz", "tylko strzelcy", "tylko Podpalacze", "nie Taran ani Wóz",
		"tylko piechota", "Taran lub piechota", "tylko Wóz"]
## Wóz rusza najwcześniej po tylu sekundach bitwy, także przy starcie „od razu” (decyzja właścicielki,
## TYMCZASOWE). Dłuższe opóźnienie albo czekanie na oddział ustawia się w planie jak zwykle.
const WAGON_DELAY_S := 20
const MAX_WAYPOINTS := 3
## Ile oddziałów mieści plan w epokach I–VI (Otwarte pytania, decyzja właściciela: 3 w epoce I,
## do 8 w epoce VI). Technologia U12 i generałowie dodadzą po +1 później.
const MAX_SQUADS_BY_AGE: Array[int] = [3, 4, 5, 6, 7, 8]
const NO_TARGET := Vector2i(-1, -1)
## Zakresy planu z serwera (#29), te same co w `private.check_plan` (migracja *_attack_replay.sql):
## START_VALUE_MAX = 600, RETREAT_MAX = 100, CELL_MAX = 63.
const START_VALUE_MAX := 600
const RETREAT_MAX := 100
const CELL_MAX := 63
## Klucze rozkazu w to_server(); innych serwer nie przyjmie.
const ORDER_KEYS: Array[String] = ["squad", "manoeuvre", "target", "waypoints", "start", "start_value", "retreat",
		"flank_left"]


class Order:
	extends RefCounted
	## Oddział atakującego (od 1, w kolejności armii jak w Battle.create_squads).
	var squad := 1
	var manoeuvre := 0
	var target := Vector2i(-1, -1)
	var waypoints: Array[Vector2i] = []
	var start := 0
	## Sekundy (AFTER_SECONDS) albo numer oddziału (AFTER_SQUAD).
	var start_value := 0
	## Procent strat, przy którym oddział się wycofuje; 0: walczy do końca.
	var retreat_percent := 0
	## Oskrzydlenie: obejście z lewej (inaczej z prawej) patrząc od miejsca startu na cel.
	var flank_left := true


var orders: Array[Order] = []


static func max_squads(age: int) -> int:
	return MAX_SQUADS_BY_AGE[clampi(age, 0, MAX_SQUADS_BY_AGE.size() - 1)]


## Dodaje (albo zastępuje) rozkaz oddziału `squad` i go zwraca, żeby ustawić resztę parametrów.
func add(squad: int, manoeuvre: int, target: Vector2i = NO_TARGET) -> Order:
	var o := order_for(squad)
	if o == null:
		o = Order.new()
		o.squad = squad
		orders.append(o)
	o.manoeuvre = manoeuvre
	o.target = target
	return o


func order_for(squad: int) -> Order:
	for o in orders:
		if o.squad == squad:
			return o
	return null


## Czy jednostka `unit` umie wykonać manewr `m`: Ostrzał tylko z zasięgiem co najmniej
## BattleConfig.RANGED_MIN_RANGE, Podpalenie tylko Podpalacz (tylko on rozpala ogień), Drabiny piechota
## lekka i ciężka, Taranowanie Taran i piechota w osłonie, Oskrzydlenie każdy poza Taranem.
## Wóz umie tylko Tabor i tylko on go umie.
static func unit_can(m: int, unit: int) -> bool:
	if unit == UnitTypes.Unit.WAGON or m == Manoeuvre.CONVOY:
		return unit == UnitTypes.Unit.WAGON and m == Manoeuvre.CONVOY
	var cls := UnitTypes.unit_class(unit)
	var infantry := cls == RecruitmentConfig.UnitClass.LIGHT or cls == RecruitmentConfig.UnitClass.HEAVY
	match m:
		Manoeuvre.RANGED:
			return UnitTypes.attack_range(unit) >= BattleConfig.RANGED_MIN_RANGE
		Manoeuvre.FIRE:
			return unit == UnitTypes.Unit.FIRE_RAISER
		Manoeuvre.FLANK:
			return unit != UnitTypes.Unit.RAM
		Manoeuvre.LADDERS:
			return infantry
		Manoeuvre.RAM_GATE:
			return infantry or unit == UnitTypes.Unit.RAM
	return true


## Manewr nowego rozkazu dla jednostki `unit`: Tabor dla Wozu, inaczej Szturm frontalny.
static func default_manoeuvre(unit: int) -> int:
	return Manoeuvre.CONVOY if unit == UnitTypes.Unit.WAGON else Manoeuvre.FRONTAL


## Czego brakuje, żeby oddział z jednostkami `unit` wykonał manewr `m` w epoce `age` przy badaniach
## `research` (bez badań technologii nie sprawdza), a pusty napis, gdy manewr jest dostępny. Jednostka,
## która manewru nie umie, daje sam ten powód (np. „tylko piechota”), bo epoka ani badanie nic nie
## zmienią; inaczej epoka i badanie po przecinku, np. „epoka II, A5 Drabiny oblężnicze”. Jednostka -1:
## bez sprawdzania jednostki.
static func missing(m: int, unit: int, age: int, research: Research = null) -> String:
	if m == Manoeuvre.CONVOY and unit != UnitTypes.Unit.WAGON:
		return UNIT_HINTS[m]  # Tabor tylko dla Wozu, także bez znanej jednostki
	if unit >= 0 and not unit_can(m, unit):
		return UNIT_HINTS[m]  # epoka ani badanie tego nie zmienią
	var parts: PackedStringArray = []
	if MANOEUVRE_AGE[m] > age:
		parts.append("epoka %s" % ["I", "II", "III", "IV", "V", "VI"][clampi(MANOEUVRE_AGE[m], 0, 5)])
	if research != null and not manoeuvre_unlocked(m, research):
		parts.append("%s %s" % [MANOEUVRE_TECH[m], TechTree.tech_name(MANOEUVRE_TECH[m])])
	return ", ".join(parts)


## Pusty napis, gdy plan jest poprawny dla armii z `squad_count` oddziałów w epoce `age`;
## inaczej powód po polsku (dla ekranu planu, #17).
## Z `research` (badania atakującego) sprawdza też technologie manewrów (#12); bez badań je pomija.
## Z `units` (rodzaj jednostek każdego oddziału, od oddziału 1) sprawdza też, czy oddział umie
## wykonać swój manewr.
func problem(squad_count: int, age: int, research: Research = null, units: Array[int] = []) -> String:
	if squad_count > max_squads(age):
		return "Za dużo oddziałów: najwyżej %d" % max_squads(age)
	for o in orders:
		if o.squad < 1 or o.squad > squad_count:
			return "Rozkaz dla nieistniejącego oddziału"
		if o.manoeuvre < 0 or o.manoeuvre >= MANOEUVRE_NAMES.size():
			return "Nieznany manewr"
		if MANOEUVRE_AGE[o.manoeuvre] > age:
			return "%s: wymaga późniejszej epoki" % MANOEUVRE_NAMES[o.manoeuvre]
		if research != null and not manoeuvre_unlocked(o.manoeuvre, research):
			return tech_hint(o.manoeuvre)
		if o.squad <= units.size() and not unit_can(o.manoeuvre, units[o.squad - 1]):
			return "Oddział %d, %s: %s" % [o.squad, MANOEUVRE_NAMES[o.manoeuvre], UNIT_HINTS[o.manoeuvre]]
		if o.manoeuvre == Manoeuvre.CONVOY and o.waypoints.is_empty():
			return "Oddział %d: wyznacz trasę Wozu" % o.squad
		if o.waypoints.size() > MAX_WAYPOINTS:
			return "Najwyżej %d punkty trasy" % MAX_WAYPOINTS
		if o.retreat_percent < 0 or o.retreat_percent > 100:
			return "Odwrót: od 0 do 100% strat"
		if o.start == Start.AFTER_SECONDS and o.start_value < 0:
			return "Start: czas nie może być ujemny"
		if o.start == Start.AFTER_SQUAD:
			if o.start_value < 1 or o.start_value > squad_count or o.start_value == o.squad:
				return "Start: wskaż inny oddział"
			if _waits_in_cycle(o.squad):
				return "Start: oddziały czekają na siebie nawzajem"
	for i in units.size():
		if units[i] == UnitTypes.Unit.WAGON and order_for(i + 1) == null:
			return "Oddział %d: wyznacz trasę Wozu" % (i + 1)
	return ""


## Czy łańcuch „czeka na oddział” zaczęty od `squad` wraca do niego.
func _waits_in_cycle(squad: int) -> bool:
	var seen := {}
	var cur := squad
	while true:
		var o := order_for(cur)
		if o == null or o.start != Start.AFTER_SQUAD:
			return false
		cur = o.start_value
		if cur == squad:
			return true
		if seen.has(cur):
			return false
		seen[cur] = true
	return false


## Czy manewr `m` jest odblokowany badaniami `research` (manewr bez technologii zawsze).
static func manoeuvre_unlocked(m: int, research: Research) -> bool:
	var tech := MANOEUVRE_TECH[m]
	return tech.is_empty() or (research != null and research.is_done(tech))


## Komunikat o brakującej technologii manewru, np. „Oskrzydlenie: zbadaj A4 Taktyka oskrzydlenia”.
static func tech_hint(m: int) -> String:
	var tech := MANOEUVRE_TECH[m]
	return "%s: zbadaj %s %s" % [MANOEUVRE_NAMES[m], tech, TechTree.tech_name(tech)]


func to_dict() -> Dictionary:
	var list: Array = []
	for o in orders:
		var wps: Array = []
		for w in o.waypoints:
			wps.append([w.x, w.y])
		list.append({"squad": o.squad, "manoeuvre": o.manoeuvre, "target": [o.target.x, o.target.y],
				"waypoints": wps, "start": o.start, "start_value": o.start_value,
				"retreat": o.retreat_percent, "flank_left": o.flank_left})
	return {"orders": list}


## Rozkazy planu do serwera (#29, `launch_attack`): tablica z to_dict()["orders"].
func to_server() -> Array:
	return to_dict()["orders"] as Array


## Plan z serwera (#29): rozkazy zapisane przy zatwierdzeniu, które przyszły z klienta atakującego, więc
## sprawdzone jak w `private.check_plan`: tablica 1..`squads` rozkazów, oddziały 1..`squads` bez powtórek,
## liczby całkowite w zakresach gry, bez obcych kluczy. Null, gdy coś się nie zgadza (bez wyjątków
## i bez częściowego planu: powtórka z innego planu wyglądałaby inaczej niż bitwa atakującego).
static func from_server(raw: Variant, squads: int) -> AttackPlan:
	if not raw is Array or (raw as Array).is_empty() or (raw as Array).size() > squads:
		return null
	var p := AttackPlan.new()
	for e: Variant in raw as Array:
		if not e is Dictionary:
			return null
		var d := e as Dictionary
		for k: Variant in d.keys():
			if not ORDER_KEYS.has(str(k)):
				return null
		var squad := _int_in(d.get("squad"), 1, squads)
		var m := _int_in(d.get("manoeuvre"), 0, MANOEUVRE_NAMES.size() - 1)
		var start_kind := _int_in(d.get("start"), 0, Start.size() - 1)
		var start_value := _int_in(d.get("start_value"), 0, START_VALUE_MAX)
		var retreat := _int_in(d.get("retreat"), 0, RETREAT_MAX)
		var target := _cell(d.get("target"), true)
		var flank: Variant = d.get("flank_left")
		var wps: Variant = d.get("waypoints")
		if squad < 0 or m < 0 or start_kind < 0 or start_value < 0 or retreat < 0 or target.x < -1 \
				or not flank is bool or not wps is Array or (wps as Array).size() > MAX_WAYPOINTS \
				or p.order_for(squad) != null:
			return null
		var o := p.add(squad, m, target)
		for w: Variant in wps as Array:
			var c := _cell(w, false)
			if c.x < 0:
				return null
			o.waypoints.append(c)
		o.start = start_kind
		o.start_value = start_value
		o.retreat_percent = retreat
		o.flank_left = flank as bool
	return p


## Liczba całkowita z JSON (int albo float bez części ułamkowej) w [lo, hi] (lo ≥ 0), inaczej -1.
static func _int_in(v: Variant, lo: int, hi: int) -> int:
	if not _is_int(v):
		return -1
	var n := int(v)
	return n if n >= lo and n <= hi else -1


static func _is_int(v: Variant) -> bool:
	return v is int or (v is float and float(v) == floorf(float(v)))


## Kratka [x, y] na mapie; z `allow_none` także NO_TARGET (obie współrzędne -1). Zła kratka: (-2, -2).
static func _cell(v: Variant, allow_none: bool) -> Vector2i:
	var bad := Vector2i(-2, -2)
	if not v is Array or (v as Array).size() != 2:
		return bad
	var a := v as Array
	if not _is_int(a[0]) or not _is_int(a[1]):
		return bad
	var c := Vector2i(int(a[0]), int(a[1]))
	if allow_none and c == NO_TARGET:
		return c
	if c.x < 0 or c.y < 0 or c.x > CELL_MAX or c.y > CELL_MAX:
		return bad
	return c


## Plan z danych zapisu (JSON daje liczby jako float, więc wszystko idzie przez int()).
static func from_dict(d: Dictionary) -> AttackPlan:
	var p := AttackPlan.new()
	for e: Variant in d.get("orders", []) as Array:
		if not e is Dictionary:
			continue
		var od := e as Dictionary
		var t: Array = od.get("target", [-1, -1])
		var o := p.add(int(od.get("squad", 1)), int(od.get("manoeuvre", 0)), Vector2i(int(t[0]), int(t[1])))
		for w: Variant in od.get("waypoints", []) as Array:
			var wa := w as Array
			o.waypoints.append(Vector2i(int(wa[0]), int(wa[1])))
		o.start = int(od.get("start", 0))
		o.start_value = int(od.get("start_value", 0))
		o.retreat_percent = int(od.get("retreat", 0))
		o.flank_left = bool(od.get("flank_left", true))
	return p
