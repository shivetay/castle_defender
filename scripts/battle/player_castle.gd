class_name PlayerCastle
extends RefCounted
## Zamek innego gracza jako cel Wyprawy (#240). Powstaje z odpowiedzi `start_attack` (AttackStart):
## kopia zamku i kopia obrony z serwera z chwili startu, seed terenu obrońcy i seed bitwy z serwera.
## Klient nie wybiera ani seeda, ani obrony przeciwnika (skill `pvp-anti-cheat`).
##
## Zamek czyta się jak zapis gry (SaveGame.from_dict) w stałej chwili `READ_MS`, a nie „teraz”, więc
## budowy, badania i szkolenie w toku zostają w toku i ta sama kopia daje zawsze ten sam zamek
## (powtórka bitwy na serwerze, #29). Łup liczy się z surowych zapasów z kopii (`economy.amounts`),
## dokładnie z tych liczb, z których serwer (`public.end_attack`) liczy limit łupu.

## Chwila odczytu kopii zamku (ms): bez nadrabiania produkcji i bez kończenia budów w toku.
const READ_MS := 0
## Ile sekund od startu ataku można planować. Serwer przyjmuje wynik do 10 minut od startu, a bitwa
## trwa najwyżej BattleConfig.time_limit_ticks() (180 s), więc zostaje zapas na wysłanie wyniku.
const PLAN_LIMIT_MIN := 7
const PLAN_LIMIT_S := PLAN_LIMIT_MIN * 60

## Id ataku ze `start_attack` (do `finish_attack`).
var attack_id := ""
var defender_id := ""
var battle_seed := 0
## Zamek-cel dla planu i bitwy: siatka, donżon jako cel, wejście z drogi i załoga obrońcy.
var target: BotCastle
## Ustawienia obrony i badania obrońcy z kopii.
var defense: DefensePlan
var research: Research
## Id oddziałów załogi w kolejności `target.defenders` (do zadań z DefensePlan).
var defender_ids: Array[int] = []
## Zapasy obrońcy z kopii, w kolejności EconomyConfig.Res (podstawa łupu jak na serwerze).
var stash: Array[int] = []
## Armia wysłana w `start_attack`: oddziały [rodzaj, liczba]. Bitwa idzie dokładnie z tym składem,
## bo serwer sprawdza ocalałych względem armii zapisanej przy starcie.
var army: Array = []
## Kiedy serwer przyjął start (s, zegar telefonu), do PLAN_LIMIT_S.
var started_s := 0
## Epoka obrońcy do domyślnych zadań załogi (DefensePlan.default_order).
var _age := 0


## Cel z odpowiedzi `start_attack` (już po AttackStart.parse_response) albo null, gdy odpowiedź
## nie jest atakiem na gracza albo kopia zamku jest nieczytelna lub nie ma donżonu.
static func from_start(start: Dictionary, sent_army: Array, now_s: int, age: int = 0) -> PlayerCastle:
	var attack := str(start.get("id", ""))
	var defender := str(start.get("defender_id", ""))
	var castle: Variant = start.get("castle")
	if attack.is_empty() or defender.is_empty() or not castle is Dictionary or sent_army.is_empty():
		return null
	var save := CastleSync.save_from_row({
		"map_seed": int(start.get("map_seed", 0)),
		"save_version": SaveGame.FORMAT_VERSION,
		"data": castle,
	})
	if save.is_empty():
		return null
	var defense_copy: Variant = start.get("defense")
	save["defense"] = defense_copy if defense_copy is Dictionary else {}
	var state := SaveGame.from_dict(save, READ_MS)
	if state == null or state.grid.keep_id() == 0:
		return null
	var pc := PlayerCastle.new()
	pc.attack_id = attack
	pc.defender_id = defender
	pc.battle_seed = int(start.get("battle_seed", 0))
	pc.army = sent_army.duplicate(true)
	pc.started_s = now_s
	pc.defense = state.defense
	pc.research = state.research
	pc.defender_ids = state.recruitment.battle_ids()
	pc.stash = stash_of(castle as Dictionary)
	var t := BotCastle.new()
	t.seed_value = state.world_seed
	t.index = -1
	t.grid = state.grid
	t.objective = state.grid.keep_id()
	t.spawn = BotCastle.edge_road(state.grid.terrain)
	t.defenders = state.recruitment.battle_squads()
	pc.target = t
	pc._age = age
	return pc



## Zapasy z kopii zamku (`economy.amounts`) tak, jak czyta je serwer: liczba całkowita 0..10 000 000,
## a zły albo brakujący wpis to 0.
static func stash_of(castle: Dictionary) -> Array[int]:
	var out: Array[int] = []
	var economy: Variant = castle.get("economy")
	var amounts: Variant = (economy as Dictionary).get("amounts") if economy is Dictionary else null
	for res in EconomyConfig.count():
		var v: Variant = (amounts as Array)[res] if amounts is Array and res < (amounts as Array).size() else 0
		var n := int(v) if (v is int or (v is float and float(v) == floorf(float(v)))) else 0
		out.append(n if n >= 0 and n <= 10000000 else 0)
	return out


## Czy plan nie trwa za długo, żeby serwer jeszcze przyjął wynik.
func can_launch(now_s: int) -> bool:
	return now_s - started_s <= PLAN_LIMIT_S


## Bitwa na zamku gracza: armia ze startu, plan ataku i badania atakującego; obrońca z kopii (załoga
## z zadaniami, priorytet wież, pułapki i badania). Ten sam cel i plan dają zawsze ten sam przebieg.
func create_battle(plan: AttackPlan, attacker_research: Research) -> Battle:
	var grid := target.grid
	var orders := defense.battle_orders(defender_ids, target.defenders, grid, _age)
	var b := Battle.for_castle_squads(grid, army, target.defenders, target.spawn, battle_seed, research,
			orders, defense.tower_priority)
	b.arm_traps(defense.traps)
	b.apply_research(Battle.Side.DEFENDER, research)
	b.set_plan(AttackPlan.from_dict(plan.to_dict()))
	b.apply_research(Battle.Side.ATTACKER, attacker_research)
	return b


## Wynik skończonej bitwy z łupem z kopii zapasów, przyciętym do capacity ocalałych (jak `end_attack`).
func result_of(b: Battle) -> BattleResult:
	var r := BattleResult.of(b)
	r.compute_player_loot(stash)
	r.limit_to_capacity(BattleResult.carry_capacity(army, b.survivors(Battle.Side.ATTACKER)))
	return r


## Treść `finish_attack` dla skończonej bitwy.
func finish_request(b: Battle, r: BattleResult) -> Dictionary:
	return AttackFinish.request(attack_id, r, army.size(), b.survivors(Battle.Side.ATTACKER))
