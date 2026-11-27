extends TestCase
## Zasięg strefy obrony (#342, ADR 0006): promień rośnie z poziomem Dworu (DefensePlan.RADIUS_PER_MANOR_LEVEL
## na poziom, w epoce II jak przy Dworze 5) i z poziomem technologii O25 Wysunięte straże
## (DefensePlan.RADIUS_PER_TECH_LEVEL na poziom). Strefa obejmuje posterunki, pułapki i zadania domyślne.

const K := BuildingTypes.Kind
const TK := TrapConfig.Kind


func _castle(manor_level: int = 1) -> BuildGrid:
	var grid := BuildGrid.new(TerrainMap.generate(WorldSeed.first_playable(1337)))
	grid.place(grid.manor_spot(64), K.MANOR, manor_level)
	grid.place(grid.keep_spot(64), K.KEEP, 1)
	return grid


## Badania z O25 na poziomie `level` (0 = niezbadana).
func _research(level: int) -> Research:
	var r := Research.new()
	if level >= 1:
		r.done[DefensePlan.REACH_TECH] = true
	if level >= 2:
		r.levels[DefensePlan.REACH_TECH] = level
	return r


func test_radius_scale() -> bool:
	assert_eq(DefensePlan.radius_for(1, 0), 10, "Dwór 1: 10 kratek")
	assert_eq(DefensePlan.radius_for(2, 0), 12, "Dwór 2: 12")
	assert_eq(DefensePlan.radius_for(3, 0), 14, "Dwór 3: 14")
	assert_eq(DefensePlan.radius_for(5, 0), 18, "Dwór 5: 18")
	assert_eq(DefensePlan.radius_for(6, 0), 18, "epoka II zostaje przy 18")
	assert_eq(DefensePlan.radius_for(0, 0), 10, "bez Dworu jak Dwór 1")
	assert_eq(DefensePlan.radius_for(1, 1), 11, "O25 poziom 1: +1")
	assert_eq(DefensePlan.radius_for(5, 5), 23, "najdalej 18 + 5")
	return true


func test_tech_is_leveled_defense_doctrine() -> bool:
	var code := DefensePlan.REACH_TECH
	assert_true(TechTree.has(code), "O25 w drzewku")
	assert_eq(TechTree.branch(code), TechTree.Branch.DEFENSE, "gałąź Obrona")
	assert_eq(TechTree.age(code), 0, "epoka I")
	assert_true(TechTree.requires(code).is_empty(), "bez wymagań")
	assert_true(TechTree.is_leveled(code), "badana na kolejne poziomy")
	assert_true(TechTree.is_doctrine(code), "drożeje jak doktryny")
	assert_eq(TechTree.max_level(code, 0), 3, "3 poziomy w epoce I")
	assert_eq(TechTree.max_level(code, 1), 5, "5 poziomów w epoce II")
	assert_eq(DefensePlan.reach_level(_research(0)), 0, "niezbadana")
	assert_eq(DefensePlan.reach_level(_research(3)), 3, "poziom 3")
	assert_eq(DefensePlan.reach_level(null), 0, "bez badań")
	return true


func test_zone_grows_with_manor_and_tech() -> bool:
	var low := _castle(1)
	var high := _castle(3)
	var c := DefensePlan.keep_center(low)
	assert_eq(DefensePlan.keep_center(high), c, "ten sam donżon")
	assert_eq(DefensePlan.radius(low), 10, "Dwór 1")
	assert_eq(DefensePlan.radius(high), 14, "Dwór 3")
	assert_true(DefensePlan.zone(high).encloses(DefensePlan.zone(low)), "wyższy Dwór obejmuje niższą strefę")
	assert_true(DefensePlan.zone(high).size.x > DefensePlan.zone(low).size.x, "i jest większa")
	high.reach_level = 2
	assert_eq(DefensePlan.radius(high), 16, "Dwór 3 i O25 poziom 2")
	return true


