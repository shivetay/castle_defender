extends Node2D
## Widok zamku z budynkami epoki I, ekonomią i kolejką budowy. Teren 64×64 kratki z seeda,
## siatka budowy, kamera z gestami. Na środku od startu stoi Dwór (poziom zamku).
## Tryb oglądania: dotknięcie budynku otwiera kartę z przyciskami Ulepsz, Rozbierz (albo Anuluj
## dla zlecenia w kolejce) i Zamknij, z kosztem ulepszenia. Przycisk Buduj otwiera panel budowy
## (BuildPanel), a Postaw włącza tryb budowy wybranego budynku: dotknięcie wolnej trawy zleca budowę (koszt schodzi od razu, na kratkach staje plac budowy,
## budynek powstaje po czasie z BuildConfig); Zmień wraca do panelu, Gotowe do oglądania. Surowce i budowa
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

## Epoka gry. Przejście do epoki II dojdzie z #34.
const CURRENT_AGE := 0

## Komunikat, gdy Rybak nie styka się z wodą (#122).
const FISHER_HINT := "Rybak musi stać tuż przy rzece"
const KEEP_NO_ROOM := "Brak miejsca na donżon: rozbierz coś obok Dworu"

## Komunikat w trybie oglądania.
const DEFAULT_MESSAGE := Hud.VIEW_MESSAGE
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
## Ekran startowy (#177): po uruchomieniu i z przycisku Menu w HUD-zie.
var start_menu: StartMenu
## Nowa gra przeładowuje scenę bez zapisu; wtedy menu się nie pokazuje drugi raz.
static var skip_menu := false
var build_panel: BuildPanel
var queue_panel: QueuePanel
## Ile fal samouczka PvE (#16) gracz obronił; trwająca bitwa (null poza bitwą).
var pve_cleared := 0
var battle_view: BattleView
var _battle_wave := -1
## Oddziały armii w kolejności oddziałów bitwy, do rozliczenia strat po fali (#164).
var _battle_ids: Array[int] = []
## Atak na zamek-cel (#17): zapisany plan, ile zamków gracz już zdobył, ekran planu i zamek-cel.
var attack_plan := AttackPlan.new()
var bots_beaten := 0
var planner: AttackPlanner
var attack_panel: AttackPanel
## Ustawienia obrony (#19): posterunki załogi i panel edycji (widoczny w trybie edycji obrony).
var defense := DefensePlan.new()
var defense_panel: DefensePanel
## Czy trwająca bitwa to atak (inaczej fala PvE).
var _attacking := false

var _terrain_tex: ImageTexture
## Dym z kominów i błyski na wodzie (#150), nad budynkami.
var ambient: AmbientView
var _selected_id := 0
var _cursor := Rect2i()
var _cursor_ok := true


