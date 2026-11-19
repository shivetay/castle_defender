extends TestCase
## Onboarding (#228): imię gracza, nazwa zamku i domyślny władca bez premii w profilu gracza,
## walidacja nazw pod font 8 px i 320×180, panel na całym ekranie.

const VIEW := Vector2(320, 180)
const PATH := "user://test_onboarding_player.json"
const E := PlayerProfile.NameError
const F := OnboardingPanel.Field
const T := OnboardingPanel.Target
const MAIN := preload("res://scripts/main.gd")


func _identity(player: String, castle: String) -> PlayerProfile.Identity:
	var id := PlayerProfile.Identity.new()
	id.player_name = player
	id.castle_name = castle
	return id


func test_default_ruler_has_no_perks() -> bool:
	assert_true(Rulers.is_known(Rulers.DEFAULT), "domyślny władca istnieje")
	assert_eq(Rulers.perks(Rulers.DEFAULT), [] as Array[String], "bez premii")
	assert_eq(Rulers.perks("nieznany"), [] as Array[String], "nieznany też bez premii")
	assert_eq(PlayerProfile.Identity.new().ruler, Rulers.DEFAULT, "nowa tożsamość ma domyślnego władcę")
	return true


func test_name_validation() -> bool:
	assert_eq(PlayerProfile.check_name("Bolko", 3, 12), E.OK, "zwykłe imię")
	assert_eq(PlayerProfile.check_name("Łęczyca-Gród 2", 3, 16), E.OK, "polskie litery, cyfra, łącznik")
	assert_eq(PlayerProfile.check_name("  Ab  ", 3, 12), E.TOO_SHORT, "spacje na brzegach się nie liczą")
	assert_eq(PlayerProfile.check_name("", 3, 12), E.TOO_SHORT, "puste")
	assert_eq(PlayerProfile.check_name("Abcdefghijklm", 3, 12), E.TOO_LONG, "13 znaków")
	assert_eq(PlayerProfile.check_name("Ala<b>", 3, 12), E.BAD_CHAR, "znaczniki")
	assert_eq(PlayerProfile.check_name("Müller", 3, 12), E.BAD_CHAR, "znak spoza fontu")
	assert_eq(PlayerProfile.check_name("Ala_Kot", 3, 12), E.BAD_CHAR, "podkreślnik")
	assert_eq(PlayerProfile.clean_name("  Gród   nad  Wisłą "), "Gród nad Wisłą", "pojedyncze spacje")
	assert_eq(PlayerProfile.error_text("Imię", E.TOO_SHORT, 3, 12), "Imię: za krótkie (min. 3 znaki)", "komunikat")
	return true


## Najdłuższe nazwy z najszerszych znaków mieszczą się w ramce pola, a komunikaty w 320 px.
func test_names_fit_on_screen() -> bool:
	var inner := int(OnboardingPanel.FIELD_SIZE.x) - 6
	assert_true(PixelFont.text_width("W".repeat(PlayerProfile.NAME_MAX)) <= inner, "najszersze imię w polu")
	assert_true(PixelFont.text_width("M".repeat(PlayerProfile.CASTLE_MAX)) <= inner, "najszersza nazwa w polu")
	var lines: Array[String] = [OnboardingPanel.SUBTITLE, OnboardingPanel.PLACEHOLDER,
			OnboardingPanel.RULER_LINE % Rulers.ruler_name(Rulers.DEFAULT),
			PlayerProfile.error_text("Zamek", E.TOO_LONG, 3, PlayerProfile.CASTLE_MAX),
			PlayerProfile.error_text("Zamek", E.BAD_CHAR, 3, PlayerProfile.CASTLE_MAX)]
	for line in lines:
		assert_true(PixelFont.text_width(line) <= int(VIEW.x) - 32, "mieści się: %s" % line)
	return true


