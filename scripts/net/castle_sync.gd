class_name CastleSync
extends RefCounted
## Synchronizacja zamku i obrony z serwerem (#23, seed terenu z #166). Logika bez sieci: treści
## żądań, decyzja po odczycie wiersza z serwera i stan rewizji na telefonie. Sieć prowadzi
## `SupabaseClient`.
##
## Wersjonowanie: `castles.revision` podbija wyzwalacz przy każdym zapisie. Telefon pamięta
## rewizję, od której zaczyna się jego stan (`SyncState`, `user://sync.json`), i zapisuje z filtrem
## `revision=eq.<ta rewizja>`. Gdy ktoś zapisał w międzyczasie, zapis nie trafia w żaden wiersz
## i klient czyta zamek od nowa (konflikt).
##
## Konflikt: serwer wygrywa, gdy ma nowszą rewizję niż ta, od której zaczął stan na telefonie.
## To przypadek kopii zapasowej Androida albo drugiego telefonu na tym samym koncie: stary zapis
## z telefonu nie nadpisze nowszego zamku. Wyjątki: „Zacznij od nowa” (świadomie nadpisuje zamek
## na serwerze) i pierwszy zapis gry sprzed #23, która ma już postęp na telefonie.
##
## Po reinstalacji (to samo konto) telefon nie ma zapisu ani stanu rewizji, więc zamek wraca
## z serwera razem z seedem terenu i tożsamością z onboardingu (#228).

const CASTLES_PATH := "/rest/v1/castles"
const DEFENSE_PATH := "/rest/v1/defense_layouts"
const PLAYERS_PATH := "/rest/v1/players"
const SELECT_OWN := "map_seed,save_version,revision,data"
## Pole w `castles.data` z tożsamością gracza z onboardingu (#228).
const PROFILE_KEY := "profile"

## Co zrobić po odczycie własnego wiersza zamku.
enum Action {
	## nic (brak seeda, nowszy format na serwerze, brak tożsamości do pierwszego zapisu)
	NOP,
	## zamku na serwerze nie ma: założyć
	INSERT,
	## zapisać stan z telefonu od rewizji serwera
	PUSH,
	## przywrócić zamek z serwera na telefon
	PULL,
}


## Rewizja zamku na serwerze, od której zaczyna się stan na telefonie. Leży osobno od zapisu
## zamku (`user://sync.json`), żeby „Zacznij od nowa” jej nie skasowało, a reinstalacja tak.
class SyncState:
	extends RefCounted
	const PATH := "user://sync.json"
	## Konto, do którego należy rewizja (inne konto = brak stanu).
	var player_id := ""
	## -1: telefon jeszcze nie zsynchronizował zamku z tym kontem.
	var revision := -1
	## „Zacznij od nowa”: najbliższy zapis nadpisuje zamek na serwerze bez względu na rewizję.
	var force_push := false
	## Zamek z serwera ma wrócić na telefon, ale jeszcze nie leży w zapisie lokalnym (np. zapis się nie
	## udał). Dopóki tak jest, telefon tylko przywraca, nigdy nie nadpisuje serwera starym zamkiem.
	var restore_pending := false
	## Ostatni nick wysłany do `players.nickname` (żeby nie wysyłać go przy każdym zapisie).
	var nickname := ""

	func to_dict() -> Dictionary:
		return {"player_id": player_id, "revision": revision, "force_push": force_push,
				"restore_pending": restore_pending, "nickname": nickname}

	## Czy na konto `user_id` czeka nieskończone przywrócenie zamku.
	func restore_pending_for(user_id: String) -> bool:
		return restore_pending and player_id == user_id

	## Rewizja dla konta `user_id`; stan innego konta liczy się jak brak stanu.
	func revision_for(user_id: String) -> int:
		return revision if player_id == user_id else -1

	static func from_dict(d: Dictionary) -> SyncState:
		var s := SyncState.new()
		s.player_id = str(d.get("player_id", ""))
		s.revision = maxi(-1, int(d.get("revision", -1)))
		s.force_push = bool(d.get("force_push", false))
		s.restore_pending = bool(d.get("restore_pending", false))
		s.nickname = str(d.get("nickname", ""))
		return s

	func save(path: String = PATH) -> Error:
		return SaveGame.write(path, to_dict())

	static func load_from(path: String = PATH) -> SyncState:
		return from_dict(SaveGame.read(path))


