class_name BuildingTypes
extends RefCounted
## Budynki epoki I: rozmiar w kratkach, nazwa w UI i reguły łączenia umocnień.
## Wał i palisada to odcinki 1×1, które same łączą się z sąsiadami (autotiling N/E/S/W).
## Dwór to siedziba władcy: jeden na zamek, stoi od startu, a jego poziom jest poziomem zamku.
## Nie ma go na pasku budowy (BUILD_BAR). Wytwórcy (#90) dochodzą za Dworem, żeby numery rodzajów
## w starszych zapisach się nie zmieniły.

enum Kind {
	RAMPART, PALISADE, GATE, TOWER, LUMBER_HUT, MANOR,
	HUNTER, TANNERY, LEATHERWORKER, POLEARM, BOWSTRING, BOWYER, FLETCHER, SADDLER, TAR_KILN,
	FLAX_FIELD, FISHER, STABLE,
	BARRACKS, WARBAND_HOUSE, ARCHERY_RANGE,
	KEEP,
	SCOUT_HOUSE,
	WATCHTOWER,
}
## Stan budynku zależny od wytrzymałości: cały, pęknięcia, wyrwa w blankach, gruz.
enum State { INTACT, CRACKED, BREACHED, RUBBLE }

const MAX_LEVEL := 5
## Najniższy procent wytrzymałości, przy którym budynek jest jeszcze w danym stanie
## (cały, pęknięcia, wyrwa). Przy 0% zostaje gruz.
const STATE_MIN_HP_PERCENT: Array[int] = [76, 41, 1]
## Bity maski sąsiadów dla autotilingu.
const N := 1
const E := 2
const S := 4
const W := 8

const NAMES: Array[String] = ["Wał ziemny", "Palisada", "Brama drewniana", "Wieża drewniana", "Chata drwala", "Dwór",
		"Chata myśliwego", "Garbarnia", "Wytwórca zbroi skórzanych", "Drzewcarz", "Cięciwiarz", "Łukmistrz",
		"Strzałmistrz", "Rymarz", "Smolarnia", "Pole lnu", "Rybak", "Stajnia", "Koszary", "Dom drużyny", "Strzelnica",
		"Wieża grodowa", "Dom zwiadowców", "Strażnica"]
## Napisy na kafelkach panelu budowy (BuildPanel, ok. 57–71 px).
const SHORT_NAMES: Array[String] = ["Wał", "Palisada", "Brama", "Wieża", "Chata", "Dwór",
		"Myśliwy", "Garbarnia", "Zbrojarz", "Drzewcarz", "Cięciwy", "Łukmistrz", "Strzały", "Rymarz", "Smolarnia",
		"Len", "Rybak", "Stajnia", "Koszary", "Drużyna", "Strzelnica", "Donżon",
		"Zwiadowcy", "Strażnica"]
const SIZES: Array[Vector2i] = [Vector2i(1, 1), Vector2i(1, 1), Vector2i(3, 1), Vector2i(2, 2), Vector2i(2, 2),
		Vector2i(2, 2), Vector2i(2, 2), Vector2i(2, 2), Vector2i(2, 2), Vector2i(2, 2), Vector2i(2, 2),
		Vector2i(2, 2), Vector2i(2, 2), Vector2i(2, 2), Vector2i(2, 2), Vector2i(2, 2), Vector2i(2, 2), Vector2i(2, 2),
		Vector2i(2, 2), Vector2i(2, 2), Vector2i(2, 2), Vector2i(2, 2), Vector2i(2, 2), Vector2i(2, 2)]
## Rodzaje na pasku budowy, w kolejności przycisków (bez Dworu): umocnienia, gospodarka (#122),
## wytwórcy w kolejności łańcucha, na końcu budynki rekrutacji (#119) i Dom zwiadowców (#92).
const BUILD_BAR: Array[int] = [Kind.RAMPART, Kind.PALISADE, Kind.GATE, Kind.TOWER, Kind.LUMBER_HUT,
		Kind.FISHER, Kind.FLAX_FIELD, Kind.HUNTER, Kind.TANNERY, Kind.LEATHERWORKER, Kind.POLEARM, Kind.BOWSTRING, Kind.BOWYER,
		Kind.FLETCHER, Kind.SADDLER, Kind.STABLE, Kind.TAR_KILN, Kind.BARRACKS, Kind.WARBAND_HOUSE,
		Kind.ARCHERY_RANGE, Kind.SCOUT_HOUSE]


