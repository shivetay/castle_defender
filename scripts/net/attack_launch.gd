class_name AttackLaunch
extends RefCounted
## Zatwierdzenie planu ataku na gracza (#28, Edge Function `launch_attack`). Plan widział tylko zarys
## zamku i to, co odsłonił zwiad; dopiero po zatwierdzeniu serwer oddaje pełne kopie zamku (`castle`)
## i obrony (`defense`) obrońcy z chwili startu, z których klient liczy bitwę. Serwer przyjmuje wynik
## (`finish_attack`) tylko po zatwierdzeniu. Ponowienie dla tego samego ataku zwraca to samo.
## Powtórka (#29): żądanie niesie plan ataku, a odpowiedź oddaje plan zapisany na serwerze (`plan`,
## surowy, sprawdza go PlayerCastle.apply_launch) i badania atakującego działające w bitwie (`techs`)
## z jego zamku na serwerze. Bitwa liczy się z nich, tak jak powtórka u obrońcy.
## Generał ataku (#31): żądanie niesie tylko rodzaj wybranego generała (`general`, bez niego klucza nie ma,
## więc stary serwer nie odrzuci żądania), a serwer bierze jego poziom i perk z zamku atakującego na
## serwerze i oddaje go w odpowiedzi (`general`: {kind, level, perk} albo null).

const PATH := "/functions/v1/launch_attack"


static func request(attack_id: String, plan: AttackPlan, general: int = -1) -> Dictionary:
	var d := {"attack_id": attack_id, "plan": plan.to_server() if plan != null else []}
	if general >= 0 and general < Generals.count():
		d["general"] = general
	return d


## Badania z odpowiedzi serwera: tylko kody, które działają w bitwie po stronie atakującego, bez powtórek.
static func parse_techs(raw: Variant) -> Array[String]:
	var out: Array[String] = []
	if not raw is Array:
		return out
	for v: Variant in raw as Array:
		var code := str(v) if v is String else ""
		if code in ["A1", "A2", "A7"] and not out.has(code):
			out.append(code)
	return out


## Badania atakującego jako Research z samymi zbadanymi kodami (do Battle.apply_research).
static func research_of(techs: Array[String]) -> Research:
	var r := Research.new()
	for code in techs:
		r.done[code] = true
	return r


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
			"defense": defense as Dictionary if defense is Dictionary else {},
			"plan": d.get("plan"), "techs": parse_techs(d.get("techs")), "general": d.get("general")}
