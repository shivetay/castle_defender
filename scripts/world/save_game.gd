class_name SaveGame
extends RefCounted
## Zapis lokalny stanu gry: JSON w user:// z numerem wersji formatu.
## Zapis idzie najpierw do pliku tymczasowego (.tmp). Potem poprzedni plik główny przechodzi
## w kopię (.bak), a .tmp staje się plikiem głównym; same zmiany nazw, bez kopiowania, więc
## w każdej chwili na dysku leży co najmniej jeden pełny zapis. Odczyt próbuje pliku głównego,
## pełnego .tmp (awaria między zmianami nazw) i kopii. Nieczytelny plik główny jest odkładany
## obok (.broken), żeby następny zapis nie zrobił z niego kopii. Zapis z nowszej wersji gry
## też nie jest nadpisywany, tylko odkładany, a gra zaczyna od nowa.
## Zapisuje się tylko to, czego nie da się odtworzyć: seed terenu, budynki, surowce, towary, kolejkę, badania, armię,
## plany ataku, ustawienia obrony, sprawdzanie szczelności z Komendy umocnień, zwiad i generałów.

const FORMAT_VERSION := 11
const PATH := "user://castle.json"

## Migracje: wersja → funkcja przerabiająca słownik tej wersji na wersję o 1 wyższą.
## Przy zmianie formatu podnieś FORMAT_VERSION i dopisz tu migrację z poprzedniej wersji.
## Wersja 2 dodała badania (#12), wersja 3 towary w zbrojowni (#88), wersja 4 armię i szkolenie (#89),
## wersja 5 postęp samouczka PvE (#16), wersja 6 plan ataku i zdobyte zamki (#17), wersja 7 ustawienia
## obrony (#19), wersja 8 zadania obrony i priorytet wież (#20), wersja 9 sprawdzanie szczelności (#199),
## wersja 10 zwiad (#28), wersja 11 generałowie i komendant obrony (#31).
static var MIGRATIONS: Dictionary = {1: _from_v1, 2: _from_v2, 3: _from_v3, 4: _from_v4, 5: _from_v5, 6: _from_v6,
		7: _from_v7, 8: _from_v8, 9: _from_v9, 10: _from_v10}

## Stan gry odczytany z pliku.
class State:
	extends RefCounted
	var world_seed := 0
	## Ile fal samouczka PvE (#16) gracz już obronił.
	var pve_cleared := 0
	## Zapisany plan ataku (#17) i ile zamków-celów gracz już zdobył.
	var attack_plan := AttackPlan.new()
	var bots_beaten := 0
	## Wybrany cel Wyprawy: numer zamku na liście BotRoster (#26).
	var attack_target := 0
	## Ustawienia obrony (#19, #20): zadania oddziałów załogi i priorytet wież.
	var defense := DefensePlan.new()
	## Sprawdź z Komendy umocnień (#199): odliczanie, wykryte i wskazana luka.
	var seal := SealCheck.new()
	## Zwiad (#28): misja w drodze i raporty.
	var scouting := Scouting.new()
	## Generałowie (#31) i generał ataku.
	var generals := Generals.new()
	var grid: BuildGrid
	var economy: Economy
	var queue: BuildQueue
	var research: Research
	var goods: Goods
	var recruitment: Recruitment
	## Ile wpisów zapisu pominięto, bo nie pasowały (0 przy zdrowym zapisie).
	var skipped := 0


