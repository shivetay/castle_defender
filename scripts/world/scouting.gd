class_name Scouting
extends RefCounted
## Zwiad (#28): misja z Chaty tropicieli (od S3 Domu zwiadowców) na zamek z ekranu wyboru celu.
## Zwiad to same informacje, bez animacji na mapie. Zwiadowcy (Tropiciele, Zwiadowcy) wychodzą
## z armii na czas misji, a po jej końcu wracają wszyscy, część albo nikt. Raport (wynik, procent
## odsłoniętego zamku) czeka w budynku i na karcie celu, a plan ataku odsłania według niego
## fragment zamku-celu (ScoutIntel).
##
## Naraz idzie jedna misja. Wynik wynika z seeda misji (PixelCanvas.hash2 i RandomNumberGenerator
## z jawnym seedem), więc ta sama misja zawsze kończy się tak samo, także po wczytaniu zapisu.
## Na razie zwiad działa na zamki-boty; zwiad na gracza liczy serwer (osobny PR, #28).
## Stan (misja i raporty) jest w zapisie gry (SaveGame, klucz "scout").

enum Result { OK, NO_BUILDING, NO_TECH, NO_SCOUTS, BUSY, NO_RESOURCES, BAD_TARGET }

const MESSAGES: Array[String] = ["", "Najpierw zbuduj Chatę tropicieli", "Najpierw zbadaj S1 Tropiciele",
		"Brak zwiadowców: wyszkol Tropiciela", "Zwiadowcy są już w drodze", "Brak surowców na zwiad",
		"Tego celu nie da się zwiadować"]
## Technologia bazowa zwiadu i ta, która go poprawia.
const BASE_TECH := "S1"
const BETTER_TECH := "S3"
## Najwięcej raportów w pamięci (najstarsze wypadają).
const MAX_REPORTS := 10


class Mission:
	extends RefCounted
	var target_key := ""
	var target_name := ""
	## Wysłani zwiadowcy: rodzaj jednostki → liczba.
	var units: Dictionary[int, int] = {}
	var duration := 0
	var start_ms := 0
	var seed_value := 0
	## Czy przy wysłaniu było S3 i ile Wież sygnałowych ma cel.
	var s3 := false
	var towers := 0

	func sent() -> int:
		var n := 0
		for u: int in units:
			n += units[u]
		return n

	func finish_ms() -> int:
		return start_ms + ScoutConfig.duration_ms(duration)


class Report:
	extends RefCounted
	var target_key := ""
	var target_name := ""
	var outcome := 0
	## Ile procent zamku odsłania raport (0: bez danych).
	var percent := 0
	var sent := 0
	var returned := 0
	var finished_ms := 0
	## Seed obszaru odsłonięcia (ScoutIntel.region).
	var region_seed := 0

	func has_intel() -> bool:
		return percent > 0


var mission: Mission = null
## Raporty od najstarszego; na jeden cel jeden raport (nowszy zastępuje starszy).
var reports: Array[Report] = []
## Licznik misji do seeda (każda misja ma inny seed).
var missions_sent := 0


func is_busy() -> bool:
	return mission != null


func remaining_ms(now_ms: int) -> int:
	return maxi(0, mission.finish_ms() - now_ms) if mission != null else 0


func report_for(target_key: String) -> Report:
	for r in reports:
		if r.target_key == target_key:
			return r
	return null


## Gotowa Chata tropicieli (poziom ≥ 1).
static func has_building(grid: BuildGrid) -> bool:
	for id: int in grid.buildings:
		if grid.kinds[id] == BuildingTypes.Kind.SCOUT_HOUSE and grid.levels[id] >= 1:
			return true
	return false


## Zwiadowcy gotowi do misji (rodzaj → liczba), najwyżej ScoutConfig.MAX_SCOUTS, najpierw Tropiciele.
static func available(recruitment: Recruitment) -> Dictionary[int, int]:
	var out: Dictionary[int, int] = {}
	var left := ScoutConfig.MAX_SCOUTS
	for u in ScoutConfig.SCOUT_UNITS:
		var n := mini(recruitment.army_of(u), left)
		if n > 0:
			out[u] = n
			left -= n
	return out


static func count_of(units: Dictionary[int, int]) -> int:
	var n := 0
	for u: int in units:
		n += units[u]
	return n


## Czemu nie da się teraz wysłać zwiadu (Result.OK: da się). Bez sprawdzania celu.
func check(grid: BuildGrid, research: Research, recruitment: Recruitment, economy: Economy) -> Result:
	if not has_building(grid):
		return Result.NO_BUILDING
	if research == null or not research.is_done(BASE_TECH):
		return Result.NO_TECH
	if is_busy():
		return Result.BUSY
	var units := available(recruitment)
	if units.is_empty():
		return Result.NO_SCOUTS
	if economy != null and not economy.can_afford(ScoutConfig.cost(count_of(units))):
		return Result.NO_RESOURCES
	return Result.OK


