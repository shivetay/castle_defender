class_name BuildingTypes
extends RefCounted
## Budynki epoki I: rozmiar w kratkach, nazwa w UI i reguły łączenia umocnień.
## Wał i palisada to odcinki 1×1, które same łączą się z sąsiadami (autotiling N/E/S/W).

enum Kind { RAMPART, PALISADE, GATE, TOWER, LUMBER_HUT }
## Stan budynku: cały, uszkodzony, zniszczony (bitwa dojdzie w kolejnych etapach).
enum State { INTACT, DAMAGED, RUINED }

const MAX_LEVEL := 5
## Bity maski sąsiadów dla autotilingu.
const N := 1
const E := 2
const S := 4
const W := 8

const NAMES: Array[String] = ["Wał ziemny", "Palisada", "Brama drewniana", "Wieża drewniana", "Chata drwala"]
const SHORT_NAMES: Array[String] = ["Wał", "Palisada", "Brama", "Wieża", "Chata"]
const SIZES: Array[Vector2i] = [Vector2i(1, 1), Vector2i(1, 1), Vector2i(2, 1), Vector2i(2, 2), Vector2i(2, 2)]


static func count() -> int:
	return NAMES.size()


static func size_of(kind: int) -> Vector2i:
	return SIZES[kind]


static func is_wall(kind: int) -> bool:
	return kind == Kind.RAMPART or kind == Kind.PALISADE


## Czy odcinek umocnienia `wall` łączy się z sąsiednim budynkiem `other`. Wał łączy się
## tylko z wałem. Palisada łączy się z palisadą, bramą i wieżą, żeby brama mogła stać w linii.
static func connects(wall: int, other: int) -> bool:
	if wall == Kind.RAMPART:
		return other == Kind.RAMPART
	if wall == Kind.PALISADE:
		return other == Kind.PALISADE or other == Kind.GATE or other == Kind.TOWER
	return false
