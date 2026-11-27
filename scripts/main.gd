extends Node2D
## Widok zamku z budynkami epoki I, ekonomią i kolejką budowy. Teren 64×64 kratki z seeda,
## siatka budowy, kamera z gestami. Na środku od startu stoi Dwór (poziom zamku).
## Tryb oglądania: dotknięcie budynku otwiera kartę z przyciskami Ulepsz, Rozbierz (albo Anuluj
## dla zlecenia w kolejce) i Zamknij, z kosztem ulepszenia. Przycisk Buduj otwiera panel budowy
## (BuildPanel), a Postaw włącza tryb budowy wybranego budynku: dotknięcie wolnej trawy zleca budowę (koszt schodzi od razu, na kratkach staje plac budowy,
## budynek powstaje po czasie z BuildConfig); Zmień wraca do panelu, Gotowe i Anuluj do oglądania. Surowce i budowa
## idą dalej, gdy gra jest w tle albo zamknięta; po powrocie komunikat podaje, ile przybyło.
## Przycisk Wojsko otwiera ekran rekrutacji wszystkich jednostek, a Szkol na karcie budynku rekrutacji
## ten sam ekran tylko z jednostkami tego budynku (RecruitPanel).
## Przycisk Obrona otwiera ustawienia obrony (DefensePanel, #19, #20): oddziałom załogi daje się
## zadania (Obrona odcinka, Patrol) w strefie wokół donżonu i ustawia priorytet celów wież.
## Przycisk Kolejka (albo czas budowy na górnym pasku) otwiera ekran Kolejka (QueuePanel, #163) z zakładkami
## Budynki i Jednostki: co się buduje i szkoli, z anulowaniem budowy.
## Przycisk Badania otwiera drzewko technologii (ResearchPanel); badanie trwa w czasie zegarowym
## jak budowa, jedno naraz.
## Gra zapisuje się (SaveGame) po każdej akcji, po ukończeniu budowy i przy zejściu do tła,
## a przy starcie wczytuje zapis i nadrabia czas nieobecności.

## Ile pikseli od krawędzi wolnej luki w linii umocnień dotknięcie sąsiedniego odcinka
## w trybie budowy nadal stawia odcinek w luce (z 8 px kratki).
const GAP_TAP_TOLERANCE := 3
## Czas animacji przebudowy Dworu na nową epokę (#34), ms.
const AGE_ANIM_MS := 2400
## Warstwa zasłony ładowania (#316): nad całym UI i widokami bitwy.
const LOADER_LAYER := 100
## Warstwa okna aktualizacji (#336): nad zasłoną ładowania.
const UPDATE_LAYER := 110
## Ekran tytułowy (#360): nad zasłoną ładowania, pod oknem aktualizacji.
const TITLE_LAYER := 105
const UPDATE_OFFLINE_NOTE := "Brak połączenia z serwerem"
const UPDATE_STILL_NOTE := "Nadal potrzebna aktualizacja"
const UPDATE_STORE_NOTE := "Nie udało się otworzyć sklepu"


## Komunikat, gdy Rybak nie styka się z wodą (#122).
const WATER_HINT := "%s musi stać tuż przy rzece"
const KEEP_NO_ROOM := "Brak miejsca na donżon: rozbierz coś obok Dworu"
## Stary zapis bez wolnego 4×4 na Targ (#408): Targ stanie sam, gdy miejsce się zwolni (_ensure_market).
const MARKET_NO_ROOM := "Zrób miejsce 4×4 na Targ"

## Komunikat w trybie oglądania.
const DEFAULT_MESSAGE := Hud.VIEW_MESSAGE
## Linia karty Strażnicy (#177): jeden poziom, więc zamiast kosztu ulepszenia krótki opis.
const WATCHTOWER_INFO := "Fale, wyprawy i rankingi"
## Linia karty donżonu (#232): bez ulepszeń i rozbiórki, strzela jak wieża.
const KEEP_INFO := "Cel ataku, strzela ze strzelcem"
## Opis karty Targu (#408).
const MARKET_INFO := "Darmowe oferty w Sklepie, z odnowieniem"
## Opis karty Komendy umocnień (#199), gdy nie trwa Sprawdź i nie ma wyniku.
const SEAL_HOUSE_INFO := "Sprawdź szczelność umocnień"
## Opis karty Chaty tropicieli (#28), gdy nie ma misji ani raportu.
const SCOUT_HOUSE_INFO := "Zwiad wysyłasz z ekranu Wyprawy"
## Karta Komendy, gdy gracz wskazał lukę (#199).
const SEAL_SELECTED_INFO := "Wybrana luka: Domknij ją"
## Zapas w px przy dotknięciu czerwonej luki (kratka ma 8 px, cel dotyku co najmniej 12 px).
const SEAL_TAP_TOLERANCE := 3.0
## Podgląd bitwy w wersji debug (#15): godot --path . -- --battle-preview. Bitwę z gry uruchomi #16.
const BATTLE_PREVIEW_ARG := "--battle-preview"

## Seed terenu: nowa gra losuje go (WorldSeed), wczytana bierze z zapisu.
var world_seed := 0

var terrain: TerrainMap
var grid: BuildGrid
var camera: PanZoomCamera
var hud: Hud
var textures := BuildingTextures.new()
var economy: Economy
var queue := BuildQueue.new()
var research := Research.new()
var goods: Goods
var recruitment := Recruitment.new()
var recruit_panel: RecruitPanel
var research_panel: ResearchPanel
## Ustawienia (#177) pod zębatką w kolumnie HUD-u.
var settings_panel: SettingsPanel
## Konto gracza w Supabase (#22); bez konfiguracji albo sieci gra działa offline.
var net: SupabaseClient
## Zamek właśnie wrócił z serwera (#23); zmienna statyczna przetrwa przeładowanie sceny.
static var _restored_from_server := false
## Zamek z serwera leży już w zapisie i scena czeka na przeładowanie: lokalny zapis by go nadpisał.
var _restoring := false
## Tożsamość gracza z onboardingu (#228): imię, nazwa zamku i władca. Null, dopóki gracz jej nie poda;
## wtedy panel onboardingu przykrywa zamek, a zamek nie idzie na serwer.
var identity: PlayerProfile.Identity
var onboarding: OnboardingPanel
## Zasłona ładowania przy synchronizacji z serwerem (#316), na własnej warstwie nad całym UI.
var sync_loader: SyncLoaderPanel
## Okno aktualizacji (#336, ADR 0006): komunikat o nowej wersji albo blokada gry.
var update_panel: UpdatePanel
var _update_layer: CanvasLayer
## Ostatnia polityka wersji z serwera (z `user://version_policy.json` do pierwszej odpowiedzi); null: nigdy.
var version_policy: ClientVersion.Policy
## Kiedy ostatnio pytaliśmy serwer o politykę (unix s), także bez odpowiedzi.
var _version_asked_s := 0
## Mini-samouczek UI (#251): stan z profilu (TutorialHints.State) i okno z pytaniem, póki otwarte.
var tutorial_state: int = TutorialHints.State.ASK
var tutorial_prompt: TutorialPrompt
var build_panel: BuildPanel
var queue_panel: QueuePanel
## Ile fal samouczka PvE (#16) gracz obronił; trwająca bitwa (null poza bitwą).
var pve_cleared := 0
var battle_view: BattleView
## Stan zniszczeń budynków własnego zamku w trwającej bitwie (BattleView.states_of).
var battle_states: Dictionary = {}
## Ruiny po atakach PvP na zamek gracza (#99): odbudowują się same, w ruinie Chata drwala i Rybak
## produkują mniej. Przychodzą z serwera (DefenseLog) po połączeniu, nie trafiają do zapisu.
var ruins := Ruins.new()
## Stany ruin narysowane ostatnio (id → BuildingTypes.State), żeby przerysować mapę tylko przy zmianie.
var _ruin_states: Dictionary = {}
var _battle_wave := -1
## Oddziały armii w kolejności oddziałów bitwy, do rozliczenia strat po fali (#164).
var _battle_ids: Array[int] = []
## Skład ataku (oddziały [rodzaj, liczba]) z chwili startu bitwy, do capacity łupu (#25).
var _battle_army: Array = []
## Atak na zamek-cel (#17): zapisany plan, ile zamków gracz już zdobył, ekran planu i zamek-cel.
var attack_plan := AttackPlan.new()
var bots_beaten := 0
## Cel Wyprawy: numer zamku-bota na liście BotRoster (#26) i ekran wyboru zamku.
var attack_target := 0
var bot_picker: BotPicker
## Wybór 3 celów Wyprawy (#24): gracze z serwera i zamki-boty.
var target_picker: TargetPicker
## Rankingi z karty Strażnicy: PvP ataku i obrony (#27) oraz PvE (#242), tabele z serwera.
var ranking_panel: RankingPanel
## Okno wyniku ataku (#99), a po powtórce raport obrony (#29).
var result_panel: ResultPanel
## Powtórki (#29): lista ostatnich obron, wczytywanie powtórki z serwera i trwająca powtórka.
var replay_panel: ReplayPanel
var _replay: BattleReplay
var _replaying := false
var _replay_loading := false
## Historia obron (#328): ostatnia lista z serwera, okienko o nowych atakach, koniec najnowszej obrony,
## o której okienko już mówiło w tej sesji (żeby nie wracało przy każdym powrocie do gry), i czy
## Historię otworzyło okienko (Wróć zamyka ją wtedy bez ustawień obrony).
var _defense_history: Array[DefenseLog.Report] = []
var defense_notice: DefenseNotice
var _noticed_s := 0
var _history_from_notice := false
var planner: AttackPlanner
var attack_panel: AttackPanel
## Okienko z informacją (produkcja surowca, limit armii).
var info_popup: InfoPopup
## Ustawienia obrony (#19): posterunki załogi i panel edycji (widoczny w trybie edycji obrony).
var defense := DefensePlan.new()
var defense_panel: DefensePanel
## Sprawdzanie szczelności z Komendy umocnień (#199).
var seal_check := SealCheck.new()
## Zwiad (#28) z Chaty tropicieli: misja w drodze i raporty o zamkach-celach.
var scouting := Scouting.new()
## Generałowie (#31): rekrutacja w Dworze, generał ataku i komendant obrony (DefensePlan.commander).
var generals := Generals.new()
## Płatne odświeżenia celów Wyprawy (#313): dzienny licznik ceny.
var target_refresh := TargetRefresh.new()
var generals_panel: GeneralsPanel
var ruler_panel: RulerPanel
## Sklep w Targu (#408).
var shop_panel: ShopPanel
## Serwer przyjął odbiór oferty: najbliższy łup z zapisu zamku to nagroda ze sklepu (komunikat).
var _shop_reward_due := false
const SHOP_REWARD_PREFIX := "Ze sklepu: "
## Porzucony atak na gracza (#240): start na serwerze liczy się jak atak na ten zamek przez dobę.
const ABANDONED_MESSAGE := "Atak porzucony: ten zamek znowu po dobie"
## Początek komunikatu o łupie z serwera i jego wersja dla nagrody za falę PvE (#288).
const LOOT_PREFIX := "Łup z ataku: "
const WAVE_REWARD_PREFIX := "Nagroda za falę: "
## Serwer nie przyjął fali albo jej wyniku (#288): nagrody nie ma.
const WAVE_FAILED_MESSAGE := "Fala poza serwerem: bez nagrody"
## Czy trwająca bitwa to atak (inaczej fala PvE).
var _attacking := false
## Atak na gracza (#240): cel z kopii z serwera (null przy zamku-bocie), czekanie na `start_attack`
## i wynik czekający na przyjęcie przez `finish_attack` (treść żądania, wynik, polegli, próby).
var _player: PlayerCastle
var _starting := false
## Zatwierdzenie planu na gracza czeka na `launch_attack` (#28).
var _launching := false
## Zwiad na gracza czeka na odpowiedź `scout` (#28): cel i długość z ekranu celów.
var _scout_target: TargetSearch.Target
var _scout_duration := 0
## Do kolejnego pytania serwera o raport zwiadu na gracza (s).
var _scout_poll_s := 0.0
## Co ile sekund pytać serwer o raport skończonej misji na gracza.
const SCOUT_POLL_S := 20.0
## Armia wysłana w ostatnim `start_attack` (do kopii celu, gdy serwer odpowie).
var _player_army: Array = []
var _finish_body: Dictionary = {}
var _finish_result: BattleResult
var _finish_fallen := 0
var _finish_tries := 0
## Wynik ataku na gracza czekający na serwer, także po zamknięciu gry (#99, `PendingFinish`).
var _pending := PendingFinish.new()
## Wysyłany wynik to zaległy wynik (z poprzedniej gry albo po wcześniejszym braku sieci).
var _finish_resumed := false
## Do kolejnej próby wysłania zaległego wyniku (s).
var _resume_poll_s := 0.0
## Co ile sekund ponawiać zaległy wynik, gdy gra jest połączona.
const RESUME_POLL_S := 30.0
## Ranking PvE (#242): wyprawa na zamek-bota zgłoszona serwerowi (start i wynik), gdy gra jest połączona.
var _pve := PveReport.new()
## Wynik wyprawy do rankingu PvE czeka na odpowiedź `finish_attack`.
var _pve_sending := false
## Fala PvE zgłoszona serwerowi (#288): start i wynik, gdy gra jest połączona; nagrodę daje tylko serwer.
var _wave := WaveReport.new()
## Wynik fali czeka na odpowiedź `pve_wave`.
var _wave_sending := false
## Serwer przyjął wygraną falę: najbliższy łup z zapisu zamku to nagroda za nią (komunikat).
var _wave_reward_due := false

var _terrain_tex: ImageTexture
## Dym z kominów i błyski na wodzie (#150), mieszkańcy, straż, proporce i pora dnia (#36), nad budynkami.
var ambient: AmbientView
var _selected_id := 0
## Początek animacji przebudowy Dworu na nową epokę (ms) albo -1 (#34).
var _age_anim_start_ms := -1
var _cursor := Rect2i()
var _cursor_ok := true


