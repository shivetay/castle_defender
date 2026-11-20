class_name Battle
extends RefCounted
## Deterministyczna symulacja bitwy (#14): stały krok 30 Hz, tylko liczby całkowite w logice,
## własny RNG z seedem (BattleRng), szukanie drogi przez AStarGrid2D i pełne oddzielenie od
## rysowania (ten obiekt nie zna żadnego węzła sceny). Ten sam zamek, te same armie i ten sam seed
## dają zawsze ten sam przebieg i wynik, co umożliwia powtórki i weryfikację na serwerze.
##
## Atakujący idą do celu (`objective`, w grze donżon, #120), po drodze walczą z obrońcami,
## a umocnienia na drodze burzą. Obrońcy bronią się przy celu i ruszają na wroga, który podejdzie.
## Wieże strzelają do atakujących. Atakujący wygrywa, gdy cel padnie albo gdy jego piechota
## utrzyma się przy celu przez CAPTURE_S sekund bez obrońców w pobliżu (zdobycie). Obrońca wygrywa,
## gdy atakujący zostaną wybici albo minie limit czasu. Zniszczenie innych budynków, także Dworu,
## nie kończy bitwy.

enum Side { ATTACKER, DEFENDER }
enum Winner { NONE = -1, ATTACKER, DEFENDER }
## ATTACKERS_ROUTED: żaden atakujący nie walczy, bo reszta się wycofała (#98).
enum EndReason { NONE, DESTROYED, CAPTURED, ATTACKERS_DEAD, TIME_LIMIT, ATTACKERS_ROUTED }
## Zdarzenia dla efektów bitwy (#101): strzał (od strzelca do celu), uderzenie w budynek, zawalenie.
enum Fx { SHOT, HIT, COLLAPSE }
## Strzelec „wieża” w zdarzeniu SHOT (wieża nie jest jednostką).
const FX_TOWER := -1


class Fighter:
	extends RefCounted
	var id := 0
	var unit := 0
	var side := 0
	## Pozycja w podjednostkach (kratka × BattleConfig.SUB).
	var x := 0
	var y := 0
	var hp := 0
	var cooldown := 0
	var target := 0  ## id wrogiej jednostki albo 0
	var path: Array[Vector2i] = []
	var path_index := 0
	var repath_in := 0
	## Kratka, do której prowadzi `path` (cel ataku albo wróg).
	var path_goal := Vector2i(-1, -1)
	## Kratka, wokół której obrońca trzyma pozycję.
	var post := Vector2i.ZERO
	## Kratka, na którą jednostka wycofuje się po złamaniu oddziału (#98): miejsce startu atakującego,
	## a dla obrońcy kratka przy donżonie, także gdy jego oddział stał na wysuniętym posterunku (#19).
	var rally := Vector2i.ZERO
	## Stanowisko (#20, #232): id wału, palisady, wieży albo donżonu, na którym jednostka stoi, albo 0.
	var wall := 0
	## Pułapki (#100): ile ticków jednostka jeszcze stoi (Wilczy dół) i ile jeszcze płonie.
	var stun := 0
	var fire := 0
	## Numer oddziału po swojej stronie (od 1, w kolejności armii).
	var squad := 0
	## Kopijnik już zaszarżował (szarża działa tylko w pierwszym uderzeniu).
	var charged := false
	## Oddział jednostki się złamał i ona wraca na start (#98).
	var retreating := false
	## Plan ataku (#18): ile punktów trasy oddziału jednostka już minęła, ile ticków wspina się
	## po drabinie i czy jest już po drugiej stronie muru.
	var wp := 0
	var climb := 0
	var climbed := false

	func cell() -> Vector2i:
		@warning_ignore("integer_division")
		return Vector2i(x / BattleConfig.SUB, y / BattleConfig.SUB)

	func alive() -> bool:
		return hp > 0


## Pułapka w bitwie (#100): rodzaj i kratka z ustawień obrony, czy już zadziałała, do którego ticku
## działa (Kolczatka, Płonące strzały) i kratki, na których działa (Zrzucane kłody, Wrząca smoła).
class TrapState:
	extends RefCounted
	var kind := 0
	var cell := Vector2i.ZERO
	var fired := false
	var until := 0
	var area: Array[Vector2i] = []


class Structure:
	extends RefCounted
	var id := 0
	var kind := 0
	var rect := Rect2i()
	var hp := 0
	var max_hp := 0
	## Poziom budynku 1–5 (Kopiec, #35: od poziomu zależy premia zasięgu sąsiednich wież).
	var level := 0
	## Wytrzymałość z poziomu budynku, przed premiami z badań (#12, O2 liczy się od niej).
	var base_hp := 0
	var cooldown := 0
	## Ile ticków budynek jeszcze płonie (Podpalacz).
	var burning := 0


var tick := 0
var winner: int = Winner.NONE
var end_reason: int = EndReason.NONE
## Ile ticków z rzędu piechota atakującego trzyma cel bez obrońców w pobliżu.
var capture_ticks := 0
## Morale oddziałów (#98): klucz _squad_key(strona, oddział) → 0..MORALE_MAX.
var morale: Dictionary[int, int] = {}
## Początkowa liczebność oddziałów (ten sam klucz), do straty morale za poległego.
var squad_size: Dictionary[int, int] = {}
var fighters: Array[Fighter] = []
var structures: Dictionary[int, Structure] = {}
var objective := 0
## Ile procent tempa strzelania mają wieże (zbrojownia bez strzał: 50%, #88).
var tower_fire_percent := 100
## Zbadane technologie stron (#12; klucz Side → {kod: true}), które działają w bitwie: A1 Hartowane
## topory, A2 Łuk kompozytowy, O2 Zaostrzone pale. Ustawia je apply_research() przed startem.
var techs: Dictionary[int, Dictionary] = {Side.ATTACKER: {}, Side.DEFENDER: {}}
## Ustawienia obrony (#19, #20): zadanie oddziału obrońcy (klucz: numer oddziału), punkty patrolu
## (kratki, na których da się stanąć) i priorytet celów wież (DefensePlan.TowerPriority).
var defence: Dictionary[int, DefensePlan.Order] = {}
var tower_priority := 0
var _patrol: Dictionary[int, Array] = {}
## Wypad konnicy (#20): brama oddziału (klucz: numer oddziału obrońcy) i oddziały, które już wyszły.
var _sortie_gate: Dictionary[int, int] = {}
var _sortie_out: Dictionary[int, bool] = {}
## Pułapki obrońcy (#100) w kolejności z ustawień obrony.
var traps: Array[TrapState] = []
## Fosa sucha obrońcy (#35): kratka → poziom fosy. Fosa nie jest budynkiem bitwy (structures): nie
## blokuje drogi i nie da się jej zburzyć, tylko spowalnia atakujących, a z O3 ich rani.
var moat: Dictionary[Vector2i, int] = {}
## Gaszenie pożarów (#35): Studnia oddziału obrońcy (klucz: numer oddziału) albo 0.
var _fire_well: Dictionary[int, int] = {}
## Kopce przy wieżach (#35): id wieży drewnianej albo donżonu → id Kopców, które stykają się z nią bokiem.
var _mounds_by: Dictionary[int, Array] = {}

var _terrain: TerrainMap
var _cells: PackedInt32Array
var _astar := AStarGrid2D.new()
## Drogi Tarana: tylko do bram, inne budynki są dla niego nieprzechodnie.
var _ram_astar := AStarGrid2D.new()
## Drogi wycofania (#98): każdy żywy budynek jest nieprzechodni, więc wycofany oddział omija mury
## i wraca przez bramy wyłomów, zamiast stać w murze.
var _retreat_astar := AStarGrid2D.new()
var _rng: BattleRng
var _next_id := 1
## Czy zapisywać zdarzenia dla efektów (#101). Włącza je tylko widok; symulacja ich nie czyta
## i nie liczy w sumie kontrolnej, więc efekty nie zmieniają przebiegu. Bez widoku lista nie rośnie.
var record_fx := false
## Plan ataku (#18) albo null: wtedy każdy oddział atakującego idzie jak w Szturmie frontalnym na cel.
var plan: AttackPlan
## Stan rozkazów oddziałów (klucz _squad_key): wystartował, wykonał zadanie (sygnał dla Start.AFTER_SQUAD),
## wycofuje się z rozkazu, polegli, trasa (punkty), budynek-cel manewru i punkt ostrzału (Ostrzał).
var _sq_started: Dictionary[int, bool] = {}
var _sq_done: Dictionary[int, bool] = {}
var _sq_retreat: Dictionary[int, bool] = {}
var _sq_dead: Dictionary[int, int] = {}
var _sq_route: Dictionary[int, Array] = {}
var _sq_goal: Dictionary[int, int] = {}
## Ostrzał: jedna kratka postoju na oddział (ustalana raz); stąd oddział strzela, bez dalszego marszu.
var _sq_fire: Dictionary[int, Vector2i] = {}
var _spawn := Vector2i.ZERO
## Zdarzenie: [tick, Fx, jednostka albo FX_TOWER, x0, y0, x1, y1]. SHOT i HIT w podjednostkach
## (HIT: x1, y1 to punkt trafienia), COLLAPSE w kratkach (pozycja i rozmiar budynku).
var _fx: Array[PackedInt32Array] = []


## Bitwa na zamku z `grid`. `attackers` i `defenders`: {UnitTypes.Unit: liczba}; każdy rodzaj staje
## jako jeden oddział (w kolejności rodzajów). Atakujący stają przy kratce `spawn`, obrońcy wokół celu.
static func create(grid: BuildGrid, objective_id: int, attackers: Dictionary, defenders: Dictionary, spawn: Vector2i,
		seed_value: int) -> Battle:
	return create_squads(grid, objective_id, _dict_to_squads(attackers), _dict_to_squads(defenders), spawn, seed_value)


## {rodzaj: liczba} jako lista oddziałów [rodzaj, liczba] w kolejności rodzajów (niezależnie od
## kolejności kluczy słownika).
static func _dict_to_squads(army: Dictionary) -> Array:
	var units: Array[int] = []
	for unit: int in army:
		units.append(unit)
	units.sort()
	var out: Array = []
	for unit in units:
		if int(army[unit]) > 0:
			out.append([unit, int(army[unit])])
	return out


## Bitwa z oddziałami (#89, #15): `attackers` i `defenders` to listy oddziałów [rodzaj, liczba]
## (np. z Recruitment.battle_squads()), w kolejności ustawienia. `defender_orders` (#19, #20): zadanie
## każdego oddziału obrońcy w tej samej kolejności (DefensePlan.battle_orders); oddział staje na
## miejscu swojego zadania, a bez zadania (null, miejsce poza mapą albo poza listą) przy celu.
static func create_squads(grid: BuildGrid, objective_id: int, attackers: Array, defenders: Array, spawn: Vector2i,
		seed_value: int, defender_orders: Array[DefensePlan.Order] = []) -> Battle:
	var b := Battle.new()
	b._rng = BattleRng.new(seed_value)
	b._terrain = grid.terrain
	b._cells = grid.cells.duplicate()
	b.objective = objective_id
	for id: int in grid.buildings:
		if grid.levels[id] < 1:
			continue  # plac budowy nie broni się
		if BuildingTypes.is_passable(grid.kinds[id]):
			# fosa (#35) to rów: kratka jest wolna dla drogi, a fosa działa na tego, kto na niej stoi
			for y in range(grid.buildings[id].position.y, grid.buildings[id].end.y):
				for x in range(grid.buildings[id].position.x, grid.buildings[id].end.x):
					b.moat[Vector2i(x, y)] = grid.levels[id]
					b._cells[y * grid.terrain.size + x] = 0
			continue
		var s := Structure.new()
		s.id = id
		s.kind = grid.kinds[id]
		s.rect = grid.buildings[id]
		s.level = grid.levels[id]
		s.max_hp = BattleConfig.building_hp(s.kind, grid.levels[id])
		s.base_hp = s.max_hp
		s.hp = s.max_hp
		b.structures[id] = s
	b._link_mounds()
	b._setup_astar()
	b._spawn = spawn
	b._spawn_squads(attackers, Side.ATTACKER, spawn)
	var center := grid.buildings[objective_id].get_center() if grid.buildings.has(objective_id) else Vector2i(spawn)
	var home := Vector2i(center) + Vector2i(0, 2)
	var anchors: Array[Vector2i] = []
	for i in defenders.size():
		var o: DefensePlan.Order = defender_orders[i] if i < defender_orders.size() else null
		if o == null or not b._terrain.in_bounds(o.post):
			anchors.append(home)
			continue
		anchors.append(o.post)
		b.defence[i + 1] = o
		var points: Array = []
		for p in o.patrol_points():
			points.append(b._walkable_near(p))
		b._patrol[i + 1] = points
		if o.task == DefensePlan.Task.SORTIE:
			b._sortie_gate[i + 1] = b._gate_near(o.post)
		if o.task == DefensePlan.Task.FIREFIGHT:
			b._fire_well[i + 1] = b._well_near(o.post)
	b._spawn_squads(defenders, Side.DEFENDER, home, anchors)
	return b


