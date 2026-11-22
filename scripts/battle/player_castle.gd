class_name PlayerCastle
extends RefCounted
## Zamek innego gracza jako cel Wyprawy (#240). Powstaje z odpowiedzi `start_attack` (AttackStart):
## seed terenu obrońcy, seed bitwy, zarys budynków, donżon i to, co odsłonił zwiad (#28). Kopie
## zamku i obrony z chwili startu przychodzą dopiero po zatwierdzeniu planu (`launch_attack`).
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
## Rodzaj zaślepki dla budynku spoza zwiadu w siatce planu (rysuje się jako zarys).
const HIDDEN_KIND := BuildingTypes.Kind.LUMBER_HUT

## Id ataku ze `start_attack` (do `finish_attack`).
var attack_id := ""
var defender_id := ""
var map_seed := 0
var battle_seed := 0
## Co odsłonił zwiad (#28, z serwera); plan pokazuje tylko to i zarys budynków.
var intel := ScoutIntel.new()
## Zamek-cel dla planu i bitwy: siatka, donżon jako cel, wejście z drogi i załoga obrońcy.
var target: BotCastle
## Ustawienia obrony i badania obrońcy z kopii; null do zatwierdzenia planu (apply_launch, #28).
var defense: DefensePlan
var research: Research
## Plan ataku i badania atakującego zapisane na serwerze przy zatwierdzeniu (#29, apply_launch). Bitwa
## liczy się z nich, a nie z planu na telefonie, więc obrońca w powtórce (BattleReplay) widzi to samo.
var plan: AttackPlan
var attacker_research: Research
## Generał ataku z serwera (#31; poziom i perk z zamku atakującego na serwerze) albo null, i generałowie
## obrońcy z kopii jego zamku (z nich komendant obrony z DefensePlan.commander).
var attacker_general: Generals.General
var defender_generals: Generals
## Id oddziałów załogi w kolejności `target.defenders` (do zadań z DefensePlan).
var defender_ids: Array[int] = []
## Zapasy obrońcy z kopii, w kolejności EconomyConfig.Res (podstawa łupu jak na serwerze).
var stash: Array[int] = []
## Armia wysłana w `start_attack`: oddziały [rodzaj, liczba]. Bitwa idzie dokładnie z tym składem,
## bo serwer sprawdza ocalałych względem armii zapisanej przy starcie.
var army: Array = []
## Kiedy serwer przyjął start (s, zegar telefonu), do PLAN_LIMIT_S.
var started_s := 0
## Epoka do domyślnych zadań załogi (DefensePlan.default_order). Przed zatwierdzeniem epoka zamku
## atakującego (`grid.age()` w main), a po apply_launch epoka zamku obrońcy z kopii (#29): powtórka
## u obrońcy nie zna epoki atakującego, a obie strony muszą liczyć to samo.
var _age := 0


## Cel z odpowiedzi `start_attack` (już po AttackStart.parse_response) albo null, gdy odpowiedź nie
## jest atakiem na gracza albo nie ma donżonu. Pełne ukrycie obrony (#28): plan widzi tylko siatkę
## z zarysem budynków, donżonem i budynkami odsłoniętymi przez zwiad (`intel` z serwera); bitwa
## potrzebuje pełnej kopii, którą daje dopiero apply_launch.
static func from_start(start: Dictionary, sent_army: Array, now_s: int, age: int = 0) -> PlayerCastle:
	var attack := str(start.get("id", ""))
	var defender := str(start.get("defender_id", ""))
	var keep: Variant = start.get("keep")
	if attack.is_empty() or defender.is_empty() or not keep is Rect2i or sent_army.is_empty():
		return null
	var pc := PlayerCastle.new()
	pc.attack_id = attack
	pc.defender_id = defender
	pc.map_seed = int(start.get("map_seed", 0))
	pc.battle_seed = int(start.get("battle_seed", 0))
	pc.army = sent_army.duplicate(true)
	pc.started_s = now_s
	pc._age = age
	var scout: Variant = start.get("intel")
	pc.intel = scout as ScoutIntel if scout is ScoutIntel else ScoutIntel.new()
	var footprint: Array[Rect2i] = []
	var raw: Variant = start.get("footprint", [])
	if raw is Array:
		footprint.assign(raw as Array)
	pc.target = fog_target(pc.map_seed, footprint, keep as Rect2i, pc.intel)
	return pc if pc.target != null else null


