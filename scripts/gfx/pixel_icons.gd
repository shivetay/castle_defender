class_name PixelIcons
extends RefCounted
## Ikony surowców, towarów i klas jednostek 5×5 zapisane w kodzie jako wzory znaków (bez plików graficznych).
## Surowce w kolejności EconomyConfig.Res: drewno (dwa bale), kamień, żywność (jabłko), złoto (moneta).
## Klasy (#87) w kolejności RecruitmentConfig.UnitClass: lekka (topór), ciężka (tarcza z umbem),
## strzelecka (łuk ze strzałą), szybka (podkowa), specjalna (płomień).
## Jednostki (#309) mają własne ikony (UNITS), żeby jednostki tej samej klasy (Chłop, Topornik,
## Oszczepnik, Włócznik) dało się odróżnić. Ikona klasy zostaje dla zwiadu, który zna tylko klasę.
## Atlas wszystkich ikon powstaje raz, przy pierwszym użyciu, i jest trzymany w cache.

const SIZE := 5

## Legenda wzorów: znak → kolor palety. '.' to przezroczystość.
const LEGEND := {
	"k": Palette.WOOD[0], "m": Palette.WOOD[1], "w": Palette.WOOD[2], "l": Palette.WOOD[3],
	"s": Palette.WATER[0], "S": Palette.WATER[1], "L": Palette.WATER[2],
	"a": Palette.ACCENT, "g": Palette.GRASS[3], "t": Palette.THATCH[1], "T": Palette.THATCH[2],
	"i": Palette.INK,
}

const RESOURCES: Array = [
	["wwwl.", "mmmw.", ".wwwl", ".mmmw", "....."],
	["..LL.", ".LiLS", "LLLSS", "LSSSs", ".sss."],
	["..mg.", ".aaa.", "aiaaa", "aaaaa", ".aaa."],
	[".TTT.", "TiTTt", "TTTTt", "TTTtt", ".ttt."],
]

const CLASSES: Array = [
	["TT.k.", "TTTk.", "TT.k.", "...k.", "...k."],
	[".mmm.", "mmmmm", "mmamm", "mmmmm", ".mmm."],
	["..wT.", ".w.T.", "wlllT", ".w.T.", "..wT."],
	["ll.ll", "l...l", "l...l", "ll.ll", ".lll."],
	["..a..", ".aa..", ".aTa.", "aaTaa", ".aaa."],
]

## Ikony jednostek 5×5 w kolejności UnitTypes.Unit (#309): topornik (topór), oszczepnik (dwa
## oszczepy), łucznik (łuk ze strzałą), tarczownik (tarcza z umbem), podpalacz (płomień), tropiciel
## (ślady stóp), jeździec (podkowa), włócznik (włócznia z grotem), drużynnik (hełm z nosalem),
## strzelec z łukiem refleksyjnym (łuk z wygiętymi końcami), kopijnik (kopia z proporcem), taran
## (belka z okuciem na kołach), kopacz (łopata), chłop (widły), zwiadowca (oko), wóz (wóz z workiem).
const UNITS: Array = [
	[".LLk.", "LLLk.", ".LLk.", "...k.", "...k."],
	["L..L.", ".w..w", "..w..", ".w.w.", "w...."],
	["..wT.", ".w.T.", "wlllT", ".w.T.", "..wT."],
	[".mmm.", "mmmmm", "mmamm", "mmmmm", ".mmm."],
	["..a..", ".aa..", ".aTa.", "aaTaa", ".aaa."],
	["ii...", "ii.ii", "...ii", "ii...", "ii..."],
	["ll.ll", "l...l", "l...l", "ll.ll", ".lll."],
	["..L..", ".LLL.", "..w..", "..w..", "..w.."],
	[".LLL.", "LLLLL", "LLsLL", "L.s.L", "L...L"],
	["TT.T.", "..TT.", "lllla", "..TT.", "TT.T."],
	["....L", "aaaw.", "aaw..", ".w...", "w...."],
	[".....", "wwwwL", "mmmmL", ".k.k.", "....."],
	["..w..", "..w..", ".LLL.", ".LLL.", "..L.."],
	["l.l.l", "l.l.l", "lllll", "..w..", "..w.."],
	[".....", ".LLL.", "LLiLL", ".LLL.", "....."],
	[".tt..", "wttww", "wwwww", ".k.k.", "....."],
]

