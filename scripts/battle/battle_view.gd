class_name BattleView
extends Node2D
## Widok bitwy na mapie zamku (#15). Jednostki nie są ludzikami: jeden oddział to ikona klasy
## na ciemnym tle z ramką w kolorze strony, liczba żywych jednostek, nad ikoną pasek morale (#98)
## i pod nią pasek zdrowia oddziału. Pod odznakami efekty (#101): pociski, pył, ogień i dym.
## Symulacja liczy się w _physics_process w stałym kroku (BattleConfig.TICK_HZ), a rysowanie
## tylko czyta jej stan, więc widok nie wpływa na przebieg.
## Po teście na telefonie (jednostki „przechodziły przez cały mur”):
## - mapa pod bitwą rysuje stan zniszczeń budynków (states_changed → CastleView.draw_buildings);
## - odznaka oddziału stoi na jednej z jego jednostek (Battle.squads_view: najbliższej środka), a nie w średniej,
##   która przy oddziale rozdzielonym murem wypadała na murze;
## - każda jednostka ma kropkę w kolorze strony, więc widać, gdzie naprawdę stoją;
## - odznaka, która musiała zejść niżej, żeby nie zasłonić innej, trzyma swój wiersz, dopóki nie zwolni
##   się miejsce na dłużej (SETTLE_FRAMES), zamiast skakać co klatkę.

## Stan zniszczeń budynków zmienił się (id → BuildingTypes.State); mapa ma się przerysować.
signal states_changed(states: Dictionary)

## Ramka oddziału: ikona 5×5 z obwódką 1 px.
const BADGE := PixelIcons.SIZE + 2
const BAR_H := 1
## Wysokość wiersza przy rozsuwaniu odznak: odznaka, pasek i 1 px odstępu.
## Odznaka od góry: pasek morale, ikona, pasek zdrowia.
const ROW := BAR_H + BADGE + BAR_H + 1
## Ile klatek z rzędu miejsce bliżej jednostki musi być wolne, zanim odznaka wróci na nie.
const SETTLE_FRAMES := 20
## Kropka jednostki: 2×2 px w kolorze strony.
const DOT := 2
## Generał (#31): drzewce proporca nad kropką i pasek zdrowia pod nią.
const GENERAL_POLE := 5
const GENERAL_BAR := 4

var battle: Battle
var running := true
## Tempo bitwy (1, 2 albo 4): ile kroków symulacji na krok czasu; samouczek #16 pozwala tylko na to.
var speed := 1
var effects := BattleEffects.new()
## Czas efektów w tickach: w trakcie bitwy to battle.tick, po jej końcu liczy dalej, żeby pociski
## doleciały, a pył opadł, zamiast zastygnąć na ostatniej klatce.
var fx_tick := 0
var _acc_us := 0
## Ostatni wysłany stan zniszczeń (id → BuildingTypes.State).
var states: Dictionary = {}
## Wiersz odznaki (klucz oddziału → przesunięcie w wierszach) i ile klatek miejsce niżej jest wolne.
var _rows: Dictionary = {}
var _free: Dictionary = {}


func _ready() -> void:
	if battle != null:
		battle.record_fx = true


func _physics_process(delta: float) -> void:
	if battle == null or not running:
		return
	_acc_us += int(delta * 1000000.0) * speed
	var tick_us := 1000000 / BattleConfig.TICK_HZ
	while _acc_us >= tick_us:
		_acc_us -= tick_us
		if battle.winner == Battle.Winner.NONE:
			battle.step()
			fx_tick = battle.tick
		else:
			fx_tick += 1
	effects.add_events(battle.take_fx())
	effects.prune(fx_tick)
	var now := states_of(battle)
	if now != states:
		states = now
		states_changed.emit(states)
	queue_redraw()


## Stan zniszczeń każdego budynku bitwy, który nie jest już cały (id → BuildingTypes.State).
static func states_of(b: Battle) -> Dictionary:
	var out := {}
	for id: int in b.structures:
		var s: Battle.Structure = b.structures[id]
		var st := BuildingTypes.state_for_hp(s.hp, s.max_hp)
		if st != BuildingTypes.State.INTACT:
			out[id] = st
	return out


