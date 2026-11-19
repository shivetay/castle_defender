class_name SealCheck
extends RefCounted
## Sprawdzanie szczelności umocnień (#199): odliczanie ~1 min z Komendy umocnień, potem lista luk
## do podświetlenia. Gracz dotyka czerwonej luki, a Domknij uszczelnia właśnie ją. Stan (odliczanie,
## luki, wybrana luka) trafia do zapisu gry, więc nie przepada po zamknięciu aplikacji.
## Bez tego budynku nie ma pełnego flow Sprawdź → czerwone luki → uszczelnienie.

const DURATION_MS := 60_000
const NO_GAP := Vector2i(-1, -1)

## Trwa odliczanie Sprawdź.
var busy := false
var start_ms := 0
## Po zakończeniu sprawdzenia: wykryte luki (puste kratki). Puste i `revealed` = obrona szczelna
## według topologii umocnień.
var gaps: Array[Vector2i] = []
var revealed := false
## Luka wskazana przez gracza (NO_GAP: żadna); Domknij uszczelnia tę lukę.
var selected := NO_GAP


func is_busy() -> bool:
	return busy


func remaining_ms(now_ms: int) -> int:
	return maxi(0, start_ms + DURATION_MS - now_ms) if busy else 0


func has_selection() -> bool:
	return revealed and gaps.has(selected)


## Start Sprawdź. `false`, gdy już trwa odliczanie.
func start(now_ms: int) -> bool:
	if busy:
		return false
	busy = true
	start_ms = now_ms
	gaps.clear()
	revealed = false
	selected = NO_GAP
	return true


## Kończy odliczanie i wypełnia `gaps` z siatki. `true`, gdy właśnie skończyło się sprawdzenie.
func update(now_ms: int, grid: BuildGrid) -> bool:
	if not busy:
		return false
	if now_ms < start_ms + DURATION_MS:
		return false
	busy = false
	gaps = grid.fort_gaps()
	revealed = true
	selected = NO_GAP
	return true


## Usuń z listy lukę już wypełnioną (albo zajętą); wybór znika razem z nią.
func prune(grid: BuildGrid) -> void:
	if not revealed:
		return
	var kept: Array[Vector2i] = []
	for c in gaps:
		if grid.building_at(c) == 0 and grid.is_fort_gap_any(c):
			kept.append(c)
	gaps = kept
	if not gaps.has(selected):
		selected = NO_GAP


## Luka pod punktem `pos` (piksele świata) albo najbliższa w odległości `tolerance` px od jej kratki;
## NO_GAP, gdy żadnej. Kratka ma 8 px, a palec zakrywa więcej, stąd zapas. Remis wygrywa luka
## wcześniejsza na liście (stała kolejność).
func gap_near(pos: Vector2, tolerance: float) -> Vector2i:
	if not revealed:
		return NO_GAP
	var best := NO_GAP
	var best_dist := tolerance
	for c in gaps:
		var r := Rect2(Vector2(c * TerrainMap.CELL), Vector2.ONE * TerrainMap.CELL)
		var dx := maxf(maxf(r.position.x - pos.x, 0.0), pos.x - r.end.x)
		var dy := maxf(maxf(r.position.y - pos.y, 0.0), pos.y - r.end.y)
		var dist := maxf(dx, dy)
		if dist <= best_dist and (best == NO_GAP or dist < best_dist):
			best = c
			best_dist = dist
	return best


## Wskazuje lukę `c`. `false`, gdy `c` nie jest wykrytą luką.
func select(c: Vector2i) -> bool:
	if not revealed or not gaps.has(c):
		return false
	selected = c
	return true


func clear() -> void:
	busy = false
	start_ms = 0
	gaps.clear()
	revealed = false
	selected = NO_GAP


## Stan do zapisu gry (SaveGame, klucz "seal").
func save_data() -> Dictionary:
	var cells: Array = []
	for c in gaps:
		cells.append([c.x, c.y])
	return {"busy": busy, "start_ms": start_ms, "revealed": revealed, "gaps": cells,
			"selected": [selected.x, selected.y]}


## Wczytuje stan z zapisu. Luki spoza mapy i wpisy w złym formacie pomija; start z przyszłości
## (np. przestawiony zegar) przesuwa na `now_ms`. Zwraca liczbę pominiętych wpisów.
func load_data(d: Dictionary, grid: BuildGrid, now_ms: int) -> int:
	clear()
	var skipped := 0
	busy = bool(d.get("busy", false))
	start_ms = mini(int(d.get("start_ms", 0)), now_ms) if busy else 0
	revealed = bool(d.get("revealed", false)) and not busy
	var cells: Variant = d.get("gaps", [])
	if revealed and cells is Array:
		for e: Variant in cells as Array:
			var c := _cell(e)
			if c == NO_GAP or not grid.terrain.in_bounds(c) or gaps.has(c):
				skipped += 1
				continue
			gaps.append(c)
	var sel := _cell(d.get("selected", []))
	if gaps.has(sel):
		selected = sel
	return skipped


static func _cell(e: Variant) -> Vector2i:
	if not (e is Array) or (e as Array).size() != 2:
		return NO_GAP
	var a := e as Array
	return Vector2i(int(a[0]), int(a[1]))
