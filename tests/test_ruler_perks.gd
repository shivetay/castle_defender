extends TestCase
## Perki władcy z technologii (#308, ADR 0002; wcześniej wybór z listy, #32): 4 linie z poziomami, pierwsza
## technologia perkowa blokuje pozostałe linie, perk liczony z badań (zapis, kopia zamku z serwera, koniec
## badania), efekty w gospodarce (Gospodarny, Budowniczy) i w bitwie (Zdobywca, Gospodarz grodu, Ukochany
## władca), Łupieżca w łupie z PvP, ten sam przebieg w powtórce i zgodność liczb z migracją serwera.

const K := BuildingTypes.Kind
const U := UnitTypes.Unit
const P := RulerPerks.Perk
const RR := Research.Result
const SIDE := Battle.Side
const SPAWN := Vector2i(32, 60)
const MIGRATION := "res://supabase/migrations/20261126121609_ruler_perk_research.sql"
const REPLAY := preload("res://tests/test_replay.gd")


func _done(codes: Array) -> Dictionary:
	var d := {}
	for c: String in codes:
		d[c] = true
	return d


func _grid() -> BuildGrid:
	return BuildGrid.new(TerrainMap.generate(1337))


## Pole bitwy bez umocnień: cel to Dwór; perk obrońcy z siatki.
func _battle(attackers: Array, defenders: Array, seed_value: int = 1, defender_perk: int = P.NONE) -> Battle:
	var grid := _grid()
	grid.ruler_perk = defender_perk
	var objective := grid.place(grid.manor_spot(64), K.MANOR, 3)
	return Battle.create_squads(grid, objective, attackers, defenders, SPAWN, seed_value)


func _first(b: Battle, side: int, squad: int = 1) -> Battle.Fighter:
	for f in b.fighters:
		if f.side == side and f.squad == squad:
			return f
	return null


func test_lines_are_technologies() -> bool:
	assert_eq(RulerPerks.count(), 8, "8 stanów perka: 4 linie po 2 poziomy")
	assert_eq(RulerPerks.SLOTS, 1, "1 miejsce na perk z technologii")
	assert_eq(RulerPerks.LINE_NAMES, ["Zdobywca", "Gospodarz grodu", "Gospodarny", "Ukochany władca"] as Array[String],
			"linie")
	var branches: Array[int] = [TechTree.Branch.ATTACK, TechTree.Branch.DEFENSE, TechTree.Branch.ECONOMY,
			TechTree.Branch.UTILITY]
	for line in RulerPerks.LINES.size():
		var codes: Array = RulerPerks.LINES[line]
		for level in codes.size():
			var code: String = codes[level]
			assert_true(TechTree.has(code), "%s w drzewku" % code)
			assert_eq(TechTree.branch(code), branches[line], "%s w gałęzi kategorii" % code)
			assert_eq(TechTree.age(code), level, "%s: poziom %d w epoce %d" % [code, level + 1, level + 1])
			assert_eq(RulerPerks.line_of(code), line, "%s w linii %d" % [code, line])
			assert_eq(RulerPerks.line_of_perk(int(RulerPerks.LINE_PERKS[line][level])), line, "stan w linii")
		assert_eq(TechTree.requires(codes[0] as String), [] as Array[String], "poziom 1 bez wymagań")
		assert_eq(TechTree.requires(codes[1] as String), [codes[0] as String] as Array[String], "poziom 2 wymaga 1")
	assert_eq(RulerPerks.line_of("A1"), -1, "zwykła technologia")
	assert_eq(RulerPerks.tech_codes().size(), 8, "8 technologii perków")
	for p in RulerPerks.count():
		assert_true(RulerPerks.line_of_perk(p) >= 0, "każdy stan w linii")
	return true


