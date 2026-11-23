extends TestCase
## Perki władcy (#32): 1 miejsce i 6 perków MVP, zmiana darmowa raz na 24 h, potem za złoto, perk z epoki,
## zapis, efekty w gospodarce (Gospodarny, Budowniczy) i w bitwie (Zdobywca, Gospodarz grodu, Ukochany
## władca), Łupieżca w łupie z PvP, ten sam przebieg w powtórce i zgodność liczb z migracją serwera.

const K := BuildingTypes.Kind
const U := UnitTypes.Unit
const P := RulerPerks.Perk
const RES := RulerPerks.Result
const SIDE := Battle.Side
const SPAWN := Vector2i(32, 60)
const MIGRATION := "res://supabase/migrations/20261123120000_ruler_perk.sql"
const HOUR_MS := 3600 * 1000
const REPLAY := preload("res://tests/test_replay.gd")


func _gold(amount: int) -> Economy:
	var e := Economy.new(0)
	e.amounts[EconomyConfig.Res.GOLD] = amount
	return e


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


func test_six_perks_one_slot_and_ages() -> bool:
	assert_eq(RulerPerks.count(), 6, "6 perków MVP")
	assert_eq(RulerPerks.SLOTS, 1, "1 miejsce")
	assert_eq(RulerPerks.NAMES, ["Zdobywca", "Łupieżca", "Gospodarz grodu", "Gospodarny", "Budowniczy",
			"Ukochany władca"] as Array[String], "nazwy z Planu MVP")
	assert_eq(RulerPerks.available(0), [P.CONQUEROR, P.STEWARD, P.THRIFTY, P.BELOVED] as Array[int], "epoka I")
	assert_eq(RulerPerks.available(1).size(), 6, "w epoce II wszystkie")
	assert_eq(RulerPerks.checked(P.LOOTER, 0), P.NONE, "Łupieżca z wyższej epoki nie działa")
	assert_eq(RulerPerks.checked(9, 1), P.NONE, "nieznany perk")
	assert_eq(RulerPerks.checked(P.LOOTER, 1), P.LOOTER, "Łupieżca w epoce II")
	return true


func test_change_free_once_per_day_then_gold() -> bool:
	var r := RulerPerks.new()
	var e := _gold(100)
	var t := 1000 * HOUR_MS
	assert_eq(r.choose(P.LOOTER, 0, e, t), RES.LOCKED, "perk od epoki II")
	assert_eq(r.choose(9, 0, e, t), RES.UNKNOWN, "nieznany perk")
	assert_eq(r.choose(P.CONQUEROR, 0, e, t), RES.OK, "pierwszy wybór")
	assert_eq(e.amounts[EconomyConfig.Res.GOLD], 100, "darmowo")
	assert_eq(r.choose(P.CONQUEROR, 0, e, t + 1), RES.SAME, "ten sam perk")
	assert_eq(r.change_gold(t + HOUR_MS), RulerPerks.CHANGE_GOLD, "druga zmiana w 24 h płatna")
	assert_eq(r.choose(P.STEWARD, 0, e, t + HOUR_MS), RES.OK, "zmiana za złoto")
	assert_eq(e.amounts[EconomyConfig.Res.GOLD], 100 - RulerPerks.CHANGE_GOLD, "pobrane złoto")
	assert_eq(r.next_free_ms(t + HOUR_MS), t + RulerPerks.COOLDOWN_MS, "płatna zmiana nie przesuwa okna")
	var poor := _gold(RulerPerks.CHANGE_GOLD - 1)
	assert_eq(r.choose(P.THRIFTY, 0, poor, t + 2 * HOUR_MS), RES.NO_GOLD, "bez złota nie zmienisz")
	assert_eq(r.perk, P.STEWARD, "perk bez zmian")
	assert_eq(r.choose(P.THRIFTY, 0, poor, t + RulerPerks.COOLDOWN_MS), RES.OK, "po 24 h znowu darmowo")
	assert_eq(poor.amounts[EconomyConfig.Res.GOLD], RulerPerks.CHANGE_GOLD - 1, "bez opłaty")
	assert_eq(r.free_ms, t + RulerPerks.COOLDOWN_MS, "nowe okno 24 h")
	for m: String in RulerPerks.MESSAGES:
		assert_true(PixelFont.text_width(m) <= 320 - 16, "komunikat „%s” mieści się" % m)
	return true


