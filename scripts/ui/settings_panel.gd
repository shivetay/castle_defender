class_name SettingsPanel
extends Node2D
## Ustawienia (#177) pod ikoną zębatki w kolumnie HUD-u, na przyciemnionym zamku. Gra startuje od razu
## w zamku (to gra PvP, bez ekranu startowego), a PvE jest w Strażnicy. Tu jest język (polski, angielski
## jako zapowiedź #64), dźwięk (zapowiedź), Zacznij od nowa z potwierdzeniem i wersja gry. Gra działa
## offline z zapisem lokalnym. Panel sam obsługuje dotyk, więc nic nie trafia do kamery ani do HUD.

signal closed
signal new_game_requested

enum Screen { SETTINGS, CONFIRM }
enum Target { NONE = -1, LANGUAGE, SOUND, NEW_GAME, CLOSE, CONFIRM_YES, CONFIRM_NO }

const TITLE := "Ustawienia"
const BUTTON_SIZE := Vector2(96, 16)
const GAP := 4
const FIRST_Y := 44
## Stopka (offline i wersja) zaczyna się tyle pikseli nad dolną krawędzią.
const FOOTER_Y := 38
const CONFIRM_TEXT := "Zacząć od nowa? Obecny zapis zniknie."
const LABELS := {
	Target.SOUND: "Dźwięk: wkrótce",
	Target.NEW_GAME: "Zacznij od nowa",
	Target.CLOSE: "Zamknij",
	Target.CONFIRM_YES: "Tak, od nowa",
	Target.CONFIRM_NO: "Nie",
}
## Języki do wyboru (#64). Na razie gra mówi tylko po polsku, angielski to zapowiedź.
const LANGUAGES: Array[String] = ["polski", "English"]
const ENGLISH_LATER := "English: wkrótce, na razie po polsku"
const SOUND_LATER := "Dźwięk dojdzie w kolejnych wersjach"
const OFFLINE_NOTE := "Gra offline, zapis na telefonie"

var screen := Screen.SETTINGS
var language := 0
## Krótka podpowiedź pod przyciskami (np. o języku angielskim).
var hint := ""

var _pressed: int = Target.NONE


func open() -> void:
	visible = true
	screen = Screen.SETTINGS
	hint = ""
	_pressed = Target.NONE
	queue_redraw()


func close() -> void:
	visible = false
	closed.emit()


## Przyciski ekranu od góry.
static func targets(s: int) -> Array[int]:
	if s == Screen.CONFIRM:
		return [Target.CONFIRM_YES, Target.CONFIRM_NO] as Array[int]
	return [Target.LANGUAGE, Target.SOUND, Target.NEW_GAME, Target.CLOSE] as Array[int]


## Prostokąty przycisków: wyśrodkowane w poziomie, jeden pod drugim (całe piksele).
static func button_rects(view: Vector2, s: int) -> Array[Rect2]:
	var out: Array[Rect2] = []
	var x := floorf((view.x - BUTTON_SIZE.x) / 2.0)
	for i in targets(s).size():
		out.append(Rect2(Vector2(x, FIRST_Y + i * (BUTTON_SIZE.y + GAP)), BUTTON_SIZE))
	return out


static func target_at(p: Vector2, view: Vector2, s: int) -> int:
	var rects := button_rects(view, s)
	for i in rects.size():
		if rects[i].has_point(p):
			return targets(s)[i]
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
		Target.LANGUAGE:
			language = (language + 1) % LANGUAGES.size()
			if language != 0:
				hint = ENGLISH_LATER
		Target.SOUND:
			hint = SOUND_LATER
		Target.NEW_GAME:
			screen = Screen.CONFIRM
		Target.CONFIRM_YES:
			new_game_requested.emit()
		Target.CONFIRM_NO:
			screen = Screen.SETTINGS
		Target.CLOSE:
			close()
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
	var t := target_at(touch.position, get_viewport_rect().size, screen)
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
	var head := TITLE.to_upper() if screen == Screen.SETTINGS else CONFIRM_TEXT
	PixelFont.draw_centered(self, Rect2(0, 24, view.x, 10), head, Palette.THATCH[2])
	draw_rect(Rect2(floorf(view.x / 2.0) - 30, 36, 60, 1), Palette.WOOD[2])
	var rects := button_rects(view, screen)
	var ts := targets(screen)
	for i in rects.size():
		Hud.paint_button(self, rects[i], label(ts[i]), _pressed == ts[i], ts[i] == Target.SOUND)
	if not hint.is_empty():
		PixelFont.draw_centered(self, Rect2(0, rects[-1].end.y + 6, view.x, 10), hint, Palette.THATCH[2])
	# stopka nad dolnym paskiem HUD-u, który prześwituje przez przyciemnienie
	PixelFont.draw_centered(self, Rect2(0, view.y - FOOTER_Y, view.x, 10), OFFLINE_NOTE, Palette.WOOD[3])
	PixelFont.draw_centered(self, Rect2(0, view.y - FOOTER_Y + 10, view.x, 10), version_text(), Palette.WOOD[3])
