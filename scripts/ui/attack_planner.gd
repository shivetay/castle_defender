class_name AttackPlanner
extends Node2D
## Planowanie ataku (#17, notatka Interfejs): mapa zamku-celu (BotCastle) ze strefą rozstawienia
## przy krawędzi mapy i strzałkami planu. Na dole pasek oddziałów, w kolumnie przyciski
## (AttackPanel). Gracz wybiera oddział, przyciskami ustawia manewr, start i odwrót, a dotykiem mapy
## cel (budynek) i trasę (do 3 punktów na trawie); koniec strzałki (domyślnie donżon) przeciąga
## na inny budynek. Plan zapisuje się w grze (SaveGame, wersja 6).
## Mgła wojny (#28): przy planowaniu widać tylko zarys budynków; odsłonięty przez zwiad fragment
## zamku (ScoutIntel) pokazuje budynki, oddziały załogi, patrole i pułapki. W bitwie mgła znika.
## Ten węzeł rysuje mapę w pikselach świata; logika edycji planu to funkcje statyczne.

## Strefa rozstawienia: tyle kratek wokół wejścia na mapę.
const ZONE_RADIUS := 2
## Start: kolejne wartości przycisku Start po „od razu” (sekundy), potem czekanie na inne oddziały.
const START_SECONDS: Array[int] = [10, 20, 30]
## Odwrót: kolejne wartości przycisku Odwrót (procent strat; 0 = nigdy).
const RETREAT_STEPS: Array[int] = [0, 30, 50, 70]
const HINT := "Dotknij budynku: cel, trawy: punkt trasy"
## Cel w budynku spoza odsłoniętego fragmentu: bez rodzaju (#28).
const HIDDEN_TARGET := "Cel: nieznany budynek"
const WAGON_HINT := "Wóz: dotknij trawy, ostatni punkt to postój"
## Połowa celu dotyku końca strzałki (min. 12×12 px logicznych).
const END_HIT := 6

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
## Stan zniszczeń budynków celu w trwającej bitwie (BattleView.states_of); poza bitwą pusty.
var states: Dictionary = {}
## Podgląd przeciąganego końca strzałki (kratka); NO_TARGET = bez przeciągania.
var drag_end_cell := AttackPlan.NO_TARGET
## Co odsłonił zwiad (#28); pusty obszar = sam zarys budynków.
var intel := ScoutIntel.new()


## Otwiera plan dla zamku `target` i oddziałów `army`. Rozkazy dla brakujących oddziałów to
## Szturm frontalny; rozkazy oddziałów spoza armii wypadają.
func open(target: BotCastle, attack_plan: AttackPlan, army: Array, current_age: int,
		scout: ScoutIntel = null) -> void:
	intel = scout if scout != null else ScoutIntel.new()
	if bot != target:
		_terrain_tex = ImageTexture.create_from_image(TerrainRenderer.render(target.grid.terrain))
	bot = target
	states = {}
	plan = attack_plan
	squads = army
	age = current_age
	show_plan = true
	fit_plan(plan, squads.size(), unit_list(squads))
	selected = clampi(selected, 1, maxi(1, squads.size()))
	visible = true
	queue_redraw()


## Rodzaj jednostek każdego oddziału armii [rodzaj, liczba].
static func unit_list(army: Array) -> Array[int]:
	var out: Array[int] = []
	for sq: Array in army:
		out.append(int(sq[0]))
	return out


## Dopasowuje plan do liczby oddziałów: każdy ma rozkaz, nadmiarowe rozkazy znikają. Z `units`
## rozkaz, którego jednostka oddziału nie umie wykonać (np. inny skład armii), wraca do domyślnego
## manewru jednostki (Szturm, a dla Wozu Tabor, #235).
static func fit_plan(p: AttackPlan, count: int, units: Array[int] = []) -> void:
	var keep: Array[AttackPlan.Order] = []
	for o in p.orders:
		if o.squad >= 1 and o.squad <= count:
			if o.squad <= units.size() and not AttackPlan.unit_can(o.manoeuvre, units[o.squad - 1]):
				o.manoeuvre = AttackPlan.default_manoeuvre(units[o.squad - 1])
			keep.append(o)
	p.orders = keep
	for i in range(1, count + 1):
		if p.order_for(i) == null:
			p.add(i, AttackPlan.default_manoeuvre(units[i - 1] if i <= units.size() else -1))


