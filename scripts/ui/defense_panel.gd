class_name DefensePanel
extends Control
## Ustawienia obrony (#19, #20, notatka Interfejs): własny zamek w trybie edycji. Na dole pasek
## oddziałów załogi, nad nim opis wybranego oddziału, w kolumnie przy prawej krawędzi Zadanie, Wieże,
## Zdejmij i Gotowe. Gracz wybiera oddział na pasku, przyciskiem Zadanie zadanie z listy (Obrona
## odcinka, Patrol), a dotykiem kratki w strefie wokół donżonu jego miejsce: przy Obronie odcinka
## trawę albo odcinek wału, palisady, bramy czy wieży, przy Patrolu kolejne punkty trasy (do 3).
## Dotknięcie miejsca innego oddziału na mapie wybiera ten oddział. Strzelec przy Obronie odcinka
## może stanąć na samym wale albo palisadzie (dotknięcie muru), a Wypad konnicy wskazuje się bramą.
## Konnica może też stanąć Przed murami (dotknięcie trawy, także na zewnątrz).
## Oddział bez ustawionego zadania ma zadanie domyślne swojej klasy (DefensePlan.default_order), opis
## to podaje. Wieże zmieniają priorytet celów wież, Zdejmij wraca do zadania domyślnego. Mapę i zadania
## rysuje main; ten węzeł rysuje tylko przyciski. Pułapki (#100) przełączają pasek na rodzaje pułapek:
## dotknięcie kratki stawia wybraną (koszt schodzi od razu), dotknięcie pułapki ją usuwa (bez zwrotu),
## a Załoga wraca do oddziałów. Powtórki (#29) otwierają listę ostatnich obron: po obejrzeniu ataku
## gracz wraca tu i od razu poprawia obronę. Komendant (#31) przełącza komendanta obrony: brak, a potem
## każdy generał gracza poza generałem ataku. Komendant dowodzi całą obroną, nie stoi na mapie.
## Zadanie Garnizon Dworu (#81) daje się wybrać tylko, gdy oddział mieści się w pojemności Dworu
## (inaczej przycisk przeskakuje na Przy donżonie); opis pokazuje zajęte miejsca garnizonu.
## Dotknięcia poza przyciskami idą do mapy (kamera i tap()).

## Układ albo wybór zmienił się (mapa ma się przerysować, a gra zapisać).
signal changed(message: String)
signal back_requested
## Powtórki (#29): lista ostatnich obron.
signal replays_requested

enum Target { NONE = -1, CLEAR, BACK, TASK, TOWERS, TRAPS, CREW, REPLAYS, COMMANDER, MORE = 50, SQUAD = 100 }
const COLUMN: Array[int] = [Target.TASK, Target.TOWERS, Target.TRAPS, Target.CLEAR, Target.REPLAYS, Target.BACK]
const LABELS: Array[String] = ["Zadanie", "Wieże", "Pułapki", "Zdejmij", "Powtórki", "Gotowe"]
## Przycisk komendanta (#31) w lewym górnym rogu (AttackPanel.general_rect), poza trybem pułapek.
const COMMANDER_LABEL := "Komend."
## Kolumna w trybie pułapek (#100).
const TRAP_COLUMN: Array[int] = [Target.CREW, Target.BACK]
const TRAP_LABELS: Array[String] = ["Załoga", "Gotowe"]
## Postawioną pułapkę usuwa jej dotknięcie (komunikat „Usunięto: …”).
const TRAP_HINT := "Wybierz pułapkę i dotknij kratki"
const MORE_LABEL := "Dalej"
const HINT := "Wybierz oddział i dotknij kratki w strefie"
const AT_KEEP := "przy donżonie"
const SQUAD_TILE := AttackPanel.SQUAD_TILE
const INFO_H := AttackPanel.INFO_H

