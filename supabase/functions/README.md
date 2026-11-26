# supabase/functions/

Edge Functions (Deno / TypeScript) wywoływane z klienta lub crona.

| Funkcja | Rola |
|---|---|
| `start_attack/` | Start ataku (#25): woła `begin_attack` (blokada celu, tarcza, limit startów, armia z zamku w limicie miejsc i utrzymania żywności, #249); zwraca seedy, a przy graczu tylko zarys, donżon i zwiad (`attack_preview`, #28) |
| `finish_attack/` | Koniec ataku (#25): woła `end_attack` (wynik i łup w limitach zapasów i capacity ocalałych, tarcza 8 h od 30%); ponowienie zwraca zapisany wynik; potem `record_destroyed` zapisuje zniszczone budynki obrońcy (#99) |
| `find_targets/` | Dobór przeciwnika (#24): woła `match_targets` z id gracza z tokenu, zwraca do 3 celów |
| `scout/` | Zwiad na gracza (#28): woła `begin_scout` (Chata tropicieli, S1 i zwiadowcy z zamku na serwerze, naraz jedna misja, 30 na dobę); wynik z seeda serwera, w odpowiedzi tylko czas misji |
| `scout_reports/` | Raporty zwiadu (#28): `scout_reports`, wynik i odsłonięte dane dopiero po końcu misji |
| `launch_attack/` | Zatwierdzenie planu ataku na gracza (#28): pełne kopie zamku i obrony dopiero teraz; `finish_attack` przyjmuje wynik tylko po nim. Zapisuje plan ataku (sprawdzony w `check_plan`) i badania atakującego z jego zamku na serwerze do powtórki (#29) oraz generała ataku (#31: rodzaj z żądania, poziom i perk z zamku na serwerze) i oddaje je klientowi |
| `attack_replay/` | Powtórka obrony (#29): woła `attack_replay` z id gracza z tokenu; tylko obrońca zakończonego ataku dostaje seedy, kopie z chwili startu, armię, plan i badania atakującego |
| `defense_history/` | Historia obron (#328): woła `defense_history` z id gracza z tokenu; 10 ostatnich zakończonych ataków na jego zamek z wynikiem, armią i nickiem napastnika (bez id i nazwy zamku napastnika) oraz znacznikiem powtórki |
| `ranking/` | Ranking PvP (#27) i PvE (#242): woła `pvp_ranking` (atak albo obrona) albo `pve_ranking` (`pve`) z id gracza z tokenu, zwraca 20 najlepszych z jego epoki i jego wiersz |
| `pve_wave/` | Fala PvE (#288): start (`begin_wave`, fala od postępu serwera, jedna naraz, 10 startów na 10 minut) i koniec (`end_wave`, wygrana najwcześniej po 5 s, wynik do 10 minut); nagrodę za wygraną dopisuje serwer do `castle_loot_pending`, ponowienie zwraca zapisany wynik |

Nowe funkcje: bez sekretów w repo; wynik/łup/ranking nie ufaj payloadom z klienta
(skill `pvp-anti-cheat`).
