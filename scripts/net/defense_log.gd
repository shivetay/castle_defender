class_name DefenseLog
extends RefCounted
## Ostatnie obrony gracza (#99): zakończone ataki na jego zamek z listą zniszczonych budynków
## (`attacks.destroyed`, zapisuje ją serwer w `public.record_destroyed`). Klient czyta je przez REST
## (RLS: gracz widzi tylko ataki, w których brał udział) i robi z nich ruiny w odbudowie (Ruins).
## Pobiera tylko id budynków i czas końca ataku; kto atakował, gra tu nie potrzebuje.

const PATH := "/rest/v1/attacks"
## Najwięcej obron w jednej odpowiedzi (starsze i tak są już odbudowane).
const LIMIT := 20
const UUID_LEN := 36


## Ścieżka zapytania: obrony gracza `user_id` zakończone po `since_s` (unix s), od najnowszej.
## Pusty tekst, gdy id nie wygląda jak UUID (nic nie idzie do sieci).
static func path(user_id: String, since_s: int) -> String:
	if not _is_uuid(user_id):
		return ""
	var since := Time.get_datetime_string_from_unix_time(maxi(0, since_s)) + "Z"
	return "%s?select=destroyed,finished_at&defender_id=eq.%s&status=eq.finished&destroyed=not.is.null&finished_at=gte.%s&order=finished_at.desc&limit=%d" \
			% [PATH, user_id, since, LIMIT]


## Odpowiedź REST: lista {"ids": Array[int], "at_ms": int} (koniec ataku, unix ms). Złe wiersze
## i złe id są pomijane, więc uszkodzona odpowiedź daje najwyżej mniej ruin.
static func parse_response(data: Variant) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if not data is Array:
		return out
	for row: Variant in data as Array:
		if not row is Dictionary or out.size() >= LIMIT:
			continue
		var d := row as Dictionary
		var at_s := parse_timestamp(str(d.get("finished_at", "")))
		var raw: Variant = d.get("destroyed")
		if at_s < 0 or not raw is Array:
			continue
		var ids: Array[int] = []
		for v: Variant in raw as Array:
			if (v is int or (v is float and float(v) == floorf(float(v)))) and int(v) > 0 \
					and ids.size() < AttackFinish.MAX_DESTROYED:
				ids.append(int(v))
		if not ids.is_empty():
			out.append({"ids": ids, "at_ms": at_s * 1000})
	return out


## Czas z PostgREST (np. `2026-11-20T10:15:00.123456+00:00` albo `...Z`) jako unix s, -1 gdy zły.
static func parse_timestamp(text: String) -> int:
	if text.length() < 19 or text[4] != "-" or text[10] != "T":
		return -1
	var base := Time.get_unix_time_from_datetime_string(text.substr(0, 19))
	if base <= 0:
		return -1
	var rest := text.substr(19)
	var cut := rest.find("+")
	var sign := 1
	if cut < 0:
		cut = rest.find("-")
		sign = -1
	if cut < 0:
		return int(base)  # bez strefy albo `Z`: UTC
	var zone := rest.substr(cut + 1)
	if zone.length() < 5 or zone[2] != ":" or not zone.substr(0, 2).is_valid_int() or not zone.substr(3, 2).is_valid_int():
		return -1
	var offset_s := (int(zone.substr(0, 2)) * 60 + int(zone.substr(3, 2))) * 60
	return int(base) - sign * offset_s


static func _is_uuid(text: String) -> bool:
	if text.length() != UUID_LEN:
		return false
	for i in text.length():
		var c := text[i]
		if i in [8, 13, 18, 23]:
			if c != "-":
				return false
		elif not ((c >= "0" and c <= "9") or (c >= "a" and c <= "f") or (c >= "A" and c <= "F")):
			return false
	return true
