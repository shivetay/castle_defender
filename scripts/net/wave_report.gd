class_name WaveReport
extends RefCounted
## Fala PvE przez serwer (#288). Bitwa z falą dalej liczy się w grze (działa też bez sieci), a gdy gra
## jest połączona, ta sama fala idzie na serwer: Edge Function `pve_wave` ze startem (`{"wave": n}`)
## przy starcie bitwy i z wynikiem (`{"wave_id": id, "won": true|false}`) po niej. Nagrodę za wygraną falę
## dopisuje wyłącznie serwer (migracja `*_pve_wave_results.sql`): czeka ona w zamku na serwerze i telefon
## dolicza ją z odpowiedzi na najbliższy zapis (`loot_applied`), bo bilans surowców na serwerze nie wlicza
## nagrody z samego licznika fal w zapisie. Fala bez sieci odblokowuje następną, ale nagrody nie daje.
## Odpowiedź na start może przyjść już po końcu bitwy, więc wynik czeka wtedy na id fali.

enum State { IDLE, STARTING, STARTED, FINISHING }

const PATH := "/functions/v1/pve_wave"

var state: int = State.IDLE
var wave := -1
var wave_id := ""
## Treść końca fali, gdy wynik jest gotowy przed odpowiedzią na start.
var pending: Dictionary = {}
## Wynik czeka na wysłanie (bitwa skończyła się przed odpowiedzią na start).
var queued := false
var tries := 0
## Ostatnie zgłoszenie skończyło się bez przyjęcia wyniku (odmowa startu albo wyniku, brak sieci).
var _failed := false


## Treść startu fali `w` (0..PveWaves.COUNT-1).
static func start_request(w: int) -> Dictionary:
	return {"wave": w}


## Treść końca fali o id `id` z serwera.
static func finish_request(id: String, won: bool) -> Dictionary:
	return {"wave_id": id, "won": won}


## Odpowiedź na start: `{"id": ..., "wave": n}` albo pusty słownik przy niepełnej odpowiedzi.
static func parse_start(data: Variant) -> Dictionary:
	if not data is Dictionary:
		return {}
	var d := data as Dictionary
	var id := str(d.get("id", ""))
	var w: Variant = d.get("wave")
	if id.is_empty() or not (w is int or w is float):
		return {}
	return {"id": id, "wave": int(w)}


## Odpowiedź na koniec: `{"status": "won"|"lost", "reward": [4 liczby]}` albo pusty słownik.
static func parse_finish(data: Variant) -> Dictionary:
	if not data is Dictionary:
		return {}
	var d := data as Dictionary
	var status := str(d.get("status", ""))
	if status != "won" and status != "lost":
		return {}
	var raw: Variant = d.get("reward")
	if not raw is Array or (raw as Array).size() != EconomyConfig.count():
		return {}
	var reward: Array[int] = []
	for v: Variant in raw as Array:
		if not (v is int or v is float):
			return {}
		reward.append(maxi(0, int(v)))
	return {"status": status, "reward": reward}


func is_idle() -> bool:
	return state == State.IDLE


## Start fali `w`: od teraz czekamy na odpowiedź serwera.
func begin(w: int) -> void:
	clear()
	state = State.STARTING
	wave = w


## Odpowiedź na start (`parse_start`). Zwraca treść końca fali do wysłania od razu, gdy wynik już czekał;
## pusta, gdy nie ma czego wysyłać. Odmowa albo odpowiedź o inną falę kończy zgłoszenie (bez nagrody).
func on_started(start: Dictionary, error: String) -> Dictionary:
	if state != State.STARTING:
		return {}
	var id := str(start.get("id", ""))
	if not error.is_empty() or id.is_empty() or int(start.get("wave", -1)) != wave:
		reset()
		_failed = true
		return {}
	wave_id = id
	state = State.STARTED
	if queued:
		return _take()
	return {}


## Koniec bitwy: treść końca fali do wysłania od razu albo pusta, gdy czekamy jeszcze na start
## (albo zgłoszenia nie ma).
func finish(won: bool) -> Dictionary:
	if state == State.IDLE or state == State.FINISHING:
		return {}
	pending = finish_request(wave_id, won)
	if state == State.STARTING:
		queued = true
		return {}
	return _take()


## Odpowiedź na koniec fali. Zwraca true, gdy trzeba ponowić tę samą treść (błąd sieci, jeszcze są próby;
## serwer zwraca wtedy zapisany wynik); inaczej zgłoszenie się kończy, a błąd po ostatniej próbie albo
## odmowa ustawiają `failed()`.
func on_finished(error: String) -> bool:
	if state != State.FINISHING:
		return false
	if error == SupabaseClient.NETWORK_ERROR and tries < AttackFinish.RETRIES:
		return true
	reset()
	_failed = not error.is_empty()
	return false


## Treść do ponowienia po błędzie sieci (liczy próbę).
func retry_body() -> Dictionary:
	if state != State.FINISHING:
		return {}
	tries += 1
	return pending


## Czy ostatnie zgłoszenie skończyło się bez przyjęcia wyniku.
func failed() -> bool:
	return _failed


## Czy fala idzie przez serwer (start w drodze albo przyjęty), więc nagroda może przyjść z serwera.
func online() -> bool:
	return state != State.IDLE and not _failed


## Bez zgłoszenia i bez znacznika porażki (przed nową falą).
func clear() -> void:
	reset()
	_failed = false


## Koniec zgłoszenia; znacznik porażki zostaje do odczytu w `failed()`.
func reset() -> void:
	state = State.IDLE
	wave = -1
	wave_id = ""
	pending = {}
	queued = false
	tries = 0


func _take() -> Dictionary:
	pending["wave_id"] = wave_id
	state = State.FINISHING
	queued = false
	tries = 1
	return pending
