class_name BuildConfig
extends RefCounted
## Koszty, czasy i wymagania budowy w jednym miejscu. Poziom 1 to postawienie budynku.
## Koszt to tablica ilości surowców w kolejności EconomyConfig.Res (drewno, kamień, żywność, złoto).
## Zmiana balansu budowy to zmiana tylko tego pliku.

## Koszt poziomu 1 dla rodzajów z paska budowy (indeks = BuildingTypes.Kind).
const BASE_COST: Array = [
	[10, 0, 10, 0],    # wał ziemny
	[20, 0, 5, 0],     # palisada
	[60, 20, 20, 0],   # brama drewniana
	[120, 40, 40, 0],  # wieża drewniana
	[80, 0, 30, 0],    # chata drwala
]
## Czas poziomu 1 w sekundach.
const BASE_TIME_S: Array[int] = [5, 10, 30, 60, 45]
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
	var base: Array = BASE_COST[kind]
	for amount: int in base:
		@warning_ignore("integer_division")
		out.append(amount * COST_PERCENT[lv - 1] / 100)
	return out


## Czas budowy poziomu `level` w milisekundach.
static func time_ms(kind: int, level: int) -> int:
	var lv := clampi(level, 1, BuildingTypes.MAX_LEVEL)
	if kind == BuildingTypes.Kind.MANOR:
		return MANOR_TIME_S[lv - 1] * 1000
	return BASE_TIME_S[kind] * TIME_MULT[lv - 1] * 1000


## Najwyższy poziom budynku `kind` przy Dworze na poziomie `manor_level`. Budynek nie może
## przerosnąć zamku; sam Dwór nie ma tego ograniczenia. Wymagania technologii dojdą z badaniami (#12).
static func max_level(kind: int, manor_level: int) -> int:
	if kind == BuildingTypes.Kind.MANOR:
		return BuildingTypes.MAX_LEVEL
	return clampi(manor_level, 1, BuildingTypes.MAX_LEVEL)
