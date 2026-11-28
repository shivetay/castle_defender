extends TestCase
## Flagi z panelu admina (#280, ADR 0020): domyślny stan z przedrostka klucza, okno czasu na zegarze serwera,
## niezaufana treść z panelu (klucze, liczba wierszy, metadata), cache w pliku i obsługa odpowiedzi w kliencie.

const PATH := "user://test_feature_flags.json"
const MIGRATION := "res://supabase/migrations/20261128160000_feature_flags.sql"
## 2026-11-28T12:00:00Z
const NOON := 1_795_867_200_000
const HOUR := 3_600_000


func _row(key: String, enabled: bool, starts: Variant = null, ends: Variant = null, kind: String = "event") -> Dictionary:
	return {"key": key, "kind": kind, "enabled": enabled, "starts_at": starts, "ends_at": ends, "metadata": {}}


func _flags(rows: Array) -> FeatureFlags:
	var f := FeatureFlags.new()
	f.apply(rows, NOON, 0)
	return f


func test_defaults_from_key_prefix() -> bool:
	var f := FeatureFlags.new()
	assert_true(f.is_active_at("feature.pvp", NOON), "funkcja bez wiersza: włączona")
	assert_true(not f.is_active_at("offer.merchant_wagon", NOON), "oferta bez wiersza: wyłączona")
	assert_true(not f.is_active_at("event.weekly", NOON), "event bez wiersza: wyłączony")
	assert_true(not f.is_active_at("cokolwiek", NOON), "nieznany przedrostek: wyłączony")
	assert_true(not f.is_active_at("feature", NOON), "sam przedrostek bez nazwy: wyłączony")
	return true


func test_enabled_and_window() -> bool:
	var f := _flags([
		_row("event.weekly", true),
		_row("event.weekend", false),
		_row("offer.merchant_wagon", true, "2026-11-28T13:00:00Z", "2026-11-28T15:00:00Z", "offer"),
		_row("feature.shop", false, null, null, "feature"),
		_row("event.open_end", true, "2026-11-28T11:00:00+00:00"),
	])
	assert_true(f.is_active_at("event.weekly", NOON), "włączona bez okna")
	assert_true(not f.is_active_at("event.weekend", NOON), "wyłączona")
	assert_true(not f.is_active_at("offer.merchant_wagon", NOON), "przed startem okna")
	assert_true(f.is_active_at("offer.merchant_wagon", NOON + HOUR), "start okna włącznie")
	assert_true(f.is_active_at("offer.merchant_wagon", NOON + 3 * HOUR), "koniec okna włącznie")
	assert_true(not f.is_active_at("offer.merchant_wagon", NOON + 3 * HOUR + 1), "po końcu okna")
	assert_true(not f.is_active_at("feature.shop", NOON), "funkcja wyłączona w panelu")
	assert_true(f.is_active_at("event.open_end", NOON), "okno bez końca")
	return true


func test_untrusted_rows() -> bool:
	var rows: Array = [
		"nie wiersz",
		_row("Event.Weekly", true),
		_row("event weekly", true),
		_row("event.%s" % "a".repeat(FeatureFlags.KEY_MAX), true),
		{"key": "event.no_enabled", "kind": "event"},
		_row("event.bad_time", true, "jutro"),
		_row("event.dup", true),
		_row("event.dup", false),
	]
	var bad_meta := _row("event.meta", true)
	bad_meta["metadata"] = "tekst"
	rows.append(bad_meta)
	var big_meta := _row("event.big", true)
	big_meta["metadata"] = {"x": "a".repeat(FeatureFlags.METADATA_MAX)}
	rows.append(big_meta)
	var f := _flags(rows)
	assert_eq(f.keys(), ["event.big", "event.dup", "event.meta"] as Array[String], "tylko dobre wiersze")
	assert_true(f.is_active_at("event.dup", NOON), "powtórzony klucz: pierwszy wiersz")
	assert_eq(f.metadata("event.meta"), {}, "metadata nie słownik: pusty")
	assert_eq(f.metadata("event.big"), {}, "za duże metadata: puste")
	assert_eq(f.metadata("event.none"), {}, "brak flagi: puste metadata")
	var many: Array = []
	for i in FeatureFlags.MAX_ROWS + 5:
		many.append(_row("event.e%d" % i, true))
	assert_eq(_flags(many).keys().size(), FeatureFlags.MAX_ROWS, "najwyżej 100 wierszy")
	assert_true(not FeatureFlags.new().apply({"error": "x"}, NOON, 0), "zła odpowiedź odrzucona")
	return true


