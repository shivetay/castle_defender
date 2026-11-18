extends TestCase
## Synchronizacja seeda mapy (#166): payload INSERT ma map_seed, UPDATE go nie rusza.


func test_insert_includes_map_seed_update_does_not() -> bool:
	var data := {"grid": {"a": 1}, "version": 8}
	var insert := CastleSync.insert_body("00000000-0000-0000-0000-00000000000a", 1337, 8, data)
	assert_eq(insert["map_seed"], 1337, "INSERT niesie seed terenu")
	assert_eq(insert["player_id"], "00000000-0000-0000-0000-00000000000a", "właściciel")
	assert_eq(insert["save_version"], 8, "wersja zapisu")
	assert_eq(insert["data"], data, "stan zamku")
	var update := CastleSync.update_body(8, data)
	assert_true(not update.has("map_seed"), "UPDATE nie zmienia seeda")
	assert_true(not update.has("player_id"), "UPDATE nie zmienia właściciela")
	assert_true(not update.has("revision"), "revision ustala serwer")
	assert_eq(update["save_version"], 8, "wersja w UPDATE")
	assert_eq(update["data"], data, "dane w UPDATE")
	return true


func test_map_seed_range_and_parse() -> bool:
	assert_true(CastleSync.is_valid_map_seed(1), "min")
	assert_true(CastleSync.is_valid_map_seed(WorldSeed.MAX_SEED), "max")
	assert_true(not CastleSync.is_valid_map_seed(0), "0 niedozwolone w castles")
	assert_true(not CastleSync.is_valid_map_seed(-1), "ujemny")
	assert_true(not CastleSync.is_valid_map_seed(WorldSeed.MAX_SEED + 1), "powyżej 31 bitów")
	assert_eq(CastleSync.map_seed_from_rows([{"map_seed": 4242}]), 4242, "odczyt z GET")
	assert_eq(CastleSync.map_seed_from_rows([]), 0, "brak wiersza")
	assert_eq(CastleSync.map_seed_from_rows([{"map_seed": 0}]), 0, "zły seed")
	assert_eq(CastleSync.own_path("abc"), "/rest/v1/castles?player_id=eq.abc", "filtr własnego")
	return true


func test_castle_data_drops_world_seed_column() -> bool:
	var save := SaveGame.to_dict(1337, BuildGrid.new(TerrainMap.generate(1337)), Economy.new(0), BuildQueue.new())
	assert_true(save.has("world_seed"), "lokalny zapis ma world_seed")
	var remote := CastleSync.castle_data(save)
	assert_true(not remote.has("world_seed"), "w JSON kolumny data seeda nie duplikujemy")
	assert_eq(int(save["world_seed"]), 1337, "lokalny seed bez zmian")
	return true


func test_next_action_insert_then_update() -> bool:
	assert_eq(CastleSync.next_action(0, 0), CastleSync.Action.NOP, "bez lokalnego seeda nic")
	assert_eq(CastleSync.next_action(1337, 0), CastleSync.Action.INSERT, "pierwszy zapis z seedem")
	assert_eq(CastleSync.next_action(1337, 1337), CastleSync.Action.UPDATE, "kolejny zapis bez zmiany seeda")
	assert_eq(CastleSync.next_action(42, 1337), CastleSync.Action.UPDATE,
			"lokalny seed nie nadpisuje bazowego (UPDATE bez map_seed)")
	return true