## Wysyła zwiad na cel `target_key` (np. „bot:3”) na `duration` (indeks ScoutConfig.DURATION_S).
## Zwiadowcy wychodzą z armii, koszt schodzi z magazynu. `towers`: Wieże sygnałowe celu.
func send(target_key: String, target_name: String, duration: int, world_seed: int, now_ms: int,
		grid: BuildGrid, research: Research, recruitment: Recruitment, economy: Economy, towers: int = 0) -> Result:
	if target_key.is_empty():
		return Result.BAD_TARGET
	var r := check(grid, research, recruitment, economy)
	if r != Result.OK:
		return r
	var units := available(recruitment)
	if economy != null and not economy.spend(ScoutConfig.cost(count_of(units))):
		return Result.NO_RESOURCES
	for u: int in units:
		_take(recruitment, u, units[u])
	var m := Mission.new()
	m.target_key = target_key
	m.target_name = target_name
	m.units = units
	m.duration = clampi(duration, 0, ScoutConfig.duration_count() - 1)
	m.start_ms = now_ms
	m.s3 = research.is_done(BETTER_TECH)
	m.towers = maxi(0, towers)
	missions_sent += 1
	m.seed_value = mission_seed(world_seed, missions_sent, target_key)
	mission = m
	return Result.OK


## Seed misji: świat gracza, numer misji i cel.
static func mission_seed(world_seed: int, number: int, target_key: String) -> int:
	return PixelCanvas.hash2(world_seed, number, target_key.hash() & 0xffff) & 0x7fffffff


## Wynik misji `m` (bez zmiany stanu): raport z wynikiem, procentem i ocalałymi.
static func resolve(m: Mission) -> Report:
	var rng := RandomNumberGenerator.new()
	rng.seed = m.seed_value
	var roll := rng.randi_range(0, 99)
	var outcome := ScoutConfig.outcome_for_roll(roll, ScoutConfig.chances(m.s3, m.towers))
	var rep := Report.new()
	rep.target_key = m.target_key
	rep.target_name = m.target_name
	rep.outcome = outcome
	rep.sent = m.sent()
	rep.returned = ScoutConfig.survivors(outcome, rep.sent)
	rep.percent = ScoutConfig.report_percent(outcome, ScoutConfig.reveal_percent(m.duration, rep.sent, m.s3))
	rep.finished_ms = m.finish_ms()
	rep.region_seed = rng.randi() & 0x7fffffff
	return rep


## Kończy misję, gdy minął jej czas: ocaleli wracają do armii, raport trafia do listy.
## Zwraca raport właśnie skończonej misji albo null.
func update(now_ms: int, recruitment: Recruitment) -> Report:
	if mission == null or now_ms < mission.finish_ms():
		return null
	var rep := resolve(mission)
	_return_units(recruitment, mission.units, rep.returned)
	mission = null
	_store(rep)
	return rep


func _store(rep: Report) -> void:
	var old := report_for(rep.target_key)
	if old != null:
		reports.erase(old)
	reports.append(rep)
	while reports.size() > MAX_REPORTS:
		reports.remove_at(0)


## Zabiera `count` jednostek `unit` z oddziałów armii, od ostatnich oddziałów.
static func _take(recruitment: Recruitment, unit: int, count: int) -> void:
	var left := count
	var list := recruitment.squads_of(unit)
	for i in range(list.size() - 1, -1, -1):
		var s := list[i]
		var n := mini(s.count, left)
		s.count -= n
		left -= n
		if left <= 0:
			break
	var ids: Array[int] = []
	var alive: Array[int] = []
	for s in recruitment.squads:
		ids.append(s.id)
		alive.append(s.count)
	# usuwa puste oddziały bez szkolenia (ta sama zasada co po bitwie)
	recruitment.apply_losses(ids, alive)


## Ocaleli (`returned` z wysłanych) wracają do oddziałów swojego rodzaju; najpierw Tropiciele.
static func _return_units(recruitment: Recruitment, units: Dictionary[int, int], returned: int) -> void:
	var left := returned
	for u in ScoutConfig.SCOUT_UNITS:
		if left <= 0 or not units.has(u):
			continue
		var n := mini(units[u], left)
		left -= n
		while n > 0:
			var id := recruitment.default_squad(u)
			if id == Recruitment.NEW_SQUAD:
				id = recruitment.add_squad(u, 0)
			var s := recruitment.squad(id)
			var put := mini(n, recruitment.free_in_squad(id))
			if put <= 0:
				# pełny oddział z miejscami zajętymi przez szkolenie: nowy oddział
				id = recruitment.add_squad(u, 0)
				s = recruitment.squad(id)
				put = mini(n, RecruitmentConfig.SQUAD_SIZE)
			s.count += put
			n -= put


