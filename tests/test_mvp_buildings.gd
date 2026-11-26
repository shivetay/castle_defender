extends TestCase
## Pozostałe budynki MVP (#35): Fosa sucha, Kopiec, Pole i spichlerz, Studnia, Kamieniołom i Wieża
## sygnałowa. Definicje, technologie (O1, O3, G4, S2), produkcja, działanie w bitwie (spowolnienie
## i kolce fosy, zasięg wież przy Kopcu, Gaszenie pożarów przy Studni) i determinizm. Grafikę
## (5 poziomów, 4 stany, paleta) sprawdza test_buildings dla wszystkich rodzajów.

const K := BuildingTypes.Kind
const U := UnitTypes.Unit
const T := DefensePlan.Task
const R := EconomyConfig.Res
const SIDE := Battle.Side
const NEW_KINDS: Array[int] = [K.DRY_MOAT, K.MOUND, K.FARM, K.WELL, K.QUARRY, K.SIGNAL_TOWER]


func _castle() -> BuildGrid:
	var grid := BuildGrid.new(TerrainMap.generate(WorldSeed.first_playable(1337)))
	grid.place(grid.manor_spot(64), K.MANOR, 1)
	grid.place(grid.keep_spot(64), K.KEEP, 1)
	return grid


func _research(codes: Array[String]) -> Research:
	var r := Research.new()
	for c in codes:
		r.done[c] = true
	return r


## Wolny prostokąt rodzaju `kind` w strefie obrony, najbliżej donżonu (pierścienie od `from`).
func _spot(grid: BuildGrid, kind: int, from: Vector2i = Vector2i(-1, -1)) -> Rect2i:
	var c := DefensePlan.keep_center(grid) if from.x < 0 else from
	for ring in range(3, 12):
		for dy in range(-ring, ring + 1):
			for dx in range(-ring, ring + 1):
				if maxi(absi(dx), absi(dy)) != ring:
					continue
				var r := Rect2i(c + Vector2i(dx, dy), BuildingTypes.size_of(kind))
				if grid.can_place(r, kind) and DefensePlan.zone(grid).encloses(r):
					return r
	return Rect2i()


func _put(f: Battle.Fighter, c: Vector2i) -> void:
	f.x = c.x * BattleConfig.SUB + BattleConfig.SUB / 2
	f.y = c.y * BattleConfig.SUB + BattleConfig.SUB / 2
	f.path.clear()


func _side(b: Battle, side: int) -> Array[Battle.Fighter]:
	var out: Array[Battle.Fighter] = []
	for f in b.fighters:
		if f.side == side:
			out.append(f)
	return out


func _battle(grid: BuildGrid, attackers: Array, defenders: Array, orders: Array[DefensePlan.Order] = [],
		seed_value: int = 5) -> Battle:
	return Battle.for_castle_squads(grid, attackers, defenders, BotCastle.edge_road(grid.terrain), seed_value, null, orders)


