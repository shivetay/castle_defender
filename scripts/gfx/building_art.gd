class_name BuildingArt
extends RefCounted
## Rysuje budynki epoki I w rzucie 3/4. Obraz ma szerokość kratek budynku, a wysokość kratek
## plus EXTRA pikseli, o które budynek wystaje ponad swoje kratki. Wiersz obrazu `g + EXTRA`
## odpowiada wierszowi `g` na ziemi, więc obraz rysuje się w (rect.position * 8) - (0, EXTRA).
##
## Wał i palisada to odcinki 1×1 z autotilingiem: środek plus ramię do każdego sąsiada z maski
## N/E/S/W (16 wariantów). Ramiona dochodzą do krawędzi kratki, więc sąsiednie odcinki
## łączą się bez dziur. Ściana i blanki rysują się osobnymi przebiegami.
@warning_ignore_start("integer_division")

const CELL := 8
## Krycie cienia rzucanego na trawę (#150).
const SHADOW_ALPHA := 0.3
## Ile pikseli budynek wystaje ponad swoje kratki (stałe dla rodzaju, niezależne od poziomu).
const EXTRA: Array[int] = [4, 4, 12, 20, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 8, 10, 10, 10, 10, 10, 22, 10]


## Rozmiar obrazu. `vertical` obraca obrys budynku (brama w pionowej linii palisady).
static func image_size(kind: int, vertical: bool = false) -> Vector2i:
	var s := BuildingTypes.size_of(kind) * CELL
	if vertical:
		s = Vector2i(s.y, s.x)
	return Vector2i(s.x, s.y + EXTRA[kind])


## Obraz budynku. `mask` ma znaczenie tylko dla wału i palisady, `vertical` tylko dla bramy.
## Poziom 0 to plac budowy (stan nie ma wtedy znaczenia).
## Przybudówka przy murze (#149): strona, po której stoi wał albo palisada. Budynek przy murze ma dach
## jednospadowy, wyższy przy murze: przy murze z boku fasada jest trójkątem prostokątnym, przy murze
## z tyłu albo z przodu dach to jedna połać bez szczytu.
enum Lean { NONE, NORTH, EAST, SOUTH, WEST }


## Czy rodzaj rysuje się jako przybudówka, gdy przylega do muru: chata drwala i warsztaty (Dwór,
## donżon, wieża, brama, pole lnu i umocnienia mają własny kształt).
static func can_lean(kind: int) -> bool:
	return not (BuildingTypes.is_wall(kind) or kind in [
			BuildingTypes.Kind.GATE, BuildingTypes.Kind.TOWER, BuildingTypes.Kind.MANOR, BuildingTypes.Kind.KEEP,
			BuildingTypes.Kind.FLAX_FIELD])


## Strona przybudówki z kierunku do muru (BuildGrid.wall_side).
static func lean_from(dir: Vector2i) -> int:
	match dir:
		Vector2i.UP:
			return Lean.NORTH
		Vector2i.RIGHT:
			return Lean.EAST
		Vector2i.DOWN:
			return Lean.SOUTH
		Vector2i.LEFT:
			return Lean.WEST
	return Lean.NONE


static func make_image(kind: int, level: int, state: int, mask: int = 0, vertical: bool = false,
		lean: int = Lean.NONE) -> Image:
	var v := vertical and kind == BuildingTypes.Kind.GATE
	var sz := image_size(kind, v)
	var img := Image.create(sz.x, sz.y, false, Image.FORMAT_RGBA8)
	if level <= 0:
		_draw_site(img, kind, mask)
		return img
	var lv := clampi(level, 1, BuildingTypes.MAX_LEVEL)
	var ln := lean if can_lean(kind) else Lean.NONE
	# przy murze z prawej: rysunek jak przy murze z lewej, odbity w poziomie
	var mirror := ln == Lean.EAST
	if mirror:
		ln = Lean.WEST
	match kind:
		BuildingTypes.Kind.RAMPART:
			_draw_rampart(img, lv, mask, state)
		BuildingTypes.Kind.PALISADE:
			_draw_palisade(img, lv, mask, state)
		BuildingTypes.Kind.GATE:
			if v:
				_draw_gate_vertical(img, lv)
			else:
				_draw_gate(img, lv)
		BuildingTypes.Kind.TOWER:
			_draw_tower(img, lv)
		BuildingTypes.Kind.LUMBER_HUT:
			_draw_hut(img, lv, ln)
		BuildingTypes.Kind.MANOR:
			_draw_manor(img, lv)
		BuildingTypes.Kind.FLAX_FIELD:
			_draw_flax_field(img, lv)
		BuildingTypes.Kind.KEEP:
			_draw_keep(img, lv)
		_:
			_draw_workshop(img, kind, lv, ln)
	if mirror:
		img.flip_x()
	_apply_state(img, kind, state, mask)
	if has_outline(kind):
		_outline_and_light(img)
	return img


## Czy budynek dostaje obrys i światło (#150). Umocnienia, brama i wieża łączą się z sąsiednimi
## odcinkami muru, więc obrys rysowałby kreskę na styku: one go nie mają.
static func has_outline(kind: int) -> bool:
	return not (BuildingTypes.is_wall(kind) or kind == BuildingTypes.Kind.GATE or kind == BuildingTypes.Kind.TOWER)


## Obrys i światło z lewej góry (#150): przezroczysty piksel przy sylwetce dostaje kolor cienia,
## a piksel sylwetki odsłonięty od lewej albo od góry rozjaśnia się o stopień w swojej rampie.
## Działa na kopii kanału alfa, więc obrys nie liczy się jako sylwetka przy rozjaśnianiu.
static func _outline_and_light(img: Image) -> void:
	var w := img.get_width()
	var h := img.get_height()
	var data := img.get_data()
	var solid := PackedByteArray()
	solid.resize(w * h)
	for i in w * h:
		solid[i] = 1 if data[i * 4 + 3] == 255 else 0
	var lighter := _lighter_map()
	for y in h:
		for x in w:
			var i := y * w + x
			if solid[i] == 1:
				var open_left := x == 0 or solid[i - 1] == 0
				var open_top := y == 0 or solid[i - w] == 0
				if open_left or open_top:
					var col := img.get_pixel(x, y)
					var up: Color = lighter.get(col.to_rgba32(), col)
					if up != col:
						img.set_pixel(x, y, up)
			elif (x > 0 and solid[i - 1] == 1) or (x < w - 1 and solid[i + 1] == 1) \
					or (y > 0 and solid[i - w] == 1) or (y < h - 1 and solid[i + w] == 1):
				img.set_pixel(x, y, Palette.SHADOW)


## Kolor o stopień jaśniejszy w rampie palety (trawa, drewno, ziemia, strzecha, woda).
static func _lighter_map() -> Dictionary:
	var pairs: Array[Array] = [
		[Palette.GRASS[0], Palette.GRASS[1]], [Palette.GRASS[1], Palette.GRASS[2]], [Palette.GRASS[2], Palette.GRASS[3]],
		[Palette.WOOD[0], Palette.WOOD[1]], [Palette.WOOD[1], Palette.WOOD[2]], [Palette.WOOD[2], Palette.WOOD[3]],
		[Palette.THATCH[0], Palette.THATCH[1]], [Palette.THATCH[1], Palette.THATCH[2]],
		[Palette.WATER[0], Palette.WATER[1]], [Palette.WATER[1], Palette.WATER[2]],
		[Palette.SHADOW, Palette.WOOD[0]],
	]
	var out := {}
	for pr in pairs:
		out[(pr[0] as Color).to_rgba32()] = pr[1]
	return out


## Cień rzucany na trawę (#150): sylwetka przesunięta o `offset` w prawo i w dół (światło z lewej
## góry), w kolorze cienia z przezroczystością. Budynek rysuje się na nim, więc widać tylko pasek
## po prawej i u dołu.
static func shadow_image(img: Image, offset: Vector2i) -> Image:
	var w := img.get_width()
	var h := img.get_height()
	var out := Image.create(w + offset.x, h + offset.y, false, Image.FORMAT_RGBA8)
	var data := img.get_data()
	var col := Color(Palette.SHADOW, SHADOW_ALPHA)
	for y in h:
		for x in w:
			if data[(y * w + x) * 4 + 3] == 255:
				out.set_pixel(x + offset.x, y + offset.y, col)
	return out


