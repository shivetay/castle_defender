class_name TechTree
extends RefCounted
## Drzewko technologii MVP (#12): 34 technologie epok I–II w czterech gałęziach, z epoką,
## oznaczeniem technologii kluczowej (★, warunek przejścia do następnej epoki, #34)
## i zależnościami. Efekty technologii dojdą osobno (opis od właściciela).
##
## Epoki według #12, #91, #92 i #34. Epoka II: A22 Kopia rycerska (Kopijnik), A46 Przeszywanica
## (Drużynnik), A47 Łuk refleksyjny i G6 ★ Zaprawa wapienna (kluczowa dla przejścia II → III).
## Reszta to epoka I, w tym A7 Strzemię (Jeździec w epoce I, #91) i O1 ★ Sypanie kopców
## (kluczowa dla przejścia I → II, #34). Do potwierdzenia z notatką Drzewko technologiczne.

enum Branch { ATTACK, DEFENSE, ECONOMY, UTILITY }

const BRANCH_NAMES: Array[String] = ["Atak", "Obrona", "Gospodarka", "Użyteczne"]
## Numery epok na ekranie (indeks = epoka, 0 = epoka I).
const AGE_NUMERALS: Array[String] = ["I", "II"]

## Wiersz: [kod, nazwa, gałąź, epoka (0 = I), kluczowa ★, wymagane kody].
## Kolejność wierszy to kolejność kafelków na ekranie drzewka.
const TECHS: Array = [
	["A1", "Hartowane topory", Branch.ATTACK, 0, false, []],
	["A2", "Łuk kompozytowy", Branch.ATTACK, 0, false, []],
	["A3", "Pochodnie smolne", Branch.ATTACK, 0, false, ["G24"]],
	["A4", "Taktyka oskrzydlenia", Branch.ATTACK, 0, false, []],
	["A5", "Drabiny oblężnicze", Branch.ATTACK, 0, false, []],
	["A6", "Taran okuty", Branch.ATTACK, 0, false, []],
	["A7", "Strzemię", Branch.ATTACK, 0, false, ["A2", "A43"]],
	["A21", "Ściana tarcz", Branch.ATTACK, 0, false, ["A38"]],
	["A38", "Wyroby skórzane", Branch.ATTACK, 0, false, []],
	["A39", "Drzewcarstwo", Branch.ATTACK, 0, false, []],
	["A40", "Cięciwy ze ścięgien", Branch.ATTACK, 0, false, []],
	["A41", "Łukmistrzostwo", Branch.ATTACK, 0, false, []],
	["A42", "Strzałmistrzostwo", Branch.ATTACK, 0, false, []],
	["A43", "Rymarstwo", Branch.ATTACK, 0, false, []],
	["A44", "Ćwiczenia strzeleckie", Branch.ATTACK, 0, false, ["A41"]],
	["A45", "Drużyna", Branch.ATTACK, 0, false, []],
	["A22", "Kopia rycerska", Branch.ATTACK, 1, false, []],
	["A46", "Przeszywanica", Branch.ATTACK, 1, false, []],
	["A47", "Łuk refleksyjny", Branch.ATTACK, 1, false, []],
	["O1", "Sypanie kopców", Branch.DEFENSE, 0, true, []],
	["O2", "Zaostrzone pale", Branch.DEFENSE, 0, false, []],
	["O3", "Fosa z kolcami", Branch.DEFENSE, 0, false, []],
	["G1", "Karczowanie lasu", Branch.ECONOMY, 0, false, []],
	["G2", "Żarna", Branch.ECONOMY, 0, false, []],
	["G4", "Kamieniarstwo", Branch.ECONOMY, 0, false, []],
	["G18", "Łowiectwo", Branch.ECONOMY, 0, false, []],
	["G19", "Garbarstwo", Branch.ECONOMY, 0, false, []],
	["G20", "Uprawa lnu", Branch.ECONOMY, 0, false, []],
	["G21", "Rybołówstwo", Branch.ECONOMY, 0, false, []],
	["G24", "Smolarstwo", Branch.ECONOMY, 0, false, []],
	["G6", "Zaprawa wapienna", Branch.ECONOMY, 1, true, []],
	["U1", "Wiec grodowy", Branch.UTILITY, 0, false, []],
	["S1", "Tropiciele", Branch.UTILITY, 0, false, []],
	["S2", "Ogniska sygnałowe", Branch.UTILITY, 0, false, []],
]

static var _rows: Dictionary = {}


static func count() -> int:
	return TECHS.size()


static func has(code: String) -> bool:
	return _row(code).size() > 0


## Kody wszystkich technologii w kolejności z TECHS.
static func codes() -> Array[String]:
	var out: Array[String] = []
	for row: Array in TECHS:
		out.append(row[0] as String)
	return out


## Kody technologii jednej gałęzi w kolejności kafelków.
static func in_branch(branch: int) -> Array[String]:
	var out: Array[String] = []
	for row: Array in TECHS:
		if int(row[2]) == branch:
			out.append(row[0] as String)
	return out


static func tech_name(code: String) -> String:
	var row := _row(code)
	return row[1] as String if row.size() > 0 else code


static func branch(code: String) -> int:
	var row := _row(code)
	return int(row[2]) if row.size() > 0 else -1


static func age(code: String) -> int:
	var row := _row(code)
	return int(row[3]) if row.size() > 0 else 0


static func is_key(code: String) -> bool:
	var row := _row(code)
	return row.size() > 0 and bool(row[4])


static func requires(code: String) -> Array[String]:
	var out: Array[String] = []
	var row := _row(code)
	if row.size() > 0:
		out.assign(row[5] as Array)
	return out


## Napis epoki, np. „Epoka II”.
static func age_label(tech_age: int) -> String:
	return "Epoka %s" % AGE_NUMERALS[clampi(tech_age, 0, AGE_NUMERALS.size() - 1)]


static func _row(code: String) -> Array:
	if _rows.is_empty():
		for row: Array in TECHS:
			_rows[row[0]] = row
	return _rows.get(code, []) as Array
