extends TestCase
## Bitwa bierze tylko zadania, które ekran Obrona daje danej klasie w danej epoce (#378): zapis spoza
## gry (kopia zamku z serwera) może mieć np. Wypad konnicy w epoce I albo piechotę na Wypadzie, a bitwa
## traktuje taki rozkaz jak brak rozkazu (zadanie domyślne). Reguły są w jednej funkcji
## (DefensePlan.task_options), z której korzysta też ekran Obrona.

const K := BuildingTypes.Kind
const U := UnitTypes.Unit
const C := RecruitmentConfig.UnitClass
const T := DefensePlan.Task
const PC_TEST := preload("res://tests/test_player_castle.gd")


## Zamek bota z bramą, murami i Studnią w strefie obrony.
func _castle() -> BuildGrid:
	var g := BotCastle.generate(BotCastle.seed_for(1337, 0), 0).grid
	if not g.has_built(K.WELL):
		g.place(g.spot_near(DefensePlan.keep_center(g), K.WELL, 8), K.WELL, 1)
	return g


## Wolna kratka strefy obrony (pierwsza w kolejności wierszy), na której może stać posterunek.
func _free(g: BuildGrid) -> Vector2i:
	var z := DefensePlan.zone(g)
	for y in range(z.position.y, z.end.y):
		for x in range(z.position.x, z.end.x):
			if DefensePlan.post_problem(g, Vector2i(x, y)).is_empty():
				return Vector2i(x, y)
	return DefensePlan.NO_POST


## Sprawdza, że `got` to zadanie domyślne klasy `unit_class` w epoce `age`.
func _is_default(got: DefensePlan.Order, g: BuildGrid, unit_class: int, age: int, label: String) -> void:
	var d := DefensePlan.default_order(g, unit_class, age)
	if d == null:
		assert_eq(got, null, label)
		return
	assert_true(got != null, label)
	assert_eq(got.task, d.task, label)
	assert_eq(got.post, d.post, label)


func test_panel_uses_plan_rules() -> bool:
	for cls in RecruitmentConfig.UnitClass.size():
		for age in Ages.COUNT:
			for well: bool in [false, true]:
				assert_eq(DefensePanel.task_options(cls, age, well), DefensePlan.task_options(cls, age, well),
						"ekran i bitwa: te same zadania")
	assert_true(not DefensePlan.task_allowed(T.SORTIE, C.FAST, 0, false), "Wypad od epoki II")
	assert_true(DefensePlan.task_allowed(T.SORTIE, C.FAST, DefensePlan.TASK_AGE[T.SORTIE], false), "konnica w epoce II")
	assert_true(not DefensePlan.task_allowed(T.SORTIE, C.LIGHT, 1, false), "piechota bez Wypadu")
	assert_true(not DefensePlan.task_allowed(T.FIELD, C.HEAVY, 0, false), "Przed murami tylko konnica")
	assert_true(not DefensePlan.task_allowed(T.FIREFIGHT, C.LIGHT, 0, false), "gaszenie tylko ze Studnią")
	assert_true(DefensePlan.task_allowed(T.FIREFIGHT, C.LIGHT, 0, true), "piechota lekka ze Studnią")
	assert_true(not DefensePlan.task_allowed(T.FIREFIGHT, C.RANGED, 0, true), "strzelcy nie gaszą")
	for cls in RecruitmentConfig.UnitClass.size():
		assert_true(DefensePlan.task_allowed(T.GARRISON, cls, 0, false), "garnizon dla każdej klasy")
		assert_true(DefensePlan.task_allowed(T.KEEP, cls, 0, false), "przy donżonie dla każdej klasy")
	return true


