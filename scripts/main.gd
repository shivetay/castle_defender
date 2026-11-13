extends Node2D
## Etap 3: widok zamku z budynkami epoki I. Teren 64×64 kratki z seeda, siatka budowy, kamera
## z gestami. Pasek u dołu wybiera budynek, dotknięcie wolnej trawy go stawia, a dotknięcie
## budynku otwiera kartę z poziomem oraz przyciskami Ulepsz i Rozbierz.

const WORLD_SEED := 1337

var terrain: TerrainMap
var grid: BuildGrid
var camera: PanZoomCamera
var hud: Hud
var textures := BuildingTextures.new()

var _terrain_tex: ImageTexture
var _selected_id := 0
var _cursor := Rect2i()
var _cursor_ok := true


func _ready() -> void:
	terrain = TerrainMap.generate(WORLD_SEED)
	grid = BuildGrid.new(terrain)
	_terrain_tex = ImageTexture.create_from_image(TerrainRenderer.render(terrain))
	textures.warm_up()

	camera = PanZoomCamera.new()
	camera.world_size = Vector2i(terrain.size, terrain.size) * TerrainMap.CELL
	add_child(camera)
	camera.make_current()
	camera.look_at_world(Vector2(terrain.center() * TerrainMap.CELL))
	camera.tapped.connect(_on_tapped)

	var layer := CanvasLayer.new()
	add_child(layer)
	hud = Hud.new()
	hud.camera = camera
	hud.world_seed = WORLD_SEED
	layer.add_child(hud)
	hud.kind_selected.connect(_on_kind_selected)
	hud.upgrade_pressed.connect(_on_upgrade)
	hud.demolish_pressed.connect(_on_demolish)
	hud.card_closed.connect(_deselect)


func _on_tapped(world_pos: Vector2) -> void:
	var cell := Vector2i((world_pos / TerrainMap.CELL).floor())
	var id := grid.building_at(cell)
	if id != 0:
		_select(id)
	elif _selected_id != 0:
		_deselect()
	else:
		var kind := hud.selected_kind
		_cursor = Rect2i(cell, BuildingTypes.size_of(kind))
		_cursor_ok = grid.place(_cursor, kind) != 0
		var title := BuildingTypes.NAMES[kind]
		hud.message = ("Postawiono: %s" % title) if _cursor_ok else "Tu nie można budować"
	queue_redraw()


func _on_kind_selected(kind: int) -> void:
	hud.message = "%s: dotknij trawy, aby postawić" % BuildingTypes.NAMES[kind]


func _select(id: int) -> void:
	_selected_id = id
	_cursor = Rect2i()
	_refresh_card()
	hud.message = "Ulepsz albo rozbierz budynek"


func _deselect() -> void:
	_selected_id = 0
	hud.hide_card()
	hud.message = "Wybierz budynek i dotknij trawy"
	queue_redraw()


func _refresh_card() -> void:
	hud.show_card(BuildingTypes.NAMES[grid.kinds[_selected_id]], grid.levels[_selected_id])
	queue_redraw()


func _on_upgrade() -> void:
	if grid.upgrade(_selected_id):
		hud.message = "Ulepszono do poziomu %d" % grid.levels[_selected_id]
		_refresh_card()
	else:
		hud.message = "Najwyższy poziom"


func _on_demolish() -> void:
	var title := BuildingTypes.NAMES[grid.kinds[_selected_id]]
	_cursor = grid.buildings[_selected_id]
	_cursor_ok = true
	grid.remove(_selected_id)
	_deselect()
	hud.message = "Rozebrano: %s" % title


func _draw() -> void:
	draw_texture(_terrain_tex, Vector2.ZERO)
	for id in grid.draw_order():
		var kind := grid.kinds[id]
		var tex := textures.draw_building(kind, grid.levels[id], BuildingTypes.State.INTACT, grid.wall_mask(id))
		var at := grid.buildings[id].position * TerrainMap.CELL - Vector2i(0, BuildingArt.EXTRA[kind])
		draw_texture(tex, Vector2(at))
	var frame := grid.buildings[_selected_id] if _selected_id != 0 else _cursor
	if frame.has_area():
		var r := Rect2(frame.position * TerrainMap.CELL, frame.size * TerrainMap.CELL)
		var ok := _selected_id != 0 or _cursor_ok
		draw_rect(r.grow(-0.5), Palette.VALID if ok else Palette.ACCENT, false, 1.0)
