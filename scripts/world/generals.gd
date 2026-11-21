class_name Generals
extends RefCounted
## Generałowie (#31, notatka Władca i generałowie): do MAX generałów, każdy innego rodzaju, rekrutacja
## za złoto w Dworze. Generał zdobywa doświadczenie w bitwach, a kolejny poziom kupuje się za złoto,
## gdy doświadczenia wystarczy. W MVP są 3 postacie (Plan MVP): Wódz drużyny, Łowczy i Budowniczy
## kopców, wszyscy od epoki I (decyzja właścicielki: w notatce Budowniczy jest od epoki II, ale wtedy
## w epoce I nie byłoby komendanta obrony), poziomy 1–3 i jeden perk dodatkowy na poziomie 3.
##
## Jeden generał dowodzi atakiem (`attack_kind`, wybór na ekranie planu ataku), a drugi, inny, jest
## komendantem obrony (DefensePlan.commander, ekran Obrona). Generał nie stoi na siatce i nie da się
## go wystawić w bitwie (decyzja właścicielki z 21.11.2026): dowodzi całym atakiem albo całą obroną,
## a jego perki działają na wszystkie oddziały strony (Battle.set_general). Dlatego z puli perków
## dodatkowych odpadają Weteran (aura) i Twardy (życie generała), a Ostrożny działa na całą armię.
##
## Koszty, progi doświadczenia i liczby z perków bez wartości w notatce są TYMCZASOWE (decyzja
## właścicielki z 21.11.2026).

enum Kind { CHIEF, HUNTSMAN, MOUND_BUILDER }
## Perki dodatkowe z puli epok I–II (poziom 3). Okrutny (+10% łupu, −5 morale) czeka, aż serwer będzie
## liczył limit łupu z generałem (także przy zamkach-botach); bez tego odrzuciłby wyższy łup.
enum Perk { NONE = -1, FAST_MARCH, CAREFUL }
enum Result { OK, FULL, TAKEN, NO_GOLD, UNKNOWN, MAX_LEVEL, NO_XP, NO_PERK_YET, PERK_SET, PERK_LOCKED, NO_MANOR }

const R := EconomyConfig.Res

const NAMES: Array[String] = ["Wódz drużyny", "Łowczy", "Budowniczy kopców"]
## Krótkie nazwy na przyciskach (do ok. 60 px).
const SHORT_NAMES: Array[String] = ["Wódz", "Łowczy", "Budown."]
## W czym generał jest najlepszy (notatka); tylko opis, przypisać można każdego.
const BEST_IN: Array[String] = ["atak", "atak", "obrona"]
## Perk główny (poziom 1).
const MAIN_PERKS: Array[String] = ["Piechota +10% obrażeń, +10 morale", "Oskrzydlenie 20% szybciej",
		"Wał, palisada, kopiec +15% wytrz."]
## Od której epoki generała da się zrekrutować (0 = I).
const KIND_AGE: Array[int] = [0, 0, 0]

const PERK_NAMES: Array[String] = ["Szybki marsz", "Ostrożny"]
const PERK_DESC: Array[String] = ["Wszyscy +1 szybkości", "Wszyscy -15% od strzał"]
## Od której epoki perk da się wybrać (notatka): Ostrożny od epoki II.
const PERK_AGE: Array[int] = [0, 1]

const MAX := 3
## MVP: poziomy 1–3 (4–5 dojdą później).
const MAX_LEVEL := 3
## Poziom, od którego generał ma perk dodatkowy.
const PERK_LEVEL := 3
## Rekrutacja w złocie (TYMCZASOWE).
const RECRUIT_GOLD := 300
## Doświadczenie potrzebne do poziomu 1, 2, 3 (TYMCZASOWE).
const LEVEL_XP: Array[int] = [0, 0, 100, 300]
## Złoto za awans na poziom 1, 2, 3 (TYMCZASOWE).
const LEVEL_GOLD: Array[int] = [0, 0, 400, 1000]
## Doświadczenie za każdą bitwę i dodatkowo za zwycięstwo (TYMCZASOWE).
const XP_BATTLE := 20
const XP_WIN := 20
## Doświadczenie rośnie najwyżej do progu ostatniego poziomu (dalej nic nie daje w MVP).
const XP_MAX := 300

