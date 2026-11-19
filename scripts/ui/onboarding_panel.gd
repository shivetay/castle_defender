class_name OnboardingPanel
extends Node2D
## Onboarding (#228): przy pierwszym uruchomieniu gracz wpisuje imię i nazwę zamku, a zamek dostaje
## domyślnego władcę bez premii (Rulers.DEFAULT). Dopóki tożsamości nie ma, panel przykrywa zamek
## i łapie każdy dotyk, a zamek nie idzie na serwer (main.gd). Tekst wpisuje się klawiaturą
## systemową: dotknięcie pola daje fokus ukrytej kontrolce LineEdit, która odbiera klawiaturę
## ekranową Androida, a tekst rysuje PixelFont. Zacznij sprawdza obie nazwy (PlayerProfile).

signal finished(identity: PlayerProfile.Identity)

enum Field { NONE = -1, PLAYER, CASTLE }
enum Target { NONE = -1, PLAYER, CASTLE, START }

const TITLE := "Witaj, władco"
const SUBTITLE := "Nazwij siebie i swój gród"
const FIELD_LABELS := {Field.PLAYER: "Imię", Field.CASTLE: "Zamek"}
const PLACEHOLDER := "dotknij, by wpisać"
const START_LABEL := "Zacznij"
const RULER_LINE := "Władca: %s, bez premii"

## Pola: etykieta po lewej, ramka z tekstem po prawej; całość wyśrodkowana (całe piksele).
const LABEL_W := 32
const FIELD_SIZE := Vector2(120, 14)
const FIELD_Y: Array[int] = [44, 62]
const RULER_Y := 82
const HINT_Y := 94
const BUTTON_SIZE := Vector2(96, 16)
const BUTTON_Y := 108

var player_name := ""
var castle_name := ""
## Pole, do którego idzie klawiatura (Field.NONE, gdy żadne).
var focused: int = Field.NONE
## Błąd walidacji albo podpowiedź pod władcą.
var hint := ""

var _input_box: LineEdit
var _pressed: int = Target.NONE


func _ready() -> void:
	# ukryta kontrolka tylko odbiera tekst; widać ją przez PixelFont, nie przez jej własny font
	_input_box = LineEdit.new()
	_input_box.modulate.a = 0.0
	_input_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_input_box.context_menu_enabled = false
	_input_box.text_changed.connect(_on_text_changed)
	_input_box.text_submitted.connect(_on_text_submitted)
	add_child(_input_box)


func open() -> void:
	visible = true
	hint = ""
	_pressed = Target.NONE
	queue_redraw()


## Ramka pola `f` na ekranie o rozmiarze `view`.
static func field_rect(view: Vector2, f: int) -> Rect2:
	var x := floorf((view.x - LABEL_W - FIELD_SIZE.x) / 2.0) + LABEL_W
	return Rect2(Vector2(x, FIELD_Y[f]), FIELD_SIZE)


static func button_rect(view: Vector2) -> Rect2:
	return Rect2(Vector2(floorf((view.x - BUTTON_SIZE.x) / 2.0), BUTTON_Y), BUTTON_SIZE)


static func target_at(p: Vector2, view: Vector2) -> int:
	if field_rect(view, Field.PLAYER).has_point(p):
		return Target.PLAYER
	if field_rect(view, Field.CASTLE).has_point(p):
		return Target.CASTLE
	if button_rect(view).has_point(p):
		return Target.START
	return Target.NONE


static func max_length(f: int) -> int:
	return PlayerProfile.NAME_MAX if f == Field.PLAYER else PlayerProfile.CASTLE_MAX


## Tekst z klawiatury bez niedozwolonych znaków, przycięty do limitu pola (spacje na brzegach
## zostają, żeby dało się wpisać dwa słowa; przycina je dopiero zapis).
static func filter_text(text: String, f: int) -> String:
	var out := ""
	for ch in text:
		if PlayerProfile.is_allowed_char(ch):
			out += ch
	return out.substr(0, max_length(f))


func field_text(f: int) -> String:
	return player_name if f == Field.PLAYER else castle_name


func set_field(f: int, text: String) -> void:
	var clean := filter_text(text, f)
	if f == Field.PLAYER:
		player_name = clean
	else:
		castle_name = clean
	hint = ""
	queue_redraw()


## Tożsamość z wpisanych pól i domyślnego władcy.
func identity() -> PlayerProfile.Identity:
	var id := PlayerProfile.Identity.new()
	id.player_name = PlayerProfile.clean_name(player_name)
	id.castle_name = PlayerProfile.clean_name(castle_name)
	id.ruler = Rulers.DEFAULT
	return id


## Pierwszy błąd walidacji (imię przed zamkiem) albo pusty tekst, gdy obie nazwy są dobre.
func validation_error() -> String:
	var err := PlayerProfile.check_name(player_name, PlayerProfile.NAME_MIN, PlayerProfile.NAME_MAX)
	if err != PlayerProfile.NameError.OK:
		return PlayerProfile.error_text(FIELD_LABELS[Field.PLAYER], err, PlayerProfile.NAME_MIN, PlayerProfile.NAME_MAX)
	err = PlayerProfile.check_name(castle_name, PlayerProfile.CASTLE_MIN, PlayerProfile.CASTLE_MAX)
	if err != PlayerProfile.NameError.OK:
		return PlayerProfile.error_text(FIELD_LABELS[Field.CASTLE], err, PlayerProfile.CASTLE_MIN,
				PlayerProfile.CASTLE_MAX)
	return ""