func order() -> AttackPlan.Order:
	return plan.order_for(selected) if plan != null else null


# --- Edycja planu (statyczne, testowane bez ekranu) ------------------------------------------------

## Następny manewr dostępny w epoce `age`, (z `research`) odblokowany badaniami i (z `unit` ≥ 0)
## wykonalny dla jednostek oddziału, po ostatnim znów pierwszy (#12).
static func next_manoeuvre(m: int, current_age: int, research: Research = null, unit: int = -1) -> int:
	var n := AttackPlan.MANOEUVRE_NAMES.size()
	for step in range(1, n + 1):
		var cand := (m + step) % n
		if AttackPlan.missing(cand, unit, current_age, research).is_empty():
			return cand
	return m


## Jednostka oddziału `squad` (od 1) albo -1.
func unit_of(squad: int) -> int:
	return int((squads[squad - 1] as Array)[0]) if squad >= 1 and squad <= squads.size() else -1


## Następny start: od razu → po 10, 20, 30 s → po zadaniu oddziału 1, 2, … (bez siebie) → od razu.
static func next_start(o: AttackPlan.Order, squad_count: int) -> void:
	var options: Array[Vector2i] = [Vector2i(AttackPlan.Start.NOW, 0)]
	for s in START_SECONDS:
		# Wóz i tak czeka WAGON_DELAY_S sekund: krótsze czasy nic by nie zmieniły (#235)
		if o.manoeuvre != AttackPlan.Manoeuvre.CONVOY or s > AttackPlan.WAGON_DELAY_S:
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
## (czwarty punkt zaczyna trasę od nowa). Tabor (#235) nie ma celu-budynku: ostatni punkt trasy
## to postój Wozu. Zwraca komunikat dla paska.
static func tap(o: AttackPlan.Order, grid: BuildGrid, cell: Vector2i, scout: ScoutIntel = null) -> String:
	if not grid.terrain.in_bounds(cell):
		return HINT
	var id := grid.building_at(cell)
	if id != 0 and o.manoeuvre == AttackPlan.Manoeuvre.CONVOY:
		return WAGON_HINT
	if id != 0:
		o.target = cell
		return target_text(grid, id, scout)
	if grid.terrain.get_tile(cell) == TerrainMap.Tile.WATER:
		return "Trasa nie prowadzi przez wodę"
	if o.waypoints.size() >= AttackPlan.MAX_WAYPOINTS:
		o.waypoints.clear()
	o.waypoints.append(cell)
	return "Trasa: punkt %d z %d" % [o.waypoints.size(), AttackPlan.MAX_WAYPOINTS]


## Kratka końca strzałki: wskazany cel albo środek donżonu (domyślny koniec). Tabor: ostatni punkt
## trasy, a bez trasy brak końca (Wóz stoi na wejściu).
static func end_cell(o: AttackPlan.Order, b: BotCastle) -> Vector2i:
	if o.manoeuvre == AttackPlan.Manoeuvre.CONVOY:
		return o.waypoints[-1] if not o.waypoints.is_empty() else AttackPlan.NO_TARGET
	if o.target != AttackPlan.NO_TARGET:
		return o.target
	if b != null and b.grid.buildings.has(b.objective):
		return b.grid.buildings[b.objective].get_center()
	return AttackPlan.NO_TARGET