func test_definitions_and_build_panel() -> bool:
	assert_eq(BuildingTypes.NAMES.size(), BuildingTypes.SHORT_NAMES.size(), "nazwy i skróty")
	assert_eq(BuildingTypes.NAMES.size(), BuildingTypes.SIZES.size(), "nazwy i rozmiary")
	var names: Array[String] = ["Fosa sucha", "Kopiec", "Pole i spichlerz", "Studnia", "Kamieniołom", "Wieża sygnałowa"]
	for i in NEW_KINDS.size():
		var kind := NEW_KINDS[i]
		assert_eq(BuildingTypes.NAMES[kind], names[i], "nazwa rodzaju %d" % kind)
		assert_true(BuildingTypes.BUILD_BAR.has(kind), "%s na pasku budowy" % names[i])
		assert_true(BuildingTypes.category(kind) >= 0, "%s w zakładce" % names[i])
		assert_true(BuildingTypes.has_levels(kind), "%s ma 5 poziomów" % names[i])
		var cost := BuildConfig.cost(kind, 1)
		assert_true(cost[0] + cost[1] + cost[2] > 0, "%s ma koszt" % names[i])
		assert_true(BuildConfig.time_ms(kind, 1) > 0, "%s ma czas budowy" % names[i])
		assert_true(not BuildPanel.describe(kind).is_empty(), "%s ma opis w panelu" % names[i])
		assert_true(PixelFont.text_width(BuildingTypes.SHORT_NAMES[kind]) <= 50, "%s: skrót mieści się na kafelku" % names[i])
	assert_eq(BuildingTypes.size_of(K.DRY_MOAT), Vector2i(1, 1), "fosa to odcinek 1×1")
	assert_eq(BuildingTypes.category(K.DRY_MOAT), BuildingTypes.Category.DEFENSE, "fosa w Umocnieniach")
	assert_eq(BuildingTypes.category(K.MOUND), BuildingTypes.Category.DEFENSE, "Kopiec w Umocnieniach")
	assert_eq(BuildingTypes.category(K.FARM), BuildingTypes.Category.ECONOMY, "Pole w Gospodarce")
	assert_eq(BuildingTypes.category(K.WELL), BuildingTypes.Category.ECONOMY, "Studnia w Gospodarce")
	assert_eq(BuildingTypes.category(K.QUARRY), BuildingTypes.Category.ECONOMY, "Kamieniołom w Gospodarce")
	assert_eq(BuildingTypes.category(K.SIGNAL_TOWER), BuildingTypes.Category.MILITARY, "Wieża sygnałowa w Wojsku")
	for kind: int in [K.DRY_MOAT, K.MOUND, K.WELL, K.QUARRY]:
		assert_true(not BuildingTypes.is_wooden(kind), "%s nie płonie" % BuildingTypes.NAMES[kind])
	assert_true(BuildingTypes.is_wooden(K.FARM) and BuildingTypes.is_wooden(K.SIGNAL_TOWER), "spichlerz i wieża z drewna")
	assert_true(BuildingTypes.is_passable(K.DRY_MOAT) and not BuildingTypes.is_passable(K.MOUND), "tylko fosa przechodnia")
	return true


## Technologie z komentarza właścicielki w #35: O1 Kopiec, G4 Kamieniołom, S2 Wieża sygnałowa; reszta bez.
func test_required_techs() -> bool:
	assert_eq(BuildConfig.required_tech(K.MOUND), "O1", "Kopiec po O1")
	assert_eq(BuildConfig.required_tech(K.QUARRY), "G4", "Kamieniołom po G4")
	assert_eq(BuildConfig.required_tech(K.SIGNAL_TOWER), "S2", "Wieża sygnałowa po S2")
	for kind: int in [K.DRY_MOAT, K.FARM, K.WELL]:
		assert_eq(BuildConfig.required_tech(kind), "", "%s od początku epoki I" % BuildingTypes.NAMES[kind])
	assert_true(not BuildConfig.is_unlocked(K.MOUND, Research.new()), "bez O1 nie ma Kopca")
	assert_true(BuildConfig.is_unlocked(K.MOUND, _research(["O1"] as Array[String])), "z O1 jest")
	assert_true(Battle.battle_tech_codes().has("O3"), "O3 działa w bitwie")
	return true


## Wieża sygnałowa bada gałąź Specjalne od epoki I (decyzja z 17.11). Budynek nie bada technologii,
## która go odblokowuje: S2 bada Dwór, a S3 Chata tropicieli (odblokowana przez S1, #28).
func test_signal_tower_researches_special() -> bool:
	assert_eq(ResearchConfig.research_building("S1"), K.SIGNAL_TOWER, "S1 w Wieży sygnałowej")
	assert_eq(ResearchConfig.research_building("S2"), K.MANOR, "S2 w Dworze, bo odblokowuje Wieżę")
	assert_eq(ResearchConfig.research_building("S3"), K.SCOUT_HOUSE, "S3 w Chacie tropicieli (#28)")
	assert_eq(UnitTypes.building(U.TRACKER), K.SCOUT_HOUSE, "Tropiciel w Chacie tropicieli, nie w Wieży sygnałowej")
	return true


