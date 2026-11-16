class_name BattleEffects
extends RefCounted
## Efekty bitwy (#101): strzały, oszczepy i garnki smoły w locie, pył przy uderzeniach w budynki
## i przy zawaleniu, ogień i dym nad płonącymi budynkami. To tylko rysowanie: efekty powstają ze
## zdarzeń, które bitwa zapisuje dla widoku (Battle.take_fx), i z jej stanu (płonące budynki).
## Symulacja nic o nich nie wie, więc nie zmieniają przebiegu ani wyniku.
##
## Czas efektów to ticki bitwy, więc przy tempie x2 i x4 przyspieszają razem z nią. Rozrzut cząstek
## idzie przez PixelCanvas.hash2 z ticku i pozycji (ten sam przebieg daje ten sam obraz), a pozycje
## są w całych pikselach mapy.

## Rodzaj pocisku: strzała to kreska 1 px, oszczep i garnek lecą łukiem z cieniem na ziemi.
enum Missile { ARROW, JAVELIN, POT }
## Rodzaj efektu na liście.
enum Kind { MISSILE, DUST, COLLAPSE }

## Ile efektów naraz najwyżej (wydajność na telefonie); nadmiar najstarszych wypada.
const MAX_ITEMS := 192
## Prędkość pocisku w pikselach na tick i granice czasu lotu.
const MISSILE_PX_PER_TICK := 4
const MISSILE_MIN_TICKS := 3
const MISSILE_MAX_TICKS := 15
## Długość strzały i oszczepu w pikselach.
const ARROW_LEN := 3
const JAVELIN_LEN := 4
## Pył po uderzeniu: cząstki i czas; zawalenie: cząstki na kratkę budynku i czas.
const DUST_PARTICLES := 6
const DUST_TICKS := 12
const COLLAPSE_PER_CELL := 3
const COLLAPSE_TICKS := 30
## Dym nad ogniem: ile smug na kratkę, ile ticków wznosi się jedna i o ile pikseli.
const SMOKE_PER_CELL := 2
const SMOKE_TICKS := 36
const SMOKE_RISE := 12
## Języki ognia na kratkę budynku.
const FLAMES_PER_CELL := 3

## Efekt: [Kind, początek (tick), czas (ticki), x0, y0, x1, y1, podtyp] w pikselach mapy.
## Pocisk: od (x0, y0) do (x1, y1), podtyp Missile. Pył: punkt (x0, y0). Zawalenie: prostokąt
## (x0, y0, x1 = szerokość, y1 = wysokość).
var items: Array[PackedInt32Array] = []


## Rodzaj pocisku strzelca (jednostka albo Battle.FX_TOWER).
static func missile_for(unit: int) -> int:
	match unit:
		UnitTypes.Unit.JAVELINEER:
			return Missile.JAVELIN
		UnitTypes.Unit.FIRE_RAISER:
			return Missile.POT
	return Missile.ARROW


## Czas lotu pocisku na odległość w pikselach.
static func flight_ticks(dist_px: int) -> int:
	@warning_ignore("integer_division")
	return clampi(dist_px / MISSILE_PX_PER_TICK, MISSILE_MIN_TICKS, MISSILE_MAX_TICKS)


## Podjednostki bitwy → piksele mapy.
static func to_px(sub: int) -> int:
	@warning_ignore("integer_division")
	return sub * TerrainMap.CELL / BattleConfig.SUB


## Dodaje efekty ze zdarzeń bitwy.
func add_events(events: Array[PackedInt32Array]) -> void:
	for e in events:
		var t := e[0]
		match e[1]:
			Battle.Fx.SHOT:
				var a := Vector2i(to_px(e[3]), to_px(e[4]))
				var b := Vector2i(to_px(e[5]), to_px(e[6]))
				var d := maxi(absi(b.x - a.x), absi(b.y - a.y))
				_push(PackedInt32Array([Kind.MISSILE, t, flight_ticks(d), a.x, a.y, b.x, b.y, missile_for(e[2])]))
			Battle.Fx.HIT:
				_push(PackedInt32Array([Kind.DUST, t, DUST_TICKS, to_px(e[5]), to_px(e[6]), 0, 0, 0]))
			Battle.Fx.COLLAPSE:
				var c := TerrainMap.CELL
				_push(PackedInt32Array([Kind.COLLAPSE, t, COLLAPSE_TICKS, e[3] * c, e[4] * c, e[5] * c, e[6] * c, 0]))


