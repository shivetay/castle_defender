extends TestCase
## Pułapki (#100, lista zatwierdzona przez właściciela): wymagania (technologia, budynek, epoka),
## miejsce, limit Dworu, działanie w bitwie (raz na bitwę), zapis i ekran Obrona w trybie pułapek.

const K := BuildingTypes.Kind
const U := UnitTypes.Unit
const TK := TrapConfig.Kind


func _bot() -> BotCastle:
	return BotCastle.generate(BotCastle.seed_for(1337, 0), 0)


func _research_all() -> Research:
	var r := Research.new()
	for code in TechTree.codes():
		r.done[code] = true
	return r


## Zamek-cel z dopisanymi budynkami, których wymagają pułapki.
func _castle() -> BuildGrid:
	var g := _bot().grid
	for kind: int in [K.HUNTER, K.LUMBER_HUT, K.FLETCHER, K.TAR_KILN]:
		g.place(g.spot_near(Vector2i(4, 4), kind, 40), kind, 1)
	return g


## Pierwsza kratka (w kolejności wierszy strefy), na której pułapka `kind` może stanąć.
func _spot(p: DefensePlan, g: BuildGrid, kind: int) -> Vector2i:
	var z := DefensePlan.zone(g)
	for y in range(z.position.y, z.end.y):
		for x in range(z.position.x, z.end.x):
			if p.trap_place_problem(g, kind, Vector2i(x, y)).is_empty():
				return Vector2i(x, y)
	return Vector2i(-1, -1)


func _battle(g: BuildGrid, attackers: Array, defenders: Array, p: DefensePlan) -> Battle:
	var b := Battle.create_squads(g, g.keep_id(), attackers, defenders, BotCastle.edge_road(g.terrain), 5)
	b.arm_traps(p.traps)
	return b


func _put(f: Battle.Fighter, c: Vector2i) -> void:
	f.x = c.x * BattleConfig.SUB + BattleConfig.SUB / 2
	f.y = c.y * BattleConfig.SUB + BattleConfig.SUB / 2
	f.path.clear()


func _attackers(b: Battle) -> Array[Battle.Fighter]:
	var out: Array[Battle.Fighter] = []
	for f in b.fighters:
		if f.side == Battle.Side.ATTACKER:
			out.append(f)
	return out


func test_requirements_and_places() -> bool:
	var g := _castle()
	var r := Research.new()
	assert_eq(TrapConfig.requirement_problem(TK.PIT, g, r, 0), "Wilczy dół: zbadaj G18 Łowiectwo", "technologia")
	r.done["G18"] = true
	var bare := BuildGrid.new(TerrainMap.generate(WorldSeed.first_playable(1337)))
	bare.place(bare.manor_spot(64), K.MANOR, 1)
	bare.place(bare.keep_spot(64), K.KEEP, 1)
	assert_eq(TrapConfig.requirement_problem(TK.PIT, bare, r, 0), "Wilczy dół: postaw Chata myśliwego", "budynek")
	assert_eq(TrapConfig.requirement_problem(TK.PIT, g, r, 0), "", "spełnione")
	var all := _research_all()
	assert_eq(TrapConfig.requirement_problem(TK.CALTROPS, bare, all, 0), "", "Kolczatka: sama technologia O2")
	assert_eq(TrapConfig.requirement_problem(TK.FIRE_ARROWS, g, all, 0), "", "Płonące strzały: Strzałmistrz i Smolarnia")
	assert_eq(TrapConfig.requirement_problem(TK.PITCH, g, all, 0), "Wrząca smoła: Epoka II", "smoła od epoki II")
	assert_eq(TrapConfig.requirement_problem(TK.PITCH, g, all, 1), "", "w epoce II tak")
	for k in TrapConfig.count():
		assert_true(TechTree.has(TrapConfig.TECH[k]), "%s: technologia z drzewka MVP" % TrapConfig.NAMES[k])
		assert_true(PixelFont.text_width(TrapConfig.SHORT_NAMES[k]) <= DefensePanel.SQUAD_TILE.x - 12, "napis na kafelku")
	var p := DefensePlan.new()
	var keep := DefensePlan.keep_center(g)
	for k in TrapConfig.count():
		var c := _spot(p, g, k)
		assert_true(c.x >= 0, "%s: jest miejsce" % TrapConfig.NAMES[k])
		match TrapConfig.PLACE[k]:
			TrapConfig.Place.BEFORE_WALL:
				var ok := false
				for d: Vector2i in [Vector2i.UP, Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT]:
					if DefensePlan.wall_post(g, c + d) and (c - keep).length_squared() > (c + d - keep).length_squared():
						ok = true
				assert_true(ok, "kłody tuż przed murem, od zewnątrz")
			TrapConfig.Place.BEFORE_GATE:
				var gate := DefensePlan.main_gate(g)
				assert_true(g.buildings[gate].grow(1).has_point(c), "smoła tuż przed bramą")
	var grass := _spot(p, g, TK.PIT)
	assert_true(not p.trap_place_problem(g, TK.LOGS, grass).is_empty() or DefensePlan.wall_post(g, grass + Vector2i.RIGHT)
			or DefensePlan.wall_post(g, grass + Vector2i.LEFT) or DefensePlan.wall_post(g, grass + Vector2i.UP)
			or DefensePlan.wall_post(g, grass + Vector2i.DOWN), "kłody nie na zwykłej trawie")
	p.add_trap(TK.PIT, grass)
	assert_eq(p.trap_place_problem(g, TK.CALTROPS, grass), "Tu już jest pułapka", "jedna pułapka na kratkę")
	assert_eq(TrapConfig.limit(1), 2, "2 pułapki na poziom Dworu")
	assert_eq(TrapConfig.limit(3), 6, "Dwór 3: 6")
	return true


