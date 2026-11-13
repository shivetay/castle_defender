class_name PixelIcons
extends RefCounted
## Ikony surowców 5×5 zapisane w kodzie jako wzory znaków (bez plików graficznych).
## Kolejność jak w EconomyConfig.Res: drewno (dwa bale), kamień, żywność (jabłko), złoto (moneta).
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

static var _atlas: ImageTexture


## Obraz atlasu: ikony obok siebie, każda w kratce SIZE×SIZE.
static func make_atlas() -> Image:
	var img := Image.create(SIZE * RESOURCES.size(), SIZE, false, Image.FORMAT_RGBA8)
	for i in RESOURCES.size():
		var rows: Array = RESOURCES[i]
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
