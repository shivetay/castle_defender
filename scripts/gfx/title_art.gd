class_name TitleArt
extends RefCounted
## Grafika ekranu tytułowego (#360), w całości z kodu i z palet (Palette.TITLE, STONE, GRASS):
## zachód słońca nad kamiennym zamkiem na skale. Od tyłu: niebo z ditheringiem Bayera, chmury,
## słońce, dwa pasma gór, sylwetki sosen pod słońce, skała z mchem, zamek z wieżami i dachówką,
## schody, duże sosny po bokach i krzaki. Na wierzchu logo „DUNHOLM” w skali 3× z obrysem.
## Obraz powstaje raz dla rozmiaru ekranu i jest deterministyczny (hash2, bez losowania).

const GAME_NAME := "Dunholm"
const SUBTITLE := "Obroń swój gród"
## Skala logo (cała liczba) i jego górna krawędź.
const LOGO_SCALE := 3
const LOGO_Y := 10
const SUBTITLE_Y := 40
## Scena jest rysowana dla wysokości 180 px; na wyższym ekranie przesuwa się w dół, a niebo rośnie.
const BASE_H := 180
const SEED := 360
## Macierz Bayera 4×4 do płynnych przejść nieba.
const BAYER: Array[int] = [0, 8, 2, 10, 12, 4, 14, 6, 3, 11, 1, 9, 15, 7, 13, 5]


static func make_image(size: Vector2i) -> Image:
	var img := Image.create(size.x, size.y, false, Image.FORMAT_RGBA8)
	var oy := maxi(size.y - BASE_H, 0)
	var cx := size.x >> 1
	_sky(img, oy + 112)
	_clouds(img, oy)
	_sun(img, Vector2i(cx, oy + 84), 27)
	_ridge(img, oy, 62, 86, 104, 1, Palette.TITLE[7], Palette.TITLE[8])
	_ridge(img, oy, 90, 102, 118, 2, Palette.TITLE[9], Palette.TITLE[10])
	_far_pines(img, oy + 128)
	_ground(img, oy + 136)
	_mid_pines(img, oy + 142, cx)
	_cliff(img, cx, oy + 122)
	_castle(img, cx, oy + 122)
	_stairs(img, cx, oy + 122)
	_near_pines(img)
	_bushes(img)
	_logo(img)
	var sub_w := PixelFont.text_width(SUBTITLE)
	var sub := Vector2i((size.x - sub_w) >> 1, SUBTITLE_Y)
	PixelFont.render(img, sub + Vector2i(1, 1), SUBTITLE, Palette.TITLE[11])
	PixelFont.render(img, sub, SUBTITLE, Palette.INK)
	return img


## Prostokąt logo na ekranie o szerokości `width`, razem z obrysem i cieniem.
static func logo_rect(width: int) -> Rect2i:
	var w := (PixelFont.text_width(GAME_NAME) + 1) * LOGO_SCALE + 2
	return Rect2i(((width - w) >> 1), LOGO_Y, w, (PixelFont.LINE + 1) * LOGO_SCALE + 2)


static func _bayer(x: int, y: int) -> int:
	return BAYER[(y & 3) * 4 + (x & 3)]


# --- Tło ------------------------------------------------------------------------------------

## Niebo od fioletu u góry do złota nad horyzontem; poniżej `horizon` też złoto (zasłonią je góry).
static func _sky(img: Image, horizon: int) -> void:
	var bands := Palette.TITLE_SKY
	for y in img.get_height():
		var t := clampf(float(y) / float(maxi(horizon, 1)), 0.0, 1.0) * float(bands.size() - 1)
		var i := mini(int(t), bands.size() - 2)
		var level := int((t - float(i)) * 16.0)
		for x in img.get_width():
			img.set_pixel(x, y, bands[i + 1] if level > _bayer(x, y) else bands[i])


## Kilka długich, płaskich chmur (schodkowe pasy) z ciemniejszym spodem.
static func _clouds(img: Image, oy: int) -> void:
	var w := img.get_width()
	for k in 6:
		var length := 28 + PixelCanvas.hash2(k, 1, SEED) % 40
		var x0 := PixelCanvas.hash2(k, 2, SEED) % maxi(w, 1) - 10
		var y0 := oy + 18 + PixelCanvas.hash2(k, 3, SEED) % 50
		PixelCanvas.rect(img, Rect2i(x0, y0, length, 2), Palette.TITLE[6])
		PixelCanvas.rect(img, Rect2i(x0 + 6, y0 - 2, length - 14, 2), Palette.TITLE[6])
		PixelCanvas.rect(img, Rect2i(x0 + 12, y0 - 3, maxi(length - 30, 4), 1), Palette.TITLE[6])
		PixelCanvas.rect(img, Rect2i(x0 + 3, y0 + 2, length - 4, 1), Palette.TITLE[2])