## Czy `world` (piksele świata) trafia w uchwyt końca strzałki rozkazu. `half` to połowa celu
## dotyku w pikselach świata (przy zoomie innym niż 1× panel przelicza END_HIT, żeby na ekranie
## było zawsze co najmniej 12×12 px logicznych).
static func hit_end(o: AttackPlan.Order, b: BotCastle, world: Vector2, half: float = END_HIT) -> bool:
	var end := end_cell(o, b)
	if end == AttackPlan.NO_TARGET:
		return false
	var d := (world - Vector2(cell_center_px(end))).abs()
	return d.x <= half and d.y <= half


## Ustawia koniec trasy na budynek w kratce `cell` (przeciągnięcie uchwytu). Trawa i woda
## nie zmieniają celu. Tabor (#235): przenosi postój (ostatni punkt trasy) na trawę.
## Zwraca komunikat dla paska.
static func set_end(o: AttackPlan.Order, grid: BuildGrid, cell: Vector2i, scout: ScoutIntel = null) -> String:
	if o.manoeuvre == AttackPlan.Manoeuvre.CONVOY:
		if not grid.terrain.in_bounds(cell) or grid.building_at(cell) != 0 \
				or grid.terrain.get_tile(cell) == TerrainMap.Tile.WATER or o.waypoints.is_empty():
			return WAGON_HINT
		o.waypoints[-1] = cell
		return "Postój Wozu przeniesiony"
	if not grid.terrain.in_bounds(cell):
		return "Koniec trasy: wskaż budynek"
	var id := grid.building_at(cell)
	if id == 0:
		return "Koniec trasy: wskaż budynek"
	o.target = cell
	return target_text(grid, id, scout)


## Komunikat celu: rodzaj budynku albo, poza fragmentem odsłoniętym przez zwiad, „nieznany” (#28).
## Bez `scout` (np. testy, stary kod) rodzaj zawsze widać.
static func target_text(grid: BuildGrid, id: int, scout: ScoutIntel = null) -> String:
	if scout != null and not scout.shows(grid.buildings[id]):
		return HIDDEN_TARGET
	return "Cel: %s" % BuildingTypes.NAMES[grid.kinds[id]]


static func clear(o: AttackPlan.Order) -> void:
	o.target = AttackPlan.NO_TARGET
	o.waypoints.clear()


## Start rozkazu na pasku. Wóz (#235) rusza najwcześniej po AttackPlan.WAGON_DELAY_S sekundach,
## więc krótszy czas pokazuje się jako to opóźnienie.
static func start_text(o: AttackPlan.Order) -> String:
	var wagon := o.manoeuvre == AttackPlan.Manoeuvre.CONVOY
	match o.start:
		AttackPlan.Start.AFTER_SECONDS:
			return "po %d s" % (maxi(o.start_value, AttackPlan.WAGON_DELAY_S) if wagon else o.start_value)
		AttackPlan.Start.AFTER_SQUAD:
			return "po oddz. %d" % o.start_value
	return "po %d s" % AttackPlan.WAGON_DELAY_S if wagon else "od razu"


static func retreat_text(percent: int) -> String:
	return "nigdy" if percent <= 0 else "%d%% strat" % percent


## Opis rozkazu na pasku nad oddziałami: [manewr, start i odwrót].
static func describe(o: AttackPlan.Order) -> Array[String]:
	return [AttackPlan.MANOEUVRE_NAMES[o.manoeuvre], "Start: %s  Odwrót: %s" % [start_text(o), retreat_text(o.retreat_percent)]]