func test_http_date() -> bool:
	assert_eq(FeatureFlags.http_date_ms("Sat, 28 Nov 2026 12:00:00 GMT"), NOON, "nagłówek Date")
	assert_eq(FeatureFlags.http_date_ms("Sat, 28 Nov 2026 12:00:00 UTC"), -1, "tylko GMT")
	assert_eq(FeatureFlags.http_date_ms("28 Nov 2026"), -1, "zły format")
	assert_eq(FeatureFlags.http_date_ms("Sat, 28 Xyz 2026 12:00:00 GMT"), -1, "zły miesiąc")
	var headers := PackedStringArray(["Content-Type: application/json", "date: Sat, 28 Nov 2026 12:00:00 GMT"])
	assert_eq(FeatureFlags.date_from_headers(headers), NOON, "nagłówek bez względu na wielkość liter")
	assert_eq(FeatureFlags.date_from_headers(PackedStringArray()), -1, "bez nagłówka")
	return true


## Zegar serwera: w sesji od chwili odpowiedzi liczy się czas monotoniczny, więc zmiana daty w telefonie nic nie daje.
func test_server_clock() -> bool:
	var f := _flags([_row("event.weekly", true, null, "2026-11-28T13:00:00Z")])
	assert_eq(f.server_now_ms(0, 0), NOON, "chwila odpowiedzi")
	assert_eq(f.server_now_ms(999_999_999_999_999, HOUR), NOON + HOUR, "zegar telefonu pominięty w sesji")
	assert_true(f.is_active_key("event.weekly", 0, HOUR), "przed końcem okna")
	assert_true(not f.is_active_key("event.weekly", 0, HOUR + 1), "po końcu okna, choć telefon cofnięty")
	var none := FeatureFlags.new()
	assert_eq(none.server_now_ms(12345, 0), 12345, "bez odpowiedzi serwera: zegar telefonu")
	return true


## Cache: po restarcie bez sieci zostają ostatnie flagi, a zegar nie cofnie się przed ostatni znany czas serwera.
func test_cache_roundtrip() -> bool:
	var f := _flags([_row("event.weekly", true, null, "2026-11-28T13:00:00Z"), _row("feature.scout", false)])
	f.local_at_fetch_ms = NOON - 2 * HOUR
	assert_eq(f.save(PATH), OK, "zapis")
	var g := FeatureFlags.load_from(PATH)
	assert_eq(g.keys(), f.keys(), "te same flagi")
	assert_true(not g.is_active_at("feature.scout", NOON), "wyłączona funkcja z cache")
	assert_eq(g.server_now_ms(NOON - 2 * HOUR + 30 * 60000, 0), NOON + 30 * 60000, "przesunięcie zegara z cache")
	assert_eq(g.server_now_ms(0, 0), NOON, "zegar cofnięty w telefonie: najwyżej ostatni czas serwera")
	var file := FileAccess.open(PATH, FileAccess.WRITE)
	file.store_string("{zepsuty")
	file.close()
	var broken := FeatureFlags.load_from(PATH)
	assert_true(broken.keys().is_empty(), "zepsuty cache: puste")
	assert_true(broken.is_active_at("feature.pvp", NOON), "zepsuty cache: domyślne")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(PATH))
	assert_true(FeatureFlags.load_from(PATH).keys().is_empty(), "bez pliku: puste")
	return true


func test_refresh_due() -> bool:
	var f := FeatureFlags.new()
	assert_true(f.refresh_due(0), "nigdy nie pobrane")
	f.apply([], NOON, 1000)
	assert_true(not f.refresh_due(1000 + FeatureFlags.REFRESH_S * 1000 - 1), "przed 15 min")
	assert_true(f.refresh_due(1000 + FeatureFlags.REFRESH_S * 1000), "po 15 min")
	return true


