class_name SaveGame
extends RefCounted
## Zapis lokalny stanu gry: JSON w user:// z numerem wersji formatu.
## Zapis idzie najpierw do pliku tymczasowego (.tmp). Potem poprzedni plik główny przechodzi
## w kopię (.bak), a .tmp staje się plikiem głównym; same zmiany nazw, bez kopiowania, więc
## w każdej chwili na dysku leży co najmniej jeden pełny zapis. Odczyt próbuje pliku głównego,
## pełnego .tmp (awaria między zmianami nazw) i kopii. Nieczytelny plik główny jest odkładany
## obok (.broken), żeby następny zapis nie zrobił z niego kopii. Zapis z nowszej wersji gry
## też nie jest nadpisywany, tylko odkładany, a gra zaczyna od nowa.
## Zapisuje się tylko to, czego nie da się odtworzyć: seed terenu, budynki, surowce i kolejkę.

const FORMAT_VERSION := 1
const PATH := "user://castle.json"

## Migracje: wersja → funkcja przerabiająca słownik tej wersji na wersję o 1 wyższą.
## Przy zmianie formatu podnieś FORMAT_VERSION i dopisz tu migrację z poprzedniej wersji.
const MIGRATIONS := {}

## Stan gry odczytany z pliku.
class State:
	extends RefCounted
	var world_seed := 0
	var grid: BuildGrid
	var economy: Economy
	var queue: BuildQueue
	## Ile wpisów zapisu pominięto, bo nie pasowały (0 przy zdrowym zapisie).
	var skipped := 0


## Słownik zapisu dla stanu gry.
static func to_dict(world_seed: int, grid: BuildGrid, economy: Economy, queue: BuildQueue) -> Dictionary:
	return {
		"version": FORMAT_VERSION,
		"world_seed": world_seed,
		"grid": grid.save_data(),
		"economy": economy.save_data(),
		"queue": queue.save_data(),
	}


## Stan gry ze słownika zapisu (po migracji) albo null, gdy zapis jest nieczytelny.
static func from_dict(data: Dictionary, now_ms: int) -> State:
	var d := migrate(data)
	if d.is_empty() or not d.has("world_seed"):
		return null
	var s := State.new()
	s.world_seed = int(d["world_seed"])
	s.grid = BuildGrid.new(TerrainMap.generate(s.world_seed))
	s.skipped += s.grid.load_data(d.get("grid", {}) as Dictionary)
	s.economy = Economy.new(now_ms)
	s.economy.load_data(d.get("economy", {}) as Dictionary)
	s.queue = BuildQueue.new()
	s.skipped += s.queue.load_data(d.get("queue", {}) as Dictionary, s.grid, now_ms)
	return s


## Doprowadza zapis do bieżącej wersji formatu. Pusty słownik, gdy wersji brak, jest nowsza
## niż ta gra albo brakuje migracji.
static func migrate(data: Dictionary) -> Dictionary:
	var version := int(data.get("version", 0))
	if version < 1 or version > FORMAT_VERSION:
		return {}
	var d := data.duplicate(true)
	while version < FORMAT_VERSION:
		if not MIGRATIONS.has(version):
			return {}
		d = (MIGRATIONS[version] as Callable).call(d)
		version += 1
		d["version"] = version
	return d


## Zapisuje stan do `path`: pełny plik tymczasowy, poprzedni plik główny → .bak, .tmp → plik główny.
## Plik główny jest zawsze ostatnim udanym zapisem (nieczytelny odkłada load_state), więc kopia
## dostaje dobry zapis, a nie „cokolwiek leży pod `path`”.
static func write(path: String, data: Dictionary) -> Error:
	var tmp := path + ".tmp"
	var f := FileAccess.open(tmp, FileAccess.WRITE)
	if f == null:
		return FileAccess.get_open_error()
	f.store_string(JSON.stringify(data, "\t"))
	f.close()
	if FileAccess.file_exists(path):
		# rename nie nadpisuje istniejącego pliku na każdej platformie, więc najpierw zwalniamy .bak
		DirAccess.remove_absolute(path + ".bak")
		var err := DirAccess.rename_absolute(path, path + ".bak")
		if err != OK:
			return err
	return DirAccess.rename_absolute(tmp, path)


## Odczytuje słownik zapisu z pliku. Pusty słownik, gdy pliku nie ma albo to nie jest JSON.
static func read(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var json := JSON.new()
	# parse() zwraca kod błędu bez wpisu ERROR w logu (uszkodzony zapis to zwykła sytuacja)
	if json.parse(FileAccess.get_file_as_string(path)) != OK:
		return {}
	return json.data as Dictionary if json.data is Dictionary else {}


## Wczytuje stan gry z `path`, a gdy się nie da, z pełnego .tmp albo z kopii. Nieczytelny plik
## główny zostaje odłożony obok (path + ".broken"), także gdy stan udało się wczytać z innego
## pliku: następny write() nie zrobi wtedy z niego kopii i nie zniszczy dobrego .bak.
## Zwraca null, gdy zapisu nie ma albo żaden plik nie jest czytelny.
static func load_state(path: String, now_ms: int) -> State:
	var s := from_dict(read(path), now_ms)
	if s != null:
		return s
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(path + ".broken")
		DirAccess.rename_absolute(path, path + ".broken")
	for candidate: String in [path + ".tmp", path + ".bak"]:
		s = from_dict(read(candidate), now_ms)
		if s != null:
			return s
	return null


## Usuwa zapis wraz z kopią i plikiem tymczasowym (np. w testach).
static func delete(path: String) -> void:
	for p: String in [path, path + ".bak", path + ".tmp", path + ".broken"]:
		if FileAccess.file_exists(p):
			DirAccess.remove_absolute(p)
