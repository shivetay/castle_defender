class_name AttackPanel
extends Control
## Przyciski planowania ataku (#17) nad mapą celu (AttackPlanner): kolumna przy prawej krawędzi
## (Manewr, Start, Odwrót, Wyczyść, Atakuj, Wróć), pasek oddziałów na dole i opis rozkazu
## wybranego oddziału. Dotknięcia poza przyciskami idą do mapy (cel i trasa); uchwyt końca
## strzałki (domyślnie donżon) przeciąga się na inny budynek bez ruszania kamery.
## Manewr otwiera listę wszystkich manewrów: dostępne z krótkim opisem, niedostępne wyszarzone
## z tym, czego brakuje (jednostka, epoka, badanie). Lista łapie wszystkie dotknięcia, a dotknięcie
## poza nią ją zamyka.

signal attack_requested
signal back_requested
## Plan albo wybór zmienił się (mapa ma się przerysować, a gra zapisać).
signal changed(message: String)

enum Target { NONE = -1, MANOEUVRE, START, RETREAT, CLEAR, ATTACK, BACK, SQUAD = 100, PICK = 200 }
const COLUMN: Array[int] = [Target.MANOEUVRE, Target.START, Target.RETREAT, Target.CLEAR, Target.ATTACK, Target.BACK]
const LABELS: Array[String] = ["Manewr", "Start", "Odwrót", "Wyczyść", "Atakuj", "Wróć"]
const SQUAD_TILE := Vector2(44, 16)
## Pasek opisu rozkazu nad oddziałami.
const INFO_H := 10
## Wiersz listy manewrów: nazwa i pod nią opis albo powód, dlaczego niedostępny.
const PICK_H := 18
const PICK_GAP := 2

var planner: AttackPlanner
var content_left := float(Hud.CORNER_INSET)
var content_right := 320.0 - Hud.CORNER_INSET
var _pressed := Target.NONE
## Otwarta lista wyboru manewru.
var picking := false
## Dotknięcie zamknęło listę: jego puszczenie nie trafia już do mapy.
var _swallow_release := false
## Przeciąganie uchwytu końca strzałki wybranego oddziału (nie rusza kamery).
var _drag_end := false


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _notification(what: int) -> void:
	if what == NOTIFICATION_VISIBILITY_CHANGED:
		picking = false
		_drag_end = false
		if planner != null:
			planner.drag_end_cell = AttackPlan.NO_TARGET


func _process(_delta: float) -> void:
	if not visible:
		return
	var bounds := Hud.content_bounds(get_viewport_rect().size, Hud.safe_area_in_view(get_viewport()))
	content_left = bounds.x
	content_right = bounds.y
	queue_redraw()


static func squad_rect(view: Vector2, left: float, i: int) -> Rect2:
	return Rect2(Vector2(left + i * (SQUAD_TILE.x + Hud.BUTTON_GAP), Hud.row_y(view)), SQUAD_TILE)


static func info_rect(view: Vector2, left: float, right: float) -> Rect2:
	return Rect2(left, Hud.row_y(view) - INFO_H - 2, right - left, INFO_H)


## Wiersz `i` listy manewrów: od lewej granicy treści do kolumny przycisków, od górnego paska.
static func pick_rect(right: float, left: float, i: int) -> Rect2:
	var w := right - Hud.BUTTON_SIZE.x - Hud.BUTTON_GAP - left
	return Rect2(left, Hud.BAR_H + 2 + i * (PICK_H + PICK_GAP), w, PICK_H)


## Cała lista manewrów (wiersze z lukami między nimi): dotknięcie w niej nie zamyka listy.
static func list_rect(left: float, right: float) -> Rect2:
	var first := pick_rect(right, left, 0)
	return first.merge(pick_rect(right, left, AttackPlan.MANOEUVRE_NAMES.size() - 1))


## Manewr pod punktem na otwartej liście albo -1.
static func pick_at(p: Vector2, left: float, right: float) -> int:
	for i in AttackPlan.MANOEUVRE_NAMES.size():
		if pick_rect(right, left, i).has_point(p):
			return i
	return -1


## Cel pod punktem: przycisk kolumny, oddział (SQUAD + numer od 0) albo NONE.
static func target_at(p: Vector2, view: Vector2, left: float, right: float, squad_count: int) -> int:
	for i in COLUMN.size():
		if Hud.column_rect(right, i).has_point(p):
			return COLUMN[i]
	for i in squad_count:
		if squad_rect(view, left, i).has_point(p):
			return Target.SQUAD + i
	return Target.NONE


