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


## Dithering 2×2: kolor piksela w szachownicy bloków 2×2 z kolorów `a` i `b`.
## Wał, sucha fosa i podsypka palisady liczą go piksel po pikselu, bo mają nieprostokątny kształt.
static func dither(x: int, y: int, a: Color, b: Color) -> Color:
	return a if ((x >> 1) + (y >> 1)) % 2 == 0 else b


# --- Rzut z góry (światło z lewej góry) ----------------------------------------------------

## Dach dwuspadowy z góry: kalenica przez środek `r` (pozioma albo pionowa), połać od północy
## albo zachodu jasna, od południa albo wschodu ciemniejsza. Źdźbła strzechy biegną w dół połaci
## (smugi z hash2), a okap po ciemnej stronie jest najciemniejszy.
static func roof_gable(img: Image, r: Rect2i, horizontal: bool, ramp: Array, ridge: Color, tex_seed: int = 0) -> void:
	var across := r.size.y if horizontal else r.size.x
	var mid := across / 2
	for y in range(r.position.y, r.end.y):
		for x in range(r.position.x, r.end.x):
			var a := (y - r.position.y) if horizontal else (x - r.position.x)
			var along := x if horizontal else y
			var lit := a < mid
			var col: Color = ramp[2] if lit else ramp[1]
			# połać w cieniu ma gęstsze ciemne źdźbła, więc kalenica jest wyraźna
			if hash2(along, 0, tex_seed + (0 if lit else 1)) % (5 if lit else 2) == 0:
				col = ramp[1] if lit else ramp[0]
			if a == across - 1:
				col = ramp[0]
			if a == mid:
				col = ridge
			px(img, x, y, col)


## Dach jednospadowy z góry: kalenica wzdłuż boku `high` (kierunek do muru), połać opada od niej.
## Jasność zależy od strony, w którą połać patrzy (światło z lewej góry).
static func roof_mono(img: Image, r: Rect2i, high: Vector2i, ramp: Array, ridge: Color, tex_seed: int = 0) -> void:
	# połać patrzy w stronę przeciwną do kalenicy
	var lit := high == Vector2i.DOWN or high == Vector2i.RIGHT
	var horizontal := high.y != 0
	var across := r.size.y if horizontal else r.size.x
	for y in range(r.position.y, r.end.y):
		for x in range(r.position.x, r.end.x):
			var a := (y - r.position.y) if horizontal else (x - r.position.x)
			if high == Vector2i.DOWN or high == Vector2i.RIGHT:
				a = across - 1 - a  # a: odległość od kalenicy
			var along := x if horizontal else y
			var col: Color = ramp[2] if lit else ramp[1]
			if a >= across / 2:
				col = ramp[1] if lit else ramp[0]
			if hash2(along, 0, tex_seed + 5) % 4 == 0:
				col = ramp[0] if a >= across / 2 else ramp[1]
			if a == 0:
				col = ridge
			px(img, x, y, col)


## Dach namiotowy (wieża) z góry: cztery połacie zbiegające się w środku, północna i zachodnia
## jasne, południowa i wschodnia ciemne, krawędzie narożne najciemniejsze, szczyt w kolorze `peak`.
static func roof_hip(img: Image, r: Rect2i, ramp: Array, peak: Color) -> void:
	var w := r.size.x
	var h := r.size.y
	for y in range(h):
		for x in range(w):
			# odległość od środka w połówkach piksela, żeby parzyste boki miały symetryczne połacie
			var dx := 2 * x + 1 - w
			var dy := 2 * y + 1 - h
			var col: Color
			if absi(dx) == absi(dy):
				col = ramp[0]
			elif absi(dy) > absi(dx):
				col = ramp[2] if dy < 0 else ramp[1]
			else:
				col = ramp[2] if dx < 0 else ramp[1]
			if absi(dx) <= 1 and absi(dy) <= 1:
				col = peak
			px(img, r.position.x + x, r.position.y + y, col)


