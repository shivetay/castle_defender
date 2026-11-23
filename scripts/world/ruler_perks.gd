class_name RulerPerks
extends RefCounted
## Perki władcy (#32, notatka Władca i generałowie): gracz jako władca zamku ma SLOTS miejsc na perk
## (w MVP 1) i wybiera jeden z 6 perków MVP. Perk działa na cały zamek: w ataku, w obronie
## i w gospodarce. Perk z wyższej epoki da się wybrać dopiero w tej epoce (Łupieżca i Budowniczy od II).
##
## Zmiana perka jest darmowa raz na COOLDOWN_MS (24 h), a każda kolejna w tym czasie kosztuje
## CHANGE_GOLD złota. Serwer przy zapisie zamku sprawdza to samo swoim zegarem (migracja
## `ruler_perk`): perk spoza gry albo z wyższej epoki odpada, a płatna zmiana bez pokrycia w złocie
## (jak przy generałach) zostaje cofnięta. Do PvP trafia więc tylko perk przyjęty przez serwer.
##
## Gdzie działają: Zdobywca i Łupieżca u atakującego (Battle.set_ruler_perk, łup z PvP liczy też
## `end_attack`), Gospodarz grodu i Ukochany władca u obrońcy (Battle.create_squads z
## BuildGrid.ruler_perk), Gospodarny w produkcji (Economy.rates), Budowniczy w czasie budowy (BuildQueue).
## Koszt zmiany jest TYMCZASOWY (notatka nie podaje kwoty).

enum Perk { NONE = -1, CONQUEROR, LOOTER, STEWARD, THRIFTY, BUILDER, BELOVED }
enum Result { OK, UNKNOWN, LOCKED, SAME, NO_GOLD }

const NAMES: Array[String] = ["Zdobywca", "Łupieżca", "Gospodarz grodu", "Gospodarny", "Budowniczy",
		"Ukochany władca"]
const CATEGORIES: Array[String] = ["atak", "atak", "obrona", "gospodarka", "gospodarka", "morale"]
const DESC: Array[String] = ["+10% obrażeń w ataku", "+15% łupu z PvP", "Budynki +10% wytrz.",
		"+10% produkcji", "Budowa -10% czasu", "+10 morale załogi"]
## Od której epoki perk da się wybrać (0 = I), z notatki.
const PERK_AGE: Array[int] = [0, 1, 0, 0, 1, 0]

## Miejsca na perki w MVP (2. od epoki III i 3. od epoki V dojdą później).
const SLOTS := 1
## Ile trwa okno darmowej zmiany.
const COOLDOWN_MS := 24 * 3600 * 1000
## Złoto za każdą kolejną zmianę w oknie (TYMCZASOWE).
const CHANGE_GOLD := 50

# --- Liczby do bitwy i gospodarki (z notatki) --------------------------------------------------------
const CONQUEROR_DAMAGE_PERCENT := 110
const LOOTER_LOOT_PERCENT := 115
const STEWARD_HP_PERCENT := 110
const THRIFTY_PRODUCTION_BONUS := 10
const BUILDER_TIME_PERCENT := 90
const BELOVED_MORALE := 10

const R := EconomyConfig.Res

const MESSAGES: Array[String] = ["", "Nie ma takiego perka", "Ten perk od późniejszej epoki",
		"Ten perk już działa", "Brakuje złota"]

## Wybrany perk albo Perk.NONE.
var perk: int = Perk.NONE
## Chwila ostatniej darmowej zmiany (unix, ms); 0, gdy jeszcze żadnej nie było.
var free_ms := 0


static func count() -> int:
	return NAMES.size()


static func is_known(p: int) -> bool:
	return p >= 0 and p < count()


## Perk `p` w zamku z epoki `age` albo Perk.NONE (nieznany albo z wyższej epoki). Tak samo czyta kopię
## zamku z serwera, więc obcy zamek nie wstawi do bitwy perka spoza gry.
static func checked(p: int, age: int) -> int:
	return p if is_known(p) and PERK_AGE[p] <= age else Perk.NONE


## Perki do wyboru w epoce `age`, w kolejności z notatki.
static func available(age: int) -> Array[int]:
	var out: Array[int] = []
	for p in count():
		if PERK_AGE[p] <= age:
			out.append(p)
	return out


static func perk_name(p: int) -> String:
	return NAMES[p] if is_known(p) else "brak"


## Premia do produkcji każdego surowca w punktach procentowych (Economy.rates).
static func production_bonus(p: int) -> int:
	return THRIFTY_PRODUCTION_BONUS if p == Perk.THRIFTY else 0


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


## Czy zmiana w chwili `now_ms` jest darmowa (pierwsza w oknie 24 h). Cofnięty zegar (`now_ms` przed
## `free_ms`) nie daje darmowej zmiany (review #276): okno trwa, aż minie 24 h od zapisanej chwili.
func is_free_change(now_ms: int) -> bool:
	return free_ms <= 0 or now_ms - free_ms >= COOLDOWN_MS


## Złoto za zmianę w chwili `now_ms`: 0 albo CHANGE_GOLD.
func change_gold(now_ms: int) -> int:
	return 0 if is_free_change(now_ms) else CHANGE_GOLD


## Kiedy znowu będzie darmowa zmiana (unix, ms); 0, gdy już jest.
func next_free_ms(now_ms: int) -> int:
	return 0 if is_free_change(now_ms) else free_ms + COOLDOWN_MS


static func change_cost(gold: int) -> Array[int]:
	var cost: Array[int] = []
	cost.resize(EconomyConfig.count())
	cost.fill(0)
	cost[R.GOLD] = gold
	return cost


## Czemu nie da się wybrać perka `p` (Result), albo OK.
func choose_problem(p: int, age: int, economy: Economy, now_ms: int) -> int:
	if not is_known(p):
		return Result.UNKNOWN
	if PERK_AGE[p] > age:
		return Result.LOCKED
	if p == perk:
		return Result.SAME
	if not economy.can_afford(change_cost(change_gold(now_ms))):
		return Result.NO_GOLD
	return Result.OK


## Wybiera perk `p`: darmowa zmiana otwiera nowe okno 24 h, płatna zabiera CHANGE_GOLD złota.
func choose(p: int, age: int, economy: Economy, now_ms: int) -> int:
	var problem := choose_problem(p, age, economy, now_ms)
	if problem != Result.OK:
		return problem
	if is_free_change(now_ms):
		free_ms = now_ms
	else:
		economy.spend(change_cost(CHANGE_GOLD))
	perk = p
	return Result.OK


## Perk, który działa w zamku z epoki `age` (Perk.NONE, gdy wybrany jest z wyższej epoki).
func active(age: int) -> int:
	return checked(perk, age)


func save_data() -> Dictionary:
	return {"perk": perk, "free_ms": free_ms}


## Odczyt z zapisu albo z kopii zamku z serwera. Zwraca liczbę pominiętych wpisów (0 albo 1).
func load_data(d: Dictionary) -> int:
	perk = Perk.NONE
	free_ms = 0
	if d.is_empty():
		return 0
	var p := Generals._int_of(d.get("perk"), Perk.NONE)
	free_ms = maxi(0, Generals._int_of(d.get("free_ms"), 0))
	if p == Perk.NONE or is_known(p):
		perk = p
		return 0
	return 1
