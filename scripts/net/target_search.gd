class_name TargetSearch
extends RefCounted
## Dobór przeciwnika (#24): odpowiedź Edge Function `find_targets` i lista dokładnie 3 celów.
## Serwer (`match_targets`) zwraca do 3 graczy bez tarczy, z epoką ±1 i rankingiem ±100, których
## gracz nie atakował w ostatnich 24 godzinach. Brakujące miejsca (i całą listę bez sieci) zajmują
## zamki-boty (#26), więc gracz zawsze ma 3 cele.
## Dane z serwera pochodzą od innych graczy, więc są niezaufane: nazwy przechodzą przez te same
## reguły co w onboardingu (PlayerProfile), liczby są przycinane, a zarys budynków ograniczony
## do mapy i do MAX_FOOTPRINT prostokątów.

const PATH := "/functions/v1/find_targets"
## Ile celów pokazuje ekran.
const COUNT := 3
## Najwyżej tyle prostokątów zarysu z serwera (zamek z zapisu ma ich mniej).
const MAX_FOOTPRINT := 400
## Ranking i łup z serwera najwyżej tyle (karta i tak ich więcej nie zmieści).
const MAX_RATING := 99999
const MAX_LOOT := 999999

## Cele-boty po numerze: zamek generuje się raz na uruchomienie gry (stały seed, więc stały wynik).
static var _bots: Dictionary[int, Target] = {}


## Jeden cel na karcie: gracz z serwera albo zamek-bot.
class Target:
	extends RefCounted
	var is_bot := false
	## Numer zamku-bota (0–19), -1 dla gracza.
	var bot_idx := -1
	## Id konta obrońcy (uuid), pusty dla bota.
	var player_id := ""
	var player_name := ""
	var castle_name := ""
	var ruler := Rulers.DEFAULT
	var age := 0
	## Ranking obrony gracza (#27, `defense_rating`); bot nie ma rankingu (-1).
	var rating := -1
	var map_seed := 0
	## Zarys budynków w kratkach mapy (bez rodzajów, poziomów i pułapek).
	var footprint: Array[Rect2i] = []
	## Szacowany łup w kolejności EconomyConfig.Res.
	var loot: Array[int] = []
	## Siła obrony na karcie (#310): bot ze Strength.bot_defense, gracz -1 (nieznana do #293).
	var strength := -1

	## Klucz celu (raporty zwiadu, #28).
	func key() -> String:
		return "bot:%d" % bot_idx if is_bot else "gracz:" + player_id


## Cel z wiersza `find_targets` albo null, gdy wiersz się nie nadaje (zły id, seed albo nazwa).
static func target_from_row(row: Dictionary) -> Target:
	var id := str(row.get("player_id", ""))
	if not _is_uuid(id):
		return null
	var map_seed := int(row.get("map_seed", 0)) if _is_number(row.get("map_seed")) else 0
	if map_seed < 1 or map_seed > WorldSeed.MAX_SEED:
		return null
	var name := safe_name(str(row.get("nickname", "")), PlayerProfile.NAME_MAX)
	var castle := safe_name(str(row.get("castle_name", "")), PlayerProfile.CASTLE_MAX)
	if castle.is_empty():
		return null
	var t := Target.new()
	t.player_id = id
	t.player_name = name if not name.is_empty() else "Gracz"
	t.castle_name = castle
	var ruler := str(row.get("ruler", ""))
	t.ruler = ruler if Rulers.is_known(ruler) else Rulers.DEFAULT
	t.age = clampi(int(row.get("age", 0)) if _is_number(row.get("age")) else 0, 0, 9)
	t.rating = clampi(int(row.get("rating", 0)) if _is_number(row.get("rating")) else 0, 0, MAX_RATING)
	t.map_seed = map_seed
	t.footprint = parse_footprint(row.get("footprint", []))
	t.loot = _parse_loot(row.get("loot", []))
	return t


## Cele-gracze z odpowiedzi `find_targets` (`{"targets": [...]}`), najwyżej COUNT, bez powtórzeń.
static func parse_response(data: Variant) -> Array[Target]:
	var out: Array[Target] = []
	if not data is Dictionary:
		return out
	var rows: Variant = (data as Dictionary).get("targets", [])
	if not rows is Array:
		return out
	var seen: Dictionary = {}
	for row: Variant in rows as Array:
		if out.size() >= COUNT:
			break
		if not row is Dictionary:
			continue
		var t := target_from_row(row as Dictionary)
		if t != null and not seen.has(t.player_id):
			seen[t.player_id] = true
			out.append(t)
	return out