## Perk z badań: najwyższy poziom jednej linii, do którego są niższe, nie wyższy niż epoka; dwie linie: brak.
func test_perk_from_research() -> bool:
	assert_eq(RulerPerks.from_done({}, 1), P.NONE, "bez technologii brak")
	assert_eq(RulerPerks.from_done(_done(["A60"]), 0), P.CONQUEROR, "A60: Zdobywca")
	assert_eq(RulerPerks.from_done(_done(["O23"]), 0), P.STEWARD, "O23")
	assert_eq(RulerPerks.from_done(_done(["G25"]), 0), P.THRIFTY, "G25")
	assert_eq(RulerPerks.from_done(_done(["U14"]), 0), P.BELOVED, "U14")
	assert_eq(RulerPerks.from_done(_done(["A60", "A61"]), 1), P.LOOTER, "A61: Zdobywca i Łupieżca")
	assert_eq(RulerPerks.from_done(_done(["O23", "O24"]), 1), P.STEWARD_2, "O24")
	assert_eq(RulerPerks.from_done(_done(["G25", "G26"]), 1), P.BUILDER, "G26: Gospodarny i Budowniczy")
	assert_eq(RulerPerks.from_done(_done(["U14", "U15"]), 1), P.BELOVED_2, "U15")
	assert_eq(RulerPerks.from_done(_done(["A60", "A61"]), 0), P.CONQUEROR, "poziom 2 w epoce I nie działa")
	assert_eq(RulerPerks.from_done(_done(["A61"]), 1), P.NONE, "poziom 2 bez poziomu 1")
	assert_eq(RulerPerks.from_done(_done(["A60", "G25"]), 1), P.NONE, "dwie linie: brak perka")
	assert_eq(RulerPerks.from_done(_done(["A1", "G1", "G25"]), 0), P.THRIFTY, "inne technologie bez znaczenia")
	assert_eq(RulerPerks.from_research(null, 1), P.NONE, "bez badań")
	return true


## Pierwsza technologia perkowa (badana albo zbadana) wybiera linię: pozostałe linie są zablokowane na stałe.
func test_first_perk_tech_locks_other_lines() -> bool:
	var r := Research.new()
	var e := Economy.new(0)
	e.capacities.fill(1000000)
	for res in EconomyConfig.count():
		e.amounts[res] = 100000
	for code in RulerPerks.tech_codes():
		if TechTree.age(code) == 0:
			assert_eq(r.check(code, 0), RR.OK, "%s na start do zbadania" % code)
	assert_eq(r.start("G25", 0, e, 0), RR.OK, "badanie Gospodarnego")
	assert_eq(RulerPerks.chosen_line(r.done, r.active), 2, "linia wybrana już w trakcie badania")
	assert_eq(r.check("A60", 0), RR.RULER_PERK_LOCKED, "w trakcie: inne linie zablokowane")
	r.update(r.finish_ms())
	for code: String in ["A60", "A61", "O23", "O24", "U14", "U15"]:
		assert_eq(r.check(code, 1), RR.RULER_PERK_LOCKED, "%s zablokowana" % code)
		assert_eq(ResearchPanel.state_text(r, code, 1, 0), "inny perk władcy", "%s: stan na kafelku" % code)
	assert_eq(r.check("G26", 0), RR.WRONG_AGE, "poziom 2 dopiero w epoce II")
	assert_eq(r.check("G26", 1), RR.OK, "w epoce II poziom 2 tej samej linii")
	assert_eq(r.check("A1", 0), RR.OK, "zwykłe technologie bez zmian")
	assert_true(PixelFont.text_width(Research.MESSAGES[RR.RULER_PERK_LOCKED]) <= 320 - 16, "komunikat mieści się")
	return true


