extends TestCase
## Ustawienia (#177): zębatka w kolumnie HUD-u zamiast ekranu startowego, język z zapowiedzią
## angielskiego, Zacznij od nowa z potwierdzeniem, układ na 320×180. PvE w karcie Strażnicy.

const VIEW := Vector2(320, 180)
const T := SettingsPanel.Target
const S := SettingsPanel.Screen
const K := BuildingTypes.Kind
const MAIN := preload("res://scripts/main.gd")


func test_buttons_and_targets() -> bool:
	assert_eq(SettingsPanel.targets(S.SETTINGS), [T.LANGUAGE, T.SOUND, T.NEW_GAME, T.CLOSE] as Array[int], "ustawienia")
	assert_eq(SettingsPanel.targets(S.CONFIRM), [T.CONFIRM_YES, T.CONFIRM_NO] as Array[int], "potwierdzenie")
	var first := SettingsPanel.button_rects(VIEW, S.SETTINGS)[0].get_center()
	assert_eq(SettingsPanel.target_at(first, VIEW, S.SETTINGS), T.LANGUAGE, "na górze język")
	assert_eq(SettingsPanel.target_at(Vector2(4, 4), VIEW, S.SETTINGS), T.NONE, "tło to nie przycisk")
	return true


## Zacznij od nowa najpierw pyta; Nie wraca, Tak wysyła sygnał. Zamknij zamyka panel.
func test_new_game_needs_confirmation() -> bool:
	var m := SettingsPanel.new()
	var asked: Array[int] = [0]
	var shut: Array[int] = [0]
	m.new_game_requested.connect(func() -> void: asked[0] += 1)
	m.closed.connect(func() -> void: shut[0] += 1)
	m.open()
	m.activate(T.NEW_GAME)
	assert_eq(m.screen, S.CONFIRM, "pytanie o potwierdzenie")
	assert_eq(asked[0], 0, "jeszcze bez nowej gry")
	m.activate(T.CONFIRM_NO)
	assert_eq(m.screen, S.SETTINGS, "Nie wraca do ustawień")
	m.activate(T.NEW_GAME)
	m.activate(T.CONFIRM_YES)
	assert_eq(asked[0], 1, "Tak zaczyna od nowa")
	m.open()
	m.activate(T.CLOSE)
	assert_true(not m.visible and shut[0] == 1, "Zamknij zamyka panel")
	m.free()
	return true


func test_language_path() -> bool:
	var m := SettingsPanel.new()
	assert_eq(m.label(T.LANGUAGE), "Język: polski", "domyślnie polski")
	m.activate(T.LANGUAGE)
	assert_eq(m.label(T.LANGUAGE), "Język: English", "wybór angielskiego")
	assert_eq(m.hint, SettingsPanel.ENGLISH_LATER, "angielski wkrótce")
	m.activate(T.LANGUAGE)
	assert_eq(m.label(T.LANGUAGE), "Język: polski", "z powrotem polski")
	m.free()
	return true


## Układ: cele ≥ 12×12, napisy mieszczą się na przyciskach i na 320 px, przyciski nad stopką.
func test_layout_fits_the_screen() -> bool:
	var m := SettingsPanel.new()
	for s: int in [S.SETTINGS, S.CONFIRM]:
		var rects := SettingsPanel.button_rects(VIEW, s)
		var ts := SettingsPanel.targets(s)
		for i in rects.size():
			var r := rects[i]
			assert_true(r.size.x >= 12 and r.size.y >= 12, "cel ≥ 12×12")
			assert_true(r.position.x >= Hud.CORNER_INSET and r.end.x <= VIEW.x - Hud.CORNER_INSET, "w poziomie na ekranie")
			assert_true(r.end.y + 16 < VIEW.y - SettingsPanel.FOOTER_Y, "nad podpowiedzią i stopką")
			assert_true(PixelFont.text_width(m.label(ts[i])) <= r.size.x - 2, "„%s” mieści się" % m.label(ts[i]))
			if i > 0:
				assert_true(r.position.y > rects[i - 1].end.y, "bez nakładania")
	for t: String in [SettingsPanel.TITLE.to_upper(), SettingsPanel.CONFIRM_TEXT, SettingsPanel.ENGLISH_LATER,
			SettingsPanel.SOUND_LATER, SettingsPanel.OFFLINE_NOTE, SettingsPanel.version_text()]:
		assert_true(PixelFont.text_width(t) <= VIEW.x - 2 * Hud.CORNER_INSET, "„%s” mieści się na 320 px" % t)
	m.free()
	return true


