extends TestCase
## Straty armii odejmuje serwer (#427, ADR 0019): polegli czekają w Recruitment.held, do serwera idą jeszcze
## w oddziale (server_data), a odpowiedź na zapis zamku (`army_applied`) je rozlicza; flagi `server_losses'
## z odpowiedzi startu wyprawy i zatwierdzenia planu oraz zgodność z migracją.

const U := UnitTypes.Unit
const MIGRATION := "res://supabase/migrations/20261128140000_army_losses.sql"
const ATTACK := "00000000-0000-0000-0000-0000000004a1"
const NOW := 1_800_000_000_000


func _grid() -> BuildGrid:
	return BuildGrid.new(TerrainMap.generate(WorldSeed.first_playable(1337)))


## Dwa oddziały toporników po 10; bitwa: pierwszy cały, drugi zostaje z 4.
func _after_battle() -> Recruitment:
	var r := Recruitment.new()
	r.add_squad(U.AXE_WARRIOR, 10)
	r.add_squad(U.AXE_WARRIOR, 10)
	r.apply_losses_held(ATTACK, [1, 2] as Array[int], [10, 4] as Array[int], NOW)
	return r


## Gra od razu odejmuje poległych, ale ich miejsca w oddziale czekają na serwer.
func test_held_losses_leave_army_but_keep_slots() -> bool:
	var r := _after_battle()
	assert_eq(r.squad(2).count, 4, "polegli zniknęli z oddziału")
	assert_eq(r.held.size(), 1, "tylko oddział ze stratami czeka")
	assert_eq(r.held_for(2), 6, "sześciu czeka na serwer")
	assert_eq(r.free_in_squad(2), 0, "miejsca poległych zajęte do rozliczenia")
	assert_eq(r.free_in_squad(1), 0, "pełny oddział")
	return true


## Do serwera polegli idą w swoim oddziale, także gdy gra usunęła pusty oddział; listy held serwer nie dostaje.
func test_server_data_returns_held_to_squads() -> bool:
	var r := _after_battle()
	var d := Recruitment.server_data(r.save_data())
	assert_true(not d.has("held"), "bez listy held")
	assert_eq(d["squads"], [[1, U.AXE_WARRIOR, 10], [2, U.AXE_WARRIOR, 10]], "stan sprzed bitwy dla serwera")
	var gone := Recruitment.new()
	gone.add_squad(U.AXE_WARRIOR, 10)
	gone.apply_losses_held(ATTACK, [1] as Array[int], [0] as Array[int], NOW)
	assert_true(gone.squad(1) == null, "pusty oddział usunięty w grze")
	assert_eq(Recruitment.server_data(gone.save_data())["squads"], [[1, U.AXE_WARRIOR, 10]],
			"oddział wraca do serwera z poległymi")
	var save := SaveGame.to_dict(1, _grid(), Economy.new(NOW), BuildQueue.new(), Research.new(), Goods.new(NOW), r)
	var data := CastleSync.castle_data(save)
	assert_eq((data["recruitment"] as Dictionary)["squads"], [[1, U.AXE_WARRIOR, 10], [2, U.AXE_WARRIOR, 10]],
			"castle_data wysyła polegli w oddziale")
	assert_true(not (data["recruitment"] as Dictionary).has("held"), "castle_data bez held")
	return true


## Rozliczenie z serwera: polegli z held tylko znikają z listy; rozliczenie bez held (przywrócony zamek albo bitwa
## przerwana zamknięciem gry) odejmuje z oddziału; zero czyści held bez zmiany oddziału.
func test_settle_losses() -> bool:
	var r := _after_battle()
	r.settle_losses([[ATTACK, 1, 0], [ATTACK, 2, 6]])
	assert_true(r.held.is_empty(), "rozliczone")
	assert_eq(r.squad(2).count, 4, "bez podwójnej straty")
	r.settle_losses([["inny-atak", 1, 3]])
	assert_eq(r.squad(1).count, 7, "strata spoza held odjęta z oddziału")
	var z := _after_battle()
	z.settle_losses([[ATTACK, 2, 0]])
	assert_true(z.held.is_empty() and z.squad(2).count == 4, "serwer nie odjął: gra zostaje przy swoich stratach")
	var more := _after_battle()
	more.settle_losses([[ATTACK, 2, 8]])
	assert_eq(more.squad(2).count, 2, "serwer odjął więcej (wynik workera): różnica z oddziału")
	return true


