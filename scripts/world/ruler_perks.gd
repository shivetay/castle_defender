class_name RulerPerks
extends RefCounted
## Perki władcy z technologii (#308, ADR 0002, notatka Władca i generałowie). Perka nie wybiera się
## z listy: odblokowuje go badanie. Perki tworzą 4 linie z poziomami, po jednej technologii na poziom
## (LINES), w gałęzi kategorii perka. Poziom 1 jest w epoce I, poziom 2 w epoce II i wymaga poziomu 1.
## Pierwsza zbadana (albo badana) technologia perkowa wybiera linię na stałe: technologie pozostałych
## linii są zablokowane we wszystkich epokach (Research.Result.RULER_PERK_LOCKED).
##
## Działa najwyższy poziom wybranej linii, nie wyższy niż epoka zamku. Stan perka (Perk) to linia
## z poziomem: CONQUEROR i LOOTER to poziomy 1 i 2 linii Zdobywcy (poziom 2 dokłada Łupieżcę),
## THRIFTY i BUILDER linii Gospodarnego (poziom 2 dokłada Budowniczego), STEWARD i STEWARD_2 linii
## Gospodarza grodu, BELOVED i BELOVED_2 linii Ukochanego władcy. Numery stanów zna serwer
## (migracja `*_ruler_perk_research.sql`): liczy perk z badań w zapisie zamku tak samo jak from_done.
## Zamek z technologiami z dwóch linii (np. z edycji zapisu) nie ma żadnego perka.
##
## Gdzie działają: Zdobywca i Łupieżca u atakującego (Battle.set_ruler_perk, łup z PvP liczy też
## `end_attack`), Gospodarz grodu i Ukochany władca u obrońcy (Battle.create_squads z
## BuildGrid.ruler_perk), Gospodarny w produkcji (Economy.rates), Budowniczy w czasie budowy (BuildQueue).
## Perk wrodzony władcy (Rulers.innate_perk) to osobna pula, która dojdzie z nowymi władcami.

enum Perk { NONE = -1, CONQUEROR, LOOTER, STEWARD, THRIFTY, BUILDER, BELOVED, STEWARD_2, BELOVED_2 }

## Nazwa i efekt stanu perka (indeks = Perk).
const NAMES: Array[String] = ["Zdobywca", "Łupieżca", "Gospodarz grodu", "Gospodarny", "Budowniczy",
		"Ukochany władca", "Gospodarz grodu II", "Ukochany władca II"]
const DESC: Array[String] = ["+10% obrażeń w ataku", "+10% obrażeń, +15% łupu z PvP", "Budynki +10% wytrz.",
		"+10% produkcji", "+10% produkcji, budowa -10% czasu", "+10 morale załogi", "Budynki +15% wytrz.",
		"+15 morale załogi"]

## Linie perków: technologie kolejnych poziomów (indeks = poziom - 1) i stany perka tych poziomów.
const LINES: Array = [["A60", "A61"], ["O23", "O24"], ["G25", "G26"], ["U14", "U15"]]
const LINE_PERKS: Array = [[Perk.CONQUEROR, Perk.LOOTER], [Perk.STEWARD, Perk.STEWARD_2],
		[Perk.THRIFTY, Perk.BUILDER], [Perk.BELOVED, Perk.BELOVED_2]]
const LINE_NAMES: Array[String] = ["Zdobywca", "Gospodarz grodu", "Gospodarny", "Ukochany władca"]

## Miejsca na perk z technologii w MVP (kolejne od epoki III i V dojdą później).
const SLOTS := 1

# --- Liczby do bitwy i gospodarki (poziom 2 TYMCZASOWY, ADR 0002) -------------------------------------
const CONQUEROR_DAMAGE_PERCENT := 110
const LOOTER_LOOT_PERCENT := 115
const STEWARD_HP_PERCENT := 110
const STEWARD_2_HP_PERCENT := 115
const THRIFTY_PRODUCTION_BONUS := 10
const BUILDER_TIME_PERCENT := 90
const BELOVED_MORALE := 10
const BELOVED_2_MORALE := 15


static func count() -> int:
	return NAMES.size()