## Słownik zapisu dla stanu gry.
static func to_dict(world_seed: int, grid: BuildGrid, economy: Economy, queue: BuildQueue,
		research: Research = null, goods: Goods = null, recruitment: Recruitment = null, pve_cleared: int = 0,
		attack_plan: AttackPlan = null, bots_beaten: int = 0, defense: DefensePlan = null,
		attack_target: int = 0, seal: SealCheck = null, scouting: Scouting = null,
		generals: Generals = null) -> Dictionary:
	return {
		"version": FORMAT_VERSION,
		"world_seed": world_seed,
		"grid": grid.save_data(),
		"economy": economy.save_data(),
		"queue": queue.save_data(),
		"research": research.save_data() if research != null else {},
		"goods": goods.save_data() if goods != null else {},
		"recruitment": recruitment.save_data() if recruitment != null else {},
		"pve": {"cleared": pve_cleared},
		"attack": {"plan": attack_plan.to_dict() if attack_plan != null else {}, "beaten": bots_beaten,
				"target": attack_target},
		"defense": defense.to_dict() if defense != null else {},
		"seal": seal.save_data() if seal != null else {},
		"scout": scouting.save_data() if scouting != null else {},
		"generals": generals.save_data() if generals != null else {},
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
	# pojemność z Magazynów przed odczytem zapasów, bo odczyt przycina je do pojemności
	s.economy.refresh_capacity(s.grid)
	s.economy.load_data(d.get("economy", {}) as Dictionary)
	s.queue = BuildQueue.new()
	s.skipped += s.queue.load_data(d.get("queue", {}) as Dictionary, s.grid, now_ms)
	s.research = Research.new()
	s.skipped += s.research.load_data(d.get("research", {}) as Dictionary, now_ms)
	s.goods = Goods.new(s.economy.last_update_ms)
	s.goods.load_data(d.get("goods", {}) as Dictionary)
	s.recruitment = Recruitment.new()
	s.skipped += s.recruitment.load_data(d.get("recruitment", {}) as Dictionary, s.grid, now_ms)
	s.pve_cleared = clampi(int((d.get("pve", {}) as Dictionary).get("cleared", 0)), 0, PveWaves.COUNT)
	var attack := d.get("attack", {}) as Dictionary
	s.attack_plan = AttackPlan.from_dict(attack.get("plan", {}) as Dictionary)
	s.bots_beaten = maxi(0, int(attack.get("beaten", 0)))
	# cel spoza odblokowanych (np. stary zapis) wraca na najwyższy dostępny zamek
	var target := int(attack.get("target", BotRoster.last_unlocked(s.bots_beaten)))
	s.attack_target = target if BotRoster.is_unlocked(target, s.bots_beaten) else BotRoster.last_unlocked(s.bots_beaten)
	s.defense = DefensePlan.from_dict(d.get("defense", {}) as Dictionary)
	s.defense.prune(s.recruitment)
	s.skipped += s.seal.load_data(d.get("seal", {}) as Dictionary, s.grid, now_ms)
	var scout: Variant = d.get("scout", {})
	s.skipped += s.scouting.load_data(scout as Dictionary if scout is Dictionary else {}, now_ms)
	var gens: Variant = d.get("generals", {})
	s.skipped += s.generals.load_data(gens as Dictionary if gens is Dictionary else {})
	if not s.generals.has_general(s.defense.commander):
		s.defense.commander = -1
	s.generals.set_attack(s.generals.attack_kind, s.defense.commander)
	return s


## Wersja 1 → 2: zapis sprzed badań dostaje pusty stan badań.
static func _from_v1(d: Dictionary) -> Dictionary:
	d["research"] = {}
	return d


## Wersja 2 → 3: zapis sprzed towarów dostaje pustą zbrojownię.
static func _from_v2(d: Dictionary) -> Dictionary:
	d["goods"] = {}
	return d


## Wersja 3 → 4: zapis sprzed rekrutacji dostaje pustą armię.
static func _from_v3(d: Dictionary) -> Dictionary:
	d["recruitment"] = {}
	return d


## Wersja 4 → 5: zapis sprzed samouczka PvE zaczyna od pierwszej fali.
static func _from_v4(d: Dictionary) -> Dictionary:
	d["pve"] = {"cleared": 0}
	return d


## Wersja 5 → 6: zapis sprzed planu ataku dostaje pusty plan i zero zdobytych zamków.
static func _from_v5(d: Dictionary) -> Dictionary:
	d["attack"] = {"plan": {}, "beaten": 0}
	return d


## Wersja 6 → 7: zapis sprzed ustawień obrony: cała załoga stoi przy donżonie.
static func _from_v6(d: Dictionary) -> Dictionary:
	d["defense"] = {}
	return d


## Wersja 7 → 8: posterunki (#19) stają się zadaniami Obrona odcinka, wieże biją najbliższego.
static func _from_v7(d: Dictionary) -> Dictionary:
	d["defense"] = DefensePlan.from_v7(d.get("defense", {}) as Dictionary)
	return d


## Wersja 8 → 9: zapis sprzed Komendy umocnień nie ma trwającego ani zakończonego Sprawdź.
static func _from_v8(d: Dictionary) -> Dictionary:
	d["seal"] = {}
	return d


## Wersja 9 → 10: zapis sprzed zwiadu (#28) nie ma misji ani raportów.
static func _from_v9(d: Dictionary) -> Dictionary:
	d["scout"] = {}
	return d


## Wersja 10 → 11: zapis sprzed generałów (#31) dostaje pustą listę generałów.
static func _from_v10(d: Dictionary) -> Dictionary:
	d["generals"] = {}
	return d


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
