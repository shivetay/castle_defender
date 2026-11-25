class_name AttackPanel
extends Control
## Przyciski planowania ataku (#17) nad mapą celu (AttackPlanner): kolumna przy prawej krawędzi
## (Manewr, Start, Odwrót, Wyczyść, Atakuj, Wróć), pasek oddziałów na dole i opis rozkazu
## wybranego oddziału. Dotknięcia poza przyciskami idą do mapy (cel i trasa); uchwyt końca
## strzałki (domyślnie donżon) przeciąga się na inny budynek bez ruszania kamery.
## Manewr otwiera listę wszystkich manewrów: dostępne z krótkim opisem, niedostępne wyszarzone
## z tym, czego brakuje (jednostka, epoka, badanie). Lista łapie wszystkie dotknięcia, a dotknięcie
## poza nią ją zamyka. Generał ataku (#31) przełącza się przyciskiem w lewym górnym rogu, pod górnym paskiem.

signal attack_requested
signal back_requested
## Plan albo wybór zmienił się (mapa ma się przerysować, a gra zapisać).
signal changed(message: String)
## Sam komunikat dla paska, bez zmiany planu (bez zapisu gry).
signal hint(message: String)

enum Target { NONE = -1, MANOEUVRE, START, RETREAT, CLEAR, ATTACK, BACK, GENERAL, SQUAD = 100, PICK = 200 }
const COLUMN: Array[int] = [Target.MANOEUVRE, Target.START, Target.RETREAT, Target.CLEAR, Target.ATTACK, Target.BACK]
const LABELS: Array[String] = ["Manewr", "Start", "Odwrót", "Wyczyść", "Atakuj", "Wróć"]
const GENERAL_LABEL := "Generał"
const SQUAD_TILE := Vector2(44, 16)
## Pasek opisu rozkazu nad oddziałami.
const INFO_H := 10
## Wiersz listy manewrów: nazwa i pod nią opis albo powód, dlaczego niedostępny.
const PICK_H := 18
const PICK_GAP := 2
## Najwięcej wierszy listy manewrów (więcej nie zmieści się nad opisem rozkazu).
const PICK_ROWS := 6

var planner: AttackPlanner
## Generałowie gracza (#31) i komendant obrony (nie dowodzi też atakiem); ustawia je main.gd.
var generals: Generals
var commander := -1
var content_left := float(Hud.CORNER_INSET)
var content_right := 320.0 - Hud.CORNER_INSET
var _pressed := Target.NONE
## Otwarta lista wyboru manewru.
var picking := false
## Dotknięcie zamknęło listę: jego puszczenie nie trafia już do mapy.
var _swallow_release := false
## Przeciąganie uchwytu końca strzałki wybranego oddziału (nie rusza kamery).
var _drag_end := false
## Palec, który trzyma uchwyt; dotknięcia innych palców w trakcie są połykane.
var _drag_index := -1


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _notification(what: int) -> void:
	if what == NOTIFICATION_VISIBILITY_CHANGED:
		picking = false
		_drag_end = false
		_drag_index = -1
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


## Przycisk generała (#31): lewy górny róg pod górnym paskiem (ten sam na ekranie Obrona).
static func general_rect(left: float) -> Rect2:
	return Rect2(Vector2(left, Hud.BAR_H + 4), Hud.BUTTON_SIZE)


## Napis przycisku generała ataku: krótka nazwa wybranego albo „Generał”.
static func general_label(g: Generals) -> String:
	if g == null or g.attack_kind < 0:
		return GENERAL_LABEL
	return Generals.SHORT_NAMES[g.attack_kind]


## Komunikat po zmianie generała ataku.
static func general_message(g: Generals) -> String:
	if g.roster.is_empty():
		return "Najpierw zwerbuj generała w Dworze"
	var gen := g.get_general(g.attack_kind)
	return "Generał ataku: %s" % Generals.label(gen) if gen != null else "Atak bez generała"


## Wiersz `i` listy manewrów: od lewej granicy treści do kolumny przycisków, od górnego paska.
static func pick_rect(right: float, left: float, i: int) -> Rect2:
	var w := right - Hud.BUTTON_SIZE.x - Hud.BUTTON_GAP - left
	return Rect2(left, Hud.BAR_H + 2 + i * (PICK_H + PICK_GAP), w, PICK_H)