func _ready() -> void:
	var saved := SaveGame.load_state(SaveGame.PATH, _now_ms())
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
		defense = saved.defense
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
	hud.message = KEEP_NO_ROOM if keep_missing else DEFAULT_MESSAGE
	hud.build_pressed.connect(_on_build_panel_opened)
	hud.change_pressed.connect(_on_build_panel_opened)
	hud.build_mode_changed.connect(_on_build_mode_changed)
	hud.siege_pressed.connect(_on_siege_pressed)
	hud.speed_pressed.connect(_on_speed_pressed)
	hud.upgrade_pressed.connect(_on_upgrade)
	hud.demolish_pressed.connect(_on_middle_button)
	hud.card_closed.connect(_deselect)
	hud.research_pressed.connect(_on_research_opened)
	hud.attack_pressed.connect(_on_attack_pressed)
	hud.defence_pressed.connect(_on_defence_pressed)
	hud.queue_pressed.connect(_on_queue_opened)

	attack_panel = AttackPanel.new()
	attack_panel.planner = planner
	attack_panel.visible = false
	layer.add_child(attack_panel)
	attack_panel.changed.connect(_on_plan_changed)
	attack_panel.back_requested.connect(_close_attack)
	attack_panel.attack_requested.connect(_on_attack_launched)

	defense_panel = DefensePanel.new()
	defense_panel.research = research
	defense_panel.economy = economy
	defense_panel.goods = goods
	defense_panel.visible = false
	layer.add_child(defense_panel)
	defense_panel.changed.connect(_on_defence_changed)
	defense_panel.back_requested.connect(_close_defence)

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
	research_panel.age = CURRENT_AGE
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
	recruit_panel.age = CURRENT_AGE
	recruit_panel.visible = false
	layer.add_child(recruit_panel)
	recruit_panel.train_requested.connect(_on_train_requested)
	recruit_panel.closed.connect(_on_overlay_closed)
	# menu dodane na końcu dostaje dotyk przed HUD-em i panelami
	start_menu = StartMenu.new()
	start_menu.has_save = saved != null
	start_menu.visible = false
	layer.add_child(start_menu)
	start_menu.continue_pressed.connect(_on_menu_continue)
	start_menu.new_game_requested.connect(_on_new_game)
	hud.menu_pressed.connect(_on_menu_opened)
	if saved != null:
		_catch_up("Witaj z powrotem: ")
	_save()
	var preview := OS.is_debug_build() and OS.get_cmdline_user_args().has(BATTLE_PREVIEW_ARG)
	if skip_menu or preview:
		skip_menu = false
	else:
		hud.overlay = true
		start_menu.open()
	if preview:
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
			defense.battle_orders(recruitment.battle_ids(), recruitment.battle_squads(), grid, CURRENT_AGE))
	view.battle.tower_priority = defense.tower_priority
	view.battle.arm_traps(defense.traps)
	view.battle.add_side_morale(Battle.Side.DEFENDER, BattleConfig.defender_morale_bonus(research))
	view.battle.apply_research(Battle.Side.DEFENDER, research)
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


func _process(_delta: float) -> void:
	_tick()
	if battle_view != null:
		_update_battle()
	if not queue.orders.is_empty():
		queue_redraw()
		if _selected_id != 0:
			_refresh_card()


func _notification(what: int) -> void:
	if economy == null or hud == null:
		return
	match what:
		NOTIFICATION_APPLICATION_RESUMED:
			_catch_up("Podczas nieobecności: ")
		NOTIFICATION_APPLICATION_PAUSED, NOTIFICATION_APPLICATION_FOCUS_OUT, NOTIFICATION_WM_CLOSE_REQUEST:
			# Android potrafi zabić aplikację w tle bez ostrzeżenia, więc zapis idzie przy wyjściu
			_tick()
			_save()


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
	# posterunki rozwiązanych oddziałów (np. po stratach) nie trafiają do zapisu
	defense.prune(recruitment)
	var err := SaveGame.write(SaveGame.PATH, SaveGame.to_dict(world_seed, grid, economy, queue, research, goods, recruitment,
			pve_cleared, attack_plan, bots_beaten, defense))
	if err != OK:
		push_warning("Nie udało się zapisać gry: %s" % error_string(err))


static func _now_ms() -> int:
	return int(Time.get_unix_time_from_system() * 1000.0)


