extends TestCase
## Badania (#12): efekty technologii w bitwie (A1 Hartowane topory, A2 Łuk kompozytowy, O2 Zaostrzone
## pale) i manewry odblokowywane technologiami (A3 Podpalenie, A4 Oskrzydlenie, A5 Drabiny, A6 Taran).

const K := BuildingTypes.Kind
const U := UnitTypes.Unit
const M := AttackPlan.Manoeuvre
const SIDE := Battle.Side


func _research(codes: Array[String]) -> Research:
	var r := Research.new()
	for c in codes:
		r.done[c] = true
	return r


func _battle(attackers: Array, defenders: Array) -> Battle:
	var bot := BotCastle.generate(BotCastle.seed_for(1337, 0), 0)
	return Battle.create_squads(bot.grid, bot.objective, attackers, defenders, bot.spawn, 7)


func _first(b: Battle, side: int, unit: int) -> Battle.Fighter:
	for f in b.fighters:
		if f.side == side and f.unit == unit:
			return f
	return null


func test_a2_composite_bow_range() -> bool:
	var b := _battle([[U.ARCHER, 1], [U.REFLEX_ARCHER, 1], [U.JAVELINEER, 1]], [[U.ARCHER, 1]])
	var archer := _first(b, SIDE.ATTACKER, U.ARCHER)
	var reflex := _first(b, SIDE.ATTACKER, U.REFLEX_ARCHER)
	var jav := _first(b, SIDE.ATTACKER, U.JAVELINEER)
	var guard := _first(b, SIDE.DEFENDER, U.ARCHER)
	assert_eq(b.range_of(archer), UnitTypes.attack_range(U.ARCHER), "bez A2 zasięg z tabeli")
	b.apply_research(SIDE.ATTACKER, _research(["A2"] as Array[String]))
	assert_eq(b.range_of(archer), UnitTypes.attack_range(U.ARCHER) * 120 / 100, "A2: łucznik +20% (6 → 7)")
	assert_eq(b.range_of(archer), 7, "łucznik 7 kratek")
	assert_eq(b.range_of(reflex), 8, "łuk refleksyjny 7 → 8")
	assert_eq(b.range_of(jav), UnitTypes.attack_range(U.JAVELINEER), "oszczepnik bez zmian (to nie łuk)")
	assert_eq(b.range_of(guard), UnitTypes.attack_range(U.ARCHER), "A2 atakującego nie działa na obrońcę")
	b.apply_research(SIDE.DEFENDER, _research(["A2"] as Array[String]))
	assert_eq(b.range_of(guard), 7, "obrońca ze swoim A2")
	return true


func test_a1_tempered_axes_vs_wood() -> bool:
	var b := _battle([[U.AXE_WARRIOR, 1]], [])
	var axe := _first(b, SIDE.ATTACKER, U.AXE_WARRIOR)
	var palisade: Battle.Structure = null
	for id: int in b.structures:
		if b.structures[id].kind == K.PALISADE and palisade == null:
			palisade = b.structures[id]
	assert_true(palisade != null, "palisada na zamku-celu")
	var base := Battle.structure_damage(U.AXE_WARRIOR, K.PALISADE)
	var hits: Array[int] = []
	for with_a1: bool in [false, true]:
		var codes: Array[String] = []
		if with_a1:
			codes.append("A1")
		b.apply_research(SIDE.ATTACKER, _research(codes))
		palisade.hp = palisade.max_hp
		axe.cooldown = 0
		axe.charged = true
		# rozrzut ±10% z BattleRng: porównujemy średnią z wielu uderzeń
		var total := 0
		for i in 200:
			var before := palisade.hp
			axe.cooldown = 0
			b._strike_structure(axe, palisade)
			total += before - palisade.hp
			palisade.hp = palisade.max_hp
		hits.append(total)
	assert_true(absi(hits[0] - base * 200) <= base * 200 / 10, "bez A1 około podstawy")
	assert_true(hits[1] * 100 >= hits[0] * 110 and hits[1] * 100 <= hits[0] * 120, "A1: około +15% w drewno")
	return true