func _input(event: InputEvent) -> void:
	if not visible or planner == null:
		return
	if _drag_end and event is InputEventScreenDrag:
		get_viewport().set_input_as_handled()
		_move_end_preview((event as InputEventScreenDrag).position)
		return
	var touch := event as InputEventScreenTouch
	if touch == null:
		return
	if _drag_end:
		get_viewport().set_input_as_handled()
		if not touch.pressed:
			_finish_end_drag(touch.position)
		return
	if picking and list_rect(content_left, content_right).has_point(touch.position):
		# w obrębie listy (z lukami między wierszami): wiersz wybiera manewr, luka nic nie robi
		get_viewport().set_input_as_handled()
		var row := pick_at(touch.position, content_left, content_right)
		var hit := Target.PICK + row if row >= 0 else Target.NONE
		if touch.pressed:
			_pressed = hit
			return
		var was_row := _pressed
		_pressed = Target.NONE
		if hit != Target.NONE and hit == was_row:
			choose(row)
		return
	if _swallow_release and not touch.pressed:
		_swallow_release = false
		get_viewport().set_input_as_handled()
		return
	if picking and touch.pressed:
		# poza listą: zamyka ją, a przycisk albo oddział pod palcem działa od razu; mapa i sam Manewr
		# tylko zamykają listę (puszczenie palca nie stawia punktu trasy ani nie otwiera listy znowu)
		picking = false
		var under := target_at(touch.position, get_viewport_rect().size, content_left, content_right, planner.squads.size())
		if under == Target.NONE or under == Target.MANOEUVRE:
			get_viewport().set_input_as_handled()
			_pressed = Target.NONE
			_swallow_release = true
			changed.emit(AttackPlanner.HINT)
			return
	var t := target_at(touch.position, get_viewport_rect().size, content_left, content_right, planner.squads.size())
	if touch.pressed:
		_pressed = t
		if t != Target.NONE:
			get_viewport().set_input_as_handled()
			return
		# mapa: uchwyt końca strzałki zamiast kamery / punktu trasy
		var o := planner.order()
		if o != null and AttackPlanner.hit_end(o, planner.bot, _world_of(touch.position)):
			get_viewport().set_input_as_handled()
			_drag_end = true
			planner.drag_end_cell = AttackPlanner.end_cell(o, planner.bot)
			planner.queue_redraw()
			changed.emit("Przenieś koniec: upuść na budynek")
		return
	var was := _pressed
	_pressed = Target.NONE
	if was == Target.NONE:
		return
	get_viewport().set_input_as_handled()
	if t == was:
		activate(was)


## Piksel świata pod punktem ekranu (kamera planu; bez kamery: sam punkt).
func _world_of(screen: Vector2) -> Vector2:
	var cam := get_viewport().get_camera_2d() as PanZoomCamera
	return cam.screen_to_world(screen) if cam != null else screen


func _move_end_preview(screen: Vector2) -> void:
	var world := _world_of(screen)
	planner.drag_end_cell = Vector2i((world / TerrainMap.CELL).floor())
	planner.queue_redraw()


func _finish_end_drag(screen: Vector2) -> void:
	_drag_end = false
	planner.drag_end_cell = AttackPlan.NO_TARGET
	var o := planner.order()
	if o == null or planner.bot == null:
		planner.queue_redraw()
		return
	var cell := Vector2i((_world_of(screen) / TerrainMap.CELL).floor())
	changed.emit(AttackPlanner.set_end(o, planner.bot.grid, cell))
	planner.queue_redraw()


## Działanie przycisku (też z testów).
func activate(t: int) -> void:
	var o := planner.order()
	if t >= Target.SQUAD:
		picking = false
		planner.selected = t - Target.SQUAD + 1
		changed.emit("Oddział %d: %s" % [planner.selected, AttackPlanner.HINT])
		return
	match t:
		Target.ATTACK:
			attack_requested.emit()
			return
		Target.BACK:
			back_requested.emit()
			return
	if o == null:
		return
	match t:
		Target.MANOEUVRE:
			picking = not picking
			changed.emit("Oddział %d: wybierz manewr" % o.squad if picking else AttackPlanner.HINT)
		Target.START:
			AttackPlanner.next_start(o, planner.squads.size())
			changed.emit("Start: %s" % AttackPlanner.start_text(o))
		Target.RETREAT:
			o.retreat_percent = AttackPlanner.next_retreat(o.retreat_percent)
			changed.emit("Odwrót: %s" % AttackPlanner.retreat_text(o.retreat_percent))
		Target.CLEAR:
			AttackPlanner.clear(o)
			changed.emit("Cel i trasa wyczyszczone")


