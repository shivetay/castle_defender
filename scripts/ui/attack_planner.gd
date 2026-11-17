class_name AttackPlanner
extends Node2D
## Planowanie ataku (#17, notatka Interfejs): mapa zamku-celu (BotCastle) ze strefą rozstawienia
## przy krawędzi mapy i strzałkami planu. Na dole pasek oddziałów, w kolumnie przyciski
## (AttackPanel). Gracz wybiera oddział, przyciskami ustawia manewr, start i odwrót, a dotykiem mapy
## cel (budynek) i trasę (do 3 punktów na trawie). Plan zapisuje się w grze (SaveGame, wersja 6).
## Ten węzeł rysuje mapę w pikselach świata; logika edycji planu to funkcje statyczne.

## Strefa rozstawienia: tyle kratek wokół wejścia na mapę.
const ZONE_RADIUS := 2
## Start: kolejne wartości przycisku Start po „od razu” (sekundy), potem czekanie na inne oddziały.
const START_SECONDS: Array[int] = [10, 20, 30]
## Odwrót: kolejne wartości przycisku Odwrót (procent strat; 0 = nigdy).
const RETREAT_STEPS: Array[int] = [0, 30, 50, 70]
const HINT := "Dotknij budynku: cel, trawy: punkt trasy"

var bot: BotCastle
var plan: AttackPlan
## Oddziały w ataku [rodzaj, liczba], w kolejności planu (oddział 1 = pierwszy).
var squads: Array = []
var age := 0
## Badania gracza: manewry bez zbadanej technologii (#12) są pomijane przy przełączaniu.
var research: Research
## Wybrany oddział (od 1).
var selected := 1
var textures: BuildingTextures
## Strzałki planu; w trakcie bitwy schowane, żeby nie zasłaniały walki.
var show_plan := true
var _terrain_tex: ImageTexture


## Otwiera plan dla zamku `target` i oddziałów `army`. Rozkazy dla brakujących oddziałów to
## Szturm frontalny; rozkazy oddziałów spoza armii wypadają.
func open(target: BotCastle, attack_plan: AttackPlan, army: Array, current_age: int) -> void:
	if bot != target:
		_terrain_tex = ImageTexture.create_from_image(TerrainRenderer.render(target.grid.terrain))
	bot = target
	plan = attack_plan
	squads = army
	age = current_age
	show_plan = true
	fit_plan(plan, squads.size())
	selected = clampi(selected, 1, maxi(1, squads.size()))
	visible = true
	queue_redraw()


## Dopasowuje plan do liczby oddziałów: każdy ma rozkaz, nadmiarowe rozkazy znikają.
static func fit_plan(p: AttackPlan, count: int) -> void:
	var keep: Array[AttackPlan.Order] = []
	for o in p.orders:
		if o.squad >= 1 and o.squad <= count:
			keep.append(o)
	p.orders = keep
	for i in range(1, count + 1):
		if p.order_for(i) == null:
			p.add(i, AttackPlan.Manoeuvre.FRONTAL)


func order() -> AttackPlan.Order:
	return plan.order_for(selected) if plan != null else null


# --- Edycja planu (statyczne, testowane bez ekranu) ------------------------------------------------

## Następny manewr dostępny w epoce `age` i (z `research`) odblokowany badaniami, po ostatnim znów
## pierwszy (#12).
static func next_manoeuvre(m: int, current_age: int, research: Research = null) -> int:
	var n := AttackPlan.MANOEUVRE_NAMES.size()
	for step in range(1, n + 1):
		var cand := (m + step) % n
		if AttackPlan.MANOEUVRE_AGE[cand] <= current_age \
				and (research == null or AttackPlan.manoeuvre_unlocked(cand, research)):
			return cand
	return m


## Następny start: od razu → po 10, 20, 30 s → po zadaniu oddziału 1, 2, … (bez siebie) → od razu.
static func next_start(o: AttackPlan.Order, squad_count: int) -> void:
	var options: Array[Vector2i] = [Vector2i(AttackPlan.Start.NOW, 0)]
	for s in START_SECONDS:
		options.append(Vector2i(AttackPlan.Start.AFTER_SECONDS, s))
	for i in range(1, squad_count + 1):
		if i != o.squad:
			options.append(Vector2i(AttackPlan.Start.AFTER_SQUAD, i))
	var cur := options.find(Vector2i(o.start, o.start_value if o.start != AttackPlan.Start.NOW else 0))
	var nxt := options[(cur + 1) % options.size()]
	o.start = nxt.x
	o.start_value = nxt.y


static func next_retreat(percent: int) -> int:
	var i := RETREAT_STEPS.find(percent)
	return RETREAT_STEPS[(i + 1) % RETREAT_STEPS.size()]


## Dotknięcie kratki `cell` mapy celu: budynek staje się celem rozkazu, trawa dodaje punkt trasy
## (czwarty punkt zaczyna trasę od nowa). Zwraca komunikat dla paska.
static func tap(o: AttackPlan.Order, grid: BuildGrid, cell: Vector2i) -> String:
	if not grid.terrain.in_bounds(cell):
		return HINT
	var id := grid.building_at(cell)
	if id != 0:
		o.target = cell
		return "Cel: %s" % BuildingTypes.NAMES[grid.kinds[id]]
	if grid.terrain.get_tile(cell) == TerrainMap.Tile.WATER:
		return "Trasa nie prowadzi przez wodę"
	if o.waypoints.size() >= AttackPlan.MAX_WAYPOINTS:
		o.waypoints.clear()
	o.waypoints.append(cell)
	return "Trasa: punkt %d z %d" % [o.waypoints.size(), AttackPlan.MAX_WAYPOINTS]