## Słońce z jaśniejszym środkiem i poziomymi przerwami u dołu, jak w pixelarcie zachodu.
static func _sun(img: Image, c: Vector2i, r: int) -> void:
	for y in range(-r, r + 1):
		if y > r / 3 and (y % 4) == 0:
			continue
		for x in range(-r, r + 1):
			var d := x * x + y * y
			if d <= r * r:
				PixelCanvas.px(img, c.x + x, c.y + y, Palette.TITLE[5] if d < (r - 5) * (r - 5) else Palette.TITLE[4])


## Pasmo gór: łamana przez szczyty (min..max) i doliny (valley). Zbocza opadające w prawo w cieniu,
## wznoszące się w świetle; przy grani jaśniejsza krawędź.
static func _ridge(img: Image, oy: int, top_min: int, top_max: int, valley: int, layer: int,
		shade: Color, light: Color) -> void:
	var w := img.get_width()
	var ridge := PackedInt32Array()
	ridge.resize(w + 1)
	var x := -24 - PixelCanvas.hash2(layer, 0, SEED) % 20
	var y := valley
	var k := 0
	while x <= w:
		var peak := k % 2 == 0
		var nx := x + 14 + PixelCanvas.hash2(k, layer, SEED) % 26
		var ny := (top_min + PixelCanvas.hash2(k, layer + 5, SEED) % maxi(top_max - top_min, 1)) if peak \
				else (valley - PixelCanvas.hash2(k, layer + 9, SEED) % 8)
		for xi in range(maxi(x, 0), mini(nx, w + 1)):
			ridge[xi] = oy + y + (ny - y) * (xi - x) / maxi(nx - x, 1)
		x = nx
		y = ny
		k += 1
	for xi in w:
		var rising := ridge[xi + 1] < ridge[xi] if xi + 1 <= w else false
		for yi in range(maxi(ridge[xi], 0), img.get_height()):
			var col := light if rising else shade
			if yi == ridge[xi] and not rising:
				col = light
			img.set_pixel(xi, yi, col)


## Rząd małych sosen pod słońce (ciemne sylwetki) na linii `base`.
static func _far_pines(img: Image, base: int) -> void:
	var w := img.get_width()
	var x := -4
	var i := 0
	while x < w + 4:
		var h := 8 + PixelCanvas.hash2(i, 7, SEED) % 10
		_pine(img, x, base + PixelCanvas.hash2(i, 8, SEED) % 3, h, Palette.TITLE[11], Palette.TITLE[11], Palette.TITLE[12])
		x += 4 + PixelCanvas.hash2(i, 9, SEED) % 5
		i += 1
	PixelCanvas.rect(img, Rect2i(0, base, w, img.get_height() - base), Palette.TITLE[11])


static func _ground(img: Image, top: int) -> void:
	for y in range(top, img.get_height()):
		for x in img.get_width():
			img.set_pixel(x, y, PixelCanvas.dither(x, y, Palette.TITLE[15], Palette.GRASS[0]))


## Średnie sosny po obu stronach skały (bez środka, gdzie stoi zamek).
static func _mid_pines(img: Image, base: int, cx: int) -> void:
	var w := img.get_width()
	var x := 0
	var i := 0
	while x < w:
		if absi(x - cx) > 64:
			var h := 16 + PixelCanvas.hash2(i, 11, SEED) % 12
			_pine(img, x, base + PixelCanvas.hash2(i, 12, SEED) % 4, h, Palette.TITLE[15], Palette.GRASS[0], Palette.GRASS[1])
		x += 7 + PixelCanvas.hash2(i, 13, SEED) % 6
		i += 1


## Sosna z pięter: każde piętro szersze od poprzedniego, lewa strona w cieniu, końce gałęzi jaśniejsze.
static func _pine(img: Image, cx: int, base: int, h: int, dark: Color, mid: Color, light: Color) -> void:
	var top := base - h
	PixelCanvas.rect(img, Rect2i(cx, base - 2, 1, 3), Palette.WOOD[0])
	for r in h - 2:
		var target := 1 + r * (h / 4) / maxi(h - 3, 1)
		var half := maxi(1, target - 2 + (r % 5))
		var y := top + r
		for x in range(cx - half, cx + half + 1):
			var col := dark if x < cx else mid
			if r % 5 == 4 and (x == cx - half or x == cx + half):
				col = light
			PixelCanvas.px(img, x, y, col)


# --- Skała i zamek ------------------------------------------------------------------------------

