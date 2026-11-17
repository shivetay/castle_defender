class_name TerrainRenderer
extends RefCounted
## Rysuje TerrainMap do jednego obrazu (kratka 8×8 px). Kafelki bazowe powstają raz, a potem
## kopiuje się je przez blit_rect. Piksel po pikselu liczone są tylko kratki na styku wysokości
## (płynne, poszarpane przejście zamiast schodków), krawędzie ścieżek i wody oraz drobne ozdoby,
## dzięki czemu mapa 512×512 px generuje się bez widocznego przycięcia.
@warning_ignore_start("integer_division")

const VARIANTS := 8
## Co która kratka trawy (z 100) dostaje ozdobę: kępkę, kwiatki, kamień albo krzak.
const DECOR_TUFT := 10
const DECOR_FLOWERS := 15
const DECOR_STONE := 18
const DECOR_BUSH := 21

enum Decor { NONE, TUFT, FLOWERS, STONE, BUSH }


static func render(map: TerrainMap) -> Image:
	var cell := TerrainMap.CELL
	var img := Image.create(map.size * cell, map.size * cell, false, Image.FORMAT_RGBA8)
	var grass: Array[Image] = []
	var grass_px: Array[PackedColorArray] = []
	for shade in Palette.GRASS.size():
		for v in VARIANTS:
			var tile := _grass_tile(shade, v)
			grass.append(tile)
			var px := PackedColorArray()
			for y in cell:
				for x in cell:
					px.append(tile.get_pixel(x, y))
			grass_px.append(px)
	var paths: Array[Image] = []
	var waters: Array[Image] = []
	for v in VARIANTS:
		paths.append(_path_tile(v))
		waters.append(_noise_tile(Palette.WATER[1], Palette.WATER[2], 40 + v, 9))
	var src := Rect2i(0, 0, cell, cell)
	var jitter := _slope_jitter(map)
	for y in map.size:
		for x in map.size:
			var c := Vector2i(x, y)
			var v := _variant(map, c)
			var at := c * cell
			match map.get_tile(c):
				TerrainMap.Tile.GRASS:
					if _on_slope(map, c):
						_draw_slope(img, map, c, grass_px, jitter)
					else:
						img.blit_rect(grass[map.get_height(c) * VARIANTS + v], src, at)
				TerrainMap.Tile.PATH:
					img.blit_rect(paths[v], src, at)
				TerrainMap.Tile.WATER:
					img.blit_rect(waters[v], src, at)
				TerrainMap.Tile.BRIDGE:
					_draw_bridge(img, map, c)
	for y in map.size:
		for x in map.size:
			_draw_edges(img, map, Vector2i(x, y))
	for y in map.size:
		for x in map.size:
			_draw_decor(img, map, Vector2i(x, y))
	return img


static func _variant(map: TerrainMap, c: Vector2i) -> int:
	return PixelCanvas.hash2(c.x, c.y, map.world_seed + 11) % VARIANTS


## Ozdoba kratki trawy (stała dla seeda). Tylko na kratkach otoczonych trawą, żeby nie wchodziła
## na brzegi ścieżek i wody.
static func decor_at(map: TerrainMap, c: Vector2i) -> int:
	var roll := PixelCanvas.hash2(c.x, c.y, map.world_seed + 77) % 100
	if roll >= DECOR_BUSH or not _grass_all_around(map, c):
		return Decor.NONE
	if roll < DECOR_TUFT:
		return Decor.TUFT
	if roll < DECOR_FLOWERS:
		return Decor.FLOWERS
	if roll < DECOR_STONE:
		return Decor.STONE
	return Decor.BUSH


## Kratka trawy, której 4 sąsiedzi (w granicach mapy) też są trawą.
static func _grass_all_around(map: TerrainMap, c: Vector2i) -> bool:
	var n := map.size
	var i := c.y * n + c.x
	var g := TerrainMap.Tile.GRASS
	if map.tiles[i] != g:
		return false
	return (c.x == 0 or map.tiles[i - 1] == g) and (c.x == n - 1 or map.tiles[i + 1] == g) \
			and (c.y == 0 or map.tiles[i - n] == g) and (c.y == n - 1 or map.tiles[i + n] == g)


