class_name BuildingTypes
extends RefCounted
## Budynki epoki I: rozmiar w kratkach, nazwa w UI i reguły łączenia umocnień.
## Wał i palisada to odcinki 1×1, które same łączą się z sąsiadami (autotiling N/E/S/W).
## Dwór to siedziba władcy: jeden na zamek, stoi od startu, a jego poziom jest poziomem zamku.
## Nie ma go na pasku budowy (BUILD_BAR). Wytwórcy (#90) dochodzą za Dworem, żeby numery rodzajów
## w starszych zapisach się nie zmieniły.

enum Kind {
	RAMPART, PALISADE, GATE, TOWER, LUMBER_HUT, MANOR,
	HUNTER, TANNERY, LEATHERWORKER, POLEARM, BOWSTRING, BOWYER, FLETCHER, SADDLER, TAR_KILN,
	FLAX_FIELD, FISHER, STABLE,
	BARRACKS, WARBAND_HOUSE, ARCHERY_RANGE,
	KEEP,
	## Chata tropicieli (#28, od S1): szkoli Tropicieli i wysyła zwiad. Po S3 Dom zwiadowców (#92),
	## w którym szkolą się też Zwiadowcy. Jeden rodzaj, więc stare zapisy Domu zwiadowców zostają.
	SCOUT_HOUSE,
	WATCHTOWER,
	## Komenda umocnień (#199): Sprawdź szczelność pierścienia i uszczelnij luki.
	SEAL_HOUSE,
	## Magazyn: podnosi pojemność drewna, kamienia i żywności ponad zapas Dworu.
	WAREHOUSE,
	## Pozostałe budynki MVP (#35): Fosa sucha (1×1, przechodnia, spowalnia), Kopiec (O1, podwyższa
	## sąsiednie wieże), Pole i spichlerz (żywność), Studnia (gaszenie pożarów), Kamieniołom (G4, kamień)
	## i Wieża sygnałowa (S2, budynek badań gałęzi Specjalne, wykrywanie zwiadu z #28).
	DRY_MOAT,
	MOUND,
	FARM,
	WELL,
	QUARRY,
	SIGNAL_TOWER,
	## Budynki epoki II spoza MVP (#102, ADR 0011): stawiane od razu na poziomie 6 (BuildConfig.start_level).
	## Młyn (#388, G5): premia do całej żywności, przy rzece.
	MILL,
}
## Stan budynku zależny od wytrzymałości: cały, pęknięcia, wyrwa w blankach, gruz.
enum State { INTACT, CRACKED, BREACHED, RUBBLE }

## Chata tropicieli po zbadaniu S3 (BuildingTypes.name_of).
const SCOUT_HOUSE_S3_NAME := "Dom zwiadowców"

const MAX_LEVEL := 5
## Najniższy procent wytrzymałości, przy którym budynek jest jeszcze w danym stanie
## (cały, pęknięcia, wyrwa). Przy 0% zostaje gruz.
const STATE_MIN_HP_PERCENT: Array[int] = [76, 41, 1]
## Bity maski sąsiadów dla autotilingu.
const N := 1
const E := 2
const S := 4
const W := 8

const NAMES: Array[String] = ["Wał ziemny", "Palisada", "Brama drewniana", "Wieża drewniana", "Chata drwala", "Dwór",
		"Chata myśliwego", "Garbarnia", "Wytwórca zbroi skórzanych", "Drzewcarz", "Cięciwiarz", "Łukmistrz",
		"Strzałmistrz", "Rymarz", "Smolarnia", "Pole lnu", "Rybak", "Stajnia", "Koszary", "Dom drużyny", "Strzelnica",
		"Wieża grodowa", "Chata tropicieli", "Strażnica", "Komenda umocnień", "Magazyn",
		"Fosa sucha", "Kopiec", "Pole i spichlerz", "Studnia", "Kamieniołom", "Wieża sygnałowa", "Młyn"]
## Napisy na kafelkach panelu budowy (BuildPanel, ok. 57–71 px).
const SHORT_NAMES: Array[String] = ["Wał", "Palisada", "Brama", "Wieża", "Chata", "Dwór",
		"Myśliwy", "Garbarnia", "Zbrojarz", "Drzewcarz", "Cięciwy", "Łukmistrz", "Strzały", "Rymarz", "Smolarnia",
		"Len", "Rybak", "Stajnia", "Koszary", "Drużyna", "Strzelnica", "Donżon",
		"Tropiciele", "Strażnica", "Komenda", "Magazyn", "Fosa", "Kopiec", "Spichlerz", "Studnia", "Kamień",
		"Sygnałowa", "Młyn"]