func test_farm_and_quarry_produce() -> bool:
	var grid := _castle()
	var base := Economy.rates(grid)
	var farm := grid.place(_spot(grid, K.FARM), K.FARM, 1)
	assert_true(farm != 0, "Pole stoi")
	var with_farm := Economy.rates(grid)
	assert_eq(with_farm[R.FOOD] - base[R.FOOD], 60, "Pole 1: +60 Ży/h")
	var quarry := grid.place(_spot(grid, K.QUARRY), K.QUARRY, 3)
	assert_true(quarry != 0, "Kamieniołom stoi")
	assert_eq(Economy.rates(grid)[R.STONE] - base[R.STONE], 80, "Kamieniołom 3: +80 Ka/h")
	grid.place(_spot(grid, K.FARM), K.FARM, 0)
	assert_eq(Economy.rates(grid)[R.FOOD], with_farm[R.FOOD], "plac budowy Pola nic nie daje")
	# limit utrzymania (#214) rośnie razem z żywnością z Pola
	assert_eq(Recruitment.upkeep_limit(grid, null), Economy.rates(grid)[R.FOOD], "utrzymanie z produkcji żywności")
	return true


## Fosa nie jest budynkiem bitwy: droga przez nią jest wolna, ale atakujący idzie po niej 2× wolniej,
## a z O3 traci co sekundę HP według poziomu fosy. Obrońcy fosa nie spowalnia.
func test_moat_slows_and_spikes() -> bool:
	var grid := _castle()
	var r := _spot(grid, K.DRY_MOAT)
	var id := grid.place(r, K.DRY_MOAT, 4)
	assert_true(id != 0, "fosa stoi")
	var b := _battle(grid, [[U.AXE_WARRIOR, 1]], [[U.AXE_WARRIOR, 1]])
	assert_true(not b.structures.has(id), "fosa nie jest budynkiem bitwy")
	assert_eq(b.moat.get(r.position, 0), 4, "kratka fosy z poziomem")
	assert_true(b._structure_at(r.position) == null, "fosa nie blokuje drogi")
	var a := _side(b, SIDE.ATTACKER)[0]
	_put(a, r.position)
	var x0 := a.x
	b._move_toward(a, a.x + 10 * BattleConfig.SUB, a.y)
	var slow := a.x - x0
	var plain := _battle(_castle(), [[U.AXE_WARRIOR, 1]], [])
	var a2 := _side(plain, SIDE.ATTACKER)[0]
	_put(a2, r.position)
	var x2 := a2.x
	plain._move_toward(a2, a2.x + 10 * BattleConfig.SUB, a2.y)
	assert_eq(slow * 2, a2.x - x2, "atakujący w fosie 2× wolniej")
	var d := _side(b, SIDE.DEFENDER)[0]
	_put(d, r.position)
	var xd := d.x
	b._move_toward(d, d.x + 10 * BattleConfig.SUB, d.y)
	assert_eq(d.x - xd, a2.x - x2, "obrońcę fosa nie spowalnia")
	# kolce: bez O3 nic, z O3 co sekundę MOAT_SPIKE_DAMAGE[poziom]
	_put(a, r.position)
	var hp := a.hp
	b.defence.clear()
	for i in BattleConfig.TICK_HZ * 2:
		b.tick += 1
		if b.tick % BattleConfig.TICK_HZ == 0 and b.has_tech(SIDE.DEFENDER, "O3"):
			b._moat_spikes()
	assert_eq(a.hp, hp, "bez O3 fosa nie rani")
	b.apply_research(SIDE.DEFENDER, _research(["O3"] as Array[String]))
	for i in 2:
		b._moat_spikes()
	assert_eq(a.hp, hp - 2 * BattleConfig.moat_spike_damage(4), "O3: 5 HP na sekundę na poziomie 4")
	assert_eq(BattleConfig.MOAT_SPIKE_DAMAGE, [2, 3, 4, 5, 6] as Array[int], "kolce według poziomu")
	return true


