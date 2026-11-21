class_name ScoutIntel
extends RefCounted
## Co plan ataku widzi z zamku-celu (#28, mgła wojny bez animacji). Bez zwiadu widać tylko zarys
## budynków (jak miniatura na karcie celu): bez rodzajów, poziomów, załogi, patroli i pułapek.
## Raport zwiadu odsłania prostokąt `region` w obrębie zabudowy, który zajmuje tyle procent jej
## obszaru, ile daje raport (Scouting.Report.percent). W nim widać budynki, miejsca oddziałów
## załogi, trasy patroli i pułapki (pole „odsłonięta” z #100). Nawet pełny sukces odsłania tylko
## część zamku. Położenie obszaru wynika z seeda raportu, więc ten sam raport zawsze odsłania to samo.
##
## Bitwa i tak liczy się z pełną obroną; mgła dotyczy tylko tego, co gracz widzi przy planowaniu.

## Pusty obszar: bez zwiadu nic nie jest odsłonięte.
const NONE := Rect2i()

var region := NONE
## Odsłonięte oddziały załogi: [klasa jednostki, kratka].
var squads: Array = []
## Odsłonięte trasy patroli: punkty trasy w kolejności obchodu.
var patrols: Array = []
## Odsłonięte pułapki: [rodzaj, kratka].
var traps: Array = []
## Odsłonięte budynki z serwera (zwiad na gracza): [prostokąt, rodzaj, poziom]. Przy zamku-bocie
## puste, bo plan ma cały zamek w siatce.
var buildings: Array = []

## Najwięcej wpisów z serwera w każdej liście (zamek ma ich mniej).
const MAX_ENTRIES := 400


func is_empty() -> bool:
	return not region.has_area()


func covers(cell: Vector2i) -> bool:
	return region.has_area() and region.has_point(cell)


## Czy budynek o prostokącie `r` jest odsłonięty (choć jedną kratką w obszarze).
func shows(r: Rect2i) -> bool:
	return region.has_area() and region.intersects(r)


## Prostokąt zabudowy: wszystkie budynki siatki (pusty, gdy nie ma budynków).
static func castle_rect(grid: BuildGrid) -> Rect2i:
	var box := NONE
	for id: int in grid.buildings:
		var r := grid.buildings[id]
		box = r if not box.has_area() else box.merge(r)
	return box


## Obszar odsłonięty przez `percent` procent zabudowy `box`, w miejscu z `seed_value`. Proporcje jak
## zabudowa, boki zaokrąglone w górę do całych kratek, a obszar zawsze mieści się w zabudowie.
static func region_of(box: Rect2i, percent: int, seed_value: int) -> Rect2i:
	if not box.has_area() or percent <= 0:
		return NONE
	var p := clampi(percent, 1, 100)
	# skala boku = pierwiastek z ułamka obszaru, w promilach (liczby całkowite)
	var scale := isqrt(p * 10000)
	@warning_ignore("integer_division")
	var w := clampi((box.size.x * scale + 999) / 1000, 1, box.size.x)
	@warning_ignore("integer_division")
	var h := clampi((box.size.y * scale + 999) / 1000, 1, box.size.y)
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var x := box.position.x + rng.randi_range(0, box.size.x - w)
	var y := box.position.y + rng.randi_range(0, box.size.y - h)
	return Rect2i(x, y, w, h)


## Pierwiastek całkowity (w dół) z `n` ≥ 0.
static func isqrt(n: int) -> int:
	if n <= 0:
		return 0
	var r := int(sqrt(float(n)))
	while r * r > n:
		r -= 1
	while (r + 1) * (r + 1) <= n:
		r += 1
	return r


## Miejsca startowe oddziałów obrońcy w bitwie `b` (przed pierwszym krokiem): [klasa, kratka]
## pierwszej jednostki każdego oddziału, w kolejności oddziałów.
static func defender_posts(b: Battle) -> Array:
	var out: Array = []
	var seen: Dictionary[int, bool] = {}
	for f in b.fighters:
		if f.side != Battle.Side.DEFENDER or f.general >= 0 or seen.has(f.squad):
			continue
		seen[f.squad] = true
		@warning_ignore("integer_division")
		var cell := Vector2i(f.x / BattleConfig.SUB, f.y / BattleConfig.SUB)
		out.append([UnitTypes.unit_class(f.unit), cell])
	return out


