class_name Research
extends RefCounted
## Stan badań: zbadane technologie i jedno trwające badanie. Koszt pobiera się przy rozpoczęciu,
## a badanie kończy się w czasie zegarowym, więc trwa też, gdy gra jest w tle albo zamknięta.
## Technologię można badać, gdy gra jest w jej epoce (lub późniejszej) i zbadano wszystkie
## technologie, których wymaga, a na zamku stoi budynek badań jej gałęzi (#165, np. Atak w Koszarach,
## ResearchConfig.research_building). Doktryny z poziomami (TechTree.LEVELED_DOCTRINES) bada się
## ponownie na kolejne poziomy, do TechTree.max_level w epoce zamku. Efekty działają razem z budynkami,
## jednostkami i bitwą; premia do produkcji (G1, G2) rośnie z poziomem doktryny.

enum Result { OK, BUSY, ALREADY_DONE, WRONG_AGE, MISSING_REQUIREMENTS, NO_RESOURCES, UNKNOWN, NO_BUILDING, MAX_LEVEL }

## Komunikaty dla gracza (indeks = Result).
const MESSAGES: Array[String] = ["", "Trwa inne badanie", "Już zbadane", "Wymaga późniejszej epoki",
		"Najpierw zbadaj wymagane technologie", "Brak surowców", "Nieznana technologia",
		"Najpierw postaw budynek badań", "Najwyższy poziom w tej epoce"]

## Zbadane kody (kod → true).
var done: Dictionary = {}
## Poziomy doktryn ponad pierwszy (kod → poziom od 2, TechTree.LEVELED_DOCTRINES). Zbadana technologia
## bez wpisu ma poziom 1.
var levels: Dictionary = {}
## Kod trwającego badania albo pusty napis.
var active := ""
var start_ms := 0
var duration_ms := 0
var cost: Array[int] = []


func is_done(code: String) -> bool:
	return done.has(code)


## Poziom technologii: 0 niezbadana, 1 zbadana, wyżej kolejne poziomy doktryny.
func level(code: String) -> int:
	if not is_done(code):
		return 0
	return maxi(1, int(levels.get(code, 1)))


## Czy trwające albo możliwe badanie `code` to kolejny poziom już zbadanej doktryny.
func is_level_up(code: String) -> bool:
	return is_done(code) and TechTree.is_leveled(code)


## Premia doktryny `code` w procentach: `base` na poziomie 1 i DOCTRINE_LEVEL_PERCENT za każdy kolejny;
## 0, gdy niezbadana.
func doctrine_percent(code: String, base: int) -> int:
	var lv := level(code)
	if lv == 0:
		return 0
	return base + TechTree.DOCTRINE_LEVEL_PERCENT * (lv - 1)


func is_busy() -> bool:
	return not active.is_empty()


## Wymagane technologie, których jeszcze nie zbadano.
func missing(code: String) -> Array[String]:
	var out: Array[String] = []
	for req in TechTree.requires(code):
		if not is_done(req):
			out.append(req)
	return out


## Czy technologię widać na ekranie drzewka w epoce `current_age`: z bieżącej i wcześniejszych epok
## zawsze, a z późniejszej dopiero, gdy zbadano wszystko, czego wymaga (decyzja właścicielki, #12).
func is_visible(code: String, current_age: int) -> bool:
	return TechTree.has(code) and (TechTree.age(code) <= current_age or missing(code).is_empty())


## Widoczne kody z listy `codes` (is_visible), w tej samej kolejności.
func visible_of(codes: Array[String], current_age: int) -> Array[String]:
	var out: Array[String] = []
	for code in codes:
		if is_visible(code, current_age):
			out.append(code)
	return out


## Premia do produkcji surowca `res` w procentach (100 = bez premii) ze zbadanych technologii.
func production_percent(res: int) -> int:
	var percent := 100
	for code: String in TechTree.PRODUCTION_BONUS:
		var bonus: Array = TechTree.PRODUCTION_BONUS[code]
		if int(bonus[0]) == res:
			percent += doctrine_percent(code, int(bonus[1]))
	return percent


## Chwila końca trwającego badania (unix, ms); -1, gdy nic się nie bada.
func finish_ms() -> int:
	return start_ms + duration_ms if is_busy() else -1