## Zamek-cel planu przed zatwierdzeniem (#28): teren z `map_seed`, zarys budynków jako zaślepki
## (rodzaj ukryty), donżon jako cel i budynki odsłonięte przez zwiad z prawdziwym rodzajem
## i poziomem. Null, gdy donżonu nie da się postawić.
static func fog_target(seed_value: int, footprint: Array[Rect2i], keep: Rect2i, scout: ScoutIntel) -> BotCastle:
	var grid := BuildGrid.new(AttackStart.terrain_map(seed_value))
	var t := BotCastle.new()
	t.seed_value = seed_value
	t.index = -1
	t.grid = grid
	t.objective = grid.place_outline(keep, BuildingTypes.Kind.KEEP, 1)
	if t.objective == 0:
		return null
	for e: Array in scout.buildings:
		if e[0] != keep:
			grid.place_outline(e[0] as Rect2i, int(e[1]), int(e[2]))
	for r in footprint:
		# zaślepka: rodzaj i tak ukryty (zarys), a plan potrzebuje tylko kratek budynku
		grid.place_outline(r, HIDDEN_KIND, 1)
	t.spawn = BotCastle.edge_road(grid.terrain)
	return t


## Czy pełna kopia z `launch_attack` już jest (bitwę da się policzyć).
func is_launched() -> bool:
	return defense != null


## Pełne kopie zamku i obrony z `launch_attack` (#28, AttackLaunch.parse_response): siatka planu
## zmienia się na prawdziwy zamek (ten sam teren, więc cele i trasy planu zostają), a bitwa ma
## załogę, zadania, pułapki i badania obrońcy oraz plan i badania atakującego zapisane na serwerze (#29).
## False, gdy kopia jest nieczytelna, bez donżonu albo bez poprawnego planu dla armii ze startu.
func apply_launch(launch: Dictionary) -> bool:
	var castle: Variant = launch.get("castle")
	if not castle is Dictionary or str(launch.get("id", attack_id)) != attack_id:
		return false
	var server_plan := AttackPlan.from_server(launch.get("plan"), army.size())
	if server_plan == null:
		return false
	var techs := AttackLaunch.parse_techs(launch.get("techs"))
	var save := CastleSync.save_from_row({
		"map_seed": map_seed,
		"save_version": SaveGame.FORMAT_VERSION,
		"data": castle,
	})
	if save.is_empty():
		return false
	# zwiad obrońcy (#28) nie dotyczy tej bitwy: kopia go nie czyta
	save.erase("scout")
	var defense_copy: Variant = launch.get("defense")
	save["defense"] = defense_copy if defense_copy is Dictionary else {}
	var state := SaveGame.from_dict(save, READ_MS)
	if state == null or state.grid.keep_id() == 0:
		return false
	defense = state.defense
	research = state.research
	plan = server_plan
	attacker_research = AttackLaunch.research_of(techs)
	attacker_general = Generals.general_from(launch.get("general"))
	defender_generals = state.generals
	_age = state.grid.age()
	defender_ids = state.recruitment.battle_ids()
	stash = stash_of(castle as Dictionary)
	var t := BotCastle.new()
	t.seed_value = state.world_seed
	t.index = -1
	t.grid = state.grid
	t.objective = state.grid.keep_id()
	t.spawn = BotCastle.edge_road(state.grid.terrain)
	t.defenders = state.recruitment.battle_squads()
	target = t
	return true



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


## Bitwa na zamku gracza: armia ze startu, plan ataku i badania atakującego z serwera; obrońca z kopii
## (załoga z zadaniami, priorytet wież, pułapki i badania). Ten sam cel i plan dają zawsze ten sam
## przebieg, więc ta sama funkcja liczy bitwę u atakującego i powtórkę u obrońcy (#29).
func create_battle() -> Battle:
	var grid := target.grid
	var orders := defense.battle_orders(defender_ids, target.defenders, grid, _age)
	var b := Battle.for_castle_squads(grid, army, target.defenders, target.spawn, battle_seed, research,
			orders, defense.tower_priority)
	b.arm_traps(defense.traps)
	b.apply_research(Battle.Side.DEFENDER, research)
	b.set_plan(AttackPlan.from_dict(plan.to_dict()))  # kopia: bitwa nie zmienia zapisanego planu
	b.apply_research(Battle.Side.ATTACKER, attacker_research)
	b.set_general(Battle.Side.ATTACKER, attacker_general)
	b.set_general(Battle.Side.DEFENDER, defense.commander_general(defender_generals))
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
