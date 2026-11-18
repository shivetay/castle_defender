class_name BuildingTextures
extends RefCounted
## Cache tekstur budynków. Każda kombinacja (rodzaj, poziom, stan, maska) jest rysowana raz,
## przy pierwszym użyciu albo w warm_up(), a potem zwracana z pamięci jako ImageTexture.

var _cache: Dictionary[int, ImageTexture] = {}
## Zamalowana część obrazu każdej tekstury (do przyklejania budynków do murów, #149).
var _used: Dictionary[int, Rect2i] = {}
## Cienie rzucane na trawę (#150), z tym samym kluczem co tekstura, liczone przy pierwszym użyciu.
var _shadows: Dictionary[int, ImageTexture] = {}


static func key(kind: int, level: int, state: int, mask: int, vertical: bool = false, lean: int = 0) -> int:
	return ((((kind * 8 + level) * 4 + state) * 16 + mask) * 2 + (1 if vertical else 0)) * 5 + lean


## Tekstura budynku. Maska N/E/S/W liczy się tylko dla wału i palisady, `vertical` tylko dla bramy.
## `lean`: przybudówka przy murze (BuildingArt.Lean, #149), tylko dla rodzajów z BuildingArt.can_lean.
func draw_building(kind: int, level: int, state: int = BuildingTypes.State.INTACT, mask: int = 0,
		vertical: bool = false, lean: int = 0) -> ImageTexture:
	var m := mask if BuildingTypes.is_wall(kind) else 0
	var v := vertical and kind == BuildingTypes.Kind.GATE
	var lv := clampi(level, 0, BuildingTypes.MAX_LEVEL)
	var ln := lean if BuildingArt.can_lean(kind) and lv >= 1 else 0
	var k := key(kind, lv, state, m, v, ln)
	var tex: ImageTexture = _cache.get(k)
	if tex == null:
		var img := BuildingArt.make_image(kind, lv, state, m, v, ln)
		tex = ImageTexture.create_from_image(img)
		_cache[k] = tex
		_used[k] = img.get_used_rect()
	return tex


## Rysuje z góry wszystkie całe (nieuszkodzone) warianty i place budowy (poziom 0), także przybudówki
## przy murze (#149), żeby budowanie nie przycinało gry.
## Razem z teksturami rysuje ich cienie (#150), żeby pierwszy widok zamku nie przycinał.
func warm_up() -> void:
	for kind in BuildingTypes.count():
		var masks := 16 if BuildingTypes.is_wall(kind) else 1
		for level in range(0, BuildingTypes.MAX_LEVEL + 1):
			for mask in masks:
				shadow(kind, level, BuildingTypes.State.INTACT, mask)
			if kind == BuildingTypes.Kind.GATE:
				shadow(kind, level, BuildingTypes.State.INTACT, 0, true)
			if BuildingArt.can_lean(kind) and level >= 1:
				for lean in range(BuildingArt.Lean.NORTH, BuildingArt.Lean.WEST + 1):
					shadow(kind, level, BuildingTypes.State.INTACT, 0, false, lean)


## Rysuje stany uszkodzeń budynków z `grid` (pęknięcia, wyłom, gruz) z ich maskami / wpustami,
## żeby pierwszy wyłom w bitwie nie przycinał gry na telefonie (całe warianty są w warm_up).
func warm_up_damage(grid: BuildGrid) -> void:
	for id in grid.draw_order():
		var kind := grid.kinds[id]
		var level := grid.levels[id]
		var mask := grid.wall_mask(id)
		var vertical := grid.is_vertical(id)
		var lean := CastleView.lean_of(grid, id)
		for state in range(BuildingTypes.State.CRACKED, BuildingTypes.State.RUBBLE + 1):
			shadow(kind, level, state, mask, vertical, lean)
		for stub in grid.wall_stubs(id):
			var wall := grid.building_at(Vector2i(stub.x, stub.y) + CastleView.dir_of(stub.z))
			for state in range(BuildingTypes.State.CRACKED, BuildingTypes.State.RUBBLE + 1):
				draw_building(grid.kinds[wall], grid.levels[wall], state, stub.z)


func cached_count() -> int:
	return _cache.size()


## Zamalowany prostokąt tekstury (w pikselach obrazu), liczony raz razem z teksturą.
func used_rect(kind: int, level: int, state: int = BuildingTypes.State.INTACT, mask: int = 0,
		vertical: bool = false, lean: int = 0) -> Rect2i:
	draw_building(kind, level, state, mask, vertical, lean)
	var m := mask if BuildingTypes.is_wall(kind) else 0
	var v := vertical and kind == BuildingTypes.Kind.GATE
	var lv := clampi(level, 0, BuildingTypes.MAX_LEVEL)
	var ln := lean if BuildingArt.can_lean(kind) and lv >= 1 else 0
	return _used[key(kind, lv, state, m, v, ln)]


## Cień budynku na trawie (#150): sylwetka tekstury przesunięta o BuildingArt.shadow_offset.
## Rysuje się w tym samym miejscu co tekstura, przed wszystkimi budynkami.
func shadow(kind: int, level: int, state: int = BuildingTypes.State.INTACT, mask: int = 0,
		vertical: bool = false, lean: int = 0) -> ImageTexture:
	var tex := draw_building(kind, level, state, mask, vertical, lean)
	var m := mask if BuildingTypes.is_wall(kind) else 0
	var v := vertical and kind == BuildingTypes.Kind.GATE
	var lv := clampi(level, 0, BuildingTypes.MAX_LEVEL)
	var ln := lean if BuildingArt.can_lean(kind) and lv >= 1 else 0
	var k := key(kind, lv, state, m, v, ln)
	var sh: ImageTexture = _shadows.get(k)
	if sh == null:
		sh = ImageTexture.create_from_image(BuildingArt.shadow_image(tex.get_image(), BuildingArt.shadow_offset(kind)))
		_shadows[k] = sh
	return sh