## Trawa: odcień bazowy z ziarnem jaśniejszych i ciemniejszych pikseli oraz kilkoma źdźbłami
## (jasny piksel nad ciemnym), które łamią równy szum.
static func _grass_tile(shade: int, variant: int) -> Image:
	var cell := TerrainMap.CELL
	var tile := Image.create(cell, cell, false, Image.FORMAT_RGBA8)
	var top := Palette.GRASS.size() - 1
	var s0 := 20 + shade * VARIANTS + variant
	for y in cell:
		for x in cell:
			var grain := PixelCanvas.hash2(x, y, s0) % 9
			var s := shade
			if grain == 0:
				s = mini(shade + 1, top)
			elif grain == 8:
				s = maxi(shade - 1, 0)
			tile.set_pixel(x, y, Palette.GRASS[s])
	for i in 2:
		var h := PixelCanvas.hash2(i, variant, 90 + shade)
		var bx := h % cell
		var by := 1 + (h / cell) % (cell - 1)
		tile.set_pixel(bx, by - 1, Palette.GRASS[mini(shade + 1, top)])
		tile.set_pixel(bx, by, Palette.GRASS[maxi(shade - 1, 0)])
	return tile


## Ścieżka: ubita ziemia z jaśniejszymi grudkami i pojedynczymi ciemnymi kamyczkami.
static func _path_tile(variant: int) -> Image:
	var cell := TerrainMap.CELL
	var tile := Image.create(cell, cell, false, Image.FORMAT_RGBA8)
	for y in cell:
		for x in cell:
			var h := PixelCanvas.hash2(x, y, 30 + variant) % 11
			var col: Color = Palette.EARTH[2]
			if h < 3:
				col = Palette.EARTH[3]
			elif h == 10:
				col = Palette.EARTH[1]
			tile.set_pixel(x, y, col)
	return tile


## Kafelek dwukolorowy: `accent` pojawia się średnio w co `rarity`-tym pikselu.
static func _noise_tile(base: Color, accent: Color, tile_seed: int, rarity: int) -> Image:
	var cell := TerrainMap.CELL
	var tile := Image.create(cell, cell, false, Image.FORMAT_RGBA8)
	for y in cell:
		for x in cell:
			tile.set_pixel(x, y, accent if PixelCanvas.hash2(x, y, tile_seed) % rarity == 0 else base)
	return tile


## Kratka trawy, której któryś z 8 sąsiadów ma inną wysokość.
static func _on_slope(map: TerrainMap, c: Vector2i) -> bool:
	var n := map.size
	var h := map.heights[c.y * n + c.x]
	for y in range(maxi(c.y - 1, 0), mini(c.y + 2, n)):
		for x in range(maxi(c.x - 1, 0), mini(c.x + 2, n)):
			if map.heights[y * n + x] != h:
				return true
	return false


## Zbocze: wysokość w pikselu to interpolacja dwuliniowa wysokości środków kratek plus szum
## (drobny i w blokach 2×2), więc granica odcieni jest miękka i poszarpana, a nie schodkowa.
## Kolor bierze się z kafelka trawy wybranego odcienia, więc ziarno pasuje do sąsiednich kratek.
static func _draw_slope(img: Image, map: TerrainMap, c: Vector2i, grass: Array[PackedColorArray],
		jitter: PackedInt32Array) -> void:
	var cell := TerrainMap.CELL
	var top := Palette.GRASS.size() - 1
	var v := _variant(map, c)
	# wysokości 3×3 kratek wokół: piksel interpoluje między środkami czterech z nich
	var hs := PackedInt32Array()
	for dy in range(-1, 2):
		for dx in range(-1, 2):
			hs.append(_height(map, c.x + dx, c.y + dy))
	for y in cell:
		var wy := c.y * cell + y
		# współrzędne w 1/16 kratki względem środków kratek
		var w := y * 2 + 1 - cell
		var iy := 0 if w < 0 else 1
		var fy := w + 16 if w < 0 else w
		for x in cell:
			var wx := c.x * cell + x
			var u := x * 2 + 1 - cell
			var ix := 0 if u < 0 else 1
			var fx := u + 16 if u < 0 else u
			var i := iy * 3 + ix
			var h := (hs[i] * (16 - fx) + hs[i + 1] * fx) * (16 - fy) + (hs[i + 3] * (16 - fx) + hs[i + 4] * fx) * fy
			var level := clampi((h + 128 + jitter[(wy & 31) * 32 + (wx & 31)]) >> 8, 0, top)
			img.set_pixel(wx, wy, grass[level * VARIANTS + v][y * cell + x])


## Szum progu na zboczach: 32×32 wartości, drobny piksel plus bloki 2×2 (z seeda mapy).
static func _slope_jitter(map: TerrainMap) -> PackedInt32Array:
	var out := PackedInt32Array()
	var s := map.world_seed
	for y in 32:
		for x in 32:
			out.append(PixelCanvas.hash2(x >> 1, y >> 1, s + 5) % 96 + PixelCanvas.hash2(x, y, s + 6) % 64 - 80)
	return out


static func _height(map: TerrainMap, x: int, y: int) -> int:
	return map.get_height(Vector2i(clampi(x, 0, map.size - 1), clampi(y, 0, map.size - 1)))


