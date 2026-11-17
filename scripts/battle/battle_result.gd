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
## zamek daje REPEAT_PERCENT łupu. Ranking (#27) i tarcza obrońcy (#25) dojdą z PvP. Liczby TYMCZASOWE.
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
	var s := stash(i)
	loot.clear()
	for res in s.size():
		var open := s[res] * (100 - PROTECTED_PERCENT) / 100
		var amount := open * LOOT_PERCENT / 100 * loot_percent() / 100
		if repeat:
			amount = amount * REPEAT_PERCENT / 100
		loot.append(amount)


## Dodaje łup do magazynu gracza. Zwraca, ile faktycznie weszło (pełny magazyn nie przyjmie nadmiaru).
func apply_loot(economy: Economy) -> Array[int]:
	var got: Array[int] = []
	for res in loot.size():
		got.append(economy.add(res, loot[res]))
	return got
