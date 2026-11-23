extends TestCase
## Mini-samouczek UI (#251): kolejne podświetlenia na ścieżce Buduj → Wojsko → Koszary → Postaw → mapa
## → Gotowe i Wojsko → Chłop → Szkol, aż armia ma 6 żołnierzy; okno z pytaniem o wyłączenie, stan
## w profilu i przełącznik w Ustawieniach.

const VIEW := Vector2(320, 180)
const S := TutorialHints.Step
const ST := TutorialHints.State
const K := BuildingTypes.Kind
const U := UnitTypes.Unit
const PROFILE := "user://test_tutorial_profile.json"


func _castle() -> BuildGrid:
	var grid := BuildGrid.new(TerrainMap.generate(WorldSeed.first_playable(1337)))
	grid.place(grid.manor_spot(64), K.MANOR, 1)
	grid.place(grid.keep_spot(64), K.KEEP, 1)
	return grid


## Ścieżka do Koszar: każdy krok wskazuje element, który go kończy, a stawianie na mapie i budowa
## mają podpowiedź zamiast przycisku.
func test_barracks_path() -> bool:
	var grid := _castle()
	var research := Research.new()
	var r := Recruitment.new()
	var goal := TutorialGoals.current(0, grid, research, r)
	assert_eq(goal, TutorialHints.GOAL_BARRACKS, "pierwszy cel: Koszary")
	var ui := TutorialHints.Ui.new()
	assert_eq(TutorialHints.step(goal, ui), S.HUD_BUILD, "najpierw Buduj")
	assert_eq(TutorialHints.hud_target(S.HUD_BUILD), Hud.Target.BUILD, "przycisk Buduj w HUD")
	ui.card_open = true
	assert_eq(TutorialHints.step(goal, ui), S.CARD_CLOSE, "otwarta karta: najpierw Zamknij")
	ui.card_open = false
	ui.build_open = true
	ui.build_category = 0
	ui.build_selected = K.RAMPART
	assert_eq(TutorialHints.step(goal, ui), S.BUILD_TAB, "w panelu: zakładka Wojsko")
	assert_eq(TutorialHints.build_target(S.BUILD_TAB), BuildPanel.Target.TAB + TutorialHints.ARMY_CATEGORY, "zakładka 4.")
	assert_eq(BuildingTypes.CATEGORY_NAMES[TutorialHints.ARMY_CATEGORY], "Wojsko", "to zakładka Wojsko")
	ui.build_category = TutorialHints.ARMY_CATEGORY
	ui.build_selected = BuildingTypes.in_category(TutorialHints.ARMY_CATEGORY)[0]
	if ui.build_selected != K.BARRACKS:
		assert_eq(TutorialHints.step(goal, ui), S.BUILD_TILE, "kafelek Koszar")
		var t := TutorialHints.build_target(S.BUILD_TILE)
		assert_eq(BuildingTypes.in_category(TutorialHints.ARMY_CATEGORY)[t - BuildPanel.Target.TILE], K.BARRACKS,
				"wskazany kafelek to Koszary")
	ui.build_selected = K.BARRACKS
	assert_eq(TutorialHints.step(goal, ui), S.BUILD_PLACE, "Postaw")
	assert_eq(TutorialHints.build_target(S.BUILD_PLACE), BuildPanel.Target.PLACE, "przycisk Postaw")
	ui.build_open = false
	ui.building = true
	ui.selected_kind = K.BARRACKS
	assert_eq(TutorialHints.step(goal, ui), S.MAP, "dotknij mapy")
	assert_eq(TutorialHints.tip(S.MAP), TutorialHints.MAP_TIP, "podpowiedź na pasku celu")
	assert_eq(TutorialHints.where(S.MAP), TutorialHints.Where.NONE, "bez przycisku")
	ui.selected_kind = K.FARM
	assert_eq(TutorialHints.step(goal, ui), S.HUD_DONE, "inny budynek: Gotowe i od nowa")
	ui.selected_kind = K.BARRACKS
	ui.barracks_placed = true
	assert_eq(TutorialHints.step(goal, ui), S.HUD_DONE, "Koszary w kolejce: Gotowe")
	assert_eq(TutorialHints.hud_target(S.HUD_DONE), Hud.Target.DONE, "przycisk Gotowe")
	ui.building = false
	assert_eq(TutorialHints.step(goal, ui), S.WAIT_BUILD, "czekanie na budowę")
	assert_true(not TutorialHints.tip(S.WAIT_BUILD).is_empty(), "z podpowiedzią")
	# po zbudowaniu Koszar cel przechodzi dalej, a z nim wskazanie
	grid.place(grid.spot_near(grid.buildings[grid.manor_id()].position, K.BARRACKS, 40), K.BARRACKS, 1)
	assert_eq(TutorialHints.step(TutorialGoals.current(0, grid, research, r), ui), S.HUD_ARMY, "potem Wojsko")
	return true


