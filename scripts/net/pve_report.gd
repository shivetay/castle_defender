class_name PveReport
extends RefCounted
## Wyprawa na zamek-bota w rankingu PvE (#242). Bitwa z botem dalej liczy się w grze (działa też bez
## sieci), a gdy gra jest połączona, ten sam atak idzie na serwer: `start_attack` z `bot_idx` i planem
## przed bitwą i `finish_attack` z wynikiem po niej. Od #413 (ADR 0016) bitwa online czeka na odpowiedź
## startu, bo seed bitwy, plan, badania, generał i perk władcy przychodzą z serwera (worker weryfikacji
## liczy z nich tę samą bitwę). Bez odpowiedzi po START_WAIT_S bitwa idzie bez serwera (`give_up`). Punkty PvE dodaje wyłącznie serwer (migracja
## `*_pve_ranking.sql`) po przyjęciu wyniku w swoich limitach; klient ich nie liczy ani nie wysyła.
## Odpowiedź na start może przyjść już po końcu bitwy, więc wynik czeka wtedy na id ataku.
## Łup trafia do magazynu tylko z wyniku przyjętego przez serwer (#282, decyzja właścicielki): serwer
## dopisuje go do zamku i telefon dolicza go z odpowiedzi na najbliższy zapis (`loot_applied`), bo bilans
## surowców na serwerze nie zna łupu z bitwy, której nie widział. Wyprawa bez sieci nic nie daje.

enum State { IDLE, STARTING, STARTED, FINISHING }

## Komunikat, gdy wynik nie trafił do rankingu (mieści się w pasku komunikatu).
const FAILED_MESSAGE := "Wyprawa poza serwerem: bez łupu i PvE"
## Okno wyniku wyprawy bez sieci (#282).
const OFFLINE_MESSAGE := "Bez sieci: wyprawa bez łupu"
## Pasek komunikatu, gdy bitwa czeka na start na serwerze (#413).
const CONNECTING_MESSAGE := "Łączę z serwerem..."
## Ile sekund bitwa czeka na odpowiedź startu, zanim ruszy bez serwera (#413).
const START_WAIT_S := 5.0

var state: int = State.IDLE
var bot_idx := -1
## Liczba oddziałów wysłanych w `start_attack` (serwer liczy ocalałych względem niej).
var squads := 0
var attack_id := ""
## Treść `finish_attack`, gdy wynik jest gotowy przed odpowiedzią na start.
var pending: Dictionary = {}
## Wynik czeka na wysłanie (bitwa skończyła się przed odpowiedzią na start).
var queued := false
var tries := 0
## Ostatnie zgłoszenie skończyło się bez przyjęcia wyniku (odmowa startu albo wyniku, brak sieci).
var _failed := false
## Ostatni start odrzucony, bo zamek-bot jest zablokowany na serwerze (#386).
var _locked := false


func is_idle() -> bool:
	return state == State.IDLE


## Start bitwy z botem `bot` armią `army`: od teraz czekamy na `start_attack`.
func begin(bot: int, army: Array) -> void:
	clear()
	state = State.STARTING
	bot_idx = bot
	squads = army.size()


## Odpowiedź `start_attack` (AttackStart.parse_response). Zwraca treść `finish_attack` do wysłania od
## razu, gdy wynik już czekał; pusta, gdy nie ma czego wysyłać. Odmowa albo odpowiedź o innego bota
## kończy zgłoszenie (bez punktów).
func on_started(start: Dictionary, error: String) -> Dictionary:
	if state != State.STARTING:
		return {}
	var id := str(start.get("id", ""))
	if not error.is_empty() or id.is_empty() or int(start.get("bot_idx", -1)) != bot_idx:
		reset()
		_failed = true
		_locked = error == AttackStart.BOT_LOCKED
		return {}
	attack_id = id
	state = State.STARTED
	if queued:
		return _take()
	return {}


## Koniec bitwy: treść `finish_attack` do wysłania od razu albo pusta, gdy czekamy jeszcze na start
## (albo zgłoszenia nie ma). `alive`: ocaleli w każdym oddziale (Battle.survivors).
func finish(result: BattleResult, alive: Array[int]) -> Dictionary:
	if state == State.IDLE or state == State.FINISHING:
		return {}
	pending = AttackFinish.request(attack_id, result, squads, alive)
	pending.erase("destroyed")  # zamek-bot powstaje z seeda, ruin nie ma (#99)
	if state == State.STARTING:
		queued = true
		return {}
	return _take()


## Odpowiedź `finish_attack`. Zwraca true, gdy trzeba ponowić tę samą treść (błąd sieci, jeszcze są
## próby; serwer zwraca wtedy zapisany wynik); inaczej zgłoszenie się kończy, a błąd po ostatniej
## próbie albo odmowa ustawiają `failed()`.
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


## Czy ostatni start odrzucono, bo serwer nie odblokował jeszcze tego zamku-bota (#386).
func locked() -> bool:
	return _locked


## Komunikat porażki do okna wyniku: przy zablokowanym bocie powód odmowy.
func failed_message() -> String:
	return AttackStart.error_message(AttackStart.BOT_LOCKED) if _locked else FAILED_MESSAGE


## Start nie odpowiedział na czas (#413): bitwa idzie bez serwera, a spóźnioną odpowiedź pomijamy.
func give_up() -> void:
	reset()
	_failed = true


## Bez zgłoszenia i bez znacznika porażki (przed nową wyprawą).
func clear() -> void:
	reset()
	_failed = false
	_locked = false


## Koniec zgłoszenia; znacznik porażki zostaje do odczytu w `failed()`.
func reset() -> void:
	state = State.IDLE
	bot_idx = -1
	squads = 0
	attack_id = ""
	pending = {}
	queued = false
	tries = 0


func _take() -> Dictionary:
	pending["attack_id"] = attack_id
	state = State.FINISHING
	queued = false
	tries = 1
	return pending


## Łup do okna wyniku wyprawy (#282): ten, który czeka na serwer, albo zera, gdy wyprawa nie idzie
## przez serwer (bez sieci albo odmowa startu). Sam łup do magazynu dolicza dopiero odpowiedź na zapis.
static func shown_loot(loot: Array[int], online: bool) -> Array[int]:
	var out: Array[int] = []
	for res in EconomyConfig.count():
		out.append(loot[res] if online and res < loot.size() else 0)
	return out