var plan: DefensePlan
## Generałowie gracza (#31) do wyboru komendanta; ustawia je main.gd.
var generals: Generals
## Zamek i epoka: do zadań domyślnych w opisie i do Wypadu konnicy (od epoki II).
var castle: BuildGrid
var age := 0
## Tryb pułapek (#100): wybrany rodzaj, a do wymagań i kosztu badania, surowce i zbrojownia gracza.
var trap_mode := false
var trap_kind := 0
var research: Research
## Rekrutacja gracza (#81): do pojemności garnizonu liczą się też jednostki w szkoleniu.
var recruitment: Recruitment
var economy: Economy
var goods: Goods
## Oddziały załogi [rodzaj, liczba] (Recruitment.battle_squads()) i ich id z rekrutacji.
var squads: Array = []
var ids: Array[int] = []
## Wybrany oddział (indeks w `squads`) i pierwszy oddział widoczny na pasku.
var selected := 0
var first := 0
var content_left := float(Hud.CORNER_INSET)
var content_right := 320.0 - Hud.CORNER_INSET
var _pressed := Target.NONE


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _process(_delta: float) -> void:
	if not visible:
		return
	var bounds := Hud.content_bounds(get_viewport_rect().size, Hud.safe_area_in_view(get_viewport()))
	content_left = bounds.x
	content_right = bounds.y
	queue_redraw()


## Otwiera edycję układu `p` dla załogi `army` (oddziały [rodzaj, liczba]) o id `squad_ids`.
func open(p: DefensePlan, army: Array, squad_ids: Array[int], castle_grid: BuildGrid = null, current_age: int = 0) -> void:
	plan = p
	castle = castle_grid
	age = current_age
	squads = army
	ids = squad_ids
	selected = clampi(selected, 0, maxi(0, squads.size() - 1))
	first = 0
	# zawsze od załogi, nawet gdy ostatnio zamknięto ekran w trybie pułapek (review #186)
	trap_mode = false
	trap_kind = 0
	visible = true


func selected_id() -> int:
	return ids[selected] if selected >= 0 and selected < ids.size() else 0


# --- Układ paska (statyczne, testowane bez ekranu) -------------------------------------------------

## Ile kafelków mieści pasek oddziałów między `left` i `right`.
static func tiles_fit(left: float, right: float) -> int:
	return maxi(1, int((right - left + Hud.BUTTON_GAP) / (SQUAD_TILE.x + Hud.BUTTON_GAP)))


## Indeksy oddziałów widocznych na pasku od `start`. Gdy wszystkie się nie mieszczą, ostatni
## kafelek to Dalej (przewija pasek), więc oddziałów jest o jeden mniej.
static func visible_squads(count: int, fit: int, start: int) -> Array[int]:
	var cap := fit if count <= fit else maxi(1, fit - 1)
	var out: Array[int] = []
	for i in range(start, mini(count, start + cap)):
		out.append(i)
	return out


## Pierwszy oddział po Dalej: następna strona, a po ostatniej znów pierwsza.
static func next_first(count: int, fit: int, start: int) -> int:
	var cap := maxi(1, fit - 1)
	return 0 if start + cap >= count else start + cap


static func tile_rect(view: Vector2, left: float, slot: int) -> Rect2:
	return AttackPanel.squad_rect(view, left, slot)


## Cel pod punktem: przycisk kolumny, Dalej, oddział (SQUAD + indeks) albo NONE.
static func column(traps_shown: bool) -> Array[int]:
	return TRAP_COLUMN if traps_shown else COLUMN


static func column_labels(traps_shown: bool) -> Array[String]:
	return TRAP_LABELS if traps_shown else LABELS


## Cel pod punktem; `count` to liczba kafelków (oddziałów albo rodzajów pułapek w trybie pułapek).
static func target_at(p: Vector2, view: Vector2, left: float, right: float, count: int, start: int,
		traps_shown: bool = false) -> int:
	var col := column(traps_shown)
	for i in col.size():
		if Hud.column_rect(right, i).has_point(p):
			return col[i]
	if not traps_shown and AttackPanel.general_rect(left).has_point(p):
		return Target.COMMANDER
	var fit := tiles_fit(left, right)
	var shown := visible_squads(count, fit, start)
	for slot in shown.size():
		if tile_rect(view, left, slot).has_point(p):
			return Target.SQUAD + shown[slot]
	if count > fit and tile_rect(view, left, shown.size()).has_point(p):
		return Target.MORE
	return Target.NONE


# --- Edycja ---------------------------------------------------------------------------------------

## Kolejny komendant obrony (#31): brak → generałowie gracza po kolei (bez generała ataku) → brak.
## Zwraca komunikat.
static func next_commander(p: DefensePlan, g: Generals) -> String:
	if g == null or g.roster.is_empty():
		return "Najpierw zwerbuj generała w Dworze"
	p.next_commander(g, g.attack_kind)
	return commander_text(p, g)


