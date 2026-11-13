extends Node2D
## Etap 4: widok zamku z budynkami epoki I, ekonomią i kolejką budowy. Teren 64×64 kratki z seeda,
## siatka budowy, kamera z gestami. Na środku od startu stoi Dwór (poziom zamku). Pasek u dołu
## wybiera budynek, a dotknięcie wolnej trawy zleca budowę: koszt schodzi od razu, na kratkach
## staje plac budowy, a budynek powstaje po czasie z BuildConfig. Dotknięcie budynku otwiera kartę
## z przyciskami Ulepsz, Rozbierz (albo Anuluj dla zlecenia w kolejce) i Zamknij. Surowce i budowa
## idą dalej, gdy gra jest w tle; po powrocie komunikat podaje, ile przybyło.

const WORLD_SEED := 1337

var terrain: TerrainMap
var grid: BuildGrid
var camera: PanZoomCamera
var hud: Hud
var textures := BuildingTextures.new()
var economy: Economy
var queue := BuildQueue.new()

var _terrain_tex: ImageTexture
var _selected_id := 0
var _cursor := Rect2i()
var _cursor_ok := true


func _ready() -> void:
	terrain = TerrainMap.generate(WORLD_SEED)
	grid = BuildGrid.new(terrain)
	economy = Economy.new(_now_ms())
	_place_manor()
	_terrain_tex = ImageTexture.create_from_image(TerrainRenderer.render(terrain))
	textures.warm_up()

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

	var layer := CanvasLayer.new()
	add_child(layer)
	hud = Hud.new()
	hud.camera = camera
	hud.world_seed = WORLD_SEED
	hud.economy = economy
	layer.add_child(hud)
	hud.kind_selected.connect(_on_kind_selected)
	hud.upgrade_pressed.connect(_on_upgrade)
	hud.demolish_pressed.connect(_on_middle_button)
	hud.card_closed.connect(_deselect)


## Dwór staje na pierwszym wolnym miejscu najbliżej środka mapy (kolejność stała dla seeda).
func _place_manor() -> void:
	var c := terrain.center()
	for r in terrain.size:
		for dy in range(-r, r + 1):
			for dx in range(-r, r + 1):
				if maxi(absi(dx), absi(dy)) != r:
					continue
				if grid.place_kind(c + Vector2i(dx, dy), BuildingTypes.Kind.MANOR) != 0:
					return


func _process(_delta: float) -> void:
	_tick()
	if not queue.orders.is_empty():
		queue_redraw()
		if _selected_id != 0:
			_refresh_card()


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_RESUMED and economy != null:
		var before: Array[int] = []
		before.assign(economy.amounts)
		_tick()
		var parts: PackedStringArray = []
		for res in before.size():
			if economy.amounts[res] > before[res]:
				parts.append("+%d %s" % [economy.amounts[res] - before[res], EconomyConfig.SHORT_NAMES[res]])
		if not parts.is_empty():
			hud.message = "Podczas nieobecności: " + " ".join(parts)


static func _now_ms() -> int:
	return int(Time.get_unix_time_from_system() * 1000.0)


## Kończy budowy, których czas minął, i nalicza produkcję do teraz. Wołane co klatkę i przed
## każdą zmianą budynków, żeby czas sprzed zmiany liczył się po starych stawkach.
func _tick() -> void:
	var now := _now_ms()
	var done := queue.update(now, grid, economy)
	for o in done:
		hud.message = "Ukończono: %s, poziom %d" % [BuildingTypes.NAMES[o.kind], o.level]
	hud.queue_text = ""
	if not queue.orders.is_empty():
		hud.queue_text = Hud.format_time(queue.remaining_ms(queue.orders[0].building_id, now))
		if queue.orders.size() > 1:
			hud.queue_text += " +%d" % (queue.orders.size() - 1)
	if not done.is_empty():
		if _selected_id != 0:
			_refresh_card()
		queue_redraw()


func _on_tapped(world_pos: Vector2) -> void:
	_tick()
	var cell := Vector2i((world_pos / TerrainMap.CELL).floor())
	var id := grid.building_at(cell)
	if id != 0:
		_select(id)
	elif _selected_id != 0:
		_deselect()
	else:
		var kind := hud.selected_kind
		var result := queue.order_build(grid, economy, cell, kind, _now_ms())
		_cursor_ok = result == BuildQueue.Result.OK
		# przy nieudanej próbie ramka ma kształt pierwszego wariantu (np. pionowej bramy)
		_cursor = grid.buildings[queue.placed_id] if _cursor_ok else grid.placement_candidates(cell, kind)[0]
		if _cursor_ok:
			hud.message = "Budowa: %s, %s" % [BuildingTypes.NAMES[kind], Hud.format_time(BuildConfig.time_ms(kind, 1))]
		else:
			hud.message = BuildQueue.MESSAGES[result]
	queue_redraw()


