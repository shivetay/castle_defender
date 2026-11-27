class_name TitleArt
extends RefCounted
## Grafika ekranu tytułowego (#360), w całości z kodu i z palety epoki I: nocne niebo z gwiazdami
## i księżycem, wzgórza, gród na kopcu z palisadą, wieżami i sztandarem, oraz logo „DUNHOLM”
## w skali 3× (całkowitej, piksele zostają ostre). Obraz powstaje raz dla rozmiaru ekranu
## i jest deterministyczny: ten sam rozmiar daje zawsze te same piksele.

const GAME_NAME := "Dunholm"
const SUBTITLE := "Obroń swój gród"
## Skala logo (cała liczba) i jego górna krawędź.
const LOGO_SCALE := 3
const LOGO_Y := 12
const SUBTITLE_Y := 42
## Linia ziemi pod grodem liczona od dołu ekranu.
const GROUND_FROM_BOTTOM := 40
const STAR_SEED := 360


static func make_image(size: Vector2i) -> Image:
	var img := Image.create(size.x, size.y, false, Image.FORMAT_RGBA8)
	var ground := size.y - GROUND_FROM_BOTTOM
	_sky(img, ground)
	_moon(img, Vector2i(size.x - 44, 26))
	_hills(img, ground)
	_castle(img, size.x >> 1, ground)
	_ground(img, ground)
	_logo(img)
	var sub_w := PixelFont.text_width(SUBTITLE)
	PixelFont.render(img, Vector2i((size.x - sub_w) >> 1, SUBTITLE_Y), SUBTITLE, Palette.THATCH[1])
	return img


## Prostokąt logo na ekranie o szerokości `width` (do testów i układu).
static func logo_rect(width: int) -> Rect2i:
	var w := (PixelFont.text_width(GAME_NAME) + 1) * LOGO_SCALE
	return Rect2i((width - w) >> 1, LOGO_Y, w, (PixelFont.LINE + 1) * LOGO_SCALE)


# --- Elementy -------------------------------------------------------------------------------

## Niebo: od cienia u góry przez ciemną wodę do jaśniejszej przy horyzoncie, przejścia ditheringiem.
static func _sky(img: Image, ground: int) -> void:
	var bands: Array[Color] = [Palette.SHADOW, Palette.WATER[0], Palette.WATER[1]]
	var w := img.get_width()
	for y in ground:
		var t := float(y) / float(maxi(ground, 1)) * float(bands.size() - 1)
		var i := mini(int(t), bands.size() - 2)
		var mix := t - float(i)
		for x in w:
			var col: Color = bands[i]
			if mix > 0.66 or (mix > 0.33 and ((x >> 1) + (y >> 1)) % 2 == 0):
				col = bands[i + 1]
			img.set_pixel(x, y, col)
			if y < ground - 30:
				var h := PixelCanvas.hash2(x, y, STAR_SEED) % 260
				if h == 0:
					img.set_pixel(x, y, Palette.INK)
				elif h == 1:
					img.set_pixel(x, y, Palette.WATER[2])


static func _moon(img: Image, c: Vector2i) -> void:
	var r := 7
	for y in range(-r, r + 1):
		for x in range(-r, r + 1):
			if x * x + y * y <= r * r:
				var col: Color = Palette.THATCH[2]
				if (x + 2) * (x + 2) + (y + 1) * (y + 1) <= 4 or (x - 3) * (x - 3) + (y - 3) * (y - 3) <= 2:
					col = Palette.THATCH[1]  # kratery
				PixelCanvas.px(img, c.x + x, c.y + y, col)


## Dwa pasma wzgórz: dalsze ciemne, bliższe z trawą w dithering z cieniem (noc).
static func _hills(img: Image, ground: int) -> void:
	var w := img.get_width()
	for x in w:
		var far := ground - 26 + int(6.0 * sin(float(x) * 0.031)) + int(3.0 * sin(float(x) * 0.087 + 1.0))
		var near := ground - 12 + int(5.0 * sin(float(x) * 0.045 + 2.0))
		for y in range(maxi(far, 0), ground):
			var col := PixelCanvas.dither(x, y, Palette.WATER[0], Palette.SHADOW)
			if y >= near:
				col = PixelCanvas.dither(x, y, Palette.GRASS[0], Palette.SHADOW)
			img.set_pixel(x, y, col)


