class_name PortraitArt
extends RefCounted
## Portrety władców (#228) w okręgu do HUD-u: popiersie 22×22 px zapisane w kodzie jako wzór znaków,
## przycięte do koła z ciemnym obrysem i złotym pierścieniem. Tekstura powstaje raz dla władcy
## i leży w cache. Domyślny Kasztelan ma futrzany kołpak z czerwonym wierzchem, brodę i czerwony
## płaszcz ze złotą zapinką.

const SIZE := 22

## Legenda wzorów: znak → kolor palety. '.' to tło portretu.
const LEGEND := {
	"a": Palette.ACCENT, "A": Palette.WOOD[1], "m": Palette.WOOD[1], "w": Palette.WOOD[2],
	"s": Palette.SKIN, "S": Palette.WOOD[3], "K": Palette.SHADOW, "k": Palette.WOOD[0],
	"T": Palette.THATCH[2],
}

## Wzory portretów według id władcy (Rulers). Nieznany władca dostaje portret domyślnego.
const PATTERNS := {
	Rulers.DEFAULT: [
		"......................",
		"......................",
		"..........aa..........",
		"........aaaaaa........",
		".......aaaaaaAa.......",
		"......aaaaaaaaaa......",
		"......mwmwmwmwmw......",
		"......wmwmwmwmwm......",
		".......SssssssS.......",
		".......sKsssKss.......",
		".......ssssssss.......",
		".......sssSssss.......",
		".......kkkssskk.......",
		".......Skkkkkks.......",
		"........kkkkkk........",
		".........kkkk.........",
		".......aaakkaaa.......",
		".....aaaaaTTaaaaa.....",
		"....aaaaaaaaaaaAaa....",
		"...aaaaaaaaaaaaAaaa...",
		"..aaaaaaaaaaaaaaAaaa..",
		"..aaaaaaaaaaaaaaaaaa..",
	],
}

## Puste miejsce na ekranie wyboru władcy: szara sylwetka głowy i ramion.
const LOCKED_PATTERN: Array[String] = [
	"......................",
	"......................",
	"......................",
	"......................",
	".........xxxx.........",
	"........xxxxxx........",
	".......xxxxxxxx.......",
	".......xxxxxxxx.......",
	".......xxxxxxxx.......",
	".......xxxxxxxx.......",
	"........xxxxxx........",
	".........xxxx.........",
	"..........xx..........",
	".......xxxxxxxx.......",
	".....xxxxxxxxxxxx.....",
	"....xxxxxxxxxxxxxx....",
	"...xxxxxxxxxxxxxxxx...",
	"...xxxxxxxxxxxxxxxx...",
	"..xxxxxxxxxxxxxxxxxx..",
	"..xxxxxxxxxxxxxxxxxx..",
	"..xxxxxxxxxxxxxxxxxx..",
	"..xxxxxxxxxxxxxxxxxx..",
]
## Klucz pustego miejsca w cache (żaden władca nie ma takiego id).
const LOCKED_KEY := "_locked"

static var _cache: Dictionary[String, ImageTexture] = {}


## Obraz portretu: wzór w kole o średnicy SIZE, pierścień i obrys na brzegu, poza kołem przezroczysto.
static func ruler_image(ruler_id: String) -> Image:
	var rows: Array = PATTERNS.get(ruler_id, PATTERNS[Rulers.DEFAULT])
	return _circle(rows, LEGEND, Palette.WATER[1], Palette.THATCH[1])


## Szare puste miejsce na władcę (bez złotego pierścienia).
static func locked_image() -> Image:
	return _circle(LOCKED_PATTERN, {"x": Palette.LOCKED[1]}, Palette.LOCKED[0], Palette.LOCKED[0])


## Wzór w kole: tło `back`, pierścień `ring`, obrys WOOD[0], poza kołem przezroczysto.
static func _circle(rows: Array, legend: Dictionary, back: Color, ring: Color) -> Image:
	var img := Image.create(SIZE, SIZE, false, Image.FORMAT_RGBA8)
	var c := (SIZE - 1) / 2.0
	for y in SIZE:
		var row: String = rows[y]
		for x in SIZE:
			var d := Vector2(x - c, y - c).length()
			if d > c + 0.5:
				continue
			var col: Color = back
			if d > c - 0.5:
				col = Palette.WOOD[0]
			elif d > c - 1.5:
				col = ring
			elif legend.has(row[x]):
				col = legend[row[x]]
			img.set_pixel(x, y, col)
	return img


static func ruler_texture(ruler_id: String) -> ImageTexture:
	if not _cache.has(ruler_id):
		_cache[ruler_id] = ImageTexture.create_from_image(ruler_image(ruler_id))
	return _cache[ruler_id]


static func locked_texture() -> ImageTexture:
	if not _cache.has(LOCKED_KEY):
		_cache[LOCKED_KEY] = ImageTexture.create_from_image(locked_image())
	return _cache[LOCKED_KEY]