func _draw() -> void:
	if battle == null:
		return
	effects.draw(self, battle, fx_tick)
	for f in battle.fighters:
		if f.alive():
			var p := dot_origin(f.x, f.y)
			draw_rect(Rect2(p.x, p.y, DOT, DOT), side_color(f.side))
	var squads: Array[Dictionary] = []
	var sides: Array[int] = []
	for side: int in [Battle.Side.DEFENDER, Battle.Side.ATTACKER]:
		for sq in battle.squads_view(side):
			squads.append(sq)
			sides.append(side)
	var origins := layout(squads, _rows, _free)
	for i in squads.size():
		draw_squad(self, squads[i], sides[i], origins[i])
	for side: int in [Battle.Side.DEFENDER, Battle.Side.ATTACKER]:
		var gv := battle.general_view(side)
		if not gv.is_empty():
			draw_general(self, gv, side)


## Lewy górny róg kropki jednostki w pozycji (`x`, `y`) w podjednostkach (całe piksele).
static func dot_origin(x: int, y: int) -> Vector2i:
	@warning_ignore("integer_division")
	return Vector2i(x * TerrainMap.CELL / BattleConfig.SUB - DOT / 2, y * TerrainMap.CELL / BattleConfig.SUB - DOT / 2)


## Miejsca odznak bez nakładania: odznaka, która zachodzi na wcześniejszą, schodzi niżej o jeden
## wiersz (kolejność stała, więc układ też). Tylko wygląd, symulacja tego nie widzi.
## Z pamięcią `rows`/`free` (słowniki widoku, klucz oddziału z Battle.squads_view) odznaka trzyma wiersz
## z poprzedniej klatki, póki jest wolny, a wraca wyżej dopiero, gdy miejsce bliżej jednostki jest
## wolne przez SETTLE_FRAMES klatek z rzędu. Bez tego dwie mijające się odznaki przeskakiwały nad
## sobą co klatkę (po teście na telefonie).
static func layout(squads: Array[Dictionary], rows: Dictionary = {}, free: Dictionary = {}) -> Array[Vector2i]:
	var placed: Array[Rect2i] = []
	var out: Array[Vector2i] = []
	for sq in squads:
		var key: int = int(sq.get("key", -1))
		var base := Rect2i(badge_origin(sq), badge_size(sq))
		var prev: int = int(rows.get(key, 0))
		var order: Array[int] = [prev]
		for k in squads.size() + 1:
			if k != prev:
				order.append(k)
		var row := order[-1]
		for k in order:
			if _row_free(base, k, placed):
				row = k
				break
		if row == prev and prev > 0:
			var lowest := -1
			for k in prev:
				if _row_free(base, k, placed):
					lowest = k
					break
			if lowest >= 0:
				free[key] = int(free.get(key, 0)) + 1
				if int(free[key]) >= SETTLE_FRAMES:
					row = lowest
					free[key] = 0
			else:
				free[key] = 0
		rows[key] = row
		var r := Rect2i(base.position + Vector2i(0, row * ROW), base.size)
		placed.append(r)
		out.append(r.position)
	return out


static func _row_free(base: Rect2i, row: int, placed: Array[Rect2i]) -> bool:
	var r := Rect2i(base.position + Vector2i(0, row * ROW), base.size)
	for p in placed:
		if p.intersects(r):
			return false
	return true


## Odznaka z liczbą i paskiem zdrowia, w pikselach.
static func badge_size(sq: Dictionary) -> Vector2i:
	return Vector2i(BADGE + PixelFont.text_width(str(int(sq["alive"]))) + 2, ROW - 1)


## Szerokość wypełnienia paska morale (0..BADGE).
static func morale_fill(sq: Dictionary) -> int:
	@warning_ignore("integer_division")
	return clampi(BADGE * int(sq.get("morale", 0)) / BattleConfig.MORALE_MAX, 0, BADGE)


## Kolor paska morale: złoty, a poniżej progu wycofania w kolorze akcentu.
static func morale_color(sq: Dictionary) -> Color:
	return Palette.ACCENT if int(sq.get("morale", 0)) < BattleConfig.MORALE_ROUT else Palette.THATCH[2]