## Pasek capacity łupu nad opisem rozkazu (#235).
static func capacity_rect(view: Vector2, left: float, right: float) -> Rect2:
	var info := info_rect(view, left, right)
	return Rect2(left, info.position.y - INFO_H - 1, right - left, INFO_H)


## Pasek capacity jest widoczny tylko przy zamkniętej liście manewrów: jej ostatni wiersz zajmuje
## to samo miejsce nad opisem rozkazu (review #252).
func capacity_visible() -> bool:
	return not picking


## Tekst capacity łupu armii, np. „Unosi łupu: 115 (wozy +100)”: ile surowców zabiorą wszyscy,
## jeśli wrócą (po bitwie liczą się tylko ocaleli).
static func capacity_text(army: Array) -> String:
	var text := "Unosi łupu: %d" % BattleResult.army_capacity(army)
	var wagons := BattleResult.wagon_capacity(army)
	if wagons > 0:
		text += " (wozy +%d)" % wagons
	return text


## Manewry na liście wyboru dla jednostki oddziału `unit`: Wóz ma sam Tabor (#235), inne jednostki
## wszystkie poza Taborem (najwyżej PICK_ROWS).
static func pick_list(unit: int) -> Array[int]:
	if unit == UnitTypes.Unit.WAGON:
		return [AttackPlan.Manoeuvre.CONVOY] as Array[int]
	var out: Array[int] = []
	for m in AttackPlan.MANOEUVRE_NAMES.size():
		if m != AttackPlan.Manoeuvre.CONVOY:
			out.append(m)
	return out


## Cała lista manewrów (wiersze z lukami między nimi): dotknięcie w niej nie zamyka listy.
static func list_rect(left: float, right: float, rows: int = PICK_ROWS) -> Rect2:
	var first := pick_rect(right, left, 0)
	return first.merge(pick_rect(right, left, maxi(1, rows) - 1))


## Wiersz pod punktem na otwartej liście z `rows` wierszami albo -1.
static func pick_at(p: Vector2, left: float, right: float, rows: int = PICK_ROWS) -> int:
	for i in rows:
		if pick_rect(right, left, i).has_point(p):
			return i
	return -1


## Manewry na otwartej liście wybranego oddziału.
func _picks() -> Array[int]:
	var o := planner.order() if planner != null else null
	return pick_list(planner.unit_of(o.squad) if o != null else -1)


## Cel pod punktem: przycisk kolumny, oddział (SQUAD + numer od 0) albo NONE.
static func target_at(p: Vector2, view: Vector2, left: float, right: float, squad_count: int) -> int:
	for i in COLUMN.size():
		if Hud.column_rect(right, i).has_point(p):
			return COLUMN[i]
	for i in squad_count:
		if squad_rect(view, left, i).has_point(p):
			return Target.SQUAD + i
	if general_rect(left).has_point(p):
		return Target.GENERAL
	return Target.NONE


func _input(event: InputEvent) -> void:
	if not visible or planner == null:
		return
	if _drag_end and event is InputEventScreenDrag:
		# drugi palec nie rusza kamery ani podglądu, dopóki uchwyt jest trzymany
		get_viewport().set_input_as_handled()
		var drag := event as InputEventScreenDrag
		if drag.index == _drag_index:
			_move_end_preview(drag.position)
		return
	var touch := event as InputEventScreenTouch
	if touch == null:
		return
	if _drag_end:
		get_viewport().set_input_as_handled()
		if not touch.pressed and touch.index == _drag_index:
			_finish_end_drag(touch.position)
		return
	var picks := _picks()
	if picking and list_rect(content_left, content_right, picks.size()).has_point(touch.position):
		# w obrębie listy (z lukami między wierszami): wiersz wybiera manewr, luka nic nie robi
		get_viewport().set_input_as_handled()
		var row := pick_at(touch.position, content_left, content_right, picks.size())
		var hit := Target.PICK + row if row >= 0 else Target.NONE
		if touch.pressed:
			_pressed = hit
			return
		var was_row := _pressed
		_pressed = Target.NONE
		if hit != Target.NONE and hit == was_row:
			choose(picks[row])
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
			hint.emit(AttackPlanner.HINT)
			return
	var t := target_at(touch.position, get_viewport_rect().size, content_left, content_right, planner.squads.size())
	if touch.pressed:
		_pressed = t
		if t != Target.NONE:
			get_viewport().set_input_as_handled()
			return
		# mapa: uchwyt końca strzałki zamiast kamery / punktu trasy
		var o := planner.order()
		if o != null and AttackPlanner.hit_end(o, planner.bot, _world_of(touch.position), _end_hit_world()):
			get_viewport().set_input_as_handled()
			_drag_end = true
			_drag_index = touch.index
			planner.drag_end_cell = AttackPlanner.end_cell(o, planner.bot)
			planner.queue_redraw()
			hint.emit("Przenieś koniec: upuść na budynek")
		return
	var was := _pressed
	_pressed = Target.NONE
	if was == Target.NONE:
		return
	get_viewport().set_input_as_handled()
	if t == was:
		activate(was)


