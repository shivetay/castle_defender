class_name RankingBoard
extends RefCounted
## Ranking PvP (#27): kontrakt Edge Function `ranking` i wiersze tabeli. Punkty liczy wyłącznie
## serwer (Elo po każdej bitwie PvP, migracja `*_pvp_ranking.sql`): osobno za atak i za obronę,
## w puli tej samej epoki. Serwer zwraca 20 najlepszych i własny wiersz gracza, gdy jest niżej.
## Wiersze opisują innych graczy, więc są niezaufane: nazwy przechodzą przez te same reguły co
## w onboardingu (TargetSearch.safe_name), liczby są przycinane, a nieznany władca daje domyślny portret.

const PATH := "/functions/v1/ranking"
enum Kind { ATTACK, DEFENSE }
## Rodzaj rankingu w żądaniu i odpowiedzi, w kolejności Kind.
const KIND_KEYS: Array[String] = ["attack", "defense"]
## Tyle najlepszych pokazuje tabela (RANKING_TOP w migracji), plus własny wiersz.
const TOP := 20
const MAX_ROWS := TOP + 1
const MAX_POINTS := 99999
const MAX_PLACE := 99999


## Jeden wiersz tabeli.
class Row:
	extends RefCounted
	## Miejsce od 1; remis daje to samo miejsce.
	var place := 0
	var player_name := ""
	var castle_name := ""
	var ruler := Rulers.DEFAULT
	var points := 0
	## Wiersz gracza, który ogląda tabelę.
	var is_me := false


static func request(kind: int) -> Dictionary:
	return {"kind": KIND_KEYS[clampi(kind, 0, KIND_KEYS.size() - 1)]}


## Wiersz z odpowiedzi albo null, gdy się nie nadaje (złe miejsce albo nazwa zamku).
static func row_from(raw: Dictionary) -> Row:
	var place: Variant = raw.get("place")
	if not _is_number(place) or int(place) < 1:
		return null
	var castle := TargetSearch.safe_name(str(raw.get("castle_name", "")), PlayerProfile.CASTLE_MAX)
	if castle.is_empty():
		return null
	var r := Row.new()
	r.place = mini(int(place), MAX_PLACE)
	var name := TargetSearch.safe_name(str(raw.get("nickname", "")), PlayerProfile.NAME_MAX)
	r.player_name = name if not name.is_empty() else "Gracz"
	r.castle_name = castle
	var ruler := str(raw.get("ruler", ""))
	r.ruler = ruler if Rulers.is_known(ruler) else Rulers.DEFAULT
	var points: Variant = raw.get("points")
	r.points = clampi(int(points) if _is_number(points) else 0, 0, MAX_POINTS)
	r.is_me = raw.get("is_me") == true
	return r


## Wiersze odpowiedzi `ranking` dla rodzaju `kind`; odpowiedź na inny rodzaj daje pustą listę.
## Najwyżej MAX_ROWS wierszy, miejsca nie maleją, a „to Ty” jest najwyżej raz.
static func parse_response(data: Variant, kind: int) -> Array[Row]:
	var out: Array[Row] = []
	if not data is Dictionary:
		return out
	var d := data as Dictionary
	if str(d.get("kind", "")) != KIND_KEYS[clampi(kind, 0, KIND_KEYS.size() - 1)]:
		return out
	var rows: Variant = d.get("rows", [])
	if not rows is Array:
		return out
	var me_seen := false
	for raw: Variant in rows as Array:
		if out.size() >= MAX_ROWS:
			break
		if not raw is Dictionary:
			continue
		var r := row_from(raw as Dictionary)
		if r == null or (not out.is_empty() and r.place < out[-1].place):
			continue
		if r.is_me:
			if me_seen:
				r.is_me = false
			me_seen = true
		out.append(r)
	return out


## Własny wiersz albo null (gracz nie ma jeszcze bitew w tej roli).
static func my_row(rows: Array[Row]) -> Row:
	for r in rows:
		if r.is_me:
			return r
	return null


## Komunikat pod tabelą: miejsce gracza albo zachęta do pierwszej bitwy.
static func summary(rows: Array[Row], kind: int) -> String:
	var me := my_row(rows)
	if me != null:
		return "Twoje miejsce: %d., punkty: %d" % [me.place, me.points]
	if kind == Kind.ATTACK:
		return "Zaatakuj gracza, żeby wejść do rankingu"
	return "Wejdziesz po pierwszym ataku na Twój zamek"


static func _is_number(v: Variant) -> bool:
	return v is int or v is float
