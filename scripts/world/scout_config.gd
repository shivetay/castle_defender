class_name ScoutConfig
extends RefCounted
## Liczby zwiadu (#28) w jednym miejscu: długości misji, odsłonięcie, koszt i szanse wyników.
## Wszystkie są TYMCZASOWE (decyzja właścicielki: balans później), notatka ich nie podaje.
## S1 Tropiciele daje bazowe 20% zamku przy krótkim zwiadzie, S3 Dom zwiadowców +10% zasięgu.

const U := UnitTypes.Unit
const R := EconomyConfig.Res

## Wynik misji: wszyscy wrócili z pełnym raportem; część zginęła, reszta wróciła z połową danych;
## wykryci uciekli bez danych; wszyscy zginęli.
enum Outcome { SUCCESS, PARTIAL, ESCAPED, FAILED }

const OUTCOME_NAMES: Array[String] = ["sukces", "częściowy", "wykryci", "porażka"]

## Jednostki zwiadu (w kolejności wysyłania): Tropiciel z S1, Zwiadowca z S3.
const SCOUT_UNITS: Array[int] = [U.TRACKER, U.SCOUT]
## Najwięcej zwiadowców w jednej misji.
const MAX_SCOUTS := 5

## Długości misji: krótki, średni i długi zwiad (sekundy) i ile procent zamku odsłaniają.
const DURATION_S: Array[int] = [2 * 60, 10 * 60, 30 * 60]
const DURATION_LABELS: Array[String] = ["2 min", "10 min", "30 min"]
const REVEAL_PERCENT: Array[int] = [20, 35, 50]
## Każdy zwiadowca ponad pierwszego: +5% zamku.
const EXTRA_SCOUT_PERCENT := 5
## S3 Dom zwiadowców: zwiad +10% zasięgu.
const S3_PERCENT := 10
const MAX_PERCENT := 80

## Koszt jednego zwiadowcy w misji, w kolejności EconomyConfig.Res (drewno, kamień, żywność, złoto).
const COST_PER_SCOUT: Array[int] = [0, 0, 10, 10]

## Szanse wyników w procentach (indeks = Outcome); suma 100.
const CHANCES: Array[int] = [60, 20, 10, 10]
## S3: +10 punktów sukcesu, zabrane z porażki i wykrycia po połowie.
const S3_SUCCESS_BONUS := 10
## Wieża sygnałowa celu (S2) wykrywa zwiad: −20 punktów sukcesu, które przechodzą na wykrycie.
## Na razie liczy się tylko na serwerze (zwiad na gracza); zamki-boty nie mają Wieży sygnałowej.
const SIGNAL_TOWER_PENALTY := 20


static func duration_count() -> int:
	return DURATION_S.size()


static func duration_ms(duration: int) -> int:
	return DURATION_S[clampi(duration, 0, DURATION_S.size() - 1)] * 1000


static func is_scout(unit: int) -> bool:
	return SCOUT_UNITS.has(unit)


## Koszt misji z `scouts` zwiadowcami.
static func cost(scouts: int) -> Array[int]:
	var out: Array[int] = []
	for amount in COST_PER_SCOUT:
		out.append(amount * maxi(0, scouts))
	return out


## Procent zamku odsłonięty przez udaną misję: długość, liczba zwiadowców i S3.
static func reveal_percent(duration: int, scouts: int, s3: bool) -> int:
	var p := REVEAL_PERCENT[clampi(duration, 0, REVEAL_PERCENT.size() - 1)]
	p += EXTRA_SCOUT_PERCENT * clampi(scouts - 1, 0, MAX_SCOUTS - 1)
	if s3:
		p += S3_PERCENT
	return clampi(p, 0, MAX_PERCENT)


## Szanse wyników (indeks = Outcome) przy S3 i liczbie Wież sygnałowych celu (`towers`, 0 lub więcej).
static func chances(s3: bool, towers: int) -> Array[int]:
	var c: Array[int] = []
	c.assign(CHANCES)
	if s3:
		@warning_ignore("integer_division")
		var half := S3_SUCCESS_BONUS / 2
		var from_failed := mini(half, c[Outcome.FAILED])
		var from_escaped := mini(S3_SUCCESS_BONUS - from_failed, c[Outcome.ESCAPED])
		c[Outcome.FAILED] -= from_failed
		c[Outcome.ESCAPED] -= from_escaped
		c[Outcome.SUCCESS] += from_failed + from_escaped
	if towers > 0:
		var moved := mini(SIGNAL_TOWER_PENALTY, c[Outcome.SUCCESS])
		c[Outcome.SUCCESS] -= moved
		c[Outcome.ESCAPED] += moved
	return c


## Wynik dla rzutu `roll` (0–99) przy szansach `c`.
static func outcome_for_roll(roll: int, c: Array[int]) -> int:
	var acc := 0
	for i in c.size():
		acc += c[i]
		if roll < acc:
			return i
	return Outcome.FAILED


## Ilu z `sent` zwiadowców wraca przy wyniku `outcome`. Częściowy: wraca połowa (w górę), ale
## przy jednym zwiadowcy ten jeden wraca.
static func survivors(outcome: int, sent: int) -> int:
	match outcome:
		Outcome.SUCCESS, Outcome.ESCAPED:
			return sent
		Outcome.PARTIAL:
			@warning_ignore("integer_division")
			return (sent + 1) / 2
	return 0


## Procent zamku w raporcie przy wyniku `outcome` (częściowy: połowa).
static func report_percent(outcome: int, full_percent: int) -> int:
	match outcome:
		Outcome.SUCCESS:
			return full_percent
		Outcome.PARTIAL:
			@warning_ignore("integer_division")
			return full_percent / 2
	return 0