func _ready() -> void:
	var saved := SaveGame.load_state(SaveGame.PATH, _now_ms())
	_pending = PendingFinish.read()
	if saved != null:
		world_seed = saved.world_seed
		# zapis sprzed profilu: seed zamku zostaje seedem gracza (first_playable go nie zmieni)
		PlayerProfile.ensure_seed(PlayerProfile.PATH, world_seed)
		grid = saved.grid
		economy = saved.economy
		queue = saved.queue
		research = saved.research
		goods = saved.goods
		recruitment = saved.recruitment
		pve_cleared = saved.pve_cleared
		attack_plan = saved.attack_plan
		bots_beaten = saved.bots_beaten
		attack_target = saved.attack_target
		defense = saved.defense
		seal_check = saved.seal
		scouting = saved.scouting
		generals = saved.generals
		target_refresh = saved.target_refresh
		terrain = grid.terrain
	else:
		world_seed = WorldSeed.for_new_game()
		terrain = TerrainMap.generate(world_seed)
		grid = BuildGrid.new(terrain)
		economy = Economy.new(_now_ms())
		goods = Goods.new(_now_ms())
	if grid.manor_id() == 0:
		_place_manor()
	if grid.keep_id() == 0:
		_place_keep()
	if grid.watchtower_id() == 0:
		_place_watchtower()
	# Targ (#408): w nowej grze po Strażnicy, w starym zapisie przy wczytaniu; nie na pułapce (#341),
	# więc kratki pułapek trafiają do siatki przed szukaniem miejsca
	defense.mark_traps(grid)
	var market_missing := not grid.place_market()
	var keep_missing := grid.keep_id() == 0
	_terrain_tex = ImageTexture.create_from_image(TerrainRenderer.render(terrain))
	textures.warm_up()
	ambient = AmbientView.new()
	ambient.setup(grid, textures)
	add_child(ambient)

	camera = PanZoomCamera.new()
	camera.world_size = Vector2i(terrain.size, terrain.size) * TerrainMap.CELL
	add_child(camera)
	camera.make_current()
	var manor_id := grid.manor_id()
	var focus := Vector2(terrain.center())
	if manor_id != 0:
		focus = grid.buildings[manor_id].get_center()
	camera.look_at_world(focus * TerrainMap.CELL)
	camera.tapped.connect(_on_tapped)

	planner = AttackPlanner.new()
	planner.textures = textures
	planner.research = research
	planner.visible = false
	add_child(planner)

	var layer := CanvasLayer.new()
	add_child(layer)
	hud = Hud.new()
	hud.economy = economy
	layer.add_child(hud)
	hud.message = KEEP_NO_ROOM if keep_missing else (MARKET_NO_ROOM if market_missing else DEFAULT_MESSAGE)
	hud.build_pressed.connect(_on_build_panel_opened)
	hud.change_pressed.connect(_on_build_panel_opened)
	hud.build_mode_changed.connect(_on_build_mode_changed)
	hud.segment_changed.connect(_on_segment_changed)
	hud.siege_pressed.connect(_on_siege_pressed)
	hud.speed_pressed.connect(_on_speed_pressed)
	hud.upgrade_pressed.connect(_on_upgrade)
	hud.demolish_pressed.connect(_on_middle_button)
	hud.card_closed.connect(_deselect)
	hud.research_pressed.connect(_on_research_opened)
	hud.attack_pressed.connect(_on_attack_pressed)
	hud.defence_pressed.connect(_on_defence_pressed)
	hud.queue_pressed.connect(_on_queue_opened)
	hud.check_pressed.connect(_on_check_pressed)
	hud.seal_pressed.connect(_on_seal_pressed)

	attack_panel = AttackPanel.new()
	attack_panel.planner = planner
	attack_panel.visible = false
	layer.add_child(attack_panel)
	attack_panel.changed.connect(_on_plan_changed)
	attack_panel.hint.connect(func(message: String) -> void: hud.message = message)
	attack_panel.back_requested.connect(_on_attack_back)
	attack_panel.attack_requested.connect(_on_attack_launched)
	bot_picker = BotPicker.new()
	bot_picker.visible = false
	layer.add_child(bot_picker)
	bot_picker.target_chosen.connect(_open_attack)
	bot_picker.closed.connect(_on_bot_list_closed)
	target_picker = TargetPicker.new()
	target_picker.visible = false
	layer.add_child(target_picker)
	target_picker.bot_chosen.connect(_open_attack)
	target_picker.player_chosen.connect(_on_player_target)
	target_picker.bots_pressed.connect(_open_bot_list)
	target_picker.closed.connect(_on_overlay_closed)
	target_picker.scout_requested.connect(_on_scout_requested)
	target_picker.scout_changed.connect(_refresh_scout_lines)
	target_picker.refresh_requested.connect(_on_targets_refresh)
	ranking_panel = RankingPanel.new()
	ranking_panel.visible = false
	layer.add_child(ranking_panel)
	ranking_panel.closed.connect(_on_overlay_closed)
	ranking_panel.kind_changed.connect(_on_ranking_kind)
	ranking_panel.message_changed.connect(_on_ranking_message)
	hud.ranking_pressed.connect(_on_ranking_pressed)
	result_panel = ResultPanel.new()
	result_panel.visible = false
	layer.add_child(result_panel)
	result_panel.closed.connect(_on_result_closed)
	replay_panel = ReplayPanel.new()
	replay_panel.visible = false
	layer.add_child(replay_panel)
	replay_panel.closed.connect(_on_replays_closed)
	replay_panel.replay_requested.connect(_on_replay_requested)
	defense_notice = DefenseNotice.new()
	layer.add_child(defense_notice)
	defense_notice.history_requested.connect(_on_notice_history)
	defense_notice.closed.connect(_on_overlay_closed)

	defense_panel = DefensePanel.new()
	defense_panel.research = research
	defense_panel.economy = economy
	defense_panel.goods = goods
	defense_panel.visible = false
	layer.add_child(defense_panel)
	defense_panel.changed.connect(_on_defence_changed)
	defense_panel.back_requested.connect(_close_defence)
	defense_panel.replays_requested.connect(_on_replays_pressed)

	build_panel = BuildPanel.new()
	build_panel.research = research
	build_panel.economy = economy
	build_panel.visible = false
	layer.add_child(build_panel)
	build_panel.place_requested.connect(_on_place_requested)
	build_panel.closed.connect(_on_build_panel_closed)

	queue_panel = QueuePanel.new()
	queue_panel.queue = queue
	queue_panel.recruitment = recruitment
	queue_panel.grid = grid
	queue_panel.visible = false
	layer.add_child(queue_panel)
	queue_panel.closed.connect(_on_overlay_closed)
	queue_panel.cancel_requested.connect(_on_queue_cancel)
	queue_panel.focus_requested.connect(_on_queue_focus)
	queue_panel.build_requested.connect(_on_build_panel_opened)
	queue_panel.army_requested.connect(_on_army_opened.bind(0))
	queue_panel.message.connect(func(text: String) -> void: hud.message = text)

	research_panel = ResearchPanel.new()
	research_panel.research = research
	research_panel.economy = economy
	research_panel.age = grid.age()
	research_panel.grid = grid
	research_panel.visible = false
	layer.add_child(research_panel)
	research_panel.research_requested.connect(_on_research_requested)
	research_panel.closed.connect(_on_overlay_closed)
	hud.army_pressed.connect(_on_army_opened.bind(0))
	hud.recruit_pressed.connect(_on_recruit_pressed)

	recruit_panel = RecruitPanel.new()
	recruit_panel.recruitment = recruitment
	recruit_panel.grid = grid
	recruit_panel.economy = economy
	recruit_panel.goods = goods
	recruit_panel.research = research
	recruit_panel.age = grid.age()
	recruit_panel.visible = false
	layer.add_child(recruit_panel)
	recruit_panel.train_requested.connect(_on_train_requested)
	recruit_panel.closed.connect(_on_overlay_closed)
	generals_panel = GeneralsPanel.new()
	generals_panel.visible = false
	layer.add_child(generals_panel)
	generals_panel.closed.connect(_on_overlay_closed)
	generals_panel.recruit_requested.connect(_on_general_recruit)
	generals_panel.promote_requested.connect(_on_general_promote)
	generals_panel.perk_requested.connect(_on_general_perk)
	settings_panel = SettingsPanel.new()
	settings_panel.visible = false
	layer.add_child(settings_panel)
	settings_panel.closed.connect(_on_overlay_closed)
	settings_panel.new_game_requested.connect(_on_new_game)
	hud.settings_pressed.connect(_on_settings_opened)
	ruler_panel = RulerPanel.new()
	ruler_panel.visible = false
	layer.add_child(ruler_panel)
	ruler_panel.closed.connect(_on_overlay_closed)
	shop_panel = ShopPanel.new()
	shop_panel.visible = false
	layer.add_child(shop_panel)
	shop_panel.closed.connect(_on_overlay_closed)
	shop_panel.claim_requested.connect(_on_shop_claim)
	hud.shop_pressed.connect(_on_shop_pressed)
	info_popup = InfoPopup.new()
	layer.add_child(info_popup)  # dostaje dotyk przed panelami
	identity = PlayerProfile.read_identity(PlayerProfile.PATH)
	hud.portrait_pressed.connect(_on_portrait_pressed)
	tutorial_state = PlayerProfile.read_tutorial(PlayerProfile.PATH)
	if pve_cleared >= PveWaves.COUNT and tutorial_state != TutorialHints.State.DONE:
		_set_tutorial(TutorialHints.State.DONE)  # 5 fal już obronionych: samouczek się więcej nie pokaże
	settings_panel.tutorial_on = TutorialHints.settings_on(tutorial_state)
	settings_panel.tutorial_changed.connect(_on_tutorial_changed)
	if identity != null:
		hud.ruler_id = identity.ruler
	else:
		# pierwsze uruchomienie: najpierw wybór władcy, potem imię i nazwa zamku, nad wszystkim innym
		# (ostatnie dziecko)
		onboarding = OnboardingPanel.new()
		layer.add_child(onboarding)
		onboarding.finished.connect(_on_onboarding_finished)
		onboarding.open()
		hud.overlay = true
		hud.message = "Wybierz władcę i nazwij zamek"
	if identity != null:
		_ask_tutorial()
	hud.resource_pressed.connect(_on_resource_info)
	recruit_panel.limit_pressed.connect(_on_army_limit_info)
	net = SupabaseClient.new()
	# start bez zapisu (reinstalacja): zamek z serwera ma pierwszeństwo przed nowym (#23)
	net.local_fresh = saved == null
	net.state_changed.connect(_on_net_state)
	net.castle_restored.connect(_on_castle_restored)
	net.targets_found.connect(_on_targets_found)
	net.ranking_loaded.connect(ranking_panel.set_rows)
	net.attack_started.connect(_on_player_attack_started)
	net.attack_finished.connect(_on_player_attack_finished)
	net.attack_launched.connect(_on_player_launched)
	net.scout_sent.connect(_on_scout_sent)
	net.scout_reports_loaded.connect(_on_scout_reports)
	net.defenses_loaded.connect(_on_defenses_loaded)
	net.defense_reports_loaded.connect(_on_defense_reports)
	net.replay_loaded.connect(_on_replay_loaded)
	net.loot_applied.connect(_on_loot_applied)
	net.wave_started.connect(_on_wave_started)
	net.wave_finished.connect(_on_wave_finished)
	net.castle_rejected.connect(_on_castle_rejected)
	net.shop_loaded.connect(shop_panel.set_groups)
	net.shop_claimed.connect(_on_shop_claimed)
	add_child(net)
	_add_sync_loader()
	_add_title_screen()
	_add_update_panel()
	if saved != null:
		_catch_up("Witaj z powrotem: ")
	if _restored_from_server:
		_restored_from_server = false
		hud.message = "Zamek wrócił z serwera"
	_save()
	if OS.is_debug_build() and OS.get_cmdline_user_args().has(BATTLE_PREVIEW_ARG):
		_start_battle_preview()


## Podgląd bitwy na własnym zamku: obrońcy to wyszkolone oddziały (albo przykładowe),
## atakujący przykładowa armia z drogi przy krawędzi mapy. Seed bitwy stały, więc podgląd
## przebiega zawsze tak samo.
func _start_battle_preview() -> void:
	var defenders := recruitment.battle_squads()
	if defenders.is_empty():
		defenders = [[UnitTypes.Unit.SHIELDBEARER, 6], [UnitTypes.Unit.ARCHER, 8]]
	var attackers := [[UnitTypes.Unit.AXE_WARRIOR, 10], [UnitTypes.Unit.JAVELINEER, 8],
			[UnitTypes.Unit.RIDER, 4], [UnitTypes.Unit.FIRE_RAISER, 3]]
	var view := BattleView.new()
	view.battle = Battle.create_squads(grid, grid.keep_id(), attackers, defenders, _edge_road(), world_seed,
			defense.battle_orders(recruitment.battle_ids(), recruitment.battle_squads(), grid, grid.age()))
	view.battle.tower_priority = defense.tower_priority
	view.battle.arm_traps(defense.battle_traps(grid, research, grid.age()))
	view.battle.add_side_morale(Battle.Side.DEFENDER, BattleConfig.defender_morale_bonus(research))
	view.battle.apply_research(Battle.Side.DEFENDER, research)
	view.battle.set_general(Battle.Side.DEFENDER, defense.commander_general(generals))
	add_child(view)
	hud.message = "Podgląd bitwy"


## Wejście na mapę: pierwsza kratka drogi na krawędzi (BotCastle.edge_road).
func _edge_road() -> Vector2i:
	return BotCastle.edge_road(terrain)


## Dwór staje na pierwszym wolnym miejscu najbliżej środka mapy (kolejność stała dla seeda).
func _place_manor() -> void:
	var spot := grid.manor_spot(terrain.size)
	if spot.has_area():
		grid.place(spot, BuildingTypes.Kind.MANOR)


## Donżon (Wieża grodowa, #120) staje obok Dworu: cel każdego ataku. Starsze zapisy dostają go
## przy wczytaniu.
func _place_keep() -> void:
	var spot := grid.keep_spot(terrain.size)
	if spot.has_area():
		grid.place(spot, BuildingTypes.Kind.KEEP)
	else:
		# stary zapis bez miejsca na donżon: bitwa nie ma celu, więc HUD to pokaże (KEEP_NO_ROOM)
		push_warning("Brak miejsca na donżon obok Dworu")


## Strażnica (#177) staje obok Dworu po donżonie: z niej wyrusza się na fale i wyprawy PvE.
## Starsze zapisy dostają ją przy wczytaniu, w najbliższym wolnym miejscu.
func _place_watchtower() -> void:
	var spot := grid.watchtower_spot(terrain.size)
	if spot.has_area():
		grid.place(spot, BuildingTypes.Kind.WATCHTOWER)
	else:
		push_warning("Brak miejsca na Strażnicę")


## Po zwolnieniu miejsca (rozbiórka, anulowana budowa) brakujący Targ staje sam (#408).
func _ensure_market() -> void:
	if grid.market_id() != 0:
		return
	if grid.place_market():
		hud.message = "Targ stanął przy Dworze"
		queue_redraw()
	else:
		hud.message = MARKET_NO_ROOM


func _process(_delta: float) -> void:
	_tick()
	# mieszkańcy i straż schodzą z widoku na czas bitwy na własnym zamku; flagi znikają ze zburzonych budynków
	var own_battle := battle_view != null and not _on_target_map()
	ambient.life = battle_view == null
	ambient.states = battle_states if own_battle else _ruin_states
	if battle_view != null:
		_update_battle()
	if not queue.orders.is_empty():
		queue_redraw()
		if _selected_id != 0:
			_refresh_card()
	if _age_anim_start_ms >= 0:
		queue_redraw()


func _notification(what: int) -> void:
	if economy == null or hud == null:
		return
	match what:
		NOTIFICATION_APPLICATION_RESUMED:
			_catch_up("Podczas nieobecności: ")
			_load_defenses()
			_maybe_check_version()
		NOTIFICATION_APPLICATION_PAUSED, NOTIFICATION_APPLICATION_FOCUS_OUT, NOTIFICATION_WM_CLOSE_REQUEST:
			# Android potrafi zabić aplikację w tle bez ostrzeżenia, więc zapis idzie przy wyjściu
			_tick()
			_save()
			if net != null:
				net.flush()


## Nadrabia czas nieobecności i podaje w komunikacie, ile surowców przybyło.
func _catch_up(prefix: String) -> void:
	var before: Array[int] = []
	before.assign(economy.amounts)
	_tick()
	var parts: PackedStringArray = []
	for res in before.size():
		if economy.amounts[res] > before[res]:
			parts.append("+%d %s" % [economy.amounts[res] - before[res], EconomyConfig.SHORT_NAMES[res]])
	if not parts.is_empty():
		hud.message = prefix + " ".join(parts)
	_save()


## Zapisuje grę. Błąd zapisu nie przerywa gry, tylko trafia do logu.
func _save() -> void:
	if _restoring:
		return
	# posterunki rozwiązanych oddziałów (np. po stratach) nie trafiają do zapisu
	defense.prune(recruitment)
	var save := SaveGame.to_dict(world_seed, grid, economy, queue, research, goods, recruitment,
			pve_cleared, attack_plan, bots_beaten, defense, attack_target, seal_check, scouting, generals,
			target_refresh)
	var err := SaveGame.write(SaveGame.PATH, save)
	if err != OK:
		push_warning("Nie udało się zapisać gry: %s" % error_string(err))
	_sync_castle(save)


## Zasłona ładowania (#316): po przywróceniu zamku z serwera przykrywa pierwszą chwilę nowej sceny,
## a na starcie, na którym zamek prawie na pewno wróci, czeka na odpowiedź serwera. Ostatni węzeł
## sceny, więc dotyk trafia do niej przed wszystkim innym.
func _add_sync_loader() -> void:
	var loader_layer := CanvasLayer.new()
	loader_layer.layer = LOADER_LAYER
	add_child(loader_layer)
	sync_loader = SyncLoaderPanel.new()
	loader_layer.add_child(sync_loader)
	net.castle_checked.connect(sync_loader.on_castle_checked)
	if _restored_from_server:
		sync_loader.start_restore()
		sync_loader.finish()
	elif SyncCurtain.waits_at_start(net.state != SupabaseClient.State.DISABLED, net.local_fresh,
			net.sync_state.restore_pending_for(net.user_id())):
		sync_loader.start_waiting()
		sync_loader.on_net_state(net.state)  # brak sieci mógł się okazać już przy dodaniu klienta


## Ekran tytułowy Dunholm (#360) tylko przy pierwszym wczytaniu sceny w tym uruchomieniu gry;
## zamek pod nim wczytuje się i łączy z serwerem. Przeładowanie sceny go nie pokazuje.
func _add_title_screen() -> void:
	if TitleScreen.shown_this_run or (OS.is_debug_build() and OS.get_cmdline_user_args().has(BATTLE_PREVIEW_ARG)):
		return
	var title_layer := CanvasLayer.new()
	title_layer.layer = TITLE_LAYER
	add_child(title_layer)
	var title := TitleScreen.new()
	title_layer.add_child(title)
	title.play_pressed.connect(title_layer.queue_free)
	title.open()


## Stan sieci w Ustawieniach; po ONLINE zaległy zamek idzie na serwer od razu (#23).
## Okno aktualizacji (#336) na własnej warstwie nad zasłoną. Zapamiętana polityka działa od razu,
## także bez sieci, a serwer jest pytany przy każdym starcie.
func _add_update_panel() -> void:
	_update_layer = CanvasLayer.new()
	_update_layer.layer = UPDATE_LAYER
	add_child(_update_layer)
	update_panel = UpdatePanel.new()
	_update_layer.add_child(update_panel)
	update_panel.update_pressed.connect(_on_update_store)
	update_panel.retry_pressed.connect(_check_version)
	version_policy = ClientVersion.Policy.load_from()
	net.version_policy_loaded.connect(_on_version_policy)
	net.update_required.connect(_on_update_required)
	_apply_version_gate()
	_check_version()


func _check_version() -> void:
	_version_asked_s = int(Time.get_unix_time_from_system())
	if not net.check_version() and update_panel.mode == UpdatePanel.Mode.HARD:
		update_panel.set_note(UPDATE_OFFLINE_NOTE)