## Przesunięcie cienia: budynki rzucają dłuższy cień niż niskie odcinki muru.
static func shadow_offset(kind: int) -> Vector2i:
	return Vector2i(1, 1) if BuildingTypes.is_wall(kind) else Vector2i(3, 1)


## Dach jednospadowy przybudówki nad ścianą `wall`, `rows` wierszy w najwyższym miejscu (#149).
## WEST: najwyżej przy lewej krawędzi (przy murze), opada w prawo, więc z fasadą tworzy trójkąt
## prostokątny. NORTH: jedna połać opadająca ku patrzącemu, najwyżej przy murze z tyłu. SOUTH: połać
## opada od muru z przodu w głąb, widać tylko niski okap.
static func _draw_lean_roof(img: Image, wall: Rect2i, rows: int, lean: int) -> void:
	match lean:
		Lean.WEST:
			var span := maxi(1, wall.size.x)
			for x in range(0, wall.end.x + 1):
				var h := maxi(2, rows - maxi(0, x - wall.position.x) * (rows - 2) / span)
				for y in range(wall.position.y - h, wall.position.y):
					var row := y - (wall.position.y - h)
					var col: Color = Palette.THATCH[2] if row < 2 else Palette.THATCH[1]
					if y == wall.position.y - 1:
						col = Palette.THATCH[0]
					elif PixelCanvas.hash2(x, y, 61) % 5 == 0:
						col = Palette.THATCH[0]
					PixelCanvas.px(img, x, y, col)
		Lean.NORTH:
			for y in range(wall.position.y - rows, wall.position.y):
				var row := y - (wall.position.y - rows)
				for x in range(maxi(0, wall.position.x - 1), mini(img.get_width(), wall.end.x + 1)):
					var col: Color = Palette.THATCH[2] if row < rows / 2 else Palette.THATCH[1]
					if row == rows - 1:
						col = Palette.THATCH[0]
					elif PixelCanvas.hash2(x, y, 61) % 5 == 0:
						col = Palette.THATCH[0]
					PixelCanvas.px(img, x, y, col)
		_:
			var low := maxi(2, rows / 2)
			for y in range(wall.position.y - low, wall.position.y):
				for x in range(maxi(0, wall.position.x - 1), mini(img.get_width(), wall.end.x + 1)):
					var col: Color = Palette.THATCH[1] if y < wall.position.y - 1 else Palette.THATCH[0]
					PixelCanvas.px(img, x, y, col)


## Daszek wiaty (poziom 1) przy murze: słupy różnej wysokości i deski pochylone od muru (#149).
static func _draw_lean_shed(img: Image, base: int, posts: Array[int], top: int, lean: int) -> void:
	if lean == Lean.WEST:
		var tall: int = posts[0]
		var short: int = posts[1]
		PixelCanvas.rect(img, Rect2i(tall, top + 2, 1, base - top - 1), Palette.WOOD[1])
		PixelCanvas.rect(img, Rect2i(short, top + 5, 1, base - top - 4), Palette.WOOD[1])
		for x in range(0, short + 3):
			var y := top + x * 3 / maxi(1, short + 2)
			PixelCanvas.px(img, x, y, Palette.WOOD[2])
			PixelCanvas.px(img, x, y + 1, Palette.WOOD[0])
		return
	for x: int in posts:
		PixelCanvas.rect(img, Rect2i(x, top + 2, 1, base - top - 1), Palette.WOOD[1])
	var depth := 3 if lean == Lean.NORTH else 2
	PixelCanvas.draw_plank_wall(img, Rect2i(0, top, posts[1] + 2, depth), Palette.WOOD)


# --- Autotiling umocnień -------------------------------------------------------------------

## Kształt odcinka na ziemi (8×8, 1 = umocnienie): środek grubości `t` i ramiona z maski.
static func wall_shape(mask: int, t: int) -> PackedByteArray:
	var f := PackedByteArray()
	f.resize(CELL * CELL)
	var lo := (CELL - t) / 2
	var hi := lo + t
	for y in CELL:
		for x in CELL:
			var in_x := x >= lo and x < hi
			var in_y := y >= lo and y < hi
			var on := in_x and in_y
			on = on or (in_x and y < lo and mask & BuildingTypes.N != 0)
			on = on or (in_x and y >= hi and mask & BuildingTypes.S != 0)
			on = on or (in_y and x >= hi and mask & BuildingTypes.E != 0)
			on = on or (in_y and x < lo and mask & BuildingTypes.W != 0)
			f[y * CELL + x] = 1 if on else 0
	return f


static func _on(f: PackedByteArray, x: int, y: int) -> bool:
	return x >= 0 and y >= 0 and x < CELL and y < CELL and f[y * CELL + x] == 1


## Grubość odcinka umocnienia na ziemi w pikselach.
static func wall_thickness(kind: int) -> int:
	return 4 if kind == BuildingTypes.Kind.RAMPART else 2


## Wysokość ściany w każdym pikselu kształtu: pełna `h`, a przy wyrwie niższa w blokach 2×2
## wybranych przez hash2. Blok w środku kratki pęka zawsze, więc wyrwa jest widoczna w każdym
## wariancie autotilingu. Wzór zależy tylko od położenia w kratce, więc odcinki dalej się łączą.
## Gdy odcinek ciągnie się na południe, wyrwa nie schodzi poniżej wierzchu ostatniego wiersza,
## bo pod nim zaczyna się już obraz sąsiedniej kratki.
static func _wall_heights(kind: int, f: PackedByteArray, mask: int, h: int, state: int) -> PackedInt32Array:
	var hm := PackedInt32Array()
	hm.resize(CELL * CELL)
	for y in CELL:
		for x in CELL:
			if not _on(f, x, y):
				continue
			var drop := 0
			if state == BuildingTypes.State.BREACHED:
				var bx := x >> 1
				var by := y >> 1
				if (bx == 2 and by == 2) or (bx == 1 and by == 1) or PixelCanvas.hash2(bx, by, 17 + kind) % 3 == 0:
					drop = mini(h, 1 + PixelCanvas.hash2(x, y, 23 + kind) % 2 + (1 if h >= 4 else 0))
				if mask & BuildingTypes.S != 0:
					drop = mini(drop, CELL - 1 - y)
			hm[y * CELL + x] = h - drop
	return hm


## Wysokość umocnienia tuż na południe od piksela, do której schodzi jego czoło: 0, gdy przed
## nim jest ziemia, wysokość sąsiada w kształcie, albo pełna `h`, gdy odcinek ciągnie się w kratce
## poniżej (tamta kratka rysuje się osobno).
static func _south_height(f: PackedByteArray, hm: PackedInt32Array, mask: int, x: int, y: int, h: int) -> int:
	if y == CELL - 1:
		return h if mask & BuildingTypes.S != 0 else 0
	if _on(f, x, y + 1):
		return mini(hm[(y + 1) * CELL + x], hm[y * CELL + x])
	return 0


## Czy piksel kształtu ma widoczne czoło (od południa nie ma dalszej części umocnienia).
static func _has_face(f: PackedByteArray, mask: int, x: int, y: int) -> bool:
	if y == CELL - 1 and mask & BuildingTypes.S != 0:
		return false
	return not _on(f, x, y + 1)


## Czy piksel leży na północnym skraju umocnienia (tam stoją blanki).
static func _is_crest(f: PackedByteArray, mask: int, x: int, y: int) -> bool:
	if y == 0 and mask & BuildingTypes.N != 0:
		return false
	return not _on(f, x, y - 1)


