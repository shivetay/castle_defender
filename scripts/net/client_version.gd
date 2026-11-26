class_name ClientVersion
extends RefCounted
## Wymuszenie aktualizacji (#336, ADR 0005): kod wersji gry i polityka wersji z serwera.
## Serwer (`public.client_version_policy()`) podaje `min_code` (niższa wersja blokuje całą grę, także
## offline) i `recommended_code` (niższa dostaje komunikat o nowej wersji najwyżej raz na 24 h).
## Ostatnia pobrana polityka leży w `user://version_policy.json`: bez sieci gra działa, ale gdy
## zapamiętana polityka każe blokować, blokuje. Plik nie zawiera nic o graczu.
## Kod wersji: MAJOR*10000 + MINOR*100 + PATCH z `config/version` (tools/version.py).

enum Gate { OK, SOFT, HARD }

const PATH := "user://version_policy.json"
const POLICY_PATH := "/rest/v1/rpc/client_version_policy"
## Nagłówek z wersją w każdym zapytaniu do Supabase; brak = wersja sprzed #336.
const HEADER := "X-Client-Version"
## Odpowiedź serwera na zbyt starą wersję (Edge Functions i wyzwalacze zapisu, SQLSTATE PT426).
const HTTP_UPDATE_REQUIRED := 426
const STORE_URL := "market://details?id=com.shivetay.dunhold"
const STORE_WEB_URL := "https://play.google.com/store/apps/details?id=com.shivetay.dunhold"
## Miękki komunikat o tej samej wersji najwyżej raz na tyle sekund.
const SOFT_INTERVAL_S := 86400
## Po powrocie z tła polityka idzie z serwera, gdy ostatnia jest starsza niż tyle sekund.
const CHECK_INTERVAL_S := 3600
const MAX_CODE := 999999999


## Kod wersji "X.Y.Z" albo 0, gdy tekst nie jest wersją (MINOR i PATCH najwyżej 99).
static func code_of(version: String) -> int:
	var parts := version.split(".")
	if parts.size() != 3:
		return 0
	var nums: Array[int] = []
	for part in parts:
		if part.is_empty() or not part.is_valid_int() or part.begins_with("-") or part.begins_with("+"):
			return 0
		nums.append(part.to_int())
	if nums[1] > 99 or nums[2] > 99 or nums[0] > 9999:
		return 0
	return nums[0] * 10000 + nums[1] * 100 + nums[2]


static func current_code() -> int:
	return code_of(str(ProjectSettings.get_setting("application/config/version", "")))


## Link do sklepu z polityki (albo domyślny), a po nim strona Google Play, gdy sklepu nie da się otworzyć.
static func store_urls(policy: Policy) -> Array[String]:
	var first := policy.store_url if policy != null else STORE_URL
	var out: Array[String] = [first]
	if first != STORE_WEB_URL:
		out.append(STORE_WEB_URL)
	return out


static func _safe_url(url: String) -> bool:
	return url.length() <= 200 and (url.begins_with("market://") or url.begins_with("https://"))


## Progi z serwera i to, co gra pamięta o komunikatach.
class Policy:
	extends RefCounted

	var min_code := 0
	var recommended_code := 0
	var store_url := STORE_URL
	## Kiedy polityka przyszła z serwera (unix s); 0: nigdy.
	var fetched_s := 0
	## Dla której rekomendowanej wersji i kiedy ostatnio wyszedł miękki komunikat.
	var soft_code := 0
	var soft_shown_s := 0

	## Polityka z odpowiedzi `client_version_policy` albo null przy złych danych.
	static func parse(body: String) -> Policy:
		var data: Variant = SupabaseConfig.parse_json(body)
		return from_dict(data as Dictionary) if data is Dictionary else null

	static func from_dict(d: Dictionary) -> Policy:
		var min_v: Variant = d.get("min_code", 0)
		var rec_v: Variant = d.get("recommended_code", 0)
		if not (_is_number(min_v) and _is_number(rec_v)):
			return null
		var p := Policy.new()
		p.min_code = int(min_v)
		p.recommended_code = maxi(int(rec_v), p.min_code)
		if p.min_code < 0 or p.recommended_code > MAX_CODE:
			return null
		var url: Variant = d.get("store_url", STORE_URL)
		p.store_url = url as String if url is String and ClientVersion._safe_url(url as String) else STORE_URL
		return p

	static func _is_number(v: Variant) -> bool:
		return (v is int or (v is float and is_equal_approx(v as float, roundf(v as float)))) \
				and absf(float(v)) <= MAX_CODE

	static func load_from(path: String = PATH) -> Policy:
		if not FileAccess.file_exists(path):
			return null
		var data: Variant = SupabaseConfig.parse_json(FileAccess.get_file_as_string(path))
		if not data is Dictionary:
			return null
		var d := data as Dictionary
		var p := from_dict(d)
		if p == null:
			return null
		p.fetched_s = int(d.get("fetched_s", 0)) if _is_number(d.get("fetched_s", 0)) else 0
		p.soft_code = int(d.get("soft_code", 0)) if _is_number(d.get("soft_code", 0)) else 0
		p.soft_shown_s = int(d.get("soft_shown_s", 0)) if _is_number(d.get("soft_shown_s", 0)) else 0
		return p

	func save(path: String = PATH) -> Error:
		var f := FileAccess.open(path, FileAccess.WRITE)
		if f == null:
			return FileAccess.get_open_error()
		f.store_string(JSON.stringify({
			"min_code": min_code, "recommended_code": recommended_code, "store_url": store_url,
			"fetched_s": fetched_s, "soft_code": soft_code, "soft_shown_s": soft_shown_s,
		}))
		f.close()
		return OK

	func gate(code: int) -> int:
		if code < min_code:
			return Gate.HARD
		if code < recommended_code:
			return Gate.SOFT
		return Gate.OK

	func soft_due(code: int, now_s: int) -> bool:
		if gate(code) != Gate.SOFT:
			return false
		return soft_code != recommended_code or now_s - soft_shown_s >= SOFT_INTERVAL_S

	func mark_soft_shown(now_s: int) -> void:
		soft_code = recommended_code
		soft_shown_s = now_s

	## Nowa polityka z serwera zachowuje pamięć o komunikatach z poprzedniej.
	func keep_soft_state(old: Policy) -> void:
		if old != null:
			soft_code = old.soft_code
			soft_shown_s = old.soft_shown_s

	## Serwer odrzucił wersję `code` (`update_required`), choć polityka jeszcze o tym nie wie.
	func force_hard(code: int) -> void:
		min_code = maxi(min_code, code + 1)
		recommended_code = maxi(recommended_code, min_code)

	func needs_check(now_s: int) -> bool:
		return fetched_s <= 0 or now_s - fetched_s >= CHECK_INTERVAL_S
