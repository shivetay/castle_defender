extends TestCase
## Weryfikacja ataku na zamek-bota (#413, ADR 0016): worker liczy bitwę z botem tą samą drogą co telefon
## (BotBattle), z zamkiem z BotRoster, seedem bitwy, planem, badaniami, generałem i perkiem z serwera.
## Ten sam job daje ten sam wynik, a zły numer albo seed zamku kończy job błędem. Bez sieci.

const U := UnitTypes.Unit
const ATTACK := "00000000-0000-0000-0000-000000041300"
const BOT := 3
const ARMY := [[U.AXE_WARRIOR, 10], [U.AXE_WARRIOR, 10], [U.ARCHER, 8]]
const SEED := 4130


## Plan na donżon bota: manewry, odwrót i start po innym oddziale.
static func _plan(bot: BotCastle) -> AttackPlan:
	var keep := bot.grid.buildings[bot.objective].position
	var p := AttackPlan.new()
	var a := p.add(1, AttackPlan.Manoeuvre.FRONTAL)
	a.retreat_percent = 30
	var b := p.add(2, AttackPlan.Manoeuvre.FLANK, keep)
	b.flank_left = false
	var c := p.add(3, AttackPlan.Manoeuvre.FRONTAL)
	c.start = AttackPlan.Start.AFTER_SQUAD
	c.start_value = 1
	return p


## Odpowiedź `start_attack` dla bota (#413) po drodze przez JSON, jak z serwera.
static func _start(plan: AttackPlan, techs: Array) -> Dictionary:
	return AttackStart.parse_response(JSON.parse_string(JSON.stringify({
		"id": ATTACK, "bot_idx": BOT, "map_seed": BotRoster.seed_of(BOT), "battle_seed": SEED,
		"plan": plan.to_server(), "techs": techs, "general": {"kind": 0, "level": 2, "perk": -1},
		"ruler_perk": RulerPerks.Perk.NONE})))


## Job z kolejki (`claim_verification`) dla ataku na bota, przez JSON jak z workera.
static func _job(plan: AttackPlan, techs: Array) -> Dictionary:
	return JSON.parse_string(JSON.stringify({
		"attack_id": ATTACK, "id": ATTACK, "sim_version": VerifyJob.project_sim_version(),
		"bot_idx": BOT, "map_seed": BotRoster.seed_of(BOT), "battle_seed": SEED,
		"castle": {}, "defense": {}, "army": ARMY, "plan": plan.to_server(), "techs": techs,
		"general": {"kind": 0, "level": 2, "perk": -1}, "ruler_perk": RulerPerks.Perk.NONE})) as Dictionary


static func _expected(b: Battle) -> Dictionary:
	b.run(BattleConfig.time_limit_ticks())
	var r := BattleResult.of(b)
	var survivors := b.survivors(Battle.Side.ATTACKER)
	while survivors.size() < ARMY.size():
		survivors.append(0)
	return {"won": r.won, "percent": r.percent, "stars": r.stars.duplicate(),
			"destroyed_ids": r.destroyed_ids.duplicate(), "survivors": survivors, "ticks": b.tick,
			"checksum": b.checksum()}


## Odpowiedź startu niesie dane bitwy z serwera; niepełny plan nie daje danych do bitwy.
func test_start_response_carries_server_battle() -> bool:
	var bot := BotRoster.generate(BOT)
	var start := _start(_plan(bot), ["A1", "A7"])
	assert_eq(start.get("bot_idx"), BOT, "numer bota")
	var b := BotBattle.from_start(bot, ARMY, start)
	assert_true(b != null, "bitwa z odpowiedzi serwera")
	var bad := start.duplicate(true)
	bad.erase("plan")
	assert_true(BotBattle.from_start(bot, ARMY, bad) == null, "bez planu nie ma bitwy z serwera")
	var other := start.duplicate(true)
	other["bot_idx"] = BOT + 1
	assert_true(BotBattle.from_start(bot, ARMY, other) == null, "odpowiedź o innego bota")
	return true


## Bitwa telefonu z odpowiedzi startu i bitwa workera z joba dają ten sam wynik i checksum.
func test_worker_matches_phone_battle() -> bool:
	var bot := BotRoster.generate(BOT)
	var plan := _plan(bot)
	var techs := ["A1", "A7", "A1:2"]
	var expected := _expected(BotBattle.from_start(bot, ARMY, _start(plan, techs)))
	var got := VerifyJob.verify(_job(plan, techs))
	assert_true(not got.has(VerifyJob.ERROR_KEY), "verify OK: %s" % got)
	for key: String in expected:
		assert_eq(got.get(key), expected[key], "zgodne: %s" % key)
	assert_eq(got.get("sim_version"), VerifyJob.project_sim_version(), "sim_version z projektu")
	return true


## Determinizm: ten sam job dwa razy daje identyczny wynik; inny seed bitwy zmienia przebieg.
func test_same_job_same_result() -> bool:
	var plan := _plan(BotRoster.generate(BOT))
	var a := VerifyJob.verify(_job(plan, ["A7"]))
	var b := VerifyJob.verify(_job(plan, ["A7"]))
	assert_true(not a.has(VerifyJob.ERROR_KEY), "pierwszy przebieg OK")
	assert_eq(a, b, "ten sam wynik")
	var other := _job(plan, ["A7"])
	other["battle_seed"] = SEED + 1
	assert_true(VerifyJob.verify(other).get("checksum") != a.get("checksum"), "inny seed, inny przebieg")
	return true


