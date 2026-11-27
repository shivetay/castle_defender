class_name AttackFinish
extends RefCounted
## Kontrakt `finish_attack` (#25): treść żądania z wynikiem bitwy i odpowiedź serwera. Serwer
## (`public.end_attack`) przyjmuje wynik tylko dla własnego ataku w toku, w 10 minut od startu,
## i odrzuca łup ponad niechronione zapasy obrońcy albo ponad capacity ocalałych (UnitTypes.CARRY).
## Ponowienie dla zakończonego ataku zwraca zapisany wynik, więc klient może bezpiecznie powtórzyć żądanie.

const PATH := "/functions/v1/finish_attack"
## Najwięcej id zniszczonych budynków w żądaniu (to samo sprawdza Edge Function). MAX_DESTROYED = 200
const MAX_DESTROYED := 200


## Treść żądania: id ataku ze `start_attack`, wynik (BattleResult.to_server), łup w kolejności
## EconomyConfig.Res i ocaleli w każdym oddziale armii wysłanej przy starcie (Battle.survivors),
## dopełnieni zerami do liczby oddziałów, oraz id zniszczonych budynków obrońcy (#99,
## BattleResult.destroyed_ids). Serwer (`public.record_destroyed`) przyjmuje tylko gotowe budynki
## z kopii zamku, bez wału i palisady, i nie więcej, niż wynika z procentu zniszczeń.
static func request(attack_id: String, result: BattleResult, squads: int, alive: Array[int]) -> Dictionary:
	var survivors: Array[int] = []
	for i in squads:
		survivors.append(maxi(0, alive[i]) if i < alive.size() else 0)
	var loot: Array[int] = []
	for res in EconomyConfig.count():
		loot.append(maxi(0, result.loot[res]) if res < result.loot.size() else 0)
	var destroyed: Array[int] = []
	for id in result.destroyed_ids:
		if id > 0 and destroyed.size() < MAX_DESTROYED:
			destroyed.append(id)
	return {"attack_id": attack_id, "result": result.to_server(), "loot": loot, "survivors": survivors,
			"destroyed": destroyed}


## Odpowiedź serwera: łup przyjęty przez serwer (w kolejności EconomyConfig.Res). Pusty słownik =
## odpowiedź niepełna; łup do magazynu klient dodaje tylko z tej odpowiedzi.
static func parse_response(data: Variant) -> Dictionary:
	if not data is Dictionary:
		return {}
	var d := data as Dictionary
	if str(d.get("status", "")) != "finished":
		return {}
	var raw: Variant = d.get("loot")
	if not raw is Array or (raw as Array).size() != EconomyConfig.count():
		return {}
	var loot: Array[int] = []
	for v: Variant in raw as Array:
		if not (v is int or v is float):
			return {}
		loot.append(maxi(0, int(v)))
	return {"status": "finished", "loot": loot}


## Ile razy klient wysyła wynik po błędzie sieci, zanim się podda (#240), i przerwa między próbami (s).
const RETRIES := 4
const RETRY_S := 3.0


## Dopisek w oknie wyniku, gdy serwer nie przyjął wyniku (#240): wtedy łupu nie ma. Bez sieci wynik
## czeka w `PendingFinish` i idzie na serwer po połączeniu (#99), więc łup może jeszcze przyjść.
static func error_note(code: String) -> String:
	match code:
		"attack_expired":
			return "Atak trwał za długo: bez łupu"
		SupabaseClient.NETWORK_ERROR:
			return "Brak sieci: wynik wyślę później"
		ClientVersion.UPDATE_REQUIRED_ERROR:
			# #336: wynik czeka w PendingFinish i wróci na serwer po aktualizacji gry
			return "Zaktualizuj grę: wynik wyślę później"
	return "Serwer odrzucił wynik: bez łupu"
