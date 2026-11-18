class_name BotRoster
extends RefCounted
## 20 zamków-botów (#26): cele Wypraw ze Strażnicy, zanim będzie wielu graczy. Lista jest wspólna dla
## wszystkich graczy (seed z numeru zamku, nie ze świata gracza), więc w etapie 9 przejdzie do bazy
## jako 20 wierszy z seedem. Trudność rośnie z numerem: poziom budynków, wieże, wał zamiast palisady
## w co drugim z pierwszych 10 zamków, zewnętrzny wał,
## budynki rekrutacji i załoga z coraz większej liczby klas. Zamki 16–20 to epoka II (jednostki epoki II).
## Po ataku zamek wraca do pełnego stanu (jest generowany od nowa), więc nowy gracz zawsze ma kogo
## zaatakować. Wszystkie liczby TYMCZASOWE, do balansu.
@warning_ignore_start("integer_division")

const COUNT := 20
## Od tego numeru (0 = pierwszy zamek) zamki są z epoki II.
const AGE_II_FROM := 15
## Od tego numeru zamek ma zewnętrzny pierścień wału przed palisadą.
const OUTER_WALL_FROM := 10
const NAMES: Array[String] = [
	"Gródek", "Bobrowa Wola", "Lisi Jar", "Kamienny Bród", "Wilcze Doły",
	"Sokola Góra", "Mszany Gród", "Zbójecki Gród", "Bielsko Stare", "Czarny Las",
	"Dębowe Wzgórze", "Jastrzębiec", "Krucza Skała", "Niedźwiedzi Kąt", "Orle Gniazdo",
	"Żelazny Bród", "Wronia Wieża", "Turzy Róg", "Smocza Jama", "Gród Pięciu Wież",
]

const K := BuildingTypes.Kind
const U := UnitTypes.Unit


## Seed zamku `i`: ten sam dla każdego gracza.
static func seed_of(i: int) -> int:
	return PixelCanvas.hash2(i, 26, 0xb07c) & 0x7fffffff


static func age_of(i: int) -> int:
	return 1 if i >= AGE_II_FROM else 0


## Umocnienie wewnętrznego pierścienia: zamki 2, 4, 6, 8 i 10 to grody na wale ziemnym, reszta ma
## palisadę (od zamku 11 z zewnętrznym wałem). Pierwszy zamek zostaje najłatwiejszy. TYMCZASOWE.
static func inner_wall_of(i: int) -> int:
	return K.RAMPART if i < OUTER_WALL_FROM and i % 2 == 1 else K.PALISADE


## Poziom budynków zamku: 1 dla zamków 1–4, potem co 4 zamki o jeden wyżej, do 5.
static func level_of(i: int) -> int:
	return clampi(1 + i / 4, 1, BuildingTypes.MAX_LEVEL)


## Wieże poza palisadą: od trzeciego zamku, najwyżej 4.
static func towers_of(i: int) -> int:
	return mini(4, (i + 1) / 3)


## Budynki rekrutacji zamku (#26): Koszary, Strzelnica, Dom drużyny, Stajnia.
static func recruit_buildings(i: int) -> Array[int]:
	var out: Array[int] = []
	if i >= 3:
		out.append(K.BARRACKS)
	if i >= 6:
		out.append(K.ARCHERY_RANGE)
	if i >= 9:
		out.append(K.WARBAND_HOUSE)
	if i >= 12:
		out.append(K.STABLE)
	return out


## Załoga zamku `i`: oddziały [rodzaj, liczba] jak w Battle.create_squads. Zamek 1 to 4 Chłopów,
## kolejne dokładają klasy (lekka, strzelecka, ciężka, szybka, specjalna), a zamki epoki II jednostki
## epoki II.
static func defenders(i: int) -> Array:
	var out: Array = [[U.PEASANT, mini(4 + i, 12)]]
	var rows: Array = [
		[U.AXE_WARRIOR, 1, 2, 12], [U.ARCHER, 2, 1, 12], [U.JAVELINEER, 4, -2, 10],
		[U.SHIELDBEARER, 7, -5, 10], [U.RIDER, 10, -8, 8], [U.FIRE_RAISER, 13, -11, 3],
		[U.SPEARMAN, 15, -10, 10], [U.GAMBESON_WARRIOR, 16, -13, 8], [U.REFLEX_ARCHER, 17, -14, 8],
		[U.LANCER, 18, -16, 4],
	]
	# wiersz: [jednostka, od zamku, przesunięcie, najwięcej]: liczba = min(i + przesunięcie, najwięcej)
	for r: Array in rows:
		if i >= int(r[1]):
			out.append([int(r[0]), mini(i + int(r[2]), int(r[3]))])
	return out


## Liczba obrońców zamku `i`.
static func defender_count(i: int) -> int:
	var n := 0
	for d: Array in defenders(i):
		n += int(d[1])
	return n


static func generate(i: int) -> BotCastle:
	var bot := BotCastle.generate(seed_of(i), i)
	bot.index = i
	return bot


## Najwyższy dostępny zamek, gdy gracz zdobył `beaten` zamków po kolei.
static func last_unlocked(beaten: int) -> int:
	return clampi(beaten, 0, COUNT - 1)


static func is_unlocked(i: int, beaten: int) -> bool:
	return i >= 0 and i <= last_unlocked(beaten)


static func is_beaten(i: int, beaten: int) -> bool:
	return i < beaten


## Krótki opis załogi, np. „5 Chłop, 2 Topornik, 1 Łucznik”, od najliczniejszych.
static func defenders_text(i: int) -> String:
	var parts: Array[String] = []
	for d: Array in defenders(i):
		parts.append("%d %s" % [int(d[1]), UnitTypes.SHORT_NAMES[int(d[0])]])
	return ", ".join(parts)
