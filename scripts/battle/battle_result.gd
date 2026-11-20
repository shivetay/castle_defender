class_name BattleResult
extends RefCounted
## Wynik ataku (#99): procent zniszczeń, 0–3 gwiazdki i łup. Liczony wyłącznie ze stanu skończonej
## bitwy (Battle) i z listy zamków (BotRoster), w liczbach całkowitych, więc atakujący, powtórka
## i serwer (etap 9) dostają ten sam wynik. Budynki obrońcy nie przepadają: bitwa działa na kopii
## (Battle.structures), a siatka zamku zostaje nietknięta, więc po bitwie zamek jest w pełnym stanie.
##
## Gwiazdki:
## - brama zdobyta: padła brama albo atakujący wszedł na mur po drabinie,
## - połowa zamku: zniszczone co najmniej STAR_PERCENT procent budynków,
## - donżon: zburzony albo zdobyty (to też koniec bitwy i wygrana, #120).
## Procent liczy budynki bez odcinków wału i palisady (jest ich wiele i zawyżałyby wynik).
##
## Łup z zamku-bota, tylko po wygranej (decyzja właścicielki, review #194): skarbiec rośnie z numerem
## zamku, magazyn chroni PROTECTED_PERCENT, a z reszty atakujący bierze do LOOT_PERCENT, w proporcji
## do procentu zniszczeń, liczonego co najmniej jak WIN_LOOT_PERCENT (nie więcej niż 50). Ponowny atak na zdobyty już
## zamek daje REPEAT_PERCENT łupu. Ranking (#27) dojdzie z PvP. Liczby TYMCZASOWE.
##
## Capacity (#25): łup razem najwyżej tyle, ile uniosą ocalali (UnitTypes.CARRY), więc więcej jednostek
## wracających z grabieży daje wyższy limit, a ocalały Wóz (#235) podnosi go najbardziej. Łup z zamku gracza liczy się tak samo, z jego zapasów
## z kopii na serwerze. Te same limity sprawdza `finish_attack` (`public.end_attack`), który odrzuca
## zawyżony łup; tarczę obrońcy (SHIELD_PERCENT) ustawia tylko serwer.
@warning_ignore_start("integer_division")

const STAR_PERCENT := 50
const PROTECTED_PERCENT := 50
const LOOT_PERCENT := 20
## Wygrana (szybki upadek donżonu kończy bitwę) daje łup co najmniej jak przy tylu procentach zniszczeń.
const WIN_LOOT_PERCENT := 50
const REPEAT_PERCENT := 50
## Skarbiec zamku `i`: drewno, kamień i żywność BASE + STEP × i, złoto GOLD_BASE + GOLD_STEP × i.
const STASH_BASE := 1000
const STASH_STEP := 500
const GOLD_BASE := 20
const GOLD_STEP := 10
## Tarcza obrońcy-gracza od tylu procent zniszczeń, na SHIELD_HOURS godzin (#25, ustawia ją serwer).
const SHIELD_PERCENT := 30
const SHIELD_HOURS := 8

enum Star { GATE, HALF, KEEP }
const STAR_NAMES: Array[String] = ["Brama zdobyta", "Połowa zamku", "Donżon"]

var won := false
var percent := 0
var stars: Array[bool] = [false, false, false]
## Łup w kolejności EconomyConfig.Res (przed limitem magazynu gracza).
var loot: Array[int] = []
var destroyed := 0
var total := 0


static func of(b: Battle) -> BattleResult:
	var r := BattleResult.new()
	r.won = b.winner == Battle.Winner.ATTACKER
	var gate := false
	for id: int in b.structures:
		var s: Battle.Structure = b.structures[id]
		if s.kind == BuildingTypes.Kind.GATE and s.hp <= 0:
			gate = true
		if BuildingTypes.is_wall(s.kind):
			continue
		r.total += 1
		if s.hp <= 0:
			r.destroyed += 1
	for f in b.fighters:
		if f.side == Battle.Side.ATTACKER and f.climbed:
			gate = true
	r.percent = r.destroyed * 100 / r.total if r.total > 0 else 0
	r.stars = [gate, r.percent >= STAR_PERCENT, r.won]
	r.loot.resize(EconomyConfig.count())
	r.loot.fill(0)
	return r


func star_count() -> int:
	var n := 0
	for s in stars:
		if s:
			n += 1
	return n


## Skarbiec zamku-bota `i` w kolejności EconomyConfig.Res.
static func stash(i: int) -> Array[int]:
	var out: Array[int] = []
	for res in EconomyConfig.count():
		if res == EconomyConfig.Res.GOLD:
			out.append(GOLD_BASE + GOLD_STEP * i)
		else:
			out.append(STASH_BASE + STASH_STEP * i)
	return out