## Kategorie w panelu budowy (po teście na telefonie): zakładki zamiast jednego długiego paska.
enum Category { DEFENSE, ECONOMY, PRODUCERS, MILITARY }
const CATEGORY_NAMES: Array[String] = ["Umocnienia", "Gospodarka", "Wytwórcy", "Wojsko"]
## Rodzaje w kategoriach, w kolejności kafelków (ta sama kolejność co BUILD_BAR).
const CATEGORIES: Array = [
	[Kind.RAMPART, Kind.PALISADE, Kind.GATE, Kind.TOWER],
	[Kind.LUMBER_HUT, Kind.FISHER, Kind.FLAX_FIELD],
	[Kind.HUNTER, Kind.TANNERY, Kind.LEATHERWORKER, Kind.POLEARM, Kind.BOWSTRING, Kind.BOWYER, Kind.FLETCHER,
			Kind.SADDLER, Kind.TAR_KILN],
	[Kind.BARRACKS, Kind.WARBAND_HOUSE, Kind.ARCHERY_RANGE, Kind.STABLE, Kind.SCOUT_HOUSE],
]


static func in_category(cat: int) -> Array[int]:
	var out: Array[int] = []
	out.assign(CATEGORIES[cat] as Array)
	return out


## Kategoria rodzaju albo -1 (Dwór nie stoi w panelu).
static func category(kind: int) -> int:
	for i in CATEGORIES.size():
		if (CATEGORIES[i] as Array).has(kind):
			return i
	return -1


static func count() -> int:
	return NAMES.size()


## Czy budynek jest z drewna (epoka I: wszystko poza wałem ziemnym i polem). Topór i ogień
## działają mocniej na drewno (#15).
static func is_wooden(kind: int) -> bool:
	return kind != Kind.RAMPART and kind != Kind.FLAX_FIELD


## Budynki, które zamek ma od startu, po jednym, i których nie da się rozebrać: Dwór, donżon (#120)
## i Strażnica (PvE, #177).
static func is_unique(kind: int) -> bool:
	return kind == Kind.MANOR or kind == Kind.KEEP or kind == Kind.WATCHTOWER


## Liczba rodzajów, które gracz stawia z panelu budowy (bez Dworu i donżonu).
static func buildable_count() -> int:
	return BUILD_BAR.size()


## Rodzaj budynku na miejscu `index` listy BUILD_BAR (kolejność rodzajów w panelu budowy).
static func bar_kind(index: int) -> int:
	return BUILD_BAR[clampi(index, 0, BUILD_BAR.size() - 1)]


static func size_of(kind: int) -> Vector2i:
	return SIZES[kind]


static func is_wall(kind: int) -> bool:
	return kind == Kind.RAMPART or kind == Kind.PALISADE


## Czy odcinek umocnienia `wall` łączy się z sąsiednim budynkiem `other`. Wał i palisada łączą się
## ze sobą nawzajem (mieszana linia nie ma szpar) oraz z bramą i wieżą, żeby stały w linii.
static func connects(wall: int, other: int) -> bool:
	if not is_wall(wall):
		return false
	return is_wall(other) or other == Kind.GATE or other == Kind.TOWER


## Stan budynku dla wytrzymałości `hp` z `max_hp`. Procent liczy się w liczbach całkowitych
## i zaokrągla w górę, więc budynek z choćby 1 punktem nigdy nie jest gruzem.
static func state_for_hp(hp: int, max_hp: int) -> int:
	if max_hp <= 0 or hp <= 0:
		return State.RUBBLE
	@warning_ignore("integer_division")
	var percent := (100 * mini(hp, max_hp) + max_hp - 1) / max_hp
	for state in STATE_MIN_HP_PERCENT.size():
		if percent >= STATE_MIN_HP_PERCENT[state]:
			return state
	return State.RUBBLE
