class_name PushNotifications
extends Node
## Powiadomienia push (#30, ADR 0012). Opakowuje wtyczkę Androida DunholdPush (singleton z AAR,
## addons/dunhold_push), której nie ma na komputerze, w testach ani w eksporcie bez AAR albo bez
## konfiguracji Firebase: wtedy `is_available()` jest false i gra o nic nie pyta.
## Zgoda: najpierw okienko w grze (PushPrompt) przy pierwszym wejściu na Wyprawę, dopiero po „Tak”
## systemowe pytanie (Android 13+). Odmowa w grze albo w systemie wraca najwcześniej po 7 dniach.
## Token urządzenia idzie na serwer Edge Function `push_token` (SupabaseClient.save_push_token)
## razem z przełącznikiem „Ataki”. Token nie trafia do logów ani do zapisu na telefonie.
## Koniec budowy to lokalne powiadomienie z wtyczki (bez serwera): gra planuje po jednym na każde
## zlecenie z kolejki przy wyjściu do tła i kasuje je po powrocie (`build_plan`, `schedule_builds`).

## Token FCM przyszedł z wtyczki.
signal token_ready(token: String)
## Odpowiedź na systemowe pytanie o zgodę.
signal permission_answered(granted: bool)

const SINGLETON := "DunholdPush"
## Edge Function zapisu i usuwania tokenu (#30).
const PATH := "/functions/v1/push_token"
## Po odmowie gra pyta znowu najwcześniej po tylu sekundach (7 dni).
const ASK_AGAIN_S := 7 * 24 * 3600
## Zgoda z okienka w grze (pole `push_consent` w profilu).
enum Consent { UNASKED, ACCEPTED, DECLINED }
const CONSENT_NAMES: Array[String] = ["", "yes", "no"]
## Token FCM: base64url i dwukropek (jak w migracji push_tokens).
const TOKEN_MIN := 20
const TOKEN_MAX := 512
## Miejsca na powiadomienia o budowie (BUILD_SLOTS we wtyczce): budowniczy i czekające zlecenia.
const BUILD_SLOTS := BuildConfig.BUILDERS + BuildConfig.MAX_WAITING
const BUILD_TITLE := "Budowa zakończona"


## Lokalne powiadomienie o końcu jednego zlecenia budowy.
class BuildNotice:
	extends RefCounted
	var slot := 0
	var delay_s := 0
	var title := ""
	var body := ""

var _plugin: Object


func _ready() -> void:
	if Engine.has_singleton(SINGLETON):
		_plugin = Engine.get_singleton(SINGLETON)
		_plugin.connect("token_received", _on_token_received)
		_plugin.connect("permission_result", _on_permission_result)


## Czy na tym urządzeniu działa push: wtyczka jest i ma konfigurację Firebase.
func is_available() -> bool:
	return _plugin != null and bool(_plugin.call("is_configured"))


## Czy jest wtyczka (lokalne powiadomienia działają też bez Firebase).
func has_plugin() -> bool:
	return _plugin != null


## Czy system pozwala pokazywać powiadomienia (Android 13+: zgoda; starsze: zawsze).
func has_permission() -> bool:
	return _plugin != null and bool(_plugin.call("has_permission"))


## Planuje powiadomienia o końcu budowy (najpierw kasuje stare). Bez wtyczki nic nie robi.
func schedule_builds(notices: Array[BuildNotice]) -> void:
	if _plugin == null:
		return
	_plugin.call("cancel_local")
	for n in notices:
		_plugin.call("schedule_local", n.slot, n.delay_s, n.title, n.body)


## Kasuje zaplanowane i widoczne powiadomienia o budowie (gracz wrócił do gry).
func cancel_builds() -> void:
	if _plugin != null:
		_plugin.call("cancel_local")


## Systemowe pytanie o zgodę; wynik w `permission_answered` (bez wtyczki od razu false).
func request_permission() -> void:
	if not is_available():
		permission_answered.emit.call_deferred(false)
		return
	_plugin.call("request_permission")


## Prośba o token urządzenia; przychodzi w `token_ready` (bez wtyczki nic nie przychodzi).
func request_token() -> void:
	if is_available():
		_plugin.call("request_token")


func _on_token_received(token: String) -> void:
	if is_valid_token(token):
		token_ready.emit(token)


func _on_permission_result(granted: bool) -> void:
	permission_answered.emit(granted)


## Czy pokazać okienko zgody: jeszcze nie pytano albo od odmowy minęło 7 dni.
static func should_ask(consent: int, declined_s: int, now_s: int) -> bool:
	match consent:
		Consent.UNASKED:
			return true
		Consent.DECLINED:
			return now_s - declined_s >= ASK_AGAIN_S
	return false


static func consent_from(name: String) -> int:
	var i := CONSENT_NAMES.find(name)
	return i if i >= 0 else Consent.UNASKED


static func consent_name(consent: int) -> String:
	return CONSENT_NAMES[clampi(consent, 0, CONSENT_NAMES.size() - 1)]


## Powiadomienia dla zleceń z kolejki `queue` w chwili `now_ms`: po jednym na zlecenie, w kolejności
## wykonania, z czasem do końca (czekające liczą się po poprzednich, BuildQueue.remaining_ms).
## Zlecenia kończące się w ciągu sekundy pomija. Treść: „Budowa zakończona”, „Palisada (poz. 3)”.
static func build_plan(queue: BuildQueue, now_ms: int, research: Research = null) -> Array[BuildNotice]:
	var out: Array[BuildNotice] = []
	if queue == null:
		return out
	for o in queue.orders:
		if out.size() >= BUILD_SLOTS:
			break
		@warning_ignore("integer_division")
		var delay_s := queue.remaining_ms(o.building_id, now_ms) / 1000
		if delay_s < 1:
			continue
		var n := BuildNotice.new()
		n.slot = out.size()
		n.delay_s = delay_s
		n.title = BUILD_TITLE
		n.body = "%s (poz. %d)" % [BuildingTypes.name_of(o.kind, research), o.level]
		out.append(n)
	return out


## Token w formacie FCM (jak w Edge Function i migracji); inny nie idzie na serwer.
static func is_valid_token(token: String) -> bool:
	if token.length() < TOKEN_MIN or token.length() > TOKEN_MAX:
		return false
	for i in token.length():
		var ch := token.unicode_at(i)
		var ok := (ch >= 48 and ch <= 57) or (ch >= 65 and ch <= 90) or (ch >= 97 and ch <= 122) \
				or ch == 45 or ch == 95 or ch == 58
		if not ok:
			return false
	return true


## Treść żądania zapisu tokenu z przełącznikiem „Ataki”.
static func save_request(token: String, attacks: bool) -> Dictionary:
	return {"token": token, "attacks": attacks}