## Gród na kopcu: kopiec z ziemi, palisada z zaostrzonymi palami, dwie wieże, brama i donżon
## ze sztandarem. Światło księżyca z prawej, okna świecą.
static func _castle(img: Image, cx: int, ground: int) -> void:
	# kopiec
	for y in range(ground - 16, ground):
		var half := 70 - (ground - y) * 2
		for x in range(cx - half, cx + half):
			PixelCanvas.px(img, x, y, PixelCanvas.dither(x, y, Palette.EARTH[1], Palette.GRASS[0]))
	var wall_top := ground - 34
	var wall_bottom := ground - 14
	# donżon za palisadą
	_tower(img, Rect2i(cx - 13, wall_top - 26, 26, wall_bottom - wall_top + 26), 10)
	_banner(img, Vector2i(cx, wall_top - 26 - 12))
	# palisada
	for x in range(cx - 46, cx + 46):
		var top := wall_top + (1 if x % 3 == 1 else 0) + (2 if x % 3 == 2 else 0)
		for y in range(top, wall_bottom):
			var col: Color = Palette.WOOD[1]
			if x % 3 == 2:
				col = Palette.WOOD[0]
			elif x % 3 == 0 and x > cx:
				col = Palette.WOOD[2]
			if y == wall_top + 7 or y == wall_bottom - 4:
				col = Palette.WOOD[0]  # poprzeczki
			PixelCanvas.px(img, x, y, col)
	# brama z ciepłym światłem w środku
	PixelCanvas.rect(img, Rect2i(cx - 5, wall_bottom - 11, 10, 11), Palette.SHADOW)
	PixelCanvas.rect(img, Rect2i(cx - 4, wall_bottom - 10, 8, 2), Palette.WOOD[0])
	PixelCanvas.rect(img, Rect2i(cx - 3, wall_bottom - 6, 6, 6), Palette.THATCH[0])
	PixelCanvas.rect(img, Rect2i(cx - 2, wall_bottom - 4, 4, 4), Palette.THATCH[1])
	# wieże narożne
	_tower(img, Rect2i(cx - 56, wall_top - 12, 14, wall_bottom - wall_top + 12), 7)
	_tower(img, Rect2i(cx + 42, wall_top - 12, 14, wall_bottom - wall_top + 12), 7)


## Wieża z belek ze spiczastym dachem ze strzechy i świecącym oknem.
static func _tower(img: Image, r: Rect2i, roof_h: int) -> void:
	for y in range(r.position.y, r.end.y):
		for x in range(r.position.x, r.end.x):
			var col: Color = Palette.WOOD[1]
			if x == r.end.x - 1 or x == r.end.x - 2:
				col = Palette.WOOD[2]  # księżyc z prawej
			elif x == r.position.x:
				col = Palette.WOOD[0]
			elif (y - r.position.y) % 5 == 4:
				col = Palette.WOOD[0]
			PixelCanvas.px(img, x, y, col)
	# okno
	var wx := r.position.x + (r.size.x >> 1) - 1
	PixelCanvas.rect(img, Rect2i(wx, r.position.y + 4, 3, 4), Palette.SHADOW)
	PixelCanvas.rect(img, Rect2i(wx, r.position.y + 5, 2, 3), Palette.THATCH[2])
	# dach: trójkąt nad wieżą, z okapem po 2 px
	var cx := r.position.x + (r.size.x >> 1)
	var half := (r.size.x >> 1) + 2
	for i in roof_h:
		var y := r.position.y - roof_h + i
		var span := maxi(1, (half * (i + 1)) / roof_h)
		for x in range(cx - span, cx + span):
			var col: Color = Palette.THATCH[0] if x < cx else Palette.THATCH[1]
			if i == roof_h - 1:
				col = Palette.WOOD[0]  # okap
			PixelCanvas.px(img, x, y, col)


static func _banner(img: Image, at: Vector2i) -> void:
	PixelCanvas.rect(img, Rect2i(at.x, at.y, 1, 12), Palette.WOOD[3])
	for i in 6:
		PixelCanvas.rect(img, Rect2i(at.x + 1, at.y + 1 + (i >> 1), 7 - i, 1), Palette.ACCENT)
	PixelCanvas.rect(img, Rect2i(at.x + 1, at.y + 4, 4, 1), Palette.ACCENT)


## Ziemia na pierwszym planie: trawa w cieniu z jaśniejszymi kępkami.
static func _ground(img: Image, ground: int) -> void:
	var w := img.get_width()
	for y in range(ground, img.get_height()):
		for x in w:
			var col := PixelCanvas.dither(x, y, Palette.GRASS[0], Palette.SHADOW)
			if y > ground + 2 and PixelCanvas.hash2(x, y, STAR_SEED + 1) % 23 == 0:
				col = Palette.GRASS[1]
			img.set_pixel(x, y, col)
	for x in w:
		if PixelCanvas.hash2(x, 0, STAR_SEED + 2) % 3 != 0:
			img.set_pixel(x, ground, Palette.GRASS[1])


## Logo: napis w skali LOGO_SCALE, jasny z ciepłym dołem, z cieniem 1 piksela logicznego.
static func _logo(img: Image) -> void:
	var text_w := PixelFont.text_width(GAME_NAME)
	var small := Image.create(text_w + 1, PixelFont.LINE + 1, false, Image.FORMAT_RGBA8)
	PixelFont.render(small, Vector2i(1, 1), GAME_NAME, Palette.SHADOW)
	PixelFont.render(small, Vector2i.ZERO, GAME_NAME, Palette.INK)
	# dół liter w kolorze strzechy (glif zajmuje wiersze CAP_TOP..CAP_TOP+4)
	for y in range(PixelFont.CAP_TOP + 3, PixelFont.LINE):
		for x in text_w:
			if small.get_pixel(x, y) == Palette.INK:
				small.set_pixel(x, y, Palette.THATCH[2])
	var r := logo_rect(img.get_width())
	for y in small.get_height():
		for x in small.get_width():
			var col := small.get_pixel(x, y)
			if col.a == 0.0:
				continue
			PixelCanvas.rect(img, Rect2i(r.position.x + x * LOGO_SCALE, r.position.y + y * LOGO_SCALE,
					LOGO_SCALE, LOGO_SCALE), col)