## Punkty strzałki rozkazu w kratkach: wejście, trasa (z punktem obejścia dla Oskrzydlenia
## bez trasy) i cel (wskazany budynek albo donżon). Z `end_override` zamiast celu (podgląd przeciągania).
static func arrow_cells(o: AttackPlan.Order, b: BotCastle, end_override: Vector2i = AttackPlan.NO_TARGET) -> Array[Vector2i]:
	var out: Array[Vector2i] = [b.spawn]
	if o.manoeuvre == AttackPlan.Manoeuvre.CONVOY:
		# Tabor: sama trasa, z podglądem przenoszonego postoju
		out.append_array(o.waypoints)
		if end_override != AttackPlan.NO_TARGET and out.size() > 1:
			out[-1] = end_override
		return out
	var goal := end_override if end_override != AttackPlan.NO_TARGET else end_cell(o, b)
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
	if show_plan:
		var hidden := hidden_ids(bot.grid, intel)
		CastleView.draw_buildings(self, bot.grid, textures, states, hidden)
		_draw_fog(hidden)
	else:
		CastleView.draw_buildings(self, bot.grid, textures, states)
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
		var mark := drag_end_cell if drag_end_cell != AttackPlan.NO_TARGET else sel.target
		if mark != AttackPlan.NO_TARGET:
			var id := bot.grid.building_at(mark)
			if id != 0:
				var r := bot.grid.buildings[id]
				CastleView.draw_frame(self, Rect2i(r.position * TerrainMap.CELL, r.size * TerrainMap.CELL), Palette.ACCENT)


## Budynki poza fragmentem odsłoniętym przez zwiad (#28): id → true.
static func hidden_ids(grid: BuildGrid, scout: ScoutIntel) -> Dictionary:
	var out := {}
	for id: int in grid.buildings:
		if scout == null or not scout.shows(grid.buildings[id]):
			out[id] = true
	return out


## Mgła (#28): ukryte budynki jako sam zarys (kolory miniatury z karty celu), a odsłonięty fragment
## w ramce, z oddziałami załogi, patrolami i pułapkami (jak na ekranie obrony).
func _draw_fog(hidden: Dictionary) -> void:
	for id: int in hidden:
		var r := bot.grid.buildings[id]
		var px := Rect2(r.position * TerrainMap.CELL, r.size * TerrainMap.CELL)
		draw_rect(px, MinimapArt.BUILDING)
		CastleView.draw_frame(self, Rect2i(px), MinimapArt.BUILDING_EDGE)
	if intel.is_empty():
		return
	CastleView.draw_frame(self, Rect2i(intel.region.position * TerrainMap.CELL, intel.region.size * TerrainMap.CELL),
			Palette.THATCH[2])
	for points: Array in intel.patrols:
		for k in points.size():
			var a := cell_center_px(points[k] as Vector2i)
			var b := cell_center_px(points[(k + 1) % points.size()] as Vector2i)
			for p in line_pixels(a, b):
				draw_rect(Rect2(p.x, p.y, 1, 1), Palette.ACCENT)
	for e: Array in intel.squads:
		var at := (e[1] as Vector2i) * TerrainMap.CELL
		draw_rect(Rect2(at.x, at.y, TerrainMap.CELL, TerrainMap.CELL), Color(Palette.SHADOW, 0.7))
		CastleView.draw_frame(self, Rect2i(at, Vector2i.ONE * TerrainMap.CELL), Palette.ACCENT)
		var cls := int(e[0])
		if PixelIcons.class_region(cls).has_area():
			PixelIcons.draw_class(self, Vector2(at + Vector2i(2, 2)), cls)
	for e: Array in intel.traps:
		var tp := (e[1] as Vector2i) * TerrainMap.CELL
		draw_rect(Rect2(tp.x, tp.y, TerrainMap.CELL, TerrainMap.CELL), Color(Palette.SHADOW, 0.7))
		CastleView.draw_frame(self, Rect2i(tp, Vector2i.ONE * TerrainMap.CELL), Palette.ACCENT)
		PixelFont.draw_centered(self, Rect2(tp, Vector2.ONE * TerrainMap.CELL), TrapConfig.GLYPHS[int(e[0])],
				Palette.THATCH[2])


func _draw_arrow(o: AttackPlan.Order, col: Color) -> void:
	var preview := drag_end_cell if o.squad == selected else AttackPlan.NO_TARGET
	var cells := arrow_cells(o, bot, preview)
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