## Kolce działają w samym kroku bitwy (step), raz na sekundę.
func test_moat_spikes_in_step() -> bool:
	var grid := _castle()
	var r := _spot(grid, K.DRY_MOAT)
	grid.place(r, K.DRY_MOAT, 1)
	var b := _battle(grid, [[U.TRACKER, 1]], [])
	b.apply_research(SIDE.DEFENDER, _research(["O3"] as Array[String]))
	var a := _side(b, SIDE.ATTACKER)[0]
	var hp := a.hp
	for i in BattleConfig.TICK_HZ * 3:
		_put(a, r.position)  # Tropiciel trzymany w fosie
		b.step()
	assert_eq(a.hp, hp - 3 * BattleConfig.moat_spike_damage(1), "3 s w fosie poziomu 1: 3 × 2 HP")
	return true


## Kopiec: wieża drewniana stykająca się z nim bokiem strzela dalej (+1, od poziomu 3 Kopca +2), po
## skosie i po upadku Kopca nie. Strzelcy na Kopcu stoją na stanowisku z +1 zasięgu.
func test_mound_raises_towers() -> bool:
	var grid := _castle()
	var tr := _spot(grid, K.TOWER)
	var tower := grid.place(tr, K.TOWER, 1)
	var b0 := _battle(grid, [[U.TRACKER, 1]], [])
	assert_eq(b0.tower_range(b0.structures[tower]), BattleConfig.TOWER_RANGE, "wieża bez Kopca")
	var side := Rect2i(tr.position + Vector2i(2, 0), Vector2i(2, 2))
	if not grid.can_place(side, K.MOUND):
		side = Rect2i(tr.position - Vector2i(2, 0), Vector2i(2, 2))
	assert_true(grid.can_place(side, K.MOUND), "miejsce na Kopiec obok wieży")
	var mound := grid.place(side, K.MOUND, 2)
	var b := _battle(grid, [[U.TRACKER, 1]], [])
	assert_eq(b.tower_range(b.structures[tower]), BattleConfig.TOWER_RANGE + 1, "Kopiec 2: +1")
	grid.upgrade(mound)
	var b3 := _battle(grid, [[U.TRACKER, 1]], [])
	assert_eq(b3.tower_range(b3.structures[tower]), BattleConfig.TOWER_RANGE + 2, "Kopiec 3: +2")
	b3._destroy(b3.structures[mound])
	assert_eq(b3.tower_range(b3.structures[tower]), BattleConfig.TOWER_RANGE, "zburzony Kopiec nic nie daje")
	assert_true(Battle.touches_side(Rect2i(0, 0, 2, 2), Rect2i(2, 1, 2, 2)), "bokiem")
	assert_true(not Battle.touches_side(Rect2i(0, 0, 2, 2), Rect2i(2, 2, 2, 2)), "po skosie nie")
	assert_true(not Battle.touches_side(Rect2i(0, 0, 2, 2), Rect2i(3, 0, 2, 2)), "z odstępem nie")
	assert_eq(Battle.station_range_bonus(K.MOUND), 1, "strzelcy na Kopcu +1")
	# łucznik z Obroną odcinka na Kopcu staje na nim
	assert_true(DefensePlan.station_post(grid, side.position), "Kopiec to stanowisko strzelców")
	var o := DefensePlan.Order.new()
	o.task = T.HOLD
	o.post = side.position
	var bs := _battle(grid, [[U.TRACKER, 1]], [[U.ARCHER, 2]], [o] as Array[DefensePlan.Order])
	assert_eq(_side(bs, SIDE.DEFENDER).size(), 2, "dwóch łuczników")
	for f in _side(bs, SIDE.DEFENDER):
		assert_eq(f.wall, mound, "łucznik stoi na Kopcu")
	# Kopiec stoi na kratkach Kopca, więc łucznik dostaje premię stanowiska: +1 do zasięgu łuku
	var archer := _side(bs, SIDE.DEFENDER)[0]
	assert_true(bs.structures.get(archer.wall) != null, "stanowisko to żywy Kopiec")
	return true


