# Backend PvP: Supabase

Asynchroniczne PvP wymaga serwera, który przechowuje zamki i układy obrony, dobiera przeciwników i zapisuje wyniki. Supabase daje to w jednym hostowanym pakiecie (Postgres, logowanie, funkcje) z darmowym progiem na start.

| Element | Rozwiązanie |
| --- | --- |
| Logowanie | Supabase Auth: konto anonimowe przy pierwszym uruchomieniu, potem powiązanie z Google |
| Połączenie z grą | `HTTPRequest` w Godot do REST i RPC Supabase (bez wtyczek) |
| Dane | Postgres: `players`, `castles` (układ budynków w JSON + wersja + `map_seed`, losowy seed terenu gracza), `defense_layouts`, `attacks` (seed, rozkazy, wynik), `shields` |
| Dobór przeciwnika | funkcja RPC w Postgres: bez tarczy, ta sama epoka ([[ADR/0010-dobor-pvp-tylko-w-tej-samej-epoce\|ADR 0010]]), ranking ±100, nie atakowany przez Ciebie w ostatnich 24 h |
| Przebieg ataku | Edge Function `start_attack` blokuje cel i zwraca kopię obrony, seed terenu obrońcy i seed bitwy; `finish_attack` zapisuje wynik, łup i tarczę |
| Powiadomienia | Firebase Cloud Messaging (HTTP v1) z Edge Function `finish_attack` po zapisaniu wyniku, w tle: jeden push na atak („Twój zamek został zaatakowany!”, wynik i procent, bez nicku). Tokeny urządzeń w `push_tokens` (bez dostępu klienta, zapis przez Edge Function `push_token`), konto serwisowe tylko w sekrecie `FCM_SERVICE_ACCOUNT`. Koniec budowy to lokalne powiadomienie na telefonie ([[ADR/0012-powiadomienia-push-fcm\|ADR 0012]]) |
| Powtórki | zapis seeda i rozkazów; powtórka to ponowne uruchomienie symulacji, nie nagranie wideo |
| Historia obron | Edge Function `defense_history` (funkcja SQL tylko dla `service_role`) zwraca tylko własne obrony: nick atakującego i siłę jego armii z `attacks.attacker_army`, bez id i nazwy zamku atakującego ([[ADR/0003-historia-obron-z-nickiem-i-sila-napastnika\|ADR 0003]]), oraz przedział siły obrony jego zamku |
| Siła celu | `match_targets` i `defense_history` liczą siłę obrony z kopii zamku na serwerze (`private.defense_strength`, wzór jak `Strength.defense`) i oddają tylko dolną granicę przedziału o stałych granicach (krok 50 / 100 / 500), bez szumu ([[ADR/0004-sila-celu-pvp-przedzial-z-serwera\|ADR 0004]]) |
| Wersja klienta | `public.client_versions` z progami `min_code` (blokada) i `recommended_code` (komunikat), czytane przez `client_version_policy()`; klient wysyła `X-Client-Version`, a Edge Functions i zapisy zamku odrzucają starszą wersję kodem `update_required` ([[ADR/0006-wymuszenie-aktualizacji-wersji-klienta\|ADR 0006]]) |
| Kampania botów | `players.bots_beaten` ustawia tylko wyzwalacz po wygranej z kolejnym botem; `begin_attack` odrzuca bota powyżej postępu (`bot_locked`). Atak na bota idzie przez `launch_attack` (plan, generał, `sim_version`), a worker weryfikuje go kluczem `bot_verification_mode` ([[ADR/0016-weryfikacja-atakow-na-zamki-boty\|ADR 0016]]) (#413) ([[ADR/0015-postep-kampanii-botow-na-serwerze\|ADR 0015]]) |
| Środowiska / deploy | staging vs prod, migracje, EF, VPS verifier, kolejność „najpierw serwer” — [[Serwer]] i `docs/PO-WYDANIU.md` |

## Symulacja deterministyczna
Bitwa liczy się w stałym kroku 30 Hz, na liczbach całkowitych (bez floatów w logice) i z seedem z serwera. Ta sama bitwa zawsze daje ten sam wynik: działają powtórki i można weryfikować oszustwa. Worker Godot headless na VPS (`server/verifier/`) odtwarza bitwę przez `claim_verification` / `submit_verification` (tryb `shadow` albo `enforce`). Ataki na boty ma ten sam worker, z osobnym kluczem `bot_verification_mode` (domyślnie `shadow`). W kolejce najpierw idą ataki PvP, potem boty, w każdej grupie FIFO ([[ADR/0016-weryfikacja-atakow-na-zamki-boty|ADR 0016]]). Atak liczy się packiem wersji gry, którą klient podał przy zatwierdzeniu ataku. Wersja bez packa / bez wiersza w `private.sim_versions` nie może atakować ([[ADR/0008-wersja-symulacji-ataku-z-klienta|ADR 0008]]).

## Reklamy z nagrodą: Google AdMob
W grze wtyczka AdMob dla Godot 4, tylko format rewarded. AdMob po obejrzeniu wywołuje weryfikację po stronie serwera (Server-Side Verification) na Edge Function `ad_reward`, która przyznaje nagrodę i pilnuje limitów dziennych w tabeli `ad_rewards`. Szczegóły nagród: [[Model wydania]].

Alternatywa: Nakama (open source serwer gier z SDK dla Godot). Ma wbudowane rankingi i matchmaking, ale trzeba go samemu hostować, więc na start jest cięższy.

Powiązane: [[Stack technologiczny]], [[Serwer]], [[Koncept gry]], [[ADR/README|ADR]]