## Napis przycisku komendanta: krótka nazwa generała albo „Komend.”.
static func commander_label(p: DefensePlan, g: Generals) -> String:
	if p == null or p.commander < 0 or g == null or not g.has_general(p.commander):
		return COMMANDER_LABEL
	return Generals.SHORT_NAMES[p.commander]


## Wskaźnik siły obrony (#263), np. „Siła obrony 245”: załoga, pułapki i umocnienia (Strength.defense).
static func strength_text(r: Recruitment, p: DefensePlan, g: BuildGrid) -> String:
	return "Siła obrony %d" % Strength.defense(r, p, g)


## Pole wskaźnika siły obrony: na prawo od przycisku komendanta, na wysokości jego środka, z 2 px
## marginesu tła wokół tekstu.
static func strength_rect(left: float, text: String) -> Rect2:
	var b := AttackPanel.general_rect(left)
	return Rect2(b.end.x + 3, b.position.y + floorf((b.size.y - PixelFont.LINE) / 2.0) - 2,
			PixelFont.text_width(text) + 4, PixelFont.LINE + 3)


## Opis komendanta: „Komendant: brak” albo „Komendant: Wódz drużyny, poz. 2”.
static func commander_text(p: DefensePlan, g: Generals) -> String:
	if p.commander < 0 or g == null or not g.has_general(p.commander):
		return "Komendant: brak"
	return "Komendant: %s" % Generals.label(g.get_general(p.commander))


## Zadanie oddziału jako tekst: „przy donżonie”, „Obrona odcinka”, „Patrol 2/3 pkt”; bez miejsca
## z prośbą o dotknięcie mapy.
static func task_text(o: DefensePlan.Order, g: BuildGrid = null) -> String:
	if o == null:
		return AT_KEEP
	if o.task == DefensePlan.Task.KEEP or o.task == DefensePlan.Task.GARRISON:
		return DefensePlan.TASK_NAMES[o.task]
	if o.post == DefensePlan.NO_POST:
		return "%s: dotknij mapy" % DefensePlan.TASK_NAMES[o.task]
	if o.task == DefensePlan.Task.PATROL:
		if o.route.is_empty():
			return "Patrol 1/%d: dodaj punkt" % (DefensePlan.MAX_ROUTE + 1)
		return "Patrol %d/%d pkt" % [o.route.size() + 1, DefensePlan.MAX_ROUTE + 1]
	if o.task == DefensePlan.Task.HOLD and g != null and DefensePlan.wall_post(g, o.post):
		return "Na murze"
	if o.task == DefensePlan.Task.HOLD and g != null and DefensePlan.station_post(g, o.post):
		var on := g.building_at(o.post)
		return "Na kopcu" if on != 0 and g.kinds[on] == BuildingTypes.Kind.MOUND else "Na wieży"
	return DefensePlan.TASK_NAMES[o.task]


## Opis zadania domyślnego oddziału klasy `unit_class` („domyślnie: na murze” itd.); bez murów
## i bramy „przy donżonie”.
static func default_text(g: BuildGrid, unit_class: int, current_age: int) -> String:
	var o := DefensePlan.default_order(g, unit_class, current_age) if g != null else null
	if o == null:
		return AT_KEEP
	if o.task == DefensePlan.Task.SORTIE:
		return "domyślnie: wypad"
	if DefensePlan.wall_post(g, o.post):
		return "domyślnie: na murze"
	return "domyślnie: przy bramie"


func unit_class_of(i: int) -> int:
	return UnitTypes.unit_class(int((squads[i] as Array)[0]))


## Opis oddziału na pasku nad kafelkami: [numer, rodzaj i liczba; zadanie].
func describe(i: int) -> Array[String]:
	var sq: Array = squads[i]
	var o := plan.order_for(ids[i])
	var text := task_text(o, castle) if o != null else default_text(castle, unit_class_of(i), age)
	if o != null and o.task == DefensePlan.Task.GARRISON:
		text += " " + garrison_text()
	return ["%d. %s ×%d" % [i + 1, UnitTypes.unit_name(int(sq[0])), int(sq[1])], text]


