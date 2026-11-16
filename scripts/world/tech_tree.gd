class_name TechTree
extends RefCounted
## Drzewko technologii MVP (#12): 34 z 131 technologii z notatki Drzewko technologiczne
## (docs/castle-defender-vault), w pięciu gałęziach, z epoką, oznaczeniem technologii kluczowej
## (★, warunek przejścia do następnej epoki, #34), efektem i zależnościami.
## Zależności są według notatki, łącznie z jej sekcją „Zmienione zależności”
## (A21 ← A38, A3 ← G24, a A7 Strzemię wymaga A2 i A43).
## Działają już efekty, które mają w grze na co wpłynąć (PRODUCTION_BONUS). Pozostałe
## (budynki, jednostki, manewry, morale) włączą się razem z tymi systemami.

enum Branch { ATTACK, DEFENSE, ECONOMY, UTILITY, SPECIAL }

const BRANCH_NAMES: Array[String] = ["Atak", "Obrona", "Gospodarka", "Użyteczne", "Specjalne"]
## Numery epok na ekranie (indeks = epoka, 0 = epoka I).
const AGE_NUMERALS: Array[String] = ["I", "II"]

## Wiersz: [kod, nazwa, gałąź, epoka (0 = I), kluczowa ★, wymagane kody, efekt].
## Kolejność wierszy to kolejność kafelków na ekranie drzewka.
const TECHS: Array = [
	["A1", "Hartowane topory", Branch.ATTACK, 0, false, [], "wojownicy +15% obrażeń przeciw drewnu"],
	["A2", "Łuk kompozytowy", Branch.ATTACK, 0, false, [], "łucznicy +20% zasięgu"],
	["A3", "Pochodnie smolne", Branch.ATTACK, 0, false, ["G24"], "jednostka Podpalacz, manewr Podpalenie"],
	["A4", "Taktyka oskrzydlenia", Branch.ATTACK, 0, false, ["A1"], "manewr Oskrzydlenie"],
	["A7", "Strzemię", Branch.ATTACK, 0, false, ["A2", "A43"], "jednostka Jeździec, konnica +25% szybkości"],
	["A21", "Ściana tarcz", Branch.ATTACK, 0, false, ["A38"], "jednostka Tarczownik"],
	["A38", "Wyroby skórzane", Branch.ATTACK, 0, false, ["G19"], "budynek Wytwórca zbroi skórzanych"],
	["A39", "Drzewcarstwo", Branch.ATTACK, 0, false, [], "budynek Drzewcarz"],
	["A40", "Cięciwy ze ścięgien", Branch.ATTACK, 0, false, ["G18"], "budynek Cięciwiarz"],
	["A41", "Łukmistrzostwo", Branch.ATTACK, 0, false, ["A40"], "budynek Łukmistrz"],
	["A42", "Strzałmistrzostwo", Branch.ATTACK, 0, false, ["G18"], "budynek Strzałmistrz, zapas strzał dla wież"],
	["A43", "Rymarstwo", Branch.ATTACK, 0, false, ["G19"], "budynek Rymarz (siodła, uprząż)"],
	["A44", "Ćwiczenia strzeleckie", Branch.ATTACK, 0, false, ["A41"], "budynek Strzelnica (rekrutacja strzelców)"],
	["A45", "Drużyna", Branch.ATTACK, 0, false, ["A38"], "budynek Dom drużyny (rekrutacja ciężkich)"],
	["A5", "Drabiny oblężnicze", Branch.ATTACK, 1, false, ["A4"], "manewr Szturm z drabinami"],
	["A6", "Taran okuty", Branch.ATTACK, 1, false, ["A1"], "jednostka Taran, manewr Taranowanie bramy"],
	["A22", "Kopia rycerska", Branch.ATTACK, 1, false, ["A7"], "jednostka Kopijnik"],
	["A46", "Przeszywanica", Branch.ATTACK, 1, false, ["A45"], "jednostka Drużynnik w przeszywanicy"],
	["A47", "Łuk refleksyjny", Branch.ATTACK, 1, false, ["A2"], "jednostka Strzelec z łukiem refleksyjnym"],
	["O1", "Sypanie kopców", Branch.DEFENSE, 0, true, [], "budynek Kopiec, warunek przejścia I → II"],
	["O2", "Zaostrzone pale", Branch.DEFENSE, 0, false, [], "palisada +20% wytrzymałości"],
	["O3", "Fosa z kolcami", Branch.DEFENSE, 0, false, ["O2"], "sucha fosa rani wrogów"],
	["G1", "Karczowanie lasu", Branch.ECONOMY, 0, false, [], "+20% drewna"],
	["G2", "Żarna", Branch.ECONOMY, 0, false, [], "+15% żywności"],
	["G18", "Łowiectwo", Branch.ECONOMY, 0, false, [], "budynek Chata myśliwego"],
	["G19", "Garbarstwo", Branch.ECONOMY, 0, false, ["G18"], "budynek Garbarnia"],
	["G20", "Uprawa lnu", Branch.ECONOMY, 0, false, ["G2"], "budynek Pole lnu"],
	["G21", "Rybołówstwo", Branch.ECONOMY, 0, false, [], "budynek Rybak przy rzece"],
	["G24", "Smolarstwo", Branch.ECONOMY, 0, false, ["G1"], "budynek Smolarnia"],
	["G4", "Kamieniarstwo", Branch.ECONOMY, 1, false, ["G1"], "budynek Kamieniołom"],
	["G6", "Zaprawa wapienna", Branch.ECONOMY, 1, true, ["G4"], "warunek przejścia II → III"],
	["U1", "Wiec grodowy", Branch.UTILITY, 0, false, [], "+5 morale załogi"],
	["S1", "Tropiciele", Branch.SPECIAL, 0, false, [], "zwiad odsłania 20% zamku przeciwnika"],
	["S2", "Ogniska sygnałowe", Branch.SPECIAL, 0, false, [], "budynek Wieża sygnałowa"],
	["S3", "Dom zwiadowców", Branch.SPECIAL, 1, false, ["S1"], "budynek Dom zwiadowców i jednostka Zwiadowca, zwiad +10% zasięgu"],
]

## Efekty, które już działają: kod → [surowiec (EconomyConfig.Res), premia do produkcji w %].
const PRODUCTION_BONUS := {
	"G1": [EconomyConfig.Res.WOOD, 20],
	"G2": [EconomyConfig.Res.FOOD, 15],
}

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


## Efekt technologii słowami, jak w notatce.
static func effect(code: String) -> String:
	var row := _row(code)
	return row[6] as String if row.size() > 0 else ""


## Napis epoki, np. „Epoka II”.
static func age_label(tech_age: int) -> String:
	return "Epoka %s" % AGE_NUMERALS[clampi(tech_age, 0, AGE_NUMERALS.size() - 1)]


static func _row(code: String) -> Array:
	if _rows.is_empty():
		for row: Array in TECHS:
			_rows[row[0]] = row
	return _rows.get(code, []) as Array