## Tożsamość w profilu obok seeda; zapis seeda jej nie kasuje, a zła tożsamość się nie zapisuje.
func test_identity_in_profile() -> bool:
	PlayerProfile.delete(PATH)
	assert_true(not PlayerProfile.has_identity(PATH), "bez profilu brak tożsamości")
	PlayerProfile.write_seed(PATH, 777)
	assert_true(not PlayerProfile.has_identity(PATH), "sam seed to jeszcze nie tożsamość")
	assert_eq(PlayerProfile.write_identity(PATH, _identity("Ab", "Gród")), ERR_INVALID_DATA, "za krótkie imię")
	assert_eq(PlayerProfile.write_identity(PATH, _identity("  Bolko ", "Gród  Bolka")), OK, "dobra tożsamość")
	var id := PlayerProfile.read_identity(PATH)
	assert_true(id != null, "tożsamość wraca z pliku")
	if id != null:
		assert_eq(id.player_name, "Bolko", "imię oczyszczone")
		assert_eq(id.castle_name, "Gród Bolka", "nazwa oczyszczona")
		assert_eq(id.ruler, Rulers.DEFAULT, "domyślny władca")
		assert_eq(PlayerProfile.sync_fields(id), {"nickname": "Bolko", "castle_name": "Gród Bolka",
				"ruler": Rulers.DEFAULT}, "pola do synchronizacji (#23)")
	assert_eq(PlayerProfile.read_seed(PATH), 777, "seed zostaje")
	PlayerProfile.write_seed(PATH, 888)
	assert_true(PlayerProfile.has_identity(PATH), "zapis seeda nie kasuje tożsamości")
	assert_eq(int(PlayerProfile.read(PATH).get("version", 0)), PlayerProfile.VERSION, "bieżąca wersja profilu")
	PlayerProfile.delete(PATH)
	return true


## Zepsuta tożsamość w pliku (np. ręczna edycja) wraca do onboardingu, a nieznany władca do domyślnego.
func test_bad_identity_in_file() -> bool:
	PlayerProfile.delete(PATH)
	SaveGame.write(PATH, {"version": 2, "player_seed": 5, "identity": {"player_name": "<script>",
			"castle_name": "Gród"}})
	assert_true(not PlayerProfile.has_identity(PATH), "niedozwolone znaki: znowu onboarding")
	SaveGame.write(PATH, {"version": 2, "identity": "Bolko"})
	assert_true(not PlayerProfile.has_identity(PATH), "tożsamość nie jest słownikiem")
	SaveGame.write(PATH, {"version": 2, "identity": {"player_name": "Bolko", "castle_name": "Gród",
			"ruler": "cesarz"}})
	var id := PlayerProfile.read_identity(PATH)
	assert_true(id != null and id.ruler == Rulers.DEFAULT, "nieznany władca to domyślny")
	PlayerProfile.delete(PATH)
	return true


func test_panel_layout() -> bool:
	var player := OnboardingPanel.field_rect(VIEW, F.PLAYER)
	var castle := OnboardingPanel.field_rect(VIEW, F.CASTLE)
	var start := OnboardingPanel.button_rect(VIEW)
	for r: Rect2 in [player, castle, start]:
		assert_true(r.size.x >= 12 and r.size.y >= 12, "cel dotyku co najmniej 12×12")
		assert_true(r.position.x >= 16 and r.end.x <= VIEW.x - 16 and r.end.y <= VIEW.y - 16, "z dala od krawędzi")
		assert_eq(r.position, r.position.floor(), "całe piksele")
	assert_true(not player.intersects(castle) and not castle.intersects(start), "nie zachodzą na siebie")
	assert_eq(OnboardingPanel.target_at(player.get_center(), VIEW), T.PLAYER, "pole imienia")
	assert_eq(OnboardingPanel.target_at(castle.get_center(), VIEW), T.CASTLE, "pole zamku")
	assert_eq(OnboardingPanel.target_at(start.get_center(), VIEW), T.START, "Zacznij")
	assert_eq(OnboardingPanel.target_at(Vector2(4, 4), VIEW), T.NONE, "tło")
	var line := OnboardingPanel.ruler_line_rect(VIEW, Rulers.DEFAULT)
	assert_true(line.size.y >= 12 and not line.intersects(castle) and not line.intersects(start), "linia władcy osobno")
	assert_eq(OnboardingPanel.target_at(line.get_center(), VIEW), T.CHANGE_RULER, "zmiana władcy")
	return true