## Po powrocie z tła: przy blokadzie zawsze (gracz mógł wrócić ze sklepu), inaczej co godzinę.
func _maybe_check_version() -> void:
	if update_panel == null:
		return
	var now := int(Time.get_unix_time_from_system())
	if update_panel.mode == UpdatePanel.Mode.HARD or now - _version_asked_s >= ClientVersion.CHECK_INTERVAL_S:
		_check_version()


func _on_version_policy(policy: ClientVersion.Policy, ok: bool) -> void:
	if not ok:
		# bez odpowiedzi zostaje zapamiętana polityka (fail-open, gdy nigdy nie przyszła)
		if update_panel.mode == UpdatePanel.Mode.HARD:
			update_panel.set_note(UPDATE_OFFLINE_NOTE)
		return
	var was_hard := update_panel.mode == UpdatePanel.Mode.HARD
	policy.keep_soft_state(version_policy)
	policy.fetched_s = int(Time.get_unix_time_from_system())
	version_policy = policy
	net.clear_update_block()
	_save_version_policy()
	_apply_version_gate()
	if was_hard and update_panel.mode == UpdatePanel.Mode.HARD:
		update_panel.set_note(UPDATE_STILL_NOTE)


## Serwer odrzucił wersję gry (426), choć polityka jeszcze o tym nie wiedziała: blokada od razu.
func _on_update_required() -> void:
	if version_policy == null:
		version_policy = ClientVersion.Policy.new()
	version_policy.force_hard(ClientVersion.current_code())
	_save_version_policy()
	_apply_version_gate()


func _save_version_policy() -> void:
	if version_policy.save() != OK:
		push_warning("Nie udało się zapisać polityki wersji na telefonie")


## Blokada, komunikat (raz na 24 h dla danej wersji) albo nic, według polityki i wersji gry.
func _apply_version_gate() -> void:
	var code := ClientVersion.current_code()
	var now := int(Time.get_unix_time_from_system())
	var gate: int = version_policy.gate(code) if version_policy != null else ClientVersion.Gate.OK
	if gate == ClientVersion.Gate.HARD:
		if update_panel.mode != UpdatePanel.Mode.HARD:
			update_panel.open(UpdatePanel.Mode.HARD)
	elif update_panel.mode == UpdatePanel.Mode.HARD:
		update_panel.open(UpdatePanel.Mode.HIDDEN)  # minimum obniżone: gra wraca
	if gate == ClientVersion.Gate.SOFT and update_panel.mode == UpdatePanel.Mode.HIDDEN \
			and version_policy.soft_due(code, now):
		update_panel.open(UpdatePanel.Mode.SOFT)
		version_policy.mark_soft_shown(now)
		_save_version_policy()
	if update_panel.visible:
		# dotyk dostaje najpierw ostatni węzeł drzewa: okno ma być przed widokami dodanymi później (bitwa)
		move_child(_update_layer, -1)


func _on_update_store() -> void:
	for url in ClientVersion.store_urls(version_policy):
		if OS.shell_open(url) == OK:
			return
	update_panel.set_note(UPDATE_STORE_NOTE)


func _on_net_state(st: int) -> void:
	settings_panel.net_state = st
	if sync_loader != null:
		sync_loader.on_net_state(st)
	if st == SupabaseClient.State.ONLINE:
		net.flush()
		_load_defenses()
		_resume_finish()


## Pyta serwer o obrony z czasu, w którym ruiny mogą jeszcze stać (#99), i o historię obron (#328),
## z której wychodzi okienko o nowych atakach i kropka nad Obroną.
func _load_defenses() -> void:
	if net != null and net.is_online():
		net.load_defense_reports()
		@warning_ignore("integer_division")
		net.load_defenses(_now_s() - Ruins.rebuild_ms(grid.age()) / 1000)


## Obrony z serwera (#99): zniszczone budynki stają się ruinami w odbudowie. Komunikat tylko wtedy,
## gdy przybyły nowe ruiny (ponowny odczyt tych samych obron niczego nie zmienia).
func _on_defenses_loaded(rows: Array[Dictionary], ok: bool) -> void:
	if not ok:
		return
	var now := _now_ms()
	_tick()  # produkcja do teraz po starych stawkach, kara liczy się od chwili, gdy klient wie o ruinach
	var added := false
	for row in rows:
		added = ruins.add(row["ids"] as Array[int], int(row["at_ms"]), grid.age()) or added
	ruins.prune(now, grid)
	if added and not ruins.is_empty():
		hud.message = "Zamek zaatakowany: w odbudowie %d bud." % ruins.ends.size()
	_refresh_ruins(now)


## Synchronizacja zamku i obrony z serwerem (#23): klient trzyma najnowszy stan i wysyła go, gdy
## jest sieć. Bez tożsamości z onboardingu (#228) zamek nie idzie na serwer (żeby serwer nie dostał
## anonimowego zamku), ale może z niego wrócić po reinstalacji.
func _sync_castle(save: Dictionary) -> void:
	if net == null or net.state == SupabaseClient.State.DISABLED:
		return
	net.sync_castle(world_seed, SaveGame.FORMAT_VERSION, CastleSync.castle_data(save, identity),
			CastleSync.defense_data(save), identity.player_name if identity != null else "", identity != null)


## Serwer ma nowszy zamek niż telefon albo telefon nie ma zapisu (reinstalacja, #23): zamek, seed
## terenu i tożsamość wracają na telefon, a scena wczytuje się od nowa z tego zapisu.
func _on_castle_restored(save: Dictionary, profile: Dictionary) -> void:
	if SaveGame.from_dict(save, _now_ms()) == null:
		push_warning("Zamek z serwera jest nieczytelny, zostaje zamek z telefonu")
		_restore_failed()
		return
	# najpierw profil, na końcu zamek: plik zamku zmienia się tylko, gdy wszystko inne już się udało
	# (seed zamku jest grywalny, więc jako seed gracza daje ten sam teren, first_playable)
	var err := PlayerProfile.write_seed(PlayerProfile.PATH, int(save["world_seed"]))
	if err == OK and not profile.is_empty():
		err = PlayerProfile.write_identity(PlayerProfile.PATH, PlayerProfile.Identity.from_dict(profile))
	if err == OK:
		err = SaveGame.write(SaveGame.PATH, save)
	if err != OK:
		push_warning("Nie udało się zapisać zamku z serwera: %s" % error_string(err))
		_restore_failed()
		return
	net.confirm_restore()
	_restored_from_server = true
	_restoring = true
	if sync_loader != null:
		sync_loader.start_restore()
	get_tree().reload_current_scene()



## Zamek z serwera nie wrócił na telefon: gra zostaje przy zamku z telefonu, więc zasłona na starcie
## (#316) nie ma już na co czekać.
func _restore_failed() -> void:
	net.restore_failed()
	if sync_loader != null:
		sync_loader.finish()


static func _now_s() -> int:
	return int(Time.get_unix_time_from_system())


static func _now_ms() -> int:
	return int(Time.get_unix_time_from_system() * 1000.0)


## Dzień lokalny telefonu dla licznika odświeżeń celów (#313): zeruje się o północy.
static func _today() -> int:
	return TargetRefresh.local_day(_now_s(), int(Time.get_time_zone_from_system().get("bias", 0)))


## Kończy budowy, których czas minął, i nalicza produkcję do teraz. Wołane co klatkę i przed
## każdą zmianą budynków, żeby czas sprzed zmiany liczył się po starych stawkach.
func _tick() -> void:
	var now := _now_ms()
	defense.mark_traps(grid)  # budynek nie stanie na pułapce (#341), także przy uszczelnianiu po budowie
	var researching := research.active
	# towary po surowcach w każdym punkcie czasu: wytwórcy zużywają drewno i żywność naliczone do tej chwili
	var done := queue.update(now, grid, economy, research, goods, recruitment.army_upkeep(), ruins)
	_refresh_ruins(now)
	var deserted := recruitment.starve(economy, grid, research)
	if not deserted.is_empty():
		_save()
	for o in done:
		hud.message = "Ukończono: %s, poziom %s" % [BuildingTypes.NAMES[o.kind], Ages.short_level(o.level)]
		if o.kind == BuildingTypes.Kind.MANOR and Ages.is_age_step(o.level):
			_on_new_age(now)
	# koniec badania to zmiana trwającego kodu (poziom doktryny był zbadany już wcześniej)
	if not researching.is_empty() and research.active != researching and research.is_done(researching):
		hud.message = "Zbadano: %s" % ResearchPanel.title_of(research, researching)
		_save()
	if research_panel != null:
		research_panel.now_ms = now
	if recruit_panel != null:
		recruit_panel.now_ms = now
	if queue_panel != null:
		queue_panel.now_ms = now
	var trained := recruitment.update(now)
	for unit in trained:
		hud.message = "Wyszkolono: %s" % UnitTypes.unit_name(unit)
	# głód na końcu, żeby „Ukończono” ani „Wyszkolono” z tej samej klatki go nie przykryły
	if not deserted.is_empty():
		hud.message = "Głód: z armii odeszło %d (brak żywności)" % deserted.size()
	if not trained.is_empty():
		_save()
	var scouted := scouting.update(now, recruitment)
	_poll_scout_reports(now)
	_poll_resume_finish()
	if scouted != null:
		hud.message = Scouting.report_text(scouted)
		_save()
	if target_picker != null and target_picker.visible:
		_refresh_scout_lines()
		_refresh_targets_button()
	var checked := false
	if _has_ready_seal_house():
		checked = seal_check.update(now, grid)
		if checked:
			seal_check.prune(grid)
			if seal_check.gaps.is_empty():
				hud.message = "Obrona szczelna"
			else:
				hud.message = "Wykryte luki: %d, dotknij luki" % seal_check.gaps.size()
			_save()
		elif seal_check.revealed:
			seal_check.prune(grid)
	elif seal_check.revealed or seal_check.is_busy():
		seal_check.clear()
	hud.queue_text = ""
	hud.queue_count = queue.orders.size() + recruitment.orders.size()
	_refresh_tutorial()
	hud.research_text = "" if not research.is_busy() else "Bad. %s" % Hud.format_time(research.remaining_ms(now))
	hud.age_text = Ages.label_for_manor(grid.manor_level())
	if not queue.orders.is_empty():
		hud.queue_text = Hud.format_time(queue.remaining_ms(queue.orders[0].building_id, now))
		if queue.orders.size() > 1:
			hud.queue_text += " +%d" % (queue.orders.size() - 1)
	if not done.is_empty() or checked or scouted != null:
		if not done.is_empty():
			_save()
		if _selected_id != 0:
			_refresh_card()
		queue_redraw()
	elif seal_check.is_busy() and _selected_id != 0 \
			and int(grid.kinds.get(_selected_id, -1)) == BuildingTypes.Kind.SEAL_HOUSE:
		# odliczanie Sprawdź na karcie Komendy; mapa się nie zmienia
		_refresh_card()
	elif scouting.is_busy() and _selected_id != 0 \
			and int(grid.kinds.get(_selected_id, -1)) == BuildingTypes.Kind.SCOUT_HOUSE:
		# odliczanie zwiadu na karcie Chaty tropicieli (#28)
		_refresh_card()


## Przebudowa Dworu skończona, czyli zamek wszedł w nową epokę (#34). Zamek, budynki i premie
## zostają; panele badań i wojska dostają nową epokę, a nad Dworem gra animacja przebudowy.
func _on_new_age(now_ms: int) -> void:
	var age := grid.age()
	research_panel.age = age
	recruit_panel.age = age
	_age_anim_start_ms = now_ms
	hud.message = "%s! Budynki z poz. 5 wejdą w nową epokę" % Ages.age_name(age)


## Dotknięcie mapy. W trybie oglądania zaznacza budynek (albo zamyka kartę), w trybie budowy
## tylko stawia wybrany budynek i niczego nie zaznacza.
func _on_tapped(world_pos: Vector2) -> void:
	if battle_view != null:
		return  # w trakcie fali tylko tempo (#16)
	if planner.visible:
		_on_plan_changed(AttackPlanner.tap(planner.order(), planner.bot.grid, Vector2i((world_pos / TerrainMap.CELL).floor()),
				planner.intel))
		return
	if defense_panel.visible:
		_on_defence_changed(defense_panel.tap(grid, Vector2i((world_pos / TerrainMap.CELL).floor())))
		return
	_tick()
	var cell := Vector2i((world_pos / TerrainMap.CELL).floor())
	var id := grid.building_at(cell)
	if not hud.building:
		if _try_select_gap(world_pos):
			return
		if id != 0:
			_select(id)
		elif _selected_id != 0:
			_deselect()
		queue_redraw()
		return
	if id != 0 and BuildGrid.replaces_walls(hud.selected_kind) and BuildingTypes.is_wall(grid.kinds[id]):
		id = 0  # brama albo wieża na wale lub palisadzie: zastępuje odcinki w linii (po teście na telefonie)
	var length := hud.build_length()
	if id != 0 and BuildingTypes.is_wall(hud.selected_kind) and length == 1:
		# palec w wąskiej luce linii umocnień trafił w sąsiedni odcinek: budujemy w luce
		var gap := grid.gap_near(world_pos, hud.selected_kind, GAP_TAP_TOLERANCE)
		if gap.x >= 0:
			cell = gap
			id = 0
	if id != 0:
		hud.message = "Tu stoi %s" % BuildingTypes.NAMES[grid.kinds[id]]
	else:
		var kind := hud.selected_kind
		var result := queue.order_build(grid, economy, cell, kind, _now_ms(), research, length, hud.segment_vertical)
		_cursor_ok = result == BuildQueue.Result.OK
		# przy nieudanej próbie ramka ma kształt pierwszego wariantu (np. pionowej bramy)
		_cursor = grid.buildings[queue.placed_id] if _cursor_ok else grid.placement_candidates(cell, kind, true)[0]
		if length > 1:
			# odcinek wału albo palisady (#371): ramka na wszystkie kratki od dotkniętej
			_cursor = Rect2i(cell, Vector2i(1, length) if hud.segment_vertical else Vector2i(length, 1))
		if _cursor_ok:
			hud.message = "Budowa: %s, %s" % [BuildingTypes.NAMES[kind], Hud.format_time(queue.orders.back().duration_ms)]
			_save()
		elif result == BuildQueue.Result.NEEDS_TECH:
			hud.message = _tech_hint(kind)
		elif result == BuildQueue.Result.NO_PLACE and _lacks_water(cell, kind):
			hud.message = WATER_HINT % BuildingTypes.NAMES[kind]
		else:
			hud.message = queue.message(result)
	queue_redraw()


## Czas budowy poziomu `level` z perkiem władcy `perk` (Budowniczy -10%, #32), jak w kolejce.
static func _build_time(kind: int, level: int, perk: int = RulerPerks.Perk.NONE) -> int:
	return RulerPerks.build_time_ms(BuildConfig.time_ms(kind, level), perk)


## Panel budowy (Buduj w trybie oglądania albo Zmień w trybie budowy).
func _on_build_panel_opened() -> void:
	_tick()
	_selected_id = 0
	build_panel.ruler_perk = grid.ruler_perk
	hud.hide_card()
	hud.overlay = true
	build_panel.select(hud.selected_kind)
	build_panel.open()
	hud.message = "Wybierz budynek"
	queue_redraw()


## Postaw z panelu budowy: tryb budowy z wybranym budynkiem, kolejne dotknięcia mapy go stawiają.
func _on_place_requested(kind: int) -> void:
	hud.overlay = false
	hud.selected_kind = kind
	hud.set_building(true)
	hud.message = build_message(kind, grid.ruler_perk, hud.build_length())
	queue_redraw()


## Zamknij w panelu budowy. Otwarty przez Zmień (w trybie budowy) wraca do stawiania dotychczasowego
## budynku z jego kosztem w komunikacie; otwarty przez Buduj wraca do oglądania (review #160).
func _on_build_panel_closed() -> void:
	hud.overlay = false
	hud.message = closed_message(hud.building, hud.selected_kind, grid.ruler_perk, hud.build_length())
	queue_redraw()


## Komunikat trybu budowy: nazwa, koszt i czas wybranego budynku (z perkiem władcy `perk`). Odcinek
## wału albo palisady z `length` kratek (#371) ma koszt z dopłatą w złocie i czas ×długość.
static func build_message(kind: int, perk: int = RulerPerks.Perk.NONE, length: int = 1) -> String:
	var level := BuildConfig.start_level(kind)
	var n := length if BuildingTypes.is_wall(kind) else 1
	return "%s: %s, %s" % [BuildingTypes.NAMES[kind], Hud.cost_text(BuildConfig.segment_cost(kind, level, n)),
			Hud.format_time(_build_time(kind, level, perk) * n)]


## Komunikat po zamknięciu panelu budowy bez Postaw.
static func closed_message(building: bool, kind: int, perk: int = RulerPerks.Perk.NONE, length: int = 1) -> String:
	return build_message(kind, perk, length) if building else DEFAULT_MESSAGE


