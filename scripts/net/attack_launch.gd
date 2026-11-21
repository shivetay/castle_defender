class_name AttackLaunch
extends RefCounted
## Zatwierdzenie planu ataku na gracza (#28, Edge Function `launch_attack`). Plan widział tylko zarys
## zamku i to, co odsłonił zwiad; dopiero po zatwierdzeniu serwer oddaje pełne kopie zamku (`castle`)
## i obrony (`defense`) obrońcy z chwili startu, z których klient liczy bitwę. Serwer przyjmuje wynik
## (`finish_attack`) tylko po zatwierdzeniu. Ponowienie dla tego samego ataku zwraca to samo.

const PATH := "/functions/v1/launch_attack"


static func request(attack_id: String) -> Dictionary:
	return {"attack_id": attack_id}


## Parsuje JSON odpowiedzi. Pusty słownik = odrzucona / niepełna odpowiedź (kopia zamku musi być obiektem).
static func parse_response(data: Variant) -> Dictionary:
	if not data is Dictionary:
		return {}
	var d := data as Dictionary
	var castle: Variant = d.get("castle")
	var defense: Variant = d.get("defense")
	if not castle is Dictionary or (castle as Dictionary).is_empty():
		return {}
	return {"id": str(d.get("id", "")), "castle": castle as Dictionary,
			"defense": defense as Dictionary if defense is Dictionary else {}}
