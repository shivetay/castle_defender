# Backend PvP: Supabase

Asynchroniczne PvP wymaga serwera, który przechowuje zamki i układy obrony, dobiera przeciwników i zapisuje wyniki. Supabase daje to w jednym hostowanym pakiecie (Postgres, logowanie, funkcje) z darmowym progiem na start.

| Element | Rozwiązanie |
| --- | --- |
| Logowanie | Supabase Auth: konto anonimowe przy pierwszym uruchomieniu, potem powiązanie z Google |
| Połączenie z grą | `HTTPRequest` w Godot do REST i RPC Supabase (bez wtyczek) |
| Dane | Postgres: `players`, `castles` (układ budynków w JSON + wersja + `map_seed`, losowy seed terenu gracza), `defense_layouts`, `attacks` (seed, rozkazy, wynik), `shields` |
| Dobór przeciwnika | funkcja RPC w Postgres: bez tarczy, epoka ±1, ranking ±100, nie atakowany przez Ciebie w ostatnich 24 h |
| Przebieg ataku | Edge Function `start_attack` blokuje cel i zwraca kopię obrony, seed terenu obrońcy i seed bitwy; `finish_attack` zapisuje wynik, łup i tarczę |
| Powiadomienia | Firebase Cloud Messaging wywoływany z Edge Function („Twój zamek został zaatakowany”) |
| Powtórki | zapis seeda i rozkazów; powtórka to ponowne uruchomienie symulacji, nie nagranie wideo |
| Historia obron | Edge Function `defense_history` (funkcja SQL tylko dla `service_role`) zwraca tylko własne obrony: nick atakującego i siłę jego armii z `attacks.attacker_army`, bez id i nazwy zamku atakującego ([[ADR/0003-historia-obron-z-nickiem-i-sila-napastnika\|ADR 0003]]) |

## Symulacja deterministyczna
Bitwa liczy się w stałym kroku 30 Hz, na liczbach całkowitych (bez floatów w logice) i z seedem z serwera. Ta sama bitwa zawsze daje ten sam wynik: działają powtórki i można weryfikować oszustwa. W MVP serwer ufa wynikowi klienta i sprawdza tylko limity (np. łup nie większy niż możliwy). Później ten sam kod GDScript uruchomiony jako Godot headless na workerze (np. Railway) odtwarza bitwę i zatwierdza wynik.

## Reklamy z nagrodą: Google AdMob
W grze wtyczka AdMob dla Godot 4, tylko format rewarded. AdMob po obejrzeniu wywołuje weryfikację po stronie serwera (Server-Side Verification) na Edge Function `ad_reward`, która przyznaje nagrodę i pilnuje limitów dziennych w tabeli `ad_rewards`. Szczegóły nagród: [[Model wydania]].

Alternatywa: Nakama (open source serwer gier z SDK dla Godot). Ma wbudowane rankingi i matchmaking, ale trzeba go samemu hostować, więc na start jest cięższy.

Powiązane: [[Stack technologiczny]], [[Koncept gry]]