## Kończy budowy, których czas minął, i nalicza produkcję do teraz. Wołane co klatkę i przed
## każdą zmianą budynków, żeby czas sprzed zmiany liczył się po starych stawkach.
func _tick() -> void:
	var now := _now_ms()
	var researching := research.active
	# towary po surowcach w każdym punkcie czasu: wytwórcy zużywają drewno i żywność naliczone do tej chwili
	var done := queue.update(now, grid, economy, research, goods)
	for o in done:
		hud.message = "Ukończono: %s, poziom %d" % [BuildingTypes.NAMES[o.kind], o.level]
	if not researching.is_empty() and research.is_done(researching):
		hud.message = "Zbadano: %s %s" % [researching, TechTree.tech_name(researching)]
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
	if not trained.is_empty():
		_save()
	hud.queue_text = ""
	hud.queue_count = queue.orders.size() + recruitment.orders.size()
	hud.goal_text = TutorialGoals.text(pve_cleared, grid, research, recruitment)
	hud.research_text = "" if not research.is_busy() else "Bad. %s" % Hud.format_time(research.remaining_ms(now))
	hud.age_text = Ages.label(0, grid.manor_level())
	if not queue.orders.is_empty():
		hud.queue_text = Hud.format_time(queue.remaining_ms(queue.orders[0].building_id, now))
		if queue.orders.size() > 1:
			hud.queue_text += " +%d" % (queue.orders.size() - 1)
	if not done.is_empty():
		_save()
		if _selected_id != 0:
			_refresh_card()
		queue_redraw()


## Dotknięcie mapy. W trybie oglądania zaznacza budynek (albo zamyka kartę), w trybie budowy
## tylko stawia wybrany budynek i niczego nie zaznacza.
func _on_tapped(world_pos: Vector2) -> void:
	if battle_view != null:
		return  # w trakcie fali tylko tempo (#16)
	if planner.visible:
		_on_plan_changed(AttackPlanner.tap(planner.order(), planner.bot.grid, Vector2i((world_pos / TerrainMap.CELL).floor())))
		return
	if defense_panel.visible:
		_on_defence_changed(defense_panel.tap(grid, Vector2i((world_pos / TerrainMap.CELL).floor())))
		return
	_tick()
	var cell := Vector2i((world_pos / TerrainMap.CELL).floor())
	var id := grid.building_at(cell)
	if not hud.building:
		if id != 0:
			_select(id)
		elif _selected_id != 0:
			_deselect()
		queue_redraw()
		return
	if id != 0 and hud.selected_kind == BuildingTypes.Kind.GATE and BuildingTypes.is_wall(grid.kinds[id]):
		id = 0  # brama na wale albo palisadzie: zastępuje odcinki w linii (po teście na telefonie)
	if id != 0 and BuildingTypes.is_wall(hud.selected_kind):
		# palec w wąskiej luce linii umocnień trafił w sąsiedni odcinek: budujemy w luce
		var gap := grid.gap_near(world_pos, hud.selected_kind, GAP_TAP_TOLERANCE)
		if gap.x >= 0:
			cell = gap
			id = 0
	if id != 0:
		hud.message = "Tu stoi %s" % BuildingTypes.NAMES[grid.kinds[id]]
	else:
		var kind := hud.selected_kind
		var result := queue.order_build(grid, economy, cell, kind, _now_ms(), research)
		_cursor_ok = result == BuildQueue.Result.OK
		# przy nieudanej próbie ramka ma kształt pierwszego wariantu (np. pionowej bramy)
		_cursor = grid.buildings[queue.placed_id] if _cursor_ok else grid.placement_candidates(cell, kind, true)[0]
		if _cursor_ok:
			hud.message = "Budowa: %s, %s" % [BuildingTypes.NAMES[kind], Hud.format_time(BuildConfig.time_ms(kind, 1))]
			_save()
		elif result == BuildQueue.Result.NEEDS_TECH:
			hud.message = _tech_hint(kind)
		elif result == BuildQueue.Result.NO_PLACE and _fisher_lacks_water(cell, kind):
			hud.message = FISHER_HINT
		else:
			hud.message = BuildQueue.MESSAGES[result]
	queue_redraw()


## Panel budowy (Buduj w trybie oglądania albo Zmień w trybie budowy).
func _on_build_panel_opened() -> void:
	_tick()
	_selected_id = 0
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
	hud.message = build_message(kind)
	queue_redraw()


## Zamknij w panelu budowy. Otwarty przez Zmień (w trybie budowy) wraca do stawiania dotychczasowego
## budynku z jego kosztem w komunikacie; otwarty przez Buduj wraca do oglądania (review #160).
func _on_build_panel_closed() -> void:
	hud.overlay = false
	hud.message = closed_message(hud.building, hud.selected_kind)
	queue_redraw()