## Wał ziemny: nasyp z ditheringiem 2×2. Poziomy: 1 goła ziemia, 2 wyższy i zarośnięty,
## 3 z suchą fosą, 4 z palikami na koronie, 5 z płotem na koronie.
static func _draw_rampart(img: Image, level: int, mask: int, state: int) -> void:
	var kind := BuildingTypes.Kind.RAMPART
	var h := 2 if level == 1 else 3
	var ex: int = EXTRA[kind]
	var t := wall_thickness(kind)
	var f := wall_shape(mask, t)
	var hm := _wall_heights(kind, f, mask, h, state)
	_wall_ground(img, f, mask, ex, level >= 3)
	for y in CELL:
		for x in CELL:
			if not _on(f, x, y):
				continue
			var hh := hm[y * CELL + x]
			var top := y + ex - hh
			for i in range(1, hh - _south_height(f, hm, mask, x, y, h) + 1):
				PixelCanvas.px(img, x, top + i, PixelCanvas.dither(x, top + i, Palette.EARTH[1], Palette.EARTH[2]))
			# korona: ziemia albo darń przemieszana z ziemią; w biegu pionowym ciemniejsze zbocza
			var grass := level >= 2
			var a: Color = Palette.GRASS[3] if grass else Palette.EARTH[3]
			var b: Color = Palette.EARTH[3] if grass else Palette.EARTH[2]
			var col := PixelCanvas.dither(x, y, a, b)
			var lo := (CELL - t) / 2
			if (y < lo or y >= lo + t) and (x == lo or x == lo + t - 1):
				col = Palette.EARTH[2] if x == lo else Palette.EARTH[1]
			if hh < h:
				# dno wyrwy: rozkopana ziemia bez darni
				col = PixelCanvas.dither(x, y, Palette.EARTH[1], Palette.EARTH[0])
			PixelCanvas.px(img, x, top, col)
	# blanki: paliki (poziom 4) albo płot (poziom 5) na północnym skraju korony
	if level < 4:
		return
	for y in CELL:
		for x in CELL:
			if not (_on(f, x, y) and _is_crest(f, mask, x, y)) or hm[y * CELL + x] < h:
				continue
			var top := y + ex - h
			if level == 4:
				if x % 2 == 0:
					PixelCanvas.px(img, x, top - 1, Palette.WOOD[2])
			else:
				PixelCanvas.px(img, x, top - 1, Palette.WOOD[2] if x % 2 == 0 else Palette.WOOD[1])
				if x % 2 == 0:
					PixelCanvas.px(img, x, top - 2, Palette.WOOD[3])


## Palisada: pale 2 px grubości, ściana wysoka na 4 px. Poziomy: 1 płaskie pale,
## 2 zaostrzone (blanki), 3 z belką spinającą, 4 na ziemnym podsypaniu, 5 z żelazną obręczą
## i wyższymi ostrzami.
static func _draw_palisade(img: Image, level: int, mask: int, state: int) -> void:
	var kind := BuildingTypes.Kind.PALISADE
	var h := 4
	var ex: int = EXTRA[kind]
	var t := wall_thickness(kind)
	var f := wall_shape(mask, t)
	var hm := _wall_heights(kind, f, mask, h, state)
	var lo := (CELL - t) / 2
	var hi := lo + t
	_wall_ground(img, f, mask, ex, false)
	if level >= 4:
		_wall_mound(img, f, mask, ex)
	for y in CELL:
		for x in CELL:
			if not _on(f, x, y):
				continue
			var hh := hm[y * CELL + x]
			var top := y + ex - hh
			# czoło od wierzchu w dół; przy wyrwie także bok wyższego pala nad niższym sąsiadem
			for i in range(1, hh - _south_height(f, hm, mask, x, y, h) + 1):
				var col: Color = Palette.WOOD[2] if x % 2 == 0 else Palette.WOOD[1]
				if i == hh:
					col = Palette.WOOD[0]
				elif level >= 3 and i == 2 and hh == h:
					col = Palette.SHADOW if level == 5 else Palette.WOOD[0]
				PixelCanvas.px(img, x, top + i, col)
			# wierzch pali: w biegu pionowym pale idą wzdłuż y, w poziomym wzdłuż x
			var vertical := y < lo or y >= hi
			var stake := y if vertical else x
			var top_col: Color = Palette.WOOD[3] if stake % 2 == 0 else Palette.WOOD[2]
			if vertical and x == hi - 1:
				top_col = Palette.WOOD[1]
			if hh < h:
				# złamany pal: ciemny, postrzępiony wierzch
				top_col = Palette.WOOD[0] if (x + y) % 2 == 0 else Palette.SHADOW
			PixelCanvas.px(img, x, top, top_col)
	if level < 2:
		return
	for y in CELL:
		for x in CELL:
			if _on(f, x, y) and _is_crest(f, mask, x, y) and x % 2 == 0 and hm[y * CELL + x] == h:
				var top := y + ex - h
				PixelCanvas.px(img, x, top - 1, Palette.WOOD[3])
				if level == 5:
					PixelCanvas.px(img, x, top - 2, Palette.WOOD[3])


## Cień (albo sucha fosa) na ziemi tuż przed czołem umocnienia.
static func _wall_ground(img: Image, f: PackedByteArray, mask: int, ex: int, ditch: bool) -> void:
	for y in CELL:
		for x in CELL:
			if not (_on(f, x, y) and _has_face(f, mask, x, y)):
				continue
			if ditch:
				for d in range(1, 3):
					var row := y + d
					if row < CELL and not _on(f, x, row):
						PixelCanvas.px(img, x, row + ex, PixelCanvas.dither(x, row, Palette.EARTH[0], Palette.SHADOW))
			elif y + 1 < CELL:
				PixelCanvas.px(img, x, y + 1 + ex, Color(Palette.SHADOW, 0.5))


## Ziemne podsypanie u stóp palisady (2 wiersze ditheringu 2×2 przed czołem).
static func _wall_mound(img: Image, f: PackedByteArray, mask: int, ex: int) -> void:
	for y in CELL:
		for x in CELL:
			if not (_on(f, x, y) and _has_face(f, mask, x, y)):
				continue
			for d in range(0, 2):
				var row := y + d
				if row < CELL:
					PixelCanvas.px(img, x, row + ex, PixelCanvas.dither(x, row, Palette.EARTH[1], Palette.EARTH[2]))


# --- Budynki wielokratkowe -----------------------------------------------------------------

## Brama drewniana (3×1) w linii palisady. Poziomy: 1 dwa skrzydła między słupami,
## 2 z nadprożem, 3 z daszkami na słupach, 4 z izbą bramną i dachem, 5 ze sztandarami i okuciami.
static func _draw_gate(img: Image, level: int) -> void:
	var w := img.get_width()
	var base := 4 + EXTRA[BuildingTypes.Kind.GATE]  # dolny wiersz czoła (ziemia, wiersz 4)
	var post_w := 3 if level >= 3 else 2
	var post_h: Array[int] = [7, 9, 11, 13, 13]
	var door_h := 6 if level == 1 else 7
	PixelCanvas.rect(img, Rect2i(0, base + 1, w, 1), Color(Palette.SHADOW, 0.5))
	# skrzydła bramy
	var door_x := post_w
	var half := (w - 2 * post_w) / 2
	PixelCanvas.draw_door(img, Rect2i(door_x, base - door_h + 1, half, door_h))
	PixelCanvas.draw_door(img, Rect2i(door_x + half, base - door_h + 1, half, door_h))
	if level == 5:
		for y: int in [base - door_h + 2, base - 1]:
			for x in range(door_x + 1, w - post_w - 1, 3):
				PixelCanvas.px(img, x, y, Palette.SHADOW)
	# izba bramna nad nadprożem
	if level >= 4:
		PixelCanvas.draw_log_wall(img, Rect2i(1, 4, w - 2, base - door_h - 4), Palette.WOOD, 5)
		PixelCanvas.draw_window(img, Vector2i(w / 2 - 1, 6))
	# słupy
	for x0: int in [0, w - post_w]:
		var top: int = base - post_h[level - 1] + 1
		PixelCanvas.rect(img, Rect2i(x0, top, post_w, post_h[level - 1]), Palette.WOOD[1])
		PixelCanvas.rect(img, Rect2i(x0, top, 1, post_h[level - 1]), Palette.WOOD[2])
		PixelCanvas.rect(img, Rect2i(x0, top, post_w, 1), Palette.WOOD[3])
		if level == 3:
			# daszki 4 px nad słupami 3 px: nawis do środka bramy, żeby nie wyjść poza obraz
			var roof_cx := x0 + 2 if x0 == 0 else x0 + 1
			PixelCanvas.draw_roof(img, roof_cx, top - 2, 2, 2, Palette.THATCH)
		if level == 5:
			PixelCanvas.rect(img, Rect2i(x0 + (1 if x0 == 0 else 0), top + 3, 2, 4), Palette.ACCENT)
	# nadproże
	if level >= 2:
		var lintel := base - door_h - 1
		PixelCanvas.rect(img, Rect2i(0, lintel, w, 2), Palette.WOOD[0])
		PixelCanvas.rect(img, Rect2i(0, lintel, w, 1), Palette.WOOD[2])
	if level >= 4:
		PixelCanvas.draw_roof(img, w / 2, 0, 10, 4, Palette.THATCH)