## Ścieżka „6 żołnierzy”: Wojsko → Chłop → Szkol, póki z kolejką brakuje żołnierzy; potem czekanie,
## a po 6 w armii wskazanie się kończy (dalsze cele mają tylko tekst).
func test_six_soldiers_path() -> bool:
	var grid := _castle()
	grid.place(grid.spot_near(grid.buildings[grid.manor_id()].position, K.BARRACKS, 40), K.BARRACKS, 1)
	var research := Research.new()
	var r := Recruitment.new()
	var goal := TutorialGoals.current(0, grid, research, r)
	assert_eq(goal, TutorialHints.GOAL_ARMY, "cel: 6 żołnierzy")
	var ui := TutorialHints.Ui.new()
	ui.barracks_placed = true
	assert_eq(TutorialHints.step(goal, ui), S.HUD_ARMY, "przycisk Wojsko")
	assert_eq(TutorialHints.hud_target(S.HUD_ARMY), Hud.Target.ARMY, "Wojsko w kolumnie")
	ui.card_open = true
	ui.card_recruit = true
	assert_eq(TutorialHints.step(goal, ui), S.CARD_RECRUIT, "karta Koszar: Szkol")
	assert_eq(TutorialHints.hud_target(S.CARD_RECRUIT), Hud.Target.CARD + Hud.CardButton.RECRUIT, "Szkol na karcie")
	ui.card_recruit = false
	assert_eq(TutorialHints.step(goal, ui), S.CARD_CLOSE, "inna karta: Zamknij")
	ui.card_open = false
	ui.recruit_open = true
	ui.recruit_units = RecruitPanel.units_for(-1)
	ui.recruit_selected = U.AXE_WARRIOR
	assert_eq(TutorialHints.step(goal, ui), S.RECRUIT_TILE, "kafelek Chłopa")
	var t := TutorialHints.recruit_target(S.RECRUIT_TILE, ui)
	assert_eq(ui.recruit_units[t - RecruitPanel.Target.TILE], U.PEASANT, "wskazany kafelek to Chłop")
	ui.recruit_selected = U.PEASANT
	for queued in 6:
		ui.training = queued
		assert_eq(TutorialHints.step(goal, ui), S.RECRUIT_TRAIN, "Szkol, w kolejce %d" % queued)
	assert_eq(TutorialHints.recruit_target(S.RECRUIT_TRAIN, ui), RecruitPanel.Target.TRAIN, "przycisk Szkol")
	ui.training = 6
	assert_eq(TutorialHints.step(goal, ui), S.NONE, "6 w kolejce: bez dalszych wskazań na ekranie")
	ui.recruit_open = false
	assert_eq(TutorialHints.step(goal, ui), S.WAIT_TRAIN, "czekanie na szkolenie")
	ui.training = 2
	ui.army = 4
	assert_eq(TutorialHints.missing(ui), 0, "4 w armii i 2 w szkoleniu to 6")
	r.add_squad(U.PEASANT, 6)
	var next := TutorialGoals.current(0, grid, research, r)
	assert_true(next != TutorialHints.GOAL_ARMY, "cel spełniony, kolejny z TutorialGoals")
	assert_eq(TutorialHints.step(next, ui), S.NONE, "bez wskazań przy dalszych celach")
	assert_eq(TutorialHints.step(-1, ui), S.NONE, "przy Oblężeniu bez wskazań")
	return true