## Procent zniszczeń, od którego liczy się łup: po wygranej co najmniej WIN_LOOT_PERCENT, po przegranej 0.
func loot_percent() -> int:
	return maxi(percent, WIN_LOOT_PERCENT) if won else 0


## Liczy łup z zamku `i`: z niechronionej części skarbca LOOT_PERCENT × loot_percent(), więc przegrana
## nic nie daje; `repeat` (zamek był już zdobyty) daje REPEAT_PERCENT tego.
func compute_loot(i: int, repeat: bool) -> void:
	_loot_from(stash(i), repeat)


## Łup z zamku gracza (#25): `amounts` to jego zapasy (z kopii zamku z `start_attack`), w kolejności
## EconomyConfig.Res. Bez zniżki za powtórkę (ten sam cel raz na 24 godziny pilnuje serwer).
func compute_player_loot(amounts: Array) -> void:
	var s: Array[int] = []
	for res in EconomyConfig.count():
		s.append(clampi(int(amounts[res]), 0, 10000000) if res < amounts.size() else 0)
	_loot_from(s, false)


func _loot_from(s: Array[int], repeat: bool) -> void:
	loot.clear()
	for res in s.size():
		var open := s[res] * (100 - PROTECTED_PERCENT) / 100
		var amount := open * LOOT_PERCENT / 100 * loot_percent() / 100
		if repeat:
			amount = amount * REPEAT_PERCENT / 100
		loot.append(amount)


## Szacowany łup na karcie celu (#24): wygrana z najmniejszym procentem łupu (WIN_LOOT_PERCENT),
## bez zniżki za powtórkę. Dla zamku-bota ze skarbca `stash(i)`.
static func estimate_bot_loot(i: int) -> Array[int]:
	var r := BattleResult.new()
	r.won = true
	r.compute_loot(i, false)
	return r.loot


## Procent zapasów gracza, który karta celu pokazuje jako szacowany łup (#24): niechroniona część
## × LOOT_PERCENT × WIN_LOOT_PERCENT, czyli 5. Ten sam procent liczy serwer w `match_targets`
## (migracja `*_match_targets.sql`, znacznik LOOT_ESTIMATE_PERCENT), test pilnuje zgodności.
static func loot_estimate_percent() -> int:
	return (100 - PROTECTED_PERCENT) * LOOT_PERCENT * WIN_LOOT_PERCENT / 10000


## Capacity łupu armii (#25): `army` to oddziały [rodzaj, liczba] z bitwy, `alive` ocaleli w każdym
## z nich (Battle.survivors). Brak wpisu w `alive` liczy się jak 0 ocalałych.
static func carry_capacity(army: Array, alive: Array[int]) -> int:
	var total := 0
	for i in mini(army.size(), alive.size()):
		var squad := army[i] as Array
		total += clampi(alive[i], 0, int(squad[1])) * UnitTypes.carry(int(squad[0]))
	return total


## Capacity łupu armii `army` [rodzaj, liczba], gdy wszyscy wrócą (plan ataku, #235): górna granica
## tego, co policzy carry_capacity po bitwie.
static func army_capacity(army: Array) -> int:
	var alive: Array[int] = []
	for sq: Array in army:
		alive.append(int(sq[1]))
	return carry_capacity(army, alive)


## Ile z capacity armii `army` dają Wozy (#235).
static func wagon_capacity(army: Array) -> int:
	var total := 0
	for sq: Array in army:
		if int(sq[0]) == UnitTypes.Unit.WAGON:
			total += maxi(0, int(sq[1])) * UnitTypes.carry(UnitTypes.Unit.WAGON)
	return total


## Przycina łup do `capacity`: przy nadmiarze każdy surowiec maleje w tej samej proporcji (w dół,
## w liczbach całkowitych), więc suma nie przekracza capacity, a wynik zależy tylko od danych.
func limit_to_capacity(capacity: int) -> void:
	var total := 0
	for amount in loot:
		total += amount
	if total <= capacity:
		return
	for res in loot.size():
		loot[res] = loot[res] * maxi(0, capacity) / total


## Wynik dla `finish_attack` (#25): dokładnie pola, które sprawdza serwer.
func to_server() -> Dictionary:
	return {"won": won, "percent": percent, "stars": stars.duplicate()}


## Dodaje łup do magazynu gracza. Zwraca, ile faktycznie weszło (pełny magazyn nie przyjmie nadmiaru).
func apply_loot(economy: Economy) -> Array[int]:
	var got: Array[int] = []
	for res in loot.size():
		got.append(economy.add(res, loot[res]))
	return got
