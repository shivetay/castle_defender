class_name FeatureFlags
extends RefCounted
## Flagi z panelu admina (#280, ADR 0020): tabela `public.feature_flags` (REST, tylko odczyt, rola authenticated).
## Flaga jest aktywna, gdy `enabled` i czas serwera jest w oknie `starts_at`..`ends_at` (oba końce włącznie,
## null = bez granicy). Klucz bez wiersza ma stan domyślny z przedrostka: `feature.*` włączone (funkcje gry działają,
## dopóki admin ich nie wyłączy), a `offer.*`, `event.*` i inne wyłączone.
## Flaga steruje tylko widocznością w kliencie. Nagród, łupu ani dostępu na serwerze nie przyznaje.
## Czas serwera bierze się z nagłówka `Date` odpowiedzi: w sesji dalej liczy go zegar monotoniczny, więc zmiana daty
## w telefonie nic nie daje. Po restarcie z cache liczy się przesunięcie zegara, ale nie wcześniej niż ostatni znany
## czas serwera. Treść z panelu jest niezaufana: klucze `[a-z0-9._]` do 64 znaków, najwyżej 100 wierszy, mały
## `metadata`. Cache `user://feature_flags.json` nie zawiera nic o graczu.

const PATH := "user://feature_flags.json"
## Granice z migracji `*_feature_flags.sql`: klucz do KEY_MAX znaków. MAX_ROWS to zapas na błąd panelu.
const KEY_MAX := 64
const MAX_ROWS := 100
## Najdłuższy `metadata` po JSON.stringify; większy jest pomijany (flaga zostaje).
const METADATA_MAX := 2000
## Odświeżanie w trakcie gry online (s).
const REFRESH_S := 900
## Tylko kolumny z grantu dla gracza (bez `id` i `updated_by`).
const LIST_PATH := "/rest/v1/feature_flags?select=key,kind,enabled,starts_at,ends_at,metadata&order=key.asc&limit=100"
const FEATURE_PREFIX := "feature."
const MONTHS: Array[String] = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]


class Flag:
	extends RefCounted
	var key := ""
	var kind := ""
	var enabled := false
	## ms od epoki; -1: bez granicy.
	var starts_ms := -1
	var ends_ms := -1
	var metadata: Dictionary = {}

	func active_at(now_ms: int) -> bool:
		return enabled and (starts_ms < 0 or now_ms >= starts_ms) and (ends_ms < 0 or now_ms <= ends_ms)


var _flags: Dictionary[String, Flag] = {}
## Czas serwera (ms) z ostatniej przyjętej odpowiedzi; -1: nigdy.
var server_at_fetch_ms := -1
## Zegar telefonu (ms) w tej samej chwili; daje przesunięcie po restarcie.
var local_at_fetch_ms := 0
## Czy odpowiedź przyszła w tej sesji (wtedy liczy zegar monotoniczny).
var _anchored := false
var _ticks_at_fetch_ms := 0


## Przyjmuje wiersze z serwera; false (stare flagi zostają), gdy odpowiedź nie jest listą albo brak czasu serwera.
func apply(rows: Variant, server_ms: int, ticks_ms: int, local_ms: int = -1) -> bool:
	if not rows is Array or server_ms < 0:
		return false
	_flags = parse_rows(rows as Array)
	server_at_fetch_ms = server_ms
	local_at_fetch_ms = local_ms if local_ms >= 0 else _wall_ms()
	_anchored = true
	_ticks_at_fetch_ms = ticks_ms
	return true


## Czas serwera teraz (ms): w sesji od odpowiedzi zegar monotoniczny, po restarcie przesunięcie zegara telefonu
## (nie wcześniej niż ostatni znany czas serwera), bez żadnej odpowiedzi zegar telefonu.
func server_now_ms(local_ms: int, ticks_ms: int) -> int:
	if _anchored:
		return server_at_fetch_ms + maxi(ticks_ms - _ticks_at_fetch_ms, 0)
	if server_at_fetch_ms >= 0:
		return maxi(local_ms + server_at_fetch_ms - local_at_fetch_ms, server_at_fetch_ms)
	return local_ms


func is_active_at(key: String, server_ms: int) -> bool:
	var f: Flag = _flags.get(key)
	return f.active_at(server_ms) if f != null else default_for(key)


func is_active_key(key: String, local_ms: int, ticks_ms: int) -> bool:
	return is_active_at(key, server_now_ms(local_ms, ticks_ms))


## Czy treść `key` ma być teraz widoczna w grze.
func is_active(key: String) -> bool:
	return is_active_key(key, _wall_ms(), Time.get_ticks_msec())


func metadata(key: String) -> Dictionary:
	var f: Flag = _flags.get(key)
	return f.metadata.duplicate(true) if f != null else {}


func keys() -> Array[String]:
	var out: Array[String] = []
	out.assign(_flags.keys())
	out.sort()
	return out


## Czy pora pobrać flagi z serwera (w tej sesji jeszcze nie albo minęło REFRESH_S).
func refresh_due(ticks_ms: int) -> bool:
	return not _anchored or ticks_ms - _ticks_at_fetch_ms >= REFRESH_S * 1000