## Brama w pionowej linii palisady (1×3), widziana z boku: słup na każdym końcu, między nimi
## zamknięte skrzydła widoczne od góry. Słupy stoją na osi palisady (kolumny 2..5), więc
## pionowe odcinki dochodzą do nich bez szpary. Poziomy jak w bramie poziomej.
static func _draw_gate_vertical(img: Image, level: int) -> void:
	var ex: int = EXTRA[BuildingTypes.Kind.GATE]
	var length := img.get_height() - ex  # długość bramy w pikselach (wzdłuż osi y)
	var post_h: Array[int] = [6, 8, 9, 10, 10]
	var ph := post_h[level - 1]
	var door_h := 5 if level == 1 else 6
	PixelCanvas.rect(img, Rect2i(2, length + ex - 0, 4, 1), Color(Palette.SHADOW, 0.5))
	# skrzydła od góry: ciemne deski z jasną krawędzią, szpara między skrzydłami, okucia na poziomie 5
	for g in range(3, length - 3):
		var top := g + ex - door_h
		PixelCanvas.px(img, 3, top, Palette.WOOD[2] if g % 2 == 0 else Palette.WOOD[1])
		PixelCanvas.px(img, 4, top, Palette.WOOD[0] if g != length / 2 - 1 else Palette.SHADOW)
		if level == 5 and g % 3 == 0:
			PixelCanvas.px(img, 3, top, Palette.SHADOW)
	for g0: int in [0, length - 3]:
		var top := g0 + ex - ph
		# wierzch słupa, czoło od dolnego wiersza i jasna lewa krawędź
		PixelCanvas.rect(img, Rect2i(2, top, 4, 3), Palette.WOOD[3])
		PixelCanvas.rect(img, Rect2i(2, top + 3, 4, ph), Palette.WOOD[1])
		PixelCanvas.rect(img, Rect2i(2, top + 3, 1, ph), Palette.WOOD[2])
		PixelCanvas.rect(img, Rect2i(2, top + 2 + ph, 4, 1), Palette.WOOD[0])
		if level == 3:
			PixelCanvas.draw_roof(img, 4, top - 2, 2, 3, Palette.THATCH)
		if level == 5:
			PixelCanvas.rect(img, Rect2i(3, top + 4, 2, 3), Palette.ACCENT)
		if g0 == 0 and level >= 2:
			# nadproże: belka wzdłuż bramy na wysokości szczytu słupów
			for g in range(3, length - 3):
				PixelCanvas.px(img, 3, g + ex - ph, Palette.WOOD[2])
				PixelCanvas.px(img, 4, g + ex - ph, Palette.WOOD[0])
	# izba bramna: strzecha nad całą bramą
	if level >= 4:
		# szczyt strzechy w wierszu 0 obrazu (ph = 10 na poziomach 4–5), okap pod spodem
		var roof_top := ex - ph - 2
		for g in range(0, length):
			var y := g + roof_top
			PixelCanvas.px(img, 1, y, Palette.THATCH[0])
			for x in range(2, 6):
				PixelCanvas.px(img, x, y, Palette.THATCH[2] if (x + g) % 3 != 0 else Palette.THATCH[1])
			PixelCanvas.px(img, 6, y, Palette.THATCH[0])
		PixelCanvas.rect(img, Rect2i(1, roof_top + length, 6, 1), Palette.THATCH[0])


## Wieża drewniana (2×2). Poziomy: 1 pomost na nogach, 2 z balustradą, 3 z obudowanym dołem,
## 4 z izbą i dachem, 5 wyższa, z flagą.
static func _draw_tower(img: Image, level: int) -> void:
	var w := img.get_width()
	var base := 13 + EXTRA[BuildingTypes.Kind.TOWER]
	var floor_y := base - 16
	PixelCanvas.rect(img, Rect2i(2, base + 1, w - 4, 1), Color(Palette.SHADOW, 0.5))
	if level < 3:
		# tylne nogi, przednie nogi i zastrzał
		for x: int in [4, 11]:
			PixelCanvas.rect(img, Rect2i(x, floor_y + 3, 1, base - floor_y - 5), Palette.WOOD[0])
		for x: int in [2, 12]:
			PixelCanvas.rect(img, Rect2i(x, floor_y + 3, 2, base - floor_y - 2), Palette.WOOD[1])
			PixelCanvas.rect(img, Rect2i(x, floor_y + 3, 1, base - floor_y - 2), Palette.WOOD[2])
		for i in range(0, 8):
			PixelCanvas.px(img, 4 + i, floor_y + 4 + i, Palette.WOOD[0])
			PixelCanvas.px(img, 11 - i, floor_y + 4 + i, Palette.WOOD[0])
	else:
		PixelCanvas.draw_log_wall(img, Rect2i(2, floor_y + 3, w - 4, base - floor_y - 2), Palette.WOOD, 7)
		PixelCanvas.draw_beams(img, Rect2i(2, floor_y + 3, w - 4, base - floor_y - 2), Palette.WOOD[0])
		PixelCanvas.draw_door(img, Rect2i(6, base - 5, 4, 6))
	# pomost
	PixelCanvas.rect(img, Rect2i(1, floor_y, w - 2, 1), Palette.WOOD[3])
	PixelCanvas.rect(img, Rect2i(1, floor_y + 1, w - 2, 1), Palette.WOOD[2])
	PixelCanvas.rect(img, Rect2i(1, floor_y + 2, w - 2, 1), Palette.WOOD[0])
	if level == 2 or level == 3:
		PixelCanvas.rect(img, Rect2i(1, floor_y - 4, w - 2, 1), Palette.WOOD[2])
		for x: int in [1, 5, 10, 14]:
			PixelCanvas.rect(img, Rect2i(x, floor_y - 3, 1, 3), Palette.WOOD[1])
	if level >= 4:
		var room_top := floor_y - 6
		PixelCanvas.draw_log_wall(img, Rect2i(2, room_top, w - 4, 6), Palette.WOOD, 9)
		PixelCanvas.draw_beams(img, Rect2i(2, room_top, w - 4, 6), Palette.WOOD[0])
		PixelCanvas.draw_window(img, Vector2i(5, room_top + 2))
		PixelCanvas.draw_window(img, Vector2i(9, room_top + 2))
		var roof_rows := 6 if level == 4 else 8
		PixelCanvas.draw_roof(img, w / 2, room_top - roof_rows, 2, roof_rows, Palette.THATCH)
		if level == 5:
			PixelCanvas.draw_flag(img, Vector2i(w / 2 - 1, room_top - roof_rows - 1), 3, Palette.ACCENT)


## Chata drwala (2×2). Poziomy: 1 wiata ze stosem drewna, 2 chata ze strzechą, 3 ze stosem
## bali z boku, 4 z oknem i szkieletem belek, 5 z drugim stosem i flagą.
static func _draw_hut(img: Image, level: int, lean: int = Lean.NONE) -> void:
	var base := 13 + EXTRA[BuildingTypes.Kind.LUMBER_HUT]
	PixelCanvas.rect(img, Rect2i(1, base + 1, 14, 1), Color(Palette.SHADOW, 0.5))
	if level == 1 and lean != Lean.NONE:
		_draw_lean_shed(img, base, [2, 11] as Array[int], base - 11, lean)
		_log_pile(img, Rect2i(4, base - 3, 6, 4))
		PixelCanvas.rect(img, Rect2i(13, base - 1, 2, 2), Palette.WOOD[2])
		return
	if level == 1:
		for x: int in [2, 11]:
			PixelCanvas.rect(img, Rect2i(x, base - 9, 1, 10), Palette.WOOD[1])
		PixelCanvas.draw_plank_wall(img, Rect2i(1, base - 11, 12, 2), Palette.WOOD)
		_log_pile(img, Rect2i(4, base - 3, 6, 4))
		PixelCanvas.rect(img, Rect2i(13, base - 1, 2, 2), Palette.WOOD[2])
		return
	var wall := Rect2i(2, base - 7, 10, 8) if level < 4 else Rect2i(1, base - 7, 12, 8)
	PixelCanvas.draw_log_wall(img, wall, Palette.WOOD, 3)
	if level >= 4:
		PixelCanvas.draw_beams(img, wall, Palette.WOOD[0])
		PixelCanvas.draw_window(img, Vector2i(wall.end.x - 4, base - 5))
	PixelCanvas.draw_door(img, Rect2i(wall.position.x + 2, base - 4, 3, 5))
	var cx := wall.position.x + wall.size.x / 2
	if lean != Lean.NONE:
		_draw_lean_roof(img, wall, 7, lean)
	else:
		PixelCanvas.draw_roof(img, cx, wall.position.y - 7, 2, 7, Palette.THATCH)
	if level >= 3:
		_log_pile(img, Rect2i(12, base - 3, 4, 4))
	if level == 5:
		_log_pile(img, Rect2i(12, base - 5, 4, 2))
		PixelCanvas.draw_flag(img, Vector2i(cx - 1, wall.position.y - 8), 5, Palette.ACCENT)