## Czy Rybak albo Młyn nie staje tylko przez brak wody: ten sam prostokąt bez warunku wody byłby wolny
## (review PR 143). Przy innych przeszkodach zostaje zwykły komunikat „Tu nie można budować”.
func _lacks_water(cell: Vector2i, kind: int) -> bool:
	if not BuildingTypes.needs_water(kind):
		return false
	var rect := Rect2i(cell, BuildingTypes.size_of(kind))
	return grid.can_place(rect) and not grid.touches_water(rect)


## Komunikat o brakującej technologii, np. „Chata myśliwego: zbadaj G18 Łowiectwo”.
func _tech_hint(kind: int) -> String:
	var tech := BuildConfig.required_tech(kind)
	return "%s: zbadaj %s %s" % [BuildingTypes.NAMES[kind], tech, TechTree.tech_name(tech)]


func _select(id: int) -> void:
	_selected_id = id
	_cursor = Rect2i()
	_refresh_card()
	hud.message = queue.upgrade_hint(grid, id, research)


func _deselect() -> void:
	_selected_id = 0
	hud.hide_card()
	hud.message = DEFAULT_MESSAGE
	queue_redraw()


## Zmiana długości albo orientacji odcinka (#371): koszt i czas w komunikacie, bez starej ramki.
func _on_segment_changed() -> void:
	_cursor = Rect2i()
	hud.message = build_message(hud.selected_kind, grid.ruler_perk, hud.build_length())
	queue_redraw()


## Wejście w tryb budowy zamyka kartę; wyjście czyści ramkę ostatniej próby.
func _on_build_mode_changed(building: bool) -> void:
	_selected_id = 0
	hud.hide_card()
	_cursor = Rect2i()
	if not building:
		hud.message = DEFAULT_MESSAGE
	queue_redraw()


## Oblężenie (#16): startuje kolejną falę samouczka na zamku gracza.
func _on_siege_pressed() -> void:
	_tick()
	var problem := siege_problem(pve_cleared, recruitment.battle_squads().size(), grid.keep_id())
	if not problem.is_empty():
		hud.message = problem
		return
	_selected_id = 0
	hud.hide_card()
	hud.set_building(false)
	_cursor = Rect2i()
	_battle_wave = pve_cleared
	_battle_ids = recruitment.battle_ids()
	_wave_begin(_battle_wave)
	var b := Battle.for_castle_squads(grid, PveWaves.squads(_battle_wave), recruitment.battle_squads(), _edge_road(),
			PveWaves.battle_seed(world_seed, _battle_wave), research,
			defense.battle_orders(_battle_ids, recruitment.battle_squads(), grid, grid.age()),
			defense.tower_priority)
	b.arm_traps(defense.battle_traps(grid, research, grid.age()))  # pułapki działają raz na bitwę, a w układzie zostają (odnawiają się, #100)
	b.apply_research(Battle.Side.DEFENDER, research)  # A2 łuki i O2 palisady obrońcy (#12)
	b.set_general(Battle.Side.DEFENDER, defense.commander_general(generals))  # komendant obrony (#31)
	battle_view = BattleView.new()
	battle_view.battle = b
	battle_view.states_changed.connect(_on_battle_states)
	add_child(battle_view)
	hud.battle = true
	hud.speed_label = speed_label(battle_view.speed)
	camera.look_at_world(Vector2(grid.buildings[grid.keep_id()].get_center() * TerrainMap.CELL))
	hud.message = "Fala %d/%d: %d wrogów idzie na donżon" % [_battle_wave + 1, PveWaves.COUNT, PveWaves.size(_battle_wave)]
	queue_redraw()


## Dlaczego nie da się zacząć fali, albo pusty tekst. Samouczek uczy rekrutacji: bez wojska fala
## nie rusza (#16).
static func siege_problem(cleared: int, squads: int, keep_id: int) -> String:
	if cleared >= PveWaves.COUNT:
		return Hud.SIEGE_LATER_MESSAGE
	if keep_id == 0:
		return KEEP_NO_ROOM
	if squads == 0:
		return "Najpierw wyszkol wojsko: Koszary i Wojsko"
	return ""


func _on_speed_pressed() -> void:
	if battle_view == null:
		return
	battle_view.speed = next_speed(battle_view.speed)
	hud.speed_label = speed_label(battle_view.speed)


## Tempo bitwy: 1 → 2 → 4 → 1.
static func next_speed(speed: int) -> int:
	return 1 if speed >= 4 else speed * 2


static func speed_label(speed: int) -> String:
	return "Tempo x%d" % speed


## Pasek i koniec fali: czas do limitu w prawym górnym rogu, po końcu wynik, nagroda i zapis.
## Komunikat po fali: wynik, polegli (gdy są) i nagroda za wygraną. Pusta nagroda przy wygranej to fala
## poza serwerem (#288: bez sieci albo odmowa), która nagrody nie daje.
static func wave_end_message(wave: int, won: bool, reward: Array[int], fallen: int) -> String:
	if won and reward.is_empty():
		if fallen > 0:
			return "Fala %d obroniona, polegli: %d. Bez nagrody" % [wave + 1, fallen]
		return "Fala %d obroniona poza serwerem: bez nagrody" % (wave + 1)
	if won:
		if fallen > 0:
			return "Fala %d obroniona, polegli: %d. +%s" % [wave + 1, fallen, Hud.cost_text(reward)]
		return "Fala %d obroniona! +%s" % [wave + 1, Hud.cost_text(reward)]
	if fallen > 0:
		return "Fala %d przegrana, polegli: %d. Wzmocnij obronę" % [wave + 1, fallen]
	return "Fala %d przegrana: wzmocnij obronę" % (wave + 1)


func _update_battle() -> void:
	var b := battle_view.battle
	var left_ms := (BattleConfig.time_limit_ticks() - b.tick) * 1000 / BattleConfig.TICK_HZ
	var label := "Atak" if _attacking else "Fala %d" % (_battle_wave + 1)
	if _replaying:
		label = "Powtórka"
	hud.queue_text = "%s %s" % [label, Hud.format_time(left_ms)]
	if b.winner == Battle.Winner.NONE:
		return
	if _replaying:
		_finish_replay(b)
		return
	if _attacking:
		_finish_attack(b)
		return
	# polegli znikają z armii, ocalali (także wycofani) wracają do swoich oddziałów (#164)
	var fallen := recruitment.apply_losses(_battle_ids, b.survivors(Battle.Side.DEFENDER))
	var won := b.winner == Battle.Winner.DEFENDER
	# Nagrodę dopisuje tylko serwer (#288): komunikat pokazuje tę, która czeka na przyjęcie wyniku, a do
	# magazynu wchodzi z odpowiedzi na najbliższy zapis (`loot_applied`). Fala bez sieci odblokowuje
	# następną, ale nic nie daje.
	# literał `[]` w trójargumentowym `if` jest nietypowany i nie da się go przypisać do Array[int]
	var reward: Array[int] = []
	if won and _wave.online():
		reward = PveWaves.reward(_battle_wave)
	_wave_send(_wave.finish(won))
	if won:
		pve_cleared = maxi(pve_cleared, _battle_wave + 1)
	hud.message = wave_end_message(_battle_wave, won, reward, fallen)
	if won and _battle_wave == PveWaves.COUNT - 1:
		hud.message = TutorialGoals.done_message(reward, fallen)  # koniec prowadzenia (#185), dalej zwykła gra
		_set_tutorial(TutorialHints.State.DONE)
	var xp := generals.add_battle_xp(defense.commander, won) if b.generals.has(Battle.Side.DEFENDER) else 0
	if xp > 0:
		hud.message += xp_note(xp)
	battle_view.queue_free()
	battle_view = null
	_on_battle_states({})  # po bitwie zamek znów jest cały
	hud.battle = false
	_battle_wave = -1
	_save()
	queue_redraw()


# --- Atak na zamek-cel (#17) -----------------------------------------------------------------------

## Oddziały armii, które idą do ataku: pierwsze tyle, ile mieści plan w bieżącej epoce.
## Armia ataku: oddziały w limicie epoki, a z nich tyle, ile mieści się w limicie miejsc i utrzymania
## zamku (#249, ten sam warunek sprawdza serwer przy starcie ataku na gracza).
## Komunikat, gdy do ataku nie ma kogo wysłać: bez wojska albo cała armia w garnizonie Dworu (#81).
func _no_army_message() -> String:
	if not recruitment.battle_squads().is_empty():
		return "Całe wojsko w garnizonie Dworu: zmień w Obronie"
	return "Najpierw wyszkol wojsko: Koszary i Wojsko"


## Garnizon Dworu (#81) zostaje w zamku.
func _attack_army() -> Array:
	var army := recruitment.battle_squads(defense.garrison_ids())
	return Recruitment.fit_attack(army.slice(0, AttackPlan.max_squads(grid.age())), grid, research)


## Zamek-bot wybrany jako cel Wyprawy (z pamięci, gdy plan pokazuje już ten zamek).
func _bot() -> BotCastle:
	if planner.bot != null and planner.bot.index == attack_target \
			and planner.bot.seed_value == BotRoster.seed_of(attack_target):
		return planner.bot
	return BotRoster.generate(attack_target)


## Wyprawa (karta Strażnicy): najpierw 3 cele (#24), gracze z serwera i zamki-boty. Bez wojska
## ekran się nie otwiera.
func _on_attack_pressed() -> void:
	_tick()
	if _attack_army().is_empty():
		hud.message = _no_army_message()
		return
	_selected_id = 0
	hud.hide_card()
	hud.set_building(false)
	_cursor = Rect2i()
	# bez tożsamości zamek nie jest na serwerze (#23), więc gracz i tak nie szuka przeciwników
	var online := net != null and identity != null and net.is_online()
	target_picker.open(bots_beaten, online)
	if online and not net.find_targets():
		target_picker.set_players([] as Array[TargetSearch.Target], false)
	_refresh_scout_lines()
	_refresh_targets_button()
	hud.overlay = true
	hud.message = "Wybierz cel ataku"
	queue_redraw()


## Ranking (karta Strażnicy, #27): tabela PvP z epoki gracza. Bez tożsamości zamek nie jest na
## serwerze (#23), więc gracza i tak nie ma w rankingu; tabela wymaga sieci.
func _on_ranking_pressed() -> void:
	_tick()
	_selected_id = 0
	hud.hide_card()
	hud.set_building(false)
	_cursor = Rect2i()
	hud.overlay = true
	ranking_panel.open(grid.age(), net != null and identity != null and net.is_online())
	queue_redraw()


## Widok rankingu bez tabeli w pamięci: prośba do serwera (wynik w `ranking_loaded`).
func _on_ranking_kind(kind: int) -> void:
	if net == null or not net.load_ranking(kind):
		ranking_panel.set_rows(kind, [] as Array[RankingBoard.Row], false)


func _on_ranking_message(text: String) -> void:
	if ranking_panel.visible:
		hud.message = text


## Stan zwiadu (#28) pod kartami celów i czy przycisk Zwiad jest czynny, dla wybranego celu.
## Nowe (#313): cena i dostępność przycisku z licznika dnia, złota i stanu sieci.
func _refresh_targets_button() -> void:
	var today := _today()
	var cost := target_refresh.cost(today)
	var online := net != null and identity != null and net.is_online()
	var affordable := target_refresh.can_afford(economy, today)
	if cost != target_picker.refresh_cost or online != target_picker.refresh_online \
			or affordable != target_picker.refresh_affordable:
		target_picker.refresh_cost = cost
		target_picker.refresh_online = online
		target_picker.refresh_affordable = affordable
		target_picker.queue_redraw()


## Nowe (#313): szuka innych celów. Złoto schodzi dopiero po udanym szukaniu (_on_targets_found).
func _on_targets_refresh() -> void:
	_tick()
	_refresh_targets_button()
	if not target_refresh.can_afford(economy, _today()):
		hud.message = "Za mało złota na nowe cele"
		return
	if not target_picker.refresh_enabled():
		return
	target_picker.begin_refresh()
	if not net.find_targets():
		target_picker.set_players([] as Array[TargetSearch.Target], false)
		hud.message = "Brak sieci: złoto zostaje"
	_refresh_targets_button()


## Wynik szukania celów. Przy płatnym odświeżeniu (#313) udane szukanie pobiera złoto, a nieudane
## (albo złoto, które w międzyczasie zniknęło) zostawia starą listę bez opłaty.
func _on_targets_found(players: Array[TargetSearch.Target], ok: bool, limited: bool) -> void:
	# panel ukryty w trakcie odświeżenia (Boty, Planuj): odpowiedź przepada bez opłaty
	if target_picker.is_refreshing() and not target_picker.visible:
		target_picker.cancel_refresh()
		return
	if target_picker.is_refreshing():
		_tick()
		var cost := target_refresh.cost(_today())
		if not ok:
			hud.message = "Za często: złoto zostaje" if limited else "Brak odpowiedzi: złoto zostaje"
		elif target_refresh.pay(economy, _today()):
			hud.message = "Nowe cele: -%d złota" % cost
			_save()
		else:
			ok = false
			hud.message = "Za mało złota na nowe cele"
	target_picker.set_players(players, ok, limited)
	_refresh_targets_button()


func _refresh_scout_lines() -> void:
	var t := target_picker.selected_target()
	if t == null:
		target_picker.scout_lines = []
		target_picker.scout_enabled = false
		target_picker.queue_redraw()
		return
	var check := scouting.check(grid, research, recruitment, economy)
	var lines := scout_lines(t, scouting, check, Scouting.available(recruitment), target_picker.scout_duration,
			research.is_done(Scouting.BETTER_TECH), _now_ms(), net != null and identity != null and net.is_online())
	var online := net != null and identity != null and net.is_online()
	var enabled := (t.is_bot or online) and check == Scouting.Result.OK
	if lines != target_picker.scout_lines or enabled != target_picker.scout_enabled:
		target_picker.scout_lines = lines
		target_picker.scout_enabled = enabled
		target_picker.queue_redraw()


## Dwie linie stanu zwiadu (#28) dla celu `t`: co wiadomo (misja w drodze, raport albo nic) i co
## da zwiad teraz (zwiadowcy, procent zamku i koszt) albo czemu się nie da.
static func scout_lines(t: TargetSearch.Target, s: Scouting, check: Scouting.Result, units: Dictionary[int, int],
		duration: int, s3: bool, now_ms: int, online: bool = false) -> Array[String]:
	var out: Array[String] = []
	var rep := s.report_for(t.key())
	if s.is_busy() and s.mission.target_key == t.key():
		var left := s.remaining_ms(now_ms)
		out.append("Zwiad w drodze: %s" % Hud.format_time(left) if left > 0 else "Zwiad wrócił: czekam na raport")
	elif rep != null:
		out.append(Scouting.report_text(rep))
	else:
		out.append("Bez zwiadu: zamek zakryje mgła")
	if not t.is_bot and not online:
		# zwiad na gracza liczy serwer (#28)
		out.append("Zwiad na gracza: wymaga sieci")
	elif check != Scouting.Result.OK:
		if s.is_busy() and s.mission.target_key != t.key():
			out.append("Zwiadowcy w drodze: %s" % s.mission.target_name)
		else:
			out.append(Scouting.MESSAGES[check])
	else:
		var n := Scouting.count_of(units)
		out.append("%d zwiad., %d%% zamku, koszt %s" % [n, ScoutConfig.reveal_percent(duration, n, s3),
				Hud.cost_text(ScoutConfig.cost(n))])
	return out


## Zwiad (#28) z ekranu celów: zwiadowcy wychodzą z armii, raport czeka w Chacie tropicieli.
func _on_scout_requested(t: TargetSearch.Target, duration: int) -> void:
	_tick()
	if not t.is_bot:
		_send_player_scout(t, duration)
		return
	var r := scouting.send(t.key(), t.castle_name, duration, world_seed, _now_ms(), grid, research, recruitment,
			economy)
	if r == Scouting.Result.OK:
		hud.message = "Zwiad wyruszył: %s, %s" % [t.castle_name, Hud.format_time(ScoutConfig.duration_ms(duration))]
		_save()
	else:
		hud.message = Scouting.MESSAGES[r]
	_refresh_scout_lines()


## Zwiad na gracza (#28): te same warunki co lokalnie, a wynik losuje i trzyma serwer. Serwer
## sprawdza Chatę, S1 i zwiadowców z zamku na serwerze, więc najpierw idzie zaległy zapis.
func _send_player_scout(t: TargetSearch.Target, duration: int) -> void:
	var check := scouting.check(grid, research, recruitment, economy)
	if check != Scouting.Result.OK:
		hud.message = Scouting.MESSAGES[check]
		return
	if net == null or identity == null or not net.is_online():
		hud.message = ScoutNet.error_message(SupabaseClient.NETWORK_ERROR)
		return
	net.flush()
	if not net.send_scout(t.player_id, duration):
		hud.message = "Poczekaj chwilę na serwer"
		return
	_scout_target = t
	_scout_duration = duration
	hud.message = "Wysyłam zwiad: %s" % t.castle_name