## Bitwa o donżon zamku z `grid` (#120): cel to Wieża grodowa.
## `research` obrońcy daje premie morale załogi (U1 Wiec grodowy, #98); każda bitwa z gry ma iść
## przez tę fabrykę, żeby premii nie zgubić.
static func for_castle(grid: BuildGrid, attackers: Dictionary, defenders: Dictionary, spawn: Vector2i,
		seed_value: int, research: Research = null) -> Battle:
	var b := create(grid, grid.keep_id(), attackers, defenders, spawn, seed_value)
	b.add_side_morale(Side.DEFENDER, BattleConfig.defender_morale_bonus(research))
	return b


## for_castle z oddziałami [rodzaj, liczba] (fale PvE #16 i armia z rekrutacji).
## `defender_orders` i `tower_priority`: ustawienia obrony (#19, #20), jak w create_squads.
static func for_castle_squads(grid: BuildGrid, attackers: Array, defenders: Array, spawn: Vector2i,
		seed_value: int, research: Research = null, defender_orders: Array[DefensePlan.Order] = [],
		tower_priority: int = DefensePlan.TowerPriority.NEAREST) -> Battle:
	var b := create_squads(grid, grid.keep_id(), attackers, defenders, spawn, seed_value, defender_orders)
	b.tower_priority = tower_priority
	b.add_side_morale(Side.DEFENDER, BattleConfig.defender_morale_bonus(research))
	return b


## Technologie strony `side` z badań gracza (#12). Wołać przed pierwszym krokiem bitwy: O2 Zaostrzone
## pale od razu wzmacnia palisady obrońcy. Bez wywołania strona walczy bez premii z badań.
func apply_research(side: int, research: Research) -> void:
	var known: Dictionary = {}
	if research != null:
		for code: String in battle_tech_codes():
			if research.is_done(code):
				known[code] = true
	techs[side] = known
	if side == Side.DEFENDER:
		# od bazowej wytrzymałości, więc ponowne wywołanie nie mnoży premii drugi raz (review #187)
		for id: int in structures:
			var st := structures[id]
			if st.kind == BuildingTypes.Kind.PALISADE:
				st.max_hp = st.base_hp
				if known.has("O2"):
					@warning_ignore("integer_division")
					st.max_hp = st.base_hp * BattleConfig.O2_PALISADE_HP_PERCENT / 100
				st.hp = st.max_hp


## Kody technologii, które coś zmieniają w bitwie.
static func battle_tech_codes() -> Array[String]:
	return ["A1", "A2", "O2", "O3"] as Array[String]


func has_tech(side: int, code: String) -> bool:
	return techs[side].has(code)


## Zasięg ataku jednostki w kratkach: z UnitTypes, a łuki strony z A2 Łuk kompozytowy +20% (#12).
func range_of(f: Fighter) -> int:
	var r := UnitTypes.attack_range(f.unit)
	if (f.unit == UnitTypes.Unit.ARCHER or f.unit == UnitTypes.Unit.REFLEX_ARCHER) and has_tech(f.side, "A2"):
		@warning_ignore("integer_division")
		r = r * BattleConfig.A2_RANGE_PERCENT / 100
	return r


## Puszcza bitwę do końca albo do `max_ticks`. Zwraca zwycięzcę (Winner).
func run(max_ticks: int = -1) -> int:
	var limit := BattleConfig.time_limit_ticks() if max_ticks < 0 else max_ticks
	while winner == Winner.NONE and tick < limit:
		step()
	return winner


## Jeden krok symulacji (1/30 s).
func step() -> void:
	if winner != Winner.NONE:
		return
	tick += 1
	for f in fighters:
		if f.alive():
			_act(f)
	if not traps.is_empty():
		_traps_act()
	if not moat.is_empty() and tick % BattleConfig.TICK_HZ == 0 and has_tech(Side.DEFENDER, "O3"):
		_moat_spikes()
	for id: int in structures:
		var s := structures[id]
		if s.hp > 0 and (s.kind == BuildingTypes.Kind.TOWER \
				or (s.kind == BuildingTypes.Kind.KEEP and keep_manned(s))):
			_tower_act(s)
		if s.hp > 0 and s.burning > 0:
			_burn(s)
	_check_end()


## Zdarzenia efektów od ostatniego odczytu (#101); lista się czyści.
func take_fx() -> Array[PackedInt32Array]:
	var out := _fx
	_fx = []
	return out


func _record(kind: int, who: int, x0: int, y0: int, x1: int, y1: int) -> void:
	if record_fx:
		_fx.append(PackedInt32Array([tick, kind, who, x0, y0, x1, y1]))


## Jednostki strony, które jeszcze walczą: żywe i niewycofane. Wóz (#235) nie walczy, więc gdy
## z armii zostały same wozy, atak się kończy, zamiast czekać na limit czasu.
func fighting_count(side: int) -> int:
	var n := 0
	for f in fighters:
		if f.side == side and f.alive() and not routed(f) and f.unit != UnitTypes.Unit.WAGON:
			n += 1
	return n


# --- Morale (#98) ----------------------------------------------------------------------------------

static func _squad_key(side: int, squad: int) -> int:
	return side * 10000 + squad


func squad_morale(side: int, squad: int) -> int:
	return int(morale.get(_squad_key(side, squad), BattleConfig.MORALE_START))


## Zmienia morale oddziału o `amount` (np. śmierć generała, MORALE_GENERAL_DEATH), w granicach 0..100.
func add_squad_morale(side: int, squad: int, amount: int) -> void:
	var key := _squad_key(side, squad)
	if morale.has(key):
		morale[key] = clampi(int(morale[key]) + amount, 0, BattleConfig.MORALE_MAX)


## Zmienia morale wszystkich oddziałów strony, np. premia załogi z badań przed startem bitwy
## (BattleConfig.defender_morale_bonus).
func add_side_morale(side: int, amount: int) -> void:
	for key: int in morale:
		@warning_ignore("integer_division")
		if key / 10000 == side:
			morale[key] = clampi(int(morale[key]) + amount, 0, BattleConfig.MORALE_MAX)


## Oddział poniżej MORALE_ROUT wycofuje się sam i już nie walczy; tak samo oddział, który według
## planu ataku stracił swój próg strat (#18).
func routed(f: Fighter) -> bool:
	return squad_morale(f.side, f.squad) < BattleConfig.MORALE_ROUT or _sq_retreat.has(_squad_key(f.side, f.squad))


## Wycofana jednostka, która już stoi na swojej kratce wycofania i nie ma dokąd uciekać.
func cornered(f: Fighter) -> bool:
	return absi(f.cell().x - f.rally.x) <= 1 and absi(f.cell().y - f.rally.y) <= 1


## Obrażenia dla jednostki; śmierć zabiera morale jej oddziałowi (loss_morale).
func _hurt(f: Fighter, dmg: int) -> void:
	if not f.alive():
		return
	f.hp -= dmg
	if not f.alive():
		add_squad_morale(f.side, f.squad, -loss_morale(f.side, f.squad))
		_count_loss(f)


## Strata morale oddziału za jednego poległego: MORALE_SQUAD_LOSS rozłożone na początkowy skład.
func loss_morale(side: int, squad: int) -> int:
	@warning_ignore("integer_division")
	return maxi(1, BattleConfig.MORALE_SQUAD_LOSS / maxi(1, int(squad_size.get(_squad_key(side, squad), 1))))


func alive_count(side: int) -> int:
	var n := 0
	for f in fighters:
		if f.side == side and f.alive():
			n += 1
	return n


## Oddziały jednej strony do rysowania (#15): dla każdego oddziału z żywymi jednostkami
## {squad, unit, alive, hp, max_hp, x, y, morale}, gdzie x, y to średnia pozycja żywych w podjednostkach.
func squads_view(side: int) -> Array[Dictionary]:
	var by_squad := {}
	var order: Array[int] = []
	for f in fighters:
		if f.side != side:
			continue
		if not by_squad.has(f.squad):
			by_squad[f.squad] = {"squad": f.squad, "unit": f.unit, "alive": 0, "hp": 0, "max_hp": 0, "x": 0, "y": 0,
					"morale": squad_morale(side, f.squad)}
			order.append(f.squad)
		var v: Dictionary = by_squad[f.squad]
		v["max_hp"] = int(v["max_hp"]) + UnitTypes.hp(f.unit)
		if f.alive():
			v["alive"] = int(v["alive"]) + 1
			v["hp"] = int(v["hp"]) + f.hp
			v["x"] = int(v["x"]) + f.x
			v["y"] = int(v["y"]) + f.y
	var out: Array[Dictionary] = []
	for sq in order:
		var v: Dictionary = by_squad[sq]
		var n := int(v["alive"])
		if n == 0:
			continue
		@warning_ignore("integer_division")
		var cx := int(v["x"]) / n
		@warning_ignore("integer_division")
		var cy := int(v["y"]) / n
		# pozycja odznaki to żywa jednostka oddziału najbliżej jego środka (przy remisie pierwsza): średnia
		# oddziału rozdzielonego murem wypadała na murze, choć nikt tam nie stał (po teście na telefonie)
		var best_d := -1
		for f in fighters:
			if f.side == side and f.squad == sq and f.alive():
				var d := _dist2(f.x, f.y, cx, cy)
				if best_d < 0 or d < best_d:
					best_d = d
					v["x"] = f.x
					v["y"] = f.y
		v["key"] = _squad_key(side, sq)
		out.append(v)
	return out


## Żywi po stronie `side` w każdym oddziale, w kolejności armii z create_squads (indeks 0 = oddział 1),
## także 0 dla wybitych. Wycofani (#98) przeżyli, więc się liczą.
func survivors(side: int) -> Array[int]:
	var out: Array[int] = []
	for f in fighters:
		if f.side != side:
			continue
		while out.size() < f.squad:
			out.append(0)
		if f.alive():
			out[f.squad - 1] += 1
	return out


## Suma kontrolna stanu bitwy (do testów determinizmu i późniejszej weryfikacji na serwerze).
func checksum() -> int:
	var h := tick * 31 + winner + 7 + end_reason * 131 + capture_ticks
	for f in fighters:
		h = _mix(h, f.id)
		h = _mix(h, f.x)
		h = _mix(h, f.y)
		h = _mix(h, f.hp)
		h = _mix(h, f.squad)
		h = _mix(h, 1 if f.charged else 0)
		h = _mix(h, f.wp * 2 + (1 if f.climbed else 0))
		h = _mix(h, f.climb)
		# kratka wycofania (review #180): dwie bitwy z różnym rozstawieniem obrońców różnią się już na starcie
		h = _mix(h, f.rally.x * 256 + f.rally.y)
		h = _mix(h, f.wall)
		h = _mix(h, f.stun * 1024 + f.fire)
	for id: int in structures:
		h = _mix(h, id)
		h = _mix(h, structures[id].hp)
		h = _mix(h, structures[id].burning)
	for c: Vector2i in moat:
		h = _mix(h, c.x * 256 + c.y)
		h = _mix(h, moat[c])
	for key: int in morale:
		h = _mix(h, key)
		h = _mix(h, int(morale[key]))
	# stan rozkazów planu ataku (#18), żeby weryfikacja w trakcie bitwy (#29) widziała też je
	for t in traps:
		h = _mix(h, (1 if t.fired else 0) + t.until * 2)
	for key: int in squad_size:
		var flags := (1 if _sq_started.has(key) else 0) + (2 if _sq_done.has(key) else 0) \
				+ (4 if _sq_retreat.has(key) else 0) + (8 if _sortie_out.has(key) else 0)
		h = _mix(h, flags)
		h = _mix(h, int(_sq_dead.get(key, 0)))
	return h