## Dwór (2×2), siedziba władcy i poziom zamku. Poziomy: 1 izba z bali pod strzechą,
## 2 ze szkieletem belek i oknem, 3 wyższy z drugim oknem, 4 z daszkiem nad wejściem,
## 5 z flagą na szczycie i tarczami na ścianie.
static func _draw_manor(img: Image, level: int) -> void:
	var base := 13 + EXTRA[BuildingTypes.Kind.MANOR]
	PixelCanvas.rect(img, Rect2i(0, base + 1, 16, 1), Color(Palette.SHADOW, 0.5))
	var wall_h := 8 if level < 3 else 10
	var wall := Rect2i(1, base - wall_h + 1, 14, wall_h)
	PixelCanvas.draw_log_wall(img, wall, Palette.WOOD, 13)
	if level >= 2:
		PixelCanvas.draw_beams(img, wall, Palette.WOOD[0])
		PixelCanvas.draw_window(img, Vector2i(3, base - 6))
	if level >= 3:
		PixelCanvas.draw_window(img, Vector2i(11, base - 6))
	PixelCanvas.draw_door(img, Rect2i(6, base - 4, 4, 5))
	PixelCanvas.draw_roof(img, 8, wall.position.y - 7, 2, 7, Palette.THATCH)
	if level >= 4:
		PixelCanvas.draw_roof(img, 8, base - 7, 4, 2, Palette.THATCH)
	if level == 5:
		PixelCanvas.draw_flag(img, Vector2i(7, wall.position.y - 8), 3, Palette.ACCENT)
		for x: int in [2, 12]:
			PixelCanvas.rect(img, Rect2i(x, base - 3, 2, 3), Palette.ACCENT)
			PixelCanvas.px(img, x + 1, base - 1, Palette.WOOD[0])


# --- Wytwórcy (#90) ---------------------------------------------------------------------------

## Warsztat wytwórcy (2×2). Wszystkie mają ten sam szkielet, a rozpoznaje się je po rekwizycie
## z prawej (_draw_prop) i po ścianie (bale albo deski). Poziomy: 1 wiata z rekwizytem pod daszkiem,
## 2 izba pod strzechą z rekwizytem obok, 3 z oknem i wyższym dachem, 4 szersza ze szkieletem belek
## i większym rekwizytem, 5 z flagą i proporcem na ścianie.
static func _draw_workshop(img: Image, kind: int, level: int, lean: int = Lean.NONE) -> void:
	var base := 13 + EXTRA[kind]
	PixelCanvas.rect(img, Rect2i(1, base + 1, 14, 1), Color(Palette.SHADOW, 0.5))
	if level == 1 and lean != Lean.NONE:
		_draw_lean_shed(img, base, [1, 10] as Array[int], base - 10, lean)
		_draw_prop(img, kind, Vector2i(3, base), false)
		return
	if level == 1:
		for x: int in [1, 10]:
			PixelCanvas.rect(img, Rect2i(x, base - 8, 1, 9), Palette.WOOD[1])
		PixelCanvas.draw_plank_wall(img, Rect2i(0, base - 10, 12, 2), Palette.WOOD)
		_draw_prop(img, kind, Vector2i(3, base), false)
		return
	var wide := level >= 4
	# szersza izba rośnie w lewo, żeby rekwizyt (kolumny 11–15) stał obok, a nie na ścianie
	var wall := Rect2i(0, base - 8, 11, 9) if wide else Rect2i(1, base - 7, 10, 8)
	if _plank_walls(kind):
		PixelCanvas.draw_plank_wall(img, wall, Palette.WOOD)
		PixelCanvas.rect(img, Rect2i(wall.position, Vector2i(wall.size.x, 1)), Palette.WOOD[0])
	else:
		PixelCanvas.draw_log_wall(img, wall, Palette.WOOD, 17 + kind)
	if wide:
		PixelCanvas.draw_beams(img, wall, Palette.WOOD[0])
	if level >= 3:
		PixelCanvas.draw_window(img, Vector2i(wall.end.x - 3, base - 5))
	PixelCanvas.draw_door(img, Rect2i(wall.position.x + 1, base - 4, 3, 5))
	var cx := wall.position.x + wall.size.x / 2
	var rows := 6 if level == 2 else (7 if level < 5 else 8)
	if lean != Lean.NONE:
		_draw_lean_roof(img, wall, rows, lean)
	else:
		PixelCanvas.draw_roof(img, cx, wall.position.y - rows, 2, rows, Palette.THATCH)
	_draw_prop(img, kind, Vector2i(11, base), wide)
	if level == 5:
		PixelCanvas.draw_flag(img, Vector2i(cx - 1, wall.position.y - rows - 1), 3, Palette.ACCENT)
		PixelCanvas.rect(img, Rect2i(wall.position.x + 5, base - 6, 2, 3), Palette.ACCENT)
		PixelCanvas.px(img, wall.position.x + 5, base - 4, Palette.WOOD[0])  # wcięcie proporca


## Garbarnia, Cięciwiarz, Strzałmistrz, Rymarz i Strzelnica mają ściany z desek, reszta z bali.
static func _plank_walls(kind: int) -> bool:
	return kind in [BuildingTypes.Kind.TANNERY, BuildingTypes.Kind.BOWSTRING, BuildingTypes.Kind.FLETCHER,
			BuildingTypes.Kind.SADDLER, BuildingTypes.Kind.ARCHERY_RANGE]


