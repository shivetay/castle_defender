class_name BuildingArt
extends RefCounted
## Rysuje budynki epoki I w rzucie z góry: widać dachy, pomosty, korony murów i blanki, a wysokość
## oddaje cień rzucany na południowy wschód (BuildingTextures.shadow). Obraz ma dokładnie rozmiar
## kratek budynku (8 px na kratkę) i rysuje się w rect.position * 8, więc nic nie zasłania sąsiadów.
## Światło pada z lewej góry: połacie od północy i zachodu są jasne, od południa i wschodu ciemne.
##
## Wał i palisada to odcinki 1×1 z autotilingiem: środek plus ramię do każdego sąsiada z maski
## N/E/S/W (16 wariantów). Ramiona dochodzą do krawędzi kratki, więc sąsiednie odcinki
## łączą się bez dziur.
@warning_ignore_start("integer_division")

const CELL := 8
## Krycie cienia rzucanego na trawę (#150).
const SHADOW_ALPHA := 0.3


## Rozmiar obrazu. `vertical` obraca obrys budynku (brama w pionowej linii palisady).
static func image_size(kind: int, vertical: bool = false) -> Vector2i:
	var s := BuildingTypes.size_of(kind) * CELL
	return Vector2i(s.y, s.x) if vertical else s


## Przybudówka przy murze (#149): strona, po której stoi wał albo palisada. Budynek przy murze ma dach
## jednospadowy z kalenicą przy murze, a korpus dochodzi do krawędzi kratek od strony muru.
enum Lean { NONE, NORTH, EAST, SOUTH, WEST }


## Czy rodzaj rysuje się jako przybudówka, gdy przylega do muru: chata drwala i warsztaty (Dwór,
## donżon, wieża, brama, pole lnu, umocnienia i budynki z #35 mają własny kształt).
static func can_lean(kind: int) -> bool:
	return not (BuildingTypes.is_wall(kind) or kind in [
			BuildingTypes.Kind.GATE, BuildingTypes.Kind.TOWER, BuildingTypes.Kind.MANOR, BuildingTypes.Kind.KEEP,
			BuildingTypes.Kind.FLAX_FIELD, BuildingTypes.Kind.WATCHTOWER] or has_own_art(kind))


## Pozostałe budynki MVP (#35), rysowane w MvpBuildingArt.
static func has_own_art(kind: int) -> bool:
	return kind in [BuildingTypes.Kind.DRY_MOAT, BuildingTypes.Kind.MOUND, BuildingTypes.Kind.FARM,
			BuildingTypes.Kind.WELL, BuildingTypes.Kind.QUARRY, BuildingTypes.Kind.SIGNAL_TOWER]


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


static func _lean_dir(lean: int) -> Vector2i:
	match lean:
		Lean.NORTH:
			return Vector2i.UP
		Lean.EAST:
			return Vector2i.RIGHT
		Lean.SOUTH:
			return Vector2i.DOWN
		Lean.WEST:
			return Vector2i.LEFT
	return Vector2i.ZERO


static func make_image(kind: int, level: int, state: int, mask: int = 0, vertical: bool = false,
		lean: int = Lean.NONE) -> Image:
	var v := vertical and kind == BuildingTypes.Kind.GATE
	var sz := image_size(kind, v)
	var img := Image.create(sz.x, sz.y, false, Image.FORMAT_RGBA8)
	if level <= 0:
		_draw_site(img, kind, mask)
		return img
	var lv := clampi(level, 1, BuildingTypes.MAX_LEVEL)
	# epoka II (#34): budynek z poziomu 5 epoki I, a na nim znaki nowej epoki (Dwór ma własny rysunek)
	var age_ii := level > BuildingTypes.MAX_LEVEL
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
			_draw_gate(img, lv, v)
		BuildingTypes.Kind.TOWER:
			_draw_tower(img, lv)
		BuildingTypes.Kind.LUMBER_HUT:
			_draw_hut(img, lv, ln)
		BuildingTypes.Kind.MANOR:
			if age_ii:
				_draw_manor_age_ii(img)
			else:
				_draw_manor(img, lv)
		BuildingTypes.Kind.FLAX_FIELD:
			_draw_flax_field(img, lv)
		BuildingTypes.Kind.KEEP:
			_draw_keep(img, lv)
		BuildingTypes.Kind.WATCHTOWER:
			_draw_watchtower(img)
		BuildingTypes.Kind.DRY_MOAT:
			MvpBuildingArt.draw_dry_moat(img, lv)
		BuildingTypes.Kind.MOUND:
			MvpBuildingArt.draw_mound(img, lv)
		BuildingTypes.Kind.FARM:
			MvpBuildingArt.draw_farm(img, lv)
		BuildingTypes.Kind.WELL:
			MvpBuildingArt.draw_well(img, lv)
		BuildingTypes.Kind.QUARRY:
			MvpBuildingArt.draw_quarry(img, lv)
		BuildingTypes.Kind.SIGNAL_TOWER:
			MvpBuildingArt.draw_signal_tower(img, lv)
		_:
			_draw_workshop(img, kind, lv, ln, mirror)
	if mirror:
		img.flip_x()
		if _mono_roof_when_leaning(kind, lv):
			_relight_mirrored(img)
	if age_ii and kind != BuildingTypes.Kind.MANOR:
		_age_ii_marks(img, kind)
	_apply_state(img, kind, state, mask)
	if has_outline(kind):
		_outline_and_light(img)
	return img


## Czy przy murze budynek dostaje dach jednospadowy (strzecha), który po odbiciu trzeba przyciemnić
## na nowo. Dach czterospadowy gospodarki rysuje się od razu z odwróconym światłem, a pomost wojska
## nie ma jasnej i ciemnej połaci, więc ich nie ruszamy (inaczej stóg wyszedłby płaski).
static func _mono_roof_when_leaning(kind: int, level: int) -> bool:
	if level < 2 or BuildingTypes.is_wall(kind) or kind == BuildingTypes.Kind.LUMBER_HUT:
		return true
	var cat := BuildingTypes.category(kind)
	return cat != BuildingTypes.Category.ECONOMY and cat != BuildingTypes.Category.MILITARY


## Po odbiciu w poziomie jasna połać wypada na wschodzie. Dach jednospadowy przy murze z prawej
## patrzy na zachód, więc jest jasny: zamieniamy odcienie strzechy o stopień w górę.
static func _relight_mirrored(img: Image) -> void:
	var swap := {
		Palette.THATCH[1].to_rgba32(): Palette.THATCH[2],
		Palette.THATCH[0].to_rgba32(): Palette.THATCH[1],
	}
	for y in img.get_height():
		for x in img.get_width():
			var c := img.get_pixel(x, y)
			if c.a == 1.0 and swap.has(c.to_rgba32()):
				img.set_pixel(x, y, swap[c.to_rgba32()])


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


