class_name PveWaves
extends RefCounted
## Samouczek PvE (#16): 5 fal oblężenia o rosnącej trudności. Przycisk Oblężenie startuje kolejną
## falę na zamku gracza: fala atakuje donżon (#120), a bronią go oddziały z rekrutacji (#89).
## Wygrana fala daje surowce i odblokowuje następną, a polegli obrońcy znikają z armii (#164).
## Skład fal i nagrody są TYMCZASOWE (decyzja właściciela).

const COUNT := 5
const U := UnitTypes.Unit
## Fale: lista oddziałów [rodzaj, liczba] jak w Battle.create_squads. Same jednostki epoki I.
## Każda jest wyraźnie słabsza niż EXPECTED_DEFENCE, bo atakujący ma przewagę zdobywania (10 s).
const WAVES: Array = [
	[[U.PEASANT, 3]],
	[[U.PEASANT, 5]],
	[[U.PEASANT, 3], [U.AXE_WARRIOR, 2]],
	[[U.AXE_WARRIOR, 4], [U.JAVELINEER, 3], [U.ARCHER, 2]],
	[[U.AXE_WARRIOR, 8], [U.JAVELINEER, 3], [U.ARCHER, 3], [U.RIDER, 1]],
]
## Obrona, którą gracz może mieć w danym momencie samouczka (wzorzec do testu balansu): na start
## Dwór 1 i Koszary 1 dają limit 12, a Chłop to jedyna jednostka bez badań; potem toporniki (A39),
## łucznicy (A44) i Dwór 2.
const EXPECTED_DEFENCE: Array = [
	[[U.PEASANT, 6]],
	[[U.PEASANT, 10]],
	[[U.PEASANT, 8], [U.AXE_WARRIOR, 4]],
	[[U.PEASANT, 4], [U.AXE_WARRIOR, 8], [U.ARCHER, 4]],
	[[U.AXE_WARRIOR, 10], [U.ARCHER, 6], [U.JAVELINEER, 6]],
]
## Nagroda za pierwszą wygraną falę: [drewno, kamień, żywność, złoto].
const REWARDS: Array = [
	[100, 50, 100, 10], [150, 100, 150, 15], [200, 150, 200, 20], [300, 200, 300, 30], [500, 300, 500, 50],
]


static func squads(wave: int) -> Array:
	return (WAVES[clampi(wave, 0, COUNT - 1)] as Array).duplicate(true)


static func reward(wave: int) -> Array[int]:
	var out: Array[int] = []
	out.assign(REWARDS[clampi(wave, 0, COUNT - 1)] as Array)
	return out


## Liczba jednostek w fali.
static func size(wave: int) -> int:
	var n := 0
	for sq: Array in squads(wave):
		n += int(sq[1])
	return n


## Seed bitwy fali: z seeda zamku i numeru fali, więc powtórka tej samej fali przebiega tak samo.
static func battle_seed(world_seed: int, wave: int) -> int:
	return PixelCanvas.hash2(world_seed, wave, 0x5ec6e) & 0x7fffffff