## Skała pod zamkiem rozszerza się w dół, z pionowymi pęknięciami, mchem na górze i zaciekami mchu.
static func _cliff(img: Image, cx: int, top: int) -> void:
	var h := img.get_height()
	for y in range(top, h):
		var d := y - top
		var half := 54 + d * 3 / 2 + (PixelCanvas.hash2(d >> 1, 1, SEED) % 4) - 2
		for x in range(cx - half, cx + half):
			var col: Color = Palette.TITLE[12]
			var seam := PixelCanvas.hash2(x / 3, (d + (x & 7)) / 7, SEED + 1) % 5
			if x % 3 == 0 and seam < 2:
				col = Palette.TITLE[11]  # pionowe żyły skały
			elif x % 3 == 1 and seam == 4 and x < cx:
				col = Palette.TITLE[10]
			if x - cx > half / 3 and (x + y) % 2 == 0:
				col = Palette.TITLE[11]  # prawa strona w cieniu
			if x - cx > half * 2 / 3:
				col = Palette.TITLE[11]
			if (x - cx + half) < 2 or (cx + half - x) < 2:
				col = Palette.TITLE[11]
			if d < 3 or (d < 3 + PixelCanvas.hash2(x >> 1, 4, SEED) % 9 and PixelCanvas.hash2(x >> 1, 5, SEED) % 3 == 0):
				col = Palette.GRASS[2] if d == 0 else Palette.GRASS[1]
			PixelCanvas.px(img, x, y, col)


## Zamek z kamienia: mur z blankami, dwie wieże boczne z flagami, dwie wieżyczki na murze i donżon
## z wysokim dachem z dachówki. Ściany jaśniejsze z lewej, okna świecą ciepło.
static func _castle(img: Image, cx: int, base: int) -> void:
	# donżon za murem
	_stone(img, Rect2i(cx - 15, base - 38, 30, 38))
	_cone_roof(img, cx, base - 38, 18, 22)
	_flag(img, Vector2i(cx, base - 38 - 22 - 9))
	_windows(img, Rect2i(cx - 15, base - 38, 30, 20), 3)
	# mur
	_stone(img, Rect2i(cx - 46, base - 18, 92, 18))
	_battlements(img, cx - 46, 92, base - 18)
	# wieżyczki na murze
	for sx: int in [-28, 28]:
		_stone(img, Rect2i(cx + sx - 5, base - 26, 10, 8))
		_cone_roof(img, cx + sx, base - 26, 7, 10)
	# wieże boczne
	for sx: int in [-50, 50]:
		var r := Rect2i(cx + sx - 7, base - 40, 14, 40)
		_stone(img, r)
		PixelCanvas.rect(img, Rect2i(r.position.x - 1, r.position.y, r.size.x + 2, 2), Palette.STONE[0])
		_battlements(img, r.position.x - 1, r.size.x + 2, r.position.y)
		_flag(img, Vector2i(cx + sx, r.position.y - 3 - 12))
		_windows(img, Rect2i(r.position.x, r.position.y + 4, r.size.x, 24), 1)
	# brama
	PixelCanvas.rect(img, Rect2i(cx - 6, base - 13, 12, 13), Palette.SHADOW)
	PixelCanvas.rect(img, Rect2i(cx - 4, base - 15, 8, 2), Palette.SHADOW)
	for x in range(cx - 5, cx + 5):
		PixelCanvas.rect(img, Rect2i(x, base - 12 + (1 if absi(x - cx) > 3 else 0), 1, 12),
				Palette.WOOD[1] if (x - cx) % 3 == 0 else Palette.WOOD[2])


## Ściana z kamienia: cegły w rzędach po 3 px z przesunięciem, lewa krawędź w świetle, prawa w cieniu.
static func _stone(img: Image, r: Rect2i) -> void:
	for y in range(r.position.y, r.end.y):
		for x in range(r.position.x, r.end.x):
			var row := (y - r.position.y) / 3
			var col: Color = Palette.STONE[1]
			if (y - r.position.y) % 3 == 2 or (x + row * 3) % 7 == 0:
				col = Palette.STONE[0]  # spoiny
			elif PixelCanvas.hash2(x >> 1, y / 3, SEED + 3) % 5 == 0:
				col = Palette.STONE[2]
			if x < r.position.x + 2:
				col = Palette.STONE[2]
			elif x >= r.end.x - 2:
				col = Palette.STONE[0]
			PixelCanvas.px(img, x, y, col)


static func _battlements(img: Image, x0: int, w: int, top: int) -> void:
	for x in range(x0, x0 + w):
		if ((x - x0) >> 1) % 2 == 0:
			PixelCanvas.rect(img, Rect2i(x, top - 3, 1, 3), Palette.STONE[2] if x == x0 else Palette.STONE[1])