## Jak _on, ale poza kratką patrzy na ramię sąsiada: odcinek ciągnie się dalej, gdy maska ma
## sąsiada w tę stronę (ramię sąsiada ma ten sam przekrój).
static func _on_line(f: PackedByteArray, mask: int, t: int, x: int, y: int) -> bool:
	var lo := (CELL - t) / 2
	var hi := lo + t
	if y < 0:
		return mask & BuildingTypes.N != 0 and x >= lo and x < hi
	if y >= CELL:
		return mask & BuildingTypes.S != 0 and x >= lo and x < hi
	if x < 0:
		return mask & BuildingTypes.W != 0 and y >= lo and y < hi
	if x >= CELL:
		return mask & BuildingTypes.E != 0 and y >= lo and y < hi
	return f[y * CELL + x] == 1


## Strona piksela umocnienia względem światła: -1 brzeg od północy albo zachodu (jasny),
## 1 brzeg od południa albo wschodu (w cieniu), 0 środek korony.
static func _edge(f: PackedByteArray, mask: int, t: int, x: int, y: int) -> int:
	if not _on_line(f, mask, t, x, y - 1) or not _on_line(f, mask, t, x - 1, y):
		return -1
	if not _on_line(f, mask, t, x, y + 1) or not _on_line(f, mask, t, x + 1, y):
		return 1
	return 0


## Grubość odcinka umocnienia na ziemi w pikselach.
static func wall_thickness(kind: int) -> int:
	return 4 if kind == BuildingTypes.Kind.RAMPART else 2


## Czy piksel leży w wyrwie: bloki 2×2 wybrane przez hash2, blok w środku kratki pęka zawsze,
## więc wyrwa jest widoczna w każdym wariancie autotilingu. Wzór zależy tylko od położenia w kratce.
static func _breached(kind: int, x: int, y: int) -> bool:
	var bx := x >> 1
	var by := y >> 1
	return (bx == 2 and by == 2) or (bx == 1 and by == 1) or PixelCanvas.hash2(bx, by, 17 + kind) % 3 == 0


## Piksel wyrwy: połowa pikseli bloku znika (widać ziemię pod spodem), reszta to ciemne szczątki.
static func _breach_pixel(img: Image, kind: int, x: int, y: int) -> void:
	if (x + y) % 2 == 0:
		img.set_pixel(x, y, Color(Palette.SHADOW, 0.0))
	else:
		img.set_pixel(x, y, Palette.EARTH[0] if kind == BuildingTypes.Kind.RAMPART else Palette.WOOD[0])


## Wał ziemny z góry: nasyp z jasnym zboczem od północy i zachodu, ciemnym od południa i wschodu.
## Poziomy: 1 goła ziemia, 2 darń na koronie, 3 z suchą fosą wokół, 4 z palikami na koronie,
## 5 z płotem na koronie.
static func _draw_rampart(img: Image, level: int, mask: int, state: int) -> void:
	var kind := BuildingTypes.Kind.RAMPART
	var t := wall_thickness(kind)
	var f := wall_shape(mask, t)
	if level >= 3:
		# sucha fosa: piksel ziemi stykający się z wałem (także z ramieniem sąsiada)
		for y in CELL:
			for x in CELL:
				if _on(f, x, y):
					continue
				if _on_line(f, mask, t, x, y - 1) or _on_line(f, mask, t, x, y + 1) \
						or _on_line(f, mask, t, x - 1, y) or _on_line(f, mask, t, x + 1, y):
					PixelCanvas.px(img, x, y, PixelCanvas.dither(x, y, Palette.EARTH[0], Palette.SHADOW))
	var grass := level >= 2
	for y in CELL:
		for x in CELL:
			if not _on(f, x, y):
				continue
			var e := _edge(f, mask, t, x, y)
			var col: Color
			if e < 0:
				col = Palette.GRASS[3] if grass else Palette.EARTH[3]
			elif e > 0:
				col = Palette.EARTH[1]
			else:
				col = PixelCanvas.dither(x, y, Palette.GRASS[2], Palette.GRASS[3]) if grass \
						else PixelCanvas.dither(x, y, Palette.EARTH[3], Palette.EARTH[2])
				if level == 4 and (x + y) % 3 == 0:
					col = Palette.WOOD[2]  # paliki na koronie
				elif level == 5:
					col = Palette.WOOD[3] if (x + y) % 3 == 0 else Palette.WOOD[1]  # płot
			PixelCanvas.px(img, x, y, col)
			if state == BuildingTypes.State.BREACHED and _breached(kind, x, y):
				_breach_pixel(img, kind, x, y)


## Palisada z góry: wierzchy pali 2 px grubości, jasna strona od północy albo zachodu.
## Poziomy: 1 płaskie pale, 2 zaostrzone (jasne szpice), 3 z belką spinającą od wewnątrz,
## 4 na ziemnym podsypaniu, 5 z żelaznymi obręczami.
static func _draw_palisade(img: Image, level: int, mask: int, state: int) -> void:
	var kind := BuildingTypes.Kind.PALISADE
	var t := wall_thickness(kind)
	var f := wall_shape(mask, t)
	if level >= 3:
		for y in CELL:
			for x in CELL:
				if _on(f, x, y):
					continue
				var behind := _on_line(f, mask, t, x, y - 1) or _on_line(f, mask, t, x - 1, y)
				var front := _on_line(f, mask, t, x, y + 1) or _on_line(f, mask, t, x + 1, y)
				if level >= 4 and (behind or front):
					PixelCanvas.px(img, x, y, PixelCanvas.dither(x, y, Palette.EARTH[2], Palette.EARTH[1]))
				if behind:
					PixelCanvas.px(img, x, y, Palette.WOOD[0])  # belka spinająca po stronie cienia
	for y in CELL:
		for x in CELL:
			if not _on(f, x, y):
				continue
			var stake := (x + y) % 2
			var lit := _edge(f, mask, t, x, y) < 0
			var col: Color
			if lit:
				col = Palette.WOOD[2] if stake == 0 else Palette.WOOD[1]
				if level >= 2 and stake == 0:
					col = Palette.WOOD[3]  # szpic
			else:
				col = Palette.WOOD[1] if stake == 0 else Palette.WOOD[0]
				if level == 5 and (x + y) % 4 == 1:
					col = Palette.SHADOW  # obręcz
			PixelCanvas.px(img, x, y, col)
			if state == BuildingTypes.State.BREACHED and _breached(kind, x, y):
				_breach_pixel(img, kind, x, y)


# --- Budynki wielokratkowe -----------------------------------------------------------------