## Most: deski w poprzek drogi i ciemniejsze poręcze wzdłuż niej.
static func _draw_bridge(img: Image, map: TerrainMap, c: Vector2i) -> void:
	var cell := TerrainMap.CELL
	var along_x := _is_road(map, c + Vector2i.LEFT) or _is_road(map, c + Vector2i.RIGHT)
	for y in cell:
		for x in cell:
			var across := y if along_x else x
			var plank := x if along_x else y
			var col: Color = Palette.WOOD[2]
			if across == 0 or across == cell - 1:
				col = Palette.WOOD[0]
			elif plank % 3 == 0:
				col = Palette.WOOD[1]
			img.set_pixel(c.x * cell + x, c.y * cell + y, col)


## Krawędzie: brzeg przy wodzie z trzciną po stronie trawy i poszarpany skraj ścieżki,
## z zaokrąglonymi narożnikami.
static func _draw_edges(img: Image, map: TerrainMap, c: Vector2i) -> void:
	if _grass_all_around(map, c):
		return
	var tile := map.get_tile(c)
	var cell := TerrainMap.CELL
	var o := c * cell
	var s := map.world_seed
	for dir: Vector2i in [Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT]:
		var n := c + dir
		if not map.in_bounds(n):
			continue
		var other := map.get_tile(n)
		if tile == TerrainMap.Tile.WATER and other != TerrainMap.Tile.WATER and other != TerrainMap.Tile.BRIDGE:
			for i in cell:
				img.set_pixelv(o + _edge_pixel(dir, i, 0), Palette.EARTH[1])
				img.set_pixelv(o + _edge_pixel(dir, i, 1), Palette.WATER[0])
				var p := o + _edge_pixel(dir, i, 2)
				if PixelCanvas.hash2(p.x, p.y, s + 8) % 3 == 0:
					img.set_pixelv(p, Palette.WATER[0])
		elif tile == TerrainMap.Tile.GRASS and other == TerrainMap.Tile.WATER:
			_draw_reeds(img, map, c, dir)
		elif tile == TerrainMap.Tile.PATH and other == TerrainMap.Tile.GRASS:
			for i in cell:
				for depth in 2:
					var p := o + _edge_pixel(dir, i, depth)
					var h := PixelCanvas.hash2(p.x, p.y, s + 9) % 4
					if (depth == 0 and h != 0) or (depth == 1 and h == 0):
						img.set_pixelv(p, _grass_under(map, n, p))
	if tile == TerrainMap.Tile.PATH or tile == TerrainMap.Tile.WATER:
		_round_corners(img, map, c)


## Narożnik ścieżki albo wody, przy którym oba boczne sąsiady to trawa, dostaje trójkąt trawy 3 px.
static func _round_corners(img: Image, map: TerrainMap, c: Vector2i) -> void:
	var cell := TerrainMap.CELL
	var last := cell - 1
	for corner: Vector2i in [Vector2i(-1, -1), Vector2i(1, -1), Vector2i(-1, 1), Vector2i(1, 1)]:
		var hn := c + Vector2i(corner.x, 0)
		var vn := c + Vector2i(0, corner.y)
		if not (map.in_bounds(hn) and map.in_bounds(vn)):
			continue
		if map.get_tile(hn) != TerrainMap.Tile.GRASS or map.get_tile(vn) != TerrainMap.Tile.GRASS:
			continue
		var cx := 0 if corner.x < 0 else last
		var cy := 0 if corner.y < 0 else last
		var sx := 1 if corner.x < 0 else -1
		var sy := 1 if corner.y < 0 else -1
		for k: Vector2i in [Vector2i(0, 0), Vector2i(1, 0), Vector2i(0, 1)]:
			var p := c * cell + Vector2i(cx + k.x * sx, cy + k.y * sy)
			img.set_pixelv(p, _grass_under(map, hn, p))
		if map.get_tile(c) == TerrainMap.Tile.WATER:
			for k: Vector2i in [Vector2i(2, 0), Vector2i(1, 1), Vector2i(0, 2)]:
				img.set_pixelv(c * cell + Vector2i(cx + k.x * sx, cy + k.y * sy), Palette.EARTH[1])


## Kolor trawy kratki `n` w pikselu `p` (z jej kafelka), żeby wstawki pasowały do sąsiada.
static func _grass_under(map: TerrainMap, n: Vector2i, p: Vector2i) -> Color:
	var shade := map.get_height(n)
	var grain := PixelCanvas.hash2(p.x & 7, p.y & 7, 20 + shade * VARIANTS + _variant(map, n)) % 9
	if grain == 0:
		shade = mini(shade + 1, Palette.GRASS.size() - 1)
	elif grain == 8:
		shade = maxi(shade - 1, 0)
	return Palette.GRASS[shade]