## Dotknięcie kratki `cell` własnego zamku. Miejsce innego oddziału go wybiera. Odcinek umocnień
## (wał, palisada, brama, wieża) w strefie daje miejsce tuż przy nim od strony donżonu, a strzelcom
## stanowisko na murze albo na wieży (#232). Przy Patrolu kolejne dotknięcia dodają punkty trasy
## (czwarte zaczyna trasę od nowa), inaczej kratka staje się miejscem Obrony odcinka. Zwraca komunikat
## dla paska.
func tap(grid: BuildGrid, cell: Vector2i) -> String:
	if trap_mode:
		return tap_trap(grid, cell)
	if squads.is_empty():
		return "Najpierw wyszkol wojsko: Koszary i Wojsko"
	var holder := plan.squad_at(cell)
	if holder != 0 and holder != selected_id() and ids.has(holder):
		select(ids.find(holder))
		return "Oddział %d: %s" % [selected + 1, task_text(plan.order_for(holder), grid)]
	var o := plan.order_for(selected_id())
	var patrol := o != null and o.task == DefensePlan.Task.PATROL
	var field := o != null and o.task == DefensePlan.Task.FIELD
	var id := grid.building_at(cell) if grid.terrain.in_bounds(cell) else 0
	if o != null and o.task == DefensePlan.Task.KEEP:
		return "Przy donżonie: zmień Zadanie, żeby wskazać miejsce"
	if o != null and o.task == DefensePlan.Task.GARRISON:
		return "Garnizon Dworu: zmień Zadanie, żeby wskazać miejsce"
	if o != null and o.task == DefensePlan.Task.FIREFIGHT:
		# Gaszenie pożarów (#35) wskazuje się Studnią: oddział czeka tuż przy niej
		if id == 0 or grid.kinds[id] != BuildingTypes.Kind.WELL or grid.levels[id] < 1 \
				or not DefensePlan.zone(grid).has_point(cell):
			return "Gaszenie: dotknij Studni"
		var beside := DefensePlan.section_post(grid, id)
		if beside == DefensePlan.NO_POST:
			return "Studnia: brak miejsca obok"
		o.post = beside
		return "Oddział %d: gasi pożary przy Studni" % (selected + 1)
	if o != null and o.task == DefensePlan.Task.SORTIE:
		# Wypad konnicy wskazuje się bramą: oddział czeka tuż za nią, od strony donżonu
		if id == 0 or grid.kinds[id] != BuildingTypes.Kind.GATE or not DefensePlan.zone(grid).has_point(cell):
			return "Wypad: dotknij bramy"
		var behind := DefensePlan.section_post(grid, id)
		if behind == DefensePlan.NO_POST:
			return "Brama: brak miejsca od środka"
		o.post = behind
		return "Oddział %d: wypad przez bramę" % (selected + 1)
	if not patrol and not field and DefensePlan.station_post(grid, cell) \
			and unit_class_of(selected) == RecruitmentConfig.UnitClass.RANGED:
		# strzelcy stają na samym murze (#20), na wieży (#232) albo na Kopcu (#35)
		plan.set_post(selected_id(), cell)
		var where := "na murze" if DefensePlan.wall_post(grid, cell) else \
				("na kopcu" if grid.kinds[id] == BuildingTypes.Kind.MOUND else "na wieży")
		return "Oddział %d: %s, %s" % [selected + 1, where, BuildingTypes.NAMES[grid.kinds[id]]]
	# odcinek umocnień przyciąga tylko Obronę odcinka; punkt patrolu stawia się na trawie (review #181)
	var section := ""
	if not patrol and not field and id != 0 and DefensePlan.is_section(grid.kinds[id]) and DefensePlan.zone(grid).has_point(cell):
		section = BuildingTypes.NAMES[grid.kinds[id]]
		cell = DefensePlan.section_post(grid, id)
		if cell == DefensePlan.NO_POST:
			return "%s: brak miejsca od środka" % section
	var problem := DefensePlan.post_problem(grid, cell)
	if not problem.is_empty():
		return problem
	if patrol:
		if o.post == DefensePlan.NO_POST or o.route.size() >= DefensePlan.MAX_ROUTE:
			o.post = cell
			o.route.clear()
		else:
			o.route.append(cell)
		return "Oddział %d: patrol, punkt %d z %d" % [selected + 1, o.route.size() + 1, DefensePlan.MAX_ROUTE + 1]
	plan.set_post(selected_id(), cell)
	if field:
		return "Oddział %d: przed murami" % (selected + 1)
	if not section.is_empty():
		return "Oddział %d: obrona odcinka, %s" % [selected + 1, section]
	return "Oddział %d: obrona odcinka" % (selected + 1)