## Punkt bramy we współrzędnych (wzdłuż, w poprzek): brama pozioma rysuje się wprost,
## pionowa z zamienionymi osiami. Strona „w poprzek = 0” jest zawsze od północy albo zachodu,
## więc światło pada tak samo w obu ułożeniach.
static func _gate_px(img: Image, vertical: bool, a: int, b: int, col: Color) -> void:
	if vertical:
		PixelCanvas.px(img, b, a, col)
	else:
		PixelCanvas.px(img, a, b, col)


static func _gate_rect(vertical: bool, a: int, b: int, la: int, lb: int) -> Rect2i:
	return Rect2i(b, a, lb, la) if vertical else Rect2i(a, b, la, lb)


## Brama drewniana (3×1) w linii palisady, z góry. Poziomy: 1 dwa słupy i zamknięte skrzydła,
## 2 z pomostem nad przejazdem, 3 z daszkami na słupach, 4 z izbą bramną pod strzechą,
## 5 ze sztandarami na słupach i okuciami na okapie.
static func _draw_gate(img: Image, level: int, vertical: bool) -> void:
	var length := 3 * CELL
	var post := 3 if level >= 3 else 2
	# skrzydła: deski w poprzek linii, szpara pośrodku
	for a in range(post, length - post):
		for b in range(3, 5):
			var col: Color = Palette.WOOD[2] if b == 3 else Palette.WOOD[1]
			if a == length / 2 or a == length / 2 - 1:
				col = Palette.SHADOW if a == length / 2 else Palette.WOOD[0]
			_gate_px(img, vertical, a, b, col)
	if level >= 2:
		# pomost nad przejazdem: deski wzdłuż bramy
		for a in range(post, length - post):
			for b in range(2, 6):
				var col: Color = Palette.WOOD[3] if b % 2 == 0 else Palette.WOOD[2]
				if b == 5:
					col = Palette.WOOD[0]
				_gate_px(img, vertical, a, b, col)
	# słupy z góry: kwadrat z jasnym rogiem
	for a0: int in [0, length - post]:
		for a in range(a0, a0 + post):
			var b0 := 3 - (post - 2)
			for b in range(b0, 5):
				var col: Color = Palette.WOOD[1]
				if a == a0 or b == b0:
					col = Palette.WOOD[3]
				_gate_px(img, vertical, a, b, col)
		if level == 3:
			var r := _gate_rect(vertical, a0, 2, post, 4)
			PixelCanvas.roof_hip(img, r, Palette.THATCH, Palette.WOOD[1])
	if level >= 4:
		var roof := _gate_rect(vertical, 1, 0, length - 2, CELL)
		PixelCanvas.roof_gable(img, roof, not vertical, Palette.THATCH, Palette.WOOD[1], 7)
	if level == 5:
		for a0: int in [0, length - 2]:
			var r := _gate_rect(vertical, a0, 1, 2, 3)
			PixelCanvas.rect(img, r, Palette.ACCENT)
		for a in range(3, length - 3, 3):
			_gate_px(img, vertical, a, CELL - 1, Palette.SHADOW)


## Wieża drewniana (2×2) z góry. Poziomy: 1 pomost z desek na czterech nogach, 2 z balustradą,
## 3 z obudową z bali wokół pomostu, 4 pod dachem namiotowym, 5 pod wyższym dachem z flagą.
static func _draw_tower(img: Image, level: int) -> void:
	var w := img.get_width()
	if level >= 3:
		# obudowa z bali: pierścień 2 px z czołami bali na rogach
		PixelCanvas.rect(img, Rect2i(1, 1, w - 2, w - 2), Palette.WOOD[1])
		PixelCanvas.rect(img, Rect2i(1, 1, w - 2, 1), Palette.WOOD[2])
		PixelCanvas.rect(img, Rect2i(1, 1, 1, w - 2), Palette.WOOD[2])
		for c: Vector2i in [Vector2i(1, 1), Vector2i(w - 3, 1), Vector2i(1, w - 3), Vector2i(w - 3, w - 3)]:
			PixelCanvas.rect(img, Rect2i(c, Vector2i(2, 2)), Palette.THATCH[1])
	PixelCanvas.deck(img, Rect2i(3, 3, w - 6, w - 6), true, Palette.WOOD, 3)
	if level <= 2:
		# nogi wystające spod pomostu na rogach
		for c: Vector2i in [Vector2i(2, 2), Vector2i(w - 4, 2), Vector2i(2, w - 4), Vector2i(w - 4, w - 4)]:
			PixelCanvas.rect(img, Rect2i(c, Vector2i(2, 2)), Palette.WOOD[0])
	if level == 2:
		PixelCanvas.frame(img, Rect2i(3, 3, w - 6, w - 6), Palette.WOOD[1])
		for c: Vector2i in [Vector2i(3, 3), Vector2i(w - 4, 3), Vector2i(3, w - 4), Vector2i(w - 4, w - 4)]:
			PixelCanvas.px(img, c.x, c.y, Palette.WOOD[3])
	if level == 3:
		PixelCanvas.px(img, w / 2, w / 2, Palette.SHADOW)  # właz na pomost
	if level >= 4:
		var inset := 2 if level == 4 else 1
		PixelCanvas.roof_hip(img, Rect2i(inset, inset, w - 2 * inset, w - 2 * inset), Palette.THATCH, Palette.WOOD[1])
	if level == 5:
		PixelCanvas.pennant(img, Vector2i(w / 2, w / 2 - 2), Palette.ACCENT)


## Korpus chaty albo warsztatu: zwykle z odstępem od krawędzi, przy murze dochodzi do jego boku.
static func _body(r: Rect2i, lean: int, size: Vector2i) -> Rect2i:
	match lean:
		Lean.WEST:
			return Rect2i(0, r.position.y, r.end.x, r.size.y)
		Lean.NORTH:
			return Rect2i(r.position.x, 0, r.size.x, r.end.y)
		Lean.SOUTH:
			return Rect2i(r.position.x, r.position.y, r.size.x, size.y - r.position.y)
	return r


## Dach korpusu: dwuspadowy z kalenicą wzdłuż dłuższego boku albo jednospadowy przy murze.
static func _roof(img: Image, body: Rect2i, lean: int, tex_seed: int) -> void:
	if lean == Lean.NONE:
		PixelCanvas.roof_gable(img, body, body.size.x >= body.size.y, Palette.THATCH, Palette.WOOD[0], tex_seed)
	else:
		PixelCanvas.roof_mono(img, body, _lean_dir(lean), Palette.THATCH, Palette.WOOD[0], tex_seed)


## Wiata (poziom 1) z góry: daszek z desek, przy murze oparty o niego.
static func _shed(img: Image, r: Rect2i, lean: int, size: Vector2i) -> void:
	var body := _body(r, lean, size)
	PixelCanvas.deck(img, body, body.size.x < body.size.y, Palette.WOOD, 11)
	PixelCanvas.rect(img, Rect2i(body.position.x, body.end.y - 1, body.size.x, 1), Palette.WOOD[0])