## Czy `map_seed` mieści się w zakresie kolumny `castles.map_seed` (1..2^31-1).
static func is_valid_map_seed(map_seed: int) -> bool:
	return map_seed >= 1 and map_seed <= WorldSeed.MAX_SEED


## Treść INSERT: seed terenu tylko przy założeniu zamku.
static func insert_body(player_id: String, map_seed: int, save_version: int, data: Dictionary) -> Dictionary:
	return {
		"player_id": player_id,
		"map_seed": map_seed,
		"save_version": save_version,
		"data": data,
	}


## Treść UPDATE: bez `map_seed` i bez `revision` (te ustala serwer / są niedostępne).
static func update_body(save_version: int, data: Dictionary) -> Dictionary:
	return {"save_version": save_version, "data": data}


## Ścieżka REST do własnego wiersza zamku (filtr po `player_id`).
static func own_path(player_id: String) -> String:
	return "%s?player_id=eq.%s" % [CASTLES_PATH, player_id]


## Odczyt własnego zamku: seed, wersja formatu, rewizja i dane (do przywrócenia).
static func read_path(player_id: String) -> String:
	return own_path(player_id) + "&select=" + SELECT_OWN


## Zapis z kontrolą wersji: trafia w wiersz tylko wtedy, gdy rewizja na serwerze to `base_revision`.
## Odpowiedź (`Prefer: return=representation`) to nowa rewizja albo pusta tablica przy konflikcie.
static func push_path(player_id: String, base_revision: int) -> String:
	return "%s&revision=eq.%d&select=revision" % [own_path(player_id), base_revision]


## Zapis układu obrony (wiersz w `defense_layouts`, z którego `start_attack` robi kopię dla ataku).
static func defense_path(player_id: String) -> String:
	return "%s?player_id=eq.%s&select=player_id" % [DEFENSE_PATH, player_id]


static func defense_insert_body(player_id: String, save_version: int, defense: Dictionary) -> Dictionary:
	return {"player_id": player_id, "save_version": save_version, "data": defense}


static func nickname_path(player_id: String) -> String:
	return "%s?id=eq.%s" % [PLAYERS_PATH, player_id]


## Pierwszy wiersz z odpowiedzi GET albo pusty słownik.
static func first_row(rows: Variant) -> Dictionary:
	if not rows is Array or (rows as Array).is_empty():
		return {}
	var row: Variant = (rows as Array)[0]
	return row as Dictionary if row is Dictionary else {}


## Odczyt `map_seed` z odpowiedzi GET (tablica wierszy) albo 0, gdy brak / zły wiersz.
static func map_seed_from_rows(rows: Variant) -> int:
	var value := int(first_row(rows).get("map_seed", 0))
	return value if is_valid_map_seed(value) else 0


## Rewizja z wiersza albo -1, gdy jej nie ma (np. pusta odpowiedź zapisu = konflikt).
static func revision_from_rows(rows: Variant) -> int:
	var row := first_row(rows)
	var value: Variant = row.get("revision")
	return int(value) if value is int or value is float else -1