# --- Liczby do bitwy (z notatki) ---------------------------------------------------------------------
const FAST_MARCH_SPEED := 1
const CAREFUL_ARROW_PERCENT := 85
const CHIEF_DAMAGE_PERCENT := 110
const CHIEF_MORALE := 10
const HUNTSMAN_FLANK_SPEED_PERCENT := 120
const MOUND_BUILDER_HP_PERCENT := 115

const MESSAGES: Array[String] = ["", "Masz już 3 generałów", "Ten generał już służy",
		"Brakuje złota", "Nie ma takiego generała", "Najwyższy poziom w tej wersji",
		"Za mało doświadczenia", "Perk dodatkowy od poziomu 3", "Perk już wybrany",
		"Ten perk od późniejszej epoki", "Najpierw zbuduj Dwór"]


## Generał gracza: rodzaj, poziom 1..MAX_LEVEL, doświadczenie i perk dodatkowy (Perk.NONE do wyboru).
class General:
	extends RefCounted
	var kind := 0
	var level := 1
	var xp := 0
	var perk: int = Perk.NONE

	func has_perk(p: int) -> bool:
		return perk == p and level >= PERK_LEVEL

	func to_dict() -> Dictionary:
		return {"kind": kind, "level": level, "xp": xp, "perk": perk}

	func duplicate_general() -> General:
		return Generals.general_from(to_dict())


## Generałowie w kolejności rekrutacji.
var roster: Array[General] = []
## Rodzaj generała dowodzącego atakiem albo -1 (bez generała).
var attack_kind := -1


static func count() -> int:
	return NAMES.size()


## Generał z danych (zapis, kopia zamku z serwera) albo null przy złym wpisie. Poziom i perk są
## przycinane do zakresów MVP, więc obcy zamek nie wstawi do bitwy generała spoza gry.
static func general_from(v: Variant) -> General:
	if not v is Dictionary:
		return null
	var d := v as Dictionary
	var kind := _int_of(d.get("kind"), -1)
	if kind < 0 or kind >= count():
		return null
	var g := General.new()
	g.kind = kind
	g.level = clampi(_int_of(d.get("level"), 1), 1, MAX_LEVEL)
	g.xp = clampi(_int_of(d.get("xp"), 0), 0, XP_MAX)
	var perk := _int_of(d.get("perk"), Perk.NONE)
	g.perk = perk if perk >= 0 and perk < PERK_NAMES.size() and g.level >= PERK_LEVEL else Perk.NONE
	return g


## Liczba całkowita z JSON (int albo float bez części ułamkowej), inaczej `fallback`.
static func _int_of(v: Variant, fallback: int) -> int:
	if v is int:
		return int(v)
	if v is float and float(v) == floorf(float(v)):
		return int(v)
	return fallback


func get_general(kind: int) -> General:
	for g in roster:
		if g.kind == kind:
			return g
	return null


func has_general(kind: int) -> bool:
	return get_general(kind) != null


## Rodzaje do rekrutacji w epoce `age`, których gracz jeszcze nie ma.
func recruitable(age: int) -> Array[int]:
	var out: Array[int] = []
	for k in count():
		if KIND_AGE[k] <= age and not has_general(k):
			out.append(k)
	return out


static func recruit_cost() -> Array[int]:
	var cost: Array[int] = []
	cost.resize(EconomyConfig.count())
	cost.fill(0)
	cost[R.GOLD] = RECRUIT_GOLD
	return cost


## Złoto za awans generała na poziom `level` (koszt w kolejności EconomyConfig.Res).
static func level_cost(level: int) -> Array[int]:
	var cost: Array[int] = []
	cost.resize(EconomyConfig.count())
	cost.fill(0)
	cost[R.GOLD] = LEVEL_GOLD[clampi(level, 0, MAX_LEVEL)]
	return cost


## Czemu nie da się zrekrutować generała `kind` (Result), albo OK. `has_manor`: rekrutacja jest w Dworze.
func recruit_problem(kind: int, age: int, economy: Economy, has_manor: bool = true) -> int:
	if kind < 0 or kind >= count() or KIND_AGE[kind] > age:
		return Result.UNKNOWN
	if not has_manor:
		return Result.NO_MANOR
	if has_general(kind):
		return Result.TAKEN
	if roster.size() >= MAX:
		return Result.FULL
	if not economy.can_afford(recruit_cost()):
		return Result.NO_GOLD
	return Result.OK