## Towary 5×5 w kolejności GoodsConfig.Good (pasek zapasu zbrojowni w Wojsku): surowe skóry,
## wyprawiona skóra, kość, ścięgna, pióra, len, zbroja skórzana, przeszywanica, tarcza, mokre skóry,
## włócznia, oszczep, kopia, topór kamienny, cięciwa, łuk, łuk refleksyjny, strzały, siodło,
## uprząż, smoła, koń.
const GOODS: Array = [
	["l...l", "lllll", ".lwl.", "lllll", "l...l"],
	["wwww.", "wllww", "wlllw", "wwllw", ".wwww"],
	["ii...", "iii..", "..i..", "..iii", "...ii"],
	["tt...", "..t..", ".t...", "..t..", "...tt"],
	["...ii", "..iii", ".iii.", ".ii..", "w...."],
	["T.T.T", ".g.g.", ".ggg.", "..g..", "..g.."],
	["ww.ww", "wwwww", ".wkw.", ".www.", ".www."],
	["TT.TT", "TTTTT", ".TtT.", ".tTt.", ".TtT."],
	[".www.", "wwwww", "wwLww", "wwwww", ".www."],
	["S...S", "SSSSS", ".SLS.", "SSSSS", "S...S"],
	["...LL", "...LL", "..w..", ".w...", "w...."],
	["..L.L", ".w.w.", "w.w..", ".t...", "t...."],
	["..L..", "..waa", "..wa.", "..w..", "..w.."],
	[".LLw.", "LLLw.", ".LLw.", "...w.", "...w."],
	[".TTT.", "T...T", "T.T.T", "T...T", ".TTT."],
	["..wi.", ".w.i.", "w..i.", ".w.i.", "..wi."],
	[".TTi.", "T..i.", "T..i.", "T..i.", ".TTi."],
	["L.L.L", "w.w.w", "w.w.w", "w.w.w", "a.a.a"],
	["l...l", "lllll", ".lll.", ".k.k.", ".k.k."],
	["l...l", ".l.l.", "..L..", ".l.l.", "l...l"],
	["..a..", "m.a.m", "mkkkm", "mmmmm", ".mmm."],
	[".lll.", "lilll", "ll.ll", "l..ll", "...ll"],
]

## Ikony 7×7 głównej kolumny HUD-u (#150), w kolejności Hud.column_targets(false): Buduj (młotek),
## Badania (księga), Wojsko (hełm z nosalem), Obrona (tarcza), Kolejka (klepsydra), Ustawienia
## (zębatka, #177). Oblężenie i Atak są na karcie Strażnicy.
const MENU_SIZE := 7
const MENU: Array = [
	[".LLLLL.", ".LLLLL.", "...l...", "...w...", "...w...", "...w...", "...k..."],
	[".......", "TTT.TTT", "TiT.TiT", "TTTkTTT", "TiTkTiT", "TTTkTTT", ".mmmmm."],
	["...a...", "..LLL..", ".LLLLL.", ".LLLLL.", ".LsLsL.", ".L.L.L.", "......."],
	[".mmmmm.", "mwwawwm", "mwwawwm", "mwaaawm", ".mwawm.", "..mwm..", "...m..."],
	["lllllll", ".TTTTT.", "..TTT..", "...T...", "..T.T..", ".TTTTT.", "lllllll"],
	["..i.i..", ".iiiii.", "iii.iii", "ii...ii", "iii.iii", ".iiiii.", "..i.i.."],
]

static var _atlas: ImageTexture
static var _class_atlas: ImageTexture
static var _menu_atlas: ImageTexture
static var _goods_atlas: ImageTexture
static var _unit_atlas: ImageTexture


## Obraz atlasu: ikony obok siebie, każda w kratce SIZE×SIZE (domyślnie surowce).
static func make_atlas(icons: Array = RESOURCES, size: int = SIZE) -> Image:
	var img := Image.create(size * icons.size(), size, false, Image.FORMAT_RGBA8)
	for i in icons.size():
		var rows: Array = icons[i]
		for y in size:
			var row: String = rows[y]
			for x in size:
				var ch := row[x]
				if ch != ".":
					img.set_pixel(i * size + x, y, LEGEND[ch] as Color)
	return img


static func atlas() -> ImageTexture:
	if _atlas == null:
		_atlas = ImageTexture.create_from_image(make_atlas())
	return _atlas