## Ekrany spoza ścieżki (bitwa, obrona, inne panele) nie dostają ramki.
func test_no_hint_on_other_screens() -> bool:
	var ui := TutorialHints.Ui.new()
	ui.other_open = true
	assert_eq(TutorialHints.step(TutorialHints.GOAL_BARRACKS, ui), S.NONE, "inny ekran")
	assert_eq(TutorialHints.step(TutorialHints.GOAL_ARMY, ui), S.NONE, "inny ekran")
	ui.other_open = false
	ui.recruit_open = true
	assert_eq(TutorialHints.step(TutorialHints.GOAL_BARRACKS, ui), S.NONE, "Wojsko przed Koszarami")
	ui.recruit_open = false
	ui.build_open = true
	assert_eq(TutorialHints.step(TutorialHints.GOAL_ARMY, ui), S.NONE, "panel budowy przy szkoleniu")
	# Wojsko z karty budynku bez Chłopa: Zamknij, potem Wojsko w HUD (review #289)
	ui.build_open = false
	ui.recruit_open = true
	ui.recruit_units = RecruitPanel.units_for(K.ARCHERY_RANGE)
	assert_true(not ui.recruit_units.has(U.PEASANT), "Strzelnica nie szkoli Chłopów")
	assert_eq(TutorialHints.step(TutorialHints.GOAL_ARMY, ui), S.RECRUIT_CLOSE, "Zamknij")
	assert_eq(TutorialHints.recruit_target(S.RECRUIT_CLOSE, ui), RecruitPanel.Target.CLOSE, "przycisk Zamknij")
	var b := Hud.content_bounds(VIEW, Rect2())
	var r := RecruitPanel.hint_rect(RecruitPanel.Target.CLOSE, VIEW, b.x, b.y, ui.recruit_units.size())
	assert_eq(RecruitPanel.target_at(r.get_center(), VIEW, b.x, b.y, ui.recruit_units.size()), RecruitPanel.Target.CLOSE,
			"ramka na Zamknij")
	return true


## Wskazane elementy istnieją w układzie paneli na 320×180, są ≥ 12×12 i mieszczą ramkę na ekranie.
func test_hint_rects_on_screen() -> bool:
	var b := Hud.content_bounds(VIEW, Rect2())
	var rects: Array[Rect2] = [
		Hud.target_rect(Hud.Target.BUILD, VIEW, b.y, false, false),
		Hud.target_rect(Hud.Target.ARMY, VIEW, b.y, false, false),
		Hud.target_rect(Hud.Target.DONE, VIEW, b.y, true, false),
		Hud.target_rect(Hud.Target.CARD + Hud.CardButton.RECRUIT, VIEW, b.y, false, true, true),
		Hud.target_rect(Hud.Target.CARD + Hud.CardButton.CLOSE, VIEW, b.y, false, true),
		BuildPanel.target_rect(TutorialHints.build_target(S.BUILD_TAB), VIEW, b.x, b.y, 0),
		BuildPanel.target_rect(TutorialHints.build_target(S.BUILD_TILE), VIEW, b.x, b.y, TutorialHints.ARMY_CATEGORY),
		BuildPanel.target_rect(TutorialHints.build_target(S.BUILD_PLACE), VIEW, b.x, b.y, TutorialHints.ARMY_CATEGORY),
	]
	var units := RecruitPanel.units_for(-1)
	var ui := TutorialHints.Ui.new()
	ui.recruit_units = units
	rects.append(RecruitPanel.hint_rect(TutorialHints.recruit_target(S.RECRUIT_TILE, ui), VIEW, b.x, b.y, units.size()))
	rects.append(RecruitPanel.hint_rect(TutorialHints.recruit_target(S.RECRUIT_TRAIN, ui), VIEW, b.x, b.y, units.size()))
	for r in rects:
		assert_true(r.size.x >= 12 and r.size.y >= 12, "cel ≥ 12×12: %s" % r)
		var g := r.grow(2)
		assert_true(g.position.x >= 0 and g.position.y >= 0 and g.end.x <= VIEW.x and g.end.y <= VIEW.y,
				"ramka na ekranie: %s" % r)
	# wskazanie trafia w ten sam przycisk, który obsługuje dotyk
	assert_eq(Hud.target_at(rects[0].get_center(), VIEW, b.y, false, false), Hud.Target.BUILD, "Buduj")
	assert_eq(Hud.target_at(rects[3].get_center(), VIEW, b.y, false, true, true),
			Hud.Target.CARD + Hud.CardButton.RECRUIT, "Szkol na karcie")
	assert_eq(BuildPanel.target_at(rects[6].get_center(), VIEW, b.x, b.y, TutorialHints.ARMY_CATEGORY),
			TutorialHints.build_target(S.BUILD_TILE), "kafelek Koszar")
	assert_eq(RecruitPanel.target_at(rects[-1].get_center(), VIEW, b.x, b.y, units.size()), RecruitPanel.Target.TRAIN,
			"Szkol")
	assert_true(not Hud.target_rect(Hud.Target.BUILD, VIEW, b.y, true, false).has_area(),
			"w trybie budowy nie ma Buduj")
	return true