static func clear(o: AttackPlan.Order) -> void:
	o.target = AttackPlan.NO_TARGET
	o.waypoints.clear()


static func start_text(o: AttackPlan.Order) -> String:
	match o.start:
		AttackPlan.Start.AFTER_SECONDS:
			return "po %d s" % o.start_value
		AttackPlan.Start.AFTER_SQUAD:
			return "po oddz. %d" % o.start_value
	return "od razu"


static func retreat_text(percent: int) -> String:
	return "nigdy" if percent <= 0 else "%d%% strat" % percent


## Opis rozkazu na pasku nad oddziałami: [manewr, start i odwrót].
static func describe(o: AttackPlan.Order) -> Array[String]:
	return [AttackPlan.MANOEUVRE_NAMES[o.manoeuvre], "Start: %s  Odwrót: %s" % [start_text(o), retreat_text(o.retreat_percent)]]


## Punkty strzałki rozkazu w kratkach: wejście, trasa (z punktem obejścia dla Oskrzydlenia
## bez trasy) i cel (wskazany budynek albo donżon).
static func arrow_cells(o: AttackPlan.Order, b: BotCastle) -> Array[Vector2i]:
	var out: Array[Vector2i] = [b.spawn]
	var goal := o.target
	if goal == AttackPlan.NO_TARGET and b.grid.buildings.has(b.objective):
		goal = b.grid.buildings[b.objective].get_center()
	if o.manoeuvre == AttackPlan.Manoeuvre.FLANK and o.waypoints.is_empty() and goal != AttackPlan.NO_TARGET:
		# ten sam punkt obejścia, który wyznaczy bitwa (Battle.set_plan)
		out.append(Battle.flank_point_between(b.spawn, goal, o.flank_left, b.grid.terrain.size))
	out.append_array(o.waypoints)
	if goal != AttackPlan.NO_TARGET:
		out.append(goal)
	return out


## Piksele odcinka od `a` do `b` (algorytm Bresenhama, całe piksele).
static func line_pixels(a: Vector2i, b: Vector2i) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	var d := Vector2i(absi(b.x - a.x), -absi(b.y - a.y))
	var s := Vector2i(1 if a.x < b.x else -1, 1 if a.y < b.y else -1)
	var err := d.x + d.y
	var p := a
	while true:
		out.append(p)
		if p == b:
			break
		var e2 := 2 * err
		if e2 >= d.y:
			err += d.y
			p.x += s.x
		if e2 <= d.x:
			err += d.x
			p.y += s.y
	return out


static func cell_center_px(c: Vector2i) -> Vector2i:
	@warning_ignore("integer_division")
	return c * TerrainMap.CELL + Vector2i.ONE * (TerrainMap.CELL / 2)


static func zone_rect(spawn: Vector2i, size: int) -> Rect2i:
	var r := Rect2i(spawn - Vector2i.ONE * ZONE_RADIUS, Vector2i.ONE * (2 * ZONE_RADIUS + 1))
	return r.intersection(Rect2i(0, 0, size, size))


# --- Rysowanie mapy -------------------------------------------------------------------------------

func _draw() -> void:
	if bot == null:
		return
	draw_texture(_terrain_tex, Vector2.ZERO)
	CastleView.draw_buildings(self, bot.grid, textures)
	var zone := zone_rect(bot.spawn, bot.grid.terrain.size)
	draw_rect(Rect2(zone.position * TerrainMap.CELL, zone.size * TerrainMap.CELL), Color(Palette.VALID, 0.25))
	CastleView.draw_frame(self, Rect2i(zone.position * TerrainMap.CELL, zone.size * TerrainMap.CELL), Palette.VALID)
	if plan == null or not show_plan:
		return
	# najpierw pozostałe oddziały, na wierzchu wybrany
	for o in plan.orders:
		if o.squad != selected:
			_draw_arrow(o, Color(Palette.THATCH[1], 0.8))
	var sel := order()
	if sel != null:
		_draw_arrow(sel, Palette.INK)
		if sel.target != AttackPlan.NO_TARGET:
			var id := bot.grid.building_at(sel.target)
			if id != 0:
				var r := bot.grid.buildings[id]
				CastleView.draw_frame(self, Rect2i(r.position * TerrainMap.CELL, r.size * TerrainMap.CELL), Palette.ACCENT)


func _draw_arrow(o: AttackPlan.Order, col: Color) -> void:
	var cells := arrow_cells(o, bot)
	for i in range(1, cells.size()):
		# kreska 2 px, żeby nie rwała się przy oddaleniu 0,5×
		for p in line_pixels(cell_center_px(cells[i - 1]), cell_center_px(cells[i])):
			draw_rect(Rect2(p.x, p.y, 2, 2), col)
	for w in o.waypoints:
		var c := cell_center_px(w)
		draw_rect(Rect2(c.x - 1, c.y - 1, 3, 3), col)
	var end := cell_center_px(cells[-1])
	draw_rect(Rect2(end.x - 2, end.y - 2, 5, 5), Color(Palette.SHADOW, 0.6))
	draw_rect(Rect2(end.x - 1, end.y - 1, 3, 3), col)