func test_pit_stops_and_hurts_once() -> bool:
	var g := _castle()
	var p := DefensePlan.new()
	var c := _spot(p, g, TK.PIT)
	p.add_trap(TK.PIT, c)
	var b := _battle(g, [[U.AXE_WARRIOR, 2], [U.RAM, 1]], [], p)
	var a := _attackers(b)
	_put(a[0], c)
	_put(a[1], c + Vector2i(10, 10))
	_put(a[2], c + Vector2i(12, 12))
	var hp := a[0].hp
	b._traps_act()
	assert_eq(a[0].hp, hp - TrapConfig.PIT_DAMAGE, "dół rani")
	assert_eq(a[0].stun, TrapConfig.PIT_STUN_S * BattleConfig.TICK_HZ, "i zatrzymuje")
	var x := a[0].x
	b._act(a[0])
	assert_eq(a[0].x, x, "w dole nie idzie")
	_put(a[1], c)
	b._traps_act()
	assert_eq(a[1].hp, UnitTypes.hp(U.AXE_WARRIOR), "drugi raz nie działa")
	# taran w dole: stoi dłużej, bez obrażeń
	var p2 := DefensePlan.new()
	p2.add_trap(TK.PIT, c)
	var b2 := _battle(g, [[U.RAM, 1]], [], p2)
	var ram := _attackers(b2)[0]
	_put(ram, c)
	b2._traps_act()
	assert_eq(ram.stun, TrapConfig.PIT_RAM_STUN_S * BattleConfig.TICK_HZ, "taran ugrzązł na 5 s")
	assert_eq(ram.hp, UnitTypes.hp(U.RAM), "bez obrażeń")
	return true


func test_caltrops_hurt_over_time_and_slow_cavalry() -> bool:
	var g := _castle()
	var p := DefensePlan.new()
	var c := _spot(p, g, TK.CALTROPS)
	p.add_trap(TK.CALTROPS, c)
	var b := _battle(g, [[U.AXE_WARRIOR, 1], [U.RIDER, 1]], [], p)
	var a := _attackers(b)
	_put(a[0], c)
	_put(a[1], c + Vector2i.RIGHT)
	var hp := a[0].hp
	var rider_hp := a[1].hp
	for t in TrapConfig.CALTROPS_S * BattleConfig.TICK_HZ + 60:
		b.tick += 1
		b._traps_act()
	assert_eq(a[0].hp, hp - TrapConfig.CALTROPS_S * TrapConfig.CALTROPS_DAMAGE_PER_S, "5 HP na sekundę przez 8 s")
	assert_true(a[1].hp < rider_hp, "obok kratki też rani")
	# spowolnienie konnicy w działającej Kolczatce
	var b2 := _battle(g, [[U.RIDER, 1]], [], p)
	var r := _attackers(b2)[0]
	_put(r, c)
	b2._traps_act()
	var x0 := r.x
	b2._move_toward(r, r.x + 10 * BattleConfig.SUB, r.y)
	var slow := r.x - x0
	var b3 := _battle(g, [[U.RIDER, 1]], [], DefensePlan.new())
	var r3 := _attackers(b3)[0]
	_put(r3, c)
	var x3 := r3.x
	b3._move_toward(r3, r3.x + 10 * BattleConfig.SUB, r3.y)
	assert_eq(slow * 2, r3.x - x3, "konnica w kolczatce 2× wolniej")
	return true


