extends TestCase
## Zapis lokalny (#13): zapis i odczyt dają ten sam stan, gra nadrabia czas po zamknięciu,
## zapis jest odporny na przerwanie, uszkodzony plik i nowszą wersję formatu.

const PATH := "user://test_save.json"
const SEED := 1337
const T0 := 1_700_000_000_000
const HOUR := 3600 * 1000
const K := BuildingTypes.Kind
const R := EconomyConfig.Res


func _free_cell(grid: BuildGrid, kind: int) -> Vector2i:
	var c := grid.terrain.center()
	for r in grid.terrain.size:
		for dy in range(-r, r + 1):
			for dx in range(-r, r + 1):
				var p := c + Vector2i(dx, dy)
				if grid.placement_for(p, kind) != Rect2i():
					return p
	return Vector2i(-1, -1)


## Zamek w trakcie gry: Dwór, gotowa chata poziom 2, wieża w budowie i czekający wał.
func _castle() -> Array:
	var grid := BuildGrid.new(TerrainMap.generate(SEED))
	grid.place_kind(_free_cell(grid, K.MANOR), K.MANOR)
	var economy := Economy.new(T0)
	var q := BuildQueue.new()
	q.order_build(grid, economy, _free_cell(grid, K.LUMBER_HUT), K.LUMBER_HUT, T0)
	var hut := q.placed_id
	q.update(T0 + 60 * 1000, grid, economy)
	q.order_upgrade(grid, economy, grid.manor_id(), T0 + 60 * 1000)
	q.update(T0 + 2 * HOUR, grid, economy)
	q.order_upgrade(grid, economy, hut, T0 + 2 * HOUR)
	q.order_build(grid, economy, _free_cell(grid, K.TOWER), K.TOWER, T0 + 2 * HOUR + 7)
	q.order_build(grid, economy, _free_cell(grid, K.RAMPART), K.RAMPART, T0 + 2 * HOUR + 9)
	q.update(T0 + 2 * HOUR + 1234, grid, economy)
	return [grid, economy, q]


func _snapshot(grid: BuildGrid, economy: Economy, q: BuildQueue) -> String:
	return JSON.stringify(SaveGame.to_dict(SEED, grid, economy, q))


func test_round_trip_keeps_state() -> bool:
	SaveGame.delete(PATH)
	var c := _castle()
	var grid: BuildGrid = c[0]
	var economy: Economy = c[1]
	var q: BuildQueue = c[2]
	assert_eq(SaveGame.write(PATH, SaveGame.to_dict(SEED, grid, economy, q)), OK, "zapis")
	var s := SaveGame.load_state(PATH, T0 + 2 * HOUR + 1234)
	assert_true(s != null, "odczyt")
	assert_eq(s.skipped, 0, "nic nie pominięto")
	assert_eq(s.world_seed, SEED, "seed")
	assert_eq(_snapshot(s.grid, s.economy, s.queue), _snapshot(grid, economy, q), "ten sam stan po odczycie")
	assert_eq(s.queue.orders.size(), 3, "trzy zlecenia")
	assert_eq(s.grid.manor_level(), 2, "dwór 2")
	SaveGame.delete(PATH)
	return true


## Kryterium #13 (oraz #10, #11 „po zamknięciu aplikacji”): wczytana po 6 godzinach gra kończy
## budowy i nalicza produkcję dokładnie tak, jak gdyby działała cały czas.
func test_closed_app_catches_up_like_running_one() -> bool:
	SaveGame.delete(PATH)
	var running := _castle()
	var saved := _castle()
	var t_save := T0 + 2 * HOUR + 1234
	SaveGame.write(PATH, SaveGame.to_dict(SEED, saved[0], saved[1], saved[2]))
	var later := t_save + 6 * HOUR
	(running[2] as BuildQueue).update(later, running[0], running[1])
	var s := SaveGame.load_state(PATH, later)
	s.queue.update(later, s.grid, s.economy)
	assert_true(s.queue.orders.is_empty(), "wszystkie budowy ukończone po zamknięciu")
	assert_eq(_snapshot(s.grid, s.economy, s.queue), _snapshot(running[0], running[1], running[2]),
			"zamknięta gra = działająca gra")
	assert_true(s.economy.amounts[R.WOOD] > (saved[1] as Economy).amounts[R.WOOD], "drewno przybyło")
	SaveGame.delete(PATH)
	return true


