class_name UnitTypes
extends RefCounted
## Jednostki MVP (#87, #15): 13 jednostek epok I–II z notatek Jednostki oraz Klasy jednostek
## i produkcja (docs/castle-defender-vault). Każda bojowa jednostka ma jedną z 5 klas
## (RecruitmentConfig.UnitClass); inżynieria zostaje osobnym typem (klasa -1), jak w notatce.
##
## Przewagi klas (ADVANTAGE) są z tabeli klas w notatce: lekka silna przeciw strzelcom w zwarciu,
## ciężka przeciw lekkiej i konnicy, strzelecka przeciw lekkiej i ciężkiej, szybka przeciw
## strzelcom. Jednostki z drzewcem (Włócznik) mają ×2 przeciw konnicy osobno (ANTI_CAVALRY).
## Rachunek jest w liczbach całkowitych, więc ten sam pojedynek zawsze kończy się tak samo.

const C := RecruitmentConfig.UnitClass
const K := BuildingTypes.Kind
const G := GoodsConfig.Good
const R := EconomyConfig.Res

enum Unit {
	AXE_WARRIOR, JAVELINEER, ARCHER, SHIELDBEARER, FIRE_RAISER, TRACKER, RIDER,
	SPEARMAN, GAMBESON_WARRIOR, REFLEX_ARCHER, LANCER,
	RAM, DIGGER,
}

## Klasa „inżynieria”: poza 5 klasami bojowymi.
const ENGINEERING := -1

## Wiersz: [nazwa, klasa, epoka (0 = I), HP, atak, zasięg, szybkość, technologia, budynek rekrutacji
## (-1: budynku jeszcze nie ma), koszt w surowcach {Res: n}, koszt w towarach {Good: n}].
## Statystyki z notatki Jednostki; koszty w towarach z notatek, ilości surowców tymczasowe.
const UNITS: Array = [
	["Wojownik z toporem", C.LIGHT, 0, 60, 10, 1, 3, "", K.BARRACKS, {R.FOOD: 10}, {G.STONE_AXE: 1}],
	["Oszczepnik", C.LIGHT, 0, 45, 8, 3, 3, "", K.BARRACKS, {R.FOOD: 10}, {G.JAVELIN: 2}],
	["Łucznik", C.RANGED, 0, 35, 7, 6, 3, "", K.ARCHERY_RANGE, {R.FOOD: 10}, {G.BOW: 1, G.ARROW: 20}],
	["Tarczownik", C.HEAVY, 0, 90, 5, 1, 2, "A21", K.WARBAND_HOUSE, {R.FOOD: 10},
			{G.SHIELD: 1, G.LEATHER_ARMOR: 1}],
	["Podpalacz", C.SPECIAL, 0, 35, 4, 3, 3, "A3", K.TAR_KILN, {R.FOOD: 10}, {G.PITCH: 2}],
	["Tropiciel", C.SPECIAL, 0, 25, 0, 0, 5, "S1", -1, {R.FOOD: 15}, {G.RAW_HIDE: 2}],
	["Jeździec", C.FAST, 0, 90, 12, 1, 6, "A7", K.STABLE, {R.FOOD: 15}, {G.HORSE: 1, G.SADDLE: 1}],
	["Włócznik", C.LIGHT, 1, 70, 9, 2, 3, "", K.BARRACKS, {R.FOOD: 10}, {G.SPEAR: 1}],
	["Drużynnik w przeszywanicy", C.HEAVY, 1, 110, 11, 1, 2, "A46", K.WARBAND_HOUSE, {R.FOOD: 15},
			{G.GAMBESON: 1, G.LEATHER_ARMOR: 1, G.SHIELD: 1}],
	["Strzelec z łukiem refleksyjnym", C.RANGED, 1, 40, 9, 7, 3, "A47", K.ARCHERY_RANGE, {R.FOOD: 10},
			{G.REFLEX_BOW: 1, G.ARROW: 20}],
	["Kopijnik", C.FAST, 1, 140, 22, 1, 5, "A22", K.STABLE, {R.FOOD: 20},
			{G.HORSE: 1, G.SADDLE: 1, G.LANCE: 1}],
	["Taran", ENGINEERING, 1, 300, 40, 1, 1, "A6", K.BARRACKS, {R.WOOD: 60}, {G.WET_HIDE: 2}],
	["Kopacz", ENGINEERING, 0, 40, 2, 1, 3, "", K.BARRACKS, {R.FOOD: 10}, {}],
]