func test_logs_hit_three_cells_along_the_wall() -> bool:
	var g := _castle()
	var p := DefensePlan.new()
	var c := _spot(p, g, TK.LOGS)
	p.add_trap(TK.LOGS, c)
	var b := _battle(g, [[U.AXE_WARRIOR, 3]], [], p)
	var st := b.traps[0]
	assert_eq(st.area.size(), 3, "3 kratki")
	var along := st.area[2] - st.area[0]
	for d: Vector2i in [Vector2i.UP, Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT]:
		if DefensePlan.wall_post(g, c + d):
			assert_eq(along.x * d.x + along.y * d.y, 0, "wzdłuż muru, nie w poprzek")
	var a := _attackers(b)
	_put(a[0], st.area[0])
	_put(a[1], st.area[2])
	_put(a[2], c + (st.area[2] - c) * 3)
	b._traps_act()
	assert_eq(a[0].hp, UnitTypes.hp(U.AXE_WARRIOR) - TrapConfig.LOGS_DAMAGE, "kłody biją na kratce obok")
	assert_eq(a[1].hp, UnitTypes.hp(U.AXE_WARRIOR) - TrapConfig.LOGS_DAMAGE, "i na drugiej")
	assert_eq(a[2].hp, UnitTypes.hp(U.AXE_WARRIOR), "dalej nie")
	return true


func test_fire_arrows_boost_and_ignite_ram() -> bool:
	var g := _castle()
	var p := DefensePlan.new()
	var c := _spot(p, g, TK.FIRE_ARROWS)
	p.add_trap(TK.FIRE_ARROWS, c)
	var b := _battle(g, [[U.RAM, 1], [U.AXE_WARRIOR, 1]], [[U.ARCHER, 1]], p)
	var archer: Battle.Fighter = null
	for f in b.fighters:
		if f.side == Battle.Side.DEFENDER:
			archer = f
	var ram := _attackers(b)[0]
	var axe := _attackers(b)[1]
	_put(archer, c)
	_put(axe, c + Vector2i(30, 30))
	_put(ram, c + Vector2i(3, 0))
	b._traps_act()
	assert_true(b.traps[0].fired, "wróg 3 kratki od kosza: płonące strzały ruszają")
	assert_true(b._fire_arrows_near(c + Vector2i(2, 2)), "strzelcy do 2 kratek od kosza")
	assert_true(not b._fire_arrows_near(c + Vector2i(3, 0)), "dalej nie")
	archer.cooldown = 0
	b._strike_unit(archer, ram)
	assert_true(ram.fire > 0, "taran płonie")
	_put(axe, c + Vector2i(2, 0))
	archer.cooldown = 0
	b._strike_unit(archer, axe)
	assert_eq(axe.fire, 0, "topornik nie płonie (podpala tylko Taran i Podpalacza)")
	var hp := ram.hp
	for t in 2 * BattleConfig.TICK_HZ:
		b.tick += 1
		b._traps_act()
	assert_true(ram.hp < hp, "płonący taran traci HP")
	return true


func test_pitch_at_gate() -> bool:
	var g := _castle()
	var p := DefensePlan.new()
	var c := _spot(p, g, TK.PITCH)
	p.add_trap(TK.PITCH, c)
	var b := _battle(g, [[U.RAM, 1], [U.AXE_WARRIOR, 1]], [], p)
	var a := _attackers(b)
	var gate := DefensePlan.main_gate(g)
	var gate_hp := b.structures[gate].hp
	_put(a[0], c)
	_put(a[1], c + Vector2i(20, 20))
	b._traps_act()
	assert_eq(a[0].hp, UnitTypes.hp(U.RAM) - TrapConfig.PITCH_DAMAGE, "smoła rani")
	assert_true(a[0].fire > 0, "i podpala")
	assert_eq(a[1].hp, UnitTypes.hp(U.AXE_WARRIOR), "daleko nic")
	assert_eq(b.structures[gate].hp, gate_hp, "brama nie cierpi")
	return true


## Ten sam układ z pułapkami i ten sam seed: ten sam przebieg; pułapki zmieniają przebieg; układ
## po bitwie zostaje nietknięty (odnawia się).
func test_traps_deterministic_and_renewed() -> bool:
	var g := _castle()
	var p := DefensePlan.new()
	for k: int in [TK.PIT, TK.CALTROPS, TK.LOGS, TK.FIRE_ARROWS]:
		p.add_trap(k, _spot(p, g, k))
	var bot := _bot()
	var sums: Array[int] = []
	for i in 2:
		var b := Battle.create_squads(g, g.keep_id(), PveWaves.squads(4), [[U.ARCHER, 6], [U.AXE_WARRIOR, 6]],
				bot.spawn, 13)
		b.arm_traps(p.traps)
		b.run()
		sums.append(b.checksum())
	assert_eq(sums[0], sums[1], "ten sam przebieg")
	var plain := Battle.create_squads(g, g.keep_id(), PveWaves.squads(4), [[U.ARCHER, 6], [U.AXE_WARRIOR, 6]], bot.spawn, 13)
	plain.run()
	assert_true(plain.checksum() != sums[0], "pułapki coś zmieniają")
	assert_eq(p.traps.size(), 4, "układ po bitwie bez zmian: pułapki się odnawiają")
	return true


