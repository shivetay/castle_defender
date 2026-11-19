# supabase/functions/

Edge Functions (Deno / TypeScript) wywoływane z klienta lub crona.

| Funkcja | Rola |
|---|---|
| `start_attack/` | Start ataku PvP (m.in. seed mapy / snapshot) — serwerowa ścieżka, klient niezaufany |
| `find_targets/` | Dobór przeciwnika (#24): woła `match_targets` z id gracza z tokenu, zwraca do 3 celów |

Nowe funkcje: bez sekretów w repo; wynik/łup/ranking nie ufaj payloadom z klienta
(skill `pvp-anti-cheat`).
