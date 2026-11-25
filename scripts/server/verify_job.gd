class_name VerifyJob
extends RefCounted
## Czysta weryfikacja bitwy PvP (#284 / #303): ten sam GDScript co gra, bez sieci i bez stanu.
## Wejście ma kształt odpowiedzi `attack_replay` (+ opcjonalnie `sim_version`). Bitwę buduje tą samą
## drogą co powtórka (`BattleReplay.from_response` → `create_battle`). Wynik i łup nadal ustala SQL
## po `submit_verification` — tu tylko przebieg i checksum.

const ERROR_KEY := "error"
## Placeholder wyniku, gdy job nie ma `result` (kolejka claim przed zapisem claimed): parse_response /
## from_response wymagają kształtu jak powtórka, a sama symulacja z wyniku nie korzysta.
const _DUMMY_RESULT := {"won": false, "percent": 0, "stars": [false, false, false]}
const _DUMMY_FINISHED_AT := "1970-01-01T00:00:00Z"


## Przelicza job. Sukces: won, percent, stars, destroyed_ids, survivors, ticks, checksum, sim_version.
## Błąd: {error: kod} — bez wyjątków przy złych danych.
static func verify(job: Dictionary) -> Dictionary:
	if job.is_empty():
		return _fail("empty_job")
	var parsed := AttackReplay.parse_response(_normalize(job))
	if parsed.is_empty():
		return _fail("invalid_job")
	var replay := BattleReplay.from_response(parsed)
	if replay == null:
		return _fail("invalid_castle")
	var b := replay.create_battle()
	b.run(BattleConfig.time_limit_ticks())
	if b.winner == Battle.Winner.NONE:
		return _fail("unfinished")
	var result := BattleResult.of(b)
	var survivors := b.survivors(Battle.Side.ATTACKER)
	while survivors.size() < replay.castle.army.size():
		survivors.append(0)
	return {
		"won": result.won,
		"percent": result.percent,
		"stars": result.stars.duplicate(),
		"destroyed_ids": result.destroyed_ids.duplicate(),
		"survivors": survivors,
		"ticks": b.tick,
		"checksum": b.checksum(),
		"sim_version": sim_version_of(job),
	}


## `sim_version` z jobu albo kod wersji gry z `application/config/version` (jak `tools/version.py`).
static func sim_version_of(job: Dictionary) -> int:
	if job.has("sim_version"):
		var raw: Variant = job.get("sim_version")
		if raw is int or (raw is float and float(raw) == floorf(float(raw))):
			var n := int(raw)
			if n >= 0:
				return n
	return project_sim_version()


## Kod SemVer z project.godot: MAJOR*10000 + MINOR*100 + PATCH (np. 0.5.1 → 501).
static func project_sim_version() -> int:
	var text := str(ProjectSettings.get_setting("application/config/version", "0.0.0"))
	var parts := text.split(".")
	if parts.size() != 3:
		return 0
	if not parts[0].is_valid_int() or not parts[1].is_valid_int() or not parts[2].is_valid_int():
		return 0
	return int(parts[0]) * 10000 + int(parts[1]) * 100 + int(parts[2])


## Kształt jak `attack_replay`: id (albo attack_id), seedy, castle, defense, army, plan, techs,
## general, ruler_perk; brakujący result/loot/finished_at uzupełnia placeholdery tylko pod parser.
static func _normalize(job: Dictionary) -> Dictionary:
	var out := job.duplicate(true)
	if str(out.get("id", "")).is_empty() and out.has("attack_id"):
		out["id"] = str(out.get("attack_id"))
	if not out.get("result") is Dictionary:
		out["result"] = _DUMMY_RESULT.duplicate(true)
	if not out.has("loot"):
		out["loot"] = [0, 0, 0, 0]
	if str(out.get("finished_at", "")).is_empty():
		out["finished_at"] = _DUMMY_FINISHED_AT
	return out


static func _fail(code: String) -> Dictionary:
	return {ERROR_KEY: code}