func recruit(kind: int, age: int, economy: Economy, has_manor: bool = true) -> int:
	var problem := recruit_problem(kind, age, economy, has_manor)
	if problem != Result.OK:
		return problem
	economy.spend(recruit_cost())
	var g := General.new()
	g.kind = kind
	roster.append(g)
	return Result.OK


## Czemu generał `kind` nie może awansować, albo OK.
func promote_problem(kind: int, economy: Economy) -> int:
	var g := get_general(kind)
	if g == null:
		return Result.UNKNOWN
	if g.level >= MAX_LEVEL:
		return Result.MAX_LEVEL
	if g.xp < LEVEL_XP[g.level + 1]:
		return Result.NO_XP
	if not economy.can_afford(level_cost(g.level + 1)):
		return Result.NO_GOLD
	return Result.OK


func promote(kind: int, economy: Economy) -> int:
	var problem := promote_problem(kind, economy)
	if problem != Result.OK:
		return problem
	var g := get_general(kind)
	economy.spend(level_cost(g.level + 1))
	g.level += 1
	return Result.OK


## Perki dodatkowe do wyboru w epoce `age`.
static func perks_for(age: int) -> Array[int]:
	var out: Array[int] = []
	for p in PERK_NAMES.size():
		if PERK_AGE[p] <= age:
			out.append(p)
	return out


## Wybór perka dodatkowego generała `kind` (raz, od poziomu PERK_LEVEL).
func choose_perk(kind: int, perk: int, age: int) -> int:
	var g := get_general(kind)
	if g == null or perk < 0 or perk >= PERK_NAMES.size():
		return Result.UNKNOWN
	if g.level < PERK_LEVEL:
		return Result.NO_PERK_YET
	if g.perk != Perk.NONE:
		return Result.PERK_SET
	if PERK_AGE[perk] > age:
		return Result.PERK_LOCKED
	g.perk = perk
	return Result.OK


## Doświadczenie po bitwie dla generała `kind` (brak generała: nic). Zwraca, ile przybyło.
func add_battle_xp(kind: int, won: bool) -> int:
	var g := get_general(kind)
	if g == null:
		return 0
	var before := g.xp
	g.xp = mini(XP_MAX, g.xp + XP_BATTLE + (XP_WIN if won else 0))
	return g.xp - before


## Ustawia generała ataku (-1: bez generała). Komendant obrony (`commander`) nie może dowodzić też
## atakiem, a generał, którego gracz nie ma, nie zostaje wybrany. Zwraca ustawiony rodzaj.
func set_attack(kind: int, commander: int = -1) -> int:
	attack_kind = kind if kind >= 0 and has_general(kind) and kind != commander else -1
	return attack_kind


## Generał ataku do bitwy (kopia) albo null.
func attack_general() -> General:
	var g := get_general(attack_kind)
	return g.duplicate_general() if g != null else null


## Kolejny generał ataku przy przełączaniu na ekranie planu: brak → generałowie po kolei (bez komendanta).
func next_attack(commander: int = -1) -> int:
	var options: Array[int] = [-1]
	for g in roster:
		if g.kind != commander:
			options.append(g.kind)
	var i := options.find(attack_kind)
	return set_attack(options[(i + 1) % options.size()], commander)


## Krótki opis generała, np. „Wódz drużyny, poz. 2”.
static func label(g: General) -> String:
	return "%s, poz. %d" % [NAMES[g.kind], g.level] if g != null else "brak"


func save_data() -> Dictionary:
	var list: Array = []
	for g in roster:
		list.append(g.to_dict())
	return {"roster": list, "attack": attack_kind}


## Odczyt zapisu (także z kopii zamku innego gracza). Złe wpisy i powtórzone rodzaje są pomijane;
## zwraca, ile pominięto.
func load_data(d: Dictionary) -> int:
	roster.clear()
	attack_kind = -1
	var skipped := 0
	var raw: Variant = d.get("roster", [])
	if raw is Array:
		for e: Variant in raw as Array:
			var g := general_from(e)
			if g == null or has_general(g.kind) or roster.size() >= MAX:
				skipped += 1
				continue
			roster.append(g)
	set_attack(_int_of(d.get("attack"), -1))
	return skipped
