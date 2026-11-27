class_name BuildingTextures
extends RefCounted
## Cache tekstur budynków. Każda kombinacja (rodzaj, poziom, stan, maska) jest rysowana raz,
## przy pierwszym użyciu albo w warm_up(), a potem zwracana z pamięci jako ImageTexture.

var _cache: Dictionary[int, ImageTexture] = {}
## Zamalowana część obrazu każdej tekstury (do przyklejania budynków do murów, #149).
var _used: Dictionary[int, Rect2i] = {}
## Cienie rzucane na trawę (#150), z tym samym kluczem co tekstura, liczone przy pierwszym użyciu.
var _shadows: Dictionary[int, ImageTexture] = {}
## Proporce na teksturze (#36): Vector4i(x płachty przy drzewcu, y, kierunek ±1, 0 = ACCENT / 1 = AGE_II_ACCENT),
## wykryte raz na obrazie razem z teksturą. AmbientView rysuje na nich łopotanie.
var _flags: Dictionary[int, Array] = {}


## Poziom rysunku: 0–5 jak poziom w epoce I, a wszystkie poziomy epoki II (6–10) to jeden
## rysunek 6 (#34): budynek z poziomu 5 ze znakami nowej epoki. Wyjątek to Dwór (#81): każdy
## poziom epoki II ma własny rysunek.
static func art_level(level: int, kind: int = -1) -> int:
	if kind == BuildingTypes.Kind.MANOR:
		return clampi(level, 0, BuildingTypes.MAX_LEVEL * 2)
	return clampi(level, 0, BuildingTypes.MAX_LEVEL + 1)


## `cells` (obrys w kratkach, BuildingArt.footprint) odróżnia budynek ze starszego zapisu w starym
## rozmiarze od nowego (#340). Każdy bok mieści się w 0–7 kratkach.
static func key(kind: int, level: int, state: int, mask: int, vertical: bool = false, lean: int = 0,
		cells: Vector2i = Vector2i.ZERO) -> int:
	var c := BuildingArt.footprint(kind, cells)
	var k := ((((kind * 16 + level) * 4 + state) * 16 + mask) * 2 + (1 if vertical else 0)) * 5 + lean
	return (k * 8 + c.x) * 8 + c.y


## Klucz cache dla wariantu po sprowadzeniu parametrów do tych, od których zależy rysunek.
static func _key_of(kind: int, level: int, state: int, mask: int, vertical: bool, lean: int, cells: Vector2i) -> int:
	var m := mask if BuildingTypes.is_wall(kind) else 0
	var v := vertical and kind == BuildingTypes.Kind.GATE
	var lv := art_level(level, kind)
	var ln := lean if BuildingArt.can_lean(kind) and lv >= 1 else 0
	return key(kind, lv, state, m, v, ln, cells)


## Tekstura budynku. Maska N/E/S/W liczy się tylko dla wału i palisady, `vertical` tylko dla bramy.
## `lean`: przybudówka przy murze (BuildingArt.Lean, #149), tylko dla rodzajów z BuildingArt.can_lean.
## `cells`: obrys budynku w kratkach (BuildGrid.cells_of, #340); zero to rozmiar rodzaju.
func draw_building(kind: int, level: int, state: int = BuildingTypes.State.INTACT, mask: int = 0,
		vertical: bool = false, lean: int = 0, cells: Vector2i = Vector2i.ZERO) -> ImageTexture:
	var m := mask if BuildingTypes.is_wall(kind) else 0
	var v := vertical and kind == BuildingTypes.Kind.GATE
	var lv := art_level(level, kind)
	var ln := lean if BuildingArt.can_lean(kind) and lv >= 1 else 0
	var k := key(kind, lv, state, m, v, ln, cells)
	var tex: ImageTexture = _cache.get(k)
	if tex == null:
		var img := BuildingArt.make_image(kind, lv, state, m, v, ln, BuildingArt.footprint(kind, cells))
		tex = ImageTexture.create_from_image(img)
		_cache[k] = tex
		_used[k] = img.get_used_rect()
		_flags[k] = find_flags(img)
	return tex


## Proporce tekstury budynku (#36), w pikselach obrazu. Zburzony budynek zwykle już ich nie ma.
func flags(kind: int, level: int, state: int = BuildingTypes.State.INTACT, mask: int = 0,
		vertical: bool = false, lean: int = 0, cells: Vector2i = Vector2i.ZERO) -> Array:
	draw_building(kind, level, state, mask, vertical, lean, cells)
	return _flags[_key_of(kind, level, state, mask, vertical, lean, cells)]


## Szuka proporców z PixelCanvas.pennant: płachta 3×2 w kolorze sztandaru z wcięciem w dolnym rogu
## od strony swobodnego końca i bez sztandaru przy drzewcu. Lustro (przybudówka z prawej) łopocze na zachód.
## Tarcze 2×2 i pasy bramy tego wzoru nie mają.
static func find_flags(img: Image) -> Array[Vector4i]:
	var found: Array[Vector4i] = []
	var size := img.get_size()
	for y in range(0, size.y - 1):
		for x in size.x:
			var col := _accent_of(img, x, y, size)
			if col < 0:
				continue
			for dir: int in [1, -1]:
				if _accent_of(img, x - dir, y, size) == col:
					continue
				if _accent_of(img, x + dir, y, size) == col and _accent_of(img, x + 2 * dir, y, size) == col \
						and _accent_of(img, x, y + 1, size) == col and _accent_of(img, x + dir, y + 1, size) == col \
						and _accent_of(img, x + 2 * dir, y + 1, size) != col and _accent_of(img, x + 3 * dir, y, size) != col:
					found.append(Vector4i(x, y, dir, col))
	return found


## 0 dla czerwieni epoki I, 1 dla błękitu epoki II, -1 dla innego koloru albo spoza obrazu.
static func _accent_of(img: Image, x: int, y: int, size: Vector2i) -> int:
	if x < 0 or y < 0 or x >= size.x or y >= size.y:
		return -1
	var c := img.get_pixel(x, y)
	if c.a < 1.0:
		return -1
	if c.is_equal_approx(Palette.ACCENT):
		return 0
	if c.is_equal_approx(Palette.AGE_II_ACCENT):
		return 1
	return -1


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


func cached_count() -> int:
	return _cache.size()


## Zamalowany prostokąt tekstury (w pikselach obrazu), liczony raz razem z teksturą.
func used_rect(kind: int, level: int, state: int = BuildingTypes.State.INTACT, mask: int = 0,
		vertical: bool = false, lean: int = 0, cells: Vector2i = Vector2i.ZERO) -> Rect2i:
	draw_building(kind, level, state, mask, vertical, lean, cells)
	return _used[_key_of(kind, level, state, mask, vertical, lean, cells)]


## Cień budynku na trawie (#150): sylwetka tekstury przesunięta o BuildingArt.shadow_offset.
## Rysuje się w tym samym miejscu co tekstura, przed wszystkimi budynkami.
func shadow(kind: int, level: int, state: int = BuildingTypes.State.INTACT, mask: int = 0,
		vertical: bool = false, lean: int = 0, cells: Vector2i = Vector2i.ZERO) -> ImageTexture:
	var tex := draw_building(kind, level, state, mask, vertical, lean, cells)
	var k := _key_of(kind, level, state, mask, vertical, lean, cells)
	var sh: ImageTexture = _shadows.get(k)
	if sh == null:
		sh = ImageTexture.create_from_image(BuildingArt.shadow_image(tex.get_image(), BuildingArt.shadow_offset(kind)))
		_shadows[k] = sh
	return sh