## Ukończone badanie technologii perkowej od razu ustawia perk zamku (BuildQueue.update).
func test_research_completion_sets_perk() -> bool:
	var grid := _grid()
	grid.place(grid.manor_spot(64), K.MANOR, 2)
	var e := Economy.new(0)
	e.capacities.fill(1000000)
	for res in EconomyConfig.count():
		e.amounts[res] = 100000
	var r := Research.new()
	assert_eq(r.start("G25", 0, e, 0, grid), RR.OK, "badanie w Dworze")
	var q := BuildQueue.new()
	q.update(r.finish_ms() - 1, grid, e, r)
	assert_eq(grid.ruler_perk, P.NONE, "przed końcem badania bez perka")
	q.update(r.finish_ms() + 1000, grid, e, r)
	assert_eq(grid.ruler_perk, P.THRIFTY, "po badaniu Gospodarny")
	return true


func test_save_round_trip() -> bool:
	var grid := _grid()
	grid.place(grid.manor_spot(64), K.MANOR, 2)
	var research := Research.new()
	research.done["G25"] = true
	var d := SaveGame.to_dict(1337, grid, Economy.new(0), BuildQueue.new(), research)
	assert_eq(int(d["version"]), 12, "wersja 12")
	assert_true(not d.has("ruler"), "perk nie trafia do zapisu, wynika z badań")
	var s := SaveGame.from_dict(JSON.parse_string(JSON.stringify(d)) as Dictionary, 0)
	assert_eq(s.grid.ruler_perk, P.THRIFTY, "perk z badań działa w siatce zamku")
	# stary wpis `ruler` z perkiem wybranym z listy (#32) się pomija
	d["ruler"] = {"perk": P.CONQUEROR, "free_ms": 5000}
	var old := SaveGame.from_dict(d, 0)
	assert_eq(old.grid.ruler_perk, P.THRIFTY, "perk z listy nie działa")
	assert_eq(old.skipped, 0, "stary wpis bez błędu")
	(d["research"] as Dictionary)["done"] = ["G25", "A60"]
	assert_eq(SaveGame.from_dict(d, 0).grid.ruler_perk, P.NONE, "dwie linie z edycji zapisu: brak perka")
	(d["research"] as Dictionary)["done"] = []
	assert_eq(SaveGame.from_dict(d, 0).grid.ruler_perk, P.NONE, "bez badań bez perka")
	return true


## Poziom 2 (ADR 0002): Łupieżca i Budowniczy dokładają efekt do poziomu 1, Gospodarz grodu i Ukochany
## władca rosną do 15.
func test_level_two_effects() -> bool:
	assert_true(RulerPerks.has_conqueror(P.CONQUEROR) and RulerPerks.has_conqueror(P.LOOTER), "Zdobywca na obu poziomach")
	assert_true(not RulerPerks.has_conqueror(P.STEWARD), "inna linia bez Zdobywcy")
	assert_eq(RulerPerks.pvp_loot(100, P.CONQUEROR), 100, "Łupieżca dopiero na poziomie 2")
	assert_eq(RulerPerks.production_bonus(P.BUILDER), RulerPerks.THRIFTY_PRODUCTION_BONUS, "Gospodarny na poziomie 2")
	assert_eq(RulerPerks.build_time_ms(1000, P.THRIFTY), 1000, "Budowniczy dopiero na poziomie 2")
	assert_eq(RulerPerks.steward_hp_percent(P.STEWARD), 110, "Gospodarz grodu +10%")
	assert_eq(RulerPerks.steward_hp_percent(P.STEWARD_2), 115, "Gospodarz grodu II +15%")
	assert_eq(RulerPerks.steward_hp_percent(P.NONE), 100, "bez perka")
	assert_eq(RulerPerks.beloved_morale(P.BELOVED), 10, "Ukochany władca +10")
	assert_eq(RulerPerks.beloved_morale(P.BELOVED_2), 15, "Ukochany władca II +15")
	var b := _battle([[U.AXE_WARRIOR, 1]], [[U.AXE_WARRIOR, 1]], 1, P.BELOVED_2)
	assert_eq(b.squad_morale(SIDE.DEFENDER, 1), BattleConfig.MORALE_START + RulerPerks.BELOVED_2_MORALE, "morale +15")
	var grid := _grid()
	var keep := grid.place(grid.keep_spot(64), K.KEEP, 1)
	var plain := Battle.create_squads(grid, keep, [[U.AXE_WARRIOR, 1]], [], SPAWN, 1)
	grid.ruler_perk = P.STEWARD_2
	var strong := Battle.create_squads(grid, keep, [[U.AXE_WARRIOR, 1]], [], SPAWN, 1)
	assert_eq(strong.structures[keep].max_hp, plain.structures[keep].max_hp * RulerPerks.STEWARD_2_HP_PERCENT / 100,
			"budynki +15%")
	var looter := _battle([[U.AXE_WARRIOR, 1]], [[U.AXE_WARRIOR, 1]])
	var axe := _first(looter, SIDE.ATTACKER)
	var enemy := _first(looter, SIDE.DEFENDER)
	var dmg := looter.unit_damage(axe, enemy)
	looter.set_ruler_perk(SIDE.ATTACKER, P.LOOTER)
	assert_eq(looter.unit_damage(axe, enemy), dmg * RulerPerks.CONQUEROR_DAMAGE_PERCENT / 100, "Łupieżca z Zdobywcą")
	return true