func test_save_round_trip() -> bool:
	var grid := _grid()
	grid.place(grid.manor_spot(64), K.MANOR, 2)
	var r := RulerPerks.new()
	r.choose(P.THRIFTY, 0, _gold(0), 5000)
	var d := SaveGame.to_dict(1337, grid, Economy.new(0), BuildQueue.new(), null, null, null, 0, null, 0, null, 0,
			null, null, null, r)
	assert_eq(int(d["version"]), 12, "wersja 12")
	var s := SaveGame.from_dict(JSON.parse_string(JSON.stringify(d)) as Dictionary, 0)
	assert_eq(s.ruler.perk, P.THRIFTY, "perk wraca z zapisu")
	assert_eq(s.ruler.free_ms, 5000, "chwila darmowej zmiany wraca")
	assert_eq(s.grid.ruler_perk, P.THRIFTY, "perk działa w siatce zamku")
	# perk z wyższej epoki w zapisie (np. kopia z serwera) nie działa w epoce I
	d["ruler"] = {"perk": P.LOOTER}
	assert_eq(SaveGame.from_dict(d, 0).grid.ruler_perk, P.NONE, "Łupieżca w epoce I nie działa")
	d["ruler"] = {"perk": 42}
	var bad := SaveGame.from_dict(d, 0)
	assert_eq(bad.ruler.perk, P.NONE, "zły perk odpada")
	assert_eq(bad.skipped, 1, "pominięty wpis")
	var old := d.duplicate(true)
	old["version"] = 11
	old.erase("ruler")
	assert_eq(SaveGame.from_dict(old, 0).ruler.perk, P.NONE, "zapis sprzed perków")
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
func _pvp(attacker_perk: Variant, defender_ruler: Dictionary) -> Array:
	var plan := REPLAY._plan(REPLAY._keep_cell())
	var castle := REPLAY._castle(REPLAY._map_seed())
	castle["ruler"] = defender_ruler
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
	var led := _pvp(P.CONQUEROR, {"perk": P.BELOVED})
	var live: Battle = led[0]
	assert_true(live.ruler_perk_is(SIDE.ATTACKER, P.CONQUEROR), "perk atakującego z serwera")
	assert_true(live.ruler_perk_is(SIDE.DEFENDER, P.BELOVED), "perk obrońcy z kopii zamku")
	assert_eq(REPLAY._trace(led[2]), led[1], "powtórka z perkami: ten sam przebieg")
	var plain := _pvp(null, {})
	assert_true(plain[1] != led[1], "bez perków inny przebieg")
	assert_true((plain[0] as Battle).ruler_perks.is_empty(), "stary serwer bez perka: bez premii")
	assert_eq((_pvp(1.0, {})[3] as PlayerCastle).attacker_ruler_perk, P.LOOTER, "liczba z JSON")
	assert_eq((_pvp(17, {})[3] as PlayerCastle).attacker_ruler_perk, P.NONE, "nieznany perk z serwera odpada")
	return true


func test_panel_fits_screen() -> bool:
	var view := Vector2(320, 180)
	var r := RulerPerks.new()
	for p in RulerPerks.count():
		var rect := RulerPanel.perk_rect(view, p)
		assert_true(rect.size.y >= 12, "cel dotyku co najmniej 12 px")
		assert_true(rect.position.x >= 16 and rect.end.x <= view.x - 16, "wiersz z dala od krawędzi")
		for age in 2:
			var label := RulerPanel.row_label(r, p, age)
			assert_true(PixelFont.text_width(label) <= int(RulerPanel.ROW_W) - 4, "„%s” mieści się" % label)
	var close := RulerPanel.close_rect(view)
	assert_true(close.end.y <= view.y - 12, "Zamknij z dala od dolnej krawędzi")
	assert_true(PixelFont.text_width(RulerPanel.PAID_LINE % [RulerPerks.CHANGE_GOLD, "23 h 59 min"]) <= int(RulerPanel.ROW_W),
			"linia kosztu mieści się")
	r.choose(P.CONQUEROR, 0, _gold(0), 1000)
	assert_eq(RulerPanel.cost_line(r, 1000 + HOUR_MS), RulerPanel.PAID_LINE % [RulerPerks.CHANGE_GOLD,
			Hud.format_time(RulerPerks.COOLDOWN_MS - HOUR_MS)], "koszt i czas do darmowej zmiany")
	assert_eq(RulerPanel.cost_line(r, 1000 + RulerPerks.COOLDOWN_MS), RulerPanel.FREE_LINE, "po 24 h darmowo")
	return true