static func _mix(h: int, v: int) -> int:
	return PixelCanvas.hash2(h, v, 0x2545)


# --- Przygotowanie -------------------------------------------------------------------------------

func _setup_astar() -> void:
	_astar.region = Rect2i(0, 0, _terrain.size, _terrain.size)
	_astar.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_NEVER
	_astar.update()
	for y in _terrain.size:
		for x in _terrain.size:
			var c := Vector2i(x, y)
			if _terrain.get_tile(c) == TerrainMap.Tile.WATER:
				_astar.set_point_solid(c, true)
			elif _cells[y * _terrain.size + x] != 0:
				_astar.set_point_weight_scale(c, BattleConfig.BUILDING_PATH_WEIGHT)
	_ram_astar.region = _astar.region
	_ram_astar.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_NEVER
	_ram_astar.update()
	for y in _terrain.size:
		for x in _terrain.size:
			var c := Vector2i(x, y)
			var id := _cells[y * _terrain.size + x]
			if _terrain.get_tile(c) == TerrainMap.Tile.WATER:
				_ram_astar.set_point_solid(c, true)
			elif id != 0 and structures.has(id) and structures[id].kind != BuildingTypes.Kind.GATE:
				_ram_astar.set_point_solid(c, true)
	_retreat_astar.region = _astar.region
	_retreat_astar.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_NEVER
	_retreat_astar.update()
	for y in _terrain.size:
		for x in _terrain.size:
			var c := Vector2i(x, y)
			var id := _cells[y * _terrain.size + x]
			if _terrain.get_tile(c) == TerrainMap.Tile.WATER or (id != 0 and structures.has(id)):
				_retreat_astar.set_point_solid(c, true)


## Stawia oddziały strony `side` na wolnych kratkach wokół `at`, a oddział `i` wokół `anchors[i]`,
## gdy lista go obejmuje (posterunki obrony, #19). Każdy punkt zaczepienia wypełnia się od środka
## w stałej kolejności, a kratka zajęta przez wcześniejszą jednostkę jest pomijana, więc dwa
## sąsiednie posterunki nie stawiają ludzi na sobie. Z jednym punktem wynik jest taki jak dawniej.
## Jednostka z posterunku dostaje kratkę wycofania przy `at` (pod donżonem), reszta wycofuje się tam,
## gdzie stanęła.
func _spawn_squads(squads: Array, side: int, at: Vector2i, anchors: Array[Vector2i] = []) -> void:
	var units: Array[int] = []
	var squad_of: Array[int] = []
	for i in squads.size():
		var sq: Array = squads[i]
		for n in int(sq[1]):
			units.append(int(sq[0]))
			squad_of.append(i + 1)
	# punkt zaczepienia → ile kratek wokół niego już sprawdzono
	var placed: Dictionary[Vector2i, int] = {}
	var taken: Dictionary[Vector2i, bool] = {}
	var rally_n := 0
	# stanowiska na murze (#20): kratki linii wału i palisady od miejsca oddziału, w stałej kolejności;
	# na wieży i donżonie (#232) kratki budynku
	var wall_cells: Dictionary[Vector2i, Array] = {}
	for k in units.size():
		var unit := units[k]
		var f := Fighter.new()
		f.squad = squad_of[k]
		f.id = _next_id
		_next_id += 1
		f.unit = unit
		f.side = side
		f.hp = UnitTypes.hp(unit)
		var anchor := anchors[f.squad - 1] if f.squad - 1 < anchors.size() else at
		var station := anchor
		if _keep_station(side, f.squad, f.unit, anchor, at):
			station = structures[objective].rect.position
		if _wall_station(side, f.squad, f.unit, station):
			if not wall_cells.has(station):
				wall_cells[station] = _wall_line(station)
			var free_wall := Vector2i(-1, -1)
			for c: Vector2i in wall_cells[station]:
				if not taken.has(c):
					free_wall = c
					break
			if free_wall.x >= 0:
				# na murze: kratka muru jest stanowiskiem, bez szukania wolnej trawy
				taken[free_wall] = true
				f.wall = _cells[free_wall.y * _terrain.size + free_wall.x]
				_place_fighter(f, free_wall, at, station, rally_n)
				rally_n += 1
				continue
		var cell := _free_cell_near(anchor, int(placed.get(anchor, 0)))
		placed[anchor] = int(placed.get(anchor, 0)) + 1
		# zajęte przez sąsiedni posterunek: kolejne kratki pierścieni (z limitem na pełną mapę)
		var tries := 0
		while taken.has(cell) and tries < BattleConfig.SPAWN_RETRIES:
			cell = _free_cell_near(anchor, int(placed[anchor]))
			placed[anchor] = int(placed[anchor]) + 1
			tries += 1
		taken[cell] = true
		_place_fighter(f, cell, at, anchor, rally_n)
		if anchor != at:
			rally_n += 1


## Stawia jednostkę `f` na kratce `cell`: posterunek, kratka wycofania (przy `at`, gdy oddział ma
## własne miejsce `anchor`), rozrzut gotowości do ataku i morale oddziału.
func _place_fighter(f: Fighter, cell: Vector2i, at: Vector2i, anchor: Vector2i, rally_n: int) -> void:
	f.x = cell.x * BattleConfig.SUB + BattleConfig.SUB / 2
	f.y = cell.y * BattleConfig.SUB + BattleConfig.SUB / 2
	f.post = cell
	f.rally = cell
	if anchor != at:
		# kratki wycofania mogą się powtarzać z miejscami innych jednostek: to tylko cel marszu
		f.rally = _free_cell_near(at, rally_n)
	f.cooldown = _rng.range_int(0, BattleConfig.ATTACK_COOLDOWN_TICKS - 1)
	fighters.append(f)
	var key := _squad_key(f.side, f.squad)
	morale[key] = BattleConfig.MORALE_START
	squad_size[key] = int(squad_size.get(key, 0)) + 1


## Czy jednostka `unit` oddziału `squad` strony `side` staje na stanowisku: strzelec obrońcy z Obroną
## odcinka, którego miejsce to kratka żywego wału albo palisady (#20), wieży drewnianej (#232) albo Kopca (#35),
## a także strzelec przy donżonie (_keep_station). Inni stają pod murem.
func _wall_station(side: int, squad: int, unit: int, anchor: Vector2i) -> bool:
	if side != Side.DEFENDER or UnitTypes.unit_class(unit) != RecruitmentConfig.UnitClass.RANGED:
		return false
	var s := _structure_at(anchor)
	if s == null:
		return false
	if s.kind == BuildingTypes.Kind.KEEP:
		return s.id == objective
	if not defence.has(squad) or defence[squad].task != DefensePlan.Task.HOLD:
		return false
	return BuildingTypes.is_wall(s.kind) or s.kind == BuildingTypes.Kind.TOWER or s.kind == BuildingTypes.Kind.MOUND


## Czy strzelec obrońcy z oddziału przy donżonie (bez zadania albo z zadaniem Przy donżonie, miejsce
## `anchor` to `home`) staje na donżonie jako jego załoga (#232). Miejsc jest tyle, ile kratek donżonu;
## reszta staje pod nim.
func _keep_station(side: int, squad: int, unit: int, anchor: Vector2i, home: Vector2i) -> bool:
	if side != Side.DEFENDER or anchor != home or UnitTypes.unit_class(unit) != RecruitmentConfig.UnitClass.RANGED:
		return false
	if defence.has(squad) and defence[squad].task != DefensePlan.Task.KEEP:
		return false
	var s: Structure = structures.get(objective, null)
	return s != null and s.kind == BuildingTypes.Kind.KEEP and s.hp > 0


## Kratki stanowisk od `start`: na wieży, donżonie i Kopcu kratki budynku wierszami (#232, #35), na murze linia
## wału i palisady połączona z `start` (bokami), od `start` wszerz, sąsiedzi w stałej kolejności N, E, S, W.
func _wall_line(start: Vector2i) -> Array:
	var st := _structure_at(start)
	if st != null and (st.kind == BuildingTypes.Kind.TOWER or st.kind == BuildingTypes.Kind.KEEP \
			or st.kind == BuildingTypes.Kind.MOUND):
		var cells: Array = []
		for y in range(st.rect.position.y, st.rect.end.y):
			for x in range(st.rect.position.x, st.rect.end.x):
				cells.append(Vector2i(x, y))
		return cells
	var out: Array = [start]
	var seen: Dictionary[Vector2i, bool] = {start: true}
	var i := 0
	while i < out.size():
		var c: Vector2i = out[i]
		i += 1
		for d: Vector2i in [Vector2i.UP, Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT]:
			var n := c + d
			if seen.has(n) or not _terrain.in_bounds(n):
				continue
			seen[n] = true
			var s := _structure_at(n)
			if s != null and BuildingTypes.is_wall(s.kind):
				out.append(n)
	return out


## `n`-ta wolna kratka w pierścieniach wokół `c` (kolejność stała).
func _free_cell_near(c: Vector2i, n: int) -> Vector2i:
	var seen := 0
	for r in _terrain.size:
		for dy in range(-r, r + 1):
			for dx in range(-r, r + 1):
				if maxi(absi(dx), absi(dy)) != r:
					continue
				var p := c + Vector2i(dx, dy)
				if not _terrain.in_bounds(p) or _astar.is_point_solid(p) or _cells[p.y * _terrain.size + p.x] != 0:
					continue
				if seen == n:
					return p
				seen += 1
	return c


# --- Jednostki -------------------------------------------------------------------------------------

func _act(f: Fighter) -> void:
	if f.cooldown > 0:
		f.cooldown -= 1
	if f.stun > 0:
		f.stun -= 1  # w wilczym dole (#100): ani kroku, ani ciosu
		return
	if routed(f):
		# wycofanie (#98): bez walki na swoją kratkę wycofania, drogą omijającą żywe budynki
		f.target = 0
		if not f.retreating:
			f.retreating = true
			f.path.clear()
		if f.wall != 0:
			_step_down(f)
		if cornered(f):
			# osaczony na swojej kratce (obrońca przy donżonie): nie ściga, ale oddaje wrogom w zasięgu (#16)
			var near := _enemy_for(f)
			if near != null and _in_range(f, near.x, near.y, range_of(f)):
				f.target = near.id
				_strike_unit(f, near)
				return
		_walk(f, f.rally, f.rally.x * BattleConfig.SUB + BattleConfig.SUB / 2, f.rally.y * BattleConfig.SUB + BattleConfig.SUB / 2,
				false, _retreat_astar)
		return
	var order := _order(f)
	if order != null:
		_act_order(f, order)
		return
	if f.side == Side.DEFENDER and defence.has(f.squad):
		_defend(f, defence[f.squad])
		return
	if f.side == Side.DEFENDER and f.wall != 0:
		# załoga donżonu bez zadania (#232): stoi na stanowisku jak strzelcy na murze (review #244)
		_wall_act(f)
		return
	_default_act(f)


## Zachowanie bez rozkazu: obrońca broni posterunku, atakujący idzie na cel bitwy, Taran na bramę.
## Wóz bez zaplanowanej trasy stoi tam, gdzie jest (#235).
func _default_act(f: Fighter) -> void:
	if f.unit == UnitTypes.Unit.WAGON:
		f.target = 0
		return
	if f.unit == UnitTypes.Unit.RAM:
		_ram_act(f)
		return
	var enemy := _enemy_for(f)
	if enemy != null:
		f.target = enemy.id
		if _in_range(f, enemy.x, enemy.y, range_of(f)):
			_strike_unit(f, enemy)
		else:
			# pościg też idzie po ścieżce: atakujący przebija się przez umocnienia, obrońca czeka
			_walk(f, enemy.cell(), enemy.x, enemy.y, f.side == Side.ATTACKER)
		return
	f.target = 0
	if f.side == Side.DEFENDER:
		_walk(f, f.post, f.post.x * BattleConfig.SUB + BattleConfig.SUB / 2, f.post.y * BattleConfig.SUB + BattleConfig.SUB / 2, false)
		return
	_advance(f)