## Komin na dachu: w prawej trzeciej części korpusu, tuż pod kalenicą od strony cienia.
static func chimney_at(body: Rect2i) -> Vector2i:
	return Vector2i(body.position.x + body.size.x * 2 / 3, body.position.y + body.size.y / 2 + 1)


## Chata drwala (2×2). Poziomy: 1 wiata ze stosem bali, 2 chata pod strzechą, 3 ze stosem bali
## z boku, 4 większa z kominem, 5 z drugim stosem i proporcem.
static func _draw_hut(img: Image, level: int, lean: int = Lean.NONE) -> void:
	var size := img.get_size()
	if level == 1:
		_shed(img, Rect2i(1, 1, 11, 6), lean, size)
		PixelCanvas.log_pile(img, Rect2i(3, 8, 7, 4))
		PixelCanvas.rect(img, Rect2i(12, 12, 2, 2), Palette.WOOD[2])  # pieniek
		PixelCanvas.px(img, 12, 12, Palette.THATCH[1])
		return
	var body := _body(Rect2i(1, 2, 10, 9) if level < 4 else Rect2i(1, 1, 11, 10), lean, size)
	_roof(img, body, lean, 3)
	if level >= 4:
		PixelCanvas.chimney(img, chimney_at(body))
	if level >= 3:
		PixelCanvas.log_pile(img, Rect2i(12, 2, 4, 8))
	if level == 5:
		PixelCanvas.log_pile(img, Rect2i(2, 13, 8, 2))
		PixelCanvas.pennant(img, Vector2i(body.position.x + 1, body.position.y + 1), Palette.ACCENT)


## Dwór (2×2), siedziba władcy i poziom zamku. Poziomy: 1 izba pod strzechą, 2 z kominem,
## 3 większy, 4 z daszkiem nad wejściem od południa, 5 z flagą i tarczami pod okapem.
static func _draw_manor(img: Image, level: int) -> void:
	var body := Rect2i(2, 2, 12, 9) if level < 3 else Rect2i(1, 1, 14, 11)
	PixelCanvas.roof_gable(img, body, true, Palette.THATCH, Palette.WOOD[0], 13)
	if level >= 2:
		PixelCanvas.chimney(img, chimney_at(body))
	if level >= 4:
		PixelCanvas.roof_gable(img, Rect2i(6, body.end.y, 4, 3), false, Palette.THATCH, Palette.WOOD[1], 14)
	if level == 5:
		PixelCanvas.pennant(img, Vector2i(body.position.x + 1, body.position.y + body.size.y / 2), Palette.ACCENT)
		for x: int in [3, 11]:
			PixelCanvas.rect(img, Rect2i(x, body.end.y, 2, 2), Palette.ACCENT)


## Dwór epoki II (#34) po przebudowie: dach z gontu na kamiennej podmurówce, daszek nad wejściem,
## dwa błękitne proporce na kalenicy i tarcze pana na kopcu pod okapem.
static func _draw_manor_age_ii(img: Image) -> void:
	var body := Rect2i(1, 1, 14, 10)
	PixelCanvas.roof_gable(img, body, true, Palette.SHINGLE, Palette.WOOD[0], 15)
	PixelCanvas.chimney(img, chimney_at(body))
	for x in range(body.position.x, body.end.x):
		for y in range(body.end.y, body.end.y + 2):
			PixelCanvas.px(img, x, y, Palette.STONE[2] if (x + y * 3) % 4 == 0 else Palette.STONE[1])
		PixelCanvas.px(img, x, body.end.y + 1, Palette.STONE[0] if x % 3 == 0 else Palette.STONE[1])
	PixelCanvas.roof_gable(img, Rect2i(6, body.end.y, 4, 3), false, Palette.SHINGLE, Palette.WOOD[1], 16)
	@warning_ignore("integer_division")
	var ridge_y := body.position.y + body.size.y / 2
	PixelCanvas.pennant(img, Vector2i(body.position.x + 1, ridge_y), Palette.AGE_II_ACCENT)
	PixelCanvas.pennant(img, Vector2i(body.end.x - 5, ridge_y), Palette.AGE_II_ACCENT)
	for x: int in [3, 11]:
		PixelCanvas.rect(img, Rect2i(x, body.end.y, 2, 2), Palette.AGE_II_ACCENT)


## Znaki epoki II (#34) na budynku z poziomu 5: kamienna podmurówka pod sylwetką budynków z obrysem
## (dolny piksel każdej kolumny) i błękitny proporzec na wieży. Wał, palisada, brama i fosa łączą się
## z sąsiadami, więc zostają bez zmian.
static func _age_ii_marks(img: Image, kind: int) -> void:
	if kind == BuildingTypes.Kind.TOWER or kind == BuildingTypes.Kind.KEEP:
		PixelCanvas.pennant(img, Vector2i(2, 1), Palette.AGE_II_ACCENT)
		return
	if not has_outline(kind):
		return
	for x in img.get_width():
		for y in range(img.get_height() - 1, -1, -1):
			if _opaque(img, x, y):
				PixelCanvas.px(img, x, y, Palette.STONE[0] if x % 3 == 0 else Palette.STONE[1])
				break


# --- Wytwórcy (#90) ---------------------------------------------------------------------------

## Warsztat (2×2). Szkielet wspólny, dach wg kategorii w panelu budowy (czytelność z dystansu):
## wytwórcy — strzecha dwuspadowa, wojsko — płaski pomost z desek, gospodarka — dach namiotowy.
## Rozpoznanie rodzaju zostaje w rekwizycie z prawej (_draw_prop, bez zmian).
## Poziomy: 1 wiata z rekwizytem, 2 izba pod dachem kategorii, 3 większa z kominem,
## 4 najszersza z większym rekwizytem, 5 z proporcem w rogu dachu i drugim przy wejściu.
## `mirrored`: obraz zostanie odbity w poziomie (przybudówka przy murze z prawej).
static func _draw_workshop(img: Image, kind: int, level: int, lean: int = Lean.NONE,
		mirrored: bool = false) -> void:
	var size := img.get_size()
	if level == 1:
		_shed(img, Rect2i(1, 1, 10, 7), lean, size)
		_draw_prop(img, kind, Vector2i(11, 3), false)
		return
	var wide := level >= 4
	var r := Rect2i(1, 2, 10, 9)
	if level == 3:
		r = Rect2i(1, 1, 10, 10)
	elif wide:
		r = Rect2i(0, 1, 11, 11)
	var body := _body(r, lean, size)
	_workshop_roof(img, body, lean, kind, mirrored)
	if level >= 3:
		PixelCanvas.chimney(img, chimney_at(body))
	_draw_prop(img, kind, Vector2i(11, 3), wide)
	if level == 5:
		PixelCanvas.pennant(img, Vector2i(body.position.x + 1, body.position.y + 1), Palette.ACCENT)
		PixelCanvas.rect(img, Rect2i(body.position.x + 4, body.end.y, 2, 2), Palette.ACCENT)


