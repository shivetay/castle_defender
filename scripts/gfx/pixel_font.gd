class_name PixelFont
extends RefCounted
## Font pikselowy zdefiniowany w kodzie (bez plików fontów). Wielkie litery 3–5 px szerokości
## i 5 px wysokości z polskimi znakami. Glify są lekkie (#327): zaokrąglone narożniki cyfr i krótkie
## belki środkowe, żeby tekst nie wyglądał na gruby. Linia ma 8 px: wiersze 0–1 to akcenty (Ć, Ó, Ż...),
## 2–6 litera, 7 ogonek (Ą, Ę) albo przecinek. Małe litery rysuje się jako wielkie.
## Atlas glifów powstaje raz dla każdego koloru z palety i jest trzymany w cache.
## Skróty surowców (EconomyConfig.SHORT_NAMES: Dr, Ka, Ży, Zł) jako osobne słowo rysują się
## ikoną z paska surowców (PixelIcons), np. „120 Dr” to liczba i ikona drewna.

const LINE := 8
const CAP_TOP := 2
const CELL_W := 6

## Glif: wiersze od góry litery (5 wierszy, opcjonalnie 6. pod linią bazową), '#' = piksel.
const GLYPHS := {
	"A": [".##.", "#..#", "####", "#..#", "#..#"],
	"B": ["###.", "#..#", "##..", "#..#", "###."],
	"C": [".###", "#...", "#...", "#...", ".###"],
	"D": ["###.", "#..#", "#..#", "#..#", "###."],
	"E": ["####", "#...", "##..", "#...", "####"],
	"F": ["####", "#...", "###.", "#...", "#..."],
	"G": [".##.", "#...", "#.##", "#..#", ".##."],
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
	"S": [".###", "#...", ".##.", "...#", "##.."],
	"T": ["###", ".#.", ".#.", ".#.", ".#."],
	"U": ["#..#", "#..#", "#..#", "#..#", ".##."],
	"V": ["#...#", "#...#", ".#.#.", ".#.#.", "..#.."],
	"W": ["#...#", "#...#", "#.#.#", "#.#.#", ".#.#."],
	"X": ["#..#", "#..#", ".##.", "#..#", "#..#"],
	"Y": ["#.#", "#.#", ".#.", ".#.", ".#."],
	"Z": ["####", "...#", ".##.", "#...", "####"],
	"0": [".#.", "#.#", "#.#", "#.#", ".#."],
	"1": [".#.", "##.", ".#.", ".#.", ".#."],
	"2": ["##.", "..#", ".#.", "#..", "###"],
	"3": ["##.", "..#", ".##", "..#", "##."],
	"4": ["#.#", "#.#", "###", "..#", "..#"],
	"5": ["###", "#..", "##.", "..#", "##."],
	"6": [".##", "#..", "###", "#.#", ".#."],
	"7": ["###", "..#", "..#", ".#.", ".#."],
	"8": [".#.", "#.#", "###", "#.#", ".#."],
	"9": [".#.", "#.#", "###", "..#", "##."],
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
	"<": ["..#", ".#.", "#..", ".#.", "..#"],
	">": ["#..", ".#.", "..#", ".#.", "#.."],
}
## Polskie litery: litera bazowa i znak diakrytyczny (kreska, kropka albo ogonek).
const ACCENTED := {
	"Ą": ["A", "ogonek"], "Ć": ["C", "acute"], "Ę": ["E", "ogonek"], "Ń": ["N", "acute"],
	"Ó": ["O", "acute"], "Ś": ["S", "acute"], "Ź": ["Z", "acute"], "Ż": ["Z", "dot"],
}

static var _atlases: Dictionary[int, ImageTexture] = {}
static var _index: Dictionary[String, int] = {}


## Początek tokenu ikony surowca w `tokens` (po nim numer surowca); żaden glif go nie używa.
const ICON_MARK := "@"


## Szerokość tekstu w pikselach (odstęp 1 px między znakami, bez odstępu na końcu).
static func text_width(text: String) -> int:
	var w := 0
	for tok in tokens(text):
		w += token_width(tok) + 1
	return maxi(w - 1, 0)


static func glyph_width(ch: String) -> int:
	var rows: Array = _rows(ch)
	return (rows[0] as String).length()


