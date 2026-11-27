class_name BuildConfig
extends RefCounted
## Koszty, czasy i wymagania budowy w jednym miejscu. Poziom 1 to postawienie budynku.
## Koszt to tablica ilości surowców w kolejności EconomyConfig.Res (drewno, kamień, żywność, złoto).
## Zmiana balansu budowy to zmiana tylko tego pliku.

const K := BuildingTypes.Kind
## Koszt poziomu 1 dla rodzajów z paska budowy. Wytwórcy (#90): koszt i czas tymczasowe,
## w skali Chaty drwala (notatka zostawia liczby balansowi).
const BASE_COST := {
	K.RAMPART: [10, 0, 10, 0],
	K.PALISADE: [20, 0, 5, 0],
	K.GATE: [60, 20, 20, 0],
	K.TOWER: [120, 40, 40, 0],
	K.LUMBER_HUT: [80, 0, 30, 0],
	K.HUNTER: [60, 0, 20, 0],
	K.TANNERY: [80, 20, 20, 0],
	K.LEATHERWORKER: [100, 20, 30, 0],
	K.POLEARM: [80, 20, 20, 0],
	K.BOWSTRING: [60, 0, 20, 0],
	K.BOWYER: [100, 0, 30, 0],
	K.FLETCHER: [80, 10, 20, 0],
	K.SADDLER: [90, 0, 30, 0],
	K.TAR_KILN: [60, 40, 10, 0],
	K.FLAX_FIELD: [30, 0, 20, 0],
	K.FISHER: [70, 0, 10, 0],
	K.STABLE: [100, 20, 40, 0],
	K.BARRACKS: [100, 20, 40, 0],
	K.WARBAND_HOUSE: [140, 30, 40, 0],
	K.ARCHERY_RANGE: [120, 10, 40, 0],
	K.KEEP: [150, 60, 40, 0],
	K.SCOUT_HOUSE: [120, 20, 40, 10],
	K.SEAL_HOUSE: [100, 40, 30, 0],
	## Magazyn: koszt tymczasowy, w skali Chaty drwala, bez żywności (sam nic nie produkuje).
	K.WAREHOUSE: [100, 40, 0, 0],
	## Pozostałe budynki MVP (#35): koszty tymczasowe, w skali Chaty drwala. Fosa to odcinek 1×1 jak wał.
	K.DRY_MOAT: [5, 0, 15, 0],
	K.MOUND: [60, 40, 40, 0],
	K.FARM: [60, 0, 20, 0],
	K.WELL: [40, 30, 10, 0],
	K.QUARRY: [100, 0, 30, 0],
	K.SIGNAL_TOWER: [100, 20, 30, 0],
}
## Czas poziomu 1 w sekundach.
const BASE_TIME_S := {
	K.RAMPART: 5, K.PALISADE: 10, K.GATE: 30, K.TOWER: 60, K.LUMBER_HUT: 45,
	K.HUNTER: 40, K.TANNERY: 50, K.LEATHERWORKER: 60, K.POLEARM: 50, K.BOWSTRING: 40, K.BOWYER: 60,
	K.FLETCHER: 50, K.SADDLER: 60, K.TAR_KILN: 45, K.FLAX_FIELD: 30, K.FISHER: 40,
	K.STABLE: 60, K.BARRACKS: 60, K.WARBAND_HOUSE: 75, K.ARCHERY_RANGE: 70,
	K.KEEP: 90, K.SCOUT_HOUSE: 70, K.SEAL_HOUSE: 60, K.WAREHOUSE: 45,
	K.DRY_MOAT: 5, K.MOUND: 60, K.FARM: 40, K.WELL: 30, K.QUARRY: 50, K.SIGNAL_TOWER: 50,
}
## Technologia, bez której budynku nie da się postawić (Drzewko technologiczne). Ulepszenia
## już postawionego budynku jej nie sprawdzają. Stajnia (#91) i Koszary (#119) nie mają technologii
## w drzewku, więc stoją od początku epoki I. Fosa sucha, Pole i spichlerz oraz Studnia (#35) też.
const REQUIRED_TECH := {
	K.HUNTER: "G18", K.TANNERY: "G19", K.LEATHERWORKER: "A38", K.POLEARM: "A39", K.BOWSTRING: "A40",
	K.BOWYER: "A41", K.FLETCHER: "A42", K.SADDLER: "A43", K.TAR_KILN: "G24",
	K.FLAX_FIELD: "G20", K.FISHER: "G21", K.WARBAND_HOUSE: "A45", K.ARCHERY_RANGE: "A44",
	K.SCOUT_HOUSE: "S1", K.SEAL_HOUSE: "O2",
	K.MOUND: "O1", K.QUARRY: "G4", K.SIGNAL_TOWER: "S2",
}
## Koszt poziomu w procentach kosztu poziomu 1, jedna ciągła krzywa przez wszystkie poziomy narastająco
## (#262, ADR 0009): epoka I ×1 … ×6, epoka II dalej ×8,5 … ×25, więc na przejściu I.5 → II.1 nic nie
## tanieje. Poziomy 6–10 TYMCZASOWE (decyzja właścicielki #262).
const COST_PERCENT: Array[int] = [100, 150, 250, 400, 600, 850, 1150, 1500, 1950, 2500]
## Mnożnik czasu poziomu względem poziomu 1, ta sama ciągła krzywa (Wieża 5 = 60 s × 90 = 90 min,
## Wieża II.5 = 60 s × 420 = 7 h). Poziomy 6–10 TYMCZASOWE (decyzja właścicielki #262).
const TIME_MULT: Array[int] = [1, 3, 10, 30, 90, 130, 180, 240, 320, 420]
## Umocnienia (wał, palisada, fosa, brama) budują się w epoce II w połowie czasu z krzywej (TIME_MULT),
## (na poziomach 6–10). Epoka I bez zmian. TYMCZASOWE (decyzja właścicielki #262).
const FORT_KINDS: Array[int] = [K.RAMPART, K.PALISADE, K.DRY_MOAT, K.GATE]
const FORT_AGE_II_TIME_PERCENT := 50

