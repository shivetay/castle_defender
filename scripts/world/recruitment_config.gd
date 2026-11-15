class_name RecruitmentConfig
extends RefCounted
## Budynki rekrutacji według klas (#119), według notatek Klasy jednostek i produkcja oraz Załoga
## i administracja. Każda klasa szkoli się we własnym budynku: Koszary (lekka), Dom drużyny (ciężka),
## Strzelnica (strzelecka), Stajnia (szybka). Jednostki specjalne mają własne budynki (Podpalacz
## w Smolarni, Tropiciel w Wieży sygnałowej, Zwiadowca w Domu zwiadowców), przypisane jednostce,
## a nie klasie; dojdą razem z jednostkami (#89, #15). Dwór nie rekrutuje.
##
## Poziom budynku podnosi limit szkolenia i tempo. Liczby są tymczasowe (notatka zostawia je
## balansowi) i czekają na rekrutację (#89).

enum UnitClass { LIGHT, HEAVY, RANGED, FAST, SPECIAL }

const CLASS_NAMES: Array[String] = ["lekka", "ciężka", "strzelecka", "szybka", "specjalna"]

## Klasa → budynek rekrutacji. Specjalna nie ma jednego budynku (patrz opis wyżej).
const CLASS_BUILDING := {
	UnitClass.LIGHT: BuildingTypes.Kind.BARRACKS,
	UnitClass.HEAVY: BuildingTypes.Kind.WARBAND_HOUSE,
	UnitClass.RANGED: BuildingTypes.Kind.ARCHERY_RANGE,
	UnitClass.FAST: BuildingTypes.Kind.STABLE,
}

## Ile jednostek mieści kolejka szkolenia budynku na poziomach 1–5. TYMCZASOWE.
const TRAINING_SLOTS: Array[int] = [2, 3, 4, 5, 6]
## Tempo szkolenia na poziomach 1–5 w procentach tempa poziomu 1. TYMCZASOWE.
const TRAINING_SPEED_PERCENT: Array[int] = [100, 120, 140, 170, 200]

## Czas szkolenia jednostki na poziomie 1 budynku, w sekundach (indeks = UnitTypes.Unit). TYMCZASOWE.
const TRAIN_TIME_S: Array[int] = [20, 20, 25, 40, 30, 30, 45, 25, 50, 35, 60, 90, 15]
## Limit armii (wyszkoleni i szkoleni): za każdy poziom Dworu i za każdy poziom Koszar (#89, #81).
## TYMCZASOWE.
const ARMY_PER_MANOR_LEVEL := 10
const ARMY_PER_BARRACKS_LEVEL := 2
## Najwięcej jednostek w jednym oddziale (oddział ma jeden rodzaj jednostek). TYMCZASOWE.
const SQUAD_SIZE := 10


## Budynek rekrutacji klasy albo -1 (klasa specjalna).
static func building_for(unit_class: int) -> int:
	return int(CLASS_BUILDING.get(unit_class, -1))


## Klasa, którą szkoli budynek `kind`, albo -1, gdy budynek nie rekrutuje (np. Dwór).
static func class_of(kind: int) -> int:
	for unit_class: int in CLASS_BUILDING:
		if int(CLASS_BUILDING[unit_class]) == kind:
			return unit_class
	return -1


static func training_slots(level: int) -> int:
	return TRAINING_SLOTS[clampi(level, 1, TRAINING_SLOTS.size()) - 1]


static func training_speed_percent(level: int) -> int:
	return TRAINING_SPEED_PERCENT[clampi(level, 1, TRAINING_SPEED_PERCENT.size()) - 1]


## Czas szkolenia jednostki `unit` w budynku na poziomie `level` (ms).
static func train_ms(unit: int, level: int) -> int:
	@warning_ignore("integer_division")
	return TRAIN_TIME_S[unit] * 1000 * 100 / training_speed_percent(level)
