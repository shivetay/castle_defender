class_name PixelCanvas
extends RefCounted
## Proceduralne rysowanie pikseli do Image (bez zewnętrznych assetów).


## Deterministyczny hash kratki: ta sama współrzędna zawsze daje ten sam wynik.
static func hash2(x: int, y: int, seed: int = 0) -> int:
	var h: int = x * 374761393 + y * 668265263 + seed * 982451653
	h = (h ^ (h >> 13)) * 1274126177
	return (h ^ (h >> 16)) & 0x7fffffff


## Teren: trawa z szumu, 4 odcienie, bez powtarzalnego wzoru.
static func make_terrain(size: Vector2i, seed: int = 1) -> Image:
	var img := Image.create(size.x, size.y, false, Image.FORMAT_RGBA8)
	for y in size.y:
		for x in size.x:
			# łagodne „plamy” z hasha bloków 8×8 plus drobny szum pikseli
			var block := hash2(x >> 3, y >> 3, seed) % 3
			var grain := hash2(x, y, seed + 7) % 5
			var shade := clampi(block + (1 if grain == 0 else 0) - (1 if grain == 4 else 0), 0, 3)
			img.set_pixel(x, y, Palette.GRASS[shade])
	return img


## Ścieżka ziemna z ditheringiem 2×2 na krawędziach.
static func draw_path(img: Image, rect: Rect2i) -> void:
	for y in range(rect.position.y, rect.end.y):
		for x in range(rect.position.x, rect.end.x):
			var edge := x == rect.position.x or x == rect.end.x - 1
			if edge and (x + y) % 2 == 0:
				continue
			img.set_pixel(x, y, Palette.EARTH[2 + hash2(x, y, 3) % 2])


## Palisada: pale 2 px szerokości, „ściana” 4 px pod zaostrzonym czubkiem.
static func draw_palisade(img: Image, origin: Vector2i, length: int) -> void:
	for i in range(0, length, 2):
		var x := origin.x + i
		img.set_pixel(x, origin.y, Palette.WOOD[3])
		for h in range(1, 5):
			img.set_pixel(x, origin.y + h, Palette.WOOD[2])
			img.set_pixel(x + 1, origin.y + h, Palette.WOOD[1])
		img.set_pixel(x, origin.y + 5, Palette.SHADOW)
		img.set_pixel(x + 1, origin.y + 5, Palette.SHADOW)


## Prosta chata z dachem strzechowym (zalążek draw_building).
static func draw_hut(img: Image, origin: Vector2i) -> void:
	var w := 12
	# ściana
	img.fill_rect(Rect2i(origin + Vector2i(1, 6), Vector2i(w - 2, 6)), Palette.WOOD[2])
	img.fill_rect(Rect2i(origin + Vector2i(5, 8), Vector2i(2, 4)), Palette.WOOD[0])
	# dach
	for row in 6:
		var inset := 5 - row
		for x in range(inset, w - inset):
			img.set_pixel(origin.x + x, origin.y + row, Palette.THATCH[2 if row < 2 else 1])
	# cień
	img.fill_rect(Rect2i(origin + Vector2i(1, 12), Vector2i(w - 2, 1)), Palette.SHADOW)