func test_disallowed_tasks_get_default_order() -> bool:
	var g := _castle()
	assert_true(DefensePlan.main_gate(g) != 0, "zamek ma bramę")
	var cell := _free(g)
	assert_true(cell != DefensePlan.NO_POST, "jest wolna kratka w strefie")
	var ids: Array[int] = [1, 2, 3, 4, 5, 6]
	var squads := [[U.RIDER, 4], [U.AXE_WARRIOR, 6], [U.AXE_WARRIOR, 6], [U.ARCHER, 6], [U.RIDER, 4], [U.AXE_WARRIOR, 6]]
	var p := DefensePlan.new()
	p.set_task(1, T.SORTIE).post = cell  # Wypad konnicy w epoce I
	p.set_task(2, T.SORTIE).post = cell  # piechota na Wypadzie
	p.set_task(3, T.FIELD).post = cell  # piechota Przed murami
	p.set_task(4, T.FIREFIGHT).post = cell  # strzelcy gaszą
	p.set_task(5, T.FIELD).post = cell  # konnica Przed murami: dozwolone
	p.set_task(6, T.FIREFIGHT).post = cell  # piechota lekka ze Studnią: dozwolone
	var got := p.battle_orders(ids, squads, g, 0)
	_is_default(got[0], g, C.FAST, 0, "Wypad w epoce I: zadanie domyślne")
	_is_default(got[1], g, C.LIGHT, 0, "piechota na Wypadzie: zadanie domyślne")
	_is_default(got[2], g, C.LIGHT, 0, "piechota Przed murami: zadanie domyślne")
	_is_default(got[3], g, C.RANGED, 0, "strzelcy na Gaszeniu: zadanie domyślne")
	assert_eq(got[4].task, T.FIELD, "konnica zostaje Przed murami")
	assert_eq(got[4].post, cell, "na swojej kratce")
	assert_eq(got[5].task, T.FIREFIGHT, "piechota lekka gasi przy Studni")
	assert_eq(p.order_for(1).task, T.SORTIE, "układ w zapisie bez zmian")
	var age2 := p.battle_orders(ids, squads, g, DefensePlan.TASK_AGE[T.SORTIE])
	assert_eq(age2[0].task, T.SORTIE, "w epoce II konnica wychodzi na wypad")
	_is_default(age2[1], g, C.LIGHT, 1, "piechota dalej bez Wypadu")
	return true


func test_firefight_without_well_gets_default_order() -> bool:
	var g := _castle()
	var cell := _free(g)
	var p := DefensePlan.new()
	p.set_task(1, T.FIREFIGHT).post = cell
	var ids: Array[int] = [1]
	var squads := [[U.AXE_WARRIOR, 6]]
	assert_eq(p.battle_orders(ids, squads, g, 0)[0].task, T.FIREFIGHT, "ze Studnią gasi")
	for id: int in g.buildings.keys():
		if g.kinds[id] == K.WELL:
			g.remove(id)
	assert_true(not g.has_built(K.WELL), "Studni już nie ma")
	_is_default(p.battle_orders(ids, squads, g, 0)[0], g, C.LIGHT, 0, "bez Studni: zadanie domyślne")
	return true


## Kopia zamku z PvP z piechotą na Wypadzie (na dozwolonej kratce strefy) liczy się jak bez rozkazu,
## a ten sam zapis daje tę samą bitwę.
func test_player_castle_ignores_disallowed_task_and_is_deterministic() -> bool:
	var castle := PC_TEST._castle(WorldSeed.first_playable(4242))
	var sums: Array[int] = []
	var cell := DefensePlan.NO_POST
	for i in 3:
		var launch: Dictionary = PC_TEST._launch()
		launch["castle"] = castle.duplicate(true)
		var pc := PlayerCastle.from_start(PC_TEST._start(), PC_TEST.ARMY, 0)
		if i > 0:
			var bad := DefensePlan.new()
			bad.set_task(1, T.SORTIE).post = cell
			launch["defense"] = JSON.parse_string(JSON.stringify(bad.to_dict())) as Dictionary
		assert_true(pc.apply_launch(launch), "kopia przyjęta")
		if i == 0:
			cell = _free(pc.target.grid)
			assert_true(cell != DefensePlan.NO_POST, "jest kratka w strefie")
			var hold := DefensePlan.new()
			hold.set_post(1, cell)
			assert_true(DefensePlan.order_allowed(pc.target.grid, hold.order_for(1), C.LIGHT), "kratka dozwolona")
		var b := pc.create_battle()
		b.run()
		sums.append(b.checksum())
	assert_eq(sums[1], sums[0], "piechota na Wypadzie jak brak rozkazu")
	assert_eq(sums[2], sums[1], "ten sam zapis, ta sama bitwa")
	return true
