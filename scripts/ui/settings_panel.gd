class_name SettingsPanel
extends Node2D
## Ustawienia (#177) pod ikoną zębatki w kolumnie HUD-u, na przyciemnionym zamku. Gra startuje od razu
## w zamku (ekran tytułowy #360 pokazuje się tylko przy uruchomieniu), a PvE jest w Strażnicy. Tu jest język (polski, angielski
## jako zapowiedź #64), dźwięk (zapowiedź), samouczek (#251: wyłączenie z potwierdzeniem, włączenie od razu),
## Zacznij od nowa z potwierdzeniem, link do Discorda (#360) i wersja gry. Gra działa offline z zapisem lokalnym. Panel sam obsługuje dotyk, więc nic nie trafia do kamery ani do HUD.

signal closed
signal new_game_requested
## Gracz włączył albo (po potwierdzeniu) wyłączył samouczek (#251).
signal tutorial_changed(on: bool)

enum Screen { SETTINGS, CONFIRM, CONFIRM_TUTORIAL }
enum Target { NONE = -1, LANGUAGE, SOUND, NEW_GAME, CLOSE, CONFIRM_YES, CONFIRM_NO, TUTORIAL, DISCORD }

const TITLE := "Ustawienia"
## Przyciski 96×13 z odstępem 2 px, żeby 6 przycisków (z Discordem, #360) zmieściło się nad
## podpowiedzią i stopką na 180 px; wciąż ponad minimum 12×12 px z CLAUDE.md.
const BUTTON_SIZE := Vector2(96, 13)
const GAP := 2
const FIRST_Y := 34
## Nagłówek i kreska pod nim.
const HEAD_Y := 20
const RULE_Y := 31
## Stopka (offline i wersja) zaczyna się tyle pikseli nad dolną krawędzią.
const FOOTER_Y := 38
const CONFIRM_TEXT := "Zacząć od nowa? Obecny zapis zniknie."
const TUTORIAL_CONFIRM_TEXT := TutorialPrompt.QUESTION
const TUTORIAL_ON := "Samouczek: wł."
const TUTORIAL_OFF := "Samouczek: wył."
const TUTORIAL_YES := "Tak, wyłącz"
const LABELS := {
	Target.SOUND: "Dźwięk: wkrótce",
	Target.NEW_GAME: "Zacznij od nowa",
	Target.DISCORD: CommunityLink.LABEL,
	Target.CLOSE: "Zamknij",
	Target.CONFIRM_YES: "Tak, od nowa",
	Target.CONFIRM_NO: "Nie",
}
## Języki do wyboru (#64). Na razie gra mówi tylko po polsku, angielski to zapowiedź.
const LANGUAGES: Array[String] = ["polski", "English"]
const ENGLISH_LATER := "English: wkrótce, na razie po polsku"
const SOUND_LATER := "Dźwięk dojdzie w kolejnych wersjach"
const OFFLINE_NOTE := "Gra offline, zapis na telefonie"
## Stan połączenia z serwerem (#22) według SupabaseClient.State: DISABLED, CONNECTING, ONLINE, OFFLINE.
const NET_NOTES: Array[String] = [
	OFFLINE_NOTE,
	"Łączenie z serwerem...",
	"Połączono z serwerem",
	"Brak sieci, gra offline",
]

var screen := Screen.SETTINGS
var language := 0
## Czy samouczek jest włączony (ustawia go main.gd z profilu).
var tutorial_on := true
## Krótka podpowiedź pod przyciskami (np. o języku angielskim).
var hint := ""
## Stan połączenia z serwerem (SupabaseClient.State); ustawia go main.gd.
var net_state := 0:
	set(v):
		net_state = v
		queue_redraw()

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
	if s == Screen.CONFIRM or s == Screen.CONFIRM_TUTORIAL:
		return [Target.CONFIRM_YES, Target.CONFIRM_NO] as Array[int]
	return [Target.LANGUAGE, Target.SOUND, Target.TUTORIAL, Target.DISCORD, Target.NEW_GAME, Target.CLOSE] as Array[int]


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
	if t == Target.TUTORIAL:
		return TUTORIAL_ON if tutorial_on else TUTORIAL_OFF
	if t == Target.CONFIRM_YES and screen == Screen.CONFIRM_TUTORIAL:
		return TUTORIAL_YES
	return LABELS.get(t, "")


## Nagłówek ekranu: tytuł ustawień albo pytanie potwierdzenia.
func head() -> String:
	match screen:
		Screen.CONFIRM:
			return CONFIRM_TEXT
		Screen.CONFIRM_TUTORIAL:
			return TUTORIAL_CONFIRM_TEXT
	return TITLE.to_upper()


## Wersja gry z project.godot, np. „Wersja 0.3.0”.
static func net_note(s: int) -> String:
	return NET_NOTES[clampi(s, 0, NET_NOTES.size() - 1)]


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
		Target.DISCORD:
			hint = CommunityLink.open_discord()
		Target.NEW_GAME:
			screen = Screen.CONFIRM
		Target.TUTORIAL:
			if tutorial_on:
				screen = Screen.CONFIRM_TUTORIAL
			else:
				tutorial_on = true
				tutorial_changed.emit(true)
		Target.CONFIRM_YES:
			if screen == Screen.CONFIRM_TUTORIAL:
				tutorial_on = false
				screen = Screen.SETTINGS
				tutorial_changed.emit(false)
			else:
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
	draw_rect(Hud.backdrop_rect(view), Color(Palette.SHADOW, 0.8))
	PixelFont.draw_centered(self, Rect2(0, HEAD_Y, view.x, 10), head(), Palette.THATCH[2])
	draw_rect(Rect2(floorf(view.x / 2.0) - 30, RULE_Y, 60, 1), Palette.WOOD[2])
	var rects := button_rects(view, screen)
	var ts := targets(screen)
	for i in rects.size():
		Hud.paint_button(self, rects[i], label(ts[i]), _pressed == ts[i], ts[i] == Target.SOUND)
	if not hint.is_empty():
		PixelFont.draw_centered(self, Rect2(0, rects[-1].end.y + 6, view.x, 10), hint, Palette.THATCH[2])
	# stopka nad dolnym paskiem HUD-u, który prześwituje przez przyciemnienie
	PixelFont.draw_centered(self, Rect2(0, view.y - FOOTER_Y, view.x, 10), net_note(net_state), Palette.WOOD[3])
	PixelFont.draw_centered(self, Rect2(0, view.y - FOOTER_Y + 10, view.x, 10), version_text(), Palette.WOOD[3])