## Gospodarny: +10 punktów procentowych do produkcji każdego surowca (i do limitu żywności armii).
func test_thrifty_raises_production() -> bool:
	var grid := _grid()
	grid.place(grid.manor_spot(64), K.MANOR, 2)
	var base := Economy.rates(grid)
	var research := Research.new()
	research.done["G2"] = true
	var g2 := Economy.rates(grid, research)
	grid.ruler_perk = P.THRIFTY
	var with := Economy.rates(grid)
	for res in base.size():
		assert_eq(with[res], base[res] * (100 + RulerPerks.THRIFTY_PRODUCTION_BONUS) / 100, "+10%% surowca %d" % res)
	var food := EconomyConfig.Res.FOOD
	var g2_percent := research.production_percent(food)
	assert_eq(Economy.rates(grid, research)[food],
			base[food] * (g2_percent + RulerPerks.THRIFTY_PRODUCTION_BONUS) / 100, "premie się sumują")
	assert_true(Economy.rates(grid, research)[food] > g2[food], "więcej niż z samym G2")
	assert_eq(Recruitment.upkeep_limit(grid, null), with[food], "limit utrzymania z perkiem")
	grid.ruler_perk = P.CONQUEROR
	assert_eq(Economy.rates(grid), base, "inny perk nie zmienia produkcji")
	return true


## Budowniczy: zlecenie budowy trwa 10% krócej; zmiana perka nie przelicza zleceń w kolejce.
func test_builder_shortens_build_time() -> bool:
	var grid := _grid()
	var manor := grid.place(grid.manor_spot(64), K.MANOR, 2)
	var e := Economy.new(0)
	e.capacities.fill(1000000)
	for res in EconomyConfig.count():
		e.amounts[res] = 100000
	var q := BuildQueue.new()
	grid.ruler_perk = P.BUILDER
	assert_eq(q.order_upgrade(grid, e, manor, 0), BuildQueue.Result.OK, "zlecenie")
	var plain := BuildConfig.time_ms(K.MANOR, 3)
	assert_eq(q.orders[0].duration_ms, plain * RulerPerks.BUILDER_TIME_PERCENT / 100, "-10% czasu")
	grid.ruler_perk = P.NONE
	assert_eq(q.orders[0].duration_ms, plain * RulerPerks.BUILDER_TIME_PERCENT / 100, "zlecenie zostaje krótsze")
	var plain_q := BuildQueue.new()
	assert_eq(plain_q.order_upgrade(grid, e, manor, 0), BuildQueue.Result.OK, "zlecenie bez perka")
	assert_eq(plain_q.orders[0].duration_ms, plain, "bez perka pełny czas")
	assert_eq(RulerPerks.build_time_ms(plain, P.CONQUEROR), plain, "inny perk bez zmian")
	return true


