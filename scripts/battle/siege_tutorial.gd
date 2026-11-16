class_name SiegeTutorial
extends RefCounted
## Postęp samouczka PvE (#16): która fala jest następna (0..WAVE_COUNT). WAVE_COUNT = ukończony.

## Indeks następnej fali do odpalenia; po wygraniu ostatniej staje się WAVE_COUNT.
var next_wave := 0


func is_complete() -> bool:
	return next_wave >= SiegeWaves.WAVE_COUNT


## Numer fali dla gracza (1..5), albo 0 gdy samouczek skończony.
func wave_number() -> int:
	return 0 if is_complete() else next_wave + 1


## Po obronie fali: przechodzi do następnej. Zwraca true, gdy właśnie ukończono wszystkie.
func advance() -> bool:
	if is_complete():
		return false
	next_wave += 1
	return is_complete()


## Po ukończeniu można odpalić fale od nowa (ćwiczenie).
func restart() -> void:
	next_wave = 0


func save_data() -> Dictionary:
	return {"next_wave": next_wave}


## Wczytuje postęp; zwraca 1, gdy wpis był niepoprawny i został pominięty (jak inne loady).
func load_data(data: Dictionary) -> int:
	if data.is_empty():
		next_wave = 0
		return 0
	if not data.has("next_wave"):
		next_wave = 0
		return 1
	next_wave = clampi(int(data["next_wave"]), 0, SiegeWaves.WAVE_COUNT)
	return 0
