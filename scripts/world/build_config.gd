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
}
## Czas poziomu 1 w sekundach.
const BASE_TIME_S := {
	K.RAMPART: 5, K.PALISADE: 10, K.GATE: 30, K.TOWER: 60, K.LUMBER_HUT: 45,
	K.HUNTER: 40, K.TANNERY: 50, K.LEATHERWORKER: 60, K.POLEARM: 50, K.BOWSTRING: 40, K.BOWYER: 60,
	K.FLETCHER: 50, K.SADDLER: 60, K.TAR_KILN: 45, K.FLAX_FIELD: 30, K.FISHER: 40,
}
## Technologia, bez której budynku nie da się postawić (Drzewko technologiczne). Ulepszenia
## już postawionego budynku jej nie sprawdzają.
const REQUIRED_TECH := {
	K.HUNTER: "G18", K.TANNERY: "G19", K.LEATHERWORKER: "A38", K.POLEARM: "A39", K.BOWSTRING: "A40",
	K.BOWYER: "A41", K.FLETCHER: "A42", K.SADDLER: "A43", K.TAR_KILN: "G24",
	K.FLAX_FIELD: "G20", K.FISHER: "G21",
}
## Mnożnik kosztu poziomów 1–5 w procentach (×1, ×1,5, ×2,5, ×4, ×6).
const COST_PERCENT: Array[int] = [100, 150, 250, 400, 600]
## Mnożnik czasu poziomów 1–5 (Wieża 5 = 60 s × 90 = 90 min).
const TIME_MULT: Array[int] = [1, 3, 10, 30, 90]

## Dwór (poziom zamku): stoi od startu na poziomie 1, ulepszenia na poziomy 2–5.
const MANOR_COST: Array = [
	[0, 0, 0, 0],
	[300, 200, 200, 0],
	[500, 350, 350, 0],
	[750, 550, 550, 0],
	[1000, 800, 800, 0],
]
const MANOR_TIME_S: Array[int] = [0, 10 * 60, 3600, 4 * 3600, 12 * 3600]

## Kolejka budowy: jeden budowniczy, a za nim do 3 czekających zleceń.
const BUILDERS := 1
const MAX_WAITING := 3


## Koszt doprowadzenia budynku `kind` do poziomu `level` (z poziomu niższego o 1).
static func cost(kind: int, level: int) -> Array[int]:
	var lv := clampi(level, 1, BuildingTypes.MAX_LEVEL)
	var out: Array[int] = []
	if kind == BuildingTypes.Kind.MANOR:
		out.assign(MANOR_COST[lv - 1])
		return out
	var base: Array = BASE_COST.get(kind, [0, 0, 0, 0])
	for amount: int in base:
		@warning_ignore("integer_division")
		out.append(amount * COST_PERCENT[lv - 1] / 100)
	return out


## Czas budowy poziomu `level` w milisekundach.
static func time_ms(kind: int, level: int) -> int:
	var lv := clampi(level, 1, BuildingTypes.MAX_LEVEL)
	if kind == BuildingTypes.Kind.MANOR:
		return MANOR_TIME_S[lv - 1] * 1000
	return int(BASE_TIME_S.get(kind, 0)) * TIME_MULT[lv - 1] * 1000


## Najwyższy poziom budynku `kind` przy Dworze na poziomie `manor_level`. Budynek nie może
## przerosnąć zamku; sam Dwór nie ma tego ograniczenia.
static func max_level(kind: int, manor_level: int) -> int:
	if kind == BuildingTypes.Kind.MANOR:
		return BuildingTypes.MAX_LEVEL
	return clampi(manor_level, 1, BuildingTypes.MAX_LEVEL)


## Kod technologii wymaganej do postawienia budynku albo pusty napis.
static func required_tech(kind: int) -> String:
	return REQUIRED_TECH.get(kind, "")


## Czy przy stanie badań `research` wolno postawić budynek `kind` (bez badań: tylko budynki
## bez wymagań).
static func is_unlocked(kind: int, research: Research) -> bool:
	var tech := required_tech(kind)
	return tech.is_empty() or (research != null and research.is_done(tech))
