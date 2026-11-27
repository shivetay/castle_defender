class_name BotRoster
extends RefCounted
## Zamki-boty (#26, #230): cele Wypraw ze Strażnicy, zanim będzie wielu graczy. 20 zamków na każdą
## epokę (MVP: I–II, razem 40). Zamki 0–19 to epoka I, 20–39 epoka II. Lista jest wspólna dla
## wszystkich graczy (seed z numeru zamku, nie ze świata gracza) i leży w bazie (`bot_castles`).
## Trudność rośnie z rangą w epoce: poziom budynków, wieże, wał zamiast palisady w co drugim
## z pierwszych 10 zamków, zewnętrzny wał, budynki rekrutacji i załoga z coraz większej liczby klas.
## Epoka II zaczyna od połowy krzywej epoki I (siła konstrukcji `structure_of`), a jej załoga to tło
## z piechoty epoki I i dokładane z rangą jednostki epoki II.
## Po ataku zamek wraca do pełnego stanu (jest generowany od nowa), więc nowy gracz zawsze ma kogo
## zaatakować. Wszystkie liczby TYMCZASOWE, do balansu.
@warning_ignore_start("integer_division")

## Zamki na epokę.
const COUNT_PER_AGE := 20
## Epoki z zamkami-botami (MVP: I–II).
const AGES := 2
const COUNT := COUNT_PER_AGE * AGES
## Od tej siły konstrukcji zamek ma zewnętrzny pierścień wału przed palisadą.
const OUTER_WALL_FROM := 10
## Najwyższa siła konstrukcji (ostatni zamek epoki I).
const MAX_STRUCTURE := COUNT_PER_AGE - 1
## Siła konstrukcji pierwszego zamku epoki II: połowa krzywej epoki I.
const AGE_II_STRUCTURE_FROM := 11
## Tło załogi epoki II: garnizon zamku epoki I o tej randze (bez jednostek specjalnych).
const AGE_II_BASE_RANK := 10
const ROMAN: Array[String] = ["I", "II", "III", "IV", "V", "VI", "VII", "VIII", "IX", "X"]
const NAMES: Array[String] = [
	# epoka I
	"Gródek", "Bobrowa Wola", "Lisi Jar", "Kamienny Bród", "Wilcze Doły",
	"Sokola Góra", "Mszany Gród", "Zbójecki Gród", "Bielsko Stare", "Czarny Las",
	"Dębowe Wzgórze", "Jastrzębiec", "Krucza Skała", "Niedźwiedzi Kąt", "Orle Gniazdo",
	"Żelazny Bród", "Wronia Wieża", "Turzy Róg", "Smocza Jama", "Gród Pięciu Wież",
	# epoka II
	"Brzozowy Gród", "Kozi Gród", "Sowia Góra", "Głęboki Rów", "Jelenia Struga",
	"Grodzisko Nowe", "Mglisty Bród", "Bursztynowa Wola", "Kamienica", "Ognisty Wał",
	"Rogaty Gród", "Srebrny Potok", "Dzicza Skała", "Strażnica Graniczna", "Książęcy Gród",
	"Wysoki Wał", "Gród nad Wisłą", "Biały Gród", "Złota Brama", "Stołeczny Gród",
]

const K := BuildingTypes.Kind
const U := UnitTypes.Unit


## Seed zamku `i`: ten sam dla każdego gracza.
static func seed_of(i: int) -> int:
	return PixelCanvas.hash2(i, 26, 0xb07c) & 0x7fffffff


## Epoka zamku `i` (0 = I).
static func age_of(i: int) -> int:
	return clampi(i, 0, COUNT - 1) / COUNT_PER_AGE


## Ranga zamku w jego epoce (0–19): trudność w epoce.
static func rank_of(i: int) -> int:
	return clampi(i, 0, COUNT - 1) % COUNT_PER_AGE


## Pierwszy zamek epoki `age`.
static func first_of_age(age: int) -> int:
	return clampi(age, 0, AGES - 1) * COUNT_PER_AGE


## „5. Lisi Jar”: ranga w epoce i nazwa.
static func title(i: int) -> String:
	return "%d. %s" % [rank_of(i) + 1, NAMES[clampi(i, 0, COUNT - 1)]]


static func age_name(age: int) -> String:
	return ROMAN[clampi(age, 0, ROMAN.size() - 1)]


## Siła konstrukcji zamku `i` (0–19): poziom budynków, wieże, wały i budynki rekrutacji. W epoce I
## to ranga, w epoce II od połowy krzywej: 11 + ranga/2, najwyżej 19.
static func structure_of(i: int) -> int:
	if age_of(i) == 0:
		return rank_of(i)
	return mini(AGE_II_STRUCTURE_FROM + rank_of(i) / 2, MAX_STRUCTURE)