## Rekwizyt wytwórcy 5 px szerokości, stojący na wierszu `at.y` od kolumny `at.x`.
## `big` to wersja dla poziomów 4–5 (więcej towaru).
static func _draw_prop(img: Image, kind: int, at: Vector2i, big: bool) -> void:
	var x := at.x
	var y := at.y
	match kind:
		BuildingTypes.Kind.HUNTER:
			# rama z rozpiętą skórą
			for px: int in [x, x + 4]:
				PixelCanvas.rect(img, Rect2i(px, y - 6, 1, 7), Palette.WOOD[0])
			PixelCanvas.rect(img, Rect2i(x, y - 6, 5, 1), Palette.WOOD[1])
			for yy in range(y - 5, y - 1):
				for xx in range(x + 1, x + 4):
					PixelCanvas.px(img, xx, yy, PixelCanvas.dither(xx, yy, Palette.EARTH[3], Palette.WOOD[2]))
			if big:
				PixelCanvas.rect(img, Rect2i(x + 1, y - 1, 3, 1), Palette.THATCH[2])  # pióra
		BuildingTypes.Kind.TANNERY:
			# kadź z garbnikiem
			PixelCanvas.rect(img, Rect2i(x, y - 3, 5, 4), Palette.WOOD[0])
			PixelCanvas.rect(img, Rect2i(x + 1, y - 3, 3, 1), Palette.EARTH[1])
			PixelCanvas.rect(img, Rect2i(x, y - 1, 5, 1), Palette.WOOD[2])
			if big:
				PixelCanvas.rect(img, Rect2i(x + 1, y - 6, 3, 3), Palette.EARTH[3])  # skóra na kadzi
		BuildingTypes.Kind.LEATHERWORKER:
			# okrągła tarcza obita skórą z czerwonym umbem
			PixelCanvas.rect(img, Rect2i(x + 1, y - 6, 3, 5), Palette.EARTH[3])
			PixelCanvas.rect(img, Rect2i(x, y - 5, 5, 3), Palette.EARTH[3])
			PixelCanvas.px(img, x + 2, y - 4, Palette.ACCENT)
			PixelCanvas.rect(img, Rect2i(x + 2, y - 1, 1, 2), Palette.WOOD[0])
			if big:
				PixelCanvas.rect(img, Rect2i(x - 1, y - 2, 2, 3), Palette.WOOD[2])  # zbroja na kołku
		BuildingTypes.Kind.POLEARM:
			# drzewca oparte o ścianę, z kamiennymi grotami
			var poles := 5 if big else 3
			for i in poles:
				var px := x + i
				PixelCanvas.rect(img, Rect2i(px, y - 7 + (i % 2), 1, 8 - (i % 2)), Palette.WOOD[3])
				PixelCanvas.px(img, px, y - 8 + (i % 2), Palette.EARTH[3])
		BuildingTypes.Kind.BOWSTRING:
			# sznury cięciw schnące między dwoma kołkami
			for px: int in [x, x + 4]:
				PixelCanvas.rect(img, Rect2i(px, y - 6, 1, 7), Palette.WOOD[0])
			var lines := 4 if big else 2
			for i in lines:
				PixelCanvas.rect(img, Rect2i(x + 1, y - 5 + 2 * i, 3, 1), Palette.THATCH[2])
		BuildingTypes.Kind.BOWYER:
			# łuk z cięciwą (drugi łuk na wyższych poziomach)
			var bows := 2 if big else 1
			for b in bows:
				var bx := x + b  # drugi łuk o 1 px w prawo: cięciwa w kolumnie 15, w obrazie
				PixelCanvas.rect(img, Rect2i(bx + 1, y - 6, 1, 6), Palette.WOOD[2])
				PixelCanvas.px(img, bx + 2, y - 7, Palette.WOOD[2])
				PixelCanvas.px(img, bx + 2, y, Palette.WOOD[2])
				PixelCanvas.rect(img, Rect2i(bx + 3, y - 7, 1, 8), Palette.THATCH[2])
		BuildingTypes.Kind.FLETCHER:
			# beczka strzał z lotkami
			PixelCanvas.rect(img, Rect2i(x, y - 3, 4, 4), Palette.WOOD[1])
			PixelCanvas.rect(img, Rect2i(x, y - 2, 4, 1), Palette.WOOD[0])
			var arrows := 4 if big else 2
			for i in arrows:
				PixelCanvas.rect(img, Rect2i(x + i, y - 6, 1, 3), Palette.WOOD[3])
				PixelCanvas.px(img, x + i, y - 6, Palette.THATCH[2] if i % 2 == 0 else Palette.ACCENT)
		BuildingTypes.Kind.SADDLER:
			# siodło z czaprakiem na koźle
			for px: int in [x, x + 4]:
				PixelCanvas.rect(img, Rect2i(px, y - 2, 1, 3), Palette.WOOD[0])
			PixelCanvas.rect(img, Rect2i(x, y - 3, 5, 1), Palette.WOOD[1])
			PixelCanvas.rect(img, Rect2i(x, y - 5, 5, 2), Palette.EARTH[2])
			PixelCanvas.rect(img, Rect2i(x + 1, y - 4, 3, 1), Palette.ACCENT)
			if big:
				PixelCanvas.rect(img, Rect2i(x + 1, y - 8, 3, 1), Palette.WOOD[2])  # uprząż na kołku
				PixelCanvas.rect(img, Rect2i(x + 1, y - 7, 1, 2), Palette.WOOD[2])
				PixelCanvas.rect(img, Rect2i(x + 3, y - 7, 1, 2), Palette.WOOD[2])
		BuildingTypes.Kind.FISHER:
			# sieć rozpięta na dwóch żerdziach, pod nią ryby (na wyższych poziomach łódka)
			for px: int in [x, x + 4]:
				PixelCanvas.rect(img, Rect2i(px, y - 7, 1, 8), Palette.WOOD[0])
			for yy in range(y - 6, y - 2):
				for xx in range(x + 1, x + 4):
					if (xx + yy) % 2 == 0:
						PixelCanvas.px(img, xx, yy, Palette.THATCH[1])
			PixelCanvas.rect(img, Rect2i(x + 1, y - 1, 2, 1), Palette.WATER[2])
			if big:
				PixelCanvas.rect(img, Rect2i(x - 1, y, 6, 1), Palette.WOOD[1])  # łódka
				PixelCanvas.rect(img, Rect2i(x, y - 1, 1, 1), Palette.WOOD[1])
				PixelCanvas.rect(img, Rect2i(x + 3, y - 1, 1, 1), Palette.WATER[2])
		BuildingTypes.Kind.STABLE:
			# koń przy żłobie z sianem (na wyższych poziomach drugi koń, gniady)
			_draw_horse(img, Vector2i(x, y), Palette.WOOD[2])
			PixelCanvas.rect(img, Rect2i(x - 1, y - 1, 1, 2), Palette.THATCH[1])  # siano
			if big:
				_draw_horse(img, Vector2i(x, y - 4), Palette.WOOD[1])
		BuildingTypes.Kind.BARRACKS:
			# manekin do ćwiczeń: słup z poprzeczką, słomiany tułów i głowa (na wyższych poziomach z tarczą)
			PixelCanvas.rect(img, Rect2i(x + 2, y - 7, 1, 8), Palette.WOOD[0])
			PixelCanvas.rect(img, Rect2i(x, y - 5, 5, 1), Palette.WOOD[1])
			PixelCanvas.rect(img, Rect2i(x + 1, y - 4, 3, 3), Palette.THATCH[2])
			PixelCanvas.rect(img, Rect2i(x + 2, y - 7, 1, 2), Palette.THATCH[1])
			if big:
				PixelCanvas.rect(img, Rect2i(x + 3, y - 4, 2, 3), Palette.EARTH[3])
				PixelCanvas.px(img, x + 4, y - 3, Palette.ACCENT)
		BuildingTypes.Kind.WARBAND_HOUSE:
			# tarcze drużyny w rzędzie na kołkach (na wyższych poziomach dwa rzędy)
			var rows := 2 if big else 1
			for row in rows:
				for i in 2:
					var sx := x + i * 3 - row
					var sy := y - 3 - row * 4
					PixelCanvas.rect(img, Rect2i(sx, sy - 1, 3, 3), Palette.EARTH[3])
					PixelCanvas.px(img, sx + 1, sy, Palette.ACCENT)
			PixelCanvas.rect(img, Rect2i(x, y, 5, 1), Palette.WOOD[0])
		BuildingTypes.Kind.ARCHERY_RANGE:
			# słomiana tarcza strzelnicza z czerwonym środkiem na kozłach (na wyższych poziomach ze strzałą)
			PixelCanvas.rect(img, Rect2i(x + 1, y - 6, 3, 5), Palette.THATCH[2])
			PixelCanvas.rect(img, Rect2i(x, y - 5, 5, 3), Palette.THATCH[2])
			PixelCanvas.rect(img, Rect2i(x + 1, y - 5, 3, 3), Palette.THATCH[1])
			PixelCanvas.px(img, x + 2, y - 4, Palette.ACCENT)
			for lx: int in [x, x + 4]:
				PixelCanvas.rect(img, Rect2i(lx, y - 1, 1, 2), Palette.WOOD[0])
			if big:
				PixelCanvas.rect(img, Rect2i(x + 2, y - 4, 3, 1), Palette.WOOD[3])  # strzała w tarczy
				PixelCanvas.px(img, x + 4, y - 4, Palette.THATCH[0])  # lotka
		BuildingTypes.Kind.SCOUT_HOUSE:
			# czatownia: wysoka żerdź z pomostem i rogiem sygnałowym (na wyższych poziomach z proporcem)
			PixelCanvas.rect(img, Rect2i(x + 2, y - 9, 1, 10), Palette.WOOD[0])
			PixelCanvas.rect(img, Rect2i(x, y - 9, 5, 1), Palette.WOOD[2])
			for lx: int in [x, x + 4]:
				PixelCanvas.px(img, lx, y - 8, Palette.WOOD[1])  # poręcz pomostu
			PixelCanvas.rect(img, Rect2i(x + 3, y - 5, 2, 1), Palette.THATCH[2])  # róg na rzemieniu
			PixelCanvas.px(img, x + 4, y - 6, Palette.THATCH[2])
			PixelCanvas.rect(img, Rect2i(x + 1, y - 1, 3, 2), Palette.WOOD[1])  # siodło na kozłach
			if big:
				PixelCanvas.rect(img, Rect2i(x + 2, y - 12, 1, 3), Palette.WOOD[0])
				PixelCanvas.rect(img, Rect2i(x + 3, y - 12, 2, 2), Palette.ACCENT)
		BuildingTypes.Kind.TAR_KILN:
			# mielerz z otworem i beczką smoły
			PixelCanvas.rect(img, Rect2i(x, y - 3, 5, 4), Palette.EARTH[2])
			PixelCanvas.rect(img, Rect2i(x + 1, y - 4, 3, 1), Palette.EARTH[2])
			PixelCanvas.px(img, x + 2, y - 1, Palette.SHADOW)
			PixelCanvas.px(img, x + 2, y, Palette.SHADOW)
			if big:
				PixelCanvas.rect(img, Rect2i(x + 2, y - 7, 1, 3), Color(Palette.SHADOW, 0.5))  # dym
				PixelCanvas.rect(img, Rect2i(x - 1, y - 2, 2, 3), Palette.SHADOW)  # beczka smoły