func _on_scout_sent(send: Dictionary, error: String) -> void:
	var t := _scout_target
	_scout_target = null
	if t == null:
		return
	if not error.is_empty():
		hud.message = ScoutNet.error_message(error)
		return
	_tick()
	scouting.start_remote(str(send["id"]), t.key(), t.castle_name, _scout_duration,
			send["units"] as Dictionary[int, int], int(send["remaining_s"]) * 1000, _now_ms(), recruitment, economy)
	hud.message = "Zwiad wyruszył: %s, %s" % [t.castle_name, Hud.format_time(int(send["remaining_s"]) * 1000)]
	_save()
	_refresh_scout_lines()


## Zaległy wynik ataku na gracza (#99) idzie na serwer, gdy nic innego nie trwa: bez bitwy, planu
## ataku na gracza, wysyłanego wyniku i wyprawy w drodze. Okno wyniku pokaże odpowiedź serwera.
func _resume_finish() -> void:
	if _pending.is_empty() or _finish_result != null or _player != null or _attacking or _pve_sending \
			or not _pve.is_idle() or net == null or not net.is_online() or net.is_attack_pending():
		return
	var r := _pending.result()
	if r == null:
		_pending = PendingFinish.new()
		PendingFinish.clear()
		return
	_finish_result = r
	_finish_body = _pending.body
	_finish_fallen = _pending.fallen
	_finish_tries = 0
	_finish_resumed = true
	_send_finish()


func _poll_resume_finish() -> void:
	if _pending.is_empty():
		return
	var t := Time.get_ticks_msec() / 1000.0
	if t < _resume_poll_s:
		return
	_resume_poll_s = t + RESUME_POLL_S
	_resume_finish()


## Misja na gracza skończona: co SCOUT_POLL_S pytamy serwer o raport.
func _poll_scout_reports(now_ms: int) -> void:
	if not scouting.remote_due(now_ms) or net == null or not net.is_online() or net.is_scout_pending():
		return
	var t := Time.get_ticks_msec() / 1000.0
	if t < _scout_poll_s:
		return
	_scout_poll_s = t + SCOUT_POLL_S
	net.load_scout_reports()


func _on_scout_reports(rows: Array[Dictionary], ok: bool) -> void:
	if not ok:
		return
	var rep := scouting.apply_reports(rows, recruitment, _now_ms())
	if rep != null:
		hud.message = Scouting.report_text(rep)
		_save()
		if _selected_id != 0:
			_refresh_card()
		if target_picker.visible:
			_refresh_scout_lines()


## Boty (ekran 3 celów): pełna lista zamków-botów, 20 na epokę (#26, #230).
func _open_bot_list() -> void:
	target_picker.visible = false
	bot_picker.open(bots_beaten, attack_target)
	hud.message = "Zdobyte: %d z %d zamków" % [mini(bots_beaten, BotRoster.COUNT), BotRoster.COUNT]
	queue_redraw()


## Wróć z listy botów: z powrotem do 3 celów.
func _on_bot_list_closed() -> void:
	target_picker.visible = true
	hud.message = "Wybierz cel ataku"
	queue_redraw()


## Karta gracza (#240): serwer zaczyna atak (`start_attack`) i oddaje kopię zamku i obrony gracza,
## a plan otwiera się dopiero z tą kopią. Do odpowiedzi ekran celów zostaje, a armia jest nietknięta.
func _on_player_target(target: TargetSearch.Target) -> void:
	if _starting:
		return
	var army := _attack_army()
	if army.is_empty():
		hud.message = _no_army_message()
		return
	if net == null or not net.is_online():
		hud.message = AttackStart.error_message(SupabaseClient.NETWORK_ERROR)
		return
	if _pending.blocks_start(true):
		# nowy start porzuciłby atak z zaległym wynikiem (review #283)
		_resume_finish()
		hud.message = PendingFinish.WAIT_MESSAGE
		return
	# serwer sprawdza armię z kopii zamku na serwerze: najpierw zaległy zapis (#23)
	net.flush()
	if not net.start_attack(target.player_id, army):
		hud.message = "Poczekaj chwilę na serwer"
		return
	_starting = true
	_player_army = army
	hud.message = "Łączę z zamkiem: %s" % target.castle_name


func _on_player_attack_started(start: Dictionary, error: String) -> void:
	if _pve.state == PveReport.State.STARTING:
		_pve_send(_pve.on_started(start, error))
		return
	_starting = false
	if not target_picker.visible:
		# gracz wyszedł z Wyprawy przed odpowiedzią: atak na serwerze wygaśnie sam, ale cel i tak
		# wróci dopiero po dobie, więc gracz ma o tym wiedzieć
		if error.is_empty() and not _attacking and battle_view == null:
			hud.message = ABANDONED_MESSAGE
		return
	if not error.is_empty():
		hud.message = AttackStart.error_message(error)
		return
	var pc := PlayerCastle.from_start(start, _player_army, _now_s(), grid.age())
	if pc == null:
		hud.message = "Zamek gracza jest nieczytelny. Wybierz inny cel"
		return
	_open_target(pc.target, pc)
	hud.message = "Zamek gracza: zaplanuj atak w %d min" % PlayerCastle.PLAN_LIMIT_MIN


## Planuj: ekran planu na wybranym zamku-bocie.
func _open_attack(index: int) -> void:
	var changed := index != attack_target or _player != null
	attack_target = index
	if changed:
		for o in attack_plan.orders:
			AttackPlanner.clear(o)
	_open_target(_bot(), null)


## Ekran planu na zamku `bot` (zamek-bot albo kopia zamku gracza `player`). Zmiana celu czyści cele
## i trasy oddziałów z planu. Przy graczu plan dotyczy armii wysłanej w `start_attack`.
func _open_target(bot: BotCastle, player: PlayerCastle) -> void:
	if player != null:
		for o in attack_plan.orders:
			AttackPlanner.clear(o)  # cele i trasy z innego zamku nie pasują do tej mapy
	_player = player
	var army := player.army if player != null else _attack_army()
	bot_picker.visible = false
	target_picker.visible = false
	planner.open(bot, attack_plan, army, grid.age(), _scout_intel(bot, player, army))
	attack_panel.generals = generals
	attack_panel.commander = defense.commander
	generals.set_attack(generals.attack_kind, defense.commander)
	attack_panel.visible = true
	hud.overlay = true
	camera.look_at_world(Vector2(bot.grid.buildings[bot.objective].get_center() * TerrainMap.CELL))
	var all := recruitment.battle_squads(defense.garrison_ids()).size()
	var by_age := mini(all, AttackPlan.max_squads(grid.age()))
	if all <= army.size():
		hud.message = AttackPlanner.HINT
	elif army.size() < by_age:
		hud.message = "W ataku %d z %d oddziałów (limit armii)" % [army.size(), all]
	else:
		hud.message = "W ataku %d z %d oddziałów (limit epoki)" % [army.size(), all]
	queue_redraw()


## Bitwa na zamku-bocie `bot` z armią `army`, przed planem i badaniami.
func _bot_battle(bot: BotCastle, army: Array) -> Battle:
	return Battle.create_squads(bot.grid, bot.objective, army, bot.defenders, bot.spawn,
			PixelCanvas.hash2(bot.seed_value, attack_target, 0xa77) & 0x7fffffff)


## Co plan ataku widzi z zamku-celu (#28): fragment z raportu zwiadu na ten cel, z miejscami załogi
## z początku bitwy (te same, z których ruszy bitwa), patrolami i pułapkami obrońcy. Bez raportu
## z danymi: cały zamek we mgle (#355).
func _scout_intel(bot: BotCastle, player: PlayerCastle, army: Array) -> ScoutIntel:
	if player != null:
		# zamek gracza (#28): odsłonięte przez zwiad podaje serwer w `start_attack`
		return player.intel
	var rep := scouting.report_for("bot:%d" % bot.index)
	if rep == null or not rep.has_intel():
		return ScoutIntel.new()
	var area := ScoutIntel.region_of(ScoutIntel.castle_rect(bot.grid), rep.percent, rep.region_seed)
	return ScoutIntel.build(area, ScoutIntel.defender_posts(_bot_battle(bot, army)), null)


func _on_plan_changed(message: String) -> void:
	hud.message = message
	planner.queue_redraw()
	_save()


## Wróć z ekranu planu. Przy graczu (#240) atak na serwerze jest już zaczęty: klient go porzuca
## (nowy start albo 10 minut zwalnia cel), a gracz dowiaduje się, że ten cel wróci dopiero po dobie
## (serwer liczy start jako atak na ten zamek, `target_recent`).
func _on_attack_back() -> void:
	var abandoned := _player != null
	_player = null
	_close_attack()
	if abandoned:
		hud.message = ABANDONED_MESSAGE


## Wróć: koniec planowania, widok własnego zamku. Plan zostaje zapisany.
func _close_attack() -> void:
	planner.visible = false
	attack_panel.visible = false
	hud.overlay = false
	hud.message = DEFAULT_MESSAGE
	camera.look_at_world(Vector2(grid.buildings[grid.manor_id()].get_center() * TerrainMap.CELL))
	_save()
	queue_redraw()


## Czy trwająca bitwa toczy się na mapie celu (AttackPlanner): atak albo powtórka obrony (#29) na kopii
## zamku z chwili ataku. Fala PvE idzie na własnym zamku.
func _on_target_map() -> bool:
	return _attacking or _replaying


## Stan zniszczeń z bitwy: przy Wyprawie i powtórce rysuje go mapa celu (AttackPlanner), w obronie własny zamek.
func _on_battle_states(states: Dictionary) -> void:
	if _on_target_map():
		planner.states = states
		planner.queue_redraw()
	else:
		planner.states = {}
		battle_states = states
		queue_redraw()


## Atakuj: bitwa na zamku-celu według planu. Ekran planu chowa się, a mapa celu zostaje.
func _on_attack_launched() -> void:
	var army := _attack_army()
	var problem := attack_plan.problem(army.size(), grid.age(), research, AttackPlanner.unit_list(army))
	if army.is_empty():
		problem = _no_army_message()
	if problem.is_empty() and _player != null:
		problem = player_attack_problem(_player, army, _now_s())
	if not problem.is_empty():
		hud.message = problem
		return
	if _player != null and not _player.is_launched():
		# pełne ukrycie obrony (#28): kopie zamku i obrony dopiero po zatwierdzeniu planu
		if _launching:
			return
		# plan idzie na serwer (#29): bitwa i powtórka u obrońcy liczą się z planu, który serwer zapisze
		if net == null or not net.launch_attack(_player.attack_id, attack_plan, generals.attack_kind):
			hud.message = AttackStart.error_message(SupabaseClient.NETWORK_ERROR)
			return
		_launching = true
		hud.message = "Zatwierdzam plan na serwerze"
		return
	if _player == null and _pending.blocks_start(net != null and net.is_online()):
		# start wyprawy na serwerze porzuciłby atak z zaległym wynikiem (review #283)
		_resume_finish()
		hud.message = PendingFinish.WAIT_MESSAGE
		return
	var bot := planner.bot
	_battle_ids = recruitment.battle_ids(defense.garrison_ids()).slice(0, army.size())
	_battle_army = army
	var b: Battle
	if _player != null:
		# seed bitwy, obrona, plan i badania z serwera (#240, #29): ta sama bitwa co powtórka u obrońcy
		b = _player.create_battle()
	else:
		b = _bot_battle(bot, army)
		b.set_plan(AttackPlan.from_dict(attack_plan.to_dict()))
		b.apply_research(Battle.Side.ATTACKER, research)  # A1 topory i A2 łuki atakującego (#12)
		b.set_general(Battle.Side.ATTACKER, generals.attack_general())  # generał ataku (#31)
		b.set_ruler_perk(Battle.Side.ATTACKER, grid.ruler_perk)  # Zdobywca (#32)
		_pve_begin(army)
	_attacking = true
	attack_panel.visible = false
	planner.show_plan = false
	planner.queue_redraw()
	hud.overlay = false
	battle_view = BattleView.new()
	battle_view.battle = b
	battle_view.states_changed.connect(_on_battle_states)
	add_child(battle_view)
	hud.battle = true
	hud.speed_label = speed_label(battle_view.speed)
	hud.message = "Atak: %d oddziały ruszają" % army.size() if army.size() > 1 else "Atak: oddział rusza"
	_save()


## Odpowiedź `launch_attack` (#28): pełna kopia zamku i obrony celu, potem bitwa z planu.
func _on_player_launched(launch: Dictionary, error: String) -> void:
	_launching = false
	if _player == null or not planner.visible:
		return
	if not error.is_empty():
		hud.message = AttackStart.error_message(error)
		return
	if not _player.apply_launch(launch):
		hud.message = "Zamek gracza jest nieczytelny. Wybierz inny cel"
		return
	# ten sam teren i te same kratki: cele i trasy planu zostają, bitwa rysuje prawdziwy zamek
	planner.bot = _player.target
	planner.intel = ScoutIntel.new()
	_on_attack_launched()


## Czemu atak na gracza nie może ruszyć, albo pusty tekst: armia musi być ta sama co w `start_attack`
## (serwer liczy ocalałych względem niej), a plan nie może trwać dłużej niż PlayerCastle.PLAN_LIMIT_S.
static func player_attack_problem(player: PlayerCastle, army: Array, now_s: int) -> String:
	if army != player.army:
		return "Armia się zmieniła: wybierz cel jeszcze raz"
	if not player.can_launch(now_s):
		return "Plan trwał za długo: wybierz cel jeszcze raz"
	return ""


## Doświadczenie generała ataku po bitwie `b` (#31): tylko gdy w niej był (ten z serwera przy graczu).
## Bot daje PD tylko do pierwszego awansu, PvP zawsze (`pvp`).
func _general_xp(b: Battle, pvp: bool) -> void:
	var g: Generals.General = b.generals.get(Battle.Side.ATTACKER, null)
	if g != null:
		generals.add_battle_xp(g.kind, b.winner == Battle.Winner.ATTACKER, pvp)


## Dopisek do komunikatu po bitwie: doświadczenie generała (#31).
static func xp_note(xp: int) -> String:
	return " · Generał +%d PD" % xp


## Koniec ataku: polegli znikają z armii, a pierwsze zdobycie zamku odblokowuje kolejny, mocniejszy
## (#26). Zamek wraca do pełnego stanu, więc można go atakować znowu.
## Wynik (#99): gwiazdki, procent zniszczeń i łup trafiają do okna wyniku. Łupu jest najwyżej tyle,
## ile uniosą ocaleli (capacity, #25). Do magazynu łup wchodzi tylko z serwera (#282): po przyjęciu wyniku
## czeka w zamku na serwerze i przychodzi w odpowiedzi na najbliższy zapis (`loot_applied`), więc wyprawa
## bez sieci nic nie daje.
func _finish_attack(b: Battle) -> void:
	if _player != null:
		_finish_player_attack(b)
		return
	var army := _battle_army  # skład z chwili startu bitwy, przed stratami
	var alive := b.survivors(Battle.Side.ATTACKER)
	var fallen := recruitment.apply_losses(_battle_ids, alive)
	var won := b.winner == Battle.Winner.ATTACKER
	var result := BattleResult.of(b)
	result.compute_loot(attack_target, BotRoster.is_beaten(attack_target, bots_beaten))
	result.limit_to_capacity(BattleResult.carry_capacity(army, alive))  # łup unoszą ocaleli (#25)
	# łup dolicza dopiero serwer (#282): okno pokazuje łup, który czeka na przyjęcie wyniku
	var online := not _pve.is_idle() and not _pve.failed()
	var got := PveReport.shown_loot(result.loot, online)
	_pve_send(_pve.finish(result, alive))  # ranking PvE (#242): punkty doda serwer
	_general_xp(b, false)
	var first := won and attack_target == bots_beaten and bots_beaten < BotRoster.COUNT
	var unlock := ""
	if first:
		unlock = "Wszystkie zamki zdobyte!" if bots_beaten + 1 >= BotRoster.COUNT \
				else BotPicker.unlock_text(bots_beaten + 1)
	elif _pve.failed():
		unlock = PveReport.FAILED_MESSAGE  # serwer odrzucił start wyprawy
	elif not online:
		unlock = PveReport.OFFLINE_MESSAGE
	if first:
		bots_beaten += 1
		if bots_beaten < BotRoster.COUNT:
			attack_target = bots_beaten  # następna Wyprawa od razu na nowy zamek
			for o in attack_plan.orders:
				AttackPlanner.clear(o)  # cel i trasa dotyczyły zdobytego zamku
	battle_view.queue_free()
	battle_view = null
	_on_battle_states({})  # po bitwie zamek znów jest cały
	hud.battle = false
	_attacking = false
	_close_attack()
	# wynik jest w oknie, więc pasek komunikatu go nie powtarza (review #194)
	hud.message = ""
	hud.overlay = true
	result_panel.show_result(result, got, fallen, unlock)
	_save()


