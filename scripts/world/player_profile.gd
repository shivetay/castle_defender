class_name PlayerProfile
extends RefCounted
## Profil gracza w user://player.json, osobno od zapisu zamku. Trzyma seed gracza: losuje się raz,
## przy pierwszym uruchomieniu, i zostaje na stałe, także gdy zapis zamku zniknie albo gracz zacznie
## od nowa. Z seeda gracza wynika seed zamku (WorldSeed.first_playable), więc ten sam gracz zawsze
## dostaje ten sam teren. Od etapu 8 seed przejdzie na konto w Supabase.

const PATH := "user://player.json"
const VERSION := 1


## Seed gracza z profilu albo 0, gdy profilu nie ma lub jest niepoprawny.
static func read_seed(path: String) -> int:
	var d := SaveGame.read(path)
	var value := int(d.get("player_seed", 0))
	return value if value > 0 and value <= WorldSeed.MAX_SEED else 0


static func write_seed(path: String, player_seed: int) -> Error:
	return SaveGame.write(path, {"version": VERSION, "player_seed": player_seed})


## Seed gracza: z profilu, a gdy go nie ma, `fallback` (np. seed ze starego zapisu zamku) albo
## nowy losowy. Nowy seed od razu trafia do profilu.
static func ensure_seed(path: String, fallback: int = 0) -> int:
	var value := read_seed(path)
	if value == 0:
		value = fallback if fallback > 0 and fallback <= WorldSeed.MAX_SEED else WorldSeed.random_seed()
		write_seed(path, value)
	return value


## Usuwa profil (w testach).
static func delete(path: String) -> void:
	SaveGame.delete(path)
