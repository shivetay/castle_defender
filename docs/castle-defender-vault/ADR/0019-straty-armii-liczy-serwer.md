# ADR 0019: Straty armii atakującego odejmuje serwer

- **Status:** przyjęty
- **Data:** 2026-11-28
- **Issue:** #427

## Kontekst

Po bitwie poległych odejmował tylko telefon (`Recruitment.apply_losses`). Serwer zna armię ataku
(`attacks.attacker_army`) i ocalałych (z telefonu albo z workera w `enforce`), ale nic nie odejmował od zamku.
Zapis zamku pilnuje tylko przyrostu armii (`economy_too_fast`, `train_too_fast`), więc spreparowany klient mógł
po każdej bitwie zapisać zamek z całym wojskiem. To ostatnia luka z grillowania #425
([[ADR/0018-porzucony-atak-rozstrzyga-serwer|ADR 0018]], pkt 8).

Uczciwy telefon już odejmuje straty i zapisuje zamek, często zanim serwer przyjmie wynik. Gdyby serwer po prostu
odjął poległych przy kolejnym zapisie (jak łup w `castle_loot_pending`, #274), uczciwy gracz straciłby wojsko
dwa razy.

## Decyzja

1. Straty odejmuje serwer. Przy wejściu skutków ataku (`outcome_applied_at`) zapisuje poległych z każdego oddziału
   w `private.castle_army_pending` (id ataku, id oddziału, liczba). Wyzwalacz zapisu zamku `castles_army_losses`
   odejmuje ich przy najbliższym zapisie do zera z tego samego oddziału, bez przenoszenia na inne oddziały,
   i zwraca rozliczenie w `castles.army_applied` (`[[id ataku, oddział, odjęci], ...]`).
2. Id oddziałów ataku zapisuje serwer przy starcie (`attacks.attacker_squads`) z kopii zamku atakującego,
   w kolejności `Recruitment.battle_ids` bez garnizonu Dworu.
3. Telefon odejmuje poległych u siebie od razu, ale trzyma ich w `Recruitment.held` i w zapisie zamku wysyła ich
   jeszcze w oddziale (`Recruitment.server_data`), dopóki odpowiedź na zapis ich nie rozliczy. Miejsca poległych
   w oddziale są zajęte do rozliczenia. Rozliczenie bez wpisu w `held` (przywrócony zamek, bitwa przerwana
   zamknięciem gry) odejmuje poległych z oddziału. Wpis nierozliczony przez dobę gra zapomina.
4. Ocaleli: z wyniku workera (`enforce`, porzucony atak), w `shadow` z wyniku telefonu. Job `failed` w `enforce`
   bierze ocalałych z telefonu, a porzucony atak bez wyniku telefonu traci całą armię ataku.
5. Starsze klienty: straty odejmuje serwer tylko dla ataków z `sim_version` ≥ `army_losses_min_sim`
   w `private.settings` (`0` = wyłączone, domyślnie) i z trybem weryfikacji `shadow` albo `enforce`. Decyzję
   zapisuje `launch_attack` w `attacks.server_losses`, a odpowiedź zatwierdzenia planu (PvP) i startu wyprawy
   z planem (bot) oddaje ją telefonowi (`server_losses`). Bez pola telefon odejmuje straty sam.
6. Kolejność wdrożenia: migracja i Edge Functions `start_attack` / `launch_attack`, potem APK, na końcu próg
   (`docs/PO-WYDANIU.md`, krok 3.3). Migracje i Edge Functions wgrywa właścicielka, na wskazanym projekcie.

## Rozważane opcje

- **Serwer odejmuje, telefon rozlicza się z odpowiedzi** (wybrana): ten sam wzorzec co łup (#274), bez
  podwójnej straty, a spreparowany klient nie ominie odjęcia, bo serwer odejmuje od tego, co telefon przyśle.
- **Telefon odejmuje, serwer sprawdza zapis względem stanu ze startu**: odrzucona. Po odrzuceniu (422) telefon
  przywraca zamek z serwera, gdzie polegli dalej żyją, więc zapis kręci się w pętli bez wyjścia.
- **Dług strat liczony per rodzaj jednostek zamiast per oddział**: odrzucony. Plan ataku i zadania obrony
  wskazują oddziały po id, więc odjęcie z innego oddziału tego samego rodzaju myliłoby gracza.
- **Przenoszenie długu na inne oddziały**, gdy oddziału już nie ma: odrzucone. Prostsze odjęcie do zera
  i mniej przypadków brzegowych.

## Konsekwencje

- W `shadow` spreparowany telefon może zgłosić, że wszyscy przeżyli. Pełną ochronę daje dopiero `enforce`,
  tak jak przy łupie ([[ADR/0016-weryfikacja-atakow-na-zamki-boty|ADR 0016]]).
- W `enforce` między końcem bitwy a wynikiem workera polegli żyją jeszcze w zamku na serwerze. Oszust może ich
  użyć w kolejnym ataku w tym czasie (zwykle sekundy). Hamuje go limit 10 startów na 10 minut.
- Wyprawa, której start przyszedł po limicie 5 s (bitwa poszła lokalnie z lokalnymi stratami), rozstrzyga się
  na serwerze ([[ADR/0018-porzucony-atak-rozstrzyga-serwer|ADR 0018]]) i serwer odejmie jej poległych jeszcze raz.
  To rzadki przypadek, do obserwacji po włączeniu progu.
- Nowy klient prosi w zapisie zamku o kolumnę `army_applied`, której stary serwer nie ma: najpierw migracja,
  potem APK.
- Nowych danych o graczu nie ma: tylko liczby jednostek i id oddziałów z zamku, kasowane z atakiem i kontem.

## Dotknięte notatki

- [[Backend PvP]]: straty armii na serwerze.
- [[Serwer]]: próg `army_losses_min_sim`.
- [[Otwarte pytania]]: wpis w „Ustalone”.