## Zdobywca: +10% obrażeń wszystkich oddziałów atakującego, w jednostki i budynki; obrońcy nie dotyczy.
func test_conqueror_boosts_attackers_only() -> bool:
	var b := _battle([[U.AXE_WARRIOR, 1], [U.ARCHER, 1]], [[U.AXE_WARRIOR, 1]])
	var axe := _first(b, SIDE.ATTACKER, 1)
	var archer := _first(b, SIDE.ATTACKER, 2)
	var enemy := _first(b, SIDE.DEFENDER)
	var axe_dmg := b.unit_damage(axe, enemy)
	var archer_dmg := b.unit_damage(archer, enemy)
	var back := b.unit_damage(enemy, axe)
	b.set_ruler_perk(SIDE.ATTACKER, P.CONQUEROR)
	assert_eq(b.unit_damage(axe, enemy), axe_dmg * RulerPerks.CONQUEROR_DAMAGE_PERCENT / 100, "piechota +10%")
	assert_eq(b.unit_damage(archer, enemy), archer_dmg * RulerPerks.CONQUEROR_DAMAGE_PERCENT / 100, "strzelcy +10%")
	assert_eq(b.unit_damage(enemy, axe), back, "obrońca bez premii")
	b.set_ruler_perk(SIDE.ATTACKER, P.LOOTER)
	assert_true(b.ruler_perk_is(SIDE.ATTACKER, P.CONQUEROR), "jeden perk na bitwę")
	var d := _battle([[U.AXE_WARRIOR, 1]], [[U.AXE_WARRIOR, 1]])
	d.set_ruler_perk(SIDE.DEFENDER, P.CONQUEROR)
	assert_true(d.ruler_perks.is_empty(), "perk obrońcy idzie tylko z siatki zamku")
	return true


## Gospodarz grodu: wszystkie budynki obrońcy +10% wytrzymałości (razem z premiami umocnień).
func test_steward_strengthens_buildings() -> bool:
	var grid := _grid()
	var keep := grid.place(grid.keep_spot(64), K.KEEP, 1)
	var ring := grid.buildings[keep].grow(2)
	var pal := grid.place(Rect2i(ring.position.x, ring.position.y, 1, 1), K.PALISADE, 1)
	var plain := Battle.create_squads(grid, keep, [[U.AXE_WARRIOR, 1]], [], SPAWN, 1)
	grid.ruler_perk = P.STEWARD
	var b := Battle.create_squads(grid, keep, [[U.AXE_WARRIOR, 1]], [], SPAWN, 1)
	for id: int in [keep, pal]:
		assert_eq(b.structures[id].max_hp, plain.structures[id].max_hp * RulerPerks.STEWARD_HP_PERCENT / 100,
				"budynek %d +10%%" % id)
		assert_eq(b.structures[id].hp, b.structures[id].max_hp, "pełne życie na start")
	var research := Research.new()
	research.done["O2"] = true
	b.apply_research(SIDE.DEFENDER, research)
	var steward_pal := plain.structures[pal].max_hp * RulerPerks.STEWARD_HP_PERCENT / 100
	assert_eq(b.structures[pal].max_hp, steward_pal * BattleConfig.O2_PALISADE_HP_PERCENT / 100, "O2 na wzmocnioną")
	b.apply_research(SIDE.DEFENDER, research)
	assert_eq(b.structures[pal].max_hp, steward_pal * BattleConfig.O2_PALISADE_HP_PERCENT / 100, "bez podwójnej premii")
	return true


