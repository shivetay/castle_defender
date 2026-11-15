extends TestCase
## Klasy jednostek (#87): 13 jednostek MVP z klasą, budynkiem i technologią według notatek
## Jednostki oraz Klasy jednostek i produkcja; przewagi klas zmieniają wynik deterministycznie;
## ikony klas 5×5 z palety.

const U := UnitTypes.Unit
const C := RecruitmentConfig.UnitClass


func test_mvp_units_and_their_classes() -> bool:
	assert_eq(UnitTypes.count(), 13, "13 jednostek MVP (Plan MVP)")
	var expected := {
		U.AXE_WARRIOR: C.LIGHT, U.JAVELINEER: C.LIGHT, U.SPEARMAN: C.LIGHT,
		U.SHIELDBEARER: C.HEAVY, U.GAMBESON_WARRIOR: C.HEAVY,
		U.ARCHER: C.RANGED, U.REFLEX_ARCHER: C.RANGED,
		U.RIDER: C.FAST, U.LANCER: C.FAST,
		U.FIRE_RAISER: C.SPECIAL, U.TRACKER: C.SPECIAL,
		U.RAM: UnitTypes.ENGINEERING, U.DIGGER: UnitTypes.ENGINEERING,
	}
	for unit: int in expected:
		assert_eq(UnitTypes.unit_class(unit), expected[unit], "%s: klasa z notatki" % UnitTypes.unit_name(unit))
	# epoka I ma jednostkę w każdej z 5 klas
	var age_one := {}
	for unit in UnitTypes.count():
		if UnitTypes.age(unit) == 0 and UnitTypes.unit_class(unit) != UnitTypes.ENGINEERING:
			age_one[UnitTypes.unit_class(unit)] = true
	assert_eq(age_one.size(), RecruitmentConfig.CLASS_NAMES.size(), "epoka I: wszystkie 5 klas")
	return true


func test_units_train_in_their_class_building() -> bool:
	for unit in UnitTypes.count():
		var unit_class := UnitTypes.unit_class(unit)
		var expected := RecruitmentConfig.building_for(unit_class)
		if expected >= 0:
			assert_eq(UnitTypes.building(unit), expected, "%s: budynek swojej klasy" % UnitTypes.unit_name(unit))
	assert_eq(UnitTypes.building(U.FIRE_RAISER), BuildingTypes.Kind.TAR_KILN, "Podpalacz w Smolarni")
	assert_eq(UnitTypes.building(U.TRACKER), -1, "Tropiciel: Wieży sygnałowej jeszcze nie ma")
	return true


func test_technologies_match_the_tree() -> bool:
	for unit in UnitTypes.count():
		var tech := UnitTypes.required_tech(unit)
		if tech.is_empty():
			continue
		assert_true(TechTree.has(tech), "%s: technologia %s w drzewku" % [UnitTypes.unit_name(unit), tech])
		assert_true(TechTree.age(tech) <= UnitTypes.age(unit), "%s: technologia nie z późniejszej epoki" % UnitTypes.unit_name(unit))
		if tech != "S1":
			assert_true(TechTree.effect(tech).contains("jednostka " + UnitTypes.unit_name(unit)),
					"%s: %s odblokowuje tę jednostkę" % [UnitTypes.unit_name(unit), tech])
	return true


func test_costs_use_goods_without_metal() -> bool:
	for unit in UnitTypes.count():
		for res: int in UnitTypes.resource_cost(unit):
			assert_true(res in [EconomyConfig.Res.WOOD, EconomyConfig.Res.STONE, EconomyConfig.Res.FOOD],
					"%s: bez metalu i złota" % UnitTypes.unit_name(unit))
		for good: int in UnitTypes.goods_cost(unit):
			assert_true(good >= 0 and good < GoodsConfig.count(), "%s: znany towar" % UnitTypes.unit_name(unit))
	var G := GoodsConfig.Good
	assert_eq(UnitTypes.goods_cost(U.ARCHER), {G.BOW: 1, G.ARROW: 20}, "Łucznik: łuk i 20 strzał (notatka)")
	assert_eq(UnitTypes.goods_cost(U.SHIELDBEARER), {G.SHIELD: 1, G.LEATHER_ARMOR: 1}, "Tarczownik: tarcza i zbroja")
	assert_eq(UnitTypes.goods_cost(U.RIDER), {G.HORSE: 1, G.SADDLE: 1}, "Jeździec: koń i siodło")
	return true