## Ile poziomów doktryn (TechTree.DOCTRINES) epoki `tech_age` zbadano albo właśnie się bada. Od tego
## rośnie koszt kolejnej doktryny i kolejnego poziomu.
func doctrine_step(tech_age: int) -> int:
	var n := 0
	for code: String in done:
		if TechTree.is_doctrine(code) and TechTree.age(code) == tech_age:
			n += level(code)
	if is_busy() and TechTree.is_doctrine(active) and TechTree.age(active) == tech_age:
		n += 1
	return n


## Koszt rozpoczęcia technologii `code` przy obecnym stanie badań: stały w epoce, a dla doktryny
## rośnie z każdą wcześniejszą doktryną tej epoki.
func cost_of(code: String) -> Array[int]:
	var a := TechTree.age(code)
	return ResearchConfig.cost(a, doctrine_step(a) if TechTree.is_doctrine(code) else 0)


## Czas badania technologii `code`: stały w jej epoce.
func time_of(code: String) -> int:
	return ResearchConfig.time_ms(TechTree.age(code))


## Czy technologię można teraz zacząć badać w epoce `current_age` (bez sprawdzania surowców).
## Z `grid` sprawdza też budynek badań gałęzi (#165); bez siatki (testy samego drzewka) go pomija.
func check(code: String, current_age: int, grid: BuildGrid = null) -> Result:
	if not TechTree.has(code):
		return Result.UNKNOWN
	if is_done(code):
		if not TechTree.is_leveled(code):
			return Result.ALREADY_DONE
		if level(code) >= TechTree.max_level(code, current_age):
			return Result.MAX_LEVEL
	if is_busy():
		return Result.BUSY
	if TechTree.age(code) > current_age:
		return Result.WRONG_AGE
	if not missing(code).is_empty():
		return Result.MISSING_REQUIREMENTS
	if grid != null and not has_building(code, grid):
		return Result.NO_BUILDING
	return Result.OK


## Czy na zamku stoi gotowy budynek badań technologii `code` (#165).
static func has_building(code: String, grid: BuildGrid) -> bool:
	return grid.has_built(ResearchConfig.research_building(code))


## Komunikat o brakującym budynku badań, np. „Najpierw postaw: Koszary”.
static func building_hint(code: String) -> String:
	return "Najpierw postaw: %s" % BuildingTypes.NAMES[ResearchConfig.research_building(code)]


## Rozpoczyna badanie: pobiera koszt i zapamiętuje czas zakończenia.
func start(code: String, current_age: int, economy: Economy, now_ms: int, grid: BuildGrid = null) -> Result:
	var result := check(code, current_age, grid)
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
	if is_done(code):
		levels[code] = level(code) + 1
	else:
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
	var lv := {}
	for code in TechTree.codes():
		if level(code) > 1:
			lv[code] = level(code)
	if not lv.is_empty():
		d["levels"] = lv
	if is_busy():
		d["active"] = {"code": active, "start_ms": start_ms, "duration_ms": duration_ms, "cost": cost.duplicate()}
	return d


## Wczytuje stan z save_data(). Nieznane kody są pomijane; zwraca liczbę pominiętych wpisów.
func load_data(d: Dictionary, now_ms: int) -> int:
	done.clear()
	levels.clear()
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
	var lv := d.get("levels", {}) as Dictionary
	if lv != null:
		for key: Variant in lv:
			var code := str(key)
			var n := int(lv[key]) if (lv[key] is int or lv[key] is float) else 0
			# poziom tylko dla zbadanej doktryny z poziomami, w granicach ostatniej epoki
			if is_done(code) and TechTree.is_leveled(code) and n >= 2 and n <= TechTree.max_level_any(code):
				levels[code] = n
			else:
				skipped += 1
	var a := d.get("active", {}) as Dictionary
	if a != null and not a.is_empty():
		var code := str(a.get("code", ""))
		# trwające badanie wraca tylko wtedy, gdy spełnia wymagania jak przy check()
		var next_ok := not is_done(code) or (TechTree.is_leveled(code) and level(code) < TechTree.max_level_any(code))
		if TechTree.has(code) and next_ok and missing(code).is_empty():
			active = code
			start_ms = int(a.get("start_ms", now_ms))
			duration_ms = maxi(0, int(a.get("duration_ms", 0)))
			for amount: Variant in a.get("cost", []) as Array:
				cost.append(maxi(0, int(amount)))
		else:
			skipped += 1
	return skipped