## Wieża grodowa (2×2, donżon epoki I, #120): najwyższa budowla zamku i cel każdego ataku.
## Poziomy: 1 wieża z bali na podmurówce z ziemi, 2 wyższa z otworem strzelniczym, 3 z gankiem
## (hurdycją) pod dachem, 4 ze szkieletem belek i drugim rzędem otworów, 5 z flagą i proporcem.
static func _draw_keep(img: Image, level: int) -> void:
	var base := 13 + EXTRA[BuildingTypes.Kind.KEEP]
	PixelCanvas.rect(img, Rect2i(1, base + 1, 14, 1), Color(Palette.SHADOW, 0.5))
	# ziemna podmurówka
	for y in range(base - 1, base + 1):
		for x in range(1, 15):
			PixelCanvas.px(img, x, y, PixelCanvas.dither(x, y, Palette.EARTH[2], Palette.EARTH[1]))
	var wall_h: Array[int] = [14, 18, 18, 22, 22]
	var h := wall_h[level - 1]
	var wall := Rect2i(3, base - 1 - h, 10, h)
	PixelCanvas.draw_log_wall(img, wall, Palette.WOOD, 23)
	PixelCanvas.draw_door(img, Rect2i(6, base - 6, 4, 5))
	if level >= 2:
		PixelCanvas.rect(img, Rect2i(7, wall.position.y + 3, 2, 3), Palette.SHADOW)
	if level >= 4:
		PixelCanvas.draw_beams(img, wall, Palette.WOOD[0])
		for x: int in [4, 10]:
			PixelCanvas.rect(img, Rect2i(x, wall.position.y + 8, 1, 3), Palette.SHADOW)
	var top := wall.position.y
	if level >= 3:
		# ganek z desek wysunięty poza ścianę
		PixelCanvas.draw_plank_wall(img, Rect2i(1, top - 3, 14, 3), Palette.WOOD)
		PixelCanvas.rect(img, Rect2i(1, top, 14, 1), Palette.WOOD[0])
		top -= 3
	PixelCanvas.draw_roof(img, 8, top - 5, 2, 5, Palette.THATCH)
	if level == 5:
		PixelCanvas.draw_flag(img, Vector2i(7, top - 4), 3, Palette.ACCENT)
		PixelCanvas.rect(img, Rect2i(4, wall.position.y + 2, 2, 4), Palette.ACCENT)


## Koń z boku, 5×4 px, stojący na wierszu `at.y` od kolumny `at.x`: tułów, głowa z grzywą
## w prawo i dwie nogi (z boku tylna i przednia para zlewają się w jedną).
static func _draw_horse(img: Image, at: Vector2i, coat: Color) -> void:
	PixelCanvas.rect(img, Rect2i(at.x, at.y - 3, 4, 2), coat)
	PixelCanvas.rect(img, Rect2i(at.x + 4, at.y - 4, 1, 2), coat)
	PixelCanvas.px(img, at.x + 3, at.y - 4, Palette.SHADOW)  # grzywa
	PixelCanvas.px(img, at.x - 1, at.y - 3, Palette.SHADOW)  # ogon
	for lx: int in [0, 3]:
		PixelCanvas.rect(img, Rect2i(at.x + lx, at.y - 1, 1, 2), Palette.WOOD[0])


## Pole lnu (2×2, #122): zaorana ziemia z rzędami lnu. Poziomy: 1 mała grządka z siewkami,
## 2 całe pole w zielonych rzędach, 3 len kwitnie na niebiesko, 4 snopki na skraju pola,
## 5 strach na wróble z czerwoną chustą.
static func _draw_flax_field(img: Image, level: int) -> void:
	var ex := EXTRA[BuildingTypes.Kind.FLAX_FIELD]
	var field := Rect2i(1, ex + 2, 14, 12) if level >= 2 else Rect2i(3, ex + 5, 8, 7)
	for y in range(field.position.y, field.end.y):
		for x in range(field.position.x, field.end.x):
			PixelCanvas.px(img, x, y, PixelCanvas.dither(x, y, Palette.EARTH[2], Palette.EARTH[1]))
	# rzędy roślin co 3 piksele; łodygi sięgają 1–2 px ponad bruzdę
	var stalk := 1 if level == 1 else 2
	for y in range(field.position.y + 1, field.end.y, 3):
		for x in range(field.position.x, field.end.x):
			if (x + y) % 2 != 0:
				continue
			PixelCanvas.rect(img, Rect2i(x, y - stalk + 1, 1, stalk), Palette.GRASS[3])
			if level >= 3 and PixelCanvas.hash2(x, y, 19) % 3 == 0:
				PixelCanvas.px(img, x, y - stalk, Palette.WATER[2])  # niebieski kwiat lnu
	if level >= 4:
		# snopki lnu na skraju pola
		for sx: int in [1, 4]:
			PixelCanvas.rect(img, Rect2i(sx, ex - 2, 2, 5), Palette.THATCH[1])
			PixelCanvas.px(img, sx, ex - 3, Palette.THATCH[2])
			PixelCanvas.rect(img, Rect2i(sx, ex, 2, 1), Palette.THATCH[0])
	if level == 5:
		# strach na wróble
		PixelCanvas.rect(img, Rect2i(12, ex - 6, 1, 10), Palette.WOOD[0])
		PixelCanvas.rect(img, Rect2i(10, ex - 3, 5, 1), Palette.WOOD[1])
		PixelCanvas.rect(img, Rect2i(11, ex - 8, 3, 2), Palette.THATCH[2])
		PixelCanvas.rect(img, Rect2i(11, ex - 6, 3, 2), Palette.ACCENT)


# --- Plac budowy -----------------------------------------------------------------------------

## Plac budowy (poziom 0): ubita ziemia na kratkach budynku, belki fundamentu po obwodzie,
## rusztowanie z dwóch słupów z poprzeczkami i stos bali. Umocnienia dostają ziemię na kształcie
## odcinka i rzadkie paliki, więc plac budowy też łączy się z sąsiadami.
static func _draw_site(img: Image, kind: int, mask: int) -> void:
	var ex: int = EXTRA[kind]
	if BuildingTypes.is_wall(kind):
		var f := wall_shape(mask, wall_thickness(kind))
		for y in CELL:
			for x in CELL:
				if not _on(f, x, y):
					continue
				PixelCanvas.px(img, x, y + ex, PixelCanvas.dither(x, y, Palette.EARTH[2], Palette.EARTH[1]))
				if (x + 2 * y) % 5 == 0:
					PixelCanvas.px(img, x, y + ex - 1, Palette.WOOD[2])
					PixelCanvas.px(img, x, y + ex - 2, Palette.WOOD[3])
		return
	var sz := img.get_size()
	var lot := Rect2i(1, ex + 1, sz.x - 2, sz.y - ex - 2)
	for y in range(lot.position.y, lot.end.y):
		for x in range(lot.position.x, lot.end.x):
			var edge := x == lot.position.x or x == lot.end.x - 1 or y == lot.position.y or y == lot.end.y - 1
			var col := PixelCanvas.dither(x, y, Palette.EARTH[2], Palette.EARTH[1])
			if edge:
				col = Palette.WOOD[1] if (x + y) % 3 != 0 else Palette.WOOD[0]
			PixelCanvas.px(img, x, y, col)
	# rusztowanie: rama z dwóch słupów z tyłu placu, wystająca ponad kratki, z poprzeczkami
	var foot := lot.position.y + 2
	var height := mini(10, foot)
	var left := lot.position.x + 1
	var right := lot.end.x - 2
	for i in height:
		PixelCanvas.px(img, left, foot - i, Palette.WOOD[3])
		PixelCanvas.px(img, right, foot - i, Palette.WOOD[3])
		if i % 3 == 1:
			for x in range(left + 1, right):
				PixelCanvas.px(img, x, foot - i, Palette.WOOD[1])
	if right - left >= 6:
		_log_pile(img, Rect2i(left + 2, lot.end.y - 3, 4, 2))