## Rozmiar w kratkach (#340, ADR 0005): Koszary 3×3, budynki wojska, Magazyn i pola 3×2 (poziomo),
## reszta 2×2, a umocnienia 1×1 i brama 3×1. Budynek ze starszego zapisu zostaje w zapisanym prostokącie
## (BuildGrid.cells_of), więc ta tabela dotyczy tylko nowych budowli.
const SIZES: Array[Vector2i] = [Vector2i(1, 1), Vector2i(1, 1), Vector2i(3, 1), Vector2i(2, 2), Vector2i(2, 2),
		Vector2i(2, 2), Vector2i(2, 2), Vector2i(2, 2), Vector2i(2, 2), Vector2i(2, 2), Vector2i(2, 2),
		Vector2i(2, 2), Vector2i(2, 2), Vector2i(2, 2), Vector2i(2, 2), Vector2i(3, 2), Vector2i(2, 2), Vector2i(3, 2),
		Vector2i(3, 3), Vector2i(3, 2), Vector2i(3, 2), Vector2i(2, 2), Vector2i(2, 2), Vector2i(2, 2), Vector2i(2, 2),
		Vector2i(3, 2), Vector2i(1, 1), Vector2i(2, 2), Vector2i(3, 2), Vector2i(2, 2), Vector2i(3, 2),
		Vector2i(2, 2), Vector2i(2, 2)]
## Rodzaje na pasku budowy, w kolejności przycisków (bez Dworu): umocnienia, gospodarka (#122),
## Magazyn, wytwórcy w kolejności łańcucha, na końcu budynki rekrutacji (#119), Chata tropicieli (#28, #92)
## i Wieża sygnałowa (#35). Młyn (#388) stoi za Rybakiem.
const BUILD_BAR: Array[int] = [Kind.RAMPART, Kind.PALISADE, Kind.GATE, Kind.TOWER, Kind.DRY_MOAT, Kind.MOUND,
		Kind.SEAL_HOUSE, Kind.LUMBER_HUT, Kind.FARM, Kind.FISHER, Kind.MILL, Kind.FLAX_FIELD, Kind.QUARRY, Kind.WELL,
		Kind.WAREHOUSE, Kind.HUNTER, Kind.TANNERY, Kind.LEATHERWORKER, Kind.POLEARM, Kind.BOWSTRING, Kind.BOWYER,
		Kind.FLETCHER, Kind.SADDLER, Kind.STABLE, Kind.TAR_KILN, Kind.BARRACKS, Kind.WARBAND_HOUSE,
		Kind.ARCHERY_RANGE, Kind.SCOUT_HOUSE, Kind.SIGNAL_TOWER]


## Kategorie w panelu budowy (po teście na telefonie): zakładki zamiast jednego długiego paska.
enum Category { DEFENSE, ECONOMY, PRODUCERS, MILITARY }
const CATEGORY_NAMES: Array[String] = ["Umocnienia", "Gospodarka", "Wytwórcy", "Wojsko"]
## Rodzaje w kategoriach, w kolejności kafelków (ta sama kolejność co BUILD_BAR).
const CATEGORIES: Array = [
	[Kind.RAMPART, Kind.PALISADE, Kind.GATE, Kind.TOWER, Kind.DRY_MOAT, Kind.MOUND, Kind.SEAL_HOUSE],
	[Kind.LUMBER_HUT, Kind.FARM, Kind.FISHER, Kind.MILL, Kind.FLAX_FIELD, Kind.QUARRY, Kind.WELL, Kind.WAREHOUSE],
	[Kind.HUNTER, Kind.TANNERY, Kind.LEATHERWORKER, Kind.POLEARM, Kind.BOWSTRING, Kind.BOWYER, Kind.FLETCHER,
			Kind.SADDLER, Kind.TAR_KILN],
	[Kind.BARRACKS, Kind.WARBAND_HOUSE, Kind.ARCHERY_RANGE, Kind.STABLE, Kind.SCOUT_HOUSE, Kind.SIGNAL_TOWER],
]


