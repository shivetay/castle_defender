class_name GoodsConfig
extends RefCounted
## Towary i przepisy produkcji (#88) w jednym miejscu, według notatki Klasy jednostek i produkcja
## (docs/castle-defender-vault). Budynek produkcyjny (wytwórca) wykonuje cykle przepisu: zużywa
## wejścia (surowce z EconomyConfig.Res i towary) i daje wyjścia. Wejścia są z kolumny „Z czego”
## notatki. Epoki I–II nie zużywają metalu; żelazo dojdzie jako surowiec od epoki III (#93).
##
## Notatka zostawia liczby (ilości, tempo, limity) jako decyzje balansowe, więc ilości w przepisach
## i tempa są tymczasowe. Budynki wytwórców dojdą w #90 (PRODUCER_KINDS).

enum Good {
	RAW_HIDE, LEATHER, BONE, SINEW, FEATHER, FLAX,
	LEATHER_ARMOR, GAMBESON, SHIELD, WET_HIDE,
	SPEAR, JAVELIN, LANCE, STONE_AXE,
	BOWSTRING, BOW, REFLEX_BOW, ARROW,
	SADDLE, HARNESS, PITCH, HORSE,
}

const NAMES: Array[String] = [
	"Surowe skóry", "Wyprawiona skóra", "Kość", "Ścięgna", "Pióra", "Len",
	"Zbroja skórzana", "Przeszywanica", "Tarcza", "Mokre skóry",
	"Włócznia", "Oszczep", "Kopia", "Topór kamienny",
	"Cięciwa", "Łuk", "Łuk refleksyjny", "Strzały",
	"Siodło", "Uprząż", "Smoła", "Koń",
]

## Pojemność zbrojowni dla każdego towaru: „limit jak przy surowcach” (EconomyConfig.CAPACITY).
const ARMORY_CAPACITY := 1000

## Wytwórcy w kolejności liczenia: najpierw ci, którzy dają półprodukty, potem ci, którzy je zużywają,
## więc długa nieobecność liczy się w jednym przebiegu łańcucha.
const PRODUCERS: Array[String] = ["hunter", "flax_field", "tannery", "bowstring", "polearm", "bowyer",
		"fletcher", "leatherworker", "saddler", "tar_kiln", "stable"]
const PRODUCER_NAMES := {
	"hunter": "Chata myśliwego", "flax_field": "Pole lnu", "tannery": "Garbarnia",
	"bowstring": "Cięciwiarz", "polearm": "Drzewcarz", "bowyer": "Łukmistrz", "fletcher": "Strzałmistrz",
	"leatherworker": "Wytwórca zbroi skórzanych", "saddler": "Rymarz", "tar_kiln": "Smolarnia",
	"stable": "Stajnia",
}
## Rodzaj budynku (BuildingTypes.Kind) → wytwórca. Uzupełni #90, gdy budynki staną w grze.
const PRODUCER_KINDS := {}

const R := EconomyConfig.Res
const G := Good
## Przepis: [wytwórca, od poziomu budynku, cykle na godzinę na poziomie 1,
##   wejścia surowców {Res: ilość}, wejścia towarów {Good: ilość},
##   wyjścia towarów {Good: ilość}, wyjścia surowców {Res: ilość}]. TYMCZASOWE liczby.
## Ułamki cykli w zapisie (Goods._progress) są indeksowane pozycją przepisu w tej tablicy: nowe
## przepisy dopisuj na końcu, a przy zmianie kolejności dopisz migrację zapisu (review PR 140).
## Budynek wykonuje naraz wszystkie przepisy, do których ma poziom (np. Łukmistrz 3 robi
## też łuki refleksyjne; to jedyny próg poziomu w notatce).
const RECIPES: Array = [
	["hunter", 1, 6, {}, {}, {G.RAW_HIDE: 2, G.BONE: 1, G.SINEW: 1, G.FEATHER: 2}, {R.FOOD: 2}],
	["flax_field", 1, 6, {}, {}, {G.FLAX: 3}, {}],
	["tannery", 1, 4, {}, {G.RAW_HIDE: 2}, {G.LEATHER: 1}, {}],
	["bowstring", 1, 4, {}, {G.SINEW: 2}, {G.BOWSTRING: 1}, {}],
	["bowstring", 1, 4, {}, {G.FLAX: 2}, {G.BOWSTRING: 1}, {}],
	["polearm", 1, 3, {R.WOOD: 3, R.STONE: 1}, {}, {G.SPEAR: 1}, {}],
	["polearm", 1, 3, {R.WOOD: 2, R.STONE: 1}, {}, {G.JAVELIN: 2}, {}],
	["polearm", 1, 2, {R.WOOD: 2, R.STONE: 2}, {}, {G.STONE_AXE: 1}, {}],
	["polearm", 1, 2, {R.WOOD: 5, R.STONE: 1}, {}, {G.LANCE: 1}, {}],
	["bowyer", 1, 2, {R.WOOD: 3}, {G.BOWSTRING: 1}, {G.BOW: 1}, {}],
	["bowyer", 3, 1, {R.WOOD: 4}, {G.BOWSTRING: 1, G.LEATHER: 1}, {G.REFLEX_BOW: 1}, {}],
	["fletcher", 1, 3, {R.WOOD: 1}, {G.BONE: 1, G.FEATHER: 2}, {G.ARROW: 10}, {}],
	["leatherworker", 1, 2, {R.WOOD: 1}, {G.LEATHER: 2}, {G.LEATHER_ARMOR: 1}, {}],
	["leatherworker", 1, 2, {R.WOOD: 2}, {G.LEATHER: 1}, {G.SHIELD: 1}, {}],
	["leatherworker", 1, 1, {}, {G.LEATHER: 1, G.FLAX: 2}, {G.GAMBESON: 1}, {}],
	["leatherworker", 1, 1, {}, {G.RAW_HIDE: 2}, {G.WET_HIDE: 1}, {}],
	["saddler", 1, 2, {R.WOOD: 1}, {G.LEATHER: 2}, {G.SADDLE: 1}, {}],
	["saddler", 1, 2, {}, {G.LEATHER: 1}, {G.HARNESS: 1}, {}],
	["tar_kiln", 1, 3, {R.WOOD: 4}, {}, {G.PITCH: 1}, {}],
	["stable", 1, 1, {R.FOOD: 10}, {}, {G.HORSE: 1}, {}],
]
## Tempo poziomów 1–5 w procentach tempa poziomu 1. TYMCZASOWE.
const LEVEL_PERCENT: Array[int] = [100, 150, 200, 275, 350]
## Puste strzały w zbrojowni zmniejszają tempo strzelania wież i strzelców do tylu procent.
const NO_ARROWS_FIRE_PERCENT := 50


static func count() -> int:
	return NAMES.size()


static func capacity(_good: int) -> int:
	return ARMORY_CAPACITY


## Cykle na godzinę przepisu `recipe` w budynku na poziomie `level` (0, gdy poziom za niski).
static func cycles_per_hour(recipe: int, level: int) -> int:
	var row: Array = RECIPES[recipe]
	if level < int(row[1]):
		return 0
	@warning_ignore("integer_division")
	return int(row[2]) * LEVEL_PERCENT[clampi(level, 1, LEVEL_PERCENT.size()) - 1] / 100