## Gaszenie pożarów: Chłopi przy Studni idą do płonącego budynku w jej pobliżu i skracają ogień;
## bez Studni (albo gdy padnie) ogień pali się jak dawniej.
func test_firefighting_at_well() -> bool:
	var grid := _castle()
	var wr := _spot(grid, K.WELL)
	var well := grid.place(wr, K.WELL, 1)
	var hr := _spot(grid, K.LUMBER_HUT, wr.position)
	var hut := grid.place(hr, K.LUMBER_HUT, 1)
	assert_true(well != 0 and hut != 0, "Studnia i chata stoją")
	var o := DefensePlan.Order.new()
	o.task = T.FIREFIGHT
	o.post = DefensePlan.section_post(grid, well)
	assert_true(o.post != DefensePlan.NO_POST, "miejsce przy Studni")
	var orders: Array[DefensePlan.Order] = [o]
	var b := _battle(grid, [[U.TRACKER, 1]], [[U.PEASANT, 3]], orders)
	var ref := _battle(grid, [[U.TRACKER, 1]], [[U.PEASANT, 3]], orders)
	ref.structures[well].hp = 0  # bez Studni nie ma czym gasić
	for battle: Battle in [b, ref]:
		battle.structures[hut].burning = BattleConfig.FIRE_S * BattleConfig.TICK_HZ
	var put_out := -1
	for t in BattleConfig.FIRE_S * BattleConfig.TICK_HZ:
		for battle: Battle in [b, ref]:
			battle.tick += 1
			for f in _side(battle, SIDE.DEFENDER):
				battle._act(f)
			var s: Battle.Structure = battle.structures[hut]
			if s.burning > 0:
				battle._burn(s)
		if put_out < 0 and b.structures[hut].burning == 0:
			put_out = t
	assert_true(put_out >= 0, "Chłopi ugasili chatę")
	assert_true(ref.structures[hut].burning == 0 and ref.structures[hut].hp < b.structures[hut].hp,
			"bez Studni chata płonęła do końca")
	assert_true(put_out < BattleConfig.FIRE_S * BattleConfig.TICK_HZ - BattleConfig.TICK_HZ, "szybciej niż sam ogień")
	assert_true(b.structures[hut].hp > ref.structures[hut].hp, "ugaszona chata ma więcej HP")
	return true


## Pożar dalej niż FIREFIGHT_RADIUS od Studni zostaje bez gaszenia.
func test_fire_too_far_from_well() -> bool:
	var grid := _castle()
	var wr := _spot(grid, K.WELL)
	var well := grid.place(wr, K.WELL, 1)
	var b := _battle(grid, [[U.TRACKER, 1]], [])
	var far := Battle.Structure.new()
	far.id = 9999
	far.kind = K.LUMBER_HUT
	far.rect = Rect2i(wr.position + Vector2i(BattleConfig.FIREFIGHT_RADIUS + 3, 0), Vector2i(2, 2))
	far.hp = 100
	far.max_hp = 100
	far.burning = 30
	b.structures[far.id] = far
	assert_true(b._fire_near(b.structures[well]) == null, "za daleko od Studni")
	far.rect.position = wr.position + Vector2i(3, 0)
	assert_true(b._fire_near(b.structures[well]) == far, "blisko Studni")
	return true


func test_firefight_task_in_panel_and_save() -> bool:
	var light := RecruitmentConfig.UnitClass.LIGHT
	assert_true(not DefensePanel.task_options(light, 0).has(T.FIREFIGHT), "bez Studni nie ma gaszenia")
	assert_true(DefensePanel.task_options(light, 0, true).has(T.FIREFIGHT), "piechota lekka gasi przy Studni")
	assert_true(not DefensePanel.task_options(RecruitmentConfig.UnitClass.RANGED, 0, true).has(T.FIREFIGHT),
			"strzelcy nie gaszą")
	assert_eq(UnitTypes.unit_class(U.PEASANT), light, "Chłop to piechota lekka")
	assert_eq(DefensePlan.TASK_NAMES[T.FIREFIGHT], "Gaszenie pożarów", "nazwa zadania")
	var p := DefensePlan.new()
	var o := p.set_task(4, T.FIREFIGHT)
	o.post = Vector2i(10, 12)
	var back := DefensePlan.from_dict(JSON.parse_string(JSON.stringify(p.to_dict())) as Dictionary)
	assert_eq(back.order_for(4).task, T.FIREFIGHT, "zadanie wraca z zapisu")
	assert_eq(back.order_for(4).post, Vector2i(10, 12), "miejsce wraca z zapisu")
	# dotknięcie Studni ustawia miejsce obok niej
	var grid := _castle()
	var wr := _spot(grid, K.WELL)
	var well := grid.place(wr, K.WELL, 1)
	var panel := DefensePanel.new()
	var plan := DefensePlan.new()
	panel.open(plan, [[U.PEASANT, 3]], [7] as Array[int], grid, 0)
	plan.set_task(7, T.FIREFIGHT).post = DefensePlan.NO_POST
	var msg := panel.tap(grid, wr.position)
	assert_eq(plan.order_for(7).post, DefensePlan.section_post(grid, well), "miejsce przy Studni (%s)" % msg)
	assert_true(panel.tap(grid, wr.position + Vector2i(6, 6)).begins_with("Gaszenie: dotknij Studni")
			or plan.order_for(7).post == DefensePlan.section_post(grid, well), "inna kratka nie zmienia miejsca")
	panel.free()
	return true