## Odpowiedzi w kliencie (bez sieci, handle_flags): dobra odpowiedź podmienia flagi i trafia do cache, błąd zostawia stare.
func test_client_handles_flags() -> bool:
	var net := SupabaseClient.new()
	net.flags_path = PATH
	var loaded: Array[bool] = []
	net.flags_loaded.connect(func(ok: bool) -> void: loaded.append(ok))
	var headers := PackedStringArray(["Date: Sat, 28 Nov 2026 12:00:00 GMT"])
	net.handle_flags(HTTPRequest.RESULT_SUCCESS, 200, headers, JSON.stringify([_row("event.weekly", true)]))
	assert_true(net.flags.is_active_at("event.weekly", NOON), "flaga z serwera")
	assert_true(FeatureFlags.load_from(PATH).is_active_at("event.weekly", NOON), "flagi w cache")
	net.handle_flags(HTTPRequest.RESULT_CANT_CONNECT, 0, PackedStringArray(), "")
	net.handle_flags(HTTPRequest.RESULT_SUCCESS, 200, headers, "{\"zła\": 1}")
	net.handle_flags(HTTPRequest.RESULT_SUCCESS, 200, PackedStringArray(), "[]")
	assert_eq(loaded, [true, false, false, false] as Array[bool], "błąd sieci, zła treść i brak Date odrzucone")
	assert_true(net.flags.is_active_at("event.weekly", NOON), "po błędzie zostają stare flagi")
	assert_true(net.is_feature_active("feature.pvp"), "funkcja bez wiersza włączona")
	assert_true(not net.load_flags(), "bez połączenia flagi się nie pobierają")
	net.free()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(PATH))
	return true


## Klient czyta tylko kolumny, które gracz ma w grantach, i jest w granicach z migracji.
func test_matches_migration() -> bool:
	var sql := FileAccess.get_file_as_string(MIGRATION)
	assert_true(sql.contains("kind in ('offer', 'event', 'feature')"), "rodzaj feature")
	assert_true(sql.contains("key ~ '^[a-z0-9._]{1,%d}$'" % FeatureFlags.KEY_MAX), "klucz do 64 znaków")
	assert_true(sql.contains("grant select (key, kind, label, description, enabled, starts_at, ends_at, metadata, updated_at)"),
			"SELECT kolumnowy bez id i updated_by")
	for col in ["key", "kind", "enabled", "starts_at", "ends_at", "metadata"]:
		assert_true(FeatureFlags.LIST_PATH.contains(col), "klient czyta %s" % col)
	assert_true(not FeatureFlags.LIST_PATH.contains("updated_by") and not FeatureFlags.LIST_PATH.contains("id,"),
			"klient nie czyta id ani updated_by")
	assert_true(FeatureFlags.LIST_PATH.contains("limit=%d" % FeatureFlags.MAX_ROWS), "limit wierszy w zapytaniu")
	return true


## Online: flagi idą z serwera od razu po połączeniu, potem dopiero po REFRESH_S; w trakcie żądania nic nie dubluje.
func test_client_refreshes_when_online() -> bool:
	var session_path := "user://test_feature_flags_session.json"
	SupabaseSession.clear(session_path)
	var net := SupabaseClient.new()
	net.setup(SupabaseConfig.parse(JSON.stringify({
		"url": "https://abc.supabase.co", "publishable_key": "sb_publishable_test123",
	})), session_path, "user://test_feature_flags_sync.json")
	net.flags_path = PATH
	net.fake_transport = true
	net._process(0.0)
	assert_eq(net.flag_requests, 0, "bez połączenia nic")
	net.handle_auth(SupabaseClient.Call.SIGNUP, HTTPRequest.RESULT_SUCCESS, 200, JSON.stringify({
		"access_token": "t1", "refresh_token": "r1", "expires_in": 3600,
		"user": {"id": "00000000-0000-0000-0000-000000000280", "is_anonymous": true},
	}))
	net._process(0.0)
	net._process(0.0)
	assert_eq(net.flag_requests, 1, "po połączeniu jedno pobranie")
	net.handle_flags(HTTPRequest.RESULT_SUCCESS, 200, PackedStringArray(["Date: Sat, 28 Nov 2026 12:00:00 GMT"]), "[]")
	net._process(0.0)
	assert_eq(net.flag_requests, 1, "świeże flagi: bez ponownego pobrania")
	net.free()
	SupabaseSession.clear(session_path)
	SaveGame.delete("user://test_feature_flags_sync.json")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(PATH))
	return true