## Koniec ataku na gracza (#240): straty jak zwykle, a łup trafia do magazynu dopiero z odpowiedzi
## `finish_attack` (serwer sprawdza limity). Do tego czasu okno wyniku czeka na serwer.
func _finish_player_attack(b: Battle) -> void:
	var alive := b.survivors(Battle.Side.ATTACKER)
	_finish_result = _player.result_of(b)
	_finish_body = _player.finish_request(b, _finish_result)
	_finish_fallen = recruitment.apply_losses(_battle_ids, alive)
	_finish_tries = 0
	_finish_resumed = false
	# wynik czeka w pliku, dopóki serwer nie odpowie: zamknięcie gry go nie gubi (#99)
	_pending.body = _finish_body
	_pending.fallen = _finish_fallen
	var err := _pending.write()
	if err != OK:
		push_warning("Nie udało się zapisać wyniku ataku: %s" % error_string(err))
	_general_xp(b, true)
	battle_view.queue_free()
	battle_view = null
	_on_battle_states({})
	hud.battle = false
	_attacking = false
	_close_attack()
	_player = null
	hud.overlay = true
	_save()
	_send_finish()


func _send_finish() -> void:
	_finish_tries += 1
	if net != null and net.finish_attack(_finish_body):
		hud.message = "Wysyłam wynik ataku..."
		return
	_on_player_attack_finished([] as Array[int], SupabaseClient.NETWORK_ERROR)


## Odpowiedź `finish_attack`: łup z serwera do magazynu i okno wyniku. Błąd sieci ponawia to samo
## żądanie (serwer zwraca zapisany wynik). Po RETRIES próbach bez sieci wynik zostaje w pliku
## i wraca na serwer później (#99, `_resume_finish`); odrzucony wynik jest bez łupu i znika.
func _on_player_attack_finished(loot: Array[int], error: String) -> void:
	if _pve_sending:
		_on_pve_finished(error)
		return
	if _finish_result == null:
		return
	if error == SupabaseClient.NETWORK_ERROR and _finish_tries < AttackFinish.RETRIES:
		hud.message = "Brak połączenia, ponawiam wynik..."
		get_tree().create_timer(AttackFinish.RETRY_S).timeout.connect(_send_finish)
		return
	var r := _finish_result
	var resumed := _finish_resumed
	_finish_result = null
	_finish_body = {}
	_finish_resumed = false
	# update_required (#336): wynik czeka w pliku jak przy braku sieci i wróci na serwer po aktualizacji
	if error == SupabaseClient.NETWORK_ERROR or error == ClientVersion.UPDATE_REQUIRED_ERROR:
		_resume_poll_s = Time.get_ticks_msec() / 1000.0 + RESUME_POLL_S
		if resumed:
			hud.message = ""  # zaległy wynik nadal czeka; okno pokazało się już po bitwie
			return
	else:
		_pending = PendingFinish.new()
		PendingFinish.clear()
	var got: Array[int] = []
	var note := "Wynik ataku dotarł na serwer" if resumed else ""
	if error.is_empty():
		r.loot = loot
		# łup jest już w zamku na serwerze (#274): telefon dolicza go z odpowiedzi na najbliższy zapis
		# (`loot_applied`), więc tu go nie dodaje; okno pokazuje łup przyjęty przez serwer
		got = loot.duplicate()
		generals.add_pvp_gold(loot[EconomyConfig.Res.GOLD])  # złoto z PvP na wyższe poziomy generałów (#31)
	else:
		r.loot.fill(0)
		got.resize(EconomyConfig.count())
		got.fill(0)
		note = AttackFinish.error_note(error)
	hud.message = ""
	hud.overlay = true
	result_panel.show_result(r, got, _finish_fallen, note)
	_save()
	if error.is_empty():
		net.flush()  # zapis od razu: odpowiedź serwera przynosi łup (#274)


# --- Ranking PvE (#242) -----------------------------------------------------------------------------

## Start bitwy z zamkiem-botem: gdy gra jest połączona, ten sam atak zaczyna się na serwerze
## (`start_attack` z `bot_idx`), żeby wynik mógł dać punkty PvE. Bez sieci bitwa idzie jak dotąd.
## Wynik ataku na gracza czekający na serwer albo poprzednia wyprawa w drodze mają pierwszeństwo.
func _pve_begin(army: Array) -> void:
	if not _pve.is_idle() or _pve_sending or _finish_result != null or not _pending.is_empty():
		return
	_pve.clear()  # nowa wyprawa: bez znacznika porażki poprzedniej
	if net == null or identity == null or not net.is_online():
		return
	net.flush()  # serwer sprawdza armię z kopii zamku (#23)
	if net.start_bot_attack(attack_target, army):
		_pve.begin(attack_target, army)


## Wysyła wynik wyprawy (pusta treść: nie ma czego wysyłać albo czekamy na start).
func _pve_send(body: Dictionary) -> void:
	if body.is_empty():
		return
	if net != null and net.finish_attack(body):
		_pve_sending = true
		return
	_on_pve_finished(SupabaseClient.NETWORK_ERROR)


## Odpowiedź `finish_attack` na wynik wyprawy: przyjęty łup czeka w zamku na serwerze (#282), więc zapis
## idzie od razu, a łup przychodzi w odpowiedzi na niego (`loot_applied`, _on_loot_applied). Błąd sieci
## ponawia tę samą treść, a odrzucony wynik pokazuje komunikat (bez łupu).
func _on_pve_finished(error: String) -> void:
	_pve_sending = false
	if _pve.on_finished(error):
		get_tree().create_timer(AttackFinish.RETRY_S).timeout.connect(
				func() -> void: _pve_send(_pve.retry_body()))
		return
	if _pve.failed():
		hud.message = PveReport.FAILED_MESSAGE
		return
	if error.is_empty() and net != null:
		_save()
		net.flush()


## Serwer scalił łup z zapasami (#274, #282): łup z własnego ataku (na gracza albo zamek-bota), nagroda
## za falę PvE (#288) albo strata po najeździe na zamek.
func _on_loot_applied(delta: Array[int]) -> void:
	_tick()
	var got := economy.apply_delta(delta)
	var text := loot_message(got)
	if _wave_reward_due and text.begins_with(LOOT_PREFIX):
		text = WAVE_REWARD_PREFIX + text.substr(LOOT_PREFIX.length())
	elif _shop_reward_due and text.begins_with(LOOT_PREFIX):
		text = SHOP_REWARD_PREFIX + text.substr(LOOT_PREFIX.length())
	_wave_reward_due = false
	_shop_reward_due = false
	if not text.is_empty():
		hud.message = text
	_save()


## Komunikat o łupie z serwera („Łup z ataku: +50 Dr +20 Ka”, „Straty z najazdu: -50 Dr”) albo pusty.
## Łup i strata scalone w jednym zapisie (gracz złupił i został złupiony przed synchronizacją) dają
## neutralne „Zmiana zapasów: +50 Dr -40 Ka” (review #278).
static func loot_message(got: Array[int]) -> String:
	var parts: Array[String] = []
	var lost := false
	var gained := false
	for res in got.size():
		if got[res] != 0:
			parts.append("%+d %s" % [got[res], EconomyConfig.SHORT_NAMES[res]])
			lost = lost or got[res] < 0
			gained = gained or got[res] > 0
	if parts.is_empty():
		return ""
	var prefix := "Zmiana zapasów: " if lost and gained else ("Straty z najazdu: " if lost else LOOT_PREFIX)
	return prefix + " ".join(parts)


# --- Fale PvE na serwerze (#288) ---------------------------------------------------------------------

## Start fali: gdy gra jest połączona, ta sama fala zaczyna się na serwerze (`pve_wave`), żeby wygrana
## mogła dać nagrodę. Bez sieci (albo gdy kanał ataków jest zajęty) fala idzie bez serwera i bez nagrody.
## Wynik poprzedniej fali w drodze albo czekający na ponowienie ma pierwszeństwo (review #290): wtedy nowa
## fala idzie bez serwera, a zgłoszenia poprzedniej nie kasujemy.
func _wave_begin(wave: int) -> void:
	if _wave_sending or not _wave.is_idle():
		return
	_wave.clear()
	if net == null or identity == null or not net.is_online():
		return
	if net.start_wave(wave):
		_wave.begin(wave)


## Odpowiedź na start fali; wynik, który już czekał, idzie od razu.
func _on_wave_started(start: Dictionary, error: String) -> void:
	_wave_send(_wave.on_started(start, error))
	if _wave.failed() and _battle_wave < 0:
		hud.message = WAVE_FAILED_MESSAGE  # fala już się skończyła z obiecaną nagrodą


## Wysyła wynik fali (pusta treść: nie ma czego wysyłać albo czekamy na start).
func _wave_send(body: Dictionary) -> void:
	if body.is_empty():
		return
	if net != null and net.finish_wave(body):
		_wave_sending = true
		return
	_on_wave_finished([] as Array[int], SupabaseClient.NETWORK_ERROR)


## Odpowiedź na wynik fali: przyjęta nagroda czeka w zamku na serwerze, więc zapis idzie od razu, a nagroda
## przychodzi w odpowiedzi na niego (`loot_applied`). Błąd sieci ponawia tę samą treść, a odrzucony wynik
## pokazuje komunikat (bez nagrody).
func _on_wave_finished(reward: Array[int], error: String) -> void:
	_wave_sending = false
	if _wave.on_finished(error):
		get_tree().create_timer(AttackFinish.RETRY_S).timeout.connect(
				func() -> void: _wave_send(_wave.retry_body()))
		return
	if _wave.failed():
		hud.message = WAVE_FAILED_MESSAGE
		return
	if error.is_empty() and net != null:
		_wave_reward_due = reward.any(func(v: int) -> bool: return v > 0)
		_save()
		net.flush()


## Serwer odrzucił stan zamku spoza limitów surowców (#274): zamek wraca z serwera.
func _on_castle_rejected() -> void:
	hud.message = "Serwer odrzucił stan zamku"


# --- Ustawienia obrony (#19) -------------------------------------------------------------------------

## Obrona: własny zamek w trybie edycji, z posterunkami załogi. Bez wojska tryb się nie otwiera.
func _on_defence_pressed() -> void:
	_tick()
	var army := recruitment.battle_squads()
	if army.is_empty():
		hud.message = _no_army_message()
		return
	if grid.keep_id() == 0:
		hud.message = KEEP_NO_ROOM
		return
	_selected_id = 0
	hud.hide_card()
	hud.set_building(false)
	_cursor = Rect2i()
	defense.prune(recruitment)
	defense_panel.generals = generals
	defense_panel.recruitment = recruitment
	defense_panel.open(defense, army, recruitment.battle_ids(), grid, grid.age())
	hud.overlay = true
	camera.look_at_world(Vector2(DefensePlan.keep_center(grid) * TerrainMap.CELL))
	hud.message = DefensePanel.HINT
	queue_redraw()


func _on_defence_changed(message: String) -> void:
	hud.message = message
	queue_redraw()
	_save()


## Historia (#29, #328) z ustawień obrony: lista ostatnich obron z serwera. Bez sieci lista pokazuje błąd.
func _on_replays_pressed() -> void:
	_history_from_notice = false
	_open_history()


## Historia z okienka o nowych atakach: bez ustawień obrony (gracz nie musi mieć armii).
func _on_notice_history() -> void:
	_history_from_notice = true
	_open_history()


func _open_history() -> void:
	defense_panel.visible = false
	_selected_id = 0
	hud.hide_card()
	_save()
	replay_panel.open()
	hud.overlay = true
	hud.message = "Wybierz obronę do obejrzenia"
	if net == null or not net.is_online():
		replay_panel.show_reports([] as Array[DefenseLog.Report], false)
		return
	if not _defense_history.is_empty():
		replay_panel.show_reports(_defense_history, true)
		_mark_defenses_seen()
	# trwające żądanie (np. ze startu gry) też odpowie w _on_defense_reports
	if not net.load_defense_reports() and not net.is_reports_pending():
		replay_panel.show_reports(_defense_history, not _defense_history.is_empty())


## Historia z serwera: przy otwartej liście ją odświeża i oznacza jako obejrzaną, a w innym razie
## sprawdza nowe ataki od ostatniego obejrzenia (kropka nad Obroną i okienko, raz na nową obronę).
func _on_defense_reports(reports: Array[DefenseLog.Report], ok: bool) -> void:
	if not ok:
		if replay_panel.visible and _defense_history.is_empty():
			replay_panel.show_reports(reports, false)
		return
	_defense_history = reports
	if replay_panel.visible:
		replay_panel.show_reports(reports, true)
		_mark_defenses_seen()
		return
	var fresh := DefenseLog.new_since(reports, PlayerProfile.read_seen_defense(PlayerProfile.PATH))
	hud.defence_alert = not fresh.is_empty()
	var newest := DefenseLog.newest_s(fresh)
	if newest > _noticed_s and _can_show_notice():
		_noticed_s = newest
		defense_notice.open(DefenseNotice.text(fresh))
		hud.overlay = true
	hud.queue_redraw()


## Okienko nie przykrywa bitwy, onboardingu ani innego otwartego ekranu; wtedy zostaje sama kropka.
func _can_show_notice() -> bool:
	return not hud.overlay and not hud.battle and battle_view == null \
			and (onboarding == null or not onboarding.visible)


## Gracz zobaczył historię: znacznik w profilu przesuwa się na najnowszą obronę, kropka gaśnie.
func _mark_defenses_seen() -> void:
	var newest := DefenseLog.newest_s(_defense_history)
	if newest > PlayerProfile.read_seen_defense(PlayerProfile.PATH):
		var err := PlayerProfile.write_seen_defense(PlayerProfile.PATH, newest)
		if err != OK:
			push_warning("Nie udało się zapisać obejrzanych obron: %s" % error_string(err))
	_noticed_s = maxi(_noticed_s, newest)
	hud.defence_alert = false
	hud.queue_redraw()


## Wróć z historii: do ustawień obrony, a gdy otworzyło ją okienko, z powrotem do zamku.
func _on_replays_closed() -> void:
	_replay_loading = false
	_on_overlay_closed()
	if not _history_from_notice:
		_on_defence_pressed()
	_history_from_notice = false


func _on_replay_requested(attack_id: String) -> void:
	if _replay_loading or battle_view != null:
		return
	if net == null or not net.load_replay(attack_id):
		hud.message = "Poczekaj chwilę na serwer"
		return
	_replay_loading = true
	hud.message = "Wczytuję powtórkę..."


## Dane powtórki z serwera: bitwa liczy się od nowa na kopii zamku z chwili ataku, na mapie celu
## (jak przy Wyprawie), bez sterowania; gracz zmienia tylko tempo (x1, x2, x4).
func _on_replay_loaded(data: Dictionary, error: String) -> void:
	if not _replay_loading:
		return
	_replay_loading = false
	if not replay_panel.visible or battle_view != null:
		return
	if not error.is_empty():
		hud.message = AttackReplay.error_message(error)
		return
	var r := BattleReplay.from_response(data)
	if r == null:
		hud.message = "Powtórka jest nieczytelna"
		return
	_replay = r
	_replaying = true
	replay_panel.visible = false
	planner.open(r.target(), AttackPlan.new(), r.castle.army, grid.age(), ScoutIntel.new())
	planner.show_plan = false
	camera.look_at_world(Vector2(r.target().grid.buildings[r.target().objective].get_center() * TerrainMap.CELL))
	battle_view = BattleView.new()
	battle_view.battle = r.create_battle()
	battle_view.states_changed.connect(_on_battle_states)
	add_child(battle_view)
	hud.overlay = false
	hud.battle = true
	hud.speed_label = speed_label(battle_view.speed)
	hud.message = "Powtórka: atak na twój zamek"
	queue_redraw()


## Koniec powtórki: raport obrony z wynikiem i łupem z serwera, a z niego od razu ustawienia obrony.
## Gdy powtórka dała inny wynik niż serwer (np. inna wersja gry u atakującego), raport to mówi.
func _finish_replay(b: Battle) -> void:
	var r := _replay
	_replay = null
	_replaying = false
	battle_view.queue_free()
	battle_view = null
	_on_battle_states({})
	planner.visible = false
	hud.battle = false
	camera.look_at_world(Vector2(DefensePlan.keep_center(grid) * TerrainMap.CELL))
	var note := "" if replay_matches(BattleResult.of(b), r.result) else REPLAY_MISMATCH
	hud.message = ""
	hud.overlay = true
	result_panel.show_defense(r.result, r.loot, note)
	queue_redraw()


## Dopisek w raporcie, gdy powtórka skończyła się inaczej, niż zapisał serwer.
const REPLAY_MISMATCH := "Powtórka różni się od wyniku"


## Czy wynik powtórki zgadza się z wynikiem zapisanym na serwerze (wygrana, procent i gwiazdki).
static func replay_matches(local: BattleResult, server: BattleResult) -> bool:
	return local.won == server.won and local.percent == server.percent and local.stars == server.stars


## Okno wyniku zamknięte: po raporcie obrony (#29) od razu ustawienia obrony, inaczej widok zamku.
func _on_result_closed() -> void:
	_on_overlay_closed()
	if result_panel.defender:
		_on_defence_pressed()


## Gotowe: koniec edycji obrony, układ zostaje zapisany.
func _close_defence() -> void:
	defense_panel.visible = false
	hud.overlay = false
	hud.message = DEFAULT_MESSAGE
	_save()
	queue_redraw()


# --- Kolejka (#163) --------------------------------------------------------------------------------

## Kolejka: co się buduje i szkoli. Karta budynku się zamyka, a HUD chowa swoje przyciski.
func _on_queue_opened() -> void:
	_tick()
	_selected_id = 0
	hud.hide_card()
	hud.set_building(false)
	_cursor = Rect2i()
	hud.overlay = true
	queue_panel.now_ms = _now_ms()
	queue_panel.open()
	hud.message = "Budowa i szkolenie"
	queue_redraw()