func test_o2_sharpened_stakes_palisade() -> bool:
	var b := _battle([[U.AXE_WARRIOR, 1]], [])
	var hp := {}
	for id: int in b.structures:
		hp[id] = b.structures[id].max_hp
	b.apply_research(SIDE.DEFENDER, _research(["O2"] as Array[String]))
	var palisades := 0
	for id: int in b.structures:
		var s := b.structures[id]
		if s.kind == K.PALISADE:
			palisades += 1
			assert_eq(s.max_hp, int(hp[id]) * 120 / 100, "palisada +20%")
			assert_eq(s.hp, s.max_hp, "pełna wytrzymałość")
		else:
			assert_eq(s.max_hp, int(hp[id]), "inne budynki bez zmian")
	assert_true(palisades > 0, "są palisady")
	var c := _battle([[U.AXE_WARRIOR, 1]], [])
	c.apply_research(SIDE.ATTACKER, _research(["O2"] as Array[String]))
	for id: int in c.structures:
		assert_eq(c.structures[id].max_hp, int(hp[id]), "O2 atakującego nie wzmacnia cudzych palisad")
	return true


func test_manoeuvres_need_their_technology() -> bool:
	var none := Research.new()
	assert_eq(AttackPlanner.next_manoeuvre(M.FRONTAL, 0, none), M.RANGED, "bez badań: Ostrzał")
	assert_eq(AttackPlanner.next_manoeuvre(M.RANGED, 0, none), M.FRONTAL, "Podpalenie i Oskrzydlenie zablokowane")
	var some := _research(["A3", "A4"] as Array[String])
	assert_eq(AttackPlanner.next_manoeuvre(M.RANGED, 0, some), M.FIRE, "A3: Podpalenie")
	assert_eq(AttackPlanner.next_manoeuvre(M.FIRE, 0, some), M.FLANK, "A4: Oskrzydlenie")
	assert_eq(AttackPlanner.next_manoeuvre(M.FLANK, 1, some), M.FRONTAL, "epoka II bez A5 i A6: bez drabin i taranu")
	var all := _research(["A3", "A4", "A5", "A6"] as Array[String])
	assert_eq(AttackPlanner.next_manoeuvre(M.FLANK, 1, all), M.LADDERS, "A5: Drabiny")
	assert_eq(AttackPlanner.next_manoeuvre(M.LADDERS, 1, all), M.RAM_GATE, "A6: Taranowanie")
	var p := AttackPlan.new()
	p.add(1, M.FLANK)
	assert_eq(p.problem(1, 0, none), "Oskrzydlenie: zbadaj A4 Taktyka oskrzydlenia", "plan z zablokowanym manewrem")
	assert_eq(p.problem(1, 0, some), "", "z A4 plan jest poprawny")
	assert_eq(p.problem(1, 0), "", "bez badań w wywołaniu (testy bitwy) sprawdzenie pominięte")
	for m in AttackPlan.MANOEUVRE_NAMES.size():
		var tech := AttackPlan.MANOEUVRE_TECH[m]
		assert_true(tech.is_empty() or TechTree.has(tech), "%s: technologia z drzewka MVP" % AttackPlan.MANOEUVRE_NAMES[m])
		assert_true(PixelFont.text_width(AttackPlan.tech_hint(m)) <= Hud.MESSAGE_MAX_WIDTH or tech.is_empty(),
				"komunikat %s mieści się" % AttackPlan.MANOEUVRE_NAMES[m])
	return true


## Kryterium #12: każda jednostka, budynek i manewr MVP ma technologię, która go odblokowuje, albo
## nie wymaga żadnej, a te technologie są w drzewku.
func test_everything_has_a_known_technology() -> bool:
	for u in UnitTypes.count():
		var tech := UnitTypes.required_tech(u)
		assert_true(tech.is_empty() or TechTree.has(tech), "%s: %s" % [UnitTypes.unit_name(u), tech])
	for k in BuildingTypes.NAMES.size():
		var tech := BuildConfig.required_tech(k)
		assert_true(tech.is_empty() or TechTree.has(tech), "%s: %s" % [BuildingTypes.NAMES[k], tech])
	return true


## Technologie nie psują determinizmu: ten sam stan badań i seed dają ten sam przebieg.
func test_research_effects_are_deterministic() -> bool:
	var r := _research(["A1", "A2", "O2"] as Array[String])
	var sums: Array[int] = []
	for i in 2:
		var b := _battle([[U.AXE_WARRIOR, 6], [U.ARCHER, 4]], [[U.ARCHER, 3], [U.PEASANT, 4]])
		b.apply_research(SIDE.ATTACKER, r)
		b.apply_research(SIDE.DEFENDER, r)
		b.run()
		sums.append(b.checksum())
	assert_eq(sums[0], sums[1], "ten sam przebieg")
	return true