## Samouczek widać przy ON i przed pytaniem; po wyłączeniu i ukończeniu znika, a pytanie pada raz.
func test_state_and_profile() -> bool:
	assert_true(TutorialHints.active(ST.ASK, 0) and TutorialHints.active(ST.ON, 4), "włączony przed 5. falą")
	assert_true(not TutorialHints.active(ST.OFF, 0), "wyłączony przez gracza")
	assert_true(not TutorialHints.active(ST.DONE, 0), "ukończony nie wraca po Zacznij od nowa")
	assert_true(not TutorialHints.active(ST.ON, PveWaves.COUNT), "po 5 falach koniec")
	assert_true(TutorialHints.should_ask(ST.ASK, 0), "pytanie dla nowego gracza")
	assert_true(not TutorialHints.should_ask(ST.ON, 0) and not TutorialHints.should_ask(ST.OFF, 0), "pytanie raz")
	assert_true(not TutorialHints.should_ask(ST.ASK, PveWaves.COUNT), "bez pytania po 5 falach")
	PlayerProfile.delete(PROFILE)
	assert_eq(PlayerProfile.read_tutorial(PROFILE), ST.ASK, "bez profilu: jeszcze nie zapytano")
	PlayerProfile.write_seed(PROFILE, 42)
	assert_eq(PlayerProfile.read_tutorial(PROFILE), ST.ASK, "stary profil bez pola")
	for st: int in [ST.ON, ST.OFF, ST.DONE]:
		assert_eq(PlayerProfile.write_tutorial(PROFILE, st), OK, "zapis")
		assert_eq(PlayerProfile.read_tutorial(PROFILE), st, "odczyt %d" % st)
	assert_eq(PlayerProfile.read_seed(PROFILE), 42, "seed zostaje w profilu")
	assert_eq(TutorialHints.state_from("cokolwiek"), ST.ASK, "nieznany tekst")
	# przełącznik w Ustawieniach pokazuje, czy samouczek naprawdę prowadzi (review #289)
	assert_true(TutorialHints.settings_on(ST.ASK) and TutorialHints.settings_on(ST.ON), "wł.")
	assert_true(not TutorialHints.settings_on(ST.OFF) and not TutorialHints.settings_on(ST.DONE), "ukończony to wył.")
	PlayerProfile.delete(PROFILE)
	return true


