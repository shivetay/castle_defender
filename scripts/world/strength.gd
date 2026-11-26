class_name Strength
extends RefCounted
## Wskaźniki siły armii i obrony (#263): jedna liczba, która pomaga ocenić gotowość bojową zamku.
## To podpowiedź w UI, nie ranking (#27) i nie wejście do bitwy ani doboru przeciwnika.
##
## Decyzje właścicielki (23.11.2026): wskaźniki widać na własnym zamku (ekran Wojsko i ekran Obrona),
## siła jednostki wynika z jej HP i ataku, a do obrony wchodzą też umocnienia (wał, palisada, brama,
## wieża). Wszystkie wagi są TYMCZASOWE (TBD, balans właścicielki). Perki, technologie i generałowie
## jeszcze nie zmieniają wskaźnika (TBD).
##
## Rachunek jest w liczbach całkowitych i zależy tylko od danych zamku, więc te same dane dają zawsze
## tę samą liczbę, w PvE i w PvP.

const K := BuildingTypes.Kind

## Siła jednostki: (HP + ATTACK_WEIGHT × atak) / UNIT_DIVISOR. Jednostki bez ataku (Tropiciel, Wóz)
## mają 0, bo nie walczą. TYMCZASOWE.
const ATTACK_WEIGHT := 5
const UNIT_DIVISOR := 10

## Siła pułapki (TrapConfig.Kind), mniej więcej obrażenia, jakie zadaje, przez UNIT_DIVISOR:
## Wilczy dół 60, Kolczatka 8 s × 5, Kłody 40, Płonące strzały (premia strzelców, bez własnych
## obrażeń) jak Kłody, Smoła 50 i podpalenie 6 s × 4. TYMCZASOWE.
const TRAP_POWER: Array[int] = [6, 4, 4, 4, 7]

## Umocnienia liczone do siły obrony. Każdy odcinek ma (wytrzymałość na swoim poziomie) / FORT_HP_DIVISOR,
## a wieża dodatkowo TOWER_ATTACK_WEIGHT × BattleConfig.TOWER_ATTACK (strzela). Dwór i donżon to cele
## ataku, nie obrona, więc ich tu nie ma. TYMCZASOWE.
const FORTS: Array[int] = [K.RAMPART, K.PALISADE, K.GATE, K.TOWER]
const FORT_HP_DIVISOR := 50
const TOWER_ATTACK_WEIGHT := 3


## Siła jednej jednostki rodzaju `unit` (UnitTypes.Unit); 0 dla nieznanego rodzaju.
static func unit_power(unit: int, hp_percent: int = 100) -> int:
	if unit < 0 or unit >= UnitTypes.count() or UnitTypes.attack(unit) <= 0:
		return 0
	@warning_ignore("integer_division")
	var hp := UnitTypes.hp(unit) * hp_percent / 100
	@warning_ignore("integer_division")
	return (hp + ATTACK_WEIGHT * UnitTypes.attack(unit)) / UNIT_DIVISOR


## Siła armii: suma sił wyszkolonych jednostek ze wszystkich oddziałów (bez tych w szkoleniu).
static func army(r: Recruitment) -> int:
	if r == null:
		return 0
	var total := 0
	for s in r.squads:
		total += s.count * unit_power(s.unit)
	return total


## Siła załogi w obronie: cała armia, a oddziały w garnizonie Dworu (#81) liczą się z premią
## wytrzymałości, jak w bitwie (BattleConfig.GARRISON_HP_PERCENT).
static func crew(r: Recruitment, plan: DefensePlan) -> int:
	if r == null:
		return 0
	var total := 0
	for s in r.squads:
		var hp_percent := BattleConfig.GARRISON_HP_PERCENT if plan != null and plan.in_garrison(s.id) else 100
		total += s.count * unit_power(s.unit, hp_percent)
	return total


static func trap_power(kind: int) -> int:
	return TRAP_POWER[kind] if kind >= 0 and kind < TRAP_POWER.size() else 0


## Siła pułapek postawionych w układzie obrony.
static func traps(plan: DefensePlan) -> int:
	if plan == null:
		return 0
	var total := 0
	for t in plan.traps:
		total += trap_power(t.kind)
	return total


## Siła jednego gotowego odcinka umocnień rodzaju `kind` na poziomie `level` (0 dla innych budynków
## i placu budowy).
static func fort_power(kind: int, level: int) -> int:
	if level < 1 or not FORTS.has(kind):
		return 0
	@warning_ignore("integer_division")
	var power := BattleConfig.building_hp(kind, level) / FORT_HP_DIVISOR
	if kind == K.TOWER:
		power += TOWER_ATTACK_WEIGHT * BattleConfig.TOWER_ATTACK
	return power


## Siła umocnień zamku: suma po gotowych odcinkach wału, palisady, bramach i wieżach.
static func forts(grid: BuildGrid) -> int:
	if grid == null:
		return 0
	var total := 0
	for id: int in grid.kinds:
		total += fort_power(grid.kinds[id], int(grid.levels.get(id, 0)))
	return total


## Siła obrony: załoga, pułapki i umocnienia.
static func defense(r: Recruitment, plan: DefensePlan, grid: BuildGrid) -> int:
	return crew(r, plan) + traps(plan) + forts(grid)


## Siła obrony zamku-bota (#310), np. na karcie celu: załoga (BotCastle.defenders) i umocnienia jego
## siatki. Bot nie ma pułapek ani garnizonu Dworu.
static func bot_defense(bot: BotCastle) -> int:
	if bot == null:
		return 0
	var total := forts(bot.grid)
	for d: Array in bot.defenders:
		total += int(d[1]) * unit_power(int(d[0]))
	return total
