extends TestCase
## Bitwa liczy się tylko z dozwolonego układu obrony (#374): zapis spoza gry (kopia zamku z serwera)
## może mieć pułapki i posterunki w dowolnym miejscu, a bitwa bierze tylko to, co postawiłby ekran
## Obrona. Pułapka spoza strefy, ponad limit Dworu albo bez wymagań nie działa; posterunek albo punkt
## patrolu spoza strefy i piechota na murze dają zadanie domyślne. Ten sam zapis daje tę samą bitwę.

const K := BuildingTypes.Kind
const U := UnitTypes.Unit
const TK := TrapConfig.Kind
const T := DefensePlan.Task
const PC_TEST := preload("res://tests/test_player_castle.gd")


func _research_all() -> Research:
	var r := Research.new()
	for code in TechTree.codes():
		r.done[code] = true
	return r


## Zamek bota z budynkami, których wymagają pułapki (jak w test_traps).
func _castle() -> BuildGrid:
	var g := BotCastle.generate(BotCastle.seed_for(1337, 0), 0).grid
	for kind: int in [K.HUNTER, K.LUMBER_HUT, K.FLETCHER, K.TAR_KILN]:
		g.place(g.spot_near(Vector2i(4, 4), kind, 40), kind, 1)
	return g


## Kratki strefy (w kolejności wierszy), na których pułapka `kind` może stanąć w pustym układzie.
func _spots(g: BuildGrid, kind: int) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	var empty := DefensePlan.new()
	var z := DefensePlan.zone(g)
	for y in range(z.position.y, z.end.y):
		for x in range(z.position.x, z.end.x):
			if empty.trap_place_problem(g, kind, Vector2i(x, y)).is_empty():
				out.append(Vector2i(x, y))
	return out


## Kratka mapy poza strefą obrony (róg najdalej od donżonu), na trawie.
func _outside(g: BuildGrid) -> Vector2i:
	var n := g.terrain.size - 1
	var c := DefensePlan.keep_center(g)
	var best := DefensePlan.NO_POST
	for p: Vector2i in [Vector2i(0, 0), Vector2i(n, 0), Vector2i(0, n), Vector2i(n, n)]:
		if best == DefensePlan.NO_POST or (p - c).length_squared() > (best - c).length_squared():
			best = p
	return best


func test_traps_outside_zone_are_dropped() -> bool:
	var g := _castle()
	var r := _research_all()
	var inside := _spots(g, TK.PIT)[0]
	var out := _outside(g)
	assert_true(not DefensePlan.zone(g).has_point(out), "kratka poza strefą")
	var p := DefensePlan.new()
	p.add_trap(TK.PIT, out)
	p.add_trap(TK.PIT, inside).revealed = true
	var got := p.battle_traps(g, r, 0)
	assert_eq(got.size(), 1, "pułapka spoza strefy odpada")
	assert_eq(got[0].cell, inside, "zostaje ta w strefie")
	assert_true(got[0].revealed, "z polem odsłonięcia")
	assert_eq(p.traps.size(), 2, "układ w zapisie bez zmian")
	var b := Battle.create_squads(g, g.keep_id(), [[U.AXE_WARRIOR, 4]], [], BotCastle.edge_road(g.terrain), 5)
	b.arm_traps(got)
	assert_eq(b.traps.size(), 1, "w bitwie działa jedna")
	assert_eq(b.traps[0].cell, inside, "ta w strefie")
	return true


func test_traps_wrong_place_limit_and_requirements() -> bool:
	var g := _castle()
	var r := _research_all()
	var limit := TrapConfig.limit(g.manor_level())
	var spots := _spots(g, TK.PIT)
	assert_true(spots.size() > limit + 2, "dość miejsc na test limitu")
	var p := DefensePlan.new()
	# Zrzucane kłody muszą stać tuż przed wałem: na kratce dla Wilczego dołu bez wału obok odpadają
	var logs_spots := _spots(g, TK.LOGS)
	var bad_logs := DefensePlan.NO_POST
	for c in spots:
		if not logs_spots.has(c):
			bad_logs = c
			break
	assert_true(bad_logs != DefensePlan.NO_POST, "kratka bez wału obok")
	p.add_trap(TK.LOGS, bad_logs)
	for i in limit + 2:
		if spots[i] != bad_logs:
			p.add_trap(TK.PIT, spots[i])
	var got := p.battle_traps(g, r, 0)
	assert_eq(got.size(), limit, "najwyżej limit Dworu")
	for t in got:
		assert_eq(t.kind, TK.PIT, "kłody w złym miejscu odpadają")
	assert_eq(got[0].cell, p.traps[1].cell, "w kolejności postawienia")
	assert_eq(p.battle_traps(g, Research.new(), 0).size(), 0, "bez technologii żadna nie działa")
	var pitch := DefensePlan.new()
	for c in _spots(g, TK.PITCH):
		pitch.add_trap(TK.PITCH, c)
		break
	assert_eq(pitch.traps.size(), 1, "jest miejsce na smołę")
	assert_eq(pitch.battle_traps(g, r, 0).size(), 0, "smoła w epoce I nie działa")
	assert_eq(pitch.battle_traps(g, r, 1).size(), 1, "w epoce II tak")
	return true


