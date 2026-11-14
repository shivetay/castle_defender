class_name Research
extends RefCounted
## Stan badań: zbadane technologie i jedno trwające badanie. Koszt pobiera się przy rozpoczęciu,
## a badanie kończy się w czasie zegarowym, więc trwa też, gdy gra jest w tle albo zamknięta.
## Technologię można badać, gdy gra jest w jej epoce (lub późniejszej) i zbadano wszystkie
## technologie, których wymaga. Efekty technologii dojdą osobno.

enum Result { OK, BUSY, ALREADY_DONE, WRONG_AGE, MISSING_REQUIREMENTS, NO_RESOURCES, UNKNOWN }

## Komunikaty dla gracza (indeks = Result).
const MESSAGES: Array[String] = ["", "Trwa inne badanie", "Już zbadane", "Wymaga późniejszej epoki",
		"Najpierw zbadaj wymagane technologie", "Brak surowców", "Nieznana technologia"]

## Zbadane kody (kod → true).
var done: Dictionary = {}
## Kod trwającego badania albo pusty napis.
var active := ""
var start_ms := 0
var duration_ms := 0
var cost: Array[int] = []


func is_done(code: String) -> bool:
	return done.has(code)


func is_busy() -> bool:
	return not active.is_empty()


## Wymagane technologie, których jeszcze nie zbadano.
func missing(code: String) -> Array[String]:
	var out: Array[String] = []
	for req in TechTree.requires(code):
		if not is_done(req):
			out.append(req)
	return out


## Ile technologii epoki `tech_age` zbadano albo właśnie się bada. Od tego rośnie koszt i czas.
func step(tech_age: int) -> int:
	var n := 0
	for code: String in done:
		if TechTree.age(code) == tech_age:
			n += 1
	if is_busy() and TechTree.age(active) == tech_age:
		n += 1
	return n


## Koszt rozpoczęcia technologii `code` przy obecnym stanie badań.
func cost_of(code: String) -> Array[int]:
	var a := TechTree.age(code)
	return ResearchConfig.cost(a, step(a))


func time_of(code: String) -> int:
	var a := TechTree.age(code)
	return ResearchConfig.time_ms(a, step(a))


## Czy technologię można teraz zacząć badać w epoce `current_age` (bez sprawdzania surowców).
func check(code: String, current_age: int) -> Result:
	if not TechTree.has(code):
		return Result.UNKNOWN
	if is_done(code):
		return Result.ALREADY_DONE
	if is_busy():
		return Result.BUSY
	if TechTree.age(code) > current_age:
		return Result.WRONG_AGE
	if not missing(code).is_empty():
		return Result.MISSING_REQUIREMENTS
	return Result.OK


## Rozpoczyna badanie: pobiera koszt i zapamiętuje czas zakończenia.
func start(code: String, current_age: int, economy: Economy, now_ms: int) -> Result:
	var result := check(code, current_age)
	if result != Result.OK:
		return result
	var price := cost_of(code)
	var duration := time_of(code)
	if not economy.spend(price):
		return Result.NO_RESOURCES
	active = code
	cost = price
	duration_ms = duration
	start_ms = now_ms
	return Result.OK


## Kończy badanie, gdy minął jego czas. Zwraca kod ukończonej technologii albo pusty napis.
func update(now_ms: int) -> String:
	if not is_busy() or start_ms + duration_ms > now_ms:
		return ""
	var code := active
	done[code] = true
	active = ""
	cost = []
	duration_ms = 0
	return code


## Ile zostało do końca trwającego badania (ms); -1, gdy nic się nie bada.
func remaining_ms(now_ms: int) -> int:
	if not is_busy():
		return -1
	return maxi(0, start_ms + duration_ms - now_ms)


## Stan do zapisu. Trwające badanie zapisuje się z kosztem i czasem z chwili rozpoczęcia.
func save_data() -> Dictionary:
	var list: Array[String] = []
	for code in TechTree.codes():
		if is_done(code):
			list.append(code)
	var d := {"done": list}
	if is_busy():
		d["active"] = {"code": active, "start_ms": start_ms, "duration_ms": duration_ms, "cost": cost.duplicate()}
	return d


## Wczytuje stan z save_data(). Nieznane kody są pomijane; zwraca liczbę pominiętych wpisów.
func load_data(d: Dictionary, now_ms: int) -> int:
	done.clear()
	active = ""
	cost = []
	duration_ms = 0
	var skipped := 0
	for entry: Variant in d.get("done", []) as Array:
		var code := str(entry)
		if TechTree.has(code):
			done[code] = true
		else:
			skipped += 1
	var a := d.get("active", {}) as Dictionary
	if a != null and not a.is_empty():
		var code := str(a.get("code", ""))
		if TechTree.has(code) and not is_done(code):
			active = code
			start_ms = int(a.get("start_ms", now_ms))
			duration_ms = maxi(0, int(a.get("duration_ms", 0)))
			for amount: Variant in a.get("cost", []) as Array:
				cost.append(maxi(0, int(amount)))
		else:
			skipped += 1
	return skipped
