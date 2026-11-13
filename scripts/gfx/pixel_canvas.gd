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


## Piksel z kontrolą granic: rysowanie poza obrazem jest pomijane, a nie zgłasza błędu.
static func px(img: Image, x: int, y: int, col: Color) -> void:
	if x >= 0 and y >= 0 and x < img.get_width() and y < img.get_height():
		img.set_pixel(x, y, col)


## Prostokąt przycięty do obrazu.
static func rect(img: Image, r: Rect2i, col: Color) -> void:
	var clipped := r.intersection(Rect2i(Vector2i.ZERO, img.get_size()))
	if clipped.has_area():
		img.fill_rect(clipped, col)


## Dithering 2×2: szachownica bloków 2×2 z kolorów `a` i `b` (wały, fosy, rumowisko).
static func dither_fill(img: Image, r: Rect2i, a: Color, b: Color) -> void:
	for y in range(r.position.y, r.end.y):
		for x in range(r.position.x, r.end.x):
			px(img, x, y, a if ((x >> 1) + (y >> 1)) % 2 == 0 else b)


## Ściana z poziomych bali: co trzeci wiersz ciemna fuga, faktura słojów z hash2.
static func draw_log_wall(img: Image, r: Rect2i, ramp: Array, tex_seed: int) -> void:
	for y in range(r.position.y, r.end.y):
		var row := y - r.position.y
		for x in range(r.position.x, r.end.x):
			var col: Color = ramp[0] if row % 3 == 2 else ramp[1 + hash2(x, y, tex_seed) % 2]
			px(img, x, y, col)


## Ściana z pionowych desek albo pali: deski szerokości 2 px, jasna i ciemna na zmianę.
static func draw_plank_wall(img: Image, r: Rect2i, ramp: Array) -> void:
	for y in range(r.position.y, r.end.y):
		for x in range(r.position.x, r.end.x):
			var col: Color = ramp[2] if ((x - r.position.x) >> 1) % 2 == 0 else ramp[1]
			px(img, x, y, col)


## Belki szkieletu: słupy po bokach i belka u góry (oczep) w kolorze `col`.
static func draw_beams(img: Image, r: Rect2i, col: Color) -> void:
	rect(img, Rect2i(r.position, Vector2i(r.size.x, 1)), col)
	rect(img, Rect2i(r.position, Vector2i(1, r.size.y)), col)
	rect(img, Rect2i(r.end.x - 1, r.position.y, 1, r.size.y), col)


## Dach dwuspadowy od frontu: `rows` wierszy, każdy o 1 px szerszy z obu stron, od szczytu
## (`top_width` px) w dół. Jaśniejszy szczyt, ciemny okap i smugi strzechy z hash2.
static func draw_roof(img: Image, top_center_x: int, top_y: int, top_width: int, rows: int, ramp: Array) -> void:
	for row in rows:
		var half := (top_width >> 1) + row
		for x in range(top_center_x - half, top_center_x + half):
			var col: Color = ramp[2] if row < 2 else ramp[1]
			if row == rows - 1:
				col = ramp[0]
			elif hash2(x, row, 61) % 5 == 0:
				col = ramp[0]
			px(img, x, top_y + row, col)


## Okno 2×2 (ciemny otwór) z jasnym parapetem pod spodem.
static func draw_window(img: Image, pos: Vector2i) -> void:
	rect(img, Rect2i(pos, Vector2i(2, 2)), Palette.SHADOW)
	rect(img, Rect2i(pos + Vector2i(-1, 2), Vector2i(4, 1)), Palette.WOOD[3])


## Drzwi z desek z ciemną ościeżnicą.
static func draw_door(img: Image, r: Rect2i) -> void:
	rect(img, r, Palette.WOOD[0])
	for y in range(r.position.y + 1, r.end.y):
		for x in range(r.position.x + 1, r.end.x - 1):
			px(img, x, y, Palette.WOOD[1] if (x - r.position.x) % 2 == 1 else Palette.WOOD[2])


## Flaga: maszt wysokości `height` od `base` w górę i proporzec 3×2 z wcięciem.
static func draw_flag(img: Image, base: Vector2i, height: int, col: Color) -> void:
	for i in height:
		px(img, base.x, base.y - i, Palette.WOOD[0])
	var top := base.y - height + 1
	rect(img, Rect2i(base.x + 1, top, 3, 2), col)
	px(img, base.x + 3, top + 1, Color(col, 0.0))