## Serwer (migracja *_ruler_perk.sql) liczy perk tymi samymi liczbami co gra.
func test_server_constants_match_game() -> bool:
	var sql := FileAccess.get_file_as_string(MIGRATION)
	assert_true(not sql.is_empty(), "migracja jest")
	assert_true(sql.contains("CONQUEROR = %d, LOOTER = %d, STEWARD = %d, THRIFTY = %d, BUILDER = %d" % [P.CONQUEROR,
			P.LOOTER, P.STEWARD, P.THRIFTY, P.BUILDER]), "numery perków")
	assert_true(sql.contains("BELOVED = %d" % P.BELOVED), "Ukochany władca")
	assert_true(sql.contains("private.json_int(p_data -> 'ruler' -> 'perk', 0, %d)" % (RulerPerks.count() - 1)), "zakres")
	assert_true(sql.contains("PERK_AGE = %s" % str(RulerPerks.PERK_AGE)), "epoki perków")
	assert_true(sql.contains("v_new in (%d, %d) and v_age < 1" % [P.LOOTER, P.BUILDER]), "perki od epoki II")
	assert_eq(RulerPerks.PERK_AGE[P.LOOTER], 1, "Łupieżca od II")
	assert_eq(RulerPerks.PERK_AGE[P.BUILDER], 1, "Budowniczy od II")
	assert_true(sql.contains("COOLDOWN = %d godziny" % (RulerPerks.COOLDOWN_MS / HOUR_MS)), "okno 24 h")
	assert_true(sql.contains("interval '%d hours'" % (RulerPerks.COOLDOWN_MS / HOUR_MS)), "okno w funkcji")
	assert_true(sql.contains("CHANGE_GOLD = %d" % RulerPerks.CHANGE_GOLD), "koszt zmiany")
	assert_true(sql.contains("v_paid) >= %d" % RulerPerks.CHANGE_GOLD), "koszt w funkcji")
	assert_true(sql.contains("- %d * coalesce(p_paid, 0)" % RulerPerks.CHANGE_GOLD), "płatne zmiany w budżecie")
	assert_true(sql.contains("v_spent := %d * coalesce" % RulerPerks.CHANGE_GOLD), "płatne zmiany u generałów")
	var pve_gold := 0
	for w in PveWaves.COUNT:
		pve_gold += PveWaves.reward(w)[EconomyConfig.Res.GOLD]
	assert_true(sql.contains("select %d + %d" % [EconomyConfig.START[EconomyConfig.Res.GOLD], pve_gold]), "złoto startowe")
	assert_true(sql.contains("sum(%d\n" % Generals.RECRUIT_GOLD), "rekrutacja generała")
	assert_true(sql.contains(">= 2 then %d" % Generals.LEVEL_GOLD[2]), "awans na 2")
	assert_true(sql.contains(">= 3 then %d" % Generals.LEVEL_GOLD[3]), "awans na 3")
	assert_true(sql.contains("LOOTER_LOOT_PERCENT = %d" % RulerPerks.LOOTER_LOOT_PERCENT), "Łupieżca")
	assert_true(sql.contains("a.attacker_ruler_perk = %d then\n      v_cap := v_cap * %d / 100" % [P.LOOTER,
			RulerPerks.LOOTER_LOOT_PERCENT]), "Łupieżca w end_attack")
	assert_true(sql.contains("THRIFTY_PRODUCTION_BONUS = %d" % RulerPerks.THRIFTY_PRODUCTION_BONUS), "Gospodarny")
	assert_true(sql.contains("private.castle_ruler_perk(p_castle) = %d then %d" % [P.THRIFTY,
			RulerPerks.THRIFTY_PRODUCTION_BONUS]), "Gospodarny w limicie żywności")
	assert_true(sql.contains("G2 = %d procent" % int((TechTree.PRODUCTION_BONUS["G2"] as Array)[1])), "premia G2")
	return true