## Tekst wyniku raportu (karta budynku i karta celu).
static func report_text(rep: Report) -> String:
	match rep.outcome:
		ScoutConfig.Outcome.SUCCESS:
			return "Zwiad: %d%% zamku, wrócili %d/%d" % [rep.percent, rep.returned, rep.sent]
		ScoutConfig.Outcome.PARTIAL:
			return "Zwiad częściowy: %d%%, wrócili %d/%d" % [rep.percent, rep.returned, rep.sent]
		ScoutConfig.Outcome.ESCAPED:
			return "Zwiad wykryty: bez danych, wrócili %d/%d" % [rep.returned, rep.sent]
	return "Zwiad nieudany: zginęli %d/%d" % [rep.sent - rep.returned, rep.sent]


# --- Zapis ------------------------------------------------------------------------------------

func save_data() -> Dictionary:
	var reps: Array = []
	for r in reports:
		reps.append({"key": r.target_key, "name": r.target_name, "outcome": r.outcome, "percent": r.percent,
				"sent": r.sent, "returned": r.returned, "at": r.finished_ms, "region": r.region_seed})
	var d := {"sent": missions_sent, "reports": reps}
	if mission != null:
		var units: Array = []
		for u: int in mission.units:
			units.append([u, mission.units[u]])
		d["mission"] = {"key": mission.target_key, "name": mission.target_name, "units": units,
				"duration": mission.duration, "start_ms": mission.start_ms, "seed": mission.seed_value,
				"s3": mission.s3, "towers": mission.towers}
	return d


## Wczytuje stan z zapisu; złe wpisy pomija. Start misji z przyszłości (przestawiony zegar)
## przesuwa na `now_ms`. Zwraca liczbę pominiętych wpisów.
func load_data(d: Dictionary, now_ms: int) -> int:
	mission = null
	reports.clear()
	missions_sent = maxi(0, int(d.get("sent", 0)))
	var skipped := 0
	var raw_reps: Variant = d.get("reports", [])
	if raw_reps is Array:
		for e: Variant in raw_reps as Array:
			var rep := _report_from(e)
			if rep == null:
				skipped += 1
				continue
			_store(rep)
	var raw: Variant = d.get("mission")
	if raw is Dictionary:
		var m := _mission_from(raw as Dictionary, now_ms)
		if m == null:
			skipped += 1
		else:
			mission = m
	return skipped


static func _report_from(e: Variant) -> Report:
	if not e is Dictionary:
		return null
	var d := e as Dictionary
	var key := str(d.get("key", ""))
	var outcome := int(d.get("outcome", -1))
	if key.is_empty() or outcome < 0 or outcome >= ScoutConfig.OUTCOME_NAMES.size():
		return null
	var rep := Report.new()
	rep.target_key = key
	rep.target_name = str(d.get("name", ""))
	rep.outcome = outcome
	rep.percent = clampi(int(d.get("percent", 0)), 0, ScoutConfig.MAX_PERCENT)
	rep.sent = clampi(int(d.get("sent", 0)), 0, ScoutConfig.MAX_SCOUTS)
	rep.returned = clampi(int(d.get("returned", 0)), 0, rep.sent)
	rep.finished_ms = int(d.get("at", 0))
	rep.region_seed = int(d.get("region", 0)) & 0x7fffffff
	return rep


static func _mission_from(d: Dictionary, now_ms: int) -> Mission:
	var key := str(d.get("key", ""))
	var raw_units: Variant = d.get("units", [])
	if key.is_empty() or not raw_units is Array:
		return null
	var m := Mission.new()
	for e: Variant in raw_units as Array:
		if not e is Array or (e as Array).size() < 2:
			return null
		var u := int((e as Array)[0])
		var n := int((e as Array)[1])
		if not ScoutConfig.is_scout(u) or n < 1 or m.units.has(u):
			return null
		m.units[u] = n
	if m.units.is_empty() or count_of(m.units) > ScoutConfig.MAX_SCOUTS:
		return null
	m.target_key = key
	m.target_name = str(d.get("name", ""))
	m.duration = clampi(int(d.get("duration", 0)), 0, ScoutConfig.duration_count() - 1)
	m.start_ms = mini(int(d.get("start_ms", 0)), now_ms)
	m.seed_value = int(d.get("seed", 0)) & 0x7fffffff
	m.s3 = bool(d.get("s3", false))
	m.towers = maxi(0, int(d.get("towers", 0)))
	return m
