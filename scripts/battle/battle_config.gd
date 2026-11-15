class_name BattleConfig
extends RefCounted
## Liczby bitwy w jednym miejscu (#14). Logika liczy się w stałym kroku TICK_HZ, a pozycje są
## w podjednostkach kratki (SUB na kratkę), więc nie ma floatów. Wartości wytrzymałości budynków
## (poza palisadą z notatki Progresja budowy) i wież są tymczasowe.

const TICK_HZ := 30
## Podjednostki na kratkę: pozycja jednostki to (kratka × SUB + przesunięcie).
const SUB := 256
## Limit czasu bitwy (notatka: 60–180 s); po nim wygrywa obrońca.
const TIME_LIMIT_S := 180
## Szybkość z notatki Jednostki (1–6) to ćwierć kratki na sekundę za punkt: 6 = 1,5 kratki/s.
const SPEED_SUB_PER_TICK := SUB / 4 / TICK_HZ
## Odstęp między uderzeniami jednostki (1 na sekundę).
const ATTACK_COOLDOWN_TICKS := TICK_HZ
## Rozrzut obrażeń z RNG bitwy, w procentach.
const DAMAGE_MIN_PERCENT := 90
const DAMAGE_MAX_PERCENT := 110
## Z jakiej odległości (w kratkach, ponad zasięg) jednostka zauważa wroga i rusza na niego.
const AGGRO_EXTRA := 3
## Koszt przejścia przez kratkę z budynkiem w szukaniu drogi: atakujący idą przez najsłabsze
## miejsce linii umocnień zamiast obchodzić ją w nieskończoność.
const BUILDING_PATH_WEIGHT := 12.0
## Co ile ticków jednostka bez celu szuka drogi od nowa.
const REPATH_TICKS := 15

## Wytrzymałość budynku na poziomie 1; poziomy mnożą ją jak palisadę z notatki Progresja budowy
## (100, 150, 220, 320, 450).
const BASE_HP := 100
const LEVEL_HP_PERCENT: Array[int] = [100, 150, 220, 320, 450]
## Mnożnik wytrzymałości rodzaju w procentach (domyślnie 100). TYMCZASOWE.
const KIND_HP_PERCENT := {
	BuildingTypes.Kind.RAMPART: 150,
	BuildingTypes.Kind.GATE: 200,
	BuildingTypes.Kind.TOWER: 250,
	BuildingTypes.Kind.MANOR: 400,
}
## Wieża drewniana strzela do atakujących (łucznicy na wieży). TYMCZASOWE.
const TOWER_ATTACK := 6
const TOWER_RANGE := 6


static func building_hp(kind: int, level: int) -> int:
	var lv := clampi(level, 1, LEVEL_HP_PERCENT.size())
	@warning_ignore("integer_division")
	return BASE_HP * LEVEL_HP_PERCENT[lv - 1] / 100 * int(KIND_HP_PERCENT.get(kind, 100)) / 100


static func time_limit_ticks() -> int:
	return TIME_LIMIT_S * TICK_HZ
