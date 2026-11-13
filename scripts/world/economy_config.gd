class_name EconomyConfig
extends RefCounted
## Liczby ekonomii w jednym miejscu: surowce, zapasy na start, produkcja i pojemność magazynów.
## Stawki są na godzinę, w całych jednostkach. Zmiana balansu to zmiana tylko tego pliku.

enum Res { WOOD, STONE, FOOD, GOLD }

const NAMES: Array[String] = ["Drewno", "Kamień", "Żywność", "Złoto"]
## Skróty na pasku surowców (ikony dojdą z HUD-em w #9).
const SHORT_NAMES: Array[String] = ["Dr", "Ka", "Ży", "Zł"]

const START: Array[int] = [500, 300, 300, 50]
## Pojemność magazynu. 0 oznacza brak limitu: złoto to docelowo waluta premium.
const CAPACITY: Array[int] = [1000, 1000, 1000, 0]
## Produkcja samego grodu, niezależna od budynków. Złoto nie rośnie samo, przybywa z łupu i PvE.
const BASE_PER_HOUR: Array[int] = [20, 20, 20, 0]

## Produkcja budynków: rodzaj → [surowiec, stawki na godzinę dla poziomów 1–5].
const BUILDING_PRODUCTION := {
	BuildingTypes.Kind.LUMBER_HUT: [Res.WOOD, [60, 90, 120, 160, 200]],
}

## Najdłuższa nieobecność, za którą liczy się produkcję. Magazyny i tak zapełniają się
## wcześniej; limit chroni rachunek przed absurdalnym zegarem systemowym.
const MAX_CATCH_UP_MS := 30 * 24 * 3600 * 1000


static func count() -> int:
	return NAMES.size()


static func is_capped(res: int) -> bool:
	return CAPACITY[res] > 0
