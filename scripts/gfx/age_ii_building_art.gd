class_name AgeIiBuildingArt
extends RefCounted
## Rysunki budynków epoki II spoza MVP (#102, ADR 0011) w rzucie z góry, w stylu BuildingArt: światło
## z lewej góry, kolory wyłącznie z palet (gont i kamień z Palette.AGE_II), faktura z PixelCanvas.hash2.
## Budynek epoki II ma poziomy 1–5 tej epoki (narastająco 6–10), więc rysunek dostaje poziom w epoce.
## Stany zniszczeń dokłada BuildingArt._apply_state.
@warning_ignore_start("integer_division")


## Młyn wodny (2×2, #388): izba pod gontem i koło łopatkowe przy prawym boku, od strony rzeki.
## Poziomy: 1 drewniana izba z małym kołem, 2 dach z gontu na całej izbie, 3 kamienna podmurówka,
## 4 większe koło i worki mąki przed wejściem, 5 proporzec epoki II na kalenicy.
static func draw_mill(img: Image, level: int) -> void:
	var size := img.get_size()
	var body := Rect2i(1, 3, size.x - 7, size.y - 5)
	if level >= 3:
		# podmurówka z ciosów: jaśniejsze od lewej góry, spoiny z faktury
		var base := body.grow(1)
		for y in range(base.position.y, base.end.y):
			for x in range(base.position.x, base.end.x):
				var col := Palette.STONE[1] if x + y < base.position.x + base.end.y else Palette.STONE[0]
				if PixelCanvas.hash2(x, y, 271) % 5 == 0:
					col = Palette.STONE[2]
				PixelCanvas.px(img, x, y, col)
	PixelCanvas.rect(img, body, Palette.WOOD[1])
	PixelCanvas.frame(img, body, Palette.WOOD[0])
	var roof := body if level >= 2 else Rect2i(body.position + Vector2i(1, 1), body.size - Vector2i(2, 3))
	PixelCanvas.roof_gable(img, roof, true, Palette.SHINGLE, Palette.WOOD[0], 277)
	_wheel(img, Vector2i(size.x - 4, size.y / 2), 3 if level >= 4 else 2)
	if level >= 4:
		# worki mąki przy wejściu
		for o: Vector2i in [Vector2i(2, size.y - 2), Vector2i(4, size.y - 2)]:
			PixelCanvas.rect(img, Rect2i(o, Vector2i(2, 1)), Palette.THATCH[2])
			PixelCanvas.px(img, o.x, o.y, Palette.THATCH[1])
	if level == 5:
		PixelCanvas.pennant(img, Vector2i(body.position.x + 1, body.position.y), Palette.AGE_II_ACCENT)


## Koło łopatkowe o promieniu `r` wokół `at`: obręcz z drewna, piasta i szprychy w krzyż.
static func _wheel(img: Image, at: Vector2i, r: int) -> void:
	for y in range(-r, r + 1):
		for x in range(-r, r + 1):
			var d := x * x + y * y
			if d > r * r + r:
				continue
			var col := Palette.WOOD[2] if d >= (r - 1) * (r - 1) + r - 1 else Palette.WATER[1]
			if x == 0 or y == 0:
				col = Palette.WOOD[0]
			PixelCanvas.px(img, at.x + x, at.y + y, col)
	PixelCanvas.px(img, at.x, at.y, Palette.WOOD[3])
