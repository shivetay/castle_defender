class_name BuildingTextures
extends RefCounted
## Cache tekstur budynków. Każda kombinacja (rodzaj, poziom, stan, maska) jest rysowana raz,
## przy pierwszym użyciu albo w warm_up(), a potem zwracana z pamięci jako ImageTexture.

var _cache: Dictionary[int, ImageTexture] = {}


static func key(kind: int, level: int, state: int, mask: int) -> int:
	return ((kind * 8 + level) * 4 + state) * 16 + mask


## Tekstura budynku. Maska N/E/S/W liczy się tylko dla wału i palisady.
func draw_building(kind: int, level: int, state: int = BuildingTypes.State.INTACT, mask: int = 0) -> ImageTexture:
	var m := mask if BuildingTypes.is_wall(kind) else 0
	var lv := clampi(level, 1, BuildingTypes.MAX_LEVEL)
	var k := key(kind, lv, state, m)
	var tex: ImageTexture = _cache.get(k)
	if tex == null:
		tex = ImageTexture.create_from_image(BuildingArt.make_image(kind, lv, state, m))
		_cache[k] = tex
	return tex


## Rysuje z góry wszystkie całe (nieuszkodzone) warianty, żeby budowanie nie przycinało gry.
func warm_up() -> void:
	for kind in BuildingTypes.count():
		var masks := 16 if BuildingTypes.is_wall(kind) else 1
		for level in range(1, BuildingTypes.MAX_LEVEL + 1):
			for mask in masks:
				draw_building(kind, level, BuildingTypes.State.INTACT, mask)


func cached_count() -> int:
	return _cache.size()
