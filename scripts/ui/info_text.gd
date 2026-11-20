class_name InfoText
extends RefCounted
## Treść okienek z informacją (po teście na telefonie: gracz nie wiedział, skąd biorą się surowce
## i gdzie podnieść limit armii). Same linie tekstu liczone z danych gry, bez rysowania (InfoPopup),
## więc da się je testować bez ekranu.

const LOOT_LINE := "Też: łup z Wypraw i nagrody za fale Oblężenia"


## Okienko surowca `res`: zapas i magazyn, produkcja na godzinę z rozbiciem (gród, budynki, badania),
## kiedy magazyn się zapełni, skąd jest pojemność (Dwór i Magazyny) i jak zdobyć więcej.
## Przy żywności `upkeep` to utrzymanie armii (#214): odejmuje się od produkcji, a przy ujemnym
## bilansie okienko mówi, kiedy zapas się skończy i że potem armia zacznie odchodzić.
static func resource(res: int, grid: BuildGrid, research: Research, amounts: Array[int],
		upkeep: int = 0) -> PackedStringArray:
	var out: PackedStringArray = []
	var have := amounts[res] if res < amounts.size() else 0
	var cap := Economy.capacities_for(grid)[res]
	if EconomyConfig.is_capped(res):
		out.append("Zapas: %d z %d (magazyn)" % [have, cap])
	else:
		out.append("Zapas: %d, bez limitu magazynu" % have)
	var army := upkeep if res == EconomyConfig.Res.FOOD else 0
	var rate := Economy.net_rates(grid, research, army)[res]
	out.append("Produkcja: %+d na godzinę" % rate)
	if EconomyConfig.BASE_PER_HOUR[res] > 0:
		out.append("- gród: +%d" % EconomyConfig.BASE_PER_HOUR[res])
	for kind: int in producers(res):
		var n := 0
		var sum := 0
		for id: int in grid.buildings:
			if grid.kinds[id] == kind and grid.levels[id] >= 1:
				var per_level: Array = (EconomyConfig.BUILDING_PRODUCTION[kind] as Array)[1]
				n += 1
				sum += int(per_level[clampi(grid.levels[id], 1, per_level.size()) - 1])
		if n > 0:
			out.append("- %s ×%d: +%d" % [BuildingTypes.NAMES[kind], n, sum])
	var percent := research.production_percent(res) if research != null else 100
	if percent != 100:
		out.append("- badania: %+d%%" % (percent - 100))
	if army > 0:
		out.append("- utrzymanie armii: -%d" % army)
	if rate < 0 and have <= 0:
		out.append("Brak żywności: z głodu odchodzą jednostki")
	elif rate < 0:
		@warning_ignore("integer_division")
		out.append("Zapas skończy się za %s" % Hud.format_time(have * Economy.MS_PER_HOUR / -rate))
		out.append("Potem z głodu odchodzą jednostki")
	if EconomyConfig.is_capped(res):
		var room := cap - have
		if room <= 0:
			out.append("Magazyn pełny: produkcja czeka, aż wydasz")
		elif rate > 0:
			@warning_ignore("integer_division")
			out.append("Magazyn pełny za %s" % Hud.format_time(room * Economy.MS_PER_HOUR / rate))
		out.append(storage_line(grid, res))
	var makers: PackedStringArray = []
	for kind: int in producers(res):
		makers.append(BuildingTypes.NAMES[kind])
	if not makers.is_empty():
		out.append("Więcej daje: %s (postaw albo ulepsz)" % ", ".join(makers))
	out.append(LOOT_LINE)
	return out


## Skąd jest pojemność surowca `res`: zapas Dworu i Magazyny razem
## (np. „Pojemność: Dwór 1000, Magazyn ×2: +1250”).
static func storage_line(grid: BuildGrid, res: int) -> String:
	var base := EconomyConfig.CAPACITY[res]
	var n := 0
	for id: int in grid.buildings:
		if grid.kinds[id] == BuildingTypes.Kind.WAREHOUSE and grid.levels[id] >= 1:
			n += 1
	if n == 0:
		return "Pojemność: Dwór %d; więcej mieści Magazyn" % base
	var extra := Economy.capacities_for(grid)[res] - base
	return "Pojemność: Dwór %d, Magazyn ×%d: +%d" % [base, n, extra]