## Anulowanie z listy (po potwierdzeniu): jak Anuluj na karcie budynku.
func _on_queue_cancel(id: int) -> void:
	_tick()
	var o := queue.order_for(id)
	if o == null:
		return
	var title := BuildingTypes.NAMES[o.kind]
	queue.cancel(grid, economy, id, _now_ms())
	hud.message = "Anulowano: %s, surowce wróciły" % title
	if grid.market_id() == 0:
		_ensure_market()
	_save()
	queue_redraw()


## Dotknięcie wiersza budowy: kamera na budynek (ekran już się zamyka).
func _on_queue_focus(id: int) -> void:
	if grid.buildings.has(id):
		camera.look_at_world(Vector2(grid.buildings[id].get_center() * TerrainMap.CELL))
		_select(id)


## Drzewko badań przykrywa mapę: karta budynku się zamyka, a HUD chowa swoje przyciski.
func _on_research_opened() -> void:
	_tick()
	_selected_id = 0
	hud.hide_card()
	_cursor = Rect2i()
	hud.overlay = true
	research_panel.open()
	hud.message = "Wybierz technologię"
	queue_redraw()


## Ekran Wojsko: `id` = 0 to widok globalny, inaczej budynek rekrutacji z karty.
func _on_army_opened(id: int) -> void:
	_tick()
	_selected_id = 0
	hud.hide_card()
	_cursor = Rect2i()
	hud.overlay = true
	recruit_panel.open(id)
	hud.message = "Wybierz jednostkę"
	queue_redraw()


func _on_recruit_pressed() -> void:
	if grid.buildings.has(_selected_id) and grid.kinds[_selected_id] == BuildingTypes.Kind.MANOR:
		_on_generals_opened()
		return
	_on_army_opened(_selected_id)


# --- Generałowie (#31) -------------------------------------------------------------------------------

## Generałowie z karty Dworu: rekrutacja, awans i perk.
func _on_generals_opened() -> void:
	_tick()
	_selected_id = 0
	hud.hide_card()
	_cursor = Rect2i()
	hud.overlay = true
	generals_panel.open(generals, grid.age())
	hud.message = "Złoto: %d" % economy.amounts[EconomyConfig.Res.GOLD]
	queue_redraw()


func _on_general_recruit(kind: int) -> void:
	_tick()
	var r := generals.recruit(kind, grid.age(), economy, grid.manor_level() >= 1)
	_general_done(r, "Do służby: %s" % Generals.NAMES[kind])


func _on_general_promote(kind: int) -> void:
	_tick()
	var r := generals.promote(kind, economy)
	var g := generals.get_general(kind)
	_general_done(r, "%s wyszkolony: poziom %d" % [Generals.NAMES[kind], g.level if g != null else 1])


func _on_general_perk(kind: int, perk: int) -> void:
	var r := generals.choose_perk(kind, perk, grid.age())
	_general_done(r, "%s: %s" % [Generals.NAMES[kind] if kind >= 0 else "", Generals.PERK_NAMES[perk]])


func _general_done(result: int, ok_message: String) -> void:
	hud.message = ok_message if result == Generals.Result.OK else Generals.MESSAGES[result]
	if result == Generals.Result.OK:
		_save()
	generals_panel.queue_redraw()


func _on_train_requested(unit: int, squad_id: int) -> void:
	_tick()
	var now := _now_ms()
	var result: Recruitment.Result
	if recruit_panel.building_id == 0:
		result = recruitment.start_any(unit, squad_id, grid, economy, goods, research, grid.age(), now)
	else:
		result = recruitment.start(unit, recruit_panel.building_id, squad_id, grid, economy, goods, research,
				grid.age(), now)
	if result == Recruitment.Result.OK:
		hud.message = "Szkolenie: %s, oddział %s (%s)" % [UnitTypes.SHORT_NAMES[unit],
				RecruitPanel.squad_label(recruitment, unit, recruitment.last_squad),
				BuildingTypes.NAMES[grid.kinds[recruitment.last_building]]]
		# kolejne jednostki domyślnie do tego samego oddziału, póki ma miejsce
		var keep := recruitment.free_in_squad(recruitment.last_squad) > 0
		recruit_panel.target_squad = recruitment.last_squad if keep else recruitment.default_squad(unit)
		_save()
	elif result == Recruitment.Result.NO_GOODS:
		hud.message = RecruitPanel.missing_text(unit, goods)
	else:
		hud.message = Recruitment.MESSAGES[result]


## Okienko surowca z górnego paska: zapas, produkcja z rozbiciem i jak zdobyć więcej.
func _on_resource_info(res: int) -> void:
	_tick()
	info_popup.open(EconomyConfig.NAMES[res], InfoText.resource(res, grid, research, economy.amounts,
			recruitment.army_upkeep()))


## Okienko limitu armii z ekranu Wojsko: skąd bierze się limit i jak go podnieść.
func _on_army_limit_info() -> void:
	info_popup.open("Limit armii", InfoText.army(grid, recruitment, research))


## Ustawienia (#177): zapis, karta i kursor się zamykają, a panel przykrywa mapę.
func _on_settings_opened() -> void:
	_tick()
	_save()
	_deselect()
	_cursor = Rect2i()
	hud.overlay = true
	settings_panel.open()
	hud.message = "Ustawienia"
	queue_redraw()


## Zacznij od nowa (potwierdzone w ustawieniach): usuwa zapis i przeładowuje scenę. Mapa zostaje
## ta sama, bo seed należy do gracza (PlayerProfile).
func _on_new_game() -> void:
	# nowa gra nadpisuje zamek na serwerze, a nie przywraca starego (#23)
	if net != null:
		net.mark_new_game()
	SaveGame.delete(SaveGame.PATH)
	PendingFinish.clear()  # wynik ataku starego zamku nie idzie już na serwer (#99)
	get_tree().reload_current_scene()


## Onboarding (#228) skończony: tożsamość trafia do profilu, a zamek może iść na serwer. Gdy zapis
## profilu się nie uda, gracz zostaje na panelu z komunikatem, a tożsamość nie istnieje w pamięci,
## więc zamek nie idzie na serwer bez trwałego profilu.
func _on_onboarding_finished(id: PlayerProfile.Identity) -> void:
	var err := PlayerProfile.write_identity(PlayerProfile.PATH, id)
	if err != OK:
		push_warning("Nie udało się zapisać profilu gracza: %s" % error_string(err))
		onboarding.show_error(OnboardingPanel.SAVE_ERROR)
		return
	identity = id
	hud.ruler_id = id.ruler
	onboarding.queue_free()
	onboarding = null
	hud.overlay = false
	hud.message = "Witaj, %s!" % id.player_name
	_save()
	_ask_tutorial()


# --- Mini-samouczek UI (#251) ------------------------------------------------------------------------

## Okno z pytaniem o samouczek, gdy gracz jeszcze nie odpowiedział i nie przeszedł 5 fal.
func _ask_tutorial() -> void:
	if not TutorialHints.should_ask(tutorial_state, pve_cleared) or tutorial_prompt != null:
		return
	tutorial_prompt = TutorialPrompt.new()
	# ostatnie dziecko warstwy UI: Godot wywołuje _input od ostatniego węzła w drzewie, więc dotyk trafia
	# najpierw tutaj (jak onboarding i info_popup)
	hud.get_parent().add_child(tutorial_prompt)
	tutorial_prompt.answered.connect(_on_tutorial_answered)
	tutorial_prompt.open()
	hud.overlay = true


func _on_tutorial_answered(keep: bool) -> void:
	tutorial_prompt.queue_free()
	tutorial_prompt = null
	hud.overlay = false
	_on_tutorial_changed(keep)


## Włączenie albo wyłączenie samouczka (okno z pytaniem albo Ustawienia).
func _on_tutorial_changed(on: bool) -> void:
	_set_tutorial(TutorialHints.State.ON if on else TutorialHints.State.OFF)
	settings_panel.tutorial_on = on
	hud.message = "Samouczek włączony" if on else "Samouczek wyłączony"
	_refresh_tutorial()


func _set_tutorial(state: int) -> void:
	tutorial_state = state
	var err := PlayerProfile.write_tutorial(PlayerProfile.PATH, state)
	if err != OK:
		push_warning("Nie udało się zapisać stanu samouczka: %s" % error_string(err))


## Tekst celu (#185) i podświetlenie kolejnego dotknięcia (#251) według bieżącego celu i stanu interfejsu.
func _refresh_tutorial() -> void:
	hud.hint_target = Hud.Target.NONE
	if build_panel != null:
		build_panel.hint_target = BuildPanel.Target.NONE
	if recruit_panel != null:
		recruit_panel.hint_target = RecruitPanel.Target.NONE
	if not TutorialHints.active(tutorial_state, pve_cleared):
		hud.goal_text = ""
		return
	hud.goal_text = TutorialGoals.text(pve_cleared, grid, research, recruitment)
	if build_panel == null or recruit_panel == null:
		return
	var ui := _tutorial_ui()
	var s := TutorialHints.step(TutorialGoals.current(pve_cleared, grid, research, recruitment), ui)
	var tip := TutorialHints.tip(s)
	if not tip.is_empty():
		hud.goal_text = tip
	hud.hint_target = TutorialHints.hud_target(s)
	build_panel.hint_target = TutorialHints.build_target(s)
	recruit_panel.hint_target = TutorialHints.recruit_target(s, ui)


func _tutorial_ui() -> TutorialHints.Ui:
	var ui := TutorialHints.Ui.new()
	ui.build_open = build_panel.visible
	ui.recruit_open = recruit_panel.visible
	ui.other_open = (hud.overlay or battle_view != null or defense_panel.visible or planner.visible
			or tutorial_prompt != null) and not ui.build_open and not ui.recruit_open
	ui.build_category = build_panel.category
	ui.build_selected = build_panel.selected
	ui.building = hud.building
	ui.selected_kind = hud.selected_kind
	ui.card_open = hud.is_card_open()
	ui.card_recruit = hud.card_recruit and not hud.card_generals
	ui.recruit_units = recruit_panel.units()
	ui.recruit_selected = recruit_panel.selected
	ui.barracks_placed = grid.kinds.values().has(BuildingTypes.Kind.BARRACKS)
	ui.army = recruitment.army_size()
	ui.training = recruitment.orders.size()
	return ui


## Portret władcy w HUD-zie (#228): panel z władcą, graczem, zamkiem i perkami władcy (#32, #308).
func _on_portrait_pressed() -> void:
	if identity == null:
		return
	_tick()
	_selected_id = 0
	hud.hide_card()
	_cursor = Rect2i()
	hud.overlay = true
	ruler_panel.open(Rulers.ruler_name(identity.ruler), "Gracz: %s · Zamek: %s" % [identity.player_name,
			identity.castle_name], Rulers.perk_text(identity.ruler), research, grid.age())
	hud.message = "Złoto: %d" % economy.amounts[EconomyConfig.Res.GOLD]


## Sklep z karty Targu (#408): tylko online, katalog z serwera.
func _on_shop_pressed() -> void:
	_tick()
	_selected_id = 0
	hud.hide_card()
	_cursor = Rect2i()
	hud.overlay = true
	shop_panel.open(economy)
	if net == null or not net.load_shop():
		shop_panel.show_offline()
	hud.message = "Targ: darmowe oferty"


## Odbierz w sklepie: nagrodę daje dopiero serwer (`shop_claim`).
func _on_shop_claim(offer_id: int) -> void:
	if net == null or not net.claim_offer(offer_id):
		shop_panel.claim_failed(SupabaseClient.NETWORK_ERROR)


## Odpowiedź `shop_claim`: odliczanie na karcie, a nagroda przychodzi z najbliższym zapisem zamku (loot_applied),
## więc zapis idzie od razu.
func _on_shop_claimed(claim: Dictionary, error: String) -> void:
	if not error.is_empty():
		shop_panel.claim_failed(error)
		if error == "cooldown" and net != null:
			net.load_shop()  # odliczanie z serwera
		return
	_tick()
	shop_panel.claim_done(claim, _now_ms())
	_shop_reward_due = true
	_save()
	if net != null:
		net.flush()


## Linie okienka władcy: kto rządzi którym zamkiem i jakie ma premie postaci (domyślny żadnych).
static func ruler_info(id: PlayerProfile.Identity) -> PackedStringArray:
	var innate := Rulers.innate_perk(id.ruler)
	return PackedStringArray([
		"Gracz: %s" % id.player_name,
		"Zamek: %s" % id.castle_name,
		"Premie: brak" if innate.is_empty() else "Premie: %s" % innate,
	])


func _on_overlay_closed() -> void:
	hud.overlay = false
	hud.message = DEFAULT_MESSAGE


func _on_research_requested(code: String) -> void:
	_tick()
	var result := research.start(code, grid.age(), economy, _now_ms(), grid)
	if result == Research.Result.NO_BUILDING:
		hud.message = Research.building_hint(code)
	elif result == Research.Result.OK:
		hud.message = "Badanie: %s, %s" % [ResearchPanel.title_of(research, code, true), Hud.format_time(research.duration_ms)]
		_save()
	else:
		hud.message = Research.MESSAGES[result]


func _refresh_card() -> void:
	if not grid.buildings.has(_selected_id):
		_deselect()
		return
	var kind := grid.kinds[_selected_id]
	var level := grid.levels[_selected_id]
	var pending := queue.has_order(_selected_id)
	var status := Ages.level_status(level) if BuildingTypes.has_levels(kind) else ""
	if pending:
		status = "budowa %s" % Hud.format_time(queue.remaining_ms(_selected_id, _now_ms()))
	elif ruins.is_ruined(_selected_id, _now_ms()):
		status = "odbudowa %s" % Hud.format_time(ruins.remaining_ms(_selected_id, _now_ms()))
	var can_upgrade := not pending and level < BuildConfig.max_level(kind, grid.manor_level()) \
			and BuildQueue.missing_techs(kind, level + 1, research).is_empty()
	var middle_enabled := pending or not BuildingTypes.is_unique(kind)
	hud.card_generals = level >= 1 and kind == BuildingTypes.Kind.MANOR
	hud.card_recruit = (level >= 1 and RecruitPanel.recruits_now(kind, recruitment, grid, research, grid.age())) \
			or hud.card_generals
	hud.card_pve = level >= 1 and kind == BuildingTypes.Kind.WATCHTOWER
	hud.card_seal = level >= 1 and kind == BuildingTypes.Kind.SEAL_HOUSE
	hud.card_plain = plain_card(kind, pending)
	hud.card_market = kind == BuildingTypes.Kind.MARKET and not pending
	hud.card_check_disabled = seal_check.is_busy()
	hud.card_seal_disabled = not seal_check.has_selection()
	# odcinek wału albo palisady (#371): karta całego odcinka, koszt ulepszenia to suma kratek
	var length := grid.segment_ids(_selected_id).size()
	hud.card_info = upgrade_info(kind, level, grid.manor_level(), pending, grid.ruler_perk, length)
	if hud.card_seal and not pending:
		hud.card_info = seal_card_info(seal_check, _now_ms())
		hud.card_info_missing = PackedStringArray()
	elif kind == BuildingTypes.Kind.SCOUT_HOUSE and level >= 1 and not pending:
		# raport zwiadu jest w budynku (#28): misja w drodze albo ostatni raport
		hud.card_info = scout_card_info(scouting, _now_ms())
		hud.card_info_missing = PackedStringArray()
	else:
		hud.card_info_missing = PackedStringArray() if pending or level >= BuildConfig.max_level(kind, Ages.MAX_TOTAL_LEVEL) \
				else Hud.missing_tokens(BuildConfig.segment_cost(kind, level + 1, length), economy.amounts)
	hud.card_needs = upgrade_needs(kind, level, grid.manor_level(), pending, research)
	hud.card_needs_ok = upgrade_needs_ok(kind, level, grid.manor_level(), pending, research)
	hud.show_card(segment_title(BuildingTypes.name_of(kind, research), length), status, can_upgrade, pending,
			middle_enabled)
	queue_redraw()


## Tytuł karty odcinka wału albo palisady (#371), np. „Palisada (3 kratki)”; pojedyncza kratka bez dopisku.
static func segment_title(name: String, length: int) -> String:
	return name if length < 2 else "%s (%s)" % [name, Hud.segment_label(Hud.Target.LENGTH, length, false)]


## Karta z samym Zamknij (#232): donżon, chyba że ma zlecenie ulepszenia ze starego zapisu, wtedy
## zwykła karta z Anuluj (review #244).
static func plain_card(kind: int, pending: bool) -> bool:
	return kind == BuildingTypes.Kind.KEEP and not pending


## Linia karty Komendy umocnień (#199): odliczanie Sprawdź, wynik albo zachęta do sprawdzenia.
static func seal_card_info(check: SealCheck, now_ms: int) -> String:
	if check.is_busy():
		return "Sprawdzanie: %s" % Hud.format_time(check.remaining_ms(now_ms))
	if check.revealed:
		if check.gaps.is_empty():
			return "Obrona szczelna"
		if check.has_selection():
			return SEAL_SELECTED_INFO
		return "Luki: %d, dotknij luki na mapie" % check.gaps.size()
	return SEAL_HOUSE_INFO