## Umocnienie wewnętrznego pierścienia przy sile `s`: 1, 3, 5, 7 i 9 to grody na wale ziemnym, reszta
## ma palisadę (od siły 10 z zewnętrznym wałem). Siła 0 zostaje najłatwiejsza. TYMCZASOWE.
static func inner_wall_of(s: int) -> int:
	return K.RAMPART if s < OUTER_WALL_FROM and s % 2 == 1 else K.PALISADE


## Poziom budynków przy sile `s`: 1 dla sił 0–3, potem co 4 o jeden wyżej, do 5.
static func level_of(s: int) -> int:
	return clampi(1 + s / 4, 1, BuildingTypes.MAX_LEVEL)


## Wieże poza palisadą przy sile `s`: od siły 2, najwyżej 4.
static func towers_of(s: int) -> int:
	return mini(4, (s + 1) / 3)


## Budynki rekrutacji przy sile `s` (#26): Koszary, Strzelnica, Dom drużyny, Stajnia.
static func recruit_buildings(s: int) -> Array[int]:
	var out: Array[int] = []
	if s >= 3:
		out.append(K.BARRACKS)
	if s >= 6:
		out.append(K.ARCHERY_RANGE)
	if s >= 9:
		out.append(K.WARBAND_HOUSE)
	if s >= 12:
		out.append(K.STABLE)
	return out


## Załoga zamku `i`: oddziały [rodzaj, liczba] jak w Battle.create_squads. Zamek 1 to 4 Chłopów,
## kolejne w epoce I dokładają klasy (lekka, strzelecka, ciężka, szybka, specjalna). Epoka II ma tło
## z piechoty epoki I (garnizon rangi AGE_II_BASE_RANK) i z rangą dokłada jednostki epoki II.
static func defenders(i: int) -> Array:
	if age_of(i) == 0:
		return _age_one_defenders(rank_of(i))
	var r := rank_of(i)
	var out := _age_one_defenders(AGE_II_BASE_RANK)
	# wiersz: [jednostka, od rangi, przesunięcie, najwięcej]: liczba = min(r + przesunięcie, najwięcej)
	var rows: Array = [
		[U.SPEARMAN, 0, 4, 14], [U.GAMBESON_WARRIOR, 3, 1, 14], [U.REFLEX_ARCHER, 6, -3, 14],
		[U.LANCER, 10, -8, 11],
	]
	for row: Array in rows:
		if r >= int(row[1]):
			out.append([int(row[0]), mini(r + int(row[2]), int(row[3]))])
	return out


## Załoga epoki I przy randze `r` (zamki 1–15 jak przed #230; od rangi 15 rosną Tarczownicy i Jeźdźcy).
static func _age_one_defenders(r: int) -> Array:
	var out: Array = [[U.PEASANT, mini(4 + r, 12)]]
	# wiersz: [jednostka, od rangi, przesunięcie, najwięcej]: liczba = min(r + przesunięcie, najwięcej)
	var rows: Array = [
		[U.AXE_WARRIOR, 1, 2, 12], [U.ARCHER, 2, 1, 12], [U.JAVELINEER, 4, -2, 10],
		[U.SHIELDBEARER, 7, -5, 14], [U.RIDER, 10, -8, 11], [U.FIRE_RAISER, 13, -11, 3],
	]
	for row: Array in rows:
		if r >= int(row[1]):
			out.append([int(row[0]), mini(r + int(row[2]), int(row[3]))])
	return out


## Liczba obrońców zamku `i`.
static func defender_count(i: int) -> int:
	var n := 0
	for d: Array in defenders(i):
		n += int(d[1])
	return n


static func generate(i: int) -> BotCastle:
	var bot := BotCastle.generate(seed_of(i), structure_of(i))
	bot.index = i
	bot.defenders = defenders(i)
	return bot


## Najwyższy dostępny zamek, gdy gracz zdobył `beaten` zamków po kolei.
static func last_unlocked(beaten: int) -> int:
	return clampi(beaten, 0, COUNT - 1)


static func is_unlocked(i: int, beaten: int) -> bool:
	return i >= 0 and i <= last_unlocked(beaten)


static func is_beaten(i: int, beaten: int) -> bool:
	return i < beaten


## Cel Wyprawy przy postępie `beaten`: `target`, gdy jest odblokowany, inaczej najwyższy odblokowany
## zamek (np. po wyrównaniu licznika z serwerem, #386).
static func unlocked_target(target: int, beaten: int) -> int:
	return target if is_unlocked(target, beaten) else last_unlocked(beaten)


## Krótki opis załogi, np. „5 Chłop, 2 Topornik, 1 Łucznik”, od najliczniejszych.
static func defenders_text(i: int) -> String:
	var parts: Array[String] = []
	for d: Array in defenders(i):
		parts.append("%d %s" % [int(d[1]), UnitTypes.SHORT_NAMES[int(d[0])]])
	return ", ".join(parts)
