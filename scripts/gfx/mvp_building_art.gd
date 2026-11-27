class_name MvpBuildingArt
extends RefCounted
## Rysunki pozostałych budynków MVP (#35) w rzucie z góry, w tym samym stylu co BuildingArt: światło
## z lewej góry, kolory wyłącznie z palety epoki, faktura z PixelCanvas.hash2. Każdy budynek ma
## 5 poziomów o różnym wyglądzie; stany zniszczeń dokłada BuildingArt._apply_state.
## Kamień nie ma w palecie epoki I osobnej szarości, więc ciosy i skała są w jasnych ziemiach
## i strzesze (piaskowiec), a szczeliny w cieniu.
@warning_ignore_start("integer_division")


## Czy punkt (`x`, `y`) obrazu `w`×`w` leży w kole o promieniu `r` (w połówkach piksela) wokół środka.
static func _in_disc(x: int, y: int, w: int, r: int) -> bool:
	var dx := 2 * x + 1 - w
	var dy := 2 * y + 1 - w
	return dx * dx + dy * dy <= r * r


## Fosa sucha (1×1): rów wykopany przez całą kratkę, więc sąsiednie odcinki tworzą ciągły rów
## w każdym kierunku. Dno z ciemnej ziemi z grudami; poziomy: 1 sam rów, 2 grudy jasnej ziemi,
## 3–5 coraz więcej zaostrzonych pali w dnie (2, 4, 6).
static func draw_dry_moat(img: Image, level: int) -> void:
	var w := img.get_width()
	for y in w:
		for x in w:
			var col := PixelCanvas.dither(x, y, Palette.EARTH[1], Palette.EARTH[0])
			if PixelCanvas.hash2(x, y, 211) % 7 == 0:
				col = Palette.EARTH[2]
			PixelCanvas.px(img, x, y, col)
	if level >= 2:
		for c: Vector2i in [Vector2i(1, 5), Vector2i(6, 2)]:
			PixelCanvas.px(img, c.x, c.y, Palette.EARTH[3])
			PixelCanvas.px(img, c.x + 1, c.y, Palette.EARTH[2])
	# pale: ciemny trzon i jasny, zaostrzony wierzch
	var stakes: Array[Vector2i] = [Vector2i(2, 2), Vector2i(5, 5), Vector2i(5, 1), Vector2i(2, 6),
			Vector2i(0, 4), Vector2i(7, 3)]
	var n := 0 if level < 3 else (level - 2) * 2
	for i in n:
		var s := stakes[i]
		PixelCanvas.px(img, s.x, s.y, Palette.WOOD[3])
		PixelCanvas.px(img, s.x, s.y + 1, Palette.WOOD[1])


## Kopiec (2×2): usypane wzgórze z trawiastymi zboczami, jaśniejsze od północnego zachodu.
## Poziomy: 1 goła ziemia, 2 zbocza obrośnięte trawą, 3 częstokół wokół szczytu, 4 schody z bali
## od południa, 5 proporzec na szczycie.
static func draw_mound(img: Image, level: int) -> void:
	var w := img.get_width()
	var r := 13 if level == 1 else 15
	for y in w:
		for x in w:
			if not _in_disc(x, y, w, r):
				continue
			var dx := 2 * x + 1 - w
			var dy := 2 * y + 1 - w
			var d := dx * dx + dy * dy
			var col: Color
			if level == 1:
				col = Palette.EARTH[1] if d > 100 else (Palette.EARTH[2] if d > 36 else Palette.EARTH[3])
			else:
				col = Palette.GRASS[0] if d > 144 else (Palette.GRASS[1] if d > 64 else Palette.GRASS[2])
				if d <= 25:
					col = Palette.EARTH[3]  # ubity szczyt
			# zbocze od północnego zachodu w świetle
			if dx + dy < -6 and d > 36:
				col = Palette.GRASS[2] if level >= 2 and d > 64 else (Palette.GRASS[3] if level >= 2 else Palette.EARTH[2])
			PixelCanvas.px(img, x, y, col)
	if level >= 3:
		# częstokół: ring pali wokół szczytu
		for y in w:
			for x in w:
				var dx := 2 * x + 1 - w
				var dy := 2 * y + 1 - w
				var d := dx * dx + dy * dy
				if d > 36 and d <= 64 and (x + y) % 2 == 0:
					PixelCanvas.px(img, x, y, Palette.WOOD[1])
	if level >= 4:
		# schody z bali od południa
		for y in range(11, 15):
			PixelCanvas.px(img, 7, y, Palette.WOOD[2])
			PixelCanvas.px(img, 8, y, Palette.WOOD[2] if y % 2 == 0 else Palette.WOOD[1])
	if level == 5:
		PixelCanvas.pennant(img, Vector2i(7, 6), Palette.ACCENT)


