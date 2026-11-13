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
## Ile pikseli budynek wystaje ponad swoje kratki (stałe dla rodzaju, niezależne od poziomu).
const EXTRA: Array[int] = [4, 4, 12, 20, 10]


## Rozmiar obrazu. `vertical` obraca obrys budynku (brama w pionowej linii palisady).
static func image_size(kind: int, vertical: bool = false) -> Vector2i:
	var s := BuildingTypes.size_of(kind) * CELL
	if vertical:
		s = Vector2i(s.y, s.x)
	return Vector2i(s.x, s.y + EXTRA[kind])


## Obraz budynku. `mask` ma znaczenie tylko dla wału i palisady, `vertical` tylko dla bramy.
static func make_image(kind: int, level: int, state: int, mask: int = 0, vertical: bool = false) -> Image:
	var v := vertical and kind == BuildingTypes.Kind.GATE
	var sz := image_size(kind, v)
	var img := Image.create(sz.x, sz.y, false, Image.FORMAT_RGBA8)
	var lv := clampi(level, 1, BuildingTypes.MAX_LEVEL)
	match kind:
		BuildingTypes.Kind.RAMPART:
			_draw_rampart(img, lv, mask)
		BuildingTypes.Kind.PALISADE:
			_draw_palisade(img, lv, mask)
		BuildingTypes.Kind.GATE:
			if v:
				_draw_gate_vertical(img, lv)
			else:
				_draw_gate(img, lv)
		BuildingTypes.Kind.TOWER:
			_draw_tower(img, lv)
		BuildingTypes.Kind.LUMBER_HUT:
			_draw_hut(img, lv)
	_apply_state(img, kind, state)
	return img


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
static func _draw_rampart(img: Image, level: int, mask: int) -> void:
	var t := 4
	var h := 2 if level == 1 else 3
	var ex: int = EXTRA[BuildingTypes.Kind.RAMPART]
	var f := wall_shape(mask, t)
	_wall_ground(img, f, mask, ex, level >= 3)
	for y in CELL:
		for x in CELL:
			if not _on(f, x, y):
				continue
			var top := y + ex - h
			if _has_face(f, mask, x, y):
				for i in range(1, h + 1):
					var dark := ((x >> 1) + ((top + i) >> 1)) % 2 == 0
					PixelCanvas.px(img, x, top + i, Palette.EARTH[1] if dark else Palette.EARTH[2])
			# korona: ziemia albo darń przemieszana z ziemią; w biegu pionowym ciemniejsze zbocza
			var grass := level >= 2
			var a: Color = Palette.GRASS[3] if grass else Palette.EARTH[3]
			var b: Color = Palette.EARTH[3] if grass else Palette.EARTH[2]
			var col: Color = a if ((x >> 1) + (y >> 1)) % 2 == 0 else b
			var lo := (CELL - t) / 2
			if (y < lo or y >= lo + t) and (x == lo or x == lo + t - 1):
				col = Palette.EARTH[2] if x == lo else Palette.EARTH[1]
			PixelCanvas.px(img, x, top, col)
	# blanki: paliki (poziom 4) albo płot (poziom 5) na północnym skraju korony
	if level < 4:
		return
	for y in CELL:
		for x in CELL:
			if not (_on(f, x, y) and _is_crest(f, mask, x, y)):
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
static func _draw_palisade(img: Image, level: int, mask: int) -> void:
	var t := 2
	var h := 4
	var ex: int = EXTRA[BuildingTypes.Kind.PALISADE]
	var f := wall_shape(mask, t)
	var lo := (CELL - t) / 2
	var hi := lo + t
	_wall_ground(img, f, mask, ex, false)
	if level >= 4:
		_wall_mound(img, f, mask, ex)
	for y in CELL:
		for x in CELL:
			if not _on(f, x, y):
				continue
			var top := y + ex - h
			if _has_face(f, mask, x, y):
				for i in range(1, h + 1):
					var col: Color = Palette.WOOD[2] if x % 2 == 0 else Palette.WOOD[1]
					if i == h:
						col = Palette.WOOD[0]
					elif level >= 3 and i == 2:
						col = Palette.SHADOW if level == 5 else Palette.WOOD[0]
					PixelCanvas.px(img, x, top + i, col)
			# wierzch pali: w biegu pionowym pale idą wzdłuż y, w poziomym wzdłuż x
			var vertical := y < lo or y >= hi
			var stake := y if vertical else x
			var top_col: Color = Palette.WOOD[3] if stake % 2 == 0 else Palette.WOOD[2]
			if vertical and x == hi - 1:
				top_col = Palette.WOOD[1]
			PixelCanvas.px(img, x, top, top_col)
	if level < 2:
		return
	for y in CELL:
		for x in CELL:
			if _on(f, x, y) and _is_crest(f, mask, x, y) and x % 2 == 0:
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
						var dark := ((x >> 1) + (row >> 1)) % 2 == 0
						PixelCanvas.px(img, x, row + ex, Palette.EARTH[0] if dark else Palette.SHADOW)
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
					var dark := ((x >> 1) + (row >> 1)) % 2 == 0
					PixelCanvas.px(img, x, row + ex, Palette.EARTH[1] if dark else Palette.EARTH[2])


# --- Budynki wielokratkowe -----------------------------------------------------------------

