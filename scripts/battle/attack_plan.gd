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

enum Manoeuvre { FRONTAL, RANGED, FIRE, FLANK, LADDERS, RAM_GATE }
enum Start { NOW, AFTER_SECONDS, AFTER_SQUAD }

const MANOEUVRE_NAMES: Array[String] = ["Szturm frontalny", "Ostrzał z dystansu", "Podpalenie", "Oskrzydlenie",
		"Szturm z drabinami", "Taranowanie bramy"]
## Od której epoki manewr jest dostępny (0 = I), z notatki.
const MANOEUVRE_AGE: Array[int] = [0, 0, 0, 0, 1, 1]
## Technologia, która odblokowuje manewr (#12, notatka Drzewko technologiczne); pusty napis: bez badań.
const MANOEUVRE_TECH: Array[String] = ["", "", "A3", "A4", "A5", "A6"]
## Krótki opis manewru na liście wyboru (ekran planu).
const MANOEUVRE_DESC: Array[String] = ["Idzie na cel i burzy, co stoi na drodze", "Strzelcy biją cel z zasięgu",
		"Podpala drewniane budynki", "Obchodzi obronę bokiem", "Wchodzi na mur po drabinach",
		"Taran bije bramę, piechota go osłania"]
## Komunikat, gdy jednostka oddziału nie umie wykonać manewru (po teście na telefonie Chłopi mieli
## Ostrzał z dystansu).
const UNIT_HINTS: Array[String] = ["", "tylko strzelcy", "tylko Podpalacze", "nie Taran",
		"tylko piechota", "Taran lub piechota"]
const MAX_WAYPOINTS := 3
## Ile oddziałów mieści plan w epokach I–VI (Otwarte pytania, decyzja właściciela: 3 w epoce I,
## do 8 w epoce VI). Technologia U12 i generałowie dodadzą po +1 później.
const MAX_SQUADS_BY_AGE: Array[int] = [3, 4, 5, 6, 7, 8]
const NO_TARGET := Vector2i(-1, -1)


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
static func unit_can(m: int, unit: int) -> bool:
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


## Czego brakuje, żeby oddział z jednostkami `unit` wykonał manewr `m` w epoce `age` przy badaniach
## `research` (bez badań technologii nie sprawdza), a pusty napis, gdy manewr jest dostępny. Jednostka,
## która manewru nie umie, daje sam ten powód (np. „tylko piechota”), bo epoka ani badanie nic nie
## zmienią; inaczej epoka i badanie po przecinku, np. „epoka II, A5 Drabiny oblężnicze”. Jednostka -1:
## bez sprawdzania jednostki.
static func missing(m: int, unit: int, age: int, research: Research = null) -> String:
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