func _push(item: PackedInt32Array) -> void:
	items.append(item)
	if items.size() > MAX_ITEMS:
		items.remove_at(0)


## Usuwa efekty, które już się skończyły.
func prune(tick: int) -> void:
	var keep: Array[PackedInt32Array] = []
	for it in items:
		if tick < it[1] + it[2]:
			keep.append(it)
	items = keep


## Postęp efektu w promilach (0 na starcie, 1000 na końcu).
static func progress(item: PackedInt32Array, tick: int) -> int:
	@warning_ignore("integer_division")
	return clampi((tick - item[1]) * 1000 / maxi(1, item[2]), 0, 1000)


## Pozycja pocisku na ziemi (bez wysokości łuku) w chwili `tick`.
static func missile_ground(item: PackedInt32Array, tick: int) -> Vector2i:
	var p := progress(item, tick)
	@warning_ignore("integer_division")
	return Vector2i(item[3] + (item[5] - item[3]) * p / 1000, item[4] + (item[6] - item[4]) * p / 1000)


## Wysokość łuku pocisku w pikselach: parabola z wierzchołkiem w połowie drogi. Strzała leci płasko.
static func missile_height(item: PackedInt32Array, tick: int) -> int:
	if item[7] == Missile.ARROW:
		return 0
	var p := progress(item, tick)
	var dist := maxi(absi(item[5] - item[3]), absi(item[6] - item[4]))
	@warning_ignore("integer_division")
	var peak := clampi(dist / 6, 2, 8)
	@warning_ignore("integer_division")
	return peak * 4 * p * (1000 - p) / 1000000


## Piksele kreski długości `length` kończącej się w `head`, skierowanej od `from` do `to`.
static func streak(head: Vector2i, from: Vector2i, to: Vector2i, length: int) -> Array[Vector2i]:
	var d := to - from
	var m := maxi(1, maxi(absi(d.x), absi(d.y)))
	var out: Array[Vector2i] = []
	for i in length:
		@warning_ignore("integer_division")
		out.append(head - Vector2i(d.x * i / m, d.y * i / m))
	return out


## Cząstki pyłu: rozchodzą się od punktu i lekko unoszą. Ten sam efekt i tick dają te same piksele.
static func dust_pixels(item: PackedInt32Array, tick: int) -> Array[Vector2i]:
	var age := tick - item[1]
	var out: Array[Vector2i] = []
	var n := DUST_PARTICLES
	var area := Vector2i.ONE
	if item[0] == Kind.COLLAPSE:
		@warning_ignore("integer_division")
		n = COLLAPSE_PER_CELL * maxi(1, item[5] / TerrainMap.CELL) * maxi(1, item[6] / TerrainMap.CELL)
		area = Vector2i(maxi(1, item[5]), maxi(1, item[6]))
	for i in n:
		var h := PixelCanvas.hash2(item[1] * 31 + i, item[3] * 131 + item[4], 0x0d057)
		var start := Vector2i(item[3] + h % area.x, item[4] + (h >> 8) % area.y)
		var dir := Vector2i((h >> 16) % 3 - 1, -1 - (h >> 18) % 2)
		@warning_ignore("integer_division")
		var step := age / 4
		out.append(start + dir * step)
	return out


## Płomienie nad budynkiem w prostokącie `rect` (piksele mapy): na każdą kratkę FLAMES_PER_CELL języków,
## które migoczą co 3 ticki. Zwraca [piksel, poziom koloru 0..2] (0: jasny czubek, 1–2: czerwony język).
static func flame_pixels(rect: Rect2i, tick: int) -> Array[Vector3i]:
	var out: Array[Vector3i] = []
	var c := TerrainMap.CELL
	@warning_ignore("integer_division")
	var phase := tick / 3
	for cy in range(rect.position.y, rect.end.y, c):
		for cx in range(rect.position.x, rect.end.x, c):
			for k in FLAMES_PER_CELL:
				var h := PixelCanvas.hash2(cx * 7 + k, cy * 13 + phase, 0xf17e)
				var x := cx + 1 + h % (c - 2)
				var base := cy + c - 1 - (h >> 6) % 4
				var height := 3 + (h >> 10) % 4
				for j in height:
					var level := 0 if j == height - 1 else (1 if j == height - 2 else 2)
					out.append(Vector3i(x, base - j, level))
	return out


