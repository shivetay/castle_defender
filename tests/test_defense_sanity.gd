extends TestCase
## Układ obrony bez zaufanej edycji lokalnej (#421, ADR 0020). Serwer (`*_defense_sanity.sql`) przyjmuje w zamku
## tylko obronę w kształcie DefensePlan.to_dict (zadania oddziałów z armii, kratki na mapie, pułapki z technologią
## i epoką w limicie Dworu), `defense_layouts` tylko równe obronie z zamku, a atak tylko z taką obroną. Liczby
## w migracji muszą być te same co w grze, a uczciwy zapis z gry musi przejść reguły.

const MIGRATION := "res://supabase/migrations/20261128160000_defense_sanity.sql"
const START_ATTACK := "res://supabase/functions/start_attack/index.ts"


func _sql() -> String:
	return FileAccess.get_file_as_string(MIGRATION)


## Znaczniki w komentarzu i liczby w funkcjach to stałe gry.
func test_server_constants_match_game() -> bool:
	var sql := _sql()
	assert_true(not sql.is_empty(), "migracja jest")
	var tasks := DefensePlan.TASK_NAMES.size()
	assert_eq(tasks, DefensePlan.Task.size(), "nazwa dla każdego zadania")
	assert_true(sql.contains("TASKS = %d" % tasks), "liczba zadań w komentarzu")
	assert_true(sql.contains("private.json_int(e -> 1, 0, %d)" % (tasks - 1)), "zadania w funkcji")
	assert_true(sql.contains("MAP_SIZE = %d" % TerrainMap.SIZE), "mapa w komentarzu")
	assert_true(sql.contains("private.json_int(p -> 0, -1, %d)" % (TerrainMap.SIZE - 1)), "mapa w funkcji")
	assert_eq(DefensePlan.NO_POST, Vector2i(-1, -1), "NO_POST jak w funkcji")
	assert_true(sql.contains("MAX_ROUTE = %d" % DefensePlan.MAX_ROUTE), "trasa w komentarzu")
	assert_true(sql.contains("jsonb_array_length(e -> 4) > %d" % DefensePlan.MAX_ROUTE), "trasa w funkcji")
	var kinds := TrapConfig.count()
	assert_true(sql.contains("TRAP_KINDS = %d" % kinds), "rodzaje pułapek w komentarzu")
	assert_true(sql.contains("private.json_int(e -> 0, 0, %d)" % (kinds - 1)), "rodzaje pułapek w funkcji")
	assert_true(sql.contains("TRAP_AGE = %s" % str(TrapConfig.AGE)), "epoki pułapek w komentarzu")
	assert_true(sql.contains("(array%s)[k + 1] > private.castle_age" % str(TrapConfig.AGE)), "epoki w funkcji")
	assert_true(sql.contains("TRAP_TECH = %s" % str(TrapConfig.TECH)), "technologie pułapek w komentarzu")
	var techs := str(TrapConfig.TECH).replace("\"", "'")
	assert_true(sql.contains("(array%s)[k + 1]" % techs), "technologie w funkcji")
	assert_true(sql.contains("LIMIT_PER_MANOR_LEVEL = %d" % TrapConfig.LIMIT_PER_MANOR_LEVEL), "limit w komentarzu")
	assert_true(sql.contains("select %d * least(greatest(" % TrapConfig.LIMIT_PER_MANOR_LEVEL), "limit w funkcji")
	assert_true(sql.contains("1), %d)" % Ages.MAX_TOTAL_LEVEL), "Dwór do poziomu 10 w funkcji")
	var priorities := DefensePlan.TOWER_PRIORITY_NAMES.size()
	assert_true(sql.contains("TOWER_PRIORITIES = %d" % priorities), "priorytety wież w komentarzu")
	assert_true(sql.contains("'tower_priority', 0, %d)" % (priorities - 1)), "priorytety w funkcji")
	assert_true(sql.contains("GENERALS = %d" % Generals.count()), "generałowie w komentarzu")
	assert_true(sql.contains("'commander', -1, %d)" % (Generals.count() - 1)), "komendant w funkcji")
	assert_true(sql.contains("errcode = 'PT422'"), "odrzut kodem HTTP 422")
	assert_eq(CastleSync.REJECTED_HTTP, 422, "klient rozpoznaje odrzut")
	return true