## Ekran władcy: Rulers.SLOTS miejsc w rzędzie, pierwsze to Kasztelan, reszta puste.
func test_ruler_screen_layout() -> bool:
	var S := OnboardingPanel.Screen
	assert_eq(Rulers.SLOTS, 5, "pięć miejsc")
	assert_eq(Rulers.at_slot(0), Rulers.DEFAULT, "pierwszy Kasztelan")
	for slot in range(1, Rulers.SLOTS):
		assert_eq(Rulers.at_slot(slot), "", "miejsce %d puste" % slot)
	var prev := Rect2()
	for slot in Rulers.SLOTS:
		var r := OnboardingPanel.slot_rect(VIEW, slot)
		assert_true(r.position.x >= 16 and r.end.x <= VIEW.x - 16, "miejsce %d z dala od krawędzi" % slot)
		assert_eq(r.position, r.position.floor(), "całe piksele")
		assert_true(not r.intersects(prev), "miejsca nie zachodzą na siebie")
		assert_eq(OnboardingPanel.target_at(r.get_center(), VIEW, S.RULER), T.SLOT + slot, "dotyk miejsca %d" % slot)
		prev = r
	assert_eq(OnboardingPanel.target_at(OnboardingPanel.button_rect(VIEW).get_center(), VIEW, S.RULER), T.CHOOSE,
			"Wybierz")
	assert_eq(OnboardingPanel.target_at(OnboardingPanel.field_rect(VIEW, F.PLAYER).get_center(), VIEW, S.RULER),
			T.NONE, "pola nazw są dopiero na drugim ekranie")
	var locked := PortraitArt.locked_image()
	assert_eq(locked.get_pixel(0, 0).a, 0.0, "puste miejsce też w kole")
	assert_eq(locked.get_pixel(1, PortraitArt.SIZE / 2), Palette.LOCKED[0], "szare tło")
	return true


## Najpierw wybór władcy: dotknięcie pokazuje premie, puste miejsce nie da się wybrać, Wybierz
## przechodzi do nazw, a linia władcy wraca do wyboru.
func test_ruler_choice() -> bool:
	var S := OnboardingPanel.Screen
	var p := OnboardingPanel.new()
	p.open()
	assert_eq(p.screen, S.RULER, "start od wyboru władcy")
	assert_true(p.slot_info().is_empty() and not p.can_choose(), "przed dotknięciem bez info i bez Wybierz")
	assert_true(not p.choose(), "nic nie zaznaczono")
	p.activate(T.SLOT + 2)
	assert_eq(p.slot_info(), PackedStringArray([Rulers.LOCKED_NAME, Rulers.LOCKED_INFO]), "puste miejsce: zapowiedź")
	assert_true(not p.choose() and p.screen == S.RULER, "pustego miejsca nie da się wybrać")
	p.activate(T.SLOT)
	assert_eq(p.slot_info(), PackedStringArray(["Kasztelan", Rulers.NO_PERKS]), "Kasztelan bez premii")
	p.activate(T.CHOOSE)
	assert_eq(p.screen, S.NAMES, "Wybierz przechodzi do nazw")
	assert_eq(p.ruler, Rulers.DEFAULT, "wybrany Kasztelan")
	p.activate(T.CHANGE_RULER)
	assert_eq(p.screen, S.RULER, "powrót do wyboru władcy")
	for line: String in [OnboardingPanel.RULER_SUBTITLE, Rulers.LOCKED_INFO, Rulers.NO_PERKS]:
		assert_true(PixelFont.text_width(line) <= int(VIEW.x) - 32, "mieści się: %s" % line)
	p.free()
	return true