func test_write_keeps_backup_and_leaves_no_tmp() -> bool:
	SaveGame.delete(PATH)
	var c := _castle()
	SaveGame.write(PATH, SaveGame.to_dict(SEED, c[0], c[1], c[2]))
	(c[1] as Economy).add(R.GOLD, 77)
	SaveGame.write(PATH, SaveGame.to_dict(SEED, c[0], c[1], c[2]))
	assert_true(FileAccess.file_exists(PATH + ".bak"), "kopia poprzedniego zapisu")
	assert_true(not FileAccess.file_exists(PATH + ".tmp"), "bez pliku tymczasowego")
	var main_gold := int((SaveGame.read(PATH)["economy"] as Dictionary)["amounts"][R.GOLD])
	var bak_gold := int((SaveGame.read(PATH + ".bak")["economy"] as Dictionary)["amounts"][R.GOLD])
	assert_eq(main_gold - bak_gold, 77, "plik główny nowszy od kopii")
	SaveGame.delete(PATH)
	return true


## Przerwany zapis (urwany plik główny) nie gubi gry: odczyt bierze kopię.
func test_broken_main_file_falls_back_to_backup() -> bool:
	SaveGame.delete(PATH)
	var c := _castle()
	SaveGame.write(PATH, SaveGame.to_dict(SEED, c[0], c[1], c[2]))
	SaveGame.write(PATH, SaveGame.to_dict(SEED, c[0], c[1], c[2]))
	var text := FileAccess.get_file_as_string(PATH)
	var f := FileAccess.open(PATH, FileAccess.WRITE)
	f.store_string(text.substr(0, text.length() / 2))
	f.close()
	var s := SaveGame.load_state(PATH, T0)
	assert_true(s != null, "gra wczytana z kopii")
	assert_eq(s.grid.buildings.size(), (c[0] as BuildGrid).buildings.size(), "wszystkie budynki z kopii")
	SaveGame.delete(PATH)
	return true


## Scenariusz z review: urwany plik główny i dobra kopia → odczyt z kopii → zaraz zapis →
## ponowny odczyt nadal widzi zamek. Zepsuty plik główny nie może trafić do .bak.
func test_corrupt_main_then_save_keeps_good_backup() -> bool:
	SaveGame.delete(PATH)
	var c := _castle()
	var d := SaveGame.to_dict(SEED, c[0], c[1], c[2])
	SaveGame.write(PATH, d)
	SaveGame.write(PATH, d)
	var f := FileAccess.open(PATH, FileAccess.WRITE)
	f.store_string("{ urwany")
	f.close()
	var s := SaveGame.load_state(PATH, T0)
	assert_true(s != null, "stan z kopii")
	assert_true(not FileAccess.file_exists(PATH), "zepsuty plik główny odłożony")
	assert_eq(FileAccess.get_file_as_string(PATH + ".broken"), "{ urwany", "jako .broken")
	assert_eq(SaveGame.write(PATH, SaveGame.to_dict(SEED, s.grid, s.economy, s.queue)), OK, "zapis po odczycie z kopii")
	assert_true(SaveGame.read(PATH + ".bak").has("version"), "kopia nadal jest dobrym zapisem")
	var again := SaveGame.load_state(PATH, T0)
	assert_true(again != null, "ponowny odczyt widzi zamek, nie nową grę")
	assert_eq(again.grid.buildings.size(), (c[0] as BuildGrid).buildings.size(), "wszystkie budynki")
	SaveGame.delete(PATH)
	return true


## Awaria między zmianami nazw w write(): pliku głównego nie ma, pełny .tmp jest najnowszy.
func test_crash_between_renames_reads_tmp() -> bool:
	SaveGame.delete(PATH)
	var c := _castle()
	SaveGame.write(PATH, SaveGame.to_dict(SEED, c[0], c[1], c[2]))
	(c[1] as Economy).add(R.GOLD, 5)
	var newer := SaveGame.to_dict(SEED, c[0], c[1], c[2])
	var f := FileAccess.open(PATH + ".tmp", FileAccess.WRITE)
	f.store_string(JSON.stringify(newer))
	f.close()
	DirAccess.rename_absolute(PATH, PATH + ".bak")  # pierwsza zmiana nazwy zrobiona, druga nie
	var s := SaveGame.load_state(PATH, T0)
	assert_true(s != null, "stan odczytany")
	assert_eq(s.economy.amounts[R.GOLD], (c[1] as Economy).amounts[R.GOLD], "z najnowszego .tmp")
	SaveGame.delete(PATH)
	return true