static func is_known(p: int) -> bool:
	return p >= 0 and p < count()


static func perk_name(p: int) -> String:
	return NAMES[p] if is_known(p) else "brak"


## Linia technologii perkowej `code` albo -1, gdy to nie technologia perka.
static func line_of(code: String) -> int:
	for line in LINES.size():
		if (LINES[line] as Array).has(code):
			return line
	return -1


## Wszystkie technologie perkowe.
static func tech_codes() -> Array[String]:
	var out: Array[String] = []
	for line: Array in LINES:
		for code: String in line:
			out.append(code)
	return out


## Linia wybrana przez zbadane technologie `done` i badanie w toku `active`: -1, gdy żadna, a -2, gdy
## więcej niż jedna (zapis spoza gry).
static func chosen_line(done: Dictionary, active: String = "") -> int:
	var found := -1
	for line in LINES.size():
		var used := (LINES[line] as Array).has(active)
		for code: String in LINES[line]:
			used = used or done.has(code)
		if not used:
			continue
		if found != -1:
			return -2
		found = line
	return found


## Czy technologię `code` blokuje już wybrana inna linia (badania `done` i w toku `active`).
static func is_locked(code: String, done: Dictionary, active: String = "") -> bool:
	var line := line_of(code)
	if line < 0:
		return false
	var chosen := chosen_line(done, active)
	return chosen != -1 and chosen != line


## Stan perka ze zbadanych technologii `done` w zamku z epoki `age`: najwyższy poziom jednej linii, do
## którego zbadano wszystkie niższe, nie wyższy niż epoka. Tak samo czyta kopię zamku z serwera.
static func from_done(done: Dictionary, age: int) -> int:
	var line := chosen_line(done)
	if line < 0:
		return Perk.NONE
	var perk: int = Perk.NONE
	var codes: Array = LINES[line]
	for level in codes.size():
		var code: String = codes[level]
		if not done.has(code) or TechTree.age(code) > age:
			break
		perk = int(LINE_PERKS[line][level])
	return perk


static func from_research(research: Research, age: int) -> int:
	return from_done(research.done, age) if research != null else Perk.NONE


## Linia stanu perka `p` albo -1.
static func line_of_perk(p: int) -> int:
	for line in LINE_PERKS.size():
		if (LINE_PERKS[line] as Array).has(p):
			return line
	return -1


# --- Efekty ------------------------------------------------------------------------------------------

## Zdobywca (oba poziomy linii): +10% obrażeń w ataku.
static func has_conqueror(p: int) -> bool:
	return p == Perk.CONQUEROR or p == Perk.LOOTER


## Wytrzymałość budynków obrońcy w procentach (Gospodarz grodu).
static func steward_hp_percent(p: int) -> int:
	if p == Perk.STEWARD:
		return STEWARD_HP_PERCENT
	if p == Perk.STEWARD_2:
		return STEWARD_2_HP_PERCENT
	return 100


## Morale załogi obrońcy na start (Ukochany władca).
static func beloved_morale(p: int) -> int:
	if p == Perk.BELOVED:
		return BELOVED_MORALE
	if p == Perk.BELOVED_2:
		return BELOVED_2_MORALE
	return 0


## Premia do produkcji każdego surowca w punktach procentowych (Economy.rates): Gospodarny na obu poziomach.
static func production_bonus(p: int) -> int:
	return THRIFTY_PRODUCTION_BONUS if p == Perk.THRIFTY or p == Perk.BUILDER else 0


## Czas budowy w procentach (BuildQueue): Budowniczy skraca go o 10%, w dół do pełnych ms.
static func build_time_ms(duration_ms: int, p: int) -> int:
	if p != Perk.BUILDER:
		return duration_ms
	@warning_ignore("integer_division")
	return duration_ms * BUILDER_TIME_PERCENT / 100


## Łup z PvP z Łupieżcą (+15%, w dół), liczony tak samo jak limit w `end_attack`.
static func pvp_loot(amount: int, p: int) -> int:
	if p != Perk.LOOTER:
		return amount
	@warning_ignore("integer_division")
	return amount * LOOTER_LOOT_PERCENT / 100
