class_name CastleView
extends RefCounted
## Rysowanie zamku z siatki budowy: budynki w kolejności rysowania z wpustami palisady. Wspólne dla
## własnego zamku (main) i zamku-celu ataku (#17), żeby oba wyglądały tak samo.


## Rysuje wszystkie budynki `grid` na `ci` (w pikselach mapy), z tekstur z `textures`.
## Najpierw cienie wszystkich budynków (#150), żeby żaden cień nie padał na sąsiedni budynek.
static func draw_buildings(ci: CanvasItem, grid: BuildGrid, textures: BuildingTextures) -> void:
	for id in grid.draw_order():
		var kind := grid.kinds[id]
		var sh := textures.shadow(kind, grid.levels[id], BuildingTypes.State.INTACT,
				grid.wall_mask(id), grid.is_vertical(id), lean_of(grid, id))
		ci.draw_texture(sh, Vector2(texture_origin(grid.buildings[id].position, kind) + attach_offset(grid, textures, id)))
	for id in grid.draw_order():
		var kind := grid.kinds[id]
		draw_wall_stubs(ci, grid, textures, id)
		var tex := textures.draw_building(kind, grid.levels[id], BuildingTypes.State.INTACT,
				grid.wall_mask(id), grid.is_vertical(id), lean_of(grid, id))
		ci.draw_texture(tex, Vector2(texture_origin(grid.buildings[id].position, kind) + attach_offset(grid, textures, id)))


## Najdalej o tyle pikseli budynek przyklejony do muru przesuwa się w jego stronę.
const MAX_ATTACH_SHIFT := 6


## Przesunięcie rysunku budynku przyklejonego bokiem do wału albo palisady (#149): o tyle całych
## pikseli, ile pustego miejsca dzieli zamalowaną część budynku od zamalowanej części muru, w stronę
## muru (najwyżej MAX_ATTACH_SHIFT). Siatka się nie zmienia, a na styku nie ma szpary ani drugiej ściany.
static func attach_offset(grid: BuildGrid, textures: BuildingTextures, id: int) -> Vector2i:
	var side: Array = grid.wall_side(id)
	var dir: Vector2i = side[0]
	if dir == Vector2i.ZERO:
		return Vector2i.ZERO
	var kind := grid.kinds[id]
	var b_used := textures.used_rect(kind, grid.levels[id], BuildingTypes.State.INTACT, 0, false, lean_of(grid, id))
	var b := Rect2i(texture_origin(grid.buildings[id].position, kind) + b_used.position, b_used.size)
	var wc: Vector2i = side[1]
	var wid := grid.building_at(wc)
	var w_used := textures.used_rect(grid.kinds[wid], grid.levels[wid], BuildingTypes.State.INTACT, grid.wall_mask(wid))
	var w := Rect2i(texture_origin(wc, grid.kinds[wid]) + w_used.position, w_used.size)
	var gap := 0
	match dir:
		Vector2i.UP:
			gap = b.position.y - w.end.y
		Vector2i.DOWN:
			gap = w.position.y - b.end.y
		Vector2i.LEFT:
			gap = b.position.x - w.end.x
		Vector2i.RIGHT:
			gap = w.position.x - b.end.x
	return dir * clampi(gap, 0, MAX_ATTACH_SHIFT)


## Strona przybudówki budynku `id` (BuildingArt.Lean): od muru, do którego przylega (#149).
static func lean_of(grid: BuildGrid, id: int) -> int:
	if not BuildingArt.can_lean(grid.kinds[id]):
		return BuildingArt.Lean.NONE
	return BuildingArt.lean_from((grid.wall_side(id)[0]) as Vector2i)


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