## Dotknięcie kratki w trybie pułapek (#100): pułapka na kratce znika (bez zwrotu kosztu), inaczej
## staje wybrana, gdy spełnia wymagania (epoka, technologia, budynki), limit Dworu, miejsce i koszt.
func tap_trap(grid: BuildGrid, cell: Vector2i) -> String:
	var existing := plan.trap_at(cell)
	if existing != null:
		plan.remove_trap(cell)
		return "Usunięto: %s" % TrapConfig.NAMES[existing.kind]
	var problem := TrapConfig.requirement_problem(trap_kind, grid, research, age)
	if not problem.is_empty():
		return problem
	var limit := TrapConfig.limit(grid.manor_level())
	if plan.traps.size() >= limit:
		return "Limit pułapek: %d (wyższy Dwór da więcej)" % limit
	problem = plan.trap_place_problem(grid, trap_kind, cell)
	if not problem.is_empty():
		return problem
	var cost: Array[int] = []
	cost.assign(TrapConfig.COST[trap_kind])
	var needed: Dictionary = TrapConfig.GOODS_COST[trap_kind]
	if economy != null and not economy.can_afford(cost):
		return "Brak surowców: %s" % TrapConfig.cost_text(trap_kind)
	if goods != null:
		for good: int in needed:
			if goods.amounts[good] < int(needed[good]):
				return "Brak towarów: %s" % TrapConfig.cost_text(trap_kind)
	if economy != null:
		economy.spend(cost)
	if goods != null:
		goods.take(needed)
	plan.add_trap(trap_kind, cell)
	return "Postawiono: %s (%d/%d)" % [TrapConfig.NAMES[trap_kind], plan.traps.size(), limit]


## Opis wybranej pułapki na pasku nad kafelkami: [nazwa i koszt; zajęte miejsca albo czego brakuje].
func trap_describe() -> Array[String]:
	var left := "%s: %s" % [TrapConfig.NAMES[trap_kind], TrapConfig.cost_text(trap_kind)]
	var problem := TrapConfig.requirement_problem(trap_kind, castle, research, age) if castle != null else ""
	var right := "%d/%d" % [plan.traps.size(), TrapConfig.limit(castle.manor_level() if castle != null else 1)]
	return [left, "zablokowana" if not problem.is_empty() else right]


## Zadania do wyboru dla oddziału klasy `unit_class` w epoce `current_age`, w kolejności przycisku
## Zadanie: Obrona odcinka, Patrol, dla konnicy Przed murami i Wypad konnicy (od epoki II), dla piechoty
## lekkiej Gaszenie pożarów, gdy zamek ma Studnię (`has_well`, #35), Garnizon Dworu (#81), na końcu
## Przy donżonie.
static func task_options(unit_class: int, current_age: int, has_well: bool = false) -> Array[int]:
	var out: Array[int] = [DefensePlan.Task.HOLD, DefensePlan.Task.PATROL]
	if unit_class == RecruitmentConfig.UnitClass.FAST:
		out.append(DefensePlan.Task.FIELD)
	if unit_class == RecruitmentConfig.UnitClass.FAST and current_age >= DefensePlan.TASK_AGE[DefensePlan.Task.SORTIE]:
		out.append(DefensePlan.Task.SORTIE)
	if unit_class == RecruitmentConfig.UnitClass.LIGHT and has_well:
		out.append(DefensePlan.Task.FIREFIGHT)
	out.append(DefensePlan.Task.GARRISON)
	out.append(DefensePlan.Task.KEEP)
	return out


## Następne zadanie oddziału: bez zadania (domyślne) pierwsze z listy, potem po kolei w kółko.
## Miejsce zostaje (Wypad bierze miejsce za bramą, a Gaszenie przy Studni dopiero z dotknięcia).
static func next_task(o: DefensePlan.Order, unit_class: int = 0, current_age: int = 0, has_well: bool = false) -> int:
	var options := task_options(unit_class, current_age, has_well)
	if o == null:
		return options[0]
	return options[(options.find(o.task) + 1) % options.size()]