## Komunikat trybu budowy: nazwa, koszt i czas wybranego budynku.
static func build_message(kind: int) -> String:
	return "%s: %s, %s" % [BuildingTypes.NAMES[kind], Hud.cost_text(BuildConfig.cost(kind, 1)),
			Hud.format_time(BuildConfig.time_ms(kind, 1))]


## Komunikat po zamknięciu panelu budowy bez Postaw.
static func closed_message(building: bool, kind: int) -> String:
	return build_message(kind) if building else DEFAULT_MESSAGE


## Czy Rybak nie staje tylko przez brak wody: ten sam prostokąt bez warunku wody byłby wolny
## (review PR 143). Przy innych przeszkodach zostaje zwykły komunikat „Tu nie można budować”.
func _fisher_lacks_water(cell: Vector2i, kind: int) -> bool:
	if kind != BuildingTypes.Kind.FISHER:
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
	hud.message = queue.upgrade_hint(grid, id)


func _deselect() -> void:
	_selected_id = 0
	hud.hide_card()
	hud.message = DEFAULT_MESSAGE
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
	var b := Battle.for_castle_squads(grid, PveWaves.squads(_battle_wave), recruitment.battle_squads(), _edge_road(),
			PveWaves.battle_seed(world_seed, _battle_wave), research,
			defense.battle_orders(_battle_ids, recruitment.battle_squads(), grid, CURRENT_AGE),
			defense.tower_priority)
	b.arm_traps(defense.traps)  # pułapki działają raz na bitwę, a w układzie zostają (odnawiają się, #100)
	b.apply_research(Battle.Side.DEFENDER, research)  # A2 łuki i O2 palisady obrońcy (#12)
	battle_view = BattleView.new()
	battle_view.battle = b
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
## Komunikat po fali: wynik, polegli (gdy są) i nagroda za wygraną.
static func wave_end_message(wave: int, won: bool, reward: Array[int], fallen: int) -> String:
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
	hud.queue_text = "%s %s" % ["Atak" if _attacking else "Fala %d" % (_battle_wave + 1), Hud.format_time(left_ms)]
	if b.winner == Battle.Winner.NONE:
		return
	if _attacking:
		_finish_attack(b)
		return
	# polegli znikają z armii, ocalali (także wycofani) wracają do swoich oddziałów (#164)
	var fallen := recruitment.apply_losses(_battle_ids, b.survivors(Battle.Side.DEFENDER))
	var won := b.winner == Battle.Winner.DEFENDER
	var reward: Array[int] = PveWaves.reward(_battle_wave) if won else []
	if won:
		for res in reward.size():
			economy.add(res, reward[res])
		pve_cleared = maxi(pve_cleared, _battle_wave + 1)
	hud.message = wave_end_message(_battle_wave, won, reward, fallen)
	if won and _battle_wave == PveWaves.COUNT - 1:
		hud.message = TutorialGoals.done_message(reward, fallen)  # koniec prowadzenia (#185), dalej zwykła gra
	battle_view.queue_free()
	battle_view = null
	hud.battle = false
	_battle_wave = -1
	_save()
	queue_redraw()


# --- Atak na zamek-cel (#17) -----------------------------------------------------------------------

## Oddziały armii, które idą do ataku: pierwsze tyle, ile mieści plan w bieżącej epoce.
func _attack_army() -> Array:
	var army := recruitment.battle_squads()
	return army.slice(0, AttackPlan.max_squads(CURRENT_AGE))


func _bot() -> BotCastle:
	if planner.bot != null and planner.bot.strength == bots_beaten \
			and planner.bot.seed_value == BotCastle.seed_for(world_seed, bots_beaten):
		return planner.bot
	return BotCastle.generate(BotCastle.seed_for(world_seed, bots_beaten), bots_beaten)