## Dwór (poziom zamku): stoi od startu na poziomie 1, ulepszenia na poziomy 2–5, a dalej epoka II
## (#34): poziom 6 to przebudowa Dworu na epokę II, czyli przejście I → II, a 7–10 to poziomy 2–5
## epoki II. Każdy poziom kosztuje i trwa więcej niż poprzedni, a przebudowa mieści się w magazynie
## grodu bez Magazynu. Poziomy 6–10 TYMCZASOWE (decyzja właścicielki #262).
const MANOR_COST: Array = [
	[0, 0, 0, 0],
	[300, 200, 200, 0],
	[500, 350, 350, 0],
	[750, 550, 550, 0],
	[1000, 800, 800, 0],
	[1000, 1000, 1000, 0],
	[1300, 1100, 1100, 0],
	[1700, 1400, 1400, 0],
	[2200, 1800, 1800, 0],
	[2800, 2300, 2300, 0],
]
const MANOR_TIME_S: Array[int] = [0, 10 * 60, 3600, 4 * 3600, 12 * 3600,
		14 * 3600, 18 * 3600, 24 * 3600, 30 * 3600, 40 * 3600]

## Kolejka budowy: jeden budowniczy, a za nim do 3 czekających zleceń.
const BUILDERS := 1
const MAX_WAITING := 3


## Koszt doprowadzenia budynku `kind` do poziomu `level` (z poziomu niższego o 1). Poziom liczy się
## narastająco przez epoki (Ages): 6 to poziom 1 epoki II.
static func cost(kind: int, level: int) -> Array[int]:
	var lv := clampi(level, 1, Ages.MAX_TOTAL_LEVEL)
	var out: Array[int] = []
	if kind == BuildingTypes.Kind.MANOR:
		out.assign(MANOR_COST[lv - 1])
		return out
	var base: Array = BASE_COST.get(kind, [0, 0, 0, 0])
	for amount: int in base:
		@warning_ignore("integer_division")
		out.append(amount * COST_PERCENT[lv - 1] / 100)
	return out


## Czas budowy poziomu `level` (narastająco) w milisekundach.
static func time_ms(kind: int, level: int) -> int:
	var lv := clampi(level, 1, Ages.MAX_TOTAL_LEVEL)
	if kind == BuildingTypes.Kind.MANOR:
		return MANOR_TIME_S[lv - 1] * 1000
	var seconds := int(BASE_TIME_S.get(kind, 0)) * TIME_MULT[lv - 1]
	if FORT_KINDS.has(kind) and Ages.of_level(lv) > 0:
		@warning_ignore("integer_division")
		seconds = seconds * FORT_AGE_II_TIME_PERCENT / 100
	return seconds * 1000


## Najwyższy poziom budynku `kind` przy Dworze na poziomie `manor_level` (oba narastająco). Budynek
## nie może przerosnąć zamku, więc do epoki II wchodzi dopiero po przebudowie Dworu i ze swojego
## poziomu 5. Sam Dwór nie ma tego ograniczenia.
static func max_level(kind: int, manor_level: int) -> int:
	if kind == BuildingTypes.Kind.MANOR:
		return Ages.MAX_TOTAL_LEVEL
	if not BuildingTypes.has_levels(kind):
		return 1
	return clampi(manor_level, 1, Ages.MAX_TOTAL_LEVEL)


## Technologie wymagane do zbudowania poziomu `level` już stojącego budynku. Tylko przebudowa Dworu
## na nową epokę ich wymaga (technologie kluczowe przejścia, Ages.TRANSITION_TECHS).
static func level_techs(kind: int, level: int) -> Array[String]:
	if kind == BuildingTypes.Kind.MANOR and Ages.is_age_step(level):
		return Ages.transition_techs(Ages.of_level(level) - 1)
	var none: Array[String] = []
	return none


## Kod technologii wymaganej do postawienia budynku albo pusty napis.
static func required_tech(kind: int) -> String:
	return REQUIRED_TECH.get(kind, "")


## Czy przy stanie badań `research` wolno postawić budynek `kind` (bez badań: tylko budynki
## bez wymagań).
static func is_unlocked(kind: int, research: Research) -> bool:
	var tech := required_tech(kind)
	return tech.is_empty() or (research != null and research.is_done(tech))
