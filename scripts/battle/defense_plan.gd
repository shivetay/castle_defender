class_name DefensePlan
extends RefCounted
## Ustawienia obrony (#19, notatki Koncept gry i Interfejs): układ, którym zamek broni się sam, gdy
## gracz jest offline. Na razie to posterunki załogi: każdy oddział z rekrutacji (#89) może dostać
## kratkę, wokół której staje na początku bitwy i do której wraca, gdy nie ma wroga w zasięgu wzroku.
## Oddział bez posterunku stoi jak dotąd przy donżonie (#120). Zadania obrony (patrol, priorytet
## wież, wypad konnicy) dojdą w #20, pułapki w #100, a komendant z generałami w #31.
##
## Posterunki są przypisane do id oddziału z rekrutacji (nie do jego miejsca w armii), więc nowy
## oddział nie przejmuje cudzego posterunku. Układ to same liczby całkowite, więc ten sam układ
## i ten sam seed dają ten sam przebieg bitwy (powtórka, weryfikacja PvP).

const NO_POST := Vector2i(-1, -1)
## Posterunek stoi najwyżej tyle kratek (w pionie i poziomie) od środka donżonu: obrona skupia się
## na donżonie (#19), a strefa przy krawędzi mapy zostaje dla atakującego. TYMCZASOWE.
const RADIUS := 10

## Id oddziału z rekrutacji → kratka posterunku.
var posts: Dictionary[int, Vector2i] = {}


func post_for(squad_id: int) -> Vector2i:
	return posts.get(squad_id, NO_POST) as Vector2i


func set_post(squad_id: int, cell: Vector2i) -> void:
	posts[squad_id] = cell


func clear_post(squad_id: int) -> void:
	posts.erase(squad_id)


## Oddział, którego posterunek stoi na kratce `cell`, albo 0 (przy remisie najniższe id).
func squad_at(cell: Vector2i) -> int:
	var best := 0
	for id: int in posts:
		if posts[id] == cell and (best == 0 or id < best):
			best = id
	return best


## Usuwa posterunki oddziałów, których nie ma już w armii (rozwiązane po stratach, #164).
func prune(recruitment: Recruitment) -> void:
	for id: int in posts.keys():
		if recruitment.squad(id) == null:
			posts.erase(id)


## Posterunki oddziałów bitwy w kolejności `ids` (Recruitment.battle_ids()); NO_POST dla oddziału
## bez posterunku. Lista idzie do Battle.create_squads.
func battle_posts(ids: Array[int]) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for id in ids:
		out.append(post_for(id))
	return out


## Środek donżonu (kratka), wokół którego liczy się strefa obrony; NO_POST bez donżonu.
static func keep_center(grid: BuildGrid) -> Vector2i:
	var keep := grid.keep_id()
	if keep == 0:
		return NO_POST
	return grid.buildings[keep].get_center()


## Strefa obrony: kratki, na których może stać posterunek (przycięta do mapy).
static func zone(grid: BuildGrid) -> Rect2i:
	var c := keep_center(grid)
	if c == NO_POST:
		return Rect2i()
	var r := Rect2i(c - Vector2i.ONE * RADIUS, Vector2i.ONE * (2 * RADIUS + 1))
	return r.intersection(Rect2i(0, 0, grid.terrain.size, grid.terrain.size))


## Pusty napis, gdy na kratce `cell` może stać posterunek; inaczej powód po polsku (pasek komunikatu).
static func post_problem(grid: BuildGrid, cell: Vector2i) -> String:
	if not grid.terrain.in_bounds(cell):
		return "Poza mapą"
	if not zone(grid).has_point(cell):
		return "Za daleko od donżonu: najwyżej %d kratek" % RADIUS
	if grid.terrain.get_tile(cell) == TerrainMap.Tile.WATER:
		return "Załoga nie stanie w wodzie"
	var id := grid.building_at(cell)
	if id != 0:
		return "Tu stoi %s" % BuildingTypes.NAMES[grid.kinds[id]]
	return ""


func to_dict() -> Dictionary:
	var ids: Array[int] = []
	for id: int in posts:
		ids.append(id)
	ids.sort()
	var list: Array = []
	for id in ids:
		list.append([id, posts[id].x, posts[id].y])
	return {"posts": list}


## Układ z danych zapisu (JSON daje liczby jako float, więc wszystko idzie przez int()). Złe wpisy
## są pomijane.
static func from_dict(d: Dictionary) -> DefensePlan:
	var p := DefensePlan.new()
	for e: Variant in d.get("posts", []) as Array:
		if not e is Array:
			continue
		var a := e as Array
		if a.size() < 3 or int(a[0]) <= 0:
			continue
		p.set_post(int(a[0]), Vector2i(int(a[1]), int(a[2])))
	return p
