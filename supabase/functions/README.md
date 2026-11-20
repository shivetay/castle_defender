# supabase/functions/

Edge Functions (Deno / TypeScript) wywoływane z klienta lub crona.

| Funkcja | Rola |
|---|---|
| `start_attack/` | Start ataku (#25): woła `begin_attack` (blokada celu, tarcza, limit startów, armia z zamku w limicie miejsc i utrzymania żywności, #249); zwraca seedy i kopie zamku i obrony |
| `finish_attack/` | Koniec ataku (#25): woła `end_attack` (wynik i łup w limitach zapasów i capacity ocalałych, tarcza 8 h od 30%); ponowienie zwraca zapisany wynik |
| `find_targets/` | Dobór przeciwnika (#24): woła `match_targets` z id gracza z tokenu, zwraca do 3 celów |
| `ranking/` | Ranking PvP (#27): woła `pvp_ranking` z id gracza z tokenu, zwraca 20 najlepszych z jego epoki (atak albo obrona) i jego wiersz |

Nowe funkcje: bez sekretów w repo; wynik/łup/ranking nie ufaj payloadom z klienta
(skill `pvp-anti-cheat`).
