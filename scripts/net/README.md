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
| `pending_finish.gd` | Wynik ataku na gracza czekający na serwer w `user://attack_result.json` (#99): przetrwa zamknięcie gry, wraca po połączeniu |
| `defense_log.gd` | Ostatnie obrony gracza (#99): zniszczone budynki z `attacks.destroyed` do odbudowy (`Ruins`); raporty obron do listy powtórek (#29) |
| `attack_replay.gd` | Powtórka obrony (#29): kontrakt `attack_replay`, sprawdzenie armii, seedów i wyniku z serwera |
| `ranking_board.gd` | Rankingi PvP (#27) i PvE (#242): odpowiedź `ranking`, wiersze tabeli |
| `pve_report.gd` | Wyprawa na zamek-bota w rankingu PvE (#242): start i wynik na serwerze, kolejność odpowiedzi, ponowienia |
| `wave_report.gd` | Fala PvE na serwerze (#288, `pve_wave`): start i wynik, kolejność odpowiedzi, ponowienia; nagrodę daje tylko serwer |
| `target_search.gd` | Dobór przeciwnika (#24): odpowiedź `find_targets`, czyszczenie danych, uzupełnianie botami do 3 celów |

Backend: `supabase/` (migracje, RLS, Edge Functions). Skille: `supabase-security`, `pvp-anti-cheat`, `user-data-privacy`.
Atak na gracza (#240): `SupabaseClient.start_attack` / `finish_attack`, cel z kopii w `scripts/battle/player_castle.gd`.
Testy: `tests/test_supabase_client.gd`, `test_player_castle.gd`, `test_castle_sync.gd`, `test_attack_start.gd`, `test_attack_finish.gd`, `test_pending_finish.gd`, `test_target_search.gd`, `test_ranking_board.gd`, `test_pve_ranking.gd`, `test_replay.gd`.
