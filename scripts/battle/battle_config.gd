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
## Obrońca przy celu widzi dalej: cała załoga reaguje razem, zamiast wchodzić do walki pojedynczo,
## gdy atakujący nadchodzą zbitą grupą (samouczek #16). TYMCZASOWE.
const DEFENDER_AGGRO_EXTRA := 8
## Koszt przejścia przez kratkę z budynkiem w szukaniu drogi: atakujący idą przez najsłabsze
## miejsce linii umocnień zamiast obchodzić ją w nieskończoność.
const BUILDING_PATH_WEIGHT := 12.0
## Waga wolnej kratki (także po wyłomie).
## Jedyne liczby zmiennoprzecinkowe bitwy: AStarGrid2D przyjmuje wagi tylko jako float. Wagi są
## stałe i dokładne w IEEE (całe liczby), więc ten sam teren daje te same ścieżki. Test
## test_battle_logic_uses_no_floats dopuszcza tylko te dwie stałe.
const FREE_PATH_WEIGHT := 1.0
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
	BuildingTypes.Kind.KEEP: 600,
}
## Zdobycie donżonu (#120): piechota atakującego stoi przy nim tyle sekund bez obrońców w pobliżu.
const CAPTURE_S := 10
## Ile kolejnych kratek sprawdza rozstawienie, gdy kratkę zajęła jednostka z sąsiedniego
## posterunku obrony (#19); potem jednostka staje na niej mimo to (mapa bez wolnego miejsca).
const SPAWN_RETRIES := 64
## Jak blisko donżonu (w kratkach od jego krawędzi) liczy się zajmowanie i obrona.
const CAPTURE_RANGE := 1
## Morale oddziałów (#98), liczby całkowite 0–100. Z notatki Drzewko technologiczne: poniżej 30 oddział
## sam się wycofuje, powyżej 80 dostaje +10% obrażeń. Start i strata za poległego są TYMCZASOWE.
const MORALE_MAX := 100
const MORALE_START := 70
const MORALE_ROUT := 30
const MORALE_HIGH := 80
const MORALE_HIGH_DAMAGE_PERCENT := 110
## Ile morale traci oddział, gdy polegnie cały jego skład; za jednego poległego traci
## MORALE_SQUAD_LOSS / początkowa liczebność (co najmniej 1). Przy starcie 70 oddział łamie się,
## gdy straci ponad połowę ludzi, niezależnie od liczebności.
const MORALE_SQUAD_LOSS := 80
## Śmierć generała (notatka Władca i generałowie): −20 morale jego oddziałów. Generałowie to #31, #32.
const MORALE_GENERAL_DEATH := -20
## U1 Wiec grodowy: +5 morale załogi.
const MORALE_U1_DEFENDERS := 5


## Premia morale załogi z badań (#98): na razie U1 Wiec grodowy. Perki władcy (Ukochany władca)
## i Kaplica dojdą z #31, #32 i epoką II.
static func defender_morale_bonus(research: Research) -> int:
	if research != null and research.is_done("U1"):
		return MORALE_U1_DEFENDERS
	return 0


## Cechy jednostek z notatki Jednostki (#15, #92), w procentach otrzymywanych albo zadawanych obrażeń.
## Od tego zasięgu (w kratkach) atak jest dystansowy: łuki, oszczepy, ogień. Włócznia (2) to wciąż walka wręcz.
const RANGED_MIN_RANGE := 3
## Tarczownik: ściana tarcz, −40% obrażeń od strzał dla siebie i sąsiadów (do 1 kratki).
const SHIELD_WALL_PERCENT := 60
## Drużynnik w przeszywanicy: −25% obrażeń wręcz.
const GAMBESON_MELEE_PERCENT := 75
## Kopijnik: szarża, ×2 obrażeń w pierwszym uderzeniu.
const CHARGE_PERCENT := 200
## Wojownik z toporem: ×1,5 obrażeń przeciw drewnu (budynki poza wałem ziemnym).
const AXE_VS_WOOD_PERCENT := 150
## Jeździec omija wolne cele (szybkość do tej wartości), chyba że stoją tuż obok.
const RIDER_IGNORES_SPEED := 2
## Podpalacz: trafiony drewniany budynek płonie tyle sekund i traci tyle punktów na sekundę. TYMCZASOWE.
const FIRE_S := 10
const FIRE_DAMAGE_PER_S := 4
## Ogień przechodzi na sąsiednie drewniane budynki (także po skosie), gdy budynek płonie już tyle
## sekund (#101). Bez losowania, więc przebieg jest powtarzalny. TYMCZASOWE.
const FIRE_SPREAD_S := 4

## Plan ataku (#18). TYMCZASOWE.
## Szturm z drabinami: tyle sekund przy murze, zanim jednostka zejdzie po drugiej stronie.
const LADDER_CLIMB_S := 3
## Oskrzydlenie bez własnej trasy: punkt obejścia co najmniej tyle kratek w bok od prostej drogi.
const FLANK_MIN_CELLS := 6
## Taranowanie bramy: osłona walczy tylko z wrogami w tylu kratkach od taranu, inaczej idzie przy nim.
const ESCORT_RADIUS := 3

## Wieża drewniana strzela do atakujących (łucznicy na wieży). TYMCZASOWE.
const TOWER_ATTACK := 6
const TOWER_RANGE := 6


static func building_hp(kind: int, level: int) -> int:
	var lv := clampi(level, 1, LEVEL_HP_PERCENT.size())
	@warning_ignore("integer_division")
	return BASE_HP * LEVEL_HP_PERCENT[lv - 1] / 100 * int(KIND_HP_PERCENT.get(kind, 100)) / 100


static func time_limit_ticks() -> int:
	return TIME_LIMIT_S * TICK_HZ