static func in_category(cat: int) -> Array[int]:
	var out: Array[int] = []
	out.assign(CATEGORIES[cat] as Array)
	return out


## Kategoria rodzaju albo -1 (Dwór nie stoi w panelu).
static func category(kind: int) -> int:
	for i in CATEGORIES.size():
		if (CATEGORIES[i] as Array).has(kind):
			return i
	return -1


static func count() -> int:
	return NAMES.size()


## Nazwa budynku w UI z uwzględnieniem badań: Chata tropicieli (#28) po S3 staje się Domem
## zwiadowców (#92), w którym szkolą się też Zwiadowcy. Bez `research` nazwa z NAMES.
static func name_of(kind: int, research: Research = null) -> String:
	if kind == Kind.SCOUT_HOUSE and research != null and research.is_done("S3"):
		return SCOUT_HOUSE_S3_NAME
	return NAMES[kind]


## Czy budynek jest z drewna (epoka I: wszystko poza wałem ziemnym, polem lnu, fosą, kopcem, studnią
## i kamieniołomem). Topór i ogień działają mocniej na drewno (#15).
static func is_wooden(kind: int) -> bool:
	return not kind in [Kind.RAMPART, Kind.FLAX_FIELD, Kind.DRY_MOAT, Kind.MOUND, Kind.WELL, Kind.QUARRY]


## Czy przez budynek da się przejść w bitwie (#35): Fosa sucha to rów, nie przeszkoda. Nie blokuje
## drogi i nie da się jej zburzyć, tylko spowalnia atakujących (Battle).
static func is_passable(kind: int) -> bool:
	return kind == Kind.DRY_MOAT


## Czy budynek stoi tylko przy wodzie: Rybak (#122) i Młyn wodny (#388).
static func needs_water(kind: int) -> bool:
	return kind == Kind.FISHER or kind == Kind.MILL


## Budynki, które zamek ma od startu, po jednym, i których nie da się rozebrać: Dwór, donżon (#120)
## i Strażnica (PvE, #177).
static func is_unique(kind: int) -> bool:
	return kind == Kind.MANOR or kind == Kind.KEEP or kind == Kind.WATCHTOWER


## Czy budynek ma poziomy do ulepszania. Strażnica (#177) ma jeden poziom (decyzja właścicielki):
## ulepszenie nic by w PvE nie zmieniało. Donżon (#232) też się nie ulepsza (decyzja właścicielki).
static func has_levels(kind: int) -> bool:
	return kind != Kind.WATCHTOWER and kind != Kind.KEEP


## Liczba rodzajów, które gracz stawia z panelu budowy (bez Dworu i donżonu).
static func buildable_count() -> int:
	return BUILD_BAR.size()


## Rodzaj budynku na miejscu `index` listy BUILD_BAR (kolejność rodzajów w panelu budowy).
static func bar_kind(index: int) -> int:
	return BUILD_BAR[clampi(index, 0, BUILD_BAR.size() - 1)]


static func size_of(kind: int) -> Vector2i:
	return SIZES[kind]


static func is_wall(kind: int) -> bool:
	return kind == Kind.RAMPART or kind == Kind.PALISADE


## Czy odcinek umocnienia `wall` łączy się z sąsiednim budynkiem `other`. Wał i palisada łączą się
## ze sobą nawzajem (mieszana linia nie ma szpar) oraz z bramą i wieżą, żeby stały w linii.
static func connects(wall: int, other: int) -> bool:
	if not is_wall(wall):
		return false
	return is_wall(other) or other == Kind.GATE or other == Kind.TOWER


## Stan budynku dla wytrzymałości `hp` z `max_hp`. Procent liczy się w liczbach całkowitych
## i zaokrągla w górę, więc budynek z choćby 1 punktem nigdy nie jest gruzem.
static func state_for_hp(hp: int, max_hp: int) -> int:
	if max_hp <= 0 or hp <= 0:
		return State.RUBBLE
	@warning_ignore("integer_division")
	var percent := (100 * mini(hp, max_hp) + max_hp - 1) / max_hp
	for state in STATE_MIN_HP_PERCENT.size():
		if percent >= STATE_MIN_HP_PERCENT[state]:
			return state
	return State.RUBBLE
