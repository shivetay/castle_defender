class_name AttackStart
extends RefCounted
## Odpowiedź `start_attack` (#166 / #25): seed terenu obrońcy osobno od seeda bitwy.
## Atakujący buduje teren z `map_seed` (`terrain_map`), a bitwę losuje z `battle_seed`.
## Pełna blokada celu, tarcze i `finish_attack` zostają w #25; tu jest kontrakt seedów.

const PATH := "/functions/v1/start_attack"


## Treść żądania ataku na zamek-bota (`bot_idx` 0..19).
static func request_bot(bot_idx: int, army: Array = []) -> Dictionary:
	return {"bot_idx": bot_idx, "army": army}


## Treść żądania ataku na gracza (`defender_id` = uuid konta).
static func request_player(defender_id: String, army: Array = []) -> Dictionary:
	return {"defender_id": defender_id, "army": army}


## Czy wartość nadaje się na seed terenu albo bitwy (0..2^31-1; 0 tylko dla botów w bazie).
static func is_seed(value: int) -> bool:
	return value >= 0 and value <= WorldSeed.MAX_SEED


## Parsuje JSON odpowiedzi `start_attack`. Pusty słownik = odrzucona / niepełna odpowiedź.
## Wymaga `map_seed` ≥ 1 (teren gracza albo bota po first_playable) i osobnego `battle_seed`.
static func parse_response(data: Variant) -> Dictionary:
	if not data is Dictionary:
		return {}
	var d := data as Dictionary
	var map_seed := int(d.get("map_seed", 0))
	var battle_seed := int(d.get("battle_seed", -1))
	if map_seed < 1 or map_seed > WorldSeed.MAX_SEED:
		return {}
	if battle_seed < 0 or battle_seed > WorldSeed.MAX_SEED:
		return {}
	var out := {
		"map_seed": map_seed,
		"battle_seed": battle_seed,
		"id": str(d.get("id", "")),
	}
	if d.has("bot_idx"):
		out["bot_idx"] = int(d["bot_idx"])
	if d.has("defender_id"):
		out["defender_id"] = str(d["defender_id"])
	return out


## Teren zamku-celu z seeda obrońcy. `first_playable` jest idempotentne dla już grywalnego
## seeda gracza i potrzebne dla surowego seeda z `bot_castles` (jak `BotCastle.generate`).
static func terrain_map(map_seed: int) -> TerrainMap:
	return TerrainMap.generate(WorldSeed.first_playable(map_seed))
