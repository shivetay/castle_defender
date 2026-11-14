class_name ResearchConfig
extends RefCounted
## Koszty i czasy badań w jednym miejscu. Koszt to tablica ilości surowców w kolejności
## EconomyConfig.Res (drewno, kamień, żywność, złoto). Zmiana balansu badań to zmiana tylko tego pliku.
##
## Według #12 każda kolejna technologia w epoce kosztuje ok. 1,6× więcej i trwa 2× dłużej.
## UWAGA: bazowe koszty i czasy poniżej są tymczasowe, do zastąpienia liczbami z notatki
## Drzewko technologiczne. Przy 30 technologiach epoki I wzrost ×1,6 / ×2 na każdą kolejną
## szybko przekracza pojemność magazynu, więc mnożniki też czekają na decyzję właściciela.

## Koszt pierwszej technologii w epoce (indeks = epoka, 0 = I). TYMCZASOWE.
const BASE_COST: Array = [
	[100, 50, 50, 0],
	[400, 300, 200, 0],
]
## Czas pierwszej technologii w epoce w sekundach. TYMCZASOWE.
const BASE_TIME_S: Array[int] = [60, 30 * 60]
## Wzrost kosztu na każdą wcześniej rozpoczętą technologię tej samej epoki, w procentach (×1,6).
const COST_STEP_PERCENT := 160
## Wzrost czasu na każdą wcześniej rozpoczętą technologię tej samej epoki (×2).
const TIME_STEP := 2
## Jedno badanie naraz.
const RESEARCHERS := 1


## Koszt technologii epoki `tech_age`, gdy w tej epoce rozpoczęto już `step` technologii.
static func cost(tech_age: int, step: int) -> Array[int]:
	var out: Array[int] = []
	out.assign(BASE_COST[clampi(tech_age, 0, BASE_COST.size() - 1)])
	for i in maxi(0, step):
		for res in out.size():
			@warning_ignore("integer_division")
			out[res] = out[res] * COST_STEP_PERCENT / 100
	return out


## Czas technologii epoki `tech_age` w milisekundach, gdy rozpoczęto już `step` technologii tej epoki.
static func time_ms(tech_age: int, step: int) -> int:
	var t := BASE_TIME_S[clampi(tech_age, 0, BASE_TIME_S.size() - 1)] * 1000
	for i in maxi(0, step):
		t *= TIME_STEP
	return t
