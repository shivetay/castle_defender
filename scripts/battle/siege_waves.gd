class_name SiegeWaves
extends RefCounted
## Pięć fal samouczka PvE (#16): rosnąca trudność, cel to donżon. Liczby TYMCZASOWE.
## Każda fala to lista oddziałów [rodzaj, liczba] dla Battle.create_squads.

const U := UnitTypes.Unit
const R := EconomyConfig.Res

const WAVE_COUNT := 5

## Atakujący kolejnych fal (epoka I). Fala 1 uczy, że trzeba mieć załogę; fala 5 miesza klasy.
const WAVES: Array = [
	[[U.PEASANT, 4]],
	[[U.AXE_WARRIOR, 4], [U.JAVELINEER, 2]],
	[[U.AXE_WARRIOR, 5], [U.ARCHER, 3]],
	[[U.AXE_WARRIOR, 6], [U.ARCHER, 4], [U.SHIELDBEARER, 2]],
	[[U.AXE_WARRIOR, 8], [U.ARCHER, 5], [U.RIDER, 2], [U.FIRE_RAISER, 2]],
]

## Nagroda za obronę fali `index` (0..4): [drewno, kamień, żywność, złoto]. Złoto z PvE (#16).
const REWARDS: Array = [
	[40, 20, 40, 5],
	[60, 30, 50, 8],
	[80, 40, 60, 12],
	[100, 50, 80, 16],
	[140, 70, 100, 25],
]


## Oddziały atakujące fali `index` (kopia, żeby bitwa nie psuła stałych).
static func attackers(index: int) -> Array:
	var out: Array = []
	for sq: Array in WAVES[clampi(index, 0, WAVE_COUNT - 1)]:
		out.append([int(sq[0]), int(sq[1])])
	return out


## Suma liczebności atakujących w fali (do testów rosnącej trudności).
static func attacker_count(index: int) -> int:
	var n := 0
	for sq: Array in attackers(index):
		n += int(sq[1])
	return n


## Dopisuje nagrodę fali do gospodarki; zwraca skrócony opis „+40 Dr +5 Zł”.
static func grant_reward(economy: Economy, index: int) -> String:
	var reward: Array = REWARDS[clampi(index, 0, WAVE_COUNT - 1)]
	var parts: PackedStringArray = []
	for res in reward.size():
		var amount := int(reward[res])
		if amount <= 0:
			continue
		economy.add(res, amount)
		parts.append("+%d %s" % [amount, EconomyConfig.SHORT_NAMES[res]])
	return " ".join(parts)