## Dach warsztatu wg kategorii: strzecha dwuspadowa (wytwórcy), pomost z desek w ramie z belek (wojsko),
## stóg czterospadowy (gospodarka). Przy murze wytwórcy dostają dach jednospadowy; wojsko i gospodarka
## trzymają swoją bryłę, a korpus i tak dochodzi do muru (_body).
static func _workshop_roof(img: Image, body: Rect2i, lean: int, kind: int, mirrored: bool) -> void:
	match BuildingTypes.category(kind):
		BuildingTypes.Category.MILITARY:
			# płaski pomost: deski w poziomie, ciemna rama z belek odróżnia go od wiaty z poziomu 1
			PixelCanvas.deck(img, body, true, Palette.WOOD, 17 + kind)
			_deck_frame(img, body, lean)
		BuildingTypes.Category.ECONOMY:
			PixelCanvas.roof_hipped(img, body, Palette.THATCH, Palette.WOOD[0], 17 + kind, mirrored)
		_:
			_roof(img, body, lean, 17 + kind)


## Rama z belek wokół pomostu wojska. Przy murze bok od muru zostaje bez belki: deski przechodzą
## w koronę muru, więc przybudówka różni się od wolnostojącej także wtedy, gdy ma ten sam obrys.
static func _deck_frame(img: Image, body: Rect2i, lean: int) -> void:
	var col: Color = Palette.WOOD[0]
	if lean != Lean.NORTH:
		PixelCanvas.rect(img, Rect2i(body.position, Vector2i(body.size.x, 1)), col)
	if lean != Lean.SOUTH:
		PixelCanvas.rect(img, Rect2i(body.position.x, body.end.y - 1, body.size.x, 1), col)
	if lean != Lean.WEST:
		PixelCanvas.rect(img, Rect2i(body.position, Vector2i(1, body.size.y)), col)
	PixelCanvas.rect(img, Rect2i(body.end.x - 1, body.position.y, 1, body.size.y), col)