## Dach czterospadowy (stóg) nad prostokątem z góry: kalenica `ridge` wzdłuż dłuższego boku, krótsza
## o krótszy bok, i narożniki pod 45° (najciemniejsze) schodzące z jej końców do rogów. Na kwadracie
## wygląda jak dach namiotowy. Połacie od północy i zachodu jasne, od południa i wschodu ciemne;
## `light_right` odwraca strony wschód–zachód (rysunek, który potem będzie odbity w poziomie).
## Źdźbła strzechy (smugi z hash2) biegną w dół połaci, jak w roof_gable.
static func roof_hipped(img: Image, r: Rect2i, ramp: Array, ridge: Color, tex_seed: int = 0,
		light_right: bool = false) -> void:
	var w := r.size.x
	var h := r.size.y
	var horizontal := w >= h
	var mid := (h if horizontal else w) / 2
	for y in range(h):
		for x in range(w):
			# d_side: odległość od dłuższego boku, d_end: od krótszego (szczytu połaci końcowej)
			var d_side := mini(y, h - 1 - y) if horizontal else mini(x, w - 1 - x)
			var d_end := mini(x, w - 1 - x) if horizontal else mini(y, h - 1 - y)
			var a := y if horizontal else x
			var along := x if horizontal else y
			var col: Color
			var lit: bool
			if d_end == d_side:
				col = ramp[0]
			else:
				if d_end < d_side:
					# połać końcowa: zachodnia albo północna
					var first := (x < w / 2) if horizontal else (y < h / 2)
					lit = first != (light_right and horizontal)
				else:
					var first := a < mid
					lit = first != (light_right and not horizontal)
				col = ramp[2] if lit else ramp[1]
				if hash2(along if d_end > d_side else a, 0, tex_seed + (0 if lit else 1)) % (5 if lit else 3) == 0:
					col = ramp[1] if lit else ramp[0]
			if a == mid and d_end >= d_side:
				col = ridge
			px(img, r.position.x + x, r.position.y + y, col)


## Pomost z desek z góry: deski szerokości 2 px wzdłuż osi x (albo y), jasna i ciemna na zmianę,
## ze stykami desek z hash2.
static func deck(img: Image, r: Rect2i, horizontal: bool, ramp: Array, tex_seed: int = 0) -> void:
	for y in range(r.position.y, r.end.y):
		for x in range(r.position.x, r.end.x):
			var a := (y - r.position.y) if horizontal else (x - r.position.x)
			var along := x if horizontal else y
			var board := a >> 1
			var col: Color = ramp[3] if board % 2 == 0 else ramp[2]
			if hash2(along, board, tex_seed + 9) % 7 == 0:
				col = ramp[1]
			px(img, x, y, col)


## Stos bali z góry: bale wzdłuż osi x po 2 wiersze (jasny wierzch, ciemniejszy spód),
## na końcach jasne czoła ze słojami.
static func log_pile(img: Image, r: Rect2i) -> void:
	for y in range(r.position.y, r.end.y):
		var row := (y - r.position.y) % 2
		for x in range(r.position.x, r.end.x):
			var col: Color = Palette.WOOD[2] if row == 0 else Palette.WOOD[1]
			if x == r.position.x or x == r.end.x - 1:
				col = Palette.THATCH[1] if row == 0 else Palette.WOOD[0]
			px(img, x, y, col)


## Obwódka 1 px wewnątrz prostokąta (balustrada, krawędź pomostu).
static func frame(img: Image, r: Rect2i, col: Color) -> void:
	rect(img, Rect2i(r.position, Vector2i(r.size.x, 1)), col)
	rect(img, Rect2i(r.position.x, r.end.y - 1, r.size.x, 1), col)
	rect(img, Rect2i(r.position, Vector2i(1, r.size.y)), col)
	rect(img, Rect2i(r.end.x - 1, r.position.y, 1, r.size.y), col)


## Komin z góry: 2×2 z ciemnym wylotem w prawym dolnym rogu.
static func chimney(img: Image, at: Vector2i) -> void:
	rect(img, Rect2i(at, Vector2i(2, 2)), Palette.EARTH[1])
	px(img, at.x, at.y, Palette.EARTH[3])
	px(img, at.x + 1, at.y + 1, Palette.SHADOW)


## Proporzec z góry: drzewce (1 px) i płachta 3×2 z wcięciem, łopocąca na wschód.
static func pennant(img: Image, at: Vector2i, col: Color) -> void:
	px(img, at.x, at.y, Palette.WOOD[0])
	rect(img, Rect2i(at.x + 1, at.y, 3, 2), col)
	px(img, at.x + 3, at.y + 1, Color(col, 0.0))