func test_far_cell_needs_higher_manor() -> bool:
	var low := _castle(1)
	var high := _castle(3)
	var c := DefensePlan.keep_center(low)
	# kratka 12 od donżonu, na której (przy wyższym Dworze) da się stanąć
	var far := Vector2i(-1, -1)
	for d: Vector2i in [Vector2i(12, 0), Vector2i(-12, 0), Vector2i(0, 12), Vector2i(0, -12), Vector2i(12, 12),
			Vector2i(-12, -12), Vector2i(12, -12), Vector2i(-12, 12)]:
		if DefensePlan.post_problem(high, c + d).is_empty():
			far = c + d
			break
	assert_true(far != Vector2i(-1, -1), "jest wolna kratka 12 od donżonu")
	assert_eq(DefensePlan.post_problem(low, far), "Za daleko od donżonu: najwyżej 10 kratek", "Dwór 1: za daleko")
	assert_eq(DefensePlan.post_problem(high, far), "", "Dwór 3: posterunek stanie")
	var plan := DefensePlan.new()
	assert_eq(plan.trap_place_problem(low, TK.CALTROPS, far), "Za daleko od donżonu: najwyżej 10 kratek",
			"pułapka przy Dworze 1: za daleko")
	assert_eq(plan.trap_place_problem(high, TK.CALTROPS, far), "", "pułapka przy Dworze 3 stanie")
	# technologia też poszerza: Dwór 1 z O25 poziom 2 sięga 12 kratek
	low.reach_level = 2
	assert_eq(DefensePlan.post_problem(low, far), "", "Dwór 1 z O25 poziom 2")
	low.reach_level = 1
	assert_eq(DefensePlan.post_problem(low, far), "Za daleko od donżonu: najwyżej 11 kratek", "komunikat z aktualnym promieniem")
	return true


## Poziom O25 nie trafia do zapisu siatki: wynika z badań (SaveGame.from_dict), jak perk władcy.
func test_save_sets_reach_level() -> bool:
	var grid := _castle(2)
	var d := SaveGame.to_dict(1337, grid, Economy.new(0), BuildQueue.new(), _research(3))
	var s := SaveGame.from_dict(JSON.parse_string(JSON.stringify(d)) as Dictionary, 0)
	assert_eq(s.grid.reach_level, 3, "poziom O25 z badań w siatce zamku")
	assert_eq(DefensePlan.radius(s.grid), 12 + 3, "Dwór 2 i O25 poziom 3")
	var none := SaveGame.from_dict(JSON.parse_string(JSON.stringify(
			SaveGame.to_dict(1337, grid, Economy.new(0), BuildQueue.new(), Research.new()))) as Dictionary, 0)
	assert_eq(none.grid.reach_level, 0, "bez O25 bez premii")
	return true


## Ukończone badanie O25 od razu poszerza strefę (BuildQueue.update).
func test_research_completion_sets_reach_level() -> bool:
	var grid := _castle(2)
	var e := Economy.new(0)
	e.capacities.fill(1000000)
	for res in EconomyConfig.count():
		e.amounts[res] = 100000
	var r := Research.new()
	assert_eq(r.start(DefensePlan.REACH_TECH, 0, e, 0, grid), Research.Result.OK, "badanie O25")
	var q := BuildQueue.new()
	q.update(r.finish_ms() - 1, grid, e, r)
	assert_eq(grid.reach_level, 0, "przed końcem badania bez premii")
	q.update(r.finish_ms() + 1000, grid, e, r)
	assert_eq(grid.reach_level, 1, "po badaniu poziom 1")
	assert_eq(r.start(DefensePlan.REACH_TECH, 0, e, r.finish_ms() + 1000, grid), Research.Result.OK, "kolejny poziom")
	q.update(r.finish_ms() + 1000, grid, e, r)
	assert_eq(grid.reach_level, 2, "po drugim badaniu poziom 2")
	return true


## Ten sam zamek i te same badania dają zawsze tę samą strefę i te same zadania domyślne.
func test_deterministic_default_orders() -> bool:
	var a := _castle(4)
	var b := _castle(4)
	a.reach_level = 2
	b.reach_level = 2
	assert_eq(DefensePlan.zone(a), DefensePlan.zone(b), "ta sama strefa")
	for cls in RecruitmentConfig.UnitClass.size():
		var oa := DefensePlan.default_order(a, cls, a.age())
		var ob := DefensePlan.default_order(b, cls, b.age())
		assert_eq(oa == null, ob == null, "to samo zadanie domyślne klasy %d" % cls)
		if oa != null and ob != null:
			assert_eq(oa.task, ob.task, "zadanie klasy %d" % cls)
			assert_eq(oa.post, ob.post, "miejsce klasy %d" % cls)
	return true


func test_research_panel_text() -> bool:
	assert_eq(ResearchPanel.reach_text(_research(0), 0), "", "przed zbadaniem bez tekstu")
	assert_eq(ResearchPanel.reach_text(_research(1), 0), "Strefa +1 kratka, następny poziom +2", "poziom 1")
	assert_eq(ResearchPanel.reach_text(_research(2), 0), "Strefa +2 kratki, następny poziom +3", "poziom 2")
	assert_eq(ResearchPanel.reach_text(_research(3), 0), "Strefa +3 kratki", "najwyższy w epoce I")
	assert_eq(ResearchPanel.reach_text(_research(5), 1), "Strefa +5 kratek", "najwyższy w epoce II")
	assert_eq(ResearchPanel.level_text(_research(1), DefensePlan.REACH_TECH, 0), "Strefa +1 kratka, następny poziom +2",
			"ekran badań")
	return true
