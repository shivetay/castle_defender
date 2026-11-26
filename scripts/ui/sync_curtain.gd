class_name SyncCurtain
extends RefCounted
## Logika zasłony ładowania przy synchronizacji z serwerem (#316), bez renderowania (rysuje ją
## SyncLoaderPanel). Bez zasłony gracz widział zamek z telefonu, a chwilę później, gdy serwer oddał
## nowszy zamek, scena przeładowywała się z innym: ekran migał.
## STARTUP: start, na którym zamek prawie na pewno wróci z serwera (bez zapisu albo po nieudanym
## przywróceniu); zasłona czeka na odpowiedź o zamku, brak sieci albo STARTUP_MAX_S.
## RESTORE: zamek z serwera właśnie się wczytuje; zasłona stoi do przeładowania sceny, a w nowej
## scenie znika po MIN_VISIBLE_S. Każda zasłona stoi co najmniej MIN_VISIBLE_S, żeby sama nie mignęła.

enum Mode { HIDDEN, STARTUP, RESTORE }

## Najdłuższe czekanie na serwer na starcie (s); potem gra rusza z zamkiem z telefonu.
const STARTUP_MAX_S := 10.0
## Najkrótszy czas na ekranie (s).
const MIN_VISIBLE_S := 0.8
## Co ile sekund zmienia się tekst klimatyczny i przybywa kropka w tytule.
const LINE_S := 1.6
const DOT_S := 0.4
const STARTUP_TITLE := "Otwieramy bramy grodu"
const RESTORE_TITLE := "Wczytuję zamek z serwera"
## Teksty klimatyczne, po kolei w kółko (zawsze od pierwszego).
const LINES: Array[String] = [
	"Rozkręcamy życie na zamku",
	"Kowal rozpala palenisko",
	"Strażnicy obejmują warty",
	"Chłopi wracają z pól",
	"Kronikarz spisuje dzieje grodu",
	"Liczymy worki w spichlerzu",
	"Łucznicy napinają cięciwy",
	"Sprawdzamy, czy mury stoją",
]

var mode: int = Mode.HIDDEN
## Czas od pokazania zasłony (s).
var elapsed := 0.0
## Powód czekania minął; zasłona zniknie, gdy minie MIN_VISIBLE_S.
var _done := false


## Czy na starcie czekać na serwer: tylko gdy serwer jest skonfigurowany, a zamek prawie na pewno
## wróci (start bez zapisu na telefonie albo nieudane przywrócenie w poprzedniej sesji).
static func waits_at_start(net_enabled: bool, local_fresh: bool, restore_pending: bool) -> bool:
	return net_enabled and (local_fresh or restore_pending)


func is_visible() -> bool:
	return mode != Mode.HIDDEN


func start_waiting() -> void:
	mode = Mode.STARTUP
	elapsed = 0.0
	_done = false


## Zamek z serwera się wczytuje. Zasłona, która już stoi, nie zaczyna liczyć od nowa.
func start_restore() -> void:
	if mode == Mode.HIDDEN:
		elapsed = 0.0
	mode = Mode.RESTORE
	_done = false


## Powód czekania minął (np. nowa scena po przywróceniu jest gotowa).
func finish() -> void:
	if mode != Mode.HIDDEN:
		_done = true


func on_net_state(st: int) -> void:
	if mode == Mode.STARTUP and (st == SupabaseClient.State.OFFLINE or st == SupabaseClient.State.DISABLED):
		_done = true


## Serwer odpowiedział o zamku i nic nie wraca (albo odczyt się nie udał).
func on_castle_checked() -> void:
	if mode == Mode.STARTUP:
		_done = true


## Upływ czasu; zwraca true, gdy zasłona właśnie zniknęła.
func advance(delta: float) -> bool:
	if mode == Mode.HIDDEN:
		return false
	elapsed += delta
	if mode == Mode.STARTUP and elapsed >= STARTUP_MAX_S:
		_done = true
	if _done and elapsed >= MIN_VISIBLE_S:
		mode = Mode.HIDDEN
		_done = false
		return true
	return false


## Tytuł z kropkami (0–3, w kółko).
func title() -> String:
	var base := RESTORE_TITLE if mode == Mode.RESTORE else STARTUP_TITLE
	return base + ".".repeat(int(elapsed / DOT_S) % 4)


func line() -> String:
	return LINES[int(elapsed / LINE_S) % LINES.size()]
