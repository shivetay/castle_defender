class_name StartMenu
extends Node2D
## Ekran startowy (#177) na przyciemnionym zamku: Kontynuuj (gdy jest zapis), Nowa gra (przy zapisie
## z potwierdzeniem) i Ustawienia (język i dźwięk na razie jako zapowiedź, #63 i #64). Gra działa
## w całości offline z zapisem lokalnym, więc menu nie łączy się z siecią. Panel sam obsługuje dotyk,
## jak inne ekrany na całą mapę, więc nic nie trafia do kamery ani do HUD.

signal continue_pressed
signal new_game_requested

enum Screen { MAIN, CONFIRM, SETTINGS }
enum Target { NONE = -1, CONTINUE, NEW_GAME, SETTINGS, CONFIRM_YES, CONFIRM_NO, LANGUAGE, SOUND, BACK }

const TITLE := "Castle Defender"
const SUBTITLE := "Od grodu do twierdzy"
const BUTTON_SIZE := Vector2(96, 16)
const GAP := 4
const FIRST_Y := 64
## Stopka (offline i wersja) zaczyna się tyle pikseli nad dolną krawędzią.
const FOOTER_Y := 38
const CONFIRM_TEXT := "Zacząć od nowa? Obecny zapis zniknie."
const LABELS := {
	Target.CONTINUE: "Kontynuuj",
	Target.NEW_GAME: "Nowa gra",
	Target.SETTINGS: "Ustawienia",
	Target.CONFIRM_YES: "Tak, od nowa",
	Target.CONFIRM_NO: "Nie",
	Target.SOUND: "Dźwięk: wkrótce",
	Target.BACK: "Wróć",
}
## Języki do wyboru (#64). Na razie gra mówi tylko po polsku, angielski to zapowiedź.
const LANGUAGES: Array[String] = ["polski", "English"]
const ENGLISH_LATER := "English: wkrótce, na razie po polsku"
const OFFLINE_NOTE := "Gra offline, zapis na telefonie"

## Czy jest zapis lokalny: wtedy jest Kontynuuj, a Nowa gra pyta o potwierdzenie.
var has_save := false
var screen := Screen.MAIN
var language := 0
## Krótka podpowiedź pod przyciskami (np. o języku angielskim).
var hint := ""

var _pressed: int = Target.NONE


func open() -> void:
	visible = true
	screen = Screen.MAIN
	hint = ""
	_pressed = Target.NONE
	queue_redraw()


func close() -> void:
	visible = false


## Przyciski ekranu od góry.
static func targets(s: int, save: bool) -> Array[int]:
	match s:
		Screen.CONFIRM:
			return [Target.CONFIRM_YES, Target.CONFIRM_NO] as Array[int]
		Screen.SETTINGS:
			return [Target.LANGUAGE, Target.SOUND, Target.BACK] as Array[int]
	if save:
		return [Target.CONTINUE, Target.NEW_GAME, Target.SETTINGS] as Array[int]
	return [Target.NEW_GAME, Target.SETTINGS] as Array[int]


## Prostokąty przycisków: wyśrodkowane w poziomie, jeden pod drugim (całe piksele).
static func button_rects(view: Vector2, s: int, save: bool) -> Array[Rect2]:
	var out: Array[Rect2] = []
	var x := floorf((view.x - BUTTON_SIZE.x) / 2.0)
	for i in targets(s, save).size():
		out.append(Rect2(Vector2(x, FIRST_Y + i * (BUTTON_SIZE.y + GAP)), BUTTON_SIZE))
	return out


static func target_at(p: Vector2, view: Vector2, s: int, save: bool) -> int:
	var rects := button_rects(view, s, save)
	for i in rects.size():
		if rects[i].has_point(p):
			return targets(s, save)[i]
	return Target.NONE


func label(t: int) -> String:
	if t == Target.LANGUAGE:
		return "Język: %s" % LANGUAGES[language]
	return LABELS.get(t, "")


## Wersja gry z project.godot, np. „Wersja 0.3.0”.
static func version_text() -> String:
	return "Wersja %s" % str(ProjectSettings.get_setting("application/config/version", "?"))


## Wynik dotknięcia przycisku `t`: przełącza ekrany albo wysyła sygnał do gry.
func activate(t: int) -> void:
	hint = ""
	match t:
		Target.CONTINUE:
			continue_pressed.emit()
		Target.NEW_GAME:
			if has_save:
				screen = Screen.CONFIRM
			else:
				new_game_requested.emit()
		Target.CONFIRM_YES:
			new_game_requested.emit()
		Target.CONFIRM_NO, Target.BACK:
			screen = Screen.MAIN
		Target.SETTINGS:
			screen = Screen.SETTINGS
		Target.LANGUAGE:
			language = (language + 1) % LANGUAGES.size()
			if language != 0:
				hint = ENGLISH_LATER
		Target.SOUND:
			hint = "Dźwięk dojdzie w kolejnych wersjach"
	queue_redraw()


# --- Dotyk -------------------------------------------------------------------------------------

func _input(event: InputEvent) -> void:
	if not visible:
		return
	if event is InputEventScreenDrag:
		get_viewport().set_input_as_handled()
		return
	var touch := event as InputEventScreenTouch
	if touch == null:
		return
	get_viewport().set_input_as_handled()
	var t := target_at(touch.position, get_viewport_rect().size, screen, has_save)
	if touch.pressed:
		_pressed = t
		queue_redraw()
		return
	var was := _pressed
	_pressed = Target.NONE
	queue_redraw()
	if was != Target.NONE and t == was:
		activate(was)


# --- Rysowanie ---------------------------------------------------------------------------------

func _draw() -> void:
	var view := get_viewport_rect().size
	draw_rect(Rect2(Vector2.ZERO, view), Color(Palette.SHADOW, 0.8))
	var title_box := Rect2(0, 22, view.x, 10)
	PixelFont.draw_centered(self, title_box, TITLE.to_upper(), Palette.THATCH[2])
	draw_rect(Rect2(floorf(view.x / 2.0) - 30, 34, 60, 1), Palette.WOOD[2])
	var sub := SUBTITLE
	if screen == Screen.CONFIRM:
		sub = CONFIRM_TEXT
	elif screen == Screen.SETTINGS:
		sub = "Ustawienia"
	PixelFont.draw_centered(self, Rect2(0, 42, view.x, 10), sub, Palette.INK)
	var rects := button_rects(view, screen, has_save)
	var ts := targets(screen, has_save)
	for i in rects.size():
		Hud.paint_button(self, rects[i], label(ts[i]), _pressed == ts[i], ts[i] == Target.SOUND)
	if not hint.is_empty():
		PixelFont.draw_centered(self, Rect2(0, rects[-1].end.y + 6, view.x, 10), hint, Palette.THATCH[2])
	# stopka nad dolnym paskiem HUD-u, który prześwituje przez przyciemnienie
	PixelFont.draw_centered(self, Rect2(0, view.y - FOOTER_Y, view.x, 10), OFFLINE_NOTE, Palette.WOOD[3])
	PixelFont.draw_centered(self, Rect2(0, view.y - FOOTER_Y + 10, view.x, 10), version_text(), Palette.WOOD[3])