## Szerokość tokenu z `tokens`: glifu albo ikony surowca.
static func token_width(tok: String) -> int:
	return PixelIcons.SIZE if tok.begins_with(ICON_MARK) else glyph_width(tok)


## Tekst jako tokeny do rysowania: wielkie litery fontu, a skrót surowca będący osobnym słowem
## (np. „Ży” w „12 Ży/h”) jako jeden token ICON_MARK + numer surowca.
static func tokens(text: String) -> PackedStringArray:
	var out: PackedStringArray = []
	var i := 0
	while i < text.length():
		var res := _resource_at(text, i)
		if res >= 0:
			out.append(ICON_MARK + str(res))
			i += EconomyConfig.SHORT_NAMES[res].length()
			continue
		for ch in _normalize(text[i]):
			out.append(ch)
		i += 1
	return out


## Numer surowca, którego skrót zaczyna się w `text` na pozycji `i` jako całe słowo, albo -1.
static func _resource_at(text: String, i: int) -> int:
	if i > 0 and _is_letter(text[i - 1]):
		return -1
	for res in EconomyConfig.SHORT_NAMES.size():
		var short: String = EconomyConfig.SHORT_NAMES[res]
		var end := i + short.length()
		if text.substr(i, short.length()) == short and (end >= text.length() or not _is_letter(text[end])):
			return res
	return -1


static func _is_letter(ch: String) -> bool:
	return ch.to_upper() != ch.to_lower()


## Rysuje tekst na CanvasItem. `pos` to lewy górny róg linii (8 px wysokości).
static func draw_text(ci: CanvasItem, pos: Vector2, text: String, col: Color) -> void:
	var atlas := _atlas(col)
	var x := floorf(pos.x)
	var y := floorf(pos.y)
	for tok in tokens(text):
		var w := token_width(tok)
		if tok.begins_with(ICON_MARK):
			PixelIcons.draw_resource(ci, Vector2(x, y + CAP_TOP), tok.substr(1).to_int())
		else:
			var src := Rect2(_index[tok] * CELL_W, 0, w, LINE)
			ci.draw_texture_rect_region(atlas, Rect2(x, y, w, LINE), src)
		x += w + 1


## Dzieli tekst na linie najwyżej `max_width` px, po słowach. Słowo dłuższe niż linia zostaje
## przycięte do szerokości (bez zawijania w środku słowa). Najwyżej `max_lines` linii (0 = bez
## limitu); gdy tekst się nie mieści, ostatnia linia kończy się „...”.
static func wrap(text: String, max_width: int, max_lines: int = 0) -> PackedStringArray:
	var lines: PackedStringArray = []
	var line := ""
	for word in text.split(" ", false):
		var candidate := word if line.is_empty() else line + " " + word
		if text_width(candidate) <= max_width or line.is_empty():
			line = candidate
		else:
			lines.append(line)
			line = word
	if not line.is_empty():
		lines.append(line)
	for i in lines.size():
		lines[i] = _fit(lines[i], max_width)
	if max_lines > 0 and lines.size() > max_lines:
		var rest := lines.slice(0, max_lines)
		rest[max_lines - 1] = _fit(rest[max_lines - 1] + "...", max_width, true)
		return rest
	return lines


## Przycina linię do `max_width` px, z „...” na końcu, gdy coś ucina (albo gdy `force_dots`).
static func _fit(text: String, max_width: int, force_dots: bool = false) -> String:
	if text_width(text) <= max_width:
		return text
	if max_width < text_width("..."):
		return ""  # patologiczna strefa bezpieczna: nawet wielokropek się nie mieści
	var out := text.trim_suffix("...") if force_dots else text
	while out.length() > 0 and text_width(out + "...") > max_width:
		out = out.substr(0, out.length() - 1)
	return out.strip_edges() + "..."


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
	for tok in tokens(text):
		if tok.begins_with(ICON_MARK):
			var s := PixelIcons.SIZE
			img.blend_rect(PixelIcons.make_atlas(), Rect2i(tok.substr(1).to_int() * s, 0, s, s),
					Vector2i(x, pos.y + CAP_TOP))
		else:
			_blit_glyph(img, Vector2i(x, pos.y), tok, col)
		x += token_width(tok) + 1


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
