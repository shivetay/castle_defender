extends Node2D
## Etap 2: widok zamku. Teren 64×64 kratki z seeda, siatka budowy i kamera z gestami.
## Dotknięcie wolnej trawy stawia chatę (2×2 kratki), dotknięcie chaty ją usuwa.

const WORLD_SEED := 1337
const HUT_SIZE := Vector2i(2, 2)

var terrain: TerrainMap
var grid: BuildGrid
var camera: PanZoomCamera
var hud: Hud

var _terrain_tex: ImageTexture
var _hut_tex: ImageTexture
var _cursor := Rect2i()
var _cursor_ok := true


func _ready() -> void:
	terrain = TerrainMap.generate(WORLD_SEED)
	grid = BuildGrid.new(terrain)
	_terrain_tex = ImageTexture.create_from_image(TerrainRenderer.render(terrain))
	var hut := Image.create(HUT_SIZE.x * TerrainMap.CELL, HUT_SIZE.y * TerrainMap.CELL, false, Image.FORMAT_RGBA8)
	PixelCanvas.draw_hut(hut, Vector2i(2, 2))
	_hut_tex = ImageTexture.create_from_image(hut)

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


func _on_tapped(world_pos: Vector2) -> void:
	var cell := Vector2i((world_pos / TerrainMap.CELL).floor())
	var id := grid.building_at(cell)
	if id != 0:
		_cursor = grid.buildings[id]
		grid.remove(id)
		_cursor_ok = true
		hud.message = "Rozebrano chatę"
	else:
		_cursor = Rect2i(cell, HUT_SIZE)
		_cursor_ok = grid.place(_cursor) != 0
		hud.message = "Postawiono chatę" if _cursor_ok else "Tu nie można budować"
	queue_redraw()


func _draw() -> void:
	draw_texture(_terrain_tex, Vector2.ZERO)
	for rect: Rect2i in grid.buildings.values():
		draw_texture(_hut_tex, Vector2(rect.position * TerrainMap.CELL))
	if _cursor.has_area():
		var r := Rect2(_cursor.position * TerrainMap.CELL, _cursor.size * TerrainMap.CELL)
		draw_rect(r.grow(-0.5), Palette.VALID if _cursor_ok else Palette.ACCENT, false, 1.0)