func test_beloved_raises_garrison_morale() -> bool:
	var b := _battle([[U.AXE_WARRIOR, 1]], [[U.AXE_WARRIOR, 1], [U.ARCHER, 1]], 1, P.BELOVED)
	assert_eq(b.squad_morale(SIDE.DEFENDER, 1), BattleConfig.MORALE_START + RulerPerks.BELOVED_MORALE, "oddział 1")
	assert_eq(b.squad_morale(SIDE.DEFENDER, 2), BattleConfig.MORALE_START + RulerPerks.BELOVED_MORALE, "oddział 2")
	assert_eq(b.squad_morale(SIDE.ATTACKER, 1), BattleConfig.MORALE_START, "atakujący bez premii")
	var c := _battle([[U.AXE_WARRIOR, 1]], [[U.AXE_WARRIOR, 1]])
	c.set_ruler_perk(SIDE.ATTACKER, P.BELOVED)
	assert_eq(c.squad_morale(SIDE.ATTACKER, 1), BattleConfig.MORALE_START, "w ataku Ukochany nic nie daje")
	return true


## Kryterium akceptacji #32: wybrany perk zmienia przebieg bitwy, a ten sam seed i perk dają ten sam przebieg.
func test_perk_changes_battle_deterministically() -> bool:
	var army := [[U.AXE_WARRIOR, 6], [U.SPEARMAN, 4]]
	var crew := [[U.AXE_WARRIOR, 6], [U.SHIELDBEARER, 4]]
	var plain := _battle(army, crew, 5)
	var led := _battle(army, crew, 5)
	led.set_ruler_perk(SIDE.ATTACKER, P.CONQUEROR)
	plain.run()
	led.run()
	assert_true(plain.checksum() != led.checksum(), "Zdobywca zmienia przebieg")
	var again := _battle(army, crew, 5)
	again.set_ruler_perk(SIDE.ATTACKER, P.CONQUEROR)
	again.run()
	assert_eq(again.checksum(), led.checksum(), "ten sam seed i perk: ten sam przebieg")
	var beloved := _battle(army, crew, 5, P.BELOVED)
	beloved.run()
	assert_true(beloved.checksum() != plain.checksum(), "Ukochany władca zmienia obronę")
	return true


## Łupieżca: +15% łupu z PvP, w dół, przed limitem capacity, tak jak `end_attack` liczy limit.
func test_looter_raises_pvp_loot() -> bool:
	var plain := BattleResult.new()
	plain.won = true
	plain.percent = 60
	plain.compute_player_loot([1000, 1000, 1000, 100])
	var looter := BattleResult.new()
	looter.won = true
	looter.percent = 60
	looter.compute_player_loot([1000, 1000, 1000, 100], P.LOOTER)
	assert_eq(plain.loot, [60, 60, 60, 6] as Array[int], "zwykły łup jak limit serwera")
	assert_eq(looter.loot, [69, 69, 69, 6] as Array[int], "Łupieżca: 115% w dół")
	looter.limit_to_capacity(100)
	var sum := 0
	for v in looter.loot:
		sum += v
	assert_true(sum <= 100, "capacity bez zmian")
	return true


## Bitwa atakującego na graczu i powtórka obrońcy: perk atakującego z serwera, perk obrońcy z kopii zamku.
func _pvp(attacker_perk: Variant, defender_techs: Array) -> Array:
	var plan := REPLAY._plan(REPLAY._keep_cell())
	var castle := REPLAY._castle(REPLAY._map_seed())
	var done: Array = ((castle["research"] as Dictionary)["done"] as Array).duplicate()
	done.append_array(defender_techs)
	(castle["research"] as Dictionary)["done"] = done
	var footprint: Array = []
	var keep: Array = []
	for e: Variant in (castle["grid"] as Dictionary)["buildings"] as Array:
		var a := e as Array
		footprint.append([a[3], a[4], a[5], a[6]])
		if int(a[1]) == K.KEEP:
			keep = [a[3], a[4], a[5], a[6]]
	var start := AttackStart.parse_response({"id": REPLAY.ATTACK, "map_seed": REPLAY._map_seed(), "battle_seed": 4242,
			"defender_id": REPLAY.DEFENDER, "footprint": footprint, "keep": keep, "intel": {}})
	var pc := PlayerCastle.from_start(start, REPLAY.ARMY, 0, 1)
	var launch := AttackLaunch.parse_response(REPLAY._wire({"id": REPLAY.ATTACK, "castle": castle, "defense": {},
			"plan": plan.to_server(), "techs": [], "general": null, "ruler_perk": attacker_perk}))
	assert_true(pc.apply_launch(launch), "kopia z launch_attack")
	var live := pc.create_battle()
	var trace := REPLAY._trace(live)
	var replay := BattleReplay.from_response(AttackReplay.parse_response(REPLAY._wire({"id": REPLAY.ATTACK,
			"map_seed": REPLAY._map_seed(), "battle_seed": 4242, "castle": castle, "defense": {}, "army": REPLAY.ARMY,
			"plan": plan.to_server(), "techs": [], "general": null, "ruler_perk": attacker_perk,
			"result": pc.result_of(live).to_server(), "loot": [0, 0, 0, 0], "finished_at": "2026-11-23T10:15:00+00:00"})))
	assert_true(replay != null, "powtórka z odpowiedzi")
	return [live, trace, replay.create_battle(), pc]


