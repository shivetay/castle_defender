extends TestCase
## Powiadomienia push (#30, ADR 0012): kiedy pytać o zgodę (po odmowie najwcześniej po 7 dniach),
## format tokenu FCM, pola w profilu (zgoda, przełączniki domyślnie włączone), zapis tokenu przez
## Edge Function `push_token` (bez id gracza w treści), okienko zgody i konfiguracja Firebase
## z `google-services.json` dla pakietu presetu.

const UID := "00000000-0000-0000-0000-0000000030cc"
const TOKEN := "dGVzdA:APA91bHxyz_-0123456789abcdef"
const PROFILE_PATH := "user://test_push_profile.json"
const SESSION_PATH := "user://test_push_session.json"
const SYNC_PATH := "user://test_push_sync.json"
const C := PushNotifications.Consent
const DAY := 24 * 3600


func test_when_to_ask() -> bool:
	assert_true(PushNotifications.should_ask(C.UNASKED, 0, 1000), "jeszcze nie pytano")
	assert_true(not PushNotifications.should_ask(C.ACCEPTED, 0, 1000 * DAY), "po zgodzie nigdy")
	assert_true(not PushNotifications.should_ask(C.DECLINED, 10 * DAY, 16 * DAY), "6 dni po odmowie nie")
	assert_true(PushNotifications.should_ask(C.DECLINED, 10 * DAY, 17 * DAY), "po 7 dniach znowu")
	for c: int in [C.UNASKED, C.ACCEPTED, C.DECLINED]:
		assert_eq(PushNotifications.consent_from(PushNotifications.consent_name(c)), c, "nazwa w obie strony: %d" % c)
	assert_eq(PushNotifications.consent_from("śmieć"), C.UNASKED, "zła nazwa to brak pytania")
	return true


func test_token_format() -> bool:
	assert_true(PushNotifications.is_valid_token(TOKEN), "token FCM")
	assert_true(not PushNotifications.is_valid_token("krótki"), "za krótki")
	assert_true(not PushNotifications.is_valid_token("a".repeat(513)), "za długi")
	assert_true(not PushNotifications.is_valid_token("abcdefghijklmnopqrstu v"), "spacja")
	assert_true(not PushNotifications.is_valid_token("abcdefghijklmnopqrstu\"x"), "cudzysłów")
	return true


func test_profile_fields() -> bool:
	PlayerProfile.delete(PROFILE_PATH)
	assert_eq(PlayerProfile.read_push_consent(PROFILE_PATH), C.UNASKED, "bez profilu: nie pytano")
	assert_true(PlayerProfile.read_push_attacks(PROFILE_PATH) and PlayerProfile.read_push_build(PROFILE_PATH),
			"przełączniki domyślnie włączone")
	assert_eq(PlayerProfile.write_push_consent(PROFILE_PATH, C.DECLINED, 5 * DAY), OK, "zapis odmowy")
	assert_eq(PlayerProfile.read_push_consent(PROFILE_PATH), C.DECLINED, "odmowa")
	assert_eq(PlayerProfile.read_push_declined(PROFILE_PATH), 5 * DAY, "czas odmowy")
	PlayerProfile.write_push_consent(PROFILE_PATH, C.ACCEPTED, 9 * DAY)
	assert_eq(PlayerProfile.read_push_consent(PROFILE_PATH), C.ACCEPTED, "zgoda")
	assert_eq(PlayerProfile.read_push_declined(PROFILE_PATH), 5 * DAY, "zgoda nie zmienia czasu odmowy")
	PlayerProfile.write_push_switches(PROFILE_PATH, false, true)
	assert_true(not PlayerProfile.read_push_attacks(PROFILE_PATH), "ataki wył.")
	assert_true(PlayerProfile.read_push_build(PROFILE_PATH), "budowa wł.")
	assert_true(not PlayerProfile.read(PROFILE_PATH).values().has(TOKEN), "token nie trafia do profilu")
	PlayerProfile.delete(PROFILE_PATH)
	return true


## Bez wtyczki Androida (komputer, testy) push jest niedostępny, a prośba o zgodę od razu daje false.
func test_without_plugin() -> bool:
	var p := PushNotifications.new()
	assert_true(not p.is_available() and not p.has_permission(), "bez wtyczki")
	p.free()
	return true


