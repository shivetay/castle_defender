extends TestCase
## Seed terenu nowej gry: losowanie, walidacja grywalności, determinizm i zapis.

## Ile seedów sprawdza test grywalności (kryterium akceptacji #97).
const SAMPLE := 1000


func test_random_seeds_are_in_range_and_differ() -> bool:
	var seen := {}
	for i in 50:
		var s := WorldSeed.random_seed()
		assert_true(s > 0 and s <= WorldSeed.MAX_SEED, "seed %d w zakresie 1..MAX_SEED" % s)
		seen[s] = true
	assert_true(seen.size() >= 49, "50 losowań daje różne seedy (jest %d różnych)" % seen.size())
	return true


func test_every_sampled_seed_gives_playable_map() -> bool:
	# próbka z jawnym seedem, żeby test był powtarzalny
	var rng := RandomNumberGenerator.new()
	rng.seed = 97
	var replaced := 0
	for i in SAMPLE:
		var first := (rng.randi() & WorldSeed.MAX_SEED) | 1
		var chosen := WorldSeed.first_playable(first)
		if chosen != first:
			replaced += 1
		if not WorldSeed.is_playable(chosen):
			assert_true(false, "seed %d (z %d) daje grywalną mapę" % [chosen, first])
	print("    %d z %d seedów wymagało ponownego losowania" % [replaced, SAMPLE])
	return true


func test_fallback_seed_is_playable() -> bool:
	assert_true(WorldSeed.is_playable(WorldSeed.FALLBACK_SEED), "seed zapasowy jest grywalny")
	return true


func test_retry_sequence_is_deterministic() -> bool:
	for first: int in [1, 42, 1337, WorldSeed.MAX_SEED]:
		assert_eq(WorldSeed.first_playable(first), WorldSeed.first_playable(first), "seed %d" % first)
		for attempt in range(1, 4):
			var n := WorldSeed.next_candidate(first, attempt)
			assert_eq(n, WorldSeed.next_candidate(first, attempt), "kandydat %d dla %d" % [attempt, first])
			assert_true(n > 0 and n <= WorldSeed.MAX_SEED, "kandydat w zakresie")
	assert_true(WorldSeed.next_candidate(42, 1) != WorldSeed.next_candidate(42, 2), "kolejne próby różne")
	return true


func test_map_without_room_for_manor_is_rejected() -> bool:
	var map := TerrainMap.generate(WorldSeed.FALLBACK_SEED)
	var mid := map.center()
	var r := WorldSeed.MANOR_MAX_RING + 2
	for y in range(mid.y - r, mid.y + r + 1):
		for x in range(mid.x - r, mid.x + r + 1):
			map.tiles[y * map.size + x] = TerrainMap.Tile.WATER
	assert_true(not WorldSeed.is_playable_map(map), "zalane wzgórze odrzucone")
	return true


func test_map_without_road_is_rejected() -> bool:
	var map := TerrainMap.generate(WorldSeed.FALLBACK_SEED)
	for i in map.tiles.size():
		if map.tiles[i] == TerrainMap.Tile.PATH or map.tiles[i] == TerrainMap.Tile.BRIDGE:
			map.tiles[i] = TerrainMap.Tile.GRASS
	assert_true(not WorldSeed.is_playable_map(map), "mapa bez drogi odrzucona")
	return true


func test_debug_override_parses_only_valid_seeds() -> bool:
	assert_eq(WorldSeed.debug_override(PackedStringArray(["--seed=42"])), 42, "poprawny seed")
	assert_eq(WorldSeed.debug_override(PackedStringArray(["--x", "--seed=7"])), 7, "seed po innym argumencie")
	assert_eq(WorldSeed.debug_override(PackedStringArray([])), 0, "brak argumentu")
	assert_eq(WorldSeed.debug_override(PackedStringArray(["--seed=abc"])), 0, "nie liczba")
	assert_eq(WorldSeed.debug_override(PackedStringArray(["--seed=0"])), 0, "zero")
	assert_eq(WorldSeed.debug_override(PackedStringArray(["--seed=-5"])), 0, "ujemny")
	assert_eq(WorldSeed.debug_override(PackedStringArray(["--seed=4294967296"])), 0, "poza zakresem")
	return true


func test_seed_survives_save_round_trip() -> bool:
	var s := WorldSeed.first_playable(WorldSeed.MAX_SEED)
	var grid := BuildGrid.new(TerrainMap.generate(s))
	var data := SaveGame.to_dict(s, grid, Economy.new(0), BuildQueue.new())
	# zapis przechodzi przez JSON, który trzyma liczby jako double
	var parsed: Variant = JSON.parse_string(JSON.stringify(data))
	var state := SaveGame.from_dict(parsed as Dictionary, 0)
	assert_true(state != null, "zapis czytelny")
	if state != null:
		assert_eq(state.world_seed, s, "seed po odczycie")
		assert_eq(state.grid.terrain.tiles, grid.terrain.tiles, "ten sam teren po odczycie")
	return true
