# ADR 0004: Siła celu PvP jako przedział liczony przez serwer

- **Status:** przyjęty
- **Data:** 2026-11-26
- **Issue:** #293

## Kontekst

Wskaźnik siły obrony (#263, `Strength.defense`) widać na własnym zamku, a na karcie celu tylko u zamków-botów,
które gra generuje z seeda (#310). Gracz-cel ma „Siła ?”, a historia obron „Obr. ?”
([[ADR/0003-historia-obron-z-nickiem-i-sila-napastnika|ADR 0003]]). `find_targets` (`match_targets`) oddaje
zarys zamku, władcę i łup, bez składu armii, pułapek i umocnień. Klient nie jest zaufany, a pełną obronę
celu dostaje dopiero w `launch_attack`; zwiad (#28) odsłania tylko jej fragment. Dokładna liczba przed atakiem
zdradzałaby to, co mgła wojny ma ukrywać ([[Backend PvP]]).

## Decyzja

1. Siłę obrony gracza-celu liczy wyłącznie serwer, funkcją `private.defense_strength(castle, layout)` z kopii
   zamku (`castles.data`) i układu obrony (`defense_layouts.data`). Wzór i wagi są te same co w grze:
   załoga z garnizonem Dworu, pułapki, wał, palisada, brama i wieża (wagi TYMCZASOWE, #263).
2. Klient dostaje tylko dolną granicę przedziału o stałych granicach, bez losowego szumu:
   krok 50 do 500, krok 100 do 2000, wyżej krok 500. Karta pokazuje np. „Siła 200-250”.
3. Po zwiadzie też widać przedział. Siła samego odsłoniętego fragmentu nie wchodzi do tej zmiany.
4. Pokazuje się tylko siła obrony. Osobnej siły armii obrońcy nie ma, bo załoga obejmuje całą armię.
5. Siła liczy się na żądanie w `match_targets` i `defense_history`, bez nowej kolumny i wyzwalacza.
6. W historii obron „Obr. 200-250” to aktualna siła obrony zamku napastnika, w tym samym przedziale.
   Bez zamku (usunięte konto) jest „Obr. ?”.
7. Karta zamku-bota też pokazuje przedział (ta sama funkcja `Strength.range_text`).
8. Zgodność klient–serwer pilnują testy. Test gry sprawdza tablice wag w migracji, a pgTAP liczy
   przykładowy zamek, który ten sam test gry liczy w `Strength.defense`.

## Rozważane opcje

- **Przedział o stałych granicach** (wybrana): pomaga wybrać cel, nie zdradza dokładnej liczby, a powtarzane
  wyszukiwania nie zawężają przedziału.
- **Przedział z losowym szumem**: odrzucony, bo kolejne wyszukiwania uśredniłyby szum do dokładnej liczby.
- **Poziom słowny (słaba / średnia / silna)**: odrzucony jako za mało konkretny przy porównaniu z własną armią.
- **Nic (jak dotąd)**: odrzucone, bo gracz nie ma czym się kierować przy wyborze celu.
- **Dokładna liczba po zwiadzie**: odrzucona, bo zdradza więcej, niż zwiad odsłania (np. oddziały bez zadania).
- **Kolumna w `castles` odświeżana przy zapisie**: odrzucona, bo dokłada stan i wyzwalacz, a liczenie
  3 albo 10 zamków na żądanie jest tanie.

## Konsekwencje

- Gra: karta celu i historia obron pokazują przedział, a bot ma przedział zamiast dokładnej liczby.
- Serwer: nowe funkcje `private.defense_strength`, `private.strength_range_low` i `private.json_int`
  (tylko `service_role`), a `match_targets` i `defense_history` mają nową kolumnę. Edge Functions
  `find_targets` i `defense_history` przekazują ją dalej. Migracja i deploy trafiają do chmury tylko
  za zgodą właścicielki.
- Dane graczy: bez nowych pól. Obcy gracz dostaje tylko zaokrąglony wskaźnik, a nie skład obrony.
- Zmiana wag w `Strength` wymaga nowej migracji z tymi samymi tablicami (test to wymusza).
- Dalej: ewentualnie siła odsłoniętego fragmentu po zwiadzie (nowe issue), finalny balans wag (#263).

## Dotknięte notatki

- [[Interfejs]]: karta celu i historia obron pokazują przedział siły.
- [[Backend PvP]]: siła celu liczona przez serwer, w kliencie tylko przedział.
- [[Otwarte pytania]]: mgła siły celu w „Ustalone”.
