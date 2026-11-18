class_name SealCheck
extends RefCounted
## Sprawdzanie szczelności umocnień (#199): odliczanie ~1 min z Komendy umocnień, potem lista luk
## do podświetlenia. Bez tego budynku nie ma pełnego flow Sprawdź → czerwone luki → uszczelnienie.

const DURATION_MS := 60_000

## Trwa odliczanie Sprawdź.
var busy := false
var start_ms := 0
## Po zakończeniu sprawdzenia: wykryte luki (puste kratki). Puste i `revealed` = obrona szczelna
## według topologii umocnień.
var gaps: Array[Vector2i] = []
var revealed := false


func is_busy() -> bool:
	return busy


func remaining_ms(now_ms: int) -> int:
	return maxi(0, start_ms + DURATION_MS - now_ms) if busy else 0


## Start Sprawdź. `false`, gdy już trwa odliczanie.
func start(now_ms: int) -> bool:
	if busy:
		return false
	busy = true
	start_ms = now_ms
	gaps.clear()
	revealed = false
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
	return true


## Usuń z listy lukę już wypełnioną (albo zajętą).
func prune(grid: BuildGrid) -> void:
	if not revealed:
		return
	var kept: Array[Vector2i] = []
	for c in gaps:
		if grid.building_at(c) == 0 and (grid.is_wall_gap(c, BuildingTypes.Kind.RAMPART) \
				or grid.is_wall_gap(c, BuildingTypes.Kind.PALISADE)):
			kept.append(c)
	gaps = kept


func clear() -> void:
	busy = false
	start_ms = 0
	gaps.clear()
	revealed = false
