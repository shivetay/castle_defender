class_name PixelFont
extends RefCounted
## Font pikselowy zdefiniowany w kodzie (bez plików fontów). Wielkie litery 3–5 px szerokości
## i 5 px wysokości z polskimi znakami. Linia ma 8 px: wiersze 0–1 to akcenty (Ć, Ó, Ż...),
## 2–6 litera, 7 ogonek (Ą, Ę) albo przecinek. Małe litery rysuje się jako wielkie.
## Atlas glifów powstaje raz dla każdego koloru z palety i jest trzymany w cache.

const LINE := 8
const CAP_TOP := 2
const CELL_W := 6

## Glif: wiersze od góry litery (5 wierszy, opcjonalnie 6. pod linią bazową), '#' = piksel.
const GLYPHS := {
	"A": [".##.", "#..#", "####", "#..#", "#..#"],
	"B": ["###.", "#..#", "###.", "#..#", "###."],
	"C": [".###", "#...", "#...", "#...", ".###"],
	"D": ["###.", "#..#", "#..#", "#..#", "###."],
	"E": ["####", "#...", "###.", "#...", "####"],
	"F": ["####", "#...", "###.", "#...", "#..."],
	"G": [".###", "#...", "#.##", "#..#", ".###"],
	"H": ["#..#", "#..#", "####", "#..#", "#..#"],
	"I": ["###", ".#.", ".#.", ".#.", "###"],
	"J": ["..##", "...#", "...#", "#..#", ".##."],
	"K": ["#..#", "#.#.", "##..", "#.#.", "#..#"],
	"L": ["#...", "#...", "#...", "#...", "####"],
	"Ł": ["#...", "#.#.", "##..", "#...", "####"],
	"M": ["#...#", "##.##", "#.#.#", "#...#", "#...#"],
	"N": ["#..#", "##.#", "#.##", "#..#", "#..#"],
	"O": [".##.", "#..#", "#..#", "#..#", ".##."],
	"P": ["###.", "#..#", "###.", "#...", "#..."],
	"Q": [".##.", "#..#", "#..#", "#.#.", ".#.#"],
	"R": ["###.", "#..#", "###.", "#.#.", "#..#"],
	"S": [".###", "#...", ".##.", "...#", "###."],
	"T": ["###", ".#.", ".#.", ".#.", ".#."],
	"U": ["#..#", "#..#", "#..#", "#..#", ".##."],
	"V": ["#...#", "#...#", ".#.#.", ".#.#.", "..#.."],
	"W": ["#...#", "#...#", "#.#.#", "##.##", "#...#"],
	"X": ["#..#", "#..#", ".##.", "#..#", "#..#"],
	"Y": ["#.#", "#.#", ".#.", ".#.", ".#."],
	"Z": ["####", "...#", ".##.", "#...", "####"],
	"0": ["###", "#.#", "#.#", "#.#", "###"],
	"1": [".#.", "##.", ".#.", ".#.", "###"],
	"2": ["###", "..#", "###", "#..", "###"],
	"3": ["###", "..#", ".##", "..#", "###"],
	"4": ["#.#", "#.#", "###", "..#", "..#"],
	"5": ["###", "#..", "###", "..#", "###"],
	"6": ["###", "#..", "###", "#.#", "###"],
	"7": ["###", "..#", "..#", ".#.", ".#."],
	"8": ["###", "#.#", "###", "#.#", "###"],
	"9": ["###", "#.#", "###", "..#", "###"],
	" ": ["..", "..", "..", "..", ".."],
	".": [".", ".", ".", ".", "#"],
	",": [".", ".", ".", ".", "#", "#"],
	":": [".", "#", ".", "#", "."],
	";": [".", "#", ".", "#", "#"],
	"-": ["...", "...", "###", "...", "..."],
	"+": ["...", ".#.", "###", ".#.", "..."],
	"/": ["..#", "..#", ".#.", "#..", "#.."],
	"×": ["...", "#.#", ".#.", "#.#", "..."],
	"·": [".", ".", "#", ".", "."],
	"%": ["#.#", "..#", ".#.", "#..", "#.#"],
	"(": [".#", "#.", "#.", "#.", ".#"],
	")": ["#.", ".#", ".#", ".#", "#."],
	"!": ["#", "#", "#", ".", "#"],
	"?": ["###", "..#", ".##", "...", ".#."],
	"'": ["#", "#", ".", ".", "."],
	"\"": ["#.#", "#.#", "...", "...", "..."],
}
## Polskie litery: litera bazowa i znak diakrytyczny (kreska, kropka albo ogonek).
const ACCENTED := {
	"Ą": ["A", "ogonek"], "Ć": ["C", "acute"], "Ę": ["E", "ogonek"], "Ń": ["N", "acute"],
	"Ó": ["O", "acute"], "Ś": ["S", "acute"], "Ź": ["Z", "acute"], "Ż": ["Z", "dot"],
}