## Najbliższy żywy wróg w zasięgu wzroku (zasięg + AGGRO_EXTRA); przy remisie niższe id.
## Jednostka bez ataku (Tropiciel) nie wdaje się w walkę.
func _enemy_for(f: Fighter) -> Fighter:
	if UnitTypes.attack(f.unit) <= 0:
		return null
	var best: Fighter = null
	var best_d := 0
	var extra := BattleConfig.DEFENDER_AGGRO_EXTRA if f.side == Side.DEFENDER else BattleConfig.AGGRO_EXTRA
	var sight := (range_of(f) + extra) * BattleConfig.SUB
	var rider := f.unit == UnitTypes.Unit.RIDER
	var reach_walls := f.climbed or range_of(f) >= BattleConfig.RANGED_MIN_RANGE
	for o in fighters:
		if o.side == f.side or not o.alive():
			continue
		# obrońcę na murze i wieży (#20) wręcz dosięgnie tylko ten, kto wszedł po drabinie; załogę donżonu
		# bije też piechota spod donżonu, bo wchodzi się do niego bez drabiny (balans, #232)
		if o.wall != 0 and not reach_walls and not _on_keep(o):
			continue
		var d := _dist2(f.x, f.y, o.x, o.y)
		if d > sight * sight:
			continue
		# Jeździec omija wolne cele, chyba że stoją tuż obok (#15)
		if rider and UnitTypes.speed(o.unit) <= BattleConfig.RIDER_IGNORES_SPEED \
				and d > BattleConfig.SUB * BattleConfig.SUB * 2:
			continue
		if best == null or d < best_d:
			best = o
			best_d = d
	return best


## Atakujący bez wroga w pobliżu idzie do celu, a budynek na drodze burzy.
func _advance(f: Fighter) -> void:
	var goal := _objective_cell()
	if goal.x < 0:
		return
	_walk(f, goal, goal.x * BattleConfig.SUB + BattleConfig.SUB / 2, goal.y * BattleConfig.SUB + BattleConfig.SUB / 2, true)


## Ruch po ścieżce z `_astar` do kratki `goal`, a na jej końcu prosto do punktu (`px`, `py`).
## Żaden ruch nie wchodzi na kratkę żywego budynku: z `breach` jednostka z atakiem go burzy,
## inaczej czeka. Ścieżka liczy się od nowa co REPATH_TICKS, po wyłomie albo gdy cel odszedł
## dalej niż o kratkę od końca ścieżki.
func _walk(f: Fighter, goal: Vector2i, px: int, py: int, breach: bool, grid: AStarGrid2D = null) -> void:
	f.repath_in -= 1
	var moved_goal := absi(goal.x - f.path_goal.x) > 1 or absi(goal.y - f.path_goal.y) > 1
	if f.path.is_empty() or f.path_index >= f.path.size() or f.repath_in <= 0 or moved_goal:
		f.path = (grid if grid != null else _astar).get_id_path(f.cell(), goal)
		f.path_index = 1
		f.path_goal = goal
		f.repath_in = BattleConfig.REPATH_TICKS
	var tx := px
	var ty := py
	var next := f.cell()
	if f.path_index < f.path.size():
		next = f.path[f.path_index]
		tx = next.x * BattleConfig.SUB + BattleConfig.SUB / 2
		ty = next.y * BattleConfig.SUB + BattleConfig.SUB / 2
	elif next != goal:
		return  # brak drogi
	var blocker := _structure_at(next)
	if blocker != null and f.side == Side.DEFENDER and grid == _ram_astar and blocker.kind == BuildingTypes.Kind.GATE:
		blocker = null  # wypad konnicy (#20): własna brama to przejście
	if blocker != null:
		# budynek na drodze: z sąsiedniej kratki burzy go atakujący z atakiem
		if breach and UnitTypes.attack(f.unit) > 0 \
				and _in_range(f, tx, ty, maxi(1, range_of(f))):
			_strike_structure(f, blocker)
		else:
			var here := f.cell()
			_move_toward(f, here.x * BattleConfig.SUB + BattleConfig.SUB / 2, here.y * BattleConfig.SUB + BattleConfig.SUB / 2)
		return
	if f.x == tx and f.y == ty:
		f.path_index += 1
		return
	_move_toward(f, tx, ty)


func _objective_cell() -> Vector2i:
	if not structures.has(objective):
		return Vector2i(-1, -1)
	return structures[objective].rect.position


## Żywy budynek na kratce `c` albo null.
func _structure_at(c: Vector2i) -> Structure:
	if not _terrain.in_bounds(c):
		return null
	var id := _cells[c.y * _terrain.size + c.x]
	if id == 0 or not structures.has(id):
		return null
	var s := structures[id]
	return s if s.hp > 0 else null


## Ruch w stronę punktu, najpierw w osi z większą różnicą (całe podjednostki).
func _move_toward(f: Fighter, tx: int, ty: int) -> void:
	var step_len := UnitTypes.speed(f.unit) * BattleConfig.SPEED_SUB_PER_TICK
	if f.side == Side.ATTACKER and UnitTypes.unit_class(f.unit) == RecruitmentConfig.UnitClass.FAST and _in_caltrops(f.cell()):
		@warning_ignore("integer_division")
		step_len = maxi(1, step_len * TrapConfig.CALTROPS_SLOW_PERCENT / 100)
	if f.side == Side.ATTACKER and moat.has(f.cell()):
		@warning_ignore("integer_division")
		step_len = maxi(1, step_len * BattleConfig.MOAT_SPEED_PERCENT / 100)
	var dx := clampi(tx - f.x, -step_len, step_len)
	var dy := clampi(ty - f.y, -step_len, step_len)
	# woda jest nieprzechodnia (#248): krok, który kończy się w wodzie, idzie drugą osią albo wcale
	if absi(tx - f.x) >= absi(ty - f.y):
		if _dry(f.x + dx, f.y):
			f.x += dx
		elif dy != 0 and _dry(f.x, f.y + dy):
			f.y += dy
	else:
		if _dry(f.x, f.y + dy):
			f.y += dy
		elif dx != 0 and _dry(f.x + dx, f.y):
			f.x += dx


## Czy punkt (`x`, `y`) w podjednostkach leży na lądzie (most to ląd).
func _dry(x: int, y: int) -> bool:
	if x < 0 or y < 0:
		return false
	@warning_ignore("integer_division")
	return _terrain.is_walkable(Vector2i(x / BattleConfig.SUB, y / BattleConfig.SUB))


func _in_range(f: Fighter, tx: int, ty: int, cells: int) -> bool:
	var r := maxi(1, cells) * BattleConfig.SUB
	return _dist2(f.x, f.y, tx, ty) <= r * r


static func _dist2(ax: int, ay: int, bx: int, by: int) -> int:
	return (ax - bx) * (ax - bx) + (ay - by) * (ay - by)


func _strike_unit(f: Fighter, enemy: Fighter) -> void:
	if f.cooldown > 0:
		return
	f.cooldown = BattleConfig.ATTACK_COOLDOWN_TICKS
	var dmg := unit_damage(f, enemy)
	if f.side == Side.DEFENDER and range_of(f) >= BattleConfig.RANGED_MIN_RANGE \
			and _fire_arrows_near(f.cell()):
		@warning_ignore("integer_division")
		dmg = dmg * TrapConfig.FIRE_ARROWS_PERCENT / 100
		_ignite_arrow_target(enemy)
	_hurt(enemy, _roll(dmg))
	f.charged = true
	if range_of(f) >= BattleConfig.RANGED_MIN_RANGE:
		_record(Fx.SHOT, f.unit, f.x, f.y, enemy.x, enemy.y)


## Obrażenia uderzenia `f` w `enemy` przed rozrzutem: przewagi klas (#87) i cechy jednostek (#15, #92).
func unit_damage(f: Fighter, enemy: Fighter) -> int:
	var dmg := UnitTypes.damage(f.unit, enemy.unit)
	var ranged := range_of(f) >= BattleConfig.RANGED_MIN_RANGE
	if f.unit == UnitTypes.Unit.LANCER and not f.charged:
		dmg = dmg * BattleConfig.CHARGE_PERCENT / 100
	if ranged and _behind_shields(enemy):
		dmg = dmg * BattleConfig.SHIELD_WALL_PERCENT / 100
	if ranged and enemy.wall != 0:
		dmg = dmg * BattleConfig.WALL_ARROW_PERCENT / 100
	if not ranged and enemy.unit == UnitTypes.Unit.GAMBESON_WARRIOR:
		dmg = dmg * BattleConfig.GAMBESON_MELEE_PERCENT / 100
	return morale_damage(f, dmg)


## Wysokie morale (powyżej MORALE_HIGH): +10% obrażeń (#98), co najmniej +1, żeby premia działała
## też przy słabych atakach (łucznik 7, tarczownik 5).
func morale_damage(f: Fighter, dmg: int) -> int:
	if dmg > 0 and squad_morale(f.side, f.squad) > BattleConfig.MORALE_HIGH:
		@warning_ignore("integer_division")
		return dmg + maxi(1, dmg * (BattleConfig.MORALE_HIGH_DAMAGE_PERCENT - 100) / 100)
	return dmg


## Czy jednostka stoi za ścianą tarcz: sama jest Tarczownikiem albo ma żywego Tarczownika
## swojej strony w promieniu 1 kratki.
func _behind_shields(target: Fighter) -> bool:
	if target.unit == UnitTypes.Unit.SHIELDBEARER:
		return true
	var r := BattleConfig.SUB
	for o in fighters:
		if o.side == target.side and o.alive() and o.unit == UnitTypes.Unit.SHIELDBEARER \
				and absi(o.x - target.x) <= r and absi(o.y - target.y) <= r:
			return true
	return false


func _strike_structure(f: Fighter, s: Structure) -> void:
	if f.cooldown > 0:
		return
	f.cooldown = BattleConfig.ATTACK_COOLDOWN_TICKS
	var dmg := structure_damage(f.unit, s.kind)
	if f.unit == UnitTypes.Unit.AXE_WARRIOR and BuildingTypes.is_wooden(s.kind) and has_tech(f.side, "A1"):
		@warning_ignore("integer_division")
		dmg = dmg * BattleConfig.A1_WOOD_PERCENT / 100
	s.hp -= _roll(morale_damage(f, dmg))
	f.charged = true  # szarża to pierwsze uderzenie w ogóle, także w umocnienie
	if record_fx:
		var hx := clampi(f.x, s.rect.position.x * BattleConfig.SUB, s.rect.end.x * BattleConfig.SUB - 1)
		var hy := clampi(f.y, s.rect.position.y * BattleConfig.SUB, s.rect.end.y * BattleConfig.SUB - 1)
		var ranged := range_of(f) >= BattleConfig.RANGED_MIN_RANGE
		_record(Fx.SHOT if ranged else Fx.HIT, f.unit, f.x, f.y, hx, hy)
	if f.unit == UnitTypes.Unit.FIRE_RAISER and BuildingTypes.is_wooden(s.kind):
		s.burning = BattleConfig.FIRE_S * BattleConfig.TICK_HZ
	if s.hp <= 0:
		_destroy(s)


## Obrażenia jednostki `unit` w budynek `kind` przed rozrzutem (#15): topór ×1,5 przeciw drewnu,
## Taran tylko w bramy.
static func structure_damage(unit: int, kind: int) -> int:
	if unit == UnitTypes.Unit.RAM and kind != BuildingTypes.Kind.GATE:
		return 0
	var dmg := UnitTypes.attack(unit)
	if unit == UnitTypes.Unit.AXE_WARRIOR and BuildingTypes.is_wooden(kind):
		dmg = dmg * BattleConfig.AXE_VS_WOOD_PERCENT / 100
	return dmg


## Płonący budynek traci FIRE_DAMAGE_PER_S punktów co sekundę, aż ogień zgaśnie albo budynek padnie.
## Po FIRE_SPREAD_S sekundach ogień przechodzi na sąsiednie drewno.
func _burn(s: Structure) -> void:
	s.burning -= 1
	if s.burning == (BattleConfig.FIRE_S - BattleConfig.FIRE_SPREAD_S) * BattleConfig.TICK_HZ:
		_spread_fire(s)
	if s.burning % BattleConfig.TICK_HZ == 0:
		s.hp -= BattleConfig.FIRE_DAMAGE_PER_S
		if s.hp <= 0:
			_destroy(s)


