extends TestCase
## start_attack (#166): map_seed terenu osobno od battle_seed; ten sam seed → ten sam teren.


func test_parse_keeps_map_seed_apart_from_battle_seed() -> bool:
	var ok := AttackStart.parse_response({
		"id": "a1", "map_seed": 1337, "battle_seed": 99, "bot_idx": 3,
	})
	assert_eq(ok["map_seed"], 1337, "seed terenu")
	assert_eq(ok["battle_seed"], 99, "seed bitwy")
	assert_true(ok["map_seed"] != ok["battle_seed"], "seedy są osobne wartościami")
	assert_eq(ok["bot_idx"], 3, "cel-bot")
	assert_true(AttackStart.parse_response({"map_seed": 1}).is_empty(), "bez battle_seed odrzucone")
	assert_true(AttackStart.parse_response({"battle_seed": 1}).is_empty(), "bez map_seed odrzucone")
	assert_true(AttackStart.parse_response({"map_seed": 0, "battle_seed": 1}).is_empty(), "map_seed 0")
	assert_eq(AttackStart.request_bot(2)["bot_idx"], 2, "żądanie na bota")
	assert_eq(AttackStart.request_player("u1")["defender_id"], "u1", "żądanie na gracza")
	return true


func test_same_map_seed_same_terrain_independent_of_battle_seed() -> bool:
	var map_seed := BotRoster.seed_of(0)
	var a := AttackStart.terrain_map(map_seed)
	var b := AttackStart.terrain_map(map_seed)
	assert_eq(_tiles(a), _tiles(b), "ten sam map_seed → ten sam teren")
	assert_eq(_tiles(a), _tiles(TerrainMap.generate(WorldSeed.first_playable(map_seed))),
			"jak BotCastle: first_playable + generate")
	# battle_seed nie wchodzi do generatora terenu
	var battle_seed := 42
	assert_true(map_seed != battle_seed, "przykład: różne seedy")
	assert_true(_tiles(a) != _tiles(TerrainMap.generate(battle_seed)),
			"teren z map_seed ≠ teren z battle_seed")
	return true


func test_attacker_matches_defender_world_seed() -> bool:
	# obrońca trzyma w castles.map_seed swój world_seed (już grywalny)
	var defender_seed := WorldSeed.first_playable(9001)
	var defender := TerrainMap.generate(defender_seed)
	var attacker := AttackStart.terrain_map(defender_seed)
	assert_eq(_tiles(defender), _tiles(attacker), "atakujący odtwarza teren obrońcy")
	assert_eq(attacker.world_seed, defender_seed, "world_seed mapy = map_seed z serwera")
	return true


func test_bot_roster_seeds_match_database_rows() -> bool:
	# wartości z supabase/migrations/..._init_pvp_schema.sql (bot_castles)
	var db: Array[int] = [
		1522671593, 1794635700, 2000785702, 786423411, 652894939, 955747868, 861633082,
		1900177340, 213453807, 136845175, 1460975256, 601804662, 1757690968, 563504191,
		821957311, 1990192917, 541277618, 797847133, 308247635, 2034701,
	]
	assert_eq(db.size(), BotRoster.COUNT, "20 zamków")
	for i in BotRoster.COUNT:
		assert_eq(BotRoster.seed_of(i), db[i], "bot %d: seed gry = seed w bazie" % i)
	return true


func _tiles(map: TerrainMap) -> Array:
	var out: Array = []
	for y in map.size:
		var row: Array = []
		for x in map.size:
			row.append(map.get_tile(Vector2i(x, y)))
		out.append(row)
	return out
