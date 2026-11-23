class_name TutorialHints
extends RefCounted
## Mini-samouczek UI (#251): przy pierwszych celach TutorialGoals (Postaw Koszary, Wyszkol 6 żołnierzy)
## podświetla element, w który trzeba teraz dotknąć: Buduj → zakładka Wojsko → kafelek Koszar →
## Postaw → mapa → Gotowe, potem Wojsko → Chłop → Szkol. Krok wynika wyłącznie z bieżącego celu i stanu
## interfejsu (Ui), więc nie trzeba go zapisywać, a po spełnieniu celu wskazanie samo przechodzi dalej.
## Dalsze cele mają tylko tekst na pasku celu (#185). Nic niczego nie blokuje: to tylko podpowiedź.
##
## Gracz może wyłączyć samouczek (okno TutorialPrompt po onboardingu albo Ustawienia). Wybór i to, że
## samouczek został ukończony, trzyma profil gracza (PlayerProfile.read_tutorial), więc Zacznij od nowa
## nie pokazuje samouczka komuś, kto już raz przeszedł 5 fal.

## Krok wskazania: który element podświetlić.
enum Step {
	NONE,
	HUD_BUILD,
	BUILD_TAB,
	BUILD_TILE,
	BUILD_PLACE,
	MAP,
	HUD_DONE,
	HUD_ARMY,
	CARD_CLOSE,
	CARD_RECRUIT,
	RECRUIT_TILE,
	RECRUIT_TRAIN,
	RECRUIT_CLOSE,
	WAIT_BUILD,
	WAIT_TRAIN,
}
## Gdzie leży podświetlany element.
enum Where { NONE, HUD, BUILD_PANEL, RECRUIT_PANEL }
## Stan samouczka w profilu: jeszcze nie zapytano, włączony, wyłączony przez gracza, ukończony.
enum State { ASK, ON, OFF, DONE }

const BARRACKS := BuildingTypes.Kind.BARRACKS
const PEASANT := UnitTypes.Unit.PEASANT
## Cele z GOALS, które mają wskazania (indeksy): Postaw Koszary, Wyszkol 6 żołnierzy.
const GOAL_BARRACKS := 0
const GOAL_ARMY := 1
## Zakładka Wojsko w panelu budowy.
const ARMY_CATEGORY := 3
## Puls ramki: pół okresu w ms.
const PULSE_MS := 400

## Podpowiedzi zamiast tekstu celu w krokach, w których nie ma przycisku do podświetlenia.
const MAP_TIP := "Dotknij wolnego pola na mapie"
const WAIT_BUILD_TIP := "Koszary się budują, poczekaj"
const WAIT_TRAIN_TIP := "Żołnierze się szkolą, poczekaj"


## Stan interfejsu potrzebny do wyboru kroku (ustawia go main.gd co klatkę, a testy ręcznie).
class Ui:
	extends RefCounted
	## Otwarty ekran na całą mapę: panel budowy, ekran Wojsko albo inny (wtedy bez wskazań).
	var build_open := false
	var recruit_open := false
	var other_open := false
	var build_category := 0
	var build_selected := 0
	## Tryb stawiania na mapie i wybrany budynek.
	var building := false
	var selected_kind := 0
	## Karta budynku i czy ma przycisk Szkol (budynek rekrutacji).
	var card_open := false
	var card_recruit := false
	## Ekran Wojsko: jednostki w bieżącym trybie i wybrana.
	var recruit_units: Array[int] = []
	var recruit_selected := -1
	## Czy w zamku stoi (albo czeka w kolejce) Koszary.
	var barracks_placed := false
	## Armia razem z jednostkami w szkoleniu.
	var army := 0
	var training := 0


## Czy samouczek (cele i wskazania) jest widoczny: włączony albo jeszcze nie zapytany, przed końcem fal.
static func active(state: int, cleared: int) -> bool:
	return (state == State.ON or state == State.ASK) and cleared < PveWaves.COUNT


## Napis przełącznika w Ustawieniach: „wł.” tylko wtedy, gdy samouczek naprawdę prowadzi (włączony albo
## przed pytaniem). Ukończony (DONE) pokazuje „wył.”; włączenie go z Ustawień to świadoma decyzja gracza
## i zapisuje ON, więc po Zacznij od nowa samouczek znowu prowadzi (review #289).
static func settings_on(state: int) -> bool:
	return state == State.ON or state == State.ASK


## Czy po wczytaniu gry zapytać gracza o samouczek (okno TutorialPrompt).
static func should_ask(state: int, cleared: int) -> bool:
	return state == State.ASK and cleared < PveWaves.COUNT


## Krok wskazania dla celu `goal` (indeks w TutorialGoals.GOALS albo -1) i stanu interfejsu.
static func step(goal: int, ui: Ui) -> int:
	if ui.other_open:
		return Step.NONE
	match goal:
		GOAL_BARRACKS:
			return _barracks_step(ui)
		GOAL_ARMY:
			return _army_step(ui)
	return Step.NONE


static func _barracks_step(ui: Ui) -> int:
	if ui.recruit_open:
		return Step.NONE
	if ui.barracks_placed:
		return Step.HUD_DONE if ui.building else Step.WAIT_BUILD
	if ui.building:
		# inny budynek w trybie stawiania: Gotowe kończy tryb i wraca do ścieżki przez Buduj
		return Step.MAP if ui.selected_kind == BARRACKS else Step.HUD_DONE
	if ui.build_open:
		if ui.build_category != ARMY_CATEGORY:
			return Step.BUILD_TAB
		return Step.BUILD_PLACE if ui.build_selected == BARRACKS else Step.BUILD_TILE
	if ui.card_open:
		return Step.CARD_CLOSE
	return Step.HUD_BUILD