## Połowa celu dotyku uchwytu w pikselach świata: na ekranie zawsze co najmniej 12×12 px
## logicznych, także przy oddaleniu 0,5×.
func _end_hit_world() -> float:
	var cam := get_viewport().get_camera_2d() as PanZoomCamera
	return AttackPlanner.END_HIT / PanZoomCamera.scale_of(cam.zoom_level) if cam != null else float(AttackPlanner.END_HIT)


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
	_drag_index = -1
	planner.drag_end_cell = AttackPlan.NO_TARGET
	var o := planner.order()
	if o == null or planner.bot == null:
		planner.queue_redraw()
		return
	var cell := Vector2i((_world_of(screen) / TerrainMap.CELL).floor())
	changed.emit(AttackPlanner.set_end(o, planner.bot.grid, cell, planner.intel))
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
		Target.GENERAL:
			if generals != null:
				generals.next_attack(commander)
				changed.emit(general_message(generals))
			return
	if o == null:
		return
	match t:
		Target.MANOEUVRE:
			picking = not picking
			hint.emit("Oddział %d: wybierz manewr" % o.squad if picking else AttackPlanner.HINT)
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
		hint.emit("%s: %s" % [AttackPlan.MANOEUVRE_NAMES[m], why])
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
	if not picking:
		Hud.paint_button(self, general_rect(content_left), general_label(generals), _pressed == Target.GENERAL, false)
	var o := planner.order()
	if o != null:
		var info := info_rect(view, content_left, content_right)
		draw_rect(info, Color(Palette.SHADOW, 0.8))
		var text := AttackPlanner.describe(o)
		PixelFont.draw_text(self, info.position + Vector2(2, 1), "%d. %s" % [o.squad, text[0]], Palette.INK)
		PixelFont.draw_right(self, info.end.x - 2, info.position.y + 1, text[1], Palette.THATCH[2])
	if capacity_visible():
		var cap := capacity_rect(view, content_left, content_right)
		var cap_text := capacity_text(planner.squads)
		draw_rect(Rect2(cap.position, Vector2(PixelFont.text_width(cap_text) + 4, cap.size.y)), Color(Palette.SHADOW, 0.8))
		PixelFont.draw_text(self, cap.position + Vector2(2, 1), cap_text, Palette.THATCH[2])
	for i in planner.squads.size():
		var sq: Array = planner.squads[i]
		var r := squad_rect(view, content_left, i)
		Hud.paint_button(self, r, "", _pressed == Target.SQUAD + i or planner.selected == i + 1, false)
		if planner.selected == i + 1:
			CastleView.draw_frame(self, Rect2i(r), Palette.INK)
		var unit := int(sq[0])
		var at := r.position + Vector2(3, 5)
		if PixelIcons.unit_region(unit).has_area():
			PixelIcons.draw_unit_badge(self, at, unit)
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
	var picks := _picks()
	for row in picks.size():
		var m := picks[row]
		var r := pick_rect(content_right, content_left, row)
		var why := missing_for(m)
		var chosen := o.manoeuvre == m
		var col: Color = Palette.WOOD[2] if chosen or _pressed == Target.PICK + row else Palette.WOOD[1]
		draw_rect(r, col if why.is_empty() else Color(Palette.SHADOW, 0.9))
		if chosen:
			CastleView.draw_frame(self, Rect2i(r), Palette.INK)
		var name_col: Color = Palette.INK if why.is_empty() else Palette.WOOD[2]
		PixelFont.draw_text(self, r.position + Vector2(3, 1), AttackPlan.MANOEUVRE_NAMES[m], name_col)
		var line := AttackPlan.MANOEUVRE_DESC[m] if why.is_empty() else reason_line(m, planner.unit_of(o.squad), why)
		PixelFont.draw_text(self, r.position + Vector2(3, 9), line, Palette.THATCH[2] if why.is_empty() else Palette.ACCENT)