func test_posts_outside_zone_get_default_order() -> bool:
	var g := _castle()
	var gate := DefensePlan.main_gate(g)
	var wall := DefensePlan.default_wall_post(g, gate)
	assert_true(wall != DefensePlan.NO_POST, "zamek ma mur w strefie")
	var out := _outside(g)
	var inside := _spots(g, TK.PIT)[0]
	var ids: Array[int] = [1, 2, 3, 4, 5]
	var squads := [[U.AXE_WARRIOR, 6], [U.AXE_WARRIOR, 6], [U.AXE_WARRIOR, 6], [U.ARCHER, 6], [U.AXE_WARRIOR, 6]]
	var p := DefensePlan.new()
	p.set_post(1, out)  # Obrona odcinka poza strefą
	var patrol := p.set_task(2, T.PATROL)  # patrol z punktem trasy poza strefą
	patrol.post = inside
	patrol.route.append(out)
	p.set_post(3, wall)  # piechota na murze
	p.set_post(4, wall)  # strzelcy na murze: dozwolone
	p.set_post(5, inside)  # piechota w strefie: dozwolone
	var got := p.battle_orders(ids, squads, g, 0)
	var light := DefensePlan.default_order(g, RecruitmentConfig.UnitClass.LIGHT, 0)
	for i in 3:
		var label := "oddział %d: zadanie domyślne" % ids[i]
		if light == null:
			assert_eq(got[i], null, label)
			continue
		assert_true(got[i] != null, label)
		assert_eq(got[i].task, light.task, label)
		assert_eq(got[i].post, light.post, label)
		assert_true(got[i].route.is_empty(), label)
	assert_eq(got[3].post, wall, "strzelcy zostają na murze")
	assert_eq(got[4].post, inside, "posterunek w strefie zostaje")
	assert_eq(p.post_for(1), out, "układ w zapisie bez zmian")
	assert_true(DefensePlan.order_allowed(g, p.order_for(4), RecruitmentConfig.UnitClass.RANGED), "strzelcy na murze")
	assert_true(not DefensePlan.order_allowed(g, p.order_for(4), RecruitmentConfig.UnitClass.LIGHT), "piechota nie")
	return true


## Kopia zamku z PvP z obroną spoza strefy (zadanie i pułapka) liczy się jak bez nich, a ten sam
## zapis daje tę samą bitwę.
func test_player_castle_ignores_outside_zone_and_is_deterministic() -> bool:
	var castle := PC_TEST._castle(WorldSeed.first_playable(4242))
	var map_seed := WorldSeed.first_playable(4242)
	var grid := BuildGrid.new(TerrainMap.generate(map_seed))
	grid.place(grid.manor_spot(WorldSeed.MANOR_MAX_RING), K.MANOR, 1)
	grid.place(grid.keep_spot(WorldSeed.KEEP_MAX_RING), K.KEEP, 1)
	var out := _outside(grid)
	var bad := DefensePlan.new()
	bad.set_post(1, out)
	bad.add_trap(TK.PIT, out)
	var sums: Array[int] = []
	for defense: Dictionary in [{}, bad.to_dict(), bad.to_dict()]:
		var launch: Dictionary = PC_TEST._launch()
		launch["castle"] = castle.duplicate(true)
		launch["defense"] = JSON.parse_string(JSON.stringify(defense)) as Dictionary
		var pc := PlayerCastle.from_start(PC_TEST._start(), PC_TEST.ARMY, 0)
		assert_true(pc.apply_launch(launch), "kopia przyjęta")
		var b := pc.create_battle()
		assert_eq(b.traps.size(), 0, "pułapka spoza strefy nie działa")
		b.run()
		sums.append(b.checksum())
	assert_eq(sums[1], sums[0], "obrona spoza strefy jak brak obrony")
	assert_eq(sums[2], sums[1], "ten sam zapis, ta sama bitwa")
	return true
