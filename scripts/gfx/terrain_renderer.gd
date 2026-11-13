class_name TerrainRenderer
extends RefCounted
## Rysuje TerrainMap do jednego obrazu (kratka 8×8 px). Kafelki bazowe powstają raz, a potem
## kopiuje się je przez blit_rect. set_pixel() działa tylko na krawędziach ścieżek, wody i zboczy,
## dzięki czemu mapa 512×512 px generuje się bez widocznego przycięcia.

const VARIANTS := 4


static func render(map: TerrainMap) -> Image:
	var cell := TerrainMap.CELL
	var img := Image.create(map.size * cell, map.size * cell, false, Image.FORMAT_RGBA8)
	var grass: Array[Image] = []
	for shade in Palette.GRASS.size():
		for v in VARIANTS:
			grass.append(_grass_tile(shade, v))
	var paths: Array[Image] = []
	var waters: Array[Image] = []
	for v in VARIANTS:
		paths.append(_noise_tile(Palette.EARTH[2], Palette.EARTH[3], 30 + v, 2))
		waters.append(_noise_tile(Palette.WATER[1], Palette.WATER[2], 40 + v, 9))
	var src := Rect2i(0, 0, cell, cell)
	for y in map.size:
		for x in map.size:
			var c := Vector2i(x, y)
			var v := PixelCanvas.hash2(x, y, map.world_seed + 11) % VARIANTS
			var at := c * cell
			match map.get_tile(c):
				TerrainMap.Tile.GRASS:
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
	return img


## Trawa: odcień bazowy z ziarnem jaśniejszych i ciemniejszych pikseli.
static func _grass_tile(shade: int, variant: int) -> Image:
	var cell := TerrainMap.CELL
	var tile := Image.create(cell, cell, false, Image.FORMAT_RGBA8)
	var top := Palette.GRASS.size() - 1
	for y in cell:
		for x in cell:
			var grain := PixelCanvas.hash2(x, y, 20 + shade * VARIANTS + variant) % 7
			var s := shade
			if grain == 0:
				s = mini(shade + 1, top)
			elif grain == 6:
				s = maxi(shade - 1, 0)
			tile.set_pixel(x, y, Palette.GRASS[s])
	return tile


## Kafelek dwukolorowy: `accent` pojawia się średnio w co `rarity`-tym pikselu.
static func _noise_tile(base: Color, accent: Color, tile_seed: int, rarity: int) -> Image:
	var cell := TerrainMap.CELL
	var tile := Image.create(cell, cell, false, Image.FORMAT_RGBA8)
	for y in cell:
		for x in cell:
			tile.set_pixel(x, y, accent if PixelCanvas.hash2(x, y, tile_seed) % rarity == 0 else base)
	return tile


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


## Krawędzie: brzeg przy wodzie, dithering 2×2 na skraju ścieżki, cień zbocza w dół wzgórza.
static func _draw_edges(img: Image, map: TerrainMap, c: Vector2i) -> void:
	var tile := map.get_tile(c)
	var cell := TerrainMap.CELL
	var o := c * cell
	for dir: Vector2i in [Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT]:
		var n := c + dir
		if not map.in_bounds(n):
			continue
		var other := map.get_tile(n)
		if tile == TerrainMap.Tile.WATER and other != TerrainMap.Tile.WATER and other != TerrainMap.Tile.BRIDGE:
			for i in cell:
				img.set_pixelv(o + _edge_pixel(dir, i, 0), Palette.EARTH[1])
				img.set_pixelv(o + _edge_pixel(dir, i, 1), Palette.WATER[0])
		elif tile == TerrainMap.Tile.PATH and other == TerrainMap.Tile.GRASS:
			var col: Color = Palette.GRASS[map.get_height(n)]
			for i in cell:
				if (i + c.x + c.y) % 2 == 0:
					img.set_pixelv(o + _edge_pixel(dir, i, 0), col)
		elif tile == TerrainMap.Tile.GRASS and other == TerrainMap.Tile.GRASS and dir == Vector2i.DOWN:
			var h := map.get_height(c)
			if map.get_height(n) < h:
				var col: Color = Palette.GRASS[h - 1]
				for i in cell:
					if i % 2 == 0:
						img.set_pixelv(o + _edge_pixel(dir, i, 0), col)


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
