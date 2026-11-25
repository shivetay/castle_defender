class_name ResearchConfig
extends RefCounted
## Koszty i czasy badań w jednym miejscu. Koszt to tablica ilości surowców w kolejności
## EconomyConfig.Res (drewno, kamień, żywność, złoto). Zmiana balansu badań to zmiana tylko tego pliku.
##
## Koszt technologii jest stały w epoce (BASE_COST). Drożeją tylko doktryny (TechTree.DOCTRINES,
## technologie z samą procentową premią): ×1,6 za każdą wcześniej rozpoczętą doktrynę tej samej epoki
## (decyzja właścicielki). Czas badań nadal rośnie ×2 z każdą technologią epoki, jak w notatce
## Drzewko technologiczne. Bazowe liczby są tymczasowe (balans).

## Koszt pierwszej technologii w epoce (indeks = epoka, 0 = I). TYMCZASOWE.
const BASE_COST: Array = [
	[100, 50, 50, 0],
	[400, 300, 200, 0],
]
## Czas pierwszej technologii w epoce w sekundach. TYMCZASOWE.
const BASE_TIME_S: Array[int] = [60, 30 * 60]
## Wzrost kosztu doktryny na każdą wcześniej rozpoczętą doktrynę tej samej epoki, w procentach (×1,6).
const COST_STEP_PERCENT := 160
## Wzrost czasu na każdą wcześniej rozpoczętą technologię tej samej epoki (×2).
const TIME_STEP := 2
## Jedno badanie naraz (drugie miejsce da U10 Kwatermistrzostwo w epoce V).
const RESEARCHERS := 1

## Budynek badań gałęzi (#165, notatka Drzewko technologiczne): [od epoki, budynek] w kolejności epok,
## indeks = TechTree.Branch. Technologię bada budynek ostatniego wpisu, który obejmuje jej epokę;
## budynek główny to Dwór. Z notatki: Atak — budynek główny, od epoki I Koszary, od V Arsenał;
## Obrona — budynek główny; Gospodarka — budynek główny, od III Targ; Użyteczne — budynek główny,
## od II Kaplica, od IV Szpital; Specjalne — Wieża sygnałowa, od II Dom zwiadowców (Chata tropicieli), od VI Sztab.
## Arsenału, Targu, Kaplicy, Szpitala i Sztabu jeszcze nie ma w grze, więc ich wpisy dojdą razem
## z nimi; do tego czasu bada je poprzedni budynek z listy albo Dwór. Wieża sygnałowa (#35) bada
## Specjalne od epoki I. Budynek nie bada technologii, która go odblokowuje (research_building pomija
## taki budynek): S2 bada Dwór. Chata tropicieli (#28) stoi od S1, więc S3 bada ona sama i po nim
## staje się Domem zwiadowców.
const BRANCH_BUILDINGS: Array = [
	[[0, BuildingTypes.Kind.BARRACKS]],
	[[0, BuildingTypes.Kind.MANOR]],
	[[0, BuildingTypes.Kind.MANOR]],
	[[0, BuildingTypes.Kind.MANOR]],
	[[0, BuildingTypes.Kind.SIGNAL_TOWER], [1, BuildingTypes.Kind.SCOUT_HOUSE]],
]


## Koszt technologii epoki `tech_age`. Dla doktryny `step` to liczba doktryn tej epoki rozpoczętych
## wcześniej; zwykła technologia ma zawsze `step` = 0 (Research.cost_of).
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


## Budynek, w którym bada się technologię `code`: ostatni budynek jej gałęzi dostępny w jej epoce,
## z pominięciem budynku, który ta technologia dopiero odblokowuje; bez takiego Dwór.
static func research_building(code: String) -> int:
	var list: Array = BRANCH_BUILDINGS[TechTree.branch(code)]
	for i in range(list.size() - 1, -1, -1):
		var e: Array = list[i]
		var kind := int(e[1])
		if int(e[0]) <= TechTree.age(code) and BuildConfig.required_tech(kind) != code:
			return kind
	return BuildingTypes.Kind.MANOR
