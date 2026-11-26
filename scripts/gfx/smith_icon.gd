class_name SmithIcon
extends RefCounted
## Animowana ikona kowala walącego młotem w kowadło (#316, zasłona ładowania), zapisana w kodzie jako
## wzory znaków jak PixelIcons. Klatki: młot w górze, w połowie, uderzenie z iskrami. Każda klatka to
## BASE (kowal bez ręki i kowadło) z nałożoną ręką z ARMS. Atlas powstaje raz i jest trzymany w cache.

const W := 22
const H := 16
enum Frame { UP, MID, HIT }

## Legenda: znak → kolor palety. '.' to przezroczystość.
const LEGEND := {
	"k": Palette.WOOD[0], "m": Palette.WOOD[1], "w": Palette.WOOD[2], "l": Palette.WOOD[3],
	"s": Palette.SKIN, "d": Palette.STONE[0], "S": Palette.STONE[1], "L": Palette.STONE[2],
	"T": Palette.THATCH[2], "a": Palette.ACCENT,
}

const BASE: Array[String] = [
	"......................",
	"......................",
	"....kkk...............",
	"....sss...............",
	"....sss...............",
	"...mmmmm..............",
	"...mlllm..............",
	"...mlllm..............",
	"...mlllm..............",
	"...mlllm..............",
	"...mlllm...LLLLLLLL...",
	"....lll....dSSSSSSd...",
	"....k.k.....ddSSdd....",
	"....k.k.......Sd......",
	"...kk.kk.....dSSSd....",
	"............dddddd....",
]

## Ręka z młotem dla każdej klatki (Frame), nakładana na BASE.
const ARMS: Array = [
	[
		"........dddd..........",
		"........dddd..........",
		".........w............",
		"........sw............",
		".......s..............",
		"......................",
	],
	[
		"......................",
		"......................",
		"......................",
		"............dd........",
		"..........w.dd........",
		"........sswwdd........",
	],
	[
		"......................",
		"......................",
		"......................",
		"................T.....",
		"..............a.......",
		"........ss........T...",
		"..........s.....a.....",
		"...........w....T.....",
		"...........ddd..a.....",
		"...........ddd........",
	],
]

static var _atlas: ImageTexture


## Obraz atlasu: klatki obok siebie, każda W×H.
static func make_atlas() -> Image:
	var img := Image.create(W * ARMS.size(), H, false, Image.FORMAT_RGBA8)
	for f in ARMS.size():
		var arm: Array = ARMS[f]
		for y in H:
			var row := BASE[y]
			var over: String = arm[y] if y < arm.size() else ""
			for x in W:
				var ch := row[x]
				if x < over.length() and over[x] != ".":
					ch = over[x]
				if ch != ".":
					img.set_pixel(f * W + x, y, LEGEND[ch] as Color)
	return img


static func atlas() -> ImageTexture:
	if _atlas == null:
		_atlas = ImageTexture.create_from_image(make_atlas())
	return _atlas


## Rysuje klatkę `frame` (Frame) lewym górnym rogiem w `pos` (całe piksele), w skali całkowitej `scale`.
static func draw(ci: CanvasItem, pos: Vector2, frame: int, scale: int = 1) -> void:
	ci.draw_texture_rect_region(atlas(), Rect2(pos.floor(), Vector2(W, H) * scale), Rect2(frame * W, 0, W, H))