## Ogień z `s` zajmuje sąsiednie żywe drewniane budynki, które jeszcze nie płoną (#101).
## Kolejność budynków jest stała, więc rozprzestrzenianie też.
func _spread_fire(s: Structure) -> void:
	var near := s.rect.grow(1)
	for id: int in structures:
		var o := structures[id]
		if o != s and o.hp > 0 and o.burning == 0 and BuildingTypes.is_wooden(o.kind) and near.intersects(o.rect):
			o.burning = BattleConfig.FIRE_S * BattleConfig.TICK_HZ


## Taran (#15): nie walczy z jednostkami, jedzie do najbliższej żywej bramy i tylko ją bije.
## Inne budynki są dla niego nieprzechodnie; bez bram stoi.
func _ram_act(f: Fighter, target_gate: Structure = null) -> void:
	var gate := target_gate if target_gate != null and target_gate.hp > 0 else _nearest_gate(f)
	if gate == null:
		return
	var gx := (gate.rect.position.x * 2 + gate.rect.size.x) * BattleConfig.SUB / 2
	var gy := (gate.rect.position.y * 2 + gate.rect.size.y) * BattleConfig.SUB / 2
	var reach := (maxi(gate.rect.size.x, gate.rect.size.y) + 2) * BattleConfig.SUB / 2
	if _dist2(f.x, f.y, gx, gy) <= reach * reach:
		_strike_structure(f, gate)
		return
	f.repath_in -= 1
	if f.path.is_empty() or f.path_index >= f.path.size() or f.repath_in <= 0:
		f.path = _ram_astar.get_id_path(f.cell(), gate.rect.position)
		f.path_index = 1
		f.repath_in = BattleConfig.REPATH_TICKS
	if f.path_index >= f.path.size():
		return
	var next := f.path[f.path_index]
	var tx := next.x * BattleConfig.SUB + BattleConfig.SUB / 2
	var ty := next.y * BattleConfig.SUB + BattleConfig.SUB / 2
	if f.x == tx and f.y == ty:
		f.path_index += 1
		return
	_move_toward(f, tx, ty)


func _nearest_gate(f: Fighter) -> Structure:
	var best: Structure = null
	var best_d := 0
	for id: int in structures:
		var s := structures[id]
		if s.kind != BuildingTypes.Kind.GATE or s.hp <= 0:
			continue
		var d := _dist2(f.x, f.y, s.rect.position.x * BattleConfig.SUB, s.rect.position.y * BattleConfig.SUB)
		if best == null or d < best_d:
			best = s
			best_d = d
	return best


## Obrażenia z rozrzutem z RNG bitwy (90–110%), co najmniej 1 przy niezerowym ataku.
func _roll(base: int) -> int:
	if base <= 0:
		return 0
	@warning_ignore("integer_division")
	return maxi(1, base * _rng.range_int(BattleConfig.DAMAGE_MIN_PERCENT, BattleConfig.DAMAGE_MAX_PERCENT) / 100)


func _destroy(s: Structure) -> void:
	s.hp = 0
	s.burning = 0
	_record(Fx.COLLAPSE, s.kind, s.rect.position.x, s.rect.position.y, s.rect.size.x, s.rect.size.y)
	for y in range(s.rect.position.y, s.rect.end.y):
		for x in range(s.rect.position.x, s.rect.end.x):
			_cells[y * _terrain.size + x] = 0
			_astar.set_point_weight_scale(Vector2i(x, y), BattleConfig.FREE_PATH_WEIGHT)
			_ram_astar.set_point_solid(Vector2i(x, y), false)
			_retreat_astar.set_point_solid(Vector2i(x, y), false)
	for f in fighters:
		f.repath_in = 0  # wyłom zmienia najkrótszą drogę


# --- Plan ataku (#18) --------------------------------------------------------------------------------

## Ustawia plan ataku przed bitwą: trasy oddziałów (Oskrzydlenie bez własnej trasy dostaje punkt
## obejścia z boku). Punkty trasy przesuwają się na najbliższą wolną kratkę. Null zdejmuje plan:
## wszyscy walczą jak bez rozkazu.
func set_plan(p: AttackPlan) -> void:
	plan = p
	_sq_route.clear()
	if p == null:
		return
	for o in p.orders:
		var route: Array = []
		var points: Array[Vector2i] = o.waypoints.duplicate()
		if o.manoeuvre == AttackPlan.Manoeuvre.FLANK and points.is_empty():
			points.append(flank_point(o))
		for w in points:
			route.append(_walkable_near(w))
		_sq_route[_squad_key(Side.ATTACKER, o.squad)] = route


## Rozkaz oddziału jednostki albo null (obrońcy i oddziały bez rozkazu).
func _order(f: Fighter) -> AttackPlan.Order:
	if plan == null or f.side != Side.ATTACKER:
		return null
	return plan.order_for(f.squad)


## Punkt obejścia dla Oskrzydlenia: w połowie drogi od miejsca startu do celu, przesunięty w bok
## (w lewo albo w prawo patrząc na cel) o połowę tej drogi, co najmniej FLANK_MIN_CELLS.
func flank_point(o: AttackPlan.Order) -> Vector2i:
	return flank_point_between(_spawn, _goal_cell_for(o), o.flank_left, _terrain.size)


## Punkt obejścia między wejściem `spawn` a celem `goal` na mapie `size`×`size` (wspólny dla bitwy
## i strzałki na ekranie planu, #17).
static func flank_point_between(spawn: Vector2i, goal: Vector2i, left: bool, size: int) -> Vector2i:
	var d := goal - spawn
	var side := Vector2i(d.y, -d.x) if left else Vector2i(-d.y, d.x)
	var m := maxi(1, maxi(absi(side.x), absi(side.y)))
	@warning_ignore("integer_division")
	var length := maxi(BattleConfig.FLANK_MIN_CELLS, maxi(absi(d.x), absi(d.y)) / 2)
	@warning_ignore("integer_division")
	var p := spawn + d / 2 + Vector2i(side.x * length / m, side.y * length / m)
	var last := size - 1
	return Vector2i(clampi(p.x, 0, last), clampi(p.y, 0, last))


## Kratka celu rozkazu do wyznaczania obejścia: wskazany cel albo cel bitwy.
func _goal_cell_for(o: AttackPlan.Order) -> Vector2i:
	if o.target != AttackPlan.NO_TARGET:
		return o.target
	if structures.has(objective):
		return structures[objective].rect.get_center()
	return _spawn


## Najbliższa kratka bez wody i bez budynku (pierścienie wokół `c`, kolejność stała).
func _walkable_near(c: Vector2i) -> Vector2i:
	var last := _terrain.size - 1
	var at := Vector2i(clampi(c.x, 0, last), clampi(c.y, 0, last))
	for r in _terrain.size:
		for dy in range(-r, r + 1):
			for dx in range(-r, r + 1):
				if maxi(absi(dx), absi(dy)) != r:
					continue
				var p := at + Vector2i(dx, dy)
				if _free_ground(p):
					return p
	return at


## Czy na kratce da się stanąć: na mapie, bez wody i bez żywego budynku.
func _free_ground(c: Vector2i) -> bool:
	return _terrain.is_walkable(c) and _structure_at(c) == null


func _act_order(f: Fighter, o: AttackPlan.Order) -> void:
	var key := _squad_key(f.side, f.squad)
	if not _sq_started.has(key):
		if not _start_ready(o) or (o.manoeuvre == AttackPlan.Manoeuvre.CONVOY and not _wagon_ready()):
			_hold(f)  # czeka na starcie, ale oddaje wrogom w zasięgu
			return
		_sq_started[key] = true
	if o.manoeuvre == AttackPlan.Manoeuvre.CONVOY:
		_order_convoy(f, key)
		return
	var route: Array = _sq_route.get(key, [])
	if f.wp < route.size():
		var w: Vector2i = route[f.wp]
		if absi(f.cell().x - w.x) <= 1 and absi(f.cell().y - w.y) <= 1:
			f.wp += 1
		elif not _hold(f):
			_walk(f, w, w.x * BattleConfig.SUB + BattleConfig.SUB / 2, w.y * BattleConfig.SUB + BattleConfig.SUB / 2, true)
		return
	match o.manoeuvre:
		AttackPlan.Manoeuvre.RANGED:
			_order_ranged(f, o, key)
		AttackPlan.Manoeuvre.FIRE:
			_order_fire(f, o, key)
		AttackPlan.Manoeuvre.LADDERS:
			_order_ladders(f, o, key)
		AttackPlan.Manoeuvre.RAM_GATE:
			_order_ram(f, o, key)
		_:
			_order_assault(f, o, key)  # Szturm frontalny i Oskrzydlenie (po obejściu)


## Wóz rusza najwcześniej po AttackPlan.WAGON_DELAY_S sekundach bitwy (#235).
func _wagon_ready() -> bool:
	return tick >= AttackPlan.WAGON_DELAY_S * BattleConfig.TICK_HZ


## Tabor (#235): Wóz jedzie po kolei przez punkty trasy drogą, która omija żywe budynki (nie burzy
## niczego, bo nie ma ataku), i staje na ostatnim. Dojazd na koniec trasy to wykonane zadanie
## (start „po oddziale” innych oddziałów). Wóz nie wdaje się w walkę.
func _order_convoy(f: Fighter, key: int) -> void:
	f.target = 0
	var route: Array = _sq_route.get(key, [])
	while f.wp < route.size():
		var w: Vector2i = route[f.wp]
		if absi(f.cell().x - w.x) > 1 or absi(f.cell().y - w.y) > 1:
			_walk(f, w, w.x * BattleConfig.SUB + BattleConfig.SUB / 2, w.y * BattleConfig.SUB + BattleConfig.SUB / 2,
					false, _retreat_astar)
			return
		f.wp += 1
	_sq_done[key] = true


func _start_ready(o: AttackPlan.Order) -> bool:
	match o.start:
		AttackPlan.Start.AFTER_SECONDS:
			return tick >= o.start_value * BattleConfig.TICK_HZ
		AttackPlan.Start.AFTER_SQUAD:
			var other := _squad_key(Side.ATTACKER, o.start_value)
			if _sq_done.has(other):
				return true
			# oddział, na który czekamy, już nie walczy: nie ma na co czekać
			for g in fighters:
				if g.side == Side.ATTACKER and g.squad == o.start_value and g.alive() and not routed(g):
					return false
			return true
	return true


## Bije wroga w zasięgu ataku bez pościgu; true, gdy było z kim walczyć.
func _hold(f: Fighter) -> bool:
	var enemy := _enemy_for(f)
	if enemy != null and _in_range(f, enemy.x, enemy.y, range_of(f)):
		f.target = enemy.id
		_strike_unit(f, enemy)
		return true
	f.target = 0
	return false


## Budynek-cel manewru oddziału: ustalony raz, przy pierwszym ruchu po trasie. Wskazana kratka
## daje budynek na niej, a bez wskazania `fallback` (np. najbliższa brama). Null, gdy cel padł.
func _goal(o: AttackPlan.Order, key: int, fallback: Structure) -> Structure:
	if not _sq_goal.has(key):
		var picked: Structure = null
		if o.target != AttackPlan.NO_TARGET:
			picked = _structure_at(o.target)
		if picked == null:
			picked = fallback
		_sq_goal[key] = picked.id if picked != null else 0
	var id := _sq_goal[key]
	if id == 0 or not structures.has(id) or structures[id].hp <= 0:
		_sq_done[key] = true
		return null
	return structures[id]


func _objective_structure() -> Structure:
	if structures.has(objective) and structures[objective].hp > 0:
		return structures[objective]
	return null


## Szturm frontalny: walczy po drodze jak bez rozkazu, ale idzie na swój cel i go burzy.
## Po zburzeniu celu oddział walczy dalej jak bez rozkazu.
func _order_assault(f: Fighter, o: AttackPlan.Order, key: int) -> void:
	var t := _goal(o, key, _objective_structure())
	if t == null:
		_default_act(f)
		return
	var enemy := _enemy_for(f)
	if enemy != null:
		f.target = enemy.id
		if _in_range(f, enemy.x, enemy.y, range_of(f)):
			_strike_unit(f, enemy)
		else:
			_walk(f, enemy.cell(), enemy.x, enemy.y, true)
		return
	f.target = 0
	_walk_to(f, t, true)


