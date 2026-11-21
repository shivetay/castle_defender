class_name AttackStart
extends RefCounted
## Odpowiedź `start_attack` (#166 / #25): seed terenu obrońcy osobno od seeda bitwy.
## Atakujący buduje teren z `map_seed` (`terrain_map`), a bitwę losuje z `battle_seed`.
## Serwer (#25, `public.begin_attack`) blokuje cel na czas ataku, sprawdza tarczę i limit startów.
## Przy ataku na gracza (#28, pełne ukrycie obrony) zwraca tylko zarys budynków (`footprint`), donżon
## (`keep`) i to, co odsłonił zwiad (`intel`); kopie zamku i obrony daje AttackLaunch po zatwierdzeniu planu.
## Wynik wysyła `AttackFinish`.

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
	# JSON null z Edge ma klucz, ale int(null)→0 / str(null) psują cel — tylko realne typy.
	var bot: Variant = d.get("bot_idx")
	if bot is int or bot is float:
		var idx := int(bot)
		if idx >= 0 and idx <= 19:
			out["bot_idx"] = idx
	var defender: Variant = d.get("defender_id")
	if defender is String and not (defender as String).is_empty():
		out["defender_id"] = defender as String
		# #28: plan dostaje zarys, donżon i odsłonięte przez zwiad; pełną obronę daje AttackLaunch
		out["footprint"] = TargetSearch.parse_footprint(d.get("footprint", []))
		var keep := TargetSearch.parse_footprint([d.get("keep")])
		if keep.is_empty():
			return {}  # bez donżonu nie ma celu ataku
		out["keep"] = keep[0]
		out["intel"] = ScoutIntel.from_server(d.get("intel"))
	return out


## Teren zamku-celu z seeda obrońcy. `first_playable` jest idempotentne dla już grywalnego
## seeda gracza i potrzebne dla surowego seeda z `bot_castles` (jak `BotCastle.generate`).
static func terrain_map(map_seed: int) -> TerrainMap:
	return TerrainMap.generate(WorldSeed.first_playable(map_seed))


## Komunikat dla gracza po odmowie `start_attack` (#240), kod z SupabaseClient.edge_error. Teksty
## mieszczą się w pasku komunikatu (font 8 px, 320 px).
static func error_message(code: String) -> String:
	match code:
		"target_busy":
			return "Ten zamek ktoś teraz atakuje. Wybierz inny cel"
		"target_shielded":
			return "Zamek jest pod tarczą. Wybierz inny cel"
		"target_recent":
			return "Ten zamek zaatakujesz znowu dopiero po dobie"
		"target_out_of_range", "target_not_found":
			return "Ten cel jest już niedostępny. Szukaj jeszcze raz"
		"rate_limited":
			return "Za dużo ataków naraz. Poczekaj chwilę"
		"army_not_owned", "attacker_no_castle", "attacker_not_found":
			return "Serwer nie zna jeszcze Twojej armii. Spróbuj za chwilę"
		"army_over_limit":
			return "Armia ponad limit miejsc. Ulepsz Dwór albo Koszary"
		"army_over_upkeep":
			return "Armia zje więcej, niż daje żywność. Postaw Rybaka"
		"bad_army":
			return "Serwer nie przyjął tej armii. Sprawdź oddziały"
		"attack_expired":
			return "Plan trwał za długo: wybierz cel jeszcze raz"
		"not_launched":
			return "Serwer nie zatwierdził planu. Spróbuj jeszcze raz"
		SupabaseClient.NETWORK_ERROR:
			return "Brak połączenia z serwerem. Spróbuj później"
	return "Serwer nie przyjął ataku. Spróbuj później"