func test_pvp_perks_match_in_replay() -> bool:
	var led := _pvp(P.CONQUEROR, ["U14"])
	var live: Battle = led[0]
	assert_true(live.ruler_perk_is(SIDE.ATTACKER, P.CONQUEROR), "perk atakującego z serwera")
	assert_true(live.ruler_perk_is(SIDE.DEFENDER, P.BELOVED), "perk obrońcy z badań w kopii zamku")
	assert_eq(REPLAY._trace(led[2]), led[1], "powtórka z perkami: ten sam przebieg")
	var plain := _pvp(null, [])
	assert_true(plain[1] != led[1], "bez perków inny przebieg")
	assert_true((plain[0] as Battle).ruler_perks.is_empty(), "stary serwer bez perka: bez premii")
	assert_eq((_pvp(1.0, [])[3] as PlayerCastle).attacker_ruler_perk, P.LOOTER, "liczba z JSON")
	assert_eq((_pvp(17, [])[3] as PlayerCastle).attacker_ruler_perk, P.NONE, "nieznany perk z serwera odpada")
	assert_eq((_pvp(P.BELOVED_2, [])[3] as PlayerCastle).attacker_ruler_perk, P.BELOVED_2, "stan poziomu 2")
	return true


func test_panel_fits_screen() -> bool:
	var view := Vector2(320, 180)
	var r := Research.new()
	r.done["A60"] = true
	r.done["A61"] = true
	for line in RulerPerks.LINES.size():
		var rect := RulerPanel.line_rect(view, line)
		assert_true(rect.size.y >= 12, "wiersz co najmniej 12 px")
		assert_true(rect.position.x >= 16 and rect.end.x <= view.x - 16, "wiersz z dala od krawędzi")
		for research: Research in [Research.new(), r]:
			var label := RulerPanel.row_label(research, line)
			assert_true(PixelFont.text_width(label) <= int(RulerPanel.ROW_W) - 4, "„%s” mieści się" % label)
	assert_eq(RulerPanel.row_label(r, 0), "Zdobywca A60 > A61: wybrana", "wybrana linia")
	assert_eq(RulerPanel.row_label(r, 2), "Gospodarny G25 > G26: zablokowana", "inna linia zablokowana")
	assert_eq(RulerPanel.row_label(Research.new(), 3), "Ukochany władca U14 > U15", "przed wyborem")
	for p in RulerPerks.count():
		for line: String in [RulerPanel.TECH_LINE % RulerPerks.NAMES[p], RulerPerks.DESC[p]]:
			assert_true(PixelFont.text_width(line) <= int(RulerPanel.ROW_W), "„%s” mieści się" % line)
	assert_eq(RulerPanel.tech_line(r, 1), RulerPanel.TECH_LINE % "Łupieżca", "perk z badań")
	assert_eq(RulerPanel.effect_line(r, 1), "+10% obrażeń, +15% łupu z PvP", "efekt perka")
	assert_eq(RulerPanel.tech_line(Research.new(), 1), RulerPanel.TECH_LINE % RulerPanel.NO_TECH_PERK, "bez perka")
	assert_eq(RulerPanel.effect_line(Research.new(), 1), RulerPanel.HINT_LINE, "bez perka podpowiedź")
	assert_true(PixelFont.text_width(RulerPanel.HINT_LINE) <= int(RulerPanel.ROW_W), "podpowiedź mieści się")
	assert_true(PixelFont.text_width(RulerPanel.INNATE_LINE % Rulers.NO_PERKS) <= int(RulerPanel.ROW_W), "perk wrodzony")
	var close := RulerPanel.close_rect(view)
	assert_true(close.end.y <= view.y - 12, "Zamknij z dala od dolnej krawędzi")
	assert_true(close.size.y >= 12, "Zamknij co najmniej 12 px")
	return true