func _on_kind_selected(kind: int) -> void:
	hud.message = "%s: %s, %s" % [BuildingTypes.NAMES[kind], Hud.cost_text(BuildConfig.cost(kind, 1)),
			Hud.format_time(BuildConfig.time_ms(kind, 1))]


func _select(id: int) -> void:
	_selected_id = id
	_cursor = Rect2i()
	_refresh_card()
	hud.message = queue.upgrade_hint(grid, id)


func _deselect() -> void:
	_selected_id = 0
	hud.hide_card()
	hud.message = "Wybierz budynek i dotknij trawy"
	queue_redraw()


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
	var middle_enabled := pending or kind != BuildingTypes.Kind.MANOR
	hud.show_card(BuildingTypes.NAMES[kind], status, can_upgrade, pending, middle_enabled)
	queue_redraw()


func _on_upgrade() -> void:
	_tick()
	var result := queue.order_upgrade(grid, economy, _selected_id, _now_ms())
	if result == BuildQueue.Result.OK:
		var o := queue.order_for(_selected_id)
		hud.message = "Ulepszanie do poziomu %d, %s" % [o.level, Hud.format_time(o.duration_ms)]
	elif result == BuildQueue.Result.NEEDS_MANOR:
		hud.message = queue.upgrade_hint(grid, _selected_id)
	else:
		hud.message = BuildQueue.MESSAGES[result]
	_refresh_card()


## Środkowy przycisk karty: Anuluj dla budynku w kolejce, inaczej Rozbierz (Dworu nie można).
func _on_middle_button() -> void:
	_tick()
	var title := BuildingTypes.NAMES[grid.kinds[_selected_id]]
	if queue.has_order(_selected_id):
		queue.cancel(grid, economy, _selected_id, _now_ms())
		_refresh_card()
		hud.message = "Anulowano: %s, surowce wróciły" % title
		return
	if grid.kinds[_selected_id] == BuildingTypes.Kind.MANOR:
		hud.message = "Dworu nie można rozebrać"
		return
	_cursor = grid.buildings[_selected_id]
	_cursor_ok = true
	grid.remove(_selected_id)
	_deselect()
	hud.message = "Rozebrano: %s" % title


func _draw() -> void:
	draw_texture(_terrain_tex, Vector2.ZERO)
	for id in grid.draw_order():
		var kind := grid.kinds[id]
		_draw_wall_stubs(id)
		var tex := textures.draw_building(kind, grid.levels[id], BuildingTypes.State.INTACT,
				grid.wall_mask(id), grid.is_vertical(id))
		draw_texture(tex, Vector2(_texture_origin(grid.buildings[id].position, kind)))
	if not queue.orders.is_empty():
		_draw_progress(queue.orders[0].building_id)
	var frame := grid.buildings[_selected_id] if _selected_id != 0 else _cursor
	if frame.has_area():
		var ok := _selected_id != 0 or _cursor_ok
		_draw_frame(Rect2i(frame.position * TerrainMap.CELL, frame.size * TerrainMap.CELL),
				Palette.VALID if ok else Palette.ACCENT)


func _texture_origin(cell: Vector2i, kind: int) -> Vector2i:
	return cell * TerrainMap.CELL - Vector2i(0, BuildingArt.EXTRA[kind])


## Wpusty: na kratce budynku przy sąsiedniej palisadzie rysuje się jej krótki odcinek (od krawędzi
## do środka kratki), a budynek przykrywa go zaraz potem. Linia dochodzi wtedy do korpusu.
func _draw_wall_stubs(id: int) -> void:
	for stub in grid.wall_stubs(id):
		var c := Vector2i(stub.x, stub.y)
		var wall := grid.building_at(c + _dir_of(stub.z))
		var kind := grid.kinds[wall]
		var tex := textures.draw_building(kind, grid.levels[wall], BuildingTypes.State.INTACT, stub.z)
		draw_texture(tex, Vector2(_texture_origin(c, kind)))


static func _dir_of(bit: int) -> Vector2i:
	match bit:
		BuildingTypes.N:
			return Vector2i.UP
		BuildingTypes.E:
			return Vector2i.RIGHT
		BuildingTypes.S:
			return Vector2i.DOWN
	return Vector2i.LEFT


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


## Ramka 1 px wewnątrz prostokąta, z czterech pełnych pasków na całych pikselach.
func _draw_frame(r: Rect2i, col: Color) -> void:
	draw_rect(Rect2(r.position.x, r.position.y, r.size.x, 1), col)
	draw_rect(Rect2(r.position.x, r.end.y - 1, r.size.x, 1), col)
	draw_rect(Rect2(r.position.x, r.position.y + 1, 1, r.size.y - 2), col)
	draw_rect(Rect2(r.end.x - 1, r.position.y + 1, 1, r.size.y - 2), col)
