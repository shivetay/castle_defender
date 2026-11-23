class_name PendingFinish
extends RefCounted
## Wynik ataku na gracza, który czeka na serwer (#99). Gra zapisuje treść `finish_attack` w osobnym
## pliku tuż po bitwie i usuwa go dopiero po odpowiedzi serwera (przyjęty albo odrzucony wynik).
## Gdy gra zamknie się wcześniej albo skończą się próby bez sieci, wynik idzie na serwer jeszcze raz
## po najbliższym połączeniu. Ponowienie jest bezpieczne: zakończony atak serwer oddaje z zapisanym
## wynikiem i łupem, a atak w toku przyjmuje w swoim limicie czasu (`attack_expired` po nim).
## Plik nie trafia do zapisu zamku ani na serwer jako zamek; ma tylko id ataku, wynik, łup, ocalałych,
## id zniszczonych budynków i liczbę poległych do okna wyniku (bez danych o graczu).

const PATH := "user://attack_result.json"
const VERSION := 1
## Najwięcej oddziałów w treści (więcej żaden atak nie wysyła).
const MAX_SQUADS := 64
## Komunikat, gdy nowy atak czeka na wysłanie zaległego wyniku (mieści się w pasku komunikatu).
const WAIT_MESSAGE := "Najpierw wysyłam wynik ataku"

## Treść `finish_attack` (AttackFinish.request); pusta, gdy nic nie czeka.
var body: Dictionary = {}
## Polegli atakującego do okna wyniku (straty są już w zapisie gry).
var fallen := 0


func is_empty() -> bool:
	return body.is_empty()


## Czy zaległy wynik blokuje start nowego ataku na serwerze. `begin_attack` porzuca poprzedni atak
## w toku tego samego gracza, więc nowy start przed wysłaniem wyniku dałby `attack_expired` i stratę
## łupu. Bez sieci nic nie startuje na serwerze, więc wyprawa na bota może iść lokalnie.
func blocks_start(online: bool) -> bool:
	return online and not is_empty()


func to_dict() -> Dictionary:
	return {"version": VERSION, "body": body.duplicate(true), "fallen": fallen}


## Zaległy wynik ze słownika pliku albo pusty, gdy plik jest zły (zły wpis nie idzie na serwer).
static func from_dict(d: Dictionary) -> PendingFinish:
	var p := PendingFinish.new()
	if int(d.get("version", 0)) != VERSION:
		return p
	var raw: Variant = d.get("body")
	if not raw is Dictionary or not valid_body(raw as Dictionary):
		return p
	var b := raw as Dictionary
	# po JSON-ie liczby są floatami: treść wraca z liczb całkowitych i bez nieznanych pól
	p.body = {"attack_id": str(b["attack_id"]), "result": DefenseLog.parse_result(b["result"]).to_server(),
			"loot": _ints(b["loot"]), "survivors": _ints(b["survivors"]), "destroyed": _ints(b.get("destroyed", []))}
	var f: Variant = d.get("fallen", 0)
	p.fallen = maxi(0, int(f)) if f is int or f is float else 0
	return p


## Czy treść ma kształt `AttackFinish.request`: id ataku, wynik, łup w liczbach >= 0, ocaleli
## i zniszczone budynki w limitach.
static func valid_body(b: Dictionary) -> bool:
	var id: Variant = b.get("attack_id")
	if not id is String or (id as String).is_empty():
		return false
	if DefenseLog.parse_result(b.get("result")) == null:
		return false
	var loot: Variant = b.get("loot")
	if not _counts(loot) or (loot as Array).size() != EconomyConfig.count():
		return false
	var survivors: Variant = b.get("survivors")
	if not _counts(survivors) or (survivors as Array).size() > MAX_SQUADS:
		return false
	var destroyed: Variant = b.get("destroyed", [])
	return _counts(destroyed) and (destroyed as Array).size() <= AttackFinish.MAX_DESTROYED


## Wynik bitwy do okna wyniku (wygrana, procent, gwiazdki i łup wysłany serwerowi).
func result() -> BattleResult:
	var r := DefenseLog.parse_result(body.get("result"))
	if r == null:
		return null
	r.loot = DefenseLog.parse_loot(body.get("loot"))
	return r


## Zapis do pliku; błąd tylko zwraca (gra działa dalej, wynik czeka w pamięci).
func write(path: String = PATH) -> Error:
	return SaveGame.write(path, to_dict())


## Odczyt jak przy zapisie gry: plik główny, a gdy go nie ma albo jest zły, pełny .tmp (awaria
## między zmianami nazw w `SaveGame.write`) i kopia .bak.
static func read(path: String = PATH) -> PendingFinish:
	for candidate: String in [path, path + ".tmp", path + ".bak"]:
		var p := from_dict(SaveGame.read(candidate))
		if not p.is_empty():
			return p
	return PendingFinish.new()


static func clear(path: String = PATH) -> void:
	SaveGame.delete(path)


static func _counts(raw: Variant) -> bool:
	if not raw is Array:
		return false
	for v: Variant in raw as Array:
		if not (v is int or (v is float and float(v) == floorf(float(v)))) or int(v) < 0:
			return false
	return true


static func _ints(raw: Variant) -> Array[int]:
	var out: Array[int] = []
	for v: Variant in raw as Array:
		out.append(int(v))
	return out
