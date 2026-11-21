class_name ScoutNet
extends RefCounted
## Zwiad na gracza (#28) przez serwer: wysłanie (Edge Function `scout`) i raporty (`scout_reports`).
## Wynik losuje i trzyma serwer (`public.begin_scout`); klient dostaje tylko czas do końca misji,
## a wynik, ocalałych i odsłonięte dane dopiero po jej końcu. Dane z serwera dotyczą innego gracza,
## więc są niezaufane: liczby przycinane, intel przez ScoutIntel.from_server.

const SEND_PATH := "/functions/v1/scout"
const REPORTS_PATH := "/functions/v1/scout_reports"
## Najwięcej raportów z odpowiedzi (serwer zwraca do 20).
const MAX_REPORTS := 20


static func request(defender_id: String, duration: int) -> Dictionary:
	return {"defender_id": defender_id, "duration": clampi(duration, 0, ScoutConfig.duration_count() - 1)}


## Odpowiedź `scout`: {id, remaining_s, units {rodzaj: liczba}} albo pusty słownik.
static func parse_send(data: Variant) -> Dictionary:
	if not data is Dictionary:
		return {}
	var d := data as Dictionary
	var id := str(d.get("id", ""))
	var trackers := _int(d.get("trackers"), 0, ScoutConfig.MAX_SCOUTS)
	var scouts := _int(d.get("scouts"), 0, ScoutConfig.MAX_SCOUTS)
	var remaining := _int(d.get("remaining_s"), 0, ScoutConfig.DURATION_S[-1])
	if id.is_empty() or trackers < 0 or scouts < 0 or remaining < 0 or trackers + scouts < 1 \
			or trackers + scouts > ScoutConfig.MAX_SCOUTS:
		return {}
	var units: Dictionary[int, int] = {}
	if trackers > 0:
		units[UnitTypes.Unit.TRACKER] = trackers
	if scouts > 0:
		units[UnitTypes.Unit.SCOUT] = scouts
	return {"id": id, "remaining_s": remaining, "units": units}


## Odpowiedź `scout_reports`: lista {id, defender_id, castle_name, finished, remaining_s, outcome,
## percent, returned, intel}; złe wpisy odpadają. Misja w drodze ma tylko id, cel i czas.
static func parse_reports(data: Variant) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if not data is Dictionary or not (data as Dictionary).get("reports") is Array:
		return out
	for e: Variant in ((data as Dictionary)["reports"] as Array).slice(0, MAX_REPORTS):
		if not e is Dictionary:
			continue
		var d := e as Dictionary
		var id := str(d.get("id", ""))
		var defender := str(d.get("defender_id", ""))
		var trackers := _int(d.get("trackers"), 0, ScoutConfig.MAX_SCOUTS)
		var scouts := _int(d.get("scouts"), 0, ScoutConfig.MAX_SCOUTS)
		var sent := trackers + scouts
		if id.is_empty() or defender.is_empty() or trackers < 0 or scouts < 0 or sent < 1:
			continue
		var row := {"id": id, "defender_id": defender, "sent": sent,
				"castle_name": TargetSearch.safe_name(str(d.get("castle_name", "")), PlayerProfile.CASTLE_MAX),
				"finished": d.get("finished") == true,
				"remaining_s": maxi(0, _int(d.get("remaining_s"), 0, 86400))}
		if row["finished"]:
			var outcome := _int(d.get("outcome"), 0, ScoutConfig.OUTCOME_NAMES.size() - 1)
			var percent := _int(d.get("percent"), 0, ScoutConfig.MAX_PERCENT)
			var returned := _int(d.get("returned"), 0, sent)
			if outcome < 0 or percent < 0 or returned < 0:
				continue
			row["outcome"] = outcome
			row["percent"] = percent
			row["returned"] = returned
			row["intel"] = d.get("intel") if d.get("intel") is Dictionary else {}
		out.append(row)
	return out


## Komunikat po odmowie `scout`, kod z SupabaseClient.edge_error (mieści się w pasku, 320 px).
static func error_message(code: String) -> String:
	match code:
		"scout_busy":
			return "Zwiadowcy są już w drodze"
		"no_building":
			return "Serwer nie widzi Chaty tropicieli"
		"no_tech":
			return "Serwer nie widzi badania S1"
		"no_scouts", "attacker_no_castle":
			return "Serwer nie zna jeszcze Twoich zwiadowców"
		"rate_limited":
			return "Za dużo zwiadów na dobę"
		"target_out_of_range", "target_not_found":
			return "Ten cel jest już niedostępny"
		SupabaseClient.NETWORK_ERROR:
			return "Brak połączenia z serwerem. Spróbuj później"
	return "Serwer nie przyjął zwiadu. Spróbuj później"


## Liczba całkowita z JSON w zakresie lo..hi albo -1.
static func _int(v: Variant, lo: int, hi: int) -> int:
	if not (v is int or (v is float and float(v) == floorf(float(v)))):
		return -1
	var n := int(v)
	return n if n >= lo and n <= hi else -1