## Zarys budynków: prostokąty [x, y, szer., wys.] mieszczące się w mapie; reszta odpada.
static func parse_footprint(raw: Variant) -> Array[Rect2i]:
	var out: Array[Rect2i] = []
	if not raw is Array:
		return out
	var map := Rect2i(0, 0, TerrainMap.SIZE, TerrainMap.SIZE)
	for e: Variant in raw as Array:
		if out.size() >= MAX_FOOTPRINT:
			break
		if not e is Array or (e as Array).size() != 4:
			continue
		var a := e as Array
		var ok := true
		for v: Variant in a:
			ok = ok and _is_number(v)
		if not ok:
			continue
		var r := Rect2i(int(a[0]), int(a[1]), int(a[2]), int(a[3]))
		if r.size.x < 1 or r.size.y < 1 or not map.encloses(r):
			continue
		out.append(r)
	return out


## Cel-bot `i` (0–19): zamek z listy BotRoster, jego zarys, siła i szacowany łup ze skarbca (z cache).
static func bot_target(i: int) -> Target:
	if _bots.has(i):
		return _bots[i]
	var t := Target.new()
	t.is_bot = true
	t.bot_idx = i
	t.player_name = "Zamek-bot"
	t.castle_name = BotRoster.NAMES[i]
	t.age = BotRoster.age_of(i)
	t.map_seed = BotRoster.seed_of(i)
	t.loot = BattleResult.estimate_bot_loot(i)
	var bot := BotRoster.generate(i)
	for id: int in bot.grid.buildings:
		t.footprint.append(bot.grid.buildings[id])
	t.strength = Strength.bot_defense(bot)
	_bots[i] = t
	return t


## Numery zamków-botów na `n` wolnych miejsc: najpierw bieżący cel kampanii, potem zdobyte od
## najmłodszego, a gdy to za mało (nowy gracz), kolejne zamki z listy. Zawsze `n` różnych numerów
## (przy n ≤ BotRoster.COUNT); ten sam postęp daje zawsze te same boty.
static func bot_indices(beaten: int, n: int) -> Array[int]:
	var out: Array[int] = []
	var current := BotRoster.last_unlocked(beaten)
	for i in range(current, -1, -1):
		if out.size() >= n:
			return out
		out.append(i)
	for i in range(current + 1, BotRoster.COUNT):
		if out.size() >= n:
			break
		out.append(i)
	return out


## Lista dokładnie COUNT celów: gracze z serwera (najwyżej COUNT), a resztę uzupełniają boty.
static func fill(players: Array[Target], beaten: int) -> Array[Target]:
	var out: Array[Target] = players.slice(0, COUNT)
	for i in bot_indices(beaten, COUNT - out.size()):
		out.append(bot_target(i))
	return out


## Epoka rzymską liczbą, np. „Epoka II”.
static func age_label(age: int) -> String:
	const ROMAN: Array[String] = ["I", "II", "III", "IV", "V", "VI", "VII", "VIII", "IX", "X"]
	return "Epoka " + ROMAN[clampi(age, 0, ROMAN.size() - 1)]


## Nazwa po czyszczeniu; pusta, gdy ma znaki spoza fontu albo jest za długa (po przycięciu do
## `max_len` znaków też musi przejść walidację).
static func safe_name(text: String, max_len: int) -> String:
	var cleaned := PlayerProfile.clean_name(text).substr(0, max_len).strip_edges()
	if PlayerProfile.check_name(cleaned, 1, max_len) != PlayerProfile.NameError.OK:
		return ""
	return cleaned


static func _parse_loot(raw: Variant) -> Array[int]:
	var out: Array[int] = []
	var a: Array = raw as Array if raw is Array else []
	for res in EconomyConfig.count():
		var v: Variant = a[res] if res < a.size() else 0
		out.append(clampi(int(v) if _is_number(v) else 0, 0, MAX_LOOT))
	return out


static func _is_number(v: Variant) -> bool:
	return v is int or v is float


static func _is_uuid(text: String) -> bool:
	if text.length() != 36:
		return false
	for i in text.length():
		var ch := text[i]
		if i in [8, 13, 18, 23]:
			if ch != "-":
				return false
		elif not ch.is_valid_hex_number():
			return false
	return true