## Serwer (migracja *_ruler_perk_research.sql) liczy perk z badań tymi samymi liczbami co gra.
func test_server_constants_match_game() -> bool:
	var sql := FileAccess.get_file_as_string(MIGRATION)
	assert_true(not sql.is_empty(), "migracja jest")
	assert_true(sql.contains("CONQUEROR = %d, LOOTER = %d, STEWARD = %d, THRIFTY = %d, BUILDER = %d, BELOVED = %d, STEWARD_2 = %d,\n-- BELOVED_2 = %d" % [
			P.CONQUEROR, P.LOOTER, P.STEWARD, P.THRIFTY, P.BUILDER, P.BELOVED, P.STEWARD_2, P.BELOVED_2]), "numery stanów")
	assert_true(sql.contains("LINES = %s" % JSON.stringify(RulerPerks.LINES).replace(",", ", ")), "linie w komentarzu")
	assert_true(sql.contains("LINE_PERKS = %s" % str(RulerPerks.LINE_PERKS)), "stany linii w komentarzu")
	var values: Array[String] = []
	for line in RulerPerks.LINES.size():
		values.append("('%s', '%s', %d, %d)" % [RulerPerks.LINES[line][0], RulerPerks.LINES[line][1],
				RulerPerks.LINE_PERKS[line][0], RulerPerks.LINE_PERKS[line][1]])
	assert_true(sql.contains("(values %s)" % ", ".join(values)), "linie w funkcji")
	assert_true(sql.contains("check (attacker_ruler_perk between -1 and %d)" % (RulerPerks.count() - 1)), "zakres stanów")
	assert_true(sql.contains("THRIFTY = %d, BUILDER = %d, THRIFTY_PRODUCTION_BONUS = %d" % [P.THRIFTY, P.BUILDER,
			RulerPerks.THRIFTY_PRODUCTION_BONUS]), "Gospodarny w komentarzu")
	assert_eq(sql.count("in (%d, %d)" % [P.THRIFTY, P.BUILDER]), 3, "Gospodarny w produkcji i limicie żywności")
	assert_true(sql.contains("private.castle_ruler_perk(p_castle) in (%d, %d) then %d" % [P.THRIFTY, P.BUILDER,
			RulerPerks.THRIFTY_PRODUCTION_BONUS]), "premia w limicie żywności")
	# Łupieżca w `end_attack` (stan 1, ostatnio `*_attack_verification.sql`) i Budowniczy w czasie budowy
	# (`*_building_sanity.sql`) bez zmian numerów
	var verify := FileAccess.get_file_as_string("res://supabase/migrations/20261125211238_attack_verification.sql")
	assert_true(verify.contains("a.attacker_ruler_perk = %d then\n      v_cap := v_cap * %d / 100" % [P.LOOTER,
			RulerPerks.LOOTER_LOOT_PERCENT]), "Łupieżca w end_attack")
	return true