func test_class_advantages() -> bool:
	assert_eq(UnitTypes.damage(U.RIDER, U.ARCHER), UnitTypes.attack(U.RIDER) * 150 / 100, "szybka ×1,5 przeciw strzeleckiej")
	assert_eq(UnitTypes.damage(U.SPEARMAN, U.RIDER), UnitTypes.attack(U.SPEARMAN) * 2, "drzewce ×2 przeciw konnicy")
	assert_eq(UnitTypes.damage(U.SHIELDBEARER, U.RIDER), UnitTypes.attack(U.SHIELDBEARER) * 150 / 100, "ciężka silna przeciw konnicy")
	assert_true(UnitTypes.damage(U.ARCHER, U.RIDER) < UnitTypes.attack(U.ARCHER), "strzelecka słaba przeciw szybkiej")
	assert_eq(UnitTypes.damage(U.RAM, U.ARCHER), UnitTypes.attack(U.RAM), "inżynieria bez przewag klas")
	assert_eq(UnitTypes.damage(U.RIDER, U.ARCHER, false), UnitTypes.attack(U.RIDER), "bez przewag: goły atak")
	return true


## Kryterium #87: przewagi klas zmieniają wynik deterministycznie.
func test_advantages_change_the_result_deterministically() -> bool:
	var plain := UnitTypes.duel(U.SPEARMAN, U.RIDER, false)
	var with_classes := UnitTypes.duel(U.SPEARMAN, U.RIDER)
	assert_eq(plain, [1, 6] as Array[int], "bez przewag Jeździec rozbija Włócznika w 6 turach")
	assert_eq(with_classes, [-1, 5] as Array[int], "z drzewcem ×2 Włócznik zabiera Jeźdźca ze sobą")
	for i in 10:
		assert_eq(UnitTypes.duel(U.SPEARMAN, U.RIDER), with_classes, "ten sam pojedynek, ten sam wynik")
	assert_eq(UnitTypes.duel(U.RIDER, U.ARCHER)[0], 0, "konnica wygrywa ze strzelcami")
	assert_eq(UnitTypes.duel(U.TRACKER, U.DIGGER)[0], 1, "Tropiciel bez ataku przegrywa")
	return true


func test_class_icons() -> bool:
	assert_eq(PixelIcons.CLASSES.size(), RecruitmentConfig.CLASS_NAMES.size(), "ikona dla każdej klasy")
	var allowed := {}
	for col: Color in Palette.AGE_I + Palette.UI:
		allowed[col.to_rgba32()] = true
	var atlas := PixelIcons.make_atlas(PixelIcons.CLASSES)
	var seen := {}
	for i in PixelIcons.CLASSES.size():
		for row: String in PixelIcons.CLASSES[i] as Array:
			assert_eq(row.length(), PixelIcons.SIZE, "ikona klasy %d: wiersz 5 znaków" % i)
		var icon := atlas.get_region(Rect2i(i * PixelIcons.SIZE, 0, PixelIcons.SIZE, PixelIcons.SIZE))
		seen[icon.get_data()] = true
		var filled := 0
		for y in PixelIcons.SIZE:
			for x in PixelIcons.SIZE:
				if icon.get_pixel(x, y).a > 0.0:
					filled += 1
					assert_true(allowed.has(icon.get_pixel(x, y).to_rgba32()), "ikona klasy %d: kolor z palety" % i)
		assert_true(filled >= 10, "ikona klasy %d czytelna" % i)
	assert_eq(seen.size(), PixelIcons.CLASSES.size(), "każda ikona klasy inna")
	return true
