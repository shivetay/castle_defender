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
	## Numer oddziału po swojej stronie (od 1, w kolejności armii).
	var squad := 0
	## Kopijnik już zaszarżował (szarża działa tylko w pierwszym uderzeniu).
	var charged := false

	func cell() -> Vector2i:
		@warning_ignore("integer_division")
		return Vector2i(x / BattleConfig.SUB, y / BattleConfig.SUB)

	func alive() -> bool:
		return hp > 0


class Structure:
	extends RefCounted
	var id := 0
	var kind := 0
	var rect := Rect2i()
	var hp := 0
	var max_hp := 0
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

var _terrain: TerrainMap
var _cells: PackedInt32Array
var _astar := AStarGrid2D.new()
## Drogi Tarana: tylko do bram, inne budynki są dla niego nieprzechodnie.
var _ram_astar := AStarGrid2D.new()
var _rng: BattleRng
var _next_id := 1


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
## (np. z Recruitment.battle_squads()), w kolejności ustawienia.
static func create_squads(grid: BuildGrid, objective_id: int, attackers: Array, defenders: Array, spawn: Vector2i,
		seed_value: int) -> Battle:
	var b := Battle.new()
	b._rng = BattleRng.new(seed_value)
	b._terrain = grid.terrain
	b._cells = grid.cells.duplicate()
	b.objective = objective_id
	for id: int in grid.buildings:
		if grid.levels[id] < 1:
			continue  # plac budowy nie broni się
		var s := Structure.new()
		s.id = id
		s.kind = grid.kinds[id]
		s.rect = grid.buildings[id]
		s.max_hp = BattleConfig.building_hp(s.kind, grid.levels[id])
		s.hp = s.max_hp
		b.structures[id] = s
	b._setup_astar()
	b._spawn_squads(attackers, Side.ATTACKER, spawn)
	var center := grid.buildings[objective_id].get_center() if grid.buildings.has(objective_id) else Vector2i(spawn)
	b._spawn_squads(defenders, Side.DEFENDER, Vector2i(center) + Vector2i(0, 2))
	return b


## Bitwa o donżon zamku z `grid` (#120): cel to Wieża grodowa.
static func for_castle(grid: BuildGrid, attackers: Dictionary, defenders: Dictionary, spawn: Vector2i,
		seed_value: int) -> Battle:
	return create(grid, grid.keep_id(), attackers, defenders, spawn, seed_value)


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
	for id: int in structures:
		var s := structures[id]
		if s.hp > 0 and s.kind == BuildingTypes.Kind.TOWER:
			_tower_act(s)
		if s.hp > 0 and s.burning > 0:
			_burn(s)
	_check_end()


## Jednostki strony, które jeszcze walczą: żywe i niewycofane.
func fighting_count(side: int) -> int:
	var n := 0
	for f in fighters:
		if f.side == side and f.alive() and not routed(f):
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


## Oddział poniżej MORALE_ROUT wycofuje się sam i już nie walczy.
func routed(f: Fighter) -> bool:
	return squad_morale(f.side, f.squad) < BattleConfig.MORALE_ROUT


## Obrażenia dla jednostki; śmierć zabiera morale jej oddziałowi (loss_morale).
func _hurt(f: Fighter, dmg: int) -> void:
	if not f.alive():
		return
	f.hp -= dmg
	if not f.alive():
		add_squad_morale(f.side, f.squad, -loss_morale(f.side, f.squad))


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
		v["x"] = int(v["x"]) / n
		@warning_ignore("integer_division")
		v["y"] = int(v["y"]) / n
		out.append(v)
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
	for id: int in structures:
		h = _mix(h, id)
		h = _mix(h, structures[id].hp)
		h = _mix(h, structures[id].burning)
	for key: int in morale:
		h = _mix(h, key)
		h = _mix(h, int(morale[key]))
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


func _spawn_squads(squads: Array, side: int, at: Vector2i) -> void:
	var units: Array[int] = []
	var squad_of: Array[int] = []
	for i in squads.size():
		var sq: Array = squads[i]
		for n in int(sq[1]):
			units.append(int(sq[0]))
			squad_of.append(i + 1)
	var placed := 0
	for k in units.size():
		var unit := units[k]
		var f := Fighter.new()
		f.squad = squad_of[k]
		f.id = _next_id
		_next_id += 1
		f.unit = unit
		f.side = side
		f.hp = UnitTypes.hp(unit)
		var cell := _free_cell_near(at, placed)
		placed += 1
		f.x = cell.x * BattleConfig.SUB + BattleConfig.SUB / 2
		f.y = cell.y * BattleConfig.SUB + BattleConfig.SUB / 2
		f.post = cell
		f.cooldown = _rng.range_int(0, BattleConfig.ATTACK_COOLDOWN_TICKS - 1)
		fighters.append(f)
		var key := _squad_key(side, f.squad)
		morale[key] = BattleConfig.MORALE_START
		squad_size[key] = int(squad_size.get(key, 0)) + 1


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
	if routed(f):
		# wycofanie (#98): bez walki do swojej kratki startowej, nie burzy niczego po drodze
		f.target = 0
		_walk(f, f.post, f.post.x * BattleConfig.SUB + BattleConfig.SUB / 2, f.post.y * BattleConfig.SUB + BattleConfig.SUB / 2, false)
		return
	if f.unit == UnitTypes.Unit.RAM:
		_ram_act(f)
		return
	var enemy := _enemy_for(f)
	if enemy != null:
		f.target = enemy.id
		if _in_range(f, enemy.x, enemy.y, UnitTypes.attack_range(f.unit)):
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
	var sight := (UnitTypes.attack_range(f.unit) + BattleConfig.AGGRO_EXTRA) * BattleConfig.SUB
	var rider := f.unit == UnitTypes.Unit.RIDER
	for o in fighters:
		if o.side == f.side or not o.alive():
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
func _walk(f: Fighter, goal: Vector2i, px: int, py: int, breach: bool) -> void:
	f.repath_in -= 1
	var moved_goal := absi(goal.x - f.path_goal.x) > 1 or absi(goal.y - f.path_goal.y) > 1
	if f.path.is_empty() or f.path_index >= f.path.size() or f.repath_in <= 0 or moved_goal:
		f.path = _astar.get_id_path(f.cell(), goal)
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
	if blocker != null:
		# budynek na drodze: z sąsiedniej kratki burzy go atakujący z atakiem
		if breach and UnitTypes.attack(f.unit) > 0 \
				and _in_range(f, tx, ty, maxi(1, UnitTypes.attack_range(f.unit))):
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
	var dx := tx - f.x
	var dy := ty - f.y
	if absi(dx) >= absi(dy):
		f.x += clampi(dx, -step_len, step_len)
	else:
		f.y += clampi(dy, -step_len, step_len)