## Zacznij bez nazw pokazuje błąd i zostaje; z dobrymi nazwami zamyka panel i oddaje tożsamość.
func test_panel_submit() -> bool:
	var p := OnboardingPanel.new()
	var got: Array[PlayerProfile.Identity] = []
	p.finished.connect(func(id: PlayerProfile.Identity) -> void: got.append(id))
	p.open()
	assert_true(not p.submit(), "puste pola")
	assert_eq(p.hint, "Imię: za krótkie (min. 3 znaki)", "najpierw imię")
	p.set_field(F.PLAYER, "Bolko<>_")
	assert_eq(p.player_name, "Bolko", "niedozwolone znaki odfiltrowane przy wpisywaniu")
	p.set_field(F.CASTLE, "Gród nad Wisłą i Odrą")
	assert_eq(p.castle_name.length(), PlayerProfile.CASTLE_MAX, "przycięte do limitu")
	p.set_field(F.CASTLE, "Gr")
	assert_true(not p.submit(), "za krótka nazwa zamku")
	assert_true(p.hint.begins_with("Zamek:"), "błąd nazwy zamku")
	p.set_field(F.CASTLE, "Gród Bolka ")
	assert_true(p.submit(), "dobre nazwy")
	assert_true(not p.visible and got.size() == 1, "panel zamknięty, jedna tożsamość")
	if got.size() == 1:
		assert_eq(got[0].castle_name, "Gród Bolka", "nazwa przycięta")
		assert_eq(got[0].ruler, Rulers.DEFAULT, "domyślny władca")
		assert_true(got[0].is_complete(), "kompletna tożsamość")
	p.free()
	return true


## Portret władcy (#228): koło 22×22 z przezroczystymi rogami, z palety, zawsze ten sam.
func test_ruler_portrait() -> bool:
	var img := PortraitArt.ruler_image(Rulers.DEFAULT)
	assert_eq(img.get_size(), Vector2i(PortraitArt.SIZE, PortraitArt.SIZE), "rozmiar")
	assert_eq(img.get_pixel(0, 0).a, 0.0, "róg poza kołem przezroczysty")
	assert_eq(img.get_pixel(PortraitArt.SIZE - 1, PortraitArt.SIZE - 1).a, 0.0, "drugi róg")
	assert_eq(img.get_pixel(PortraitArt.SIZE / 2, PortraitArt.SIZE / 2).a, 1.0, "środek pełny")
	assert_eq(img.get_pixel(PortraitArt.SIZE / 2, 0), Palette.WOOD[0], "obrys na brzegu koła")
	assert_eq(img.get_data(), PortraitArt.ruler_image(Rulers.DEFAULT).get_data(), "deterministyczny")
	assert_eq(PortraitArt.ruler_image("nieznany").get_data(), img.get_data(), "nieznany władca: domyślny portret")
	for row: String in PortraitArt.PATTERNS[Rulers.DEFAULT]:
		assert_eq(row.length(), PortraitArt.SIZE, "wiersz wzoru ma %d znaków" % PortraitArt.SIZE)
	return true


## Portret w lewym górnym rogu: pod paskiem surowców i pod paskiem celu, obok kolumny przycisków.
func test_portrait_in_hud() -> bool:
	var b := Hud.content_bounds(VIEW, Rect2(Vector2.ZERO, VIEW))
	var goal := Hud.goal_rect(b.x, b.y)
	for has_goal: bool in [false, true]:
		var r := Hud.portrait_rect(b.x, has_goal)
		assert_true(r.size.x >= 12 and r.size.y >= 12, "cel dotyku co najmniej 12×12")
		assert_true(r.position.y >= Hud.BAR_H and r.position.x >= Hud.CORNER_INSET, "pod paskiem, z marginesem")
		assert_true(r.position.x < VIEW.x / 4.0 and r.end.y < VIEW.y / 2.0, "lewy górny róg")
		assert_true(not r.intersects(Hud.column_rect(b.y, 0, true)), "z dala od kolumny przycisków")
	assert_true(not Hud.portrait_rect(b.x, true).intersects(goal), "pod paskiem celu")
	var h := Hud.new()
	assert_true(not h.shows_portrait(), "bez tożsamości bez portretu")
	h.ruler_id = Rulers.DEFAULT
	assert_true(h.shows_portrait(), "po onboardingu portret jest")
	h.battle = true
	assert_true(not h.shows_portrait(), "w bitwie znika")
	h.free()
	var lines := MAIN.ruler_info(_identity("Bolko", "Gród Bolka"))
	assert_eq(lines, PackedStringArray(["Gracz: Bolko", "Zamek: Gród Bolka", "Premie: brak"]), "okienko władcy")
	return true