## Held przetrwa zapis gry, a po dobie bez rozliczenia gra go zapomina.
func test_held_round_trip_and_expiry() -> bool:
	var r := _after_battle()
	var back := Recruitment.new()
	back.load_data(r.save_data(), _grid(), NOW + 1000)
	assert_eq(back.held_for(2), 6, "polegli czekają po wczytaniu")
	assert_eq(str(back.held[0]["attack"]), ATTACK, "id ataku")
	var late := Recruitment.new()
	late.load_data(r.save_data(), _grid(), NOW + RecruitmentConfig.HELD_TTL_MS + 1)
	assert_true(late.held.is_empty(), "po dobie zapomniane")
	var bad := r.save_data()
	bad["held"] = [[1, 2, 0, 6, NOW], ["a", 2, 99, 6, NOW], ["a", 2, 0, 0, NOW]]
	var none := Recruitment.new()
	none.load_data(bad, _grid(), NOW)
	assert_true(none.held.is_empty(), "złe wpisy pominięte")
	return true


## Odpowiedź na zapis zamku: tylko poprawne rozliczenie, inaczej nic.
func test_army_from_rows() -> bool:
	assert_eq(CastleSync.army_from_rows([{"army_applied": [[ATTACK, 2, 6.0]]}]), [[ATTACK, 2, 6]], "rozliczenie")
	assert_eq(CastleSync.army_from_rows([{"army_applied": []}]), [], "nic do rozliczenia")
	assert_eq(CastleSync.army_from_rows([{}]), [], "starszy serwer bez kolumny")
	assert_eq(CastleSync.army_from_rows([{"army_applied": [[ATTACK, 0, 1]]}]), [], "zły oddział")
	assert_eq(CastleSync.army_from_rows([{"army_applied": [[ATTACK, 2, 11]]}]), [], "ponad rozmiar oddziału")
	assert_eq(CastleSync.army_from_rows([{"army_applied": [[2, 2, 1]]}]), [], "id ataku nie tekstem")
	assert_true(CastleSync.SELECT_PUSH.contains("army_applied"), "zapis prosi o rozliczenie")
	return true


## Flaga z serwera: start wyprawy z planem i zatwierdzenie planu PvP; bez pola telefon odejmuje sam.
func test_server_losses_flags() -> bool:
	var start := AttackStart.parse_response({"id": ATTACK, "map_seed": 7, "battle_seed": 9, "bot_idx": 0,
			"plan": [], "techs": [], "general": null, "ruler_perk": -1, "server_losses": true})
	var p := PveReport.new()
	p.begin(0, [[U.AXE_WARRIOR, 10]])
	p.on_started(start, "")
	assert_true(p.server_losses, "wyprawa: straty odejmie serwer")
	p.reset()
	assert_true(not p.server_losses, "po zgłoszeniu flaga znika")
	var old := AttackStart.parse_response({"id": ATTACK, "map_seed": 7, "battle_seed": 9, "bot_idx": 0, "plan": []})
	var q := PveReport.new()
	q.begin(0, [[U.AXE_WARRIOR, 10]])
	q.on_started(old, "")
	assert_true(not q.server_losses, "starszy serwer: telefon odejmuje sam")
	var launch := AttackLaunch.parse_response({"id": ATTACK, "castle": {"grid": {}}, "server_losses": true})
	assert_eq(launch["server_losses"], true, "zatwierdzenie planu niesie flagę")
	assert_eq(AttackLaunch.parse_response({"id": ATTACK, "castle": {"grid": {}}})["server_losses"], false,
			"bez pola: false")
	return true


## Liczby z migracji: oddział do SQUAD_SIZE, próg wersji domyślnie wyłączony.
func test_matches_migration() -> bool:
	var sql := FileAccess.get_file_as_string(MIGRATION)
	assert_true(sql.contains("fallen smallint not null check (fallen between 0 and %d)" % RecruitmentConfig.SQUAD_SIZE),
			"polegli w oddziale do SQUAD_SIZE")
	assert_true(sql.contains("('army_losses_min_sim', '0')"), "próg domyślnie wyłączony")
	assert_true(sql.contains("army_applied"), "kolumna rozliczenia")
	return true