func _in_range(f: Fighter, tx: int, ty: int, cells: int) -> bool:
	var r := maxi(1, cells) * BattleConfig.SUB
	return _dist2(f.x, f.y, tx, ty) <= r * r


static func _dist2(ax: int, ay: int, bx: int, by: int) -> int:
	return (ax - bx) * (ax - bx) + (ay - by) * (ay - by)


func _strike_unit(f: Fighter, enemy: Fighter) -> void:
	if f.cooldown > 0:
		return
	f.cooldown = BattleConfig.ATTACK_COOLDOWN_TICKS
	_hurt(enemy, _roll(unit_damage(f, enemy)))
	f.charged = true


## Obrażenia uderzenia `f` w `enemy` przed rozrzutem: przewagi klas (#87) i cechy jednostek (#15, #92).
func unit_damage(f: Fighter, enemy: Fighter) -> int:
	var dmg := UnitTypes.damage(f.unit, enemy.unit)
	var ranged := UnitTypes.attack_range(f.unit) >= BattleConfig.RANGED_MIN_RANGE
	if f.unit == UnitTypes.Unit.LANCER and not f.charged:
		dmg = dmg * BattleConfig.CHARGE_PERCENT / 100
	if ranged and _behind_shields(enemy):
		dmg = dmg * BattleConfig.SHIELD_WALL_PERCENT / 100
	if not ranged and enemy.unit == UnitTypes.Unit.GAMBESON_WARRIOR:
		dmg = dmg * BattleConfig.GAMBESON_MELEE_PERCENT / 100
	return morale_damage(f, dmg)


## Wysokie morale (powyżej MORALE_HIGH): +10% obrażeń (#98).
func morale_damage(f: Fighter, dmg: int) -> int:
	if squad_morale(f.side, f.squad) > BattleConfig.MORALE_HIGH:
		@warning_ignore("integer_division")
		return dmg * BattleConfig.MORALE_HIGH_DAMAGE_PERCENT / 100
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
	s.hp -= _roll(morale_damage(f, structure_damage(f.unit, s.kind)))
	f.charged = true  # szarża to pierwsze uderzenie w ogóle, także w umocnienie
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
func _burn(s: Structure) -> void:
	s.burning -= 1
	if s.burning % BattleConfig.TICK_HZ == 0:
		s.hp -= BattleConfig.FIRE_DAMAGE_PER_S
		if s.hp <= 0:
			_destroy(s)


## Taran (#15): nie walczy z jednostkami, jedzie do najbliższej żywej bramy i tylko ją bije.
## Inne budynki są dla niego nieprzechodnie; bez bram stoi.
func _ram_act(f: Fighter) -> void:
	var gate := _nearest_gate(f)
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
	for y in range(s.rect.position.y, s.rect.end.y):
		for x in range(s.rect.position.x, s.rect.end.x):
			_cells[y * _terrain.size + x] = 0
			_astar.set_point_weight_scale(Vector2i(x, y), BattleConfig.FREE_PATH_WEIGHT)
			_ram_astar.set_point_solid(Vector2i(x, y), false)
	for f in fighters:
		f.repath_in = 0  # wyłom zmienia najkrótszą drogę


# --- Wieże i koniec ----------------------------------------------------------------------------------

func _tower_act(s: Structure) -> void:
	if s.cooldown > 0:
		s.cooldown -= 1
		return
	var cx := (s.rect.position.x * 2 + s.rect.size.x) * BattleConfig.SUB / 2
	var cy := (s.rect.position.y * 2 + s.rect.size.y) * BattleConfig.SUB / 2
	var r := BattleConfig.TOWER_RANGE * BattleConfig.SUB
	var best: Fighter = null
	var best_d := 0
	for f in fighters:
		if f.side != Side.ATTACKER or not f.alive():
			continue
		var d := _dist2(cx, cy, f.x, f.y)
		if d <= r * r and (best == null or d < best_d):
			best = f
			best_d = d
	if best == null:
		return
	@warning_ignore("integer_division")
	s.cooldown = BattleConfig.ATTACK_COOLDOWN_TICKS * 100 / maxi(1, tower_fire_percent)
	_hurt(best, _roll(BattleConfig.TOWER_ATTACK))


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
		# wycofany oddział ani nie zdobywa, ani nie broni celu
		if not f.alive() or routed(f) or not zone.has_point(f.cell()):
			continue
		if f.side == Side.DEFENDER:
			capture_ticks = 0
			return
		var unit_class := UnitTypes.unit_class(f.unit)
		if unit_class == RecruitmentConfig.UnitClass.LIGHT or unit_class == RecruitmentConfig.UnitClass.HEAVY:
			holders += 1
	capture_ticks = capture_ticks + 1 if holders > 0 else 0