## Pole i spichlerz (3×2, #340): pole zboża w rzędach i spichlerz pod strzechą w rogu. Poziomy: 1 grządka
## z zielonym zbożem i mały spichlerz, 2 całe pole, 3 zboże dojrzewa (złote), 4 większy spichlerz
## na palach, 5 snopy na skraju pola.
static func draw_farm(img: Image, level: int) -> void:
	# większe pole (#340): pole sięga prawego i dolnego brzegu, spichlerz stoi w prawym górnym rogu
	var size := img.get_size()
	var extra := size - Vector2i(16, 16)
	var field := Rect2i(1, 7, size.x - 2, size.y - 8) if level >= 2 else Rect2i(1, 9 + extra.y, 9, 6)
	for y in range(field.position.y, field.end.y):
		for x in range(field.position.x, field.end.x):
			PixelCanvas.px(img, x, y, PixelCanvas.dither(x, y, Palette.EARTH[2], Palette.EARTH[1]))
	var grain: Color = Palette.THATCH[2] if level >= 3 else Palette.GRASS[3]
	var stalk: Color = Palette.THATCH[1] if level >= 3 else Palette.GRASS[2]
	for y in range(field.position.y, field.end.y, 2):
		for x in range(field.position.x, field.end.x):
			PixelCanvas.px(img, x, y, grain if PixelCanvas.hash2(x, y, 223) % 3 != 0 else stalk)
	# spichlerz: korpus z desek i dach dwuspadowy z kalenicą wzdłuż
	var barn := Rect2i(8 + extra.x, 1, 7, 5) if level < 4 else Rect2i(6 + extra.x, 1, 9, 6)
	if level >= 4:
		# pale pod spichlerzem (chronią zboże przed wilgocią i myszami)
		for c: Vector2i in [Vector2i(barn.position.x, barn.end.y), Vector2i(barn.end.x - 1, barn.end.y)]:
			PixelCanvas.px(img, c.x, c.y, Palette.WOOD[0])
	PixelCanvas.rect(img, barn, Palette.WOOD[1])
	PixelCanvas.roof_gable(img, Rect2i(barn.position.x, barn.position.y, barn.size.x, barn.size.y - 1), true,
			Palette.THATCH, Palette.WOOD[1], 227)
	PixelCanvas.px(img, barn.position.x + 1, barn.end.y - 1, Palette.WOOD[0])  # drzwi
	if level == 5:
		for sx: int in [1, 4]:
			PixelCanvas.rect(img, Rect2i(sx, 2, 2, 3), Palette.THATCH[1])
			PixelCanvas.px(img, sx, 2, Palette.THATCH[2])
			PixelCanvas.px(img, sx + 1, 3, Palette.WOOD[1])  # powrósło


## Studnia (2×2): cembrowina wokół wody, z poziomem coraz porządniej. Poziomy: 1 ziemny wylot z wodą,
## 2 cembrowina z ciosów i kołowrót, 3 wiadro i koryto z wodą, 4 bruk dookoła, 5 daszek nad kołowrotem.
static func draw_well(img: Image, level: int) -> void:
	var w := img.get_width()
	if level >= 4:
		for y in range(1, w - 1):
			for x in range(1, w - 1):
				if _in_disc(x, y, w, 15):
					var col := PixelCanvas.dither(x, y, Palette.EARTH[3], Palette.EARTH[2])
					if PixelCanvas.hash2(x, y, 233) % 5 == 0:
						col = Palette.THATCH[1]
					PixelCanvas.px(img, x, y, col)
	for y in w:
		for x in w:
			var dx := 2 * x + 1 - w
			var dy := 2 * y + 1 - w
			var d := dx * dx + dy * dy
			if d > 100:
				continue
			var col: Color
			if d <= 36:
				col = Palette.WATER[1] if (dx + dy) < 0 else Palette.WATER[0]
			elif level == 1:
				col = Palette.EARTH[1] if dx + dy > 0 else Palette.EARTH[2]
			else:
				# ciosy cembrowiny: jaśniejsze od lewej góry, spoiny co kilka pikseli
				col = Palette.THATCH[1] if dx + dy < 0 else Palette.THATCH[0]
				if PixelCanvas.hash2(x, y, 239) % 4 == 0:
					col = Palette.EARTH[2]
			PixelCanvas.px(img, x, y, col)
	if level >= 2:
		# kołowrót w poprzek wylotu na dwóch słupkach
		PixelCanvas.rect(img, Rect2i(3, 7, 10, 1), Palette.WOOD[2])
		PixelCanvas.px(img, 3, 7, Palette.WOOD[0])
		PixelCanvas.px(img, 12, 7, Palette.WOOD[0])
	if level >= 3:
		PixelCanvas.rect(img, Rect2i(8, 8, 2, 2), Palette.WOOD[1])  # wiadro
		PixelCanvas.px(img, 8, 8, Palette.WOOD[3])
		PixelCanvas.rect(img, Rect2i(1, 12, 5, 3), Palette.WOOD[1])  # koryto
		PixelCanvas.rect(img, Rect2i(2, 13, 3, 1), Palette.WATER[2])
	if level == 5:
		PixelCanvas.roof_gable(img, Rect2i(4, 3, 8, 4), true, Palette.THATCH, Palette.WOOD[1], 241)
		PixelCanvas.px(img, 12, 3, Palette.ACCENT)