## Ostrzał z dystansu: oddział ma jeden punkt postoju w zasięgu celu. Wróg w zasięgu strzału —
## stój i strzelaj (bez podejścia). Marsz tylko gdy nikt nie jest w zasięgu, i tylko do tego
## punktu; stamtąd ostrzał budynku, bez dalszego chodzenia naprzód. Jednostki bez dystansu:
## jak w szturmie.
func _order_ranged(f: Fighter, o: AttackPlan.Order, key: int) -> void:
	var r := range_of(f)
	if r < BattleConfig.RANGED_MIN_RANGE:
		_order_assault(f, o, key)
		return
	var t := _goal(o, key, _objective_structure())
	if t == null:
		_default_act(f)
		return
	# Wróg w zasięgu strzału: stój i bij; nie idź naprzód.
	if _hold(f):
		return
	# Cel w zasięgu: ostrzał z miejsca, bez dalszego marszu pod mur.
	if _rect_in_range(f, t.rect, r):
		_strike_structure(f, t)
		return
	var hold := _fire_hold_cell(key, t, r)
	# Na wyznaczonym punkcie: stój (punkt jest w zasięgu); inaczej tylko dojście do niego.
	if f.cell() == hold:
		return
	_walk(f, hold, hold.x * BattleConfig.SUB + BattleConfig.SUB / 2,
			hold.y * BattleConfig.SUB + BattleConfig.SUB / 2, false)


## Jedna kratka postoju oddziału na Ostrzał: od strony wejścia, w zasięgu `cells` od budynku-celu.
## Ustalana raz na klucz oddziału; potem wszyscy stoją i strzelają stąd.
func _fire_hold_cell(key: int, t: Structure, cells: int) -> Vector2i:
	if _sq_fire.has(key):
		return _sq_fire[key]
	var reach := maxi(BattleConfig.RANGED_MIN_RANGE, cells)
	var hold := Vector2i.ZERO
	var found := false
	# Od pełnego zasięgu w dół: wolna kratka, z której cel jest w zasięgu euklidesowym.
	for dist in range(reach, 0, -1):
		var raw := fire_hold_point(_spawn, t.rect, dist, _terrain.size)
		var cand := _walkable_near(raw)
		if _cell_rect_in_range(cand, t.rect, reach):
			hold = cand
			found = true
			break
	if not found:
		hold = _walkable_near(fire_hold_point(_spawn, t.rect, reach, _terrain.size))
	_sq_fire[key] = hold
	return hold


## Punkt ostrzału między wejściem `spawn` a prostokątem celu `rect`: o `cells` kratek od krawędzi
## budynku w stronę wejścia (wspólny dla bitwy i testów).
static func fire_hold_point(spawn: Vector2i, rect: Rect2i, cells: int, size: int) -> Vector2i:
	var edge := Vector2i(
			clampi(spawn.x, rect.position.x, rect.end.x - 1),
			clampi(spawn.y, rect.position.y, rect.end.y - 1))
	var d := spawn - edge
	var m := maxi(1, maxi(absi(d.x), absi(d.y)))
	var reach := maxi(1, cells)
	@warning_ignore("integer_division")
	var p := edge + Vector2i(d.x * reach / m, d.y * reach / m)
	var last := size - 1
	return Vector2i(clampi(p.x, 0, last), clampi(p.y, 0, last))


## Czy środek kratki `c` sięga prostokąta `r` w zasięgu `cells` (jak _rect_in_range dla jednostki).
func _cell_rect_in_range(c: Vector2i, r: Rect2i, cells: int) -> bool:
	var fx := c.x * BattleConfig.SUB + BattleConfig.SUB / 2
	var fy := c.y * BattleConfig.SUB + BattleConfig.SUB / 2
	var nx := clampi(fx, r.position.x * BattleConfig.SUB, r.end.x * BattleConfig.SUB - 1)
	var ny := clampi(fy, r.position.y * BattleConfig.SUB, r.end.y * BattleConfig.SUB - 1)
	var reach := maxi(1, cells) * BattleConfig.SUB
	return _dist2(fx, fy, nx, ny) <= reach * reach


## Podpalenie: oddział bierze na cel drewniane budynki, które jeszcze nie płoną (wskazany, potem
## najbliższy), i bije je z zasięgu. Zadanie jest wykonane, gdy pierwszy cel płonie albo padł.
func _order_fire(f: Fighter, o: AttackPlan.Order, key: int) -> void:
	var t: Structure = null
	if o.target != AttackPlan.NO_TARGET:
		t = _structure_at(o.target)
	if t == null or t.burning > 0 or not BuildingTypes.is_wooden(t.kind):
		if o.target != AttackPlan.NO_TARGET:
			_sq_done[key] = true  # wskazany cel płonie albo padł
		t = _nearest_wood(f)
	if t == null:
		_sq_done[key] = true
		_default_act(f)
		return
	if _rect_in_range(f, t.rect, maxi(1, range_of(f))):
		_strike_structure(f, t)
		if t.burning > 0 or t.hp <= 0:
			_sq_done[key] = true
		return
	if not _hold(f):
		_walk_to(f, t, true)


## Najbliższy żywy drewniany budynek, który jeszcze nie płonie (przy remisie pierwszy w kolejności).
func _nearest_wood(f: Fighter) -> Structure:
	var best: Structure = null
	var best_d := 0
	for id: int in structures:
		var s := structures[id]
		if s.hp <= 0 or s.burning > 0 or not BuildingTypes.is_wooden(s.kind):
			continue
		var c := _rect_center_sub(s.rect)
		var d := _dist2(f.x, f.y, c.x, c.y)
		if best == null or d < best_d:
			best = s
			best_d = d
	return best


## Szturm z drabinami: oddział podchodzi pod wskazany odcinek muru (bez wskazania pod najbliższy),
## po LADDER_CLIMB_S sekundach schodzi po drugiej stronie i walczy dalej jak bez rozkazu. Brama
## i wyłom nie są potrzebne. Gdy po drugiej stronie nie ma miejsca, oddział rąbie mur.
func _order_ladders(f: Fighter, o: AttackPlan.Order, key: int) -> void:
	if f.climbed:
		_default_act(f)
		return
	var wall := _goal(o, key, _nearest_wall(f))
	if wall == null:
		f.climbed = true
		_default_act(f)
		return
	if _hold(f):
		return
	if _touches(f.cell(), wall.rect):
		f.climb += 1
		if f.climb < BattleConfig.LADDER_CLIMB_S * BattleConfig.TICK_HZ:
			return
		var land := _landing(f, wall)
		if land.x < 0:
			_strike_structure(f, wall)
			return
		f.x = land.x * BattleConfig.SUB + BattleConfig.SUB / 2
		f.y = land.y * BattleConfig.SUB + BattleConfig.SUB / 2
		f.climbed = true
		f.path.clear()
		_sq_done[key] = true
		return
	var approach := _approach(f, wall)
	_walk(f, approach, approach.x * BattleConfig.SUB + BattleConfig.SUB / 2,
			approach.y * BattleConfig.SUB + BattleConfig.SUB / 2, false)


func _nearest_wall(f: Fighter) -> Structure:
	var best: Structure = null
	var best_d := 0
	for id: int in structures:
		var s := structures[id]
		if s.hp <= 0 or not BuildingTypes.is_wall(s.kind):
			continue
		var c := _rect_center_sub(s.rect)
		var d := _dist2(f.x, f.y, c.x, c.y)
		if best == null or d < best_d:
			best = s
			best_d = d
	return best


## Czy kratka `c` styka się z prostokątem `r` (także po skosie), ale w nim nie leży.
static func _touches(c: Vector2i, r: Rect2i) -> bool:
	return r.grow(1).has_point(c) and not r.has_point(c)


## Wolna kratka przy murze od strony jednostki (najbliższa jej), z której przystawia drabinę.
func _approach(f: Fighter, wall: Structure) -> Vector2i:
	var best := wall.rect.position
	var best_d := -1
	var here := f.cell()
	for c in _ring(wall.rect):
		if not _free_ground(c):
			continue
		var d := (c - here).length_squared()
		if best_d < 0 or d < best_d:
			best = c
			best_d = d
	return best


## Kratka zejścia za murem: wolna, przy murze, po przeciwnej stronie niż jednostka (najdalej od
## niej), albo (-1, -1), gdy takiej nie ma. Kratki, na których stoi już inna żywa jednostka, idą
## na koniec, żeby oddział nie lądował jeden na drugim (review PR 175); gdy wszystkie są zajęte,
## jednostka schodzi na najlepszą z nich.
func _landing(f: Fighter, wall: Structure) -> Vector2i:
	var here := f.cell()
	var wall_d := (wall.rect.get_center() - here).length_squared()
	var best := Vector2i(-1, -1)
	var best_d := -1
	var best_free := false
	for c in _ring(wall.rect):
		if not _free_ground(c):
			continue
		var d := (c - here).length_squared()
		if d <= wall_d:
			continue
		var free := not _occupied(c, f)
		if best_d < 0 or (free and not best_free) or (free == best_free and d > best_d):
			best = c
			best_d = d
			best_free = free
	return best


## Czy na kratce `c` stoi żywa jednostka inna niż `who`.
func _occupied(c: Vector2i, who: Fighter) -> bool:
	for g in fighters:
		if g != who and g.alive() and g.cell() == c:
			return true
	return false


## Kratki dookoła prostokąta, w stałej kolejności (wiersze od góry).
static func _ring(r: Rect2i) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	var g := r.grow(1)
	for y in range(g.position.y, g.end.y):
		for x in range(g.position.x, g.end.x):
			var c := Vector2i(x, y)
			if not r.has_point(c):
				out.append(c)
	return out


## Taranowanie bramy: Taran oddziału jedzie na wskazaną bramę (bez wskazania na najbliższą),
## a reszta oddziału go osłania: walczy z wrogami przy taranie, inaczej idzie przy nim. Bez taranu
## piechota sama szturmuje bramę. Zadanie jest wykonane, gdy brama padnie.
func _order_ram(f: Fighter, o: AttackPlan.Order, key: int) -> void:
	var gate := _goal(o, key, _nearest_gate(f))
	if gate == null:
		_default_act(f)
		return
	if f.unit == UnitTypes.Unit.RAM:
		_ram_act(f, gate)
		return
	var ram := _nearest_ram(f)
	if ram == null:
		_order_assault(f, o, key)
		return
	var enemy := _enemy_for(f)
	var reach := BattleConfig.ESCORT_RADIUS * BattleConfig.SUB
	if enemy != null and _dist2(enemy.x, enemy.y, ram.x, ram.y) <= reach * reach:
		f.target = enemy.id
		if _in_range(f, enemy.x, enemy.y, range_of(f)):
			_strike_unit(f, enemy)
		else:
			_walk(f, enemy.cell(), enemy.x, enemy.y, true)
		return
	f.target = 0
	if _dist2(f.x, f.y, ram.x, ram.y) > BattleConfig.SUB * BattleConfig.SUB:
		_walk(f, ram.cell(), ram.x, ram.y, false)


func _nearest_ram(f: Fighter) -> Fighter:
	var best: Fighter = null
	var best_d := 0
	for g in fighters:
		if g.side != f.side or not g.alive() or g.unit != UnitTypes.Unit.RAM:
			continue
		var d := _dist2(f.x, f.y, g.x, g.y)
		if best == null or d < best_d:
			best = g
			best_d = d
	return best


## Idzie do budynku `t`; z `breach` burzy go (i to, co stoi na drodze), gdy dojdzie.
func _walk_to(f: Fighter, t: Structure, breach: bool) -> void:
	var c := t.rect.position
	_walk(f, c, c.x * BattleConfig.SUB + BattleConfig.SUB / 2, c.y * BattleConfig.SUB + BattleConfig.SUB / 2, breach)


## Środek prostokąta kratek w podjednostkach.
static func _rect_center_sub(r: Rect2i) -> Vector2i:
	@warning_ignore("integer_division")
	return Vector2i((r.position.x * 2 + r.size.x) * BattleConfig.SUB / 2, (r.position.y * 2 + r.size.y) * BattleConfig.SUB / 2)


## Czy najbliższy punkt prostokąta kratek `r` jest w zasięgu `cells` kratek od jednostki.
func _rect_in_range(f: Fighter, r: Rect2i, cells: int) -> bool:
	var nx := clampi(f.x, r.position.x * BattleConfig.SUB, r.end.x * BattleConfig.SUB - 1)
	var ny := clampi(f.y, r.position.y * BattleConfig.SUB, r.end.y * BattleConfig.SUB - 1)
	var reach := maxi(1, cells) * BattleConfig.SUB
	return _dist2(f.x, f.y, nx, ny) <= reach * reach


