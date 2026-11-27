class_name EconomyConfig
extends RefCounted
## Liczby ekonomii w jednym miejscu: surowce, zapasy na start, produkcja i pojemność magazynów.
## Stawki są na godzinę, w całych jednostkach. Zmiana balansu to zmiana tylko tego pliku.

enum Res { WOOD, STONE, FOOD, GOLD }

const NAMES: Array[String] = ["Drewno", "Kamień", "Żywność", "Złoto"]
## Skróty w komunikacie o nieobecności („+120 Dr +20 Ka”). Pasek surowców ma ikony (PixelIcons).
const SHORT_NAMES: Array[String] = ["Dr", "Ka", "Ży", "Zł"]

const START: Array[int] = [500, 300, 300, 50]
## Pojemność na start, którą daje Dwór (niezależnie od poziomu). 0 oznacza brak limitu: złoto
## to docelowo waluta premium. Więcej mieści się dopiero po postawieniu Magazynów.
const CAPACITY: Array[int] = [1000, 1000, 1000, 0]
## Ile pojemności dodaje każdy Magazyn na poziomach 1–10 narastająco (drewnu, kamieniowi i żywności
## po równo). Magazyny się sumują. Liczby tymczasowe; poziomy 6–10: decyzja właścicielki #262.
const WAREHOUSE_CAPACITY: Array[int] = [500, 750, 1000, 1500, 2000, 2500, 3000, 3500, 4500, 6000]
## Produkcja samego grodu, niezależna od budynków. Złoto nie rośnie samo, przybywa z łupu i PvE.
const BASE_PER_HOUR: Array[int] = [20, 20, 20, 0]

## Produkcja budynków: rodzaj → [surowiec, stawki na godzinę dla poziomów 1–10 narastająco].
## Poziomy 6–10 (epoka II) TYMCZASOWE, decyzja właścicielki #262.
const BUILDING_PRODUCTION := {
	BuildingTypes.Kind.LUMBER_HUT: [Res.WOOD, [60, 90, 120, 160, 200, 240, 280, 330, 380, 440]],
	## Rybak (#122): żywność, stawiany tylko przy wodzie. Stawki tymczasowe, w skali Chaty drwala.
	BuildingTypes.Kind.FISHER: [Res.FOOD, [40, 60, 80, 110, 140, 170, 200, 230, 270, 310]],
	## Pole i spichlerz (#35): główne źródło żywności epoki I, w skali Chaty drwala. Kamieniołom (#35,
	## G4): kamień. Stawki tymczasowe, do decyzji balansowej właścicielki.
	BuildingTypes.Kind.FARM: [Res.FOOD, [60, 90, 120, 160, 200, 240, 280, 330, 380, 440]],
	BuildingTypes.Kind.QUARRY: [Res.STONE, [40, 60, 80, 110, 140, 170, 200, 230, 270, 310]],
}

## Najdłuższa nieobecność, za którą liczy się produkcję. Magazyny i tak zapełniają się
## wcześniej; limit chroni rachunek przed absurdalnym zegarem systemowym.
const MAX_CATCH_UP_MS := 30 * 24 * 3600 * 1000


static func count() -> int:
	return NAMES.size()


static func is_capped(res: int) -> bool:
	return CAPACITY[res] > 0


## O ile Magazyn mieści więcej po dojściu do poziomu `level` (z poziomu niższego o 1); poziom 1
## to postawienie. Poza zakresem poziomów 0.
static func warehouse_gain(level: int) -> int:
	if level < 1 or level > WAREHOUSE_CAPACITY.size():
		return 0
	return WAREHOUSE_CAPACITY[level - 1] - (WAREHOUSE_CAPACITY[level - 2] if level >= 2 else 0)