static var _atlases: Dictionary[int, ImageTexture] = {}
static var _index: Dictionary[String, int] = {}


## Szerokość tekstu w pikselach (odstęp 1 px między znakami, bez odstępu na końcu).
static func text_width(text: String) -> int:
	var w := 0
	for ch in _normalize(text):
		w += glyph_width(ch) + 1
	return maxi(w - 1, 0)


static func glyph_width(ch: String) -> int:
	var rows: Array = _rows(ch)
	return (rows[0] as String).length()


## Rysuje tekst na CanvasItem. `pos` to lewy górny róg linii (8 px wysokości).
static func draw_text(ci: CanvasItem, pos: Vector2, text: String, col: Color) -> void:
	var atlas := _atlas(col)
	var x := floorf(pos.x)
	var y := floorf(pos.y)
	for ch in _normalize(text):
		var w := glyph_width(ch)
		var src := Rect2(_index[ch] * CELL_W, 0, w, LINE)
		ci.draw_texture_rect_region(atlas, Rect2(x, y, w, LINE), src)
		x += w + 1


## Tekst wyśrodkowany w poziomie i w pionie w prostokącie.
static func draw_centered(ci: CanvasItem, r: Rect2, text: String, col: Color) -> void:
	var x := r.position.x + floorf((r.size.x - text_width(text)) / 2.0)
	var y := r.position.y + floorf((r.size.y - LINE) / 2.0)
	draw_text(ci, Vector2(x, y), text, col)


## Tekst wyrównany do prawej krawędzi `right_x`.
static func draw_right(ci: CanvasItem, right_x: float, y: float, text: String, col: Color) -> void:
	draw_text(ci, Vector2(right_x - text_width(text), y), text, col)


## Rysuje tekst do obrazu (np. do testów albo tekstur).
static func render(img: Image, pos: Vector2i, text: String, col: Color) -> void:
	var x := pos.x
	for ch in _normalize(text):
		_blit_glyph(img, Vector2i(x, pos.y), ch, col)
		x += glyph_width(ch) + 1


## Wielkie litery; znaki spoza fontu zamienia na „?”.
static func _normalize(text: String) -> String:
	var out := ""
	for ch in text.to_upper():
		out += ch if (GLYPHS.has(ch) or ACCENTED.has(ch)) else "?"
	return out


static func _rows(ch: String) -> Array:
	if ACCENTED.has(ch):
		return GLYPHS[ACCENTED[ch][0]]
	return GLYPHS[ch]


static func _blit_glyph(img: Image, at: Vector2i, ch: String, col: Color) -> void:
	var rows: Array = _rows(ch)
	for ry in rows.size():
		var row: String = rows[ry]
		for rx in row.length():
			if row[rx] == "#":
				PixelCanvas.px(img, at.x + rx, at.y + CAP_TOP + ry, col)
	if not ACCENTED.has(ch):
		return
	var w := glyph_width(ch)
	match ACCENTED[ch][1]:
		"acute":
			PixelCanvas.px(img, at.x + (w >> 1) + 1, at.y, col)
			PixelCanvas.px(img, at.x + (w >> 1), at.y + 1, col)
		"dot":
			PixelCanvas.px(img, at.x + (w >> 1), at.y + 1, col)
			PixelCanvas.px(img, at.x + (w >> 1) - 1, at.y + 1, col)
		"ogonek":
			PixelCanvas.px(img, at.x + w - 1, at.y + LINE - 1, col)


## Atlas wszystkich glifów w danym kolorze: komórki CELL_W×LINE w jednym rzędzie.
static func _atlas(col: Color) -> ImageTexture:
	var key := col.to_rgba32()
	if _atlases.has(key):
		return _atlases[key]
	var chars: Array[String] = []
	for ch: String in GLYPHS:
		chars.append(ch)
	for ch: String in ACCENTED:
		chars.append(ch)
	var img := Image.create(chars.size() * CELL_W, LINE, false, Image.FORMAT_RGBA8)
	for i in chars.size():
		_index[chars[i]] = i
		_blit_glyph(img, Vector2i(i * CELL_W, 0), chars[i], col)
	var tex := ImageTexture.create_from_image(img)
	_atlases[key] = tex
	return tex