## Kamieniołom (3×2, #340): wyrobisko schodzące tarasami w głąb, z ciosami gotowymi do wywózki. Poziomy:
## 1 płytkie wyrobisko, 2 drugi taras i stos ciosów, 3 żuraw z bali, 4 rampa z deskami do wywózki,
## 5 drugi stos ciosów i proporzec na żurawiu.
static func draw_quarry(img: Image, level: int) -> void:
	# większe wyrobisko (#340): ciosy i pomost przy prawym i dolnym brzegu
	var size := img.get_size()
	var extra := size - Vector2i(16, 16)
	var pit := Rect2i(1, 1, size.x - 2, size.y - 2) if level >= 2 else Rect2i(2, 2, 11 + extra.x, 11 + extra.y)
	for y in range(pit.position.y, pit.end.y):
		for x in range(pit.position.x, pit.end.x):
			var edge := mini(mini(x - pit.position.x, pit.end.x - 1 - x), mini(y - pit.position.y, pit.end.y - 1 - y))
			var col: Color
			if edge == 0:
				col = Palette.THATCH[1]
			elif edge <= 2:
				col = Palette.THATCH[0]
			elif edge <= 4 and level >= 2:
				col = Palette.EARTH[2]
			else:
				col = Palette.EARTH[1]
			if PixelCanvas.hash2(x, y, 251) % 9 == 0:
				col = Palette.SHADOW  # szczelina w skale
			PixelCanvas.px(img, x, y, col)
	if level >= 2:
		_blocks(img, Vector2i(10, 10) + extra)
	if level >= 3:
		# żuraw: słup w rogu i wysięgnik nad wyrobiskiem
		PixelCanvas.rect(img, Rect2i(2, 2, 2, 2), Palette.WOOD[1])
		for i in 6:
			PixelCanvas.px(img, 4 + i, 4 + i / 2, Palette.WOOD[2])
		PixelCanvas.px(img, 10, 7, Palette.WOOD[0])  # hak z liną
	if level >= 4:
		PixelCanvas.deck(img, Rect2i(12 + extra.x, 2, 3, 6), false, Palette.WOOD, 257)
	if level == 5:
		_blocks(img, Vector2i(3, 11 + extra.y))
		PixelCanvas.pennant(img, Vector2i(2, 1), Palette.ACCENT)


## Stos dwóch ciosów 2×2 z jasnym wierzchem.
static func _blocks(img: Image, at: Vector2i) -> void:
	for o: Vector2i in [Vector2i.ZERO, Vector2i(2, 1)]:
		PixelCanvas.rect(img, Rect2i(at + o, Vector2i(2, 2)), Palette.THATCH[0])
		PixelCanvas.px(img, at.x + o.x, at.y + o.y, Palette.THATCH[2])


