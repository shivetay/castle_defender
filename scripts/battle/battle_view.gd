class_name BattleView
extends Node2D
## Widok bitwy na mapie zamku (#15). Jednostki nie są ludzikami: jeden oddział to ikona klasy
## na ciemnym tle z ramką w kolorze strony, liczba żywych jednostek, nad ikoną pasek morale (#98)
## i pod nią pasek zdrowia oddziału. Pod odznakami efekty (#101): pociski, pył, ogień i dym.
## Symulacja liczy się w _physics_process w stałym kroku (BattleConfig.TICK_HZ), a rysowanie
## tylko czyta jej stan, więc widok nie wpływa na przebieg.

## Ramka oddziału: ikona 5×5 z obwódką 1 px.
const BADGE := PixelIcons.SIZE + 2
const BAR_H := 1
## Wysokość wiersza przy rozsuwaniu odznak: odznaka, pasek i 1 px odstępu.
## Odznaka od góry: pasek morale, ikona, pasek zdrowia.
const ROW := BAR_H + BADGE + BAR_H + 1

var battle: Battle
var running := true
## Tempo bitwy (1, 2 albo 4): ile kroków symulacji na krok czasu; samouczek #16 pozwala tylko na to.
var speed := 1
var effects := BattleEffects.new()
var _acc_us := 0


func _ready() -> void:
	if battle != null:
		battle.record_fx = true


func _physics_process(delta: float) -> void:
	if battle == null or not running or battle.winner != Battle.Winner.NONE:
		return
	_acc_us += int(delta * 1000000.0) * speed
	var tick_us := 1000000 / BattleConfig.TICK_HZ
	while _acc_us >= tick_us and battle.winner == Battle.Winner.NONE:
		_acc_us -= tick_us
		battle.step()
	effects.add_events(battle.take_fx())
	effects.prune(battle.tick)
	queue_redraw()


func _draw() -> void:
	if battle == null:
		return
	effects.draw(self, battle)
	var squads: Array[Dictionary] = []
	var sides: Array[int] = []
	for side: int in [Battle.Side.DEFENDER, Battle.Side.ATTACKER]:
		for sq in battle.squads_view(side):
			squads.append(sq)
			sides.append(side)
	var origins := layout(squads)
	for i in squads.size():
		draw_squad(self, squads[i], sides[i], origins[i])


## Miejsca odznak bez nakładania: odznaka, która zachodzi na wcześniejszą, schodzi niżej o jeden
## wiersz (kolejność stała, więc układ też). Tylko wygląd, symulacja tego nie widzi.
static func layout(squads: Array[Dictionary]) -> Array[Vector2i]:
	var placed: Array[Rect2i] = []
	var out: Array[Vector2i] = []
	for sq in squads:
		var at := badge_origin(sq)
		var r := Rect2i(at, badge_size(sq))
		for attempt in squads.size():
			var hit := false
			for p in placed:
				if p.intersects(r):
					hit = true
					break
			if not hit:
				break
			r.position.y += ROW
		placed.append(r)
		out.append(r.position)
	return out


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