## Czego brakuje oddziałowi wybranemu w planie do manewru `m` (pusty napis: dostępny).
func missing_for(m: int) -> String:
	var o := planner.order()
	if o == null:
		return ""
	return AttackPlan.missing(m, planner.unit_of(o.squad), planner.age, planner.research)


## Wybór manewru `m` z listy (też z testów): dostępny staje się rozkazem i zamyka listę, niedostępny
## zostawia listę otwartą i mówi na pasku, czego brakuje.
func choose(m: int) -> void:
	var o := planner.order()
	if o == null or m < 0 or m >= AttackPlan.MANOEUVRE_NAMES.size():
		return
	var why := missing_for(m)
	if not why.is_empty():
		changed.emit("%s: %s" % [AttackPlan.MANOEUVRE_NAMES[m], why])
		return
	o.manoeuvre = m
	picking = false
	changed.emit(AttackPlan.MANOEUVRE_NAMES[m])


func _draw() -> void:
	if planner == null:
		return
	var view := get_viewport_rect().size
	for i in COLUMN.size():
		Hud.paint_button(self, Hud.column_rect(content_right, i), LABELS[i], _pressed == COLUMN[i], false)
	var o := planner.order()
	if o != null:
		var info := info_rect(view, content_left, content_right)
		draw_rect(info, Color(Palette.SHADOW, 0.8))
		var text := AttackPlanner.describe(o)
		PixelFont.draw_text(self, info.position + Vector2(2, 1), "%d. %s" % [o.squad, text[0]], Palette.INK)
		PixelFont.draw_right(self, info.end.x - 2, info.position.y + 1, text[1], Palette.THATCH[2])
	for i in planner.squads.size():
		var sq: Array = planner.squads[i]
		var r := squad_rect(view, content_left, i)
		Hud.paint_button(self, r, "", _pressed == Target.SQUAD + i or planner.selected == i + 1, false)
		if planner.selected == i + 1:
			CastleView.draw_frame(self, Rect2i(r), Palette.INK)
		var unit := int(sq[0])
		var cls := UnitTypes.unit_class(unit)
		var at := r.position + Vector2(3, 5)
		if PixelIcons.class_region(cls).has_area():
			PixelIcons.draw_class(self, at, cls)
		else:
			PixelFont.draw_text(self, at - Vector2(0, 2), UnitTypes.SHORT_NAMES[unit].left(1), Palette.INK)
		PixelFont.draw_text(self, r.position + Vector2(10, 3), "%d×%d" % [i + 1, int(sq[1])], Palette.INK)
	if picking:
		_draw_picker()


## Druga linia wiersza niedostępnego manewru: „Niedostępne: …”, gdy jednostka oddziału go nie umie
## (stała niezdolność), inaczej „Wymaga: …” (epoka, badanie).
static func reason_line(m: int, unit: int, why: String) -> String:
	var unit_ok := unit < 0 or AttackPlan.unit_can(m, unit)
	return ("Wymaga: " if unit_ok else "Niedostępne: ") + why


func _draw_picker() -> void:
	var o := planner.order()
	if o == null:
		return
	for m in AttackPlan.MANOEUVRE_NAMES.size():
		var r := pick_rect(content_right, content_left, m)
		var why := missing_for(m)
		var chosen := o.manoeuvre == m
		var col: Color = Palette.WOOD[2] if chosen or _pressed == Target.PICK + m else Palette.WOOD[1]
		draw_rect(r, col if why.is_empty() else Color(Palette.SHADOW, 0.9))
		if chosen:
			CastleView.draw_frame(self, Rect2i(r), Palette.INK)
		var name_col: Color = Palette.INK if why.is_empty() else Palette.WOOD[2]
		PixelFont.draw_text(self, r.position + Vector2(3, 1), AttackPlan.MANOEUVRE_NAMES[m], name_col)
		var line := AttackPlan.MANOEUVRE_DESC[m] if why.is_empty() else reason_line(m, planner.unit_of(o.squad), why)
		PixelFont.draw_text(self, r.position + Vector2(3, 9), line, Palette.THATCH[2] if why.is_empty() else Palette.ACCENT)
