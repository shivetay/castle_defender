class_name BattleReplay
extends RefCounted
## Powtórka obrony (#29): bitwa na zamku obrońcy policzona jeszcze raz z danych zapisanych na serwerze
## (AttackReplay), a nie nagranie. Cel, załoga, pułapki, plan i badania atakującego budują się tą samą
## drogą co u atakującego (PlayerCastle.apply_launch i create_battle), a symulacja jest deterministyczna,
## więc obrońca widzi dokładnie ten przebieg, który widział atakujący. Wynik i łup w raporcie pochodzą
## z serwera (atakujący nie ustawia ich sam: limity sprawdza `end_attack`).

## Cel z kopii z chwili startu: zamek obrońcy w tamtym stanie, a nie bieżący.
var castle: PlayerCastle
## Wynik z serwera i łup, który zabrał atakujący (EconomyConfig.Res).
var result: BattleResult
var loot: Array[int] = []
## Koniec ataku (unix s).
var at_s := 0


## Powtórka z odpowiedzi `attack_replay` (po AttackReplay.parse_response) albo null, gdy kopia albo plan
## są nieczytelne.
static func from_response(d: Dictionary) -> BattleReplay:
	if d.is_empty():
		return null
	var pc := PlayerCastle.new()
	pc.attack_id = str(d.get("id", ""))
	pc.map_seed = int(d.get("map_seed", 0))
	pc.battle_seed = int(d.get("battle_seed", 0))
	pc.army = (d.get("army", []) as Array).duplicate(true)
	if pc.army.is_empty() or not pc.apply_launch({"id": pc.attack_id, "castle": d.get("castle"),
			"defense": d.get("defense", {}), "plan": d.get("plan"), "techs": d.get("techs", [])}):
		return null
	var r := BattleReplay.new()
	r.castle = pc
	r.result = d.get("result") as BattleResult
	r.loot.assign(d.get("loot", []) as Array)
	r.at_s = int(d.get("at_s", 0))
	return r if r.result != null else null


## Nowa bitwa od początku (każde obejrzenie liczy się od zera).
func create_battle() -> Battle:
	return castle.create_battle()


## Zamek-cel do narysowania mapy powtórki.
func target() -> BotCastle:
	return castle.target