## Rekwizyt wytwórcy z góry, 5 px szerokości, od lewego górnego rogu `at`.
## `big` to wersja dla poziomów 4–5 (więcej towaru).
static func _draw_prop(img: Image, kind: int, at: Vector2i, big: bool) -> void:
	var x := at.x
	var y := at.y
	match kind:
		BuildingTypes.Kind.HUNTER:
			# rama z rozpiętą skórą
			PixelCanvas.rect(img, Rect2i(x, y, 5, 6), Palette.WOOD[0])
			for yy in range(y + 1, y + 5):
				for xx in range(x + 1, x + 4):
					PixelCanvas.px(img, xx, yy, PixelCanvas.dither(xx, yy, Palette.EARTH[3], Palette.WOOD[2]))
			if big:
				PixelCanvas.rect(img, Rect2i(x + 1, y + 7, 3, 2), Palette.THATCH[2])  # pióra
		BuildingTypes.Kind.TANNERY:
			# okrągła kadź z garbnikiem
			_ring(img, Rect2i(x, y, 5, 5), Palette.WOOD[0], Palette.EARTH[1])
			if big:
				_ring(img, Rect2i(x, y + 6, 5, 5), Palette.WOOD[0], Palette.EARTH[3])
		BuildingTypes.Kind.LEATHERWORKER:
			# okrągła tarcza obita skórą z czerwonym umbem
			_ring(img, Rect2i(x, y, 5, 5), Palette.EARTH[2], Palette.EARTH[3])
			PixelCanvas.px(img, x + 2, y + 2, Palette.ACCENT)
			if big:
				PixelCanvas.rect(img, Rect2i(x + 1, y + 6, 3, 4), Palette.WOOD[2])  # zbroja na kozłach
		BuildingTypes.Kind.POLEARM:
			# drzewca złożone na kozłach, z kamiennymi grotami
			var poles := 5 if big else 3
			for i in poles:
				PixelCanvas.rect(img, Rect2i(x + i, y + 1, 1, 8), Palette.WOOD[3])
				PixelCanvas.px(img, x + i, y, Palette.EARTH[3])
			PixelCanvas.rect(img, Rect2i(x, y + 4, 5, 1), Palette.WOOD[0])
		BuildingTypes.Kind.BOWSTRING:
			# cięciwy schnące między dwoma kołkami
			PixelCanvas.rect(img, Rect2i(x, y, 1, 7), Palette.WOOD[0])
			PixelCanvas.rect(img, Rect2i(x + 4, y, 1, 7), Palette.WOOD[0])
			var lines := 4 if big else 2
			for i in lines:
				PixelCanvas.rect(img, Rect2i(x + 1, y + 1 + 2 * i, 3, 1), Palette.THATCH[2])
		BuildingTypes.Kind.BOWYER:
			# łuk z cięciwą leżący na ziemi (drugi łuk na wyższych poziomach)
			var bows := 2 if big else 1
			for b in bows:
				var bx := x + b * 2
				PixelCanvas.rect(img, Rect2i(bx + 1, y + 1, 1, 6), Palette.WOOD[2])
				PixelCanvas.px(img, bx + 2, y, Palette.WOOD[2])
				PixelCanvas.px(img, bx + 2, y + 7, Palette.WOOD[2])
				PixelCanvas.rect(img, Rect2i(bx + 2, y + 1, 1, 6), Palette.THATCH[2])
		BuildingTypes.Kind.FLETCHER:
			# beczka strzał z lotkami
			_ring(img, Rect2i(x, y, 5, 5), Palette.WOOD[1], Palette.WOOD[0])
			var arrows := 4 if big else 2
			for i in arrows:
				PixelCanvas.px(img, x + 1 + i % 3, y + 1 + i / 3 + i % 2, Palette.THATCH[2] if i % 2 == 0 else Palette.ACCENT)
		BuildingTypes.Kind.SADDLER:
			# siodło z czaprakiem na koźle
			PixelCanvas.rect(img, Rect2i(x, y + 2, 5, 1), Palette.WOOD[1])
			PixelCanvas.rect(img, Rect2i(x + 1, y, 3, 5), Palette.EARTH[2])
			PixelCanvas.rect(img, Rect2i(x + 1, y + 2, 3, 1), Palette.ACCENT)
			if big:
				PixelCanvas.rect(img, Rect2i(x + 1, y + 7, 3, 1), Palette.WOOD[2])  # uprząż
				PixelCanvas.rect(img, Rect2i(x + 1, y + 7, 1, 3), Palette.WOOD[2])
		BuildingTypes.Kind.FISHER:
			# sieć rozpięta na żerdziach, obok ryby (na wyższych poziomach łódka)
			for yy in range(y, y + 5):
				for xx in range(x, x + 5):
					if (xx + yy) % 2 == 0:
						PixelCanvas.px(img, xx, yy, Palette.THATCH[1])
			PixelCanvas.rect(img, Rect2i(x + 1, y + 6, 2, 1), Palette.WATER[2])
			if big:
				PixelCanvas.rect(img, Rect2i(x + 1, y + 8, 3, 3), Palette.WOOD[1])  # łódka
				PixelCanvas.px(img, x + 2, y + 9, Palette.WOOD[0])
		BuildingTypes.Kind.STABLE:
			# koń z góry przy żłobie z sianem (na wyższych poziomach drugi, gniady)
			_draw_horse(img, Vector2i(x + 1, y + 1), Palette.WOOD[2])
			PixelCanvas.rect(img, Rect2i(x, y, 3, 1), Palette.THATCH[1])  # żłób z sianem
			if big:
				_draw_horse(img, Vector2i(x + 3, y + 2), Palette.WOOD[1])
		BuildingTypes.Kind.BARRACKS:
			# manekin z góry: słup z poprzeczką i słomiana głowa (na wyższych poziomach z tarczą)
			PixelCanvas.rect(img, Rect2i(x, y + 2, 5, 1), Palette.WOOD[1])
			PixelCanvas.rect(img, Rect2i(x + 1, y + 1, 3, 3), Palette.THATCH[2])
			PixelCanvas.px(img, x + 2, y + 2, Palette.THATCH[1])
			if big:
				_ring(img, Rect2i(x + 1, y + 5, 3, 3), Palette.EARTH[3], Palette.EARTH[3])
				PixelCanvas.px(img, x + 2, y + 6, Palette.ACCENT)
		BuildingTypes.Kind.WARBAND_HOUSE:
			# tarcze drużyny w rzędzie (na wyższych poziomach dwa rzędy)
			var rows := 2 if big else 1
			for row in rows:
				for i in 2:
					var sx := x + i * 3 - (1 if i == 1 else 0)
					var sy := y + row * 4
					PixelCanvas.rect(img, Rect2i(sx, sy, 3, 3), Palette.EARTH[3])
					PixelCanvas.px(img, sx + 1, sy + 1, Palette.ACCENT)
		BuildingTypes.Kind.ARCHERY_RANGE:
			# słomiana tarcza strzelnicza z czerwonym środkiem (na wyższych poziomach ze strzałą)
			_ring(img, Rect2i(x, y, 5, 5), Palette.THATCH[2], Palette.THATCH[1])
			PixelCanvas.px(img, x + 2, y + 2, Palette.ACCENT)
			if big:
				PixelCanvas.rect(img, Rect2i(x + 2, y + 5, 1, 4), Palette.WOOD[3])  # strzała
				PixelCanvas.px(img, x + 2, y + 9, Palette.THATCH[0])  # lotka
		BuildingTypes.Kind.SCOUT_HOUSE:
			# czatownia na żerdzi: pomost z rogiem sygnałowym (na wyższych poziomach z proporcem)
			PixelCanvas.rect(img, Rect2i(x, y, 5, 5), Palette.WOOD[2])
			PixelCanvas.rect(img, Rect2i(x + 1, y + 1, 3, 3), Palette.WOOD[3])
			PixelCanvas.px(img, x + 2, y + 2, Palette.WOOD[0])  # żerdź
			PixelCanvas.rect(img, Rect2i(x + 1, y + 6, 3, 1), Palette.THATCH[2])  # róg
			if big:
				PixelCanvas.pennant(img, Vector2i(x, y + 8), Palette.ACCENT)
		BuildingTypes.Kind.SEAL_HOUSE:
			# plan umocnień na stole: obrys pierścienia z luką na czerwono (#199)
			PixelCanvas.rect(img, Rect2i(x, y, 5, 5), Palette.WOOD[1])
			PixelCanvas.frame(img, Rect2i(x + 1, y + 1, 3, 3), Palette.WOOD[3])
			PixelCanvas.px(img, x + 2, y + 1, Palette.ACCENT)  # luka
			if big:
				PixelCanvas.rect(img, Rect2i(x + 1, y + 6, 3, 1), Palette.WOOD[0])  # linijka
				PixelCanvas.px(img, x + 4, y + 7, Palette.ACCENT)
		BuildingTypes.Kind.WAREHOUSE:
			# skrzynia z okuciem i worek zboża (na wyższych poziomach druga skrzynia i beczka)
			PixelCanvas.rect(img, Rect2i(x, y, 5, 4), Palette.WOOD[1])
			PixelCanvas.rect(img, Rect2i(x, y + 1, 5, 1), Palette.WOOD[0])  # okucie
			PixelCanvas.rect(img, Rect2i(x + 1, y + 5, 3, 2), Palette.THATCH[2])  # worek
			PixelCanvas.px(img, x + 2, y + 5, Palette.THATCH[0])  # związany wylot
			if big:
				PixelCanvas.rect(img, Rect2i(x, y + 8, 3, 3), Palette.WOOD[2])
				_ring(img, Rect2i(x + 3, y + 8, 2, 3), Palette.WOOD[0], Palette.WOOD[1])
		BuildingTypes.Kind.TAR_KILN:
			# mielerz z dymnikiem i beczka smoły
			_ring(img, Rect2i(x, y, 5, 5), Palette.EARTH[1], Palette.EARTH[2])
			PixelCanvas.px(img, x + 2, y + 2, Palette.SHADOW)
			if big:
				_ring(img, Rect2i(x + 1, y + 6, 3, 3), Palette.WOOD[0], Palette.SHADOW)  # beczka smoły


## Okrąg z góry w prostokącie (koło przybliżone ściętymi rogami): obwódka `rim`, środek `fill`.
static func _ring(img: Image, r: Rect2i, rim: Color, fill: Color) -> void:
	for y in range(r.position.y, r.end.y):
		for x in range(r.position.x, r.end.x):
			var ex := x == r.position.x or x == r.end.x - 1
			var ey := y == r.position.y or y == r.end.y - 1
			if ex and ey:
				continue
			PixelCanvas.px(img, x, y, rim if ex or ey else fill)


## Koń z góry, 2×5 px: tułów, głowa z grzywą na północ i ogon.
static func _draw_horse(img: Image, at: Vector2i, coat: Color) -> void:
	PixelCanvas.rect(img, Rect2i(at.x, at.y + 1, 2, 4), coat)
	PixelCanvas.px(img, at.x, at.y, coat)
	PixelCanvas.px(img, at.x + 1, at.y + 1, Palette.SHADOW)  # grzywa
	PixelCanvas.px(img, at.x, at.y + 5, Palette.SHADOW)  # ogon


