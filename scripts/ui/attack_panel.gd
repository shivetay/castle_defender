class_name AttackPanel
extends Control
## Przyciski planowania ataku (#17) nad mapą celu (AttackPlanner): kolumna przy prawej krawędzi
## (Manewr, Start, Odwrót, Wyczyść, Atakuj, Wróć), pasek oddziałów na dole i opis rozkazu
## wybranego oddziału. Dotknięcia poza przyciskami idą do mapy (cel i trasa).

signal attack_requested
signal back_requested
## Plan albo wybór zmienił się (mapa ma się przerysować, a gra zapisać).
signal changed(message: String)

enum Target { NONE = -1, MANOEUVRE, START, RETREAT, CLEAR, ATTACK, BACK, SQUAD = 100 }
const COLUMN: Array[int] = [Target.MANOEUVRE, Target.START, Target.RETREAT, Target.CLEAR, Target.ATTACK, Target.BACK]
const LABELS: Array[String] = ["Manewr", "Start", "Odwrót", "Wyczyść", "Atakuj", "Wróć"]
const SQUAD_TILE := Vector2(44, 16)
## Pasek opisu rozkazu nad oddziałami.
const INFO_H := 10

var planner: AttackPlanner
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


static func squad_rect(view: Vector2, left: float, i: int) -> Rect2:
	return Rect2(Vector2(left + i * (SQUAD_TILE.x + Hud.BUTTON_GAP), Hud.row_y(view)), SQUAD_TILE)


static func info_rect(view: Vector2, left: float, right: float) -> Rect2:
	return Rect2(left, Hud.row_y(view) - INFO_H - 2, right - left, INFO_H)


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
	var touch := event as InputEventScreenTouch
	if touch == null:
		return
	var t := target_at(touch.position, get_viewport_rect().size, content_left, content_right, planner.squads.size())
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
	var o := planner.order()
	if t >= Target.SQUAD:
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
			o.manoeuvre = AttackPlanner.next_manoeuvre(o.manoeuvre, planner.age)
			changed.emit(AttackPlan.MANOEUVRE_NAMES[o.manoeuvre])
		Target.START:
			AttackPlanner.next_start(o, planner.squads.size())
			changed.emit("Start: %s" % AttackPlanner.start_text(o))
		Target.RETREAT:
			o.retreat_percent = AttackPlanner.next_retreat(o.retreat_percent)
			changed.emit("Odwrót: %s" % AttackPlanner.retreat_text(o.retreat_percent))
		Target.CLEAR:
			AttackPlanner.clear(o)
			changed.emit("Cel i trasa wyczyszczone")


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