func test_save_and_panel() -> bool:
	var g := _castle()
	var p := DefensePlan.new()
	var c := _spot(p, g, TK.CALTROPS)
	p.add_trap(TK.CALTROPS, c).revealed = true
	var d := p.to_dict()
	var q := DefensePlan.from_dict(JSON.parse_string(JSON.stringify(d)) as Dictionary)
	assert_eq(q.to_dict(), d, "zapis pułapek")
	assert_true(q.trap_at(c).revealed, "z polem odsłonięta (#28)")
	# ekran Obrona w trybie pułapek
	var e := Economy.new(0)
	for res in EconomyConfig.count():
		e.amounts[res] = 500
	var goods := Goods.new(0)
	var panel := DefensePanel.new()
	panel.research = _research_all()
	panel.economy = e
	panel.goods = goods
	var plan := DefensePlan.new()
	panel.open(plan, [[U.ARCHER, 2]], [1] as Array[int], g, 0)
	panel.activate(DefensePanel.Target.TRAPS)
	assert_true(panel.trap_mode, "Pułapki: tryb pułapek")
	panel.activate(DefensePanel.Target.SQUAD + TK.PIT)
	var spot := _spot(plan, g, TK.PIT)
	var wood := e.amounts[0]
	assert_eq(panel.tap(g, spot), "Postawiono: Wilczy dół (1/%d)" % TrapConfig.limit(g.manor_level()), "stawia")
	assert_eq(e.amounts[0], wood - int((TrapConfig.COST[TK.PIT] as Array)[0]), "koszt schodzi")
	assert_eq(panel.tap(g, spot), "Usunięto: Wilczy dół", "dotknięcie pułapki ją usuwa")
	assert_eq(plan.traps.size(), 0, "bez pułapki")
	panel.activate(DefensePanel.Target.SQUAD + TK.FIRE_ARROWS)
	var arrows := _spot(plan, g, TK.FIRE_ARROWS)
	assert_true(panel.tap(g, arrows).begins_with("Brak towarów"), "płonące strzały wymagają smoły i strzał")
	goods.add(GoodsConfig.Good.PITCH, 2)
	goods.add(GoodsConfig.Good.ARROW, 10)
	assert_true(panel.tap(g, arrows).begins_with("Postawiono"), "z towarami stawia")
	assert_eq(goods.amounts[GoodsConfig.Good.ARROW], 5, "zbrojownia oddaje 5 strzał")
	panel.activate(DefensePanel.Target.SQUAD + TK.PITCH)
	assert_eq(panel.tap(g, _spot(plan, g, TK.PITCH)), "Wrząca smoła: Epoka II", "smoła zablokowana w epoce I")
	for i in TrapConfig.limit(g.manor_level()):
		panel.trap_kind = TK.CALTROPS
		panel.tap(g, _spot(plan, g, TK.CALTROPS))
	assert_eq(plan.traps.size(), TrapConfig.limit(g.manor_level()), "do limitu")
	panel.trap_kind = TK.CALTROPS
	assert_true(panel.tap(g, _spot(plan, g, TK.CALTROPS)).begins_with("Limit pułapek"), "ponad limit nie")
	var view := Vector2(320, 180)
	var b := Hud.content_bounds(view, Rect2())
	assert_eq(DefensePanel.target_at(Hud.column_rect(b.y, 0).get_center(), view, b.x, b.y, 5, 0, true),
			DefensePanel.Target.CREW, "Załoga na górze kolumny")
	assert_eq(DefensePanel.target_at(DefensePanel.tile_rect(view, b.x, 4).get_center(), view, b.x, b.y, 5, 0, true),
			DefensePanel.Target.SQUAD + 4, "piąty kafelek pułapki")
	panel.activate(DefensePanel.Target.CREW)
	assert_true(not panel.trap_mode, "Załoga wraca do oddziałów")
	panel.activate(DefensePanel.Target.TRAPS)
	panel.activate(DefensePanel.Target.SQUAD + TK.LOGS)
	panel.open(plan, [[U.ARCHER, 2]], [1] as Array[int], g, 0)
	assert_true(not panel.trap_mode and panel.trap_kind == 0, "ponowne otwarcie zaczyna od załogi (review #186)")
	assert_true(PixelFont.text_width(DefensePanel.TRAP_HINT) <= Hud.MESSAGE_MAX_WIDTH, "podpowiedź mieści się")
	for k in TrapConfig.count():
		assert_true(PixelFont.text_width("Brak surowców: " + TrapConfig.cost_text(k)) <= Hud.MESSAGE_MAX_WIDTH,
				"%s: komunikat mieści się" % TrapConfig.NAMES[k])
	panel.free()
	return true