## Brama drewniana (2×1) w linii palisady. Poziomy: 1 dwa skrzydła między słupami,
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
			PixelCanvas.draw_roof(img, x0 + post_w / 2 + 1, top - 2, 2, 2, Palette.THATCH)
		if level == 5:
			PixelCanvas.rect(img, Rect2i(x0 + (1 if x0 == 0 else 0), top + 3, 2, 4), Palette.ACCENT)
	# nadproże
	if level >= 2:
		var lintel := base - door_h - 1
		PixelCanvas.rect(img, Rect2i(0, lintel, w, 2), Palette.WOOD[0])
		PixelCanvas.rect(img, Rect2i(0, lintel, w, 1), Palette.WOOD[2])
	if level >= 4:
		PixelCanvas.draw_roof(img, w / 2, 0, 10, 4, Palette.THATCH)


## Brama w pionowej linii palisady (1×2), widziana z boku: słup na każdym końcu, między nimi
## zamknięte skrzydła widoczne od góry. Słupy stoją na osi palisady (kolumny 2..5), więc
## pionowe odcinki dochodzą do nich bez szpary. Poziomy jak w bramie poziomej.
static func _draw_gate_vertical(img: Image, level: int) -> void:
	var ex: int = EXTRA[BuildingTypes.Kind.GATE]
	var post_h: Array[int] = [6, 8, 9, 10, 10]
	var ph := post_h[level - 1]
	var door_h := 5 if level == 1 else 6
	PixelCanvas.rect(img, Rect2i(2, 16 + ex - 0, 4, 1), Color(Palette.SHADOW, 0.5))
	# skrzydła od góry: ciemne deski z jasną krawędzią, okucia na poziomie 5
	for g in range(3, 13):
		var top := g + ex - door_h
		PixelCanvas.px(img, 3, top, Palette.WOOD[2] if g % 2 == 0 else Palette.WOOD[1])
		PixelCanvas.px(img, 4, top, Palette.WOOD[0] if g != 7 else Palette.SHADOW)
		if level == 5 and g % 3 == 0:
			PixelCanvas.px(img, 3, top, Palette.SHADOW)
	for g0: int in [0, 13]:
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
			for g in range(3, 13):
				PixelCanvas.px(img, 3, g + ex - ph, Palette.WOOD[2])
				PixelCanvas.px(img, 4, g + ex - ph, Palette.WOOD[0])
	# izba bramna: strzecha nad całą bramą
	if level >= 4:
		var roof_top := ex - ph - 3
		for g in range(-1, 16):
			var y := g + roof_top
			PixelCanvas.px(img, 1, y, Palette.THATCH[0])
			for x in range(2, 6):
				PixelCanvas.px(img, x, y, Palette.THATCH[2] if (x + g) % 3 != 0 else Palette.THATCH[1])
			PixelCanvas.px(img, 6, y, Palette.THATCH[0])
		PixelCanvas.rect(img, Rect2i(1, roof_top + 16, 6, 1), Palette.THATCH[0])


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
			PixelCanvas.draw_flag(img, Vector2i(w / 2 - 1, room_top - roof_rows - 1), 4, Palette.ACCENT)


## Chata drwala (2×2). Poziomy: 1 wiata ze stosem drewna, 2 chata ze strzechą, 3 ze stosem
## bali z boku, 4 z oknem i szkieletem belek, 5 z drugim stosem i flagą.
static func _draw_hut(img: Image, level: int) -> void:
	var base := 13 + EXTRA[BuildingTypes.Kind.LUMBER_HUT]
	PixelCanvas.rect(img, Rect2i(1, base + 1, 14, 1), Color(Palette.SHADOW, 0.5))
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
	PixelCanvas.draw_roof(img, cx, wall.position.y - 7, 2, 7, Palette.THATCH)
	if level >= 3:
		_log_pile(img, Rect2i(12, base - 3, 4, 4))
	if level == 5:
		_log_pile(img, Rect2i(12, base - 5, 4, 2))
		PixelCanvas.draw_flag(img, Vector2i(cx - 1, wall.position.y - 8), 5, Palette.ACCENT)


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

## Uszkodzenia: ciemne dziury i osmalenia z hash2. Zniszczenie: zostaje dolna część
## z rumowiskiem. Wzór jest deterministyczny, więc ten sam stan zawsze wygląda tak samo.
static func _apply_state(img: Image, kind: int, state: int) -> void:
	if state == BuildingTypes.State.INTACT:
		return
	var sz := img.get_size()
	var foot_h := sz.y - EXTRA[kind]
	var keep_row := sz.y - foot_h / 2 - 3
	var rubble_row := sz.y - 4
	for y in sz.y:
		for x in sz.x:
			var h := PixelCanvas.hash2(x, y, 91 + kind) % 7
			if img.get_pixel(x, y).a == 0.0:
				if state == BuildingTypes.State.RUINED and y >= rubble_row and h < 2:
					img.set_pixel(x, y, Palette.EARTH[1] if h == 0 else Palette.WOOD[0])
				continue
			if state == BuildingTypes.State.RUINED and y < keep_row:
				img.set_pixel(x, y, Color(Palette.SHADOW, 0.0))
			elif h == 0:
				img.set_pixel(x, y, Palette.SHADOW)
			elif h == 1:
				img.set_pixel(x, y, Palette.EARTH[1])