## Lewy górny róg odznaki oddziału w pikselach mapy (całe piksele, środek na pozycji oddziału).
static func badge_origin(sq: Dictionary) -> Vector2i:
	@warning_ignore("integer_division")
	var px := int(sq["x"]) * TerrainMap.CELL / BattleConfig.SUB
	@warning_ignore("integer_division")
	var py := int(sq["y"]) * TerrainMap.CELL / BattleConfig.SUB
	@warning_ignore("integer_division")
	return Vector2i(px - BADGE / 2, py - BADGE / 2)


## Szerokość wypełnienia paska zdrowia (0..BADGE); żywy oddział ma co najmniej 1 px.
static func hp_fill(sq: Dictionary) -> int:
	var max_hp := maxi(1, int(sq["max_hp"]))
	@warning_ignore("integer_division")
	return clampi(maxi(1, BADGE * int(sq["hp"]) / max_hp), 1, BADGE)


static func side_color(side: int) -> Color:
	return Palette.SIDE_ATTACKER if side == Battle.Side.ATTACKER else Palette.SIDE_DEFENDER


## Generał (#31): złoty proporzec na drzewcu nad kropką postaci i pod nią pasek zdrowia (całe piksele).
static func draw_general(ci: CanvasItem, gv: Dictionary, side: int) -> void:
	var p := dot_origin(int(gv["x"]), int(gv["y"]))
	ci.draw_rect(Rect2(p.x, p.y - GENERAL_POLE, 1, GENERAL_POLE), Palette.WOOD[0])
	ci.draw_rect(Rect2(p.x + 1, p.y - GENERAL_POLE, 3, 2), Palette.THATCH[2])
	ci.draw_rect(Rect2(p.x + 1, p.y - GENERAL_POLE + 2, 3, 1), side_color(side))
	var max_hp := maxi(1, int(gv["max_hp"]))
	@warning_ignore("integer_division")
	var fill := clampi(maxi(1, GENERAL_BAR * int(gv["hp"]) / max_hp), 1, GENERAL_BAR)
	ci.draw_rect(Rect2(p.x - 1, p.y + DOT + 1, GENERAL_BAR, BAR_H), Palette.SHADOW)
	ci.draw_rect(Rect2(p.x - 1, p.y + DOT + 1, fill, BAR_H), Palette.VALID)


static func draw_squad(ci: CanvasItem, sq: Dictionary, side: int, top: Vector2i) -> void:
	ci.draw_rect(Rect2(top.x, top.y, BADGE, BAR_H), Palette.SHADOW)
	ci.draw_rect(Rect2(top.x, top.y, morale_fill(sq), BAR_H), morale_color(sq))
	var at := top + Vector2i(0, BAR_H)
	var col := side_color(side)
	ci.draw_rect(Rect2(at.x, at.y, BADGE, BADGE), col)
	ci.draw_rect(Rect2(at.x + 1, at.y + 1, BADGE - 2, BADGE - 2), Palette.SHADOW)
	var unit := int(sq["unit"])
	var cls := UnitTypes.unit_class(unit)
	if PixelIcons.class_region(cls).has_area():
		PixelIcons.draw_class(ci, Vector2(at + Vector2i.ONE), cls)
	else:
		# inżynieria nie ma ikony klasy: pierwsza litera nazwy
		PixelFont.draw_centered(ci, Rect2(at.x, at.y, BADGE, BADGE), UnitTypes.SHORT_NAMES[unit].left(1), Palette.INK)
	ci.draw_rect(Rect2(at.x, at.y + BADGE, BADGE, BAR_H), Palette.SHADOW)
	ci.draw_rect(Rect2(at.x, at.y + BADGE, hp_fill(sq), BAR_H), Palette.VALID)
	var text := str(int(sq["alive"]))
	ci.draw_rect(Rect2(at.x + BADGE, at.y, PixelFont.text_width(text) + 2, BADGE), Palette.SHADOW)
	PixelFont.draw_text(ci, Vector2(at.x + BADGE + 1, at.y - 1), text, col)
