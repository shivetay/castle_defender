extends TestCase
## VerifyJob (#303): ten sam job → ten sam wynik/checksum; zgodność z bitwą atakującego jak
## `test_replay.gd`; zły job → błąd, nie crash. Bez sieci.

const REPLAY := preload("res://tests/test_replay.gd")
const U := UnitTypes.Unit
const SIM := 501


## Job w kształcie odpowiedzi `attack_replay` (+ sim_version), przez JSON jak z workera.
func _job(plan: AttackPlan, techs: Array, result: BattleResult = null) -> Dictionary:
	var r := result if result != null else BattleResult.new()
	var raw := {
		"id": REPLAY.ATTACK,
		"map_seed": REPLAY._map_seed(),
		"battle_seed": 4141,
		"castle": REPLAY._castle(REPLAY._map_seed()),
		"defense": {},
		"army": REPLAY.ARMY,
		"plan": plan.to_server(),
		"techs": techs,
		"result": r.to_server(),
		"loot": [10, 20, 0, 0],
		"finished_at": "2026-11-21T10:15:00.123+00:00",
		"sim_version": SIM,
	}
	return REPLAY._wire(raw) as Dictionary


func _run_to_result(b: Battle) -> Dictionary:
	b.run(BattleConfig.time_limit_ticks())
	var result := BattleResult.of(b)
	var survivors := b.survivors(Battle.Side.ATTACKER)
	while survivors.size() < REPLAY.ARMY.size():
		survivors.append(0)
	return {
		"won": result.won,
		"percent": result.percent,
		"stars": result.stars.duplicate(),
		"destroyed_ids": result.destroyed_ids.duplicate(),
		"survivors": survivors,
		"ticks": b.tick,
		"checksum": b.checksum(),
	}


## Ten sam job dwa razy: identyczny wynik i checksum (determinizm workera).
func test_same_job_same_checksum() -> bool:
	var plan := REPLAY._plan(REPLAY._keep_cell())
	var job := _job(plan, ["A7", "A1"])
	var a := VerifyJob.verify(job)
	var b := VerifyJob.verify(job)
	assert_true(not a.has(VerifyJob.ERROR_KEY), "pierwszy przebieg OK")
	assert_true(not b.has(VerifyJob.ERROR_KEY), "drugi przebieg OK")
	assert_eq(a.get("checksum"), b.get("checksum"), "ten sam checksum")
	assert_eq(a.get("won"), b.get("won"), "ta sama wygrana")
	assert_eq(a.get("percent"), b.get("percent"), "ten sam procent")
	assert_eq(a.get("stars"), b.get("stars"), "te same gwiazdki")
	assert_eq(a.get("destroyed_ids"), b.get("destroyed_ids"), "te same zniszczenia")
	assert_eq(a.get("survivors"), b.get("survivors"), "ci sami ocaleli")
	assert_eq(a.get("ticks"), b.get("ticks"), "ten sam czas")
	assert_eq(a.get("sim_version"), SIM, "sim_version z jobu")
	return true


## Wynik VerifyJob zgadza się z bitwą atakującego (fikstura jak `test_replay_matches_attacker_battle`).
func test_matches_attacker_battle() -> bool:
	var plan := REPLAY._plan(REPLAY._keep_cell())
	var techs := ["A7", "A1", "G2"]
	var pc := REPLAY._attacker(plan, techs)
	assert_true(pc != null, "atakujący dostaje kopię")
	var live := pc.create_battle()
	var expected := _run_to_result(live)
	assert_true(live.winner != Battle.Winner.NONE, "bitwa się kończy")
	var job := _job(plan, techs, pc.result_of(live))
	# bez claimed result — worker claim może podać same dane bitwy
	job.erase("result")
	job.erase("loot")
	job.erase("finished_at")
	var got := VerifyJob.verify(job)
	assert_true(not got.has(VerifyJob.ERROR_KEY), "verify OK")
	assert_eq(got.get("checksum"), expected.get("checksum"), "checksum jak u atakującego")
	assert_eq(got.get("won"), expected.get("won"), "wygrana")
	assert_eq(got.get("percent"), expected.get("percent"), "procent")
	assert_eq(got.get("stars"), expected.get("stars"), "gwiazdki")
	assert_eq(got.get("destroyed_ids"), expected.get("destroyed_ids"), "zniszczenia")
	assert_eq(got.get("survivors"), expected.get("survivors"), "ocaleli")
	assert_eq(got.get("ticks"), expected.get("ticks"), "ticki")
	# powtórka obrońcy z tym samym jobem (z wynikiem) też ten sam przebieg
	var with_result := _job(plan, techs, pc.result_of(live))
	var again := VerifyJob.verify(with_result)
	assert_eq(again.get("checksum"), expected.get("checksum"), "z wynikiem w jobie: ten sam checksum")
	return true


## Job z attack_id zamiast id i bez sim_version: nadal działa, sim_version z projektu.
func test_attack_id_and_project_sim_version() -> bool:
	var plan := REPLAY._plan(REPLAY._keep_cell())
	var job := _job(plan, ["A7"])
	job.erase("id")
	job["attack_id"] = REPLAY.ATTACK
	job.erase("sim_version")
	var got := VerifyJob.verify(job)
	assert_true(not got.has(VerifyJob.ERROR_KEY), "verify z attack_id")
	assert_eq(got.get("sim_version"), VerifyJob.project_sim_version(), "sim_version z project.godot")
	assert_true(int(got.get("sim_version")) > 0, "wersja projektu niezerowa")
	return true


## Zły job → słownik z error, bez crasha.
func test_bad_job_returns_error() -> bool:
	assert_eq(VerifyJob.verify({}).get(VerifyJob.ERROR_KEY), "empty_job", "pusty")
	assert_eq(VerifyJob.verify({"id": "x"}).get(VerifyJob.ERROR_KEY), "invalid_job", "bez pól")
	var plan := REPLAY._plan(REPLAY._keep_cell())
	var raw := _job(plan, [])
	raw["army"] = []
	assert_eq(VerifyJob.verify(raw).get(VerifyJob.ERROR_KEY), "invalid_job", "pusta armia")
	raw = _job(plan, [])
	raw["plan"] = []
	assert_eq(VerifyJob.verify(raw).get(VerifyJob.ERROR_KEY), "invalid_castle", "bez planu")
	raw = _job(plan, [])
	raw["castle"] = {"grid": {}}
	assert_eq(VerifyJob.verify(raw).get(VerifyJob.ERROR_KEY), "invalid_castle", "kopia bez donżonu")
	raw = _job(plan, [])
	raw["army"] = [[99, 1]]
	assert_eq(VerifyJob.verify(raw).get(VerifyJob.ERROR_KEY), "invalid_job", "zły rodzaj jednostki")
	return true


## Limit ticków jak w grze: TIME_LIMIT_S × TICK_HZ.
func test_time_limit_matches_game() -> bool:
	assert_eq(BattleConfig.time_limit_ticks(), BattleConfig.TIME_LIMIT_S * BattleConfig.TICK_HZ,
			"limit jak w BattleConfig")
	return true