## Kolumna HUD-u bez Oblężenia i Ataku, na dole zębatka Ustawień.
func test_settings_button_in_hud_column() -> bool:
	var b := Hud.content_bounds(VIEW, Rect2())
	var targets := Hud.column_targets(false)
	assert_true(not targets.has(Hud.Target.SIEGE) and not targets.has(Hud.Target.ATTACK), "PvE poza kolumną")
	assert_eq(targets[-1], Hud.Target.SETTINGS, "Ustawienia na dole kolumny")
	var r := Hud.column_rect(b.y, targets.size() - 1, true)
	assert_eq(Hud.target_at(r.get_center(), VIEW, b.y, false, false), Hud.Target.SETTINGS, "dotknięcie zębatki")
	assert_eq(Hud.column_label(Hud.Target.SETTINGS), "Ustawienia", "dymek z nazwą")
	return true


## Karta Strażnicy: tylko Oblężenie, Wyprawa i Zamknij (jeden poziom, nie do rozebrania).
func test_watchtower_card() -> bool:
	var b := Hud.content_bounds(VIEW, Rect2())
	var card := Hud.card_rects(VIEW, false, true)
	assert_eq(card.size(), 3, "3 przyciski")
	assert_true(card[0].position.x >= b.x and card[-1].end.x <= b.y, "karta mieści się na 320 px")
	assert_eq(Hud.target_at(card[0].get_center(), VIEW, b.y, false, true, false, false, true),
			Hud.Target.CARD + Hud.CardButton.SIEGE, "pierwszy: Oblężenie")
	assert_eq(Hud.target_at(card[1].get_center(), VIEW, b.y, false, true, false, false, true),
			Hud.Target.CARD + Hud.CardButton.ATTACK, "drugi: Wyprawa")
	assert_eq(Hud.target_at(card[2].get_center(), VIEW, b.y, false, true, false, false, true),
			Hud.Target.CARD + Hud.CardButton.CLOSE, "trzeci: Zamknij")
	assert_true(PixelFont.text_width(MAIN.WATCHTOWER_INFO) <= int(card[-1].end.x - card[0].position.x),
			"opis mieści się na karcie")
	for button in Hud.card_buttons(false, true):
		assert_true(PixelFont.text_width(Hud.card_label(button)) <= Hud.BUTTON_SIZE.x - 2, "„%s” mieści się" % Hud.card_label(button))
	return true


## Strażnica stoi od startu przy Dworze, jest jedna i nie da się jej rozebrać.
func test_watchtower_is_unique_and_placed_near_manor() -> bool:
	var grid := BuildGrid.new(TerrainMap.generate(WorldSeed.first_playable(1337)))
	var manor := grid.place(grid.manor_spot(WorldSeed.MANOR_MAX_RING), K.MANOR, 1)
	grid.place(grid.keep_spot(WorldSeed.KEEP_MAX_RING), K.KEEP, 1)
	var spot := grid.watchtower_spot(grid.terrain.size)
	assert_true(spot.has_area(), "jest miejsce na Strażnicę")
	var id := grid.place(spot, K.WATCHTOWER, 1)
	assert_eq(grid.watchtower_id(), id, "Strażnica w siatce")
	assert_true(spot.grow(WorldSeed.KEEP_MAX_RING).intersects(grid.buildings[manor]), "blisko Dworu")
	assert_true(not spot.grow(1).intersects(grid.buildings[manor]) and not spot.grow(1).intersects(grid.buildings[grid.keep_id()]),
			"z kratką odstępu od Dworu i donżonu")
	assert_true(BuildingTypes.is_unique(K.WATCHTOWER), "jedna, nie do rozebrania")
	assert_true(not BuildingTypes.BUILD_BAR.has(K.WATCHTOWER), "nie ma jej na pasku budowy")
	assert_true(not BuildingArt.can_lean(K.WATCHTOWER), "własny kształt, bez przybudówki")
	var again := BuildGrid.new(TerrainMap.generate(WorldSeed.first_playable(1337)))
	again.place(again.manor_spot(WorldSeed.MANOR_MAX_RING), K.MANOR, 1)
	again.place(again.keep_spot(WorldSeed.KEEP_MAX_RING), K.KEEP, 1)
	assert_eq(again.watchtower_spot(again.terrain.size), spot, "to samo miejsce dla seeda")
	assert_true(BuildingArt.make_image(K.WATCHTOWER, 1, 0).get_used_rect().has_area(), "rysunek Strażnicy")
	# jeden poziom (decyzja właścicielki): nie da się jej ulepszyć nawet przy Dworze 5
	assert_true(not BuildingTypes.has_levels(K.WATCHTOWER), "bez poziomów")
	assert_eq(BuildConfig.max_level(K.WATCHTOWER, BuildingTypes.MAX_LEVEL), 1, "najwyższy poziom 1")
	assert_eq(MAIN.upgrade_info(K.WATCHTOWER, 1, 5, false), MAIN.WATCHTOWER_INFO, "karta bez kosztu ulepszenia")
	assert_true(BuildingTypes.has_levels(K.KEEP) and BuildingTypes.has_levels(K.BARRACKS), "inne budynki mają poziomy")
	assert_eq(BuildQueue.new().upgrade_hint(grid, id), BuildQueue.NO_LEVELS_HINT, "komunikat bez wymogu Dworu")
	return true