## Okno z pytaniem: dwa przyciski ≥ 12×12 na ekranie, teksty na 320 px, odpowiedź przez sygnał.
func test_prompt() -> bool:
	var rects := TutorialPrompt.button_rects(VIEW)
	assert_eq(rects.size(), 2, "dwa przyciski")
	for i in rects.size():
		var r := rects[i]
		assert_true(r.size.x >= 12 and r.size.y >= 12, "cel ≥ 12×12")
		assert_true(r.position.x >= Hud.CORNER_INSET and r.end.x <= VIEW.x - Hud.CORNER_INSET, "w poziomie")
		assert_true(r.end.y + 14 < VIEW.y - Hud.BAR_H, "nad dolnym paskiem z notką")
		var label: String = TutorialPrompt.LABELS[TutorialPrompt.targets()[i]]
		assert_true(PixelFont.text_width(label) <= r.size.x - 2, "„%s” mieści się" % label)
		assert_eq(TutorialPrompt.target_at(r.get_center(), VIEW), TutorialPrompt.targets()[i], "dotknięcie")
	assert_true(rects[0].position.y > TutorialPrompt.question_y() + PixelFont.LINE, "pod pytaniem")
	var texts: Array[String] = [TutorialPrompt.QUESTION, TutorialPrompt.LATER_NOTE, TutorialHints.MAP_TIP,
			TutorialHints.WAIT_BUILD_TIP, TutorialHints.WAIT_TRAIN_TIP]
	texts.append_array(TutorialPrompt.LINES)
	for t in texts:
		assert_true(PixelFont.text_width(t) <= VIEW.x - 2 * Hud.CORNER_INSET, "„%s” mieści się na 320 px" % t)
	var goal_w := int(Hud.goal_rect(Hud.CORNER_INSET, VIEW.x - Hud.CORNER_INSET, false).size.x) \
			- PixelFont.text_width(Hud.GOAL_PREFIX) - 8
	for t: String in [TutorialHints.MAP_TIP, TutorialHints.WAIT_BUILD_TIP, TutorialHints.WAIT_TRAIN_TIP]:
		assert_true(PixelFont.text_width(t) <= goal_w, "„%s” mieści się na pasku celu" % t)
	var p := TutorialPrompt.new()
	var got: Array[int] = []
	p.answered.connect(func(keep: bool) -> void: got.append(1 if keep else 0))
	p.open()
	p.activate(TutorialPrompt.Target.TURN_OFF)
	assert_true(not p.visible, "okno się zamyka")
	p.open()
	p.activate(TutorialPrompt.Target.KEEP)
	assert_eq(got, [0, 1] as Array[int], "Wyłącz, potem Prowadź")
	p.free()
	return true


## Ustawienia: wyłączenie pyta o potwierdzenie, włączenie działa od razu.
func test_settings_toggle() -> bool:
	var m := SettingsPanel.new()
	var got: Array[int] = []
	m.tutorial_changed.connect(func(on: bool) -> void: got.append(1 if on else 0))
	m.open()
	assert_eq(m.label(SettingsPanel.Target.TUTORIAL), SettingsPanel.TUTORIAL_ON, "włączony")
	m.activate(SettingsPanel.Target.TUTORIAL)
	assert_eq(m.screen, SettingsPanel.Screen.CONFIRM_TUTORIAL, "pytanie")
	assert_eq(m.head(), TutorialPrompt.QUESTION, "nagłówek z pytaniem")
	assert_eq(m.label(SettingsPanel.Target.CONFIRM_YES), SettingsPanel.TUTORIAL_YES, "Tak, wyłącz")
	m.activate(SettingsPanel.Target.CONFIRM_NO)
	assert_true(m.tutorial_on and got.is_empty(), "Nie zostawia samouczek")
	m.activate(SettingsPanel.Target.TUTORIAL)
	m.activate(SettingsPanel.Target.CONFIRM_YES)
	assert_true(not m.tutorial_on and m.screen == SettingsPanel.Screen.SETTINGS, "wyłączony, z powrotem w ustawieniach")
	assert_eq(m.label(SettingsPanel.Target.TUTORIAL), SettingsPanel.TUTORIAL_OFF, "napis wył.")
	m.activate(SettingsPanel.Target.TUTORIAL)
	assert_true(m.tutorial_on, "włączenie od razu")
	assert_eq(got, [0, 1] as Array[int], "sygnały")
	m.free()
	return true