## Intel z obszaru `area`: oddziały z `posts` (defender_posts), patrole i pułapki z `defense`
## (może być null, np. zamek-bot), tylko te w obszarze. Patrol jest odsłonięty, gdy choć jeden
## jego punkt leży w obszarze.
static func build(area: Rect2i, posts: Array, defense: DefensePlan) -> ScoutIntel:
	var intel := ScoutIntel.new()
	intel.region = area
	if not area.has_area():
		return intel
	for e: Array in posts:
		if intel.covers(e[1] as Vector2i):
			intel.squads.append(e)
	if defense != null:
		var ids: Array[int] = []
		ids.assign(defense.orders.keys())
		ids.sort()
		for id in ids:
			var o := defense.orders[id]
			if o.task != DefensePlan.Task.PATROL or o.route.is_empty():
				continue
			var points := o.patrol_points()
			for c in points:
				if intel.covers(c):
					intel.patrols.append(points)
					break
		for t in defense.traps:
			if intel.covers(t.cell):
				intel.traps.append([t.kind, t.cell])
	return intel


## Oznacza pułapki `defense` w obszarze jako odsłonięte (pole z #100); pozostałe zostają ukryte.
static func mark_traps(defense: DefensePlan, area: Rect2i) -> int:
	var n := 0
	for t in defense.traps:
		t.revealed = area.has_area() and area.has_point(t.cell)
		if t.revealed:
			n += 1
	return n


## Intel z odpowiedzi serwera (`intel` z `scout_reports` albo `start_attack`, #28): {region,
## buildings, squads, patrols, traps}. Dane pochodzą od innego gracza, więc są niezaufane: wszystko
## musi leżeć na mapie i w obszarze, rodzaje w zakresie, listy ograniczone; zły wpis odpada, a zły
## obszar daje pusty intel.
static func from_server(raw: Variant) -> ScoutIntel:
	var intel := ScoutIntel.new()
	if not raw is Dictionary:
		return intel
	var d := raw as Dictionary
	var map := Rect2i(0, 0, TerrainMap.SIZE, TerrainMap.SIZE)
	var r := _ints(d.get("region"), 4)
	if r.is_empty():
		return intel
	var area := Rect2i(r[0], r[1], r[2], r[3])
	if area.size.x < 1 or area.size.y < 1 or not map.encloses(area):
		return intel
	intel.region = area
	for e: Variant in _list(d.get("buildings")):
		var b := _ints(e, 6)
		if b.is_empty():
			continue
		var rect := Rect2i(b[0], b[1], b[2], b[3])
		if rect.size.x >= 1 and rect.size.y >= 1 and map.encloses(rect) and area.intersects(rect) \
				and b[4] >= 0 and b[4] < BuildingTypes.count():
			intel.buildings.append([rect, b[4], clampi(b[5], 0, BuildingTypes.MAX_LEVEL)])
	for e: Variant in _list(d.get("squads")):
		var q := _ints(e, 3)
		if not q.is_empty() and q[0] >= UnitTypes.ENGINEERING and q[0] < RecruitmentConfig.CLASS_NAMES.size() \
				and intel.covers(Vector2i(q[1], q[2])):
			intel.squads.append([q[0], Vector2i(q[1], q[2])])
	for e: Variant in _list(d.get("patrols")):
		var points: Array[Vector2i] = []
		var seen := false
		for p: Variant in _list(e):
			var c := _ints(p, 2)
			if c.is_empty() or not map.has_point(Vector2i(c[0], c[1])) or points.size() > DefensePlan.MAX_ROUTE:
				points.clear()
				break
			points.append(Vector2i(c[0], c[1]))
			seen = seen or intel.covers(points[-1])
		if points.size() >= 2 and seen:
			intel.patrols.append(points)
	for e: Variant in _list(d.get("traps")):
		var t := _ints(e, 3)
		if not t.is_empty() and t[0] >= 0 and t[0] < TrapConfig.count() and intel.covers(Vector2i(t[1], t[2])):
			intel.traps.append([t[0], Vector2i(t[1], t[2])])
	return intel


## Lista z serwera najwyżej MAX_ENTRIES wpisów (zła wartość: pusta).
static func _list(v: Variant) -> Array:
	return (v as Array).slice(0, MAX_ENTRIES) if v is Array else []


## Dokładnie `n` liczb całkowitych z tablicy JSON albo pusta lista.
static func _ints(v: Variant, n: int) -> Array[int]:
	var out: Array[int] = []
	if not v is Array or (v as Array).size() != n:
		return out
	for x: Variant in v as Array:
		if not (x is int or (x is float and float(x) == floorf(float(x)))):
			return [] as Array[int]
		out.append(int(x))
	return out
