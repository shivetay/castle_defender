class_name BuildingTypes
extends RefCounted
## Budynki epoki I: rozmiar w kratkach, nazwa w UI i reguły łączenia umocnień.
## Wał i palisada to odcinki 1×1, które same łączą się z sąsiadami (autotiling N/E/S/W).
## Dwór to siedziba władcy: jeden na zamek, stoi od startu, a jego poziom jest poziomem zamku.
## Nie ma go na pasku budowy, więc pasek pokazuje rodzaje 0..buildable_count()-1.

enum Kind { RAMPART, PALISADE, GATE, TOWER, LUMBER_HUT, MANOR }
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

const NAMES: Array[String] = ["Wał ziemny", "Palisada", "Brama drewniana", "Wieża drewniana", "Chata drwala", "Dwór"]
const SHORT_NAMES: Array[String] = ["Wał", "Palisada", "Brama", "Wieża", "Chata", "Dwór"]
const SIZES: Array[Vector2i] = [Vector2i(1, 1), Vector2i(1, 1), Vector2i(3, 1), Vector2i(2, 2), Vector2i(2, 2),
		Vector2i(2, 2)]


static func count() -> int:
	return NAMES.size()


## Rodzaje, które gracz stawia z paska budowy (bez Dworu).
static func buildable_count() -> int:
	return Kind.MANOR


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
