# ADR 0010: Dobór PvP, zwiad i atak tylko w tej samej epoce

- **Status:** przyjęty
- **Data:** 2026-11-27
- **Issue:** #383

## Kontekst

Serwer łączył graczy z epok ±1: `match_targets` (`abs(p.age - me.age) <= 1`), `begin_attack`
i `begin_scout` (odrzut `target_out_of_range` przy różnicy większej niż 1). Przy grillowaniu balansu
epoki II (#262, Q15) właścicielka zdecydowała, że sytuacja, w której zamek epoki II przegrywa z tańszą
armią epoki I, ma być niemożliwa. Balans ([[ADR/0009-model-balansu-epok-ciagla-krzywa|ADR 0009]]) to jedna
warstwa, a ograniczenie doboru to druga. Klient już teraz uzupełnia brakujące karty celów zamkami-botami
z Wyprawy (`TargetSearch.fill`, napis „Brak graczy: boty”).

## Decyzja

1. `match_targets` zwraca tylko graczy z tej samej epoki (`p.age = me.age`).
2. `begin_attack` odrzuca gracza-cel z innej epoki (`d_age <> v_age` → `target_out_of_range`).
3. `begin_scout` stosuje tę samą zasadę. Odwet, gdy powstanie, też.
4. Gdy w epoce gracza nie ma celów, karty uzupełniają boty z Wyprawy według postępu kampanii, tak jak
   dotąd. Atak na bota nie sprawdza epoki.
5. Pozostałe warunki doboru (ranking ±100, tarcza, 24 h od ostatniego ataku, limity) się nie zmieniają.

## Rozważane opcje

- **Boty z Wyprawy jak dotąd** (wybrana): bot nikogo nie atakuje, więc nie łamie zasady ochrony obrońcy.
  Klient i Wyprawa zostają bez zmian.
- **Boty tylko z epoki gracza**: odrzucona na teraz. Zmienia Wyprawę i klienta bez potrzeby. Jeśli będzie
  potrzebna, dostanie osobny ticket.
- **Pusty ekran z komunikatem**: odrzucona, bo gracz zostałby bez celów do ataku.

## Konsekwencje

- Gracz epoki II nie trafia na gracza epoki I i odwrotnie, ani przy doborze, ani przy zwiadzie i starcie
  ataku, nawet ze zmodyfikowanym klientem: serwer czyta epokę z `players.age`.
- Na testach zamkniętych gracze epoki II mogą długo widzieć tylko boty. To świadoma cena tej decyzji.
- Bez nowych tabel i kolumn, bez nowych danych graczy.
- Migracja `*_same_age_matching.sql` trafia na projekt w chmurze dopiero za zgodą właścicielki.

## Dotknięte notatki

- [[Koncept gry]]: wybór celu z tej samej epoki.
- [[Backend PvP]]: dobór przeciwnika w tej samej epoce.
- [[Otwarte pytania]]: decyzja w sekcji „Ustalone”.