## Atak: ekran planu na zamku-celu. Bez wojska ekran się nie otwiera.
func _on_attack_pressed() -> void:
	_tick()
	var army := _attack_army()
	if army.is_empty():
		hud.message = "Najpierw wyszkol wojsko: Koszary i Wojsko"
		return
	_selected_id = 0
	hud.hide_card()
	hud.set_building(false)
	_cursor = Rect2i()
	var bot := _bot()
	planner.open(bot, attack_plan, army, CURRENT_AGE)
	attack_panel.visible = true
	hud.overlay = true
	camera.look_at_world(Vector2(bot.grid.buildings[bot.objective].get_center() * TerrainMap.CELL))
	var all := recruitment.battle_squads().size()
	hud.message = AttackPlanner.HINT if all <= army.size() else \
			"W ataku %d z %d oddziałów (limit epoki)" % [army.size(), all]
	queue_redraw()


func _on_plan_changed(message: String) -> void:
	hud.message = message
	planner.queue_redraw()
	_save()


## Wróć: koniec planowania, widok własnego zamku. Plan zostaje zapisany.
func _close_attack() -> void:
	planner.visible = false
	attack_panel.visible = false
	hud.overlay = false
	hud.message = DEFAULT_MESSAGE
	camera.look_at_world(Vector2(grid.buildings[grid.manor_id()].get_center() * TerrainMap.CELL))
	_save()
	queue_redraw()


## Atakuj: bitwa na zamku-celu według planu. Ekran planu chowa się, a mapa celu zostaje.
func _on_attack_launched() -> void:
	var army := _attack_army()
	var problem := attack_plan.problem(army.size(), CURRENT_AGE, research)
	if army.is_empty():
		problem = "Najpierw wyszkol wojsko: Koszary i Wojsko"
	if not problem.is_empty():
		hud.message = problem
		return
	var bot := planner.bot
	_battle_ids = recruitment.battle_ids().slice(0, army.size())
	var b := Battle.create_squads(bot.grid, bot.objective, army, bot.defenders, bot.spawn,
			PixelCanvas.hash2(bot.seed_value, bots_beaten, 0xa77) & 0x7fffffff)
	b.set_plan(AttackPlan.from_dict(attack_plan.to_dict()))
	b.apply_research(Battle.Side.ATTACKER, research)  # A1 topory i A2 łuki atakującego (#12)
	_attacking = true
	attack_panel.visible = false
	planner.show_plan = false
	planner.queue_redraw()
	hud.overlay = false
	battle_view = BattleView.new()
	battle_view.battle = b
	add_child(battle_view)
	hud.battle = true
	hud.speed_label = speed_label(battle_view.speed)
	hud.message = "Atak: %d oddziały ruszają" % army.size() if army.size() > 1 else "Atak: oddział rusza"
	_save()


## Koniec ataku: polegli znikają z armii, a zdobyty zamek odblokowuje kolejny, mocniejszy cel.
func _finish_attack(b: Battle) -> void:
	var fallen := recruitment.apply_losses(_battle_ids, b.survivors(Battle.Side.ATTACKER))
	var won := b.winner == Battle.Winner.ATTACKER
	if won:
		bots_beaten += 1
		for o in attack_plan.orders:
			AttackPlanner.clear(o)  # cel i trasa dotyczyły zdobytego zamku
	battle_view.queue_free()
	battle_view = null
	hud.battle = false
	_attacking = false
	_close_attack()
	hud.message = attack_end_message(won, fallen)
	_save()


static func attack_end_message(won: bool, fallen: int) -> String:
	var head := "Zamek zdobyty!" if won else "Atak odparty."
	return head if fallen == 0 else "%s Polegli: %d" % [head, fallen]


# --- Ustawienia obrony (#19) -------------------------------------------------------------------------