## Smugi dymu nad płonącym budynkiem: unoszą się z jego górnej krawędzi i bledną.
## Zwraca [piksel, wiek w promilach].
static func smoke_pixels(rect: Rect2i, tick: int) -> Array[Vector3i]:
	var out: Array[Vector3i] = []
	var c := TerrainMap.CELL
	for cx in range(rect.position.x, rect.end.x, c):
		for k in SMOKE_PER_CELL:
			var h := PixelCanvas.hash2(cx * 5 + k, rect.position.y, 0x5e0e)
			var t := (tick + h % SMOKE_TICKS) % SMOKE_TICKS
			@warning_ignore("integer_division")
			var rise := t * SMOKE_RISE / SMOKE_TICKS
			@warning_ignore("integer_division")
			var drift := (t / 8) * ((h >> 8) % 3 - 1)
			@warning_ignore("integer_division")
			out.append(Vector3i(cx + (h >> 4) % c + drift, rect.position.y + 2 - rise, t * 1000 / SMOKE_TICKS))
	return out


## Rysuje efekty z listy i ogień płonących budynków bitwy.
func draw(ci: CanvasItem, battle: Battle) -> void:
	var tick := battle.tick
	for id: int in battle.structures:
		var s := battle.structures[id]
		if s.hp <= 0 or s.burning <= 0:
			continue
		var r := Rect2i(s.rect.position * TerrainMap.CELL, s.rect.size * TerrainMap.CELL)
		for p in smoke_pixels(r, tick):
			# kłąb 2×2, który z wiekiem blednie
			ci.draw_rect(Rect2(p.x, p.y, 2, 2), Color(Palette.SHADOW, 0.8 * (1.0 - p.z / 1000.0)))
		# czubek jasny, pod nim akcent i żar: ogień odcina się od strzechy
		var flame: Array[Color] = [Palette.THATCH[2], Palette.ACCENT, Palette.ACCENT]
		for p in flame_pixels(r, tick):
			ci.draw_rect(Rect2(p.x, p.y, 1, 1), flame[p.z])
	for it in items:
		if tick < it[1]:
			continue
		match it[0]:
			Kind.MISSILE:
				_draw_missile(ci, it, tick)
			Kind.DUST, Kind.COLLAPSE:
				var fade := 1.0 - progress(it, tick) / 1000.0
				var col := Color(Palette.THATCH[0] if it[0] == Kind.DUST else Palette.EARTH[2], 0.8 * fade)
				for p in dust_pixels(it, tick):
					ci.draw_rect(Rect2(p.x, p.y, 1, 1), col)


static func _draw_missile(ci: CanvasItem, it: PackedInt32Array, tick: int) -> void:
	var g := missile_ground(it, tick)
	var lift := Vector2i(0, missile_height(it, tick))
	var from := Vector2i(it[3], it[4])
	var to := Vector2i(it[5], it[6])
	match it[7]:
		Missile.ARROW:
			for p in streak(g, from, to, ARROW_LEN):
				ci.draw_rect(Rect2(p.x, p.y, 1, 1), Palette.INK)
		Missile.JAVELIN:
			ci.draw_rect(Rect2(g.x, g.y, 1, 1), Color(Palette.SHADOW, 0.6))
			for p in streak(g - lift, from, to, JAVELIN_LEN):
				ci.draw_rect(Rect2(p.x, p.y, 1, 1), Palette.WOOD[3])
		Missile.POT:
			ci.draw_rect(Rect2(g.x, g.y, 2, 1), Color(Palette.SHADOW, 0.6))
			var top := g - lift - Vector2i(0, 1)
			ci.draw_rect(Rect2(top.x, top.y, 2, 2), Palette.WOOD[1])
			ci.draw_rect(Rect2(top.x, top.y, 1, 1), Palette.ACCENT)
