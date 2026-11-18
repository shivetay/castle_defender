class_name CastleSync
extends RefCounted
## Zapis seeda terenu zamku na serwer (#166, część #23).
## Przy pierwszym zapisie klient wstawia wiersz z `map_seed` (stały seed gracza). Kolejne zapisy
## zmieniają tylko `save_version` i `data` — kolumna `map_seed` nie ma grantu UPDATE i jest
## niezmienna w bazie. Pełna synchronizacja obrony i konfliktów revision zostaje w #23.

const CASTLES_PATH := "/rest/v1/castles"
const SELECT_OWN := "map_seed,save_version,revision,updated_at"


## Czy `map_seed` mieści się w zakresie kolumny `castles.map_seed` (1..2^31-1).
static func is_valid_map_seed(map_seed: int) -> bool:
	return map_seed >= 1 and map_seed <= WorldSeed.MAX_SEED


## Treść INSERT: seed terenu tylko przy założeniu zamku.
static func insert_body(player_id: String, map_seed: int, save_version: int, data: Dictionary) -> Dictionary:
	return {
		"player_id": player_id,
		"map_seed": map_seed,
		"save_version": save_version,
		"data": data,
	}


## Treść UPDATE: bez `map_seed` i bez `revision` (te ustala serwer / są niedostępne).
static func update_body(save_version: int, data: Dictionary) -> Dictionary:
	return {"save_version": save_version, "data": data}


## Ścieżka REST do własnego wiersza zamku (filtr po `player_id`).
static func own_path(player_id: String) -> String:
	return "%s?player_id=eq.%s" % [CASTLES_PATH, player_id]


## Odczyt `map_seed` z odpowiedzi GET (tablica wierszy) albo 0, gdy brak / zły wiersz.
static func map_seed_from_rows(rows: Variant) -> int:
	if not rows is Array or (rows as Array).is_empty():
		return 0
	var row: Variant = (rows as Array)[0]
	if not row is Dictionary:
		return 0
	var value := int((row as Dictionary).get("map_seed", 0))
	return value if is_valid_map_seed(value) else 0


## Dane zamku wysyłane do `castles.data`: ten sam kształt co lokalny zapis, bez pola world_seed
## (seed stoi w osobnej kolumnie `map_seed`).
static func castle_data(save: Dictionary) -> Dictionary:
	var out := save.duplicate(true)
	out.erase("world_seed")
	return out


## Co zrobić po odczycie własnego wiersza: INSERT (brak), UPDATE (jest), NOP (zły lokalny seed).
enum Action { NOP, INSERT, UPDATE }


static func next_action(local_map_seed: int, remote_map_seed: int) -> int:
	if not is_valid_map_seed(local_map_seed):
		return Action.NOP
	if remote_map_seed == 0:
		return Action.INSERT
	# seed w bazie jest źródłem prawdy; lokalny zapis tylko aktualizuje data
	return Action.UPDATE