## Zajęte miejsca garnizonu Dworu i pojemność (#81), np. „8/12”.
func garrison_text() -> String:
	if recruitment == null or castle == null:
		return ""
	return "%d/%d" % [plan.garrison_units(recruitment), RecruitmentConfig.garrison_capacity(castle)]


static func tower_text(priority: int) -> String:
	return "Wieże: najpierw %s" % DefensePlan.TOWER_PRIORITY_NAMES[priority]


## Wybiera oddział `i` i przewija pasek tak, żeby było go widać.
func select(i: int) -> void:
	selected = clampi(i, 0, maxi(0, squads.size() - 1))
	var fit := tiles_fit(content_left, content_right)
	var guard := 0
	first = 0
	while not visible_squads(squads.size(), fit, first).has(selected) and guard < squads.size():
		first = next_first(squads.size(), fit, first)
		guard += 1


func _input(event: InputEvent) -> void:
	if not visible or plan == null:
		return
	var touch := event as InputEventScreenTouch
	if touch == null:
		return
	var count := TrapConfig.count() if trap_mode else squads.size()
	var t := target_at(touch.position, get_viewport_rect().size, content_left, content_right, count, first if not trap_mode else 0,
			trap_mode)
	if touch.pressed:
		_pressed = t
		if t != Target.NONE:
			get_viewport().set_input_as_handled()
		return
	var was := _pressed
	_pressed = Target.NONE
	if was == Target.NONE:
		return
	get_viewport().set_input_as_handled()
	if t == was:
		activate(was)


## Działanie przycisku (też z testów).
func activate(t: int) -> void:
	if trap_mode and t >= Target.SQUAD:
		trap_kind = clampi(t - Target.SQUAD, 0, TrapConfig.count() - 1)
		var problem := TrapConfig.requirement_problem(trap_kind, castle, research, age) if castle != null else ""
		changed.emit(problem if not problem.is_empty() else "%s: %s" % [TrapConfig.NAMES[trap_kind], TrapConfig.cost_text(trap_kind)])
		return
	if t == Target.TRAPS:
		trap_mode = true
		changed.emit(TRAP_HINT)
		return
	if t == Target.CREW:
		trap_mode = false
		changed.emit(HINT)
		return
	if t >= Target.SQUAD:
		select(t - Target.SQUAD)
		changed.emit("Oddział %d: %s" % [selected + 1, HINT])
		return
	match t:
		Target.MORE:
			first = next_first(squads.size(), tiles_fit(content_left, content_right), first)
			changed.emit(HINT)
		Target.BACK:
			back_requested.emit()
		Target.REPLAYS:
			replays_requested.emit()
		Target.COMMANDER:
			changed.emit(next_commander(plan, generals))
		Target.TOWERS:
			plan.tower_priority = (plan.tower_priority + 1) % DefensePlan.TOWER_PRIORITY_NAMES.size()
			changed.emit(tower_text(plan.tower_priority))
		Target.TASK:
			if selected_id() != 0:
				var well := castle != null and castle.has_built(BuildingTypes.Kind.WELL)
				var current := plan.order_for(selected_id())
				var task := next_task(current, unit_class_of(selected), age, well)
				var full := ""
				if task == DefensePlan.Task.GARRISON and (recruitment == null
						or not plan.garrison_fits(selected_id(), recruitment, castle)):
					# Dwór pełny (#81): przycisk przeskakuje na następne zadanie
					full = "Garnizon pełny %s, " % garrison_text()
					var skip := DefensePlan.Order.new()
					skip.task = task
					task = next_task(skip, unit_class_of(selected), age, well)
				var o := plan.set_task(selected_id(), task)
				if not full.is_empty():
					changed.emit("%sOddział %d: %s" % [full, selected + 1, task_text(o, castle)])
					return
				if o.task == DefensePlan.Task.GARRISON:
					changed.emit("Oddział %d: Garnizon Dworu %s" % [selected + 1, garrison_text()])
					return
				if o.task == DefensePlan.Task.SORTIE or o.task == DefensePlan.Task.FIREFIGHT:
					o.post = DefensePlan.NO_POST  # brama albo Studnia do wskazania
				changed.emit("Oddział %d: %s" % [selected + 1, task_text(o, castle)])
		Target.CLEAR:
			if selected_id() != 0:
				plan.clear_post(selected_id())
				changed.emit("Oddział %d: %s" % [selected + 1, default_text(castle, unit_class_of(selected), age)])