## Wieża sygnałowa (2×2): wysoki pomost z koszem ogniska sygnałowego. Poziomy: 1 pomost z ogniskiem,
## 2 balustrada, 3 daszek namiotowy nad czatownią (ogień w rogu), 4 drugi kosz z ogniem, 5 proporzec.
static func draw_signal_tower(img: Image, level: int) -> void:
	var w := img.get_width()
	var platform := Rect2i(2, 2, w - 4, w - 4)
	PixelCanvas.deck(img, platform, level % 2 == 0, Palette.WOOD, 263)
	# słupy w rogach pomostu
	for c: Vector2i in [platform.position, Vector2i(platform.end.x - 1, platform.position.y),
			Vector2i(platform.position.x, platform.end.y - 1), platform.end - Vector2i.ONE]:
		PixelCanvas.px(img, c.x, c.y, Palette.WOOD[0])
	if level >= 2:
		PixelCanvas.frame(img, platform, Palette.WOOD[1])
	var fire := Vector2i(7, 7) if level < 3 else Vector2i(10, 10)
	if level >= 3:
		PixelCanvas.roof_hip(img, Rect2i(3, 3, 7, 7), Palette.THATCH, Palette.WOOD[1])
	_beacon(img, fire)
	if level >= 4:
		_beacon(img, Vector2i(10, 3))
	if level == 5:
		PixelCanvas.pennant(img, Vector2i(5, 5), Palette.ACCENT)


## Kosz z ogniem sygnałowym 2×2: żar, płomień i iskra.
static func _beacon(img: Image, at: Vector2i) -> void:
	PixelCanvas.rect(img, Rect2i(at, Vector2i(2, 2)), Palette.SHADOW)
	PixelCanvas.px(img, at.x, at.y, Palette.ACCENT)
	PixelCanvas.px(img, at.x + 1, at.y, Palette.THATCH[2])
	PixelCanvas.px(img, at.x, at.y + 1, Palette.THATCH[2])


## Targ (4×4, #408): ubity plac z czterema straganami pod pasiastymi daszkami (akcent i jasna strzecha),
## skrzynki i towar przed ladami, a pośrodku słup z proporcem. Targ nie ma poziomów, więc rysunek jeden.
static func draw_market(img: Image) -> void:
	var w := img.get_width()
	var h := img.get_height()
	# plac z ubitej ziemi z grudami
	for y in range(1, h - 1):
		for x in range(1, w - 1):
			var col := PixelCanvas.dither(x, y, Palette.EARTH[3], Palette.THATCH[0])
			if PixelCanvas.hash2(x, y, 409) % 7 == 0:
				col = Palette.EARTH[2]
			PixelCanvas.px(img, x, y, col)
	# cztery stragany w rogach placu, między nimi przejście w krzyż
	var stall := Vector2i(w / 2 - 3, h / 2 - 4)
	for i in 4:
		var at := Vector2i(2 + (i % 2) * (w / 2 - 1), 2 + (i / 2) * (h / 2 - 1))
		_stall(img, Rect2i(at, stall), i)
	# słup z proporcem na środku placu
	var mid := Vector2i(w / 2, h / 2)
	PixelCanvas.rect(img, Rect2i(mid - Vector2i(1, 1), Vector2i(2, 2)), Palette.WOOD[1])
	PixelCanvas.px(img, mid.x - 1, mid.y - 1, Palette.WOOD[3])
	PixelCanvas.pennant(img, Vector2i(mid.x, mid.y - 3), Palette.ACCENT)


## Stragan z góry: daszek w pasy (akcent i jasna strzecha) z ciemnym okapem od południa, pod nim lada
## z towarem; `variant` zmienia towar (skrzynki, chleby, zieleniny, worki).
static func _stall(img: Image, r: Rect2i, variant: int) -> void:
	var roof := Rect2i(r.position, Vector2i(r.size.x, r.size.y - 3))
	for y in range(roof.position.y, roof.end.y):
		for x in range(roof.position.x, roof.end.x):
			var stripe := ((x - roof.position.x) / 2) % 2 == 0
			var col := Palette.ACCENT if stripe else Palette.THATCH[2]
			if y == roof.end.y - 1:
				col = Palette.WOOD[0]  # okap w cieniu
			PixelCanvas.px(img, x, y, col)
	# lada pod daszkiem i towar na niej
	var counter := Rect2i(r.position.x, roof.end.y, r.size.x, 2)
	PixelCanvas.rect(img, counter, Palette.WOOD[2])
	PixelCanvas.rect(img, Rect2i(counter.position.x, counter.end.y - 1, counter.size.x, 1), Palette.WOOD[0])
	var goods: Array[Color] = [Palette.WOOD[3], Palette.THATCH[1], Palette.GRASS[2], Palette.THATCH[2]]
	for k in range(1, r.size.x - 1, 3):
		PixelCanvas.px(img, counter.position.x + k, counter.position.y, goods[variant % goods.size()])
	# skrzynka przy ladzie
	var crate := Vector2i(r.end.x - 2, r.end.y - 1)
	PixelCanvas.rect(img, Rect2i(crate, Vector2i(2, 1)), Palette.WOOD[1])