## Obrona: własny zamek w trybie edycji, z posterunkami załogi. Bez wojska tryb się nie otwiera.
func _on_defence_pressed() -> void:
	_tick()
	var army := recruitment.battle_squads()
	if army.is_empty():
		hud.message = "Najpierw wyszkol wojsko: Koszary i Wojsko"
		return
	if grid.keep_id() == 0:
		hud.message = KEEP_NO_ROOM
		return
	_selected_id = 0
	hud.hide_card()
	hud.set_building(false)
	_cursor = Rect2i()
	defense.prune(recruitment)
	defense_panel.open(defense, army, recruitment.battle_ids(), grid, CURRENT_AGE)
	hud.overlay = true
	camera.look_at_world(Vector2(DefensePlan.keep_center(grid) * TerrainMap.CELL))
	hud.message = DefensePanel.HINT
	queue_redraw()


func _on_defence_changed(message: String) -> void:
	hud.message = message
	queue_redraw()
	_save()


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
	_on_army_opened(_selected_id)


func _on_train_requested(unit: int, squad_id: int) -> void:
	_tick()
	var now := _now_ms()
	var result: Recruitment.Result
	if recruit_panel.building_id == 0:
		result = recruitment.start_any(unit, squad_id, grid, economy, goods, research, CURRENT_AGE, now)
	else:
		result = recruitment.start(unit, recruit_panel.building_id, squad_id, grid, economy, goods, research,
				CURRENT_AGE, now)
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


## Menu z gry: zapis, karta i kursor się zamykają, a menu przykrywa mapę (#177).
func _on_menu_opened() -> void:
	_tick()
	_save()
	_deselect()
	_cursor = Rect2i()
	hud.overlay = true
	start_menu.has_save = true
	start_menu.open()
	queue_redraw()


func _on_menu_continue() -> void:
	start_menu.close()
	_on_overlay_closed()


## Nowa gra: bez zapisu po prostu wchodzi do świeżego zamku, a przy zapisie (już potwierdzonym w menu)
## usuwa go i przeładowuje scenę. Mapa zostaje ta sama, bo seed należy do gracza (PlayerProfile).
func _on_new_game() -> void:
	if not start_menu.has_save:
		_on_menu_continue()
		return
	SaveGame.delete(SaveGame.PATH)
	skip_menu = true
	get_tree().reload_current_scene()


func _on_overlay_closed() -> void:
	hud.overlay = false
	hud.message = DEFAULT_MESSAGE


func _on_research_requested(code: String) -> void:
	_tick()
	var result := research.start(code, CURRENT_AGE, economy, _now_ms(), grid)
	if result == Research.Result.NO_BUILDING:
		hud.message = Research.building_hint(code)
	elif result == Research.Result.OK:
		hud.message = "Badanie: %s, %s" % [TechTree.tech_name(code), Hud.format_time(research.duration_ms)]
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
	var status := "poziom %d/%d" % [level, BuildingTypes.MAX_LEVEL]
	if pending:
		status = "budowa %s" % Hud.format_time(queue.remaining_ms(_selected_id, _now_ms()))
	var can_upgrade := not pending and level < BuildConfig.max_level(kind, grid.manor_level())
	var middle_enabled := pending or not BuildingTypes.is_unique(kind)
	hud.card_recruit = level >= 1 and RecruitPanel.recruits(kind)
	hud.card_info = upgrade_info(kind, level, grid.manor_level(), pending)
	hud.card_info_missing = PackedStringArray() if pending or level >= BuildingTypes.MAX_LEVEL \
			else Hud.missing_tokens(BuildConfig.cost(kind, level + 1), economy.amounts)
	hud.show_card(BuildingTypes.NAMES[kind], status, can_upgrade, pending, middle_enabled)
	queue_redraw()


