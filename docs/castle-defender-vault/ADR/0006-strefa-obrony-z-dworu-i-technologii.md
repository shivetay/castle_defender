# ADR 0006: Strefa obrony rośnie z Dworem i technologią O25

- **Status:** przyjęty
- **Data:** 2026-11-27
- **Issue:** #342

## Kontekst

Strefa obrony (`DefensePlan.zone`) miała stały promień 10 kratek od środka donżonu. Od niej zależą
posterunki załogi, pułapki (`trap_place_problem`) i zadania domyślne (brama i odcinek muru muszą stać
w strefie). Poziom Dworu podnosił tylko limit liczby pułapek (`TrapConfig.limit`), więc rozbudowa zamku
nie dawała więcej miejsca na obronę.

## Decyzja

1. Rośnie **cała strefa obrony**, nie tylko reguła pułapek: posterunki, pułapki i wybór bramy i murów
   do zadań domyślnych używają tego samego promienia.
2. Promień = 10 + 2 × (`Ages.bonus_level(poziom Dworu)` − 1) + poziom O25. Dwór 1: 10, Dwór 5: 18;
   w epoce II zostaje jak przy Dworze 5 (jak limit pułapek). Liczby są tymczasowe
   (`DefensePlan.RADIUS`, `RADIUS_PER_MANOR_LEVEL`, `RADIUS_PER_TECH_LEVEL`).
3. Nowa technologia **O25 Wysunięte straże** (Obrona, epoka I, bez wymagań, bada Dwór): +1 kratka
   na poziom. Jest doktryną z poziomami jak A1, A2, G1 i G2: 3 poziomy w epoce I, 5 w epoce II,
   każdy poziom drożeje jak kolejna doktryna epoki. Najdalej 18 + 5 = 23 kratki. Kod O4 jest w notatce
   zajęty (Częstokół), stąd O25.
4. Poziom O25 trzyma `BuildGrid.reach_level`, liczony z badań jak perk władcy (`SaveGame.from_dict`,
   `BuildQueue.update`), więc nie trafia do zapisu. Bitwa PvP i powtórka biorą go z kopii zamku obrońcy.
5. Serwer zna O25 w drzewku i na listach doktryn (migracja `*_defense_reach.sql`). Strefy nie liczy:
   liczy ją symulacja bitwy (gra i worker weryfikacji).

## Rozważane opcje

- **Cała strefa** (wybrana przez właścicielkę): jedna ramka na mapie i jedna reguła.
- **Tylko pułapki**: odrzucona. Dwie strefy na ekranie, a posterunki zostałyby przy 10 kratkach.
- **Skala +1 albo +3 na poziom Dworu**: odrzucone na rzecz +2 (wyraźnie, ale bez pułapek przy krawędzi mapy).
- **O25 jako zwykła technologia (+1 raz)** albo z poziomami po stałym koszcie: odrzucone, poziomy jak doktryny.

## Konsekwencje

- Zamki z Dworem powyżej 1 (także boty) mają od razu większą strefę. Zadania domyślne mogą wybrać inną
  bramę albo odcinek muru niż przedtem, więc przebieg bitwy na tych zamkach się zmienia. Nowa wersja
  gry ma nowy `sim_version`, więc weryfikacja starszych bitew liczy je starym packiem.
- Drzewko ma 44 technologie, gałąź Obrona 6.
- Migrację trzeba wgrać na projekt przed wydaniem z O25, inaczej serwer odrzuci zapis zamku z O25
  (`bad_research`).

## Dotknięte notatki

- docs/castle-defender-vault/Budynki/Obrona.md
- docs/castle-defender-vault/Drzewko technologiczne.md
