# ADR 0016: Weryfikacja ataków na zamki-boty na serwerze

- **Status:** przyjęty
- **Data:** 2026-11-27
- **Issue:** #413

## Kontekst

Od #386 serwer pilnuje kolejności kampanii botów (`players.bots_beaten`, [[ADR/0015-postep-kampanii-botow-na-serwerze|ADR 0015]]).
Sama wygrana nadal idzie z telefonu: o zwycięstwie, łupie z bota (#282) i punktach PvE (#242) decyduje klient.
Spreparowany klient w ok. 40 startach dochodzi do bota 39.

Worker weryfikacji (#284) liczy tylko ataki PvP. Atak na bota nie ma na serwerze planu, badań, generała, perku
ani `sim_version`, bo pomija `launch_attack`. Telefon liczy bitwę z botem z własnego seeda, a nie z `battle_seed`
z serwera, więc wynik nie jest odtwarzalny po stronie serwera.

## Decyzja

1. Weryfikacja botów ma osobny klucz `bot_verification_mode` (`off` / `shadow` / `enforce`), domyślnie `shadow`.
   Nie dzieli przełącznika z PvP. W `shadow` worker liczy wynik i porównuje go z telefonem, ale nie zmienia nagród.
   Ścieżka `enforce` jest gotowa na serwerze; włączenie wymaga zgody właścicielki. UX „weryfikacja” idzie osobno w #417.
2. Worker buduje zamek-bota z `bot_idx` i `map_seed` przez `BotRoster`. Zły seed kończy job błędem. Kopii zamku-bota
   nie ma w bazie.
3. Atak na bota online niesie plan, generała i `sim_version` już w `start_attack`. Serwer zatwierdza plan w tej
   samej transakcji co start (`public.begin_bot_attack` = `begin_attack` + `launch_attack`), bo zamek-bot nie ma
   ukrytej obrony i drugi etap nic nie daje. Badania, poziom generała i perk bierze serwer z zamku gracza
   i oddaje je w odpowiedzi. Online bitwa z botem czeka na tę odpowiedź i używa `battle_seed` z serwera.
   Bez odpowiedzi w 5 s, przy błędzie sieci albo odmowie bitwa idzie jak dotąd bez serwera (lokalny seed,
   bez łupu). Offline bez zmian.
4. W `enforce` łup, punkty PvE i `bots_beaten` przyznaje dopiero `verified_result`. Gdy wynik workera różni się
   od telefonu (mismatch), liczy się wynik workera. Gdy job zakończy się `failed`, nagród nie ma.
5. Kolejka weryfikacji: najpierw ataki PvP, potem boty, w każdej grupie FIFO.
6. Stare klienty bez `launch_attack` nie trafiają do kolejki. Przed włączeniem `enforce` właścicielka podnosi
   `min_code` ([[ADR/0006-wymuszenie-aktualizacji-wersji-klienta|ADR 0006]]).
7. Migracje i Edge Functions wgrywa właścicielka, na projekcie, który wskaże za każdym razem.

## Rozważane opcje

- **Kopia zamku-bota przy `begin_attack`**: odrzucona. Zamek to kod wersjonowany packiem, a kopia w bazie rozjechałaby się z grą przy zmianie bilansu.
- **Plan zapisywany w `finish_attack`**: odrzucona. Plan ma być zatwierdzony przed bitwą i pochodzić z serwera.
- **Start, a potem osobne `launch_attack` jak w PvP**: odrzucone. Dwa czekania przed bitwą bez zysku, bo zamek-bot
  nie ma ukrytej obrony.
- **Wspólny przełącznik z PvP**: odrzucony. Boty i PvP wdrażamy w innym tempie; problem z botami nie może zablokować PvP.
- **`failed` daje nagrody z telefonu**: odrzucone. To furtka: wystarczy „zepsuć” job.
- **FIFO bez priorytetu**: odrzucone. W `enforce` atak PvP blokuje obrońcę do czasu weryfikacji, więc zaległe boty przed nim szkodziłyby graczom.

## Konsekwencje

- Bitwa z botem online czeka przed startem na odpowiedź `start_attack` („Łączę z serwerem...”), zwykle poniżej sekundy.
- Nowy klient wysyła do `start_attack` pola `plan`, `general` i `sim_version`, których stara Edge Function nie zna
  (`unknown_field`): najpierw wdrożenie serwera, potem wydanie klienta.
- Bitwy z botami online losują inaczej: seed pochodzi z serwera, a nie z telefonu.
- Rośnie obciążenie workera. Miernik `oldest_pending_s` pokaże, czy kolejka stoi.
- Nowych danych o graczu nie ma. Używane są tylko kolumny ataku, które już istnieją.
- Ochrona z [[ADR/0015-postep-kampanii-botow-na-serwerze|ADR 0015]] przestaje być częściowa po włączeniu `enforce` dla botów. Do tego czasu zostaje częściowa.

## Dotknięte notatki

- [[Backend PvP]]: worker weryfikuje też ataki na boty, klucz `bot_verification_mode`, priorytet PvP w kolejce.
- [[Serwer]]: klucz `bot_verification_mode` i kolejka w sekcji o verifierze.
- [[Otwarte pytania]]: wpis w „Ustalone”.