## Dane zamku wysyłane do `castles.data`: ten sam kształt co lokalny zapis, bez pola world_seed
## (seed stoi w osobnej kolumnie `map_seed`), bez wersji (kolumna `save_version`) i bez lokalnego
## stanu Sprawdź (`seal`) i zwiadu (`scout`, #28). Z tożsamością z onboardingu w `profile`, żeby wróciła po reinstalacji.
static func castle_data(save: Dictionary, identity: PlayerProfile.Identity = null) -> Dictionary:
	var out := save.duplicate(true)
	out.erase("world_seed")
	out.erase("version")
	# Sprawdź z Komendy umocnień (#199) to stan lokalny gracza, serwer go nie potrzebuje
	out.erase("seal")
	# zwiad (#28) też zostaje na telefonie: kopia zamku trafia do atakującego (`start_attack`),
	# a raporty mówią, kogo gracz zwiadował
	out.erase("scout")
	if identity != null:
		out[PROFILE_KEY] = identity.to_dict()
	return out


## Układ obrony do `defense_layouts.data`: zadania oddziałów, pułapki i priorytet wież (#19, #20, #100).
static func defense_data(save: Dictionary) -> Dictionary:
	var d: Variant = save.get("defense", {})
	return (d as Dictionary).duplicate(true) if d is Dictionary else {}


## Zapis lokalny (jak `SaveGame.to_dict`) z wiersza serwera albo pusty słownik, gdy wiersz się nie
## nadaje: zły seed, wersja formatu spoza 1..`max_version` albo dane nie są obiektem.
static func save_from_row(row: Dictionary, max_version: int = SaveGame.FORMAT_VERSION) -> Dictionary:
	var map_seed := int(row.get("map_seed", 0))
	var version := int(row.get("save_version", 0))
	var data: Variant = row.get("data")
	if not is_valid_map_seed(map_seed) or version < 1 or version > max_version or not data is Dictionary:
		return {}
	var save := (data as Dictionary).duplicate(true)
	save.erase(PROFILE_KEY)
	save["version"] = version
	save["world_seed"] = map_seed
	return save


## Tożsamość z wiersza serwera albo null, gdy jej nie ma albo jest niepełna.
static func identity_from_row(row: Dictionary) -> PlayerProfile.Identity:
	var data: Variant = row.get("data")
	if not data is Dictionary:
		return null
	var raw: Variant = (data as Dictionary).get(PROFILE_KEY)
	if not raw is Dictionary:
		return null
	var id := PlayerProfile.Identity.from_dict(raw as Dictionary)
	return id if id.is_complete() else null


## Co zrobić po odczycie własnego wiersza zamku.
## - `local_revision`: rewizja ze `SyncState` (-1: telefon jeszcze nie synchronizował).
## - `local_fresh`: gra wystartowała bez zapisu na telefonie (reinstalacja albo „Zacznij od nowa”).
## - `force_push`: „Zacznij od nowa” ma nadpisać zamek na serwerze.
## - `can_push`: gracz ma tożsamość z onboardingu (bez niej zamek nie idzie na serwer).
static func decide(local_map_seed: int, local_revision: int, local_fresh: bool, force_push: bool,
		can_push: bool, row: Dictionary, format_version: int = SaveGame.FORMAT_VERSION) -> int:
	if row.is_empty():
		return Action.INSERT if can_push and is_valid_map_seed(local_map_seed) else Action.NOP
	# zamek zapisała nowsza wersja gry: tej wersji nie wolno go nadpisać ani wczytać
	if int(row.get("save_version", 0)) > format_version:
		return Action.NOP
	var remote_revision := int(row.get("revision", 0))
	var restorable := not save_from_row(row, format_version).is_empty()
	if force_push:
		return Action.PUSH if can_push else Action.NOP
	# start bez zapisu na telefonie, ale nie z „Zacznij od nowa” (to ustawia force_push): reinstalacja
	# albo utracony zapis, więc zamek wraca z serwera
	if local_fresh and restorable:
		return Action.PULL
	# gra z postępem sprzed #23 (zapis był, rewizji nie) zostaje i idzie na serwer
	if local_revision < 0:
		return Action.PUSH if can_push else Action.NOP
	if remote_revision > local_revision and restorable:
		return Action.PULL
	return Action.PUSH if can_push else Action.NOP
