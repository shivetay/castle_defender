# supabase/tests/

Testy bazy (pgTAP), głównie RLS.

| Ścieżka | Rola |
|---|---|
| `database/rls_test.sql` | Właściciel może, obcy gracz nie — scenariusze na tabelach PvP |
| `database/match_targets_test.sql` | Dobór przeciwnika (#24): filtry, limit 3, tylko serwer wywoła funkcję |
| `database/ruins_test.sql` | Zniszczone budynki po ataku (#99): tylko serwer, gotowe budynki z kopii, limit z procentu, odczyt tylko dla obrońcy |
| `database/replay_test.sql` | Powtórka obrony (#29): plan sprawdzony i zapisany przy zatwierdzeniu, badania z zamku na serwerze, ponowienie bez zmian, powtórka tylko dla obrońcy |
| `database/attack_flow_test.sql` | Start i koniec ataku (#25): blokada celu, tarcze, limity armii i startów, zawyżony łup, capacity, idempotencja |

```bash
supabase test db
```