## Zacznij: przy błędzie pokazuje go i zostaje, przy dobrych nazwach zamyka się z tożsamością.
func submit() -> bool:
	hint = validation_error()
	queue_redraw()
	if not hint.is_empty():
		return false
	focus(Field.NONE)
	visible = false
	finished.emit(identity())
	return true


## Przenosi klawiaturę do pola `f` (Field.NONE chowa klawiaturę).
func focus(f: int) -> void:
	focused = f
	queue_redraw()
	if _input_box == null or not is_inside_tree():
		return
	if f == Field.NONE:
		_input_box.release_focus()
		DisplayServer.virtual_keyboard_hide()
		return
	_input_box.max_length = max_length(f)
	_input_box.text = field_text(f)
	_input_box.caret_column = _input_box.text.length()
	var r := field_rect(get_viewport_rect().size, f)
	_input_box.position = r.position
	_input_box.size = r.size
	_input_box.grab_focus()
	_input_box.edit()


func activate(t: int) -> void:
	match t:
		Target.PLAYER:
			focus(Field.PLAYER)
		Target.CASTLE:
			focus(Field.CASTLE)
		Target.START:
			submit()
		_:
			focus(Field.NONE)


func _on_text_changed(text: String) -> void:
	if focused == Field.NONE:
		return
	set_field(focused, text)
	var clean := field_text(focused)
	if clean != text:
		_input_box.text = clean
		_input_box.caret_column = clean.length()


## Enter na klawiaturze: z imienia przechodzi do zamku, z zamku próbuje zacząć.
func _on_text_submitted(_text: String) -> void:
	if focused == Field.PLAYER:
		focus(Field.CASTLE)
	else:
		submit()


# --- Dotyk -------------------------------------------------------------------------------------

func _input(event: InputEvent) -> void:
	if not visible:
		return
	if event is InputEventScreenDrag:
		get_viewport().set_input_as_handled()
		return
	var touch := event as InputEventScreenTouch
	if touch == null:
		return  # klawiatura idzie dalej, do ukrytego LineEdit
	get_viewport().set_input_as_handled()
	var t := target_at(touch.position, get_viewport_rect().size)
	if touch.pressed:
		_pressed = t
		queue_redraw()
		return
	var was := _pressed
	_pressed = Target.NONE
	queue_redraw()
	if t == was:
		activate(was)


# --- Rysowanie ---------------------------------------------------------------------------------

func _draw() -> void:
	var view := get_viewport_rect().size
	draw_rect(Rect2(Vector2.ZERO, view), Color(Palette.SHADOW, 0.9))
	PixelFont.draw_centered(self, Rect2(0, 14, view.x, 10), TITLE.to_upper(), Palette.THATCH[2])
	PixelFont.draw_centered(self, Rect2(0, 25, view.x, 10), SUBTITLE, Palette.WOOD[3])
	draw_rect(Rect2(floorf(view.x / 2.0) - 30, 38, 60, 1), Palette.WOOD[2])
	for f: int in [Field.PLAYER, Field.CASTLE]:
		_draw_field(view, f)
	PixelFont.draw_centered(self, Rect2(0, RULER_Y, view.x, 10),
			RULER_LINE % Rulers.ruler_name(Rulers.DEFAULT), Palette.WOOD[3])
	if not hint.is_empty():
		PixelFont.draw_centered(self, Rect2(0, HINT_Y, view.x, 10), hint, Palette.ACCENT)
	Hud.paint_button(self, button_rect(view), START_LABEL, _pressed == Target.START, false)


func _draw_field(view: Vector2, f: int) -> void:
	var r := field_rect(view, f)
	PixelFont.draw_text(self, Vector2(r.position.x - LABEL_W, r.position.y + 3), FIELD_LABELS[f], Palette.INK)
	var active := focused == f
	draw_rect(r, Palette.WOOD[0])
	# obwódka 1 px z pełnych prostokątów (draw_rect bez wypełnienia rysuje linie w połowie piksela)
	var edge: Color = Palette.THATCH[2] if active else Palette.WOOD[2]
	draw_rect(Rect2(r.position, Vector2(r.size.x, 1)), edge)
	draw_rect(Rect2(r.position + Vector2(0, r.size.y - 1), Vector2(r.size.x, 1)), edge)
	draw_rect(Rect2(r.position, Vector2(1, r.size.y)), edge)
	draw_rect(Rect2(r.position + Vector2(r.size.x - 1, 0), Vector2(1, r.size.y)), edge)
	var text := field_text(f)
	var at := Vector2(r.position.x + 3, r.position.y + 3)
	if text.is_empty() and not active:
		PixelFont.draw_text(self, at, PLACEHOLDER, Palette.WOOD[2])
		return
	PixelFont.draw_text(self, at, text, Palette.INK)
	if active:
		var caret_x := at.x + PixelFont.text_width(text) + (1.0 if text.is_empty() else 2.0)
		draw_rect(Rect2(caret_x, at.y + PixelFont.CAP_TOP, 1, 5), Palette.THATCH[2])
