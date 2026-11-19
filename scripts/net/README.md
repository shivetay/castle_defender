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
| `target_search.gd` | Dobór przeciwnika (#24): odpowiedź `find_targets`, czyszczenie danych, uzupełnianie botami do 3 celów |

Backend: `supabase/` (migracje, RLS, Edge Functions). Skille: `supabase-security`, `pvp-anti-cheat`, `user-data-privacy`.
Testy: `tests/test_supabase_client.gd`, `test_castle_sync.gd`, `test_attack_start.gd`, `test_attack_finish.gd`, `test_target_search.gd`.
