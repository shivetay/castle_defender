# ADR 0018: Porzucony atak z zatwierdzonym planem rozstrzyga serwer

- **Status:** przyjęty
- **Data:** 2026-11-28
- **Issue:** #425

## Kontekst

`start_attack` oddaje telefonowi `battle_seed`, a bitwa jest deterministyczna. Przy zamku-bocie od #413
([[ADR/0016-weryfikacja-atakow-na-zamki-boty|ADR 0016]]) telefon dostaje od razu także plan, badania, generała i perk.
Spreparowany klient może więc policzyć wynik przed bitwą, przegraną porzucić (nowy start porzuca poprzedni atak)
i zacząć od nowa z nowym seedem. Weryfikacja przez worker tego nie łapie, bo bitwa z wybranym seedem jest prawdziwa.

Fakty z kodu przed tą decyzją:

- **PvP:** porzucenie liczy się w Elo jak przegrana (`apply_pvp_rating`, `won = false`), bez łupu, a `target_recent`
  blokuje ten cel na 24 h. Pełna obrona przychodzi dopiero z `launch_attack`, czyli przy zatwierdzeniu planu.
  Porzucenie PvP nigdy nie daje więcej niż przegrana.
- **Zamek-bot:** plan zatwierdza `begin_bot_attack` w tej samej transakcji co seed, więc commit-reveal już działa.
  Porzucenie nic jednak nie kosztowało, a kolejny start na tego samego bota dostawał nowy seed. Hamował to tylko
  limit 10 startów na 10 minut.
- Wynik wyprawy na bota nie trafiał do `PendingFinish`, więc zamknięcie gry albo brak sieci po bitwie zostawiały
  uczciwie porzucony atak.
- Strat wojska atakującego serwer nie odejmuje: zamek zapisuje telefon, a serwer pilnuje tylko przyrostu armii
  (`economy_too_fast`, `train_too_fast`).

## Decyzja

1. Porzucony atak z zatwierdzonym planem (`launched_at` i `sim_version` ustawione: PvP po `launch_attack`, bot po
   `begin_bot_attack`) trafia do kolejki workera, a skutki wchodzą z jego wyniku tak, jakby gracz dokończył bitwę:
   łup, ranking Elo, tarcza, ruiny, punkty PvE i postęp kampanii. Atak zamyka się wtedy jako `finished`
   (rozstrzygnięty przez serwer: `claimed_result is null` przy ustawionym `verification`).
2. Dotyczy trybów `shadow` i `enforce` danego rodzaju ataku (`verification_mode` dla PvP, `bot_verification_mode`
   dla botów). W `off` porzucenie zostaje po staremu.
3. Atak bez zatwierdzonego planu (wyjście z ekranu planu PvP, stary klient bez planu przy bocie) zostaje po staremu:
   przy PvP przegrana w Elo od razu i 24 h na ten cel.
4. Ranking porzuconego ataku w kolejce czeka na wynik workera. Gdy job skończy się `failed` (3 nieudane próby),
   porzucony atak na gracza liczy się raz jako przegrana, jak dotąd. `requeue_verification` nie wrzuca go drugi raz.
5. `claim_verification` przed wzięciem jobu porzuca ataki w toku starsze niż 10 minut, więc porzucony atak trafia
   do kolejki także wtedy, gdy nikt nie zaczyna nowego ataku.
6. Wynik wyprawy na bota czeka w pliku `PendingFinish` do odpowiedzi serwera. Po braku sieci albo zamknięciu gry
   wraca na serwer, a nowy start online czeka na jego wysłanie, jak przy ataku na gracza.
7. Bez limitu porzuceń (`abandon_limited`): po rozstrzygnięciu przez serwer porzucenie nic nie daje.
8. Straty armii atakującego po bitwie liczy serwer, w osobnym tickecie, blokowanym przez #425.
9. Migrację wgrywa właścicielka, na projekcie, który wskaże za każdym razem. Zmiana jest po stronie bazy, więc
   stary klient działa dalej bez zmian.

## Rozważane opcje

- **Porzucony atak rozstrzyga worker** (wybrana): porzucenie przestaje cokolwiek dawać, a uczciwie przerwana bitwa
  dostaje swój prawdziwy wynik, nawet wygraną.
- **Limit porzuconych startów na boty** (np. 3 na godzinę, `abandon_limited`): odrzucony. Ogranicza tylko liczbę
  rzutów, a karze uczciwych graczy ze słabą siecią.
- **Seed przypisany do pary (gracz, bot) do zakończenia ataku**: odrzucony. Oszust zna wtedy seed kolejnej próby
  z góry i może offline dobrać plan pod konkretny rzut.
- **Commit-reveal (seed po zatwierdzeniu planu)**: nic nie daje. Przy bocie plan już jest zatwierdzany przed seedem,
  a przy PvP pełna obrona przychodzi dopiero z zatwierdzeniem planu.
- **Porzucenie liczone jak przegrana ze stratami**: odrzucone na teraz. Straty liczy telefon, więc serwer nie może
  ich wymusić bez osobnej zmiany (punkt 8).
- **Status `abandoned` z wynikiem zamiast `finished`**: odrzucony. Ranking, złoto z łupu, historia obron, powtórki
  i ruiny patrzą na `finished`, więc każde z tych miejsc wymagałoby zmiany.

## Konsekwencje

- Oszust może dalej zamiast porzucenia wysłać od razu uczciwą przegraną i zacząć od nowa. Hamuje go limit
  10 startów na 10 minut, a zyskuje tylko czas bitwy i wojsko, które domknie punkt 8.
- Wyprawa, której start przyszedł po limicie 5 s (bitwa poszła lokalnie), rozstrzyga się na serwerze z seedem
  i planem serwera. Wynik może się różnić od bitwy, którą gracz widział, ale łup i postęp kampanii są uczciwe.
- Obrońca porzuconego ataku z planem jest zablokowany do wyniku workera (jak przy ataku w weryfikacji w `enforce`).
- Rośnie obciążenie workera o porzucone ataki z planem.
- Nowych kolumn i danych o graczu nie ma.

## Dotknięte notatki

- [[Backend PvP]]: porzucony atak z planem w kolejce workera.
- [[Serwer]]: verifier rozstrzyga też porzucone ataki.
- [[Otwarte pytania]]: wpis w „Ustalone”.
