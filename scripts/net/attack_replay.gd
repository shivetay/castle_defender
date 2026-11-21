class_name AttackReplay
extends RefCounted
## Kontrakt `attack_replay` (#29): dane do powtórki zakończonej obrony. Serwer oddaje je tylko obrońcy:
## seedy terenu i bitwy, kopie zamku i obrony z chwili startu, armię atakującego, plan i badania
## atakującego zapisane przy zatwierdzeniu planu oraz wynik i łup. Powtórka to nie wideo: klient liczy
## bitwę jeszcze raz (BattleReplay) tą samą drogą co atakujący (PlayerCastle), więc widzi ten sam przebieg.
## Wszystko z odpowiedzi jest sprawdzane: plan i armia przyszły pierwotnie z klienta atakującego.

const PATH := "/functions/v1/attack_replay"
## Najwięcej oddziałów armii (AttackPlan.MAX_SQUADS_BY_AGE w epoce VI).
const MAX_SQUADS := 8
## Najwięcej jednostek w oddziale z serwera (z zapasem; limit oddziału sprawdza serwer przy starcie).
const MAX_COUNT := 1000


static func request(attack_id: String) -> Dictionary:
	return {"attack_id": attack_id}


## Odpowiedź serwera jako słownik dla BattleReplay.from_response albo pusty, gdy czegoś brakuje.
## Klucze: id, map_seed, battle_seed, castle, defense, army, plan (surowy), techs, result (BattleResult),
## loot, at_s.
static func parse_response(data: Variant) -> Dictionary:
	if not data is Dictionary:
		return {}
	var d := data as Dictionary
	var castle: Variant = d.get("castle")
	var defense: Variant = d.get("defense")
	var army := parse_army(d.get("army"))
	var result := DefenseLog.parse_result(d.get("result"))
	var map_seed := _seed(d.get("map_seed"))
	var battle_seed := _seed(d.get("battle_seed"))
	var at_s := DefenseLog.parse_timestamp(str(d.get("finished_at", "")))
	if not castle is Dictionary or (castle as Dictionary).is_empty() or army.is_empty() or result == null \
			or map_seed < 0 or battle_seed < 0 or str(d.get("id", "")).is_empty():
		return {}
	return {"id": str(d.get("id", "")), "map_seed": map_seed, "battle_seed": battle_seed,
			"castle": castle as Dictionary, "defense": defense as Dictionary if defense is Dictionary else {},
			"army": army, "plan": d.get("plan"), "techs": AttackLaunch.parse_techs(d.get("techs")),
			"general": d.get("general"),
			"result": result, "loot": DefenseLog.parse_loot(d.get("loot")), "at_s": maxi(0, at_s)}


## Armia [[rodzaj, liczba], …] z serwera: 1..MAX_SQUADS oddziałów, znany rodzaj, liczba 1..MAX_COUNT.
## Pusta tablica, gdy którykolwiek wpis jest zły (powtórka z innej armii byłaby inna).
static func parse_army(raw: Variant) -> Array:
	if not raw is Array or (raw as Array).is_empty() or (raw as Array).size() > MAX_SQUADS:
		return []
	var out: Array = []
	for e: Variant in raw as Array:
		if not e is Array or (e as Array).size() != 2:
			return []
		var unit := AttackPlan._int_in((e as Array)[0], 0, UnitTypes.count() - 1)
		var count := AttackPlan._int_in((e as Array)[1], 1, MAX_COUNT)
		if unit < 0 or count < 0:
			return []
		out.append([unit, count])
	return out


## Seed 0..2^31-1 (jak w kolumnach `attacks`), -1 gdy zły.
static func _seed(v: Variant) -> int:
	return AttackPlan._int_in(v, 0, 0x7fffffff)


## Komunikat dla gracza po błędzie `attack_replay`.
static func error_message(code: String) -> String:
	match code:
		"replay_missing":
			return "Ta obrona nie ma powtórki"
		"attack_not_found":
			return "Nie ma już tej obrony"
		SupabaseClient.NETWORK_ERROR:
			return "Brak połączenia: spróbuj później"
	return "Serwer nie oddał powtórki"