static func _army_step(ui: Ui) -> int:
	var need := missing(ui)
	if ui.recruit_open:
		if need <= 0:
			return Step.NONE
		if not ui.recruit_units.has(PEASANT):
			# Wojsko z karty budynku bez Chłopa (np. Strzelnica): Zamknij i dalej przez Wojsko w HUD
			return Step.RECRUIT_CLOSE
		return Step.RECRUIT_TRAIN if ui.recruit_selected == PEASANT else Step.RECRUIT_TILE
	if ui.build_open:
		return Step.NONE
	if ui.building:
		return Step.HUD_DONE
	if need <= 0:
		return Step.WAIT_TRAIN
	if ui.card_open:
		return Step.CARD_RECRUIT if ui.card_recruit else Step.CARD_CLOSE
	return Step.HUD_ARMY


## Ilu żołnierzy brakuje do celu „Wyszkol 6” po doliczeniu tych w szkoleniu.
static func missing(ui: Ui) -> int:
	var need := int((TutorialGoals.GOALS[GOAL_ARMY] as Array)[3])
	return maxi(0, need - ui.army - ui.training)


## Gdzie leży element kroku.
static func where(s: int) -> int:
	match s:
		Step.HUD_BUILD, Step.HUD_DONE, Step.HUD_ARMY, Step.CARD_CLOSE, Step.CARD_RECRUIT:
			return Where.HUD
		Step.BUILD_TAB, Step.BUILD_TILE, Step.BUILD_PLACE:
			return Where.BUILD_PANEL
		Step.RECRUIT_TILE, Step.RECRUIT_TRAIN, Step.RECRUIT_CLOSE:
			return Where.RECRUIT_PANEL
	return Where.NONE


## Cel dotyku do podświetlenia w HUD (Hud.Target, przyciski karty jako CARD + CardButton) albo NONE.
static func hud_target(s: int) -> int:
	match s:
		Step.HUD_BUILD:
			return Hud.Target.BUILD
		Step.HUD_DONE:
			return Hud.Target.DONE
		Step.HUD_ARMY:
			return Hud.Target.ARMY
		Step.CARD_CLOSE:
			return Hud.Target.CARD + Hud.CardButton.CLOSE
		Step.CARD_RECRUIT:
			return Hud.Target.CARD + Hud.CardButton.RECRUIT
	return Hud.Target.NONE


## Cel w panelu budowy (BuildPanel.Target, zakładka TAB + i, kafelek TILE + i) albo NONE.
static func build_target(s: int) -> int:
	match s:
		Step.BUILD_TAB:
			return BuildPanel.Target.TAB + ARMY_CATEGORY
		Step.BUILD_TILE:
			return BuildPanel.Target.TILE + BuildingTypes.in_category(ARMY_CATEGORY).find(BARRACKS)
		Step.BUILD_PLACE:
			return BuildPanel.Target.PLACE
	return BuildPanel.Target.NONE


## Cel na ekranie Wojsko (RecruitPanel.Target, kafelek TILE + i) albo NONE.
static func recruit_target(s: int, ui: Ui) -> int:
	match s:
		Step.RECRUIT_TILE:
			return RecruitPanel.Target.TILE + ui.recruit_units.find(PEASANT)
		Step.RECRUIT_TRAIN:
			return RecruitPanel.Target.TRAIN
		Step.RECRUIT_CLOSE:
			return RecruitPanel.Target.CLOSE
	return RecruitPanel.Target.NONE


## Tekst zamiast celu na pasku, gdy krok nie ma przycisku do podświetlenia (mapa, czekanie);
## pusty: zostaje tekst celu.
static func tip(s: int) -> String:
	match s:
		Step.MAP:
			return MAP_TIP
		Step.WAIT_BUILD:
			return WAIT_BUILD_TIP
		Step.WAIT_TRAIN:
			return WAIT_TRAIN_TIP
	return ""


## Pulsująca ramka wokół celu dotyku: stała ramka 1 px tuż za przyciskiem i druga, o piksel dalej,
## co drugie pół okresu. Kolory z palety, całe piksele.
static func draw_frame(ci: CanvasItem, r: Rect2, ms: int) -> void:
	@warning_ignore("integer_division")
	var on := (ms / PULSE_MS) % 2 == 0
	_outline(ci, r.grow(1), Palette.THATCH[2])
	if on:
		_outline(ci, r.grow(2), Palette.ACCENT)


static func _outline(ci: CanvasItem, r: Rect2, col: Color) -> void:
	ci.draw_rect(Rect2(r.position, Vector2(r.size.x, 1)), col)
	ci.draw_rect(Rect2(r.position + Vector2(0, r.size.y - 1), Vector2(r.size.x, 1)), col)
	ci.draw_rect(Rect2(r.position, Vector2(1, r.size.y)), col)
	ci.draw_rect(Rect2(r.position + Vector2(r.size.x - 1, 0), Vector2(1, r.size.y)), col)


## Stan samouczka jako tekst w profilu i z powrotem (nieznany tekst: jeszcze nie zapytano).
const STATE_NAMES: Array[String] = ["", "on", "off", "done"]


static func state_name(state: int) -> String:
	return STATE_NAMES[clampi(state, 0, STATE_NAMES.size() - 1)]


static func state_from(name: String) -> int:
	var i := STATE_NAMES.find(name)
	return i if i > 0 else State.ASK