## Ten sam zamek z fosą, Kopcem i Studnią, ta sama armia i seed: ten sam przebieg i wynik.
func test_battle_with_new_buildings_is_deterministic() -> bool:
	var grid := _castle()
	var wr := _spot(grid, K.WELL)
	var well := grid.place(wr, K.WELL, 2)
	grid.place(_spot(grid, K.MOUND), K.MOUND, 1)
	for i in 4:
		grid.place(_spot(grid, K.DRY_MOAT), K.DRY_MOAT, 1 + i)
	var o := DefensePlan.Order.new()
	o.task = T.FIREFIGHT
	o.post = DefensePlan.section_post(grid, well)
	var orders: Array[DefensePlan.Order] = [o, null]
	var sums: Array[int] = []
	for run in 2:
		var b := _battle(grid, [[U.FIRE_RAISER, 4], [U.AXE_WARRIOR, 6]], [[U.PEASANT, 4], [U.ARCHER, 3]], orders, 77)
		b.apply_research(SIDE.DEFENDER, _research(["O3"] as Array[String]))
		b.run(BattleConfig.TICK_HZ * 60)
		sums.append(b.checksum())
	assert_eq(sums[0], sums[1], "ten sam seed, ta sama suma kontrolna")
	return true


## #315: Kamieniołom da się postawić w epoce I, ale dopiero po zbadaniu G4 (która wymaga G1).
func test_quarry_available_in_age_one_after_g4() -> bool:
	assert_eq(TechTree.age("G4"), 0, "G4 Kamieniarstwo w epoce I")
	assert_eq(TechTree.requires("G4"), ["G1"] as Array[String], "G4 nadal wymaga G1")
	var r := Research.new()
	assert_eq(r.check("G4", 0), Research.Result.MISSING_REQUIREMENTS, "bez G1 G4 zablokowana")
	r.done["G1"] = true
	assert_eq(r.check("G4", 0), Research.Result.OK, "po G1 G4 da się badać w epoce I")
	assert_eq(BuildConfig.required_tech(K.QUARRY), "G4", "Kamieniołom nadal wymaga G4")
	# Budowa w zamku z epoki I (Dwór 1): bez G4 zablokowana w panelu, z G4 dostępna i staje na siatce.
	var grid := _castle()
	assert_eq(Ages.of_level(grid.manor_level()), 0, "zamek w epoce I")
	assert_true(not BuildConfig.is_unlocked(K.QUARRY, r), "z samą G1 Kamieniołomu nie ma")
	assert_eq(BuildPanel.state_text(K.QUARRY, r), "zbadaj G4", "panel budowy: zbadaj G4")
	r.done["G4"] = true
	assert_true(BuildConfig.is_unlocked(K.QUARRY, r), "z G4 Kamieniołom odblokowany")
	assert_eq(BuildPanel.state_text(K.QUARRY, r), "dostępny", "panel budowy: dostępny")
	assert_true(grid.place(_spot(grid, K.QUARRY), K.QUARRY, 1) != 0, "Kamieniołom staje w zamku z epoki I")
	return true
