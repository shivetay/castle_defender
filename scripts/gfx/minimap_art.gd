class_name MinimapArt
extends RefCounted
## Miniatura zamku na karcie celu (#24): wycinek SIZE×SIZE kratek terenu z seeda (1 px na kratkę)
## wokół zabudowy, a na nim zarys budynków jednym kolorem. Rodzajów budynków, poziomów, wojska
## i pułapek miniatura nie pokazuje (to zadanie zwiadu, #28). Tekstura powstaje raz dla celu
## i leży w cache.
@warning_ignore_start("integer_division")

const SIZE := 32
const BUILDING: Color = Palette.THATCH[2]
const BUILDING_EDGE: Color = Palette.WOOD[0]

static var _cache: Dictionary[String, ImageTexture] = {}


## Lewy górny róg wycinka: środek zarysu (albo mapy, gdy zarysu nie ma), przycięty do mapy.
static func window_origin(footprint: Array[Rect2i], map_size: int = TerrainMap.SIZE) -> Vector2i:
	var center := Vector2i(map_size / 2, map_size / 2)
	if not footprint.is_empty():
		var box := footprint[0]
		for r in footprint:
			box = box.merge(r)
		center = box.get_center()
	var limit := maxi(0, map_size - SIZE)
	return Vector2i(clampi(center.x - SIZE / 2, 0, limit), clampi(center.y - SIZE / 2, 0, limit))


## Kolor kratki terenu: trawa według wysokości, ścieżka, woda, most.
static func tile_color(map: TerrainMap, c: Vector2i) -> Color:
	match map.get_tile(c):
		TerrainMap.Tile.PATH:
			return Palette.EARTH[2]
		TerrainMap.Tile.WATER:
			return Palette.WATER[1]
		TerrainMap.Tile.BRIDGE:
			return Palette.WOOD[2]
	return Palette.GRASS[clampi(map.get_height(c), 0, Palette.GRASS.size() - 1)]


## Obraz miniatury: teren z `map_seed` i zarys budynków; obwódka budynku od południa i wschodu
## ciemniejsza, żeby sąsiednie budynki dało się rozróżnić.
static func castle_image(map_seed: int, footprint: Array[Rect2i]) -> Image:
	var map := AttackStart.terrain_map(map_seed)
	var origin := window_origin(footprint, map.size)
	var img := Image.create(SIZE, SIZE, false, Image.FORMAT_RGBA8)
	for y in SIZE:
		for x in SIZE:
			var c := origin + Vector2i(x, y)
			img.set_pixel(x, y, tile_color(map, c) if map.in_bounds(c) else Palette.SHADOW)
	var view := Rect2i(origin, Vector2i(SIZE, SIZE))
	for r in footprint:
		var part := r.intersection(view)
		if part.size.x <= 0 or part.size.y <= 0:
			continue
		for y in range(part.position.y, part.end.y):
			for x in range(part.position.x, part.end.x):
				var edge := (x == r.end.x - 1 or y == r.end.y - 1) and r.size != Vector2i.ONE
				img.set_pixel(x - origin.x, y - origin.y, BUILDING_EDGE if edge else BUILDING)
	return img


## Tekstura miniatury z cache pod kluczem celu (TargetSearch.Target.key()).
static func castle_texture(key: String, map_seed: int, footprint: Array[Rect2i]) -> ImageTexture:
	if not _cache.has(key):
		_cache[key] = ImageTexture.create_from_image(castle_image(map_seed, footprint))
	return _cache[key]


## Czyści cache (zamek gracza mógł się zmienić od ostatniego szukania).
static func clear_cache() -> void:
	_cache.clear()
