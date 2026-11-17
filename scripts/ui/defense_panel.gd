class_name DefensePanel
extends Control
## Ustawienia obrony (#19, #20, notatka Interfejs): własny zamek w trybie edycji. Na dole pasek
## oddziałów załogi, nad nim opis wybranego oddziału, w kolumnie przy prawej krawędzi Zadanie, Wieże,
## Zdejmij i Gotowe. Gracz wybiera oddział na pasku, przyciskiem Zadanie zadanie z listy (Obrona
## odcinka, Patrol), a dotykiem kratki w strefie wokół donżonu jego miejsce: przy Obronie odcinka
## trawę albo odcinek wału, palisady, bramy czy wieży, przy Patrolu kolejne punkty trasy (do 3).
## Dotknięcie miejsca innego oddziału na mapie wybiera ten oddział. Wieże zmieniają priorytet celów
## wież, Zdejmij odsyła oddział pod donżon. Mapę i zadania rysuje main; ten węzeł rysuje tylko przyciski.
## Dotknięcia poza przyciskami idą do mapy (kamera i tap()).

## Układ albo wybór zmienił się (mapa ma się przerysować, a gra zapisać).
signal changed(message: String)
signal back_requested

enum Target { NONE = -1, CLEAR, BACK, TASK, TOWERS, MORE = 50, SQUAD = 100 }
const COLUMN: Array[int] = [Target.TASK, Target.TOWERS, Target.CLEAR, Target.BACK]
const LABELS: Array[String] = ["Zadanie", "Wieże", "Zdejmij", "Gotowe"]
const MORE_LABEL := "Dalej"
const HINT := "Wybierz oddział i dotknij kratki w strefie"
const AT_KEEP := "przy donżonie"
const SQUAD_TILE := AttackPanel.SQUAD_TILE
const INFO_H := AttackPanel.INFO_H

var plan: DefensePlan
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
func open(p: DefensePlan, army: Array, squad_ids: Array[int]) -> void:
	plan = p
	squads = army
	ids = squad_ids
	selected = clampi(selected, 0, maxi(0, squads.size() - 1))
	first = 0
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
static func target_at(p: Vector2, view: Vector2, left: float, right: float, count: int, start: int) -> int:
	for i in COLUMN.size():
		if Hud.column_rect(right, i).has_point(p):
			return COLUMN[i]
	var fit := tiles_fit(left, right)
	var shown := visible_squads(count, fit, start)
	for slot in shown.size():
		if tile_rect(view, left, slot).has_point(p):
			return Target.SQUAD + shown[slot]
	if count > fit and tile_rect(view, left, shown.size()).has_point(p):
		return Target.MORE
	return Target.NONE


# --- Edycja ---------------------------------------------------------------------------------------

## Zadanie oddziału jako tekst: „przy donżonie”, „Obrona odcinka”, „Patrol 2/3 pkt”; bez miejsca
## z prośbą o dotknięcie mapy.
static func task_text(o: DefensePlan.Order) -> String:
	if o == null:
		return AT_KEEP
	if o.post == DefensePlan.NO_POST:
		return "%s: dotknij mapy" % DefensePlan.TASK_NAMES[o.task]
	if o.task == DefensePlan.Task.PATROL:
		return "Patrol %d/%d pkt" % [o.route.size() + 1, DefensePlan.MAX_ROUTE + 1]
	return DefensePlan.TASK_NAMES[o.task]


## Opis oddziału na pasku nad kafelkami: [numer, rodzaj i liczba; zadanie].
func describe(i: int) -> Array[String]:
	var sq: Array = squads[i]
	return ["%d. %s ×%d" % [i + 1, UnitTypes.unit_name(int(sq[0])), int(sq[1])], task_text(plan.order_for(ids[i]))]


