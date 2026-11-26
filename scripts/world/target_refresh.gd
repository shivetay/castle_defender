class_name TargetRefresh
extends RefCounted
## Płatne odświeżenie listy celów Wyprawy (#313). Pierwsze dwa odświeżenia dnia kosztują po
## BASE_COST złota, każde kolejne o STEP więcej (5, 5, 7, 9, 11...). Licznik zeruje się o północy
## według zegara telefonu (dzień lokalny z `local_day`). Złoto pobiera się dopiero po udanym
## szukaniu (`pay`), więc nieudane szukanie niczego nie kosztuje i nie podbija ceny.
## Otwarcie Wyprawy dalej szuka celów za darmo; płaci się tylko za przycisk „Nowe”.

const BASE_COST := 5
const STEP := 2
## Tyle odświeżeń dnia kosztuje BASE_COST.
const FLAT_COUNT := 2
const SECONDS_PER_DAY := 86400
## Licznik ponad tyle i tak nie zmienia rozsądnie ceny (zapis z zewnątrz jest przycinany).
const MAX_COUNT := 1000

## Dzień lokalny (numer dnia od 1970-01-01) ostatniego płatnego odświeżenia.
var day := -1
## Ile odświeżeń zapłacono w dniu `day`.
var count := 0


## Koszt odświeżenia numer `n` w dniu (od 0): 5, 5, 7, 9, 11...
static func cost_for(n: int) -> int:
	return BASE_COST + STEP * maxi(0, n - FLAT_COUNT + 1)


## Numer dnia lokalnego: czas uniksowy `unix_s` przesunięty o strefę czasową telefonu
## (`bias_min`, minuty od UTC, jak `Time.get_time_zone_from_system()["bias"]`).
static func local_day(unix_s: int, bias_min: int) -> int:
	return floori(float(unix_s + bias_min * 60) / SECONDS_PER_DAY)


## Ile odświeżeń zapłacono już w dniu `today` (inny dzień zaczyna od zera).
func paid_today(today: int) -> int:
	return count if today == day else 0


## Cena następnego odświeżenia w dniu `today`.
func cost(today: int) -> int:
	return cost_for(paid_today(today))


## Koszt jako tablica surowców (EconomyConfig.Res), dla Economy.can_afford i spend.
func cost_array(today: int) -> Array[int]:
	var out: Array[int] = []
	out.resize(EconomyConfig.count())
	out.fill(0)
	out[EconomyConfig.Res.GOLD] = cost(today)
	return out


func can_afford(economy: Economy, today: int) -> bool:
	return economy.can_afford(cost_array(today))


## Pobiera cenę za udane odświeżenie i podbija licznik dnia. False, gdy brakuje złota (nic się
## wtedy nie zmienia).
func pay(economy: Economy, today: int) -> bool:
	if not economy.spend(cost_array(today)):
		return false
	count = paid_today(today) + 1
	day = today
	return true


func save_data() -> Dictionary:
	return {"day": day, "count": count}


## Wczytuje stan z save_data(). Brakujące albo złe pola dają stan startowy.
func load_data(d: Dictionary) -> void:
	var raw_day: Variant = d.get("day", -1)
	var raw_count: Variant = d.get("count", 0)
	day = int(raw_day) if raw_day is int or raw_day is float else -1
	count = clampi(int(raw_count), 0, MAX_COUNT) if raw_count is int or raw_count is float else 0
	if day < 0:
		day = -1
		count = 0