func test_client_saves_token() -> bool:
	SupabaseSession.clear(SESSION_PATH)
	SaveGame.delete(SYNC_PATH)
	var c := SupabaseClient.new()
	c.setup(SupabaseConfig.parse(JSON.stringify({
		"url": "https://abc.supabase.co", "publishable_key": "sb_publishable_test123",
	})), SESSION_PATH, SYNC_PATH)
	c.fake_transport = true
	assert_true(not c.save_push_token(TOKEN, true), "offline nic nie idzie")
	c.handle_auth(SupabaseClient.Call.SIGNUP, HTTPRequest.RESULT_SUCCESS, 200, JSON.stringify({
		"access_token": "t1", "refresh_token": "r1", "expires_in": 3600,
		"user": {"id": UID, "is_anonymous": true},
	}))
	assert_true(not c.save_push_token("zły token", true), "zły token nie idzie")
	var got: Array[bool] = []
	c.push_token_saved.connect(func(ok: bool) -> void: got.append(ok))
	assert_true(c.save_push_token(TOKEN, false), "token idzie")
	assert_eq(c.sent_requests[-1]["path"], PushNotifications.PATH, "Edge Function push_token")
	assert_eq(c.sent_requests[-1]["body"], {"token": TOKEN, "attacks": false}, "token i przełącznik, bez id gracza")
	assert_true(not c.save_push_token(TOKEN, true), "naraz jeden zapis")
	c.handle_push(HTTPRequest.RESULT_SUCCESS, 200, "{\"ok\": true}")
	c.handle_push(HTTPRequest.RESULT_SUCCESS, 400, "{\"error\": \"bad_token\"}")
	assert_eq(got, [true, false] as Array[bool], "wynik zapisu")
	c.free()
	SupabaseSession.clear(SESSION_PATH)
	SaveGame.delete(SYNC_PATH)
	return true


func test_prompt() -> bool:
	var view := Vector2(320, 180)
	var p := PushPrompt.new()
	var got: Array[bool] = []
	p.answered.connect(func(yes: bool) -> void: got.append(yes))
	p.open()
	assert_true(p.visible, "otwarte")
	assert_true(p.lines.size() <= 3, "pytanie w 3 liniach")
	p.choose(PushPrompt.YES)
	assert_true(not p.visible, "zamknięte")
	p.open()
	p.choose(PushPrompt.LATER)
	assert_eq(got, [true, false] as Array[bool], "Tak i Nie teraz")
	assert_eq(PushPrompt.target_at(PushPrompt.yes_rect(view).get_center(), view), PushPrompt.YES, "Tak")
	assert_eq(PushPrompt.target_at(PushPrompt.later_rect(view).get_center(), view), PushPrompt.LATER, "Nie teraz")
	assert_eq(PushPrompt.target_at(Vector2(2, 2), view), -1, "tło")
	for r: Rect2 in [PushPrompt.yes_rect(view), PushPrompt.later_rect(view)]:
		assert_true(r.size.x >= 12 and r.size.y >= 12, "cel ≥ 12×12")
		assert_true(r.position.x >= Hud.CORNER_INSET and r.end.x <= view.x - Hud.CORNER_INSET, "z dala od krawędzi")
	for t: String in [PushPrompt.YES_LABEL, PushPrompt.LATER_LABEL]:
		assert_true(PixelFont.text_width(t) <= PushPrompt.BUTTON.x - 2, "„%s” mieści się" % t)
	p.free()
	return true


func test_firebase_config() -> bool:
	var json := JSON.stringify({
		"project_info": {"project_number": "123456789", "project_id": "dunhold-test"},
		"client": [
			{"client_info": {"mobilesdk_app_id": "1:123456789:android:aaa",
				"android_client_info": {"package_name": "com.shivetay.dunhold"}},
				"api_key": [{"current_key": "AIzaRelease"}]},
			{"client_info": {"mobilesdk_app_id": "1:123456789:android:bbb",
				"android_client_info": {"package_name": "com.shivetay.dunhold.debug"}},
				"api_key": [{"current_key": "AIzaDebug"}]},
		],
	})
	var debug := FirebaseConfig.for_package(json, "com.shivetay.dunhold.debug")
	assert_eq(debug, {"app_id": "1:123456789:android:bbb", "api_key": "AIzaDebug", "project_id": "dunhold-test",
		"sender_id": "123456789"}, "aplikacja z pakietu presetu")
	assert_eq(FirebaseConfig.for_package(json, "com.inna.gra"), {}, "obcy pakiet")
	assert_eq(FirebaseConfig.for_package("{zły", "com.shivetay.dunhold"), {}, "zły plik")
	var evil := json.replace("AIzaRelease", "AIza\\\"/><evil x=\\\"")
	assert_eq(FirebaseConfig.for_package(evil, "com.shivetay.dunhold"), {}, "znaki spoza zestawu odrzucone")
	var xml := FirebaseConfig.manifest_entries(debug)
	assert_true(xml.contains("android:name=\"dunhold.firebase.app_id\" android:value=\"1:123456789:android:bbb\""), "wpis app_id")
	assert_eq(xml.count("<meta-data"), 4, "cztery wpisy")
	assert_eq(FirebaseConfig.manifest_entries({}), "", "bez konfiguracji nic")
	return true
