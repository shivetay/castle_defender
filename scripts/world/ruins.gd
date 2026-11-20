class_name Ruins
extends RefCounted
## Odbudowa zamku po ataku PvP (#99). Atak na gracza nie zmienia jego zamku: bitwa idzie na kopii
## z serwera. Serwer (`public.record_destroyed`) zapisuje jednak, które budynki padły, a obrońca
## czyta swoje ostatnie obrony (DefenseLog) i widzi te budynki jako ruiny. Ruiny odbudowują się
## same w REBUILD_MIN_BY_AGE minut, więc nic nie przepada, a po odbudowie budynek jest w pełnym stanie.
##
## Kara (decyzja właścicielki: minimalna): budynek z produkcją surowców (EconomyConfig.BUILDING_PRODUCTION)
## w ruinie daje PRODUCTION_PERCENT swojej produkcji. Wytwórcy towarów, wojsko i umocnienia działają
## bez zmian, a w bitwie ruina broni się jak cały budynek. Lista zniszczeń pochodzi od klienta
## atakującego, dopóki serwer nie liczy powtórki (#29), więc kara jest celowo mała.
##
## Stan nie trafia do zapisu gry: po starcie gry klient znowu czyta obrony z serwera. Czas to unix ms.
## Liczby TYMCZASOWE.
@warning_ignore_start("integer_division")

## Czas odbudowy w minutach według epoki obrońcy (Ages): epoka I godzina, każda następna o godzinę dłużej.
const REBUILD_MIN_BY_AGE: Array[int] = [60, 120, 180, 240, 300, 360]
const PRODUCTION_PERCENT := 75
const MS_PER_MIN := 60 * 1000

## Id budynku → początek i koniec odbudowy (unix ms).
var starts: Dictionary[int, int] = {}
var ends: Dictionary[int, int] = {}


static func rebuild_ms(age: int) -> int:
	return REBUILD_MIN_BY_AGE[clampi(age, 0, REBUILD_MIN_BY_AGE.size() - 1)] * MS_PER_MIN


## Budynki `ids` padły w ataku zakończonym o `at_ms`. Ten sam atak dodany drugi raz niczego nie
## zmienia, a późniejszy atak na ten sam budynek zaczyna odbudowę od nowa. Zwraca, czy coś się zmieniło.
func add(ids: Array[int], at_ms: int, age: int) -> bool:
	var changed := false
	var end := at_ms + rebuild_ms(age)
	for id in ids:
		if id <= 0 or ends.get(id, -1) >= end:
			continue
		starts[id] = at_ms
		ends[id] = end
		changed = true
	return changed


## Usuwa ruiny już odbudowane i te, których budynku nie ma w zamku (rozebrany) albo jest placem budowy.
## Zwraca, czy coś się zmieniło.
func prune(now_ms: int, grid: BuildGrid) -> bool:
	var gone: Array[int] = []
	for id: int in ends:
		if ends[id] <= now_ms or not grid.buildings.has(id) or grid.levels[id] < 1:
			gone.append(id)
	for id in gone:
		starts.erase(id)
		ends.erase(id)
	return not gone.is_empty()


func is_empty() -> bool:
	return ends.is_empty()


func is_ruined(id: int, at_ms: int) -> bool:
	return ends.has(id) and starts[id] <= at_ms and at_ms < ends[id]


## Budynki w ruinie w chwili `at_ms` (do BuildGrid.ruined).
func active_at(at_ms: int) -> Dictionary[int, bool]:
	var out: Dictionary[int, bool] = {}
	for id: int in ends:
		if is_ruined(id, at_ms):
			out[id] = true
	return out


## Najbliższa chwila po `after_ms`, w której zmienia się zbiór ruin (początek albo koniec odbudowy),
## albo -1. Ekonomia nalicza produkcję do tej chwili po starych stawkach (BuildQueue.update).
func next_change_after(after_ms: int) -> int:
	var best := -1
	for id: int in ends:
		for t: int in [starts[id], ends[id]]:
			if t > after_ms and (best < 0 or t < best):
				best = t
	return best


## Ile zostało do końca odbudowy (ms), 0 gdy budynek nie jest w ruinie.
func remaining_ms(id: int, now_ms: int) -> int:
	return ends[id] - now_ms if is_ruined(id, now_ms) else 0


## Wygląd budynku w odbudowie: pierwsza trzecia czasu gruz, druga wyrwa, ostatnia pęknięcia.
func state_of(id: int, now_ms: int) -> int:
	if not is_ruined(id, now_ms):
		return BuildingTypes.State.INTACT
	var span := maxi(1, ends[id] - starts[id])
	var third := (now_ms - starts[id]) * 3 / span
	return [BuildingTypes.State.RUBBLE, BuildingTypes.State.BREACHED, BuildingTypes.State.CRACKED][clampi(third, 0, 2)]


## Stany wszystkich ruin w chwili `now_ms` (id → BuildingTypes.State), jak CastleView.draw_buildings.
func states(now_ms: int) -> Dictionary:
	var out := {}
	for id: int in ends:
		if is_ruined(id, now_ms):
			out[id] = state_of(id, now_ms)
	return out