## Trzcina na trawie przy wodzie: co kilka pikseli dwupikselowe źdźbło z jasnym czubkiem.
static func _draw_reeds(img: Image, map: TerrainMap, c: Vector2i, dir: Vector2i) -> void:
	var cell := TerrainMap.CELL
	var o := c * cell
	for i in cell:
		var p := o + _edge_pixel(dir, i, 0)
		var h := PixelCanvas.hash2(p.x, p.y, map.world_seed + 12) % 5
		if h == 0:
			img.set_pixelv(p, Palette.GRASS[0])
			if p.y > 0:
				img.set_pixel(p.x, p.y - 1, Palette.GRASS[3])
		elif h == 1:
			img.set_pixelv(p, Palette.GRASS[0])


## Ozdoby na trawie w stałym miejscu kratki (z seeda). Mieszczą się w kratce.
static func _draw_decor(img: Image, map: TerrainMap, c: Vector2i) -> void:
	var kind := decor_at(map, c)
	if kind == Decor.NONE:
		return
	var cell := TerrainMap.CELL
	var h := PixelCanvas.hash2(c.x, c.y, map.world_seed + 78)
	var o := c * cell
	var shade := map.get_height(c)
	var top := Palette.GRASS.size() - 1
	var light: Color = Palette.GRASS[mini(shade + 1, top)]
	var dark: Color = Palette.GRASS[maxi(shade - 1, 0)]
	match kind:
		Decor.TUFT:
			# kępka: trzy źdźbła w kształcie V nad ciemną nasadą
			var p := o + Vector2i(1 + h % 5, 2 + (h / 5) % 5)
			img.set_pixelv(p, dark)
			img.set_pixelv(p + Vector2i(-1, -1), light)
			img.set_pixelv(p + Vector2i(1, -1), light)
			img.set_pixelv(p + Vector2i(0, -1), dark)
			img.set_pixelv(p + Vector2i(0, -2), light)
		Decor.FLOWERS:
			# kwiatki: 3 kropki czerwone albo żółte z ciemną łodyżką pod spodem
			var col: Color = Palette.ACCENT if h % 2 == 0 else Palette.THATCH[2]
			for k in 3:
				var hk := PixelCanvas.hash2(k, h, 3)
				var p := o + Vector2i(1 + hk % 6, 1 + (hk / 6) % 5)
				img.set_pixelv(p, col)
				img.set_pixelv(p + Vector2i(0, 1), dark)
		Decor.STONE:
			# kamień 3×2 z jasnym wierzchem i cieniem z prawej u dołu
			var p := o + Vector2i(1 + h % 4, 3 + (h / 4) % 3)
			for x in 3:
				img.set_pixelv(p + Vector2i(x, 0), Palette.EARTH[3] if x < 2 else Palette.EARTH[2])
				img.set_pixelv(p + Vector2i(x, 1), Palette.EARTH[1])
			img.set_pixelv(p + Vector2i(3, 1), Palette.GRASS[0])
		Decor.BUSH:
			# krzak 6×5: ciemna kępa z jaśniejszymi liśćmi od lewej góry i cieniem u dołu
			var p := o + Vector2i(h % 2, 1 + (h / 2) % 2)
			for y in 5:
				for x in 6:
					var corner := (x == 0 or x == 5) and (y == 0 or y == 4)
					if corner:
						continue
					var col: Color = Palette.GRASS[0]
					if y == 4:
						col = Palette.SHADOW if x > 1 else Palette.GRASS[0]
					elif x + y <= 3 and PixelCanvas.hash2(x, y, h) % 3 != 0:
						col = Palette.GRASS[2]
					elif PixelCanvas.hash2(x, y, h + 1) % 4 == 0:
						col = Palette.GRASS[1]
					img.set_pixelv(p + Vector2i(x, y), col)


## Piksel przy krawędzi kratki od strony `dir`: `i` wzdłuż krawędzi, `depth` w głąb kratki.
static func _edge_pixel(dir: Vector2i, i: int, depth: int) -> Vector2i:
	var last := TerrainMap.CELL - 1
	if dir == Vector2i.UP:
		return Vector2i(i, depth)
	if dir == Vector2i.DOWN:
		return Vector2i(i, last - depth)
	if dir == Vector2i.LEFT:
		return Vector2i(depth, i)
	return Vector2i(last - depth, i)


static func _is_road(map: TerrainMap, c: Vector2i) -> bool:
	if not map.in_bounds(c):
		return false
	var t := map.get_tile(c)
	return t == TerrainMap.Tile.PATH or t == TerrainMap.Tile.BRIDGE
