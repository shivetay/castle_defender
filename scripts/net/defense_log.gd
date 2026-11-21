class_name DefenseLog
extends RefCounted
## Ostatnie obrony gracza (#99): zakończone ataki na jego zamek z listą zniszczonych budynków
## (`attacks.destroyed`, zapisuje ją serwer w `public.record_destroyed`). Klient czyta je przez REST
## (RLS: gracz widzi tylko ataki, w których brał udział) i robi z nich ruiny w odbudowie (Ruins).
## Pobiera tylko id budynków i czas końca ataku; kto atakował, gra tu nie potrzebuje.
## Raporty obron (#29): wynik, łup i id ataku do powtórki (AttackReplay) dla ekranu powtórek.

const PATH := "/rest/v1/attacks"
## Najwięcej obron w jednej odpowiedzi (starsze i tak są już odbudowane).
const LIMIT := 20
const UUID_LEN := 36


## Ścieżka zapytania: obrony gracza `user_id` zakończone po `since_s` (unix s), od najnowszej.
## Tylko z niepustą listą zniszczeń (`neq.{}`; null też odpada): ataki bez zniszczeń nie zajmują
## miejsc w LIMIT, więc nie wypchną obrony, po której ruiny jeszcze stoją (review #255).
## Pusty tekst, gdy id nie wygląda jak UUID (nic nie idzie do sieci).
static func path(user_id: String, since_s: int) -> String:
	if not _is_uuid(user_id):
		return ""
	var since := Time.get_datetime_string_from_unix_time(maxi(0, since_s)) + "Z"
	return "%s?select=destroyed,finished_at&defender_id=eq.%s&status=eq.finished&destroyed=neq.%%7B%%7D&finished_at=gte.%s&order=finished_at.desc&limit=%d" \
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


# --- Raporty obron (#29) -----------------------------------------------------------------------

## Ile ostatnich obron pokazuje ekran powtórek.
const REPORTS_LIMIT := 5


## Raport jednej obrony: id ataku (do powtórki), wynik z serwera, łup, który zabrał atakujący,
## i koniec ataku (unix s). Kto atakował, gra tu nie pobiera.
class Report:
	extends RefCounted
	var id := ""
	var result: BattleResult
	var loot: Array[int] = []
	var at_s := 0


## Ścieżka zapytania: ostatnie zakończone obrony gracza `user_id`, od najnowszej (RLS: gracz widzi tylko
## ataki, w których brał udział). Tylko z zapisanym planem (`orders` różne od `[]`): ataki sprzed #29
## nie mają powtórki, więc nie zajmują miejsc na liście (review #266). Pusty tekst, gdy id nie wygląda jak UUID.
static func reports_path(user_id: String) -> String:
	if not _is_uuid(user_id):
		return ""
	return "%s?select=id,result,loot,finished_at&defender_id=eq.%s&status=eq.finished&orders=neq.%%5B%%5D&order=finished_at.desc&limit=%d" \
			% [PATH, user_id, REPORTS_LIMIT]


## Odpowiedź REST z raportami. Wiersze bez poprawnego id, wyniku albo czasu są pomijane.
static func parse_reports(data: Variant) -> Array[Report]:
	var out: Array[Report] = []
	if not data is Array:
		return out
	for row: Variant in data as Array:
		if not row is Dictionary or out.size() >= REPORTS_LIMIT:
			continue
		var d := row as Dictionary
		var r := Report.new()
		r.id = str(d.get("id", ""))
		r.result = parse_result(d.get("result"))
		r.at_s = parse_timestamp(str(d.get("finished_at", "")))
		r.loot = parse_loot(d.get("loot"))
		if _is_uuid(r.id) and r.result != null and r.at_s >= 0:
			out.append(r)
	return out


## Wynik z serwera (`attacks.result`, BattleResult.to_server): wygrana atakującego, procent 0..100
## i 3 gwiazdki. Null, gdy kształt się nie zgadza.
static func parse_result(raw: Variant) -> BattleResult:
	if not raw is Dictionary:
		return null
	var d := raw as Dictionary
	var won: Variant = d.get("won")
	var percent: Variant = d.get("percent")
	var stars: Variant = d.get("stars")
	if not won is bool or not (percent is int or (percent is float and float(percent) == floorf(float(percent)))) \
			or int(percent) < 0 or int(percent) > 100 or not stars is Array or (stars as Array).size() != 3:
		return null
	var r := BattleResult.new()
	r.won = won as bool
	r.percent = int(percent)
	for i in 3:
		var st: Variant = (stars as Array)[i]
		if not st is bool:
			return null
		r.stars[i] = st as bool
	return r


## Łup z serwera w kolejności EconomyConfig.Res; zły albo brakujący wpis to 0.
static func parse_loot(raw: Variant) -> Array[int]:
	var out: Array[int] = []
	for res in EconomyConfig.count():
		var v: Variant = (raw as Array)[res] if raw is Array and res < (raw as Array).size() else 0
		out.append(maxi(0, int(v)) if (v is int or (v is float and float(v) == floorf(float(v)))) else 0)
	return out


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
