class_name TrapConfig
extends RefCounted
## Pułapki (#100, lista zatwierdzona przez właściciela 17.11.2026, notatka Budynki/Obrona): każda wymaga
## technologii i (poza Kolczatką) budynku, stoi w strefie obrony na wolnej kratce, którą da się przejść,
## jest ukryta przed atakującym (odsłania ją dopiero zwiad, #28) i działa raz na bitwę; po bitwie odnawia
## się za darmo. Limit: LIMIT_PER_MANOR_LEVEL pułapek na poziom Dworu. Liczby są TYMCZASOWE.

enum Kind { PIT, CALTROPS, LOGS, FIRE_ARROWS, PITCH }
## Gdzie stoi pułapka: na trawie, tuż przed wałem albo palisadą (od zewnątrz), przy murze albo wieży,
## tuż przed bramą (od zewnątrz).
enum Place { GRASS, BEFORE_WALL, NEAR_WALL, BEFORE_GATE }

const NAMES: Array[String] = ["Wilczy dół", "Kolczatka", "Zrzucane kłody", "Płonące strzały", "Wrząca smoła"]
## Napisy na kafelkach paska pułapek (do ok. 30 px).
const SHORT_NAMES: Array[String] = ["Dół", "Kolce", "Kłody", "Ogień", "Smoła"]
## Znak na mapie (ekran Obrona).
const GLYPHS: Array[String] = ["D", "K", "Ł", "P", "S"]
const AGE: Array[int] = [0, 0, 0, 0, 1]
const TECH: Array[String] = ["G18", "O2", "G1", "A42", "G24"]
## Budynki, które muszą stać (gotowe) na zamku.
const BUILDINGS: Array = [
	[BuildingTypes.Kind.HUNTER],
	[],
	[BuildingTypes.Kind.LUMBER_HUT],
	[BuildingTypes.Kind.FLETCHER, BuildingTypes.Kind.TAR_KILN],
	[BuildingTypes.Kind.TAR_KILN],
]
const PLACE: Array[int] = [Place.GRASS, Place.GRASS, Place.BEFORE_WALL, Place.NEAR_WALL, Place.BEFORE_GATE]
## Koszt postawienia w surowcach (drewno, kamień, żywność, złoto) i w towarach ze zbrojowni.
const COST: Array = [[30, 0, 10, 0], [20, 20, 0, 0], [50, 0, 0, 0], [20, 0, 0, 0], [40, 0, 0, 0]]
const GOODS_COST: Array = [{}, {}, {}, {GoodsConfig.Good.PITCH: 1, GoodsConfig.Good.ARROW: 5},
		{GoodsConfig.Good.PITCH: 1}]
const LIMIT_PER_MANOR_LEVEL := 2

## Wilczy dół: obrażenia i ile sekund ofiara stoi (Taran dłużej).
const PIT_DAMAGE := 60
const PIT_STUN_S := 3
const PIT_RAM_STUN_S := 5
## Kolczatka: przez tyle sekund rani co sekundę na kratce i obok niej, konnica idzie tam 2× wolniej.
const CALTROPS_S := 8
const CALTROPS_DAMAGE_PER_S := 5
const CALTROPS_SLOW_PERCENT := 50
## Zrzucane kłody: obrażenia każdego na 3 kratkach wzdłuż muru.
const LOGS_DAMAGE := 40
## Płonące strzały: rusza, gdy wróg podejdzie na tyle kratek do kosza z żarem; przez tyle sekund
## strzelcy obrońcy i wieże w promieniu FIRE_ARROWS_RADIUS od kosza zadają więcej i podpalają
## Taran i Podpalacza.
const FIRE_ARROWS_TRIGGER := 4
const FIRE_ARROWS_RADIUS := 2
const FIRE_ARROWS_S := 15
const FIRE_ARROWS_PERCENT := 130
## Wrząca smoła: rusza, gdy wróg stanie pod bramą; obrażenia w promieniu 1 kratki i podpalenie.
const PITCH_DAMAGE := 50
## Podpalona jednostka (Płonące strzały, Wrząca smoła) traci tyle HP na sekundę przez tyle sekund.
const UNIT_FIRE_S := 6
const UNIT_FIRE_DAMAGE_PER_S := 4


static func count() -> int:
	return NAMES.size()


static func limit(manor_level: int) -> int:
	# poziomy epoki II dokładają miejsca jak epoka I (Ages.bonus_level, #262): do 20
	return LIMIT_PER_MANOR_LEVEL * maxi(1, Ages.bonus_level(manor_level))


## Pusty napis, gdy pułapkę `kind` można postawić (epoka, technologia, budynki); inaczej powód.
static func requirement_problem(kind: int, grid: BuildGrid, research: Research, age: int) -> String:
	if AGE[kind] > age:
		return "%s: %s" % [NAMES[kind], TechTree.age_label(AGE[kind])]
	var tech := TECH[kind]
	if research == null or not research.is_done(tech):
		return "%s: zbadaj %s %s" % [NAMES[kind], tech, TechTree.tech_name(tech)]
	for b: int in BUILDINGS[kind]:
		if not grid.has_built(b):
			return "%s: postaw %s" % [NAMES[kind], BuildingTypes.NAMES[b]]
	return ""


## Koszt jako tekst, np. „20 Dr, 1 Smoła, 5 Strzały”.
static func cost_text(kind: int) -> String:
	var cost: Array[int] = []
	cost.assign(COST[kind])
	var parts: PackedStringArray = [Hud.cost_text(cost)]
	var goods: Dictionary = GOODS_COST[kind]
	for good: int in goods:
		parts.append("%d %s" % [int(goods[good]), GoodsConfig.NAMES[good]])
	return ", ".join(parts)