## Jednostki z drzewcem: ×2 obrażeń przeciw konnicy (Włócznik w notatce Jednostki).
const ANTI_CAVALRY: Array[int] = [Unit.SPEARMAN]
const ANTI_CAVALRY_PERCENT := 200

## Przewagi klas: [atakujący][broniący się] w procentach obrażeń (100 = bez przewagi).
## Kolejność jak RecruitmentConfig.UnitClass: lekka, ciężka, strzelecka, szybka, specjalna.
const ADVANTAGE: Array = [
	[100, 100, 150, 100, 100],  # lekka: silna przeciw strzelcom w zwarciu
	[150, 100, 100, 150, 100],  # ciężka: silna przeciw lekkiej i konnicy
	[150, 125, 100, 75, 100],   # strzelecka: silna przeciw lekkiej i ciężkiej, słaba przeciw szybkiej
	[125, 75, 150, 100, 100],   # szybka: silna przeciw strzelcom, słaba przeciw ciężkiej
	[100, 100, 100, 100, 100],  # specjalna: zależnie od jednostki
]


static func count() -> int:
	return UNITS.size()


static func unit_name(unit: int) -> String:
	return UNITS[unit][0] as String


## Klasa jednostki (RecruitmentConfig.UnitClass) albo ENGINEERING.
static func unit_class(unit: int) -> int:
	return int(UNITS[unit][1])


static func age(unit: int) -> int:
	return int(UNITS[unit][2])


static func hp(unit: int) -> int:
	return int(UNITS[unit][3])


static func attack(unit: int) -> int:
	return int(UNITS[unit][4])


static func attack_range(unit: int) -> int:
	return int(UNITS[unit][5])


static func speed(unit: int) -> int:
	return int(UNITS[unit][6])


static func required_tech(unit: int) -> String:
	return UNITS[unit][7] as String


static func building(unit: int) -> int:
	return int(UNITS[unit][8])


static func resource_cost(unit: int) -> Dictionary:
	return UNITS[unit][9] as Dictionary


static func goods_cost(unit: int) -> Dictionary:
	return UNITS[unit][10] as Dictionary


## Mnożnik obrażeń (w procentach) jednostki `attacker` przeciw `defender` z przewag klas
## i drzewca. Inżynieria nie ma przewag klasowych.
static func advantage_percent(attacker: int, defender: int) -> int:
	var a := unit_class(attacker)
	var d := unit_class(defender)
	var percent := 100
	if a != ENGINEERING and d != ENGINEERING:
		percent = int((ADVANTAGE[a] as Array)[d])
	if ANTI_CAVALRY.has(attacker) and d == C.FAST:
		@warning_ignore("integer_division")
		percent = percent * ANTI_CAVALRY_PERCENT / 100
	return percent


## Obrażenia jednego uderzenia `attacker` w `defender` (liczby całkowite).
static func damage(attacker: int, defender: int, with_advantage: bool = true) -> int:
	var percent := advantage_percent(attacker, defender) if with_advantage else 100
	@warning_ignore("integer_division")
	return attack(attacker) * percent / 100


## Pojedynek wręcz jeden na jeden, w turach: obie jednostki uderzają jednocześnie, dopóki któraś
## nie padnie. Zwraca [zwycięzca: 0 = `a`, 1 = `b`, -1 = remis, liczba tur]. Do testu przewag (#87);
## pełna symulacja bitwy to #14.
static func duel(a: int, b: int, with_advantage: bool = true) -> Array[int]:
	var hp_a := hp(a)
	var hp_b := hp(b)
	var hit_a := damage(a, b, with_advantage)
	var hit_b := damage(b, a, with_advantage)
	if hit_a <= 0 and hit_b <= 0:
		return [-1, 0] as Array[int]
	var turns := 0
	while hp_a > 0 and hp_b > 0:
		hp_b -= hit_a
		hp_a -= hit_b
		turns += 1
	if hp_a <= 0 and hp_b <= 0:
		return [-1, turns] as Array[int]
	return [0 if hp_b <= 0 else 1, turns] as Array[int]