## Linia karty Chaty tropicieli (#28): zwiad w drodze, ostatni raport albo podpowiedź.
static func scout_card_info(s: Scouting, now_ms: int) -> String:
	if s.is_busy():
		return "Zwiad: %s, %s" % [s.mission.target_name, Hud.format_time(s.remaining_ms(now_ms))]
	if not s.reports.is_empty():
		return Scouting.report_text(s.reports[-1])
	return SCOUT_HOUSE_INFO


## Opis karty z kosztem ulepszenia, np. „Ulepsz: 180 Dr 60 Ka 60 Ży, 3:00”. Wymagania są osobno
## (upgrade_needs).
## `length`: liczba kratek odcinka wału albo palisady (#371); koszt i czas to suma kratek.
static func upgrade_info(kind: int, level: int, _manor_level: int, pending: bool,
		perk: int = RulerPerks.Perk.NONE, length: int = 1) -> String:
	if pending:
		return "Trwa budowa"
	if kind == BuildingTypes.Kind.KEEP:
		return KEEP_INFO
	if kind == BuildingTypes.Kind.MARKET:
		return MARKET_INFO
	if not BuildingTypes.has_levels(kind):
		return WATCHTOWER_INFO
	if level >= BuildConfig.max_level(kind, Ages.MAX_TOTAL_LEVEL):
		return "Najwyższy poziom"
	# poziom 5 → 1 następnej epoki (#34): Dwór się przebudowuje, inne budynki wchodzą w epokę
	var verb := "Ulepsz"
	if Ages.is_age_step(level + 1):
		verb = "Przebuduj" if kind == BuildingTypes.Kind.MANOR else Ages.age_name(Ages.of_level(level + 1))
	return "%s: %s, %s%s" % [verb, Hud.cost_text(BuildConfig.segment_cost(kind, level + 1, length)),
			Hud.format_time(_build_time(kind, level + 1, perk) * length), BuildQueue.capacity_gain_text(kind, level + 1)]


## Linia karty z wymaganiami następnego poziomu (po teście na telefonie), np. „Wymaga: Dwór poz. 3
## (masz 2)”; pusta, gdy budynek nie ma następnego poziomu albo jest w budowie. Dwór wymaga tylko
## surowców, a przebudowa Dworu na nową epokę (#34) technologii kluczowych. Inne budynki wymagają
## Dworu co najmniej na poziomie, do którego rosną (poziomy epoki II: „II.1”).
static func upgrade_needs(kind: int, level: int, manor_level: int, pending: bool,
		research: Research = null) -> String:
	if pending or not BuildingTypes.has_levels(kind) or level >= BuildConfig.max_level(kind, Ages.MAX_TOTAL_LEVEL):
		return ""
	if kind == BuildingTypes.Kind.MANOR:
		var techs := BuildConfig.level_techs(kind, level + 1)
		if techs.is_empty():
			return "Wymaga: tylko surowców"
		# przebudowa na nową epokę: brakujące technologie z nazwą, a gdy wszystkie są, same kody
		var missing := BuildQueue.missing_techs(kind, level + 1, research)
		if missing.is_empty():
			return "Wymaga: %s (zbadane)" % ", ".join(techs)
		var names: PackedStringArray = []
		for code in missing:
			names.append("%s %s" % [code, TechTree.tech_name(code)])
		return "Wymaga: %s" % ", ".join(names)
	return "Wymaga: Dwór poz. %s (masz %s)" % [Ages.short_level(level + 1), Ages.short_level(manor_level)]


## Czy wymagania następnego poziomu są spełnione (kolor linii „Wymaga:”: zielony albo czerwony).
static func upgrade_needs_ok(kind: int, level: int, manor_level: int, pending: bool,
		research: Research = null) -> bool:
	return pending or (level < BuildConfig.max_level(kind, manor_level)
			and BuildQueue.missing_techs(kind, level + 1, research).is_empty())


func _on_upgrade() -> void:
	_tick()
	var result := queue.order_upgrade(grid, economy, _selected_id, _now_ms(), research)
	if result == BuildQueue.Result.OK:
		var o := queue.order_for(_selected_id)
		hud.message = "Ulepszanie do poziomu %s, %s" % [Ages.short_level(o.level), Hud.format_time(o.duration_ms)]
		_save()
	elif result == BuildQueue.Result.NEEDS_MANOR or result == BuildQueue.Result.NEEDS_TECH:
		hud.message = queue.upgrade_hint(grid, _selected_id, research)
	else:
		hud.message = BuildQueue.MESSAGES[result]
	_refresh_card()


## Sprawdź szczelność z Komendy umocnień (#199): ~1 min odliczania, potem czerwone luki.
func _on_check_pressed() -> void:
	_tick()
	if not grid.buildings.has(_selected_id) or grid.kinds[_selected_id] != BuildingTypes.Kind.SEAL_HOUSE \
			or grid.levels[_selected_id] < 1:
		hud.message = "Najpierw zbuduj Komendę umocnień"
		return
	if not seal_check.start(_now_ms()):
		hud.message = "Trwa sprawdzanie szczelności"
		_refresh_card()
		return
	hud.message = "Sprawdzanie szczelności, %s" % Hud.format_time(SealCheck.DURATION_MS)
	_save()
	_refresh_card()
	queue_redraw()


## Domknij lukę wskazaną przez gracza: zleca odcinek wału/palisady jak zwykła budowa (#199).
func _on_seal_pressed() -> void:
	_tick()
	if not grid.buildings.has(_selected_id) or grid.kinds[_selected_id] != BuildingTypes.Kind.SEAL_HOUSE \
			or grid.levels[_selected_id] < 1:
		hud.message = "Najpierw zbuduj Komendę umocnień"
		return
	seal_check.prune(grid)
	if not seal_check.revealed:
		hud.message = "Najpierw Sprawdź szczelność"
		_refresh_card()
		return
	if seal_check.gaps.is_empty():
		hud.message = "Obrona szczelna"
		_refresh_card()
		return
	if not seal_check.has_selection():
		hud.message = "Dotknij czerwonej luki na mapie"
		_refresh_card()
		return
	var cell := seal_check.selected
	var kind := grid.wall_kind_for_gap(cell)
	var result := queue.order_build(grid, economy, cell, kind, _now_ms(), research)
	if result == BuildQueue.Result.OK:
		seal_check.prune(grid)
		hud.message = "Uszczelnianie: %s, %s" % [BuildingTypes.NAMES[kind],
				Hud.format_time(_build_time(kind, BuildConfig.start_level(kind), grid.ruler_perk))]
		_save()
	elif result == BuildQueue.Result.NEEDS_TECH:
		hud.message = _tech_hint(kind)
	else:
		hud.message = queue.message(result)
	_refresh_card()
	queue_redraw()


## Środkowy przycisk karty: Anuluj dla budynku w kolejce, inaczej Rozbierz (Dworu i donżonu nie można).
func _on_middle_button() -> void:
	_tick()
	var title := BuildingTypes.NAMES[grid.kinds[_selected_id]]
	if queue.has_order(_selected_id):
		queue.cancel(grid, economy, _selected_id, _now_ms())
		_refresh_card()
		hud.message = "Anulowano: %s, surowce wróciły" % title
		if grid.market_id() == 0:
			_ensure_market()
		_save()
		return
	if BuildingTypes.is_unique(grid.kinds[_selected_id]):
		hud.message = "Tego budynku nie można rozebrać"
		return
	_cursor = grid.segment_rect(_selected_id)
	_cursor_ok = true
	# odcinek wału albo palisady (#371) rozbiera się w całości
	for id in grid.segment_ids(_selected_id):
		recruitment.drop_building(id)
		grid.remove(id)
	# rozebrany Magazyn od razu zmniejsza pojemność (nadmiar przepada)
	economy.refresh_capacity(grid)
	_deselect()
	hud.message = "Rozebrano: %s" % title
	if grid.market_id() == 0:
		_ensure_market()
	_save()


## Odbudowa ruin (#99): usuwa odbudowane, a mapę i kartę odświeża tylko przy zmianie wyglądu.
func _refresh_ruins(now: int) -> void:
	if ruins.is_empty() and _ruin_states.is_empty():
		return
	ruins.prune(now, grid)
	var st := ruins.states(now)
	if st == _ruin_states:
		return
	_ruin_states = st
	queue_redraw()
	if _selected_id != 0:
		_refresh_card()


func _draw() -> void:
	draw_texture(_terrain_tex, Vector2.ZERO)
	# w bitwie stany z bitwy; poza nią ruiny po ataku PvP (#99)
	CastleView.draw_buildings(self, grid, textures, battle_states if battle_view != null and not _on_target_map() else _ruin_states)
	if not queue.orders.is_empty():
		_draw_progress(queue.orders[0].building_id)
		for extra in queue.orders[0].extra_ids:
			_draw_progress(extra)
	_draw_seal_gaps()
	_draw_age_rebuild()
	var frame := grid.segment_rect(_selected_id) if _selected_id != 0 else _cursor
	if frame.has_area():
		var ok := _selected_id != 0 or _cursor_ok
		CastleView.draw_frame(self, Rect2i(frame.position * TerrainMap.CELL, frame.size * TerrainMap.CELL),
				Palette.VALID if ok else Palette.ACCENT)
	if defense_panel != null and defense_panel.visible:
		_draw_defence()


## Czerwone podświetlenie luk po Sprawdź z Komendy umocnień (#199); wybrana luka w ramce tuszu.
func _draw_seal_gaps() -> void:
	if not seal_check.revealed or not _has_ready_seal_house():
		return
	for c in seal_check.gaps:
		var at := c * TerrainMap.CELL
		draw_rect(Rect2(at.x, at.y, TerrainMap.CELL, TerrainMap.CELL), Color(Palette.ACCENT, 0.45))
		var frame := Palette.INK if c == seal_check.selected else Palette.ACCENT
		CastleView.draw_frame(self, Rect2i(at, Vector2i.ONE * TerrainMap.CELL), frame)


## Przy otwartej karcie Komendy umocnień dotknięcie czerwonej luki ją wskazuje (#199): Domknij
## uszczelni właśnie tę lukę. `true`, gdy dotknięcie trafiło w lukę.
func _try_select_gap(world_pos: Vector2) -> bool:
	if _selected_id == 0 or int(grid.kinds.get(_selected_id, -1)) != BuildingTypes.Kind.SEAL_HOUSE:
		return false
	var gap := seal_check.gap_near(world_pos, SEAL_TAP_TOLERANCE)
	if gap == SealCheck.NO_GAP or not seal_check.select(gap):
		return false
	hud.message = "Wybrano lukę: Domknij"
	_save()
	_refresh_card()
	queue_redraw()
	return true


## Czy stoi gotowa Komenda umocnień (poziom ≥ 1) — bez niej nie ma flow Sprawdź / luk (#199).
func _has_ready_seal_house() -> bool:
	for id: int in grid.kinds:
		if grid.kinds[id] == BuildingTypes.Kind.SEAL_HOUSE and grid.levels[id] >= 1:
			return true
	return false


## Tryb edycji obrony: strefa wokół donżonu, trasy patroli (zamknięta pętla z punktami) i znaczniki
## miejsc oddziałów (ikona klasy w ramce; wybrany oddział w ramce koloru tuszu, miejsce zastawione
## budynkiem na czerwono).
func _draw_defence() -> void:
	var zone := DefensePlan.zone(grid)
	var px := Rect2i(zone.position * TerrainMap.CELL, zone.size * TerrainMap.CELL)
	draw_rect(Rect2(px), Color(Palette.VALID, 0.12))
	CastleView.draw_frame(self, px, Palette.VALID)
	for i in defense_panel.ids.size():
		var o := defense.order_for(defense_panel.ids[i])
		if o != null and o.task == DefensePlan.Task.PATROL and o.post != DefensePlan.NO_POST:
			_draw_patrol(o, Palette.INK if i == defense_panel.selected else Color(Palette.THATCH[1], 0.8))
	# wybrany oddział na końcu, żeby jego znacznik był na wierzchu (domyślne miejsca bywają wspólne)
	var order: Array[int] = []
	for i in defense_panel.ids.size():
		if i != defense_panel.selected:
			order.append(i)
	if defense_panel.selected < defense_panel.ids.size():
		order.append(defense_panel.selected)
	for i in order:
		var o := defense.order_for(defense_panel.ids[i])
		var unit := int((defense_panel.squads[i] as Array)[0])
		var cls := UnitTypes.unit_class(unit)
		var post := defense.post_for(defense_panel.ids[i])
		# oddział bez zadania: miejsce zadania domyślnego jego klasy, w przygaszonej ramce (#20)
		var fallback := o == null
		if fallback:
			var d := DefensePlan.default_order(grid, cls, grid.age())
			post = d.post if d != null else DefensePlan.NO_POST
		if post == DefensePlan.NO_POST:
			continue
		var at := post * TerrainMap.CELL
		var blocked := not DefensePlan.post_problem(grid, post).is_empty() and not DefensePlan.station_post(grid, post)
		var col: Color = Palette.INK if i == defense_panel.selected else Palette.THATCH[1]
		if fallback and i != defense_panel.selected:
			col = Palette.WOOD[0]
		draw_rect(Rect2(at.x, at.y, TerrainMap.CELL, TerrainMap.CELL), Color(Palette.SHADOW, 0.7))
		CastleView.draw_frame(self, Rect2i(at, Vector2i.ONE * TerrainMap.CELL), Palette.ACCENT if blocked else col)
		PixelIcons.draw_unit(self, Vector2(at + Vector2i(2, 2)), unit)
	# pułapki (#100): znak rodzaju na ciemnym polu w czerwonej ramce
	for t in defense.traps:
		var tp := t.cell * TerrainMap.CELL
		draw_rect(Rect2(tp.x, tp.y, TerrainMap.CELL, TerrainMap.CELL), Color(Palette.SHADOW, 0.7))
		CastleView.draw_frame(self, Rect2i(tp, Vector2i.ONE * TerrainMap.CELL), Palette.ACCENT)
		PixelFont.draw_centered(self, Rect2(tp, Vector2.ONE * TerrainMap.CELL), TrapConfig.GLYPHS[t.kind], Palette.THATCH[2])


## Trasa patrolu: odcinki 1 px między punktami (z powrotem do pierwszego) i znaczniki 3×3 px punktów.
func _draw_patrol(o: DefensePlan.Order, col: Color) -> void:
	var points := o.patrol_points()
	if points.size() > 1:
		for k in points.size():
			var a := AttackPlanner.cell_center_px(points[k])
			var b := AttackPlanner.cell_center_px(points[(k + 1) % points.size()])
			for p in AttackPlanner.line_pixels(a, b):
				draw_rect(Rect2(p.x, p.y, 1, 1), col)
	for p in o.route:
		var c := AttackPlanner.cell_center_px(p)
		draw_rect(Rect2(c.x - 1, c.y - 1, 3, 3), col)


## Pasek postępu 2 px nad kratkami budowanego budynku, w całych pikselach.
## Animacja przebudowy Dworu na nową epokę (#34): od Dworu rozchodzą się 3 pierścienie pyłu
## w kolorach kamienia i sztandaru epoki II, w całych pikselach. Tylko wizualia, bez wpływu na grę.
func _draw_age_rebuild() -> void:
	if _age_anim_start_ms < 0 or grid.manor_id() == 0:
		return
	var t := _now_ms() - _age_anim_start_ms
	if t < 0 or t >= AGE_ANIM_MS:
		_age_anim_start_ms = -1
		return
	var r := grid.buildings[grid.manor_id()]
	var px_rect := Rect2i(r.position * TerrainMap.CELL, r.size * TerrainMap.CELL)
	for ring in 3:
		@warning_ignore("integer_division")
		var grow := (t - ring * 300) / 60
		if grow < 0:
			continue
		var fade := 1.0 - float(t) / AGE_ANIM_MS
		var col := Palette.AGE_II_ACCENT if ring == 1 else Palette.STONE[1]
		var g := px_rect.grow(grow)
		var a := Color(col, fade)
		for x in range(g.position.x, g.end.x, 3):
			draw_rect(Rect2(x, g.position.y, 1, 1), a)
			draw_rect(Rect2(x, g.end.y - 1, 1, 1), a)
		for y in range(g.position.y, g.end.y, 3):
			draw_rect(Rect2(g.position.x, y, 1, 1), a)
			draw_rect(Rect2(g.end.x - 1, y, 1, 1), a)


func _draw_progress(id: int) -> void:
	if not grid.buildings.has(id):
		return
	var r := grid.buildings[id]
	var w := r.size.x * TerrainMap.CELL - 2
	var at := r.position * TerrainMap.CELL + Vector2i(1, -3)
	@warning_ignore("integer_division")
	var fill := w * queue.progress_permille(id, _now_ms()) / 1000
	draw_rect(Rect2(at.x, at.y, w, 2), Palette.SHADOW)
	draw_rect(Rect2(at.x, at.y, fill, 2), Palette.VALID)
