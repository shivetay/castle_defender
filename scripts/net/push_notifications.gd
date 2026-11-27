class_name PushNotifications
extends Node
## Powiadomienia push (#30, ADR 0012). Opakowuje wtyczkę Androida DunholdPush (singleton z AAR,
## addons/dunhold_push), której nie ma na komputerze, w testach ani w eksporcie bez AAR albo bez
## konfiguracji Firebase: wtedy `is_available()` jest false i gra o nic nie pyta.
## Zgoda: najpierw okienko w grze (PushPrompt) przy pierwszym wejściu na Wyprawę, dopiero po „Tak”
## systemowe pytanie (Android 13+). Odmowa w grze albo w systemie wraca najwcześniej po 7 dniach.
## Token urządzenia idzie na serwer Edge Function `push_token` (SupabaseClient.save_push_token)
## razem z przełącznikiem „Ataki”. Token nie trafia do logów ani do zapisu na telefonie.

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

var _plugin: Object


func _ready() -> void:
	if Engine.has_singleton(SINGLETON):
		_plugin = Engine.get_singleton(SINGLETON)
		_plugin.connect("token_received", _on_token_received)
		_plugin.connect("permission_result", _on_permission_result)


## Czy na tym urządzeniu działa push: wtyczka jest i ma konfigurację Firebase.
func is_available() -> bool:
	return _plugin != null and bool(_plugin.call("is_configured"))


## Czy system pozwala pokazywać powiadomienia (Android 13+: zgoda; starsze: zawsze).
func has_permission() -> bool:
	return is_available() and bool(_plugin.call("has_permission"))


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