## Wieża grodowa (2×2, donżon epoki I, #120) z góry: najwyższa budowla zamku i cel każdego ataku.
## Poziomy: 1 wieża pod dachem namiotowym na ziemnej podmurówce, 2 większa, 3 z gankiem (hurdycją)
## z desek wokół dachu, 4 z wyższym dachem i belkami ganku, 5 z flagą i proporcem.
static func _draw_keep(img: Image, level: int) -> void:
	var w := img.get_width()
	for y in range(1, w - 1):
		for x in range(1, w - 1):
			PixelCanvas.px(img, x, y, PixelCanvas.dither(x, y, Palette.EARTH[2], Palette.EARTH[1]))
	if level >= 3:
		PixelCanvas.deck(img, Rect2i(2, 2, w - 4, w - 4), false, Palette.WOOD, 23)
		if level >= 4:
			for c: Vector2i in [Vector2i(2, 2), Vector2i(w - 3, 2), Vector2i(2, w - 3), Vector2i(w - 3, w - 3)]:
				PixelCanvas.px(img, c.x, c.y, Palette.WOOD[0])
	var roof: Array[int] = [8, 10, 10, 12, 12]
	var rs := roof[level - 1]
	var o := (w - rs) / 2
	PixelCanvas.roof_hip(img, Rect2i(o, o, rs, rs), Palette.THATCH, Palette.WOOD[0] if level >= 2 else Palette.WOOD[1])
	if level == 5:
		PixelCanvas.pennant(img, Vector2i(w / 2, w / 2 - 2), Palette.ACCENT)
		PixelCanvas.rect(img, Rect2i(2, w / 2, 1, 3), Palette.ACCENT)


## Strażnica (2×2, #177) z góry: pomost z desek z balustradą, czatownia pod daszkiem namiotowym
## z proporcem, kosz z ogniem sygnałowym w rogu i drabina od południa. Ma jeden poziom
## (BuildingTypes.has_levels), więc rysunek od niego nie zależy.
static func _draw_watchtower(img: Image) -> void:
	var w := img.get_width()
	PixelCanvas.deck(img, Rect2i(1, 1, w - 2, w - 3), true, Palette.WOOD, 29)
	PixelCanvas.frame(img, Rect2i(1, 1, w - 2, w - 3), Palette.WOOD[1])
	PixelCanvas.roof_hip(img, Rect2i(4, 3, 8, 8), Palette.THATCH, Palette.WOOD[1])
	PixelCanvas.pennant(img, Vector2i(8, 5), Palette.ACCENT)
	# kosz z ogniem sygnałowym
	PixelCanvas.rect(img, Rect2i(11, 10, 2, 2), Palette.SHADOW)
	PixelCanvas.px(img, 11, 10, Palette.ACCENT)
	PixelCanvas.px(img, 12, 11, Palette.THATCH[2])
	# drabina od południa
	for y in range(w - 3, w):
		PixelCanvas.px(img, 7, y, Palette.WOOD[2])
		PixelCanvas.px(img, 9, y, Palette.WOOD[2])
		if y % 2 == 0:
			PixelCanvas.px(img, 8, y, Palette.WOOD[3])


## Pole lnu (2×2, #122): zaorana ziemia z rzędami lnu. Poziomy: 1 mała grządka z siewkami,
## 2 całe pole w zielonych rzędach, 3 len kwitnie na niebiesko, 4 snopki na skraju pola,
## 5 strach na wróble z czerwoną chustą.
static func _draw_flax_field(img: Image, level: int) -> void:
	var field := Rect2i(1, 1, 14, 14) if level >= 2 else Rect2i(3, 4, 8, 7)
	for y in range(field.position.y, field.end.y):
		for x in range(field.position.x, field.end.x):
			PixelCanvas.px(img, x, y, PixelCanvas.dither(x, y, Palette.EARTH[2], Palette.EARTH[1]))
	# rzędy roślin co 3 piksele
	for y in range(field.position.y + 1, field.end.y, 3):
		for x in range(field.position.x, field.end.x):
			if (x + y) % 2 != 0 and level >= 2:
				continue
			if level == 1 and x % 2 != 0:
				continue
			PixelCanvas.px(img, x, y, Palette.GRASS[3])
			if level >= 2:
				PixelCanvas.px(img, x, y + 1, Palette.GRASS[2])
			if level >= 3 and PixelCanvas.hash2(x, y, 19) % 3 == 0:
				PixelCanvas.px(img, x, y, Palette.WATER[2])  # niebieski kwiat lnu
	if level >= 4:
		for sx: int in [2, 5]:
			PixelCanvas.rect(img, Rect2i(sx, 2, 2, 2), Palette.THATCH[1])
			PixelCanvas.px(img, sx, 2, Palette.THATCH[2])
	if level == 5:
		# strach na wróble z góry: krzyż z kapeluszem i chustą
		PixelCanvas.rect(img, Rect2i(10, 5, 5, 1), Palette.WOOD[1])
		PixelCanvas.rect(img, Rect2i(11, 4, 3, 3), Palette.THATCH[2])
		PixelCanvas.rect(img, Rect2i(12, 7, 1, 2), Palette.ACCENT)


# --- Plac budowy -----------------------------------------------------------------------------

## Plac budowy (poziom 0) z góry: ubita ziemia na kratkach budynku, belki fundamentu po obwodzie,
## słupy rusztowania w rogach z poprzeczką i stos bali. Umocnienia dostają ziemię na kształcie
## odcinka i rzadkie paliki, więc plac budowy też łączy się z sąsiadami.
static func _draw_site(img: Image, kind: int, mask: int) -> void:
	if BuildingTypes.is_wall(kind):
		var f := wall_shape(mask, wall_thickness(kind))
		for y in CELL:
			for x in CELL:
				if not _on(f, x, y):
					continue
				PixelCanvas.px(img, x, y, PixelCanvas.dither(x, y, Palette.EARTH[2], Palette.EARTH[1]))
				if (x + 2 * y) % 5 == 0:
					PixelCanvas.px(img, x, y, Palette.WOOD[3])
		return
	var sz := img.get_size()
	var lot := Rect2i(1, 1, sz.x - 2, sz.y - 2)
	for y in range(lot.position.y, lot.end.y):
		for x in range(lot.position.x, lot.end.x):
			var edge := x == lot.position.x or x == lot.end.x - 1 or y == lot.position.y or y == lot.end.y - 1
			var col := PixelCanvas.dither(x, y, Palette.EARTH[2], Palette.EARTH[1])
			if edge:
				col = Palette.WOOD[1] if (x + y) % 3 != 0 else Palette.WOOD[0]
			PixelCanvas.px(img, x, y, col)
	# rusztowanie: słupy w rogach placu i poprzeczka wzdłuż północnego boku
	for c: Vector2i in [lot.position + Vector2i(1, 1), Vector2i(lot.end.x - 2, lot.position.y + 1)]:
		PixelCanvas.px(img, c.x, c.y, Palette.WOOD[3])
	for x in range(lot.position.x + 2, lot.end.x - 2):
		PixelCanvas.px(img, x, lot.position.y + 1, Palette.WOOD[2])
	if lot.size.x >= 8 and lot.size.y >= 6:
		PixelCanvas.log_pile(img, Rect2i(lot.position.x + 2, lot.end.y - 4, 4, 2))


