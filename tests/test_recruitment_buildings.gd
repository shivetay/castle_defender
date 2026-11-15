extends TestCase
## Budynki rekrutacji według klas (#119): Koszary, Dom drużyny, Strzelnica (i Stajnia z #91),
## technologie z drzewka, klasa każdego budynku, limit i tempo szkolenia od poziomu. Grafikę
## (5 poziomów, 4 stany, paleta) sprawdza test_buildings dla wszystkich rodzajów.

const T0 := 1_700_000_000_000
const K := BuildingTypes.Kind
const C := RecruitmentConfig.UnitClass


func _free_cell(grid: BuildGrid, kind: int) -> Vector2i:
	var c := grid.terrain.center()
	for r in grid.terrain.size:
		for dy in range(-r, r + 1):
			for dx in range(-r, r + 1):
				var p := c + Vector2i(dx, dy)
				if grid.placement_for(p, kind) != Rect2i():
					return p
	return Vector2i(-1, -1)


func test_each_class_has_its_building() -> bool:
	assert_eq(RecruitmentConfig.building_for(C.LIGHT), K.BARRACKS, "lekka: Koszary")
	assert_eq(RecruitmentConfig.building_for(C.HEAVY), K.WARBAND_HOUSE, "ciężka: Dom drużyny")
	assert_eq(RecruitmentConfig.building_for(C.RANGED), K.ARCHERY_RANGE, "strzelecka: Strzelnica")
	assert_eq(RecruitmentConfig.building_for(C.FAST), K.STABLE, "szybka: Stajnia")
	assert_eq(RecruitmentConfig.building_for(C.SPECIAL), -1, "specjalna: budynek każdej jednostki osobno")
	for unit_class: int in [C.LIGHT, C.HEAVY, C.RANGED, C.FAST]:
		assert_eq(RecruitmentConfig.class_of(RecruitmentConfig.building_for(unit_class)), unit_class,
				"budynek szkoli tylko swoją klasę (%s)" % RecruitmentConfig.CLASS_NAMES[unit_class])
	return true


## Kryterium #119: Dwór grodowy nie rekrutuje już jednostek.
func test_manor_does_not_recruit() -> bool:
	assert_eq(RecruitmentConfig.class_of(K.MANOR), -1, "Dwór nie rekrutuje")
	assert_eq(RecruitmentConfig.class_of(K.TOWER), -1, "wieża nie rekrutuje")
	return true


func test_technologies_from_tree() -> bool:
	assert_eq(BuildConfig.required_tech(K.BARRACKS), "", "Koszary od początku epoki I")
	assert_eq(BuildConfig.required_tech(K.WARBAND_HOUSE), "A45", "Dom drużyny: A45 Drużyna")
	assert_eq(BuildConfig.required_tech(K.ARCHERY_RANGE), "A44", "Strzelnica: A44 Ćwiczenia strzeleckie")
	for kind: int in [K.WARBAND_HOUSE, K.ARCHERY_RANGE]:
		assert_true(TechTree.effect(BuildConfig.required_tech(kind)).begins_with("budynek " + BuildingTypes.NAMES[kind]),
				"%s: technologia z drzewka" % BuildingTypes.NAMES[kind])
	var grid := BuildGrid.new(TerrainMap.generate(1337))
	var q := BuildQueue.new()
	var e := Economy.new(T0)
	var r := Research.new()
	assert_eq(q.order_build(grid, e, _free_cell(grid, K.BARRACKS), K.BARRACKS, T0, r), BuildQueue.Result.OK,
			"Koszary bez badań")
	assert_eq(q.order_build(grid, e, _free_cell(grid, K.ARCHERY_RANGE), K.ARCHERY_RANGE, T0, r),
			BuildQueue.Result.NEEDS_TECH, "Strzelnica bez A44 nie")
	assert_eq(q.order_build(grid, e, _free_cell(grid, K.WARBAND_HOUSE), K.WARBAND_HOUSE, T0, r),
			BuildQueue.Result.NEEDS_TECH, "Dom drużyny bez A45 nie (review PR 145)")
	r.done["A45"] = true
	assert_eq(q.order_build(grid, e, _free_cell(grid, K.WARBAND_HOUSE), K.WARBAND_HOUSE, T0, r),
			BuildQueue.Result.OK, "po A45 tak")
	return true


## Poziom budynku podnosi limit i tempo szkolenia (#119).
func test_level_raises_training_limit_and_speed() -> bool:
	for level in range(2, BuildingTypes.MAX_LEVEL + 1):
		assert_true(RecruitmentConfig.training_slots(level) > RecruitmentConfig.training_slots(level - 1),
				"poziom %d: większy limit" % level)
		assert_true(RecruitmentConfig.training_speed_percent(level) > RecruitmentConfig.training_speed_percent(level - 1),
				"poziom %d: szybciej" % level)
	return true


func test_recruitment_buildings_on_bar_and_buildable() -> bool:
	var grid := BuildGrid.new(TerrainMap.generate(1337))
	grid.place_kind(_free_cell(grid, K.MANOR), K.MANOR, 5)
	for kind: int in [K.BARRACKS, K.WARBAND_HOUSE, K.ARCHERY_RANGE]:
		assert_true(BuildingTypes.BUILD_BAR.has(kind), "%s na pasku" % BuildingTypes.NAMES[kind])
		var id := grid.place_kind(_free_cell(grid, kind), kind)
		assert_true(id > 0 and grid.upgrade(id), "%s staje i da się ulepszyć" % BuildingTypes.NAMES[kind])
	return true
