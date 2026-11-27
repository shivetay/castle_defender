# ADR 0015: Postęp kampanii zamków-botów na serwerze

- **Status:** przyjęty
- **Data:** 2026-11-27
- **Issue:** #386

## Kontekst

Zamki-boty odblokowują się po kolei (`BotRoster.is_unlocked`), ale licznik zdobytych zamków był tylko
w zapisie gry na telefonie (`attack.beaten`). `begin_attack` sprawdzał wyłącznie, czy `bot_idx` mieści się
w 0–39. Spreparowany klient mógł od nowego konta atakować bota 39: najwyższy limit łupu
(`1000 + 500 × bot_idx`, złoto `20 + 10 × bot_idx`) i najwięcej punktów PvE (`10 + 5 × bot_idx`).

Dodatkowo karty Wyprawy (`TargetSearch.bot_indices`) uzupełniały nowemu graczowi brakujące karty botami
powyżej odblokowanego, więc uczciwy klient też atakował zamki zablokowane w kampanii.

Ataków na boty nie liczy worker weryfikacji (#284): o wygranej decyduje wynik z telefonu w limitach
`end_attack`, tak jak przy punktach PvE (#242).

## Decyzja

1. Postęp kampanii trzyma serwer w `players.bots_beaten` (`smallint`, 0–40, start 0). Ustawia go wyłącznie
   wyzwalacz na `attacks`: przy przejściu ataku na bota ze `started` do `finished` z wygraną i
   `bot_idx = bots_beaten` licznik rośnie o 1. Klient nie ma uprawnienia `UPDATE` do tej kolumny.
   `attack.beaten` z JSON zamku nie jest źródłem prawdy.
2. `begin_attack` odrzuca bota `bot_idx > bots_beaten` błędem `bot_locked`. Edge Function `start_attack`
   zwraca wtedy `409 {"error": "bot_locked", "bots_beaten": N}`.
3. Migracja raz importuje postęp istniejących graczy: `max(bot_idx) + 1` z wygranych ataków na boty
   w `attacks`. Bez okresu przejściowego.
4. Bitwa bez sieci dalej odblokowuje zamek w grze (bez łupu, jak od #282). Gdy serwer odrzuci zamek,
   klient przyjmuje licznik z odpowiedzi serwera i pokazuje „Najpierw zdobądź poprzedni zamek z siecią”.
5. Karty Wyprawy pokazują tylko odblokowane boty. Nowy gracz bez graczy w epoce widzi mniej niż 3 karty.

## Rozważane opcje

- **Kolumna z wyzwalaczem** (wybrana): jedno źródło prawdy, tani odczyt w `begin_attack`, wzór jak
  `pve_points`.
- **Liczenie z `attacks` przy każdym starcie**: bez nowych danych, ale zapytanie po historii przy każdym
  ataku, a wynik i tak pochodzi z telefonu.
- **`attack.beaten` z zamku w `castles`**: odrzucone, bo pisze go klient.
- **Okres przejściowy dla starych graczy**: odrzucony; import z `attacks` wystarcza, a zamki można zdobyć
  ponownie online.
- **Wygrana offline nie odblokowuje**: odrzucone, gra bez sieci zostaje jak dziś.
- **Zablokowane boty na kartach Wyprawy bez przycisku ataku / bez zmian**: odrzucone, uczciwy klient nie
  powinien proponować celu, który serwer odrzuci.

## Konsekwencje

- Pominięcie kampanii wymaga teraz zgłoszenia wygranej z każdym kolejnym botem (ok. 40 startów, limit
  10 startów / 10 min). Ochrona jest częściowa, dopóki worker nie liczy ataków na boty: #413.
- Postęp zdobyty tylko offline albo przed serwerem nie przechodzi na serwer; gracz zdobywa te zamki ponownie
  z siecią.
- Nowe pole o graczu: `players.bots_beaten` (postęp gry, nie dane osobowe), znika razem z kontem.
- Migrację i Edge Function wgrywa właścicielka.

## Dotknięte notatki

- [[Backend PvP]]: serwer pilnuje kolejności zamków-botów.
- [[Otwarte pytania]]: wpis w „Ustalone”.