## Czy budynek dostaje obrys i światło (#150). Umocnienia, brama i wieża łączą się z sąsiednimi
## odcinkami muru, więc obrys rysowałby kreskę na styku: one go nie mają. Fosa sucha (#35) też nie,
## bo sąsiednie odcinki fosy tworzą jeden rów.
static func has_outline(kind: int) -> bool:
	return not (BuildingTypes.is_wall(kind) or kind == BuildingTypes.Kind.GATE or kind == BuildingTypes.Kind.TOWER
			or kind == BuildingTypes.Kind.DRY_MOAT)


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
		[Palette.SHINGLE[0], Palette.SHINGLE[1]], [Palette.SHINGLE[1], Palette.SHINGLE[2]],
		[Palette.STONE[0], Palette.STONE[1]], [Palette.STONE[1], Palette.STONE[2]],
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
	# natywne kopiowanie przez maskę sylwetki (szybkie przy setkach wariantów w warm_up)
	var solid := Image.create(w, h, false, Image.FORMAT_RGBA8)
	solid.fill(Color(Palette.SHADOW, SHADOW_ALPHA))
	var out := Image.create(w + offset.x, h + offset.y, false, Image.FORMAT_RGBA8)
	out.blit_rect_mask(solid, img, Rect2i(Vector2i.ZERO, img.get_size()), offset)
	return out


## Przesunięcie cienia na południowy wschód: im wyższa budowla, tym dłuższy cień. Niskie odcinki
## muru, pola, studnia i kamieniołom rzucają krótki cień, wieże i donżon najdłuższy, a fosa żadnego.
static func shadow_offset(kind: int) -> Vector2i:
	if kind == BuildingTypes.Kind.DRY_MOAT:
		return Vector2i.ZERO  # rów nie rzuca cienia (#35)
	if BuildingTypes.is_wall(kind) or kind in [BuildingTypes.Kind.FLAX_FIELD, BuildingTypes.Kind.FARM,
			BuildingTypes.Kind.WELL, BuildingTypes.Kind.QUARRY]:
		return Vector2i(1, 1)
	if kind in [BuildingTypes.Kind.TOWER, BuildingTypes.Kind.KEEP, BuildingTypes.Kind.WATCHTOWER,
			BuildingTypes.Kind.SIGNAL_TOWER]:
		return Vector2i(3, 3)
	return Vector2i(2, 2)


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


## Rysy: z punktów wybranych przez hash2 spośród pikseli budynku, co krok o piksel w dół i w bok
## albo prosto. Malują tylko istniejące piksele budynku, więc nie wychodzą poza jego sylwetkę.
static func _draw_cracks(img: Image, kind: int) -> void:
	var sz := img.get_size()
	var solid: Array[Vector2i] = []
	for y in sz.y:
		for x in sz.x:
			if _opaque(img, x, y):
				solid.append(Vector2i(x, y))
	if solid.is_empty():
		return
	var wall := BuildingTypes.is_wall(kind)
	var count := 2 if wall else 3
	var length := 3 if wall else 6
	for n in count:
		# punkty startu rozłożone po całej sylwetce, żeby rysy się nie nakładały
		var p := solid[(PixelCanvas.hash2(n, 7, 51 + kind) % maxi(1, solid.size() / count) + n * solid.size() / count) % solid.size()]
		for step in length:
			if p.x >= 0 and p.y >= 0 and p.x < sz.x and p.y < sz.y and _opaque(img, p.x, p.y):
				img.set_pixel(p.x, p.y, Palette.SHADOW)
			p += Vector2i(PixelCanvas.hash2(n, step, 53 + kind) % 3 - 1, 1)


## Dwa wyłomy od północnej krawędzi budynku (zapadnięty dach, wyrwa w pomoście): kolumny ścięte
## o 4–6 px z postrzępionym dnem i ciemną krawędzią przełomu. Wyłomy leżą w środkowej części
## sylwetki i nie ścinają więcej niż połowy kolumny (w niskich co najmniej piksel).
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
			var d := mini(depth - PixelCanvas.hash2(x, n, 43 + kind) % 2, maxi(1, (bottoms[x] - tops[x] + 1) / 2))
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


## Gruz umocnienia: rumowisko dokładnie na kształcie odcinka, więc też się łączy z sąsiadami.
## Z palisady zostają leżące pale.
static func _wall_rubble(img: Image, kind: int, mask: int) -> void:
	var f := wall_shape(mask, wall_thickness(kind))
	img.fill(Color(Palette.SHADOW, 0.0))
	for y in CELL:
		for x in CELL:
			if not _on(f, x, y):
				continue
			var col := _rubble_color(kind, x, y)
			if kind == BuildingTypes.Kind.PALISADE and PixelCanvas.hash2(x, y, 79 + kind) % 4 == 1:
				col = Palette.WOOD[1]
			PixelCanvas.px(img, x, y, col)


## Pierwsza i ostatnia niepusta kolumna (x, y) według wierzchów kolumn.
static func _opaque_span(tops: PackedInt32Array) -> Vector2i:
	var span := Vector2i(-1, -1)
	for x in tops.size():
		if tops[x] >= 0:
			if span.x < 0:
				span.x = x
			span.y = x
	return span


## Gruz budynku wielokratkowego z góry: rumowisko na zajmowanej części kratek (gęstsze w środku,
## na skraju rozrzucone szczątki) i kilka osmalonych belek leżących w poprzek.
static func _building_rubble(img: Image, kind: int) -> void:
	var used := img.get_used_rect()
	img.fill(Color(Palette.SHADOW, 0.0))
	if not used.has_area():
		return
	var c := used.get_center()
	for y in range(used.position.y, used.end.y):
		for x in range(used.position.x, used.end.x):
			var far := absi(x - int(c.x)) * 2 > used.size.x - 3 or absi(y - int(c.y)) * 2 > used.size.y - 3
			if far and PixelCanvas.hash2(x, y, 71 + kind) % 3 != 0:
				continue
			img.set_pixel(x, y, _rubble_color(kind, x, y))
	for n in 3:
		var y := used.position.y + 1 + PixelCanvas.hash2(n, 3, 77 + kind) % maxi(1, used.size.y - 2)
		var x0 := used.position.x + PixelCanvas.hash2(n, 4, 77 + kind) % maxi(1, used.size.x / 2)
		var length := 3 + PixelCanvas.hash2(n, 5, 77 + kind) % 4
		for i in length:
			PixelCanvas.px(img, x0 + i, y, Palette.WOOD[0] if i == length - 1 else Palette.WOOD[1])