static func default_for(key: String) -> bool:
	return key.begins_with(FEATURE_PREFIX) and key.length() > FEATURE_PREFIX.length() and valid_key(key)


static func valid_key(key: String) -> bool:
	if key.is_empty() or key.length() > KEY_MAX:
		return false
	for ch in key:
		if not (ch == "." or ch == "_" or (ch >= "a" and ch <= "z") or (ch >= "0" and ch <= "9")):
			return false
	return true


## Dobre wiersze (najwyżej MAX_ROWS pierwszych); przy powtórzonym kluczu zostaje pierwszy.
static func parse_rows(rows: Array) -> Dictionary[String, Flag]:
	var out: Dictionary[String, Flag] = {}
	for i in mini(rows.size(), MAX_ROWS):
		var f := flag_from(rows[i])
		if f != null and not out.has(f.key):
			out[f.key] = f
	return out


static func flag_from(row: Variant) -> Flag:
	if not row is Dictionary:
		return null
	var r := row as Dictionary
	var key: Variant = r.get("key")
	var enabled: Variant = r.get("enabled")
	if not key is String or not valid_key(key as String) or not enabled is bool:
		return null
	var f := Flag.new()
	f.key = key as String
	var kind: Variant = r.get("kind", "")
	f.kind = kind as String if kind is String and valid_key(kind as String) else ""
	f.enabled = enabled as bool
	f.starts_ms = _time_ms(r.get("starts_at"))
	f.ends_ms = _time_ms(r.get("ends_at"))
	if f.starts_ms == -2 or f.ends_ms == -2:
		return null
	var meta: Variant = r.get("metadata", {})
	if meta is Dictionary and JSON.stringify(meta).length() <= METADATA_MAX:
		f.metadata = (meta as Dictionary).duplicate(true)
	return f


## -1: null (bez granicy), -2: zły czas.
static func _time_ms(v: Variant) -> int:
	if v == null:
		return -1
	if not v is String:
		return -2
	var ms := ShopNet.iso_ms(v as String)
	return ms if ms >= 0 else -2


## Nagłówek HTTP `Date` (RFC 7231, np. „Sat, 28 Nov 2026 12:00:00 GMT”) w ms od epoki; -1, gdy zły.
static func http_date_ms(text: String) -> int:
	var parts := text.strip_edges().split(" ", false)
	if parts.size() != 6 or parts[5] != "GMT" or not parts[0].ends_with(","):
		return -1
	var month := MONTHS.find(parts[2]) + 1
	var hms := parts[4].split(":")
	if month <= 0 or hms.size() != 3 or not parts[1].is_valid_int() or not parts[3].is_valid_int():
		return -1
	for p in hms:
		if p.length() != 2 or not p.is_valid_int():
			return -1
	var day := parts[1].to_int()
	var year := parts[3].to_int()
	if day < 1 or day > 31 or year < 1970 or hms[0].to_int() > 23 or hms[1].to_int() > 59 or hms[2].to_int() > 60:
		return -1
	var s := Time.get_unix_time_from_datetime_dict({"year": year, "month": month, "day": day,
			"hour": hms[0].to_int(), "minute": hms[1].to_int(), "second": hms[2].to_int()})
	return s * 1000


static func date_from_headers(headers: PackedStringArray) -> int:
	for h in headers:
		var i := h.find(":")
		if i > 0 and h.substr(0, i).strip_edges().to_lower() == "date":
			return http_date_ms(h.substr(i + 1))
	return -1


static func load_from(path: String = PATH) -> FeatureFlags:
	var out := FeatureFlags.new()
	if not FileAccess.file_exists(path):
		return out
	var data: Variant = SupabaseConfig.parse_json(FileAccess.get_file_as_string(path))
	if not data is Dictionary:
		return out
	var d := data as Dictionary
	var server: Variant = d.get("server_ms")
	var local: Variant = d.get("local_ms")
	var rows: Variant = d.get("flags")
	if not (server is int or server is float) or not (local is int or local is float) or not rows is Array:
		return out
	out._flags = parse_rows(rows as Array)
	out.server_at_fetch_ms = maxi(int(server), -1)
	out.local_at_fetch_ms = int(local)
	return out


func save(path: String = PATH) -> Error:
	var rows: Array = []
	for key in keys():
		var f: Flag = _flags[key]
		rows.append({"key": f.key, "kind": f.kind, "enabled": f.enabled, "starts_at": _iso(f.starts_ms),
				"ends_at": _iso(f.ends_ms), "metadata": f.metadata})
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()
	file.store_string(JSON.stringify({"server_ms": server_at_fetch_ms, "local_ms": local_at_fetch_ms, "flags": rows}))
	file.close()
	return OK


static func _iso(ms: int) -> Variant:
	if ms < 0:
		return null
	return Time.get_datetime_string_from_unix_time(ms / 1000) + ".%03d+00:00" % (ms % 1000)


static func _wall_ms() -> int:
	return int(Time.get_unix_time_from_system() * 1000.0)