## Limit pułapek serwera to TrapConfig.limit dla każdego poziomu Dworu (przy Dworze 0 jak przy 1).
func test_trap_limit_matches_server_formula() -> bool:
	for level in range(0, Ages.MAX_TOTAL_LEVEL + 1):
		var server := TrapConfig.LIMIT_PER_MANOR_LEVEL * mini(maxi(level, 1), Ages.MAX_TOTAL_LEVEL)
		assert_eq(TrapConfig.limit(maxi(level, 1)), server, "Dwór %d" % level)
	return true


## Zapis z gry ma kształt, który serwer przyjmuje: [id, zadanie, x, y, trasa] z id bez powtórzeń, trasa do
## MAX_ROUTE punktów, zadanie bez kratki jako NO_POST, pułapki [rodzaj, x, y, 0/1], priorytet i komendant.
func test_game_save_has_server_shape() -> bool:
	var plan := DefensePlan.new()
	plan.set_post(3, Vector2i(30, 31))
	var patrol := plan.set_task(1, DefensePlan.Task.PATROL)
	patrol.post = Vector2i(20, 20)
	patrol.route.append(Vector2i(25, 20))
	patrol.route.append(Vector2i(25, 25))
	plan.set_task(2, DefensePlan.Task.KEEP)
	plan.add_trap(TrapConfig.Kind.PIT, Vector2i(10, 12))
	plan.add_trap(TrapConfig.Kind.PITCH, Vector2i(63, 0)).revealed = true
	plan.tower_priority = DefensePlan.TowerPriority.CAVALRY
	plan.commander = Generals.count() - 1
	var d := plan.to_dict()
	var ids: Array[int] = []
	for e: Variant in d["orders"] as Array:
		var a := e as Array
		assert_eq(a.size(), 5, "zadanie z trasą")
		assert_true(not ids.has(int(a[0])), "id bez powtórzeń")
		ids.append(int(a[0]))
		assert_true(int(a[1]) >= 0 and int(a[1]) < DefensePlan.TASK_NAMES.size(), "zadanie z listy")
		var post := Vector2i(int(a[2]), int(a[3]))
		assert_true(post == DefensePlan.NO_POST or Rect2i(0, 0, TerrainMap.SIZE, TerrainMap.SIZE).has_point(post),
				"kratka na mapie albo NO_POST")
		assert_true((a[4] as Array).size() <= DefensePlan.MAX_ROUTE, "trasa w limicie")
	assert_eq(ids, [1, 2, 3] as Array[int], "wszystkie oddziały, rosnąco")
	assert_eq(d["traps"], [[TrapConfig.Kind.PIT, 10, 12, 0], [TrapConfig.Kind.PITCH, 63, 0, 1]], "pułapki")
	assert_eq(int(d["tower_priority"]), DefensePlan.TowerPriority.CAVALRY, "priorytet wież")
	assert_eq(int(d["commander"]), Generals.count() - 1, "komendant")
	# zadanie bez kratki (Przy donżonie) idzie z NO_POST
	var keep := (d["orders"] as Array)[1] as Array
	assert_eq(Vector2i(int(keep[2]), int(keep[3])), DefensePlan.NO_POST, "Przy donżonie bez kratki")
	return true


## Zapis zamku i obrony z gry to ten sam słownik obrony, więc `defense_layouts` = `castles.data.defense`.
func test_castle_and_layout_carry_same_defense() -> bool:
	var plan := DefensePlan.new()
	plan.set_post(4, Vector2i(30, 30))
	plan.add_trap(TrapConfig.Kind.CALTROPS, Vector2i(5, 6))
	var save := {"defense": plan.to_dict()}
	assert_eq(CastleSync.defense_data(save), CastleSync.castle_data(save, null).get("defense"), "ta sama obrona")
	return true


## Atak na cel z obroną spoza zamku: atakujący dostaje 409 i szuka innego celu.
func test_defense_invalid_message() -> bool:
	var ts := FileAccess.get_file_as_string(START_ATTACK)
	assert_true(ts.contains("defense_invalid: 409"), "Edge Function przekazuje kod")
	assert_true(_sql().contains("raise exception 'defense_invalid' using errcode = 'P0001'"), "kod z begin_attack")
	assert_eq(AttackStart.error_message("defense_invalid"), AttackStart.error_message("target_not_found"),
			"jak niedostępny cel")
	assert_true(AttackStart.error_message("defense_invalid") != AttackStart.error_message("cokolwiek"),
			"własny komunikat")
	return true