## Odwrót z planu (#18): oddział, który stracił swój próg procentowy ludzi, wycofuje się jak przy
## złamanym morale.
func _count_loss(f: Fighter) -> void:
	var key := _squad_key(f.side, f.squad)
	_sq_dead[key] = int(_sq_dead.get(key, 0)) + 1
	var o := _order(f)
	if o == null or o.retreat_percent <= 0:
		return
	if _sq_dead[key] * 100 >= o.retreat_percent * int(squad_size.get(key, 1)):
		_sq_retreat[key] = true


# --- Zadania obrony (#20) ----------------------------------------------------------------------------

func _defend(f: Fighter, o: DefensePlan.Order) -> void:
	if f.wall != 0:
		_wall_act(f)
	elif o.task == DefensePlan.Task.PATROL:
		_patrol_act(f)
	elif o.task == DefensePlan.Task.SORTIE:
		_sortie_act(f)
	elif o.task == DefensePlan.Task.FIELD:
		_field_act(f)
	elif o.task == DefensePlan.Task.FIREFIGHT:
		_firefight_act(f)
	else:
		_hold_section(f)


## Stanowisko na murze: strzela do wroga w zasięgu (+WALL_RANGE_BONUS, z wieży i donżonu
## +TOWER_STATION_RANGE_BONUS, #232) i nie schodzi. Gdy odcinek padnie, jednostka zostaje na gruzie
## i broni się dalej jak Obrona odcinka z tego miejsca.
func _wall_act(f: Fighter) -> void:
	var s: Structure = structures.get(f.wall, null)
	if s == null or s.hp <= 0:
		f.wall = 0
		f.post = f.cell()
		f.path.clear()
		_hold_section(f)
		return
	var enemy := _enemy_for(f)
	if enemy != null and _in_range(f, enemy.x, enemy.y, range_of(f) + station_range_bonus(s.kind)):
		f.target = enemy.id
		_strike_unit(f, enemy)
		return
	f.target = 0


## Czy `f` stoi na donżonie jako jego załoga (#232).
func _on_keep(f: Fighter) -> bool:
	var s: Structure = structures.get(f.wall, null)
	return s != null and s.kind == BuildingTypes.Kind.KEEP


## Dodatkowy zasięg strzelca na stanowisku z budynku `kind`: z wieży i donżonu dalej niż z muru (#232).
## Kopiec (#35, decyzja właścicielki) daje tyle co mur: +1.
static func station_range_bonus(kind: int) -> int:
	if kind == BuildingTypes.Kind.TOWER or kind == BuildingTypes.Kind.KEEP:
		return BattleConfig.TOWER_STATION_RANGE_BONUS
	return BattleConfig.WALL_RANGE_BONUS


## Zejście z muru (np. przy wycofaniu): na wolną kratkę przy murze najbliżej kratki wycofania.
func _step_down(f: Fighter) -> void:
	var s: Structure = structures.get(f.wall, null)
	f.wall = 0
	if s == null or s.hp <= 0:
		return
	var best := Vector2i(-1, -1)
	var best_d := -1
	for c in _ring(s.rect):
		if not _free_ground(c):
			continue
		var d := (c - f.rally).length_squared()
		if best_d < 0 or d < best_d:
			best = c
			best_d = d
	if best.x >= 0:
		f.x = best.x * BattleConfig.SUB + BattleConfig.SUB / 2
		f.y = best.y * BattleConfig.SUB + BattleConfig.SUB / 2
	f.path.clear()


## Brama najbliżej kratki `c` (żywa, przy remisie niższe id) albo 0.
func _gate_near(c: Vector2i) -> int:
	var best := 0
	var best_d := -1
	for id: int in structures:
		var s := structures[id]
		if s.kind != BuildingTypes.Kind.GATE or s.hp <= 0:
			continue
		var d := (s.rect.get_center() - c).length_squared()
		if best_d < 0 or d < best_d or (d == best_d and id < best):
			best = id
			best_d = d
	return best


## Wypad konnicy: czeka za bramą (bije tylko w zasięgu). Gdy atakujący podejdzie pod bramę albo brama
## padnie, oddział wychodzi przez nią (własna brama jest dla niego przejściem), bije wrogów najwyżej
## SORTIE_REACH kratek od bramy, a bez nich wraca na swoje miejsce.
func _sortie_act(f: Fighter) -> void:
	var key := _squad_key(f.side, f.squad)
	var gate: Structure = structures.get(int(_sortie_gate.get(f.squad, 0)), null)
	if not _sortie_out.has(key) and _sortie_triggered(gate):
		_sortie_out[key] = true
	if not _sortie_out.has(key):
		_hold(f)
		return
	var base := gate.rect if gate != null else Rect2i(f.post, Vector2i.ONE)
	var area := base.grow(BattleConfig.SORTIE_REACH)
	var enemy: Fighter = null
	var best_d := 0
	for o in fighters:
		if o.side == f.side or not o.alive() or not area.has_point(o.cell()):
			continue
		var d := _dist2(f.x, f.y, o.x, o.y)
		if enemy == null or d < best_d:
			enemy = o
			best_d = d
	if enemy != null:
		f.target = enemy.id
		if _in_range(f, enemy.x, enemy.y, range_of(f)):
			_strike_unit(f, enemy)
		else:
			_walk(f, enemy.cell(), enemy.x, enemy.y, false, _ram_astar)
		return
	f.target = 0
	_walk(f, f.post, f.post.x * BattleConfig.SUB + BattleConfig.SUB / 2, f.post.y * BattleConfig.SUB + BattleConfig.SUB / 2,
			false, _ram_astar)


## Konnica przed murami: stoi na swoim miejscu (także poza murami), bije wrogów najwyżej FIELD_RADIUS
## kratek od niego, a bez nich wraca. Jeździ drogami taranu, więc własne bramy są dla niej przejściem,
## a mury nie.
func _field_act(f: Fighter) -> void:
	var area := Rect2i(f.post, Vector2i.ONE).grow(BattleConfig.FIELD_RADIUS)
	var enemy: Fighter = null
	var best_d := 0
	for o in fighters:
		if o.side == f.side or not o.alive() or not area.has_point(o.cell()):
			continue
		var d := _dist2(f.x, f.y, o.x, o.y)
		if enemy == null or d < best_d:
			enemy = o
			best_d = d
	if enemy != null:
		f.target = enemy.id
		if _in_range(f, enemy.x, enemy.y, range_of(f)):
			_strike_unit(f, enemy)
		else:
			_walk(f, enemy.cell(), enemy.x, enemy.y, false, _ram_astar)
		return
	f.target = 0
	_walk(f, f.post, f.post.x * BattleConfig.SUB + BattleConfig.SUB / 2, f.post.y * BattleConfig.SUB + BattleConfig.SUB / 2,
			false, _ram_astar)


## Czy wypad ma ruszyć: brama padła albo żywy, niewycofany atakujący jest SORTIE_TRIGGER kratek od niej.
func _sortie_triggered(gate: Structure) -> bool:
	if gate == null or gate.hp <= 0:
		return true
	var near := gate.rect.grow(BattleConfig.SORTIE_TRIGGER)
	for o in fighters:
		if o.side == Side.ATTACKER and o.alive() and not routed(o) and near.has_point(o.cell()):
			return true
	return false


## Obrona odcinka: bije wroga w zasięgu, ściga tylko tych, którzy podeszli na HOLD_RADIUS kratek
## do jej miejsca, a potem wraca na miejsce.
func _hold_section(f: Fighter) -> void:
	var enemy := _enemy_for(f)
	if enemy != null:
		var near := absi(enemy.cell().x - f.post.x) <= BattleConfig.HOLD_RADIUS \
				and absi(enemy.cell().y - f.post.y) <= BattleConfig.HOLD_RADIUS
		if _in_range(f, enemy.x, enemy.y, range_of(f)):
			f.target = enemy.id
			_strike_unit(f, enemy)
			return
		if near:
			f.target = enemy.id
			_walk(f, enemy.cell(), enemy.x, enemy.y, false)
			return
	f.target = 0
	_walk(f, f.post, f.post.x * BattleConfig.SUB + BattleConfig.SUB / 2, f.post.y * BattleConfig.SUB + BattleConfig.SUB / 2, false)


## Patrol: krąży po punktach trasy oddziału (od miejsca startu), a wroga w zasięgu wzroku bije
## i ściga jak bez zadania; potem wraca do punktu, do którego szedł. `wp` to numer tego punktu.
func _patrol_act(f: Fighter) -> void:
	var enemy := _enemy_for(f)
	if enemy != null:
		f.target = enemy.id
		if _in_range(f, enemy.x, enemy.y, range_of(f)):
			_strike_unit(f, enemy)
		else:
			_walk(f, enemy.cell(), enemy.x, enemy.y, false)
		return
	f.target = 0
	var points: Array = _patrol[f.squad]
	var p: Vector2i = points[f.wp % points.size()]
	if absi(f.cell().x - p.x) <= 1 and absi(f.cell().y - p.y) <= 1:
		f.wp = (f.wp + 1) % points.size()
		p = points[f.wp]
	_walk(f, p, p.x * BattleConfig.SUB + BattleConfig.SUB / 2, p.y * BattleConfig.SUB + BattleConfig.SUB / 2, false)


## Czy wieża woli tego atakującego według priorytetu celów (#20).
func _tower_prefers(f: Fighter) -> bool:
	match tower_priority:
		DefensePlan.TowerPriority.RAM:
			return f.unit == UnitTypes.Unit.RAM
		DefensePlan.TowerPriority.RANGED:
			return UnitTypes.unit_class(f.unit) == RecruitmentConfig.UnitClass.RANGED
		DefensePlan.TowerPriority.CAVALRY:
			return UnitTypes.unit_class(f.unit) == RecruitmentConfig.UnitClass.FAST
	return false


# --- Pułapki (#100) -----------------------------------------------------------------------------------

## Uzbraja pułapki z ustawień obrony przed bitwą (kopie: bitwa nie zmienia układu). Zrzucane kłody
## działają na 3 kratkach wzdłuż muru, przy którym stoją, a Wrząca smoła na kratkach wokół siebie.
func arm_traps(list: Array[DefensePlan.Trap]) -> void:
	traps.clear()
	for t in list:
		if not _terrain.in_bounds(t.cell):
			continue
		var st := TrapState.new()
		st.kind = t.kind
		st.cell = t.cell
		match t.kind:
			TrapConfig.Kind.LOGS:
				var along := Vector2i.RIGHT
				for d: Vector2i in [Vector2i.UP, Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT]:
					var s := _structure_at(t.cell + d)
					if s != null and BuildingTypes.is_wall(s.kind):
						along = Vector2i(absi(d.y), absi(d.x))
						break
				for k in range(-1, 2):
					st.area.append(t.cell + along * k)
			TrapConfig.Kind.PITCH:
				for dy in range(-1, 2):
					for dx in range(-1, 2):
						st.area.append(t.cell + Vector2i(dx, dy))
		traps.append(st)