func _draw() -> void:
	if plan == null:
		return
	var view := get_viewport_rect().size
	var strength := strength_text(recruitment, plan, castle)
	var sr := strength_rect(content_left, strength)
	draw_rect(sr, Color(Palette.SHADOW, 0.8))
	PixelFont.draw_text(self, sr.position + Vector2(2, 2), strength, Palette.INK)
	var col := column(trap_mode)
	var labels := column_labels(trap_mode)
	for i in col.size():
		Hud.paint_button(self, Hud.column_rect(content_right, i), labels[i], _pressed == col[i], false)
	if trap_mode:
		_draw_traps_bar(view)
		return
	Hud.paint_button(self, AttackPanel.general_rect(content_left), commander_label(plan, generals),
			_pressed == Target.COMMANDER, false)
	if not squads.is_empty():
		var info := AttackPanel.info_rect(view, content_left, content_right)
		draw_rect(info, Color(Palette.SHADOW, 0.8))
		var text := describe(selected)
		PixelFont.draw_text(self, info.position + Vector2(2, 1), text[0], Palette.INK)
		PixelFont.draw_right(self, info.end.x - 2, info.position.y + 1, text[1], Palette.THATCH[2])
	var fit := tiles_fit(content_left, content_right)
	var shown := visible_squads(squads.size(), fit, first)
	for slot in shown.size():
		_draw_tile(tile_rect(view, content_left, slot), shown[slot])
	if squads.size() > fit:
		Hud.paint_button(self, tile_rect(view, content_left, shown.size()), MORE_LABEL, _pressed == Target.MORE, false)


## Pasek pułapek: opis wybranej i kafelek każdego rodzaju (zablokowane przygaszone).
func _draw_traps_bar(view: Vector2) -> void:
	var info := AttackPanel.info_rect(view, content_left, content_right)
	draw_rect(info, Color(Palette.SHADOW, 0.8))
	var text := trap_describe()
	var right_w := PixelFont.text_width(text[1]) + 6
	PixelFont.draw_text(self, info.position + Vector2(2, 1), ResearchPanel.fit_text(text[0], int(info.size.x - right_w - 4)),
			Palette.INK)
	PixelFont.draw_right(self, info.end.x - 2, info.position.y + 1, text[1], Palette.THATCH[2])
	for k in TrapConfig.count():
		var r := tile_rect(view, content_left, k)
		Hud.paint_button(self, r, "", _pressed == Target.SQUAD + k or trap_kind == k, false)
		if trap_kind == k:
			CastleView.draw_frame(self, Rect2i(r), Palette.INK)
		var locked := castle != null and not TrapConfig.requirement_problem(k, castle, research, age).is_empty()
		var col: Color = Palette.WOOD[0] if locked else Palette.INK
		PixelFont.draw_text(self, r.position + Vector2(3, 3), TrapConfig.GLYPHS[k], Palette.THATCH[2] if not locked else col)
		PixelFont.draw_text(self, r.position + Vector2(10, 3), TrapConfig.SHORT_NAMES[k], col)


func _draw_tile(r: Rect2, i: int) -> void:
	var sq: Array = squads[i]
	Hud.paint_button(self, r, "", _pressed == Target.SQUAD + i or selected == i, false)
	if selected == i:
		CastleView.draw_frame(self, Rect2i(r), Palette.INK)
	var unit := int(sq[0])
	var cls := UnitTypes.unit_class(unit)
	var at := r.position + Vector2(3, 5)
	if PixelIcons.class_region(cls).has_area():
		PixelIcons.draw_class_badge(self, at, cls)
	else:
		PixelFont.draw_text(self, at - Vector2(0, 2), UnitTypes.SHORT_NAMES[unit].left(1), Palette.INK)
	PixelFont.draw_text(self, r.position + Vector2(10, 3), "%d×%d" % [i + 1, int(sq[1])], Palette.INK)
	if plan.post_for(ids[i]) != DefensePlan.NO_POST:
		# znacznik: oddział ma zadanie z miejscem
		draw_rect(Rect2(r.end.x - 5, r.position.y + 3, 2, 2), Palette.VALID)
