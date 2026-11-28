# ADR 0020: Układ obrony do ataku tylko taki, jaki ma zamek na serwerze

- **Status:** przyjęty
- **Data:** 2026-11-28
- **Issue:** #421

## Kontekst

Atak PvP dostaje kopię `defense_layouts.data` obrońcy (`begin_attack` → `attacks.defense_snapshot`). Tabela miała
tylko limit rozmiaru i RLS właściciela. Koszt pułapek liczy bilans zamku z `castles.data.defense`
(`private.trap_counts`, #274), więc spreparowany klient mógł zapisać do `defense_layouts` pułapki, za które
nie zapłacił, i zadania oddziałów spoza armii.

Uczciwy klient wysyła oba z tego samego słownika: najpierw zamek, po udanym zapisie zamku tę samą obronę do
`defense_layouts` (`SupabaseClient`, #23). Serwer przy stratach (#427) zmienia tylko `recruitment` i zostawia
oddział z liczbą 0. Liczby i rodzaje jednostek obrony nie siedzą w układzie, tylko w kopii zamku
(`castle_snapshot.recruitment`, sprawdzanej przez sanity armii). Strefę obrony, kratki przy murach, zadanie
dozwolone dla klasy i epoki, budynki i miejsce pułapki oraz pojemność garnizonu filtruje sama symulacja
(`DefensePlan.order_allowed`, `battle_traps`, `battle_garrison`), ta sama u atakującego i na workerze.

## Decyzja

1. Źródłem prawdy obrony jest `castles.data.defense`. Zapis `defense_layouts` z API jako gracz musi być mu równy,
   inaczej HTTP 422 `defense_mismatch`. Bez zamku nie ma obrony.
2. Wyzwalacz zapisu zamku (`castles_check_defense`, każdy zapis) odrzuca obronę spoza kształtu
   `DefensePlan.to_dict` kodem 422 `bad_defense`:
   - zadania `[id > 0, zadanie 0..7, x, y, trasa?]`, id bez powtórzeń i tylko z `recruitment.squads`, kratka na mapie
     64×64 albo `[-1, -1]`, trasa najwyżej 2 punkty na mapie;
   - pułapki `[rodzaj 0..4, x, y, odkryta 0/1?]`, kratki bez powtórzeń, najwyżej 2 na poziom Dworu (1..10), epoka
     i technologia rodzaju zbadane;
   - `tower_priority` 0..3, `commander` od -1 do liczby generałów − 1.
3. Geometrię i wymagania budynków dalej pilnuje symulacja. Ruiny po ataku chwilowo łamią je uczciwym graczom,
   więc serwer ich nie odrzuca.
4. `begin_attack` z układem różnym od obrony z kopii zamku albo z obroną zamku spoza reguł kończy się
   `defense_invalid` (P0001, `start_attack` 409, w grze „Ten cel jest już niedostępny”), bez cichej podmiany.
5. Telefon po 422 na zapisie obrony czyta zamek od nowa (jak przy konflikcie) i zapisuje zamek z obroną.
6. Migracja raz przycina złe wpisy w `castles.data.defense` i ustawia `defense_layouts` = obrona z zamku, także
   zakłada brakujące wiersze (wyjątek od zasady „bez przycinania”, jak w #274).

## Rozważane opcje

- **Układ równy obronie z zamku, kształt sprawdzany przy zapisie zamku** (wybrana): jedno źródło prawdy, koszt pułapek
  i zabudowa już są sprawdzane na zamku, najmniej zmian w kliencie i w funkcjach, które czytają `defense_layouts`
  (zwiad, siła celu, dobór).
- **Osobny walidator `defense_layouts` względem zamku**: odrzucony. Dwa bloby mogą się rozjechać, a każda reguła
  byłaby w dwóch miejscach.
- **`begin_attack` bierze obronę z `castles.data`, tabela zostaje legacy**: odrzucony na teraz. Zmienia zwiad, siłę
  celu i dobór, które czytają `defense_layouts`.
- **Sprawdzanie geometrii (strefa, mury, miejsce pułapki) na serwerze**: odrzucone. Kopiowałoby `BuildGrid` do SQL,
  a ruiny łamią te warunki uczciwym graczom; symulacja i tak je filtruje.

## Konsekwencje

- Pułapka, za którą gracz nie zapłacił w zamku, i zadanie spoza armii nie dojdą do ataku.
- Obrońca, którego zapis obrony nie doszedł po zapisie zamku, chwilowo nie jest celem (`defense_invalid`), aż telefon
  zapisze go od nowa.
- Nowy kod błędu `defense_invalid` wymaga nowej `start_attack`; starsza zwraca go jako ogólny błąd. Migracja i Edge
  Function idą przed APK. Stary klient przy `defense_mismatch` ponawia obronę po przerwie, ale wysyła ten sam
  słownik co w zamku, więc go nie dostaje.
- Nowych danych o graczu nie ma.

## Dotknięte notatki

- [[Backend PvP]]: obrona do ataku tylko z zamku.
- [[Otwarte pytania]]: wpis w „Ustalone”.
