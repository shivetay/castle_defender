class_name TutorialGoals
extends RefCounted
## Prowadzenie gracza do 5 fal samouczka (#185): krótka lista celów w kolejności, w jakiej są potrzebne.
## Kolejny cel to pierwszy niespełniony z tych, które dotyczą fali, przed którą stoi gracz (i wcześniejszych);
## gdy wszystkie są spełnione, celem jest Oblężenie. Po 5. fali prowadzenie się kończy.
##
## Ścieżka wynika z obrony, z którą fale się wygrywa (PveWaves.EXPECTED_DEFENCE), i z łańcuchów towarów:
## Chłopi z Koszar (fale 1–2), toporniki z Drzewcarza (fala 3), łucznicy z Chaty myśliwego, Cięciwiarza,
## Łukmistrza, Strzałmistrza i Strzelnicy oraz brama z palisadą (fala 4), Dwór 2 dla większej armii
## i oszczepnicy (fala 5). Nic nie blokuje Oblężenia: cele tylko podpowiadają. Stan liczy się z gry,
## więc nie trzeba go zapisywać.

enum Check { BUILT, RESEARCHED, ARMY, UNIT, WALLS, MANOR, SIEGE }

## [przed falą (0 = pierwsza), rodzaj sprawdzenia, parametr, ilość, tekst]. Parametr: rodzaj budynku,
## kod technologii albo jednostka.
const GOALS: Array = [
	[0, Check.BUILT, BuildingTypes.Kind.BARRACKS, 1, "Postaw Koszary (Buduj, Wojsko)"],
	[0, Check.ARMY, 0, 6, "Wyszkol 6 żołnierzy (Wojsko)"],
	[1, Check.ARMY, 0, 10, "Wyszkol 10 żołnierzy (Wojsko)"],
	[2, Check.RESEARCHED, "A39", 1, "Zbadaj A39 Drzewcarstwo (Badania)"],
	[2, Check.BUILT, BuildingTypes.Kind.POLEARM, 1, "Postaw Drzewcarza (Buduj, Wytwórcy)"],
	[2, Check.UNIT, UnitTypes.Unit.AXE_WARRIOR, 4, "Wyszkol 4 Wojowników z toporem"],
	[3, Check.RESEARCHED, "G18", 1, "Zbadaj G18 Łowiectwo (Badania)"],
	[3, Check.BUILT, BuildingTypes.Kind.HUNTER, 1, "Postaw Chatę myśliwego"],
	[3, Check.RESEARCHED, "A40", 1, "Zbadaj A40 Cięciwy ze ścięgien"],
	[3, Check.BUILT, BuildingTypes.Kind.BOWSTRING, 1, "Postaw Cięciwiarza"],
	[3, Check.RESEARCHED, "A41", 1, "Zbadaj A41 Łukmistrzostwo"],
	[3, Check.BUILT, BuildingTypes.Kind.BOWYER, 1, "Postaw Łukmistrza"],
	[3, Check.RESEARCHED, "A42", 1, "Zbadaj A42 Strzałmistrzostwo"],
	[3, Check.BUILT, BuildingTypes.Kind.FLETCHER, 1, "Postaw Strzałmistrza"],
	[3, Check.RESEARCHED, "A44", 1, "Zbadaj A44 Ćwiczenia strzeleckie"],
	[3, Check.BUILT, BuildingTypes.Kind.ARCHERY_RANGE, 1, "Postaw Strzelnicę"],
	[3, Check.UNIT, UnitTypes.Unit.ARCHER, 4, "Wyszkol 4 Łuczników"],
	[3, Check.BUILT, BuildingTypes.Kind.GATE, 1, "Postaw bramę na drodze do donżonu"],
	[3, Check.WALLS, 0, 4, "Postaw 4 odcinki palisady przy bramie"],
	[4, Check.MANOR, 0, 2, "Ulepsz Dwór do poziomu 2"],
	[4, Check.UNIT, UnitTypes.Unit.AXE_WARRIOR, 10, "Wyszkol 10 Wojowników z toporem"],
	[4, Check.UNIT, UnitTypes.Unit.ARCHER, 6, "Wyszkol 6 Łuczników"],
	[4, Check.UNIT, UnitTypes.Unit.JAVELINEER, 6, "Wyszkol 6 Oszczepników"],
]


## Komunikat po wygranej 5. fali: koniec samouczka z nagrodą (i poległymi), jak inne fale (review #189).
static func done_message(reward: Array[int], fallen: int) -> String:
	if fallen > 0:
		return "Koniec samouczka, polegli: %d. +%s" % [fallen, Hud.cost_text(reward)]
	return "Samouczek ukończony! +%s" % Hud.cost_text(reward)


## Indeks bieżącego celu w GOALS albo -1, gdy celem jest Oblężenie (albo samouczek jest skończony).
static func current(cleared: int, grid: BuildGrid, research: Research, recruitment: Recruitment) -> int:
	if cleared >= PveWaves.COUNT:
		return -1
	for i in GOALS.size():
		var g: Array = GOALS[i]
		if int(g[0]) > cleared:
			break
		if not is_met(g, grid, research, recruitment):
			return i
	return -1


## Tekst celu na pasku HUD; pusty, gdy samouczek się skończył.
static func text(cleared: int, grid: BuildGrid, research: Research, recruitment: Recruitment) -> String:
	if cleared >= PveWaves.COUNT:
		return ""
	var i := current(cleared, grid, research, recruitment)
	if i < 0:
		return "Oblężenie: fala %d z %d" % [cleared + 1, PveWaves.COUNT]
	return GOALS[i][4] as String


static func is_met(g: Array, grid: BuildGrid, research: Research, recruitment: Recruitment) -> bool:
	var need := int(g[3])
	match int(g[1]):
		Check.BUILT:
			return grid.has_built(int(g[2]))
		Check.RESEARCHED:
			return research != null and research.is_done(g[2] as String)
		Check.ARMY:
			return recruitment.army_size() >= need
		Check.UNIT:
			return recruitment.army_of(int(g[2])) >= need
		Check.WALLS:
			var n := 0
			for id: int in grid.kinds:
				if BuildingTypes.is_wall(grid.kinds[id]) and grid.levels[id] >= 1:
					n += 1
			return n >= need
		Check.MANOR:
			return grid.manor_level() >= need
	return true
