class_name CastleView
extends RefCounted
## Rysowanie zamku z siatki budowy: budynki w kolejności rysowania z wpustami palisady. Wspólne dla
## własnego zamku (main) i zamku-celu ataku (#17), żeby oba wyglądały tak samo.


## Rysuje wszystkie budynki `grid` na `ci` (w pikselach mapy), z tekstur z `textures`.
static func draw_buildings(ci: CanvasItem, grid: BuildGrid, textures: BuildingTextures) -> void:
	for id in grid.draw_order():
		var kind := grid.kinds[id]
		draw_wall_stubs(ci, grid, textures, id)
		var tex := textures.draw_building(kind, grid.levels[id], BuildingTypes.State.INTACT,
				grid.wall_mask(id), grid.is_vertical(id))
		ci.draw_texture(tex, Vector2(texture_origin(grid.buildings[id].position, kind)))


static func texture_origin(cell: Vector2i, kind: int) -> Vector2i:
	return cell * TerrainMap.CELL - Vector2i(0, BuildingArt.EXTRA[kind])


## Wpusty: na kratce budynku przy sąsiedniej palisadzie rysuje się jej krótki odcinek (od krawędzi
## do środka kratki), a budynek przykrywa go zaraz potem. Linia dochodzi wtedy do korpusu.
static func draw_wall_stubs(ci: CanvasItem, grid: BuildGrid, textures: BuildingTextures, id: int) -> void:
	for stub in grid.wall_stubs(id):
		var c := Vector2i(stub.x, stub.y)
		var wall := grid.building_at(c + dir_of(stub.z))
		var kind := grid.kinds[wall]
		var tex := textures.draw_building(kind, grid.levels[wall], BuildingTypes.State.INTACT, stub.z)
		ci.draw_texture(tex, Vector2(texture_origin(c, kind)))


static func dir_of(bit: int) -> Vector2i:
	match bit:
		BuildingTypes.N:
			return Vector2i.UP
		BuildingTypes.E:
			return Vector2i.RIGHT
		BuildingTypes.S:
			return Vector2i.DOWN
	return Vector2i.LEFT


## Ramka 1 px wewnątrz prostokąta, z czterech pełnych pasków na całych pikselach.
static func draw_frame(ci: CanvasItem, r: Rect2i, col: Color) -> void:
	ci.draw_rect(Rect2(r.position.x, r.position.y, r.size.x, 1), col)
	ci.draw_rect(Rect2(r.position.x, r.end.y - 1, r.size.x, 1), col)
	ci.draw_rect(Rect2(r.position.x, r.position.y + 1, 1, r.size.y - 2), col)
	ci.draw_rect(Rect2(r.end.x - 1, r.position.y + 1, 1, r.size.y - 2), col)
