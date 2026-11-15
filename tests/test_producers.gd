extends TestCase
## Budynki produkcyjne epoki I (#90): wymagania technologii z drzewka, stawianie, produkcja
## towarów, napisy na pasku budowy. Grafikę (5 poziomów, 4 stany, paleta) sprawdza test_buildings
## dla wszystkich rodzajów, także wytwórców.

const T0 := 1_700_000_000_000
const HOUR := 3600 * 1000
const K := BuildingTypes.Kind
const PRODUCERS: Array[int] = [K.HUNTER, K.TANNERY, K.LEATHERWORKER, K.POLEARM, K.BOWSTRING, K.BOWYER,
		K.FLETCHER, K.SADDLER, K.TAR_KILN]


func _rich_economy() -> Economy:
	var e := Economy.new(T0)
	for res in EconomyConfig.count():
		e.amounts[res] = 1000
	return e


func _free_cell(grid: BuildGrid, kind: int) -> Vector2i:
	var c := grid.terrain.center()
	for r in grid.terrain.size:
		for dy in range(-r, r + 1):
			for dx in range(-r, r + 1):
				var p := c + Vector2i(dx, dy)
				if grid.placement_for(p, kind) != Rect2i():
					return p
	return Vector2i(-1, -1)


## Technologia każdego wytwórcy jest tą, której efekt w drzewku to „budynek <nazwa>”.
func test_each_producer_needs_its_technology() -> bool:
	for kind in PRODUCERS:
		var tech := BuildConfig.required_tech(kind)
		assert_true(TechTree.has(tech), "%s: technologia %s istnieje" % [BuildingTypes.NAMES[kind], tech])
		assert_true(TechTree.effect(tech).begins_with("budynek " + BuildingTypes.NAMES[kind]),
				"%s: %s odblokowuje ten budynek" % [BuildingTypes.NAMES[kind], tech])
		assert_true(GoodsConfig.PRODUCER_KINDS.has(kind), "%s produkuje towar" % BuildingTypes.NAMES[kind])
		assert_true(BuildingTypes.BUILD_BAR.has(kind), "%s na pasku budowy" % BuildingTypes.NAMES[kind])
	for kind: int in [K.RAMPART, K.PALISADE, K.GATE, K.TOWER, K.LUMBER_HUT]:
		assert_eq(BuildConfig.required_tech(kind), "", "%s bez wymagań" % BuildingTypes.NAMES[kind])
	return true


## Kryterium #121/#12: budynek wytwórcy da się postawić dopiero po zbadaniu jego technologii.
func test_producer_built_only_after_research() -> bool:
	var grid := BuildGrid.new(TerrainMap.generate(1337))
	var e := _rich_economy()
	var q := BuildQueue.new()
	var r := Research.new()
	var cell := _free_cell(grid, K.HUNTER)
	assert_eq(q.order_build(grid, e, cell, K.HUNTER, T0, r), BuildQueue.Result.NEEDS_TECH, "bez Łowiectwa nie")
	assert_eq(q.order_build(grid, e, cell, K.HUNTER, T0), BuildQueue.Result.NEEDS_TECH, "bez stanu badań nie")
	assert_eq(grid.building_at(cell), 0, "nic nie stanęło")
	assert_eq(e.amounts[EconomyConfig.Res.WOOD], 1000, "koszt nie zszedł")
	r.done["G18"] = true
	assert_eq(q.order_build(grid, e, cell, K.HUNTER, T0, r), BuildQueue.Result.OK, "po Łowiectwie tak")
	assert_eq(q.order_build(grid, e, _free_cell(grid, K.TOWER), K.TOWER, T0, r), BuildQueue.Result.OK,
			"wieża nie wymaga technologii")
	return true


## Kryterium #90: każdy budynek da się postawić, ulepszyć i produkuje swój towar.
func test_producers_build_upgrade_and_produce() -> bool:
	var grid := BuildGrid.new(TerrainMap.generate(1337))
	grid.place_kind(_free_cell(grid, K.MANOR), K.MANOR, 5)
	for kind in PRODUCERS:
		var id := grid.place_kind(_free_cell(grid, kind), kind)
		assert_true(id > 0, "%s staje na mapie" % BuildingTypes.NAMES[kind])
		assert_true(grid.upgrade(id), "%s da się ulepszyć" % BuildingTypes.NAMES[kind])
	var producers := Goods.producers(grid)
	assert_eq(producers.size(), PRODUCERS.size(), "każdy wytwórca liczy się w produkcji")
	# każdy wytwórca osobno, z zapasem wejść: po godzinie przybywa jego towaru
	for kind in PRODUCERS:
		var producer: String = GoodsConfig.PRODUCER_KINDS[kind]
		var goods := Goods.new(T0)
		for good in GoodsConfig.count():
			goods.amounts[good] = 100
		var gained := goods.update(T0 + HOUR, {producer: producers[producer]}, _rich_economy())
		assert_true(gained.max() > 0, "%s produkuje swój towar" % BuildingTypes.NAMES[kind])
	return true


func test_construction_site_does_not_produce() -> bool:
	var grid := BuildGrid.new(TerrainMap.generate(1337))
	grid.place_kind(_free_cell(grid, K.TAR_KILN), K.TAR_KILN, 0)
	assert_eq(Goods.producers(grid), {}, "plac budowy Smolarni jeszcze nie produkuje")
	return true


func test_bar_labels_fit_buttons() -> bool:
	for kind in BuildingTypes.BUILD_BAR:
		var label := BuildingTypes.SHORT_NAMES[kind]
		assert_true(PixelFont.text_width(label) <= Hud.BUTTON_SIZE.x - 4, "„%s” mieści się na przycisku" % label)
		var hint := "%s: zbadaj %s %s" % [BuildingTypes.NAMES[kind], "A38", TechTree.tech_name("A38")]
		assert_true(PixelFont.text_width(hint) <= Hud.MESSAGE_MAX_WIDTH, "„%s” mieści się w pasku" % hint)
	return true


func test_bar_slots_map_to_kinds() -> bool:
	assert_eq(BuildingTypes.bar_kind(0), K.RAMPART, "pierwsze miejsce: wał")
	assert_eq(BuildingTypes.bar_kind(5), K.FISHER, "za chatą drwala budynki gospodarcze (#122)")
	assert_eq(BuildingTypes.bar_kind(7), K.HUNTER, "potem pierwszy wytwórca")
	assert_eq(BuildingTypes.bar_kind(BuildingTypes.buildable_count() - 1), K.TAR_KILN, "ostatnie: Smolarnia")
	var seen := {}
	for kind in BuildingTypes.BUILD_BAR:
		seen[kind] = true
	assert_eq(seen.size(), BuildingTypes.BUILD_BAR.size(), "każdy rodzaj raz")
	return true