## Stożkowy dach z dachówki nad ścianą szerokości 2×half; okap wystaje o 1 px.
static func _cone_roof(img: Image, cx: int, base: int, half: int, h: int) -> void:
	for i in h:
		var y := base - h + i
		var span := 1 + (half + 1) * i / maxi(h - 1, 1)
		for x in range(cx - span, cx + span):
			var col: Color = Palette.ROOF_TILE[1] if x < cx - span / 3 else Palette.ROOF_TILE[0]
			if (i % 3) == 2 and (x + i) % 2 == 0:
				col = Palette.TITLE[11] if col == Palette.ROOF_TILE[0] else Palette.ROOF_TILE[0]
			PixelCanvas.px(img, x, y, col)
	PixelCanvas.rect(img, Rect2i(cx - half - 2, base - 1, 2 * half + 4, 1), Palette.TITLE[11])


static func _flag(img: Image, at: Vector2i) -> void:
	PixelCanvas.rect(img, Rect2i(at.x, at.y, 1, 12), Palette.WOOD[0])
	PixelCanvas.rect(img, Rect2i(at.x + 1, at.y, 7, 2), Palette.ACCENT)
	PixelCanvas.rect(img, Rect2i(at.x + 1, at.y + 2, 5, 2), Palette.ACCENT)
	PixelCanvas.rect(img, Rect2i(at.x + 6, at.y + 2, 2, 1), Palette.ACCENT)


## Okna 2×3 rozłożone równo w prostokącie, z ciepłym światłem i ciemnym nadprożem.
static func _windows(img: Image, r: Rect2i, count: int) -> void:
	for i in count:
		var x := r.position.x + (i + 1) * r.size.x / (count + 1) - 1
		for j in 2:
			var y := r.position.y + 3 + j * 11
			if y + 4 > r.end.y:
				continue
			PixelCanvas.rect(img, Rect2i(x, y, 2, 4), Palette.SHADOW)
			PixelCanvas.rect(img, Rect2i(x, y + 1, 2, 3), Palette.TITLE[4])


## Schody od bramy w dół skały, rozszerzające się ku dołowi.
static func _stairs(img: Image, cx: int, top: int) -> void:
	for y in range(top, img.get_height()):
		var half := 5 + (y - top) / 6
		var col: Color = Palette.STONE[0] if (y - top) % 3 == 0 else Palette.STONE[1]
		PixelCanvas.rect(img, Rect2i(cx - half, y, 2 * half, 1), col)
		PixelCanvas.px(img, cx - half, y, Palette.TITLE[11])
		PixelCanvas.px(img, cx + half - 1, y, Palette.TITLE[11])


# --- Pierwszy plan -------------------------------------------------------------------------------

## Duże sosny przy lewej i prawej krawędzi.
static func _near_pines(img: Image) -> void:
	var w := img.get_width()
	var h := img.get_height()
	var spots: Array[Vector2i] = [Vector2i(10, 46), Vector2i(30, 58), Vector2i(52, 40), Vector2i(72, 30)]
	for i in spots.size():
		var s := spots[i]
		var jitter := PixelCanvas.hash2(i, 21, SEED) % 6
		_pine(img, s.x + jitter, h - 4, s.y, Palette.TITLE[15], Palette.GRASS[0], Palette.GRASS[2])
		_pine(img, w - s.x - jitter, h - 4, s.y - jitter, Palette.TITLE[15], Palette.GRASS[0], Palette.GRASS[2])


## Krzaki na samym dole ekranu.
static func _bushes(img: Image) -> void:
	var h := img.get_height()
	for x in img.get_width():
		var bump := 3 + (PixelCanvas.hash2(x >> 3, 31, SEED) % 4) - absi((x & 7) - 4) / 2
		for y in range(h - maxi(bump, 1), h):
			img.set_pixel(x, y, Palette.GRASS[1] if y == h - bump else Palette.TITLE[15])


## Logo: napis w skali LOGO_SCALE, jasny z ciepłym dołem, z obrysem 1 px i cieniem.
static func _logo(img: Image) -> void:
	var text_w := PixelFont.text_width(GAME_NAME)
	var small := Image.create(text_w + 1, PixelFont.LINE + 1, false, Image.FORMAT_RGBA8)
	PixelFont.render(small, Vector2i(1, 1), GAME_NAME, Palette.TITLE[11])
	PixelFont.render(small, Vector2i.ZERO, GAME_NAME, Palette.INK)
	for y in range(PixelFont.CAP_TOP + 3, PixelFont.LINE):
		for x in text_w:
			if small.get_pixel(x, y) == Palette.INK:
				small.set_pixel(x, y, Palette.TITLE[4])
	var r := logo_rect(img.get_width())
	var o := r.position + Vector2i(1, 1)
	var s := LOGO_SCALE
	for pass_i in 2:
		for y in small.get_height():
			for x in small.get_width():
				var col := small.get_pixel(x, y)
				if col.a == 0.0:
					continue
				var cell := Rect2i(o.x + x * s, o.y + y * s, s, s)
				if pass_i == 0:
					PixelCanvas.rect(img, cell.grow(1), Palette.SHADOW)
				else:
					PixelCanvas.rect(img, cell, col)
