class_name PixelIcons
extends RefCounted
## Ikony surowców i klas jednostek 5×5 zapisane w kodzie jako wzory znaków (bez plików graficznych).
## Surowce w kolejności EconomyConfig.Res: drewno (dwa bale), kamień, żywność (jabłko), złoto (moneta).
## Klasy (#87) w kolejności RecruitmentConfig.UnitClass: lekka (topór), ciężka (tarcza z umbem),
## strzelecka (łuk ze strzałą), szybka (podkowa), specjalna (płomień).
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

static var _atlas: ImageTexture
static var _class_atlas: ImageTexture


## Obraz atlasu: ikony obok siebie, każda w kratce SIZE×SIZE (domyślnie surowce).
static func make_atlas(icons: Array = RESOURCES) -> Image:
	var img := Image.create(SIZE * icons.size(), SIZE, false, Image.FORMAT_RGBA8)
	for i in icons.size():
		var rows: Array = icons[i]
		for y in SIZE:
			var row: String = rows[y]
			for x in SIZE:
				var ch := row[x]
				if ch != ".":
					img.set_pixel(i * SIZE + x, y, LEGEND[ch] as Color)
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
static func draw_class(ci: CanvasItem, pos: Vector2, unit_class: int) -> void:
	if _class_atlas == null:
		_class_atlas = ImageTexture.create_from_image(make_atlas(CLASSES))
	ci.draw_texture_rect_region(_class_atlas, Rect2(pos.floor(), Vector2(SIZE, SIZE)),
			Rect2(unit_class * SIZE, 0, SIZE, SIZE))
