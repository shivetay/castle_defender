class_name ResultPanel
extends Node2D
## Okno wyniku ataku (#99) na środku ekranu: tytuł, 3 gwiazdki (zdobyte złote, brakujące ciemne),
## procent zniszczeń, które warunki gwiazdek spełniono, łup (np. „50 Dr 50 Ka”), polegli i odblokowany
## zamek. Dalej zamyka okno. Okno samo obsługuje dotyk, więc nic nie trafia do kamery ani do HUD.
@warning_ignore_start("integer_division")

signal closed

const SIZE := Vector2(240, 150)
const BUTTON := Vector2(64, 16)
const WIN_TITLE := "Zamek zdobyty!"
const LOSS_TITLE := "Atak odparty"
const CLOSE_LABEL := "Dalej"
## Gwiazdka 9×7: '#' to piksel gwiazdki.
const STAR: Array[String] = ["....#....", "...###...", "#########", ".#######.", "..#####..", ".###.###.",
		"##.....##"]
const STAR_W := 9
const STAR_GAP := 6

var result: BattleResult
## Łup, który faktycznie wszedł do magazynu (po limicie).
var got: Array[int] = []
var fallen := 0
## Np. „Odblokowany: 2. Bobrowa Wola”; pusty, gdy nic się nie odblokowało.
var unlock_text := ""

var _pressed := false


func show_result(r: BattleResult, gained: Array[int], fallen_count: int, unlock: String) -> void:
	result = r
	got = gained
	fallen = fallen_count
	unlock_text = unlock
	visible = true
	_pressed = false
	queue_redraw()


func close() -> void:
	visible = false
	closed.emit()


static func panel_rect(view: Vector2) -> Rect2:
	return Rect2(((view - SIZE) / 2.0).floor(), SIZE)


static func close_rect(view: Vector2) -> Rect2:
	var p := panel_rect(view)
	return Rect2(Vector2(floorf(p.get_center().x - BUTTON.x / 2.0), p.end.y - BUTTON.y - 6), BUTTON)


## Linie pod gwiazdkami: [tekst, kolor].
static func lines(r: BattleResult, gained: Array[int], fallen_count: int, unlock: String) -> Array:
	var out: Array = [["Zniszczenia: %d%%" % r.percent, Palette.INK]]
	for i in BattleResult.STAR_NAMES.size():
		var ok: bool = r.stars[i]
		out.append([("+ " if ok else "- ") + BattleResult.STAR_NAMES[i], Palette.VALID if ok else Palette.WOOD[3]])
	var loot := Hud.cost_text(gained)
	out.append(["Łup: " + (loot if not loot.is_empty() else "brak"), Palette.THATCH[2]])
	if fallen_count > 0:
		out.append(["Polegli: %d" % fallen_count, Palette.ACCENT])
	if not unlock.is_empty():
		out.append([unlock, Palette.INK])
	return out


# --- Dotyk -------------------------------------------------------------------------------------

func _input(event: InputEvent) -> void:
	if not visible:
		return
	if event is InputEventScreenDrag:
		get_viewport().set_input_as_handled()
		return
	var touch := event as InputEventScreenTouch
	if touch == null:
		return
	get_viewport().set_input_as_handled()
	var on := close_rect(get_viewport_rect().size).has_point(touch.position)
	if touch.pressed:
		_pressed = on
		queue_redraw()
		return
	var was := _pressed
	_pressed = false
	queue_redraw()
	if was and on:
		close()


# --- Rysowanie ---------------------------------------------------------------------------------

func _draw() -> void:
	if result == null:
		return
	var view := get_viewport_rect().size
	draw_rect(Rect2(Vector2.ZERO, view), Color(Palette.SHADOW, 0.6))
	var p := panel_rect(view)
	draw_rect(p, Color(Palette.SHADOW, 0.95))
	CastleView.draw_frame(self, Rect2i(p), Palette.WOOD[2])
	PixelFont.draw_centered(self, Rect2(p.position.x, p.position.y + 5, p.size.x, 10),
			WIN_TITLE if result.won else LOSS_TITLE, Palette.THATCH[2] if result.won else Palette.ACCENT)
	var stars_w := 3 * STAR_W + 2 * STAR_GAP
	var x0 := int(p.get_center().x) - stars_w / 2
	for i in 3:
		_draw_star(Vector2i(x0 + i * (STAR_W + STAR_GAP), int(p.position.y) + 18), result.stars[i])
	var y := p.position.y + 30
	for line: Array in lines(result, got, fallen, unlock_text):
		PixelFont.draw_centered(self, Rect2(p.position.x, y, p.size.x, 10), line[0] as String, line[1] as Color)
		y += PixelFont.LINE + 2
	Hud.paint_button(self, close_rect(view), CLOSE_LABEL, _pressed, false)


func _draw_star(at: Vector2i, on: bool) -> void:
	var col: Color = Palette.THATCH[2] if on else Palette.WOOD[0]
	for y in STAR.size():
		for x in STAR_W:
			if STAR[y][x] == "#":
				draw_rect(Rect2(at.x + x, at.y + y, 1, 1), col)
