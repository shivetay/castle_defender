class_name BotBattle
extends RefCounted
## Bitwa z zamkiem-botem (#413, ADR 0016) liczona jedną drogą u atakującego i na workerze weryfikacji
## (VerifyJob). Online plan, badania, generał i perk władcy atakującego oraz seed bitwy pochodzą
## z odpowiedzi `start_attack` (serwer bierze je z zamku atakującego na serwerze), więc worker odtworzy
## dokładnie tę bitwę. Bez sieci bitwa idzie z planu i badań z telefonu i z lokalnego seeda (bez łupu, #282).


## Bitwa z botem `bot` armią `army` ([rodzaj, liczba]): zamek z BotRoster, plan (kopia: bitwa nie zmienia
## zapisanego planu), badania, generał i perk władcy atakującego.
static func create(bot: BotCastle, army: Array, battle_seed: int, plan: AttackPlan, research: Research,
		general: Generals.General, ruler_perk: int) -> Battle:
	var b := Battle.create_squads(bot.grid, bot.objective, army, bot.defenders, bot.spawn, battle_seed)
	b.set_plan(AttackPlan.from_dict(plan.to_dict()))
	b.apply_research(Battle.Side.ATTACKER, research)  # A1 topory i A2 łuki atakującego (#12)
	b.set_general(Battle.Side.ATTACKER, general)  # generał ataku (#31)
	b.set_ruler_perk(Battle.Side.ATTACKER, ruler_perk)  # Zdobywca (#32)
	return b


## Bitwa z danych serwera: odpowiedź `start_attack` (AttackStart.parse_response) albo job workera
## w tym samym kształcie. Null, gdy dane dotyczą innego bota albo plan nie pasuje do armii.
static func from_start(bot: BotCastle, army: Array, start: Dictionary) -> Battle:
	if bot == null or army.is_empty() or int(start.get("bot_idx", -1)) != bot.index:
		return null
	var plan := AttackPlan.from_server(start.get("plan"), army.size())
	if plan == null:
		return null
	var techs: Array[String] = AttackLaunch.parse_techs(start.get("techs"))
	return create(bot, army, int(start.get("battle_seed", 0)), plan, AttackLaunch.research_of(techs),
			Generals.general_from(start.get("general")), PlayerCastle.ruler_perk_from(start.get("ruler_perk")))


## Seed bitwy bez sieci (jak przed #413): z seeda zamku i numeru celu.
static func local_seed(bot: BotCastle, target: int) -> int:
	return PixelCanvas.hash2(bot.seed_value, target, 0xa77) & 0x7fffffff