## Budynki, które produkują surowiec `res` (EconomyConfig.BUILDING_PRODUCTION), w stałej kolejności.
static func producers(res: int) -> Array[int]:
	var out: Array[int] = []
	for kind: int in EconomyConfig.BUILDING_PRODUCTION:
		if int((EconomyConfig.BUILDING_PRODUCTION[kind] as Array)[0]) == res:
			out.append(kind)
	out.sort()
	return out


## Okienko limitu armii: ile jest, skąd bierze się limit (Dwór i każde Koszary) i jak go podnieść,
## a pod spodem drugi, niezależny limit: utrzymanie w żywności względem produkcji Ży (#214).
static func army(grid: BuildGrid, recruitment: Recruitment, research: Research = null) -> PackedStringArray:
	var out: PackedStringArray = []
	var limit := Recruitment.army_limit(grid)
	var used := recruitment.army_size() + recruitment.orders.size()
	out.append("W armii %d, w szkoleniu %d, limit %d" % [recruitment.army_size(), recruitment.orders.size(), limit])
	if used >= limit:
		out.append("Limit pełny: nikogo więcej nie wyszkolisz")
	out.append("Limit to suma:")
	out.append("- Dwór poz. %d: +%d" % [grid.manor_level(), RecruitmentConfig.ARMY_PER_MANOR_LEVEL * grid.manor_level()])
	# Koszary zliczone w jednej linii jak chaty w okienku surowca, więc okienko nie rośnie z ich liczbą
	var barracks := 0
	var levels := 0
	for id: int in grid.buildings:
		if grid.kinds[id] == BuildingTypes.Kind.BARRACKS and grid.levels[id] >= 1:
			barracks += 1
			levels += grid.levels[id]
	if barracks == 0:
		out.append("- Koszary: brak")
	else:
		out.append("- Koszary ×%d (poziomy razem %d): +%d" % [barracks, levels, RecruitmentConfig.ARMY_PER_BARRACKS_LEVEL * levels])
	out.append("Więcej miejsc: ulepsz Dwór (+%d za poziom)" % RecruitmentConfig.ARMY_PER_MANOR_LEVEL)
	out.append("albo postaw i ulepszaj Koszary (+%d za poziom)" % RecruitmentConfig.ARMY_PER_BARRACKS_LEVEL)
	out.append_array(upkeep(grid, recruitment, research))
	return out


## Linie utrzymania armii (#214): zużycie względem produkcji żywności, stan i jak podnieść limit.
static func upkeep(grid: BuildGrid, recruitment: Recruitment, research: Research = null) -> PackedStringArray:
	var out: PackedStringArray = []
	var used := recruitment.upkeep_used()
	var limit := Recruitment.upkeep_limit(grid, research)
	out.append("Utrzymanie: %d z %d Ży/h produkcji" % [used, limit])
	if used > limit:
		out.append("Za mało żywności: nie wyszkolisz nikogo, armia")
		out.append("je zapas, a gdy go zabraknie, odchodzi")
	elif used >= limit:
		out.append("Utrzymanie pełne: nikogo więcej nie wyszkolisz")
	out.append("Jednostka je %d Ży/h, konna %d, taran %d" % [UnitTypes.upkeep(UnitTypes.Unit.AXE_WARRIOR),
			UnitTypes.upkeep(UnitTypes.Unit.RIDER), UnitTypes.upkeep(UnitTypes.Unit.RAM)])
	var names: PackedStringArray = []
	for kind in producers(EconomyConfig.Res.FOOD):
		names.append(BuildingTypes.NAMES[kind])
	out.append("Więcej: postaw i ulepszaj %s" % ", ".join(names))
	return out