## Stos drewna od czoła: końce bali 2×2 (jasny słój, ciemna kora).
static func _log_pile(img: Image, r: Rect2i) -> void:
	for y in range(r.position.y, r.end.y):
		for x in range(r.position.x, r.end.x):
			var lx := (x - r.position.x) % 2
			var ly := (y - r.position.y) % 2
			var col: Color = Palette.WOOD[2]
			if lx == 0 and ly == 0:
				col = Palette.THATCH[1]
			elif lx == 1 and ly == 1:
				col = Palette.WOOD[0]
			PixelCanvas.px(img, x, y, col)


# --- Stan ---------------------------------------------------------------------------------

## Cztery stany zniszczeń. Pęknięcia: ciemne rysy z hash2. Wyrwa: pęknięcia plus wyłom
## w sylwetce (w umocnieniach rysuje go już _wall_heights). Gruz: zostaje rumowisko na kratkach
## budynku. Wzór jest deterministyczny, więc ten sam stan zawsze wygląda tak samo.
static func _apply_state(img: Image, kind: int, state: int, mask: int) -> void:
	match state:
		BuildingTypes.State.CRACKED:
			_draw_cracks(img, kind)
		BuildingTypes.State.BREACHED:
			if not BuildingTypes.is_wall(kind):
				_carve_breach(img, kind)
			_draw_cracks(img, kind)
		BuildingTypes.State.RUBBLE:
			if BuildingTypes.is_wall(kind):
				_wall_rubble(img, kind, mask)
			else:
				_building_rubble(img, kind)


static func _opaque(img: Image, x: int, y: int) -> bool:
	return img.get_pixel(x, y).a == 1.0


## Górny nieprzezroczysty piksel kolumny albo -1 dla pustej kolumny.
static func _column_top(img: Image, x: int) -> int:
	for y in img.get_height():
		if _opaque(img, x, y):
			return y
	return -1


## Rysy: od punktu w górnej połowie kolumny w dół, co krok o piksel w bok albo prosto.
## Malują tylko istniejące piksele budynku, więc nie wychodzą poza jego sylwetkę.
static func _draw_cracks(img: Image, kind: int) -> void:
	var sz := img.get_size()
	var wall := BuildingTypes.is_wall(kind)
	var count := 2 if wall else 3
	var length := 3 if wall else 6
	for n in count:
		var x := PixelCanvas.hash2(n, 7, 51 + kind) % sz.x
		var top := -1
		for i in sz.x:
			top = _column_top(img, (x + i) % sz.x)
			if top >= 0:
				x = (x + i) % sz.x
				break
		if top < 0:
			return
		var y := top + 1 + PixelCanvas.hash2(n, 8, 51 + kind) % (2 if wall else 5)
		for step in length:
			if x >= 0 and x < sz.x and y < sz.y and _opaque(img, x, y):
				img.set_pixel(x, y, Palette.SHADOW)
			y += 1
			x += PixelCanvas.hash2(n, step, 53 + kind) % 3 - 1


## Dwa wyłomy w górnej krawędzi budynku (dach, blanki, szczyt słupów): kolumny ścięte o 4–6 px
## z postrzępionym dnem i ciemną krawędzią przełomu. Wyłomy leżą w środkowej części sylwetki
## i nie ścinają więcej niż połowy kolumny.
static func _carve_breach(img: Image, kind: int) -> void:
	var sz := img.get_size()
	var tops := PackedInt32Array()
	var bottoms := PackedInt32Array()
	for x in sz.x:
		var top := _column_top(img, x)
		tops.append(top)
		var bottom := top
		if top >= 0:
			for y in range(sz.y - 1, top - 1, -1):
				if _opaque(img, x, y):
					bottom = y
					break
		bottoms.append(bottom)
	var span := _opaque_span(tops)
	var inner := maxi(1, (span.y - span.x + 1) / 2)
	for n in 2:
		var w := 3 + PixelCanvas.hash2(n, 0, 41 + kind) % 2
		var start := clampi(span.x + inner / 2 - 1 + PixelCanvas.hash2(n, 1, 41 + kind) % inner, 0, sz.x - w)
		var depth := 4 + PixelCanvas.hash2(n, 2, 41 + kind) % 3
		for x in range(start, start + w):
			if tops[x] < 0:
				continue
			var d := mini(depth - PixelCanvas.hash2(x, n, 43 + kind) % 2, (bottoms[x] - tops[x]) / 2)
			for y in range(tops[x], tops[x] + d):
				img.set_pixel(x, y, Color(Palette.SHADOW, 0.0))
			var edge := tops[x] + d
			if d > 0 and _opaque(img, x, edge):
				img.set_pixel(x, edge, Palette.SHADOW)


## Barwy gruzu: ziemia dla wału, drewno z ziemią dla reszty.
static func _rubble_color(kind: int, x: int, y: int) -> Color:
	var h := PixelCanvas.hash2(x, y, 73 + kind)
	if kind == BuildingTypes.Kind.RAMPART:
		var earth: Array[Color] = [Palette.EARTH[0], Palette.EARTH[1], Palette.EARTH[2]]
		return earth[h % earth.size()]
	var debris: Array[Color] = [Palette.WOOD[0], Palette.WOOD[1], Palette.WOOD[2], Palette.EARTH[1], Palette.SHADOW]
	return debris[h % debris.size()]


## Gruz umocnienia: niski kopiec dokładnie na kształcie odcinka, więc rumowisko też się łączy
## z sąsiadami. Z palisady sterczą kikuty pali.
static func _wall_rubble(img: Image, kind: int, mask: int) -> void:
	var ex: int = EXTRA[kind]
	var f := wall_shape(mask, wall_thickness(kind))
	img.fill(Color(Palette.SHADOW, 0.0))
	for y in CELL:
		for x in CELL:
			if not _on(f, x, y):
				continue
			PixelCanvas.px(img, x, y + ex, _rubble_color(kind, x, y))
			var h := PixelCanvas.hash2(x, y, 79 + kind) % 4
			if h == 0:
				PixelCanvas.px(img, x, y + ex - 1, _rubble_color(kind, x, y + 1))
			elif h == 1 and kind == BuildingTypes.Kind.PALISADE and x % 2 == 0:
				PixelCanvas.px(img, x, y + ex - 1, Palette.WOOD[1])
				PixelCanvas.px(img, x, y + ex - 2, Palette.WOOD[0])


## Pierwsza i ostatnia niepusta kolumna (x, y) według wierzchów kolumn.
static func _opaque_span(tops: PackedInt32Array) -> Vector2i:
	var span := Vector2i(-1, -1)
	for x in tops.size():
		if tops[x] >= 0:
			if span.x < 0:
				span.x = x
			span.y = x
	return span


## Gruz budynku wielokratkowego: kopiec rumowiska przy froncie, najwyższy pośrodku, za nim
## rozrzucone szczątki na kratkach budynku i kilka osmalonych kikutów belek. Zajmuje tylko
## kolumny, w których stał budynek.
static func _building_rubble(img: Image, kind: int) -> void:
	var sz := img.get_size()
	var tops := PackedInt32Array()
	for x in sz.x:
		tops.append(_column_top(img, x))
	var span := _opaque_span(tops)
	img.fill(Color(Palette.SHADOW, 0.0))
	var ground: int = EXTRA[kind]
	var front := sz.y - 2
	for x in range(span.x, span.y + 1):
		if tops[x] < 0:
			continue
		var heap := mini(5, 1 + mini(x - span.x, span.y - x) * 2 / 3) + PixelCanvas.hash2(x, 0, 75 + kind) % 2
		var top := front - heap
		for y in range(ground + 1, front + 1):
			if y > top:
				img.set_pixel(x, y, _rubble_color(kind, x, y))
			elif y == top:
				img.set_pixel(x, y, Palette.EARTH[3] if PixelCanvas.hash2(x, y, 76 + kind) % 3 == 0 else Palette.WOOD[2])
			elif PixelCanvas.hash2(x, y, 71 + kind) % 4 == 0:
				img.set_pixel(x, y, _rubble_color(kind, x, y))
		PixelCanvas.px(img, x, front + 1, Color(Palette.SHADOW, 0.5))
	for n in 3:
		var x := span.x + PixelCanvas.hash2(n, 3, 77 + kind) % (span.y - span.x + 1)
		if tops[x] < 0:
			continue
		var base := front - 2 - PixelCanvas.hash2(n, 4, 77 + kind) % 3
		var height := 3 + PixelCanvas.hash2(n, 5, 77 + kind) % 3
		for i in height:
			img.set_pixel(x, base - i, Palette.WOOD[0] if i == height - 1 else Palette.WOOD[1])