## Pułapki w jednym kroku: wyzwalanie (atakujący na kratce albo w pobliżu) i działanie w czasie,
## a do tego płonące jednostki.
func _traps_act() -> void:
	for t in traps:
		match t.kind:
			TrapConfig.Kind.PIT:
				if not t.fired:
					var v := _attacker_on([t.cell])
					if v != null:
						t.fired = true
						var ram := v.unit == UnitTypes.Unit.RAM
						v.stun = (TrapConfig.PIT_RAM_STUN_S if ram else TrapConfig.PIT_STUN_S) * BattleConfig.TICK_HZ
						if not ram:
							_hurt(v, TrapConfig.PIT_DAMAGE)
						_trap_fx(t.cell)
			TrapConfig.Kind.CALTROPS:
				if not t.fired and _attacker_on([t.cell]) != null:
					t.fired = true
					t.until = tick + TrapConfig.CALTROPS_S * BattleConfig.TICK_HZ
					_trap_fx(t.cell)
				if t.fired and tick <= t.until and tick % BattleConfig.TICK_HZ == 0:
					var r := Rect2i(t.cell, Vector2i.ONE).grow(1)
					for f in fighters:
						if f.side == Side.ATTACKER and f.alive() and r.has_point(f.cell()):
							_hurt(f, TrapConfig.CALTROPS_DAMAGE_PER_S)
			TrapConfig.Kind.LOGS:
				if not t.fired and _attacker_on(t.area) != null:
					t.fired = true
					for f in fighters:
						if f.side == Side.ATTACKER and f.alive() and t.area.has(f.cell()):
							_hurt(f, TrapConfig.LOGS_DAMAGE)
					_trap_fx(t.cell)
			TrapConfig.Kind.FIRE_ARROWS:
				if not t.fired:
					var near := Rect2i(t.cell, Vector2i.ONE).grow(TrapConfig.FIRE_ARROWS_TRIGGER)
					for f in fighters:
						if f.side == Side.ATTACKER and f.alive() and near.has_point(f.cell()):
							t.fired = true
							t.until = tick + TrapConfig.FIRE_ARROWS_S * BattleConfig.TICK_HZ
							_trap_fx(t.cell)  # rozpalony kosz (review #186)
							break
			TrapConfig.Kind.PITCH:
				if not t.fired and _attacker_on(t.area) != null:
					t.fired = true
					for f in fighters:
						if f.side == Side.ATTACKER and f.alive() and t.area.has(f.cell()):
							_hurt(f, TrapConfig.PITCH_DAMAGE)
							_ignite(f)
					_trap_fx(t.cell)
	for f in fighters:
		if f.fire > 0 and f.alive():
			f.fire -= 1
			if f.fire % BattleConfig.TICK_HZ == 0:
				_hurt(f, TrapConfig.UNIT_FIRE_DAMAGE_PER_S)


## Pierwszy żywy atakujący (w kolejności jednostek) na którejś z kratek `cells` albo null.
func _attacker_on(cells: Array[Vector2i]) -> Fighter:
	for f in fighters:
		if f.side == Side.ATTACKER and f.alive() and cells.has(f.cell()):
			return f
	return null


## Czy działająca Kolczatka obejmuje kratkę `c` (kratka pułapki i sąsiednie).
func _in_caltrops(c: Vector2i) -> bool:
	for t in traps:
		if t.kind == TrapConfig.Kind.CALTROPS and t.fired and tick <= t.until \
				and absi(c.x - t.cell.x) <= 1 and absi(c.y - t.cell.y) <= 1:
			return true
	return false


## Czy strzelec na kratce `c` jest w zasięgu działającego kosza Płonących strzał.
func _fire_arrows_near(c: Vector2i) -> bool:
	for t in traps:
		if t.kind == TrapConfig.Kind.FIRE_ARROWS and t.fired and tick <= t.until \
				and absi(c.x - t.cell.x) <= TrapConfig.FIRE_ARROWS_RADIUS \
				and absi(c.y - t.cell.y) <= TrapConfig.FIRE_ARROWS_RADIUS:
			return true
	return false


## Podpala Taran albo Podpalacza (Płonące strzały) i każdego w Wrzącej smole: traci HP co sekundę.
func _ignite(f: Fighter) -> void:
	f.fire = maxi(f.fire, TrapConfig.UNIT_FIRE_S * BattleConfig.TICK_HZ)


## Płonąca strzała podpala tylko Taran (drewno) i Podpalacza (smoła, którą niesie).
func _ignite_arrow_target(f: Fighter) -> void:
	if f.unit == UnitTypes.Unit.RAM or f.unit == UnitTypes.Unit.FIRE_RAISER:
		_ignite(f)


func _trap_fx(c: Vector2i) -> void:
	var x := c.x * BattleConfig.SUB + BattleConfig.SUB / 2
	var y := c.y * BattleConfig.SUB + BattleConfig.SUB / 2
	_record(Fx.HIT, FX_TOWER, x, y, x, y)


# --- Wieże i koniec ----------------------------------------------------------------------------------

## Czy donżon `s` ma załogę strzelców (#232, decyzja właścicielki): wtedy strzela jak wieża drewniana
## (ten sam zasięg, obrażenia, priorytet celów i tempo ze strzał zbrojowni). Załoga to żywi, niewycofani
## strzelcy obrońcy (klasa RANGED) na stanowisku na donżonie (`Fighter.wall`), jak strzelcy na murze.
func keep_manned(s: Structure) -> bool:
	for f in fighters:
		if f.wall == s.id and f.alive() and not f.retreating:
			return true
	return false


func _tower_act(s: Structure) -> void:
	if s.cooldown > 0:
		s.cooldown -= 1
		return
	var cx := (s.rect.position.x * 2 + s.rect.size.x) * BattleConfig.SUB / 2
	var cy := (s.rect.position.y * 2 + s.rect.size.y) * BattleConfig.SUB / 2
	var r := tower_range(s) * BattleConfig.SUB
	# najbliższy w zasięgu, a z priorytetem (#20) najbliższy z wybranej grupy, jeśli jest
	var best: Fighter = null
	var best_d := 0
	var pref: Fighter = null
	var pref_d := 0
	for f in fighters:
		if f.side != Side.ATTACKER or not f.alive():
			continue
		var d := _dist2(cx, cy, f.x, f.y)
		if d > r * r:
			continue
		if best == null or d < best_d:
			best = f
			best_d = d
		if _tower_prefers(f) and (pref == null or d < pref_d):
			pref = f
			pref_d = d
	if pref != null:
		best = pref
	if best == null:
		return
	@warning_ignore("integer_division")
	s.cooldown = BattleConfig.ATTACK_COOLDOWN_TICKS * 100 / maxi(1, tower_fire_percent)
	var dmg := BattleConfig.TOWER_ATTACK
	if _fire_arrows_near(s.rect.get_center()):
		@warning_ignore("integer_division")
		dmg = dmg * TrapConfig.FIRE_ARROWS_PERCENT / 100
		_ignite_arrow_target(best)
	_hurt(best, _roll(dmg))
	_record(Fx.SHOT, FX_TOWER, cx, cy, best.x, best.y)


## Zasięg strzału wieży drewnianej albo obsadzonego donżonu w kratkach: TOWER_RANGE plus premia
## od żywego Kopca, który styka się z nią bokiem (#35). Z kilku Kopców liczy się najwyższa premia.
func tower_range(s: Structure) -> int:
	var bonus := 0
	for id: int in _mounds_by.get(s.id, []) as Array:
		var m: Structure = structures.get(id, null)
		if m != null and m.hp > 0:
			bonus = maxi(bonus, BattleConfig.mound_range_bonus(m.level))
	return BattleConfig.TOWER_RANGE + bonus


## Czy prostokąty kratek `a` i `b` stykają się bokiem (nie po skosie i bez nakładania).
static func touches_side(a: Rect2i, b: Rect2i) -> bool:
	if a.intersects(b):
		return false
	return a.grow_individual(1, 0, 1, 0).intersects(b) or a.grow_individual(0, 1, 0, 1).intersects(b)


## Spis Kopców przy wieżach i donżonie (#35), raz przy tworzeniu bitwy, w stałej kolejności budynków.
func _link_mounds() -> void:
	for id: int in structures:
		var s := structures[id]
		if s.kind != BuildingTypes.Kind.TOWER and s.kind != BuildingTypes.Kind.KEEP:
			continue
		var near: Array = []
		for mid: int in structures:
			var m := structures[mid]
			if m.kind == BuildingTypes.Kind.MOUND and touches_side(s.rect, m.rect):
				near.append(mid)
		if not near.is_empty():
			_mounds_by[id] = near


## Kolce w fosie (#35, O3 Fosa z kolcami): co sekundę każdy żywy atakujący na kratce fosy traci
## BattleConfig.moat_spike_damage(poziom fosy) punktów, w stałej kolejności jednostek.
func _moat_spikes() -> void:
	for f in fighters:
		if f.side != Side.ATTACKER or not f.alive():
			continue
		var c := f.cell()
		if moat.has(c):
			_hurt(f, BattleConfig.moat_spike_damage(moat[c]))


## Studnia najbliżej kratki `c` (żywa, przy remisie niższe id) albo 0.
func _well_near(c: Vector2i) -> int:
	var best := 0
	var best_d := -1
	for id: int in structures:
		var s := structures[id]
		if s.kind != BuildingTypes.Kind.WELL or s.hp <= 0:
			continue
		var d := (s.rect.get_center() - c).length_squared()
		if best_d < 0 or d < best_d or (d == best_d and id < best):
			best = id
			best_d = d
	return best


## Płonący żywy budynek najbliżej Studni `well` i najwyżej FIREFIGHT_RADIUS kratek od niej (środek do
## środka), przy remisie niższe id; null, gdy nic nie płonie albo Studnia padła.
func _fire_near(well: Structure) -> Structure:
	if well == null or well.hp <= 0:
		return null
	var wc := _rect_center_sub(well.rect)
	var reach := BattleConfig.FIREFIGHT_RADIUS * BattleConfig.SUB
	var best: Structure = null
	var best_d := 0
	for id: int in structures:
		var s := structures[id]
		if s.hp <= 0 or s.burning <= 0:
			continue
		var sc := _rect_center_sub(s.rect)
		var d := _dist2(wc.x, wc.y, sc.x, sc.y)
		if d > reach * reach:
			continue
		if best == null or d < best_d or (d == best_d and id < best.id):
			best = s
			best_d = d
	return best


## Gaszenie pożarów (#35, notatka Manewry i zadania): oddział czeka przy swojej Studni jak Obrona
## odcinka. Gdy w promieniu FIREFIGHT_RADIUS kratek od Studni płonie budynek, idzie do niego i każdy
## gaszący, który stoi tuż przy nim, co sekundę skraca ogień o FIREFIGHT_S sekund. Wtedy nie walczy.
## Bez żywej Studni (albo gdy padła) nie ma czym gasić i oddział tylko broni swojego miejsca.
func _firefight_act(f: Fighter) -> void:
	var well: Structure = structures.get(int(_fire_well.get(f.squad, 0)), null)
	var fire := _fire_near(well)
	if fire == null:
		_hold_section(f)
		return
	f.target = 0
	if _rect_in_range(f, fire.rect, 1):
		if f.cooldown == 0:
			f.cooldown = BattleConfig.ATTACK_COOLDOWN_TICKS
			fire.burning = maxi(0, fire.burning - BattleConfig.FIREFIGHT_S * BattleConfig.TICK_HZ)
		return
	_walk_to(f, fire, false)


func _check_end() -> void:
	_update_capture()
	if structures.has(objective) and structures[objective].hp <= 0:
		_finish(Winner.ATTACKER, EndReason.DESTROYED)
	elif capture_ticks >= BattleConfig.CAPTURE_S * BattleConfig.TICK_HZ:
		_finish(Winner.ATTACKER, EndReason.CAPTURED)
	elif alive_count(Side.ATTACKER) == 0:
		_finish(Winner.DEFENDER, EndReason.ATTACKERS_DEAD)
	elif fighting_count(Side.ATTACKER) == 0:
		_finish(Winner.DEFENDER, EndReason.ATTACKERS_ROUTED)
	elif tick >= BattleConfig.time_limit_ticks():
		_finish(Winner.DEFENDER, EndReason.TIME_LIMIT)


func _finish(side: int, reason: int) -> void:
	winner = side
	end_reason = reason


## Zdobywanie celu: piechota atakującego (klasa lekka albo ciężka) przy celu i żadnego obrońcy
## w tym samym pasie wokół niego. Przerwa w obsadzie zeruje licznik.
func _update_capture() -> void:
	if not structures.has(objective) or structures[objective].hp <= 0:
		return
	var zone := structures[objective].rect.grow(BattleConfig.CAPTURE_RANGE)
	var holders := 0
	for f in fighters:
		# wycofany atakujący nie zdobywa; wycofany obrońca broni celu tylko osaczony na swojej kratce (#16)
		if not f.alive() or not zone.has_point(f.cell()):
			continue
		if routed(f) and not (f.side == Side.DEFENDER and cornered(f)):
			continue
		if f.side == Side.DEFENDER:
			capture_ticks = 0
			return
		var unit_class := UnitTypes.unit_class(f.unit)
		if unit_class == RecruitmentConfig.UnitClass.LIGHT or unit_class == RecruitmentConfig.UnitClass.HEAVY:
			holders += 1
	capture_ticks = capture_ticks + 1 if holders > 0 else 0