## Dotknięcie kratki `cell` własnego zamku. Miejsce innego oddziału go wybiera. Odcinek umocnień
## (wał, palisada, brama, wieża) w strefie daje miejsce tuż przy nim od strony donżonu. Przy
## Patrolu kolejne dotknięcia dodają punkty trasy (czwarte zaczyna trasę od nowa), inaczej kratka
## staje się miejscem Obrony odcinka. Zwraca komunikat dla paska.
func tap(grid: BuildGrid, cell: Vector2i) -> String:
	if squads.is_empty():
		return "Najpierw wyszkol wojsko: Koszary i Wojsko"
	var holder := plan.squad_at(cell)
	if holder != 0 and holder != selected_id() and ids.has(holder):
		select(ids.find(holder))
		return "Oddział %d: %s" % [selected + 1, task_text(plan.order_for(holder))]
	var section := ""
	var id := grid.building_at(cell) if grid.terrain.in_bounds(cell) else 0
	if id != 0 and DefensePlan.is_section(grid.kinds[id]) and DefensePlan.zone(grid).has_point(cell):
		section = BuildingTypes.NAMES[grid.kinds[id]]
		cell = DefensePlan.section_post(grid, id)
		if cell == DefensePlan.NO_POST:
			return "%s: brak miejsca od środka" % section
	var problem := DefensePlan.post_problem(grid, cell)
	if not problem.is_empty():
		return problem
	var o := plan.order_for(selected_id())
	if o != null and o.task == DefensePlan.Task.PATROL:
		if o.post == DefensePlan.NO_POST or o.route.size() >= DefensePlan.MAX_ROUTE:
			o.post = cell
			o.route.clear()
		else:
			o.route.append(cell)
		return "Oddział %d: patrol, punkt %d z %d" % [selected + 1, o.route.size() + 1, DefensePlan.MAX_ROUTE + 1]
	plan.set_post(selected_id(), cell)
	if not section.is_empty():
		return "Oddział %d: obrona odcinka, %s" % [selected + 1, section]
	return "Oddział %d: obrona odcinka" % (selected + 1)


## Następne zadanie oddziału: bez zadania → Obrona odcinka → Patrol → Obrona odcinka… Miejsce zostaje.
static func next_task(o: DefensePlan.Order) -> int:
	if o == null:
		return DefensePlan.Task.HOLD
	return (o.task + 1) % DefensePlan.TASK_NAMES.size()


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
	var t := target_at(touch.position, get_viewport_rect().size, content_left, content_right, squads.size(), first)
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
		Target.TOWERS:
			plan.tower_priority = (plan.tower_priority + 1) % DefensePlan.TOWER_PRIORITY_NAMES.size()
			changed.emit(tower_text(plan.tower_priority))
		Target.TASK:
			if selected_id() != 0:
				var o := plan.set_task(selected_id(), next_task(plan.order_for(selected_id())))
				changed.emit("Oddział %d: %s" % [selected + 1, task_text(o)])
		Target.CLEAR:
			if selected_id() != 0:
				plan.clear_post(selected_id())
				changed.emit("Oddział %d: %s" % [selected + 1, AT_KEEP])


func _draw() -> void:
	if plan == null:
		return
	var view := get_viewport_rect().size
	for i in COLUMN.size():
		Hud.paint_button(self, Hud.column_rect(content_right, i), LABELS[i], _pressed == COLUMN[i], false)
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


func _draw_tile(r: Rect2, i: int) -> void:
	var sq: Array = squads[i]
	Hud.paint_button(self, r, "", _pressed == Target.SQUAD + i or selected == i, false)
	if selected == i:
		CastleView.draw_frame(self, Rect2i(r), Palette.INK)
	var unit := int(sq[0])
	var cls := UnitTypes.unit_class(unit)
	var at := r.position + Vector2(3, 5)
	if PixelIcons.class_region(cls).has_area():
		PixelIcons.draw_class(self, at, cls)
	else:
		PixelFont.draw_text(self, at - Vector2(0, 2), UnitTypes.SHORT_NAMES[unit].left(1), Palette.INK)
	PixelFont.draw_text(self, r.position + Vector2(10, 3), "%d×%d" % [i + 1, int(sq[1])], Palette.INK)
	if plan.post_for(ids[i]) != DefensePlan.NO_POST:
		# znacznik: oddział ma zadanie z miejscem
		draw_rect(Rect2(r.end.x - 5, r.position.y + 3, 2, 2), Palette.VALID)
