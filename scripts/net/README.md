# scripts/net/

Klient sieciowy PvP (Supabase). W kliencie **tylko** klucz publishable/`anon` — nigdy `service_role`.

## Kluczowe pliki

| Plik | Rola |
|---|---|
| `supabase_config.gd` | Odczyt `config/supabase.json` (wzór: `config/supabase.example.json`) |
| `supabase_client.gd` | HTTP / REST do API |
| `supabase_session.gd` | Sesja anonimowa, tryb offline |
| `castle_sync.gd` | Synchronizacja zamku i obrony (#23): treści żądań, rewizje, decyzja INSERT/PUSH/PULL |
| `attack_start.gd` | Start ataku: seedy terenu i bitwy, kopie zamku i obrony celu-gracza (#166, #25) |
| `attack_finish.gd` | Koniec ataku (#25): treść żądania `finish_attack` i łup przyjęty przez serwer |
| `defense_log.gd` | Ostatnie obrony gracza (#99): zniszczone budynki z `attacks.destroyed` do odbudowy (`Ruins`) |
| `ranking_board.gd` | Rankingi PvP (#27) i PvE (#242): odpowiedź `ranking`, wiersze tabeli |
| `pve_report.gd` | Wyprawa na zamek-bota w rankingu PvE (#242): start i wynik na serwerze, kolejność odpowiedzi, ponowienia |
| `target_search.gd` | Dobór przeciwnika (#24): odpowiedź `find_targets`, czyszczenie danych, uzupełnianie botami do 3 celów |

Backend: `supabase/` (migracje, RLS, Edge Functions). Skille: `supabase-security`, `pvp-anti-cheat`, `user-data-privacy`.
Atak na gracza (#240): `SupabaseClient.start_attack` / `finish_attack`, cel z kopii w `scripts/battle/player_castle.gd`.
Testy: `tests/test_supabase_client.gd`, `test_player_castle.gd`, `test_castle_sync.gd`, `test_attack_start.gd`, `test_attack_finish.gd`, `test_target_search.gd`, `test_ranking_board.gd`, `test_pve_ranking.gd`.