## Zły numer zamku, seed niezgodny z BotRoster albo zły plan: błąd joba, bez symulacji.
func test_bad_bot_job() -> bool:
	var plan := _plan(BotRoster.generate(BOT))
	var job := _job(plan, [])
	job["map_seed"] = BotRoster.seed_of(BOT) + 1
	assert_eq(VerifyJob.verify(job).get(VerifyJob.ERROR_KEY), "bad_bot_seed", "seed spoza BotRoster")
	job = _job(plan, [])
	job["bot_idx"] = BotRoster.COUNT
	assert_eq(VerifyJob.verify(job).get(VerifyJob.ERROR_KEY), "bad_bot", "numer poza listą")
	job = _job(plan, [])
	job["bot_idx"] = "3"
	assert_eq(VerifyJob.verify(job).get(VerifyJob.ERROR_KEY), "bad_bot", "numer nie jest liczbą")
	job = _job(plan, [])
	job["plan"] = []
	assert_eq(VerifyJob.verify(job).get(VerifyJob.ERROR_KEY), "invalid_job", "bez planu")
	job = _job(plan, [])
	job["army"] = [[99, 1]]
	assert_eq(VerifyJob.verify(job).get(VerifyJob.ERROR_KEY), "invalid_job", "zły rodzaj jednostki")
	return true


## Bitwa bez sieci zostaje jak przed #413: lokalny seed z zamku i numeru celu.
func test_offline_seed_unchanged() -> bool:
	var bot := BotRoster.generate(BOT)
	assert_eq(BotBattle.local_seed(bot, BOT), PixelCanvas.hash2(bot.seed_value, BOT, 0xa77) & 0x7fffffff,
			"wzór seeda bez sieci")
	return true


## Żądanie startu z planem niesie plan, generała i wersję symulacji; bez planu ma stary kształt.
func test_request_bot_with_plan() -> bool:
	var plan := _plan(BotRoster.generate(BOT))
	var d := AttackStart.request_bot(BOT, ARMY, plan, 1)
	assert_eq(d.get("plan"), plan.to_server(), "plan")
	assert_eq(d.get("general"), 1, "generał")
	assert_eq(d.get("sim_version"), VerifyJob.project_sim_version(), "wersja symulacji")
	assert_true(not AttackStart.request_bot(BOT, ARMY, plan).has("general"), "bez generała bez klucza")
	assert_eq(AttackStart.request_bot(BOT, ARMY).keys(), ["bot_idx", "army"], "bez planu jak dotąd")
	return true


## Start bez odpowiedzi na czas (#413): wyprawa idzie bez serwera, a spóźniona odpowiedź nic nie zmienia.
func test_give_up_ignores_late_start() -> bool:
	var p := PveReport.new()
	p.begin(BOT, ARMY)
	p.give_up()
	assert_true(p.is_idle(), "bez zgłoszenia")
	assert_true(p.failed(), "bez łupu i PvE")
	assert_eq(p.on_started({"id": ATTACK, "bot_idx": BOT}, ""), {}, "spóźniony start pominięty")
	assert_true(p.is_idle(), "dalej bez zgłoszenia")
	assert_eq(p.finish(BattleResult.new(), [10, 10, 8]), {}, "wynik nie idzie na serwer")
	return true


## Migracja i Edge Function używają tych samych liczb i kluczy co gra (#413).
func test_matches_migration_and_edge() -> bool:
	var sql := FileAccess.get_file_as_string("res://supabase/migrations/20261128090000_bot_verification.sql")
	assert_true(not sql.is_empty(), "migracja jest")
	assert_true(sql.contains("v_stash := 20 + 10 * a.bot_idx") and sql.contains("v_stash := 1000 + 500 * a.bot_idx"),
			"skarbiec bota jak BattleResult.stash")
	assert_eq([BattleResult.GOLD_BASE, BattleResult.GOLD_STEP, BattleResult.STASH_BASE, BattleResult.STASH_STEP],
			[20, 10, 1000, 500], "liczby skarbca w grze")
	assert_true(sql.contains("v_loot[i + 1] * %d / 100" % BattleResult.REPEAT_PERCENT), "powtórka jak REPEAT_PERCENT")
	assert_true(sql.contains("order by (t.defender_id is null), v.created_at"), "najpierw PvP")
	assert_true(sql.contains("'bot_idx', a.bot_idx"), "job niesie numer bota")
	var fn := FileAccess.get_file_as_string("res://supabase/functions/start_attack/index.ts")
	var keys := AttackStart.request_bot(BOT, ARMY, AttackPlan.new(), 0).keys()
	for k: String in keys:
		assert_true(fn.contains("\"%s\"" % k), "Edge Function przyjmuje klucz %s" % k)
	assert_true(fn.contains("MAX_ORDERS = %d" % AttackPlan.MAX_SQUADS_BY_AGE[-1]), "limit rozkazów jak w grze")
	assert_true(fn.contains("\"begin_bot_attack\""), "start z planem przez begin_bot_attack")
	return true