## Linia karty z kosztem ulepszenia, np. „Ulepsz: 180 Dr 60 Ka 60 Ży, 3:00”.
static func upgrade_info(kind: int, level: int, manor_level: int, pending: bool) -> String:
	if pending:
		return "Trwa budowa"
	if level >= BuildingTypes.MAX_LEVEL:
		return "Najwyższy poziom"
	var text := "Ulepsz: %s, %s" % [Hud.cost_text(BuildConfig.cost(kind, level + 1)),
			Hud.format_time(BuildConfig.time_ms(kind, level + 1))]
	if level >= BuildConfig.max_level(kind, manor_level):
		text += ", najpierw Dwór"
	return text


func _on_upgrade() -> void:
	_tick()
	var result := queue.order_upgrade(grid, economy, _selected_id, _now_ms())
	if result == BuildQueue.Result.OK:
		var o := queue.order_for(_selected_id)
		hud.message = "Ulepszanie do poziomu %d, %s" % [o.level, Hud.format_time(o.duration_ms)]
		_save()
	elif result == BuildQueue.Result.NEEDS_MANOR:
		hud.message = queue.upgrade_hint(grid, _selected_id)
	else:
		hud.message = BuildQueue.MESSAGES[result]
	_refresh_card()


## Środkowy przycisk karty: Anuluj dla budynku w kolejce, inaczej Rozbierz (Dworu i donżonu nie można).
func _on_middle_button() -> void:
	_tick()
	var title := BuildingTypes.NAMES[grid.kinds[_selected_id]]
	if queue.has_order(_selected_id):
		queue.cancel(grid, economy, _selected_id, _now_ms())
		_refresh_card()
		hud.message = "Anulowano: %s, surowce wróciły" % title
		_save()
		return
	if BuildingTypes.is_unique(grid.kinds[_selected_id]):
		hud.message = "Tego budynku nie można rozebrać"
		return
	_cursor = grid.buildings[_selected_id]
	_cursor_ok = true
	recruitment.drop_building(_selected_id)
	grid.remove(_selected_id)
	_deselect()
	hud.message = "Rozebrano: %s" % title
	_save()


func _draw() -> void:
	draw_texture(_terrain_tex, Vector2.ZERO)
	CastleView.draw_buildings(self, grid, textures)
	if not queue.orders.is_empty():
		_draw_progress(queue.orders[0].building_id)
	var frame := grid.buildings[_selected_id] if _selected_id != 0 else _cursor
	if frame.has_area():
		var ok := _selected_id != 0 or _cursor_ok
		CastleView.draw_frame(self, Rect2i(frame.position * TerrainMap.CELL, frame.size * TerrainMap.CELL),
				Palette.VALID if ok else Palette.ACCENT)
	if defense_panel != null and defense_panel.visible:
		_draw_defence()


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
		var cls := UnitTypes.unit_class(int((defense_panel.squads[i] as Array)[0]))
		var post := defense.post_for(defense_panel.ids[i])
		# oddział bez zadania: miejsce zadania domyślnego jego klasy, w przygaszonej ramce (#20)
		var fallback := o == null
		if fallback:
			var d := DefensePlan.default_order(grid, cls, CURRENT_AGE)
			post = d.post if d != null else DefensePlan.NO_POST
		if post == DefensePlan.NO_POST:
			continue
		var at := post * TerrainMap.CELL
		var blocked := not DefensePlan.post_problem(grid, post).is_empty() and not DefensePlan.wall_post(grid, post)
		var col: Color = Palette.INK if i == defense_panel.selected else Palette.THATCH[1]
		if fallback and i != defense_panel.selected:
			col = Palette.WOOD[0]
		draw_rect(Rect2(at.x, at.y, TerrainMap.CELL, TerrainMap.CELL), Color(Palette.SHADOW, 0.7))
		CastleView.draw_frame(self, Rect2i(at, Vector2i.ONE * TerrainMap.CELL), Palette.ACCENT if blocked else col)
		if PixelIcons.class_region(cls).has_area():
			PixelIcons.draw_class(self, Vector2(at + Vector2i(2, 2)), cls)
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