## Rysuje ikonę surowca `res` lewym górnym rogiem w `pos` (całe piksele).
static func draw_resource(ci: CanvasItem, pos: Vector2, res: int) -> void:
	ci.draw_texture_rect_region(atlas(), Rect2(pos.floor(), Vector2(SIZE, SIZE)),
			Rect2(res * SIZE, 0, SIZE, SIZE))


## Rysuje ikonę klasy jednostki `unit_class` (RecruitmentConfig.UnitClass) lewym górnym rogiem w `pos`.
## Fragment atlasu klas dla `unit_class`; pusty dla klasy spoza zakresu (inżynieria,
## UnitTypes.ENGINEERING = -1), która nie ma ikony.
static func class_region(unit_class: int) -> Rect2:
	if unit_class < 0 or unit_class >= CLASSES.size():
		return Rect2()
	return Rect2(unit_class * SIZE, 0, SIZE, SIZE)


## Rysuje ikonę klasy; dla klasy bez ikony nic nie rysuje.
static func draw_class(ci: CanvasItem, pos: Vector2, unit_class: int) -> void:
	var region := class_region(unit_class)
	if not region.has_area():
		return
	if _class_atlas == null:
		_class_atlas = ImageTexture.create_from_image(make_atlas(CLASSES))
	ci.draw_texture_rect_region(_class_atlas, Rect2(pos.floor(), Vector2(SIZE, SIZE)), region)


## Ikona klasy na ciemnym tle SIZE+2 (Wojsko, pasek planu ataku/obrony, odznaka bitwy):
## bez tego brązowa tarcza (WOOD[1]) znika na drewnianym kafelku UI.
static func draw_class_badge(ci: CanvasItem, pos: Vector2, unit_class: int) -> void:
	if not class_region(unit_class).has_area():
		return
	var at := pos.floor()
	ci.draw_rect(Rect2(at - Vector2.ONE, Vector2(SIZE + 2, SIZE + 2)), Palette.SHADOW)
	draw_class(ci, at, unit_class)


## Fragment atlasu jednostek dla `unit` (UnitTypes.Unit); pusty dla jednostki spoza zakresu.
static func unit_region(unit: int) -> Rect2:
	if unit < 0 or unit >= UNITS.size():
		return Rect2()
	return Rect2(unit * SIZE, 0, SIZE, SIZE)


## Rysuje ikonę jednostki `unit` lewym górnym rogiem w `pos`; dla jednostki bez ikony nic nie rysuje.
static func draw_unit(ci: CanvasItem, pos: Vector2, unit: int) -> void:
	var region := unit_region(unit)
	if not region.has_area():
		return
	if _unit_atlas == null:
		_unit_atlas = ImageTexture.create_from_image(make_atlas(UNITS))
	ci.draw_texture_rect_region(_unit_atlas, Rect2(pos.floor(), Vector2(SIZE, SIZE)), region)


## Ikona jednostki na ciemnym tle SIZE+2, jak draw_class_badge.
static func draw_unit_badge(ci: CanvasItem, pos: Vector2, unit: int) -> void:
	if not unit_region(unit).has_area():
		return
	var at := pos.floor()
	ci.draw_rect(Rect2(at - Vector2.ONE, Vector2(SIZE + 2, SIZE + 2)), Palette.SHADOW)
	draw_unit(ci, at, unit)


## Rysuje ikonę `i` z MENU lewym górnym rogiem w `pos`.
static func draw_menu(ci: CanvasItem, pos: Vector2, i: int) -> void:
	if _menu_atlas == null:
		_menu_atlas = ImageTexture.create_from_image(make_atlas(MENU, MENU_SIZE))
	ci.draw_texture_rect_region(_menu_atlas, Rect2(pos.floor(), Vector2(MENU_SIZE, MENU_SIZE)),
			Rect2(i * MENU_SIZE, 0, MENU_SIZE, MENU_SIZE))


## Rysuje ikonę towaru `good` (GoodsConfig.Good) lewym górnym rogiem w `pos`.
static func draw_good(ci: CanvasItem, pos: Vector2, good: int) -> void:
	if good < 0 or good >= GOODS.size():
		return
	if _goods_atlas == null:
		_goods_atlas = ImageTexture.create_from_image(make_atlas(GOODS))
	ci.draw_texture_rect_region(_goods_atlas, Rect2(pos.floor(), Vector2(SIZE, SIZE)),
			Rect2(good * SIZE, 0, SIZE, SIZE))