## Nieczytelny zapis bez kopii: nowa gra, a stary plik zostaje odłożony, nie nadpisany.
func test_unreadable_save_is_set_aside() -> bool:
	SaveGame.delete(PATH)
	var f := FileAccess.open(PATH, FileAccess.WRITE)
	f.store_string("to nie jest JSON {")
	f.close()
	assert_true(SaveGame.load_state(PATH, T0) == null, "nowa gra")
	assert_true(not FileAccess.file_exists(PATH), "główny plik zwolniony")
	assert_eq(FileAccess.get_file_as_string(PATH + ".broken"), "to nie jest JSON {", "stary plik odłożony")
	SaveGame.delete(PATH)
	assert_true(SaveGame.load_state(PATH, T0) == null, "brak zapisu = nowa gra")
	return true


func test_versions_and_migrations() -> bool:
	var c := _castle()
	var d := SaveGame.to_dict(SEED, c[0], c[1], c[2])
	assert_eq(int(d["version"]), SaveGame.FORMAT_VERSION, "zapis ma bieżącą wersję")
	assert_eq(SaveGame.migrate(d), d, "bieżąca wersja bez zmian")
	var newer := d.duplicate(true)
	newer["version"] = SaveGame.FORMAT_VERSION + 1
	assert_true(SaveGame.migrate(newer).is_empty(), "nowszego formatu nie czytamy")
	assert_true(SaveGame.from_dict(newer, T0) == null, "nowszy zapis = brak stanu")
	var unversioned := d.duplicate(true)
	unversioned.erase("version")
	assert_true(SaveGame.migrate(unversioned).is_empty(), "zapis bez wersji odrzucony")
	for v in range(1, SaveGame.FORMAT_VERSION):
		assert_true(SaveGame.MIGRATIONS.has(v), "jest migracja z wersji %d" % v)
	return true


## Zapis z błędnymi wpisami wczytuje się bez awarii: złe budynki i ich zlecenia są pomijane,
## a zapasy nie przekraczają pojemności magazynów.
func test_tampered_entries_are_skipped() -> bool:
	var c := _castle()
	var d := SaveGame.to_dict(SEED, c[0], c[1], c[2])
	var buildings: Array = (d["grid"] as Dictionary)["buildings"]
	buildings.append([999, 2, 3, -5, -5, 3, 1])  # poza mapą
	buildings.append([1000, 77, 1, 1, 1, 1, 1])  # nieznany rodzaj
	(d["queue"] as Dictionary)["orders"].append({"building_id": 999, "level": 4, "cost": [1, 1, 1, 0]})
	((d["economy"] as Dictionary)["amounts"] as Array)[R.WOOD] = 999999
	var s := SaveGame.from_dict(JSON.parse_string(JSON.stringify(d)) as Dictionary, T0)
	assert_true(s != null, "zapis wczytany")
	assert_eq(s.skipped, 3, "dwa złe budynki i zlecenie bez budynku")
	assert_true(not s.grid.buildings.has(999), "zły budynek pominięty")
	assert_eq(s.economy.amounts[R.WOOD], EconomyConfig.CAPACITY[R.WOOD], "drewno przycięte do magazynu")
	var next_id := int((d["grid"] as Dictionary)["next_id"])
	assert_eq(s.grid.place_kind(_free_cell(s.grid, K.RAMPART), K.RAMPART), next_id,
			"nowy budynek dostaje kolejne id z zapisu (odrzucone wpisy go nie przesuwają)")
	return true


func test_same_save_same_castle() -> bool:
	var a := _castle()
	var d := JSON.stringify(SaveGame.to_dict(SEED, a[0], a[1], a[2]))
	var s1 := SaveGame.from_dict(JSON.parse_string(d) as Dictionary, T0 + 5 * HOUR)
	var s2 := SaveGame.from_dict(JSON.parse_string(d) as Dictionary, T0 + 5 * HOUR)
	s1.queue.update(T0 + 9 * HOUR, s1.grid, s1.economy)
	s2.queue.update(T0 + 9 * HOUR, s2.grid, s2.economy)
	assert_eq(_snapshot(s1.grid, s1.economy, s1.queue), _snapshot(s2.grid, s2.economy, s2.queue), "deterministycznie")
	return true
