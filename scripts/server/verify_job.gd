class_name VerifyJob
extends RefCounted
## Czysta weryfikacja bitwy PvP (#284 / #303) i z zamkiem-botem (#413): ten sam GDScript co gra, bez sieci i bez stanu.
## Wejście ma kształt odpowiedzi `attack_replay` (+ opcjonalnie `sim_version`). Bitwę buduje tą samą
## drogą co powtórka (`BattleReplay.from_response` → `create_battle`). Wynik i łup nadal ustala SQL
## po `submit_verification` — tu tylko przebieg i checksum.

const ERROR_KEY := "error"
## Placeholdery pod `AttackReplay.parse_response` / `BattleReplay.from_response`: symulacja nie czyta
## claimed `result` / `loot` / `finished_at`, więc zawsze je nadpisujemy (oszust nie zablokuje jobu).
const _DUMMY_RESULT := {"won": false, "percent": 0, "stars": [false, false, false]}
const _DUMMY_FINISHED_AT := "1970-01-01T00:00:00Z"


## Przelicza job. Sukces: won, percent, stars, destroyed_ids, survivors, ticks, checksum, sim_version.
## Błąd: {error: kod} — bez wyjątków przy złych danych.
static func verify(job: Dictionary) -> Dictionary:
	if job.is_empty():
		return _fail("empty_job")
	var sim := project_sim_version()
	var mismatch := _sim_version_mismatch(job, sim)
	if not mismatch.is_empty():
		return mismatch
	if job.get("bot_idx") != null:
		return _verify_bot(job, sim)
	var parsed := AttackReplay.parse_response(_normalize(job))
	if parsed.is_empty():
		return _fail("invalid_job")
	var replay := BattleReplay.from_response(parsed)
	if replay == null:
		return _fail("invalid_castle")
	var b := replay.create_battle()
	# Battle.step przy tick >= time_limit_ticks kończy obrońcą (EndReason.TIME_LIMIT), więc po
	# run(time_limit_ticks) winner nie powinien zostać NONE — gałąź unfinished to tylko bezpiecznik.
	return _run(b, replay.castle.army.size(), sim)


## Atak na zamek-bota (#413, ADR 0016): zamek z BotRoster (seed musi się zgadzać z `bot_castles`), bitwa
## tą samą drogą co u atakującego (BotBattle.from_start) z planem, badaniami, generałem i perkiem z serwera.
static func _verify_bot(job: Dictionary, sim: int) -> Dictionary:
	var raw: Variant = job.get("bot_idx")
	if not (raw is int or (raw is float and float(raw) == floorf(float(raw)))):
		return _fail("bad_bot")
	var idx := int(raw)
	if idx < 0 or idx >= BotRoster.COUNT:
		return _fail("bad_bot")
	if AttackReplay._seed(job.get("map_seed")) != BotRoster.seed_of(idx):
		return _fail("bad_bot_seed")
	var battle_seed := AttackReplay._seed(job.get("battle_seed"))
	var army := AttackReplay.parse_army(job.get("army"))
	if battle_seed < 0 or army.is_empty():
		return _fail("invalid_job")
	var start := job.duplicate(true)
	start["bot_idx"] = idx
	start["battle_seed"] = battle_seed
	var b := BotBattle.from_start(BotRoster.generate(idx), army, start)
	if b == null:
		return _fail("invalid_job")
	return _run(b, army.size(), sim)


## Bitwa do końca i wynik w kształcie `submit_verification`.
static func _run(b: Battle, squads: int, sim: int) -> Dictionary:
	b.run(BattleConfig.time_limit_ticks())
	if b.winner == Battle.Winner.NONE:
		return _fail("unfinished")
	var result := BattleResult.of(b)
	var survivors := b.survivors(Battle.Side.ATTACKER)
	while survivors.size() < squads:
		survivors.append(0)
	return {
		"won": result.won,
		"percent": result.percent,
		"stars": result.stars.duplicate(),
		"destroyed_ids": result.destroyed_ids.duplicate(),
		"survivors": survivors,
		"ticks": b.tick,
		"checksum": b.checksum(),
		"sim_version": sim,
	}


## Kod SemVer z project.godot: MAJOR*10000 + MINOR*100 + PATCH (np. 0.5.1 → 501).
## Wynik workera zawsze poświadcza tę wersję (wersja packa / projektu, który liczył).
static func project_sim_version() -> int:
	var text := str(ProjectSettings.get_setting("application/config/version", "0.0.0"))
	var parts := text.split(".")
	if parts.size() != 3:
		return 0
	if not parts[0].is_valid_int() or not parts[1].is_valid_int() or not parts[2].is_valid_int():
		return 0
	return int(parts[0]) * 10000 + int(parts[1]) * 100 + int(parts[2])


## Gdy job podaje sim_version inną niż wersja tego packa/projektu → błąd (zły pack albo zła kolejka).
static func _sim_version_mismatch(job: Dictionary, project: int) -> Dictionary:
	if not job.has("sim_version"):
		return {}
	var raw: Variant = job.get("sim_version")
	if not (raw is int or (raw is float and float(raw) == floorf(float(raw)))):
		return _fail("sim_version_mismatch")
	var n := int(raw)
	if n < 0 or n != project:
		return _fail("sim_version_mismatch")
	return {}


## Kształt jak `attack_replay`: id (albo attack_id), seedy, castle, defense, army, plan, techs,
## general, ruler_perk. Claimed result/loot/finished_at zawsze zastępowane placeholderami.
static func _normalize(job: Dictionary) -> Dictionary:
	var out := job.duplicate(true)
	var id: Variant = out.get("id")
	if (id == null or str(id).is_empty()) and out.has("attack_id"):
		out["id"] = str(out.get("attack_id"))
	out["result"] = _DUMMY_RESULT.duplicate(true)
	out["loot"] = [0, 0, 0, 0]
	out["finished_at"] = _DUMMY_FINISHED_AT
	return out


static func _fail(code: String) -> Dictionary:
	return {ERROR_KEY: code}
